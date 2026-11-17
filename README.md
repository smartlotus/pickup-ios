# Pickup for iOS & iPadOS

> 把日子，拾起来。 / Keep the little things.

基于原 Android / Web V2 日记应用 **Pickup** 深度重构并移植的原生 **Swift 6 + SwiftUI + iOS 26 Liquid Glass** 版本，专为 **iPhone 与 iPad** 打造，**无需 \$99/年 Apple 开发者账号、无需上架 App Store**。

## 核心亮点

- **iOS 26 原生液态玻璃（Liquid Glass）视觉语言**：严格保留 Pickup 标志性的 **纯黑白 (`#060606` / `#F4F3ED`)** 与 **紫黑 (`#121212` / `#7C4DFF`)** 双主题、**有机红笔圈 (`#F46862`)** 与 **复古怀表金 (`#C5A86A`)**，采用 `GlassEffectContainer`、`.glassEffect(.regular.interactive(), in:)` 与 `.tabBarMinimizeBehavior(.onScrollDown)`，同时对 iOS 18 提供多层高光降级材质。
- **iPhone + iPad 自适应架构**：
  - iPhone：浮动液态玻璃 `TabView` + 可形变快速拾起胶囊（写日记 / 手绘涂鸦 / 立即备份）。
  - iPad：自适应 `NavigationSplitView` 浮动侧边栏 + 双列网格卡片 + 硬件键盘快捷键（`⌘N`, `⌘1–⌘5`, `⇧⌘B`）+ PencilKit 随手涂鸦。
- **完整本地数据保险箱（Data Vault）与防 7 天签名丢失体系**：
  - **双向无损导入导出**：100% 兼容 Pickup Android / Web v2 `pickup-portable-backup` 标准 ZIP（iOS 扩展字段独立存储于 `ios-extensions.json`，确保 `backup.json` 严格过审）、`AES-256-GCM` 加密 `.pickupvault`、人类可读 Markdown 文集 `.md.zip` 与旧版 JSON 数组导入。替换导入前自动生成安全快照防误删。
  - **自动定时本地备份引擎**：支持每 6 小时 / 每天定时 / 每周 / 每次编辑后 / 退入后台，支持自定义保留份数（置顶快照永久保留）、`BGAppRefreshTask` 后台调度，以及通过系统 `UIDocumentPicker` 绑定外部安全目录（“文件” App / iCloud Drive / 局域网 NAS）。
  - **本地数据管理与体检**：字节级存储环形图、孤儿媒体扫描与一键清理、大体积媒体排行、缺失引用修复与安全重置。
- **核心四柱体验延续**：日记 Capture（实况照片 / 视频 / 音乐标注 / 心情天气标签 / 450ms 草稿自动保存）、红笔时间线 + 「往年今日」记忆回响、每日一次「去留 Revisit」偶遇写回、以及披露确认后仅传文字的 **AI Hub**。

## 免开发者账号安装方式（Zero \$99 Fee）

### 方式一：SideStore / AltStore（推荐，Wi-Fi 每 7 天自动续签）
1. 在 [Releases](https://github.com/smartlotus/pickup-ios/releases/latest) 下载 `PickupIOS.ipa`。
2. 手机安装 SideStore 或 AltStore，导入 `PickupIOS.ipa` 并使用免费个人 Apple ID 签名安装；开启后台 Wi-Fi 自动续签。
3. 首次打开后，立即在「数据」标签页绑定一个「文件」App 外部文件夹并开启每日自动备份。

### 方式二：Sideloadly 电脑一键安装
1. 在 macOS 或 Windows 下载 Sideloadly，连接 iPhone / iPad。
2. 拖入 `PickupIOS.ipa`，填入免费 Apple ID 即可签发安装。

### 方式三：Xcode 源码直装（仓库已内置预生成 `PickupIOS.xcodeproj`）
1. 克隆本仓库并用 Xcode 打开预生成的 `PickupIOS.xcodeproj`（或运行 `xcodegen generate`）。
2. 选择 `PickupIOS` 靶标 → `Signing & Capabilities` → `Team` 选择你的免费 `Personal Team`（已移除 Push/CloudKit 等付费权限），插线直装至真机。

### 方式四：云端 GitHub Actions (`macos-26` + Xcode 26) 自动构建无签名 IPA 与实机截图
如果你本地没有安装 Xcode，可授权一次 `workflow` scope 并启用仓库内附带的云端工作流 [ci/ios-ci-release.yml](ci/ios-ci-release.yml)：

```zsh
gh auth refresh -h github.com -s workflow
bash scripts/enable_cloud_ipa_ci.sh
```

## 本地核心测试

```zsh
swift test
```

## License

MIT — Copyright © 2026 Zhuyouqian & Pickup contributors.
