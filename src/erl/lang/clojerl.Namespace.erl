%% @doc Clojure 命名空间模块
%% @desc
%% - 功能：实现 Clojure 命名空间管理，使用 gen_server 维护所有命名空间的状态
%% - 依赖：
%%   - gen_server - OTP 行为，用于管理命名空间状态
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.IReference' - 引用协议（支持元数据修改）
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Namespace').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behaviour(gen_server).

-behavior('clojerl.IHash').
-behavior('clojerl.IMeta').
-behavior('clojerl.IReference').
-behavior('clojerl.IStringable').

-export([hash/1]).
-export([ meta/1
        , with_meta/2
        ]).
-export([ alter_meta/3
        , reset_meta/2
        ]).
-export([str/1]).

-export([ current/0
        , current/1

        , all/0
        , find/1
        , find_or_create/1
        , remove/1

        , name/1
        , intern/2
        , update_var/1
        , update_var/2
        , find_var/1
        , find_var/2
        , find_mapping/2
        , get_mappings/1
        , get_aliases/1

        , refer/3
        , import_type/1
        , import_type/2
        , unmap/2
        , add_alias/3
        , remove_alias/2
        , mapping/2
        , alias/2
        ]).

%% gen_server callbacks
-export([ start_link/0
        , init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-export_type([type/0]).
-type type() :: #{ ?TYPE    => ?M
                 , id       => any()
                 , name     => 'clojerl.Symbol':type()
                 , mappings => ets:tid()   %% 符号到 Var 的映射表
                 , aliases  => ets:tid()   %% 命名空间别名表
                 , meta     => ?NIL | any()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 创建命名空间（使用符号的元数据）
-spec ?CONSTRUCTOR('clojerl.Symbol':type()) -> type().
?CONSTRUCTOR(Name) ->
  ?CONSTRUCTOR(Name, 'clojerl.Symbol':meta(Name)).

%% @doc 创建命名空间（指定元数据）
-spec ?CONSTRUCTOR('clojerl.Symbol':type(), any()) -> type().
?CONSTRUCTOR(Name, Meta) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(Name)
             , <<"Namespace name must be a symbol">>
             ),
  Opts = [set, protected, {keypos, 1}],
  Id   = 'clojerl.Symbol':name(Name),

  #{ ?TYPE    => ?M
   , id       => Id
   , name     => Name
   , mappings => ets:new(mappings, Opts)
   , aliases  => ets:new(aliases, Opts)
   , meta     => Meta
   }.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IHash
