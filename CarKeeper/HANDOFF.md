# HANDOFF —— 长安车管家（iOS 原生版）

> 这份文档写给**下一个接手的人**（人或 agent）。目标：不读代码也能知道「现在有什么、东西在哪、
> 为什么这么做、改的时候会踩什么」。所有数字与路径都是 2026-09-23 在 `main` 上核对过的实测值。
>
> 它不替代那几份专门文档（见 §12 文档地图），而是把它们串成一条可执行的路径。

---

## 0. 30 秒入门

| 项 | 事实 |
|---|---|
| 是什么 | 长安车联网官方 App 的 **iOS 原生重写**：车主查看车况、远程车控、充电、行程、保养 |
| 后端 | **没有自己的后端**。App 直连长安官方接口（`m.iov.changan.com.cn` / `scrm.changan.com.cn`） |
| 技术栈 | SwiftUI · iOS 26.0+ · `@Observable` · MapKit · Swift Charts · AppIntents · CryptoKit · LocalAuthentication |
| 规模 | **71 个 Swift 文件 / 21,706 行**（`CarKeeper/` 下），2 个 target（`CarKeeper` + `CarKeeperTests`） |
| 构建 | **XcodeGen**：`CarKeeper/project.yml` → `CarKeeper.xcodeproj`（`xcodeproj` 不入库） |
| 交付 | GitHub Actions 出**未签名 ipa** → 侧载工具自签安装（7 天续期） |
| 参考实现 | `ChangAnMiniProgram/`（微信小程序原版，本次重写的移植来源） |
| 设计原型 | `design-preview/`（8 个自包含 HTML 预览页，挑版式时用） |

### 唯一的硬约束：免费（未缴 99 美元）个人开发者账号

这一条决定了大量取舍，**接手的第一个小时必须先接受它**：

| 能力 | 状态 | 后果 |
|---|---|---|
| App Group | ❌ 拿不到 | 小组件 / 表盘 / 灵动岛**整条链路已删除**（含界面、target、entitlements） |
| CloudKit / HealthKit / WeatherKit / StoreKit / Family Controls | ❌ | 已删（`scan/paidcap.py` 门禁守着不许回来） |
| BGTaskScheduler | ❌ | 后台刷新已删，调用会抛 ObjC 异常直接杀进程 |
| CarPlay / App Clip | ❌ | target 已删（App Clip 还额外需要备案域名 + associated-domains） |
| MapKit 显示地图 | ✅ 可以 | **但不能提供路线导航**（无 ADP 成员资格做不了 MKDirections） |
| 通知 / 定位 / 相机 / 相册 / FaceID | ✅ | 正常，`project.yml` 里已声明用途字符串 |

---

## 1. 怎么跑起来、怎么验证

### 1.1 本机（Windows 开发机）的真实处境

**这台开发机上没有 Swift 工具链**（`swift` / `swiftc` / Xcode 都不存在）。因此：

- **编译只在 CI 上发生**。本地唯一能做的验证是静态门禁 + 风格检查 + `bash -n`。
- 改完必须看 CI 日志才能知道「编不编得过」。这也是仓库里为什么会有 23 项门禁（§8）。

```bash
# 本机可跑的全部验证（在仓库根）
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
node CarKeeper/check_style.js
for s in delguard paths design keys access lexguard scan logic shadowguard scenes \
         targets unreachable futureproof orphans deep eol oneentry traps \
         scopeguard paidcap copy lintcfg ternary enumguard; do python3 scan/$s.py; done
```

> `delguard.py` 比的是「上一次提交 vs 现在」——它在本地看的是**你手上还没提交的改动**，
> 在 CI 上看的是这次提交。它专门盯「声明被删/重写了、使用还在」（两次真实事故都是它）。

### 1.2 在 macOS 上构建（或照 CI 抄）

```bash
cd CarKeeper
xcodegen generate                    # 由 project.yml 生成工程
xcodebuild build \
  -project CarKeeper.xcodeproj -scheme CarKeeper \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -quiet
```

### 1.3 CI（`.github/workflows/ios-build.yml`）

两个 job，顺序依赖：

1. **`static-gate`**（ubuntu，秒级）：`check_style.js` + 23 项 `scan/*.py`。**任一红即整体失败**。
   （它的 checkout 要 `fetch-depth: 2` —— `delguard.py` 需要 `HEAD~1` 才比得出「这次提交改掉了什么」。）
2. **`build-unsigned-ipa`**（macos，约 3 分钟，额度按 10 倍计费）：XcodeGen → xcodebuild → 打 `Payload/` zip 成 ipa
   → **IPA 内容体检**（只打印顶层结构，`|| true` 不阻断）→ 上传 artifact → 覆盖发布到 tag `latest` 的 Release（App 内「检查更新」从这里下载）。

> 为什么静态门禁值得这么重：一个编译错误要花掉一整轮 macOS runner。**每一条能搬进静态检查的判据，
> 都把 3 分钟 + 10 倍额度换成一次秒级检查**。§8 的表里每一条都标注了它是哪次真实事故的产物。

### 1.4 签名与安装（为什么 ipa 是「未签名」的）

免费账号不能走 TestFlight / App Store 分发。当前路径是：CI 产出未签名 ipa → 用侧载工具（如 AltStore / Sideloadly）
或 Xcode 用**自己的 Apple ID** 重签后安装，**每 7 天到期需重签**。`README.md` 里有逐步说明。

---

## 2. 全局架构

### 2.1 分层（自下而上）

```
┌ 网络层  Services/API.swift          APIClient（9 个端点）+ TokenStore（Keychain）+ Retrier
├ 模型层  Models/ApiModels.swift      报文 → 可渲染结构（EnergyModel / HealthModel / ……）
│         Models/ViewModels.swift     enum VM：纯计算，从 [String: Any?] 取出界面要的值
│         Models/Analysis.swift       enum AN：8 域 verdict + overall 结论
├ 状态层  AppStore.swift              @MainActor @Observable 单例：登录态 / caches / 命令历史 / 本机累积
├ 设计层  Design/Tokens → ArtTheme → DS → Charts / SkyLight / SkyOverlay / MapStyleSpec / DSSwipeStrip
├ 界面层  CarKeeperApp（入口 + NavState）→ MapShellView → MapSpineView（唯一的屏）→ 6 档页面
└ 服务层  Services/*.swift            通知 / 提醒 / 健康钥匙 / 加密 / 采样 / 天气 / 更新 / 估值……
```

### 2.2 导航模型：**一个屏 + 一条模式条**

这是整个 UI 最重要的约定，**违反它会被门禁拦住**（`scan/oneentry.py`）。

```
MapShellView（唯一的屏）
  └ NavigationStack(path: $nav.path)     ← path 永远是空的（全库不再 push 功能页）
      └ MapSpineView                     ← 六页同屏（pageDeck）+ 一条底条
          ├ 「现在」那一页：地图铺满全屏（画到屏幕最上沿）+ 车牌徽标（点开是菜单：
          │                 图层 / 重取数据 / 此刻的光 / 回到车）+ 浮动两卡
          ├ 其余五档：整屏的不透明页，卡片窗停在条子上沿（ArcStack 叠叠乐）
          └ 底部一行：左臂（车牌前两字）｜模式条（DSSwipeStrip）｜右臂（快捷车控）
```

（这一格曾经写的是「顶部：图层胶囊 + 工具栏（搜索 / 图层 / 定位 / 分屏）」+
「贴底的一张纸」——那张纸已按原型拆成整屏的六页，顶栏也已收进车牌徽标的菜单；
全局搜索整体删除，右臂现在一键发车控指令。）

