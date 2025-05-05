%% @doc Clojerl compiler's entrypoint.
%%
%% Provides functions to compile files, strings and forms.
-module(clj_compiler).

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-dialyzer(no_return).

-export([ file/1
        , file/2
        , string/1
        , string/2
        , load/1
        , load_file/1
        , load_string/1
        , eval/1
        , eval/2
        , eval/3
        , eval_expressions/1
        , eval_expressions/2
        , module/1
        , module/2
        , current_file/0
        ]).

-export([ no_warn_dynamic_var_name/1
        , no_warn_symbol_as_erl_fun/1
        ]).

-type clj_flag() :: 'no-warn-symbol-as-erl-fun'
                  | 'no-warn-dynamic-var-name'.

-type options() :: #{ clj_flags   => [clj_flag()] %% clojerl compilation flags
                    , file        => string()     %% Source file name
                    , reader_opts => map()        %% Options for the reader
                    , time        => boolean()    %% Measure and show
                                                  %% compilation times
                    , output      => binary | asm | core %% Output format
                    , fake        => boolean()    %% Fake modules being compiled
                    }.

-type compiled_modules() :: [file:filename_all()].
-type return_type()      :: compiled_modules | env.

-export_type([options/0]).

%%------------------------------------------------------------------------------
%% Public API
%%------------------------------------------------------------------------------

-spec default_options() -> options().
default_options() ->
  #{ clj_flags   => []
   , file        => ?NO_SOURCE
   , reader_opts => #{}
   , time        => false
   , output      => binary
   , fake        => false
   }.

%% @equiv file(File, default_options())
-spec file(file:filename_all()) -> compiled_modules().
file(File) when is_binary(File) ->
  file(File, default_options()).

%% @doc Compiles the file whose path is `File' using the provided options.
%%
%% Returns a list of paths for the generated BEAM binaries. This can be
%% used to keep track of the compiling dependency between files, which
%% is useful for incremental compiling.
-spec file(file:filename_all(), options()) -> compiled_modules().
file(File, Opts) when is_binary(File) ->
  file(File, Opts, clj_env:default(), compiled_modules).

%% @equiv string(Src, default_options())
-spec string(binary()) -> clj_env:env().
string(Src) when is_binary(Src) ->
  string(Src, default_options()).

%% @doc Compiles the code in `Src' using the provided options.
%%
%% Returns a `clj_env:env()' compilation context.
-spec string(binary(), options()) -> clj_env:env().
string(Src, Opts) when is_binary(Src) ->
  string(Src, Opts, clj_env:default()).

%% @doc Compiles and load code from avoid reader.
%%
%% Returns the value of the last expression.
-spec load('erlang.io.PushbackReader':type()) -> any().
load(PushbackReader) ->
  Opts        = default_options(),
  ReaderOpts0 = maps:get(reader_opts, Opts),
  ReaderOpts1 = ReaderOpts0#{?OPT_IO_READER => PushbackReader},
  Env         = string(<<>>, Opts#{reader_opts => ReaderOpts1}),
  clj_env:get(eval, Env).

%% @doc Compiles and load code from a file.
%%
%% Returns the value of the last expression.
-spec load_file(binary()) -> any().
load_file(Path) ->
  Env = file(Path, default_options(), clj_env:default(), env),
  clj_env:get(eval, Env).

%% @doc Compiles and load code from a string.
%%
%% Returns the value of the last expression.
-spec load_string(binary()) -> any().
load_string(Src) ->
  Env = string(Src),
  clj_env:get(eval, Env).

%% @equiv eval(Form, default_options())
-spec eval(any()) -> {any(), clj_env:env()}.
eval(Form) ->
  eval(Form, default_options()).

%% @doc Evaluates a form.
%%
%% Returns the evaluated value for the form and the resulting
%% `clj_env:env()' compilation context.
-spec eval(any(), options()) -> {any(), clj_env:env()}.
eval(Form, Opts) ->
  eval(Form, Opts, clj_env:default()).

