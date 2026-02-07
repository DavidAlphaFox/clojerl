%% @doc 分块缓冲区
%% @desc
%% - 功能：用于处理分块序列的缓冲区，提供添加元素、生成块和计数功能
%% - 依赖：作为内部辅助模块，用于构建 TupleChunk
%% @private
-module('clojerl.ChunkBuffer').

-include("clojerl.hrl").

-export([?CONSTRUCTOR/1]).

-export([ add/2
        , chunk/1
        , count/1
        ]).

-export_type([type/0]).
-type type() :: #{ ?TYPE  => ?M
                 , buffer => list()
                 }.

-spec ?CONSTRUCTOR(integer()) -> type().
?CONSTRUCTOR(_Capacity) ->
  #{ ?TYPE  => ?M
   , buffer => []
   }.

add(#{?TYPE := ?M, buffer := Items} = X, Item) ->
  X#{buffer := [Item | Items]}.

chunk(#{?TYPE := ?M, buffer := Items}) ->
  Tuple = list_to_tuple(lists:reverse(Items)),
  'clojerl.TupleChunk':?CONSTRUCTOR(Tuple).

count(#{?TYPE := ?M, buffer := Items}) ->
  length(Items).