**换档不换屏**：地图与纸的位置、高度、底色在 6 档之间完全不变，变的只有纸里装的内容。
这条是从相机 App 的模式条学来的，`DSSwipeStrip` 就是那条条子（可手拖、跟手、吸附、中心项放大）。

#### 一级：6 个功能档（`HomeMode`）

| 档 | 页面 | 深链 | 说明 |
|---|---|---|---|
| `now` 现在 | 地图本身（4 图层） | —（无独立页） | 默认档；`MapSpineLayer` 是它的二级选择 |
| `vehicle` 车辆 | `VehicleView` → 档案 / 健康 / 保养 | `.vehicle` / `.health` / `.service` | 三段回答同一个问题：这辆车怎么了 |
| `charge` 充电 | `ChargeView`（含目的地计算器） | `.battery` | 充电 + 电池 + 趋势 |
| `control` 车控 | `ControlView` | `.control` | 指令、车身明细、PIN、历史 |
| `trips` 出行 | `TripsEventsView`（时间轴 + 评分 + 消息） | `.trips`（别名 `.score` / `.dashboard` / `.parking`） | |
| `mine` 我的 | `MineView` → 设置 / 应急 / 诊断 | `.mine` / `.emergency` / `.dev` | |

- 顺序按**使用频率**排，不按功能分类。
- `HomeMode.storageKey = "carkeeper_home_mode"`（`@AppStorage`）→ 重启回到上次那一档。
- 档内段落见 `HomeSub`（车辆：档案/健康/保养；我的：设置/应急/诊断）。它不是导航层级，
  **没有第二层返回按钮**；深链落到哪一段由 `HomeMode.destination(for:)` 决定。

#### 二级：「现在」档内部的 4 个地图图层（`MapSpineLayer`）

`now` / `trips` / `holds` / `charge` —— 每一个是**一个真实问题**（车在哪 / 去过哪 / 停在哪 / 去哪充电），
不是地图图层分类。持久化键 `carkeeper_map_layer`；`MapSpineLayer.makeCurrent()` 让别处也能把地图开到某一层。

#### 深链（`carkeeper://`）

`Deeplink` 12 个 case（见 `CarKeeperApp.swift`）。`CarKeeperApp.openDeeplink` → `NavState.openMode(for:)`
→ 写 `HomeMode` 键 + 清空栈。**深链也不准开出「第二份页面」**——这是历史上最容易反复长回来的地方。

#### 唯一的去功能入口

```swift
NavState.shared.openMode(_ mode: HomeMode, sub: HomeSub? = nil)   // 去功能只有这一种走法
```

`path` 恒为空，`popToRoot()` 仍保留只是为了让收尾逻辑能表达「回到地图」。
`Notification.Name` 里只有 4 个通知，且**每一个都真有发射点**（`.pinConfirmed` / `.tempConfirmed` /
`.didLogout` / `.locationUpdated`）；历史上「有名字、没发射」的 5 个导航通知已删。

### 2.3 数据流（从接口到屏幕）

```
用户操作 / 定时器
   ↓
APIClient（9 个端点，POST 带 token）── Retrier.global 自动重试（幂等请求）
   ↓  原始 JSON（[String: Any]）
AppStore.gather(carId:includeMessages:includeCheck:)
   ↓  6 个数据源**并行**（withTaskGroup）
AppStore.saveCache([key: value])
   ├ caches[key] = value（nil = 这次没取到 → 清空，界面显示「没取到」）
   ├ messages → ingestEvents() → 行程（唯一行程生成器）
   ├ charge → recordEnergySnapshot + HistoryStore.record（SOC / 功率 / 胎压三条曲线）
   ├ 全部失败且已登录 → isOfflineMode = true
   └ location 移动 > ≈5.5 m → post(.locationUpdated)（镜头跟随 / 重取天气 / 低电量提示）
   ↓
VM.energy / VM.bodyStatus / VM.tyreStatus / VM.locStatus / AN.summarize …（纯计算，无副作用）
   ↓
界面（`MapSpineView` 与各档页面）
```

**关键决定：`AppStore.caches` 不是缓存。** 它只装「刚刚那一次接口响应」——
不做 TTL、不跨启动落盘、失败不保留旧值。因此界面上的每个数字都能追溯到一次真实响应；
某个源这次没取到，界面就显示自己的空/失败态。

> 历史上这里有一整套「缓存思维」：`cacheTTL = 180s`、`needsRefresh`、`isCacheExpired`、`staleKeys`、
> 「网络异常，显示缓存数据」、失败保留旧值。**2026-09-23 全部删除，且不要加回来**——
> 它带来的正是「看着是数据、其实早过期」。这条改动涉及 `AppStore` + 各页的 `loadIfNeeded`。

**本机累积（唯一允许落盘的一类）**：SOC / 充电功率 / 胎压三条曲线（`HistoryStore`，5 / 1 / 30 分钟采样），
行程与停车史、保养里程、保险年检、账本类记录 —— 原因是**服务端只有「当前状态」接口**，历史无处可取。
这类数据的取舍必须显式做（见 §6）。

---

## 3. 网络层（`Services/API.swift`）

### 3.1 端点表（9 个，全部实测）

| 方法 | 端点 | 返回 | 进哪个 cache 键 |
|---|---|---|---|
| `smsSend` | `scrm.changan.com.cn/app-m/prod-api/auth/cac/smsSend` | 发短信验证码（不重试） | — |
| `getPicCode` | 同上 `/picSend`（GET 二进制，MIME 嗅探） | 图形验证码图片 | — |
| `login` | 同上 `/appLogin` | token | —（写 Keychain） |
| `getCars` | `m.iov.changan.com.cn/appserver/api/car/getMyCars?isNev=1` | 车辆列表 | `cars` |
| `getUser` | `/appserver/api/user/getUserInfoByToken` | 用户 | `user` |
| `getCarCheck` | `/appserver/api/carcheck/getCheckResult?carId&isNev=1` | 体检报告 | `check` |
| `getCarPm25` | `/appserver/api/car/pm/getCarPm25ByCarId` | 车内 PM2.5 | `pm25` |
| `getCharge` | `/appserver/api/charge/info` | 电量 / 充电 | `charge` |
| `getControl` | `/api/car/getControlStatus` | 车身状态（门/窗/锁/胎压/里程） | `control` |
| `getControlInfo` | `/api/car/getControlInfo?carId&id=taskId` | 指令执行结果（轮询） | — |
| `getLocation` | `/appserver/api/cardata/getCarLocation?mapType=GCJ02` | 位置（Lat/Lng/Heading） | `location` |
| `getMessages` | `/appserver/api/information/pageReceiverInfoByTime?actionType=2&limit=2000` | 事件流 | `messages` |
| `sendControlCommand` | `/api/car/control?pin&cmd&carId`（**不重试**） | 指令受理 | — |
| refresh | `…/auth/cac/refresh` | 新 access_token | —（写 Keychain） |

### 3.2 Token 与安全

- **Token 存在 Keychain**（`TokenStore`，`kSecAttrAccessibleAfterFirstUnlock`），不再放 UserDefaults：
  实测证明 `refresh_token` **不轮换**（`expires_in: 86400`），泄露即长期可用；而 UserDefaults 会进 iCloud 备份。
  首次读取会把旧 UserDefaults 里的令牌**迁移进 Keychain 并删掉明文**（用户无感）。
- `TokenStore.clear()` 同时删 Keychain 与旧 UserDefaults 键（退出登录必须两处都删）。
- `DataEncryption`（CryptoKit AES-GCM + Keychain 密钥）用于车牌等敏感字段；`SecureStorage` 是它的封装。
- 人类可读的报文日志走 `RawLogStore`（键 `changan_raw_log`），用于排障。

### 3.3 重试与刷新

