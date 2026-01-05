# 开发速查（Quick Reference）- HarmonyOS App

一个将上游「速查表/备忘清单」Markdown 预处理为离线卡片数据，并在 HarmonyOS 上以更适合手机阅读的方式展示的应用。

开源地址: [jqknono/reference-harmony](https://github.com/jqknono/reference-harmony)

App 下载: [AppGallery](https://appgallery.huawei.com/app/detail?id=reference.app.jqknono.com)

<!-- <a href="https://appgallery.huawei.com/app/detail?id=reference.app.jqknono.com"><img src="assets/appgallery-icon.png" alt="华为应用市场（AppGallery）" height="40" /></a> -->

[![AppGallery QR](assets/https___appgallery.huawei.com_app_detail_id=reference.app.jqknono.com.png)](https://appgallery.huawei.com/app/detail?id=reference.app.jqknono.com)

- [备忘清单文件列表--Github Pages](https://jqknono.github.io/reference-harmony/)
- [备忘清单文件列表--阿里云托管(大陆用户可访问)](https://reference.jqknono.com/)

> 在线清单列表更新速度优先于 App 内离线内容更新速度, App 内部分清单更新存在延迟, 部分清单可能未包含, 可以使用**添加在线 Markdown 链接**或**导入本地 Markdown 文件**来获得最新内容。

## 应用介绍

### 应用一句话简介（17 个字以内，用于小编推荐）

离线速查+测验，随查随学

### 应用介绍（面向普通用户，用于应用商店介绍）

一款随身速查与学习应用，汇集 **380+** 份技术速查表，涵盖编程语言、开发工具、数据库、命令行等常用主题的要点、代码示例与问答卡片。支持离线浏览、关键词搜索、章节快速跳转；提供在线 Markdown 解析、知识测验、收藏与最近阅读等功能，中英双语与深浅主题自由切换。

- **海量速查**：内置 185+ 中文、200+ 英文速查表，涵盖 Git、Docker、Python、JavaScript、React、MySQL、Linux 命令等热门主题。
- **知识测验**：基于文档中的问答卡片自动生成测验题，边查边学，巩固记忆。
- **在线解析**：支持输入任意在线 Markdown 链接，实时解析为卡片阅读。
- **收藏与历史**：收藏常用文档，自动记录最近阅读，快速回访。
- **快速检索**：支持目录搜索、文档内搜索与章节跳转，查找更高效。
- **离线可用**：内容内置，弱网/无网也能查看。
- **个性阅读**：支持中英文切换与深色/浅色主题。
- **横屏适配**：横屏模式下自动调整布局，平板体验更佳。

## 功能

- **目录（Catalog）**：按文档列表浏览与搜索，显示章节数/卡片数；支持收藏与最近阅读分组展示。
- **阅读（Read）**：按章节分组展示卡片（`text` / `code` / `qa`），支持文档内搜索与章节快速跳转（Chip 导航、TOC 面板）。
- **测验（Quiz）**：从当前文档的问答卡片中随机抽题，进行知识测验并查看得分与答题详情。
- **设置（Settings）**：语言（`zh`/`en`）与主题（`dark`/`light`）切换；在线 Markdown 链接管理；学习模式开关。
- **离线数据**：运行时从 `rawfile` 读取 JSON 渲染，不依赖在线接口。
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
2. 确认已配置 HarmonyOS SDK（本工程 `modelVersion` 为 `6.0.1`，对应 API 21）。
3. 运行 `tools/sync_reference_docs.mjs` 生成/更新离线数据（可选，仓库已包含一份示例数据）。
4. 选择设备/模拟器后运行。

### 命令行构建（用于验证/CI）

仓库约束要求：每次修改 `.ets/.ts/.js/.mjs` 后必须验证编译通过。编译命令如下（按本机 DevEco 安装路径调整）：

```powershell
"C:\Program Files\Huawei\DevEco Studio\tools\node\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" clean --mode module -p product=default assembleHap --analyze=normal --parallel --incremental --daemon
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
- `submodules/`：上游数据源仓库（可选但推荐）
  - `submodules/jaywcjlove-reference`：中文数据源
  - `submodules/fechin-reference`：英文数据源
- `docs/DEV_PLAN.md`：实现思路与迭代计划

## 开发约束（重要）

- **启用 Git Hooks（提交前自动同步版本信息）**：首次克隆后执行一次 `git config core.hooksPath .githooks`（或 `npm run hooks:install`），之后每次 `git commit` 会自动把 `AppScope/app.json5` 的 `versionCode` 更新为当前时间戳，并将 `AppScope/app.json5` 的 `versionName/versionCode` 同步到 `entry/src/main/ets/pages/index/SettingsTab.ets`（关于页兜底版本展示）后加入暂存区。
- 禁止在本仓库的**源代码**（`.ets/.ts/.js/.mjs`，包含工具脚本）中使用 `try/catch/finally` 语句块。
- 处理异常请使用返回结果类型或 Promise 的双参数 `then(onFulfilled, onRejected)` 链路/显式 `throw`。
- 如需补充上下文，请在同一执行路径直接构造 `Error` 并抛出（或拒绝 Promise），不要借助 `try/catch` 包裹。

## 常见问题

- **`hvigor/ohpm` 命令行工具启动报错**（`Class extends value undefined...`）：见 `docs/DEV_PLAN.md` 的 “命令行工具依赖冲突” 说明。
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
