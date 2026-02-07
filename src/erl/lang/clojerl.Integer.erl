%% @doc 整数类型模块
%% @desc
%% - 功能：为 Erlang 整数提供 Clojure 协议实现
%% - 依赖：'clojerl.IHash'（哈希协议）、'clojerl.IStringable'（字符串转换协议）
-module('clojerl.Integer').

-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: integer().

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IStringable
%% @doc 将整数转换为二进制字符串

str(Int) when is_integer(Int) ->
  integer_to_binary(Int).

%% clojerl.IHash
%% @doc 计算整数的哈希值

hash(Int) when is_integer(Int) ->
  erlang:phash2(Int).