- `Retrier`（指数退避 + 抖动）：默认 4 次 / 1s 起 / ×2 / 上限 8s / 抖动 0.3；另有 `.aggressive`、`.dataReliable`、`.none`。
- **有副作用的 POST 必须 `retryable: false`**（车控指令、发短信）——重复下发是真实危害。
- token 刷新用 `AtomicTaskHolder` **并发去重**：同一时刻 N 个请求过期只刷一次。

### 3.4 报文解析的两条铁律

1. **键一律首字母小写**（实测：`remainPower` / `totalOdometer`）。Swift 的 `[String: Any]` 下标大小写敏感，
   写成 `["RemainPower"]` 就是**永远 nil**，而 nil 经 `num()` 又常变成 `0` → 界面显示成一种「正常状态」。
   读取一律走 `ci*` 家族（`ciString` / `ciNumber` / `ciBool` / `ciArray` / `ciObject` / `ciVal` / `ciPick`）。
   **`scan/keys.py` 在 CI 上拦这条。**
2. **没有的键不许编值**。界面缺数据时显示 `--` 或一句「未上报」，不用默认值填空。
   （历史事故：预计充满时间读的是根本不存在的 `ChargPower` / `ChargingPower`，于是那个数字永远是空的。）

---

## 4. 界面逐项

### 4.1 地图主屏（「现在」档）—— 全 App 唯一的屏**文件**：`Features/Map/MapSpineView.swift`（1203 行，骨架：六页同屏 / 底条 / 浮动两卡 / 图层胶囊）、
`MapSpineLayers.swift`（139 行，「现在」那一档四个图层各自的内容 —— 2026-09-23 拆出，
理由见那里的文件头）、`MapSpineData.swift`（数据层）、`MapCarPin.swift`（车钉）、
`HomeModeHead.swift`（巨字头：只给**一个**事实 + 一行小字，依据在下面每一张卡里）。

**骨架（2026-09-23 按原型 `design-preview/stack.html` 重排过）**：一张全屏 MapKit 地图，
上面只摆原型里本来就有的东西 —— **底部浮动两卡**
（`.float`：底边离屏底 98pt、卡间 12）+ 地图自己的**罗盘**与**比例尺**。
**这一档没有导航栏**（`.toolbar(.hidden, for: .navigationBar)`）：地图一直画到屏幕最上沿。

**车牌徽标不在图上了**（2026-09-24，用户：「地图页顶部的信息也挪动到下面的玻璃卡片」）：
它原来挂在左上（安全区下 8pt）。**信息**（车牌 + 状态 + 上报时间）已搬进浮动首卡的卡头
（`nowHead`）；**菜单**（四个图层 / 重取数据 / 此刻的光 / 回到车）变成卡头上那枚图层胶囊
（`layerMenu`）。搬进卡里比浮在瓦片上更准：徽标只能用重阴影把字从底图里抬出来，
卡里它就是正文，遮罩与对比度都由玻璃负责。

**底图上因此没有任何压暗层**（同一条要求的另一半）：原型 `.maptop{height:240px}`（0.72）
与 `.mapvig{inset:0}`（四角压暗）**都已删**；`SkyOverlay` 里那条「顶部压暗」也删了 ——
它不住在地图上，它住在根画布的 `haze` 里，压的是**每一屏**的顶上（用户看到的
「其他页面的暗层」就是它）。删得掉的理由是同一条：`.maptop` 当初只为给车牌徽标铺底，
而顶栏早在它之前就变成了玻璃 —— 一条占半屏的压暗去服务一个已经有底的控件，是纯亮度损失。

**浮动两卡**（顺序就是读的顺序）：

| 卡 | 头 | 内容 |
|---|---|---|
| 现状卡 `nowCard` | 车牌 + 状态 · 上报多久了（原先挂在图上的徽标）+ 图层胶囊菜单 | 地址（大字）→ 巨字**续航**（`DSBigNumber`）→ 副行（表显 · 充不充电）→ 光带 |
| 四格读数 `readoutChips` | 无 | 车速 / 电量 / 胎压（取四轮里**最低**那条）/ 车锁，**同一行、同一基线**（原型 `.chip:nth-child(odd)` 的 ±7px 错位已删 —— 用户 2026-09-24：「下面 4 个按钮要规整，不要歪歪扭扭」） |

**卡头那枚图层胶囊同时是这一屏的菜单**（`layerMenu`，`Menu`）：四个地图图层（当前那层带勾）、重取数据、
此刻的光（`skySheet`）、回到车；iPad 上多一项「新车况窗口」。
把这几件事收进菜单是**结构**上的选择：原型首页只有「车牌 + 两卡」，每多一枚钮就不像它了。
那一屏多出来的四样（图层选择卡、常驻操作条、光名药丸、回到车浮钮）与顶栏三枚钮就是这么收掉的。

**图层选择现在在菜单里，不是一张卡**：图上仍然四个图层，换层时浮动首卡换成那一层的内容
（`tripsContent` / `holdsContent` / `chargeContent`），所以「看图上的哪个问题」与「读它的数」
还是同一张卡。**刻意没有照搬**「左右滑取景框换模式」——地图的横向拖拽是平移，
抢掉它比少一个手势糟得多。

**四个图层各自画什么、数据从哪来**：

| 图层 | 图上元素 | 数据来源 | 空态文案 |
|---|---|---|---|
| `now` | 车钉 + 续航范围圈 + 异常钉 | `location` + `control` + `VM.energy` | 还没收到位置上报 |
| `trips` | 每段行程的**起终点连线**（`MapTripLine`） | `store.tripHistory` | 还没有行程记录 |
| `holds` | 常停点 + 热区圈（`MapHotspot`，聚类） | `store.parkingHistory` / `parkingPoints` | 还没有停车记录 |
| `charge` | 附近充电站（`MKLocalSearch` + 聚合 `MapChargerCluster`） | 现场搜索 + 充电会话 | 正在搜索附近充电站 |

**换层时首卡里的内容**：`tripsContent` / `holdsContent` / `chargeContent`，都在 `MapSpineView` 内，
各自有 `emptyNotice`（取不到就说取不到，不摆占位）。

**车钉（`MapCarPin`）**：四种画法对四个艺术方向 —— 夜光（刻度盘 + 弧形 + 发光 + 接地阴影）、
纸上（墨线圈，无发光无阴影）、巨字（发丝环 + 十字准线）、原生。车头朝向由 `Heading` 驱动。

**那个常驻操作条已经不在了**（`MapQuickBar.swift` 已删，2026-09-23）：它那 4 个动作
（锁车 `LockDoor` / 解锁 `UnLockDoor` / 空调 `OpenAir` / 寻车 `RemoteSearchCar`）与验 PIN / FaceID
在**车控那一档**一模一样地存在（同一套 `CommandCenter`）。这符合全站那条“同一功能只有一种存在方式”：
首页是一条取景框 + 一条模式条，不再兼任控制台。

**镜头**：`focusOn(_:)` / `centerOnCar(force:)`；`AppStore.mapFocus` 是跨页请求「把地图移到某点」的唯一通道。

**已知的数据缺口（界面照实说明，不补假数据）**：
- 行程**没有 GPS 轨迹点**（`TripRecord` 只有起终点两个坐标）→ 画的是直线，不是实际路线。
- 异常**没有发现地点** → 只能挂在车当前位置，文案写「发现时车在这儿」。
- 充电站**没有功率/价格**（那是第三方数据源的事）。

### 4.2 车辆档 —— `VehicleView`（档案 / 健康 / 保养）

三段共用一个分段控件，**不是三个页面**（此前它们是条子上的三格，而三格回答的是同一个问题）。
分段控件与那一叠卡表就住在 `VehicleView` 里（无外壳）：分段的**状态**在页面里，
卡表就必须在同一个视图里 —— 拆到外壳里过，代价是编译错 + 页内的 `@State` 永不被安装。

