%% @doc Clojure Reader 条件读取数据结构
%% @desc
%% - 功能：实现 Clojure reader 的条件读取功能（Reader Conditional）
%%   - 支持基于特性（feature）的条件表达式读取
%%   - 支持拼接（splicing）和非拼接两种模式
%%   - 提供 #? 语法糖用于条件编译
%% - 用途：用于 Clojure 代码的条件编译和平台特定代码选择
%% @end
%% @private
-module('clojerl.reader.ReaderConditional').

-include("clojerl.hrl").

-behavior('clojerl.IEquiv').
-behavior('clojerl.IHash').
-behavior('clojerl.ILookup').
-behavior('clojerl.IStringable').

-export([?CONSTRUCTOR/2]).

-export([equiv/2]).
-export([hash/1]).
-export([ get/2
        , get/3
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE       => ?M
                 , list        => any()
                 , is_splicing => boolean()
                 }.

-spec ?CONSTRUCTOR('clojerl.List':type(), boolean()) -> type().
?CONSTRUCTOR(List, IsSplicing) ->
  #{ ?TYPE       => ?M
   , list        => List
   , is_splicing => IsSplicing
   }.

equiv( #{?TYPE := ?M, list := X1, is_splicing := Y}
     , #{?TYPE := ?M, list := X2, is_splicing := Y}
     ) ->
  clj_rt:equiv(X1, X2);
equiv(_, _) ->
  false.

%% clojerl.IHash

hash(#{?TYPE := ?M} = ReaderCond) ->
  erlang:phash2(ReaderCond).

%% clojerl.ILookup

get(#{?TYPE := ?M} = ReaderCond, Key) ->
  get(ReaderCond, Key, ?NIL).

get(#{?TYPE := ?M, list := Form}, form, _) ->
  Form;
get(#{?TYPE := ?M, is_splicing := IsSplicing}, 'splicing?', _) ->
  IsSplicing;
get(#{?TYPE := ?M}, _, NotFound) ->
  NotFound.

%% clojerl.IStringable

str(#{?TYPE := ?M, list := List, is_splicing := IsSplicing}) ->
  Splice = case IsSplicing of
             true  -> <<"@">>;
             false -> <<>>
           end,
  ListBin = clj_rt:str(List),
  <<"#?", Splice/binary, ListBin/binary>>.
