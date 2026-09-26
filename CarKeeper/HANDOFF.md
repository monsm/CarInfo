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
| 规模 | **79 个 Swift 文件 / 24,609 行**（`find CarKeeper -name '*.swift'`，2026-09-25 重新量；上一版那个数还是 09-23 的快照，此后每一轮都在加东西而它没动过） |
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
- 改完必须看 CI 日志才能知道「编不编得过」。这也是仓库里为什么会有 **33 条**静态门禁
  （§8；加上 `check_style.js` 共 34 项，`scan/all.py` 一次跑齐）。

```bash
# 本机可跑的全部验证（在仓库根）—— 一条命令，别挑着跑
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
python3 scan/all.py
```

> **为什么是「一条命令」而不是那个 `for s in ...` 循环**：循环的清单与 CI 逐字同序，
> 但它是**给人抄的**，而 2026-09-24 就漏抄了 —— 改完只跑了清单里的一半，
> 三条红全部由 CI 报出来（其中两条是本地跑一遍就会当场红的真 bug：
> 界面文案里的实现词、`MapSpineView.swift` 越过 `file_length` 阈值）。
> `scan/all.py` 干的就是那个循环：**清单从 `.github/workflows/ios-build.yml` 里解析出来**
> （这里不另抄一份 —— 抄一份的后果是 CI 加了门禁而本地不知道，于是本地永远绿），
> 逐条跑完**所有**条（CI 用 `bash -e`，红在第一条就停；本地要的是一次看到全部红）。
> 它自己不判任何东西，所以登记在 `paths.py` 的豁免表里（连同理由）。
>
> 它还有一条与判据无关的自保：控制台打不出 ✅/❌ 时（Windows 的 GBK 控制台），
> 符号降级为 `[通过]` / `[红]` —— **红绿不能长得一样**。

> `delguard.py` 比的是「旧版本 vs 现在」，而**旧版本取谁看工作区干不干净**：
> 工作区有改动（本地）→ 比 `HEAD`（手上这份就是未来的那一笔，它的父提交是 HEAD）；
> 工作区干净（CI）→ 比 `HEAD~1`（就是这次提交）。它盯的是「声明被删/重写了、使用还在」——
> 三次真实事故都是它，而它自己的两个盲区也是 2026-09-24 当场补的（见 §11）。

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

两个 job：第二个依赖第一个（**2026-09-25 起是两条** —— 原来还有第三个 `make-private`）。

1. **`static-gate`**（ubuntu，秒级）：`check_style.js` + 31 项 `scan/*.py`。**任一红即整体失败**。
   （它的 checkout 要 `fetch-depth: 2` —— CI 上工作区干净，`delguard.py` 要拿 `HEAD~1`
   才比得出「这次提交改掉了什么」。）
2. **`build-unsigned-ipa`**（macos，约 3 分钟，额度按 10 倍计费）：XcodeGen → xcodebuild → 打 `Payload/` zip 成 ipa
   → **IPA 内容体检**（只打印顶层结构，`|| true` 不阻断）→ 上传 artifact → 覆盖发布到 tag `latest` 的 Release（App 内「检查更新」从这里下载）。
> **`make-private` 已于 2026-09-25 删除**（用户：「移除变私库的自动化」）。它原来是第三个 job：
> 构建一结束（`if: always()`，红绿都跑）就去 `PATCH /repos/{owner}/{repo}` 把仓库改成私有。
> 删它的理由有两层：
>   · **代价**：那个 PATCH 需要**仓库级 Administration 写权限**的 PAT（`GITHUB_TOKEN` 的
>     `permissions:` 清单里根本没有 `administration`，拿它去调只会 403），于是仓库要长期养一个
>     能改自己设置的密钥 —— 这是整条流水线上权限最高的一个东西。
>   · **归属**：「这个仓是不是私有」是一句**人的决定**，不该由 CI 的终态判据去维持。
>     `REPO_ADMIN_TOKEN` 这个 secret 现在没人读了，请手动删掉它。
> 想转就自己来一次（也可反过来）：`gh repo edit <owner>/<repo> --visibility private --accept-visibility-change-consequences`。

**为额度加的三条（2026-09-24）：**

