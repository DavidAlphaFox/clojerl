%% @doc BitString 模块 - Erlang 二进制串的 Clojure 接口
%% @desc
%% - 功能：为 Erlang 的 bitstring 类型提供 Clojure 协议实现，支持计数、哈希、
%%   序列化和字符串表示等功能。将 Erlang 原生二进制串集成到 Clojerl 类型系统中。
%% - 依赖：实现 'clojerl.ICounted', 'clojerl.IHash', 'clojerl.ISequential',
%%   'clojerl.ISeqable', 'clojerl.IStringable' 协议
-module('clojerl.BitString').

-include("clojerl.hrl").

-behavior('clojerl.ICounted').
-behavior('clojerl.IHash').
-behavior('clojerl.ISequential').
-behavior('clojerl.ISeqable').
-behavior('clojerl.IStringable').

-export([count/1]).
-export([hash/1]).
-export([ seq/1
        , to_list/1
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: bitstring().

%%------------------------------------------------------------------------------
%% Protocols
%%------------------------------------------------------------------------------

count(BitString) ->
  bit_size(BitString).

hash(BitString) ->
  erlang:phash2(BitString).

seq(<<>>) -> ?NIL;
seq(BitString) -> bitstring_to_list(BitString).

to_list(Str)  -> seq(Str).

str(BitString) when is_bitstring(BitString) ->
  Elements    = do_str(bitstring_to_list(BitString), []),
  ElementsStr = string:join(Elements, " "),
  ElementsBin = iolist_to_binary(ElementsStr),

  <<"#bin[", ElementsBin/binary, "]">>.

%%------------------------------------------------------------------------------
%% Internal
%%------------------------------------------------------------------------------

do_str([], Acc) ->
  lists:reverse(Acc);
do_str([Byte | Rest], Acc) when is_integer(Byte) ->
  ByteStr = integer_to_list(Byte),
  do_str(Rest, [ByteStr | Acc]);
do_str([BitString | Rest], Acc) when is_bitstring(BitString) ->
  Size           = bit_size(BitString),
  <<Value:Size>> = BitString,
  ValueStr       = integer_to_list(Value),
  SizeStr        = integer_to_list(Size),
  BitStringStr   = ["[", ValueStr, " :unit ", SizeStr, " :size 1]"],
  do_str(Rest, [BitStringStr | Acc]).