- **档案 `VehicleView`**：身份区（车牌/VIN/车型，点字段可复制）+ 档案分组 + 维保照片（`PhotoPickerSheet`）
  + **车辆提示 `VehicleTipsSection`**（从这辆车的读数推出的提示，按 `TipCategory` 过滤）
  + **里程日志 `MileageJournalSection`**（含费用记录）。
- **健康 `HealthDataView`**：综合评分 + **故障码** + 检测系统（逐项可展开）+ **原始字段 `RawDataSection`**
  （结论与依据同源，所以原始数据没有再单开一页）。语义映射把 `AN` 的结论翻译成颜色与词。
- **保养 `MaintenanceMoneyView`**：统计卡 + 即将到期 + 年份筛选 + 时间线 + 添加记录；
  还装着 **`InspectionSection`（年检）**、**`VehicleValuationSection`（车辆估值）**、**`ExportDataSection`（导出）**。

数据来源：`cars` + `control` + `check`（体检）。深链：`.vehicle` / `.health` / `.service`。

### 4.3 充电档 —— `ChargeView`（2026-09-23 从零重写）

旧 `BatteryView` 的问题不是排版，是**它同时是五个页面**（充电/电池健康/故障码/账本/计算器）。
新页只有三件事，顺序就是看的顺序：

1. **充电**：还在不在充、功率、还要多久（`chargeHero` + `chargeDetail`）。
   **充电功率的唯一算法**是 `VM.chargePowerKW = totalVoltage × totalCurrent`（报文里没有 `ChargPower` 键）。
2. **电池**：一致性（单体电压 / 温度探针柱图 + 统计）、绝缘电阻、电压/温度采样子系统、动力电机、电池告警。
   电池域的结论只取 `AN.summarize` 里 `battery` 那一域，**其余五域归体检**（同一句话不在两页各说一遍）。
3. **趋势**：SOC 与充电功率两条曲线（`DSTrendChart`），周期 24 小时 / 7 天 / 30 天。
   数据来自 `HistoryStore` 的**本机采样**（服务端不提供历史），不足两个点时显示「正在积累数据」而不是空图。
4. **目的地续航计算器 `DestinationCalculatorSection`**：按当前续航留 15% 余量判断够不够。

不在这里的东西：故障码、综合评分 → 体检；**充电账本（花了多少钱）整条链路已删除**（无账单接口，
算法是本机积分度数 × 手填电价）。

### 4.4 车控档 —— `ControlView`（1103 行）

- 头部：读数就在车上（一屏不堆卡片）+ `CarTopView` 俯视示意图（薄线描，不着色）。
- 车身明细：门 / 窗 / 后备箱 / 锁（`VM.bodyStatus`）。
- **快捷预设场景**：如「夏天上车」（`OpenAir` + 26℃）、「冬天上车」（18℃）、「离车」（`LockDoor`）。
- 指令列表 + **执行中**状态 + **记录**（`AppStore.commandHistory`，最多 50 条）。
  指令结果三态：成功 / 失败 / **未确认**（60 秒没等到终态，或服务端状态值不认识）——
  「未确认」不是「失败」，这是刻意的。
- 交互：`PINKeypadView`（玻璃化数字键盘）、`ACStepperView`（温度弹层）、`SiriShortcutsCard`。
- **验证那道门只有一处：`ControlCommandFlow`（`Features/Control/ControlCommandFlow.swift`）。**
  一条指令要走完 温度 → 生物识别 → 控车码 → 下发 四步，而发起处只做一件事：
  `request = ControlRequest(key:name:)`。
  现在挂它的有两处：这一页（`onCmd` / `onPresetScene`）与**地图右臂的快捷车控**。
  此前地图那条路直接调 `AppStore.sendControlCommand`（拿 Keychain 里存的旧码就发）——
  同一个动作两套强度，安全的那条形同虚设（用户 2026-09-24 的原话：
  「右下角的控车选了后不用输入密码？不用选温度？」）。
  **加第三个车控入口时也要挂它**，不要另写一遍验证。
  故意不过这道门的只有一条：`UpCarCondition`（刷新车况）—— 它不改车状态，
  只是把车端叫醒一次；门的成本是用户手输控车码，只该收在会改变车状态的动作上。
- 执行链路：`CommandCenter` 负责发起 → 轮询 `/api/car/getControlInfo` 到终态 → 收尾（写历史、提示）。
  视图生命周期绑定在 `CommandCenter` 上，避免「页面关了指令还在轮询」或相反。
  在地图上发起的指令把它当**回执落地处**：地图只看 toast，详细结果留在车控页的结果 sheet。

### 4.5 出行档 —— `TripsEventsView`

**一屏三节**（此前是三个独立页面/深链）：

- **行程时间轴**：`store.tripHistory`，每段带 `MiniTripMap`（起终点小图）+ 里程/时长/能耗
  （能效用**每 1% SOC 多少 km**，因为 `capacity` 是 null，kWh/100km 算不出来）。
- **驾驶评分 `ScoreSection`**：三个维度（续航达成 / 读数一致 / 稳定），**算不出来就是 nil**，
  不装成「没有这回事」；页面末尾还写明「这一页量不出来的东西」。
- **消息 `MessagesSection`**：车的事件流（点火 / 熄火 / 告警…），分段控件 + 标签胶囊过滤。
  事件流同时是**行程生成的唯一数据源**。

`.parking` / `.score` / `.dashboard` 都是别名 → 落到同一页。

### 4.6 我的档 —— `MineView`（设置 / 应急 / 诊断）

- **设置 `MineView`**：Apple Profile 风格身份卡 + 车辆卡（切车 `selectCar`）+ 设置分组（退出登录、
  检查更新） + **家庭管理 `FamilyManagementView`**、**临时钥匙 `TempKeyListView`**、
  **隐私面板 `PrivacySection`**、**月报 `MonthlyReportSection`**、Siri 卡片入口、真开关（低电量省电 / 夜间模式）。
- **应急 `EmergencyPanel`**：SOS 按钮 + 快捷操作 + 紧急联系人 + 位置共享 + 紧急叠加层。
  代价说明：从「1 次拖动」变成「1 次拖动 + 1 次点击」，但 SOS 也仍然在地图操作条上。
- **诊断 `DevView`**：色板 / 字体 / 令牌数值 / 运行状态 / 能力位图（`car.funCode`）+
  **艺术主题入口 `ThemeGallerySection`**（主题画廊住在这里，不占档位）。

### 4.7 不是档位的屏（各有一处入口，不再重复）

| 屏 | 怎么到 | 说明 |
|---|---|---|
| `SplashView` | 冷启动 1.5 秒 | 之后再判断进登录 / 引导 / 主屏 |
| `OnboardingView` | 未登录且没看过引导 | 键 `carkeeper_onboarding_seen` |
| `LoginView` | 未登录 | 手机号 + 短信码 + 图形码；`TokenStore.save` 后进主屏 |
| `GlobalSearchHUD` | 地图工具栏 / 我的 | `fullScreenCover`（不是 sheet）；搜页面、车牌、行程、指令；空态文案分「还没输」与「没匹配」两种情况 |
| `BiometricLockOverlay` | 敏感页二次验证 | `RemoteLockManager` 后台超时自动隐藏 |
| `ThemeGallerySection` | 诊断档 | 4 个艺术方向 + 小界面样本，切换立即生效 |
| `PrivacyDashboardView` | 我的 | 三类：留在本机的 / 离开本机的 / 没在收集的 |

---

## 5. 设计系统

### 5.1 四层，严格单向

```
Tokens（静态令牌，唯一来源） → ArtTheme（4 个方向 = 一整套取值） → DS 原语（唯一容器/分组形态） → 页面
```

