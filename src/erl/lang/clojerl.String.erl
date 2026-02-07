%% @doc Clojure 字符串模块
%% @desc
%% - 功能：为 Erlang 二进制（作为字符串）提供 Clojure 字符串操作和协议实现
%% - 依赖：
%%   - 'clojerl.ICounted' - 计数协议（获取字符串长度）
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.ISeqable' - 可序列化协议（字符串可作为字符序列）
%%   - 'clojerl.IStringable' - 字符串转换协议
-module('clojerl.String').

-compile({no_auto_import, [length/1]}).

-include("clojerl.hrl").

-behavior('clojerl.ICounted').
-behavior('clojerl.IHash').
-behavior('clojerl.ISeqable').
-behavior('clojerl.IStringable').

-export([ substring/2
        , substring/3
        , starts_with/2
        , ends_with/2
        , contains/2
        , append/2
        , index_of/2
        , index_of/3
        , last_index_of/2
        , last_index_of/3
        , join/2
        , char_at/2
        , to_upper/1
        , to_lower/1
        , is_whitespace/1
        , is_printable/1
        , length/1
        , split/2
        , split/3
        , replace/3
        ]).

-export([count/1]).
-export([hash/1]).
-export([ seq/1
        , to_list/1
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: binary().

%%------------------------------------------------------------------------------
%% 字符串操作函数
%%------------------------------------------------------------------------------

%% @doc 获取子串（从指定位置到末尾）
-spec substring(binary(), integer()) -> binary().
substring(Str, Start) when is_binary(Str), Start >= 0 ->
  do_substring(Str, Start, count(Str), 0, []).

%% @doc 获取子串（从 Start 到 End）
-spec substring(binary(), integer(), integer()) -> binary().
substring(Str, Start, End) when is_binary(Str), Start =< End, Start >= 0 ->
  do_substring(Str, Start, End, 0, []).

%% @doc 子串辅助函数（递归实现）
-spec do_substring(binary(), integer(), integer(), integer(), iodata()) ->
  binary().
do_substring(_Str, _Start, End, End, Acc) ->
  iolist_to_binary(Acc);
do_substring(<<>>, _Start, _End, _Index, Acc) ->
  iolist_to_binary(Acc);
do_substring(<<Ch/utf8, Str/binary>>, Start, End, Index, Acc)
  when Index >= Start ->
  do_substring(Str, Start, End, Index + 1, [Acc, Ch]);
do_substring(<<_/utf8, Str/binary>>, Start, End, Index, Acc) ->
  do_substring(Str, Start, End, Index + 1, Acc).

%% @doc 判断字符串是否以指定前缀开头
-spec starts_with(binary(), binary()) -> boolean().
starts_with(Str, Prefix) ->
  Size = size(Prefix),
  case Str of
    <<Prefix:Size/binary, _/binary>> -> true;
    _ -> false
  end.

%% @doc 判断字符串是否以指定后缀结尾
-spec ends_with(binary(), binary()) -> boolean().
ends_with(Str, Ends) when size(Ends) > size(Str)->
  false;
ends_with(Str, Ends) ->
  StrSize = byte_size(Str),
  EndsSize = byte_size(Ends),
  Ends == binary:part(Str, {StrSize, - EndsSize}).

%% @doc 判断字符串是否包含指定模式
-spec contains(binary(), binary()) -> boolean().
contains(Subject, Pattern) ->
  [] =/= binary:matches(Subject, Pattern).

%% @doc 追加字符串
-spec append(binary(), binary()) -> binary().
append(X, Y) when is_binary(X), is_binary(Y) ->
  <<X/binary, Y/binary>>.

%% @doc 查找子串首次出现的位置
-spec index_of(binary(), binary()) -> integer().
index_of(Str, Value) ->
  index_of(Str, Value, 0).

%% @doc 从指定位置开始查找子串首次出现的位置
-spec index_of(binary(), binary(), integer()) -> integer().
index_of(<<>>, _Value, _FromIndex) ->
  -1;
index_of(Str, Value, FromIndex) ->
  do_index_of(Str, Value, erlang:size(Value), 0, FromIndex).

%% @doc 查找子串位置的辅助函数
-spec do_index_of(binary(), binary(), integer(), integer(), integer()) ->
  integer().
do_index_of(<<>>, _, _, _, _) ->
  -1;
do_index_of(<<_/utf8, Rest/binary>>, Value, Length, Index, FromIndex)
  when Index < FromIndex ->
  do_index_of(Rest, Value, Length, Index + 1, FromIndex);
do_index_of(Str, Value, Length, Index, FromIndex) ->
  case Str of
    <<Value:Length/binary, _/binary>> ->
      Index;
    <<_/utf8, Rest/binary>> ->
      do_index_of(Rest, Value, Length, Index + 1, FromIndex)
  end.

%% @doc 查找子串最后出现的位置
-spec last_index_of(binary(), binary()) -> integer().
last_index_of(Str, Value) ->
  last_index_of(Str, Value, 0).

%% @doc 从指定位置开始查找子串最后出现的位置
-spec last_index_of(binary(), binary(), integer()) -> integer().
last_index_of(<<>>, _Value, _FromIndex) ->
  -1;
last_index_of(Str, Value, FromIndex) ->
  Length = count(Str) - FromIndex,
  case binary:matches(Str, Value, [{scope, {FromIndex, Length}}]) of
    [] -> -1;
    Matches ->
      {Index, _} = lists:last(Matches),
      Index
  end.

%% @doc 将字符串列表用分隔符连接
-spec join([any()], binary()) -> binary().
join([], _) ->
  <<>>;
join([S], _) ->
  clj_rt:str(S);
join([H | T], Sep) ->
  B = << <<Sep/binary, (clj_rt:str(X))/binary>> || X <- T >>,
  HStr = clj_rt:str(H),
  <<HStr/binary, B/binary>>.

%% @doc 获取指定位置的字符
-spec char_at(binary(), non_neg_integer()) -> binary().
char_at(<<Ch/utf8, _/binary>>, 0) ->
  <<Ch/utf8>>;
char_at(<<_/utf8, Str/binary>>, Index) when Index >= 0->
  char_at(Str, Index - 1).

%% @doc 转换为大写
-spec to_upper(binary()) -> binary().
to_upper(Str) when is_binary(Str) ->
  List = unicode:characters_to_list(Str),
  unicode:characters_to_binary(string:to_upper(List)).

%% @doc 转换为小写
-spec to_lower(binary()) -> binary().
to_lower(Str) when is_binary(Str) ->
  List = unicode:characters_to_list(Str),
  unicode:characters_to_binary(string:to_lower(List)).

%% @doc 判断是否是空白字符
-spec is_whitespace(binary()) -> boolean().
is_whitespace(Str) ->
  Regex = <<"[\\s\\t\\x0B\\x1C\\x1D\\x1E\\x1F\\x{2000}\\x{2002}]">>,
  match =:= re:run(Str, Regex, [{capture, none}, unicode]).

%% @doc 判断是否是可打印字符
-spec is_printable(binary()) -> boolean().
is_printable(Str) ->
  io_lib:printable_list(unicode:characters_to_list(Str)).

%% @doc 获取字符串长度（Unicode 字符数）
-spec length(binary()) -> non_neg_integer().
length(Str) ->
  case unicode:characters_to_list(Str) of
    {error, _, _} -> error(<<"Invalid unicode binary string">>);
    List -> erlang:length(List)
  end.

%% @doc 分割字符串
-spec split(binary(), binary()) -> [binary()].
split(Str, Pattern) ->
  split(Str, Pattern, [{return, binary}]).

%% @doc 分割字符串（带选项）
-spec split(binary(), binary(), [any()]) -> [binary()].
split(Str, Pattern, Options) ->
  re:split(Str, Pattern, Options).

%% @doc 替换字符串中的所有匹配项
-spec replace(binary(), binary(), binary()) -> binary().
replace(Str, Target, Replacement) ->
  binary:replace(Str, Target, Replacement, [global]).

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.ICounted
%% @doc 获取字符串长度（Unicode 字符数）
count(Str) ->
  length(Str).

%% clojerl.IHash
%% @doc 计算字符串的哈希值
hash(Str) ->
  erlang:phash2(Str).

%% clojerl.ISeqable
%% @doc 获取字符串的序列形式（字符序列）
seq(<<>>) -> ?NIL;
seq(Str)  -> 'clojerl.StringSeq':?CONSTRUCTOR(Str).

%% @doc 将字符串转换为列表
to_list(Str)  -> to_seq(Str, []).

%% clojerl.IStringable
%% @doc 将字符串转换为字符串（自身）
str(Str) -> Str.

%%------------------------------------------------------------------------------
%% 辅助函数
%%------------------------------------------------------------------------------

%% @doc 将字符串转换为字符序列列表
to_seq(<<>>, Result) ->
  lists:reverse(Result);
to_seq(<<Ch/utf8, Rest/binary>>, Result) ->
  to_seq(Rest, [<<Ch/utf8>> | Result]).