%% @doc 计算命名空间的哈希值
hash(Ns = #{?TYPE := ?M}) ->
  erlang:phash2(Ns).

%% clojerl.IMeta
%% @doc 获取命名空间的元数据
meta(#{?TYPE := ?M, meta := Meta}) ->
  Meta.

%% @doc 设置命名空间的元数据
with_meta(#{?TYPE := ?M} = Ns0, Meta) ->
  Ns1 = Ns0#{meta := Meta},
  gen_server:call(?MODULE, {update, Ns1}).

%% clojerl.IReference
%% @doc 修改命名空间的元数据（通过函数）
alter_meta(#{?TYPE := ?M, name := Name}, F, Args0) ->
  Ns0   = find(Name),
  Meta0 = clj_rt:meta(Ns0),
  Args1 = clj_rt:cons(Meta0, Args0),
  Meta1 = clj_rt:apply(F, Args1),
  Ns1   = Ns0#{meta := Meta1},
  Ns1   = gen_server:call(?MODULE, {update, Ns1}),
  Meta1.

%% @doc 重置命名空间的元数据
reset_meta(#{?TYPE := ?M} = Ns0, Meta) ->
  Ns1 = Ns0#{meta := Meta},
  Ns1 = gen_server:call(?MODULE, {update, Ns1}),
  Meta.

%% clojerl.IStringable
%% @doc 将命名空间转换为字符串
str(#{?TYPE := ?M, name := Name}) ->
  'clojerl.Symbol':str(Name).

%%------------------------------------------------------------------------------
%% 导出函数
%%------------------------------------------------------------------------------

%% @doc 获取当前命名空间
-spec current() -> type().
current() ->
  NsVar = 'clojerl.Var':?CONSTRUCTOR(<<"clojure.core">>, <<"*ns*">>),
  clj_rt:deref(NsVar).

%% @doc 设置当前命名空间
-spec current(type()) -> type().
current(#{?TYPE := ?M} = Ns) ->
  NsVar = 'clojerl.Var':?CONSTRUCTOR(<<"clojure.core">>, <<"*ns*">>),
  clj_rt:'set!'(NsVar, Ns),
  Ns.

%% @doc 获取所有命名空间
-spec all() -> [type()].
all() -> [Ns || {_, Ns} <- ets:tab2list(?MODULE)].

%% @doc 查找命名空间，如未加载则尝试从编译模块加载
-spec find('clojerl.Symbol':type()) -> type() | ?NIL.
find(Name) ->
  case clj_utils:ets_get(?MODULE, clj_rt:str(Name)) of
    ?NIL -> gen_server:call(?MODULE, {load, Name});
    {_, Ns} -> Ns
  end.

%% @doc 在当前命名空间中查找 Var
-spec find_var('clojerl.Symbol':type()) ->
  'clojerl.Var':type() | ?NIL.
find_var(Symbol) ->
  find_var(current(), Symbol).

%% @doc 在指定命名空间中查找 Var
-spec find_var(type(), 'clojerl.Symbol':type()) ->
  'clojerl.Var':type() | ?NIL.
find_var(#{?TYPE := ?M} = Ns, Symbol) ->
  Var = find_mapping(Ns, Symbol),
  case clj_rt:'var?'(Var) of
    true  -> Var;
    false -> ?NIL
  end.

%% @doc 查找符号对应的映射（Var 或 Symbol）
-spec find_mapping(type(), 'clojerl.Symbol':type()) ->
  'clojerl.Var':type() | 'clojerl.Symbol':type() | ?NIL.
find_mapping(#{?TYPE := ?M} = DefaultNs, Symbol) ->
  case resolve_ns(DefaultNs, Symbol) of
    ?NIL -> ?NIL;
    Ns ->
      NameSym = clj_rt:symbol(clj_rt:name(Symbol)),
      mapping(Ns, NameSym)
  end.

%% @doc 解析符号的命名空间
-spec resolve_ns(type(), 'clojerl.Symbol':type()) ->
  type() | ?NIL.
resolve_ns(#{?TYPE := ?M} = DefaultNs, Symbol) ->
  ?ERROR_WHEN(not clj_rt:'symbol?'(Symbol), <<"Argument must be a symbol">>),

  case clj_rt:namespace(Symbol) of
    ?NIL  -> DefaultNs;
    NsStr ->
      NsSym = clj_rt:symbol(NsStr),
      case find(NsSym) of
        ?NIL -> alias(DefaultNs, NsSym);
        Ns   -> Ns
      end
  end.

%% @doc 查找或创建命名空间
-spec find_or_create('clojerl.Symbol':type()) -> type().
find_or_create(Name) ->
  ?ERROR_WHEN(not clj_rt:'symbol?'(Name), <<"Argument must be a symbol">>),
  Ns = case find(Name) of
         ?NIL -> gen_server:call(?MODULE, {new, Name});
         X -> X
       end,
  current(Ns).

%% @doc 移除命名空间
-spec remove('clojerl.Symbol':type()) -> boolean().
remove(Name) ->
  ?ERROR_WHEN(not clj_rt:'symbol?'(Name), <<"Argument must be a symbol">>),
  gen_server:call(?MODULE, {remove, Name}).

%% @doc 获取命名空间的名称
-spec name(type()) -> 'clojerl.Symbol':type().
name(#{?TYPE := ?M, name := Name}) -> Name.

%% @doc 将符号 intern 到命名空间（创建 Var）
-spec intern(type(), 'clojerl.Symbol':type()) -> type().
intern(#{?TYPE := ?M, name := NsNameSym} = Ns, Symbol) ->
  ?ERROR_WHEN(not clj_rt:'symbol?'(Symbol), <<"Argument must be a symbol">>),

  ?ERROR_WHEN( clj_rt:namespace(Symbol) =/= ?NIL
             , <<"Can't intern namespace-qualified symbol">>
             ),

  NsStr   = 'clojerl.Symbol':name(NsNameSym),
  NameStr = 'clojerl.Symbol':name(Symbol),
  Var     = 'clojerl.Var':?CONSTRUCTOR(NsStr, NameStr),

  check_if_override(Ns, Symbol, mapping(Ns, Symbol), Var),

  gen_server:call(?MODULE, {intern, Ns, Symbol, Var}).

%% @doc 更新 Var
-spec update_var('clojerl.Var':type()) -> type().
update_var(Var) ->
  VarNsSym = clj_rt:symbol(clj_rt:namespace(Var)),
  update_var(find(VarNsSym), Var).

%% @doc 在指定命名空间中更新 Var
-spec update_var(type(), 'clojerl.Var':type()) -> type().
update_var(#{?TYPE := ?M} = Ns, Var) ->
  ?ERROR_WHEN( not clj_rt:'var?'(Var)
             , <<"Argument must be a var">>
             ),

  gen_server:call(?MODULE, {update_var, Ns, Var}).

%% @doc 获取命名空间的所有映射
-spec get_mappings(type()) -> map().
get_mappings(#{?TYPE := ?M, mappings := Mappings}) ->
  maps:from_list(ets:tab2list(Mappings)).

%% @doc 获取命名空间的所有别名
-spec get_aliases(type()) -> map().
get_aliases(#{?TYPE := ?M, aliases := Aliases}) ->
  maps:from_list(ets:tab2list(Aliases)).

%% @doc 在命名空间中引用一个 Var（refer）
-spec refer(type(), 'clojerl.Symbol':type(), 'clojerl.Var':type()) ->
  type().
refer(#{?TYPE := ?M} = Ns, Sym, Var) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(Sym)
             , <<"Name for refer var is not a symbol">>
             ),

  ?ERROR_WHEN( clj_rt:namespace(Sym) =/= ?NIL
             , <<"Can't refer namespace-qualified symbol">>
             ),

  Old = mapping(Ns, Sym),

  case 'clojerl.Var':equiv(Old, Var) of
    true -> ok;
    false -> check_if_override(Ns, Sym, Old, Var)
  end,

  gen_server:call(?MODULE, {intern, Ns, Sym, Var}).

%% @doc 导入类型
-spec import_type(binary()) -> type().
import_type(TypeName) ->
  import_type(TypeName, true).

%% @doc 导入类型（可选择是否检查加载）
-spec import_type(binary(), boolean()) -> type().
import_type(TypeName, CheckLoaded) ->
  Module = binary_to_atom(TypeName, utf8),
  ?ERROR_WHEN( CheckLoaded
               andalso {module, Module} =/= code:ensure_loaded(Module)
             , [ <<"Type ">>, TypeName, <<" could not be loaded. ">>]
             ),

  SymName = lists:last(binary:split(TypeName, <<".">>, [global])),
  Sym     = clj_rt:symbol(SymName),
  Type    = 'erlang.Type':?CONSTRUCTOR(Module),
  Ns      = current(),
  Exists  = mapping(Ns, Sym),

  ?ERROR_WHEN( Exists =/= ?NIL
               andalso not clj_rt:equiv(Exists, Type)
             , [ Sym , <<" already refers to: ">> , Exists
               , <<" in namespace: ">> , name(Ns)
               ]
             ),

  gen_server:call(?MODULE, {intern, Ns, Sym, Type}).

%% @doc 取消映射
-spec unmap(type(), 'clojerl.Symbol':type()) -> type().
unmap(#{?TYPE := ?M} = Ns, Sym) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(Sym)
             , <<"Name for refer var is not a symbol">>
             ),

  gen_server:call(?MODULE, {unmap, Ns, Sym}).

%% @doc 添加别名
-spec add_alias(type(), 'clojerl.Symbol':type(), type()) ->
  type().
add_alias( #{?TYPE := ?M, name := NsName} = Ns
         , AliasSym
         , #{?TYPE := ?M} = AliasedNs
         ) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(AliasSym)
             , <<"Name for refer var is not a symbol">>
             ),

  case clj_module:in_context() of
    false -> ok;
    true  ->
      NsNameAtom = clj_rt:keyword(NsName),
      clj_module:add_alias(AliasSym, name(AliasedNs), NsNameAtom)
  end,

  gen_server:call(?MODULE, {add_alias, Ns, AliasSym, AliasedNs}).

%% @doc 移除别名
-spec remove_alias(type(), 'clojerl.Symbol':type()) ->
  type().
remove_alias(#{?TYPE := ?M} = Ns, AliasSym) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(AliasSym)
             , <<"Name for refer var is not a symbol">>
             ),

  gen_server:call(?MODULE, {remove_alias, Ns, AliasSym}).

%% @doc 获取符号对应的映射
-spec mapping(type(), 'clojerl.Symbol':type()) ->
  'clojerl.Var':type() | ?NIL.
mapping(#{?TYPE := ?M, mappings := Mappings}, Symbol) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(Symbol)
             , <<"Argument must be a symbol">>
             ),

  case clj_utils:ets_get(Mappings, clj_rt:str(Symbol)) of
    {_, Var} -> Var;
    ?NIL -> ?NIL
  end.

%% @doc 获取符号对应的别名
-spec alias(type(), 'clojerl.Symbol':type()) -> type() | ?NIL.
alias(#{?TYPE := ?M, aliases := Aliases}, Symbol) ->
  ?ERROR_WHEN( not clj_rt:'symbol?'(Symbol)
             , <<"Argument must be a symbol">>
             ),

  case clj_utils:ets_get(Aliases, clj_rt:str(Symbol)) of
    {_, Var} -> Var;
    ?NIL -> ?NIL
  end.

%%------------------------------------------------------------------------------
%% gen_server 回调函数
%%------------------------------------------------------------------------------

%% @doc 启动命名空间服务器
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc 初始化服务器
init([]) ->
  ets:new(?MODULE, [named_table, set, protected, {keypos, 1}]),
  {ok, ?NIL}.

handle_call({new, Name}, _From, State) ->
  Ns = #{id := Id} = ?CONSTRUCTOR(Name),
  clj_utils:ets_save(?MODULE, {Id, Ns}),
  {reply, Ns, State};
handle_call({update, Ns}, _From, State) ->
  #{id := Id} = Ns,
  clj_utils:ets_save(?MODULE, {Id, Ns}),
  {reply, Ns, State};
handle_call({load, Name}, _Form, State) ->
  Ns = case load(Name) of
         ?NIL ->
           ?NIL;
         #{id := Id} = X ->
           clj_utils:ets_save(?MODULE, {Id, X}),
           X
       end,
  {reply, Ns, State};
handle_call( { update_var
             , Ns = #{?TYPE := ?M, mappings := Mappings}
             , Var
             }
           , _Form
           , State
           ) ->
  clj_utils:ets_save(Mappings, {clj_rt:name(Var), Var}),
  {reply, Ns, State};
handle_call( { intern
             , Ns = #{?TYPE := ?M, mappings := Mappings}
             , Symbol
             , Var
             }
           , _From
           , State
           ) ->
  clj_utils:ets_save(Mappings, {clj_rt:name(Symbol), Var}),
  {reply, Ns, State};
handle_call( { unmap
             , Ns = #{?TYPE := ?M, mappings := Mappings}
             , Symbol
             }
           , _From
           , State
           ) ->
  true = ets:delete(Mappings, clj_rt:name(Symbol)),
  {reply, Ns, State};
handle_call( { add_alias
             , Ns = #{?TYPE := ?M, aliases := Aliases}
             , Symbol
             , AliasedNs
             }
           , _From
           , State
           ) ->
  clj_utils:ets_save(Aliases, {clj_rt:name(Symbol), AliasedNs}),
  {reply, Ns, State};
handle_call( { remove_alias
             , Ns = #{?TYPE := ?M, aliases := Aliases}
             , Symbol
             }
           , _From
           , State
           ) ->
  true = ets:delete(Aliases, clj_rt:name(Symbol)),
  {reply, Ns, State};
handle_call({remove, Name}, _From, State) ->
  Result = true =:= ets:delete(?MODULE, clj_rt:name(Name)),
  {reply, Result, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Msg, State) ->
  {noreply, State}.

terminate(_Msg, State) ->
  {ok, State}.

code_change(_Msg, _From, State) ->
  {ok, State}.

%%------------------------------------------------------------------------------
%% 内部函数
%%------------------------------------------------------------------------------

%% @doc 检查是否覆盖已有映射
-spec check_if_override( type()
                       , 'clojerl.Symbol':type()
                       , ?NIL | 'clojerl.Var':type()
                       , 'clojerl.Var':type()
                       ) ->
  ok.
check_if_override(_, _, ?NIL, _) ->
  ok;
check_if_override(Ns, Sym, Old, New) ->
  NsName   = 'clojerl.Symbol':name(name(Ns)),
  OldVarNs = 'clojerl.Var':namespace(Old),
  NewVarNs = 'clojerl.Var':namespace(New),
  Message  = [Sym, <<" already refers to: ">>, Old, <<" in namespace: ">>, Ns],
  Warn     = not ( OldVarNs =:= NsName
                   orelse NewVarNs =:= <<"clojure.core">>
                 ),

  ?ERROR_WHEN(Warn andalso OldVarNs =/= <<"clojure.core">>, Message),

  ?WARN_WHEN(Warn, [<<"WARNING: ">>, Message]).

%% @doc 加载命名空间
-spec load('clojerl.Symbol':type()) -> type() | ?NIL.
load(Name) ->
  Module = clj_rt:keyword(Name),
  case code:ensure_loaded(Module) of
    {module, _} ->
      maybe_load_ns(Name, Module);
    {error, _} -> ?NIL
  end.

%% @doc 如果模块是 Clojure 模块则加载命名空间
-spec maybe_load_ns('clojerl.Symbol':type(), module()) -> type() | ?NIL.
maybe_load_ns(Name, Module) ->
  case clj_module:is_clojure(Module) of
    true -> load_ns(Name, Module);
    false -> ?NIL
  end.

%% @doc 从模块属性加载命名空间
-spec load_ns('clojerl.Symbol':type(), module()) -> type().
load_ns(Name, Module) ->
  Attrs    = Module:module_info(attributes),
  Mappings = fetch_attribute(mappings, #{}, Attrs),
  Aliases  = fetch_attribute(aliases, #{}, Attrs),
  Meta     = fetch_attribute(meta, ?NIL, Attrs),
  Ns       = ?CONSTRUCTOR(Name, Meta),
  #{ ?TYPE    := ?M
   , mappings := MappingsId
   , aliases  := AliasesId
   } = Ns,

  MappingsFun = fun(K, V) -> clj_utils:ets_save(MappingsId, {K, V}) end,
  maps:map(MappingsFun, Mappings),

  AliasesFun = fun(K, V) ->
                   LoadedNs = load(V),
                   clj_utils:ets_save(AliasesId, {K, LoadedNs})
               end,
  maps:map(AliasesFun, Aliases),
  Ns.

%% @doc 从模块属性列表中获取指定属性
-spec fetch_attribute(atom(), any(), [any()]) -> any().
fetch_attribute(Name, Default, Attributes) ->
  case lists:keyfind(Name, 1, Attributes) of
    {Name, [Value]} -> Value;
    false           -> Default
  end.
