%% @doc Clojure 集合（Set）模块
%% @desc
%% - 功能：实现 Clojure 不可变持久化集合类型，支持哈希冲突处理
%% - 依赖：
%%   - 'clojerl.ICounted' - 计数协议
%%   - 'clojerl.IColl' - 集合协议
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IFn' - 函数协议，集合可作为函数检查成员
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.ILookup' - 查找协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.ISet' - 集合协议（支持 disjoin/contains）
%%   - 'clojerl.ISeqable' - 可序列化协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Set').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.ICounted').
-behavior('clojerl.IColl').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IFn').
-behavior('clojerl.IHash').
-behavior('clojerl.ILookup').
-behavior('clojerl.IMeta').
-behavior('clojerl.ISet').
-behavior('clojerl.ISeqable').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , ?CONSTRUCTOR/2
        ]).
-export([count/1]).
-export([ cons/2
        , empty/1
        ]).
-export([equiv/2]).
-export([apply/2]).
-export([hash/1]).
-export([ get/2
        , get/3
        ]).
-export([ meta/1
        , with_meta/2
        ]).
-export([ disjoin/2
        , contains/2
        ]).
-export([ seq/1
        , to_list/1
        ]).
-export([str/1]).

-import( clj_hash_collision
       , [ get_entry/3
         , create_entry/4
         , without_entry/3
         ]).

-type mappings() :: #{integer() => {any(), true} | [{any(), true}]}.

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , set   => map()       %% 哈希到值的映射
                 , count => non_neg_integer()  %% 元素计数
                 , meta  => ?NIL | any()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 从值列表创建集合
-spec ?CONSTRUCTOR(list()) -> type().
?CONSTRUCTOR(Values) when is_list(Values) ->
  ?CONSTRUCTOR(Values, false);
?CONSTRUCTOR(Values) ->
  ?CONSTRUCTOR(clj_rt:to_list(Values)).

%% @doc 从值列表创建集合（可选择是否对重复值报错）
-spec ?CONSTRUCTOR(list(), boolean()) -> type().
?CONSTRUCTOR(Values, FailDuplicates) when is_list(Values) ->
  {Count, MapSet, _} = lists:foldl( fun build_mappings/2
                                  , {0, #{}, FailDuplicates}
                                  , Values
                                  ),
  #{ ?TYPE => ?M
   , set   => MapSet
   , count => Count
   , meta  => ?NIL
   }.

%% @private
%% @doc 构建集合映射（处理哈希冲突）
-spec build_mappings(any(), {integer(), mappings(), boolean()}) ->
  {integer(), mappings(), boolean()}.
build_mappings(Value, {Count, Map, FailDuplicates}) ->
  Hash = clj_rt:hash(Value),
  {Diff, Entry} = create_entry(Map, Hash, Value, true),
  ?ERROR_WHEN( FailDuplicates andalso Diff == 0
             , [<<"Duplicate key: ">>, Value]
             ),
  {Count + Diff, Map#{Hash => Entry}, FailDuplicates}.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.ICounted
%% @doc 获取集合中的元素数量
count(#{?TYPE := ?M, count := Count}) -> Count.

%% clojerl.IColl
%% @doc 向集合添加元素
cons(#{?TYPE := ?M, set := MapSet, count := Count} = Set, X) ->
  Hash  = clj_rt:hash(X),
  {Diff, Entry} = create_entry(MapSet, Hash, X, true),
  Set#{set := MapSet#{Hash => Entry}, count := Count + Diff}.

%% @doc 返回空集合
empty(_) -> ?CONSTRUCTOR([]).

%% clojerl.IEquiv
%% @doc 判断集合是否等价
equiv( #{?TYPE := ?M, set := MapSetX, count := Count}
     , #{?TYPE := ?M, set := MapSetY, count := Count}
     ) ->
  clj_hash_collision:equiv(MapSetX, MapSetY);
equiv(#{?TYPE := ?M, set := MapSetX}, Y) ->
  clj_rt:'set?'(Y) andalso do_equiv(maps:values(MapSetX), Y).

%% @doc 等价判断辅助函数
do_equiv([], _) ->
  true;
do_equiv([{V, _} | Rest], Y) ->
  case 'clojerl.ISet':contains(Y, V) of
    false -> false;
    true  -> do_equiv(Rest, Y)
  end.

%% clojerl.IFn
%% @doc 将集合作为函数调用（检查元素是否在集合中）
apply(#{?TYPE := ?M, set := MapSet}, [Item]) ->
  Hash = clj_rt:hash(Item),
  case get_entry(MapSet, Hash, Item) of
    ?NIL   -> ?NIL;
    {V, _} -> V
  end;
apply(_, Args) ->
  CountBin = integer_to_binary(length(Args)),
  throw(<<"Wrong number of args for set, got: ", CountBin/binary>>).

%% clojerl.IHash
%% @doc 计算集合的哈希值
hash(#{?TYPE := ?M, set := MapSet}) ->
  Fun    = fun
             (Hash, Entry, Acc) when is_list(Entry) ->
               lists:duplicate(length(Entry), Hash) ++ Acc;
             (Hash, _, Acc) ->
               [Hash | Acc]
           end,
  Hashes = maps:fold(Fun, [], MapSet),
  clj_murmur3:unordered_hashes(Hashes).

%% clojerl.ILookup
%% @doc 获取值（默认返回 nil）
get(#{?TYPE := ?M} = Set, Value) ->
  get(Set, Value, ?NIL).

%% @doc 获取值（可指定默认值）
get(#{?TYPE := ?M, set := MapSet}, Value, NotFound) ->
  Hash = clj_rt:hash(Value),
  case get_entry(MapSet, Hash, Value) of
    ?NIL   -> NotFound;
    {V, _} -> V
  end.

%% clojerl.IMeta
%% @doc 获取集合的元数据
meta(#{?TYPE := ?M, meta := Meta}) -> Meta.

%% @doc 设置集合的元数据
with_meta(#{?TYPE := ?M} = Set, Metadata) ->
  Set#{meta => Metadata}.

%% clojerl.ISet
%% @doc 从集合中移除元素
disjoin(#{?TYPE := ?M, set := MapSet0, count := Count} = Set, Value) ->
  Hash = clj_rt:hash(Value),
  {Diff, MapSet1} = without_entry(MapSet0, Hash, Value),
  Set#{set => MapSet1, count => Count + Diff}.

%% @doc 判断集合是否包含指定值
contains(#{?TYPE := ?M, set := MapSet}, Value) ->
  Hash = clj_rt:hash(Value),
  get_entry(MapSet, Hash, Value) /= ?NIL.

%% clojerl.ISeqable
%% @doc 获取集合的序列形式
seq(#{?TYPE := ?M, set := MapSet} = Set) ->
  case maps:size(MapSet) of
    0 -> ?NIL;
    _ -> to_list(Set)
  end.

%% @doc 将集合转换为列表
to_list(#{?TYPE := ?M, set := MapSet}) ->
  maps:fold(fun to_list_fold/3, [], MapSet).

to_list_fold(_Hash, {V, _}, List) ->
  [V | List];
to_list_fold(_Hash, Vs, List) ->
  [V || {V, _} <- Vs] ++ List.

%% clojerl.IStringable
%% @doc 将集合转换为字符串
str(#{?TYPE := ?M} = Set) ->
  clj_rt:print_str(Set).