- **`Design/Tokens.swift`**：`TokensPalette`（颜色）/ `TokensSpacing`（4 的倍数，页面边距 20）/ `TokensRadius` /
  `TokensTypo`（字号）/ `TokensMotion` / `TokensHaptic` / `TokensHair`（发丝线）/ `TokensSize` / `TokensSerif` / `TokensTracking`。
- **`Design/DS.swift`**（1077 行）：唯一一套容器与排版原语 —— `DSCanvas`、`DSCard`、`DSGroup`/`DSGroupRow`、
  `DSSection`（唯一的分组形态，inset-grouped）、`DSKeyValueRow`、`DSBigNumber`、`DSLightBar`、`DSStatStrip`、
  `DSSegmented`、`DSChip`、`DSNotice`、`DSPlaceholder`、`DSSkeleton`、`DSExpandGroup`（唯一的折叠）、
  `DSPaperPage`、`DSPrimaryButtonStyle`、`DSRowButtonStyle`、`DSSurfaceModifier`……
- **`Design/Theme.swift`**：`AppCanvas`（画布与光**在根部只画一次**）、`SkyOverlay` 接入、`StatusDot`、`Pill`、
  `MonthlyReportSection`、`PowerSavingToggle`。
- **`Design/Charts.swift`**：`DSTrendChart`（单序列，SOC / 功率共用）、`DSTyreTrendChart`（四条曲线）、
  `DSTrendEmpty`（数据不够时的说明，不是灰块）。
- **`Design/StackSpec.swift`**：叠叠乐的全部手感数字（七种叠法 → `StackMetrics`）
  + 纯几何（`StackMath`，不碰视图，可单独对）。**手感要调就只改这里**，
  不要到页面里改一个局部数字。
  2026-09-24 按用户要求调过的三个数（都写在原处，连同「为什么」）：
  `directionBias` 0.85 → 1.0（吸附临界点从 47% 移到正好一半）、
  `flingVelocity` 550 → 900（普通滑动不再多跳一格）、
  `.arc.shrink` 0.07 → 0.03（滚动中卡片的大小差异减半）、
  `.arc.fadeBottom` 140 → 44（滑到底时末卡底边贴近卡片窗下沿，不留一个手掌高的空白）。
- **`Design/StackLabView.swift`**：七种叠法的对照页（`DevView` → 叠叠乐），
  挑中哪一种写进 `UserDefaults`（`StackSpec.variantKey`），六页立刻跟着换。
- **五个功能界面共用的三个原语**（阶段 1 的产物，职责分得很硬）：
  `GlassCard`（一张卡的材质与内边距） → `ArcStack`（几何 / 手势 / 消失带 / 无障碍翻页）
  → `StackPageView`（巨字头 + 那一叠） → `DSSwipeStrip`（底部那条相机式模式条，已重写）。
  `ArcStack` 收的是**未包装的 `StackCard`** 而不是 `AnyView` —— 因为
  「这张卡要不要挂系统玻璃」取决于它此刻离阅读线多远，而那个距离只有 `ArcStack` 知道。

**铁律（`scan/design.py` 在 CI 上拦）**：字号与颜色分量只允许出现在令牌定义文件里。
不许在页面里写 `.font(.system(size: 14))` 或 `Color(red:...)`。

**颜色从哪来**：`TokensPalette` 是**主题相关**的静态计算值，所以切主题靠
`CarKeeperApp` 上的 `.id(artThemeRaw)` **重建整棵树**才生效（令牌不产生 SwiftUI 依赖）。

### 5.2 四个艺术方向（`ArtTheme`）

| 方向 | 信条 | 落地难度 | 明暗 | 画布装饰 |
|---|---|---|---|---|
| `nocturne` 夜光 | 美来自光：黑底承担信息量，光只给车 | 最能落地 | 深色 | 光池（0.16） |
| `paper` 纸上 | 美来自印刷：纸面、墨线、红笔 | 最贵（MapKit 画不出纸与墨） | 浅色 | 纸纹（0.05） |
| `typographic` 巨字 | 美来自尺度：极细巨字对极小标注 | 最省 | — | 发丝网格（0.08） |
| `native` 原生 | 美来自系统：语义色、分组表面、发丝线（跟随系统外观） | 现状 | nil | 无 |

### 5.3 地图样式（`Design/MapStyleSpec.swift`）

`ArtTheme.mapSpec` 把主题翻译成 MapKit 旋钮。**四套用的都是 `.standard`**，差别只在参数与蒙版上
（实测值，`Design/MapStyleSpec.swift`）：

| 主题 | MapStyle | 蒙版 scrim | 不透明度 | cameraHeading | 车钉 | 发光 |
|---|---|---|---|---|---|---|
| `nocturne` | `.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)` | `0x0A0910` | 0.55 | 7° | `.ring` | ✅ |
| `paper` | 同上 | `0xF2E9D8` | 0.30 | 0° | `.ink` | ❌ |
| `typographic` | 同上 | `0x0A0A0C` | 0.78 | 0° | `.rule` | ❌ |
| `native` | `.standard`（不传参 = 系统默认） | 无 | 0 | 0° | `.ring` | ✅ |

`cameraDistance` 固定 1400。四套共同点：**压暗系统瓦片 + 排除全部 POI + 关路况**，
再用蒙版层把色彩拉向主题方向。`paper` 在代码注释里被诚实标注为「打折方案」——
纸与墨需要整层自建地图（MapLibre + 自有样式），代价见 `MAPKIT-FEASIBILITY.md` §3.2。

> 法律边界写在 `MAPKIT-FEASIBILITY.md`：**不能**用自绘瓦片替代 MapKit（会违反地图数据条款），
> 所以「纸上」方向只能在 MapKit 之上叠纸纹与墨线，不能自己画地图。

### 5.4 光（这个 App 的「颜色来自天上」的部分）

- **`Design/SkyLight.swift`**：真实太阳位置算法（赤纬 / 时差 / 高度角 / 方位角，NOAA 级公式）→
  `SkyPhase` 六相（白昼 / 低角度日光 / 日出日落 / 民用暮光 / 蓝调 / 深夜）；
  **晴空模型 1050 × sin(高度角)**；**云量衰减 `G = 晴空 × (1 − 0.75 × N^3.4)`**（N = 云量 0…1）；
  `SkyFact` 是「为什么现在是这个光」的逐条事实（地图的 `lightPill`/`skySheet` 展示它）。
- **`Services/WeatherService.swift`**：`api.open-meteo.com`（免 key）。WMO 天气码 → 中文。
  **取不到就退回晴空模型，并在界面上照实写明「上面是晴空模型的算法值」**——不拿默认值冒充实况。
- **`Design/SkyOverlay.swift`**：光池 / 雾霭 / 暗角 / 颗粒 / 发丝网格五个图层。
- 纯函数部分有单元测试：`Tests/PureLogicTests.swift`（太阳位置、云量衰减、充电站聚合）——
  **只在开发机的 Xcode 上跑**（CI 的测试 job 已按成本考量删除）。

---

## 6. 本机持久化清单（42 个 `carkeeper_*` 键 + 网络层几个非前缀键）

> 判据：**服务端有这个字段吗？** 有 → 不落盘；没有（只能本机攒）→ 落盘，并在文档与界面上说清它是本机的。

