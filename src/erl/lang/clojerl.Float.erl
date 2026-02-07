%% @doc Clojure 浮点数模块
%% @desc
%% - 功能：为 Erlang 浮点数提供 Clojure 协议实现
%% - 依赖：
%%   - 'clojerl.IEquiv' - 等值比较协议（使用 == 而非 =:=）
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Float').

-behavior('clojerl.IEquiv').
-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([equiv/2]).
-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: float().

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IStringable
%% @doc 将浮点数转换为字符串
str(Float) when is_float(Float) ->
  list_to_binary(io_lib:format("~w", [Float])).

%% clojerl.IHash
%% @doc 计算浮点数的哈希值
hash(Float) when is_float(Float) ->
  erlang:phash2(Float).

%% clojerl.IEquiv
%% @doc 判断两个数值是否等价（使用 == 进行数值比较）
equiv(X, Y) when is_float(X) andalso is_float(Y) ->
  X == Y;
equiv(X, Y) ->
  X =:= Y.
