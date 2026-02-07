%% @private
%% @doc Clojerl OTP监督者模块
%% @desc
%% 功能: 实现OTP supervisor行为，管理Clojerl应用的子进程
%%       监督和管理Namespace、Module、Cache、Agent、Atom、Delay等进程
%%       使用one_for_one重启策略
%% 依赖: 实现 supervisor 行为
-module(clojerl_sup).
-behavior(supervisor).

-export([start_link/0, init/1]).

-spec start_link() -> ignore | {error, term()} | {ok, pid()}.
start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec init(term()) ->
  {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}} | ignore.
init(_Args) ->
  SupFlags = #{strategy => one_for_one},
  Specs    = [ #{ id    => 'clojerl.Namespace'
                , start => {'clojerl.Namespace', start_link, []}
                }
             , #{ id    => clj_module
                , start => {clj_module, start_link, []}
                }
             , #{ id    => clj_cache
                , start => {clj_cache, start_link, []}
                }
             , #{ id    => 'clojerl.Agent.Server'
                , start => {'clojerl.Agent.Server', start_link, []}
                }
             , #{ id    => 'clojerl.Atom'
                , start => {'clojerl.Atom', start_link, []}
                }
             , #{ id    => 'clojerl.Delay'
                , start => {'clojerl.Delay', start_link, []}
                }
             ],
  {ok, {SupFlags, Specs}}.