| 类别 | 键（节选） | 退出登录是否清 |
|---|---|---|
| 账号与凭据 | `car_token_config`（**Keychain**）、`carkeeper_encryption_key`、`carkeeper_key`（PIN）、`carkeeper_biometric_setup` | ✅ |
| 选择与导航 | `carkeeper_selected_car_id`、`carkeeper_home_mode`、`carkeeper_map_layer` | 部分 |
| 外观与提示 | `carkeeper_art_theme`、`carkeeper_force_dark_mode` / `_light_mode`、`carkeeper_night_start_hour` / `_end_hour`、`carkeeper_voice_enabled`、`carkeeper_home_card_order`、`carkeeper_power_saving` | ❌（属于本机偏好） |
| **本机累积**（服务端无历史接口） | `carkeeper_hist_soc_v1` / `_power_v1` / `_tyre_v1`（三条曲线）、`carkeeper_processed_event_ids`（行程生成）、`carkeeper_parking_loc` / `_time` / `_points`（停车史） | ✅ |
| 手填记录 | `carkeeper_last_service_mileage`、`carkeeper_service_reminders`、`carkeeper_mileage_entries`、`carkeeper_maintenance_photos`、`carkeeper_insurance_policies`、`carkeeper_inspections`、`carkeeper_current_mileage` / `_total_mileage` | ✅ |
| 提醒与勿扰 | `carkeeper_dnd_mode`、`carkeeper_charge_notify`、`carkeeper_charge_complete_notify`、`carkeeper_next_service_date`、`carkeeper_last_charge_alert` | 部分 |
| 家人与钥匙 | `carkeeper_family_members`、`carkeeper_temp_keys` | ✅ |
| 其它 | `carkeeper_focus_mode`、`carkeeper_current_speed`、`carkeeper_shake_to_lock`、`carkeeper_onboarding_seen` | ❌ |

**已删除、不要加回来的**：`carkeeper_api_stats` / `_page_metrics` / `_home_load_time` / `_version_logs` / `_crash_log`
（诊断统计，用户明确要求删）、充电账本、以及 App Group 里的 `widget_*` / `watch_*` 共享快照。

---

## 7. 服务层清单（`CarKeeper/Services/` 与 `CarKeeper/CarKeeper/Services/`）

| 服务 | 干什么 | 触发/落盘 |
|---|---|---|
| `API.swift` | 网络、Token(Keychain)、刷新去重 | 全局 |
| `HistoryStore` | SOC 5min / 功率 1min / 胎压 30min 采样，三条曲线 + 清理 | 每次 `saveCache` 后 |
| `ChargingStatusMonitor` | 由报文驱动的充电观察点（开始 / 结束 / 充满跃迁时才推送） | `recordHistory` 调用 |
| `SmartNotificationManager` | 通知类别（充电 / 胎压 / 勿扰）+ 资格与去重 | 启动注册，业务触发 |
| `MaintenanceReminderScheduler` / `InsuranceReminderScheduler` | 保养 / 年检提醒排程 | 里程变化 / 启动 |
| `ServiceReminderManager` | 保养项定义与进度 | 车辆档 |
| `WeatherService` | open-meteo 实况（TTL 内且没走远不发请求） | 位置变化 / 启动 |
| `Retrier` / `NetworkEnhancements` | 退避重试 / 网络质量监控 / 离线模式 | 请求层 |
| `Monitoring` | 内存读数（**不落盘**） | 启动后每 10s |
| `DataEncryption` / `SecureStorage` | AES-GCM + Keychain | 车牌等敏感字段 |
| `BiometricLock` / `RemoteLockManager` | FaceID 二次验证 / 后台超时隐藏 | 敏感页 / 启动 |
| `NightModeManager` / `FocusModeManager` | 夜间时段 / 专注模式 | 启动与设置 |
| `GestureEnhancements` / `ShakeDetector` | 摇一摇锁车（自己验 PIN 后发 `CentralLock`） | 启动 |
| `FamilyAndKeySharing` | 家庭成员 / 临时钥匙 | 我的档 |
| `InsuranceManager` | 保单 CRUD | 保养档 |
| `BillingAndCalendar` | 车辆估值 + 年检日历（估值是**估算**，不是市场价，界面写明） | 保养档 |
| `UpdateService` | 检查更新（读 GitHub Release `latest`）+ 分享 | 我的档 |
| `EnhancedToastManager` / `AppStore.ToastManager` | 全局提示 | 全局 |
| `RawLogStore` | 请求/错误原始日志（排障） | 请求层 |
| `MD5` | 登录签名 `signF` | 认证 |
| `NightModeManager` 等 | 见上 | |

---

## 8. 工程约束与门禁（22 项 + 风格检查）

### 8.1 门禁表（每一项都是某次真实事故的产物）

| # | 门禁 | 拦什么 |
|---|---|---|
| 1 | `paths.py` | `project.yml` 与工作流里声明的路径必须存在；每个 target 必须被 CI 编到；**双向**：`scan/` 下的脚本必须在 CI 清单里或在豁免表里写明理由 |
| 2 | `design.py` | 字号 / 颜色分量 / 色相字面量只许出现在令牌文件 |
| 3 | `keys.py` | 报文键只准通过 `ci*` 家族读取（防大小写写错 → 静默零值） |
| 4 | `access.py` | 剥注释与字面量，避免里面的 `foo.bar` 被当成引用（供其它检查器复用） |
| 5 | `lexguard.py` | 中文 / 全角字符出现在**代码位置**（嵌套双引号、全角标点、未闭合字符串） |
| 6 | `scan.py` | 地毯式结构扫描：括号 / 引号 / `#if` 配平、重复声明、未声明名字、幽灵构造 |
| 7 | `logic.py` | 名字解析查不出的逻辑/结构类编译错误 |
| 8 | `shadowguard.py` | 禁止嵌套 SDK 同名类型造成遮蔽 |
| 9 | `scenes.py` | 多窗口 / 分屏（`#47`）接线必须完整 |
| 10 | `targets.py` | 跨 target 符号可见性 |
| 11 | `unreachable.py` | `return` 之后仍有同缩进语句 |
| 12 | `futureproof.py` | 未来系统版本（iOS 27/28）前瞻性审计 + 根目录必须存在 |
| 13 | `orphans.py` | 孤儿页面：「写了但没有任何地方能到达」 |
| 14 | `deep.py` | 更深的结构问题：SDK 同名遮蔽、协议一致性、闭包参数、清洗保真度 |
| 15 | `eol.py` | committed blob 的字节级行尾问题（字面量里裸换行 / 行中裸 CR / `\r\r\n`） |
| 16 | `oneentry.py` | **入口唯一性**：同一件事只准有一条到达路径 |
| 17 | `traps.py` | 编译得过但真机一走到就崩的构造（`hashValue` 参与算术、强解包、`try!` / `as!`） |
| 18 | `scopeguard.py` | 名字在项目里、但在调用点不在作用域（跳类型调静态成员必须带前缀） |
| 19 | `paidcap.py` | 免费账号用不了的能力（entitlements 白名单 / Info.plist 禁键 / 禁 import / target 白名单） |
| 20 | `copy.py` | 界面文案三类判据：实现词（缓存/报文/字段/接口）不上界面、复述句式、超 30 字 |
| 21 | `lintcfg.py` | `.swiftlint.yml` 的排除清单与阈值必须和真实文件树一致 |
| 22 | `ternary.py` | 三元运算符的 `?` 不能贴住前一个 token（否则变可选链）—— 见 §11 事故记录 |
| 23 | `delguard.py` | **删了声明、使用还在**：旧版本里成员级声明过、新版本里没有声明了、代码里还在用它（`pvValue` / `shapeScroll` 两次事故的两条根因） |
| + | `check_style.js`（node） | 风格与括号配平 |

**门禁的写法约定**（新加一项时照抄）：
① 文件头写清「为什么需要它」并引用真实事故；② 判据只认「不可能合法」的形态，不猜意图；
③ 放行表显式列出（假阳性会让整条门禁被无视）；④ 先抹掉注释与字符串正文；
⑤ **双向验证**：注入探针必须报、撤掉必须转绿，探针结果写进文件头或提交信息。

