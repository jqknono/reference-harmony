# Engineering guardrails

- 禁止在本仓库的**源代码**（`.ets/.ts/.js/.mjs`）中使用 `try`/`catch`/`finally` 语句块（工具脚本也同样适用）。
- 处理异常时请使用返回结果类型或 Promise 的双参数 `then(onFulfilled, onRejected)` 链路/显式 `throw`，但不要写 `try`/`catch` 语句块。
- 如果需要补充上下文，请在同一执行路径直接构造 `Error` 并抛出（或拒绝 Promise），不要借助 `try`/`catch` 包裹。
- `entry/src/main/resources/rawfile/reference/**` 属于参考内容数据，允许出现 `try/catch/finally` 字样（代码示例文本）。
- 每次修改 `.ets/.ts/.js/.mjs` 后必须验证编译通过, 这是编译命令: `"C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default assembleHap --analyze=normal --parallel --incremental --daemon`
