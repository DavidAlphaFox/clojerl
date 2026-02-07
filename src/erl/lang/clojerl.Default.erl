%% @doc Default 模块 - 默认类型实现
%% @desc
%% - 功能：用于在 extend-type 表单中允许 'default' 符号作为类型，作为万能
%%   实现的捕获类型。当没有更具体的类型匹配时，提供默认实现。
%% - 依赖：无特定协议实现，作为类型系统的辅助模块
%% @private
-module('clojerl.Default').
