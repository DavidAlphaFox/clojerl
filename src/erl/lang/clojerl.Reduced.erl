%% @doc Clojure Reduced（归约完成）模块
%% @desc
%% - 功能：包装值以信号归约操作应提前终止
%% - 依赖：
%%   - 'clojerl.IDeref' - 解引用协议（获取包装的值）
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IStringable' - 字符串转换协议
%%
%% @private
-module('clojerl.Reduced').

-include("clojerl.hrl").

-behavior('clojerl.IDeref').
-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([deref/1]).
-export([hash/1]).
-export([str/1]).

-export([?CONSTRUCTOR/1]).
-export([is_reduced/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , value => any()  %% 包装的值
                 }.

%%------------------------------------------------------------------------------
%% 构造函数和判断函数
%%------------------------------------------------------------------------------

%% @doc 创建 Reduced 对象
-spec ?CONSTRUCTOR(any()) -> type().
?CONSTRUCTOR(Value) ->
  #{?TYPE => ?M, value => Value}.

%% @doc 判断值是否是 Reduced 对象
-spec is_reduced(type()) -> boolean().
is_reduced(#{?TYPE := ?M}) -> true;
is_reduced(_) -> false.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IDeref
%% @doc 解引用获取包装的值
deref(#{?TYPE := ?M, value := Value}) -> Value.

%% clojerl.IHash
%% @doc 计算 Reduced 对象的哈希值
hash(#{?TYPE := ?M} = X) -> erlang:phash2(X).

%% clojerl.IStringable
%% @doc 将 Reduced 对象转换为字符串
str(#{?TYPE := ?M, value := Value}) ->
  ValueStr = clj_rt:str(Value),
  <<"#<clojerl.Reduced ", ValueStr/binary, ">">>.
