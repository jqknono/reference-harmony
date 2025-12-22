# Engineering guardrails

- 修改 `.ets` 后需验证编译通过, 这是编译命令: `cd "F:\code\reference-harmony" ; & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --parallel --incremental`
- 静态检查（ArkTSCheck）, 使用 `F:\huawei\command-line-tools` 下的 CodeLinter 对 ArkTS 进行静态检查，命令如下:
  - `cd "F:\code\reference-harmony" ; & "F:\huawei\command-line-tools\tool\node\node.exe" "F:\huawei\command-line-tools\codelinter\index.js" "F:\huawei\command-line-tools\sdk" -c ".\\code-linter.json5" -p default -e error,warn .`

# UI 布局约束

- 代码块应占满横向空间，不应有左右缩进（负 margin）。
- 禁止按像素（px）调整布局尺寸，应使用字体相对值（基于 `fontSize` 计算）。
