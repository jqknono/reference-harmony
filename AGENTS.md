# Engineering guardrails

- 每次修改 `.ets` 后必须验证编译通过, 这是编译命令: `cd "F:\code\reference-harmony" ; & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default assembleHap --analyze=normal --parallel --incremental --daemon`

# UI 布局约束

- 代码块应占满横向空间，不应有左右缩进（负 margin）。
- 禁止按像素（px）调整布局尺寸，应使用字体相对值（基于 `fontSize` 计算）。
