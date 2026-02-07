%% @doc ProcessVal 模块 - 进程字典值容器
%% @desc
%% - 功能：提供基于 Erlang 进程字典的值存储机制。每个 ProcessVal 实例
%%   在进程字典中存储值，提供快速的进程本地状态访问。支持重置和销毁操作。
%%   适用于需要进程隔离状态的场景。
%% - 依赖：实现 'clojerl.IDeref', 'clojerl.IEquiv', 'clojerl.IHash',
%%   'clojerl.IStringable' 协议
-module('clojerl.ProcessVal').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.IDeref').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , reset/2
        , destroy/1
        ]).

-export([deref/1]).
-export([equiv/2]).
-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , id    => {process_val, integer()}
                 }.

-spec ?CONSTRUCTOR(any()) -> type().
?CONSTRUCTOR(Value) ->
  Id = {process_val, erlang:unique_integer()},
  _  = erlang:put(Id, {ok, Value}),
  #{ ?TYPE => ?M
   , id    => Id
   }.

-spec reset(type(), any()) -> any().
reset(#{?TYPE := ?M, id := Id}, Value) ->
  _ = erlang:put(Id, {ok, Value}),
  Value.

-spec destroy(type()) -> ok.
destroy(#{?TYPE := ?M, id := Id}) ->
  erlang:erase(Id),
  ok.

%%------------------------------------------------------------------------------
%% Protocols
%%------------------------------------------------------------------------------

str(#{?TYPE := ?M, id := {process_val, Id}}) ->
  IdStr = integer_to_binary(Id),
  <<"#<clojerl.ProcessVal ", IdStr/binary, ">">>.

deref(#{?TYPE := ?M, id := Id}) ->
  case erlang:get(Id) of
    undefined   -> ?ERROR([<<"No process value available for: ">>, Id]);
    {ok, Value} -> Value
  end.

equiv( #{?TYPE := ?M, id := Id}
     , #{?TYPE := ?M, id := Id}
     ) ->
  true;
equiv(_, _) ->
  false.

hash(#{?TYPE := ?M, id := Id}) ->
  erlang:phash2(Id).
