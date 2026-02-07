%% @doc Clojerl 表达式抽象语法树类型定义
%% @desc
%% - 功能：定义 Clojerl 编译器的抽象语法树（AST）表达式类型
%% - 用途：用于表示 Clojure 代码的中间表示形式，贯穿词法分析、语法分析和代码生成阶段
%% - 表达式统一结构：所有表达式都包含 op（操作类型）、env（环境）、form（原始形式）、tag（类型标签）
-ifndef(CLOJERL_EXPR).

-define(CLOJERL_EXPR, true).

-include("clojerl.hrl").
-include("clojerl_int.hrl").

%% 循环类型：标识不同的循环上下文
%% - fn: 在函数定义中
%% - fn_method: 在函数方法中
%% - var: 在 var 绑定中
%% - loop: 在 loop 循环中
-type loop_type()      :: fn | fn_method | var | loop.

%% 循环标识符：用于关联 loop 和 recur 表达式
-type loop_id()        :: 'clojerl.Symbol':type().

%% 常量表达式：表示字面量常量（数字、字符串、nil、布尔值等）
-type constant_expr()  :: #{ op   => constant
                           , env  => clj_env:env()
                           , form => any()
                           , tag  => expr()
                           }.

%% 引用表达式：表示 (quote x) 或 'x 形式，返回表达式本身而不求值
-type quote_expr()     :: #{ op   => quote
                           , env  => clj_env:env()
                           , expr => any()
                           , form => any()
                           , tag  => expr()
                           }.

%% 局部变量表达式：表示局部变量引用
%% - name: 变量符号
%% - shadow: 是否遮蔽外层作用域
%% - underscore: 是否为下划线变量（忽略绑定）
%% - id: 变量的唯一标识符
%% - binding: 是否为绑定位置
-type local_expr()     :: #{ op         => local
                           , env        => clj_env:env()
                           , form       => any()
                           , tag        => expr()
                           , name       => 'clojerl.Symbol':type()
                           , shadow     => any()
                           , underscore => boolean()
                           , id         => integer()
                           , binding    => boolean()
                           }.

%% 绑定表达式：表示函数参数或 let/loop 绑定
%% - pattern: 绑定模式（用于解构绑定）
%% - variadic?: 是否为变参绑定
%% - arg_id: 参数位置索引
%% - local: 绑定类型（arg/loop/let）
-type binding_expr()   :: #{ op          => binding
                           , env         => clj_env:env()
                           , form        => any()
                           , tag         => expr()
                           , pattern     => expr()
                           , 'variadic?' => boolean()
                           , arg_id      => integer()
                           , local       => arg | loop | 'let'
                           }.

%% 函数表达式：表示 (fn [...] ...) 函数定义
%% - variadic?: 是否为变参函数
%% - fixed_arities: 所有固定参数数量的方法列表
%% - min/max_fixed_arity: 最小/最大固定参数数量
%% - variadic_arity: 变参方法的参数数量
%% - erlang-fn?: 是否为包装的 Erlang 函数
%% - methods: 所有方法表达式列表
%% - once: 是否为单次调用函数
%% - local: 函数本身的局部变量
-type fn_expr()        :: #{ op              => fn
                           , env             => clj_env:env()
                           , form            => any()
                           , tag             => expr()
                           , 'variadic?'     => boolean()
                           , fixed_arities   => [arity()]
                           , min_fixed_arity => ?NIL | integer()
                           , max_fixed_arity => ?NIL | integer()
                           , variadic_arity  => ?NIL | integer()
                           , 'erlang-fn?'    => boolean()
                           , methods         => [expr()]
                           , once            => boolean()
                           , local           => local_expr()
                           }.

%% 函数方法表达式：表示函数的某个方法（多重方法之一）
%% - loop_id: 关联的循环标识符（用于 recur）
%% - loop_type: 循环类型
%% - variadic?: 是否为变参方法
%% - params: 参数绑定列表
%% - guard: 守卫条件表达式
%% - fixed_arity: 固定参数数量
%% - body: 方法体表达式
-type fn_method_expr() :: #{ op          => fn_method
                           , env         => clj_env:env()
                           , form        => any()
                           , tag         => expr()
                           %% , name        => 'clojerl.Symbol':type()
                           , loop_id     => loop_id()
                           , loop_type   => loop_type()
                           , 'variadic?' => boolean()
                           , params      => [expr()]
                           , guard       => expr()
                           , fixed_arity => integer()
                           , body        => expr()
                           }.

%% Do 表达式：表示 (do ...), 顺序执行多个语句并返回最后一个值
%% - statements: 语句表达式列表
%% - ret: 返回值表达式
-type do_expr()        :: #{ op         => do
                           , env        => clj_env:env()
                           , form       => any()
                           , tag        => expr()
                           , statements => [expr()]
                           , ret        => expr()
                           }.

