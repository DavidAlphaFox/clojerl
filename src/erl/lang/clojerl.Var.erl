%% @doc Clojure Var（变量）模块
%% @desc
%% - 功能：实现 Clojure 的 Var 类型，Var 是命名空间中可变的变量容器
%% - 依赖：
%%   - 'clojerl.IDeref' - 解引用协议，获取 Var 的值
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IFn' - 函数协议，Var 可作为函数调用
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IMeta' - 元数据协议
%%   - 'clojerl.INamed' - 命名协议
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Var').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.IDeref').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IFn').
-behavior('clojerl.IHash').
-behavior('clojerl.IMeta').
-behavior('clojerl.INamed').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/2
        , create/0
        , is_dynamic/1
        , is_macro/1
        , is_public/1
        , is_bound/1
        , has_root/1
        , get/1
        ]).

-export([ function/1
        , module/1
        , val_function/1
        , process_args/2
        , is_valid_arity/2
        , fake_fun/2
        ]).

-export([ push_bindings/1
        , pop_bindings/0
        , get_bindings/0
        , get_bindings_map/0
        , reset_bindings/1
        , dynamic_binding/1
        , dynamic_binding/2
        , find/1
        ]).

-export([deref/1]).
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
-type type() :: #{ ?TYPE     => ?M
                 , ns        => binary()
                 , name      => binary()
                 , ns_atom   => atom()
                 , name_atom => atom()
                 , val_atom  => atom()
                 , meta      => ?NIL | any()
                 , fake_fun  => boolean()
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 从命名空间和名称创建 Var
-spec ?CONSTRUCTOR(binary(), binary()) -> type().
?CONSTRUCTOR(Ns, Name) ->
  #{ ?TYPE     => ?M
   , ns        => Ns
   , name      => Name
   , ns_atom   => binary_to_atom(Ns, utf8)
   , name_atom => binary_to_atom(Name, utf8)
   , val_atom  => binary_to_atom(<<Name/binary, "__val">>, utf8)
   , meta      => ?NIL
   , fake_fun  => false
   }.

%% @doc 创建匿名 Var（使用 UUID 生成名称）
-spec create() -> type().
create() ->
  Ns   = 'erlang.util.UUID':random(),
  Name = 'erlang.util.UUID':random(),
  ?CONSTRUCTOR(clj_rt:str(Ns), clj_rt:str(Name)).

%%------------------------------------------------------------------------------
%% Var 属性查询函数
%%------------------------------------------------------------------------------

