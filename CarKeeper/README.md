# 长安车管家（iOS 原生版）

由微信小程序 `ChangAnMiniProgram` 移植而来的原生 iOS App。

- **技术栈**：Swift 6 + SwiftUI，最低 iOS 26.0
- **网络**：直连长安官方接口（不再走云函数代理）
- **设计**：遵循苹果 HIG（系统配色 / SF Symbols / 原生控件 / 深浅色自动适配）
- **构建**：GitHub Actions 出未签名 ipa，你用自签工具安装

## 目录

```
CarKeeper/
├─ project.yml                    # XcodeGen 工程配置
├─ .github/workflows/ios-build.yml
└─ CarKeeper/
   ├─ CarKeeperApp.swift          # @main 入口 + 路由
   ├─ AppStore.swift             # @Observable 全局状态
   ├─ Models/                    # 数据模型 + 视图模型 + 分析层
   ├─ Services/                  # API 直连 / MD5 / 原始日志
   ├─ Design/                    # 设计系统（主题 / 组件）
   ├─ Features/                  # 10 个功能页
   └─ Resources/                 # Assets / Info.plist
```

## 功能移植对照

| 小程序 | iOS 实现 |
|---|---|
| 云函数 changanProxy | **移除**，URLSession 直连（keep-alive 解决 CDN 节点绑定） |
| 登录（手机/图形/短信） | `LoginView`（异步加载图形码 + 60s 倒计时 + 安全重试） |
| 车况首页 | `HomeView`（SOC Hero + 8 域状态 + 30s/8s 轮询 + 快控） |
| 车控 | `ControlView`（锁/解锁 + 指令 + PIN 数字键盘 + 温度 Stepper + 轮询） |
| 消息 | `MessagesView`（日期分组 + 就地展开 + 分类标签） |
| 我的 | `MineView`（用户卡 + 车辆卡 + 常用入口 + 退出登录） |
| 车辆档案 | `VehicleView`（名片 + 分组行 + VIN 复制） |
| 健康报告 | `HealthView`（评分圆环 + 系统手风琴） |
| 电池与充电 | `BatteryView`（Swift Charts 柱图 + 充电会话 + 故障码 + 告警） |
| 全量数据 | `DataView`（8 种 kind + 复制 + 刷新） |
| 开发者工具 | `DevView`（网络通道 + 请求日志 + 排查指引 + 清缓存） |

## 本地构建

```bash
cd CarKeeper
brew install xcodegen
xcodegen generate
open CarKeeper.xcodeproj
```

Xcode 中把 signing 切到你的 Apple ID（Your Personal Team），选一个已配置的 App ID 即可真机调试。

## 未签名构建 + 自签安装（GitHub Actions）

1. 推送仓库到 GitHub，Actions 自动跑 `ios-build.yml`（也可手动 workflow_dispatch 触发）。
2. 构建产物为 `CarKeeper-unsigned.ipa`（`CODE_SIGNING_ALLOWED=NO`，无描述文件）。
3. 下载 zip，解压得 `CarKeeper-unsigned.ipa`。
4. **自签安装**（二选一）：
   - **AltStore（推荐，Mac 端）**：打开 ipa → 登录你的免费 Apple ID → 安装；
   - **SideLoader（无 Mac）**：iOS 上接收 ipa → 登录 Apple ID → 安装。
5. 安装后在 iPhone「设置 → 通用 → VPN 与设备管理」里**信任**该开发者证书。

### 7 天续期

免费 Apple ID 签名的 App **7 天过期**。到期后：

- 重新触发 Actions（手动或定时）拿新 ipa → 重新自签安装；
- 或 AltStore 配置**自动刷新**（需 Mac 常开或定期开机）；
- 若 7 天后未续期，需删除重装并重新信任。

### 可选：开发证书签名

为让 ipa 安装后更稳，可用你的免费 Apple ID 在 Xcode 生成一个**开发描述文件**，上传为 Actions secret（`DEV_CERT_P12` / `P12_PASS` / `PROVISION`），workflow 会改为带描述文件的 ad-hoc 构建。默认仍走纯未签名 + AltStore 重签路径。

## 网络说明（直连）

- 域名：`scrm.changan.com.cn`（登录/刷新/验证码）+ `m.iov.changan.com.cn`（车辆数据）
- 直连无白名单限制（iOS 原生）；`URLSession` 默认 HTTP/2 + 连接复用，`picSend` 与 `smsSend` 大概率命中同一 CDN 节点。
- 仍保留「无记录安全重试一次」「码不匹配不重试」语义，避免重复发短信。
- `RawLogStore` 记录请求/响应原文（内存 60 条 + NSLog），开发者页可查看/复制。

## 需要替换的占位

- `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER: com.you.CarKeeper` 改成你自己的反向域名。
- 若用开发证书签名，把描述文件上传为 secret。

## 已知限制

- 免费 Apple ID 7 天过期；
- `Map` 车图（长安缩略图 URL）用 `AsyncImage` 加载，失败时隐藏；
- 真机需在联网环境下首次登录（图形验证码异步拉取）；
- 无推送（小程序原本就没有 APNs）。