### 8.2 三条铁律（违反会被 CI 拦住）

1. **入口唯一**：去功能只有 `NavState.openMode(_:)` 一条路。不许 push 第二份功能页、
   不许再加 Tab 栏、不许再加「全部功能」目录（历史上有过 4 套入口并存）。
2. **令牌唯一**：字号 / 颜色 / 间距只能来自 `Tokens*`。页面里不许写数值。
3. **键大小写**：报文键一律小写读，且只能通过 `ci*` 家族。

### 8.3 其它工程约定

- `.gitattributes` 强制源码 **LF**（`*.swift` / `*.md` / `*.py` / `*.yml` …）。Windows 上 `autocrlf=true`
  曾造成 `\r\r\n` 叠两层 → 裸 CR 混进字符串字面量 → 编译失败。
- `.swiftlint.yml` 里**不再排除任何文件**（`excluded` 会让整个文件退出全部规则，包括 `force_unwrapping`）。
  改为把 `file_length` / `type_body_length` / `function_body_length` 阈值调到与代码真实形状相符
  （1200 / 1200 / 160），越界就由 `lintcfg.py` 拦下并要求说明理由。
- `build.sh` 本机用 `swiftlint lint --strict`（warning 升级为错误）。
- 提交信息用中文，写清「为什么」；历史提交可作范例（`git log --oneline`）。

---

## 9. 已知缺口、陷阱与「不要做」

### 9.1 数据层面的硬缺口（不是 bug，是接口就没有）

- **行程没有轨迹点** → 地图上是起终点连线。要画真实路线必须先有轨迹接口。
- **`capacity` 是 null** → kWh/100km 算不出来；能效只能按「每 1% SOC 多少 km」。
- **服务端只有「当前状态」接口**，没有历史 → 所有曲线都是本机攒的；卸载即消失。
- **没有导航能力**（免费账号 + `MKDirections` 被列为禁 API）→ 只能显示与搜索，不能规划路线。
- **`refresh_token` 不轮换** → 安全上按长期凭证对待（所以放 Keychain）。

### 9.2 不要做

- ❌ 不要加回**任何** TTL / 失败保留旧值 /「显示缓存数据」逻辑。
- ❌ 不要加回小组件 / 表盘 / 灵动岛 / App Clip / CarPlay target（免费账号下没有一条可用链路）。
- ❌ 不要在根视图挂**无限循环动画**（整棵树反复失效：深色下发暗发黏 + 持续耗电）。
- ❌ 不要在 `@main` 与 `struct CarKeeperApp` 之间插入任何声明（属性绑定到下一个声明，会静默接管入口）。
- ❌ 不要把 `Message`/`Data` 之类的系统类型名拿来做自己的类型名（`shadowguard`）。
- ❌ 不要用 `try?` 包住「必须成功」的异步调用（`try?` 会让 `do` 体永不抛错，`catch` 变死代码）。
- ❌ 不要为了「让界面好看」而给缺失数据填默认值。

### 9.3 已核实的文档/注释漂移（代码是对的，注释旧了）

- ~~`MapSpineView.swift` 头部与 `bottomPanel` 注释写「9 档」、`CarKeeperApp.swift` 写「10 档」~~
  **已改**：`bottomPanel` 这个类型本身已随结构对齐删掉，两处计数注释都改成 6 档。
  留着这条是因为它的成因还没被机制拦住 —— 「注释里的数字」没有任何门禁在盯。
- `DESIGN-SPEC.md` 的小节标题仍用旧页面名（如「行程页 (TripAnalyticsView)」），实际类型是 `TripsEventsView`。
- `GlobalSearchHUD` 的空态提示曾写「搜页面、车牌、行程、指令、**充电记录**。」，而充电记录随
  充电账本一起删了（代码里的注释已注明），提示却还在承诺它 —— **已改**。
  这一类「文案承诺了一个已删除的功能」的漂移，22 项门禁**查不到**：`copy.py` 只管词、长度与复述句式，
  不核对「这句话说的东西还在不在」。写文档时逐屏读才会碰到。

### 9.4 未验证的部分（必须如实交接）

**本地无法编译**：这台开发机没有 Swift 工具链，所以**每一次改动是否编得过，只有 CI 能回答**。
静态门禁能覆盖结构、符号、键名、文案、行尾、作用域，**覆盖不了类型检查与语法细节**——
最近一次真实事故就是一个空格（§11）。接手后第一件事建议先跑一遍 CI 建立基线。

**只能等真机的四件事**（不是没做，是这台机器上量不出来）：

1. 卡片栈自己的竖向拖动与屏幕左缘的返回手势会不会打架。
2. 手工传给弹簧的 `initialVelocity`（`StackSpec.settle(velocity:)`）转得对不对。
3. 底部条在真实 390pt 下「三个字露出来多少」看着顺不顺。
4. 八张卡全在画面里时的帧率（性能策略是只给 `abs(tShape) < 0.9` 的卡挂系统玻璃，
   其余走主题表面色；若卡，下一步是调阈值而不是换材质）。

---

## 10. 常见改动怎么做（配方）

### 10.1 给模式条加一档（最常见）

1. `HomeMode` 加一个 `case`，填 `title` / `deeplink`；
2. `HomeMode.destination(for:)` 里给新档相关深链加分支（**每一个 `Deeplink` 都必须落到某一档，不许落空**）；
3. `MapSpineView.pageContent(_:)` 加一个 `case`（这是**唯一**列全功能界面的地方）；
4. 若要档内分段：加 `HomeSub` case，并放进 `vehicleTabs` / `mineTabs` 之一 + 对应页面
   （`VehicleView` / `MineView`）`cards` 里的 `switch`；
5. 跑门禁（`oneentry.py` 会检查入口唯一性）。

档位清单由 `HomeMode.allCases` 生成，条子与页面同源 —— **不需要在别处再登记一次**。
（曾经有这样一处：`GlobalSearchHUD` 的搜索项。那个页面已随「右下角的搜索从项目移除」
一起删除，而它当时漏登记的代价正是「搜索里静默地少一档」。）

### 10.2 加一个网络接口

1. `APIClient` 加方法（POST + `token=` 查询参数；有副作用就 `retryable: false`）；
2. 决定它进哪个 cache 键（新键要同时改 `AppStore.caches` 初始化、`clearCache`、`gather`）；
   数据时刻不用另外接线： `cacheTime(键)` 由 `saveCache` 自己盖，
   你只要在**带读数的那张卡**上写 `at: store.cacheTime("你的键")`；
3. 读字段一律用 `ci*` 家族，先查 `API-FIELD-MAP.md` 确认键名与类型；
4. 在模型层（`ApiModels` / `ViewModels`）翻译成可渲染结构，**不要在 View 里读报文**。

### 10.3 加一项门禁

照 §8.1 的约定写 `scan/xxx.py`（含「为什么需要它」的文件头 + 双向探针），
**然后必须加进 `.github/workflows/ios-build.yml` 的 `for s in ...` 清单**——
`paths.py` 会拦住「写了但 CI 从不运行它」，但别依赖它兜底。

### 10.4 改界面文案

`scan/copy.py` 会对全量字面量跑三类判据。写文案前先看它的文件头——那里写着「哪三类句子是禁止的」
以及每一条对应删过的哪句话。

---

## 11. 事故档案（读这几条能省很多时间）

