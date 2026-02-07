%% @doc 基础错误异常模块
%% @desc
%% - 功能：Clojerl 的基础错误类，所有其他错误类型的父类
%% - 提供错误消息的基本功能，用于一般性错误情况
-module('clojerl.Error').

-include("clojerl.hrl").

-behavior('clojerl.IEquiv').
-behavior('clojerl.IError').
-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([?CONSTRUCTOR/1]).

-export([equiv/2]).
-export([ message/1
        , message/2
        ]).
-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE   => ?M
                 , message => binary()
                 }.

-spec ?CONSTRUCTOR(binary()) -> type().
?CONSTRUCTOR(Message) when is_binary(Message) ->
  #{ ?TYPE   => ?M
   , message => Message
   }.

%%------------------------------------------------------------------------------
%% Protocols
%%------------------------------------------------------------------------------

%% clojerl.IEquiv

equiv(#{?TYPE := ?M} = X, #{?TYPE := ?M} = X) ->
  true;
equiv(_, _) ->
  false.

%% clojerl.IError

message(#{?TYPE := ?M, message := Message}) ->
  Message.

message(#{?TYPE := ?M} = Error, Msg) ->
  Error#{message := Msg}.

%% clojerl.IHash

hash(#{?TYPE := ?M} = Error) ->
  erlang:phash2(Error).

%% clojerl.IStringable

str(#{?TYPE := ?M} = Error) ->
  clj_utils:error_str(?M, message(Error)).