| 措施 | 省下的是什么 | 代价（写在明处） |
|---|---|---|
| `concurrency: cancel-in-progress` | 被下一次 push 取代的那一轮，剩下的时间不再结算 —— 本仓库一天推几十次，这是最大的一条 | 它会在**任意一步**杀 job，包括 `gh release upload --clobber`；被砍在中间时 tag `latest` 可能短暂没有 .ipa，下一次成功的运行补回来 |
| `paths-ignore: ["**.md"]` | 只改文档的提交完全不跑（已逐条核实：没有任何一条门禁读 .md） | 拿不到那一次的 CI 记录；名单故意只写 .md，其余一律照跑 |
| （三条的理由原本写着「转私有后的额度」—— 那条自动化已删，而这三条与可见性无关，照旧留着：省的是 runner 时间本身） | | |
| `timeout-minutes: 10 / 20` | 挂死那一次的尾巴：job 默认超时 360 分钟，macOS 按 10 倍扣 = 3600 配额分钟，一次就能吃掉近两个月的免费额度 | 正常 3~4 分钟的构建封在 20 分钟，慢网络下留了 5 倍余量 |

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
├ 设计层  Design/Tokens → DS → Charts / SkyLight / Theme / DSSwipeStrip
├ 界面层  CarKeeperApp（入口 + NavState）→ MapShellView → MapSpineView（唯一的屏）→ 6 档页面
└ 服务层  Services/*.swift            通知 / 提醒 / 健康钥匙 / 采样 / 天气 / 更新 / 估值……
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
这条是从相机 App 的模式条学来的，`DSSwipeStrip` 就是那条条子（可手拖、跟手、吸附、选中项放大）。
2026-09-25 按用户「选中的宽度加大、滑动区变高」+「控件大小都很不 iOS」调过三个数：
**条高 46 → 54**（两侧圆钮按原型那条关系一起从 50 走到 58；整条底条的命中区现在还包括
它离底那 26pt 空白带 —— `contentShape(Rectangle())`）、**一档宽 34 → 38**（整条更长）、
**选中胶囊 = 格宽 × 1.9**（原 1.75；它是选中**指示器**，而各段依旧等宽，所以吸附不会飘）。
模式条占的纵向空间随之从 86 涨到 94（`barTotal` = 26 + 54 + 14）—— 它是派生量。

**整条上的横拖只有一个写者**（2026-09-25 修）：手指按在条子**任意位置**（含它上下那圈
空白带）都能拖，但宿主（`MapSpineView`）只把「绝对增量 + 松手预测落点」转发给条子
（`DSSwipeStrip.RowDrag`）—— 位置 `c`、越界阻尼、吸附、展开与 620ms 后的收回**全在条子里**；
条子自己的手势在跟同一根手指时，这条转发整个作废（`guard cBase == nil`）并忘掉起点，
所以永远不会出现第二个写 `c` 的人。
上一版是宿主自己按 `barRowWidth / 档数` 算档位写 `modePosition`，三个后果都真实存在过：
**条子不跟手**（`c` 没人碰，动的只有页面）、**松手没人写回**（页面停在两页各半透明，
`fade` = 0.5，下一次碰条子才归位）、**两臂展开后没人收回**（收回的节奏住在条子的
松手逻辑里，只有条子自己的手势会走到）。吸附同时改成**看速度**：`snap(projected:)` 吃
系统给的 `predictedEndTranslation` —— 只看松手位置的话，「甩」与「停」结果一样。
（明账：转发的是绝对增量，条子按当时插值中的节距换算 —— 手停在档位边界几 pt 之内的
轻甩理论上可能差一档；但与上一版的区别是性质上的：两个人算、还是一个人算。）

> **条子的几何只有一个来源，就是「当前露出几档」**（2026-09-24 第三次修正）：
> 间距按露出档数算 —— 静止露三档 → 宽裕（节距 68）；展开装全部 → 不够才压。
> 而选中那枚玻璃胶囊的尺寸由**格宽 ×1.5** 与**条高 ×0.94** 推出，**不跟节距挂钩**。
> 上一版的病根正是这两处耦合：静止时只露三档、却用着为六档压出来的节距 40，
> 于是胶囊被封顶成 38 —— 几乎就是字的宽度，用户看到的是「一颗贴字的椭圆」
>（用户 2026-09-24：「首页 选中的玻璃体太小了，大 50%」）。

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
用户操作 / 自动刷新的节律循环（RefreshLoop）
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

**自动刷新的节律（2026-09-26 改过，用户点名要的）**：**一个循环**（`Services/RefreshLoop.swift`），
节律由三个输入算出来，三个输入都只有一处出 —— 当前在哪一档（`HomeMode.storageKey`，模式条写的
那一个键）、车在不在动（最近一次报文里的 `VehicleSpeed`，`AppStore.isCarMoving`）、
以及**连着读到几次 0 速度**（循环自己数，见 §27）：

| 何时 | 间隔 | 取什么 |
|---|---|---|
| 地图页 · 车在动 | **2 s** | `fetchCore()`（车况四项） |
| 地图页 · 车停着 | **2→4→8→16→32→60 s**（每读到一次 0 就翻倍，封顶 60） | `fetchCore()` |
| 其他五档 · 轻 | **60 s** | `fetchCore()` |
| 其他五档 · 重 | **300 s** 或**翻到这一页时** | `fetchVehicleData()`（含消息与体检） |

⚠️ 停着那一档是一条**退避曲线**（用户 2026-09-26：「15 秒久了，改用更智能的算法吧，
直至最高 60 秒」）：自变量就是「连着读到过几次 0 速度」（不另记时刻 ——
每一次取数本身就是一次读数）。刚停下时按「还在动」问（2 秒：那时我们还不知道是红灯还是车位），
然后 4 → 8 → 16 → 32 → **60 封顶**。发现起步的代价永远只是当前这一档的等待，
而车一动就归零。
（它换掉的是两个更早的形状：「停着固定 60 秒」与「停着固定 15 秒」——
 前者漏起步，后者在一停一整夜时白问 240 次/小时。）
⚠️ 一次睡眠是**一秒一格**的：节律会变（车动起来 / 停够久 / 换档），一口气睡完的那种写法
会让变化等到这一觉睡完才生效 —— 而那意味着换档要等整整一分钟。

地图页那颗**手动**「全局刷新」（图层面板里）走 `RefreshLoop.refreshAll()` —— 即**全部接口**，
刷完弹一句反馈（全取到 / 有 N 项没取到，缺项取自 `saveCache` 里值为 nil 的那些键）。

为什么不做成「每页一个定时器」：六页是**同时建出来**的（§4.1 的 `pageDeck`），每页一个 `Timer`
就是六个循环各按自己的节律问同一个服务端 —— 换一次档会把六份请求都点着。
三条自我约束写在那个文件头：不并发（一次取数 `await` 完了才睡下一次）、没登录/没车不取、
进后台不做特殊处理（进程被挂起，`Task.sleep` 随之停摆）。

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
| `getMessages` | `/appserver/api/information/pageReceiverInfoByTime?actionType=2&limit=2000`（**4 个连续的 7 天窗口**，见 §4.5） | 事件流 | `messages` |
| `sendControlCommand` | `/api/car/control?pin&cmd&carId`（**不重试**） | 指令受理 | — |
| refresh | `…/auth/cac/refresh` | 新 access_token | —（写 Keychain） |

### 3.2 Token 与安全

- **Token 存在 Keychain**（`TokenStore`，`kSecAttrAccessibleAfterFirstUnlock`），不再放 UserDefaults：
  实测证明 `refresh_token` **不轮换**（`expires_in: 86400`），泄露即长期可用；而 UserDefaults 会进 iCloud 备份。
  首次读取会把旧 UserDefaults 里的令牌**迁移进 Keychain 并删掉明文**（用户无感）。
- `TokenStore.clear()` 同时删 Keychain 与旧 UserDefaults 键（退出登录必须两处都删）。
- ~~`DataEncryption` / `SecureStorage`~~ **已于 2026-09-25 删除**：它把车牌加密后写进
  UserDefaults，而全仓没有一处读它（只写不读 + 静默失败）。车牌不属于「被加密保存的敏感字段」
  —— 它只出现在报文与界面上，本机不另存一份。
- 人类可读的报文日志走 `RawLogStore`（键 `changan_raw_log`），用于排障。

### 3.3 重试与刷新

- `Retrier`（指数退避 + 抖动）：默认 4 次 / 1s 起 / ×2 / 上限 8s / 抖动 0.3；另有 `.aggressive`、`.dataReliable`、`.none`。
- **有副作用的 POST 必须 `retryable: false`**（车控指令、发短信）——重复下发是真实危害。
- token 刷新用 `AtomicTaskHolder` **并发去重**：同一时刻 N 个请求过期只刷一次。
- **「多久问一次」不在这里**：那是 `RefreshLoop` 的节律（见 §2.3）。重试管「一次请求失败之后怎么办」，
  节律管「隔多久发起下一次」—— 两件事分开，谁也不替谁兜底。

### 3.4 报文解析的两条铁律

1. **键一律首字母小写**（实测：`remainPower` / `totalOdometer`）。Swift 的 `[String: Any]` 下标大小写敏感，
   写成 `["RemainPower"]` 就是**永远 nil**，而 nil 经 `num()` 又常变成 `0` → 界面显示成一种「正常状态」。
   读取一律走 `ci*` 家族（`ciString` / `ciNumber` / `ciBool` / `ciArray` / `ciObject` / `ciVal` / `ciPick`）。
   **`scan/keys.py` 在 CI 上拦这条。**
2. **没有的键不许编值**。界面缺数据时显示 `--` 或一句「未上报」，不用默认值填空。
   （历史事故：预计充满时间读的是根本不存在的 `ChargPower` / `ChargingPower`，于是那个数字永远是空的。）

---

## 4. 界面逐项

### 4.1 地图主屏（「现在」档）—— 全 App 唯一的屏**文件**：`Features/Map/MapSpineView.swift`（**1157 行**；骨架：六页同屏 / 底条 / 镜头 / 图层 / 手势；2026-09-25 一共拆出三份，都在同一个阈值（1200）之前：`MapNowCard.swift`（「现在」那一张卡本身 + 卡里三个数的排版）、`MapSpineReadouts.swift`（收起时那一横 + 抽屉 + 比例尺）、`MapQuickButtons.swift`（右侧两枚钮）。拆的都是**一件独立的事**，界面一字未改 —— 第三次拆（加完抽屉之后本文件又到 1201 行）搬的正是那张卡本身；
2026-09-25 它到过 1201 行、越过了 `lintcfg.py` 的 1200 阈值，于是把「光」表拆成
`MapSkySheet.swift`（含共用原语 `MapNotice`）；同日再涨到 1212 行（托底要抬到条子之上 +
子页顶部留白），于是把那张铺底的壁纸再拆成 `MapWallpaperLayer.swift` —— 两次拆的都是文件，
界面一字未改。**Toast 浮层也住在这一屏里**（它要抬到底条之上，而条子的高度只有这里知道）。
**同一天「底条整行横拖」从 `MapSpineBottomBar.swift` 搬了回来**：那次拆分让一个
从没编译过的文件进了仓库（见 §11 的 09-25 行），而它要用的四个成员都是 `private` ——
搬回来之后它们各自保持 `private`，那一条手势与它的状态 `barDragBase` 又住在一起）、
`MapSpineLayers.swift`（139 行，「现在」那一档四个图层各自的内容 —— 2026-09-23 拆出，
理由见那里的文件头）、`MapSpineData.swift`（数据层）、`MapCarPin.swift`（车钉）、
`HomeModeHead.swift`（巨字头：只给**一个**事实 + 一行小字，依据在下面每一张卡里）。

**骨架（2026-09-23 按原型 `design-preview/stack.html` 重排过）**：一张全屏 MapKit 地图，
上面只摆原型里本来就有的东西 —— **底部那一张卡**（2026-09-25 起它是一个抽屉）
（`.float`：底边离屏底 98pt）+ **罗盘**与**比例尺** —— 两件都是**系统的**
（2026-09-25 第十一轮改回来：`MapCompass(scope:)` / `MapScaleView(anchorEdge:scope:)`
可以当**独立视图**挂，位置由我们自己给。第 9～10 轮那两件自己画的（自量尺子 + 自画罗盘）
已删，见 §22）。
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

**子页面的暗层也全删了（2026-09-24 同日第六轮：「每个子界面的暗层都去掉，不要！」）**：
此前还有三层不透明画布叠在子页面底下 —— ① `MapSpineView.body` 根部的
`.background(TokensPalette.canvas)`；② `pageDeck()` 六层同屏底下垫的那层
`TokensPalette.canvas.ignoresSafeArea()`；③ `pageBody` 每张非地图子页各自的
`.background(TokensPalette.canvas.ignoresSafeArea())`。三层全删：非地图子页现在铺的是
**壁纸图**（`wallpaperLayer()`，来自 `Services/WallpaperService.swift`）。
 iOS 读不到主屏壁纸（无公开 API，壁纸归 SpringBoard 管），所以「桌面的那张」只能换一种
拿到方式。**三条路（`WallpaperSource`，2026-09-25）**：

| 图源 | 怎么来 | 要不要钱 / 钥匙 |
|---|---|---|
| 相册自选 `photo` | `PhotosPicker` 选一张本地图（JPEG 0.82 落盘） | 不要，也不联网 |
| 必应每日 `bing` | `HPImageArchive.aspx?format=js&idx=0` 的当天那张 | 不要，免密钥 |
| Windows 聚焦 `spotlight` | `fd.api.iris.microsoft.com/v4/api/selection?placement=88000820` | 不要，免密钥 |

  「如果需要密钥就算了」是用户给这条功能的边界，所以只有这两家（都是别人给自己产品
  用的公开只读 JSON）进了代码。两条在线源都是**每天换一张**：取到的图落成
  `Documents/carkeeper-wallpaper.jpg`（与相册那张同一个文件，铺图只有一条路径），
  `UserDefaults` 记「取到的是哪一天」（`dayStamp`，UTC 天数）；同一天启动直接读盘，
  跨天才再去取一次（取图失败保留上一天那张，`failed` 让设置行说一句人话）。
  没图（没选 / 点「不铺」）时回落到 `TokensPalette.canvas`（浅色模式浅灰 /
  深色模式近黑，随 AppCanvas 的光），观感与删暗层之前相同，但不再是「暗层」。
  第一次取图在 `MapSpineView` 的 `.task` 里催（`refreshIfStale()`，故意放在
  `LaunchFence` 之外：它只往 Documents 落一张 JPEG，不碰车况与地图状态）。

**只有一张大卡**（2026-09-24 第八轮：用户「地图页地下 4 个独立的读数融合进大卡片，
最上面那行也删掉——和下面重复」）：这一档原本「浮动两卡 + 四格读数」三块，
现在收成**一张** `nowCard`（`GlassCard`）：

- 卡头一行只剩**一枚图层胶囊**（`layerMenu`）—— 右对齐。原先那行还写着车牌 + 状态
  + 上报时间，与卡内正文说的是同一件事，已删（重复）。
- `.now` 分支拉出来之后的正文：地址（大字）→ 副行（表显 · 充不充电）→ 光带
  （`nowMetrics`，在 `MapNowCard.swift`）→ **两排其余读数**（`readoutsDrawer`，
  `MapSpineReadouts.swift`）。
- **这张卡现在是一个抽屉（2026-09-25 第五轮，用户第 2 条：「下面的卡片不是抽屉样……
  默认只显示一横，拉出来才是全部」，并附了 Apple 地图那张导航卡当参考）**：
  收起（默认）= 一枚拉手（那「一横」）+ **三个数**（续航 / 电量 / 车速，`summaryBar`
  用 `DSBigNumber`、字号 30）+ 图层胶囊；拉出来 = 卡的全部内容。
  两态的排版在 `MapSpineReadouts.swift`，外壳在 `MapNowCard.swift`。
  · 那三个数是**用户点名的三个**，且它们**不随开合消失** —— 参考图里也在同一个位置，
    所以抽屉正文里**不再重复**这三个数（一个事实一个出处）。
  · **巨字续航因此不见了**：它原先占 `size 56` 一整行。这不是排版缩水，是重复的消除 ——
    同一个 412 km 不必在卡里说两遍（用户 2026-09-24：「地图页的信息有很多是重复的」）。
  · **上一轮那张系统 sheet 与它那行「其余读数」入口一起删了**（`readoutsSheet` /
    `readoutsDisclosure`）：抽屉**就是这张卡**，而系统 sheet 永远是屏幕底部的一张新面 ——
    它会盖住模式条（全站唯一的入口），于是「拉开的抽屉」与「卡片自己」成了两处内容；
    用户要的参考图里那张卡本身就是抽屉。三代写法各自的代价记在 `MapSpineReadouts` 头注。
  · 拖动只看**方向 + 阈值**（`predictedEndTranslation`，所以轻甩就走过去），
    不做连续跟手：两个落点固定，中间没有第三种停法 —— 第一代那样自己算高度、
    自己夹边界，换来的只有「拖的时候卡跟着手指长」。
- **地图右侧两枚快速钮（同日第三轮，用户：「地图页要像 ios 地图 app 右侧的图标一样
  加入快速回到车的位置和手机的位置」）**：`MapQuickButtons.swift`（两枚 44×44
  `.overMedia` 玻璃圆钮，竖排、让开系统罗盘）。「回到车」原本在图层菜单里 ——
  那里删掉、这里留下（同一件事两个入口就是重复）；「手机的位置」是**新能力**：
  全仓此前没有任何 CoreLocation 代码（见 `Services/PhoneLocation.swift`），
  钮的图形自己就是状态（`location.fill` / `location` / `location.slash`），
  拿到的点作为蓝点画在图上（`phonePin`）。
- `readoutChips`（旧版独立玻璃卡）：零调用点，已删（2026-09-25 逐卡核对那一轮）——
  「同一件事有两个写法」在这个仓库里就是下一个事故的种子（文件里那段注释留了去向）。

**图层胶囊同时是这一屏的菜单**（`layerMenu`，`Menu`）：四个地图图层（当前那层带勾）、重取数据、
此刻的光（`skySheet`）、回到车；iPad 上多一项「新车况窗口」。

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

**车钉（`MapCarPin`）**：三种钉法对三种钉风格 —— `MapPinStyle` 的 `.ring`（发光环，
默认给夜光与原生）/ `.ink`（墨线圈，纸上）/ `.rule`（发丝环 + 十字准线，巨字）。新增 16 套
主题各自取这三种之一（见 `MapStyleSpec.swift`）。车头朝向由 `Heading` 驱动。

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

**2026-09-25 逐卡核对（用户：「全局看重复内容…每个卡片仔细核对是否合理，内容展开后是否拥挤」）**：
这一档是「页面壳套在卡里」的重灾区，三件事一次改完：

- **卡里不再套页面壳**。`HealthDataView` 与 `MaintenanceMoneyView` 原本各自包着
  `DSPaperPage`（自带一层 `ScrollView` + 一层纸面底 + 自己的左右 16pt + 一行页标题），
  而它们**只**作为那张卡的内容存在（全仓无第二个调用点）。叠进卡里的后果是：
  第二层滚动 + 第二层底 + 双重内边距（卡 18 + 页 16 = **34pt**，内容比别人窄一圈），
  标题也说两遍（卡头「体检」+ 页标题「体检与数据」）。现在两者都改成
  `VStack(alignment: .leading, spacing: 0) { … }`（间距与那股纸完全一致，只是不再有纸）。
  它们都是所在那一叠的**末卡**，所以「末尾停在末卡下沿」的规则保证底部读得到。
- **卡头已经写过名字，正文不再写第二遍**。`DSSectionHeader.title` 现在是可空的
  （默认 `""`）：`VehicleTipsSection` 的「用车提示」、`MileageJournalSection` 的
  「里程记账」、`MessagesSection` 的「车辆消息与事件」都改成了空标题 —— 它们栖身的卡
  分别叫「用车提示」「里程记账」「车的事件」，这三行只剩右侧那个动作（「全部已读」）。
  （同一条判据上一轮已经用在「常来之地 / 常停之地」与「驾驶评分 / 评分」上。）
- **一个动作不能挂在永远不显示的工具栏上**。`MaintenanceMoneyView` 的「＋（添加保养
  记录）」原来只存在于 `.toolbar`，而全 App 的导航栏是隐藏的（地图那一档没有顶栏，
  子页继承同一个栈）—— 那个入口从未显示过，等于「加一条保养记录」没有入口。
  现在它是内容里的一个按钮（`addServiceButton`），形状与「里程记账」卡里的
  「添加记录」一致。

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

### 4.4 车控档 —— `ControlView`（960 行）

- 头部：读数就在车上（一屏不堆卡片）+ **一辆真的三维车**（`CarModelView`，RealityKit：
  代码搭的车身/座舱/四门/四轮/灯，拖动转车、点部位控车）—— 2026-09-25 第九轮换掉
  了那张线描俯视图（`CarTopView`，已删，理由见 §20.7）。
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

**行程卡上限 30 段**（2026-09-25，用户：「行程页的最大行程控制在 30 条，其他均以消息显示」）：
`tripCardCap = 30`，一次仍只建 5 张（`tripCardStep`），由人点「再放 5 段出来」；到 30 之后
那一行**换成陈述句**（「再往前的 N 段在下面『车的事件』里，按时间列着」），而不是一个按了
没反应的灰按钮 —— 超出的那些没有丢，点火/熄火事件本来就一条条列在「车的事件」卡里
（同一份消息的另一种读法）。上限的理由是每张行程卡里是一张**真的** `MiniTripMap`。

**消息窗口：跨度 30 天，形状仍是 7 天一段**（2026-09-24 两次修）：
`APIClient.messageDays = 30`、`APIClient.messageSliceDays = 7`。
**「跨度」与「形状」是两件事**：形状 = 抓包里那一次请求的样子（`startTime` 到 `endTime`
相隔 7 天），它**唯一被验证过**；跨度 = 界面要覆盖多少历史，用户要 30 天就 30 天。
所以 30 天 = 五段 7 天的请求（末段只有 2 天）再合并，而不是发一个 30 天的窗口 ——
服务端能不能接受更长的区间没有任何证据，而「窗口太小」与「窗口太大」在界面上
长得一模一样（都是 0 条）。原先只要最近 7 天，于是车三周没开 →
「车的事件」与「由消息配出来的行程」同时为空，看起来就像「拿不到数据」。
空态会写明窗口（「近 30 天没有事件」），**没有 token** 时也会明说
（原先那一支只是把 loading 关掉，屏幕上与「真的没消息」一模一样）。

> ⚠️ 这条推论的另一半写在明处：**若 30 天里确实有事件而界面还是空的，那就不是跨度的问题。**
> 四种失败在界面上长得一样（①请求没发出去 ②被拒 ③服务端说 0 条 ④给了 55 条而我们解析成 0 条），
> 所以有那台仪器：**我的 → 诊断 → 消息自检**（一次发三种窗口、七次请求，
> 把 HTTP 状态 / 响应字节数 / 服务端自报条数 / 我们解析到的条数并排报出来，可一键复制）。

- **行程时间轴**：`store.tripHistory`，每段带 `MiniTripMap`（起终点小图）+ 里程/时长/能耗。
  ⚠️ **一次只建最近 5 段**（`TripsEventsView.shownTrips`）—— 那张小图是一张真的 `Map`，
  而 `ArcStack` 把这一页的卡一次全建出来：几十段行程 = 几十个 MapKit 视图同时初始化，
  真机上会在几秒内冲到 1.7 GB 并被系统收走（见 §6.1 与 `REDESIGN-STATUS` 第五轮）。
  更多的由 `再放 5 段出来` 那个动作放出来。同理：消息一节一次只画最近 3 天。
  （能效用**每 1% SOC 多少 km**，因为 `capacity` 是 null，kWh/100km 算不出来）。
- **驾驶评分 `ScoreSection`**：三个维度（续航达成 / 读数一致 / 稳定），**算不出来就是 nil**，
  不装成「没有这回事」；页面末尾还写明「这一页量不出来的东西」。
- **消息 `MessagesSection`**：车的事件流（点火 / 熄火 / 告警…），分段控件 + 标签胶囊过滤。
  事件流同时是**行程生成的唯一数据源**。

`.parking` / `.score` / `.dashboard` 都是别名 → 落到同一页。

### 4.6 我的档 —— `MineView`（设置 / 应急 / 诊断）

- **设置 `MineView`**：Apple Profile 风格身份卡 + 车辆卡（切车 `selectCar`）+ 设置分组（退出登录、
  检查更新） + **家庭管理 `FamilyManagementView`**、**临时钥匙 `TempKeyListView`**、
  **隐私面板 `PrivacySection`**、**月报 `MonthlyReportSection`**、Siri 卡片入口、真开关（低电量省电 / 夜间模式）、
  **背景图小卡（`wallpaperRow`，2026-09-24 第六/七轮；2026-09-25 加两个在线源）** ——
  「应用」组里一行，形如 iOS 设置的值选择器：左边「背景图」，右边 `Picker`（`.menu`）
  三选一 —— 相册自选 / 必应每日 / Windows 聚焦；下面缩略图（120pt）+ 相册那一档才有
  的「选一张」（`PhotosPicker`）+ 有图时才有「不铺」+ 一句来源说明；取图失败时多一行
  「取图没成功，先铺画布底色」，在线图另附图源给的署名。
  它改的是 App 自己的背景，不是系统的（iOS 没有读主屏壁纸的公开 API），所以与
  「设备与模式」组（改系统的：夜间 / 省电 / 专注）不并列。
- **应急 `EmergencyPanel`**：SOS 按钮 + 快捷操作 + 紧急联系人 + 位置共享 + 紧急叠加层。
  2026-09-25 拆掉三层页壳：`ScrollView`（里外两层都能滚时手势塌给内层，而内层拿到
  无限高、永远滚不动）、页边距（卡 18 + 页 20 = **38pt**，全 App 最窄的一张）、
  页标题（卡头写「应急」，正文再写一遍「紧急求助」）。页边距只属于真正的整页。
  代价说明：从「1 次拖动」变成「1 次拖动 + 1 次点击」，但 SOS 也仍然在地图操作条上。
- **诊断 `DevView`**：运行状态 / 能力位图（`car.funCode`）+ **消息自检 + 原始日志**
  （两台仪器并排在同一个 `diagnosticsGroups` 里）。
  （2026-09-25 拆掉 `ScrollView` + 页标题「设计令牌」，滚动归叠叠乐。）
  ⚠️ **同日第九轮第 6 条把六组「与界面本身有关」的东西整块删掉**：卡片叠预览
  （`StackLabView` 整页）、画布与表面色板、语义色色板、字体样张、几何数值、动效数值。
  那一页的名字叫诊断 —— 诊断回答「这台设备此刻在发生什么」，不是「我们的设计长什么样」。
  （「艺术主题样张」`ThemeGallerySection` 更早一轮就已删 —— 主题只剩原生一种。）
  它们是为同一类抱怨造的：「消息拿不到数据」。
  · **消息自检**（`MessageProbeSection`，2026-09-24）：一次发三种窗口（30 天一段 /
    30 天分五段 / 7 天一段）、共七次请求，把四个数并排报出来 ——
    **HTTP 状态 / 响应字节数 / 服务端自报条数 / 我们解析到的条数**。
    分得清那四种长得一样的失败：请求没发出去、被拒、服务端说 0 条、有 55 条而解析成 0 条。
    它走 `APIClient.probeMessageWindow`：**不合并、不兜底、不重试**，要的就是没加工的那份。
  · **原始日志**（`RawLogStore`：最近 60 条请求/响应，已打码，可一键复制）：
    那份日志**一直在写，却没有任何界面在读它**，于是每次「拿不到数据」都只能猜。
    再报这类问题时，先看这一组里那条请求的 status 与响应长度。
  · **上一次启动**（`StartupJournal`，2026-09-24）：启动阶段的路标轨迹。
    没有收尾标记 = 上一次没走完，最后一行就是它死前到达的那一步。
    那一行里的两个数是这一组存在的理由：**常驻内存**与**距上限还剩多少**
    （`os_proc_available_memory()`，系统直接给出的额度）—— 后者才是判据，因为
    RSS 单独看回答不了「这算不算高」（4 GB 与 8 GB 的机器、前台与后台额度不同）。
    组内第一行给的是 `previousRun().verdict`：已经算好的**一句结论**
    （被信号终止 / 像是被内存杀掉 / 不像内存的事 / 走完了），不再要人拿对照表去推。
    它存在的唯一理由是：系统级处决不会留下任何东西（见 §6.1）。

### 4.7 不是档位的屏（各有一处入口，不再重复）

| 屏 | 怎么到 | 说明 |
|---|---|---|
| `SplashView` | 冷启动 1.5 秒 | 之后再判断进登录 / 引导 / 主屏 |
| `OnboardingView` | 未登录且没看过引导 | 键 `carkeeper_onboarding_seen` |
| `LoginView` | 未登录 | 手机号 + 短信码 + 图形码；`TokenStore.save` 后进主屏 |
| `GlobalSearchHUD` | 地图工具栏 / 我的 | `fullScreenCover`（不是 sheet）；搜页面、车牌、行程、指令；空态文案分「还没输」与「没匹配」两种情况 |
| `BiometricLockOverlay` | 敏感页二次验证 | `RemoteLockManager` 后台超时自动隐藏 |
| ~~`ThemeGallerySection`~~ | ~~诊断档~~ | **已删除（2026-09-25）**，随艺术主题整份删除 —— 它列的是 20 套可切换方向，而方向只剩原生一种 |
| `PrivacyDashboardView` | 我的 | 三类：留在本机的 / 离开本机的 / 没在收集的 |

---

## 5. 设计系统

### 5.1 三层，严格单向

```
Tokens（静态令牌，唯一来源） → DS 原语（唯一容器/分组形态） → 页面
  （2026-09-25 之前中间还有一层 `ArtTheme`：20 个方向 = 一整套取值。
   用户定下只用原生后这一层整份删除 —— 见 §5.2、§17.1）
```

- **`Design/Tokens.swift`**：`TokensPalette`（颜色）/ `TokensSpacing`（4 的倍数，页面边距 20；
  2026-09-25 补上缺的一档 **12 = `snug`** —— 原先全 App 有十几处用字面量 `10/11/12` 去凑它）/ `TokensRadius` /
  `TokensTypo`（字号）/ `TokensMotion` / `TokensHaptic` / `TokensHair`（发丝线）/ `TokensSize` / `TokensTracking`
  （`TokensSerif` 衬线标题 2026-09-25 随艺术主题一起删 —— 它服务的「艺术方向下把标题搬进版面」那条路不存在了）。
- **`Design/DS.swift`**（1077 行）：唯一一套容器与排版原语 —— `DSCanvas`、`DSCard`、`DSGroup`/`DSGroupRow`、
  `DSSection`（唯一的分组形态，inset-grouped）、`DSKeyValueRow`、`DSBigNumber`、`DSLightBar`、`DSStatStrip`、
  `DSSegmented`、`DSChip`、`DSNotice`、`DSPlaceholder`、`DSSkeleton`、`DSExpandGroup`（唯一的折叠）、
  `DSPrimaryButtonStyle`、`DSRowButtonStyle`、`DSSurfaceModifier`……
  · **2026-09-25 删掉的三个**：`DSPaperPage` / `DSPaperPageModifier` / `dsPaperPage()`（全页「纸」外壳）
    与 `DSPageTitle`（艺术方向下画在版面里的页标题）。它们的用户全是**卡里的正文**
    （体检 / 保养 / 诊断 / 应急），而卡里的正文不该再套一层页面 —— 那是双重内边距
    （卡 18 + 页 16/20）与「一个东西两个名字」（卡头 + 页标题）的来源。
    真正的整页（登录 / 引导 / 开场）不用它们：它们本来就只有导航栏。
- **`Design/Theme.swift`**：`AppCanvas`（画布与光**在根部只画一次**）、`StatusDot`、`Pill`、
  `MonthlyReportSection`。（`PowerSavingToggle` 2026-09-25 第九轮随「设备与模式」删除。）
- **`Design/Charts.swift`**：`DSTrendChart`（单序列，SOC / 功率共用）、`DSTyreTrendChart`（四条曲线）、
  `DSTrendEmpty`（数据不够时的说明，不是灰块）。
- **`Design/StackSpec.swift`**：那一叠剩下的那点几何 —— **只有 `Card`（圆角、内边距、
  左右外边距、卡片间距）与 `settle`（无障碍翻页那一下）**。间距要调就改这里，
  不要到页面里改一个局部数字。
  2026-09-25 这个文件从「七种叠法的一张表」缩成一张卡：`StackVariant` / `StackMetrics` /
  `StackKind` / `variantKey` / `chosen` / `remember` 全删 —— 用户 09-24 删到只剩一种叠法，
  09-25 滚动本身又交回系统，「叠法」这件事已经没有可选项（见 `ArcStack` 头注）。
  同一轮删掉的还有阅读线、消失带与两端留白：它们都是自管滚动时代的产物。
  要找回那七种的参数，看删掉它们的那次提交。
- **`Design/CardFit.swift`**（411 行，2026-09-25 新增）：**「展开后有多挤」的唯一算法** ——
  行高取自 `UIFont.preferredFont(forTextStyle:).lineHeight`（当前动态字号下的真实值）、
  折行数取自 `NSString.boundingRect`（真量，不是字数÷每行字数）、可用高度取自
  `ArcStack` 量到的视口（环境值 `\.cardViewport`）。产出 `Verdict`（占几屏）与
  `Plan`（`.all` / `.chunk(keep:rest:)`，`keep` 是逐行累加真实高度得出的）。
  出口只有 `DSCardMoreRow`（「还有 N 条 · 展开后约 M 屏」）—— 摊开与收起来必须是同一行。
  视口量不到时返回 `.unknown` 并**放弃分块**：不允许把「不知道」当成「放得下」。
  守门人是 `scan/expand.py`（编号 26）。
- **`Design/DSGlass.swift`**（2026-09-25 新增）：**「浮在内容之上」那一层的唯一材质** ——
  `dsGlass(in:interactive:hairline:)` 与两个便捷写法（胶囊 / 圆角矩形）、
  以及 `dsGlassLayer(spacing:)`（多块玻璃包成一层，`GlassEffectContainer` 的入口）。
  三层规则写在文件头：浮层 → 真玻璃；**卡里不玻璃**（叠玻璃会糊成一片）；内容表面不玻璃。
  **材质只有一档 `.clear`**（2026-09-26 第二轮：`variant:` 参数与 `DSGlassVariant` 一起删 ——
  用户定的「玻璃就默认选更透」，见 §35.3），可点的表面交 `interactive`（按压由系统演，
  不再自己压透明度）；「降低透明度」那一档由文件里那条 `UIAccessibility` 分支接。
  守门人是 `scan/glass.py`（编号 28）。
- ~~**`Design/StackLabView.swift`**~~：卡片叠预览页 —— **2026-09-25 第九轮整份删除**。
  用户第 6 条（「诊断里面删除一切和 UI 相关的」）把它连同四组色板、字体样张、几何与动效
  数值一起移出了「诊断」：那一页的名字叫诊断，诊断回答的是「这台设备此刻在发生什么」，
  不是「我们的设计长什么样」（理由见 §20.5）。
- **六个功能界面共用的三个原语**（阶段 1 的产物，职责分得很硬）：
  `GlassCard`（一张卡的材质与内边距） → `ArcStack`（**只有系统滚动** + 无障碍翻页）
  → `StackPageView`（那一叠 + 页面的个性色） → `DSSwipeStrip`（底部那条相机式模式条，已重写）。
  `ArcStack` 收的是**未包装的 `StackCard`** 而不是 `AnyView` —— 卡片的类型本来就不同
  （巨字头 / 图表 / 列表），而顺序是运行时可变的（分段控件换段、行程条数随数据变）。

**铁律（`scan/design.py` 在 CI 上拦）**：字号与颜色分量只允许出现在令牌定义文件里。
不许在页面里写 `.font(.system(size: 14))` 或 `Color(red:...)`。

**颜色从哪来**：`TokensPalette` 是**主题相关**的静态计算值，所以切主题靠
`CarKeeperApp` 上的 `.id(artThemeRaw)` **重建整棵树**才生效（令牌不产生 SwiftUI 依赖）。

### 5.2 艺术主题（2026-09-25 **已整份删除**）

这里曾经有 **20 套可切换的艺术方向**（夜光 / 纸上 / 巨字 / 原生，外加第八轮头脑风暴补的
16 套），每套是**一整套取值**（画布 / 表面 / 字 / 强调 / 装饰 / 字重 / 明暗 / 六页个性色），
外加一页「主题样张」与一个横向可滑的切换器。

**2026-09-25 用户定下「主题用原生，其他 19 套全删了」**，于是：

| 删掉的 | 它原来做什么 |
|---|---|
| `Design/ArtTheme.swift` | 20 个方向的取值表 + `ArtThemeStore` + `ArtThemeSpec` 便捷构造（一次算齐 15+ 字段） |
| `Features/ThemeGalleryView.swift` | 诊断档里的主题样张页（20 枚胶囊 + 小界面样本） |
| `Design/MapStyleSpec.swift` | 把主题翻译成 MapKit 旋钮（见 §5.3） |
| `Design/SkyOverlay.swift` | 光池 / 雾霭 / 暗角 / 颗粒 / 发丝网格五个**装饰**图层 |
| `TokensSerif` / `CanvasDecor` / `preferredScheme` | 衬线标题 / 画布装饰 / 主题自带明暗 |

**留下的**：`TokensPalette` / `TokensTypo` 等的取值**直接写在这一处**（回到 v4 的样子），
不再往外转一层 —— 「只有一种取值的开关就是一层假的选择」。两个原来由主题提供的计算值
（`artHex` 解析、`nativeDynamic` 动态色）**原实现原取值搬进 `Tokens.swift`**；
`Design/Theme.swift` 只剩画布与光；地图回到**系统原样**（不再压暗、不再盖蒙版、车钉只有一种）。

顺手治了一处**说谎的指针**：`SkyLight.swift` 与 `WeatherService.swift` 的「命名：顶层类型，
不嵌套泛用名（历史事故见 ArtTheme.swift 的说明）」指的是一份已删的文件 —— 已改指
`Tokens.swift` 的文件头（那里的记录一直在，只是换了住处）。

### 5.3 地图样式（2026-09-25 **已删除**）

这里曾经有一张「主题 → MapKit 旋钮」的对应表（`Design/MapStyleSpec.swift`：蒙版 scrim /
不透明度 / `cameraHeading` / 三种车钉 `.ring`·`.ink`·`.rule` / 发光开关）。
二十套里**十九套其实共用同一行参数**（`muted` + 色温蒙版），差别只在蒙版色上。

**2026-09-25 随主题一起删**：地图现在**就是系统地图**（`.standard` 不传参 = 系统默认），
车钉只剩一种。`MAPKIT-FEASIBILITY.md` 保留 —— 它研究的是 **MapKit 到底有几个旋钮**，
那些结论与「我们用不用它们」无关，文件头已注明它的服务对象已删。

### 5.4 光（这个 App 的「颜色来自天上」的部分）

- **`Design/SkyLight.swift`**：真实太阳位置算法（赤纬 / 时差 / 高度角 / 方位角，NOAA 级公式）→
  `SkyPhase` 六相（白昼 / 低角度日光 / 日出日落 / 民用暮光 / 蓝调 / 深夜）；
  **晴空模型 1050 × sin(高度角)**；**云量衰减 `G = 晴空 × (1 − 0.75 × N^3.4)`**（N = 云量 0…1）；
  `SkyFact` 是「为什么现在是这个光」的逐条事实（地图的 `lightPill`/`skySheet` 展示它）。
- **`Services/WeatherService.swift`**：`api.open-meteo.com`（免 key）。WMO 天气码 → 中文。
  **取不到就退回晴空模型，并在界面上照实写明「上面是晴空模型的算法值」**——不拿默认值冒充实况。
- **`Design/SkyOverlay.swift`（已删）**：光池 / 雾霭 / 暗角 / 颗粒 / 发丝网格五个装饰图层 ——
  2026-09-25 随艺术主题一起删。留下的 `SkyLight` 不是装饰：它是**算光的**（太阳位置 → 六相 →
  云量衰减），地图车钉的 `lamp` 与「光」表都还在读它。
- 纯函数部分有单元测试：`Tests/PureLogicTests.swift`（太阳位置、云量衰减、充电站聚合）——
  **只在开发机的 Xcode 上跑**（CI 的测试 job 已按成本考量删除）。

---

## 6. 本机持久化清单（27 个 `carkeeper_*` 键）

> 判据：**服务端有这个字段吗？** 有 → 不落盘；没有（只能本机攒）→ 落盘，并在文档与界面上说清它是本机的。
>
> ⚠️ **这张表是 `scan/localstore.py` 的唯一真值**（它不是另抄一份清单：门禁直接读这张表，
> 与 `scan/all.py` 从工作流里解析门禁清单同一个做法）。三条判据：
> ① 代码里出现的每个 `carkeeper_*` 键都必须在这张表里（否则「新加的键没人给它定性」）；
> ② 标了「账号」的键必须在**退出登录**时被清掉（清的人是 `logout()` 自己，
>    或它调用到的某个 `clear()` / `resetAll()` —— 见门禁文件头）；
> ③ 表里写着的键必须在代码里真的存在（否则就是这份清单在说谎 —— 它以前就说过：
>    `carkeeper_art_theme` 随艺术主题删除后还在表里，而表的标题写着「42 个」而实际是 33 个）。
>
> 全名写、不写简写（早先用过 `carkeeper_parking_loc` / `_time` / `_points` 这种缩写，
> 代价是**这张表根本没法机械对账** —— 简写只有人能补全，而人不会每次都补）。

| 键 | 它是什么 | 归属 | 退出登录清 |
|---|---|---|---|
| `carkeeper_selected_car_id` | 上次选中的车（重启后回到那一辆） | 账号 | ✅ |
| `carkeeper_hist_soc_v1` | SOC 曲线（5 分钟一个 ≈ 7 天） | 账号 | ✅ |
| `carkeeper_hist_power_v1` | 充电功率曲线（1 分钟一个 ≈ 25 小时） | 账号 | ✅ |
| `carkeeper_hist_tyre_v1` | 胎压曲线（30 分钟一个 ≈ 16 天） | 账号 | ✅ |
| `carkeeper_processed_event_ids` | 行程去重台账（服务端每次返回同一个 7 天窗口） | 账号 | ✅ |
| `carkeeper_parking_loc` | 最近一次停车位置 | 账号 | ✅ |
| `carkeeper_parking_time` | 最近一次停车时刻 | 账号 | ✅ |
| `carkeeper_parking_points` | 停车点序列（≥2 次成「常停热区」） | 账号 | ✅ |
| `carkeeper_last_service_mileage` | 上次保养里程（本机记录） | 账号 | ✅ |
| `carkeeper_service_reminders` | 保养项与上次/下次（清掉回落到出厂周期表） | 账号 | ✅ |
| `carkeeper_service_timestamp` | 维保时间戳 | 账号 | ✅ |
| `carkeeper_current_mileage` | 里程（上一次取到的那个数） | 账号 | ✅ |
| `carkeeper_total_mileage` | 总里程（保养计划的基线） | 账号 | ✅ |
| `carkeeper_mileage_entries` | 里程账本 | 账号 | ✅ |
| `carkeeper_maintenance_photos` | 保养单据照（base64） | 账号 | ✅ |
| `carkeeper_insurance_policies` | 保单 | 账号 | ✅ |
| `carkeeper_inspections` | 年检记录 | 账号 | ✅ |
| `carkeeper_biometric_setup` | 生物识别已设置 | 设备 | ❌ |
| `carkeeper_home_mode` | 上次停留的档位 | 设备 | ❌ |
| `carkeeper_map_layer` | 地图「现在」层的子层 | 设备 | ❌ |
| `carkeeper_map_drawer` | 地图抽屉拉出来了没有（2026-09-25「给它一点记忆」） | 设备 | ❌ |
| `carkeeper_home_card_order` | 首页卡片顺序 | 设备 | ❌ |
| `carkeeper_force_dark_mode` | 明暗偏好：强制深色（唯一出处是「我的 → 夜间模式」） | 设备 | ❌ |
| `carkeeper_onboarding_seen` | 引导页看过 | 设备 | ❌ |
| `carkeeper_wallpaper_source` | 子页壁纸的来源（必应 / Windows 聚焦 / 相册） | 设备 | ❌ |
| `carkeeper_wallpaper_stamp` | 子页壁纸的日期戳（同一天不重复取） | 设备 | ❌ |
| `carkeeper_wallpaper_credit` | 子页壁纸的署名（必应/聚焦要求显示） | 设备 | ❌ |

> 「归属」列的定义：**账号** = 换一个账号登录后它必须消失（否则要么是隐私泄漏，
> 要么是拿上一个账号的数当自己的用）；**设备** = 这台机器上的偏好，与谁登录无关。
>
> 一句话判据（写代码时用它）：**这条数据是关于「车/人」的，还是关于「这台手机」的？**

### 6.0 这张表被对抗式审核修过一次（2026-09-25 第七轮）

那一轮把「表里标 ✅ 的键」与「`logout()` 真的清了什么」对了一遍，查出 **8 个标了 ✅
却没人清**的键 —— 三条后果：

| 漏掉的键 | 换账号后会怎样 |
|---|---|
| `carkeeper_parking_points` | 地图「停车」层的钉与「常停热区」显示**前一个账号**去过的地方（位置隐私）。上一版清了停车位置（单数）与时刻，漏了这个数组 —— 而 `parkingHistory` 是从磁盘现算的，清内存没用 |
| `carkeeper_maintenance_photos` | 前一个账号拍的保养单据照仍在，新账号直接看得见 |
| `carkeeper_inspections` | 年检记录跨账号可见 —— 而且它还有 **@Published 内存副本**：只删键的话，同一次运行里仍然看得见（下次启动才「自动消失」，那是重启的功劳） |
| `carkeeper_processed_event_ids` | **清派生却留台账**：`tripHistory` 被清空、台账里那 7 天窗口的事件仍是「已处理」→ 重新登录后行程页一直是空的（数据再也重建不出来） |
| `carkeeper_service_reminders` / `carkeeper_current_mileage` / `carkeeper_total_mileage` / `carkeeper_service_timestamp` | 里程与保养基线是**上一辆车**的，「距下次保养还有多少公里」跟着错（`last_service_mileage` 当时已清 —— 只清一套里的一个，等于没清） |

所以这张表现在有门禁；改代码时**先改这张表**（键的归属是设计决定，不是实现细节）。

**已删除、不要加回来的**：`carkeeper_display_glow` / `carkeeper_glass_level` /
`carkeeper_glass_fill`（「设置 → 显示」那一节，用户 2026-09-26 第 2、3 条：
文字发光整块删除、玻璃定为「更透」、界面实度定为 50% —— 三行设置连同唯一的读者
`DisplaySettings` 一起删，见 `Tokens.swift` 里那两段说明）,
`carkeeper_api_stats` / `_page_metrics` / `_home_load_time` /
`_version_logs` / `_crash_log`（诊断统计，用户明确要求删）、`carkeeper_art_theme`
（随艺术主题整份删除）、`carkeeper_encryption_key` / `carkeeper_key`（PIN 现在在 Keychain）、
`carkeeper_checkin_count` / `carkeeper_last_checkin`（「上车打卡」已删）、
`carkeeper_siri_usage`（Siri 统计已删）、`carkeeper_current_speed`（唯一读者
`FocusModeManager.isDriving` 已删 —— 它当年读的就是这个**从来没人写**的键）、
`carkeeper_family_members` / `carkeeper_temp_keys`（家庭管理与临时钥匙，用户第 7 条：
整块功能删除）、`carkeeper_voice_enabled`（语音播报，同上）、`carkeeper_focus_mode` /
`carkeeper_shake_to_lock` / `carkeeper_power_saving` / `carkeeper_force_light_mode`
（「设备与模式」那一节，用户第 4 条：整节删除 —— 四个开关各自的实现文件
`FocusModeManager` / `GestureEnhancements` / `NightModeManager` 一起删）,
`carkeeper_dnd_mode` / `carkeeper_charge_complete_notify` / `carkeeper_next_service_date` /
`carkeeper_last_charge_alert`、`carkeeper_night_start_hour` / `_end_hour`、
`carkeeper_hist_*`（旧的不带 `_v1` 后缀那批）、充电账本，以及 App Group 里的
`widget_*` / `watch_*` 共享快照（小组件体系已删）。

### 6.1 三个例外文件（不是 UserDefaults，也不是业务数据）

· `Documents/carkeeper-startup-journal.txt` 与 `-prev.txt`（`Services/StartupJournal.swift`）。
  2026-09-24 新增：用户报「App 载入不到 10 秒就闪退，而**系统里没有日志**」。
  没有日志本身就是诊断信息 —— 应用层错误通常会留一份 `.ips`；什么都没有，
  通常意味着**系统级处决**（内存回收 / 看门狗），而那种终止**不调用 App 里任何一行代码**，
  所以只能把路标写在死之前。

  与上面那个被删的 `_crash_log` 的区别是硬性的，三条都写进了 `StartupJournal` 文件头：
  **不收集业务数据**（只有阶段名 + 相对秒数 + 内存两个数）、**不累积**（只留上一次与这一次，
  每份上限 4 KB）、**不上业务界面**（只在「我的 → 诊断」里，没有统计。只显示、可复制）。

  > 这也是为什么它现在是**唯一**能看到那类闪退的地方：系统那份报告要先把
  > 「设置 → 隐私与安全性 → 分析与改进 → 共享 iPhone 分析」打开（关着时 iOS 不保留报告），
  > 打开的盘以后再复现，才能拿到 jetsam / watchdog 的权威记录。在有它之前，我们有轨迹。
· `Documents/carkeeper-wallpaper.jpg`（`Services/WallpaperService.swift`，2026-09-24 第七轮）：
  相册选的一张壁纸图（JPEG 0.82），子页面铺底用。「不铺」钮删它；不是业务数据、
  不跨启动累积（每次选都整张替换）。

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
| `PhoneLocation` | **手机自己的位置**（CoreLocation）：按需要权限、取到就停、拿不到就如实说（`idle/asking/denied/locating/found/failed`）。全仓唯一的 CoreLocation 代码（地图右侧那枚「手机的位置」）| 用户按下那枚钮 |
| `WallpaperService` | 子页面壁纸图（相册选的一张 JPEG，本地存 `Documents/carkeeper-wallpaper.jpg`，不依赖网络） | 「我的→设置」选一张/不铺；启动时读回 |
| `RefreshLoop` | **自动刷新的节律**（地图 2s/15s、其余档 60s 轻 + 5 分钟重、手动「全局刷新」= 全部接口） | 根视图启动时 `start()`（幂等） |
| `Retrier` / `NetworkEnhancements` | 退避重试 / 网络质量监控 / 离线模式。⚠️ `NetworkEnhancements` 里原本还有一套 `RetryConfig` + `URLSession.dataTaskRetryable`，2026-09-25 删（**第二套重试实现**且零读者；真正在用的是 `Retrier.global`，见 §4 请求层） | 请求层 |
| `Monitoring` | 内存读数（**不落盘**） | 启动后每 10s |
| ~~`DataEncryption` / `SecureStorage`~~ | 已删（2026-09-25） | 只写不读的加密壳，见 §9.3 |
| `BiometricLock` / `RemoteLockManager` | FaceID 二次验证 / 后台超时隐藏 | 敏感页 / 启动 |
| ~~`NightModeManager` / `FocusModeManager`~~ | 夜间时段 / 专注模式 —— **2026-09-25 第九轮删除**（用户第 4 条删「设备与模式」，明暗改由系统决定） | 已无 |
| ~~`GestureEnhancements` / `ShakeDetector`~~ | 摇一摇锁车 —— **同日删除**（同上） | 已无 |
| ~~`FamilyAndKeySharing`~~ | 家庭成员 / 临时钥匙 —— **2026-09-25 第九轮删除**（用户第 7 条） | 已无 |
| `InsuranceManager` | 保单 CRUD | 保养档 |
| `BillingAndCalendar` | 车辆估值 + 年检日历（估值是**估算**，不是市场价，界面写明） | 保养档 |
| `UpdateService` | 检查更新（读 GitHub Release `latest`）+ 分享 | 我的档 |
| `AppStore.ToastManager` | 全局提示（**唯一**一条：`EnhancedToastManager` 2026-09-25 已删 —— 16 处调用写给一个没有任何视图渲染的 `@Published`，等于按了按钮什么都不弹；浮层现在住在 `MapSpineView` 里，抬在底条之上） | 全局 |
| `RawLogStore` | 请求/错误原始日志（排障） | 请求层 |
| `MD5` | 登录签名 `signF` | 认证 |

---

## 8. 工程约束与门禁（31 项 + 风格检查）

### 8.1 门禁表（每一项都是某次真实事故的产物）

编号 = `.github/workflows/ios-build.yml` 里那条 `for s in …` 的**顺序**（`scan/all.py`
就是照它跑的）。所以新加一条就接在末尾 —— 老记录里「第 N 条」是当时手数的，
`spacing` 插进清单中段之后全部后移了一位，以这张表为准。

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
| 12 | `futureproof.py` | 未来系统版本（iOS 27/28）前瞻性审计 + 根目录必须存在。判据是「对**系统**的弹性枚举做穷举 switch 却不写 `default`」—— 2026-09-25 修了一处假阳性：它原来只看主题词的**拼写**，而表里有 `status` / `phase` / `configuration` 这类普通名词，于是 `switch phone.status`（我们自己的 `PhoneLocation.Status`）被要求补 `@unknown default` —— 对自己的枚举补它是**反的**（会把「新增一档时编译器提醒你改这里」一起关掉）。现在两个条件都要：主题词命中 **且** 主语里没有项目自己声明的类型名，且那三个普通名词已从表里拿掉。代价写在文件里：真遇见「成员名叫 `status` 的系统枚举」会漏报 —— 方向是「宁可漏，不可噪」。探针：注入一个真的 `switch scenePhase`（无 default）→ 当场报出；还原后文件哈希一致、转绿 |
| 13 | `orphans.py` | 两条判据。① 孤儿页面：「写了但没有任何地方能到达」（只认顶层类型）。② **系统类型扩展里没人读的成员**（`extension X` 里 `X` 不是项目自己声明的类型，而成员名在全仓除声明外一次都没出现）。② 是 2026-09-25 补的：那时删掉底条自算档位那段代码后，文件层的 `private extension Double { func clamped(to:) }` 成了「声明在、没有读者」—— 而它前面 31 条门禁一条都看不见（判据 ① 只认顶层类型）。加上判据 ② 的当场报到两个真的：`URLSession.dataTaskRetryable` + `RetryConfig`（**第二套重试实现**，App 真正走的是 `Retrier.global`）与 `UIColor.dsDynamic`（**第二套动态色**，全 App 用的是 `TokensPalette.nativeDynamic` —— 原名
`ArtTheme.nativeDynamic`，2026-09-25 随那个文件搬进 `Tokens.swift`）。收窄三条写在文件里：名字短于 6 个字符不看、读者只按「名字出现过」数（保守方向，宁可漏报）、`DerivedData/` 不算读者。探针验过：注入 `extension Double { func probeDeadMember() }` → 当场报出那个文件与成员名；还原后文件哈希与注入前一致、转绿 |
| 14 | `deep.py` | 更深的结构问题：SDK 同名遮蔽、协议一致性、闭包参数、清洗保真度 |
| 15 | `eol.py` | committed blob 的字节级行尾问题（字面量里裸换行 / 行中裸 CR / `\r\r\n`） |
| 16 | `oneentry.py` | **入口唯一性**：同一件事只准有一条到达路径。判据 ③ 是「档位在 `HomeModeHead` 里出现**恰好一次**」——0 次 = 加了档位卡头没跟上；≥2 次 = 同一档有两处表述（原判据是「< 2 报错」，2026-09-24 定义反了，见 §11） |
| 17 | `traps.py` | 编译得过但真机一走到就崩的构造（`hashValue` 参与算术、强解包、`try!` / `as!`） |
| 18 | `scopeguard.py` | 名字在项目里、但在调用点不在作用域（跳类型调静态成员必须带前缀） |
| 19 | `paidcap.py` | 免费账号用不了的能力（entitlements 白名单 / Info.plist 禁键 / 禁 import / target 白名单） |
| 20 | `copy.py` | 界面文案三类判据：实现词（缓存/报文/字段/接口）不上界面、复述句式、超 30 字 |
| 21 | `lintcfg.py` | `.swiftlint.yml` 的排除清单与阈值必须和真实文件树一致 |
| 22 | `ternary.py` | 三元运算符的 `?` 不能贴住前一个 token（否则变可选链）—— 见 §11 事故记录 |
| 23 | `delguard.py` | **删了声明、使用还在**：旧版本里成员级声明过、新版本里没有声明了、代码里还在用它（`pvValue` / `shapeScroll` / `messageWeeks` 三次事故的根因）。**跨文件**：声明在 A、使用在 B 也算（B 里的用法只认带前缀的那种）—— 它自己的两个盲区都是 2026-09-24 当场补的。2026-09-25 又补了**两条收窄**（判据 ④ / ⑤）：删 `StackMetrics.padTop/padBottom`（自管排版的死字段）时它把三处**别的类型**的同名成员当成残留引用报了出来 —— 使用处文件自己声明了同名成员（`CardFit.Row`）不看，`A.B.name` 里紧挨着名字的那段是项目类型（`StackSpec.Card.padTop`）也不看；而历史那三次（`APIClient.messageWeeks` 这种一段前缀）照旧报。同一天还查出一条**文档说谎**：文件尾那两条 `--from/--to` 自测在两种取法下都是绿的（旧版里那两个名字的声明缩进比 4 深，判据 ① 当场就找不到），已换成两条今天真能跑的探针 |
| 24 | `enumguard.py` | 表驱动调用族的 SDK 枚举简写必须是已核成员（`accessibilityAction` / `textCase` / `accessibilityElement(children:)` / `scrollBounceBehavior`） |
| 25 | `spacing.py` | 界面代码里的间距必须是 `TokensSpacing` 那一档（字面量只允许 0/1 与四个**几何值** 18/20/40/108，逐条写明理由）。它是 2026-09-25「所有页面的间距布局都很不 iOS」那一轮的守门人：先吸 111 处字面量、补刻度缺的 12（`snug`），再把它固定下来 |
| 26 | `expand.py` | **展开类内容不许写死高度**：界面代码里不得出现 `frame(height: 数字)`（只给高度、没给宽度的那种；`frame(width: 44, height: 44)` 是形状，不管）。例外表 11 条，键是「文件:值」，每条都写清「为什么这个高度是画出来的」（图表 / 指示线 / 样例色块 / 缩略图），**一条不再成立就报红**。它是 2026-09-25「展开后的拥挤程度要完全根据数据算」那一轮的守门人 |
| 27 | `printguard.py` | App 与 Services 里不得出现 `print(`（例外只有设计令牌页）。它是 2026-09-25 那一轮的守门人：全仓仅有的两处 `print` 都是「提醒没发出去」——`print` 的问题不是吵，是**没有读者**（那条路径写进了「诊断」在读的日志） |
| 28 | `glass.py` | **玻璃只有一个入口**：`.glassEffect` / `GlassEffectContainer` 只许出现在 `Design/DSGlass.swift`；玻璃底下不许垫不透明的面（同一条链里 `.fill(TokensPalette.…)` 出现在 `.dsGlass` 之前即报红）；不许再引入旧材质语言（`…Material`）。它是 2026-09-25「全局液态玻璃的质感全项目每个犄角旮旯方方面面都做到位了吗」那一轮的守门人：那一轮查出真玻璃只有 3 处，其余浮层用的都是「名字叫 glass、值等于 `fillSubtle`」的扁平令牌（该别名已删），另有两处把玻璃**垫在不透明的面底下** |
| 29 | `extguard.py` | **extension 的三条铁律**：① 必须在文件层（不许嵌套）；② 直接成员层不许有实例存储属性（`static` 放行）；③ 跨文件不许碰别处的 `private` / `fileprivate` 成员。它是 2026-09-25 那次 CI 红的产物：`MapSpineBottomBar.swift` 一台戏犯了三条（嵌套的 `private extension Double`、`@State` 存储属性、读写四个 `private` 成员），而 29 条门禁一条都没拦住 —— 因为没有任何判据知道「extension 该长什么样」 |
| 30 | `initguard.py` | **调用点的实参标签必须能被某个声明的 init 接下**。三条收窄（宁可漏，不可噪）：只判「init 写在类型**体内**」的类型（写在 extension 里不会抑制隐式 memberwise init，那时按参数表判会误报）、只判至少两个带标签实参的调用点（`Foo(x)` 与 `init(_:)` 从文本上分不开）、同名类型多处出现就整条跳过（裸名字对应哪一个要看调用点上下文）。它是 2026-09-25 第二批 CI 红的产物：`ArtThemeSpec` 四处「参数全对、却没有任何 init 收得下」——根因是 Swift 那条规则：结构体一旦自己声明了任何 `init`，编译器就不再合成 memberwise init。它诞生当天被自己的**两条误报**教过（嵌套类型的 init 被算到外层；`TripRecord` 同名两个），两条都写在文件头里 |
| 31 | `iconcheck.py` | **图标**：`Contents.json` 与 PNG 必须说同一件事。五条判据 —— 文件都在 / 声明尺寸 × scale == 实际像素 / 每个槽位有浅色·深色·着色三套 / 三张 1024 主图满幅（不带透明，四角与四边中点各与相隔 64px 的内侧色差 ≤ 14） / 没有没人引用的 PNG。它是 2026-09-25「图标完全不符合 iOS 调性」那一轮的产物：v1.0 犯了三个**可量**的错却编译得过、当时 31 条门禁全绿（自己套圆角 + 内缩 4%；`convert('RGB')` 把透明边压成纯黑、实测四角 (0,0,0)；只有一张图、没有深色/着色外观）。**它自己读 PNG**：`scan/copy.py` 与标准库 `copy` 同名会把 Pillow 的 XML 依赖打坏（`AttributeError: module 'copy' has no attribute 'deepcopy'`），所以 scan/ 里任何 `import PIL` 的门禁都跑不起来 —— 解码器与 Pillow 逐点比对过。探针验过：换回 v1.0 的 1024 → 报出 4 条（左右边中点 (0,0,0) vs 内侧 (255,159,0)，色差 255）；多一张没人引用的 PNG → 报出；删掉某槽位的着色条目 → 报出 |
| 32 | `perf.py` | **「每次界面求值都会跑的那条路上，不许有一次性就能建好的东西」**。两条判据：① `DateFormatter()` / `NumberFormatter()` / `ISO8601DateFormatter()` 的构造只许出现在 `DateText.swift`（池子在那里；键是 `locale|格式`，所以有界）；② `CLLocation(` 不许造在比较/筛选/排序闭包里（按花括号配对扫到闭包结束，跨行的也认）。它是 2026-09-25「性能轮」的产物，两条都来自**量出来的**形状：全仓原有 9 处 `DateFormatter()`，其中 `MapTripLine.timeText`（`MapSpineLayers` 每段行程读一次 → 30 段 × 每 2 秒求值一次）、`VM.parseDate`（一次调用最多造 7 个，按记录调）、`RawLogStore.now()` 落在每次求值的路径上；`clusterChargers` 的判据 `out.firstIndex(where: { CLLocation(...).distance(from: here) … })` 是**每次比较**造一个对象（一枚钉子 × 每一组）。两条都**不报错、不崩、编译全过**，只是慢 —— 而慢没有输出。探针验过（双向）：池子外注入 `let f = DateFormatter()` → 当场报出该文件与行号；比较闭包里注入 `CLLocation(...)` → 当场报出；还原后文件哈希与注入前一致、转绿。例外表两处（`ALLOWED` / `COORD_ALLOWED`）都要求写明理由 |
| 33 | `localstore.py` | **本机持久化键的归属与「换账号会不会跟着走」**。真值是 `HANDOFF.md` §6 那张分类表（门禁直接读它，不另抄一份 —— 与 `all.py` 从工作流解析门禁清单同一个做法）。三条判据：① 代码里出现的每个 `carkeeper_*` 键都必须在表里（新键必须被定性：关于车/人 = 账号，关于这台手机 = 设备）；② 标「账号」的必须在退出登录时被清（清法是三选一：`logout()` 体里直接删、调一个登记过的 `clear()`/`resetAll()`、或经 setter 清并留下证人）；③ 表里的键必须在代码里真的存在。它是 2026-09-25 第七轮对抗式审核的产物：把「表里标 ✅」与「`logout()` 真的清了什么」对一遍，查出 **8 个标了 ✅ 却没人清**的键（停车史数组 → 位置隐私；保养单据照；年检记录（还有 `@Published` 内存副本，只删键不够）；行程去重台账 → 清派生却留台账，重新登录后行程再也生成不出来；里程/保养基线四项）。这些**只在换账号时才看得见**。门禁诞生当天被自己的两个洞教过：一是不认「键写在符号常量里」（`socKey` / `Self.selectedCarIdKey`，六条假阳性），二是把 `MineView.toggleVoice()` 里的局部 `let key` 当成符号常量（于是「设备键 `carkeeper_voice_enabled` 被清了」误报）—— 两条收窄都写在文件头。探针验过三条：注入新键 → 报「没定性」；从 `logout()` 里拿掉一个账号键 → 报「没被清」；往表里塞一个幽灵键 → 报「表在说谎」；三次还原哈希都一致 |
| + | `check_style.js`（node） | 风格与括号配平 |
| + | `all.py`（**本地**执行器） | 不判任何东西：把上面这份清单（从工作流解析，不另抄）一次跑齐。CI 不跑它 —— 跑第二遍没有信息量 |

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
  （这一轮真撞上了一次：`CardFit` 里那个字档枚举本来叫 `Text` —— 于是同一个文件里
  `Text` 既可能是 SwiftUI 的、也可能是字档。已改名 `Typo`。）
- ❌ 不要给**展开类**内容写固定高度，也不要写「大概放得下几条」（`expand.py`）。
  高度只有两个来源：内容自己撑出来，或 `CardFit` 按数据算（真实行高 + 真实折行数 +
  `ArcStack` 量到的视口）。看不清视口时它返回 `.unknown` 并**放弃分块** ——
  「不知道」不允许被当成「放得下」。
- ❌ 不要用 `try?` 包住「必须成功」的异步调用（`try?` 会让 `do` 体永不抛错，`catch` 变死代码）。
- ❌ 不要在页面里自己开定时器取数（每页一条 = 六个循环问同一个服务端）。节律只有
  `RefreshLoop` 一处；要改「多久一次」就改那里，别在调用点加 `Timer`。
- ❌ 不要为了「让界面好看」而给缺失数据填默认值。

### 9.3 已核实的文档/注释漂移（代码是对的，注释旧了）

- ~~`MapSpineView.swift` 头部与 `bottomPanel` 注释写「9 档」、`CarKeeperApp.swift` 写「10 档」~~
  **已改**：`bottomPanel` 这个类型本身已随结构对齐删掉，两处计数注释都改成 6 档。
  留着这条是因为它的成因还没被机制拦住 —— 「注释里的数字」没有任何门禁在盯。
- **`REDESIGN-STATUS.md` 批 3 那份「仍未做」清单已经过期了一半**（2026-09-25 逐条核过代码）：
  月报不再写死（`Theme.swift` 自己写着「曾经是 1250 km …」）、`tripHistory` 已有写入点
  （`AppStore.swift` 的 `insert(record, at: 0)`）、`"Mileage"` 那个键名在仓里已经不存在、
  `daysUntil` 走的 `parseDate` 解析不了就返回 nil。
  **没过期的那一条**：车控页还没按 `funCode` 开合控件（见 §9.1 的数据缺口）。
  教训同上一行：日志类文档写下的「仍未做」没人会回头改 —— 读它的人要自己核一遍代码。
- **`scan/scan.py` 白名单里的两句话在替不存在的用法担保**（2026-09-25 本轮清掉）：
  `accessibilityScrollAction` 那条写着「叠叠乐**没有 ScrollView**，不挂它 VoiceOver 用户完全无法翻页」——
  而那一叠现在就是系统的 `ScrollView`（三指滚动自带），那句话描述的世界已经不存在；
  `accessibilityAction` 那条也已无人调用。两条一起从白名单删除（白名单里留着不用的名字
  是另一种「清单失真」），而 `enumguard.py` 的那条教训以 `#` 注释留在原处。
  另：`interpolatingSpring` 那条的「吸附回落的弹簧」也改了 —— 它现在只服务无障碍翻页那一步。
  这一类漂移（**注释/白名单里的断言**）31 条门禁全部查不到：它们查的是代码里的名字，
  不查「这句话说的东西还在不在」。
- `DESIGN-SPEC.md` 的小节标题仍用旧页面名（如「行程页 (TripAnalyticsView)」），实际类型是 `TripsEventsView`。
- `GlobalSearchHUD` 的空态提示曾写「搜页面、车牌、行程、指令、**充电记录**。」，而充电记录随
  充电账本一起删了（代码里的注释已注明），提示却还在承诺它 —— **已改**。
  这一类「文案承诺了一个已删除的功能」的漂移，31 条静态门禁**查不到**：`copy.py` 只管词、长度与复述句式，
  不核对「这句话说的东西还在不在」。写文档时逐屏读才会碰到。

### 9.4 未验证的部分（必须如实交接）

**本地无法编译**：这台开发机没有 Swift 工具链，所以**每一次改动是否编得过，只有 CI 能回答**。
静态门禁能覆盖结构、符号、键名、文案、行尾、作用域，**覆盖不了类型检查与语法细节**——
最近一次真实事故就是一个空格（§11）。接手后第一件事建议先跑一遍 CI 建立基线。

**只能等真机的四件事**（不是没做，是这台机器上量不出来）：

1. 卡片栈的竖向滚动（现在是系统 `ScrollView`）与屏幕左缘的返回手势会不会打架。
2. 系统滚动的惰性与橡皮筋在真机上的观感（这正是用户第 1 条要的东西；
   `scrollBounceBehavior(.always)` 是显式写出来的，而「两端都回弹」最终要眼睛确认）。
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
| 09-24 | CI 静态门红 3 条（`copy` / `lintcfg` / `oneentry`） | 本地只跑了清单里的一半 —— 而三条里两条是真 bug（空态含实现词「接口」；`MapSpineView.swift` 涨到 1206 行越过阈值），本地全跑就会当场红 | `scan/all.py`（把「记得跑那个循环」变成一条命令，清单从工作流解析） |
| 09-24 | 门禁拦住了正确的写法 | `oneentry.py` 判据 ③ 写的是「档位要出现**两次**（巨字 + 依据行）」，而当天的「精致度」设计恰好把依据行删了 —— 门禁坚持的是旧设计 | 判据翻成「**恰好一次**」，并在文件头写明为什么定义反了 |
| 09-24 | `delguard.py` 本地**假绿**两次（同一轮内自己发现） | 它有两个盲区：① 旧版本永远取 `HEAD~1`，而 `messageWeeks` 是**在 HEAD 里才引入**的（拿 HEAD~1 比时那个名字根本不存在）；② 「使用」只在**同一个文件**里找，而 `messageWeeks` 声明在 `API.swift`、用在 `MessagesSection.swift` | 旧版本按工作区干不干净选（有改动 → `HEAD`）；使用跨文件找（其它文件只认带前缀的用法）。探针就是那次真事故本身：修前绿、修后报出 `API.swift` 声明没了 + `MessagesSection.swift:210` 还在用 |
| 09-24 | CI 编译失败（`StartupJournal.swift:92` 的 `URL?`） | 新写的 `begin()` 里，`if let text = Self.read(cur), let prev` 只解开了「上一次」的路径，下面 `removeItem(at: cur)` 里的 `cur` 仍是 `URL?` —— 本地看不见（没有 Swift 工具链） | 拆成两段解包（顺带把「拿不到路径时不静默放过」写进注释）；同一次构建的三条警告一并清掉 |
| 09-24 | `scan/all.py` 在 Windows 上崩 | 控制台是 GBK，`print("  ✅ …")` 直接 `UnicodeEncodeError` —— 保证「本地全跑」的脚本自己先崩 | 只改 `errors` + 符号降级为 `[通过]`/`[红]`（红绿不可混同）；子进程 `PYTHONIOENCODING=utf-8` |
| 09-24 | 真机闪退**仍然复现**，而且系统里没有日志 | 「没有日志」本身就是判据：应用层错误会留下一份 .ips 报告，什么都没有通常意味的是**系统级终止**（jetsam / 看门狗）—— 那类终止不调用 App 的任何一行代码。而它现在恰好最难看见：自建的崩溃上报已在 09-23 按用户要求删除，系统报告又只在「设置 → 隐私与安全性 → 分析与改进 → 共享 iPhone 分析」打开时才落盘 | 启动轨迹补三样：**心跳**（每秒一行，写在后台队列上，于是最后一行离死亡时刻不超过 1 秒）、**主线程卡住判据**（心跳还在写而主线程 N 秒没回话 = 卡死；心跳自己也停了 = 被处决）、**地图页各步打点**（原来的打点全落在头一两秒，而事故发生在「地图出现后几秒」，正好落在盲区里） |
| 09-25 | **CI 连红两次：`MapSpineBottomBar.swift:71` 「declaration is only valid at file scope」** | 上一轮为了把 `MapSpineView.swift` 收回 1200 行以内，把「底条整行横拖」搬进新文件，而那个文件**一台戏犯了三个错**：① `private extension Double` 写在 `extension MapSpineView { … }` 体内（Swift 只允许文件层）；② `@State private var barDragBase` 是 extension 里的存储属性；③ 读写 `modePosition` / `barOpen` / `modeIndex` / `barRowWidth` —— 四个都是 `MapSpineView.swift` 里的 `private`（`private` 的作用域是**文件**）。而**29 条门禁全绿**：当时的判据里没有一条知道 extension 该长什么样 | 那个文件整体撤掉，手势与控制它的状态搬回同一个文件；`filteredRuns` 在 `ControlView.swift` 里去掉 `private`（它被 `ControlFit.swift` 用着 —— 同一个错的第二处）。新增第 29 条门禁 `extguard.py`（三条铁律），探针验过：判据 ①② 注入即报、撤掉转绿；判据 ③ 用真事故复现（把 `filteredRuns` 改回 `private`，当场报出 `ControlFit.swift:58/63`）。第一版探针把宿主与扩展写在同一个文件里，③ 因此不报 —— 而那是**对的**（`private` 的作用域是文件，同文件用私有成员合法）：探针不报可能是判据漏了，也可能是探针没造成那个形状，两者必须先分清。教训写进那条门禁的文件头：**「拆文件」不是免费的 —— 它会把「同一个作用域」拆成两个** |
| 09-25 | **CI 第二批红：一次 26 条、六种形状** | 上一次把语法层那三个错修掉之后，编译器**第一次走过语法层**，于是一口气把「很久没编译过」的账摊开：① `ArtTheme.swift` 四处 `extra arguments at positions #3, #4, #5, #7…`——根因是 Swift 的规则：**结构体一旦自己声明了任何 `init`，就不再合成隐式的 memberwise init**，而 `75c80ce` 给 `ArtThemeSpec` 加的便捷 init 正好把那四处全字段写法弄红（标签与值一个都没错）；② `DSGlass` 的 `S: Shape` 接不住 `strokeBorder`（它只在 `InsettableShape` 上）；③ `HealthDataView` 的 `ambiguous use of 'opacity'`（`Color.opacity` 与 `ShapeStyle.opacity` 同名，而 `.background(_:)` 的参数是泛型 `S: ShapeStyle`）；④ `MapSpineView` 的 `Self.barSeam`——**它从未在任何提交里被声明过**（注释与两个使用点是同一笔写进来的，只有声明那一行没进文件）；⑤ `MapStyleSpec` 十六处裸写静态成员 `mutedSpec`（实例上下文里用静态成员不合法）；⑥ `MessagesSection` 的 `ambiguous use of 'accessibilityHint'`（推断问题，不是语义问题） | `ArtTheme` 那四处调用点**不动**，改为把全字段 init 显式写回来（26 个参数、顺序 = 存储属性声明顺序）——那四套主题每个颜色旁都写着对比度实测值，改用便捷入口＝「把量过的值换成算出来的值」，是设计变更；`dsGlass` 的约束收窄到 `InsettableShape`（三个便捷入口与全部调用点都满足，不损失调用点）；`opacity` 用具名 `let inset: Color` 钉住**期望类型**；`barSeam` 补回声明（那段注释早就写明了这个 9）；`mutedSpec` 十六处改 `Self.mutedSpec`；消息行的按钮拆成 `rowButton(_:isOpen:)`（行为一字未变，无障碍那两句仍挂在同一个 Button 上）。门禁侧补了两个洞：`scan.py` 的「未知成员」判据现在认 `Self.`——此前**所有 `Self.` 引用都在盲区**（`MEMBER_REF` 把 `Self` 当成类型名，判据遇到不在类型表里的名字直接跳过），`barSeam` 就是这么溜过去的；新增第 30 条 `initguard.py`（调用点实参 vs 声明的 init），双向探针验过：**删掉全字段 init 就恰好报出那四处**、补回即绿，当前树 0 处。`initguard` 诞生当天被自己的两条误报教过 —— 嵌套类型的 init 被算到外层、同名类型（`AppStore.TripRecord` 与 `Models/AppDataModel.swift` 的 `TripRecord`）—— 两条都写进了文件头；另有一处是共用件的洞：`extguard.mask` 处理行注释时留下开头那根 `/`，把 4 个最大调用点的标签抽取全弄脏了 |
| 09-25 | **CI 第三批：26 → 2** | ① `HealthDataView` 的 `conflicting arguments to generic parameter 'Result' ('Void' vs. '(inserted: Bool, memberAfterInsert: String)')` —— `Set.insert` 有返回值，而在 ViewBuilder 里 `withAnimation` 的泛型 `Result` 同时收到「外层要 Void」与「单表达式闭包给出元组」两个约束；② `MessagesSection` 的 `ambiguous use of 'accessibilityHint'` **上一批的修法没成**（把按钮拆成独立函数不足以解决），因为 `accessibilityHint` 在 `View` 与 `ModifiedContent` 上各有一份、返回类型还不同，receiver 恰是 `.accessibilityLabel` 留下的 `ModifiedContent` 时两个候选都合法 | `_ = set.insert(x)` 四处一起写明（值本来没人用，说出来 `Result` 就只剩 Void）；`accessibilityHint` 那一处改用泛型函数 `withHint<V: View>(_:)` —— **成员查找在泛型声明处做、只看约束**，`ModifiedContent` 那一支永远不可能是候选（与 `ViewModifier.body(content:)` 里能随手写 `content.xxx` 同理）。**决定性的测量**：全仓「无障碍标签接另一个无障碍修饰符」共 **28 处、27 处编译得过** —— 所以这**不是**一条全仓规矩，只是那一处推断预算不够；照着一个偶发结果去改另外 27 处，是把「编译器这次的心情」写进界面代码。上一批文档里把它归为「推断问题、拆开就好」是**推理**，CI 证明它错了：同一处怀疑花一分钟数一遍同类写法（28 / 1），结论就完全不同 |
| 09-25 | **权限说明一直在替一个不存在的能力担保** | `NSLocationWhenInUseUsageDescription` 写的是「用于显示车辆当前位置」—— 而车的位置是**服务端**给的（`AppStore.currentLocation` 来自车端报文），全仓没有任何 CoreLocation 代码：这句话从写下那天起就没对过。同一轮才发现用户要的那枚「手机的位置」钮**无依无靠**（没有第二个位置可指）| 新增 `Services/PhoneLocation.swift`（按需要权限、取到就停、拿不到就如实说），说明改成它真的做的事：「用于在地图上显示手机与车辆的位置」。这一类漂移（**plist 权限文案**）31 条门禁查不到：`paidcap.py` 只管禁键，没有任何判据核对「权限键的文案说的是不是代码真做的事」 |
| 09-24 | 冷启动把同一件事问了三遍 | 根视图 `onAppear` 里两处 + 地图外壳 `.task` 各自调 `bootstrap()` —— 并发三份 `getCars` + `getUser`，并三次 `cancel` / 重启预加载（每次预加载都是 6 个请求）。冷启动头几秒本来就在抢 CPU 与网络 | `bootstrap()` 合并**同时**在飞的那几趟；串行重复调用（重新登录 / 下拉刷新）照旧各取一次；`logout()` 丢掉句柄，新账号必须另起一趟 |

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
| `StackSpec` | 卡片自己的几何（圆角 / 内边距 / 外边距 / 间距）+ 无障碍翻页那一下的弹簧 | 不 import SwiftUI 之外的任何东西，不碰视图。叠法、阅读线、消失带、判定全删（2026-09-25）| 
| `GlassCard` | 一张卡的外观（玻璃 + 一抹个性色 + 标题行） | 不决定卡在哪儿；也没有「要不要挂玻璃」的开关（那个开关会随滚动位置换材质）|
| `ArcStack` | 那一叠：**系统 `ScrollView` + `VStack` + 无障碍翻页** | 位置、惯性、两端、指示条、三指滚动全归系统；它不知道卡里装的是什么 |
| `DSSwipeStrip` | 底部那条：胶囊外轨 + 胶囊选中格，静止三档、按下展开、连续跟手，选中那档的字是主题强调色 | 不换屏（它只写回 `homeMode`） |
| `DSGlass` | 「浮在内容之上」那一层的唯一材质（形状 / 变体 / `interactive` / 多块合成一层） | 不决定哪块表面该是玻璃（那是设计判断，写在它的头注里） |

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
- **卡高由内容撑**，不写 `frame(height:)`。卡片按真实高度排队（系统 `VStack`），
  写死高度会让「行程那一叠」与「设置那一叠」的滚动距离不一样。
- **无数据就写一句真话**（`GlassCardEmpty`），不要摆 `--`。读数带时间用 `StackCard.at`。

### ③ 三条容易踩的坑（都是这次真的踩到的）

- **`StackSpec` 里的数字只能改一处。** 六页的手感任何一处不同，都说明有人在页面里
  另写了一遍间距。
- **条子的几何全部由 `width` 参数推出来，没有一处存起来。** 把它存成 @State 那版
  在非 390pt 的机器上首帧会停在错的地方（而且只在第一帧，很容易被当成“闪一下”）。
- **改 `ArcStack` 时不要往它上面加东西。** 它现在就是「`ScrollView` + `VStack` + 无障碍翻页」；
  每一层自己画的东西在上面都加过一遍：遮罩（消失带）、每张卡的 `offset / rotation3DEffect /
  scaleEffect / opacity / allowsHitTesting`、`.scrollIndicators(.hidden)`、自己算的高度与落点。
  它们一一被删（用户 2026-09-25 第 1 条：「除了地图外其他的界面怎么滑动起来都很不 iOS？
  iOS 的原生流畅呢？」）—— 删除理由逐条写在 `ArcStack` 头注，加回来前先去读那一节。
  留在容器上的唯一非系统行为是 `.accessibilityAdjustableAction`（元素级上下轻扫 =
  上一张 / 下一张，它比连续滚动更好定位；三指滚动本来就是系统的）。
  已知限制：它只跟「被点了几次」走，手滚过好几张之后下一次翻页仍从上次的序号继续。
  （更早这里写过 `.accessibilityAction(.scrollUp/.scrollDown)` —— 那两个成员不存在，
  见 `REDESIGN-STATUS` 的「CI 报回来的三处」一节。）

### ④ 怎么看那一叠卡

`我的 → 诊断 → 卡片叠`。它自 2026-09-24 起不是「对照页」了：叠法只剩一种，
而 2026-09-25 滚动也归了系统 —— 页子留着是为了一叠卡本身的观感（参差高度、玻璃层次、
条子的两种跟手形态），那些只有真机能判，七选一与它的 `UserDefaults` 已删。
这套东西在浏览器里的原型是 `design-preview/stack.html`（那个文件夹是设计过程，不进 App target）。

---

## 14. 2026-09-25 第二轮：那一叠卡只剩系统滚动

触发：用户「子页面上下滚动的换回 ios 原生吧，还有哪些可以换回 ios 原生的用问题问我」。
这句话里要留意一件事：**第一轮已经换过了**（`ArcStack` 09-25 上一轮就从自管手势改成
`ScrollView`），但**那一轮从未编过** —— CI 连续三个批次红在各处类型错误上（见 §11）。
所以用户手上那个包很可能还是「自管手势」那一版。第一轮改对了方向，壳上却还挂着
三层自己画的东西，那些是不需要 CI 也能读出来的：

| 删掉的东西 | 它原来为什么在 | 为什么现在不对 |
|---|---|---|
| 上下**消失带遮罩**（`.mask` + 渐隐） | 卡片当时是斜的、要转出画面，硬裁会在边上露直角 | 转出 09-24 就删了。剩下的作用只是让一个原生滚动容器的两端平白变淡（而且那些子页铺的是**壁纸**，渐隐是往一个不存在的底色里淡） |
| 每张卡的 `offset / rotation3DEffect / scaleEffect / opacity / allowsHitTesting` | 七种叠法的形变 | 唯一叠法下系数全是 0/1 —— 五个修饰符里四个什么也没做，剩下那个把滚出去的卡淡成 0.9 |
| `.scrollIndicators(.hidden)` | 「这一层没有 chrome」 | 它连「你在滚动」那条指示条一起关了；系统列表是**给**的 |
| 量高度 / `tops` / 落点清单 / 两端边距 | 位置与形变要自己算 | 位置归系统之后全部失去读者（`CardFit` 只用宽度） |
| `StackVariant` / `StackMetrics` / `StackKind` / `variantKey` / `chosen` / `remember` | 七选一与「存下来的那一档」 | 只剩一种叠法，而它已经没有属于自己的行为（= 系统的 `VStack`）| 
| `GlassCard.glassy` + `CardSurface` | 「只给可见的卡挂玻璃」的性能妥协 | 同一张卡会因滚动位置换材质 —— 滚过去那一刻最像贴图 |

改完 `ArcStack` 是 159 行（此前 383）：`ScrollView { VStack(spacing: StackSpec.Card.gap) { 卡片 } }`
+ 无障碍逐张翻页。`StackSpec` 缩成 56 行（只有 `Card` 与 `settle`）。

**留下的唯一非系统行为**：`.accessibilityAdjustableAction`（读屏用户上下轻扫 = 上一张 /
下一张）。它是无障碍挡位、不画东西、也不碰滚动的物理。已知限制写在 `ArcStack` 头注：
它只跟「被点了几次」走，手滚过好几张之后下一次翻页仍从上次的序号继续。

**顺带修的注释漂移**（都是「代码已经对了、注释还在替旧实现说话」这一类）：
`DS.swift` / `ControlFit.swift` / `ExportDataSection.swift` / `MessagesSection.swift` /
`EmergencyPanel.swift` 里五处「叠叠乐自管手势（没有 ScrollView）」—— 那句话现在是错的。
结论不变（卡里不要套第二层滚动），但理由变了：外面那一层现在是真 `ScrollView`，
卡里再套一层，那一块区域的竖向拖动会被**内层**吃掉（旧版是「手势塌给内层」）。**门禁侧一条**：新写的预览页页头文案被 `copy.py` 报「过长（64 > 30）」—— 门禁是对的
（那句话在替用户解释实现），改成一句短的。

### 同一轮的第二个决定（用户从候选里选的）：「其余读数」改成系统 sheet

> ⚠️ **2026-09-25 第五轮已取代**：用户看过 Apple 地图那张导航卡之后说
> 「下面的卡片不是抽屉样……默认只显示一横，拉出来才是全部」，于是那一张 sheet
> 与它那行入口整块删掉，抽屉回到**这张卡自己**里（见 §16 第二项）。
> 下面这一节保留原样，它是那一步的完整代价清单 —— 里面「系统的落点更多 / 拉手随
> 辅助功能走 / 半屏时地图仍可拖」三条都是真的，换代的原因**不是**它们不对，
> 而是系统 sheet 的位置永远在屏幕底部：它会盖住模式条，而那一条是全站唯一的入口。

我把「还有哪些可以换回系统原生」列成了一张表交给用户（问题在提交信息 / 对话里），
他选了三项里的两项，改的就是这两项：

- **保留相机式模式条**（不换系统 Tab 栏）：六档 + 两侧圆钮映不进系统页签栏（一般最多五个），
  换掉会同时丢掉拖动跟手与两臂布局。
- **保留玻璃叠叠乐**（不换 `List`/`Form`）：玻璃卡是这个 App 的识别度所在。
- **做：地图抽屉 → 系统 sheet + `presentationDetents`。**

改动：卡里那一道**自己拉的抽屉**整块删除（自画拉手 `drawerGrabber` + 连续量
`drawerReveal` + 拖动起点 `drawerBase` + 量自然高的 `drawerMeasure` + 宿主 `moreDrawer`），
换成一行 disclosure（`readoutsDisclosure`）+ 一个 `.sheet`：

| 上一版自画的 | 现在系统的 |
|---|---|
| 两个落点（走 / 不走）+ 手算吸附 | `presentationDetents([.medium, .large])`：档位、橡皮筋、下拉关闭全归系统 |
| 自画拉手（`Capsule` 36×5） | `presentationDragIndicator(.visible)`：那枚随辅助功能设置走的系统 grabber |
| 抽屉全程盖着地图 | `presentationBackgroundInteraction(.enabled(upThrough: .medium))`：半屏时地图仍可拖 |
| 三个状态变量 | 一个 `showReadouts: Bool` |

两个新的 SDK 名字对着 Apple 文档 JSON 核过后登记进 `scan/scan.py`
（`presentationBackgroundInteraction` / `presentationDragIndicator` / `PresentationBackgroundInteraction`，
externalID 写在登记项里）。顺带删掉 `TokensMotion.reveal` —— 它唯一的读者就是那道抽屉。

**顺带查出的一个门禁盲区（未动，只记录）**：`orphans.py` 只认「系统类型扩展里的成员」，
而**项目自己的令牌枚举**（`TokensMotion` / `TokensTypo`）里的零读者成员整类不在范围内。
用一把粗探针（Design 下全部 `static let/var` × 全仓 `.名字` 计数）扫出来 6 个候选，
但它分不清「真死」与「通过别的路径被用到」：其中 `TokensMotion.page` / `screen`
两个**在 HEAD 与工作树里都是零读者**（已单独核过），而 `ArtTheme.changed` /
`CardFit.defaultValue` 那两个需要看上下文才能判。这一条要不要变成判据是一个独立决定。

**一个差点被写进文档的错误结论（记在这里）**：改 `DevView` 时我看到那里的 `DSGroup(footer:)`
文案很长而没被报，一度以为「作为参数传出去的文案逃过了 `copy.py`」并把它写成了发现。
量了一下才反转：`copy.py` 扫的是**每一行的字符串字面量**，与它出现在哪个位置无关；
`DevView` 之所以没被报是它在 `EXEMPT_FILES` 里（设计令牌页的正文就是「缓存/字段」那些词）。
量出来的数：这种「作为参数传出」的中文文案 399 条，其中 > 30 字的 **0 条** ——
判据在全仓是一致的。教训与 HANDOFF §11 里那条同源：**先把「它真的有这个形状吗」量出来，
再下结论**（这次是先写了结论，才想起来量）。

---

## 15. 2026-09-25 第三轮：AppIcon 整张重画（v1.0 → v2.1）

触发：用户「重新设计软件图标吧！完全不符合 ios 调性！太丑了！」。

「调性」听着主观，但这件事之所以不是「换一张好看点的图」，是因为 v1.0 犯了四条**可以指着像素说清**的错
—— 它们全部编译得过、当时 31 条门禁全绿、模拟器里也完全正常，因此没有任何自动检查看得见：

| # | 问题 | 实测 | v2.x |
|---|---|---|---|
| ① | 底色近黑 | 1024 亮度 p05/p50/p95 = **0.000 / 0.096 / 0.659**（深蓝黑 `#1A1A2E→#0D0D1A`）—— 主屏上一块黑 | 亮琥珀→橙，p05/p50/p95 = **0.561 / 0.718 / 0.957** |
| ② | 图上有字 | 「长安车管家」+「CHANGAN CONNECT」两行，占下缘约一成高 | 一个字都没有（Apple 规范第一条：图标不要放文字） |
| ③ | 自己套圆角 + 内缩 4%，四角被压成纯黑 | `convert('RGB')` 把透明边压成 **(0,0,0)**；左右边中点 (0,0,0) vs 内侧 (255,159,0)，**色差 255** | 满幅、模式 `RGB`、不画圆角；8 点实测最大色差 **7**（门禁上限 14） |
| ④ | 没有深色 / 着色外观 | 7 张全是同一张浅色 | 7 槽位 × 3 外观 = **21 张** |

**改完的形状**：白色（深色外观下琥珀色）轿车侧影 + 顶上一道淡白高光；窗与轮拱是**挖空**
（透出底色，不是画深色块），没有描边 / 阴影 / 光晕。车身底下那道弧是 App 里「车钉外面那圈弧」
（续航圈）的图形引用。实测占位：车身 689×409（长高比 1.68），占画布宽 67% / 高 40%，
连同弧到画布高 93%。（v2.0 的车只有 300 高 / 占 29%，主屏上看是「中间一条小车」，v2.1 放大到只留一圈呼吸位。）

**出包来源只剩一条路**：`generate_appicon_pillow.py`（唯一来源）+ `generate_appicon.sh`（入口，
顺手跑 `scan/iconcheck.py`）。之前 `generate_appicon.sh` 的 ImageMagick 分支在这台机器上根本用不到，
而它的 cairosvg 退路指向一个**不存在的** `generate_appicon.py` —— 也就是说文档承诺的退路是条死路，
只在「这台机器没有 ImageMagick」时才会被走到。更根本的问题：ImageMagick 只能渲 SVG，
而 SVG 里只有浅色一套外观，用它刷新会得到「一半新图一半旧图」的图标集 —— 正是这个仓库记过的那个坑
（**改了 A，真机上看到 B**）。所以现在 `AppIcon.svg` 降级为矢量对照，不再出包。

**新增一条门禁** `scan/iconcheck.py`（工作流清单末尾，第 31 条；详见 §8.1），
五条判据全部当场能量。写它的过程中撞到一个值得记的墙：**`scan/` 里不能 `import PIL`** ——
脚本目录会进 `sys.path`，而 `scan/copy.py`（文案门禁）与标准库 `copy` 同名，Pillow 的 XML 依赖
一 `import copy` 就拿错模块，当场 `AttributeError: module 'copy' has no attribute 'deepcopy'`。
于是它自己写了 PNG 解码器（zlib + 五种过滤器），并与 Pillow 逐点比对过（3 张主图 × 9 采样点）。

**验证状态**：本地 `python3 scan/all.py` **32/32 全绿**（31 条门禁 + `check_style.js`）。
本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**；这里能给的证据是可量的事实
（尺寸、三套外观齐全、满幅色差 ≤ 7、亮度分位、58px 下 ASCII 渲染能读出车形）。
文档：`AppIcon-SPEC.md` 重写为 v2.x（含每条旧问题的实测数字）；本节；`REDESIGN-STATUS.md` 同名日期一节。

### 15.1 之后又换了一次：v2.1 → v3.0（用户挑了探索稿 040）

v2.x 修掉了四条**规**上的错，但构图仍是我一个人定的（琥珀底 + 白色轿车 + 车底一道弧）。
于是又做了一轮 **100 个 1024 方向的探索稿**（自包含单页，用户在浏览器 / 真机里看），
用户报回一个编号：**040「两厢 · 纸白底」**。

v3.0 = 把 040 折进正式渲染器：车形换**两厢**、底换**纸白**、车身从白换成**墨色**；
v2.1 那道车底弧**删掉**（040 里没有它）。折进来时与探索稿**逐点比对**过：完全相同 99.76%、
差 > 8 色阶的 0.24%（全落在 1px 宽的车身边缘，来自常数取整）—— 比对顺带查出一个真参数错
（柔影位移 23 → 22：23 时有 89485 个像素有差，22 时 174 个）。探索稿与它的两个生成脚本
**用完即弃**，只留中选的那一张（留着 100 个方案，下一个人改图标时不知道以哪个为准）。

当前亮色 1024 实测：亮度 p05 / p50 / p95 = **0.136 / 0.916 / 0.980**，模式 `RGB`（无 alpha，
满幅）。`AppIcon-SPEC.md` 是这一版的完整规范。

## 16. 2026-09-25 第五轮：五条真机反馈

用户一次给了五条（编号就是他给的顺序）。这一节的顺序也是这个，每条后面写清**根因**、
**改法**与**证据**。所有改动都未提交。

### 16.1 卡片宽度：只有「现在」与「车辆」合格，其余五页窄了 20pt

**根因是 `pageBackground()`**：它叫「页面底色 + 统一页面边距」，而函数体只剩一行
`contentMargins(.horizontal, 20, for: .scrollContent)` —— **底色与光早就不在那里**
（它们在 App 根部的 `AppCanvas`）。留下的那一行加在**这一页滚动内容**的左右，
于是「调用过它的页面」的卡叠比「没调用的页面」窄 20pt。实测（402pt 宽的机器，
量卡里那层分组面到屏幕边的距离）：

| 页面 | 分组面宽 | 左右各空 |
|---|---|---|
| 车辆（没调用） | 328pt | 36pt（= 18 卡内缩 + 18 卡内边距） |
| 出行 / 车控 / 我的（调用了） | 288pt | 56pt —— 多出来的正是那 20pt |

**改法**：整段删掉，而不是留着它 —— 一个叫「页面底色」却不产生底色、只把卡片变窄的函数，
与「一个叫 `glass` 却不产生玻璃的参数」是同一类谎（`DSCard` 头注里记过那一条）。
六个调用点全部删掉；真正需要那 20pt 页边距的两处（登录页 / 「光」浮层）现在自己写明白。
登录页顺带修掉一个**双重内缩**：它自己已经有一层 `.padding(.horizontal, page)`，
叠上 `contentMargins` 的那 20 就是 40pt。

### 16.2 地图页：删掉大字地名；底部那张卡改成抽屉；比例尺移到灵动岛下面

用户原话：「地图页最上面的位置没删」「下面的卡片不是抽屉样……默认只显示一横，
拉出来才是全部」「地图页的比列缩尺放到灵动岛下面，2 秒后消失」。
**第一句与第三句我问了澄清**（`ask_questions`）：他确认「最上面」= **那行大字地名**
（衬线 29pt，安全区下 108pt），比例尺则要挂到灵动岛下面。

- **删掉 `mapPlaceLabel`**：图上那句地名唯一的存在处。顺带删掉它读的
  `MapSpineData.placeLabel`（地址截到 7 个字）—— **删完就没有读者了**，
  而这一步只能靠人 grep：`scan/orphans.py` 只盖系统类型的扩展成员。
- **底部那张卡变成抽屉**：收起（默认）= 拉手 + **续航 / 电量 / 车速** + 图层胶囊；
  拉出来 = 卡的全部内容。那一横用 `DSBigNumber`（字号 30，同一套排版换字号），
  拖动只看方向 + 阈值（`predictedEndTranslation`，轻甩就走）。
  **巨字续航（`size 56`）因此消失**：它就是那三个数里的第一个 —— 不是排版缩水，
  是重复的消除（用户 09-24：「地图页的信息有很多是重复的」）。
- **上一轮那张系统 sheet 整块删掉**（`readoutsSheet` / `readoutsDisclosure` /
  `showReadouts`）：抽屉**就是这张卡**，而系统 sheet 永远在屏幕底部 —— 它会盖住模式条
  （`oneentry.py` 守着的那条唯一入口）。三代写法（自画抽屉 → 系统 sheet → 卡自己）
  各自的代价记在 `MapSpineReadouts` 头注里，这是同一个诉求的第三次答复。
- ~~**比例尺自己量**~~（**第十一轮已作废**：系统那件可以独立摆位，这一整段机器都删了，见 §22）：
  当时的理由是「系统 `MapScaleView` 的位置由 MapKit 定（贴角），搬不动」—— **那句话是错的**。所以
  `MapReader` + `MapProxy.convert(_:from:)` 把屏幕上相距 200pt 的两点换成经纬度、
  用 `CLLocation.distance` 量出地面距离。**数是真的量出来的，不是按镜头距离估的** ——
  一支会撒谎的尺子比没有尺子更糟。尺子挂在**安全区之内**（`nowLayer` 那一层），
  所以对齐到「顶」就是灵动岛下沿；挂在地图上就会跟着 `ignoresSafeArea(.top)` 钻到
  灵动岛底下。2 秒后淡出（`flashScale()`；镜头每变一次重计时，代号防串台）。
  三个新 SDK 名字（`MapReader` / `MapProxy` / `convert`）对着 Apple 文档 JSON 核过后
  登记进 `scan/scan.py`；`convert` 这条**特意写明**「名字很泛、白名单是按名字判的」。

### 16.3 底部模式条：点选对得准，滑动选对不准

用户：「点选菜单入口的时候，不会出现选中框和入口没对准，但是滑动选入口，
很容易出现对不准」—— 这个**不对称**本身就是根因的指纹。条子里的 `c` 是「行内坐标」的
一个数，而同一档在两个**间距**下的行内坐标不是同一个数（间距随展开插值：静止按三档算、
展开按全部算），于是间距一变，上一次算出来的 `c` 就落在两档之间：
透镜钉在条正中不动，而当前那一档的字偏到旁边去了。

两条路的**时序不同**，所以只有滑动那条会偏：

- **点选**：`pick()` 改档位与 `expand = 0` 发生在同一轮里 → `.onChange(of: selectedID)`
  拿到的 `gap` 已经是收回后的值 → 算对了；
- **滑动**：`snap()` 改档位时条子还**开着**（收回被推到 620ms 之后，那是「给你看刚才划过
  哪些档」），等 620ms 后收回，间距变了而**没有谁再算一次 `c`** → 从此偏着，
  直到用户再碰一下条子。

**改法**：加一条 `.onChange(of: expand)` → 重新落位（`settle`）。手指正按着时不重算
（那一刻 `c` 归手势管），而收回发生在松手之后，所以守卫拦不住要治的那个时序。

### 16.4 Windows 聚焦取不到图（必应却行）

用户：「必应可以拿到图片，但是 windows 聚焦失败了」。**用真报文核出来的**：
接口返回的形状是 `ad.landscapeImage.asset` / `ad.portraitImage.asset` —— 键名是
**`asset`**，而解析器只找 `u` / `url`（`ad` 的子字典里**没有这两个键**）。
于是 `picks` 永远为空 → 这一源永远取不到图；必应走的是 `urlbase`（另一条路），
所以「必应行、聚焦不行」。

**顺带查出同一函数里的第二个 bug**：署名读的是 `copyright_text` / `title_text`，
而真报文里叫 **`copyright`** / **`title`** —— 署名那行**永远是空的**（看起来像
「这张图没有署名」）。两个都改了。

**证据**：把新旧两个解析器逐行照抄成 Python、在真实接口上跑（2026-09-25 实跑）：
旧 = **0 张图 / 0 条署名**，新 = **4 张图**，取到的地址是 `1080x1920` 的竖图，
署名 `© Ondrej Prosicky / iStock / Getty Images Plus`。顺序也写死了（竖图优先，
不再遍历 `ad.values` —— Swift 字典遍历顺序未定义，同一份报文会今天取竖、明天取横）。

### 16.5 控件应该是玻璃质感，「黑颜色太突兀」

**根因是 `TokensPalette.nightSurface`**（= `spec.surface` = 深色 #1C1C1E / 浅色 #FFFFFF，
**不透明**）：卡片本身是玻璃（`GlassCard` → `dsGlass`），而卡里那层面用它 ——
等于「玻璃中间挖了一个黑洞」。用户截图里那一块块黑：分组面（`DSGroup`）、
占位面（`DSPlaceholder`）、提示条（`DSNotice`）、搜索框、分段控件的滑块、评分空态。

**改法：加一个令牌 `TokensPalette.panel`**（= 当前主题 `surface` 的**半透明版**，0.5），
把上面七处全部改成它。为什么是「同一个色值的半透明版」而不是另写一个灰：
二十套主题因此各自保住自己的面色（纸上主题里这层仍是纸色），而 0.5 让卡片自己的玻璃
与它底下的壁纸继续透上来 —— 它才像同一块材质的一层，而不是贴上去的一块板。
**0.5 是这里唯一的刻度**，全 App 的面一起变。

分段控件的滑块单独一条：它改读 **`glassHighlight`**（「玻璃里面那一层更亮的底」）——
与模式条上那枚透镜是同一个东西，同一个令牌。原先它在深色下是 (28,28,30)，
**比它所在的凹槽还暗**，于是「选中的那一格」看起来是个黑洞；而 iOS 深色下选中段
本来就该比凹槽**亮**。顺带把最后一个系统 `Picker(.segmented)`（充电页的趋势周期）
换成 `DSSegmented`：全 App 只有一个分段控件。

**故意不做的事**：不在卡里再挂一层 `.glassEffect`。`DSGlass` 三层规则第 ② 条写着
**卡里不玻璃**（玻璃叠玻璃会糊成一片，而卡片自己已经是玻璃），而 `scan/glass.py`
第 ③ 条也会拦「玻璃底下垫不透明面」。用户要的「玻璃质感」在这里是**半透明**，
不是第二块材质 —— 这一条我写在令牌的注释里，免得下一个人把它当成漏做。

### 16.6 这一轮的门禁与文档

`python3 scan/all.py` —— **32/32 全绿**。三处门禁当场抓到过东西：`scan.py` 拦下三个
没登记的 SDK 名字（`MapReader` / `MapProxy` / `convert`，登记后才绿）、
`lintcfg.py` 拦下 `MapSpineView.swift` 到 **1201 行**（改法是把「现在」那一张卡
搬进 `MapNowCard.swift`，现在 1157 行 —— 不是加进排除清单、也不是抬阈值）。
文档：本节；`REDESIGN-STATUS.md` 同名日期一节；`DESIGN-UNIFY.md` 里两处引用
`pageBackground()` 的表格改成现状。

**边界**：本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**。
这一轮新引入的可编译性风险集中在三处：`MapReader` / `MapProxy.convert` 的用法、
抽屉的 `DragGesture` + `accessibilityElement` 组合、以及 `TokensPalette.panel`
（`Color.opacity` 在 `fill` 里）。纯 Swift 侧的括号平衡与改动前后逐一比对过（未变），
但那不等于编译得过。
## 17. 2026-09-25 第六轮：主题只剩原生、图标换成 040、底条只留一种跟手

用户三句话：「图标用 040」「主题用原生，其他 19 套全删了」「选整行滚动，另外一个也删了」。
三条都是**减到只剩一种**——而每一次减，真正的工作量都不在删掉那一样东西，
而在「删掉之后谁接住它的读者」。

### 17.1 主题：20 套 → 1 套

删掉的五处见 §5.2 的表。**难点全在值必须逐个搬，不能重写**：

| 原来由主题提供的 | 现在 | 为什么不能连值一起删 |
|---|---|---|
| `TokensPalette` / `TokensTypo` 的取值 | 直接写回 `Tokens.swift` | 全 App 约 800 处读者，值必须**逐值相等**地搬 |
| `ArtTheme.artHex` | `TokensPalette.artHex`（同实现同取值） | `pageAccents` 的六个个性色仍在读它 |
| `ArtTheme.nativeDynamic` | `TokensPalette.nativeDynamic` | 动态色是系统语义值的另一种写法，v4 起就在用 |
| `preferredScheme`（主题自带明暗） | 删 | 「我的 → 夜间模式」成为**唯一**说这件事的人；nil = 跟随系统 |
| 地图蒙版 / 三种车钉 | 系统原样 | 见 §5.3 |

「只有一种取值的开关就是一层假的选择」——这句话这轮又兑现了四次。
代价也照实写在这里：**`scan/orphans.py` 看不见这一层**（它只认「系统类型扩展里没人读的成员」，
而项目自己的令牌枚举整类不在范围内），所以这一轮是不是真的删干净了，靠的是人过一遍
（`grep` 全仓 + 每个删除点都留了记录），不是门禁。这条盲区在 §16 已记过一次，依旧未动。

### 17.2 图标：v2.1 → v3.0（用户挑了 040）

见 §15.1。要点：这不是「再画一张更好看的」，是**把选择权交回用户**之后照他的选择重建；
`generate_appicon_pillow.py` 仍是唯一出包来源，`scan/iconcheck.py` 仍是那五条可量的判据。

### 17.3 底条：跟手形态只有一种

`DSSwipeStrip` 的 `Follow` 枚举有两个值：「整行跟手」（手指拖整行、透镜钉在正中、字从它下面
滑过）与「透镜跟手」（透镜从字上滑过去、整行基本不动）。用户定下前者，后者删掉 ——
枚举本身一起删，因为**只有一个取值的参数不是参数**。

删完之后**「松手会到哪儿」的预测算法也只剩一份**：那里原本是一个 `switch`，两个分支就是两份
预测。少一种跟手形态，顺带少了半套惯性逻辑 —— 这是这轮唯一一处「删了对、顺手也对了」的地方。

### 验证状态

本地 `python3 scan/all.py` —— **33/33 全绿**（32 条门禁 + `check_style.js`；第 32 条 `perf.py`
是紧接着的性能轮加的，见 §18）。
本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**：这里能给的证据只有可量的事实
（图标三外观齐全、满幅色差、亮度分位；令牌搬移是逐值相等）。

这轮新引入的可编译性风险集中在三处，都已写进 `REDESIGN-STATUS.md` 同名一节：
`MapReader` / `MapProxy.convert` 的用法、抽屉的 `DragGesture` + `accessibilityElement` 组合、
`TokensPalette.panel`（带透明度的 `Color` 进 `fill`）。
## 18. 2026-09-25 第七轮：性能与流畅性（先量，后改）

用户：「再全局全项目优化性能流畅性！」—— 这一轮不做「感觉更快」的改动：
**先量出「谁在每次求值时重来一遍」，再改那几处，并把量出来的数字写进注释与门禁。**

### 18.1 先把预算算清楚（这决定了改哪儿值）

本机没有编译器、没有 Instruments，所以「预算」只能从代码里推：

| 事实 | 出处 | 结论 |
|---|---|---|
| 地图页在车动起来时 **每 2 秒** 求值一次 | `RefreshLoop.Cadence.moving`（用户 2026-09-25 定的节律） | 每次求值里的任何浪费，× 0.5 Hz |
| 六页同屏**是关着的**（`LaunchFence.sixPageDeck = false`） | `Services/LaunchFence.swift` | 树里只有当前那一档 → 只需优化「当前页」的路（**这一行的前提第十轮被推翻了**：用户要求正常启动 → 四个开关全开，见 §21.2） |
| 手机定位：百米精度、取到就停 | `Services/PhoneLocation.swift` | 不是热路径，不动 |
| 历史库上限 soc 2000 / power 1500 / tyre 760 | `Services/HistoryStore.swift` 的 cap | 全表扫描只有 3 个读者、都带窗口 → 不是热路径 |
| 壁纸只在载入/刷新时解码一次 | `Services/WallpaperService.swift` | 不是热路径 |

于是热路径只有一条：**地图页「现在」这一档，每次求值里的那几件事。**

### 18.2 量出来的三处（都是同一个形状：每次求值重造「只取决于常量的东西」）

| # | 位置 | 量出来的形状 | 改法 |
|---|---|---|---|
| ① | `MapSpineView`：`let d = data` + `.onChange(of: d.carCoordinate…)` + `nowLayer()` 各一处 | `MapSpineData.build()` **一次求值建三套** —— 而 `build()` 里含行程映射、停车点映射、胎压、异常点与两处聚类 | 三处收成一处：sheet 那份挪进**闭包**（只在弹出时求值）、`.onChange` 改盯 `store.currentLocation`（车自己的读数，同一个 `caches["location"]`）、只留 `nowLayer` 那一处 |
| ② | `MapTripLine.timeText`、`VM.parseDate`、`RawLogStore.now()` 等 9 处 `DateFormatter()` | `DateFormatter` 构造要现装一套 ICU 格式化器，而同一个 `(locale, 格式)` **造出来永远一样**；`timeText` 是**每段行程读一次**（30 段 × 每 2 秒），`parseDate` 一次调用最多造 7 个 | 新建 `Services/DateText.swift`：按 `locale\|格式` 缓存的池子。**locale 逐调用点保留**（`zh_CN` / `en_US_POSIX` / 系统默认三种都不合并），所以是搬住处、不是改行为 |
| ③ | `clusterChargers` 的 `firstIndex(where: { CLLocation(...).distance(from: here) … })`、`clusterHotspots` 的质心 | 前者**每次比较**造一个 `CLLocation`（一枚钉子 × 每一组），后者在 `for j in group` 的每一轮重造同一个质心 | 每个站/每个组各造一次（O(n) 而不是 O(n × 组数)）、质心提到循环外。比较用的仍是 `CLLocation.distance(from:)` 本尊 —— **判据与分组结果一字未改** |

### 18.3 为什么这一轮没有动「六页同屏」

它是这份代码里**最大**的一笔开销（`LaunchFence` 的注释记着：内存从 49 MB 涨到 1.7 GB 只要四秒），
但它已经有一个**明确的开关**、且现在是关的。剩下能省的只有「隐藏的那几页要不要跟着
`caches` 的写入重新求值」—— 那需要把隐藏页换成 `EmptyView`，而**代价是每页自己的状态
（滚动位置、展开的分组）在换档时被销毁**。那是设计变更，不是性能修复：
真要做，得由用户决定「省那点 CPU」还是「保住换档前的状态」。**记在这里，不动。**

> **后续（2026-09-25 第十轮）**：用户回执「先正常启动试一次」→ `LaunchFence` 四个开关
> 全部打开，六页同屏回到树上。于是上面那个「隐藏页会不会跟着 `caches` 的写入重新求值」
> 的问题**重新成立**（那是这份代码里最大的一笔开销），而取舍仍然没变：省 CPU 就得
> 毁掉每页自己的状态。等真机上的观感与内存数据回来再决定。

### 18.4 防回归：新门禁 `scan/perf.py`

这一轮的两处都**不报错、不崩、编译全过**，只是慢 —— 而慢没有输出。
所以按本仓惯例给它们各立一条判据（详见 §8 第 32 条）：
格式化器只许从池子里取、坐标不许造在比较闭包里。
两条都做了**双向探针**（注入即报、还原即绿、哈希一致）。

### 验证状态

本地 `python3 scan/all.py` —— **33/33 全绿**（32 条门禁 + `check_style.js`）。

**本机没有 Swift 工具链：编译与真实帧率只有 CI / 真机能回答。** 这一轮能站得住的证据是
**计数**（一次求值建几套派生数据：3 → 1；每次比较分配几次坐标对象：O(n × 组数) → O(n)；
每次求值构造几个 `DateFormatter`：按行数计 → 0），不是帧率。
本轮新引入的可编译性风险集中在三处：`MapSpineView.body` 里 sheet 闭包内构造
（`@ViewBuilder` 闭包里的表达式求值时机）、`clusterChargers` 的平行数组
（`outLoc` 必须与 `out` 一一对应 —— 这一点写进了注释，因为它是这里唯一能被写错的约束）、
以及 `DateText` 的线程安全形态（见下）。

**一处写完又改回来的东西（值得记）**：`DateText` 第一版写的是
`@MainActor enum` + `static var` 池 —— 看起来最自然（"全 App 都在主线程"），
**但它会直接编译不过**：读者里有两个明确在后台线程上，`RawLogStore` 与 `APIClient`
（后者的注释自己写着「parseMessages 会在协作线程跑，不能在那里假设主线程」），
而 `APIClient.messagesURL` 是**同步的非隔离函数** —— 从它里面调 `@MainActor` 的
静态方法没有异步跳转的余地。已改成全仓既有的形态：`final class` + `static let shared`
+ `NSLock`（与 `RawLogStore` 同一个形状、同一个理由），锁的粒度是「取构造器」一次，
格式化在锁外跑。**教训**：「主线程」是本仓库的**默认假设**，不是**事实** ——
凡是给全仓共用的工具，先看有没有后台读者，再决定隔不隔离。
## 19. 2026-09-25 第八轮：地毯式对抗式审核（这一轮查的是**语义层**）

用户：「再次全局全项目地毯式对抗式各维度审查全项目！」。这一轮不查语法与结构
（那 33 条门禁已经把它们扫过很多遍了），专挑**门禁看不见的那一层**：两处代码各自都对，
但它们**关于同一件事的假设不一致** —— 编译器不报错、门禁不报错、平时也看不出来。

### 19.1 怎么挑维度：找「两边都写着真值」的地方

这一轮的判据是：**同一个事实被写在了两个地方**。列出来之后逐对核对：

| 事实 | 写在哪 | 对不对得起 |
|---|---|---|
| 「哪些本机键是关于账号的」 | `HANDOFF.md` §6 那张表（每行标 ✅/❌） | `AppStore.logout()` 真的清了什么 |
| 「报文里那个键叫什么」 | 真实抓包 | 代码里的读键（`keys.py` 守着一半） |
| 「这个数是公里还是米 / 是比例还是百分比」 | 服务端字段语义 | 界面上的单位 |
| 「这条数据是设备的还是账号的」 | 界面上的措辞 | 代码的清理路径 |

第一条当场对出了东西（见下）。第二条上一轮查过（`asset` / `copyright` 两个键），
第三条第四条留在「未查」里 —— 它们需要真机或真报文，这一轮**没有**硬结论。

### 19.2 对出来的东西：8 个账号绑定的键，退出登录时没人清

§6 那张表的每一行都写着归属，而 `logout()` 是照着「记得的那几项」写的 ——
两边的差就是这一轮的收获。**八条，三个后果**：

| 漏掉的键 | 换账号后会发生什么 |
|---|---|
| `carkeeper_parking_points`（最多 200 个停车点，含地址与时间） | 地图「停车」层的钉与「常停热区」显示**前一个账号**去过的地方。上一版清了停车位置（单数）与时刻，漏了这个数组 —— 而 `parkingHistory` 是**从磁盘现算**的，清内存不会让它消失 |
| `carkeeper_maintenance_photos`（用户拍的单据照，base64） | 前一个账号的照片新账号直接看得见 |
| `carkeeper_inspections`（年检记录） | 跨账号可见 —— 且它有 `@Published` **内存副本**：只删键的话同一次运行里照样看得见（「下次启动才自动消失」是重启的功劳） |
| `carkeeper_processed_event_ids`（行程去重台账） | **清派生却留台账**：`tripHistory` 被清空、台账里那 7 天窗口的事件仍然算「已处理」→ 重新登录后行程页**一直是空的**，数据再也重建不出来 |
| `carkeeper_service_reminders` / `_current_mileage` / `_total_mileage` / `_service_timestamp` | 里程与保养基线是**上一辆车**的，「距下次保养还有多少公里」跟着错。上一版清了 `last_service_mileage` —— 而它们本来是一套，**只清一套里的一个等于没清** |

改法：`logout()` 补齐七处（`parking_loc` 本来就走 setter 清），并给 `InspectionCalendar`
加一个 `resetAll()`（内存 + 键一起清，与 `FamilyManager` / `TempKeyManager` 同一个形状）。

**这一轮最值得记的不是那八个键，是它们为什么能一起漏**：`logout()` 清的是
「记得的那几项」，而**没有任何一处能回答「一共该清几项」**。所以修法与修法不一样 ——
补齐八个键只是把账还了；让 §6 那张表变成 `scan/localstore.py` 的**唯一真值**，
才是把这一类错关掉。

### 19.3 顺带治掉的文档漂移：那张表本身

对账时先撞上的是**表自己的毛病**，两条都能量出来：

- 标题写着「42 个 `carkeeper_*` 键」，代码里实际 **33 个**；
- 表里混着**三个简写**（`carkeeper_parking_loc` / `_time` / `_points` 这种缩写），
  还有几行塞两三个键 —— 后果是**这张表根本没法机械对账**：简写只有人能补全，
  而人不会每次都补。反方向也有：表里躺着 `carkeeper_art_theme`（随艺术主题删除）
  与 `carkeeper_checkin_count` / `carkeeper_siri_usage` / `carkeeper_current_speed`
  这几个**已经没有任何读者**的键。

所以 §6 重写成「一行一个键、全名、四列（键 / 它是什么 / 归属 / 退出登录清）」，
并明确写上**它就是那道门禁的真值**。键的归属从今天起是**设计决定**，不是实现细节。

### 19.4 新门禁 `scan/localstore.py`（第 33 条）

三条判据见 §8。两处**自己撞的洞**也写进了文件头（它们比判据本身更值得留）：

1. 第一版不认「键写在符号常量里」—— 而 `HistoryStore.socKey` 与 `Self.selectedCarIdKey`
   都是这种写法，于是 `clear()` 明明清了三条曲线、门禁却报「没清」（**六条假阳性**）；
2. 认了符号之后又**认得太多**：`MineView.toggleVoice()` 里有一句局部
   `let key = "carkeeper_voice_enabled"`，而 `logout()` 里也有个叫 `key` 的循环变量 ——
   两者一撞，「设备键 `carkeeper_voice_enabled` 被清了」误报。收窄成
   **只认以 `Key` 结尾的符号 + 跨文件必须带限定**。

（写这道门的第一版还踩了本仓记载过的同一个坑的变体：掩码函数把**字符串内容也丢掉**，
于是 33 个真实键被数成 9 个 —— 全是注释里的。掩码是本仓反复出错的地方，
`extguard.mask` 也在这里留过一根多余的 `/`。）

### 19.5 这一轮**没有**下结论的

诚实记下来，免得下次以为查过了：

- **单位与量纲**（公里/米、比例/百分比、摄氏度/华氏度）：需要真报文或真机截图才能定，
  这一轮只确认了「没有任何地方做单位换算」（`VM` 里全是取数与显示，换算发生在服务端）；
- **服务端字段语义随时间变化**（同一个键在不同车型上含义不同）：同上；
- **内存与线程的实际行为**（泄漏、真并发）：本机没有 Instruments 也没有真机。

### 验证状态

本地 `python3 scan/all.py` —— **34/34 全绿**（33 条门禁 + `check_style.js`）。

本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**。这一轮的证据是
**对账**（33 个键逐行核对）+ **双向探针**（三条判据各注入一次、还原哈希一致），
而不是运行时观测。`InspectionCalendar.resetAll()` 是新增的公开方法，
它的调用点只有 `logout()` 一处 —— 这一类「为清理而新加的方法」是这轮唯一的新 API 面。

---

## 20. 2026-09-25 第九轮：十条（玻璃通透度 / 顶部 / 卡里的灰 / 三处删除 / 三维车 / 地图七处 / 玻璃上的字）

用户一次给了十条，混着**问句**与**改法**，所以先分类再动手：

| 类 | 条 | 这一轮做的事 |
|---|---|---|
| 问句 | 1（玻璃是不是最通透那一档）、10（玻璃上的字怎么适配） | 查到 Apple 的两条明文规定，答案是「`.clear` 才是最通透的一档，但它只属于底下是连续画面的控件」与「自适应确实没开 —— 因为我们一直传固定色」 |
| 一致性 | 2（子页顶部要与地图页一样）、3（卡里那层灰要通透） | `ArcStack` 给滚动内容让出顶部内衬；`fillSubtle` 与 `panel` 改成同一块材质的两个深浅 |
| 删除 | 4、6、7（+ 5 的一半） | 「设备与模式」整节、诊断里所有 UI 相关项、共享密钥/家庭管理/语音播报 |
| 重做 | 8（车控的车）、9（地图七处） | 代码搭的真三维车；定位漂移 / 车钉 / 罗盘 / 比例尺 / 抽屉排版 |

### 20.1 液态玻璃到底有几档（第 1 条）

系统给的只有**两档**（`Glass.regular` / `Glass.clear`，`Glass` 是一个没有 case 的
类型，取用方式就是这两个静态成员）——`.clear` 就是「最通透」的那一档，而
HIG「Materials」对它的用法有一句硬话：

> “reserve clear Liquid Glass for components over visually rich backgrounds.”

也就是说：**通透度不是一个可以随便往下拧的旋钮，它跟着「底下是什么」走**。
两个已有的变体常量（`DSGlassVariant.regular` / `.overMedia`）就是这句话的两半：

- 底是**连续的画面**（地图瓦片）→ `.clear`：全 App 三个地方在用，都在地图上
  （图层胶囊、两枚快速钮、罗盘）。
- 底是**App 自己的界面**（画布、别的卡、壁纸）→ `.regular`：卡片走它。
  `.clear` 在这里的代价是**卡里的正文对比度会跟着底下的壁纸走** —— 而卡片是
  「读的内容」，不是「浮在照片上的控件」。这一条写在 `GlassCard` 的注释里
  （早在 09-25 那一轮就定了），这一轮只是把它答出来。

### 20.2 玻璃上的字：vibrancy 确实没开（第 10 条）

用户问「是不是没开启自适应文字颜色」——**对，没开启**。原因是这一仓一直在传
`Color(uiColor: .label)` 这类**已经解析成固定值**的颜色，而系统那个「自动适配」
只作用于 `foregroundStyle(.primary)` / `.secondary` / `.tertiary` 这类**语义层级样式**
（WWDC25「Build a SwiftUI app with the new design」原话：*“SwiftUI automatically uses
a vibrant text color that adapts to maintain legibility against colorful backgrounds.”*；
HIG「Materials」：*“Help ensure legibility by using vibrant colors on top of materials.”*）。

修法是把「玻璃上的字」收成一个新令牌 `TokensInk`（三档，与 `TokensPalette` 的文字三档
一一对应，区别只有它们是 `AnyShapeStyle`），然后只换**底下真的是玻璃**的那些调用点：
模式条（未选中那两档）、卡头、次操作按钮（玻璃胶囊）、轻提示、地图上那三枚圆钮、
图层胶囊、底条两臂。卡片里的正文**不换** —— 那里的底是 `panel`（标准半透明面），
要的是确定的对比度，不是跟着底下自调。

### 20.3 子页顶部与地图页对齐（第 2 条）

地图页的内容从时钟下面连续穿过（它整页 `ignoresSafeArea(.top)`），而子页的卡片窗
停在状态栏**下面**。两条路对齐的办法是给滚动内容加一层顶部内衬：

- `MapSpineView` 量出「屏幕顶到这一层的顶」写进环境（`stackTopInset`）——
  用 `frame(in: .global).minY` 而不是 `safeAreaInsets`（后者在已被父层让开的视图里读到 0）。
- `ArcStack` 用 `.contentMargins(.top, topInset)` 让第一张卡静止时仍让开状态栏，
  并加 `.scrollEdgeEffectStyle(.soft, for: .top)`（iOS 26 给滚动边缘的那层柔化延伸）。

### 20.4 卡里那层灰（第 3 条）

`fillSubtle` 原来读 `quaternarySystemFill` —— 那是系统为**不透明背景**定的灰，
压在玻璃卡上就是一块灰纱：不折射、不跟着底下的颜色变。现在它与 `panel` 同源
（都从 `surface` 取，只是更淡：0.22 / 0.34），于是卡片、分组面、控件底成了
**同一块材质的三个深浅**，而不是三种来路不同的灰。同时把 `panel` 从 0.5 调到 0.34
（用户在深色 + 彩色壁纸下仍然读得出「一块灰面」）。

### 20.5 删除三条（第 4 / 6 / 7 条）

- **第 4 条「设备与模式」整节删除**：摇一摇锁车 / 省电模式 / 夜间模式 / 专注模式。
  删的不是四个开关，是**四个功能**：`GestureEnhancements`（`ShakeDetector`）、
  `NightModeManager`、`FocusModeManager` 三个文件整份删除，`AppStore` 里那个省电模式的
  成员与 `Theme.swift` 里的 `PowerSavingToggle` 一起走。明暗从此只有一个说话的人：
  系统（App 根部不再挂 `.preferredColorScheme`，nil 就是跟随系统）。
- **第 6 条「诊断里删掉一切和 UI 相关的」**：卡片叠预览（`StackLabView` 整页删除）、
  画布与表面色板、语义色色板、字体样张、几何数值、动效数值 —— 六组。诊断回答的是
  「这台设备此刻在发生什么」；要报障的人不该先划过一屏设计令牌。
- **第 7 条「删除共享密钥、家庭管理、语音播报」**：`Services/FamilyAndKeySharing.swift`
  整份删除（313 行：`TempKeyManager` + `FamilyManager` + 两个页面 + 两行）。
  「语音播报」那一行删得最干净 —— 它翻转的 `carkeeper_voice_enabled`
  **全仓没有一个读者**（`VoiceBroadcastManager` 这个类型早就不存在了）：
  一个只有写者、没有读者的开关，是这个仓库里最贵的一种摆设。

连带：§6 那张本机键表删掉七行（`carkeeper_family_members` / `_temp_keys` /
`_voice_enabled` / `_focus_mode` / `_shake_to_lock` / `_power_saving` /
`_force_light_mode`），`scan/localstore.py` 里那条指向已删文件的清理登记也一并删掉 ——
**删功能就必须同时删表里的行**，否则门禁立刻报「这张清单在说谎」（它就是这么发现的）。

### 20.6 检查更新与那把 key（第 5 条）

用户给的是二选一：「删除检查更新**或者**将 key 直接写在代码中（我之前提供过）」。
选的是后者，做法：令牌只有**一个**出处 —— 新增 `Services/GithubToken.swift` 的
`static let value`，`UpdateService.githubToken` 只是它的只读转发（原来那把读存在
`UserDefaults`，于是**每台设备都要手输一次**，而「检查更新」在输之前什么都不做、
看起来像坏的）。那个 Token 弹窗（`showToken` / `tokenDraft`）与它的 `@State` 一起删除。

⚠️ 中途有一个值得记的差一点：那一行先是**空的** —— 用户说「我之前提供过」，而
**全仓与 git 全历史**（`git log --all -S"ghp_"` / `-S"github_pat_"`）里搜不到任何该形状的
字符串，所以当时只能在文件里留一个空格子并与用户确认。令牌是用户随后在对话里贴过来的
（`github_pat_` 形状），现在写在 `GithubToken.value` 那一行。

**把账记全（这不是劝阻，是让下一个人知道自己在拿什么换）**：这个字符串会进**仓库历史**、
也会进 **ipa**，任何人拿到 App 都能读出来 —— 它不是一个秘密；它最好是 fine-grained、
只读该仓库（`Contents: Read`）、随时可吊销的一把。它为空时不是崩、也不是静默失败：
「检查更新」会说出一句人话（「没有配访问令牌，暂时无法检查更新」），那条路留着是有用的。

### 20.7 车控那一屏的车（第 8 条）

新增 `Features/Control/CarModelView.swift`（RealityKit）：一辆**代码搭的**三维车 ——
车身 / 座舱 / 全景玻璃顶 / 前后风挡 / 四门（带把手）/ 四轮（圆柱横过来）/ 后备箱 /
前灯 / 车头，各是 `MeshResource` 生成的基本体。交互两件：

- **拖动转的是车**（Y 轴自转 + 一点俯仰，转的是模型不是镜头）—— 卡片里那辆车原地转身。
- **点哪控哪**：车门 / 前灯 / 车头各有碰撞体，`TapGesture().targetedToAnyEntity()`
  把被点中的实体交回来。⚠️ 可点的**只有**指令表里有的那几件
  （`LockDoor` / `UnLockDoor` / `FlashLight` / `Whistle`）：后备箱**点不动**，
  因为它只有状态、没有开合指令 —— 摆一个「点了什么都不发生」的后备箱正是这个仓库
  一直在删的东西。四门点下去给一个二选一（锁车 / 解锁），不替用户猜。

旧的那张（`CarTopView`）是线描俯视图：不是「不好看」，而是「不是车」——
一个俯视轮廓回答不了「我的车现在什么样」。整块已删（含 `artSize` / `artAspect` 两个派生量）。

### 20.8 地图页七处（第 9 条）

| 用户看到的 | 根因 | 改法 |
|---|---|---|
| 手机位置漂移近 1 公里（「我选了精确定位」） | ① 我们自己只要了 `kCLLocationAccuracyHundredMeters`；② 第一个点直接用（常常是缓存的旧点）；③ 从来没读过 `horizontalAccuracy` | 要 `kCLLocationAccuracyBest`；一批回调里挑**最准**的；够准（≤35 m）就用、不够就等（6 秒后落兜底并标 `coarse`）；精度**如实画出来**（蓝点外那圈淡圆的半径就是它） |
| 车没有车的图标了 | `MapCarPin.body` **从来没有调用过 `ringStyle`** —— 刻度盘、电量弧、底盘、那个数字全在里面，于是钉上只剩一团虚光和一个小缺口环 | 三样一起画，各说一件事：`ringStyle`（电量的形状）+ `carGlyph`（车本身，按 Heading 转）+ `socBadge`（数字，挂到圆盘下）。缺口环（`headingMark`）删掉：同一个事实不再用两种画法说 |
| 指南针太上了 | 系统的 `MapCompass` 位置由 MapKit 定（安全区紧下沿的角落），搬不动 | 整个 `.mapControls` 撤掉，罗盘自己画一枚（`Triangle` 红针 + 点一下回正北），挂在**与右侧两枚钮同一行**的位置上 —— **第十一轮推翻**：`MapCompass(scope:)` 可以当独立视图挂，位置由我们给，两件都换回系统的（见 §22）；那一轮「撤掉 `.mapControls`」还顺手把**默认控件集**放回来了（罗盘被时间压住的那一枚） |
| 比例尺不出现（缩放时该出现） | 唯一的触发者是一条 `.onChange(of: camera)`，而相机绑定的回写并不覆盖每一种手势 | 换 `onMapCameraChange(frequency: .continuous)`（平移与缩放都会来），并加一个门槛：距离没变过 6% 不重露尺子（否则一次拖动会留下上百个 2 秒计时器） |
| 抽屉里参数不该「框选」、要平铺居中 | 每格一个圆角矩形 + 一圈发丝线 —— 那不是分组，是给每个数各配了一个容器 | 去掉底与描边（数直接贴在卡上），并改成「数与名字两行、各格等宽平分、整行同一中轴」；顺序也换成数字当头（与 Apple 地图那张卡同一套读法） |

### 20.9 顺手治掉的「说谎的指针」

删功能/搬文件时，指向它们的说明不会自己跟着变 —— 这一轮又清出四处：

- `MapNowCard` / `MapSpineReadouts` / `MapSpineView` 三处注释还在把 `spec`（艺术主题的
  取值表，第六轮已随主题删除）列成「跨文件可见的成员之一」：读者会去找一个不存在的成员。
- `scan/copy.py` 与 `scan/printguard.py` 给 `DevView` 的豁免**仍然需要**（它真的在界面
  文案里说「缓存」—— 它正是「清除缓存」那一页），但**理由变了**：它从「设计令牌页」
  变成「排障页」。豁免名单里留一句过期的理由，与留一个过期条目一样坏。
- §0 的规模数（「71 个文件 / 21,706 行」）还是 09-23 的快照，此后每轮都在加东西而它没动过；
  §4.4 说车控档的车是「`CarTopView` 俯视示意图」；§5 的文件清单里躺着 `StackLabView`；
  §6 的服务表里躺着四个已删的 manager —— 四处一起改现状。
- `PROTOTYPE-TO-SWIFTUI` 里「入口是 `DevView` → 卡片叠 → 卡片叠预览页」也改成删除记录。

### 验证状态

`python3 scan/all.py` —— **34/34 全绿**（33 条门禁 + `check_style.js`）。这一轮**没有新门禁**，
但有三处是门禁当场抓出来才修掉的：`copy.py`（三条界面文案超 30 字）、
`lintcfg.py`（`MapSpineView.swift` 又到 1207 行 → 把「地图上画什么」那一段搬进
`Map/MapSpineAnnotations.swift`）、`localstore.py`（§6 表里七个键已不存在）。
另外 `scan.py` 拦下 20 个未登记的 SDK 名字，逐个对着 Apple 文档 JSON 核过之后登记
（核实里**当场改掉一个真错误**：`SimpleMaterial.init(color:roughness:isMetallic:)` 的
`roughness` 是 `MaterialScalarParameter` 而不是 `Float` —— 传 Float 变量编译不过）。

本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**。这一轮风险最高的三处
（都写在各文件的头注里）：RealityKit 那一段（`RealityView` 是 iOS 18+、`@Sendable` 的
`make` 闭包里不碰 `self`）、`MapSpineAnnotations.swift` 这次搬移（八个函数从
`private` 放开）、以及 `scrollEdgeEffectStyle`（iOS 26+，部署目标正好是 26.0）。

---

## 21. 2026-09-25 第十轮：CI 第一次红（3 条）+ 用户四条回执

这一轮只有两件事：把 CI 第一次红修掉，然后按用户的四条回执动手。

### 21.1 CI 第一次红：三条错，全在同一行形状上

```
CarModelView.swift:269:18: error: value of type 'Entity' has no member 'model'
CarModelView.swift:274:22: error: value of type 'Entity' has no member 'model'
CarModelView.swift:278:19: error: value of type 'Entity' has no member 'model'
```

根因是一处**类型写宽了**：`CarRig` 里 `doors: [Entity]` / `trunk: Entity?` /
`headLights: [Entity]` —— 而给它们上色走的是 `door.model?.materials`（改状态色那条路）。
`model` 在 `HasModel` 协议上（**`ModelEntity` 符合它，`Entity` 不符合**），
所以「写宽」不是「更灵活」，而是**当场丢掉能力**，并且要到 CI 才发现。

改成 `ModelEntity` 之后这行代码的意思也更准确了：那三处本来就都是 `ModelEntity(...)` 造出来的。
**本机没有编译器时的规矩**（这一轮新加的）：**造出来的是什么类型，就写什么类型** ——
写宽只会把错误推到 CI，写窄编译器会当场告诉你。

### 21.2 四条回执与落地

| 用户回执 | 落地 |
|---|---|
| 「1、先正常启动试一次」 | `LaunchFence` 四个开关**全部打开**（`sixPageDeck` / `launchServices` / `splash` / `mapFetches`）＝ 正式形态。文件头的实验记录从「① 最小启动」改成「① 最小启动 → ② 四个全开」，并写明**如果又退，按什么顺序往回关**（先关最大的一笔：六页同屏） |
| 「3、试试（但是我追求的就是液态玻璃的美感）」 | 卡片不再一律 `.regular`：按**底下真的是什么**选变体（见 21.3） |
| 「5、试试」 | 抽屉给了记忆与呼吸（见 21.4） |
| 「6、私库和个人 ipa，没有任何泄露」 | 把用户的判断记进 `Services/GithubToken.swift`（事实照旧：它进了仓库历史、也会进 ipa；只是**当下没有第二个读者**）。不是「安全」的证明，是一条备注：哪天要把这个 repo 或这个包给别人用，先换一把 |

### 21.3 卡片那一步不是开关，是**事实的传递**

新增 `EnvironmentValues.photoBackdrop`（默认 `false` ＝ 底下是纯色画布）：

- 铺照片的那五张子页：`.environment(\.photoBackdrop, wallpaper.image != nil)`
  —— **选了「不铺」或还没选时回落到 `TokensPalette.canvas`（一块纯色），那就是 false**；
- 地图那一档：`.environment(\.photoBackdrop, true)`（底下是瓦片，连续的画面）；
- `GlassCard` 按它选变体（`.overMedia` / `.regular`）—— **2026-09-26 第二轮删**：
  材质定死 `.clear` 之后，「底下是不是照片」这个事实不再影响任何一块玻璃，
  于是 `photoBackdrop` 环境值与 `GlassCard.frosted` 两个参数一起没了（见 §35.3）。

`Glass` 两个变体的选择规则**是 Apple 定的，不是审美定的**（HIG：*reserve clear Liquid Glass
for components over visually rich backgrounds*），而 `.clear` 压在纯色上几乎什么都看不见
（卡片会像消失）—— 所以这里没有「更透」这个旋钮，只有「底下是什么」这个事实。

**代价如实说**：`.clear` 不磨砂，卡里正文的对比度会跟着底下的照片走。卡头已经走 `TokensInk`
（第九轮），而正文那几百处仍是不透明的标签色。真机上如果某张照片让某一行读不清，
**回退就是这一行**（换回 `.regular`）。

同一轮补的一处漏：地图右侧那三枚圆钮（图层 / 定位 / 罗盘）此前各自是一块玻璃，
而**底条 + 两臂早就包在 `GlassEffectContainer` 里了** —— 挨着的玻璃要交给容器才会互相折射
（看起来是同一层材质上的三个形状，而不是三张贴纸）。现在这一列也包上了。

### 21.4 抽屉：记忆 + 呼吸

- **记忆**：`@State var drawerOpen` → `@AppStorage(MapSpineView.drawerKey)` ——
  键 `carkeeper_map_drawer`，一个**设备**键（「这台手机上我把这张卡拉出来了没有」，
  与谁登录、哪辆车无关）。写法照抄隔壁两行（`MapSpineLayer.storageKey` / `HomeMode.storageKey`）：
  键名只有一个出处，不就地写字面量。
  **「默认只有一横」没有被推翻**：没人拉过时它仍然是收起的（`@AppStorage` 的默认值是 false），
  只有用户自己拉出来之后，下次打开地图它还在那儿 —— 那是他上一步的意图。
- **呼吸**：抽屉内容从**硬切**改成 `.transition(.opacity)`。原来卡片高度在 `withAnimation`
  里长出来，而内容一上来就是满不透明（两件事不同拍）。现在同时发生：高度在长，内容在显影。

### 21.5 门禁自己长了一条（`localstore.py` 判据 ④）

加那个新键时，`localstore.py` 立刻报了「`carkeeper_map_drawer` 没定性」——这是它设计内的行为。
但同一趟输出里还有一句更值得记的话：

```
HANDOFF §6 分类表：27 个键（账号 17 / 设备 10），标题自称 27 个
```

**改之前那句是「表 26 行、标题自称 33 个」。** 第九轮删「设备与模式」等七个键时，
表里的**行**删了，而**标题里的数字**没人改（它此前已经错过一次：写照「42」实际 33）。
于是新增判据 ④：**§6 标题自称的键数必须等于表的行数** —— 这是同一个事实写在两处的
第四次（前三次：`preferredScheme` 与夜间模式、`logout()` 的清键清单、门禁登记表里指向
已删文件的条目）。

探针双向验过：把标题数字改成 99 → 当场报；把数字整段删掉 → 也报（读不到也是一种失真）；
两次都还原后哈希与改动前一致、门禁转绿。

顺带记一个**门禁自己踩的坑**：判据 ④ 第一版每次都说「对不上」，而理由打印出来是某条
setter 的注释 —— 因为我给变量起名叫 `why`，而上面 `SETTERS` 那个循环里的同名局部
（`for key, (witness, why) in …`）漏到了函数作用域里。**变量名也是一种约定**：
在同一个函数体里，别跟上面循环的临时名撞。

---

## 22. 2026-09-25 第十一轮：系统那两件仪器回来了、续航圈差 1000 倍、以及「我跑到湖里去了」

这一轮由用户三条回执 + 两张真机图带出来。三条回执里有两件是**真错**，而且都是
「一个判断错了，一整套机器跟着长出来 / 一个单位错了，一件仪器变成假象」这种形状。

### 22.1 三条回执与落地

| 用户回执 | 落地 |
|---|---|
| 「1、**我要的是系统罗盘和系统比例尺**，只是他们被时间压住了，往下调整下」 | 两件都换成**系统的**，并且第一次真正控制它们的位置（见 22.2） |
| 「5、状态栏时间后面的是**睡眠模式**」 | 不是我们画的 —— 我把那个图标读成了车（`9:18` 右边那个）；不动任何代码 |
| 「6、我的位置离车很近很近就 20 米左右，但是给我自己**定位到湖里面去了**！」 | 两套坐标系（见 22.4） |

### 22.2 「系统控件搬不动」是一句错话 —— 它为这一屏养了整套机器

第 9 条那一轮我判定：`MapCompass` 的位置由 MapKit 定死、搬不动，于是**自己画了一枚罗盘**；
同一句话在比例尺那边更贵 —— 为了「量出一把真的尺子」，多出了：

| 为躲那个不存在的限制而长出来的东西 | 数量 |
|---|---|
| `MapReader` + `MapProxy.convert` 测距、`metersPerPoint` / `scaleBar` / `ruler` / `scaleRuler` | 5 个函数 |
| `flashScale` + `scaleShown` / `scaleToken`（两秒计时器与它的代号） | 1 个函数 + 2 个 `@State` |
| `onMapCameraChange(frequency: .continuous)`（**每帧回调**）+ 它喂的 `cameraHeading` / `cameraCenter` / `cameraDistanceNow` + `lastScaleDistance` | 1 条回调 + 4 个 `@State` |

**真相**（Apple 文档里明写）：`MapCompass` / `MapScaleView` 可以当**独立视图**用，
用一条 `scope` 线挂到地图上 —— `Map(position:scope:)` + `MapCompass(scope:)` +
`MapScaleView(anchorEdge:scope:)` + `.mapScope(_:)`。也就是说**位置由持有它们的那个容器决定**，
想放哪儿放哪儿。上面那一整张表全部删掉。

同一轮还关掉了一件第 9 条留下的副作用：那一轮把 `.mapControls { MapCompass() }` **整个撤掉**，
而**撤掉不等于关掉** —— MapKit 的默认控件集里本来就有罗盘，它在地图**转过之后**自动出现
（Apple 原文：*the default mapControls configuration shows a compass when the map is rotated*）。
地图又是 `ignoresSafeArea(edges: .top)`，于是那枚自动罗盘贴在**地图自己的角**上 ——
正好是状态栏里，压住电池。用户那张截图上因此有**两枚罗盘**。现在写死两行：
`.mapControls { }` + `.mapControlVisibility(.hidden)`，两行都挂在 Map **自己**身上
（`mapControlVisibility` 是向下传的环境值，挂在外层容器上会把我们摆在别处的那两件一起隐藏）。

位置：**比例尺**在左上、**罗盘**坐在右侧那一列的第一格（Apple 地图里它也是这个位置，
下面才是「回到车 / 手机的位置」两枚）。两者都对齐到**安全区顶** —— 这一层还在安全区里，
所以「顶」就是灵动岛下沿（用户第 2 条 + 这一轮「往下调整下」）。
罗盘占一格固定尺寸：北朝上时系统那枚自己不画（Apple 的行为），留出这一格，
下面两枚钮就不会随它上下跳。

### 22.3 续航圈：半径差了 1000 倍

对着用户那张截图核图上的每一样东西时发现的：车钉外那圈**蓝色虚线圆**不是定位误差圈，
是**续航圈**（`rangeCircle`）。而它的半径只有 200 多米 —— 因为代码把车端的
`RemainedPowerMile` 当**米**用了，注释还写着「**本身就是米**，不换算、不猜单位」。

单位不是猜的，有两处硬证据：

- `API-FIELD-MAP.md`：`remainedPowerMile` 样例 `204`，单位写着 **km**（charge 与 control 一致）；
- **同一个数在卡里一直按 km 显示**（「续航 243 km」）—— 一处当 km、一处当米，这两个不能都对。

后果正是它看起来的样子：一个 243 km 的圈在当前缩放下**根本看不见**，而那个 243 m 的小圈
与「定位误差圈」的形状一模一样。改法是一处乘法（`rangeMeters` 里 ×1000），
单位也是「同一件事实」，所以换算只留这一处。

### 22.4 「我跑到湖里」：两套坐标系，不是定位不准

症状的指纹很硬：那个点**自称精度 ≤20 m**（所以图上连误差圈都不画），却落在 600 m 外的水面上。
一个「自信且错」的读数只有**系统性偏移**做得到 —— 而这里正好有三个坐标来源：

| 来源 | 坐标系 | 对不对 |
|---|---|---|
| 手机（`CLLocationManager`） | **WGS-84**（GPS 原始值） | ✗ 打在中国区地图上偏 300–600 m |
| 车（车端 `/cardata/getCarLocation?mapType=GCJ02`） | **GCJ-02**（接口自己声明的，见 `API-FIELD-MAP.md`） | ✓ |
| 地图瓦片（高德，地图右下角有署名） | **GCJ-02** | — |

所以整屏**只有自己那个点是歪的** —— 与用户看到的完全一致（车钉在小区里，蓝点在湖里）。
Apple 自己的蓝点不偏，是因为它内部替我们换了；第三方 App 拿到的仍是原始值。

改法：新增 `Services/ChinaDatum.swift`（WGS-84 → GCJ-02 的公开近似算法，
域外原样返回；另含反向的迭代版并写明它为什么留着），`PhoneLocation` 加一个
`mapCoordinate`（**画地图时才用**），三处调用点（钉 / 误差圈 / 把镜头移过去的两处）
改用它。距离、方位这类量与坐标系无关，不动。

**验证法（一步）**：站在车边按一下「手机的位置」—— 蓝点应该落在车钉上（20 m 上下）。
如果还是偏，说明这台设备的实际情况与上面那份文档不同，那就得回到「量」而不是猜。

### 22.5 验证状态

`python3 scan/all.py` —— **34/34 全绿**。

本机没有 Swift 工具链：**编译与真实观感只有 CI / 真机能回答**。这一轮风险最高的两处：
`ChinaDatum` 那两段级数（本机没法编译，所以逐项照抄公认实现、**不自行化简**）、
以及 `mapScope` 那条线（`Map(scope:)` / `.mapScope(_:)` 的用法对着 Apple 文档 JSON 核过，
但「两件仪器摆在我们给的位置上」这件事只有真机能看见）。

---

## §23 第十二轮（2026-09-25）：九条界面/功能要求，三条是**量出来的**

用户一次给了九条（原文记在下面每一行的「要求」列里）。这一轮与以往不同的地方：
**三条要求各撞上一个用 curl 量出来的事实**，而那三个事实比改动本身更重要。

### 23.1 九条各自落成了什么

| # | 用户的要求 | 落成了什么 | 证据/边界 |
|---|---|---|---|
| 1 | 行程：起终点图标分不清、是直线距离、点卡翻转、懒加载 | 「起/终」两枚**写字**的圆牌；线换成**道路路线**（OSRM）；点卡翻面看详情；滑到底自动续 5 段（按钮删了） | 见 §23.2 —— 第一次实现用的是 `MKDirections`，被门禁拦下 |
| 2 | 车辆页健康布局「太不 iOS，太业余」 | 评分区从「96pt 超细巨字 + 线性光带 + 计数条」变成**一枚环**（`DSRing`，弧＝百分比、中心写分数）；分系统行里那条 88pt 才 3pt 高的迷你光带删掉（它与右边的百分数是同一个数的两种画法） | `CardFit` 里对应的 block 同步删（它量的必须就是版式真画的） |
| 3 | 卡片三个要素加粗；抽屉打开加深模糊、关闭降低 | `TokensTypo.display(size, weight:)` 新开一个参数（默认仍是超细，只有这三个数走 `.bold`）；`GlassCard(frosted:)` —— 抽屉拉开时卡片改用**磨砂**那一档玻璃（`.regular`），收起时按底下是什么选 | 「模糊深浅」在系统材质里只有 `.clear`（不磨砂）/`.regular`（磨砂）两个变体，没有连续旋钮 |
| 4 | 底条字太弱；选中要有玻璃胶囊 | 未选中的字从自适应色改回实色 `TokensPalette.primary`（vibrancy 的本意就是压低对比度，而这是**导航**）；选中胶囊从「白色半透明扁面」换成**真玻璃**（`dsGlass`），与条子同处一个 `GlassEffectContainer` | 条子与胶囊现在是同一容器里的两块形状（iOS 26 分段控件的形态） |
| 5 | 充电页放得下不换行；全站逐个控件审 | 审了一圈：**罪犯是共享控件**，所以修在四处 —— `DSKeyValueRow`（key 原来允许两行、value 不限行）、`DSStatRow`、`DSSegmented`（固定高 32 的格子里折行 = 被剪掉）、`DSSectionHeader`，加充电页的 `miniStat` | 单行 + `minimumScaleFactor`（装不下就缩，不折行） |
| 6 | 车控要真两厢车；指令/一键降到玻璃卡上；少用多级玻璃 | 车身几何按「两厢」重画（**总长 4.60→4.10 米**而轴距不动 = 短后悬；座舱拉到尾 2.50；尾门从「车尾外的独立后备箱盖」变成竖在座舱后缘的高尾门）；`DSGroup` **不再自带一层底**（那一层 `panel` 就是「多级层」） | 见 §23.4：模型仍是基本体拼的，资产库里 0 个 usdz |
| 7 | 我的页去掉「电车」 | 删掉那张「去看车辆」的卡（它的动作只是跳到模式条上的「车辆」档），连带删掉只有它一个读者的 `TokensSize.iconLg` | 全仓搜「电车」一处都搜不到 —— 那是**服务端给的车名**，不是我们写的字 |
| 8a | Windows 聚焦又失败，必应 100% 成功 | 量出根因：**尺寸差 + 共用一个 12 秒超时**（必应那张 341 KB，聚焦那张 1.34–2.0 MB），而且一张失败就整源失败。图改成 45 秒超时 + 候选顺次顶位（索引本来就给了 4 张） | 索引与图片 URL 都实测 200（含带着 App 自己的 UA） |
| 8b | 「给通透玻璃上的字加一圈反色发光外壳？」 | 做了：`dsInkGlow()`（新文件 `Design/InkGlow.swift`，**只有一个 View 扩展**），壳色是动态令牌 `TokensHalo.ink`（暗色主题压黑 / 亮色主题提白） | 用在地图这一屏压着连续画面的玻璃字上（模式条、三个数、圆钮、图层胶囊） |
| 9 | 检查更新报 401（`Bad credentials`） | 见 §23.3 —— 令牌本身无效，而**仓库其实是公开库**（匿名就能读），所以默认改走匿名；错误体不再原样倒给用户（401/403/404 各一句人话） | curl 的四次返回都记在 `GithubToken.swift` 里 |

### 23.2 行程路线：`MKDirections` 被门禁拦下，改用 OSRM

第一版按最自然的写法用了 MapKit 的路线（`MKDirections` + `MKRoute.polyline`）。
`scan/paidcap.py` 当场报红，依据是 Apple 自己的话：

> 非 ADP 成员（＝本项目的免费账号）可以用 MapKit，**但不能提供路线导航**。

这不是「门禁太严」：那段代码在付费账号下能跑，在这个 App 的账号下不能 ——
而它可能只是安静地失败，看起来像网络问题。所以换成 **OSRM 的公共演示服务**
（免密钥、不需要账号）——与本仓「天气从 WeatherKit 换 Open-Meteo」是同一条路数。
实测（杭州 → 上海）：HTTP 200、1.1 KB、4.4 秒。

⚠️ 顺带一个容易漏的点，这一轮的实现里做了：**请求前后都要换算坐标**。
行程坐标来自车端接口（`mapType=GCJ02`），而 OSRM 吃 WGS-84 ——
直接发过去会让它拿一个偏移 300–600 米的点去求路，出来的线跟瓦片南北错位。
所以发请求前 `ChinaDatum.wgs84(fromGCJ02:)`、拿到点串后逐点 `gcj02(fromWGS84:)`。
`ChinaDatum` 头注里那句「反向换算也写了用途」在这里第一次被用上。

### 23.3 检查更新：令牌无效，而仓库是**公开库**

用户报的第 9 条是一整块原始 JSON：`{"message":"Bad credentials","status":"401"}`。
四次 curl 量出来的事实：

| 量的是什么 | 结果 |
|---|---|
| 文件里那把 93 字符的 fine-grained 令牌打 `/user` | **401 Bad credentials**（形状完整，但 GitHub 不认） |
| 同一把打 `/repos/monsm/CarInfo` | 401 |
| **完全不带令牌**打 `/repos/monsm/CarInfo` | **200，`private: false`** |
| 不带令牌打 `releases/tags/latest` | 200，附件 `CarKeeper-unsigned.ipa`（2544318 字节）都在 |
| 匿名下载那个 ipa（不走 API） | 200 |

前两条说明那把令牌是坏的（本地无法补救）。后三条推翻了一个此前记进文档的判断 ——
用户曾说过「我的是私库和个人 ipa，没有任何泄露」：**后一半成立，前一半不成立**。
所以：`GithubToken.value` 清空、`fetchLatestRelease` 不再因「没有令牌」而抛
（`.noToken` 连错误类型一起删）、错误体经 `humanMessage(status:body:)` 译成人话。

⚠️ 匿名不是万能的，这一轮**当场遇到**：连续调了几次之后，本机 IP 被回了
`403 rate limit exceeded`（`X-RateLimit-Remaining: 0`，上限 60/小时）。
手机上更可能撞上（运营商出口是大内网共享 IP）。所以那个令牌的空位留着：
哪天限流了，在这里放一把 fine-grained、只读该仓库的令牌就立刻恢复，**改动只有一行**。

### 23.4 三条边界（如实记，免得下次以为查过了）

- **模型资产**：仓库里 `*.usdz / *.glb / *.scn / *.obj` 一个都没有（查过）。所以
  「真车」目前只能是**代码拼出来的两厢车轮廓**（短后悬 + 竖直尾门 + 长车顶）。
  要真模型，缺的是资产不是代码：把 `CarRig.build()` 换成载入 USDZ 即可。
- **OSRM 是演示服务器**：没有 SLA、有速率限制、也可能变慢或不可达。
  取不到就是直线，而卡片上会写明「线是两点连线」（不能默认用户看不出区别）。
- **没有编译器也没有真机**：本轮改动里视觉风险最高的两处是
  `DSGroup` 去掉那层底（全站分组一起变）与 `GlassCard(frosted:)`（抽屉开合换材质）。

### 23.5 这一轮门禁抓到的（四类，都记在这儿免得下次重犯）

1. `copy.py`：我写的两句错误文案分别是 49 与 33 字，**超了 30 字的线**。改短。
2. `design.py` ③：`Color.black.opacity(...) / Color.white.opacity(...)` 是**色相字面量**。
   改成动态色令牌 `TokensHalo.ink`（取值表回到 `Tokens.swift`）。
3. `orphans.py`：`struct DSInkGlow: ViewModifier` + `DSInkGlow.Strength` 被判成孤儿
   （调用点写的是 `.soft` 这种隐式成员表达式，判据看不见类型名）。收成**一个 View 扩展**
   —— 没有顶层类型，也就不需要白名单。
4. `paidcap.py`：`MKDirections`（见 §23.2）。这一条是这一轮**最有价值**的一次报红。

---

## §24 第十三轮（2026-09-25）：地图页那一条手工 + 一份全站性能账

用户两条：

> 1、地图页默认极限 3D 视角；车牌名删除 电量 删除 车放正，车用玻璃胶囊 不要黑乎乎；
> 2、底部导航点选或滑动，全部页面不需要颤抖放大特效，太耗性能，总结下全部页面还有哪些
> 耗性能的列举出来，我们来看看是否减弱或删除。

第 2 条的后半句（清单）就是 §24.4 —— 那一节是**这一轮真正的交付物**。

### 24.1 第 1 条：五件事，七处改动

| 要求 | 改了什么 | 记在哪儿 |
| --- | --- | --- |
| 默认极限 3D | 新增 `cameraPitch = 65`，**三处镜头共用**；`mapStyle(.standard(elevation: .realistic))` | `MapSpineView.cameraPitch` |
| 默认 3D（补） | 开机第一帧就把镜头立起来：停在 `AppStore.parkingLocation`（上一次知道的车位）上 | `MapSpineView.task` 开头那一段 |
| 默认 3D（补） | `fly(to:)`（移到手机）与点充电站聚合点此前把 `pitch` 写死 `0` —— 一次镜头移动会把视角从 3D 打回平面 | `MapQuickButtons` / `MapSpineAnnotations` |
| 车牌名删除 | 底条左臂从「车牌前两个字」换成 `car.fill`；`plateShort` / `plateText` 删除 | `MapSpineView.bottomBar` |
| 电量删除 | 刻度盘 / 电量弧 / 盘下那枚数字徽标整块删除 | `MapCarPin`（头注写着账） |
| 车放正 | 删「按航向旋转」：`car.fill` 是**正面视角**的车，转 90° 像车歪了/翻了 | 同上 |
| 玻璃胶囊 | 钉改成 `dsGlassCapsule(variant: .overMedia)`；删掉 `surface` 画的实心黑底盘 | 同上 |

三条**没写进用户要求、但必须一起改**的：

1. **俯仰角不是「写一个更大的数」**。Apple 对 `MapCamera.pitch` 的原文是
   *“A value of 0 results in a camera that points straight down at the map. Angles greater
   than 0 result in a camera that pitches toward the horizon”* —— **没有固定上限**，
   实际能到多少由镜头高度决定、MapKit 自己夹。所以「极限」在这里的意思是
   **仍然读得清路网的极限**：65° 是 Apple 地图 3D 视图的量级，再往上地图变成一条条水平线。
2. **`Annotation("")` 不再是 `d.carName`**：第一个参数是**图上会画的标题**（MapKit 画在钉下面），
   传车名就是在钉下面再写一行 —— 用户要的正好相反。顺带把 `.frame(68×44)` 从调用点删掉：
   钉自己的尺寸归 `MapCarPin`，同一个几何只有一个出处。
3. `MapSpineData.headingDeg` **保留**（它是车端接口的原始字段，与 `API-FIELD-MAP` 一起记着
   「车头朝哪儿」这件事，将来给俯视车钉或箭头用得到）；删掉的是「它必须画出来」这个假设。

**犹豫之后没做的一件事**：钉下面的其他钉（停车点 / 充电站）也还是 `surface` 画的实心面，
没有一起换成玻璃。它们是**一屏十几个**，而第 2 条要的正好是省性能 —— 给每个充电站钉加一层材质，
就是十几个离屏合成。要统一，应该在「减少玻璃层数」那条账里一起算（见 §24.4 第 5 行）。

### 24.2 第 2 条前半：颤抖放大 —— 三处删除 + 一处根因

三处删除：

- `pageDeck` 里 `scaleEffect(1 − a × 0.035)`（六页同屏那一叠，**每帧**跟着手指变）；
- `DSPrimaryButtonStyle` 里 `scaleEffect(isPressed ? 0.985 : 1)` —— 全仓唯一一处「按下缩放」，
  而它是 `maxWidth: .infinity` 的整宽胶囊（一次非整数缩放 = 一次离屏合成）；
- `ArmSlot` 里 `scaleEffect(open ? 0.86 : 1)`（原型 `.arm{transform:scale(.86)}` 那句**不照搬**：
  它发生在「手指刚按下、条子开始展开」那一刻，而这一条底条的三个形状同处一个
  `GlassEffectContainer`、背后是一张活地图）。

**根因不在这三处，在弹簧。** `DSSwipeStrip` 的位置量 `c` 用的是 `TokensMotion.count`
（`dampingFraction: 0.6` —— 有意会弹一下）。对抽屉张开、筛选切换那类**离散**变化，那点过冲是反馈；
但 `c` 每一帧都被宿主拿去算**六页的交叉过渡 `opacity`** —— 弹簧过冲于是变成
「六页（含一张活地图）的透明度来回摆」，而那叠每一帧都在重画。新增
`TokensMotion.settle`（`dampingFraction: 1.0`，临界阻尼、不过冲），`snap` / `settle` 两处改用它。
副作用是好事：**点选**与**滑动吸附**从此是同一种动效（此前一个走 `count`、一个走 `settle`，
到同一档看起来是两件事）。

### 24.3 全站性能账（用户要的那份清单）

| # | 东西 | 量级 | 现状 | 建议 |
| --- | --- | --- | --- | --- |
| 1 | **六页同屏**（`LaunchFence.sixPageDeck`） | 6 页全建；`RefreshLoop` 2s 一拍，六页一起重求值 | 开 | 最大的一笔。可改成「当前档 + 相邻档」三页（代价：跨两档拖动时中间那页要现建，闪一下） |
| 2 | 壁纸 | 5 张子页各铺一张**全屏图**（同一张图 5 份） | 开 | 提到 deck 背后只铺一层；风险是 `now` 那页地图是透明的，过渡时会透出壁纸 |
| 3 | `MapSpineData.build()` | 每次求值一次：`parkingHistory` 每条现造一个 `CLLocation`、`parkingLocation` 每次读要 unarchive UserDefaults、`clusterHotspots` O(n²)、一堆字符串 | 每次求值都算 | 按「输入的版本号」缓存一份；或把 `parkingLocation` 读出来放进 `AppStore` 的 `@Published`（它现在每次读都解档） |
| 4 | `.realistic` 立体高程 | 3D 建筑，GPU | 本轮开 | 真机觉得卡就换回 `.standard`（一行） |
| 5 | 玻璃 | 11 处真材质 + 3 个 `GlassEffectContainer`；列表里**逐张卡**一层 | 开 | 卡片多的页面（车辆 / 出行 / 我的）把列表卡从玻璃退回 `panel`（用户第 6 条「尽量少用多级玻璃」的下一步） |
| 6 | `dsInkGlow` | 5 处（模式条那几行字在拖动时每帧位置都在变） | 本轮新增 | 它换来的是「瓦片上的字看得清」，先留着；若真机烫手，模式条那几处可以只留选中那一档 |
| 7 | 行程卡 | 每张 = **一张真 `Map`** + 两面向时存在（背面 14 行）+ 一张路线请求 | 本轮改 | 懒加载已经把同屏张数压到 5–10；再往下要「正面用静态缩略图、点了才建 Map」 |
| 8 | `RefreshLoop` | 2 s（车在动）/ 15 s（停着）/ 60 s 轻 + 300 s 重（其他档） | 开 | 已经在闸门里（`LaunchFence.mapFetches`）；2 s 那档可考虑「车在动**且**地图在前台」 |
| 9 | 启动那一批服务 | 通知授权 / 里程与充电监测 / 保养与保险排程 / 内存与网络质量监控 / 后台超时隐藏 | 开 | 都在 `LaunchFence.launchServices` 后面，二分实验用得到 |
| 10 | 一趟 14 个子视图的 `VStack` | `TripsEventsView.tripBack` | `logic.py` 只在日志里提一句 | 本 SDK 不报错（沿用 §#7 那条证据）；只为可读性，不急 |

清单里 **1 / 3 / 5 / 7** 是真金白银，**2 / 4 / 6** 是「观感换性能」的取舍，
**8 / 9 / 10** 现状合理。这份表按用户的说法是给他挑的，不是我要动的一批。

### 24.4 边界

- **本机没有 Swift 工具链、也没有真机**：这一轮改动里编译风险最高的两处是
  `MapCamera(centerCoordinate:distance:heading:pitch:)` 的四处调用（签名对着 Apple 文档核过）
  与 `MapCarPin` 重写后的整块（`dsGlassCapsule(variant:)` / `TokensInk` / `dsInkGlow` 的组合）；
  观感风险最高的是**65° 俯仰角**与**开机第一帧落在 `parkingLocation`** 这两处：
  前者可能不够「极限」、后者在「车早就开走而 `parkingLocation` 还是旧值」时会让镜头先落在旧点
  （真实定位一回来 `centerOnCar` 就把它移到正确位置）。
- **`.realistic` 与俯仰角是一对**：只给俯仰角是「斜看一张平面图」，只给 `.realistic` 是
  「俯视一堆积木」；两者要一起才有 Apple 地图 3D 的样子。回退是两处，不是一处。

## §25 第十四轮（2026-09-25）：五条手工，两条量出了数

用户这一轮的五条：行程卡的高度没被地图占满、全局字体加一层发光阴影、底部导航删掉「车辆」、
滑动选择时两端那两枚圆钮应该消失、充电页的「电压 / 电流」拥挤。

### 25.1 行程卡只占了一半（`TripsEventsView`）

**根因是 `ZStack` 的尺寸规则，不是地图。** 那张卡的两面（正面 = 地图 + 一行数字，
背面 = 6–9 行读数）此前是 `ZStack` 的两个兄弟 —— `ZStack` 取**较大的那个孩子**当自己的高度，
而背面高一截，于是正面被裁在上半截、下半截空着（看起来就是「地图只占了一半」）。
改法是把**背面当底、正面当 `overlay`**（overlay 拿到的是被覆盖那一层的尺寸），
地图取 `minHeight: 132` + `maxHeight: .infinity`：多出来的高度全归地图。
同一次把 `expand.py` 里那条 `TripsEventsView.swift:132` 的例外删了 —— 那个高度不再是写死的。

### 25.2 全局文字外壳（`Design/InkGlow.swift` 的 `DSTextGlow`）

用户原话：「全局全部字体都加层发光阴影 看看能不能在液态玻璃中看清」。
`TextRenderer` 是 SwiftUI 给「绘字这一步」留的钩子，而 `View.textRenderer(_:)` 的文档原文是
*「any text views **within it** will use renderer to draw themselves」* —— 挂在 App 根上
（`CarKeeperApp.root` 的 `.dsTextGlow()`）就是全局；挂在某一页上只有那一页（那正是
第一版 `dsInkGlow()` 那四张名单没盖住其余几百行的原因）。三条实现细节：

- 每一段 run 先画**只画影子**的那一遍（`options: .shadowOnly`），再原样画字 —— 少了这个选项
  就得把字画两遍，而半透明的字画两遍会**变浓**（这一仓的正文大量用 `.opacity`）。
- 半径按**这一段字自己的高度**选（`run.typographicBounds.rect.height >= 22` → `radiusWide`）：
  13pt 正文与 96pt 巨字不能用同一圈壳（这是上一版那个 `strong:` 参数的全局版）。
- `displayPadding` 报出去：文档给这个属性写的用途原文就是
  *「when drawing the text with a shadow this may be used to extend the drawing bounds to avoid
  clipping the shadow」*。

两条后果如实记：① 三处**文字**上的逐处 `.dsInkGlow()` 因此删掉（两层壳叠在一起只是更浓），
`dsInkGlow()` 保留给**图形**（SF Symbol 不是字，渲染器碰不到）；② 代价是**每条文字的 run
都多一遍离屏模糊**，关掉它 = 删掉根上那一行。**未验证**（只有真机能答）：渲染器会不会绕过
材质文字的 vibrancy（`TokensInk`），以及 `displayPadding` 会不会让文字盒变大。

### 25.3 充电的「电压 / 电流」（拥挤的算术）

它原来是一个字段拼出来的句子 `398.2V / 12.4A`（12 个字符），而那一格的可写宽度是
**卡内宽 322 ÷ 3 − 两侧内边 32 ≈ 75pt**，`TokensTypo.data` 是 17pt 等宽数字 ——
5 个数字 + 点 + 空格 + 单位 ≈ 67pt，两段就是 ~110pt：只能靠 `minimumScaleFactor` 缩到 0.7，
于是同一排三个数一大一小（这正是用户看到的那一幕）。改法：`EnergyModel.voltAmp` 拆成
`volt` / `amp` 两个字段，`DSStatStrip.Item` 多一个可选的第二行（`second:`），那一格写两行 ——
每个数都是原尺寸。同一次把条子的 `HStack` 改成**顶对齐**：三格的标签仍在同一条基线上。

### 25.4 条子上删掉「车辆」+ 两端圆钮的让位

**「车辆」是唯一不在条子上的档**（用户：「因为左下角已有入口」——那枚入口就是左臂的车钮，
它一直是「回到车辆那一档」这一个动作）。三件事必须一起改，否则坏掉的那一半不会报错：

1. `HomeMode.vehicle` 挪到 **case 表的末尾**。叠叠乐的层号就是条子报的连续位置
   （identity，见 `MapSpineView.deckPos`），而 `stripItems` = `allCases` 去掉末尾那一档 ——
   排在中游的话，条子的第 2 档与叠叠乐的第 2 层不是同一件事，拖动时整叠页面错一位
   （不报错，只是看起来「页面换错了」）。排在末尾之后，它的层号恰好等于条子的长度 5，
   而那正是「五档全部淡到 0」的位置（`fade(i) = |i − 5| ≥ 1`）。
   同一次把 `pageAccents` 那一排**跟着换了位**：按下标取色的规矩没变，但五个留在条子上的页
   保持各自原来的颜色 —— 删一个入口不该把五页的配色也重排一遍。
2. `DSSwipeStrip.index` 变成 `Int?`。`nil` 的三种表现就是这条要求本身：五个字都不取强调色、
   **透镜淡出**（一枚钉在正中的玻璃胶囊，会让「我在车辆档」看起来像「我在条子的某一档上」）、
   条子停在**离当前位置最近的那一档**上（平时就是刚离开的那一档 —— 之后从条子往下拖正好接得上）。
   「此刻在哪」这个事实交给那枚车钮说（`arm(icon:current:)`，图形取强调色）。
3. `MapSpineView.deckPos` 在「车辆 + 手指已经落到条子上（`barOpen`）」时把位置**交回条子管** ——
   少了这一条，从车辆往条子上拖要等松手页面才动（拖动全过程停在车辆），而那正是「不跟手」。

**两端圆钮的让位**（用户第 4 条）改成**不在场**（`ArmSlot` 的 `if open`），而不是
`width: 0` + `opacity: 0` + `clipped()`：后者按那两个修饰符确实不可见，而这两个形状住在
`dsGlassLayer` 的 `GlassEffectContainer` 里，那个容器的职责原文就是
*「combines multiple Liquid Glass shapes into a single shape that can morph individual shapes
into one another」* —— 在它眼里「收到 0 宽」是「变小」而不是消失，而旁边那条子正在同一时刻
长到整行宽（两者还会互相折射）。顺带少两枚玻璃的离屏合成。
`ArmSlot` 同时**从 `MapSpineView.swift` 搬进 `Design/DSSwipeStrip.swift`**：它本来就是那个控件
状态机上的一个后果（见 `onExpand` 的契约），而 `MapSpineView.swift` 这一轮又撞到 1200 行 ——
搬的是**一件事**，不是一坨代码（同一条规矩在 `MapNowCard` / `MapSpineReadouts` 那两次用过）。

**顺手修掉一个真的会看到的 bug**：`rowDragChanged` 的松手分支此前**无条件吸附** —— 于是
「点左臂那枚车钮」会先换到车辆档、紧接着被按原地位置吸回某一档（看起来是「点车钮没用」）。
现在只有**真的拖过 8pt** 才吸附；没拖过的那一下是「点」，不是「拖条」。

### 25.5 门禁这一轮的三处

- `scan.py`：新登记 `TextRenderer` / `EdgeInsets`（都取过 Apple 文档 JSON：前者 iOS 17+，
  而 `View.textRenderer(_:)` 这个**修饰符**是 iOS 18+；后者 iOS 13+，是 `displayPadding` 的类型）。
  同时**删掉 `onMapCameraChange`** 那一条：全仓只剩注释里提到它（第十一、十二轮把两个读者都删了）。
- `expand.py`：删掉 `TripsEventsView.swift:132` 那条例外（见 25.1）。
- `orphans.py`：`InkGlow.swift` 进白名单 —— 文件里唯一的类型 `DSTextGlow` 只作为
  `.textRenderer(_:)` 的参数在**本文件内**被构造（系统只给这一种接法），理由与 `DSGlass.swift` 同形。

### 25.6 边界

本机没有 Swift 工具链、也没有真机。编译风险最高的两处：`DSTextGlow`（`TextRenderer` /
`.flattenedRuns` 的写法对着 WWDC24 的样例与文档 JSON 核过）与 `ArmSlot` 的
`@ViewBuilder body(content:)`。观感风险最高的是**全局文字外壳**：它同时动了几百处文字的
绘制路径（包括材质文字的 vibrancy 与 `displayPadding` 带来的盒尺寸变化），而这两件只有真机能答。

## §26 出行页：行程 / 事件改成两段（tab）

用户（同日，接 §25）：「出行里面行程卡和消息列表的上下布局改为 tab 页」。

**改的是什么**：`TripsEventsView` 的叠叠乐从「一张长卷」（总览 → 30 张行程地图卡 → 常停之地 →
评分 → **车的事件**）变成「巨字头 → 分段控件 → 当前那一段的卡」。两段是 **行程**（总览 /
行程卡 / 常停之地 / 评分）与 **事件**（`MessagesSection`）。

**为什么不是给行程卡与消息各自一叠**：分段控件与巨字头停在原地（它们是同一张卡），
换段时下面那一叠只换成员 —— 这是车辆档（档案 / 健康 / 保养）已经定下的做法，
同一件事只有一种做法。

四处跟着改的（它们都是「一份事实一个出处」的直接后果）：

- **段落词汇用现有的 `HomeSub`**，新增 `journeys` / `events` 两个 case 与 `tripsTabs`；
  不另写一个页面局部的枚举 —— 「档内段落」这件事只能有一份词汇。段落状态是 `@State`
  （不是持久化的键）：它是一次**看法的选择**，不是「当前位置」（后者是 `HomeMode`）。
- **懒加载只挂在「行程」那一段**（`reachBottom`）：事件那一段是一次列完的消息流，
  给它挂「到底就续 5 段」只会无缘无故多放出几张卡。
- **「更早的 N 段」那张卡的文案改了**：它写的是「在下面「车的事件」里」—— 而车的事件
  现在是另一段，不在下面。**指示的是位置，位置换了，指示也得分着换**。
- 文档与注释里四处「在下面 / 下面那张」同步改成「那一段」（`tripCardCap` 的说明、文件头、
  空态那句、`restAsMessagesRow`）。

**没改的**：常停之地与评分留在「行程」那一段（聚类与评分都是按同一份行程算出来的，
不是第三种读法）；`.trips / .parking / .score / .dashboard` 四个深链仍然落到「出行」档，
而它们的落点默认就是第一段（`@State` 的初值）—— 所以这次不需要 `nav.homeSub` 提示那套机制。

**边界**：切段时那一叠的滚动位置不重置（车辆 / 「我的」两档本来也是这样）——
事件那一段只有 3 张卡、装不下一屏时偏移会被系统夹回 0，所以实际看不太出来；
真机上若觉得疙疙瘩瘩，下一手是给 `ArcStack` 加一个「换卡表就回项」的输入。

### 这一轮的 CI 只红了一条（`MapSpineView.swift:681`）

`run 8a803d9`（2026-09-25T15:34）BUILD FAILED，全日志只有一条错：

```
MapSpineView.swift:681:62: error: result values in '? :' expression have
mismatching types 'Color' and 'AnyShapeStyle'
    .foregroundStyle(current ? TokensPalette.accent : TokensInk.primary)
```

- **根因**：`TokensInk.primary` 是 `AnyShapeStyle`（装箱的层级样式，见 §20 那一轮
  「玻璃上的字要自适应」），而 `TokensPalette.accent` 是具体 `Color`。
  **Swift 的三元要求两个分支同一个类型** —— 这条账是 §20 换字色时留下的：
  同一次改动的两半各自来自两个类型世界，而本机没有 Swift 工具链，只有 CI 能看见。
- **修法**：`current ? AnyShapeStyle(TokensPalette.accent) : TokensInk.primary`
  —— 把具体色装箱到对方那一支的类型上。
- **为什么不「两边都用 `Color`」**：非当前态那一支走的正是**自适应色**，
  那是这一枚钮压在真玻璃上要的东西（见 `armLabel` 上面那段）；
  为了类型好看把它换成 `TokensPalette.primary` 就是悄悄改设计。
  （`DSSwipeStrip` 那处「选中 / 未选中」确实两边都用 `Color` —— 因为那里
  §25 已经**明确**把导航字改回实色了，是另一个决定，不是这条规矩的反例。）
- **顺手全仓查了一遍**：`MapQuickButtons.swift:97`（两支都是 `TokensInk`）与
  `DSSwipeStrip.swift:440`、`MapSpineReadouts.swift:174`、`ScoreSection.swift:219`
  这些三元都各自同类型 —— **混类型的只有这一处**。
- **行数**：这一改把 `MapSpineView.swift` 推到 1202 行（越过 1200，`lintcfg.py` 会红），
  把注释压到四行后回到 **1199**。

**教训一句话**：这里没有任何一条本机门禁能替 CI 看类型 —— 所以「两个分支来自
两个类型世界」这种事，写的时候就得自己盯：`TokensInk.*` 旁边不许直接坐一个 `Color`。

---

## §27 第十五轮（2026-09-26）：底条照相机重构、两个显示设置、刷新节律改四档、镜头跟着车、行程卡去掉电量

用户这一轮的六条要求，落下来的东西与**只由 CI / 真机能回答的部分**：

### 27.1 底部导航照相机那条模式行的形状重建

用户：「你并没有按照相机 app 来设计底部导航，重新仔细研究相机 app 的逻辑，来重构我们的底部导航」。
相机那张图（他附了三张截图）里的形状是：**模式名在一整条贴底的全宽横带里，选中的那个套一枚胶囊；
两枚圆钮在它上面一行**。我们此前是「圆钮 + 浮胶囊 + 圆钮」同一行。

- `MapSpineView.bottomBar` 改成**两行**（`VStack`）：上面一行两枚圆钮（左 = 车辆那一档的入口，
  右 = 快捷车控），下面一行只有模式条 —— 于是它拿到的就是整行宽度（374）。
- `DSSwipeStrip`：条宽不再是变量（`barWidth(width:)` 直接返回容器给的宽度），
  形状从胶囊改成圆角矩形（横带的两端不是半圆），间距只有一种算法（**全部档位都装下**）。
- **连带删掉的**（同一个决定的另一半，留着就是两套形态）：`expand` / `onExpand` / `retractToken`
  / `ArmSlot`（两枚圆钮的「让位」）与那两条 620ms 收回计时器。它们存在的唯一理由是
  「静止只露三档」—— 而那个前提正是**圆钮在挤条宽**造成的，圆钮一走它就没有对象了。
- 顺带：`MapSpineView.deckPos` 里那个读 `barOpen` 的分支改读 `barRowDrag != nil`
 （「手指在不在条子上」这个事实，本条转发自己就有）。

### 27.2 两个自定义设置（`Design/DisplaySettings.swift`，三个新键）

用户：「设置文字的发光阴影程度；全局调整液态玻璃的通透度？（可行的话）」。

- **可行性的实话**：系统没给「材质的透明度」旋钮。能选的是**用哪一档材质** ——
  所以「玻璃通透度」是三档（更透 = `.clear` / 标准 = 按底下是什么选 / 更实 = `.regular` + 一层
  `Glass.tint`），而**滑块**调的是另一件事：App 自己那几层半透明的底有多实
 （`TokensPalette.panel` / `fillSubtle`，以及「更实」那一档的 tint 浓淡）。
  两件分开是为了让「更透的材质 + 更实的底」这类组合也调得出来。
- 文字发光程度是 0…100% 的滑杆，**默认 50% 恰好等于 2026-09-25 那一版的样子**
 （半径 3 / 4、浓度 0.45 / 0.65）—— 装上这一版界面一处不变，起点是用户上一步看到的那张脸。
  两处读它的地方（`DSTextGlow.draw` 与 `displayPadding`）必须是同一个数：半径画得比留白大，
  光会被裁掉一角。
- 三格都是**设备**键（§6 那张表从 27 行加到 30 行，标题里的数跟着改）：这一台手机上我把界面调成什么样，
  与谁登录无关。

### 27.3 刷新节律改成四档（见 §2.3 那张表）

用户：连续 10 次 0 速度 → 15 秒；有速度 → 2 秒（自动刷新 api）；其他页面 1 分钟；
重 api「用户查看时再加载，或每 5 分钟一次」。

**当场修正**：做完之后用户问「那是不是 15 秒后读到速度又恢复实时刷新」—— 是（`interval`
第一个分支就是它，最多 15 秒 + 一次请求就回到 2 秒），但顺着这一问发现「连 10 次才切」那个
形状里「刚停下」比「停很久」问得还少，于是用户当场选了**一读到 0 就是 15 秒**。

- 停着那一档最终不是任何一个定值，而是一条**退避曲线**（用户第二次回过来说
  「15 秒久了，改用更智能的算法吧，直至最高 60 秒」）：`2 → 4 → 8 → 16 → 32 → 60`，
  每读到一次 0 速度翻一倍。自变量是「连着读到过几次 0」（读数就是自变量，不另记时刻）；
  封顶 60（用户给的数）—— 一停一整夜就是 60 次/小时，而不是固定 15 秒那种 240 次/小时。
- 重的两路（消息 + 体检）只在**翻到这一页时**或每 5 分钟取一次；其余时候那一页只要车况四项。
- 循环的睡眠改成**一秒一格**：换档要当场生效（那一页的重数据要当场取），
  而一口气睡完的写法会让它等到这一觉结束。

### 27.4 镜头跟着车（新文件 `Features/Map/MapCameraFollow.swift`）

用户：「地图页要随着车的方向实时改变地图朝向 …… 车永远居中在地图顶部到底部抽屉之间居中，
选了人的位置也同样的逻辑显示，车在运动的时候车永远是优先于人的位置显示」。

- 四句话 = 四件可判的事：朝向随车（车动时 `heading` = 车头朝向，停着回正北）、
  车钉落在「地图顶 → 抽屉」那段的正中（镜头中心沿**车背后**那个方向推出去一段，
  而不是「向南推」—— 地图按航向转起来之后屏幕下沿已经不是南了）、
  人那一侧走**同一个函数**、车动时一律跟车。
- 新状态 `follow`（跟车 / 跟手机）：按那两个钮改的是它，不是「上一次移过镜头」。
  手机的位置一到就移镜头那条 `onChange` 加了 `follow == .phone && !isCarMoving` 两道判断 ——
  少了第一道，之前选过手机之后每一次手机定位报点都会把镜头拉走。
- `centerOnCar` 与新状态一起搬出 `MapSpineView.swift`（它当时 1231 行，越过 `lintcfg.py` 的 1200）；
  据 `didCenterOnce` 放开了 `private`（跨文件读，`extguard.py` 盯着这一类）。
- ⚠️ 只有一个数需要真机校：`spanFactor`（一屏纵向覆盖多少米 ÷ 镜头距离）。
  车钉偏高/偏低就改这一个数（0.5 = 车钉正好落在正中）。

### 27.5 行程卡：去掉电量，显示起点与终点位置名

- `TripRecord` 加 `startAddr` / `endAddr`（**带默认值的 `var`**：让两个构造点里暂时没有地址的
  那一处不必为了新字段而改）。
- 名字来自点火 / 熄火两条消息各自的 `addrName`（舱单里本来就有，没有任何一步是反查）。
- 正面地图下面多一行「起点 → 终点」，背面那张表把「电量 60% → 55%」换成「起点 / 终点」两行。
  **两个名字都缺时那一行整个不出现**（不画一个空箭头）。
- 合并两个数据源时**位置名从落选的那条补上**：一边有里程、另一边有地址是常态，
  少了这一步，「合并」恰好会把唯一存在的那两个名字丢掉。
- 留在原地没动的那两行：`每 1% 电量` / `平均能耗`。它们不是「电量」这个状态，
  而是**算得出来的能效**（且 `kmPerPercent` 是本机唯一真算得出的那一个口径）。
  用户若要的是「这一页不要任何与电有关的字」，那两行也该删 —— 这一条等他一句话。

### 27.6 验证状态

`python3 scan/all.py` —— **34/34 全绿**（三处新键进了 §6 那张表；`MapSpineView.swift` 压在 1199 行）。

本机没有 Swift 工具链：**编译只有 CI 能验**，而这一轮的观感（横带的比例、车钉落在带子的哪个位置、
发光滑杆的手感）**只有真机能验**。风险最高的两处如实写在这里：
`Glass.tint` 这个材质用法（名字对着 Apple 的 Liquid Glass 文档核过，但本机无法编译确认），
与 `@ObservedObject` 挂在 `App` 上能不能把整棵树带着重画（若不能，设置会在下一次换档时生效）。

---

## §28 第十七轮（2026-09-26）：底条照相机重构**改对了**、两个「画不出来」的修法

用户：「底部导航的改错了，你并没有仔细看相机底部导航静态和动态时的结构，先读懂，给我看后再实施」。
先只量、只读、不动代码，量完把结论交回，他确认后才改（本次）。

### 28.1 三张图按像素量出来的东西

工具是 Pillow（`python` + `PIL`，本机有）：找暗带、量字宽字高、数亮像素、按局部对比度判断
「这一块有没有东西」。**量出来的**（不是看着像）：

| 量什么 | 相机静态（图 1，1206×627） | 相机动态（图 2，手指拖到一半） |
|---|---|---|
| 可见档数 | **3**（视频/照片/人像）—— 而两图合起来证明这台机器有 6 档 | 5 档半（最左那档被屏幕左边缘切掉） |
| 字距（节距） | 190px ≈ 62pt | 190px —— **与静态一样** |
| 选中那枚字 | 78×33px | 同量级 |
| 选中胶囊 | ≈197×122px（顶边平直段 131px） | 同量级，且**不在正中**（55% 处） |
| 底带 | 顶边一条直线，离屏幕底 247px ≈ 81pt | 顶边抬到 295px ≈ 97pt，且更实（白墙 255 → 95，≈60% 黑） |
| 字心离屏幕底 | 175px ≈ 57pt | —— |
| 两枚圆钮 | 缩略图、翻转镜头，**与字同一行**、在带子两端 | **不在场** |

两条推论就是这一轮的骨架：①**静态只露当前档 ±1**，其余靠拖（不是「五档铺满」）；
② **两枚圆钮本来就在这一行** —— 「只露三档」是它们的后果，不是另一个审美选择。
第三张图是我们自己的界面（v16 之前那一版），量出来的结果在 28.4。

### 28.2 v16 错在哪：两处都是「把后果当成了选择」

- 静态改成「五档等距铺满整行」—— 相机没有这个形态；
- 把两枚圆钮挪到条子上面另起一行，理由是「条子只剩 240pt」—— **推理是反的**：
  正因为两枚钮在这一行，条子才只放得下三档。

（其余量到的差：底带实度我们约 20% 黑、相机约 60%；这一项**没改** ——
「玻璃通透度」现在是用户自己那根设置，全局一个数，不该由底条另立一套。）

### 28.3 现在的形态（用户 2026-09-26 的三个选择）

> ⚠️ **本节的三条已被 §29 纠正**（第三批干净裁图量出来的是另一个形状）：
> 「条宽 = 三档 + 两条间距」是把观察到的结果当输入；底玻璃**不是通铺**而是两钮之间的胶囊；
> 「不做动态态」是当时的取舍，§29 起照相机做了。读本节请连着 §29 一起读。

1. **静态三档**（照相机）：`DSSwipeStrip.staticSlots = 3`，条宽 = 三档 + 两条间距（≈193pt）。
   它不再是插值 —— 「几何用的宽度」与「画出来的宽度」因此是同一个函数（`barWidth(gap:)`）。
2. **两枚圆钮回到这一行、在带子两端**：`bottomBar` 从两行 VStack 改回一行 HStack，
   两个 `Spacer(minLength: 0)` 把圆钮推到两端；中段 = `stripLaneWidth` = 整行 − 两枚 58 − 两条 9 ≈ 240pt。
3. **跟手形态照旧、透镜钉在正中**（他原话：「底下的带子随手动，但是玻璃胶囊永远居中显示」）——
   也就是**不做**相机那种「按下时圆钮让位、带子变高变实」的动态态；`expand` / `ArmSlot` 仍在历史里。
4. 顺带把条子自己那圈玻璃删了（`bar(width:)`）：底玻璃现在是宿主那条**通铺的带子**（`MapSpineView.band`）——
   一条带子里再画一根窄的，就成了「带子里又有一根带子」。`glass.py` 的四条判据重跑绿。

### 28.4 两个「画不出来」的修法（没有一条是猜的）

用户答「v16（两行）也这样」—— 而他那张图上我量到的是：**条子内部整片平坦**
（行内起伏 < 8/255，一个字形都没有）、**左钮内部也平坦**（68…69、起伏 0），
只有右钮那枚钥匙是白的（251）。也就是说那两处确实什么都没画出来。本机不能编译、
不能复现，于是**把能让人「什么都不显示」的机制一条条拆掉**（而不是猜哪一条是元凶）：

- **条子：删掉标签裁剪判据**。原本只有 `x` 落在条子附近的那两档才画（其余靠遮罩裁），
  画的多少取决于一个**算出来的位置**；现在五个字全画、靠 `.mask { Rectangle() }` 裁 ——
  窗口里一共五个字，代价可以忽略，而少一条判据就少一整类「算错就什么都不显示」。
- **底条上的字与图形一律实色**：左钮的图形从 `TokensInk.primary`（自适应墨色 / vibrancy）
  换成实色 `TokensPalette.primary`。两枚钮走的是同一段代码，当时唯一的差别就是颜色 ——
  同一行里实色那枚（钥匙）量到 251，自适应色那枚（车）量到「空」。
  ⚠️ 这条依据是**两张截图的对比**，不是受控实验：若装上之后仍然看不见，下一个要排的就是
  全局文字外壳 `DSTextGlow`（关掉它只需删 `CarKeeperApp.swift` 里那一行 `.dsTextGlow()`）。
- 连带删掉 `arm(text:)` 那个车牌分支（已无调用点，里面的 `TokensInk.secondary` 正是要治的东西）。

### 28.5 一处如实写下的偏离

相机那条底带一直铺到**屏幕最下沿**；我们停在离底 26pt（`band` 只比行高多出来的那部分没加）。
理由：MapKit 的法律信息与「高德地图」那两行字就在这 26pt 里（`.ignoresSafeArea` 之后它们
是屏幕最底一格的常客），盖住它比少 26pt 更糟。要照相机铺到底，`band` 上加一行
`.padding(.bottom, -Self.barGap)` 即可（代价是那两行字被盖住）。

### 28.6 验证状态

`python3 scan/all.py` —— **34/34 全绿**（`MapSpineView.swift` 压在 1199 行、`DSSwipeStrip.swift` 591 行）。

只有 CI 能验：这一改动了两个文件的类型面（`arm` / `armLabel` 去掉了 `text:` 形参与
`AnyShapeStyle` 装箱、`band` 用 `Rectangle` 当 `InsettableShape`）。
只有真机能验：三档窗口在 390pt 上的疏密、通铺带子的实度（它现在由「玻璃通透度」那根设置决定）、
以及 28.4 那两处是不是真的回来了 —— **这一条最想要一张新截图**。

---

## §29 第十八轮（2026-09-26）：第三批裁图定形 —— 底玻璃是**两钮之间那一条胶囊**，并补上相机的拖动态

用户：先读懂三张图（这一批是**裁出来的干净底**，1206 宽，3.07 px/pt），用 HTML 模拟出来看；
看完选「全照相机」→ 才动 Swift。模拟页在 `design-preview/camera-bar.html`（三张图的 1:1 复刻 +
一块可拖的 + 我们 v18 的两态），它自己也是量出来的：**我的模拟里先后量出两个错**（静态窗口
写成 248 而不是 215，于是「再远一档」会探进窗口；渐隐用了层外坐标），两处都改了。

### 29.1 三张图比 §28 多量到/纠正了什么

| 量什么 | 图 1 静态 | 图 2 / 图 3 拖动中 |
|---|---|---|
| 底玻璃 | **两枚圆钮之间的一条胶囊，660×144px = 215×47pt**（两端半圆） | **溶解**（纯黑底里量不到它） |
| 两枚圆钮 | 144px = **47pt，与带子等高**；离屏边 102px = 33pt；中缝 28px = 9pt | 不在场 |
| 选中胶囊 | 219×124px = **71×40pt = 0.86 × 带高** | 237×144px = **77×47pt = 1.0 × 带高** |
| 胶囊位置 | 带子正中 | **仍在正中**（两图都是 603px）—— 跟手的字，不是胶囊 |
| 字距 / 字号 | 190px = 62pt（**1.32 × 带高**） / 40px→13pt（带高 3.6 × 字高） | 与静态**完全一样** |
| 字色 | 选中黄 #FFD60A，其余纯白，且黄字压在胶囊**上面** | 最外那档暗到 ~57% |

两条推翻 §28 的结论：① 静态那条**不是通铺全宽**，是两钮之间那一段（而 **215pt 恰好就是
那一段** —— 所以它不是常量，是「行宽 − 两钮 − 两条中缝」）；② 拖动时带子不是「变高变实」而是
**溶解**（那条结论来自一张没裁干净的照片：黑底上那点亮度差是背景，不是带子）。

### 29.2 落进代码的（几何全部按上面那几条推出来）

- **带子 = 条子自己**：`DSSwipeStrip.band(barW:)` 画一条 `Capsule`，宽度 = `availableWidth`
  = 两钮之间那一段；宿主的 `MapSpineView.band`（通铺矩形）**删了** —— 两处各画一次就成了
  「一条窄的坐在一条宽的里」。
- **圆钮 58 → 54（与条高相等）**，`barPad` 仍 8pt（⬇ 29.4 那条偏离）；于是
  `stripLaneWidth` = 374 − 108 − 18 = **248pt**，而相机那 215pt 正是它的同一个量
  （相机：33+47+9+215+9+47+33 = 393；我们：8+54+9+248+9+54+8 = 390，带子占同一段的比例 0.66）。
- **节距 74 → 71**（= 带高 54 × 1.32）：`slot` 38 → 36、`gapMax` 0.73 → **0.65 × 带高**，
  且它按 `spillWidth` 算而不是按带宽 —— 两张图量到的字距一样，所以这个数不能挂在带宽上。
- **`staticSlots` 删了**：条宽不再由「静止看得见几档」推。三档现在是几何的**后果**
  （248 ÷ 71 = 3.5：当前档 ±1 整格在带里，±2 整个在带外）。
- **胶囊两态**：`loupeWidth(pitch)` = 1.15 × 节距（静止）/ 1.24（拖动），`loupeHeight`
  = 0.86 × 条高 → 1.0。尺寸变形走 `TokensMotion.settle`（它住在 `GlassEffectContainer`
  里正是为了 morph）。
- **拖动态**（`dragging` = 手指越过 8pt，且两条通道各报各的一半）：带子淡到 0、胶囊长到满高、
  **遮罩从条宽改到 `spillWidth`（整屏）**于是字铺满、最外那档按「离开可见带多远」渐隐到 0.55。
  宿主的 `barDragging` 让两枚圆钮让位（`DSSwipeStrip.onDragging` 报上去）。
- 字画到条子外面是**故意的**：`frame` 不动（布局因此不抖），变的只有那块遮罩。

### 29.3 ⛔ 这一节的结论**已作废**（2026-09-26 当天，见 §30.2 第三条）

「圆钮的让位用透明」是错的：用户装上之后报「滚动时俩边的圆胶囊怎么不消失了」。
原因与修法写在 §30.2；下面这段保留原样，因为它记的是**当时为什么那样想**。

文件末尾那段历史说「真玻璃上的消失必须是不在场」（`ArmSlot` 那次的教训）。这次**反过来**，
理由写得进代码：带子的宽度就是「两钮之间那一段」，钮真的不在场就会把这一段撑宽，于是正在
溶解的带子位置会跳、胶囊与字也跟着跳。相机没这个问题（它拖动时带子本来就不见了）。
代价：透明之后真机上可能还剩一点形 —— **真机看见鬼影时的下一手**已经写在那里：把它挪出
`GlassEffectContainer`，而不是改宽度。

### 29.4 一处如实写下的偏离（与 §28.5 同一条的另一半）


相机两枚圆钮离屏边 **33pt**，我们仍是 **8pt**（`barPad`，原型 `.bottom{padding:0 8px}` 的值）。
不照做是算术：我们的条高比相机大 15%（54 / 47），把外边距也放到 33，248pt 的带子会被挤到
198pt，而节距 71 的「当前档 ±1」需要 213pt —— 三档就装不下了。要两边都要，得同时收条高或收节距，
那是下一轮的事。另：相机那条带子铺到屏幕最下沿，我们停在离底 26pt（MapKit 法律信息，见 §28.5）。

### 29.5 验证状态

`python3 scan/all.py` —— **34/34 全绿**（`MapSpineView.swift` 正好 1200 行、`DSSwipeStrip.swift` 661 行）。
`design-preview/camera-bar.html` 是本轮的模拟页（浏览器里能拖，已在 Preview 开过）。

只有 CI 能验：`DSSwipeStrip` 的成员初始化器多了 `spillWidth` / `onDragging` 两个参数
（声明顺序与调用点已核过：`items / selectedID / availableWidth / spillWidth / onDragging / onPosition / rowDrag`，
且把原先那个会与函数同名的局部 `pitch` 删掉了 —— 本机没有编译器，这种地方不能靠运气）。
只有真机能验：**字溢出条子会不会被上游裁掉**（`frame` 之外绘制依赖没有别的 `.clipped()`；
若真机上字在 248pt 处被切，就把遮罩与坐标搬进宿主）、圆钮透明后有没有鬼影、以及
「拖动时字铺满整屏」在 390pt 上的观感。

---

## §30 第二十轮（2026-09-26）：相机到底拿什么挡住「降低透明度」、卡片变大的账、圆钮真的移出层级

用户这一轮一次说了三件事，而它们分别落在**三处**、根因各不相同：

  1. 「每个界面的卡片怎么都变大了」
  2. 「把系统的液态玻璃变成了最不通透（辅助功能 → 显示与文字大小 → 降低透明度），
     我们的 app 变成了这样，而相机的几乎没变 —— 你好好分析下相机的层结构」
  3. 「现在滚动 俩边的圆胶囊怎么不消失了」

### 30.1 第一条：全局文字外壳的留白**改了排版**

`DSTextGlow.displayPadding` 此前返回「四面各留一格 = 外壳半径（3pt）」。Apple 对这个属性的
原话是 *「Returns the size of the extra padding added to any drawing layer used to rasterize the
text. For example when drawing the text with a shadow this may be used to extend the drawing
bounds to avoid clipping the shadow.」* —— 而那圈留白**就是这段文字的
排版尺寸**：每行字高 6pt，而卡片是按内容撑高的 → 全 App 每一张卡片都跟着长（一张五行字的卡
约 +30pt）。

为什么现在才看得见：`displayPadding` 与全局外壳是同一个提交进来的，而那一次 CI 是**红的**
（编译错，见 §26），所以用户上一个能装的包里还没有外壳 —— 他看到的「变大」就是这一处。

修法：`displayPadding` 返回 `EdgeInsets()`。**发光是绘制，不是排版** —— 一个效果不该把整棵
界面的尺寸往下推。代价如实写在那里：壳比字宽出 3pt 而没有留白，**最外那一圈会被裁掉**
（字形自己的侧边距还在）。真机上若嫌壳太弱，正解是让**宿主**留白，而不是让每一行字自己撑。

### 30.2 第二条：相机为什么不变 —— 它那一块面是**它自己画的**

先量再改（用户那张截图 888×542，用他自己的底条当尺子：条高 128px = 54pt → 2.37 px/pt）：

- 卡片内部**能看出底下的地图纹理**（亮度起伏 74…180），整块只比周围的地图亮 ~20/255；
  → 系统的降法不是「变成不透明的面色」，而是**去掉模糊、只留一层淡色**。
- 而字是白的：`TokensPalette.primary` = `.label`，深色下就是白 —— **白字压在淡色上**。
- 同一屏每一块玻璃都是这个形态，所以整屏像被几块浅色大方块盖住（远看就是「卡片变大了」）。

相机为什么几乎没变：**它那条底子底下没有系统材质** —— 那是一层半透明黑（自己画的）。
「降低透明度」能降的只有材质，没有材质就没有可降的东西。（与 §29 那条「带子是一片均匀的填充、
看不出底下的草皮纹理」是同一份测量。）

所以「像相机」不是照抄它的形状，而是：**这块面的样子由我们自己保证**。正常档交给
`.glassEffect`（折射 / 高光 / 按压都归系统），无障碍档自己给一块实底 ——
HIG 对同一件事的写法就是 *「offer solid-fill alternatives at component level」*。

落下来的（**第一版，当晚就崩了，见 §30.5**）：`Design/DSGlass.swift` 多一个
`DSGlassSurface`（`View`），读 `@Environment(\.accessibilityReduceTransparency)`，
那一档画 **`TokensPalette.surface` 的不透明实底 + 同一圈发丝线**。
那一版的理由是：扩展函数里读不到 `@Environment`（玻璃得先是一个 `View`）。
**现在的那一版不新建任何类型**：`dsGlass` 自己读系统那个属性
（`UIAccessibility.isReduceTransparencyEnabled`，UIKit），两个分支交给 `@ViewBuilder`
（一个 `some View` 函数的所有 `return` 必须同一个底层类型 —— 不标它就编译不过）。

### 30.3 第三条：`GlassEffectContainer` 会把子视图的玻璃合成成一个形状

`barDragging` 的接线一直是通的（`DSSwipeStrip.onDragging` → `MapSpineView.barDragging`），
而两枚圆钮那版是 `.opacity(barDragging ? 0 : 1)`。这一整行（两钮 + 带子 + 胶囊）在**同一个
`GlassEffectContainer`** 里，而那个容器的职责就是把子树里的玻璃**合成成一个形状** ——
透明度 0 在它眼里只是「内容不见了」，那块圆玻璃仍然算在这一层里。
（§29.3 的结论因此作废：那里写的「用透明而不是不在场」正是这一条的病根。）

修法：`arm(...)` / `quickArm` 改成 `@ViewBuilder` + `if barDragging`（不在场），占位是一块
**同尺寸**的空视图（`armSize`：底玻璃的宽度 = 两钮之间那一段，它必须一个字不变），淡出交给
`.transition(.opacity)` + 行上的 `.animation(TokensMotion.fade, value: barDragging)`。
带子同样处理（`DSSwipeStrip.body` 的 `if !dragging` + `.transition(.opacity)`）。

### 30.4 验证状态

`python3 scan/all.py` —— **34/34 全绿**（`MapSpineView.swift` 1198 行、`DSSwipeStrip.swift` 670 行、
`DSGlass.swift` 209 行、`InkGlow.swift` 121 行；这一轮没动任何门禁）。

只有 CI 能验：`dsGlass` 的 `@ViewBuilder` 分支与 `UIAccessibility` 这个名字（已登记进
`scan/scan.py` 的 `VERIFIED_SDK_ADDITIONS`）、`arm` / `quickArm` 的 `@ViewBuilder` 分支、
以及 `if` 里的 `.transition(.opacity)`。

只有真机能验（也是这一轮风险最高的三处）：
  · **容器还能不能看见包在 `DSGlassSurface` 里的玻璃**（多一层自定义视图之后，两钮 / 带子 /
    胶囊之间的折射与合并是否照旧）。这是唯一一处「可能白改」；不行就把 `glassEffect` 那半边
    搬回调用点，只把实底留在包装里。
  · 圆钮**移出层级**之后，正拖到一半的手指会不会被中断（若中断，退路是回到透明度版本 +
    把圆钮挪出 `GlassEffectContainer`，而不是改宽度）。
  · 降低透明度那一档下：实底 + `.label` 的白字 / 黑字读不读得出来、发丝线够不够把卡片与背后分开。

### 30.5 当晚返工：那一版**启动就崩**（`EXC_BAD_ACCESS` / 栈溢出）

用户装上 §30.2 那一版后的崩因报告（`bug_type 309`，`incident 9E63FF9E-FBB7-48DF-81AB-9917098721D0`）
把根因指得很具体 —— **`glassEffect` 不能从「泛型 `View` 的 `body`」里调**：

```
启动 14:49:52.577 → 崩在 14:49:54.4386（约 1.9 秒）
EXC_BAD_ACCESS (SIGSEGV) —「Could not determine thread index for stack guard region」
  即**栈溢出**（`recursionInfoArray`: depth 906 / originalLength 5572，hottest = AG 的 update）

栈顶（imageIndex 0 = 我们的二进制）：
  DSGlassSurface.body.getter                            ← 那个泛型 `View`
  swift_getOpaqueTypeMetadataImpl                       ← 在建它 `some View` 的元数据
  swift_getTypeByMangledName
  swift::SubstGenericParametersFromMetadata::buildDescriptorPath   ← 自我递归直到栈顶
寄存器里反复出现：anonymous descriptor View.glassEffect<A>(_:in:) / extension descriptor View
```

也就是说：**同一个调用，从 `View` 扩展函数里发出（`Self` 在调用点已经是具体类型）
一直好好的，而那一次被搬进一个泛型 `View` 的 `body` 之后，运行时期解析那个扩展成员的
元数据时无限递归。** 拆法是取消那个类型（回到「本文件只有 `DSGlassVariant` 一个类型」），
开关改成读系统属性；两个分支用 `@ViewBuilder`（它是**函数**，与那个崩掉的 `body` 不是
同一种东西）。这一段写进文档是为了让下一轮的人**不要再试那个包装**。

连带的一笔：`scan/delguard.py` 当场报了三条假阳性（`variant` / `interactive`「声明没了、
使用还在」）—— 它们本来就有声明，只是那声明是 `dsGlass` 的**形参**（缩进 8，
而 `MEMBER_DECL` 只认 ≤ 4）。已补判据 ⑦：**使用处所在的文件自己声明了同名形参 → 不报**。
没接在全项目的 `global_new` 上 —— 形参名（`style` / `pad` / `row`）太常见，
放进去会把真错永远遮住。

---

## §31 第二十二轮（2026-09-26）：底条不再走系统材质、卡片变大的根因（一个自引用的宽度）

用户一次给了两个问题、一处纠正，落下来是三件事。**这一轮的全部依据都是拿 PIL 从
那张 1206×2622（= 402×874pt，3 px/pt）的截图里量出来的数**，不是看着像。

### 31.1 卡片「变大」的根因：一个自引用的宽度（不是卡片自己的常量）

先排除了最容易被赖的那一头：`StackSpec.Card.inset` / `padH` / `radius` 与页面留白
在近十几个提交里**一字未改**（`git log -S` 逐个数过）。量出来的事实是：

| 量什么 | 值 | 应该是 |
|---|---|---|
| 第一张卡的**上**沿 | 234px = **78pt** | 78（= 安全区 62 + 16）✅ |
| 「充电」二字左缘 | ≈ 32px = **10.7pt** | 36（= 页 18 + 卡 18） |
| 卡左缘 | ≈ **−8pt**（在屏幕外） | +18 |
| 底条那条带子 | 895px = **298pt** | 260（= 402 − 16 − 108 − 18） |
| 两枚圆钮 | 各被屏幕边切掉 ≈ 66px = **22pt** | 完整可见，离屏边 8pt |

竖向一个数都不差、横向处处往外溢 ≈ 22–25pt —— 这不是「卡片变大了」，是**整层比屏幕
宽、又在窗口里居中**，于是每一页、每一张卡、底条上的每一件都跟着往外溢。

**哪一层把它撑宽的**：底条的宽是**量自己那一行**得到的

```
containerWidth  ←  GeometryReader 量 bottomBar 那一行
barRowWidth     =  containerWidth − 2 × barPad
stripLaneWidth  =  barRowWidth − 2 × armSize − 2 × barSeam
这一行的理想宽   = 2×barPad + 2×armSize + 2×barSeam + stripLaneWidth
```

代进去：`理想宽 = containerWidth` —— 也就是**量到多少，这一行就有多宽，下次就还量到
多少**。`X ≥ 屏宽` 的每一个值都是稳定不动点（不是唯一解），所以某一帧量到偏大
（换档 / 转场 / 六页同屏那一帧）它就**永久闩在那儿**，再不回来。截图里量到的那个闩值
≈ 440pt，于是 298 = 440 − 142 与 22pt 的溢出**互相印证**（同一台机器、同一个根因）。

这条链条是 `785344b`（09-24）引入、`80e1ade`（09-26）接上的；两版都把「量自己」当成
条宽的唯一输入。**修法不是调数，是切断自引用**：

- `body` 外面一层 `GeometryReader` 量**屏幕**（它拿的是 proposal，子树画多宽都改不了它）；
- `deck` / `pageDeck` / `pageBody` / `bottomBar` 全部钉成 `minWidth = maxWidth = pageWidth`；
- `deck` 的 `ZStack` 再钉一道 `frame(width:)` —— 任何子层的「理想宽」都不许撑开它；
- `ArcStack` 的卡叠与**每一张卡**也钉到量到的视口宽（卡里有一件理想宽更大的东西时，
  它自己溢出，推不动别的卡）；
- `@State containerWidth` 整个删掉（连同 `barRowWidth` / `stripLaneWidth` /
  `stripSpillWidth` 三个 `var` → 三个吃 `pageWidth` 的函数）。

### 31.2 底条不再走系统材质（相机为什么「不响应」）

用户：「系统玻璃变最不通透后，我们的底部导航也响应了，而相机的不会响应」。
相机那条横带**底下没有系统材质** —— 它是自己画的一层半透明面；而「降低透明度」能降的
只有材质，没有材质就没有可降的东西。所以那条带子在两种设置下**逐像素相同**。

现在两条都照相机做：`TokensPalette.barFill`（亮 = 白 72% / 暗 = 近黑 72%）与
`barSelection`（比底子再偏一层明暗的选中格）。`tokenDynamic` 因此多了一个 `alpha`
形参（只服务这两个值）。**顺带解决了两件一直没修掉的事**：

1. `GlassEffectContainer` 会把同层的字与选中胶囊一起吞掉（真机上量到「带子里一个字都
   没有」）—— 底条这条路上再没有玻璃，也就没有那个容器（`.dsGlassLayer` 从
   `bottomBar` 上删掉；地图右侧那几枚钮仍然用它，它们压在**连续画面**上，那条路没问题）。
2. 「降低透明度」那一档再也不用管了：它不再影响底条。

### 31.3 左钮的图形为什么只在「不通透」时消失

同一段颜色代码，两枚钮在真机上表现不同：左边（`Button`）空了，右边（`Menu`）一直在。
差别只剩容器 —— iOS 会替玻璃层上的 `Button` 处理它的 label，那一步在那一档下把图形
吞掉了。现在**图形面在 `Button` 之外**（`armDisc` 只当 label 与命中区，`armGlyph`
画在它上面并 `allowsHitTesting(false)`）。依据是两张截图的对比、不是受控实验。

### 31.4 验证

`scan/all.py` **34/34 全绿**（`MapSpineView.swift` 1195 行、`ArcStack.swift` 220、
`DSSwipeStrip.swift` 683、`DSGlass.swift` 222）。`design-preview/camera-bar.html` 里
那一格已换成 **v19 三态**（静止 / 拖动中 / 系统设成最不通透），第三帧与第一帧同源 ——
那是这一轮最直接可验收的一件东西。

只有 CI 能验：`deck` 多了一层 `GeometryReader` 后的成员顺序、`tokenDynamic` 的新形参、
所有 `frame(minWidth:maxWidth:)` 的写法。
只有真机能验：闩是否真的不再发生（这是本轮唯一的目标）、自己画的那层在亮色下的观感、
圆钮改自画面之后按压反馈还在不在。

---

## §32 第二十四轮（2026-09-26）：整族尺寸回到相机量到的值、吸附不再「甩到邻居」、子页也能从底条下穿过

用户三条，一条一个根因，都不是调数：

1. 「滑动到 A，放手就容易去相邻的入口」——**吸附把速度当成了位置**；
2. 「左右 2 个圆球太贴着边框了，和相机的尺寸距离大小不匹配」——**整族数比相机大 15%**；
3. 「地图页和下面的底部导航可以穿过，为什么其他的界面都不能穿过底部的导航」——
   子页那一条 `.padding(.bottom, barTotal)` 把**滚动视口截在条子上沿**了。

### 32.1 带高 54 → 47：一族数一起回位（这是第 2 条的根因）

第 2 条表面上只说了两枚圆钮，实际是**整族尺寸**：2026-09-25 用户说过「滑动区变高」，
于是条高 46 → 54。而条子这一族几何**全由带高推出来**，且每一条式子的**比例是照相机定的**：

| 量 | 式子 | 带高 54（本轮之前） | 带高 47（现在） | 相机量到的 |
|---|---|---|---|---|
| 节距（字距） | 1.32 × 带高 | 71 | **62.0** | 62（190px）|
| 选中胶囊（静止） | 1.15 × 节距 × 0.86 × 带高 | 82×46 | **71×40** | 71×40（219×124px）|
| 圆钮 | = 带高 | 54 | **47** | 47（144px）|
| 离屏边 | 相机：102px | 8 | **33** | 33 |
| 离屏底 | 相机：带子下沿 33.5 上沿 80.5 | 26 | **33** | 33.5 / 80.5 |

也就是说：**带高换回相机那个数，四条式子同时落回相机量到的绝对值**。上一版「尺寸不匹配」
不是某一个常数写错了，是这一族数整体比相机大一圈。三处连带：

- `gapMax` 从「0.65 × 带高」改成 **「1.32 × 带高 − 格宽」**。两个式子在带高 54 时给同一个值
  （所以一直没露馅），带高回到 47 就分开了：0.65 × 47 会给出节距 66.6，而相机是 62。
  1.32 才是量到的那个比例，0.65 是**为 54 凑出来的系数**。
- 字号 15 → **13**（相机 glyph 40px = 13pt；带高 3.6 × 字高，两边逐字相同）。
  只换条高、不换字号，静止形态里字占的份量仍然比相机大一圈。
- 圆钮的直径**不再各写一个**：`MapSpineView.armSize = DSSwipeStrip.barHeight`
  （此前是 54/54 两个数靠注释维持相等）。`DSSwipeStrip.barHeight` 因此从实例属性改成
  `static let`，文件内十几处一律 `Self.barHeight`。

**「滑动区」一点没小**：整行（含条下那 33pt）仍是滑动区，触摸高度 47 + 33 = 80pt，
与条高 54 那一版（54 + 26 = 80）**逐点相同**；条子上沿仍是离屏底 80，`barTotal` 仍是 94 ——
所以页面窗口、Toast 高度、`MapCameraFollow` 那个「可见带中心 38%」全都不用动。

### 32.2 吸附：位置说了算，速度只买一步（第 1 条）

松手时此前直接拿 `predictedEndTranslation` 去换档位。它是系统按速度算出的「松手后手指
将到的地方」，在**一次普通拖动**里通常比手指多走 20–60pt（0.3–0.9 档，节距 62）——
用户把 A 对到透镜正中时手上还剩一点速度，那多出来的一截正好把他推过 0.5 档，于是落到邻居。
**而用户对的是眼睛看到的那一档，不是速度预测出来的位置。**

现在（`landingPV`，两条通道同一个函数）：投影比停手位置多出不到半档 → 完全按位置吸附
（速度只是噪声）；超过半档才算「甩」，而甩**最多多走一档**（`±1`）。

同一处还补了一个真错：`rowBase`（条**外**那条通道的起点）原先只在 `rowDragChanged`
里清，而那条手势被接管 / 被系统取消时**不会走 `onEnded`** —— 起点就留着上一次触摸的值，
下一次算出的 `c` 是「过时的起点 − 本次增量」，松手吸附到的是错的档（用户看到的同样是
「放手去相邻的入口」）。现在条子自己的手势一开始就把它清掉：起点与手指绑在同一条通道上。

### 32.3 子页也能从底条下穿过（第 3 条）

只有地图那一档能穿，因为只有它没有那一句 `.padding(.bottom, Self.barTotal)` ——
**给页面加 padding 等于把滚动视口截在条子上沿**，卡片永远到不了条子底下，条子背后
只剩壁纸（看起来就是一块不透明的板）。

现在：子页视口铺到屏底（`.ignoresSafeArea(edges: .bottom)`），底条那一段改由 `ArcStack`
做成**滚动内容的内衬**（新环境值 `stackBottomInset`，宿主给 `barTotal`）——
两件事同时成立：**卡片从条子下穿过**（与相机里取景框的关系同一种），而最后一张仍能
整张滚到条子上沿之上（够得着、读得完）。两条判据同属一个数，那是它必须是内衬而不是
padding 的全部理由。

### 32.4 验证

`scan/all.py` **34/34 全绿**（`MapSpineView.swift` 1199 行、`DSSwipeStrip.swift` 727、
`ArcStack.swift` 231、`CardFit.swift` 480）。`design-preview/camera-bar.html` 的那一格
换成 **v20**（带高 47 / 节距 62 / 圆钮 47 / 离屏边 33 —— 与上面三张相机裁图同源），
并新增一格「底条能不能穿过」的前后对照。

只有 CI 能验：`DSSwipeStrip.barHeight` 改成静态后那十几处 `Self.`、跨类型引用
（`MapSpineView.armSize = DSSwipeStrip.barHeight`）、`contentMargins(.bottom, …)` 的写法、
新环境值 `stackBottomInset`。
只有真机能验：翻到 A 松手是不是就停在 A（这一轮唯一的目标）、两枚圆钮的观感是否与相机
同量级、子页的卡片是否真的从底条下穿过且最后一张能整张露出来。

---

## §33 第二十五轮（2026-09-26）：选中胶囊的质感、行程地图居中、刷新倒计时

### 33.1 选中那一枚从「一个扁平色」变成三层

⚠️ **同一天被第三批推翻**：下面这三层自画的伪玻璃已删，选中那一枚回到**真玻璃**。
原因写在 §34——那一次缺的不是层次，是材质。

用户：「底部导航选中的玻璃和相机的玻璃质感差的太远了」。三代写法各自缺的那一块
（历史写在 `DSSwipeStrip.capsule` 上）：

| 写法 | 缺什么 |
|---|---|
| 扁平色（白 14%） | 画不出玻璃 —— 一块均匀的灰 |
| 真材质 `.dsGlass` | 必须住在 `GlassEffectContainer` 里，而那条路已经把内容吞过一次 |
| **现在：画出来的三层** | 底（自上而下变淡）、边（上亮下暗）、影子（把它从带子上抬起来）|

**为什么真材质在这里不值**：它坐在我们这条**自己画的**带子上，而带子后面是一块平的
半透明面 —— 真玻璃能多给的那一点折射在这里照不出东西；而它会把「降低透明度」那一档
重新拉回到底条上（上一轮用户点名不要的正是那个）。
三个令牌写在 `TokensPalette`：`barSelection` / `barSelectionRim`（两条由上到下的
渐变，亮暗方向相反 —— 因为底子 `barFill` 本身就是反的）/ `barSelectionShadow`。

### 33.2 行程页那张小地图：镜头是状态，中心是包围盒

用户：「行程页地图应该把行程居中」。两处都对不上：

- `Map(position: .constant(…))`：那个值在**第一帧**（`road` 还空着）就定下了，
  那时画的是两点直线；路线回来之后线换成了绕行的那一条，**镜头却不动**。
  现在镜头是 `@State`，`.task` 里先按两点取一次景、**路线回来再框一次**。
- 中心此前取「点串正中间那一个点」：采样点按距离均匀时它才约等于中点，
  而绕行（下高速绕一圈）会让它整个偏到一侧。现在取**包围盒的中心**（与采样无关），
  跨度取包围盒的**长边**（`2.4` 那个系数留着 —— 它此前就在）。

连带把地图的手势关了（`.allowsHitTesting(false)`）：镜头改成状态之后它会接手势，
而这张图在一叠卡里 —— 手指落在图上就不再滚那一叠。它本来就是个说明图（POI 全关、
没有任何控件）。

### 33.3 刷新倒计时（调试）—— 节律仍然只有一处

用户：「地图页加入刷新倒计时吧，我感觉没刷新一样（调试用）」。那句话说的是一件真事：
这条循环**没有任何可见的反馈** —— 停着的车报文几乎不变，数据不变界面就不变，
于是「在刷」与「没在刷」看起来一模一样。

`MapRefreshBadge`（`MapSpineReadouts.swift`）把三件事写在脸上：**还剩几秒**、
**此刻这一档的节律**、**退避走到第几拍**。三种写法各对应一个真实状态：
「—」（还没走过第一趟）、「…」（到点了、请求还在飞）、「Ns」（倒数）。

⚠️ 它读的全是循环自己的数（`interval` / `lastTickAt` / `zeroStreak`），
**不另存**「下次该几点刷」—— 那会是第二个节律。为了读 `zeroStreak`，它从 `private`
改成 `private(set)`（读得、写不得，读者就这一处）。秒表由 `TimelineView` 走：
只有这一格每秒重画，那张活地图不会被拖进来。

新引入的两个 SDK 名字（`TimelineView` / `TimelineSchedule.periodic(from:by:)`）
已对着 Apple 文档页逐个核实并登记进 `scan/scan.py` 的 `VERIFIED_SDK_ADDITIONS`
（登记处写着两页的 title/abstract 原话）。

### 33.4 验证

`scan/all.py` **34/34 全绿**（含 `lintcfg.py`：本轮没有文件越 1200 行 ——
徽标的**位置**因此写在 `MapSpineReadouts.swift` 里，`MapSpineView` 只多一行调用）。

只有 CI 能验：三个新令牌的类型（`LinearGradient` 当 `ShapeStyle` 传给 `fill` / `strokeBorder`）
与 `shadow(color:radius:y:)` 这个写法、`@State` 的 `MapCameraPosition`、
`TimelineView` 闭包里的 `@MainActor` 归属。
只有真机能验：那枚胶囊的质感是否到了相机的量级、行程图是否整条居中、
倒计时的秒数与实际取数是否对得上（上一条正是它存在的理由）。

---

## §34 第二十六轮（2026-09-26）：底条的分工与相机**逐块相同** —— 带子自己画，三块形状是真玻璃

用户：「底部导航区域，准确的是 3 个液态玻璃：左右的球和中间的选中；底下的带子尽量保持
一个液态玻璃试试，但应该不是液态玻璃，要不然又看不到文字了」。

**他自己两个直觉都对，而它们正好是这一块的答案**：

1. 「准确的是 3 个液态玻璃」——相机那三块（左下缩略图、右下翻转镜头、中间那枚选中胶囊）
   **都是系统玻璃**。我们上一轮只把**选中那一枚**做成了自画的三层伪玻璃（底渐变 / 边 /
   影子），那是「像玻璃」，不是玻璃；两枚圆钮更早还被从真玻璃改回过画面（`armDisc`）。
   这一轮三块全部回到 `dsGlass`：两枚圆钮压在**连续画面**（壁纸 / 地图）上 → `.overMedia`；
   选中那一枚坐在带子上 → `.regular`。选中的标签仍是强调色、画在它们**上面**（z 序不变）。
2. 「带子应该不是液态玻璃，要不然又看不到文字了」——**对**，而且是三条各自独立的理由：
   - **量出来的**：相机那条横带的像素是一片均匀填充、看不出底下的纹理，且「降低透明度」
     对它无效 —— 这只有「自己画的面」能解释（材质会被那个开关降）；
   - 它是选中那一枚**下面**那一层：它变成玻璃，就成了「一块表面里叠两块玻璃」
     （`DSGlass.swift` 规则 ②），而那条路在真机上把整条的内容吞过一次；
   - **字压在材质上时，对比度就由材质说了算** —— 这正是「又看不到文字了」，
     而这条带子上的字是全 App 唯一入口的名字。

### 34.1 代码上改了什么

| 位置 | 之前 | 现在 |
|---|---|---|
| `MapSpineView.armDisc` | `Circle().fill(barFill)` + 发丝线 | `Color.clear.dsGlass(in: Circle(), interactive: true)` |
| `DSSwipeStrip.capsule` | 自画三层（底渐变 / 边 / 影子） | `Color.clear.dsGlass(in: Capsule())` |

> 上面两个调用点写着 `variant:` —— 那是**当时**的写法：那个参数与 `DSGlassVariant`
> 已在同一天的第三批随「玻璃就默认选更透」整份删掉（§35.3）。
| `DSSwipeStrip.band` | 自画（`barFill` + 发丝线） | **不动** —— 它就是相机那条「不是玻璃」的带子 |
| `TokensPalette` | `barSelection` / `barSelectionRim` / `barSelectionShadow` | **三个都删**（一个读者都不剩；`barFill` 留着，带子还在用）|

`capsule` 上不另加投影：系统玻璃自带边缘与投影，再加一层就是两层影子。

### 34.2 一处**故意不照规则 ② 做**的取舍（写在调用点）

`DSGlass.swift` 规则 ② 说「一片区域里多块玻璃要由 `dsGlassLayer` 划定」。这一行**不包**：
那个容器把同层的字与选中胶囊一起吞掉过一次（真机上量到「带子里一个字都没有」）。
现在三块玻璃**从不相变、也不跨块变形**（「按住展开」那个状态 2026-09-26 就已删），
容器能多给的只剩互相折射 —— 而它的代价是这一行里唯一的文字。
真机上若看着像三张贴纸，下一手就是包回来（那时至少知道是什么在变看不见）。

### 34.3 验证与两条只有真机能答的

`scan/all.py` **34/34 全绿**（`MapSpineView.swift` 1199 行 —— 贴着门禁，所以这一段
容器的取舍写在底条那一行的注释里，不再另开文件）。`glass.py` 的规则 ③（玻璃底下不许垫
不透明的面）在两处都重新核过：两条链的接收者都是 `Color.clear`（没有 `.fill` 垫底）。

只有 CI 能验：`Color.clear` 当接收者的写法、`.dsGlass(in:)` 两处的形状约束（`Circle` /
`Capsule` 都是 `InsettableShape`）、`interactive: true` 落在 `Button` 的 label 里。
只有真机能验：**亮色模式下选中那一枚的对比度**（带子亮 = 白 72%，玻璃在上面更亮，
强调色的字还读不读得出 —— 这是这一轮唯一可能翻车的地方）、
以及三块玻璃挨着 9pt 看起来是不是同一层材质。

### 34.4 三件跟着改、但容易漏掉的连带（都不在本轮需求里）

1. **带子不再跟「降低透明度」走 —— 这是要的；但它也不再跟「玻璃通透度」那个设置走。**
   后者是「我的 → 显示」里那三档（`DisplaySettings.GlassLevel`，它只有一个读者：
   `dsGlassMaterial`）。带子从材质上摘下来之后，选「最通透 / 最实」时它**逐像素不变** ——
   与相机那条横带一致，但它与这个全局开关的口号（「全局调整液态玻璃的通透度」）之间
   留了一道缝：带子在这一屏占的面积最大，观感上它会显得「不听话」。
   两条路都不需要新概念：让它读 `fill`（它与三块形状同一个调节钮，代价是 `barFill`
   要从一个静态色变成算出来的色），或者把它写进那个开关的说明里（带子不是玻璃）。
   **暂不动** —— 这一条是观感决定，该由用户点头。
2. **模拟页 `design-preview/camera-bar.html` 从三帧变四帧**：「我们」那一组现在有
   静止 / 拖动中 / 系统设成最不通透 / **对照：带子也做成玻璃**。第四帧就是上面那条
   「试试」的可视答案 —— 带子变亮变糊、边缘变亮，而它在真机上会同时丢掉两样东西
   （字的对比度由材质说了算；以及带子开始跟「降低透明度」走）。它**不是**一件待办，
   是一场对照：真要在 App 里试，改的是 `band` 一个函数。
3. **删掉 `TokensSize.barHeight`（56）**：条高还在 54 那一族时留下的数，而真正的出处是
   `DSSwipeStrip.barHeight`（47）。它**一个读者都没有**（全仓 grep 过），而两个名字
   指同一件东西、其中一个还是旧值 —— 下一个人拿到的就是错的那个（同类：
   `TokensPalette.barSelection` 那三个随伪玻璃一起删）。四条陈旧注释同时改了
   （`barGap` 还是 26 / 离底 60pt / 「含离底那 26pt」两处）。

---

## §35 第二十七轮（2026-09-26）：图源下拉、文字发光整份删除、玻璃只剩一档、
带子再透一级、事件懒加载、地图车头朝上 + 行驶轨迹 + 跟手抽屉

用户一次给了六条。落下来是六件事，其中三件是**删东西**（第 2、3 条把一个设置整组、
一份设置类型、一层挂了十几处的壳一起拿掉），一件是换掉一个人称坏掉的控制。

### 35.1 图源下拉：打不开的那一下（第 1 条）

用户原话：「选了必应后可下拉继续选其他，但是选了 windows 聚焦 就无法再下拉选其他了」。

**本机无法复现**（没有编译器、也没有那台设备），所以这里没有「修好了某一条已知机制」的证书，
而是**换掉那个人称坏掉的控制**：`Picker(.menu)` → 自己写的 `Menu` + 每档一个 `Button`
（与这一页另外两处菜单同形：`Label(title, systemImage: 勾/圈)` —— 地图的图层胶囊与底条右臂
用的就是这一种，两个从没被报过打不开）。再加一条：点**当前那一档**不再是「什么都不发生」，
它变成「再取一次」（`wallpaper.reload()`）—— 即使某一档曾经卡住，它也不再是一个死路口。

代价写在这里：`Menu` 的外观由系统定，与 `Picker` 那种「值右对齐 + 上下箭头」的 iOS 设置行
**不完全一样**（菜单里多了勾与圆）。这一条是换取「一定能打开」的代价。

### 35.2 文字发光：整份删除（第 2 条）

删掉的东西：`Design/InkGlow.swift` **整个文件**（两个实现：挂在 App 根上给每一行字的
`DSTextGlow` + 图形一侧的 `dsInkGlow()`）、`DisplaySettings.glow`、那一格 0…100% 的滑杆、
本机键 `carkeeper_display_glow`、以及十几处调用点上的壳。`scan/scan.py` 的白名单与
`scan/orphans.py` 的例外表随之清空（没有壳可放行）。

为什么是「整份」而不是「调小一点」：那一层壳不是一层影，它把**每一行字**都换成
「一层反色外发光」 —— 压在玻璃上时字会自己发光，而卡片会看起来发灰（它盖住的正是
底下的照片）。删掉之后顶着可读性的只剩两件事：玻璃上的 `TokensInk` 三档自适应文字色
与 `weight: .bold`。

### 35.3 玻璃只剩一档，界面实度定在 50%（第 3 条）

· **`.clear` 成为唯一材质**：`DSGlassVariant` 与 `dsGlass(variant:)` 一起删（一个永远被忽略的
  参数正是这一仓反复删的那类东西）；`GlassCard.frosted` 与 `EnvironmentValues.photoBackdrop`
  也一起删 —— 「底下是不是照片」这个事实不再影响任何一块玻璃。
· **界面实度**：`TokensPalette.faceFill` 固定 **0.5** → `fillSubtle` = `surface` × 0.11、
  `panel` = `surface` × 0.17（比上一版更透）。
· **入口删除**：「我的 → 显示」那一组三个控件（发光程度 / 玻璃三档 / 实度）连同
  `DisplaySettings.swift` 整份删除；本机键从 30 个减到 **27** 个（第 6 节那张表已同步）。

诚实代价：`.clear` 不磨砂（HIG 把 clear 留给「压在连续画面上」的控件），而卡片是这一档最大的
用户 → 卡里正文的对比度跟着壁纸走。回退是 `dsGlassMaterial` 里那一个词（`.clear` → `.regular`），
不是再开一个参数。

### 35.4 带子再透一级（第 4 条）

`TokensPalette.barFill` 的 alpha **0.72 → 0.55**（亮 = 白 55%、暗 ≈ 黑 55%）。
不是量出来的数：相机那条带子叠在地图上，浓度读不出来 —— 一档 = 16 个百分点，
与相机那条半透明黑的量级一致。要盯的只有一件事：带子上那三档字的对比度。

### 35.5 事件懒加载（第 5 条）

消息那一节从「点一下『再看早 3 天』」改成**滑到底自己续**：`MessagesSection.shownDays`
从 `@State` 变 `@Binding`，续的动作搬到宿主 `TripsEventsView.loadMoreEventDays`
（滚动到没到底只有那一叠知道：`ArcStack.onReachBottom`）。按钮撤了 —— 往下滑本身就是
「我还要看」的证据，而按钮把同一个意图多问了一遍。

一次三天的步长不变，且它是**必须**的：这一叠是普通 `VStack`（懒容器量不到叠卡的几何，
见 `ArcStack`），所以「看得见的那几天是整段建出来的」—— 227 行那一次内存事故
（0.97s 消息到手 → 4.01s 1720 MB → 5.3s 被系统收走）就是这么来的。封顶交给数据：
`filteredGrouped` 有多少天就画多少天（服务端 7 天窗口）。

### 35.6 地图：车头朝上 + 默认 2D + 行驶轨迹（第 6 条上半）

· **俯仰 65 → 0**：`cameraPitch = 0` 就是 2D（Apple：*a value of 0 results in a camera that
  points straight down at the map*），`MapStyle` 的 elevation 跟着 `.realistic` → `.flat` ——
  两件事是同一个决定的两半（立体建筑在 2D 下看不到多少，却最贵）。
· **朝向 = 总是车头**（`store.carHeadingDeg`）：推翻前一版「停着回正北」。停着也有车头，
  而在停下那一刻突然翻成北向上，才是真的不可解释。车端还没报过航向时它是 0 = 北向上 —— 不猜。
· **`DriveTrace`（新服务，`Services/DriveTrace.swift`）**：点火清空成新的一段、熄火封口
  （点**不清**，线留着）、8 米一个点（GPS 抖动之下不动）、2000 点上限（按 8 米算约 16 km，
  一趟够用）。落点只有**一处**：`AppStore.saveCache` 里那条定位通知的同一个点上。
· **画法**：`MapSpineAnnotations.driveTraceLine` 用与行程线同一套（宽而淡的亮晕 + 主线）——
  同一件东西（一条路径）在地图上只该有一种画法。
· **模拟开关**在图层胶囊菜单里（「模拟行驶轨迹」）：沿车当前位置向北 33 米/步、东西按 `sin` 摆，
  1.5 秒一步 —— 真机上想看一眼轨迹长什么样，只有这一条路（否则必须真开一段）。

### 35.7 抽屉：跟手抽出 + 「现在」搬进抽屉（第 6 条下半）

· **跟手**：`drawerReveal`（0…1）= 手指位移 ÷ 正文自然高度，卡片高度 = `drawerBodyHeight × reveal`
  —— 两态之间那一段也是真的（`MapNowCard` 量正文高度的那一个几何读者就为此而留）。
· **松手**：先看位置（过一半以位置为准），没过一半才看那一甩的方向
  （`predictedEndTranslation`）—— 与模式条的吸附、与系统的 sheet 是同一条规矩。
· **「现在」那一枚图层胶囊搬进抽屉的正文**（`drawerContent` 的最上面）：收起时这张卡只剩
  一横 + 三个数（用户：「外面只显示 3 个」），拉开时那些事才在。

### 35.8 验证

新门禁 `scan/delguard.py`（编号 **1** —— CI 那份清单的第一条）：比对 HEAD 与本树，
一个名字「旧版有声明、新版没了、
还有人在用」即红 —— 那是编译错误，不用等 macOS runner。**它这一轮真抓到一次**：
`TokensPalette.canvas` 在改名途中被写成 `canvasProbe`，而五个读者还写着旧名。
它这一轮还补了一条**假阳性**判据（⑧）：`TokensHalo` 整个文件被删之后，它把
`CarModelView` 里 `body.scale`（RealityKit 实体的系统成员）当成了被删的那个 ——
两条同时满足才不报：「这个名字在 SDK 符号表里」且「每一次出现都是 `小写值.name`」。

`scan/all.py` **34/34 全绿**；`MapSpineView.swift` **1199** 行（阈值 1200）。

只有 CI 能验：`Menu` 里 `Button` + `Label(…, systemImage:)` 的写法、`@Binding` 的两处传递
（`MessagesSection(shownDays: $eventDays)` / `ArcStack(onReachBottom:)`）、`MapPolyline` 的
坐标数组、`pitch: 0` 与 `.mapStyle(…, elevation: .flat)` 的组合、`TimelineView(.periodic(…))`
闭包里的 actor 归属。

只有真机能验：图源菜单四档都能拉开（第 1 条那件事本机复现不了）；轨迹那条线在真开的路上
是什么形状（模拟只给形状，不给“它真的在记”）；2D 下车钉落在带子里的位置
（`MapCameraFollow.spanFactor` 那根回退线）；抽屉跟手的手感；以及 `.clear` 下卡片正文的对比度。

---

## §36 第二十八轮（2026-09-26）：图源不再走弹窗、抽屉的频闪找到根因、
玻璃上的字按官方的 dimming layer 解决

用户三条：图源第三次报同一个毛病（这次给了完整复现）、抽屉“别扭 + 闪屏频闪”
并直接问「系统地图里原生用的啥」、以及「玻璃通透的情况下文字怎么能看得清，
苹果官方是怎么解决的」。第三条是一个**要引文的问题**，所以下面全带原文出处。

### 36.1 图源：两代弹窗都被同一个毛病否掉，于是不弹了（第 1 条）

用户这次的复现是完整的，两条线索各指向一个方向：

> 「图源不换页面的情况下可以一直换，但是换了其他页面回来，如果上次是 windows 聚焦，
>  那就再也点不动，重开软件都不行，只能点不铺，再重新选」

· 「重开软件都不行」→ 状态是**持久的**（`source` 落盘在 `carkeeper_wallpaper_source`），
  所以不是某一次手势丢了，而是「一进来就是这个样子」；
· 「只能点不铺」→ 同一张卡里别的按钮还能按，所以不是整片被挡住。

而**两代写法都被同一个毛病否掉过**：先是系统的 `Picker(.menu)`，后是自己写的 `Menu`
（§35.1）。两次换个的都是**弹窗**，两次坏的都是**弹窗打不开**。本机没有编译器、
也没有那台设备，这个机制我复现不了 —— 所以这一版把依赖换掉：
三个选项**直接摆在行里**（`DSSegmented`），没有第四种东西要弹出来，
也就没有「弹不出来」这回事。

· 行的排版：上「背景图 + 当前全名」，中三格（相册 / 必应 / 聚焦），下是说明与署名。
  段名短是因为一行装不下三个全名（`WallpaperSource.segmentTitle`），全名留在上面那一行。
· 点**当前那一档**仍然是「再取一次」（`MineView.pickSource`）：分段控件会把同一个值
  再写一次，所以「点当前那一档」自然走到 `reload()` —— 那一行没有死路口。

诚实的账：如果真因不是「弹窗」而是**那一格位置的命中**，那么换成行里的控件之后
它同样会坏（只是不再是“弹窗打不开”）。所以这一条要真机上再确认一次 ——
它是这一轮唯一**没被证伪也不能被证明**的一件。

### 36.2 抽屉：原生是什么、我们为什么不能用它、频闪的真因（第 2 条）

**原生是什么**（用户问的那一句）：Apple 地图 / 查找 / 股市 里那种「常挂在下面、
能拉高拉低」的卡是 `UISheetPresentationController`；SwiftUI 里同一台机器叫
`.sheet` + `.presentationDetents([...], selection:)`，常驻靠 `isPresented: .constant(true)`
+ `interactiveDismissDisabled()`，底下的地图仍可用靠
`presentationBackgroundInteraction(.enabled(upThrough:))`（Apple 文档：
*presentationBackgroundInteraction(_:)* —— “On many platforms, SwiftUI automatically
disables the view behind a sheet”）。跟手、动量、吸附、橡皮筋、VoiceOver 的
收起/展开**全是系统做的**。

**我们为什么不用它**：这不是取舍，是几何装不下 —— 系统 sheet 永远是**窗口底部**的
一张面，而这一屏底部是我们自己的入口条（全站唯一的导航）。sheet 会直接盖住它，
与 `MapSpineReadouts` 头注里第二代写法（那个 sheet）被删是同一个理由，
只是那一次盖住的是模式条。所以「借系统那台机器」在这里做不到，
能借的是它**做对的那几件事**（连续跟手 + 单一落点规矩），而它们在四代之前就有了。

**频闪的真因**（这一版真正修的）：连续量（`drawerReveal` / `drawerBodyHeight`）此前是
`MapSpineView` 的 `@State`，而拖动是**每帧**写它 —— 于是 `MapSpineView.body`
每帧重建一次，而那个 body 里有六页同屏、一张活地图、一条轨迹、底条。
一帧一屏地重建就是用户看到的那阵闪。两处改：

① **状态挪进它自己那个视图**（新 `MapNowDrawer`，`MapNowCard.swift`）：一帧里重画的只剩
   这张卡。骨架那一屏只剩那个**离散**的 `drawerOpen`（持久化键）。
   卡头（`MapSpineReadouts`）与外壳之间用一个 `DrawerHandle` 交接：连续量、当拍高度、
   当前档、点一下、落到某个端点 —— 手势的注释与读数因此仍住在同一份文件里。
② **`highPriorityGesture`**（原来是 `.gesture`）：拉手坐在一个**可滚动**的叠里，
   两者同时认领同一根竖手指时会互相抢 —— 手指走一段、内容往下滚一段，
   一抢一放就是那阵闪的另一半。优先级给了拉手（这一格竖着走就是拉抽屉）。

顺手加的一条：`onChanged` 里**只在值真变了才写**（手势系统会把同一个回调重复递几次），
以及拖动落点仍照老规矩（先看位置，没过一半才看那一甩）。

### 36.3 玻璃上的字：官方有明文答案 —— dimming layer（第 3 条）

两处原文，同一句话：

· **HIG「Materials」**（元数据里 `alert-text: “Updated guidance for Liquid Glass.”`）：
  *“For optimal contrast and legibility, determine whether to add a **dimming layer**
  behind components with clear Liquid Glass: If the underlying content is bright,
  consider adding a **dark dimming layer of 35% opacity** … If the underlying content
  is sufficiently dark … you don’t need to apply a dimming layer.”*
· **`Glass.clear` 的文档**：*“When using clear glass, ensure content remains legible by
  adding a dimming layer or other treatment beneath the glass. For example, you could
  add a transparent black color beneath your glass …”*，样例代码是
  `Label(“Flag”, …).padding().glassEffect(.clear).background(.black.opacity(0.3))`。

所以「通透」与「字读得出来」**不是二选一**：`.clear` 自己不带任何保证，
保证来自它**底下那一层** —— 而那一层是同一个 `.clear` 的**配套件**，不是它的替代品。

落法：新令牌 `TokensPalette.glassDim`（亮色下白 35% / 暗色下黑 35%），
由 `dsGlass` 在玻璃**之下**垫（`.background` 挂在 `.glassEffect` 之后 —— 与官方样例
逐字同一个顺序），调用点只传一个倍率 `dim:`。三处决定：

· **颜色取「与字反相」**：官方那个例子的字是白的（媒体控件），所以垫黑；
  我们这一仓的字是自适应的（亮色下近黑、暗色下纯白）—— 垫黑会在亮色模式下把黑字埋掉。
· **35% 用的是他给的数**（亮色下白 35% 比黑 35% 更“奶”一点，那是「更透」与
  「字读得出来」之间那一步的价钱）；`dim` 参数默认 1，**只有底条那一枚**传 0 ——
  它是全 App 唯一一块坐在我们自己画的面上（`barFill`）的玻璃，垫了就是同一件事做两遍。
· 「降低透明度」那一档一字未改：它本来就走不透明 `surface` 那条支路（没有材质，也就不用垫）。

**更重的一条（官方另一句话，本轮没动）**：同一页 HIG 写着
*“Don’t use Liquid Glass in the content layer.”* —— Liquid Glass 是**功能层**的语言
（导航与控件），而内容层的表面该用 standard materials；而
*“Use the regular variant when background content might create legibility issues, or when
components have a significant amount of text, such as alerts, sidebars, or popovers”*。
我们那几百处读数就在**内容层**，且属于「文字很多」那一类 —— 按官方的分法，
它们本来该是 `.regular`（磨砂 + 调亮度）或标准材质，而不是 `.clear` + 对比底。
本轮按用户上一轮的吩咐把材质定死在 `.clear`，所以只落了 dimming layer；
要改的只是一个词（`dsGlassMaterial` 里的 `.clear` → `.regular`），代价与收益都写在
`DSGlass.swift` 那段注释里。

### 36.4 验证

`scan/all.py` **34/34 全绿**。`scan/glass.py` 的规则③（玻璃底下不许垫不透明的面）
一字未改，但文件头补了一句：新的那层对比底住在**唯一入口里面**（调用点只传倍率），
所以「调用点垫的面」仍然是红的。

只有 CI 能验：`MapNowDrawer` 那个 `init`（`@ViewBuilder` + `@escaping` + 泛型两个）、
`DrawerHandle` 的 `Binding<CGFloat>` 写法、`DSSegmented` 接一个自定义 `Binding`
（读 `wallpaper.source`、写 `pickSource`）、`.background { if … { shape.fill(…) } }`
这个 ViewBuilder 位置。
只有真机能验：图源三格是不是真的永远点得动（第 1 条唯一没被证实的一件）、
抽屉跟手还闪不闪（本轮的主修）、空 35% / 黑 35% 加起来在**亮色模式 + 亮壁纸**下
卡里的字是不是真的更好读（这是本轮唯一可能「改完更差」的地方 —— 觉得发奶就把
`glassDim` 那一个数往下调）。
