%% @doc Clojure 列表模块
%% @desc
%% - 功能：实现 Clojure 不可变持久化列表类型
%% - 依赖：
%%   - 'clojerl.ICounted' - 计数协议
%%   - 'clojerl.IColl' - 集合协议
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IEncodeErlang' - Erlang 编码协议
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.IReduce' - 归约协议
%%   - 'clojerl.ISeq' - 序列协议
%%   - 'clojerl.ISequential' - 顺序集合协议
%%   - 'clojerl.IStack' - 栈协议（支持 peek/pop）
%%   - 'clojerl.ISeqable' - 可序列化协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.List').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.ICounted').
-behavior('clojerl.IColl').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IEncodeErlang').
-behavior('clojerl.IHash').
-behavior('clojerl.IMeta').
-behavior('clojerl.IReduce').
-behavior('clojerl.ISeq').
-behavior('clojerl.ISequential').
-behavior('clojerl.IStack').
-behavior('clojerl.ISeqable').
-behavior('clojerl.IStringable').

-export([?CONSTRUCTOR/1]).

-export([count/1]).
-export([ cons/2
        , empty/1
        ]).
-export([equiv/2]).
-export(['clj->erl'/2]).
-export([hash/1]).
-export([ meta/1
        , with_meta/2
        ]).
-export([ reduce/2
        , reduce/3
        ]).
-export([ first/1
        , next/1
        , more/1
        ]).
-export([ peek/1
        , pop/1
        ]).
-export([ seq/1
        , to_list/1
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , items => list()     %% Erlang 列表存储元素
                 , meta  => ?NIL | any()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 从列表创建 Clojure 列表
-spec ?CONSTRUCTOR(list()) -> type().
?CONSTRUCTOR([]) ->
  #{?TYPE => ?M, items => [], meta => ?NIL};
?CONSTRUCTOR(Items) when is_list(Items) ->
  #{?TYPE => ?M, items => Items, meta => ?NIL};
?CONSTRUCTOR(?NIL) ->
  ?CONSTRUCTOR([]);
?CONSTRUCTOR(Items) ->
  ?CONSTRUCTOR(clj_rt:to_list(Items)).

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.ICounted
%% @doc 获取列表长度
count(#{?TYPE := ?M, items := Items}) -> length(Items).

%% clojerl.IColl
%% @doc 在列表头部添加元素（cons 操作）
cons(#{?TYPE := ?M, items := []} = List, X) ->
  List#{items => [X]};
cons(#{?TYPE := ?M, items := Items} = List, X) ->
  List#{items => [X | Items]}.

%% @doc 返回空列表
empty(_) -> ?CONSTRUCTOR([]).

%% clojerl.IEquiv
%% @doc 判断列表是否等价
equiv( #{?TYPE := ?M, items := X}
     , #{?TYPE := ?M, items := Y}
     ) ->
  clj_rt:equiv(X, Y);
equiv(#{?TYPE := ?M, items := X}, Y) ->
  case clj_rt:'sequential?'(Y) of
    true  -> 'erlang.List':equiv(X, Y);
    false -> false
  end.

%% clojerl.IEncodeErlang
%% @doc 将 Clojure 列表转换为 Erlang 列表
'clj->erl'(#{?TYPE := ?M} = X, Recursive) ->
  List = to_list(X),
  case Recursive of
    true  -> [clj_rt:'clj->erl'(Item, true) || Item <- List];
    false -> List
  end.

%% clojerl.IHash
%% @doc 计算列表的哈希值
hash(#{?TYPE := ?M, items := X}) ->
  clj_murmur3:ordered(X).

%% clojerl.IMeta
%% @doc 获取列表的元数据
meta(#{?TYPE := ?M, meta := Meta}) -> Meta.

%% @doc 设置列表的元数据
with_meta(#{?TYPE := ?M} = List, Metadata) ->
  List#{meta => Metadata}.

%% clojerl.IReduce
%% @doc 归约列表（无初始值）
reduce(#{?TYPE := ?M, items := []}, F) ->
  clj_rt:apply(F, []);
reduce(#{?TYPE := ?M, items := [First | Rest]}, F) ->
  do_reduce(F, First, Rest).

%% @doc 归约列表（有初始值）
reduce(#{?TYPE := ?M, items := Items}, F, Init) ->
  do_reduce(F, Init, Items).

%% @doc 归约辅助函数
do_reduce(F, Acc, [First | Items]) ->
  Val = clj_rt:apply(F, [Acc, First]),
  case 'clojerl.Reduced':is_reduced(Val) of
    true  -> 'clojerl.Reduced':deref(Val);
    false -> do_reduce(F, Val, Items)
  end;
do_reduce(_F, Acc, []) ->
  Acc.

%% clojerl.ISeq
%% @doc 获取列表第一个元素
first(#{?TYPE := ?M, items := []}) -> ?NIL;
first(#{?TYPE := ?M, items := [First | _]}) -> First.

%% @doc 获取除第一个元素的序列
next(#{?TYPE := ?M, items := []}) -> ?NIL;
next(#{?TYPE := ?M, items := [_ | []]}) -> ?NIL;
next(#{?TYPE := ?M, items := [_ | Rest]} = List) ->
  List#{items => Rest}.

%% @doc 获取除第一个元素的序列（若为空则返回自身）
more(#{?TYPE := ?M, items := []} = List) -> List;
more(#{?TYPE := ?M, items := [_ | Rest]} = List) ->
  List#{items => Rest}.

%% clojerl.IStack
%% @doc 查看栈顶元素
peek(#{?TYPE := ?M, items := Items}) ->
  'erlang.List':peek(Items).

%% @doc 弹出栈顶元素
pop(#{?TYPE := ?M, items := []}) ->
  ?ERROR(<<"Can't pop empty list">>);
pop(#{?TYPE := ?M, items := [_ | Rest]} = List) ->
  List#{items => Rest}.

%% clojerl.ISeqable
%% @doc 获取序列形式
seq(#{?TYPE := ?M, items := []}) -> ?NIL;
seq(#{?TYPE := ?M, items := Seq}) -> Seq.

%% @doc 转换为 Erlang 列表
to_list(#{?TYPE := ?M, items := Items}) -> Items.

%% clojerl.IStringable
%% @doc 将列表转换为字符串
str(#{?TYPE := ?M, items := []}) ->
  <<"()">>;
str(#{?TYPE := ?M} = List) ->
  clj_rt:print_str(List).
