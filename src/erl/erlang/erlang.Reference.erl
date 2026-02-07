%% @doc Erlang Reference 类型的 Clojure 包装器
%% @desc
%% - 功能：为 Erlang reference 提供 Clojure 接口，实现 IHash 和 IStringable 协议
%% - 作用：使 Erlang reference 可以在 Clojerl 环境中表示和使用
-module('erlang.Reference').

-behavior('clojerl.IStringable').
-behavior('clojerl.IHash').

-export([str/1]).
-export([hash/1]).

-export_type([type/0]).
-type type() :: reference().

%% clojerl.IStringable

str(Ref) when is_reference(Ref) ->
  <<"#Ref<", RefBin/binary>> = list_to_binary(erlang:ref_to_list(Ref)),
  <<"#<Ref ", RefBin/binary>>.

%% clojerl.IHash

hash(Ref) when is_reference(Ref) ->
  erlang:phash2(Ref).