%% @private
-spec eval(any(), options(), clj_env:env()) -> {any(), clj_env:env()}.
eval(Form, Opts, Env0) ->
  Fun  = fun(F, EnvAcc) -> eval1(F, Opts, EnvAcc) end,
  Env1 = clj_env:push(#{}, Env0),
  Env2 = check_top_level_do(Fun, Form, Env1),
  {clj_env:get(eval, Env2), Env2}.

-spec eval1(any(), options(), clj_env:env()) -> clj_env:env().
eval1(Form, Opts, Env) ->
  ProcDict = erlang:get(),
  DoEval   = fun() -> copy_proc_dict(ProcDict), do_eval(Form, Opts, Env) end,
  {Exprs, Modules, Env1} = run_monitored(DoEval),

  lists:foreach(module_fun(Opts), Modules),
  Value = eval_expressions(Exprs),
  clj_env:put(eval, Value, Env1).

%% Flags

%% @private
-spec no_warn_symbol_as_erl_fun(clj_env:env()) -> boolean().
no_warn_symbol_as_erl_fun(Env) ->
  check_flag('no-warn-symbol-as-erl-fun', Env).

%% @private
-spec no_warn_dynamic_var_name(clj_env:env()) -> boolean().
no_warn_dynamic_var_name(Env) ->
  check_flag('no-warn-dynamic-var-name', Env).

%%------------------------------------------------------------------------------
%% Helper functions
%%------------------------------------------------------------------------------

%% @doc Compile code from a string.
%%
%% Return the modified `clj_env:env()'.
-spec string(binary(), options(), clj_env:env()) -> clj_env:env().
string(Src, Opts, Env) when is_binary(Src) ->
  ProcDict = erlang:get(),
  DoCompile = fun() ->
                  copy_proc_dict(ProcDict),
                  compile_string(Src, Opts, Env)
              end,
  run_monitored(DoCompile).

-spec timed_string(binary(), options(), clj_env:env()) ->
  compiled_modules().
timed_string(Src, Opts, Env) when is_binary(Src) ->
  File = maps:get(file, Opts, ?NO_SOURCE),
  ok   = io:format("Compiling ~s~n", [File]),
  clj_utils:time("Total", fun string/3, [Src, Opts, Env]).

-spec file( file:filename_all(), options(), clj_env:env(), return_type()) ->
  compiled_modules() | clj_env:env().
file(File, Opts0, Env0, ReturnType) when is_binary(File) ->
  ?ERROR_WHEN( not filelib:is_regular(File)
             , [<<"File '">>, File, <<"' does not exist">>]
             ),
  case file:read_file(File) of
    {ok, Src} ->
      Opts  = maps:merge(default_options(), Opts0),
      Opts1 = Opts#{ reader_opts => reader_opts(File)
                   , file        => unicode:characters_to_list(File)
                   },
      CompileFun = string_fun(Opts1),
      Env1 = CompileFun(Src, Opts1, Env0),
      case ReturnType of
        compiled_modules -> clj_env:get(compiled_modules, Env1);
        env -> Env1
      end;
    Error ->
      error(Error)
  end.

-spec string_fun(options()) -> function().
string_fun(#{time := true}) ->
  fun timed_string/3;
string_fun(_) ->
  fun string/3.

-spec reader_opts(binary()) -> map().
reader_opts(File) ->
  Opts = #{file => File},
  case filename:extension(File) of
    <<".cljc">> ->
      Opts#{?OPT_READ_COND => allow};
    _ ->
      Opts
  end.

-spec copy_proc_dict([{any(), any()}]) -> ok.
copy_proc_dict(List) ->
  [erlang:put(K, V) || {K, V} <- List],
  ok.

-spec run_monitored(fun()) -> any().
run_monitored(Fun) ->
  {_Pid, Ref} = erlang:spawn_monitor(Fun),
  receive
    {'DOWN', Ref, _, _, {shutdown, Result}} ->
      Result;
    {'DOWN', Ref, _, _, {Kind, Error, Stacktrace}} ->
      erlang:raise(Kind, Error, Stacktrace);
    {'DOWN', Ref, _, _, Info} ->
      throw(Info)
  end.

-spec compile_string(binary(), options(), clj_env:env()) -> no_return().
compile_string(Src, Opts0, Env0) when is_binary(Src) ->
  Opts     = maps:merge(default_options(), Opts0),

  #{ clj_flags   := CljFlags
   , reader_opts := RdrOpts0
   , time        := Time
   } = Opts,

  RdrOpts     = RdrOpts0#{time => Time},
  File        = maps:get(file, RdrOpts, ?NIL),
  Mapping     = #{ clj_flags     => CljFlags
                 , compiler_opts => Opts
                 , eval          => ?NIL
                 , location      => #{file => File}
                 },
  Env1        = clj_env:push(Mapping, Env0),

  %% Resolve function to be used (normal/timed)
  AnnEmitEval = analyze_emit_eval_fun(Opts),
  Fun         = module_fun(Opts),
  %% 对clje的编译在此处进行
  CompileFun =
    fun() ->
        try
          current_file(File),
          Env2  = clj_reader:read_fold(AnnEmitEval, Src, RdrOpts, Env1),
          %% Maybe report time
          Time andalso report_time(Env2),
          %% Compile all modules
          Beams = [Fun(M) || M <- clj_module:all_modules()],
          Env3  = clj_env:put(compiled_modules, Beams, Env2),
          {shutdown, Env3}
        catch ?WITH_STACKTRACE(Kind, Error, Stacktrace)
            {Kind, Error, Stacktrace}
        end
    end,

  Result = clj_module:with_context(CompileFun),

  exit(Result).

-define(CURRENT_FILE, '__current_file__').

%% @private
%% @doc Gets the current file that is being compiled if set
-spec current_file() -> binary().
current_file() ->
   case erlang:get(?CURRENT_FILE) of
     undefined -> <<?NO_SOURCE>>;
     X -> X
   end.

%% @doc Sets the current file that is being compiled
-spec current_file(binary()) -> ok.
current_file(Filename) ->
  erlang:put(?CURRENT_FILE, Filename).

-spec do_eval(any(), options(), clj_env:env()) -> no_return().
do_eval(Form, Opts0, Env0) ->
  Opts     = maps:merge(default_options(), Opts0),
  CljFlags = maps:get(clj_flags, Opts),

  EvalFun =
    fun() ->
        try
          Env  = clj_env:push(#{clj_flags => CljFlags}, Env0),
          %% Emit & eval form and keep the resulting value
          Env1 = clj_analyzer:analyze(Form, Env),
          {Exprs, Env2} = clj_emitter:emit(Env1),

          { shutdown
          , { Exprs
            , clj_module:all_modules()
            , clj_env:pop(Env2)
            }
          }
        catch ?WITH_STACKTRACE(Kind, Error, Stacktrace)
            {Kind, Error, Stacktrace}
        end
    end,

  Result = clj_module:with_context(EvalFun),

  exit(Result).

-spec check_flag(clj_flag(), clj_env:env()) -> boolean().
check_flag(Flag, Env) ->
  case clj_env:get(clj_flags, Env) of
    CljFlags when is_list(CljFlags) ->
      lists:member(Flag, CljFlags);
    ?NIL ->
      false
  end.

-spec report_time(clj_env:env()) -> ok.
report_time(Env) ->
  Times = clj_env:time(Env),
  [ io:format("~s: ~p ms~n", [K, erlang:trunc(V / 1000)])
    || {K, V} <- maps:to_list(Times)
  ],
  ok.

analyze_emit_eval_fun(#{time := true}) ->
  fun(Form, Env) ->
      check_top_level_do(fun timed_analyze_emit_eval/2, Form, Env)
  end;
analyze_emit_eval_fun(_) ->
   fun analyze_emit_eval/2.

-spec timed_analyze_emit_eval(any(), clj_env:env()) -> clj_env:env().
timed_analyze_emit_eval(Form, Env0) ->
  {TimeAnn, Env1} = timer:tc(clj_analyzer, analyze, [Form, Env0]),
  Env2 = clj_env:time("Analyzer", TimeAnn, Env1),

  {TimeEmit, {Exprs, Env3}} = timer:tc(clj_emitter, emit, [Env2]),
  Env4 = clj_env:time("Emitter", TimeEmit, Env3),

  {TimeEval, Value} = timer:tc(fun() -> eval_expressions(Exprs) end),
  Env5 = clj_env:time("Eval", TimeEval, Env4),

  clj_env:update(eval, Value, Env5).

-spec analyze_emit_eval(any(), clj_env:env()) -> clj_env:env().
analyze_emit_eval(Form, Env) ->
  check_top_level_do(fun do_analyze_emit_eval/2, Form, Env).

-spec do_analyze_emit_eval(any(), clj_env:env()) -> clj_env:env().
do_analyze_emit_eval(Form, Env) ->
  Env1          = clj_analyzer:analyze(Form, Env),
  {Exprs, Env2} = clj_emitter:emit(Env1),
  Value         = eval_expressions(Exprs),
  clj_env:update(eval, Value, Env2).

-spec check_top_level_do(function(), any(), clj_env:env()) -> clj_env:env().
check_top_level_do(Fun, Form, Env) ->
  Expanded = clj_analyzer:macroexpand(Form, Env),
  case
    clj_rt:'seq?'(Expanded)
    andalso clj_rt:equiv(clj_rt:first(Expanded), clj_rt:symbol(<<"do">>))
  of
    true ->
      Rest = clj_rt:rest(Expanded),
      lists:foldl(Fun, Env, clj_rt:to_list(Rest));
    false ->
      Fun(Expanded, Env)
  end.

-spec module_fun(options()) -> function().
module_fun(#{time := true} = Opts) ->
  fun(Module) ->
      clj_utils:time("Compile Module", fun module/2, [Module, Opts])
  end;
module_fun(Opts) ->
  fun(Module) -> module(Module, Opts) end.

%% @private
-spec module(cerl:c_module()) -> binary().
module(Module) ->
  module(Module, #{}).

%% @private
-spec module(cerl:c_module(), options()) -> binary().
module(Module, #{output := asm}) ->
  ok = output_asm(Module),
  ?NO_SOURCE;
module(Module, #{output := core}) ->
  ok = output_core(Module),
  ?NO_SOURCE;
module(Module, Opts) ->
  ok      = clj_behaviour:check(Module),
  ErlOpts = erl_compiler_options(Opts),
  case compile:noenv_forms(Module, ErlOpts) of
    {ok, _, Beam0, _Warnings} ->
      %% Fetch the module name from the AST since the one
      %% returned is sometimes the empty list in older
      %% Erlang/OTP releases (e.g. 19).
      Name           = cerl:atom_val(cerl:module_name(Module)),
      Beam1          = clj_utils:add_core_to_binary(Beam0, Module),
      Beam2          = maybe_replace_compile_info(Beam1, Module),
      BeamPath       = maybe_output_beam(Name, Module, Beam2, Opts),
      {module, Name} = code:load_binary(Name, BeamPath, Beam2),
      unicode:characters_to_binary(BeamPath);
    {error, Errors, Warnings} ->
      error({Errors, Warnings})
  end.

-spec erl_compiler_options(options()) -> [term()].
erl_compiler_options(Opts) ->
  Source = maps:get(file, Opts, ?NO_SOURCE),
  [ from_core, clint, binary, return_errors, return_warnings, {source, Source}
  | env_compiler_options()
  ].

%% @doc Parse ERL_COMPILER_OPTIONS env variable.
%% Copied from the compile module because this function is
%% not available for older Erlang/OTP releases (i.e. 18).
-spec env_compiler_options() -> [term()].
env_compiler_options() ->
  Key = "ERL_COMPILER_OPTIONS",
  case os:getenv(Key) of
    false ->
      [];
    Str when is_list(Str) ->
      parse_compiler_options(Str)
  end.

-spec parse_compiler_options(string()) -> [term()].
parse_compiler_options(Str) ->
  case erl_scan:string(Str) of
    {ok, Tokens, _} ->
      Dot = {dot, erl_anno:new(1)},
      case erl_parse:parse_term(Tokens ++ [Dot]) of
        {ok, List} when is_list(List) -> List;
        {ok, Term} -> [Term];
        {error, _Reason} ->
          []
      end;
    {error, {_, _, _Reason}, _} -> []
  end.

%% @private
-spec eval_expressions([cerl:cerl()]) -> [any()].
eval_expressions(Expressions) ->
  eval_expressions(Expressions, true).

%% @private
-spec eval_expressions([cerl:cerl()], boolean()) -> [any()].
eval_expressions(Expressions, true = _ReplaceExprs) ->
  CurrentNs     = 'clojerl.Namespace':current(),
  CurrentNsSym  = 'clojerl.Namespace':name(CurrentNs),
  CurrentNsBin  = 'clojerl.Symbol':str(CurrentNsSym),
  CurrentNsAtom = binary_to_existing_atom(CurrentNsBin, utf8),
  ReplacedExprs = [ clj_module:replace_calls(Expr, CurrentNsAtom)
                    || Expr <- Expressions
                  ],
  eval_expressions(ReplacedExprs, false);
eval_expressions(Expressions, false = _ReplaceExprs) ->
  core_eval:exprs(Expressions).

-spec output_asm(cerl:c_module()) -> ok | {error, term()}.
output_asm(Module) ->
  CompilePath = case compile_path(false) of
                  ?NIL -> ".";
                  X    -> unicode:characters_to_list(X)
                end,

  Name       = cerl:concrete(cerl:module_name(Module)),
  Filename   = atom_to_list(Name),
  Path       = filename:join(CompilePath, "dummy"),
  ok         = filelib:ensure_dir(Path),
  ErlOpts = [from_core, 'S', {outdir, CompilePath}, {source, Filename}],

  case compile:noenv_forms(Module, ErlOpts) of
    {ok, _, _Asm} -> ok;
    {error, Errors, Warnings} -> error({Errors, Warnings})
  end.

-spec output_core(cerl:c_module()) -> ok | {error, term()}.
output_core(Module) ->
  CompilePath = case compile_path(false) of
                  ?NIL -> ".";
                  X    -> X
                end,
  Source      = core_pp:format(Module),
  Name        = cerl:concrete(cerl:module_name(Module)),
  Filename    = atom_to_list(Name) ++ ".core",
  Path        = filename:join(CompilePath, Filename),
  ok          = filelib:ensure_dir(Path),
  file:write_file(Path, Source).

%% Keep compile_info information for modules that were originally compiled
%% as Erlang modules (e.g. protocol modules).
%% This is to avoid rebar3 re-compiling the modules because it detects
%% their `compile_info` options were changed.

-spec maybe_replace_compile_info(binary(), cerl:c_module()) -> binary().
maybe_replace_compile_info(Beam, Module) ->
  Name = cerl:concrete(cerl:module_name(Module)),
  code:ensure_loaded(Name),
  case original_compile_info(Name) of
    undefined   -> Beam;
    CompileInfo -> clj_utils:add_compile_info_to_binary(Beam, CompileInfo)
  end.

-spec original_compile_info(module()) -> [any()] | undefined.
original_compile_info(Name) ->
  case code:which(Name) of
    Filename when is_list(Filename) ->
      compile_info(Filename);
    _ -> undefined
  end.

-spec compile_info(list()) -> [any()] | undefined.
compile_info(Target) ->
  case beam_lib:chunks(Target, [compile_info]) of
    {ok, {_mod, Chunks}} ->
      proplists:get_value(compile_info, Chunks, []);
    {error, beam_lib, _} ->
      undefined
  end.

-spec maybe_output_beam(module(), cerl:c_module(), binary(), options()) ->
  string().
maybe_output_beam(_Name, _Module, _BeamBinary, #{fake := true}) ->
  ?NO_SOURCE;
maybe_output_beam(Name, Module, BeamBinary, _Opts) ->
  CompileFiles = 'clojure.core':'*compile-files*__val'(),
  case CompileFiles of
    true  ->
      IsProtocol = clj_module:is_protocol(Module),
      output_beam(Name, IsProtocol, BeamBinary);
    false ->
      clj_utils:store_binary(Name, BeamBinary),
      ?NO_SOURCE
  end.

-spec output_beam(module(), boolean(), binary()) -> string().
output_beam(Name, IsProtocol, BeamBinary) ->
  CompilePath  = compile_path(IsProtocol),
  ?ERROR_WHEN(CompilePath =:= ?NIL, <<"*compile-path* not set">>),
  ok           = ensure_path(CompilePath),
  NameBin      = atom_to_binary(Name, utf8),
  BeamFilename = <<NameBin/binary, ".beam">>,
  BeamPath     = filename:join([CompilePath, BeamFilename]),
  ok           = file:write_file(BeamPath, BeamBinary),
  unicode:characters_to_list(BeamPath).

-spec compile_path(boolean()) -> binary() | ?NIL.
compile_path(true) ->
  case 'clojure.core':'*compile-protocols-path*__val'() of
    ?NIL ->
      ?WARN(<<"*compile-protocols-path* not set, using *compile-path*">>),
      'clojure.core':'*compile-path*__val'();
    Path ->
      Path
  end;
compile_path(false) ->
  'clojure.core':'*compile-path*__val'().

-spec ensure_path(binary()) -> ok.
ensure_path(Path) when is_binary(Path) ->
  ok   = filelib:ensure_dir(filename:join([Path, "dummy"])),
  true = code:add_path(unicode:characters_to_list(Path)),
  ok.
