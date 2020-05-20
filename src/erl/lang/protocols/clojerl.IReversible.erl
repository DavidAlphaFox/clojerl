-module('clojerl.IReversible').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-clojure(true).
-protocol(true).

-export(['rseq'/1]).
-export([?SATISFIES/1]).
-export([?EXTENDS/1]).

-callback 'rseq'(any()) -> any().
-optional_callbacks(['rseq'/1]).

'rseq'(Seq) ->
  case Seq of
    #{?TYPE := 'clojerl.Subvec'} ->
      'clojerl.Subvec':'rseq'(Seq);
    #{?TYPE := 'clojerl.Vector'} ->
      'clojerl.Vector':'rseq'(Seq);
    #{?TYPE := _} ->
      clj_protocol:not_implemented(?MODULE, 'rseq', Seq);
    X_ when erlang:is_binary(X_) ->
      clj_protocol:not_implemented(?MODULE, 'rseq', Seq);
    X_ when erlang:is_boolean(X_) ->
      clj_protocol:not_implemented(?MODULE, 'rseq', Seq);
    ?NIL ->
      clj_protocol:not_implemented(?MODULE, 'rseq', Seq);
    _ ->
      clj_protocol:not_implemented(?MODULE, 'rseq', Seq)
  end.

?SATISFIES(X) ->
  case X of
    #{?TYPE := 'clojerl.Subvec'} ->  true;
    #{?TYPE := 'clojerl.Vector'} ->  true;
    #{?TYPE := _} ->  false;
    X_ when erlang:is_binary(X_) ->  false;
    X_ when erlang:is_boolean(X_) ->  false;
    ?NIL ->  false;
    _ -> false
  end.

?EXTENDS(X) ->
  case X of
    'clojerl.Subvec' -> true;
    'clojerl.Vector' -> true;
    _ -> false
  end.