| 日期 | 事故 | 根因 | 现在的防线 |
|---|---|---|---|
| 09-21 | CI 编译失败 | 字符串里嵌了 ASCII 双引号 | `lexguard.py` |
| 09-22 | CI 卡在 `xcodegen generate` | `project.yml` 声明了已删目录（本地有空壳，干净检出没有） | `paths.py` |
| 09-22 | CI 报「没有 CarKeeper scheme」 | 一旦显式写了 `schemes:`，XcodeGen 不再自动生成其它方案 | `paths.py` |
| 09-22 | 车锁车窗恒显示「已锁/已关」 | 报文键大小写写错 → 永远 nil → 看着像正常状态 | `keys.py` |
| 09-22 | 12 个编译错误 | 收助手函数时调用写了裸名字，而助手住在 `enum` 里 | `scopeguard.py` |
| 09-23 | 真机闪退（SIGTRAP） | `6 + type.hashValue * 2` 溢出，而它写在默认值里 | `traps.py` |
| 09-23 | 预计充满时间恒为空 | 读的键（`ChargPower`）在报文里不存在 | 改为 `VM.chargePowerKW` |
| 09-23 | CI 编译失败 | `searchText.isEmpty? "…"` 少一个空格 → 被读成可选链 | `ternary.py` |
| 09-23 | 检查范围悄悄变小 | `rglob` 对不存在的目录不报错，白名单里留着已删目录 | `_roots.py`（根目录必须存在） |
| 09-23 | 门禁写了但没接 | `copy.py` 没加进 CI 的 `for s in ...` | `paths.py` 的反方向检查 |
| 09-23 | CI 编译失败（3 条 `pvValue`） | 撤 `pv` 状态时把 `pvValue` 函数本体一起删了，5 处调用还在 | `delguard.py` |
| 09-24 | CI 编译失败（3 条 `shapeScroll`） | 重写它的注释时把声明本身写没了，3 处使用还在 | `delguard.py` |

---

## 12. 文档地图（每份 md 管什么，别再重复写）

| 文件 | 用途 | 什么时候读 |
|---|---|---|
| `HANDOFF.md`（本文） | **总入口**：有什么、在哪、怎么改 | 接手第一天 |
| `README.md` | 构建 / 自签安装 / 7 天续期 / 网络说明 / 已知限制 | 要装到手机上时 |
| `API-FIELD-MAP.md`（1024 行） | **抓包逐字段全解**：21 条请求时间线、9 个端点、每个字段的类型与含义 | 碰任何接口字段前 |
| `DESIGN-UNIFY.md` | 统一契约：一页长什么样、一件东西只有一种做法、谁在拦 | 改 UI 结构前 |
| `DESIGN-SPEC.md` | Kansei 设计规范（配色 / 动效 / 玻璃 / 排版 / 触觉 / 布局） | 调视觉时 |
| `MAPKIT-FEASIBILITY.md` | 三个艺术方向 × 真实 MapKit 的可行性矩阵与法律边界 | 改地图样式前 |
| `AppIcon-SPEC.md` | 图标规范与两种生成方法 | 换图标时 |
| `REDESIGN-STATUS.md`（约 90KB） | **逐轮改造日志**：每轮做了什么、为什么、验证了什么、哪些没被证明 | 想知道「为什么是这样」时 |
| `../README.md`（仓库根） | 只有一行，是仓库占位 | — |
| `../design-preview/*.html` | 8 个自包含设计预览（三种艺术方向 / 六屏地图 / 十种融合 / 20 套样品） | 挑版式时（浏览器直接打开） |
| `../ChangAnMiniProgram/` | 微信小程序参考实现（功能与接口的原始来源） | 想确认「原版怎么做」时 |

---

## 13. 接手第一天的建议顺序

1. **跑一遍静态门禁**（§1.1），确认本地环境能复现 CI 的绿灯。
2. **推一个空提交或看最近一次 CI**，确认编译基线是绿的（§9.4：编译只在 CI 上）。
3. **读 §2.2 导航模型**，然后在模拟器/真机上只做一件事：把 6 档依次拨一遍，确认「换档不换屏」。
4. **按 §4.3 读 `ChargeView`**（它是最新重写的页，风格最贴近当前约定），再按需读 `MapSpineView`。
5. 想改什么，先查 §10 的配方与 §8.2 的三条铁律，再动手。

---

## 附：2026-09-23 之后的形态（玻璃卡 + 相机式底部条）

这一版把五张功能界面从「一整页滚动」换成了**一叠玻璃卡**，入口那条也从
「定宽 + 中心放大」换成了相机那条（静止三档 → 按下展开全部）。
动手前先读下面四条，它们解释了新代码里所有看起来“多出来”的东西。

### ① 新增四个 Design 原语，职责分得很硬

| 类型 | 它管什么 | 它**不**管什么 |
|---|---|---|
| `StackSpec` / `StackMath` | 全部数值与纯判定（焦点、吸附落点、两端硬停） | 不 import SwiftUI 之外的任何东西，不碰视图 |
| `GlassCard` | 一张卡的外观（玻璃 + 一抹个性色 + 标题行） | 不决定卡在哪儿 |
| `ArcStack` | 七种叠法的几何、手势、消失带、无障碍翻页 | 不知道卡里装的是什么 |
| `DSSwipeStrip` | 底部那条：胶囊外轨 + 胶囊选中格，静止三档、按下展开、连续跟手，选中那档的字是主题强调色 | 不换屏（它只写回 `homeMode`） |

### ② 五页的写法已经统一，新加一页就照抄

```swift
var body: some View { StackPageView(accent: mode.accent, label: "…", cards: cards) }

@MainActor private var cards: [StackCard] {
    var out = HomeMode.xxx.headCards          // 巨字头就是第一张卡
    out.append(StackCard(id: "a", title: "短标题", value: "可选读数", content: AnyView(…)))
    return out
}
```

三条硬约束：

- **巨字头是卡，不是页头。** 不要再往纸上加“固定不滚的头”——那正是这次拆掉的东西。
- **头卡只给一个事实。** 它曾经还带三行依据（车牌 / 车架号 / 保险 之类），而那三行
  逐条又在下一张卡里再说一遍 —— 已删（2026-09-24）。一条事实只该有一个出处：
  头卡是这一页的标题，依据在下面每一张卡里。
- **卡高由内容撑**，不写 `frame(height:)`。七种叠法的焦点与吸附全部靠真实高度算，
  写死高度会让「行程那一叠」与「设置那一叠」手感不一样。
- **无数据就写一句真话**（`GlassCardEmpty`），不要摆 `--`。读数带时间用 `StackCard.at`。

### ③ 三条容易踩的坑（都是这次真的踩到的）

- **`StackMath` 里的数字只能改一处。** 六页的手感任何一处不同，都说明有人在页面里
  另写了一遍间距。
- **条子的几何全部由 `width` 参数推出来，没有一处存起来。** 把它存成 @State 那版
  在非 390pt 的机器上首帧会停在错的地方（而且只在第一帧，很容易被当成“闪一下”）。
- **卡片栈没有 `ScrollView`，也就没有系统给的三指滚动。** 翻页靠容器上的两条动作：
  `.accessibilityAdjustableAction`（元素级上下轻扫 = 上一张 / 下一张）与
  `.accessibilityScrollAction`（区域级三指扫）。改 `ArcStack` 的手势层时不要顺手
  删掉 —— 它不会报错，只会让 VoiceOver 用户完全翻不了页。
  （这里原本写的是 `.accessibilityAction(.scrollUp/.scrollDown)` —— 那两个成员不存在，
  见 `REDESIGN-STATUS` 的「CI 报回来的三处」一节。）

### ④ 怎么挑叠法

`我的 → 诊断 → 叠叠乐`。七种叠法在同一个窗口里切换，挑中的那种写进
`UserDefaults`（`StackSpec.variantKey`），六页立刻跟着换。默认**弧出**。
这套东西在浏览器里的原型是 `design-preview/stack.html`（那个文件夹是设计过程，不进 App target）。
