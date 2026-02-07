%% @doc Clojure 关键字模块
%% @desc
%% - 功能：实现 Clojure 关键字（keyword）类型，关键字是类似 :foo 的标识符
%% - 依赖：
%%   - 'clojerl.IFn' - 函数协议，关键字可作为函数从映射中查找值
%%   - 'clojerl.IHash' - 哈希协议
%%   - 'clojerl.INamed' - 命名协议
%%   - 'clojerl.IStringable' - 字符串转换协议
%%   - 'erlang.io.IWriter' - 写入协议
%%   - 'erlang.io.IReader' - 读取协议
-module('clojerl.Keyword').

-include("clojerl.hrl").
-include("clojerl_int.hrl").

-behavior('clojerl.IFn').
-behavior('clojerl.IHash').
-behavior('clojerl.INamed').
-behavior('clojerl.IStringable').
-behavior('erlang.io.IWriter').
-behavior('erlang.io.IReader').

-export([ ?CONSTRUCTOR/1
        , ?CONSTRUCTOR/2
        , find/1
        , find/2
        ]).

-export([apply/2]).
-export([hash/1]).
-export([ read/1
        , read/2
        , read_line/1
        , skip/2
        ]).
-export([ write/2
        , write/3
        ]).
-export([ name/1
        , namespace/1
        ]).
-export([str/1]).

-export_type([type/0]).
-type type() :: atom().

%%------------------------------------------------------------------------------
%% 构造函数和查找函数
%%------------------------------------------------------------------------------

%% @doc 从符号或二进制创建关键字
-spec ?CONSTRUCTOR('clojerl.Symbol':type() | binary()) -> type().
?CONSTRUCTOR(Name) when is_binary(Name) ->
  binary_to_atom(Name, utf8);
?CONSTRUCTOR(Name) when is_atom(Name) ->
  Name;
?CONSTRUCTOR(Symbol) ->
  binary_to_atom(clj_rt:str(Symbol), utf8).

%% @doc 从命名空间和名称创建关键字
-spec ?CONSTRUCTOR(binary(), binary()) -> type().
?CONSTRUCTOR(Namespace, Name)
  when is_binary(Namespace) andalso is_binary(Name) ->
  binary_to_atom(<<Namespace/binary, "/", Name/binary>>, utf8);
?CONSTRUCTOR(?NIL, Name) ->
  ?CONSTRUCTOR(Name).

%% @doc 查找已存在的简单关键字
-spec find(binary()) -> type().
find(Name) ->
  try
    binary_to_existing_atom(Name, utf8)
  catch
    _:_ -> ?NIL
  end.

%% @doc 查找已存在的带命名空间的关键字
-spec find(binary() | ?NIL, binary()) -> type().
find(?NIL, Name) ->
  find(Name);
find(Namespace, Name) ->
  try
    binary_to_existing_atom(<<Namespace/binary, "/", Name/binary>>, utf8)
  catch
    _:_ -> ?NIL
  end.

%%------------------------------------------------------------------------------
%% 协议实现
%%------------------------------------------------------------------------------

%% clojerl.IFn
%% @doc 关键字可作为函数，从映射中查找对应的值

apply(Keyword, [Map]) ->
  case 'clojerl.ILookup':?SATISFIES(Map) of
    true  -> 'clojerl.ILookup':get(Map, Keyword);
    false -> clj_rt:get(Map, Keyword)
  end;
apply(Keyword, [Map, NotFound]) ->
  case 'clojerl.ILookup':?SATISFIES(Map) of
    true  -> 'clojerl.ILookup':get(Map, Keyword, NotFound);
    false -> clj_rt:get(Map, Keyword, NotFound)
  end;
apply(_Keyword, Args) ->
  CountBin = integer_to_binary(length(Args)),
  ?ERROR(<<"Wrong number of args for keyword, got: ", CountBin/binary>>).

%% clojerl.IHash
%% @doc 计算关键字的哈希值

hash(Keyword) ->
  erlang:phash2(Keyword).

%% clojerl.INamed
%% @doc 获取关键字的名称部分（不含命名空间和前导冒号）

name(Keyword) ->
  KeywordBin = atom_to_binary(Keyword, utf8),
  case binary:split(KeywordBin, <<"/">>) of
    [_] -> KeywordBin;
    [_, Name] -> Name
  end.

%% @doc 获取关键字的命名空间部分
namespace(Keyword) ->
  KeywordBin = atom_to_binary(Keyword, utf8),
  case binary:split(KeywordBin, <<"/">>) of
    [_] -> ?NIL;
    [Namespace, _] -> Namespace
  end.

%% clojerl.IStringable
%% @doc 将关键字转换为字符串（带前导冒号）

str(Keyword) ->
  KeywordBin = atom_to_binary(Keyword, utf8),
  <<":", KeywordBin/binary>>.

%% erlang.io.IReader
%% @doc 从 IO 读取字符

read(IO) ->
  read(IO, 1).

read(IO, Length)
  when IO =:= standard_io; IO =:= standard_error ->
  io:get_chars(IO, "", Length);
read(Name, Length) ->
  case erlang:whereis(Name) of
    undefined ->
      error(<<"Invalid process name">>);
    _ ->
      io:get_chars(Name, "", Length)
  end.

%% @doc 从 IO 读取一行
read_line(IO)
  when IO =:= standard_io; IO =:= standard_error ->
  io:request(IO, {get_line, unicode, ""});
read_line(Name) ->
  case erlang:whereis(Name) of
    undefined ->
      error(<<"Invalid process name">>);
    _ ->
      io:request(Name, {get_line, unicode, ""})
  end.

%% @doc 跳过指定长度的字符（不支持）
skip(_IO, _Length) ->
  error(<<"unsupported operation: skip">>).

%% erlang.io.IWriter
%% @doc 向 IO 写入字符串

write(Name, Str) when is_atom(Name), is_binary(Str) ->
  io:put_chars(Name, Str).

%% @doc 格式化写入
write(IO, Format, Values)
  when IO =:= standard_io; IO =:= standard_error ->
  ok = io:fwrite(IO, Format, clj_rt:to_list(Values)),
  IO;
write(Name, Str, Values) when is_atom(Name) ->
  case erlang:whereis(Name) of
    undefined ->
      error(<<"Invalid process name">>);
    _ ->
      io:fwrite(Name, Str, clj_rt:to_list(Values))
  end.
