%% @doc Clojerl 类型系统表示模块
%% @desc
%% - 功能：表示 Clojerl 中的类型信息，提供类型检查和协议满足检查
%% - 作用：支持类型实例检查、协议满足检查、类型继承关系检查
%% - 特性：实现了面向对象风格的多态和类型系统
-module('erlang.Type').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.IHash').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , module/1
        , 'instance?'/2
        , 'satisfies?'/2
        , 'extends?'/2
        ]).

-export([hash/1]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , name  => atom()
                 }.

-spec ?CONSTRUCTOR(atom()) -> type().
?CONSTRUCTOR(Name) when is_atom(Name) ->
  #{?TYPE => ?M, name => Name}.

-spec module(type()) -> module().
module(#{?TYPE := ?M, name := Name}) -> Name.

-spec 'instance?'(type(), any()) -> boolean().
'instance?'(#{?TYPE := ?M, name := Name}, #{?TYPE := Name}) ->
  true;
'instance?'(#{?TYPE := ?M, name := Name}, X) ->
  clj_rt:type_module(X) == Name.

-spec 'satisfies?'(type(), any()) -> boolean().
'satisfies?'(#{?TYPE := ?M, name := Type}, X) ->
  Type:?SATISFIES(X).

-spec 'extends?'(type(), type()) -> boolean().
'extends?'(#{?TYPE := ?M, name := Type}, #{?TYPE := ?M, name := ValueType}) ->
  Type:?EXTENDS(ValueType).

%%------------------------------------------------------------------------------
%% Protocols
%%------------------------------------------------------------------------------

hash(#{?TYPE := ?M, name := Name}) -> erlang:phash2(Name).

str(#{?TYPE := ?M, name := Name}) -> erlang:atom_to_binary(Name, utf8).
