# 开发速查（Quick Reference）- HarmonyOS App

一个将上游「速查表/备忘清单」Markdown 预处理为离线卡片数据，并在 HarmonyOS 上以更适合手机阅读的方式展示的应用。

开源地址: [jqknono/reference-harmony](https://github.com/jqknono/reference-harmony)

App 下载: [AppGallery](https://appgallery.huawei.com/app/detail?id=reference.app.jqknono.com)

<!-- <a href="https://appgallery.huawei.com/app/detail?id=reference.app.jqknono.com"><img src="assets/appgallery-icon.png" alt="华为应用市场（AppGallery）" height="40" /></a> -->

[![AppGallery QR](assets/https___appgallery.huawei.com_app_detail_id=reference.app.jqknono.com.png)](https://appgallery.huawei.com/app/detail?id=reference.app.jqknono.com)

- [在线清单列表（Web / GitHub Pages）](https://jqknono.github.io/reference-harmony/)
- [在线清单列表（Web / 阿里云托管，大陆用户可访问）](https://reference.jqknono.com/)

> 在线清单列表更新速度优先于 App 内离线内容更新速度。App 会尝试加载“云端清单”（在线目录）；若遇到延迟或缺失，仍可使用**添加在线 Markdown 链接**或**导入本地 Markdown 文件**获取最新内容。

## 应用介绍

### 应用一句话简介（17 个字以内，用于小编推荐）

程序员的随身速查宝典，学编程必备

### 应用介绍（面向普通用户，用于应用商店介绍, 8000字以内, 不支持Emoji）

**程序员的口袋知识库** —— 随时随地查阅技术文档，让学习编程不再枯燥！

无论你是刚入门的编程小白，还是经验丰富的技术大牛，这款应用都能帮你快速查阅各种编程语言、开发框架、常用工具的语法和命令。告别频繁百度，一个 App 搞定所有速查需求！

**海量内容，一网打尽**
- 收录 **400+** 精选技术速查表（197 中文 + 206 英文）
- 覆盖 Python、Java、JavaScript、Go、Rust、C/C++ 等主流编程语言
- 囊括 React、Vue、Docker、Git、MySQL、Redis 等热门技术栈
- 从 Linux 命令到正则表达式，从 Vim 快捷键到 ChatGPT 提示词，应有尽有

**卡片式学习，高效记忆**
- 知识点按卡片组织，清晰直观，一目了然
- 智能测验功能，通过问答巩固所学，让记忆更牢固
- 收藏夹 + 阅读历史，打造你的专属知识库

**贴心设计，极致体验**
- 深色/浅色主题自由切换，夜间学习不伤眼
- 强大搜索功能，秒速定位你要的内容
- 完全离线可用，地铁飞机上随时查阅
- 横屏适配，平板阅读更舒适
- 中英双语切换，外语文档轻松阅读

**持续更新，永不过时**
- 支持添加在线 Markdown 链接，实时获取最新文档
- 支持导入本地 Markdown 文件，打造个人知识库
- 开源项目，社区驱动，内容持续丰富

**适合人群**：程序员、开发者、计算机专业学生、IT 运维人员、技术爱好者

立即下载，开启你的高效学习之旅！

## 功能

- **目录（Catalog）**：按文档列表浏览与搜索，显示章节数/卡片数；支持收藏与最近阅读分组展示。
- **阅读（Read）**：按章节分组展示卡片（`text` / `code` / `qa`），支持文档内搜索与章节快速跳转（Chip 导航、TOC 面板）。
- **测验（Quiz）**：从当前文档的问答卡片中随机抽题，进行知识测验并查看得分与答题详情。
- **设置（Settings）**：语言（`zh`/`en`）与主题（`dark`/`light`）切换；在线 Markdown 链接管理；学习模式开关。
- **离线数据**：运行时从 `rawfile` 读取 JSON 渲染，不依赖在线接口。
- **在线清单列表**：从后端加载“云端清单”索引，在目录中直接浏览并打开/测验（运行时解析 Markdown）。
- **在线 Markdown**：支持添加任意在线 Markdown 链接，实时解析为卡片格式阅读。

## 数据来源与生成

工程将上游 Markdown 转为如下离线资源：

- `entry/src/main/resources/rawfile/reference/{zh|en}/*.json`
- `entry/src/main/resources/rawfile/reference/{zh|en}/manifest.json`
- `entry/src/main/resources/rawfile/reference/manifest.json`（`zh/en` 打包后的 bundle）

同步/生成脚本：`tools/sync_reference_docs.mjs`

### 推荐（使用 submodule，本地生成）

```bash
git submodule update --init --recursive
node tools/sync_reference_docs.mjs --mode=local
```

### 可选（无 submodule，走 GitHub API）

```bash
node tools/sync_reference_docs.mjs --mode=github
```

常用参数：

- `--langs=zh,en`：选择生成语言
- `--zh-ref=main` / `--en-ref=main`：指定上游分支/Tag
- `--limit=20`：仅生成前 N 个文档（便于调试）
- `--filter=keyword`：仅处理路径包含关键字的文档
- `--concurrency=8`：并发数
- `--keep-tags`：生成 JSON 时保留行内 `<tag>` / `</tag>`（默认会剥离标签，仅保留内部文本；行内代码/转义的 `\\<tag>`/autolink 不受影响）

> 如果 App 提示 “加载 manifest 失败”，通常是 `rawfile/reference/**` 未生成或不完整，先运行上述脚本。

## 构建与运行

### 使用 DevEco Studio（推荐）

1. 用 DevEco Studio 打开工程目录（本仓库根目录）。
2. 确认已配置 HarmonyOS SDK（本工程 `targetSdkVersion` 为 `6.0.1(21)`，对应 API 21）。
3. 运行 `tools/sync_reference_docs.mjs` 生成/更新离线数据（可选，仓库已包含一份示例数据）。
4. 选择设备/模拟器后运行。

### 命令行构建（用于验证/CI）

仓库约束要求：每次修改 `.ets/.ts/.js/.mjs` 后必须验证编译通过。编译命令如下（按本机 DevEco 安装路径调整）：

```powershell
"C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default assembleHap --analyze=normal --parallel --incremental --daemon
```

### 在线清单工程（Vue + Node）

后端（提供在线目录 API 与 `/mds/**` 托管）：

```bash
cd online/server
node src/index.mjs
```

前端（Vue 清单列表页，默认读取静态 `catalog.json`；也支持通过 `VITE_API_BASE` 走后端 API）：

```bash
cd online/web
npm install
npm run dev
```

构建（用于 GitHub Pages，产物在 `online/web/dist/`，并包含 `dist/mds/**` 与 `dist/catalog.json`）：

```bash
cd online/web
npm install
npm run build
```

## 工程结构

- `AppScope/`：应用级配置（`app.json5`、应用资源等）
- `entry/`：Stage 模型入口模块
  - `entry/src/main/ets/pages/Index.ets`：主页面（Tabs：Catalog / List / Settings）
  - `entry/src/main/ets/common/referenceRepository.ets`：从 `rawfile` 读取并解析 JSON
  - `entry/src/main/ets/common/referenceModels.ets`：数据结构（manifest / doc / card）
  - `entry/src/main/ets/components/ReferenceCard.ets`：卡片渲染
  - `entry/src/main/resources/rawfile/reference/`：离线数据（由脚本生成）
- `tools/sync_reference_docs.mjs`：同步上游 Markdown 并生成离线 JSON
- `online/server/`：在线清单后端（Node.js）：提供 `GET /api/v1/catalog` 与静态 `/mds/**` 托管
- `online/web/`：在线清单前端（Vue3+Vite）：清单列表页（搜索/复制链接/下载）；GitHub Pages 由此构建
- `submodules/`：上游数据源仓库（可选但推荐）
  - `submodules/jaywcjlove-reference`：中文数据源（197 篇）
  - `submodules/fechin-reference`：英文数据源（206 篇）
- `docs/`：开发文档
  - `docs/dev_plan_1.md`：实现思路与迭代计划
  - `docs/dev_plan_2.md`：功能扩展路线图

## 开发约束（重要）

- **启用 Git Hooks（提交前自动同步版本信息）**：首次克隆后执行一次 `git config core.hooksPath .githooks`（或 `npm run hooks:install`），之后每次 `git commit` 会自动把 `AppScope/app.json5` 的 `versionCode` 更新为当前时间戳，并将 `AppScope/app.json5` 的 `versionName/versionCode` 同步到 `entry/src/main/ets/pages/index/SettingsTab.ets`（关于页兜底版本展示）后加入暂存区。
- 禁止在本仓库的**源代码**（`.ets/.ts/.js/.mjs`，包含工具脚本）中使用 `try/catch/finally` 语句块。
- 处理异常请使用返回结果类型或 Promise 的双参数 `then(onFulfilled, onRejected)` 链路/显式 `throw`。
- 如需补充上下文，请在同一执行路径直接构造 `Error` 并抛出（或拒绝 Promise），不要借助 `try/catch` 包裹。

## 常见问题

- **`hvigor/ohpm` 命令行工具启动报错**（`Class extends value undefined...`）：见 `docs/dev_plan_1.md` 的 “命令行工具依赖冲突” 说明。
- **GitHub API 受限/拉取慢**：优先使用 `git submodule update --init --recursive` 并 `--mode=local`。

## 致谢与说明

离线数据来源：

- 中文：`jaywcjlove/reference`（MIT License，详见 `submodules/jaywcjlove-reference/LICENSE`）
- 英文：`Fechin/reference`（GPL-3.0，详见 `submodules/fechin-reference/LICENSE`）

## 上架合规 / 隐私（AppGallery Connect）

> 本节仅整理华为官方文档要点与链接；实际要求以 AppGallery Connect / 审核政策页面为准。

- **隐私政策（强制）**：创建应用或更新版本时，必须提交 App 隐私政策链接，且需与 App 内隐私政策内容保持一致。参考：[隐私政策链接提交及内容规范参考 FAQ](https://developer.huawei.com/consumer/cn/doc/app/50128)
- **隐私标签（上架需填写）**：上架应用时需填写应用及第三方组件收集的个人数据项与用途。参考：[AppGallery 隐私标签服务说明](https://developer.huawei.com/consumer/cn/doc/privacy-label)
- **应用隐私说明（条件触发）**：若检测到涉及敏感隐私权限或受限开放权限，需要在 AGC 填写“应用隐私说明”。参考：[配置隐私说明](https://developer.huawei.com/consumer/cn/doc/app/agc-help-release-app-privacy-desc-0000002313477969)
- **提交审核流程**：参考：[提交审核（HarmonyOS 5 及以上）](https://developer.huawei.com/consumer/cn/doc/app/agc-help-release-app-submit-0000002286180890)
- **隐私声明管理（可选参考）**：参考：[FAQ-管理隐私声明](https://developer.huawei.com/consumer/cn/doc/app/agc-help-privacy-policy-faq-0000002342315628)
- **个人信息保护常见问题（可选参考）**：参考：[APP 常见个人信息保护问题 FAQ](https://developer.huawei.com/consumer/cn/doc/app/FAQ-faq-09)

## 官方开发文档（HarmonyOS）

- **设计**：[HarmonyOS 设计规范与指南](https://developer.huawei.com/consumer/cn/design/)
- **ArkTS**：[ArkTS 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts)
- **ArkUI**：[ArkUI 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkui)
- **ArkData**：[ArkData 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkdata)
- **Ability Kit**：[Ability Kit 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ability-kit)
- **UI Design Kit**：[UI Design Kit 指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-kit-guide)
- **最佳实践**：[HarmonyOS 最佳实践](https://developer.huawei.com/consumer/cn/doc/best-practices/bpta-best-practices-overview)
- **API 参考**：[HarmonyOS API 参考](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/development-intro-api)
- **AppGallery Connect**：[AppGallery Connect 文档入口](https://developer.huawei.com/consumer/cn/agconnect/)
