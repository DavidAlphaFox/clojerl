%% @doc Clojure 向量模块
%% @desc
%% - 功能：实现 Clojure 不可变持久化向量类型，支持高效的随机访问
%% - 依赖：
%%   - 'clojerl.IAssociative' - 关联集合协议
%%   - 'clojerl.ICounted' - 计数协议
%%   - 'clojerl.IColl' - 集合协议
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IEncodeErlang' - Erlang 编码协议
%%   - 'clojerl.IFn' - 函数协议，向量可作为函数按索引查找值
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.ILookup' - 查找协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.IReduce' - 归约协议
%%   - 'clojerl.IReversible' - 可反转协议
%%   - 'clojerl.IIndexed' - 索引访问协议（支持 nth）
%%   - 'clojerl.ISequential' - 顺序集合协议
%%   - 'clojerl.IStack' - 栈协议
%%   - 'clojerl.ISeqable' - 可序列化协议
%%   - 'clojerl.IStringable' - 字符串转换协议
%%   - 'clojerl.IVector' - 向量协议
-module('clojerl.Vector').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.IAssociative').
-behavior('clojerl.ICounted').
-behavior('clojerl.IColl').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IEncodeErlang').
-behavior('clojerl.IFn').
-behavior('clojerl.IHash').
-behavior('clojerl.ILookup').
-behavior('clojerl.IMeta').
-behavior('clojerl.IReduce').
-behavior('clojerl.IReversible').
-behavior('clojerl.IIndexed').
-behavior('clojerl.ISequential').
-behavior('clojerl.IStack').
-behavior('clojerl.ISeqable').
-behavior('clojerl.IStringable').
-behavior('clojerl.IVector').

-export([?CONSTRUCTOR/1]).
-export([ contains_key/2
        , entry_at/2
        , assoc/3
        ]).
-export([count/1]).
-export([ cons/2
        , empty/1
        ]).
-export([equiv/2]).
-export(['clj->erl'/2]).
-export([apply/2]).
-export([hash/1]).
-export([ get/2
        , get/3
        ]).
-export([ meta/1
        , with_meta/2
        ]).
-export([rseq/1]).
-export([ reduce/2
        , reduce/3
        ]).