%% If 表达式：表示 (if test then else) 条件分支
%% - test: 测试条件表达式
%% - then: 条件为真时的表达式
%% - else: 条件为假时的表达式
-type if_expr()        :: #{ op   => 'if'
                           , env  => clj_env:env()
                           , form => any()
                           , tag  => expr()
                           , test => expr()
                           , then => expr()
                           , 'else' => expr()
                           }.

%% Let 表达式：表示 (let [bindings] body), 局部变量绑定
%% - body: 主体表达式
%% - bindings: 绑定表达式列表
-type let_expr()       :: #{ op       => 'let'
                           , env      => clj_env:env()
                           , form     => any()
                           , tag      => expr()
                           , body     => expr()
                           , bindings => [expr()]
                           }.

%% Loop 表达式：表示 (loop [bindings] body), 循环结构
%% - loop_id: 循环唯一标识符
%% - body: 循环体表达式
%% - bindings: 循环绑定列表
-type loop_expr()      :: #{ op       => loop
                           , env      => clj_env:env()
                           , form     => any()
                           , tag      => expr()
                           , loop_id  => loop_id()
                           , body     => expr()
                           , bindings => [expr()]
                           }.

%% Recur 表达式：表示 (recur args), 递归循环（只能出现在 loop/fn 中）
%% - exprs: 递归参数表达式列表
%% - loop_id: 关联的循环标识符
%% - loop_type: 循环类型（fn/fn_method/var/loop）
-type recur_expr()     :: #{ op        => recur
                           , env       => clj_env:env()
                           , form      => any()
                           , tag       => expr()
                           , exprs     => [expr()]
                           , loop_id   => loop_id()
                           , loop_type => loop_type()
                           }.

%% Letfn 表达式：表示 (letfn [fns] body), 相互递归的局部函数定义
%% - vars: 函数变量绑定列表
%% - fns: 函数表达式列表
%% - body: 主体表达式
-type letfn_expr()     :: #{ op        => letfn
                           , env       => clj_env:env()
                           , form      => any()
                           , tag       => expr()
                           , vars      => [local_expr()]
                           , fns       => [fn_expr()]
                           , body      => expr()
                           }.

%% Case 表达式：表示 (case test clauses default), 模式匹配分支
%% - test: 被测试的表达式
%% - clauses: 子句列表，每对为 {模式表达式, 结果表达式}
%% - default: 默认表达式（无可匹配时执行）
-type case_expr()      :: #{ op      => 'case'
                           , env     => clj_env:env()
                           , form    => any()
                           , tag     => expr()
                           , test    => expr()
                           , clauses => [{expr(), expr()}]
                           , default => expr() | ?NIL
                           }.

%% Erlang Map 表达式：表示 Erlang 风格的 map 结构（#{key => val}）
%% - keys: 键表达式列表
%% - vals: 值表达式列表
%% - pattern: 是否为模式匹配上下文
-type erl_map_expr()   :: #{ op      => erl_map
                           , env     => clj_env:env()
                           , form    => any()
                           , tag     => expr()
                           , keys    => [expr()]
                           , vals    => [expr()]
                           , pattern => boolean()
                           }.

%% Erlang List 表达式：表示 Erlang 风格的列表（[item | tail]）
%% - items: 列表元素表达式列表
%% - tail: 列表尾部表达式（用于构造非空列表）
-type erl_list_expr()  :: #{ op      => erl_list
                           , env     => clj_env:env()
                           , form    => any()
                           , tag     => expr()
                           , items   => [expr()]
                           , tail    => expr() | ?NIL
                           }.

%% Erlang Binary 表达式：表示 Erlang 二进制数据（<<segments>>）
%% - segments: binary 分段表达式列表
-type erl_binary_expr() :: #{ op       => erl_list
                            , env      => clj_env:env()
                            , form     => any()
                            , tag      => expr()
                            , segments => [binary_segment_expr()]
                            }.

%% Binary 分段表达式：表示 binary 构造中的单个分段
%% - value: 值表达式
%% - size: 大小表达式
%% - unit: 单位表达式
%% - type: 类型表达式
%% - flags: 标志表达式
-type binary_segment_expr() :: #{ op    => erl_list
                                , env   => clj_env:env()
                                , form  => any()
                                , tag   => expr()
                                , value => expr()
                                , size  => expr()
                                , unit  => expr()
                                , type  => expr()
                                , flags => expr()
                                }.

%% 元组表达式：表示 Erlang 元组（{item1, item2, ...}）
%% - items: 元组元素表达式列表
-type tuple_expr()     :: #{ op      => tuple
                           , env     => clj_env:env()
                           , form    => any()
                           , tag     => expr()
                           , items   => [expr()]
                           }.

