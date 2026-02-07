%% @doc Clojure 范围（Range）模块
%% @desc
%% - 功能：实现惰性数值范围序列，支持起始值、结束值和步长
%% - 依赖：
%%   - 'clojerl.ICounted' - 计数协议
%%   - 'clojerl.IColl' - 集合协议
%%   - 'clojerl.IChunkedSeq' - 分块序列协议
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IEncodeErlang' - Erlang 编码协议
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.IReduce' - 归约协议
%%   - 'clojerl.ISeq' - 序列协议
%%   - 'clojerl.ISequential' - 顺序集合协议
%%   - 'clojerl.ISeqable' - 可序列化协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Range').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.ICounted').
-behavior('clojerl.IColl').
-behavior('clojerl.IChunkedSeq').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IEncodeErlang').
-behavior('clojerl.IHash').
-behavior('clojerl.IMeta').
-behavior('clojerl.IReduce').
-behavior('clojerl.ISeq').
-behavior('clojerl.ISequential').
-behavior('clojerl.ISeqable').
-behavior('clojerl.IStringable').

-export([?CONSTRUCTOR/3]).

-export([count/1]).
-export([ cons/2
        , empty/1
        ]).
-export([ chunked_first/1
        , chunked_more/1
        , chunked_next/1
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
-export([ seq/1
        , to_list/1
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , start => integer()  %% 起始值
                 , 'end' => integer()  %% 结束值（不包含）
                 , step  => integer()  %% 步长
                 , meta  => ?NIL | any()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 创建范围（空范围返回空列表）
-spec ?CONSTRUCTOR(integer(), integer(), integer()) -> type() | [].
?CONSTRUCTOR(Start, End, Step) when Step > 0, End =< Start;
                                    Step < 0, Start =< End;
                                    Start == End ->
  [];
?CONSTRUCTOR(Start, End, Step) ->
  #{ ?TYPE => ?M
   , start => Start
   , 'end' => End
   , step  => Step
   , meta  => ?NIL
   }.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.ICounted
%% @doc 计算范围中的元素数量
count(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}) ->
  (End - Start + Step) div Step - 1.

%% clojerl.IColl
%% @doc 在范围前添加元素
cons(#{?TYPE := ?M} = Range, X) ->
  'clojerl.Cons':?CONSTRUCTOR(X, Range).

%% @doc 返回空列表
empty(_) -> [].

%% clojerl.IChunkedSeq
%% @doc 获取第一个分块
chunked_first(#{?TYPE := ?M, start := Start0, 'end' := End0, step := Step0}) ->
  End1    = Start0 + ?CHUNK_SIZE * Step0,
  End2    = case Step0 >= 0 of
              true  -> erlang:min(End0, End1);
              false -> erlang:max(End0, End1)
            end,
  Numbers = to_list(Start0, End2, Step0),
  Tuple   = list_to_tuple(Numbers),
  'clojerl.TupleChunk':?CONSTRUCTOR(Tuple).

%% @doc 获取下一个分块序列
chunked_next(#{?TYPE := ?M} = Range) ->
  case chunked_more(Range) of
    [] -> ?NIL;
    More -> More
  end.

%% @doc 获取剩余的分块序列
chunked_more(#{?TYPE := ?M, start := Start0, 'end' := End0, step := Step0}) ->
  Start1 = Start0 + ?CHUNK_SIZE * Step0,
  ?CONSTRUCTOR(Start1, End0, Step0).

%% clojerl.IEquiv
%% @doc 判断范围是否等价
equiv( #{?TYPE := ?M, start := Start, 'end' := End, step := Step}
     , #{?TYPE := ?M, start := Start, 'end' := End, step := Step}
     ) ->
  true;
equiv(#{?TYPE := ?M} = X, Y) ->
  case clj_rt:'sequential?'(Y) of
    true  -> 'erlang.List':equiv(to_list(X), Y);
    false -> false
  end.

%% clojerl.IEncodeErlang
%% @doc 将范围转换为 Erlang 列表
'clj->erl'(#{?TYPE := ?M} = X, _Recursive) ->
  %% A range will always have numbers, which must not implement IEncodeErlang
  to_list(X).

%% clojerl.IHash
%% @doc 计算范围的哈希值
hash(#{?TYPE := ?M} = X) ->
  clj_murmur3:ordered(to_list(X)).

%% clojerl.IMeta
%% @doc 获取范围的元数据
meta(#{?TYPE := ?M, meta := Meta}) -> Meta.

%% @doc 设置范围的元数据
with_meta(#{?TYPE := ?M} = Range, Metadata) ->
  Range#{meta => Metadata}.

%% clojerl.IReduce
%% @doc 归约范围（无初始值）
reduce(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}, F) ->
  do_reduce(F, Start, Start + Step, End, Step).

%% @doc 归约范围（有初始值）
reduce(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}, F, Init) ->
  do_reduce(F, Init, Start, End, Step).

%% @doc 归约辅助函数
do_reduce(_F, Acc, Start, End, Step) when
    Step >= 0, Start + Step > End;
    Step < 0, Start + Step < End ->
  Acc;
do_reduce(F, Acc, Start, End, Step) ->
  Val = clj_rt:apply(F, [Acc, Start]),
  case 'clojerl.Reduced':is_reduced(Val) of
    true  -> 'clojerl.Reduced':deref(Val);
    false -> do_reduce(F, Val, Start + Step, End, Step)
  end.

%% clojerl.ISeq
%% @doc 获取范围的第一个元素
first(#{?TYPE := ?M, start := Start}) -> Start.

%% @doc 获取除第一个元素外的序列
next(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}) when
    Step > 0, Start + Step >= End;
    Step < 0, Start + Step =< End ->
  ?NIL;
next(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}) ->
  ?CONSTRUCTOR(Start + Step, End, Step).

%% @doc 获取除第一个元素外的序列（空则返回空列表）
more(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}) when
    Step > 0, Start + Step >= End;
    Step < 0, Start + Step =< End ->
  [];
more(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}) ->
  ?CONSTRUCTOR(Start + Step, End, Step).

%% clojerl.ISeqable
%% @doc 获取范围的序列形式
seq(#{?TYPE := ?M} = Seq) -> Seq.

%% @doc 将范围转换为列表
to_list(#{?TYPE := ?M, start := Start, 'end' := End, step := Step}) ->
  to_list(Start, End, Step).

%% clojerl.IStringable
%% @doc 将范围转换为字符串
str(#{?TYPE := ?M} = Range) ->
  clj_rt:print_str(Range).

%%------------------------------------------------------------------------------
%% 辅助函数
%%------------------------------------------------------------------------------

%% @doc 将范围参数转换为列表
-spec to_list(number(), number(), number()) -> [number()].
to_list(Start, End, Step) when is_float(Start);
                               is_float(End);
                               is_float(Step) ->
  N = clj_utils:ceil((End - Start) / Step),
  to_list_loop(N, Start, Step, []);
to_list(Start, End, Step) when Step >= 0 ->
  lists:seq(Start, End - 1, Step);
to_list(Start, End, Step) when Step < 0 ->
  lists:seq(Start, End + 1, Step).

%% We need to build the list from the Start to the End to avoid
%% floating point rounding errors.
%% @doc 浮点数范围列表构建循环（避免舍入误差）
-spec to_list_loop(integer(), number(), number(), [number()]) -> [number()].
to_list_loop(N, X, Step, L) when N >= 4 ->
  Y = X + Step,
  Z = Y + Step,
  W = Z + Step,
  to_list_loop(N - 4, W + Step, Step, [W, Z, Y, X | L]);
to_list_loop(N, X, Step, L) when N >= 2 ->
  Y = X + Step,
  to_list_loop(N - 2, Y + Step, Step, [Y, X | L]);
to_list_loop(1, X, _, L) ->
  lists:reverse([X | L]);
to_list_loop(0, _, _, L) ->
  lists:reverse(L).
