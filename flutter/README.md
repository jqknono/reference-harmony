# Reference Harmony - Flutter 版本

基于 Flutter 框架开发的速查手册应用，支持 HarmonyOS NEXT 平台。

## 项目概述

本项目是 Reference Harmony 的 Flutter 实现版本，使用 Flutter OHOS 分支支持在鸿蒙系统上运行。

## 开发环境要求

### 基础环境

- **Flutter SDK**: 3.7.12+ (OHOS 分支)
- **Dart SDK**: 3.0.0+
- **DevEco Studio**: 5.0.0+
- **HarmonyOS SDK**: 5.0.0 (API 12)+
- **Node.js**: 18.15.0+
- **JDK**: 17+

### 获取 Flutter OHOS 分支

```bash
# 克隆 Flutter OHOS 仓库
git clone https://gitcode.com/openharmony-sig/flutter_flutter.git flutter_ohos
cd flutter_ohos
git checkout 3.7.12-ohos-1.0.4
```

### 环境变量配置 (Windows)

```powershell
# Flutter OHOS SDK
$env:PATH = "D:\flutter_ohos\bin;$env:PATH"

# 依赖缓存目录
$env:PUB_CACHE = "D:\PUB"

# 国内镜像（可选）
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"

# HarmonyOS SDK
$env:TOOL_HOME = "C:\Program Files\Huawei\DevEco Studio"
$env:DEVECO_SDK_HOME = "$env:TOOL_HOME\sdk"
$env:PATH = "$env:TOOL_HOME\tools\ohpm\bin;$env:PATH"
$env:PATH = "$env:TOOL_HOME\tools\hvigor\bin;$env:PATH"
$env:PATH = "$env:TOOL_HOME\tools\node;$env:PATH"

# JDK
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17"
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
```

### 环境变量配置 (macOS/Linux)

```bash
# Flutter OHOS SDK
export PATH=/path/to/flutter_ohos/bin:$PATH

# 依赖缓存目录
export PUB_CACHE=/path/to/pub_cache

# 国内镜像（可选）
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

# HarmonyOS SDK (macOS)
export TOOL_HOME=/Applications/DevEco-Studio.app/Contents
export DEVECO_SDK_HOME=$TOOL_HOME/sdk
export PATH=$TOOL_HOME/tools/ohpm/bin:$PATH
export PATH=$TOOL_HOME/tools/hvigor/bin:$PATH
export PATH=$TOOL_HOME/tools/node/bin:$PATH

# JDK
export JAVA_HOME=/path/to/jdk-17
export PATH=$JAVA_HOME/bin:$PATH
```

## 项目结构

```
flutter/
├── lib/                          # Dart 源代码
│   ├── main.dart                 # 应用入口
│   ├── models/                   # 数据模型
│   │   └── reference_models.dart # 参考文档模型
│   ├── providers/                # 状态管理
│   │   ├── app_state.dart        # 应用状态
│   │   └── theme_provider.dart   # 主题管理
│   ├── l10n/                     # 国际化
│   │   └── app_localizations.dart
│   ├── pages/                    # 页面
│   │   ├── home_page.dart        # 主页
│   │   └── tabs/                 # 标签页
│   │       ├── catalog_tab.dart  # 目录
│   │       ├── read_tab.dart     # 阅读
│   │       ├── quiz_tab.dart     # 测验
│   │       ├── settings_tab.dart # 设置
│   │       └── custom_list_tab.dart # 收藏
│   └── widgets/                  # 组件
│       ├── doc_card.dart         # 文档卡片
│       ├── reference_card_widget.dart # 参考卡片
│       └── toc_drawer.dart       # 目录抽屉
├── ohos/                         # HarmonyOS 平台代码
│   ├── AppScope/                 # 应用作用域配置
│   ├── entry/                    # 入口模块
│   │   └── src/main/
│   │       ├── ets/              # ArkTS 代码
│   │       ├── resources/        # 资源文件
│   │       └── module.json5      # 模块配置
│   ├── build-profile.json5       # 构建配置
│   └── oh-package.json5          # 包配置
├── assets/                       # 资源文件
│   ├── fonts/                    # 字体
│   ├── icons/                    # 图标
│   └── reference/                # 参考文档数据
│       ├── zh/                   # 中文文档
│       └── en/                   # 英文文档
├── pubspec.yaml                  # Flutter 项目配置
└── README.md                     # 本文档
```

## 开发指南

### 1. 检查环境

```bash
flutter doctor -v
```

确保 Flutter 和 OpenHarmony 检查结果都显示 **ok**。

### 2. 获取依赖

```bash
cd flutter
flutter pub get
```

### 3. 运行应用

#### 在鸿蒙设备上运行

```bash
# 查看连接的设备
flutter devices

# 运行调试版本
flutter run -d <deviceId> --debug

# 运行发布版本
flutter run -d <deviceId> --release
```

#### 在其他平台运行（开发调试用）

```bash
# Android
flutter run -d android

# iOS
flutter run -d ios

# Web
flutter run -d chrome
```

### 4. 构建应用

#### 构建 HAP 文件

```bash
# 调试版本
flutter build hap --debug

# 发布版本
flutter build hap --release
```

构建产物位于：`ohos/entry/build/default/outputs/default/entry-default-signed.hap`

#### 构建 APP 包

```bash
flutter build app --release
```

### 5. 安装应用

```bash
# 使用 hdc 安装
hdc -t <deviceId> install <hap文件路径>
```

## 功能特性

- 📚 **文档目录**: 浏览中英文速查手册
- 📖 **文档阅读**: 支持代码块、表格、列表等格式
- 🔍 **搜索功能**: 文档内全文搜索
- 🌙 **深色模式**: 支持浅色/深色/跟随系统
- 🌐 **多语言**: 支持中文和英文界面
- 📑 **目录导航**: 快速跳转到文档章节

## 常见问题

### 1. 模拟器调试

HarmonyOS 模拟器仅支持 macOS (ARM64) 系统调试。

### 2. 构建失败

如果出现 `Error: The hvigor depends on the npmrc file` 错误，请在用户目录创建 `.npmrc` 文件：

```
registry=https://repo.huaweicloud.com/repository/npm/
@ohos:registry=https://repo.harmonyos.com/npm/
```

### 3. 运行时崩溃

如果调试版本运行崩溃，提示 snapshot 版本不匹配，请：

1. 设置环境变量：
   ```bash
   export FLUTTER_STORAGE_BASE_URL=https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com
   ```
2. 删除 `flutter_ohos/bin/cache` 目录
3. 执行 `flutter clean`
4. 重新运行

### 4. 日志查看

```bash
# 关闭全局日志
hdc shell hilog -b X

# 开启指定域日志
hdc shell hilog -b D -D A00000
```

## 参考资源

- [Flutter OHOS 官方仓库](https://gitcode.com/openharmony-sig/flutter_flutter)
- [Flutter OHOS 示例](https://gitee.com/openharmony-sig/flutter_samples)
- [HarmonyOS 开发者文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides)
- [Flutter 官方文档](https://flutter.dev/docs)

## 许可证

MIT License
