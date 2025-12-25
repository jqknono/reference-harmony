# Engineering guardrails

- 修改 `.ets` 后需验证编译通过, 这是编译命令: `cd "F:\code\reference-harmony" ; & "C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default -p buildMode=default assembleHap --analyze=normal --parallel --incremental`
- submodules\jaywcjlove-reference\docs\quickreference.md 中描述了`rehype`的使用方式.
- `sync_reference_docs.mjs` 和 `markdownDocParser.ets` 逻辑需保持一致.

## 编译问题处理

- `hvigorw --stop-daemon`

## UI 布局约束

- 代码块应占满横向空间，不应有左右缩进（负 margin）。
- 禁止按像素（px）调整布局尺寸，应使用字体相对值（基于 `fontSize` 计算）。

## 开发文档

- [设计](https://developer.huawei.com/consumer/cn/doc/design-guides/design-concepts-0000001795698445)
- [ArkTS（方舟编程语言）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts)
- [ArkUI（方舟 UI 框架）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkui)
- [ArkData（方舟数据管理）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkdata)
- [Ability Kit（程序框架服务）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ability-kit)
- [UI Design Kit（UI 设计套件）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-kit-guide)
- [最佳实践](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-best-practices-overview)
- [API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/development-intro-api)
