%% @doc Clojure 符号模块
%% @desc
%% - 功能：实现 Clojure 符号（symbol）类型，符号是类似 foo 或 ns/foo 的标识符
%% - 依赖：
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IFn' - 函数协议，符号可作为函数从映射中查找值
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.INamed' - 命名协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Symbol').

-include("clojerl.hrl").

-behavior('clojerl.IEquiv').
-behavior('clojerl.IFn').
-behavior('clojerl.IHash').
-behavior('clojerl.IMeta').
-behavior('clojerl.INamed').
-behavior('clojerl.IStringable').

-export([?CONSTRUCTOR/1, ?CONSTRUCTOR/2]).

-export([equiv/2]).
-export([apply/2]).
-export([hash/1]).
-export([ meta/1
        , with_meta/2
        ]).
-export([ name/1
        , namespace/1
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , ns    => ?NIL | binary()
                 , name  => binary()
                 , meta  => ?NIL | any()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 从字符串创建符号（自动解析命名空间）
-spec ?CONSTRUCTOR(binary()) -> type().
?CONSTRUCTOR(<<"/">>)  ->
  ?CONSTRUCTOR(?NIL, <<"/">>);
?CONSTRUCTOR(Name0) when is_binary(Name0) ->
  case binary:split(Name0, <<"/">>) of
    [Namespace, Name1] ->
      ?CONSTRUCTOR(Namespace, Name1);
    _ ->
      ?CONSTRUCTOR(?NIL, Name0)
  end.

%% @doc 从命名空间和名称创建符号
-spec ?CONSTRUCTOR(binary() | ?NIL, binary()) -> type().
?CONSTRUCTOR(Namespace, Name)
  when is_binary(Namespace) orelse Namespace == ?NIL,
       is_binary(Name) ->
  #{ ?TYPE => ?M
   , ns    => Namespace
   , name  => Name
   , meta  => ?NIL
   }.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IFn
%% @doc 符号可作为函数，从映射中查找对应的值

apply(#{?TYPE := ?M} = Symbol, [Map]) ->
  clj_rt:get(Map, Symbol);
apply(#{?TYPE := ?M} = Symbol, [Map, NotFound]) ->
  clj_rt:get(Map, Symbol, NotFound);
apply(_, Args) ->
  CountBin = integer_to_binary(length(Args)),
  throw(<<"Wrong number of args for symbol, got: ", CountBin/binary>>).

%% clojerl.IStringable
%% @doc 将符号转换为字符串

str(#{?TYPE := ?M, ns := ?NIL, name := Name}) ->
  Name;
str(#{?TYPE := ?M, ns := Ns, name := Name}) ->
  <<Ns/binary, "/", Name/binary>>.

%% @doc 获取符号的名称部分
name(#{?TYPE := ?M, name := Name}) -> Name.

%% @doc 获取符号的命名空间部分
namespace(#{?TYPE := ?M, ns := Ns}) -> Ns.

%% @doc 获取符号的元数据
meta(#{?TYPE := ?M, meta := Meta}) -> Meta.

%% @doc 设置符号的元数据
with_meta(#{?TYPE := ?M} = Symbol, Metadata) ->
  Symbol#{meta => Metadata}.

%% @doc 判断两个符号是否相等
equiv( #{?TYPE := ?M, ns := Ns, name := Name}
     , #{?TYPE := ?M, ns := Ns, name := Name}
     ) ->
  true;
equiv(_, _) ->
  false.

%% @doc 计算符号的哈希值
hash(#{?TYPE := ?M, ns := Ns, name := Name}) ->
  erlang:phash2({Ns, Name}).
