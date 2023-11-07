%%% Code generate by scripts/generate-protocols
-module('clojerl.IReference').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-clojure(true).
-protocol(true).

-export(['alter_meta'/3, 'reset_meta'/2]).
-export([?SATISFIES/1]).
-export([?EXTENDS/1]).

-callback 'alter_meta'(any(), any(), any()) -> any().
-callback 'reset_meta'(any(), any()) -> any().
-optional_callbacks(['alter_meta'/3, 'reset_meta'/2]).

-export_type([type/0]).
-type type() :: #{_ => _}.

'alter_meta'(Ref, Fun, Args) ->
  case Ref of
    #{?TYPE := 'clojerl.Agent'} ->
      'clojerl.Agent':'alter_meta'(Ref, Fun, Args);
    #{?TYPE := 'clojerl.Namespace'} ->
      'clojerl.Namespace':'alter_meta'(Ref, Fun, Args);
    #{?TYPE := _} ->
      clj_protocol:not_implemented(?MODULE, 'alter_meta', Ref);
    X_ when erlang:is_binary(X_) ->
      clj_protocol:not_implemented(?MODULE, 'alter_meta', Ref);
    X_ when erlang:is_boolean(X_) ->
      clj_protocol:not_implemented(?MODULE, 'alter_meta', Ref);
    ?NIL ->
      clj_protocol:not_implemented(?MODULE, 'alter_meta', Ref);
    _ ->
      clj_protocol:not_implemented(?MODULE, 'alter_meta', Ref)
  end.

'reset_meta'(Ref, Meta) ->
  case Ref of
    #{?TYPE := 'clojerl.Agent'} ->
      'clojerl.Agent':'reset_meta'(Ref, Meta);
    #{?TYPE := 'clojerl.Namespace'} ->
      'clojerl.Namespace':'reset_meta'(Ref, Meta);
    #{?TYPE := _} ->
      clj_protocol:not_implemented(?MODULE, 'reset_meta', Ref);
    X_ when erlang:is_binary(X_) ->
      clj_protocol:not_implemented(?MODULE, 'reset_meta', Ref);
    X_ when erlang:is_boolean(X_) ->
      clj_protocol:not_implemented(?MODULE, 'reset_meta', Ref);
    ?NIL ->
      clj_protocol:not_implemented(?MODULE, 'reset_meta', Ref);
    _ ->
      clj_protocol:not_implemented(?MODULE, 'reset_meta', Ref)
  end.

?SATISFIES(X) ->
  case X of
    #{?TYPE := 'clojerl.Agent'} ->  true;
    #{?TYPE := 'clojerl.Namespace'} ->  true;
    #{?TYPE := _} ->  false;
    X_ when erlang:is_binary(X_) ->  false;
    X_ when erlang:is_boolean(X_) ->  false;
    ?NIL ->  false;
    _ -> false
  end.

?EXTENDS(X) ->
  case X of
    'clojerl.Agent' -> true;
    'clojerl.Namespace' -> true;
    _ -> false
  end.