%% @doc 判断 Var 是否是动态变量
-spec is_dynamic(type()) -> boolean().
is_dynamic(#{?TYPE := ?M, meta := Meta}) when is_map(Meta) ->
  clj_rt:get(Meta, dynamic, false);
is_dynamic(#{?TYPE := ?M}) ->
  false.

%% @doc 判断 Var 是否是宏
-spec is_macro(type()) -> boolean().
is_macro(#{?TYPE := ?M, meta := Meta}) when is_map(Meta) ->
  clj_rt:get(Meta, macro, false);
is_macro(#{?TYPE := ?M}) ->
  false.

%% @doc 判断 Var 是否是公共的
-spec is_public(type()) -> boolean().
is_public(#{?TYPE := ?M, meta := Meta}) when is_map(Meta) ->
  not clj_rt:get(Meta, private, false);
is_public(#{?TYPE := ?M}) ->
  true.

%% @doc 判断 Var 是否已绑定
-spec is_bound(type()) -> boolean().
is_bound(#{?TYPE := ?M} = Var) ->
  has_root(Var)
  orelse ( is_dynamic(Var)
           andalso clj_scope:contains(str(Var), get_bindings())
         ).

%% @doc 判断 Var 是否有根值
-spec has_root(type()) -> boolean().
has_root(#{?TYPE := ?M} = Var) ->
  deref(Var) =/= ?UNBOUND.

%% @doc 获取 Var 的值
-spec get(type()) -> boolean().
get(Var) -> deref(Var).

%% @doc 获取 Var 对应的 Erlang 模块
-spec module(type()) -> atom().
module(#{?TYPE := ?M, ns_atom := NsAtom}) ->
  NsAtom.

%% @doc 获取 Var 对应的函数名
-spec function(type()) -> atom().
function(#{?TYPE := ?M, name_atom := NameAtom}) ->
  NameAtom.

%% @doc 获取 Var 值函数的函数名
-spec val_function(type()) -> atom().
val_function(#{?TYPE := ?M, val_atom := ValAtom}) ->
  ValAtom.

%% @doc 设置是否使用假函数
-spec fake_fun(type(), boolean()) -> type().
fake_fun(#{?TYPE := ?M} = Var, IsFakeFun) ->
  Var#{fake_fun => IsFakeFun}.

%%------------------------------------------------------------------------------
%% 动态绑定管理
%%------------------------------------------------------------------------------

%% @doc 推入新的动态绑定层级
-spec push_bindings('clojerl.IMap':type()) -> ok.
push_bindings(BindingsMap) ->
  Bindings      = get_bindings(),
  NewBindings   = clj_scope:new(Bindings),
  AddBindingFun = fun(K, Acc) ->
                      clj_scope:put( clj_rt:str(K)
                                   , {ok, clj_rt:get(BindingsMap, K)}
                                   , Acc
                                   )
                  end,
  NewBindings1  = lists:foldl( AddBindingFun
                             , NewBindings
                             , clj_rt:to_list(clj_rt:keys(BindingsMap))
                             ),
  erlang:put(dynamic_bindings, NewBindings1),
  ok.

%% @doc 弹出当前动态绑定层级
-spec pop_bindings() -> ok.
pop_bindings() ->
  Bindings = get_bindings(),
  Parent   = clj_scope:parent(Bindings),
  erlang:put(dynamic_bindings, Parent),
  ok.

%% @doc 获取当前动态绑定
-spec get_bindings() -> clj_scope:scope() | ?NIL.
get_bindings() ->
  case erlang:get(dynamic_bindings) of
    undefined -> ?NIL;
    Bindings  -> Bindings
  end.

%% @doc 获取动态绑定的映射形式
-spec get_bindings_map() -> map().
get_bindings_map() ->
  case get_bindings() of
    ?NIL      -> #{};
    Bindings  ->
      UnwrapFun = fun(_, {ok, X}) -> X end,
      clj_scope:to_map(UnwrapFun, Bindings)
  end.

%% @doc 重置动态绑定到指定状态
-spec reset_bindings(clj_scope:scope()) -> ok.
reset_bindings(Bindings) ->
  erlang:put(dynamic_bindings, Bindings).

%% @doc 获取动态绑定的值
-spec dynamic_binding('clojerl.Var':type() | binary()) -> {ok, any()} | ?NIL.
dynamic_binding(Key) when is_binary(Key) ->
  clj_scope:get(Key, get_bindings());
dynamic_binding(Var) ->
  dynamic_binding(str(Var)).

%% @doc 设置动态绑定的值
-spec dynamic_binding('clojerl.Var':type() | binary(), any()) -> {ok, any()} | ?NIL.
dynamic_binding(Key, Value) when is_binary(Key) ->
  case get_bindings() of
    ?NIL -> push_bindings(#{});
    X -> X
  end,
  Bindings0 = get_bindings(),
  Bindings1 = case clj_scope:update(Key, {ok, Value}, Bindings0) of
                  not_found -> clj_scope:put(Key, {ok, Value}, Bindings0);
                  Bindings  -> Bindings
                end,
  erlang:put(dynamic_bindings, Bindings1),
  Value;
dynamic_binding(Var, Value) ->
  dynamic_binding(str(Var), Value).

%% @doc 从限定符号查找 Var
-spec find('clojerl.Symbol':type()) -> type() | ?NIL.
find(QualifiedSymbol) ->
  NsName = clj_rt:namespace(QualifiedSymbol),
  ?ERROR_WHEN( NsName =:= ?NIL
             , <<"Symbol must be namespace-qualified">>
             ),

  Ns = 'clojerl.Namespace':find(clj_rt:symbol(NsName)),
  ?ERROR_WHEN( Ns =:= ?NIL
             , [<<"No such namespace: ">>, NsName]
             ),

  'clojerl.Namespace':find_var(Ns, QualifiedSymbol).

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.INamed
%% @doc 获取 Var 的名称
name(#{?TYPE := ?M, name := Name}) ->
  Name.

%% @doc 获取 Var 的命名空间
namespace(#{?TYPE := ?M, ns := Ns}) ->
  Ns.

%% clojerl.IStringable
%% @doc 将 Var 转换为字符串
str(#{?TYPE := ?M, ns := Ns, name := Name}) ->
  <<"#'", Ns/binary, "/", Name/binary>>.

%% clojerl.IDeref
%% @doc 解引用 Var，获取其值
deref(#{ ?TYPE    := ?M
       , ns       := Ns
       , name     := Name
       , ns_atom  := Module
       , val_atom := FunctionVal
       , fake_fun := FakeFun
       } = Var) ->
  try
    %% Make the call in case the module is not loaded and handle the case
    %% when it doesn't even exist gracefully.
    apply_fun(FakeFun, Module, FunctionVal, 0, [])
  catch
    ?WITH_STACKTRACE(Type, undef, Stacktrace)
      case erlang:function_exported(Module, FunctionVal, 0) of
        false ->
          case deref_dynamic(Var) of
            {ok, Value} -> Value;
            ?NIL        -> ?ERROR(<<"Could not dereference ",
                                    Ns/binary, "/", Name/binary, ". "
                                    "There is no Erlang function "
                                    "to back it up.">>)
          end;
        true  ->
          erlang:raise(Type, undef, Stacktrace)
      end
  end.

%% @doc 解引用动态 Var
-spec deref_dynamic(type()) -> ?NIL | {ok, any()}.
deref_dynamic(Var) ->
  case is_dynamic(Var) of
    true -> dynamic_binding(Var);
    false -> ?NIL
  end.

%% clojerl.IEquiv
%% @doc 判断两个 Var 是否相等
equiv( #{?TYPE := ?M, ns := Ns, name := Name}
     , #{?TYPE := ?M, ns := Ns, name := Name}
     ) ->
  true;
equiv(_, _) ->
  false.

%% clojerl.IHash
%% @doc 计算 Var 的哈希值
hash(#{?TYPE := ?M, ns := Ns, name := Name}) ->
  erlang:phash2({Ns, Name}).

%% clojerl.IMeta
%% @doc 获取 Var 的元数据
meta(#{?TYPE := ?M, meta := Meta}) -> Meta.

%% @doc 设置 Var 的元数据
with_meta(#{?TYPE := ?M} = Var, Metadata) ->
  Var#{meta => Metadata}.

%% clojerl.IFn
%% @doc 将 Var 作为函数调用
apply( #{ ?TYPE     := ?M
        , ns_atom   := Module
        , name_atom := Function
        , fake_fun  := FakeFun
        , meta      := Meta
        }
     , Args0
     ) ->
  {Arity, Args1} = case process_args(Meta, Args0) of
                     {Arity_, Args_, Rest_} ->
                       {Arity_, Args_ ++ [Rest_]};
                     X -> X
                   end,

  apply_fun(FakeFun, Module, Function, Arity, Args1).

%%------------------------------------------------------------------------------
%% 参数处理函数
%%------------------------------------------------------------------------------

%% @doc 验证元数是否有效
-spec is_valid_arity(Meta :: map(), Arity :: arity()) -> boolean().
is_valid_arity(#{'variadic?' := true} = Meta, Arity) ->
  #{ max_fixed_arity := MaxFixedArity
   , fixed_arities   := FixedArities
   } = Meta,
  MaxFixedArity =:= ?NIL
    orelse MaxFixedArity =< Arity
    orelse lists:member(Arity, FixedArities);
is_valid_arity(#{fixed_arities := FixedArities}, Arity) ->
  lists:member(Arity, FixedArities).

%% @doc 处理函数参数（支持变参函数）
-spec process_args(map(), [any()]) ->
  {arity(), [any()]} | {arity(), [any()], any()}.
process_args(#{'variadic?' := true} = Meta, Args) ->
  #{ max_fixed_arity := MaxFixedArity
   , variadic_arity  := VariadicArity
   } = Meta,
  {Length, Args1, Rest} = bounded_length(Args, VariadicArity),
  if
    MaxFixedArity =/= ?NIL
    andalso Rest =:= ?NIL
    andalso (MaxFixedArity >= Length orelse Length < VariadicArity) ->
      {Length, Args1};
    true ->
      {Length + 1, Args1, Rest}
  end;
process_args(_, Args) when is_list(Args) ->
  {length(Args), Args};
process_args(_, Args) ->
  Args1 = clj_rt:to_list(Args),
  {length(Args1), Args1}.

%% @doc 计算有界长度（用于变参函数）
-spec bounded_length(any(), non_neg_integer()) ->
  {non_neg_integer(), list(), any()}.
bounded_length(Args, Max) when is_list(Args) ->
  Length = length(Args),
  case Length =< Max of
    true  -> {Length, Args, ?NIL};
    false ->
      {Args1, Rest} = lists:split(Max, Args),
      {Max, Args1, Rest}
  end;
bounded_length(?NIL, Max) ->
  bounded_length(?NIL, 0, Max, []);
bounded_length(Args, Max) ->
  TypeModule = clj_rt:type_module(Args),
  bounded_length(TypeModule:seq(Args), 0, Max, []).

%% @doc 有界长度递归辅助函数
-spec bounded_length(any(), non_neg_integer(), non_neg_integer(), list()) ->
  {non_neg_integer(), list(), any()}.
bounded_length(?NIL, N, _Max, Acc) ->
  {N, lists:reverse(Acc), ?NIL};
bounded_length(Rest, N, _Max = N, Acc) ->
  {N, lists:reverse(Acc), Rest};
bounded_length(Rest, N, Max, Acc) ->
  TypeModule = clj_rt:type_module(Rest),
  First = TypeModule:first(Rest),
  Rest1 = TypeModule:next(Rest),
  bounded_length(Rest1, N + 1, Max, [First | Acc]).

%%------------------------------------------------------------------------------
%% 辅助函数
%%------------------------------------------------------------------------------

%% @doc 应用函数（支持假函数）
-spec apply_fun(type(), module(), atom(), arity(), [any()]) -> any().
apply_fun(false, Module, Function, _Arity, Args) ->
  erlang:apply(Module, Function, Args);
apply_fun(_, Module, Function, Arity, Args) ->
  Fun = clj_module:fake_fun(Module, Function, Arity),
  erlang:apply(Fun, Args).
