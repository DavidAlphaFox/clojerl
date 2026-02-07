%% @doc Clojure Future（未来值）模块
%% @desc
%% - 功能：实现异步计算，在另一个进程中执行函数并获取结果
%% - 依赖：
%%   - gen_server - OTP 行为，每个 Future 有独立的 gen_server 进程
%%   - 'erlang.io.ICloseable' - 可关闭协议
%%   - 'clojerl.IBlockingDeref' - 阻塞解引用协议（支持超时）
%%   - 'clojerl.IDeref' - 解引用协议
%%   - 'clojerl.IEquiv' - 等值比较协议
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.IPending' - 待定协议（检查是否已完成）
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.Future').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behaviour(gen_server).

-behavior('erlang.io.ICloseable').
-behavior('clojerl.IBlockingDeref').
-behavior('clojerl.IDeref').
-behavior('clojerl.IEquiv').
-behavior('clojerl.IHash').
-behavior('clojerl.IPending').
-behavior('clojerl.IStringable').

-export([ ?CONSTRUCTOR/1
        , cancel/1
        , 'cancelled?'/1
        , 'done?'/1
        ]).

-export([close/1]).
-export([deref/3]).
-export([deref/1]).
-export(['realized?'/1]).
-export([equiv/2]).
-export([hash/1]).
-export([str/1]).

%% eval
-export([ eval/2
        ]).

%% gen_server callbacks
-export([ start_link/2
        , init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-export_type([type/0]).
-type type() :: #{ ?TYPE => ?M
                 , id    => binary()  %% 唯一标识符
                 , pid   => pid()     %% 管理 Future 的进程 PID
                 }.

%%------------------------------------------------------------------------------
%% 构造函数
%%------------------------------------------------------------------------------

%% @doc 创建 Future 对象（启动异步计算）
-spec ?CONSTRUCTOR(any()) -> type().
?CONSTRUCTOR(Fn) ->
  UUID      = 'erlang.util.UUID':random(),
  Id        = 'erlang.util.UUID':str(UUID),
  {ok, Pid} = start_link(Id, Fn),
  #{ ?TYPE => ?M
   , id    => Id
   , pid   => Pid
   }.

%% @doc 取消 Future
-spec cancel(type()) -> ok.
cancel(#{?TYPE := ?M, pid := Pid}) ->
  ok = gen_server:stop(Pid).

%% @doc 判断 Future 是否已取消
-spec 'cancelled?'(type()) -> boolean().
'cancelled?'(#{?TYPE := ?M, pid := Pid}) ->
  not erlang:is_process_alive(Pid).

%% @doc 判断 Future 是否已完成
-spec 'done?'(type()) -> boolean().
'done?'(#{?TYPE := ?M, pid := Pid}) ->
  erlang:is_process_alive(Pid) andalso gen_server:call(Pid, 'done?').

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.ICloseable
%% @doc 关闭 Future（停止计算进程）
close(#{?TYPE := ?M, pid := Pid}) ->
  ok = gen_server:stop(Pid).

%% clojerl.IBlockingDeref
%% @doc 阻塞解引用（支持超时）
deref(#{?TYPE := ?M, pid := Pid}, TimeoutMs, TimeoutVal) ->
  try do_deref(Pid, TimeoutMs)
  catch exit:{timeout, _} -> TimeoutVal
  end.

%% clojerl.IDeref
%% @doc 解引用 Future（等待计算完成）
deref(#{?TYPE := ?M, pid := Pid}) ->
  do_deref(Pid, infinity).

%% clojerl.IEquiv
%% @doc 判断两个 Future 是否相等
equiv( #{?TYPE := ?M, id := Id}
     , #{?TYPE := ?M, id := Id}
     ) ->
  true;
equiv(_, _) ->
  false.

%% clojerl.IHash
%% @doc 计算 Future 的哈希值
hash(#{?TYPE := ?M, id := Id}) ->
  erlang:phash2(Id).

%% clojerl.IPending
%% @doc 判断 Future 是否已完成
'realized?'(#{?TYPE := ?M} = Future) ->
  'done?'(Future).

%% clojerl.IStringable
%% @doc 将 Future 转换为字符串
str(#{?TYPE := ?M, id := Id}) ->
  <<"#<clojerl.Future ", Id/binary, ">">>.

%%------------------------------------------------------------------------------
%% gen_server 回调函数
%%------------------------------------------------------------------------------

-type state() :: #{ id      => binary()
                  , fn      => function()
                  , result  => ?NIL | {ok, any()}  %% 计算结果
                  , pending => queue:queue()        %% 等待结果的请求队列
                  }.

%% @doc 启动 Future 的 gen_server 进程
start_link(Id, Fn) ->
  gen_server:start_link(?MODULE, {Id, Fn}, []).

%% @doc 初始化 Future 状态并启动异步计算
-spec init({binary(), function()}) -> {ok, state()}.
init({Id, Fn}) ->
  State = #{ id      => Id
           , fn      => Fn
           , result   => ?NIL
           , pending => queue:new()
           },
  proc_lib:spawn_link(?MODULE, eval, [self(), Fn]),
  {ok, State}.

%% @doc 处理同步调用（解引用和状态查询）
handle_call(deref, From, #{result := ?NIL, pending := Pending} = State0) ->
  State1 = State0#{pending := queue:cons(From, Pending)},
  {noreply, State1};
handle_call(deref, _From, #{result := Result} = State) ->
  {reply, Result, State};
handle_call('done?', _From, #{result := Result} = State) ->
  {reply, Result =/= ?NIL, State}.

%% @doc 处理异步消息（计算完成通知）
handle_cast({result, Result}, #{pending := Pending} = State) ->
  [gen_server:reply(From, Result) || From <- queue:to_list(Pending)],
  {noreply, State#{result := Result, pending := queue:new()}}.

handle_info(_Msg, State) ->
  {noreply, State}.

terminate(_Msg, State) ->
  {ok, State}.

code_change(_Msg, _From, State) ->
  {ok, State}.

%%------------------------------------------------------------------------------
%% 辅助函数
%%------------------------------------------------------------------------------

%% @doc 在独立进程中执行函数
-spec eval(pid(), function()) -> ok.
eval(Pid, Fn) ->
  Result = try {ok, clj_rt:apply(Fn, [])}
           catch _:Error -> {error, Error}
           end,
  ok = gen_server:cast(Pid, {result, Result}).

%% @doc 解引用 Future（阻塞等待结果）
-spec do_deref(pid(), timeout()) -> any().
do_deref(Pid, Timeout) ->
  case gen_server:call(Pid, deref, Timeout) of
    {ok, Value} -> Value;
    {error, Error} -> ?ERROR(Error)
  end.
