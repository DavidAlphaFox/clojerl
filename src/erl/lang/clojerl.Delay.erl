%% @doc Clojure 延迟计算模块
%% @desc
%% - 功能：实现延迟计算（delay），函数只在首次访问时执行一次
%% - 依赖：
%%   - gen_server - OTP 行为，用于管理延迟计算状态
%%   - 'erlang.io.ICloseable' - 可关闭协议
%%   - 'clojerl.IDeref' - 解引用协议
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IPending' - 待定协议（检查是否已计算）
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Delay').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behaviour(gen_server).

-behavior('erlang.io.ICloseable').
-behavior('clojerl.IDeref').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IHash').
-behavior('clojerl.IPending').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , force/1
        ]).

-export([close/1]).
-export([deref/1]).
-export(['realized?'/1]).
-export([equiv/2]).
-export([hash/1]).
-export([str/1]).

%% gen_server callbacks
-export([ start_link/0
        , init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , id    => binary()      %% 唯一标识符
                 , fn    => function()    %% 要延迟执行的函数
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 创建延迟计算对象
-spec ?CONSTRUCTOR(any()) -> type().
?CONSTRUCTOR(Fn) ->
  UUID = 'erlang.util.UUID':random(),
  Id   = 'erlang.util.UUID':str(UUID),
  #{ ?TYPE => ?M
   , id    => Id
   , fn    => Fn
   }.

%% @doc 强制计算并返回值
-spec force(type()) -> any().
force(#{?TYPE := ?M} = X) -> deref(X);
force(X) -> X.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.ICloseable
%% @doc 关闭延迟计算对象，清除缓存
close(#{?TYPE := ?M, id := Id}) ->
  true = ets:delete(?MODULE, Id),
  ok.

%% clojerl.IDeref
%% @doc 解引用延迟计算对象（首次调用时执行函数）
deref(#{?TYPE := ?M, id := Id, fn := Fn}) ->
  Result = case clj_utils:ets_get(?MODULE, Id) of
             ?NIL -> gen_server:call(?MODULE, {deref, Id, Fn}, infinity);
             {Id, R} -> R
           end,
  case Result of
    {ok, Value} -> Value;
    {error, Error} -> ?ERROR(Error)
  end.

%% clojerl.IEquiv
%% @doc 判断两个延迟计算对象是否相等
equiv( #{?TYPE := ?M, id := Id}
     , #{?TYPE := ?M, id := Id}
     ) ->
  true;
equiv(_, _) ->
  false.

%% clojerl.IHash
%% @doc 计算延迟计算对象的哈希值
hash(#{?TYPE := ?M, id := Id}) ->
  erlang:phash2(Id).

%% clojerl.IPending
%% @doc 判断延迟计算是否已完成
'realized?'(#{?TYPE := ?M, id := Id}) ->
  clj_utils:ets_get(?MODULE, Id) =/= ?NIL.

%% clojerl.IStringable
%% @doc 将延迟计算对象转换为字符串
str(#{?TYPE := ?M, id := Id}) ->
  <<"#<clojerl.Delay ", Id/binary, ">">>.

%%------------------------------------------------------------------------------
%% gen_server 回调函数
%%------------------------------------------------------------------------------

%% @doc 启动延迟计算服务器
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc 初始化服务器（创建 ETS 表缓存计算结果）
init([]) ->
  ets:new(?MODULE, [named_table, set, public, {keypos, 1}]),
  {ok, ?NIL}.

%% @doc 处理同步调用（解引用请求）
handle_call({deref, Id, Fn}, _From, State) ->
  {Id, Reply} = case clj_utils:ets_get(?MODULE, Id) of
                  ?NIL -> clj_utils:ets_save(?MODULE, {Id, eval(Fn)});
                  Value -> Value
                end,
  {reply, Reply, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info(_Msg, State) ->
  {noreply, State}.

terminate(_Msg, State) ->
  {ok, State}.

code_change(_Msg, _From, State) ->
  {ok, State}.

%%------------------------------------------------------------------------------
%% 辅助函数
%%------------------------------------------------------------------------------

%% @doc 执行函数并捕获错误
eval(Fn) ->
  try {ok, clj_rt:apply(Fn, [])}
  catch _:Error -> {error, Error}
  end.
