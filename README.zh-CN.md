# GoldPrice for macOS

[English](README.md) | [简体中文](README.zh-CN.md)

`GoldPrice` 是一个原生 SwiftUI macOS 菜单栏应用，用于实时追踪国际金价，支持 `USD / OZ` 和 `RMB / g` 双币种显示，带有桌面小组件和独立详情窗口。

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![SwiftUI](https://img.shields.io/badge/built%20with-SwiftUI-gold)
![Widget](https://img.shields.io/badge/widget-supported-8a6a1f)

## 预览

### 主面板（Dashboard）

![Dashboard Preview](docs/assets/preview-dashboard.png)

### 菜单栏面板

![Menu Bar Preview](docs/assets/preview-menubar.png)

## 功能

- 常驻菜单栏，点击即可查看金价
- 主应用每秒刷新一次
- 同时显示 `USD / OZ` 和 `RMB / g`
- 支持手动切换数据源：`自动`、`Kitco`、`Gold API`
- 支持切换菜单栏显示币种：点击切换按钮在美元和人民币之间切换
- 价格提醒：设定目标价，穿越时菜单栏闪烁 + 提示音 + 面板横幅通知
- 提醒历史：可回溯所有触发过的提醒及时间
- 详情窗口带短期价格走势图
- 支持 `systemSmall` 和 `systemMedium` 桌面小组件
- 纯原生 SwiftUI 实现，零第三方依赖

## 系统要求

- macOS 14 或更高版本
- Xcode 15 或更高版本
- 可访问公开金价数据源的网络连接

## 快速开始

1. 用 Xcode 打开 `GoldPrice.xcodeproj`
2. 选择 `GoldPrice` scheme
3. 在 `Signing & Capabilities` 中为 `GoldPrice` 和 `GoldPriceWidgetExtension` 分配 Team
4. 如果默认的 `com.example.*` bundle identifier 冲突，请替换为你自己的
5. 运行目标选择 `My Mac`
6. 按 `Cmd + R` 运行

首次启动后，应用入口在 macOS 菜单栏。点击金价数字打开面板，点击 `详情` 打开完整窗口。

## 文档

- [使用手册](docs/USAGE.md)
- [构建与发布](docs/BUILD_AND_RELEASE.md)
- [贡献指南](CONTRIBUTING.md)

中文版本：

- [使用手册](docs/USAGE.zh-CN.md)
- [构建与发布](docs/BUILD_AND_RELEASE.zh-CN.md)
- [贡献指南](CONTRIBUTING.zh-CN.md)

## 数据来源

应用目前支持以下模式：

- `自动`：优先使用 `Kitco`，失败时回退到 `Gold API`
- `Kitco`：直接从 Kitco 图表页面解析实时数据
- `Gold API`：使用 `https://api.gold-api.com/price/XAU`

`RMB / g` 价格从报价源中一同解析出的 `USD/CNY` 汇率计算得出。如果汇率解析失败，人民币价格将显示为 `--`。

## 刷新策略

- 菜单栏面板和详情窗口：每秒刷新一次
- 小组件：刷新频率由 `WidgetKit` 控制

这意味着真正的秒级更新仅适用于主应用，不适用于小组件。短期走势图仅在报价源返回新数据时推进。

## 项目结构

```text
GoldPriceApp/
  GoldPriceApp.swift
  MenuBarViews.swift
  ContentView.swift
  GoldPriceViewModel.swift

GoldPriceWidget/
  GoldPriceWidget.swift

Shared/
  GoldPriceService.swift
  GoldPriceModels.swift
  Formatting.swift
  GoldPriceTheme.swift

docs/
  assets/
  USAGE.md
  USAGE.zh-CN.md
  BUILD_AND_RELEASE.md
  BUILD_AND_RELEASE.zh-CN.md

scripts/
  generate_app_icon.swift
  generate_icon_concepts.swift
  generate_readme_previews.swift
  render_menu_header_preview.swift
```

## 本地构建

无签名本地构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Debug \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## 已知限制

- 小组件无法每秒刷新
- 金价解析依赖第三方页面结构和公开 API
- 仓库暂未包含签名和公证自动化
- 仓库暂未包含 `LICENSE` 文件

## 贡献

欢迎提交 Issue 和 Pull Request。在进行较大改动之前，请先阅读[贡献指南](CONTRIBUTING.md)。

## 许可证

尚未添加许可证文件。如果你计划公开发布此仓库，请在此之前确定许可证。
