%% @doc Erlang Port 类型的 Clojure 包装器
%% @desc
%% - 功能：为 Erlang port 提供 Clojure 接口，实现 IHash 和 IStringable 协议
%% - 作用：使 Erlang port 可以在 Clojerl 环境中表示和使用
-module('erlang.Port').

-behavior('clojerl.IStringable').
-behavior('clojerl.IHash').

-export([str/1]).
-export([hash/1]).

-export_type([type/0]).
-type type() :: port().

%% clojerl.IStringable

str(Port) when is_port(Port) ->
  PortStr = erlang:port_to_list(Port),
  <<"#Port<", PortBin/binary>> = list_to_binary(PortStr),
  <<"#<Port ", PortBin/binary>>.

%% clojerl.IHash

hash(Port) when is_port(Port) ->
  erlang:phash2(Port).
