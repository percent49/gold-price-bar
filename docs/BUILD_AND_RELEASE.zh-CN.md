# 构建与发布

[English](BUILD_AND_RELEASE.md) | [简体中文](BUILD_AND_RELEASE.zh-CN.md)

本指南面向开发者，涵盖本地构建、`.dmg` 打包以及分发所需的额外步骤。

## 1. 环境要求

- macOS
- Xcode 15+
- 可用的命令行工具：`xcodebuild`、`hdiutil`

## 2. Debug 构建

用于本地开发：

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

典型输出：

```text
.build/DerivedData/Build/Products/Debug/GoldPrice.app
```

## 3. Release 构建

用于打包：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project GoldPrice.xcodeproj \
  -scheme GoldPrice \
  -configuration Release \
  -derivedDataPath ./.build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

典型输出：

```text
.build/DerivedData/Build/Products/Release/GoldPrice.app
```

## 4. 构建 `.dmg`

最简本地打包流程：

```bash
mkdir -p ./.build/dmg-root
cp -R ./.build/DerivedData/Build/Products/Release/GoldPrice.app ./.build/dmg-root/
ln -s /Applications ./.build/dmg-root/Applications

hdiutil create \
  -volname "GoldPrice" \
  -srcfolder ./.build/dmg-root \
  -ov \
  -format UDZO \
  ./GoldPrice.dmg
```

输出：

```text
./GoldPrice.dmg
```

## 5. 分发给其他用户

如果你打算将应用发给其他 macOS 用户，仅靠普通 `.dmg` 是不够的。

推荐流程：

1. 使用 `Developer ID Application` 签名 `GoldPrice.app`
2. 提交至 `notarytool` 进行公证
3. 将公证结果装订（staple）回 `app` 或 `dmg`

典型命令链：

```bash
xcodebuild archive ...
xcodebuild -exportArchive ...
hdiutil create ...
xcrun notarytool submit ...
xcrun stapler staple ...
```

## 6. 常见发布问题

### 小组件不显示

检查：

- 主应用和小组件 extension 使用相同的 Team
- bundle identifier 没有冲突
- 主应用已成功启动过至少一次

### Gatekeeper 阻止启动

这通常意味着构建是未签名或未公证的。在公开发布前完成签名和公证。

### 数据源失效

应用依赖第三方报价源。如果 `Kitco` 页面结构发生变化，请检查：

- `Shared/GoldPriceService.swift`
- `Shared/GoldPriceModels.swift`

## 7. 建议的发布检查清单

- `Release` 构建成功
- 菜单栏面板正常打开
- 详情窗口正常显示
- `自动`、`Kitco`、`Gold API` 三种模式均已验证
- `RMB / g` 显示正确
- 小组件可被系统识别
- 安装包正确挂载
- 如果公开发布，签名和公证已完成