%% Def 表达式：表示 (def name init), 定义 Var
%% - name: 定义名称符号
%% - var: 对应的 Var 对象
%% - init: 初始化表达式
%% - dynamic: 是否为动态绑定
-type def_expr()       :: #{ op      => def
                           , env     => clj_env:env()
                           , form    => any()
                           , tag     => expr()
                           , name    => 'clojerl.Symbol':type()
                           , var     => 'clojerl.Var':type()
                           , init    => expr()
                           , dynamic => boolean()
                           }.

%% Import 表达式：表示 (import typename), 导入 Erlang 类型
%% - typename: 类型名称（二进制形式，如 <<"erlang.IO">>）
-type import_expr()    :: #{ op       => import
                           , env      => clj_env:env()
                           , form     => any()
                           , tag      => expr()
                           , typename => binary()
                           }.

%% New 表达式：表示 (new Type args), 创建 Erlang 类型的实例
%% - type: 类型表达式列表
%% - args: 构造参数表达式列表
-type new_expr()       :: #{ op       => new
                           , env      => clj_env:env()
                           , form     => any()
                           , tag      => expr()
                           , type     => [expr()]
                           , args     => [expr()]
                           }.

%% Deftype 表达式：表示 (deftype name fields protocols methods opts), 定义新类型
%% - name: 类型名称符号
%% - type: 生成的 Erlang 类型
%% - fields: 字段定义列表
%% - protocols: 实现的协议列表
%% - methods: 方法定义列表
%% - opts: 选项列表
-type deftype_expr()   :: #{ op        => deftype
                           , env       => clj_env:env()
                           , form      => any()
                           , tag       => expr()
                           , name      => 'clojerl.Symbol':type()
                           , type      => 'erlang.Type':type()
                           , fields    => [expr()]
                           , protocols => [expr()]
                           , methods   => [expr()]
                           , opts      => [any()]
                           }.

%% Defprotocol 表达式：表示 (defprotocol name methods_sigs), 定义协议
%% - methods_sigs: 方法签名列表
-type defprotocol_expr() :: #{ op           => defprotocol
                             , env          => clj_env:env()
                             , form         => any()
                             , tag          => expr()
                             , methods_sigs => [any()]
                             }.

%% Extend-type 表达式：表示 (extend-type type impls), 扩展已有类型
%% - type: 被扩展的类型表达式
%% - impls: 协议实现映射（协议 => 方法列表）
-type extend_type_expr() :: #{ op        => extend_type
                             , env       => clj_env:env()
                             , form      => any()
                             , tag       => expr()
                             , type      => expr()
                             , impls     => #{expr() => [expr()]}
                             }.

%% Invoke 表达式：表示函数调用 (f args...)
%% - f: 被调用函数表达式
%% - args: 参数表达式列表
-type invoke_expr()      :: #{ op   => invoke
                             , env  => clj_env:env()
                             , form => any()
                             , tag  => expr()
                             , f    => expr()
                             , args => [expr()]
                             }.

%% 解析类型表达式：解析 Erlang 类型的占位符
%% - function: 解析函数名
-type resolve_type_expr() :: #{ op       => resolve_type
                              , env      => clj_env:env()
                              , form     => any()
                              , tag      => expr()
                              , function => atom()
                              }.

%% Throw 表达式：表示 (throw exception stacktrace), 抛出异常
%% - exception: 异常表达式
%% - stacktrace: 堆栈跟踪表达式
-type throw_expr()        :: #{ op         => throw
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , exception  => expr()
                              , stacktrace => expr()
                              }.

%% Try 表达式：表示 (try body catch finally), 异常处理
%% - body: 主体表达式
%% - catches: catch 子句列表
%% - finally: finally 块表达式
-type try_expr()          :: #{ op        => 'try'
                              , env       => clj_env:env()
                              , form      => any()
                              , tag       => expr()
                              , body      => expr()
                              , catches   => [catch_expr()]
                              , finally   => expr()
                              }.

%% Catch 表达式：try 的 catch 子句
%% - class: 异常类型表达式
%% - local: 异常绑定表达式
%% - stacktrace: 堆栈跟踪绑定表达式（可选）
%% - guard: 守卫条件
%% - body: catch 主体表达式
-type catch_expr()        :: #{ op         => 'catch'
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , class      => expr()
                              , local      => binding_expr()
                              , stacktrace => binding_expr() | ?NIL
                              , guard      => expr()
                              , body       => expr()
                              }.

