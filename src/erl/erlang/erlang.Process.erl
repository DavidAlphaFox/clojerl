%% @doc Erlang 进程标识符（PID）的 Clojure 包装器
%% @desc
%% - 功能：为 Erlang PID 提供 Clojure 接口，实现 IHash 和 IStringable 协议
%% - 作用：使 Erlang 进程可以在 Clojerl 环境中表示和使用
-module('erlang.Process').

-behavior('clojerl.IStringable').
-behavior('clojerl.IHash').

-export([str/1]).
-export([hash/1]).

-export_type([type/0]).
-type type() :: pid().

%% clojerl.IStringable

str(Pid) when is_pid(Pid) ->
  PidStr = pid_to_list(Pid),
  PidBin = list_to_binary(PidStr),
  <<"#", PidBin/binary>>.

%% clojerl.IHash

hash(Pid) when is_pid(Pid) ->
  erlang:phash2(Pid).
