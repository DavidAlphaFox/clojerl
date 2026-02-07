%% @doc Clojure Nil 模块
%% @desc
%% - 功能：定义 nil 值的模块（nil 在 Clojerl 中用空映射表示）
%% - 说明：nil 在 Clojerl 中只是一个标记，实际上使用空映射 #{?TYPE => ?NIL} 表示
-module('clojerl.Nil').
