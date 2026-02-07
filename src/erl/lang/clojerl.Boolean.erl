%% @doc Clojure 布尔值模块
%% @desc
%% - 功能：为 Erlang 布尔值提供 Clojure 协议实现
%% - 依赖：'clojerl.IHash'（哈希协议）、'clojerl.IStringable'（字符串转换协议）
-module('clojerl.Boolean').

-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: boolean().

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IHash
%% @doc 计算布尔值的哈希值
hash(true)  -> erlang:phash2(true);
hash(false) -> erlang:phash2(false).

%% clojerl.IStringable
%% @doc 将布尔值转换为字符串
str(true)  -> <<"true">>;
str(false) -> <<"false">>.
