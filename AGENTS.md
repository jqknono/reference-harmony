# Engineering guardrails

- 修改 `.ets` 后需验证编译通过, 这是编译命令: `cd "F:\code\reference-harmony" ; & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default -p buildMode=default assembleHap --analyze=normal --parallel --incremental`
- submodules\jaywcjlove-reference\docs\quickreference.md 中描述了`rehype`的使用方式.
- `sync_reference_docs.mjs` 和 `markdownDocParser.ets` 逻辑需保持一致.

## 编译问题处理

- `hvigorw --stop-daemon`

# UI 布局约束

- 代码块应占满横向空间，不应有左右缩进（负 margin）。
- 禁止按像素（px）调整布局尺寸，应使用字体相对值（基于 `fontSize` 计算）。
