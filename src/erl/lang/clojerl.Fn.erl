%% @doc Clojure 函数包装模块
%% @desc
%% - 功能：包装 Erlang 函数使其符合 Clojure 的 IFn 协议
%% - 依赖：
%%   - 'clojerl.IFn' - 函数协议
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Fn').

-compile({no_auto_import, [{apply, 2}]}).

-include("clojerl.hrl").

-behavior('clojerl.IFn').
-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , fn/1
        ]).

-export([ apply/2
        , hash/1
        , str/1
        ]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , fn    => function()  %% 包装的 Erlang 函数
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 从 Erlang 函数创建 Clojure 函数
-spec ?CONSTRUCTOR(function()) -> type().
?CONSTRUCTOR(Fn) ->
  #{ ?TYPE => ?M
   , fn    => Fn
   }.

%% @doc 获取包装的 Erlang 函数
-spec fn(type()) -> function().
fn(#{?TYPE := ?M, fn := Fn}) ->
  Fn.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IFn
%% @doc 应用函数（接受列表或可序列化的参数）
apply(#{?TYPE := ?M, fn := Fn}, Args) when is_list(Args) ->
  Fn(Args);
apply(#{?TYPE := ?M, fn := Fn}, Args) ->
  Fn(clj_rt:to_list(Args)).

%% clojerl.IHash
%% @doc 计算函数的哈希值
hash(#{?TYPE := ?M} = Fun) ->
  erlang:phash2(Fun).

%% clojerl.IStringable
%% @doc 将函数转换为字符串（显示模块和函数名）
str(#{?TYPE := ?M, fn := Fn})  ->
  {module, Module} = erlang:fun_info(Fn, module),
  {name, Name}     = erlang:fun_info(Fn, name),
  ModuleBin        = atom_to_binary(Module, utf8),
  NameBin          = atom_to_binary(Name, utf8),

  <<"#<", ModuleBin/binary, "/", NameBin/binary, ">">>.
