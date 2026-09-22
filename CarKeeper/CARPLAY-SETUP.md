# CarPlay 配置完整教程（个人开发者账号）

> 适用于 `com.you.CarKeeper` 这个 bundle ID，步骤通用。

---

## 一、确认前提

| 项目 | 你的状态 |
|---|---|
| Apple Developer 账号 | 个人/组织账号均可（$99/年） |
| 项目已推送的代码 | ✅ `8a2aba4` 及之前全部已提交 |
| Xcode 版本 | ≥ 26.x（iOS 26.5 SDK） |

---

## 二、Apple Developer Portal 设置（共 3 步）

### 第 1 步：给 App ID 开通 CarPlay capability

1. 打开 [developer.apple.com/account](https://developer.apple.com/account)
2. 左侧 **Identifiers** → 找到 `com.you.CarKeeper`（或对应的 Bundle ID）
3. 点击进入 → 点 **Edit**
4. 在 Capabilities 列表里找到 **CarPlay**（搜索框搜 "car" 也行）
5. 勾选它 → 点 **Save**

> ⚠️ 如果列表里找不到 CarPlay：
> - 确认你签的是 **Wildcard** 还是 **Explicit** App ID。CarPlay 只支持 Explicit App ID。
> - 如果是 Wildcard，需要新建一个 Exact Bundle ID（如 `com.you.CarKeeper`），再绑定 CarPlay capability。

### 第 2 步：创建/更新 Provisioning Profile

1. 左侧 **Profiles** → **All**
2. 找到主 App 的 profile（`com.you.CarKeeper`）
3. 点 **Edit**
4. 在 Capability 列表里确认 **CarPlay** 已被勾选（第 1 步的变更会反映在这里）
5. 点 **Generate** → **Download**
6. 双击下载的 `.mobileprovision` 文件，Xcode 会自动安装它

> 扩展（CarPlay extension）不需要单独 profile，它继承主 App 的 profile。

### 第 3 步：确认 App Group 已配好

CarPlay 扩展需要读主 App 写入 `group.com.you.CarKeeper` 的数据。

1. 左侧 **Identifiers** → 找 `group.com.you.CarKeeper`（App Group 的 ID）
2. 如果不存在 → 点 **+` 新建 → 选 **App Groups** → Identifier 填 `group.com.you.CarKeeper` → Create
3. 回到主 App 的 Provisioning Profile → Edit → 确认 **App Groups** capability 已勾选 → Generate

---

## 三、本地 Xcode 设置

### 第 1 步：配置 Signing

1. 用 Xcode 打开 `CarKeeper/CarKeeper.xcodeproj`
2. 选中顶层项目 → 选 **CarKeeper** target → **Signing & Capabilities**
3. Team 选你的个人开发者账号
4. Bundle Identifier 确认是 `com.you.CarKeeper`
5. 勾选 **Automatically manage signing**

### 第 2 步：配置 CarPlay 扩展的 Signing

1. 在左侧 Navigator 找到 **CarPlay** target（注意是扩展，不是主 App）
2. 同样打开 **Signing & Capabilities**
3. 勾选 **Automatically manage signing**
4. Bundle Identifier 应该是 `com.you.CarKeeper.carplay`（project.yml 里已配好）

> ⚠️ 如果 Xcode 提示「No profiles for com.you.CarKeeper.carplay were found」：
> 回到 Portal → Profiles → 编辑主 profile → 确认 CarPlay 能力已加入 → 重新 Generate → 装回 Xcode。

### 第 3 步：把 CarPlay target 加入 Scheme

1. 顶部 Scheme 下拉 → **Edit Scheme...**
2. 左侧 **Run** → **Options**
3. 确认 **Enable CG Profile** 已勾选（这是调试用，不影响发行）
4. 点击 **Info** 标签 → 确认 CarPlay target 在 Build 列表里（通常会自动包含）

### 第 4 步：连接到 CarPlay Simulator（开发机测试）

1. 菜单栏 **Product** → **Destination** → 选 **Simulator** → 选任意 iPhone（iOS 18+）
2. 运行 App（⌘R）
3. 运行后，在模拟器里：**Hardware** → **External Displays** → **iPhone 16 Pro**（或其他支持的型号）
4. 新窗口弹出后，在 simulator 里打开 App → 车机屏幕应该显示地图 + 车况

> 如果没有 External Displays 菜单：Xcode 版本太旧，需要 ≥ 26.x。

---

## 四、真车测试（需要车机支持 CarPlay）

1. 用 USB 数据线把 iPhone 连到支持 CarPlay 的车
2. 在 Xcode 里选 **Your Physical Device** 作为运行目标
3. 点 Run（⌘R），Xcode 会把 App + CarPlay 扩展一起安装到手机
4. 车机屏幕上应该出现长安车管家图标
5. 进入后显示实时地图（车辆位置来自 `location` 缓存的 Lat/Lng）

---

## 五、常见问题

| 问题 | 原因 | 解决 |
|---|---|---|
| 车机上看不到 App 图标 | Profile 没包含 CarPlay capability | 重新 Generate profile |
| 车机图标在但页面空白 | App Group 权限未开通 | Portal 里确认 `group.com.you.CarKeeper` 存在且 profile 已勾选 |
| 地图钉显示在错误位置 | Lat/Lng 坐标系不对 | 车端报文是 GCJ-02，直接传入 MKMapKit 即可，无需转换 |
| 构建报 `entitlements not found` | project.yml 没加 `CODE_SIGN_ENTITLEMENTS` | 已修复（见 commit `8a2aba4`） |
| CI 构建成功但车上跑不起来 | 签名证书是 Development 而非 Distribution | 车机测试用 Development 签名即可；上架才需要 Distribution |

---

## 六、自签 App 能用 CarPlay 吗？

**能。** 个人开发者账号完全支持 CarPlay，不需要 MFi 认证（MFi 只针对硬件厂商）。

CarPlay capability 在 Apple Developer Portal 里对个人开发者开放，开通条件只有一个：
> 你的 App ID 必须支持 CarPlay（勾选对应 capability），且 Provisioning Profile 包含该能力。

本项目的 `CarPlay.entitlements` 里 `carplay-car-registration` 设为 `false`，这意味着：
- 你的 App **不会**出现在 Apple 的「认证车辆」清单里（这个清单是给 OEM 用的）
- 但在支持 CarPlay 的车上**完全可以正常运行**——大多数私家车/新能源车都支持第三方 CarPlay App

---

*本文档由代码生成，基于 2026-09-22 的项目状态。*