-export([ nth/2
        , nth/3
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
                 , array => clj_vector:vector()  %% 底层向量存储
                 , meta  => ?NIL | any()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 从列表创建向量
-spec ?CONSTRUCTOR(list()) -> type().
?CONSTRUCTOR(Items) when is_list(Items) ->
  #{ ?TYPE => ?M
   , array => clj_vector:new(Items)
   , meta  => ?NIL
   }.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IAssociative
%% @doc 判断向量是否包含指定索引
contains_key(#{?TYPE := ?M, array := Array}, Index) ->
  is_valid_index(Array, Index).

%% @doc 获取指定索引的条目
entry_at(#{?TYPE := ?M, array := Array}, Index) ->
  case is_valid_index(Array, Index) of
    true  -> ?CONSTRUCTOR([Index, clj_vector:get(Index, Array)]);
    false -> ?NIL
  end.

%% @doc 关联索引和值到向量
assoc(#{?TYPE := ?M, array := Array} = Vector, Index, Value) ->
  case is_valid_index(Array, Index) orelse Index == clj_vector:size(Array) of
    true  -> Vector#{array => clj_vector:set(Index, Value, Array)};
    false -> ?ERROR(<<"Index out of bounds">>)
  end.

%% clojerl.ICounted
%% @doc 获取向量长度
count(#{?TYPE := ?M, array := Array}) -> clj_vector:size(Array).

%% clojerl.IColl
%% @doc 在向量尾部添加元素
cons(#{?TYPE := ?M, array := Array} = Vector, X) ->
  Vector#{array => clj_vector:cons(X, Array)}.

%% @doc 返回空向量
empty(_) -> ?CONSTRUCTOR([]).

%% clojerl.IEquiv
%% @doc 判断向量是否等价
equiv( #{?TYPE := ?M, array := X}
     , #{?TYPE := ?M, array := Y}
     ) ->
  case clj_vector:size(X) == clj_vector:size(Y) of
    true ->
      X1 = clj_vector:to_list(X),
      Y1 = clj_vector:to_list(Y),
      'erlang.List':equiv(X1, Y1);
    false -> false
  end;
equiv(#{?TYPE := ?M, array := X}, Y) ->
  case clj_rt:'sequential?'(Y) of
    true  -> 'erlang.List':equiv(clj_vector:to_list(X), Y);
    false -> false
  end.

%% clojerl.IEncodeErlang
%% @doc 将向量转换为 Erlang 元组
'clj->erl'(#{?TYPE := ?M} = X, Recursive) ->
  List0 = to_list(X),
  List1 = case Recursive of
            true  -> [clj_rt:'clj->erl'(Item, true) || Item <- List0];
            false -> List0
          end,
  list_to_tuple(List1).

%% clojerl.IFn
%% @doc 将向量作为函数调用（按索引查找值）
apply(#{?TYPE := ?M, array := Array}, [Index]) when is_integer(Index) ->
  ?ERROR_WHEN(not is_valid_index(Array, Index), <<"Index out of bounds">>),
  clj_vector:get(Index, Array);
apply(#{?TYPE := ?M}, [_]) ->
  ?ERROR(<<"Key must be integer">>);
apply(#{?TYPE := ?M}, Args) ->
  CountBin = integer_to_binary(length(Args)),
  ?ERROR(<<"Wrong number of args for vector, got: ", CountBin/binary>>).

%% clojerl.IHash
%% @doc 计算向量的哈希值
hash(#{?TYPE := ?M, array := Array}) ->
  clj_murmur3:ordered(clj_vector:to_list(Array)).

%% clojerl.ILookup
%% @doc 获取索引处的值（默认返回 nil）
get(#{?TYPE := ?M} = Vector, Index) ->
  get(Vector, Index, ?NIL).

%% @doc 获取索引处的值（可指定默认值）
get(#{?TYPE := ?M, array := Array}, Index, NotFound) ->
  case is_valid_index(Array, Index) of
    true  -> clj_vector:get(Index, Array);
    false -> NotFound
  end.

%% clojerl.IMeta
%% @doc 获取向量的元数据
meta(#{?TYPE := ?M, meta := Meta}) -> Meta.

%% @doc 设置向量的元数据
with_meta(#{?TYPE := ?M} = Vector, Meta) ->
  Vector#{meta => Meta}.

%% clojerl.IReduce
%% @doc 归约向量（无初始值）
reduce(#{?TYPE := ?M, array := Array}, F) ->
  clj_vector:reduce(F, Array).

%% @doc 归约向量（有初始值）
reduce(#{?TYPE := ?M, array := Array}, F, Init) ->
  clj_vector:reduce(F, Init, Array).

%% clojerl.IReversible
%% @doc 获取反向序列
rseq(#{?TYPE := ?M, array := Array} = Vector) ->
  case clj_vector:size(Array) of
    0 -> ?NIL;
    Count -> 'clojerl.Vector.RSeq':?CONSTRUCTOR(Vector, Count - 1)
  end.

%% clojerl.IIndexed
%% @doc 获取第 N 个元素（越界则报错）
nth(#{?TYPE := ?M, array := Array}, N) ->
  case is_valid_index(Array, N) of
    true  -> clj_vector:get(N, Array);
    false -> error(badarg)
  end.

%% @doc 获取第 N 个元素（越界则返回默认值）
nth(#{?TYPE := ?M, array := Array}, N, NotFound) ->
  case is_valid_index(Array, N) of
    true  -> clj_vector:get(N, Array);
    false -> NotFound
  end.

%% clojerl.IStack
%% @doc 查看栈顶元素（最后一个元素）
peek(#{?TYPE := ?M, array := Array}) ->
  case clj_vector:size(Array) of
    0    -> ?NIL;
    Size -> clj_vector:get(Size - 1, Array)
  end.

%% @doc 弹出栈顶元素
pop(#{?TYPE := ?M, array := Array} = Vector) ->
  Vector#{array => clj_vector:pop(Array)}.

%% clojerl.ISeqable
%% @doc 获取向量的序列形式
seq(#{?TYPE := ?M, array := Array}) ->
  case clj_vector:size(Array) of
    0 -> ?NIL;
    Size when Size =< ?CHUNK_SIZE -> clj_vector:to_list(Array);
    _ -> 'clojerl.Vector.ChunkedSeq':?CONSTRUCTOR(Array, 0, 0)
  end.

%% @doc 将向量转换为列表
to_list(#{?TYPE := ?M, array := Array}) ->
  clj_vector:to_list(Array).

%% clojerl.IStringable
%% @doc 将向量转换为字符串
str(#{?TYPE := ?M} = Vector) ->
  clj_rt:print_str(Vector).

%%------------------------------------------------------------------------------
%% 辅助函数
%%------------------------------------------------------------------------------

%% @doc 判断索引是否有效
is_valid_index(Array, Index) ->
  is_integer(Index) andalso Index >= 0 andalso Index < clj_vector:size(Array).
