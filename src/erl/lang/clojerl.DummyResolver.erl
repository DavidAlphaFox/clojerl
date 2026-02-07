%% @doc DummyResolver 模块 - 虚拟符号解析器
%% @desc
%% - 功能：提供 IResolver 协议的最小实现，用于不需要真正符号解析的场景。
%%   所有解析操作都返回原始符号，命名空间始终返回 "dummy"。
%%   主要用于测试和作为占位符解析器。
%% - 依赖：实现 'clojerl.IResolver' 协议
-module('clojerl.DummyResolver').

-include("clojerl.hrl").

-behavior('clojerl.IResolver').

-export([?CONSTRUCTOR/0]).

-export([ 'current_ns'/1
        , 'resolve_class'/2
        , 'resolve_alias'/2
        , 'resolve_var'/2
        ]).

-export_type([type/0]).
-type type() :: #{?TYPE => ?M}.

?CONSTRUCTOR() ->
  #{?TYPE => ?M}.

%%------------------------------------------------------------------------------
%% Protocols
%%------------------------------------------------------------------------------

current_ns(_) -> clj_rt:symbol(<<"dummy">>).

resolve_class(_, Symbol) -> Symbol.

resolve_alias(_, Symbol) -> Symbol.

resolve_var(_, Symbol) -> Symbol.