%% Erlang 函数表达式：表示对 Erlang 模块函数的引用（module:function/arity）
%% - module: 模块名
%% - function: 函数名
%% - arity: 参数数量
-type erl_fun_expr()      :: #{ op        => erl_fun
                              , env       => clj_env:env()
                              , form      => any()
                              , tag       => ?NO_TAG
                              , module    => module()
                              , function  => atom()
                              , arity     => arity()
                              }.

%% Var 表达式：表示对 Var 的引用
%% - name: Var 名称符号
%% - var: Var 对象
%% - is_dynamic: 是否为动态 Var
-type var_expr()          :: #{ op         => var
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , name       => 'clojerl.Symbol':type()
                              , var        => 'clojerl.Var':type()
                              , is_dynamic => boolean()
                              }.

%% Type 表达式：表示类型引用（用于类型检查）
%% - type: 类型符号
-type type_expr()         :: #{ op         => type
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , type       => 'clojerl.Symbol':type()
                              }.

%% With-meta 表达式：表示 (with-meta obj meta), 为对象添加元数据
%% - meta: 元数据表达式
%% - expr: 目标对象表达式
-type with_meta_expr()    :: #{ op         => with_meta
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , meta       => expr()
                              , expr       => expr()
                              }.

%% Vector 表达式：表示向量（[item1, item2, ...]）
%% - items: 向量元素表达式列表
-type vector_expr()       :: #{ op         => vector
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , items      => [expr()]
                              }.

%% Set 表达式：表示集合（#{item1, item2, ...}）
%% - items: 集合元素表达式列表
-type set_expr()          :: #{ op         => set
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , items      => [expr()]
                              }.

%% Map 表达式：表示映射表（{key1 val1, key2 val2, ...}）
%% - keys: 键表达式列表
%% - vals: 值表达式列表
-type map_expr()          :: #{ op         => map
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , keys       => [expr()]
                              , vals       => [expr()]
                              }.

%% Receive 表达式：表示 (receive clauses after), Erlang 消息接收
%% - clauses: 消息匹配子句列表
%% - after: after 子句（超时处理）
-type receive_expr()      :: #{ op         => 'receive'
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , clauses    => [expr()]
                              , 'after'    => expr()
                              }.

%% After 表达式：receive 的 after 子句
%% - timeout: 超时表达式
%% - body: 超时后执行的体表达式
-type after_expr()        :: #{ op         => 'after'
                              , env        => clj_env:env()
                              , form       => any()
                              , tag        => expr()
                              , timeout    => expr()
                              , body       => expr()
                              }.

%% Erlang 别名表达式：用于模式匹配中的变量别名（= Pattern）
%% - variable: 变量表达式
%% - pattern: 模式表达式
-type erl_alias_expr()    :: #{ op       => erl_alias
                              , env      => clj_env:env()
                              , form     => any()
                              , tag      => expr()
                              , variable => expr()
                              , pattern  => expr()
                              }.

%% On-load 表达式：模块加载时执行的表达式
%% - body: 加载时执行的体表达式
-type on_load_expr()      :: #{ op    => on_load
                              , env   => clj_env:env()
                              , form  => any()
                              , tag   => expr()
                              , body  => expr()
                              }.

%% 表达式联合类型：表示所有可能的 AST 表达式类型
%% - 控制流：do, if, case, try, catch, throw
%% - 绑定与作用域：let, loop, recur, letfn, local, binding
%% - 函数：fn, fn_method, invoke, erl_fun
%% - 定义：def, deftype, defprotocol, extend-type
%% - 数据字面量：constant, vector, set, map, quote
%% - Erlang 互操作：erl_map, erl_list, erl_binary, tuple, erl_fun, erl_alias
%% - 引用：var, local, type, resolve_type
%% - 元数据：with_meta
%% - 并发：receive, after
%% - 模块：import, new, on_load
-type expr() :: constant_expr()
              | quote_expr()
              | local_expr()
              | binding_expr()
              | fn_expr()
              | fn_method_expr()
              | do_expr()
              | if_expr()
              | let_expr()
              | loop_expr()
              | recur_expr()
              | letfn_expr()
              | case_expr()
              | def_expr()
              | import_expr()
              | new_expr()
              | deftype_expr()
              | defprotocol_expr()
              | extend_type_expr()
              | invoke_expr()
              | resolve_type_expr()
              | throw_expr()
              | try_expr()
              | catch_expr()
              | erl_fun_expr()
              | var_expr()
              | type_expr()
              | with_meta_expr()
              | erl_map_expr()
              | erl_list_expr()
              | erl_binary_expr()
              | binary_segment_expr()
              | tuple_expr()
              | vector_expr()
              | set_expr()
              | map_expr()
              | receive_expr()
              | after_expr()
              | erl_alias_expr()
              | on_load_expr().

-endif.
