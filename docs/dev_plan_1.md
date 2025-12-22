# 开发速查（Quick Reference）鸿蒙应用开发计划

## 应用功能概览

### 核心功能

1. **文档目录（Catalog Tab）**
   - 展示所有可用的速查文档列表
   - 显示每个文档的章节数和卡片数
   - 支持文档标题/名称搜索过滤
   - 支持中英文双语文档切换
   - 支持本地离线文档和在线 Markdown 文档

2. **阅读页（Cheatsheet Tab）**
   - 按章节分组展示卡片内容（text / code / qa 类型）
   - 支持文档内关键词搜索
   - 章节快速导航（底部 Chip 导航栏）
   - 目录面板（TOC Panel）快速跳转
   - 卡片内容支持代码高亮、表格渲染、Markdown 解析

3. **测验功能（Quiz Tab）**
   - 基于文档表格内容自动生成选择题
   - 支持选择题目数量（5/10/15 题）
   - 实时答题反馈和正确答案展示
   - 测验记录统计（总测验数、平均分、正确率）
   - 最近测验历史列表

4. **设置页（Settings Tab）**
   - 屏幕方向控制（竖屏/横屏/自动）
   - 语言切换（中文/英文）
   - 主题切换（暗黑/明亮）
   - 艾宾浩斯记忆提醒（基于遗忘曲线的复习通知）
   - 学习模式（表格内容遮盖，便于自测）
   - 在线 Markdown 链接管理（添加/删除/复制）

### 数据管理

- **离线数据**：构建期将 Markdown 预处理成 JSON，打包进 `rawfile`
- **在线数据**：支持输入在线 Markdown URL，解析后缓存本地
- **持久化**：使用 Preferences 保存用户设置和测验记录

## 数据来源

- 中文数据源：`https://github.com/jaywcjlove/reference/tree/main/docs`
- 英文数据源：`https://github.com/Fechin/reference/tree/main/source/_posts`

## 数据流设计

1. `tools/sync_reference_docs.mjs` 优先从本地 submodule 读取 Markdown（没有则通过 GitHub API 拉取）
2. 解析 Markdown -> `{ sections[], cards[] }` JSON
3. 输出到 `entry/src/main/resources/rawfile/reference/{zh|en}/*.json` + `manifest.json`
4. App 运行时通过 `resourceManager.getRawFileContent()` 读取 JSON 并渲染

## Submodules（推荐）

- 初始化/更新：`git submodule update --init --recursive`

## 本仓库已搭好的框架

- 模块名：`entry`（Stage 模型）
- 入口页面：`entry/src/main/ets/pages/Index.ets`
- 数据模型：`entry/src/main/ets/common/referenceModels.ets`
- 数据读取：`entry/src/main/ets/common/referenceRepository.ets`
- 卡片组件：`entry/src/main/ets/components/ReferenceCard.ets`
- 测验工具：`entry/src/main/ets/common/quizModels.ets`、`quizUtils.ets`、`quizRepository.ets`
- 在线文档：`entry/src/main/ets/common/onlineMdModels.ets`、`onlineMdRepository.ets`
- 记忆提醒：`entry/src/main/ets/common/ebinghausReminder.ets`
- 主题系统：`entry/src/main/ets/common/appTheme.ets`
- 示例数据：`entry/src/main/resources/rawfile/reference/zh/manifest.json`、`entry/src/main/resources/rawfile/reference/en/manifest.json`

## 常用命令

- 同步并生成数据：`node tools/sync_reference_docs.mjs`（默认 `--mode=auto`，有 submodule 就走本地）
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
