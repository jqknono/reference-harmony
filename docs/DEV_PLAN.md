# 快速参考（Quick Reference）鸿蒙应用开发计划（MVP）

## 目标
- 将 `https://github.com/jaywcjlove/reference/tree/main/docs` 下的 Markdown 转成“便于手机阅读/记忆”的卡片。
- App 底部提供导航（Tabs），并在阅读页底部提供“章节快速跳转”。

## MVP 范围（1~3 天可跑通）
- 离线数据：构建期把 Markdown 预处理成 JSON，打包进 `rawfile`。
- 文档列表页：展示文档标题/卡片数量，点选进入阅读页。
- 阅读页：卡片列表（text / code / qa），点击 QA 卡片正反切换。
- 章节导航：阅读页底部横向滚动 chip，一键跳转到该章节。
- 基础脚手架脚本：拉取 GitHub docs 并生成 JSON（后续再优化解析质量）。

## 数据流设计
1) `tools/sync_reference_docs.mjs` 从 GitHub 拉取 `docs/**/*.md`
2) 解析 Markdown -> `{ sections[], cards[] }` JSON
3) 输出到 `entry/src/main/resources/rawfile/reference/*.json` + `manifest.json`
4) App 运行时通过 `resourceManager.getRawFileContent()` 读取 JSON 并渲染

## 迭代路线（建议）
1. **解析增强**：更好识别表格/代码块/多级标题，减少“碎卡片”
2. **搜索**：按标题/正文实时过滤卡片（先在当前文档内）
3. **收藏/最近阅读**：本地持久化（Preferences）
4. **主题与排版**：暗色模式、字号、代码高亮（可选）

## 本仓库已搭好的框架
- 模块名：`entry`（Stage 模型）
- 入口页面：`entry/src/main/ets/pages/Index.ets`
- 数据模型：`entry/src/main/ets/common/referenceModels.ets`
- 数据读取：`entry/src/main/ets/common/referenceRepository.ets`
- 卡片组件：`entry/src/main/ets/components/ReferenceCard.ets`
- 示例数据：`entry/src/main/resources/rawfile/reference/manifest.json`

## 常用命令
- 同步并生成数据：`node tools/sync_reference_docs.mjs`
- 构建（需要 Java/JDK）：`F:\\huawei\\command-line-tools\\bin\\hvigorw.bat --cwd . assembleApp -p product=default -p buildMode=debug`

## 开发环境（建议）
- IDE：DevEco Studio（用图形界面配置 SDK/JDK 最省事）
- SDK：已在本机 `F:\\huawei\\sdk\\20`（API 21 / 6.0.1）
- Node：`F:\\huawei\\command-line-tools\\tool\\node\\node.exe`（本机为 v18.20.1）
- JDK：命令行打包 `hap/app` 需要系统可用 `java`（配置 `JAVA_HOME` 或把 `java.exe` 加到 `PATH`）

## 文档链接（可直接访问的）
- OpenHarmony 文档总入口：`https://docs.openharmony.cn/`
- OpenHarmony Docs（Gitee 仓库）：`https://gitee.com/openharmony/docs`
- OpenHarmony 应用开发文档（目录入口，含 ArkTS/ArkUI）：`https://gitee.com/openharmony/docs/tree/master/zh-cn/application-dev`
- 数据来源仓库：`https://github.com/jaywcjlove/reference`
- 参考网页样式（示例）：`https://wangchujiang.com/reference/docs/javascript.html`

## 文档链接（可能需要浏览器/地区/登录）
- HarmonyOS 开发者文档入口（华为）：`https://developer.huawei.com/consumer/cn/doc/`

## 备注：命令行工具依赖冲突
如果你要在本机用 `hvigor/ohpm` 命令行工具，`F:\\huawei\\command-line-tools` 里存在 `minizlib -> minipass` 的嵌套依赖冲突会导致启动报错（`Class extends value undefined...`）。我已将以下目录重命名为 `minipass.bak` 以绕开冲突：
- `F:\\huawei\\command-line-tools\\hvigor\\hvigor-ohos-plugin\\node_modules\\minizlib\\node_modules\\minipass`
- `F:\\huawei\\command-line-tools\\ohpm\\node_modules\\minizlib\\node_modules\\minipass`
