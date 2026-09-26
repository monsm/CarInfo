# CarKeeper 重构状态（截至 2026-09-22）

一句话：**首页就是地图；一个令牌层（只有原生一套取值）；界面上的每个数字要么来自车端真实字段，要么不出现。**

> ⚠️ **读这份文件的顺序**：它是一份**逐轮追加**的记录，全文 3600+ 行。
> 「四套艺术主题 / 20 套艺术方向 / `ArtTheme` / `ThemeGalleryView` / `MapStyleSpec` /
> `TokensSerif`」这些词在下面的历史小节里到处都是 —— **它们在 2026-09-25 已全部删除**
>（用户：「主题用原生，其他 19 套全删了」）。最新的状态永远在**文末那几节**；
> 前面的小节是当时的记录，只有明确标了「已被取代 / 已作废」的地方才需要回看。
>
> 2026-09-25 第九轮又删掉了一批名字（同样只在历史小节里出现）：
> `CarTopView`（线描俯视图 → 现在是 RealityKit 的 `CarModelView`）、`StackLabView`、
> `NightModeManager` / `FocusModeManager` / `GestureEnhancements` / `ShakeDetector` /
> `PowerSavingToggle` / `VoiceBroadcastManager` / `FamilyAndKeySharing`（家庭管理 / 临时钥匙）。

---

## 1. 现在的四层结构

| 层 | 是什么 | 关键文件 |
|---|---|---|
| **设计层** | 令牌（颜色/字/间距/圆角/动效/触觉）+ DS 组件 —— **只有原生一套取值**（艺术主题 2026-09-25 整份删除，见文末第六轮） | `Design/Tokens.swift`、`Design/DS.swift`、`Design/Theme.swift` |
| **数据适配层** | 把 `AppStore` 的真实缓存翻译成"地图上画得出来的东西"；**没有数据就是 nil** | `Features/Map/MapSpineData.swift`、`Services/ChargeLedger.swift`、`Services/HistoryStore.swift` |
| **页面层** | 地图主屏 + 深潜页（43 个文件 → 现在 12 个面） | `Features/Map/*`、`Features/Battery/*`、`Features/Control/*`、`Features/Mine/*` |
| **系统层** | Siri / 无障碍 ｜ ⚠️ Widget / Watch / App Clip / App Group 与它们的目录**均已删除**（免费账号拿不到这些能力，见 §0 的硬约束） | `Features/SiriShortcuts.swift`；~~`Widgets/` / `WatchApp/` / `AppClip/` / `Shared/`~~ |

**换肤是换值，不是换名字**（⚠️ **2026-09-25 已作废**）：`TokensPalette` / `TokensTypo` 的取值
曾全部转发自当前主题（`ArtThemeStore.spec`），于是约 800 处调用点跟随切换而零改动。
用户定下**只用原生**之后，这层转发被拆掉、取值**逐值搬回** `Tokens.swift` —— 因为
「只有一种取值的开关就是一层假的选择」。搬移时值一个没改，改的只是住处（详见文末第六轮）。
艺术方向的入口（我的 → 开发者工具 → 艺术主题，`Features/ThemeGalleryView.swift`）**已删除**。

## 2. 首页（地图主屏）

- 地图是 MapKit 的真瓦片、真坐标、真手势；艺术方向 → 真实 MapKit 配置见 `MAPKIT-FEASIBILITY.md`。
- **四个图层 = 四个真实问题**：现在 / 行程 / 停车 / 充电。
- **车钉外面那圈弧就是电量**；顶部缺口是 location 接口读来的真实车头朝向。
- 底部「为什么」面板逐条写清每个数字的来路；**推不出来就不显示**。
- 「全部功能」索引页收着所有深潜页（去掉 Tab 栏的代价补在这里）。
- 充电层多一个**功率曲线回放**：曲线就是车端 1 分钟一个的真实采样（与账本同源），样本不足两个点时如实说明、不画。
- 「现在」层有**续航圈**（`MapCircle`，半径 = 车报的 RemainedPowerMile）；「停车」层有**常停热区**（停车史 ±80m 聚类，≥2 次成圈，半径是几何的产物）。
- 未接图层的功能：**任何一层的地图都没有标注聚合**（现在是最近 12 个充电站的权宜之计）。

## 3. 融合表（旧页面去哪儿了）

| 旧页面 | 归宿 |
|---|---|
| `VehicleView`（452 行，车辆档案） | 保留为深潜页（VIN/保险/维保/照片）—— 它本来就不是"此刻" |
| `DashboardView`（153） | **删除**：三个子分数是拿总分做算术编出来的（`score / 3`、`+10`、`+20`） |
| `VehicleTipsView`（326） | 保留为深潜页（用车提醒） |
| `EmergencyPanel`（240） | 保留为深潜页（SOS 是真功能） |
| `VoiceBroadcastView`（124） | **删除**：零引用 |
| `VehicleStatusView`（302，app 内） | **删除**：零引用（小组件里有自己的同名类型，属另一个 target） |
| `EnergyRealtimeView`（237） | **删除**：电池容量 15 kWh 是写死的假值，四个视图零引用 |
| `EnergyCostCalculator`（117） | **删除**，能力被 `ChargeLedger` 用真数据重做 |
| `SmartChargeScheduler`（122） | **删除**：峰谷电价是写死的 5 段假设表，却以"建议"口吻输出 |
| `CarbonSavingsCard`（58） | **删除**：零引用 |
| `SmartNotifications`（168） | **删除**：三个类型零引用（其中一个是项目里第三份 `ChargingStation`） |
| `ChargingStationFinder` / `ChargingStationMapView`（Theme.swift 内 139 行） | **删除**：搜的是写死的北京坐标，把非充电站标成"慢充"，地址是原始经纬度 |
| `DriveBehaviorScore` + `calculateDriveBehaviorScore` | **删除**：读 `AggressiveAccel`/`HarshBrake` 两个全项目只此一处的键名 → 永远 0 次 + 100 分 |
| `EasterEggs.swift`（196，7 个类型） | **删除**：所有类型零外部引用 |
| `HomeIntegration.swift`（151，6 个类型） | **删除**：HomeKit UI 没有任何入口 |
| `DeveloperTools.swift`（148，7 个类型） | **删除**：与 `DevView` 重复，且零引用 |
| `PlatformFeatures.swift`（171，7 个类型） | **删除**：锁屏/手表/Mac 三个壳子零引用；iPad 分栏入口改挂在地图主屏工具栏（常规宽度才出现） |
| `SOCDetailSheet` / `CarSwitchGesture` / `InspectorCard` 等 12 个零引用组件 | **删除**（`DSStatTile`、`FluidTempHero`、`EnhancedToastView`、`CarSel`、`MapKitConfigurator`、`InspectionCard`、`InsuranceCard`、`ServiceReminderRow`、`FocusModeHomeView`、`FocusModeSettingsView`） |
| `AppDataModel` 里 8 个类型（4 个 Repository + 4 个 Model） | **删除**：整套 SwiftData 仓储从未被调用（`TripRecord` 保留，它是活的） |
| `L10n` + `I18n`（两套本地化，158 行） | **删除**：无人调用，且 `en.lproj`/`zh-hans.lproj` 一个 `.strings` 都没有 |

## 4. 数据诚实规则（这一版真正的地基）

1. **`nil` 不填空**：没有读数就是 `nil`/空数组，组件整块不出现（胎压行、充电账本、驾驶评分都是这样）。
2. **"不知道"和"中等水平"不能长得一样**：`AppStore.drivingScore` 因此从 `Int` 改成 `Int?`（原来无行程时返回 75）。
3. **报警来自车端的报警位**，不是我们按阈值猜的（胎压的 `LfPressureWarning`）。
4. **度数是真值，电价是用户的假设**：`ChargeLedger` 把车端 1 分钟一个的充电功率采样积分成 kWh（梯形法），电价由用户设定并在界面上写明"按你设的 X 元/度"。
5. **只给能测量的东西打分**：评分只用行程里的电耗与各段电耗的一致程度；急加速/急刹车/舒适度**量不出来就不做**（页面上写明了原因）。
6. **行程线是起终点连线，不是轨迹**：`TripRecord` 没有轨迹点，界面上照实写。
7. **异常没有"发生地点"**：只能挂在车当前坐标，文案写"最后一次上报时车在这儿"。

## 5. 验证方式（以及它的边界）

仓库里有 8 个静态检查器，`scan/` 下：`lexguard`（字符串边界/中文出现在代码位置）、`scan.py`（未声明的类型/成员、结构性问题）、`logic.py`、`shadowguard`（含 `--strict`）、`scenes`、`targets`、`unreachable`、`futureproof`，外加 `check_style.js`（行长/风格）。CI 已改成**先在 Linux 上跑这些检查器**，把 3 分钟的 macOS 来回变成十几秒。

**边界**：这些机器都在 Windows/Linux 上，**没有 Swift 编译器**。本轮所有改动都是静态验证过的（符号、API 名字逐个对 Apple 文档 JSON 核实、括号净余额与 HEAD 对照），**但没有一次真正的 `xcodebuild`**。历史上的两次 CI 编译错误（中文串里的 ASCII 双引号、删除 `GlassCard` 后 LoginView 仍引用）都是这么暴露出来的 —— 所以 push 之后请看一眼 Actions。

## 6. 已知缺口（不是忘了，是没做）

- 地图**标注聚合已做**：充电站不再只取最近 12 个，取回全部（上限 60）后按 400m 地面距离聚成组，孤立站是钉子、挨在一起的是带真实站数的圈，点圈放大到那一组。地图上另有系统 `MapScaleView` 比例尺。
- **充电回放已做**（功率采样曲线，数据与账本同源）；**行程回放做不了** —— `TripRecord` 只有起终点、没有逐点轨迹，这是数据现状，界面里已照实写明。
- 各页仍有约 30 处**有意保留**的系统色/写死色：Widget（语义色）、App Clip 与 Watch（独立 target，没有主题）、模态遮罩、阴影、图标本身。三个主 tab 里的 `.primary/.secondary/.tertiary` 形状色已全部改读令牌（28 处）。
- **天气已接**（Open-Meteo，无密钥）：云量 / 降水 / 天气码是实况，辐照度 = 晴空模型 × 云量衰减 `(1 − 0.75 × 云量^3.4)`。取不到实况时（离线 / 失败 / 还没取到）退回晴空模型，并在「光」表那一行写明「没有天气数据」。
  - 为什么不是苹果内置的 WeatherKit：它要 `com.apple.developer.weatherkit` entitlement，而本项目是**未签名 / 侧载**构建（`project.yml` 里因此关掉了 CloudKit —— 无 entitlement 时构造 `CKContainer` 会抛 ObjC 异常直接杀进程），WeatherKit 受同一约束。
  - 隐私：只发经纬度且**保留两位小数**（约 1.1 km 网格），不带车辆标识 / 账号 / 设备号，快照只在内存里、不落盘；隐私面板里新增了一节「离开本机的数据」（三个真实域名）。
- **纯函数测试只在 CI 上跑**：新增了 `CarKeeperTests` target（光的太阳位置、充电站聚合），但这台开发机没有 Swift 工具链 —— 测试由 CI 的 `unit-tests` job 执行，且设了 `continue-on-error`（模拟器镜像漂移的失败与代码无关）。
- **AppIcon 的 3 个「未指派子项」警告仍在**：12 个图标文件都被 `Contents.json` 引用了，真正的病因需要在真 Xcode 里看一眼（很可能是现代「单尺寸」图标的写法与旧式 iPad 槽位混用）。它是警告，不影响构建。
- **`LoginView` 版面已重排**（2026-09-22，见第 9 节）：表单改成 inset-grouped 分组、标题走衬线、去掉了那层把光挡在门外的不透明 `DSCanvas`。
- **令牌存在 UserDefaults，不在 Keychain**：`TokenStore` 用 `UserDefaults.standard` 存 access token（PIN 倒是存在 Keychain）。这是**待改的安全债**，本轮只把它写进登录页脚与隐私面板，没有动存储实现 —— 在拿不到编译器的环境下改鉴权存储，风险大于收益。
- 预览仍是 `PreviewProvider`（8 个文件，未迁移到 `#Preview` 宏）—— 只影响开发体验。
- 预览仍是 `PreviewProvider`（未迁移到 `#Preview` 宏）。
- **旧首页（列表版）已删除**（`Features/Home/HomeView.swift`，1327 行；它内部还挂着一个早已断链的 `MapView`）。所谓「新旧对照」到那一批就结束了 —— 想回退请用 Git，不在 App 里留一个死页面当纪念品。
- 切换主题会重建整棵子树，其间 `@State` 会重置（导航状态在 `NavState` 里，不受影响）。

## 7. 样品 → 真机的落差对账

设计样品（`design-preview/light.html`、`map.html`）里让人一眼亮的那些东西，逐项对到真机上了哪些：

| 样品里的东西 | 真机 | 说明 |
|---|---|---|
| 光由**真实太阳位置**算出（高度角/方位角） | ✅ 已落地 | `Design/SkyLight.swift`：NOAA 简化算法，纯数学不联网，可复算 |
| 光名（白昼/低角度日光/日出日落/暮光/蓝调/深夜） | ✅ 已落地 | 药丸里显示，点开是完整的「光」表 |
| 光池有方向、暗角、颗粒 | ⛔ **已删除（2026-09-25）** | 曾在 `Features/Map/MapSkyOverlay.swift`：它先被拆开（「光」表搬进 `Features/Map/MapSkySheet.swift`），五个**装饰**图层最后随艺术主题一起删 —— 「按主题档位开关」在方向只剩原生后只剩一个取值。算光的 `SkyLight` 留着（车钉的 `lamp` 在读它） |
| 车灯亮度 = 1 − 辐照度/220 | ✅ 已落地 | 车钉脚下的暖光；正午不亮，黄昏才亮 |
| 大字地名（衬线 + 疏排） | ✅ 已落地 | `TokensSerif`（Songti SC，取不到就退回系统衬线）+ `TokensTracking` |
| 车钉是「一件做出来的东西」 | ✅ 已落地 | 刻度盘 + 电量弧 + 接地阴影 + 车头朝向缺口 |
| 底部面板：抓手 + 衬线大标题 + 键值行 + 四宫格动作 | ✅ 已落地 | 面板顶部是衬线车名 + 描边小车；动作块 58pt、主操作只有一个 |
| 图上文字注记（「14:20 后备箱未关」） | ✅ 已落地 | 异常钉自带真文案，带文字阴影 |
| 「为什么现在是这个样子」表 | ✅ 已落地 | 「光」表：6 行可复算的事实 + 每条规则写在值旁边 |
| 真实云量 / 天气码 | ✅ 已落地 | Open-Meteo 实况（无密钥）；辐照度 = 晴空模型 × 云量衰减 `(1 − 0.75 × 云量^3.4)` |
| 实测辐照度（辐射计读数） | ❌ 没有 | 免费源里没有辐射计值，所以那一栏写的是「模型 × 实况云量」，不是实测 |
| 手绘地图（路网 casing / 水面 / 街区 / 纸墨） | ❌ 做不到 | MapKit 没有任何公开 API 能改瓦片颜色（见 `MAPKIT-FEASIBILITY.md`）。叠在上面的光层是受控的，瓦片不是 |
| 充电站旁的「¥0.68 谷电」价签 | ❌ 不做 | 那是**用户自己设的电价**，不是该站的实际价。标在搜出来的站旁边就是造假 |

一句话：**能由物理或真实字段算出来的，全部落地了；需要换掉整个地图渲染引擎的，如实标注做不到。**

## 8. 全量落地：让光与排版铺满每一屏

样品只在两屏上成立了很久。原因不是「没做」，而是一个很具体的结构问题：

> 28 屏里只有 2 屏有画布；而且 **16 屏各自在根上铺了一层不透明的 `.background(TokensPalette.background)`** ——
> 它把根部的光整个盖死。这就是「换了主题却看不出变化」的真正原因。

这一批拆的就是这堵墙：

| 做的事 | 覆盖范围 | 原理 |
|---|---|---|
| **光搬到根上**（`Theme.swift` 的 `AppCanvas`） | **每一屏** | 同一束光（车所在地的太阳位置）只画一次；两个屏幕上的光方向不一样，比没有光更糟 |
| **拆掉 16 处不透明画布** | 16 屏 | 保留 4 处：三个 sheet 内容（没有根画布垫着的独立呈现层）+ 地图主屏自己那层 |
| **分组标题改走衬线**（`DSSectionHeader` → `TokensSerif.section`） | **每一屏** | 分组标题是全 App 最密集的一行字 |
| **卡片/分组加发丝描边**（`DSCard` / `DSGroup`） | **每一屏** | 纸与墨的语言里，「一块面」是靠线画出来的 |
| **大标题搬进版面**（`dsPageTitle` + `DSPageTitle`） | 车控 / 充电 / 我的 / 消息 | 导航栏的字体改不了（系统字体），所以标题只能画在内容里 |
| **时刻滑块**（地图的「光」表里） | 地图主屏 | 拖一下看完一天的光；回放时药丸上打「回放」标记 —— 它同时是这套光的**证明** |

两条不许打折的规矩在这一批里都守住了：

1. **原生主题 = 现状**：`TokensSerif.section/page`、卡片的描边、导航栏大标题的存留，全部先判 `TokensPalette.decor == .none`。
   切回原生，界面与切换前逐像素相同。
2. **不吃点击**：画布与光层都是 `allowsHitTesting(false)`，它们只是光，不是控件。

### 这一批**没有**做的（说清，不含糊）

- **车控 / 充电 / 我的 的版式结构没有重排**。它们是 1081 / 615 / 590 行、由卡片堆起来的旧结构；
  这一批做到的是「光与字铺满每一屏」，不是「把每一屏重新排版」。
  重排版面必须在能编译、能看真机的条件下逐屏做 —— 盲改一千行布局，只会把能跑的东西改坏。
- 地图瓦片仍是系统渲染（见上一节）。
- 登录 / 引导 / Splash 也拿到了光（它们不在 Tab 体系里，但同样住在根部画布之上）。
  - **更正（2026-09-22）**：这句话当时对 `LoginView` 是**错的** —— 它自己铺了一层不透明的 `DSCanvas`（全项目最后一处），把根部的光整个挡住了。本轮移除了那一层，登录页这才真的拿到光。

## 8. 样品 → 真机的最后一轮（这一轮补的是「铺满」）

前几轮做的是**机制**（光引擎、刻印排版、车钉做工），落在少数几屏上；
这一轮做的是**把它们铺满**，并顺手把审计出来的结构性缺口补掉。

| 做的事 | 覆盖 | 为什么它值钱 |
|---|---|---|
| **浮层画布** `dsSheetCanvas()` | 19 处 sheet / fullScreenCover | 弹层盖住整屏，根部的画布到不了它后面 —— 光只铺到一半，比没有光更糟。用 `presentationBackground` 而不是 `.background`：那才是「这个呈现层的背景」这件事本身。原生主题不做任何事 |
| **12 个零版面页面重排** | 维保 / 里程 / 用车提醒 / 导出 / 隐私 / 指令历史 / 应急 / 全局搜索 / 更新日志 / 引导 / Splash / 快捷指令 | 之前它们只有「光垫在背后 + 系统导航栏标题」，没有版面 |
| **页标题进版面** | 上述 12 屏 + 三个主 tab | 导航栏的字体改不了（系统字体），所以标题只能画在内容里；同时修掉原生下的**重复标题**（内容标题必须只在艺术方向下出现） |
| **页边距** | 7 个界面（含车控 / 充电 / 我的 三个主 tab） | 审计发现的真问题：这些界面**根本没有页面水平内缩**，内容贴着屏幕边 —— 「粗糙」最直接的一处 |
| **卡片标题搬出表面** | 全 App 的 `CardBox` | 标题与内容同层时，「哪一层是分组、哪一层是内容」只能靠圆角猜；现在与 `DSGroup` 同一套 inset-grouped 语法 |
| **形状色收成令牌** | 三个主 tab，28 处 | `.primary/.secondary/.tertiary` 不跟随主题 |
| **颜色只留给真状态** | 统计三色、四色按钮矩阵、彩色药丸筛选 | 三个数字不是三种状态；筛选是互斥选项，该用系统分段语法 |
| **主题画廊改用真光层** | `ThemeGalleryView` | 原先手搓了一份「小号版」装饰，两个实现已经开始分叉（网格透明度 0.07 vs 0.08）。现在样张与真机是同一个 `SkyOverlay` |

### 这一轮修掉的「写了但不会生效」的代码

审计（而不是感觉）查出来的，全部是**不报错的错**：

- `MileageJournalView` 的 `.swipeActions(edge:)` 写在 `VStack` 里 —— `swipeActions` 只在 `List` 的行内生效，**滑动删除从来没有工作过**（`.listStyle(.plain)` 加在 VStack 上同样是空转）。现在删除挂在长按菜单上，并在页脚说明。
- `PrivacyDashboardView` / `MileageJournalView` 在「我的」的导航栈里**又套了一层 NavigationStack** —— 两条导航栏、标题说两遍。已拆。
- `OnboardingView` 的 `isLastPage` 永远是 `false`：那半个分支（含一句永远为空的 `Text`）是死的，已删。
- 上一轮的教训在 `scan.py` 里留了检查器（幽灵构造），所以这一轮同一类错是本地 0.2 秒抓到的。

## 9. 天气、登录页、车控版面（2026-09-22）

### 9.1 天气接上了：光从「晴空模型」变成「按实况云量折算」

`Services/WeatherService.swift`（新）+ `SkyLight` 新增可选的天气输入：

| 环节 | 做法 |
|---|---|
| 数据源 | `api.open-meteo.com`（无密钥、无注册）。取 `cloud_cover / precipitation / temperature_2m / weather_code` |
| 刷新 | 15 分钟 TTL；车挪出 5km 也作废；并发护栏（同一次取数只发一个请求）；失败**不改写旧快照** |
| 参与方式 | `SkyLight.now(at:coordinate:weather:)`，不传就完全等于以前（默认参数，测试与画廊不受影响） |
| 云量 → 辐照度 | `G = G_晴空 × (1 − 0.75 × N^3.4)`（Kasten–Czeplak 经验近似；**式子印在「光」表那一行的说明里**） |
| 降水 → 颗粒 | 降水越强颗粒越重（湿的街面会脏） |
| 回看时刻 | 滑块拖出来的时刻**不带天气** —— 那份实况是「现在」的云，挂到早上 6 点就是造假 |
| 取不到时 | 退回晴空模型，那一行的标签也从「全天空辐照度」变回「晴空辐照度」，说明里写「没有天气数据，不是实测」 |

顺带改掉了一个界面上说不得实话的地方——不是本轮新加的，是旧版就写着的：
「晴空辐照度」那一行以前是唯一的说法，现在有实况时它会诚实地改口。

### 9.2 登录页：版面重排 + **把那六个空壳函数补回来**

两个发现，第二个比第一个严重得多：

1. **光被自己挡住**：`LoginView` 是全项目最后一处用不透明 `DSCanvas` 的屏（其余 16 处上一轮就拆了），而光在根部只画一次 —— 于是登录页成了全 App 唯一「没有光」的一屏。已移除。
2. **登录按钮点了什么都不会发生**：`loadCaptcha / sendSMS / performLogin / checkBiometric / biometricLogin` **五个函数的函数体全是 `/* 保持原有逻辑 */`**（从 `b3af51e` 那次重设计起被删成空壳，注释却还写着「保持原有逻辑」）。已按 `b3af51e` 的历史实现恢复，并保持与 `APIClient.smsSend/login`、`AppStore.bootstrap` 的现有签名一致。
3. 倒计时原来用 `Timer.publish(...).autoconnect()` 写成**计算属性** —— 每次视图求值都会新建定时器并重建订阅（倒计时因此时灵时不灵）。改成 Task 循环，离开页面即取消。

版面：表单改成 inset-grouped 分组（不再在卡片里再挖一层填充输入框）、标题走衬线 + 疏排、一屏只有一个实心胶囊、按钮为何是灰的写在按钮下方、页脚说明凭据去哪儿了。

### 9.3 车控：版面就是信息架构

旧版是一条平铺的卡片堆，状态、动作、记录混在同一层。现在按人来的顺序重排：

**车现在什么样（姿态图 + 一句话 + 逐字段明细）→ 现在该做什么（唯一实心胶囊）→ 还能做什么 → 一键场景 → 做过什么**

同时修掉三处「说明与行为不符」（都属于数据诚实规则）：

- **一键场景的说明是假的**：三条场景分别写着「22℃ 座椅加热 + 后窗除雾」「18℃ 强冷模式」「锁车 + 关窗 + 折叠后视镜」，而代码实际只发一条 `OpenAir`，温度用的还是上一次残留的 `pendingTemp`。现在场景自带**指令与温度**（真的会发出去），说明只写真的会发的东西。
- **一键场景很可能什么都没发**：`onPresetScene` 直接调 `execute(pinDigits)`，而 `pendingCmd` 默认是空串（`execute` 开头 `guard !cmd.isEmpty else { return }`）、`pendingTemp` 是上一次的残留值 —— 场景既没告诉它发哪条，也没告诉它多少度，还跳过了身份验证这道门。现在场景与单个指令走**同一条路径**（先验身份 → PIN → 执行）。
- **`CardBox` / `ExpandingCardBox` 补上 `footer`**：规则与边界写在分组脚下，而不是只写在注释里（注释只有写代码的人看得见）。
- 「执行记录」改名「做过什么」，并在**收起状态**下就写明「只留最近 10 条（本机、本次运行）；全部记录在「指令历史」页里」。

### 9.4 验证与边界

- 10 个检查器全绿：`scan.py` 未声明的类型 / 构造 / 方法 / 未知成员 **全为 0**、幽灵构造 0；`lexguard` 字符串边界 0 / 孤儿属性 0；`shadowguard` / `logic` / `deep` / `eol` / `futureproof` / `scenes` / `targets` / `unreachable` 全 0；`check_style` 0 问题。
- 本轮新用的 SDK 名字（`Equatable` / `URLQueryItem` / `URLComponents`）**逐个对过 Apple 文档 JSON**（记下 externalID）才登记，显式核实清单到 41 个。
- 新增 8 条纯函数测试（云量衰减式子、阴天正午 = 25%、单调性、降水加重颗粒、表的说法随数据变、URL 里不得出现精确坐标、解析缺字段返回 nil、作废距离）。
- **仍然没有编译器**：这一批同样只经过静态验证，push 后由 CI 给出结论。

## 10. 查漏补缺：把「写了但没人能用到」的东西接上（2026-09-22）

这一批不是调色，是一次**审计 + 接线**。判据只有一条：一段代码如果
「没有入口」「没有调用点」或「调用了但什么都没做」，它就不算功能。

### 10.1 三个空桩变成了真实现

- **`ChargingStatusMonitor`**（原来 12 行、方法体是空的，壳层只写了
  `_ = ChargingStatusMonitor.shared`，连 `startMonitoring()` 都没调）
  → 改成由**真实报文驱动**：`AppStore.recordHistory()` 每次拿到车端数据就调用
  `observe(soc:charging:powerKW:)`，只在「开始充电 / 充电结束 / 充满」三个**跃迁**上
  推一条本地通知。它不生成充电记录（那是 `HistoryStore` + `ChargeLedger` 的活），
  两边各算一遍会出现两个不一样的总度数。
- **`AppIntentsManager`**（空桩、只被 `_ =` 引用一次）→ **删除**。
- **Siri 车控**：旧的三个 `INIntent` 子类需要 Intents Extension target 才可能被唤起，
  而 `project.yml` 里没有那个 target —— 所谓「Siri 车控」从来没通。改成真正的
  `AppIntent` + `AppShortcutsProvider`（不需要额外 target），五条短语：锁车 / 解锁 /
  开空调 / 关空调 / 寻车。顺带修掉一处静默错位：使用次数记的是 `lock_on` / `lock_off`，
  而卡片读的是 `lock_true` / `lock_false` —— 所以卡片永远显示「还没有用过语音指令」。

### 10.2 两处「提醒永远不可能响」

- **维保提醒**读 `carkeeper_current_mileage`，而这个键**全库只有读、没有写**（恒为 0）
  → 现在由 `AppStore.recordHistory()` 从车端 `Mileage` 字段写入，并真正调用调度器。
- **保险提醒**的 `scheduleInsuranceReminder` **从来没有调用点**；而且它的触发器只写了
  「9:00」、**把到期日整个丢掉**了（于是无论保到什么时候，都是明天 9:00 响一次）；
  窗口还写成 `days <= 30 && days > 20`（只有恰好落在那几天里被打开才排得上）。
  现在按到期日倒推真实日期，并由「年检与保险」页在进入/新增时调用。
- 两个调度器的 `clearAllReminders()` 原来用的是 `removeAllPendingNotificationRequests()`
  —— 那会连**别人的**待发通知一起清掉。各自只撤自己的。

### 10.3 摇一摇锁车：它以前不锁车

- `ShakeDetector.onShake` 的唯一设置点只弹一句「摇一摇已触发」，**不发任何指令**；
  阈值 1.5 g 也意味着走路放兜里就会被触发（静止时合加速度本就是重力 1.0 g）。
  现在：阈值 2.6 g + 8 秒冷却；真的走「验登录 → 验 PIN → 发 `CentralLock` → 记指令历史」，
  车已锁着就不发（照实说「车已锁好」）。
- 这个功能此前**没有任何地方能打开**（`carkeeper_shake_to_lock` 默认 false 且无人写入）
  → 「我的」里补了开关。

### 10.4 全局搜索：以前搜的是写死的字符串

`GlobalSearchHUD` 原先搜 6 条硬编码文案、每条的 `action` 都是空闭包，而且**没有任何入口**。
现在搜真东西：16 个页面（跳转走统一导航）、车辆档案字段、实时读数、行程、指令历史、
充电会话；入口在地图顶栏与「我的」。

### 10.5 「我的」：26 个磁贴一条平铺 + 一个到不了的退出登录

- 磁贴按意图分六组：车辆 / 用车 / 钱与证件 / 报告与共享 / 设备与模式 / 应用。
  「维保提醒」与「维保记录」原来是两个磁贴、同一个 `.service`，现在只留一个。
- **`logout()` 一直存在，但没有任何按钮调用它** —— 用户无法退出登录。现已接上（带二次确认）。
- 监控接进「开发者工具」：内存 / 网络延迟 / 离线模式 / API 成功率 / 崩溃记录 /
  充电监控 / 摇一摇 / 专注模式 / 车端里程 / 上次保养里程。它们本来就跑着，
  只是输出没有任何界面在显示 —— 那就等于没有。

### 10.6 一处工程告警的病因确认（**结论已更正**，见文末「CI 复红」一节）

当时记的结论是：AppIcon 每次 CI 都报「3 unassigned children」，成因是 `1x` 的
76×76 / 29×29 / 40×40 三个槽位在当前 SDK 已不再分配（数量「正好是 3」）。
**这个结论是错的** —— 3 只是巧合：那一轮把三个 1x 全删之后，N 并没有归零，
而是 3 → 2，剩下的 2 正好等于 `Contents.json` 里 `idiom: "ipad"` 的条数。
真正的成因是 `idiom`，证据与推演见 `AppIcon-SPEC.md`。

### 10.7 验证

- `scan.py`：未声明的类型 / 构造·函数 / 方法 / 未知成员 **全为 0**，幽灵构造 0；显式核实的
  SDK 名字 **58 个**（本轮新增的 `AppIntent` / `AppShortcutsProvider` / `AppShortcut` /
  `IntentDescription` / `IntentDialog` / `LocalizedStringResource` / `IntentResult` /
  `ProvidesDialog` / `fullScreenCover` / `submitLabel` 都先打印 Apple 文档 JSON 的
  `decl` 与 externalID 才登记）。
- `lexguard` / `shadowguard` / `logic` / `deep` / `eol` / `futureproof` / `scenes` /
  `targets` / `unreachable` / `orphans` 全 0；`check_style` 0 问题。
- 24 个改动文件的括号净余额与 HEAD 逐文件零差异。
- **这台机器仍然没有 Swift 编译器**：本批只经过静态验证，push 后由 CI 给结论。

## 11. CI 在 `xcodegen generate` 就挂了：一个空目录（2026-09-22）

第一次拿到真 CI 日志，失败点**不在 Swift**：

```
Spec validation error: Target "CarKeeper" has a missing source directory
  ".../CarKeeper/HealthKit"
```

`project.yml` 里声明了 `- path: HealthKit`，而那个目录的唯一文件
（`HealthKitManager.swift`）在「删死代码」那一批里被删了。**git 不跟踪空目录** ——
本地开发机上目录还在（被删文件留下的空壳），所以本地 `xcodegen generate` 一切正常；
只有干净检出会失败。代价是整轮 macOS runner，而且日志会误导人去看 Swift 错误。

修掉的三处连带：

- `project.yml`：删掉 `- path: HealthKit`；顺带删掉 `NSHealthShare/UpdateUsageDescription`
  —— 全仓已无任何 HealthKit API 调用，留着这两条会让人以为 App 在读健康数据。
- `.swiftlint.yml`：删掉过时的 `CarKeeper/HealthKit` 排除项。
- 新增 **`scan/paths.py`**：验证 `project.yml` 里声明的每个 source / resource / info 路径
  真的存在，**并且**验证 CI 工作流点名的检查器脚本都存在（含
  `for s in a b c; do python3 scan/$s.py` 这种循环写法 —— 漏掉它，检查器改名而忘了改列表
  就查不出来）。做了正反自测：干净树 0 报错；注入一条不存在的路径立刻以 ❌ + 退出码 1 拦住。
- 静态门禁的检查器清单补上此前没有在 CI 里跑的四个：`paths`（新）、`orphans`、`deep`、`eol`。
  其中 `orphans` 正是「写了页面但没有任何入口」的守卫 —— 这类问题以前只能靠人发现。

一个仍然存在的工程事实：**这台开发机没有 Swift 编译器**，所以 Swift 层面的错误只能在
CI 上看到。这一轮至少把「根本走不到编译」的那一层堵住了。

### 11.1 紧接其后的一次：CI 找不到 `CarKeeper` scheme

`xcodegen generate` 过了之后的第二个失败点仍然不在 Swift：

```
xcodebuild: error: The project named "CarKeeper" does not contain a scheme named "CarKeeper"
```

成因是 `bae6080`（加测试 target 那一批）往 `project.yml` 末尾加了顶层 `schemes:`，
里面**只**声明了 `CarKeeperTests`，注释却写着「CarKeeper scheme 是 XcodeGen 按 target
自动生成的」—— 事实相反：**一旦显式给出 `schemes:`，就不再有其它 target 的自动方案**。
本地 Xcode 打开工程会自动补一个 scheme，所以本地怎么试都正常。

现在两条 scheme 都显式声明（`CarKeeper` 走 build/test/archive，`CarKeeperTests` 给测试 job），
并且 `scan/paths.py` 增加了第三条规则：**工作流里 `-scheme X` 用到的每个名字，
必须在 `schemes:` 里声明过**（`schemes:` 缺席时才退回「每个 target 都有自动方案」）。

值得记下来的是：这个检查器的**第一版有洞** —— 它把「是 target 名」也算通过，而
`CarKeeper` 正好也是 target 名，于是反向自测（临时抽掉那条 scheme）当场没报。改成
「`schemes:` 存在时只认显式声明」之后，同样的探针立刻 ❌ + 退出码 1。

### 11.2 第一次真正跑到编译器：三个 Swift 错误

CI 终于走完 `xcodegen` + scheme，进入了 Swift 编译。三个错误，全部是这一轮新写的代码：

| 文件 | 错误 | 成因 |
|---|---|---|
| `MileageJournalView.swift:115` | `incorrect argument label (have '_:specifier:', expected '_:default:')` | `"¥\(x, specifier: "%.1f")"` 是 **`Text` 的 `LocalizedStringKey` 插值**语法，`DSKeyValueRow.value` 收的是普通 `String` —— 普通字符串插值没有 `specifier:`。改成 `String(format:)`。同文件第 262 行那处**是合法的**（它在 `Text(...)` 里），保留 |
| `SiriShortcuts.swift:65` | `value of optional type 'Int?' must be unwrapped` | `air(on:)` 写成 `temperature: on ? temperature : nil`，而 `sendControlCommand(temperature: Int = 17)` 收非可选。改成开机才带温度的分支 |
| `TripsTimelineView.swift:23` | `'clusterHotspots' is inaccessible due to 'private'` | 行程时间轴复用了地图的聚类函数，而它是 `private static` |

## 12. 新增：`scan/access.py`（跨文件访问 private）

第三个错误是**纯静态就能查出来**的一类：限定引用（`类型名.成员名`）指向了另一个文件里的
`private` / `fileprivate` 成员。这台机器没有编译器，这类错误只能靠人眼，而人眼漏了。

第一次尝试是全查「跨文件引用了任何 private 成员名」——**2916 条命中，全是
`font` / `now` / `content` / `filter` 这种同名噪音**。噪音检查器等于没有检查器，
所以最终只查**限定引用**：这正是编译器报的那一类，且几乎没有误报。

反向自测的写法也学了一课：探针**必须自带声明**，不能指向仓库里现有的某个 private 成员 ——
第一版探针指向 `MapSpineData.clusterHotspots`，而这个函数在同一个提交里被改成 internal，
于是探针「没问题可报」，自测误判成检查器坏了。现在探针自己声明一个
`AccessProbeHolder.secret()` 再从另一个文件引用它，通过后随即删除。

同一次里 `scan/paths.py` 还加了第四条规则：**磁盘上不得有「不在任何已声明 source 之下」
的 Swift 文件**。仓库里 `CarKeeper/Services/` 与 `CarKeeper/CarKeeper/Services/` 两个目录
（前者在 spec 里声明，后者被 `- path: CarKeeper/` 覆盖）都在编译 —— 但如果哪天改的那份
两份都不是，它就变成「改了等于没改、而且毫无报错」的文件。现存 0 个。

CI 静态门禁清单因此从 13 项变成 14 项（新增 `access`）。

### 13.1 一次被自己否掉的检查器（记录，因为它值得记住）

`SiriShortcuts` 那个「`Int?` 传给 `Int`」的错误卡了两轮 CI。为了一次扫干净，我写了个
启发式探针：找「`标签: 标识符` 且该标识符被声明为可选、而某个同名标签期望非可选标量」。

结果：**36 条命中，几乎全是误报** —— `Button(action: action)` 里那个 `action` 是闭包，
`title: title` 里那个 `title` 是非可选的局部量。根因是启发式只认标签名，不认
调用到底指向哪个函数、也不认标识符在该处真实类型。

而且这件事有**编译器自己给的证据**：同一次 CI 对同样的文件只报出 1 个错误，
说明这些文件全都通过了类型检查 —— 36 条命中，真的 0 条。

所以探针**没有进仓库**。这是同一课第二次出现（第一次是 `access.py` 初版 2916 条噪音）：
**能查的类型问题只有真类型检查器能查；静态脚本能可靠抓的是「结构」类问题**
（跨文件 private、未声明成员、路径缺失、孤儿页面），一旦伸到类型语义就会变成噪音，
而噪音门禁比没有门禁更糟 —— 因为它会训练人忽略它。

## 14. 批 0：拆掉 5 Tab 骨架（方案 A 的第一批）

### 14.1 病灶：48 个入口指向约 24 个页面

用户的判词是「缝合怪」，而这不是感觉，是结构：**两套信息架构同时在跑**。

| 入口系统 | 位置 | 规模 |
|---|---|---|
| 底部 5 个 tab | `CarKeeperApp:TabView` | 首页(地图) / 车控 / 充电 / 行程 / 我的，各一个独立 `NavigationStack` |
| 地图 4 个图层 | `MapSpineData` | 现在 / 行程 / 停车 / 充电 |
| 地图右上角索引页 | `MapSpineView:indexSheet` | `ForEach(Deeplink.allCases)` —— 16 项平铺 |
| 「我的」磁贴墙 | `MineView` | 27 个磁贴 |

物证是那句留了两代人的注释：**「全部功能在右上角的索引页里（去掉 Tab 栏的代价补在那里）」**
—— 某个版本的方向是**去掉 Tab 栏、地图是唯一入口**，索引页是为那个世界建的；
后来 Tab 栏回来了，索引页没拆。于是同一个「行程」有 4 个入口，「停车」有 3 个。

### 14.2 这一批做了什么

- `MainTab` 枚举、`selectedTab`、`controlPath` / `chargePath` / `tripsPath` / `minePath`、
  `clearTabPaths()`、`selectedTabVoiceOverLabel`、`Deeplink.hostTab`、Tab 角标、
  切 Tab 朗读 —— **整体删除**。`TabView` 换成**一个** `NavigationStack`，
  根是 `MapSpineView`（壳层 586 → 429 行）。
- `pushNavigation(_ link:targetTab:)` → `pushNavigation(_ link:)`：没有 Tab 可切，
  导航只有一个栈。11 个调用点（地图 7、搜索 3、我的 1）全部改到位。
- **新增 `Deeplink.mine`**：`MineView` 原本靠「我的」Tab 才能到达，Tab 栏一删它就成了
  孤儿页。加这个 case 之后它由索引页的「系统」组进入（批 3 会把它改造成「车与账号」）。
- **索引页升级为唯一目录**：从平铺 16 项改为按意图分四组 ——
  这辆车 / 出行 / 保养与钱 / 系统。并且**刻意不列 `.dashboard` 与 `.parking`**：
  它们指向的页面与 `.score` / `.trips` 是同一个（深链仍可用，只是不出现在目录里）。
- 低电量角标原本挂在 Tab 上，Tab 没了 → 改挂在**既有的 Toast** 上（跌破 20% 提示一次，
  回到 20% 以上才重新武装）。不新造控件。
- 三处把 Tab 栏当真的注释一并改掉（`DS.swift` 的玻璃规则、`MapSpineView` 的架构规则、
  `CarKeeperApp` 的分屏说明）—— 注释说谎比代码说谎更贵。

### 14.3 `orphans.py` 当场抓到我的漏项

我加了 `Deeplink.mine`，却忘了把它接进 `deeplinkDestination` 的 switch ——
于是 `MineView` 变成一个**打不开的孤儿页**。检查器立刻报 ❌ 并给出两种修法。

这是「孤儿页面」检查器第二次发挥作用（第一次是 `GlobalSearchHUD` 本身），
而且这次抓的是**我同一批改动里的错**：本地几秒内发现，不必等一轮 CI。
（编译器也会报非穷举 switch，但那是下一轮 CI 的事。）

### 14.4 还没做的（下一批）

批 1 必须紧跟：**没有 Tab 栏 = 锁车/开空调多一次点击**。高频操作应该在批 1
以「地图上的常驻操作条」补回来 —— 答案在地图上，不是把 Tab 栏加回来。

## 15. 旧骨架的残留审计（批 0 之后）

问得很对：批 0 只拆了**电话 App** 的骨架。全库扫一遍同类残留，结果是——

### 15.1 电话壳层：确认清零

`MainTab` / `selectedTab` / 四个 per-tab path / `clearTabPaths()` / `Deeplink.hostTab` /
Tab 角标 / 切 Tab 朗读：全库各只剩 **一行「已整体删除」的说明性注释**。
剩下两处 `TabView` 是合法的：引导页翻页（`PageTabViewStyle`）、watchOS 自己的 TabView。

### 15.2 残留一：CI 只编译了 7 个 target 里的 1 个

`scheme CarKeeper` 的 build action 只列了 `CarKeeper`，于是
**WidgetBundle / AppClip / WatchApp / WatchKitApp 从来没有被 CI 编译过一次**。
里面有错也看不见 —— 这正是「构建过了」这句话之前一直不成立的原因。

现在 build job 末尾多了一步 **编译体检**（`Compile other targets`，非阻断）：
逐个 `xcodebuild -target ... -sdk ...`，每个 target 单独一份 derived data，
日志按目标分组。它排在**打包与 Release 上传之后**，所以不可能影响 ipa 产物。

同时留下一个坑位说明：**等它绿了就该把它改成阻断的**。
顺带踩掉一个自己差点写下的 bug —— 不要写 `xcodebuild ... | tail -40` 然后看管道退出码
（那取的是 `tail` 的状态，恒为 0，失败会被当成成功）。先落盘再判断。

### 15.3 残留二：同一个文件存在两份副本（Watch）

`WatchApp.swift` 与 `ComplicationController.swift` 在磁盘上有**两份、
分别属于两个 target**（扩展与 WatchKitApp），内容靠人肉保持一致 ——
改一份忘另一份，两个 target 各跑各的，而且**没有任何检查会出声**。

现在 `paths.py` 多三条文件级规则（都要先把每个 target 的 sources 展开到文件）：

| 规则 | 现存状态 | 反向自测 |
|---|---|---|
| 同一 target 内不得有同名 .swift（重复符号，编译必挂） | 0 处 | 造一个同名副本 → ❌ 退出码 1 |
| 跨 target 同名但不同路径的两份副本必须一字不差 | 4 组，全部一致 | 给一份加一行 → ❌ 报「已漂移」 |
| project.yml 的每个 target 都必须被 CI 覆盖（scheme + 体检清单） | 7/7 覆盖 | 从清单里抽掉 WatchKitApp → ❌ 退出码 1 |

第三条是双向的：CI 里点名了 spec 中不存在的 target 也会报（名字写错的那一类）。

**没有修的那部分**：Watch 的这份「复制粘贴式共享」本身是债 ——
正经做法是让扩展有自己的入口文件、把共享的东西抽成 framework。
但它需要真机/真 Xcode 验证（watchOS 的 app 与扩展谁是 `@main` 载体，
在没有编译器与真机的环境里靠猜改，比留着这条守卫风险大）。先由守卫兜住漂移。

## 16. 批 1：高频操作回到地图上（加上「旧骨架残留」审计）

### 16.1 先回答「旧骨架是不是完全干掉了」

电话壳层：**是**。`MainTab` / `selectedTab` / 四个 per-tab path / `clearTabPaths()` /
`Deeplink.hostTab` / Tab 角标 / 切 Tab 朗读——全库各只剩一行「已整体删除」的注释。
剩下两处 `TabView` 合法：引导页翻页、watchOS 自己的 TabView。

但同一个扫查又拎出**两个新的同类残留**，都在第 15 节里修掉了（CI 从没编译过
5 个 target；Watch 有两份同名副本靠人肉同步）。这一条本身值得记：
**「骨架拆完了」这句话，得靠扫全库才能说出口**。

### 16.2 批 1 做了什么

批 0 拆掉 Tab 栏之后，锁车变成「索引页 → 车控 → 点锁车」——**为了一个动作离开车所在的
那张图，是退步**。批 1 的答案不是把 Tab 栏加回来，而是两条：

**① 执行路径归一**（新文件 `Features/Control/CommandCenter.swift`）。
发起一条指令其实是五件事：验身份 → 发指令 → 按 TaskId 轮询到车辆终态 → 写指令历史 →
重拉车况缓存。这五件事原先只写在 `ControlView` 里，而地图上的操作条也要发同一条指令。
两边各写一遍，迟早会出现「地图上锁车显示成功、车控页里同一辆车显示失败」——
这种分歧没有任何检查能发现，因为两边都「自己是对的」。现在整条路径只有一份。

`ControlView` 里那一千多行视图代码**一行都没改**：执行状态改成五个只读转发属性
（`busy` / `running` / `history` / `lastResult` / `showResult`），写入只发生在中心里。
顺带把三个「编译器不会说、但用户会看到」的地方一起修了：

| 原先 | 问题 | 现在 |
|---|---|---|
| `store.addCommandHistory(cmd: "", name: "")` | **指令历史里每一条都没有名字**，看不出做了什么 | 传真实指令名 |
| 成功时 `show("")` | 只有图标没有字；在地图上发指令不跳页，读不出是哪条的结果 | 带指令名的文案 |
| `pollTask?.cancel()` | 只停轮询不清状态 → 条子永远停在「正在执行」，下一次指令被静默挡回去 | `abandon()` 停轮询 + 收干净 |

**② 地图上的常驻操作条**（新文件 `Features/Map/MapQuickBar.swift`）。
锁车 / 解锁 / 空调 / 寻车四个动作**不离开地图**就能发出去：验身份（Face ID → 控车码，
两样都要，不是重复）→ 下发 → 在原地看进度。指令跑的时候，这条**变成那条指令本身**
（名字 + 「第 3 次查询 · 车辆处理中」），不做全屏遮罩——车就在地图上，发指令时还该看得见它。

两个身份验证为什么都要：Face ID 证明「是本人」，而控车码是**车端协议要求的参数**
（`sendControlCommand(pin:)` 直接带它下发）。车控页原先就是这个顺序，操作条沿用同一套。

### 16.3 顺手清掉的三处

- **`pendingQuickCtrl` 删了**：它全库**没有任何地方写入**（注释写着「首页快控穿透」，
  但首页从来没设过），读它的只有车控页的 `onAppear`。批 1 之后地图直接执行，
  这条路彻底无必要 —— 同时带走了 `quickAllowlist` / `resolveQuick` 这对「简写表」。
- **`ControlView` 的 `@EnvironmentObject var nav` 删了**：全文件一次都没用过。
  留着的真实代价不是啰嗦——而是一旦这一屏改用 sheet 呈现，环境里缺这个对象会直接崩。
- **地图上的「找车」改名「回到车」**：它做的是把镜头移回车（`centerOnCar`），
  而「寻车」是另一件事（下发 `RemoteSearchCar` 让车鸣笛闪灯，现在在操作条里）。
  两个都叫「找车」= 用户分不清点哪个。

### 16.4 验证

14 个静态检查器全绿、风格 0 问题、改动文件括号余额逐文件与 HEAD 配平。
`scan.py` 逮到一处真问题：`truncationMode` 不在显式核实名单里——打印 Apple 文档 JSON
确认它是 **`View` 的方法而非 `Text` 的**（`nonisolated func truncationMode(_ mode: Text.TruncationMode) -> some View`，
externalID `doc://com.apple.SwiftUI/documentation/SwiftUI/View/truncationMode(_:)`）后才登记，清单到 60 个。

### 16.5 没做的部分，以及为什么

**「上滑展开完整车控」的抽屉没做**：底部面板现在是一个静态 `VStack`（不是真的 sheet），
把它改成可拖拽的多档抽屉是**版面改动**，而这台机器没有编译器、也没有模拟器——
我看不见它长什么样。操作条的真正目的（高频动作不离开地图）已经达成；
抽屉是形态优化，应该等设备上确认过操作条之后再动。

**执行中的指令在离开车控页时会被放弃**（`abandon()`）：这是原先的行为，我保持了它，
而不是顺手改成「后台跑完再提示」——那会改变电量与语义，属于另一个决定。

## 17. 删掉单元测试 job（2026-09-22，按用户要求）

### 17.1 删了什么、失去了什么

CI 里那个 `unit-tests`（`Unit tests (pure logic, non-blocking)`）整体删掉了。
它原本是纯函数测试（光的太阳位置、充电站聚合）的**唯一**执行处，而且**非阻断**——
红不红都不影响构建产物。每次 push 却要为此多占一整个 macOS runner，
而 macOS 额度是按 **10 倍**计费的：花 10 倍成本跑一个不影响成败的东西。

失去的东西要说清楚：**`Tests/PureLogicTests.swift` 从此不再被任何 CI 编译过。**
这是真实的代价，不是零成本删除。target 与 scheme 都保留，开发机上
`Product > Test` 随时能跑（这正是那些测试最初该被跑的地方）。

### 17.2 不能让规则靠沉默蒙过去

删掉之后，`paths.py` 那条「project.yml 里的每个 target 都必须被 CI 编到」
会出现一个**看似通过、其实是假的**结果：`CarKeeper` scheme 的 test action 里
依旧写着 `CarKeeperTests`，于是它会被算作「已覆盖」，而它实际上一行都没被编过。

两处收紧：

| 改动 | 原来 | 现在 |
|---|---|---|
| 只看「被工作流真正引用的 scheme」 | 看 spec 里声明的所有 scheme | 工作流没跑过的 scheme 不算数 |
| test action 只在真的跑测试时才算覆盖 | 声明了就算 | 必须有 `xcodebuild test` 才认 |

再加上**显式豁免**：`CI_UNCOVERED_TARGETS` 里写明 `CarKeeperTests` 与**理由**，
输出成 ⚠️ 而不是 ✅。反过来，豁免名单里出现 spec 中不存在的 target 也会被报出来
（陈旧豁免该删了）。默认值仍然是「每个 target 都要被编到」。

反向自测两条：把豁免拿掉 → ❌ 退出码 1（并顺手报出陈旧豁免条目）；
给工作流加回一条 `xcodebuild test -scheme CarKeeperTests` → 自动变回 ✅。
第二条同样重要：**证明这条规则不是永久瞎的**，测试真的回来时它认得。

`project.yml` 里那句「单元测试 job 用它」也一并改成实话 —— 注释说谎比代码说谎更贵。

---

## 2026-09-22 · 统一契约（DESIGN-UNIFY.md）

「各种风格混用」不是感觉，是对着数字能证的：仓库里同时活着**四代容器、三套行、三种标题机制、
两个页面边距机制**。这一轮先立契约（`DESIGN-UNIFY.md`），再按它清场。

这一轮落地的：

| 位置 | 改了什么 |
|---|---|
| `DS.swift` | 新增 `DSExpandGroup`（折叠分组回到 DS 语言；旧 `ExpandingCardBox` 的替代品） |
| `MineView` | 6 个 `CardBox` → `DSGroup`；28 个 Tesla 磁贴 → `DSRow` 设置行；`glassCard` 行 → `DSGroupRow`；`tile()` 辅助函数删除 |
| `Theme.swift` | `MonthlyReportGenerator` 从「自建卡片 + 自建行」→ `DSRow`；`ReportSection`/`ReportRow`（第五种行）删除，月报改用 `DSGroup` + `DSKeyValueRow` + `DSPrimaryButtonStyle`；`PowerSavingToggle` 的 `.green`/`.orange` → 令牌 |
| 标题 | 7 个裸 `.navigationTitle` 的页面（全量数据 / 设计令牌 / 驾驶评分 / 健康报告 / 艺术主题 / 行程 / 车辆档案）改成 `DSPageTitle` + `dsPageTitle()` **成套**；`DevView` 连横向页面边距都没有，补了 `pageBackground()`（⚠️ 该函数 **2026-09-25 第五轮整段删除**，见文末同名一节） |
| 卡片 | `ExportDataView` / `ServiceHistoryView` / `BiometricLock` / `FamilyAndKeySharing` 的 `.glassCard()` → `DSCard`；维保记录的空态改走 `DSPlaceholder` |
| 令牌 | `Theme.font(...)` 调用点清零（8 处）；`.green`/`.orange`/`.red` 直用清零（`AppStore.statusColor`、省电开关、电池达成率） |

还没做（写明数量，不装作完成）：

| 位置 | 数量 |
|---|---|
| 电池页旧世代 | 16 处（`ExpandingCardBox` 3 / `CardBox` 4 / `KVRow` 5 / `ListDivider` 3） |
| 车控页旧世代 | 12 处（`ExpandingCardBox` 2 / `CardBox` 3 / `KVRow` 4 / `ListDivider` 3） |
| 应用内硬编码字号 | 68 处 |
| 假数据 | `MonthlyReportGenerator` 的 1250 km / 14.5 / 8 次 / 65% / 85 分 |

顺带一个「命名对齐」：`MineView` 的标题从「我的」改成**「车与账号」**（索引页里它就叫这个名字），
`VehicleView` 的空态文案「请先在「我的」页面绑定车辆」也改成「车与账号」——
同一个页面两个名字，是导航里最容易迷路的地方。

`DSExpandGroup` 目前**没有调用点**：它是下一批（电池 / 车控）要用的容器，先放在 DS 里，
免得那一批再发明第五个。这一点写进了契约文档，不让它变成悄悄躺着的死代码。

14 个检查器 + `check_style` 全绿，14 个改动文件括号余额逐文件配平。

---

## 第三批：字体与颜色的**字面量清零**（并加了一道会出声的门）

前两批把「同一件事的多个名字」合并了（四代容器 → DS；两套行 → DSRow；三种标题机制 → 成套）。
这一批处理的是更隐蔽的一层：**同一件事的多个数值**。它不表现为"多了一个类型"，
而表现为"同一页里 13/14/15pt 混着写"——看起来就是没对齐。

### 迁移前 vs 迁移后（数出来的，不是感觉）

| 项 | 迁移前 | 迁移后 |
|---|---|---|
| `.font(.system(size: N))` 字面量 | 112 处 / 26 个文件 | **0 处**（定义处之外；3 处显式豁免） |
| 颜色分量字面量（手写 RGB） | 4 处（含纸纹的暖棕、遮罩的纯黑、阴影） | **0 处**（全部进 ArtTheme 的取值表） |
| 色相直用（`.white` / `.red` / `.black` / `.green` …） | 25 个文件里有 | **0 处** |
| 跨 target 各自一套数值 | AppClip 19 / 小组件 6（各自写死） | AppClip / 小组件**共用 `Shared/WidgetTokens.swift`** |
| `Theme.swift` | 1128 行（第二代设计系统：`CardBox` / `FluidHeroFont` / Dynamic Type 工具…） | **415 行**：只剩画布与光、两个小零件、两个被「车与账号」直接用的视图 |
| `Color(hex:)` / `Theme.font` / `Theme.lineHeight` | 三个"第二个入口" | **已删**（字体只从 `TokensTypo` 出，颜色只从 `TokensPalette` 出） |

### 新增 `scan/design.py`（把「完全统一」变成可执行的约束）

三条规则，只拦**结构**（这正是静态脚本能可靠做到的那一类）：

1. 字号字面量 → 只允许在 `Tokens.swift` / `WidgetTokens.swift`
2. 颜色分量字面量 → 只允许在 `ArtTheme.swift`（主题取值表）/ `WidgetTokens.swift`
3. 色相字面量（含 `colors: [.red, .orange]` 这种裸色名）→ 一律不允许

豁免必须**写明理由**，输出成 ⚠️ 而不是 ✅（沿用 `paths.py` 的约定）。目前 3 条豁免：
主题样张页（它的职责就是把真实取值显示给人看）、Watch 的两个副本（理由见下）。

> 反向自测做了：注入一处 `.font(.system(size: 14))` → ❌ + 退出码 1；
> 同一处写进 `EXEMPT` → ⚠️ 并打印理由；把豁免删掉 → 又变 ❌。

### 为迁移补的三个口子（都是「同一件事被做了很多次」的典型）

| 新令牌 | 它替掉的东西 | 为什么必须是令牌 |
|---|---|---|
| `TokensPalette.scrim` | `.black` 遮罩、暗角、车钉落地阴影（7 处） | 纯黑在暖色纸面上会发蓝 —— 纸主题的遮罩是**墨** |
| `TokensPalette.labelOnTint` | 紧急面板 / AppClip 上的 `.white` 文字 | 琥珀底配白字只有 1.9:1；"彩色面上的文字色"必须是主题的一部分 |
| `TokensTypo.fixed(N, weight:)` | 图钉 / 药丸 / 图标字形 / 环内读数（~45 处） | 那些画布是几何图形，字号**不能**跟随 Dynamic Type（放大会撑破它）；但尺寸仍只能从令牌文件出 |

`WT.Palette.onAccent` 与 `WT.Typo.fixed` 是它们在**世界面**的同名同义对应物 ——
两边的命名刻意一致，这样"车机上看到的"与"手机里看到的"是同一条规则。

### Watch 为什么没并进来（先去核实，再豁免）

共享 `WidgetTokens.swift` 的前提是它能在那个平台编译。查了 Apple 文档 JSON：

```
secondarySystemGroupedBackground
  platforms = iOS 13.0 / iPadOS 13.0 / Mac Catalyst 13.1 / visionOS 1.0
  —— 没有 watchOS
```

`WT.Palette` 的取值面是系统语义色，所以**手表不能共享这份文件**（不是不想共享）。
手表那 19 处字面量按它的 155pt 画布另定，豁免理由写成了**平台事实**并记进 `scan/design.py`。

### 顺带发现的三个「说错了话」的地方

1. `ArtTheme.swift` 头部写着「App 里仍有约 130 处写死的颜色，不跟随主题，属于下一轮的事」——
   本轮就是那一轮，已改成实情（并把仍未做的一条如实留着：换主题会重置子树 `@State`）。
2. `Theme.swift` 里两处 `\.white` 注释与「页面的加载态用 `DSSkeleton`」混在一起，
   孤儿 `///` 注释挂在已删的类型上 —— 已清。
3. `TokensSize.icon*` 与 `.font(.system(size: TokensSize.icon))` 是这个仓库里的**中间形态**
   （尺寸是令牌，但字体构造仍在调用点）。定尺零件现在统一走 `TokensTypo.fixed`。

### 仍未做（不装作完成）

- `MonthlyReportGenerator` 的月报仍是写死的 `1250 km / 14.5 / 8 次 / 65% / 85 分`。
- AppClip 那一屏的「特斯拉 Model 3 / 85% / 420km」是编的（连车型都对不上）。
- `tripHistory` / `parkingHistory` 仍**没有任何写入点** → 行程与停车两个层必然是空的。
- 车控页还没按 `funCode` 开合控件（本车 `#StateWindow:0`、`#PeriodicCharge:0` 照样显示按钮）。
- `daysUntil` 还没拒绝 `0000-00-00`；`AppStore` 写里程用的键名（`Mileage`）与真实报文
  （`totalOdometer`）不匹配 → 维保提醒永远不会响。

15 个检查器（新增 `design`）+ `check_style` 全绿；31 个改动文件括号余额逐文件配平
（用 `design.py` 的同一套字符串/注释剥离实现来数，不另写一套）。

---

## 批 3：「车」一屏收口 —— 车辆档案 ← 里程记账 + 用车提示

页面集合从 20 收成 7 的第三批。两个页面**不是被删掉，而是被吸收**：内容一行不丢，
页面外壳（`ScrollView` / `DSPageTitle` / `.dsPageTitle` / 工具栏）删掉，改由车辆档案提供。

| 原 | 现 | 备注 |
|---|---|---|
| `MileageJournalView`（从「我的」以 sheet 打开） | `Features/Vehicle/MileageJournalSection.swift` | 文件随内容一起搬进 `Features/Vehicle/` |
| `VehicleTipsView`（深链 `carkeeper://tips`） | `Features/Vehicle/VehicleTipsSection.swift` | 同上 |
| `Deeplink.tips` | 已删 | 索引页 / 搜索 / `MineView` 三处重复入口一并去掉 |
| `MineView` 的「里程记账」行 + sheet | 已删 | 它现在在车辆档案里；分组页脚文案改成实话 |

### 吸收时逮到的三个「不会改变任何东西的控件」

1. **里程记账的「本月 / 上月 / 全部」分段只换选中态。** 统计读全量、明细也读全量 ——
   切到「上月」数字纹丝不动。现在规格真正生效：一个 `periodRange` 定义口径，
   统计与明细共用它，分组右侧还显示这一口径下的条数。
2. **里程记账工具栏的「清空历史」闭包是空的**（`// 清空所有记录（需确认）` 后面什么都没有）：
   按下去什么都不发生。现在 `MileageTracker.clearAll()` 真的清，且必须先过 `confirmationDialog`。
3. **用车提示里「去充电」/「查看详情」是两支空实现**（`// Navigate to charging` + `break`）：
   按下去什么都看不到，**然后这条提示被标记已读** —— 用户以为处理过了，其实只是被藏起来了。
   这一节没有自己的导航目标，所以改成给一个可见回应（既有 Toast）+ 说明写在注释里。

另外「全部已读」从导航栏工具栏挪到分组标题最右侧（`DSSectionHeader(trailing:action:)`）——
并入之后这一节没有自己的导航栏，动作必须落在内容里。

15 个检查器 + `check_style` 全绿；七个改动文件括号余额逐文件配平。

---

## 批 4：「车与账号」不再是第二份功能目录

这一页此前自己列了两组「车辆 / 用车」链接（健康报告、电池、档案、全量数据、评分、
行程、维保、停车、紧急求助、附近充电站）—— 与地图右上角索引页**逐行重复**。
同一件事两个入口，就是缝合怪的来源。两组已删，功能目录只在地图上有一份。

页面现在是纯设置：身份卡 · 车辆卡（`nav.pushNavigation(.vehicle)`）· 钱与证件 ·
报告与共享 · 设备与模式 · 应用（含全局搜索、消息中心、隐私与数据、OTA 日志、
语音播报、开发者工具、退出登录）。副标题与无障碍提示改成实情。

15 个检查器 + `check_style` 全绿。

---

## 批 5：「保养与钱」一屏 —— 吸收维保 + 年检保险 + 充电账单 + 估值 + 导出

`ServiceHistoryView` → **`MaintenanceMoneyView`**（`Features/Maintenance/`），
页面标题从「维保记录」改成「保养与钱」，并把四个原本各占一个弹层/深链的东西并成一屏：

| 原 | 现 | 备注 |
|---|---|---|
| `InspectionCalendarView`（弹层） | `InspectionSection` | 仍在 `Services/BillingAndCalendar.swift`，只提供内容 |
| `VehicleValuationView`（弹层） | `VehicleValuationSection` | 同上 |
| `ChargeBillSheet`（弹层） | `ChargeBillSection` | 同上 |
| `ExportDataView`（深链 `.export`） | `ExportDataSection` | 文件搬到 `Features/Maintenance/` |
| `Deeplink.export` | 已删 | 索引页 / 搜索两处入口一并去掉 |
| 「车与账号」的「钱与证件」三行 + 三个 sheet + 三个 `@State` | 已删 | 它们现在是保养与钱里的三节 |

页面顺序按「先到期、再花钱、后带走」：即将到期（保养里程 / 年检保险日期两套口径）→
保养记录（统计/年份/时间线）→ 充电账单 → 车辆估值 → 导出。

顺带删掉「车与账号」里最后一条功能入口（消息中心）—— 功能目录只在地图上有一份。
`Theme.swift` 里那句「导出页的 `ExportDataView` 才是真的导出」也改成现在的实话。

15 个检查器 + `check_style` 全绿；七个改动文件括号余额逐文件配平。

---

## 批 6：「体检与数据」一屏 —— 结论 + 依据

「健康报告」与「全量数据」讲的是同一次 `carcheck`：一个是结论，一个是原文。
分成两页等于把一句话拆成两屏，所以合并：

| 原 | 现 | 备注 |
|---|---|---|
| `HealthView`（深链 `.health`） | `HealthDataView`（`Features/Health/`） | 页面标题改成「体检与数据」 |
| `DataView`（深链 `.data`） | `RawDataSection`（同目录） | 8 个分类菜单 + 复制/刷新/分享从导航栏挪进内容里的节标题行 |
| `Deeplink.data` + `navToData` 通知 | 已删 | 索引页 / 搜索两处入口一并去掉 |

`RawDataSection` 放在 if/else 链**之外**：体检报告读不到时，原始字段往往正是排错要看的东西。
默认分类也从「全量分析」改成「检测报告原文」—— 它就在评分的正下方，读者顺着结论往下就是依据。

15 个检查器 + `check_style` 全绿；五个改动文件括号余额逐文件配平。

---

## 批 7：「出行」一屏 —— 行程 + 常停之地 + 评分 + 车的事件

| 原 | 现 | 备注 |
|---|---|---|
| `TripsTimelineView`（深链 `.trips`，别名 `.parking`） | `TripsEventsView`（`Features/Trips/`） | 页面标题改成「出行」 |
| `MessagesView`（深链 `.messages`） | `MessagesSection`（同目录） | 搜索框从 `.searchable` 回到内容里，「全部已读」从导航栏挪到节标题右侧 |
| `DrivingScorePage`（深链 `.score`，别名 `.dashboard`） | `ScoreSection`（同目录） | 它**完全**由行程电耗算出，就该长在时间轴旁边 |
| `navToMessages` / `navToData` 通知 | 已删 | 两个都**零个投递点**（声明了、监听了、从没人发） |
| `AppStore.unreadMessageCount` | 已删 | 永远返回 0，且全仓零个读取点 |

顺带修掉同一页里的**两套外壳**：「空态」与「有数据」原本是两条互斥的整页分支，
各自带一套 `ScrollView` + 页面标题。现在只有一张画布：行程在上、常停之地在中间、
评分在下、车的事件在最下面。

地图「现在」那一格里原有一个叫「异常」的动作块，它跳的正是消息页 —— 而消息里多数是
点火/熄火这类**正常事件**，叫「异常」等于把正常行驶标成故障。现在它叫「事件」，指向出行页。

## 最终页面集合（这一轮做完的样子）

地图（家）+ 9 个深潜面：车 / 电池与充电 / 车控 / 体检与数据 / 出行 / 保养与钱 /
应急面板 / 车与账号 / 开发者工具。改造前约 20 个页面。

**刻意保留为独立屏幕的三个**（理由写在 `DESIGN-UNIFY.md` 第 7 节）：电池与充电（它是
地图「充电」层的深度视图）、应急面板（紧急入口不能埋在别处）、开发者工具（仓库说明书，
不是用户功能）。

15 个检查器 + `check_style` 全绿；本轮五个改动文件括号余额逐文件配平。

### 收尾：搜索列表与索引页对齐

全局搜索结果里还留着两条**指向同一个页面**的别名条目（「驾驶总览」→ `.dashboard`、
「停车位置」→ `.parking`，两者都开出行页），其中「驾驶总览」这个名字来自早已删除的
`DashboardView` —— 搜索里承诺一个不存在的总览页，是界面在说谎。
搜索列表 = 页面清单，一对一；别名只作为深链存在，不再作为「第二条入口」。
（索引页在 2026-09-23 已整个删掉，所以这份清单也不再和谁对齐 —— 它现在**从
`HomeMode.allCases` 派生**，提示语与图标由一个穷举 switch 给：那才是真的“一对一”，
因为两只手再无抄漏的机会。）

---

## 地毯式对拗式复查（2026-09-23）

一次把「还没做完的」找出来的复查。结论：代码级门禁（16 项）干净，但**漏在门禁看不见的地方**。

### 1. 入口只统一了一半（已补）

模式条立起来之后，仍有 **10 处绕过它 direct push 页面**：地图卡片里的三个动作块、
三个「看全部…」按钮、索引页行、「我的」的车辆卡与链接行、全局搜索的六组结果。
同一个功能因此仍然有两种存在方式（卡片里一份、push 出来一份）。

现在只有一种：`NavState.openMode(_:)` —— 写档位键 + 清栈回到地图，
由 `HomeMode.init?(link:)` 做深链→档位的翻译；不是档位的子页面（隐私 / OTA /
家庭 / 钥匙）才 push。我上一轮加的「长按纸面 push 整屏版」也删了 ——
它正是“同一页两种存在方式”的又一个例子。

### 2. 五个「有名字、没发射」的通知（已删）

`.navToVehicle` / `.navToHealth` / `.navToBattery` / `.navToDev` / `.navHome`：
每个都只有一个观察者（根视图里写 `nav.path = [...]`），而**全项目零 post** ——
既是从未生效的死线，又是与模式条并行的第二条导航路径。

反过来，`.locationUpdated` 是**三个观察者、零 post**（地图跟车走 / 重取天气 /
低电量提示三条行为从未生效过）。这一条不是删，是**补发射点**：
`AppStore.saveCache`（location 缓存的唯一写入点），带 ≈5.5 米的变动门槛。

### 3. 消息列表永远空 —— 根因是 carId 闸，不是解析

`MessagesSection` 用 `guard !store.carId.isEmpty` 挡在加载前，而消息接口 URL 里
**没有 carId**，小程序也只检查 token。`carId` 要等 bootstrap 的 `getCars` 回来才有值，
`getCars` 一失败就是空串 → 消息永远空，看上去像「解析不对」。
现在只看 token；解析出 0 条会 NSLog 打顶层键与响应长度；空状态区分「真没消息」
与「拉取失败（带真实错误）」；已读判据回到小程序的 `readStatus`。

### 4. 图标：两份并存（已对齐）

仓库根目录另有一份 `AppIcon/`（12 个 PNG，文档里的旧命令写进去的）—— 而 Xcode 只认
appiconset。已删掉根目录那份，并把 `AppIcon-SPEC.md` 的生成命令改成唯一的
`generate_appicon.sh`。

（这一节原先还写着「缺 iPad 76×76 1x 导致 2 unassigned children，已补齐」——
那句话是错的：补齐之后 N 从 2 变成了 3。成因与证据见文末「CI 复红」一节。）

### 5. 删掉的死代码

`DSIconButtonStyle`、`EmptyStateView`（两个全项目零引用）、三个空目录（`b/`、`state/`）。

### 6. 刻意没动（它们不是垃圾）

`clogs*.txt` / `clogs.zip`：`.gitignore` 里的本地拓包日志，是分析报文的证据，不进仓也不删。
`design-preview/*.html`（8 份设计预览）：设计决策的凭据，每份内容都不同、无重复；
其中 `fusion.html`（底部模式条 10 套融合）已随本轮入库。
根目录 `README.md` 只有一行 `# CarInfo` —— 仓库门户页，留着。

---

## 收尾三件（2026-09-23 续）

### 1. 02 的卡头：每一档先给一个事实

上一轮只把九个（现为十个）功能界面塞进了同一张固定高度的纸 —— 外壳统一了，
每张脸还是原来那张。现在每档顶上多了一块**固定不滚**的卡头
（`Features/Map/HomeModeHead.swift`）：一个巨字 + 一行说明 + 三条依据。

- 数字**只从已有 ViewModel 取**（`VM.energy / vehicleSummary / healthModel /
  maintenancePlan / userModel / bodyStatus / comfortStatus`），页面里不重算 ——
  同一件事两处各算一次就会出现两个答案。
- 取不到就照实说（“还没有体检记录”、“里程还没上报”），不摆 `--` 冒充。
- 「现在」那一档没有卡头：那张纸本身就是地图的面板（车名 + 地址 + 状态行），
  再叠一个巨字就是两层标题。

### 2. 索引页拆掉了（那份目录是最后一个“第二入口”）

地图工具栏的格子按钮与整张「全部功能」索引页（带 `indexSheet` / `indexGroup` /
`indexRow` / `deeplinkTitle` 四件零件）已删。原来只在那里能找到的「应急」
现在是模式条上的一档 —— 紧急入口本来就不该埋在一层目录里。

### 3. 把「入口只有一条」交给 CI 守

新增 `scan/oneentry.py`，三条判据：

| 判据 | 防的是什么 |
|---|---|
| 属于某一档的深链**哪里都不准**被 push（包括 App 入口；深链也走 `openMode`） | 下次又一个页面自己 push 第二份「车辆页」 |
| 档位 ↔ `pageContent` 一一对应 | 加了档位、忘了接页面（或反过来） |
| 档位在 `HomeModeHead` 里出现两次（巨字 + 依据行） | 加了档位、但那档看起来不像一家人 |

它已接进工作流的门禁列表（当时共 17 条；加上下面的 `traps.py` 后为 18 条）。设计契约
`DESIGN-UNIFY.md` 第 6 节同步成「两级模式条 + 一份目录」的现状。

---

## 真机崩溃（2026-09-23 09:14）—— `hashValue` 冒充业务数据

第一份真机报告（iPhone17,1 / iOS 27.2 beta；`bug_type 309`，`EXC_BREAKPOINT`）。
它不是「布局不对」，是**切到车辆档必崩**。栈：

    VehicleTipsSection.body.getter
      → VehicleTipsSection.tips.getter
        → ServiceReminderManager.reminders.getter
          → ServiceReminderManager.defaultReminders.getter   ← SIGTRAP

崩的那行是：

    nextDate: cal.date(byAdding: .month, value: 6 + type.hashValue * 2, to: today)!

`hashValue` 是**每进程随机种子**（既不是固定值，也不是枚举序号），能到 ±9.2e18：

1. `6 + hashValue * 2` 本身就可能**整数溢出** → Swift 溢出即 trap（SIGTRAP）；
2. 就算侥幸不溢出，`date(byAdding: .month, value: 4.6e18)` 返回 nil，而代码用了 `!`；
3. `10000 + Double(type.hashValue) * 5000` 同源 —— 默认里程会变成 4.6e19 km 这种数字。

它崩在**默认值**上，也就是「只要用户没自己存过提醒（绝大多数人），进那一档必崩」。

### 改法

`defaultReminders` 改成**确定的**：每型用它自己的周期表（`serviceIntervalMiles`），
上次 = 今天往前一个周期，下次 = 今天往后一个周期，里程从 0 起算 —— 不编数据、也不做会崩的计算。

同一类隐患一次清完（全是「上游一变就崩」）：

| 位置 | 原写法 | 现在 |
|---|---|---|
| `ServiceReminderManager.defaultReminders` | `6 + type.hashValue * 2` + `!` | 周期表 + `?? today` |
| `ServiceReminderManager.upcomingReminders` | `date(byAdding:)!` | **删掉**（全项目零调用 → 死代码，还带一个 trap） |
| `FamilyAndKeySharing.createKey` | `date(byAdding: days)!` | `?? Date()`：算不出来就发一把已过期的钥匙 |
| `InsuranceManager.expiringPolicies` | `date(byAdding: 60d)!` | `?? now`：宁可少报，不误报 |
| `SmartNotificationManager.checkServiceDue` | `date(byAdding: 7d)!` | `?? Date()`：窗口算不出来就不发 |
| `MileageJournalSection.totalThisMonth` | `date(from:)!` | `?? now` |
| `AN.stats` | `arr.min()! / arr.max()!` | `guard let mn = …, mx = …` |
| `AN` 四处电池极值 | `arr.isEmpty ? "--" : arr.min()!` ×4 | `extremeText(numberList(…))`（新助手，四份抄写收成一份） |
| `HistoryStore.record` 三处 | `x.last == nil \|\| … x.last!.t …` | `x.last.map { … } ?? true` |
| `AppStore.savePin` | `pin.data(using: .utf8)!` | `guard let … else { return }`（不存空 PIN） |
| `UpdateService` 两处 URL | `URL(string: …)!`，其中一处是**服务端返回的**字符串 | `guard let` + `throw` |
| `API.request` | `s.data(using: .utf8)!` | `?? Data()` |

### 把这一类交给 CI：`scan/traps.py`（第 18 项门禁）

编译期不报错、静态门禁原先也看不见、本地无 Xcode 更看不出来 —— 这类构造只能靠规则拦。
五条判据：`.hashValue` 出现在业务代码 · 日期构造后 `!` · **任何**调用结果 `)!` ·
`first/last/min/max` 后 `!` · `try!` / `as!`。

用真机报告里的原文验过：那两行命中①与②，而同源的 `hashValue` 里程行命中①；
改成 `?? today` / 周期表之后不再命中 —— 门禁不是摆设。

**还没被证明的那一步**：本次修复本身只经过静态门禁（18 项全绿），真机确认要重新装一轮 IPA。

---

## 免费账号能力的收尾（2026-09-23）

依据：Apple《Supported capabilities (iOS)》—— 那张表按 ADP / ADEP / Apple Developer（免费）
三档列出每个能力；同一页的注释里还写着：非 ADP 成员可以用 MapKit，**但不能提供路线导航**。

### 删掉

| 删了什么 | 为什么它用不了 | 代价 |
|---|---|---|
| `AppClip/` 整个 target（8 个文件） | 调用前提是 associated-domains 里的 `appclips:` 域 —— 那份 entitlement 上一轮已删；分发又只能走 App Store / TestFlight（均需付费）。它只能是一个「编译得动、但永远打不开」的 target | 少编 2 个文件 + 一个 target；`project.yml` 一段、工作流清单、7 个扫描器的引用同步清 |
| Info.plist 的 `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` | HealthKit 代码早删；而且 HealthKit 是要注册的能力。留着就是让系统为一个永远不会发生的权限准备文案 | 无 |
| Info.plist 的 `CKCloudKitEnabled` | CloudKit 同步那套代码早删 | 无 |

删 App Clip 时顺手清掉了 `scan/baseline` 之外的七个扫描器里对 CarPlay / AppClip 的残留引用 ——
它们的 docstring 还在说「扩展 target（Widgets / WatchApp / CarPlay / AppClip）」，
而 CarPlay 目录早已不存在：**文档跟代码对不上时，文档就是那句谎言。**

### 新增第 19 项门禁：`scan/paidcap.py`

这类东西的共同特征是「编译得过・门禁全绿・UI 上看得见入口・点下去永远拿不到东西」，
而且**后来的人会照着它继续写**。所以把它变成可执行的约束，四条判据：

| 判据 | 内容 |
|---|---|
| ① entitlements 键白名单 | 目前只准 `com.apple.security.application-groups` 一项 |
| ② Info.plist 禁键 | UIBackgroundModes / BGTaskScheduler / HealthKit 用途说明 / CKCloudKitEnabled / NSAppClip / aps-environment / weatherkit / icloud-* |
| ③ 源码禁 import 与禁 API | CloudKit・HealthKit・WeatherKit・StoreKit・PassKit・HomeKit・GameKit・NetworkExtension・SensorKit・MusicKit・CoreNFC・DeviceCheck・Sign in with Apple・FamilyControls/DeviceActivity/ManagedSettings・BGTaskScheduler，以及 APNs 注册、`CKContainer`、`HKHealthStore`、critical/time-sensitive 通知、内购、**`MKDirections`** |
| ④ target 白名单 | CarKeeper / WidgetBundle / WatchApp / WatchKitApp / CarKeeperTests；AppClip / CarPlay 不许回来 |

**它不是摆设**：注入探针（`aps-environment` + `com.apple.developer.healthkit` 两个 entitlement 键，
以及 `import CloudKit` / `CKContainer.default()` / `MKDirections.Request()` /
`registerForRemoteNotifications()`）一次全部被抓到，探针删除后立刻转绿。
第一次跑还被 `scan/baseline/` 误伤过 —— 那是**冻结的旧树快照**，不该被当前纪律追着改，
已在扫描范围里排除。

### 仍在用、且免费那一档拿不到的：App Group（唯一一项）

小组件 / Watch / 实时活动靠 `UserDefaults(suiteName: "group.com.you.CarKeeper")` 共用车况快照。
风险在于：免费账号在开发者后台**看不到 Identifiers 列表**，侧载工具重新签名时可能把这份
entitlement 摘掉。**所有读取点都带兜底**（`?? .standard` 或 `guard let … else`），
所以最坏情况是小组件显示占位数据，而不会崩 —— 这一点已由 `paidcap.py` 判据④守住。
如果要它真的显示真数据，需要付费会员；是否删掉这三个扩展，待真机侧载环境确认后决定。

---

## 小组件为什么「压根没得选」（2026-09-23，调查中）

真机反馈：**系统里根本没有可加的小组件**（不是显示占位，是列表里没这一项）。
先排除掉的那些：扩展的 `NSExtension` 声明是对的（只有
`com.apple.widgetkit-extension`，没有非法的 `NSExtensionPrincipalClass`）；
工程的依赖方向也对（`CarKeeper` 依赖 `WidgetBundle`，后者不依 App）。

可疑的是**打包与侧载之间的那一段**，而它以前在日志里是看不见的：

| 环节 | 事实 |
|---|---|
| CI 构建 | 全部 `CODE_SIGNING_ALLOWED=NO`，所以 `.appex` 是**未签名**的 |
| CI 打包 | 只做 `Payload/CarKeeper.app` + zip，**从不报告包里有什么** |
| 侧载 | 由用户的工具重新签名并注入 entitlements —— 嵌套扩展签不签是那一步的事 |

于是同一句「小组件没出现」对应两种**修法完全相反**的原因：

1. 包里有未签名的 `.appex`，侧载工具没处理嵌套扩展 → 换/配置工具即可；
2. 包里根本没有 `.appex`（XcodeGen 的 embed 没生效）→ 要改工程。

### 做的两件事

- **打包步骤改为会说话**：打完 IPA 就打印包内容 —— 顶层结构、`PlugIns/` 里每个
  `.appex` 的扩展点 / bundle id / 版本、它**签了没有**、App 自身签名与 entitlements、
  以及 IPA 里跟扩展/手表相关的条目。全程 `|| true`：它是体检，不是门禁。
  两个分支都用伪造的包验过（有 PlugIns / 没有 PlugIns）。
- **`scan/paths.py` 新增一条**：打包步骤必须打印包内容。否则「扩展有没有随包分发」
  又变回看不见的事实，而它的两种原因需要相反的行动。
  同时修了它自己的一个真 bug：**正则不跳注释** —— 我在注释里解释「为什么不用某种 for 写法」时，
  那句注释本身长成了那个写法，于是它报出一个叫 `...` 的 target。现在扫描前先删整行注释。
  反向自测：注释里的假清单被忽略，而真清单漏掉 `WatchKitApp` 仍然报红。

下一步就等下一轮 CI 日志里那段「IPA 内容体检」。它一出结论，就知道该改工程还是改侧载流程。

---

## CI 复红（2026-09-23 01:50）—— 12 个编译错误 + 一处「永远显示 0」

读完上一次推送的 CI 日志，红的原因是 12 个编译错误，而它们**全是上一轮我自己引入的**：

| 现象 | 真因 |
|---|---|
| `cannot find 'extremeText' / 'numberList' in scope`（Analysis.swift ×8） | 把四处 `arr.isEmpty ? "--" : arr.min()!` 收成助手时写成了**裸名字**。助手住在 `enum AN` 里，而调用点在**顶层函数** `batteryModel(_:)` 内 —— 越了作用域。改成 `AN.extremeText(AN.numberList(...))` |
| `HomeModeHead:186 cast ... always fails` | 诊断档那行「消息缓存 N 条」写的是 `ciVal(caches, "messages") as? [[String: Any]]`，而 `ciVal` 只返回 `[String: Any]?` —— 这个转换**恒失败**，于是该行永远是 0 条，看上去像「消息拉不到」，其实只是取错了形状（消息缓存存的是数组，`MessagesSection` 自己就是直接下标取的）。改为 `store.caches["messages"] as? [[String: Any]]` |
| `HomeModeHead:82/147 downcast ... does nothing`（警告） | `ciVal(...) as? [String: Any]` 是空转（返回值本来就是 `[String: Any]?`）。去掉 `as?` |

顺手做了同类扫描：`AN` 的所有成员（`stats` / `numberList` / `extremeText` / `barsOf` /
`summarize` / 四个状态常量）在 `AN` 体外是否还有裸调 —— 结论是没有别处。

### 同一份日志里的 AppIcon 警告：结论纠正

N 从 2 变 3 是这一轮造成的（往 `Contents.json` 里加了一条 `idiom: "ipad"` 的 76×76 1x）。
把四个提交的 JSON 组成与 CI 的 N 对齐之后，成因确定了：**被忽略的是 `idiom: "ipad"`
的条目，不是 1x 槽位**。判决点是 `ad02a88` —— 那一轮把三个 1x 全删，N 只从 3 变 2。
详见 `AppIcon-SPEC.md`。

处置：`Contents.json` 与磁盘都收到 **7 条 / 7 文件，全部 `idiom: "universal"` +
`platform: "ios"`**（1024 + 60@2x/3x + 29@2x/3x + 40@2x/3x）；两个生成脚本的槽位表
同步收窄，免得重新生成又把那五个没人引用的文件写回来。依据是 Apple 文档那句
「iOS, iPadOS, tvOS, and watchOS apps can auto-generate all icon variations from a
single 1024×1024 pixel image」。

预期下一轮 CI 的 N = 0 —— 这一条**只能由 CI 证实**，本地没有 Xcode。

### 新增第 19 项门禁 `scan/scopeguard.py`

那 8 个错误的成因值得写成规则：**名字在项目里、但在调用点不在作用域**。
`scan.py` 见到「项目内有这个声明」就放行，所以它看不见；能看见它的只有 10 倍计费的
macOS runner。判据只有一条：某个类型的 `static` 成员被跨类型裸调（没写 `类型.` 前缀）。

合法情形全部实测放行：调用点在该名字所属类型体内（含嵌套与外层）、文件顶层有同名声明、
项目里有同名全局函数、名字短于 6 个字符（太容易撞上局部变量与参数）。

双向都验过，不是摆设：注入探针（`enum ProbeOwner { static func probeHelper }` + 顶层函数
与另一个类型里的两个调用点）**两处都报**；删掉探针立刻转绿。它还先测出一个假阴性：
第一版把同文件内的静态成员当成「文件局部」，而事故恰好发生在同一个文件里
（`extremeText` 与调用点都在 Analysis.swift）—— 那样它会静默放行这起真实事故。
假阳性也修过一轮：`BatteryView` / `ControlView` 各自都有 `private func sectionLabel(...)`，
而 `sectionLabel` 同时是令牌类型的静态成员，第一版误报 9 处。

---

## 文案精简（2026-09-23）

界面上出现了大量「教学式说明」：把已经显示在屏幕上的东西再讲一遍、给空状态配一句比喻、
在页脚解释这个数字怎么算出来的。统一刀法，只动字面量、不动结构：

1. **删复述**：解释「这个按钮做什么」「点下面那个才会拨出去」这类句子，删净。
2. **删比喻**：「就没有光」「这里就会长出一条时间线」等换成直说或删除。
3. **页脚压成一句**：来源说明保留必要区分（电价是自填的、估算不是市场价、超时标为待确认），
   其余解释撤掉。
4. **页头副标题 ≤ 12 字**：「账号、车辆切换、数据与隐私、关于」→「账号、车辆、数据、关于」。
5. **搜索里的每档说明压成词组**：这一栏是各档的第二份目录，越短越好。

覆盖面：地图档（含光/天气那一段）、车辆、健康、电池、车控、行程与评分、消息、保养与钱、
我的、紧急求助、搜索、隐私与数据、主题画廊、登录、Siri 快捷指令、设计令牌页面，以及
`Services/` 下的保险与账本文案。地图样式与主题的「处境」说明也一并压短。

判据不是「字数」而是「删掉之后还看不看得懂」：保留具体事实（NOAA 不联网、梯形法积分、
`VehicleValuation.estimateValue` 里可改系数），删掉口气、比喻与重复。

改动只碰中文与说明性英文，未动任何键名、CSV 表头、故障码表（`ApiModels` 里那些是车端故障名原文）。
19 项静态门禁 + 风格检查 + 括号配平全绿。

---

## 查漏补缺（2026-09-23，收尾复查）

上一轮结束时留了几个没被验过的口子。逐个走一遍 —— 其中第一个是**真会挂编译**的。

### 1. `SkyLight.swift` 括号不配平（会挂编译）

`facts(at:)` 里少了一个右括号：`rows.append(SkyFact(...))` 只写了一层 `)`，
于是从那一行起，整个文件的深度永久停在 1，尾部多出一个悬空的 `}`。
它由 `scan.py` 的结构性检查报出（`括号不配平 (=136 )=135`）。
补上右括号后 `(=136 )=136`，`scan.py` 转绿。

这条值得记一笔：它是**括号配平这一整个人工检查类别**里唯一一条机器看得见、
而当时没人看的。`scan/_brackets.py` 本来就是干这个的，但它是一支临时脚本、
硬编码着一份包括已删 `BatteryView.swift` 在内的文件清单，从未接进 CI —— 于是它**自己成了
死代码**（真的跑不起来了：`FileNotFoundError` 指向那个已删文件）。本次已删除它。

覆盖面核过：`scan.py` 的结构性检查查的是 `()` / `[]` / `{}` 配平 + 字符串未闭合 +
`#if`/`#endif` 配平 —— `_brackets.py` 只做了其中的第一项，所以删掉它没有任何覆盖损失。

### 2. `.swiftlint.yml` 的排除清单整份是空转的（两个方向都错）

新增第 20 项门禁 `scan/lintcfg.py` 后查出：

| 方向 | 事实 |
|---|---|
| 基准错一层 | 清单写的是 `CarKeeper/CarKeeper/Design/DS.swift`，而配置住在 `CarKeeper/.swiftlint.yml`。SwiftLint 文档：included / excluded 按**配置文件所在目录**解析 —— 于是实际指向 `CarKeeper/CarKeeper/CarKeeper/Design/DS.swift`，五条全不存在。**这份清单从来没有排除过任何文件。** |
| 只减不增 | `CarKeeper/WatchApp` / `CarKeeper/Widgets` 随小组件删除后没清掉；而 `MapSpineView.swift` 长到 1126 行、越过 `file_length.error(1000)`，反倒没进清单。 |

处置不是把路径改对，而是**不再排除任何文件**：写进 `excluded` 会让整个文件退出 swiftlint
—— 退的不只是尺寸那条，还有 `force_unwrapping` / `implicitly_unwrapped_optional` 这些
真正防事故的规则。被排除的恰好是最大、最复杂的文件，用「关掉全部检查」换「少一条超长提示」，
代价与收益差得太远。改为把尺子调到与代码真实形状相符（`file_length` 1200、
`type_body_length` 1200、`function_body_length` 160，余量按当前最大值给），于是
**每个文件都被每一条规则检查**；越过阈值时由 `lintcfg.py` 在 Linux 上秒级拦下，
要求你「要么改小、要么把为什么该调说清」。

这条同时修掉一个隐性后果：`build.sh` 用的是 `swiftlint lint --strict`，warning 会被升级 ——
也就是本次改动之前，本机 `./build.sh` 的 lint 步是红的（11 个文件越过 500 行）。

### 3. 检查范围正在悄悄缩小：不存在的根目录由静默跳过变成硬失败

`futureproof` / `lexguard` / `shadowguard` 三个检查器都用
`Path(tk).rglob("*.swift")` 收集文件，而 `rglob` 对**不存在的目录不报错、只返回空**。
于是删除小组件 / 表盘 / App Clip / CarPlay / HealthKit 之后，它们的根目录清单里仍留着
`Shared` / `Widgets` / `WatchApp` / `HealthKit` 二十多项死路径，而输出依然是「0 个问题 ✅」。

新增 `scan/_roots.py`：列出来的根目录必须存在、且里面得有 .swift，否则直接失败。
三个检查器 + `copy.py` 的目录清单全部改走它（`copy.py` 的 `SHARED` / `WIDGETS` / `WATCH`
三项也一并清掉，并补上此前漏掉的 `CarKeeper/Models`）。覆盖范围核对无误：现在三个检查器
扫到的 71 个文件 = 全仓 Swift 文件总数。

`scan.py` 里同一形状的两处也修了：`APP` 清单里的 `HealthKit` / `Shared`，
以及**整个恒为 0 的 WIDGET 半边**（`Widgets` + `Shared` 两棵目录已不存在，
它从此只会打印「重复声明: 0 / 幽灵构造: 0」—— 一个恒为 0 的绿灯不是绿灯，
因为它让「检查过」与「没检查」无法区分）。`target_files` 也改成缺路径即失败。

### 4. 文案门禁接进 CI

`scan/copy.py` 上一轮写好但**没有进 CI 的 `for s in ...` 循环** —— 等于没接。
现在它与 `lintcfg.py` 一起进了门禁清单，共 21 项。

### 5. 文档里把已删东西写成现存的段落

逐条核过并改：`README.md` 的「功能移植对照」表里 5 个实现名（`HomeView` / `MessagesView` /
`HealthView` / `BatteryView` / `DataView`）**在原树里一个都不存在**，已改成真实入口
并补上「入口只有底部模式条」这条规则；`DESIGN-SPEC.md` 的 `充电页 (BatteryView)`、
`车况页 (HomeView)` 改成实际类型名；`DESIGN-UNIFY.md` 的跨 target 令牌表、
三个令牌文件表、以及「刻意保留为独立屏幕的三个」整节标注作废并写明现在的真相；
`API-FIELD-MAP.md` 行里的 `ChargeLedger`、`MAPKIT-FEASIBILITY.md` §4 表里三个已不存在的
文件路径，都改成「这是当时的记录，现在在哪」。

### 已核实上一轮确实落了地（不是漏）

- `HomeMode` 就是 6 档（现在 / 车辆 / 充电 / 车控 / 出行 / 我的），
  `destination(for:)` 把**每一个** `Deeplink` 都映射到「档 + 档内分段」，没有落空的分支。
- 合并页在磁盘上都在：`VehicleHubView` / `MineHubView` / `ChargeView` / `DestinationCalculatorView`。
  （2026-09-23 修正：前两个已在同一天被并掉 —— 见本文最后的「CI 报回来的三处」；
  当时这一行是真的，后来结构变了。）
- 小组件 / 表盘 / 实时活动三棵树、`Shared/`、三份 entitlements、`project.yml` 里的对应 target
  均已删除；`scan/targets.py` 与 `scan/paidcap.py` 都在守它们不回来。

21 项门禁（含新增的 `copy` 与 `lintcfg`）全绿；风格检查 0 问题；工作流 YAML 与内联 shell 语法通过。

---

## 编译红灯（2026-09-23，第 22 项门禁）

### 事故：一个空格，21 项门禁全绿

`GlobalSearchHUD.swift:86`：

```swift
message: searchText.isEmpty? "搜页面、车牌、行程、指令、充电记录。"
                              ^ 少一个空格
```

Swift 把 `isEmpty?` 读成**可选链**，于是这一行成了「对 `Bool` 做可选链、后面再接一个裸字符串」：

    error: expected ',' separator

这一行是「精简文案」那轮手工改三元时留下的 —— 原文是一句 `message: "..."`，
被拆成「空 / 非空」两种文案，拆的时候把空格丢了。

### 为什么 21 项一项都没拦住

它们没漏跑，是这一类**不在任何一项的判据里**：

| 已有的判据 | 为什么看不见 |
|---|---|
| `scan.py`：括号 / 引号 / `#if` 配平 | 这里三者**都是配平的** —— 少的是空格，不是符号 |
| `copy.py` / `lexguard.py`：词与句子 | 判据是「这句话该不该存在」，与运算符写法无关 |
| `futureproof` / `deep` / `logic` … | 查的是声明、调用、跨文件一致性，不看运算符 |

只有编译器看得见 —— 而编译器在 macOS runner 上（一轮 3 分钟，额度按 10 倍计）。
同一个事故 2026-09-22 已经在 `TripsEventsView` 的 `id:` 参数上发生过一次，
两次都是靠 CI 日志发现的。

### 新增第 22 项门禁：`scan/ternary.py`

判据只认「不可能合法」的形态，**不猜意图**：`?` 紧贴前一个 token、后面隔一段空白、
再接一个不可能是可选链的字符。合法写法逐条显式放行（`foo?.bar` / `foo?[0]` / `foo?(x)` /
`foo ?? "x"` / 类型可选后接 `= , ) ] } > & | : {` 或行尾 / `try?` `as?` / `-> String? in`）。

两个细节不写就会假阳性，所以都写进文件头了：

- **类型可选是最大的假阳性来源**：第一版把整棵树当输入，报出 96 条，其中 91 条是它在
  **行尾**的形态（`let x: Date?`、`var x: String? { nil }`）。行尾一律放行，只有下一行的
  第一个非空字符是字符串字面量时才报 —— 那个形态（`cond?` 换行接 `"文案"`）同样不可能是合法 Swift。
- **必须先抹掉字面量与注释**：一句中文提示里引用另一句话（`他说"这样?"`）完全正常，
  那不是代码。`code_only()` 逐个处理行注释 / 块注释 / 多行字符串（`"""`）/ 单行字符串，
  行号与列号保持不变。

**双向验证**：21 条探针（5 条该报、16 条该放行）全部符合预期 —— 含真事故那一行、
`a == b? "y" : "n"`、行尾 `?` 接字符串，以及类型可选 / 可选链 / 空合 / `try?` / `as?` /
`case let v?` / 字符串正文 / 注释 / 多行字符串。修好后全仓 71 个 .swift 零命中。

### 顺手补掉上一轮没补的那个缝：检查器「写了但没跑」

`paths.py` 原来只查一个方向（CI 点名的脚本在不在磁盘上），反方向没人管 ——
而 `copy.py` 正是从这个缝里漏掉的：文件在、判据写好了、所有输出全绿，
因为它根本不在那个 `for s in ...` 循环里。**「没跑」与「跑了没问题」在日志上长得一模一样。**

现在反过来要求：`scan/` 下每个 `.py` 要么出现在 CI 的检查器清单里，要么写进
`paths.py` 的 `CI_UNCOVERED_CHECKERS` 并写明理由。据此查出 `verify_eol.py` 一直是
「存在但从不运行」—— 读过之后它确实该留在外面：它是**提交前的人工比对工具**
（对比工作区与 HEAD、列出差异让人判断「这些是不是本轮有意改的」），
工作区与 HEAD 本来就该不一样，它没有通过/失败的判据。字节级的行尾检查由门禁 `eol.py` 负责。

**探针**：把 `ternary` 从工作流的循环里拿掉 → `paths.py` 立刻报
「scan/ternary.py 在磁盘上，但 CI 从不运行它」，还原后转绿。

### 验证与没被证明的一环

22 项门禁全绿（新增 `ternary`），风格检查 0 问题。

**仍然没被证明的是编译** —— 本地既没有 Xcode，也没有任何 Swift 工具链
（`swiftc` / `swift` 都不存在），所以这一行只能等 CI。这也正是为什么「只有编译器看得见」
的判据值得持续搬进静态门禁：每搬过来一条，就把一轮 macOS runner 的往返换成一次秒级检查。

---

## 相机式底部条 + 叠叠乐（原型 → Swift，本轮）

原型在 `design-preview/stack.html`（用户逐轮挑出来的那一版）。这一轮把它变成真机代码：

### 新增四个原语（全部在 `Design/`）

| 文件 | 它是什么 | 它为什么不能省 |
|---|---|---|
| `StackSpec.swift` | 七种叠法的全部数值 + `StackMath` 纯函数 | 同一个决定只能做一次。六页各写一遍，就会出现「出行页手感对、充电页不对」 |
| `GlassCard.swift` | 一张卡：系统液态玻璃 + 个性色一抹 + 标题行 | 卡**透**才叫叠。不透明的话错位多少看起来都是一摞纸 |
| `ArcStack.swift` | 自管手势的卡片栈：七种叠法 + 消失带 + 弹簧吸附 | 见下：`ScrollView` 的对齐基准与「卡顶停在消失带下沿」对不上 |
| `DSSwipeStrip.swift`（重写）| 静止三档 → 按下展开六档 + 玻璃透镜 | 旧版只有「定宽 + 中心放大」，没有展开这一层 |

### 三个必须先说清的取舍

**① 放弃 `ScrollView`，代价写在代码里。** 系统吸附以「卡片的边」为对齐基准，
与「卡顶停在消失带下沿」这条自定义阅读线对不上，所以改成自管手势。
**代价是没有三指滚动 —— VoiceOver 用户会完全无法翻页。**
因此容器上挂了两条动作：`.accessibilityAdjustableAction`（元素级上下轻扫）与
`.accessibilityScrollAction`（区域级三指扫）。这类缺失不会有任何报错提醒你，
所以它写进了 `scan.py` 白名单条目的理由里。
（修正：本节先前写的是 `.accessibilityAction(.scrollUp/.scrollDown)` —— 那两个成员
不存在，是 CI 报回来的第一处；详见本文最后的「CI 报回来的三处」。）

**② 条子静止只露三档是「条宽」造成的，不是屏幕不够宽。**
截图里第 4 档的头一个字母是被**条自己的圆角边**裁掉的。所以「手一滑就全显示」的
正确形态是**条向两侧长开**，而不是把间距压扁。这一条决定了整个几何。

**③ 玻璃的两处来源不同。** 卡与条用系统 `.glassEffect(_:in:)`（折射是物理材质，
四套艺术主题下自己去适配底色）；透镜用 `glassHighlight` 令牌。
把条子写成 `fillSubtle` 平涂也不难看，但那就退化成一块灰底，不再是「透镜」。

### 六页都改了，改法是同一句

`DSPaperPage { 巨字头; 发丝线; 内容 }` → `StackPageView(cards: [巨字头, …, 内容])`。
巨字头从「固定在纸顶」变成**那一叠的第一张卡**：旧版整屏一起滚，巨字会滚出去；
现在它可以被滑走，往后一拉还能拉回来。

- `HomeMode` 的 case 顺序改成 **出行 · 车辆 · ［现在］ · 充电 · 车控 · 我的** ——
  地图在正中。首页顶在最左边时，左边是空的，「静止露三档」看起来像「到头了」。
- 每页的个性色落进 `ArtThemeSpec.pageAccents`（四套主题各六色），
  所以**换主题时六页一起换**，而不是在页面里写死六个色。
- `DevView` 里多了「叠叠乐」一节 + 全屏对照页（`StackLabView`）：七种叠法在同一个窗口里
  切换，挑中哪一种会写进偏好，六页立刻跟着换（默认弧出）。

### 本轮修掉的三个真缺陷（都是先算出来才发现）

1. **滚轮的两分支写法会算出 `opacity > 1`。** `a > 70 ? … : 1 - (-a-70)/40` 在 a 为正时
   下面那一支恒大于 1。改成按 `|a|` 淡出 —— 淡出必须按**角度**而不是按「第几张」：
   卡片高度不一，按张数算会让高卡还在画面里就已经透了。
2. **模式条把「可用宽度」存成了 @State。** 于是它只会被测量那一次写对，
   在非 390pt 的机器上首帧的位置是按默认宽度算的。改成**全部几何由 `width` 参数推出**，
   另在绘制处夹一次合法范围 —— 派生量不会有陈旧值。
3. **`StackSpec.overscroll` 在重写时丢了，而 `StackMath.damped` 还在用它。**
   这是 `scan.py` 报出来的（「项目类型的未知成员」），不是我看出来的 ——
   它这次真的拦住了一个会挂编译的问题。

### 验证

22 项门禁全绿（`scan.py` 的白名单新增了 8 个 SDK 符号，每个都附 Apple 文档 decl）、
风格检查 0 问题、工作流 7 个内联 shell 块通过 `bash -n`。

**没被证明的仍然是编译**，另外还有三件只能等真机：
手势与系统返回手势的边缘冲突、自管弹簧与系统惯性的衔接手感、
以及「八张卡全在画面里」那种极端态的帧率。

### 收尾：性能开关、数据时刻、惯性交接（同日）

上一轮留下三处「做了但只做了一层」，三个都补上了。

**① 多张玻璃的性能（`ArcStack` + `GlassCard`）**
判定放在 `ArcStack.cardView`：`glassy: abs(tShape) < 0.9`。
阈值取 0.9 是因为消失带正好从那里开始明显变淡 ——
**材质切换必须发生在看不见的地方**，否则滑到一半会看到一张卡“闪”一下换了底。
关掉时走主题的 `TokensPalette.surface`，与玻璃**共用同一个 `RoundedRectangle`**，
所以轮廓不变。为此 `ArcStack.cards` 从 `[AnyView]` 改成未包装的 `[StackCard]` ——
提前包成 `AnyView` 的话，「这张卡离阅读线多远」就传不进卡的内部了，
玻璃的开关会退化成一个常量。

**② 三态的最后一层 —— 数据时刻（`AppStore.cacheTimes`）**
「无数据」原本就在（`GlassCardEmpty`），缺的是「这份读数是什么时候的」。
补法是**给数据源盖时刻**，不是给卡片盖时刻：键与 `caches` 相同，
唯一的写入点是 `saveCache`（它也是 `caches` 唯一的写入点）；
值为空时**同时清掉时刻** —— 留着一个时间戳而值是空的，会让卡片显示
“有数据但很久没更新”，而真实情况是「这次没取到」，那是两种不同的状态。
它**不是 TTL**：不过期、不落盘、不拦请求。
调用点是「带读数的那几张卡」：充电页四张同源（`charge`）、出行页汇总（`messages`）、
车辆页档案与车控页车身（`control`）。
**故意不给**纯动作卡与纯设置卡（指令 / 一键场景 / 快捷指令 / 设置 / 关于）——
它们没有会过期的数值，挂一个时间反而是噪音。
「我的」页整页没有时间戳：那一页的车辆信息来自登录后的资料，不在 `caches` 里。

**③ 惯性交接（`StackSpec.settle(velocity:)`）**
`initialVelocity` 要的是「占剩余路程的倍数 / 秒」，所以传峰值速度 ÷ 剩余距离，
**上限 ±8**（手势里那一帧的峰值可能极大，不封顶会甩到天上）。
“阈值”取「剩余距离 > 1pt 才给」——接近 0 时会放大成无穷。
速度取的是**这一段手势的峰值**而不是最后一帧：滚动收尾那几帧本来就几乎不动，
最后一帧算出来恒为 0，于是「甩出去再翻一张」这条规则永远不会触发。

这一轮没有新增门禁，也没有新增 SDK 符号（用的都是已登记的 API）。

---

## CI 报回来的三处（2026-09-23，`6606a43` 的构建日志）

第一次拿到编译器的判决：**门禁全绿，CI 报三处错**。逐条说完 ——
三处都不是「手滑」，而是三种不同的机制失效。

### ① `AccessibilityActionKind` 没有 `.scrollUp` / `.scrollDown`

```
ArcStack.swift:85:35: error: type 'AccessibilityActionKind' has no member 'scrollUp'
```

这两个成员不存在：`AccessibilityActionKind` 只有
`default / delete / escape / magicTap / showMenu`（Apple 文档 JSON 的 topicSections）。

**真正的原因不是打错一个名字，而是白名单里的一句话被当成了证据。**
当时 `scan.py` 的 `VERIFIED_SDK_ADDITIONS` 里写着
「`.scrollUp / .scrollDown` 为 `AccessibilityActionKind` 的静态成员」——
那句话是上一轮写进去的，而**门禁的判据只有「名字在不在表里」**
（`accessibilityAction` 确实存在 → 整条调用放行），从没有任何东西去检查
**白名单里的说法对不对**。于是那份说明反过来成了「已经核实过」的证据。

修法两层：

- 代码改用两条真 API，每条都对着 Apple 文档 JSON 核过 decl 与 externalID：
  `.accessibilityAdjustableAction`（元素级：焦点在这叠纸上时上下轻扫 = 上一张 / 下一张）+
  `.accessibilityScrollAction`（区域级三指扫，收 `Edge`，扫向底边即下一张）。
- 白名单那条说明重写，并**把这次事故写进条目的理由里**：
  白名单里的一句话也是断言，它得自己带着出处。

### ② 新增 `scan/enumguard.py`：SDK 枚举成员不许凭印象拼

`scan.py` 的「未知成员」判据只看**项目自己声明的类型**（`Foo.bar`），
点号前缀的枚举简写（`.scrollUp`）从头到尾没人看过 —— 这类错只有编译器看得见，
而编译器在 macOS runner 上，一轮 3 分钟（额度按 10 倍计）。

新门禁是**表驱动**的，只认两种写法 ——「`(` 后面紧跟 `.成员`」与「表里声明了标签的
`标签: .成员`」（命名动作、传变量、传 `nil`、无实参一律放行），
表里每一行都必须带 Apple 文档 URL：

| 调用族 | 参数类型 | 已核成员（出处见文件内） |
|---|---|---|
| `accessibilityAction` | `AccessibilityActionKind` | default / delete / escape / magicTap / showMenu |
| `textCase` | `Text.Case` | lowercase / uppercase |
| `accessibilityElement(children:)` | `AccessibilityChildBehavior` | combine / contain / ignore |
| `scrollBounceBehavior` | `ScrollBounceBehavior` | automatic / always / basedOnSize |

带标签那一族的标签本身也在表里（`arg: "children"`）—— 不限制标签的话，
`.foo(title: .bar)` 这种到处都有的写法会被大量误判。

它**自己也能失败**（门禁不能只是一段日志）：拿 `.scrollUp`、`.CamelCase`、
`children: .everything`、`.sometimes` 试过，四处都抓到；合法成员、无实参形态、
注释里写的 `.scrollUp` 都不误报（先抹掉注释与字符串再扫）；
空表直接按失败退出（「范围为零」与「没问题」不能长得一样）。
已加进工作流的门禁清单，现共 24 项。

顺便把这一轮新写的代码里**所有** SDK 枚举简写逐条过了一遍（98 种，
含 `GraphicsContext.Filter.blur`、`GridItem(.flexible())`、`ScrollBounceBehavior` 等）——
除已修的那一处外没有第二个凭印象拼的名字。

### ③ `instance member 'sectionCards' cannot be used on type 'VehicleView'`

```
VehicleHubView.swift:51: error: instance member 'sectionCards' cannot be used on type 'VehicleView'
MineHubView.swift:40:  error: instance member 'sectionCards' cannot be used on type 'MineView'
```

这一处比前两处重，因为它不只是编译错 —— **那个结构从第一天起就是错的**：
分段的控件与卡表住在外壳（`VehicleHubView` / `MineHubView`），
而这一段的**状态**（维保照片与照片选择器、OTA 状态与令牌）住在页面里。
外壳想拿页面的卡表，只能当类型成员调（编译不过）；就算绕过去，
那些 `@State` 也**永远不会被安装**（页面根本没被渲染）——
「维保照片」会变成一个点了没反应的按钮。一个页面只能有一个所有者。

修法是**把外壳并掉**，而不是给外壳开后门：

- `VehicleView` / `MineView` 自己拥有巨字头 → 分段控件 → 本段卡表这一叠，
  并自己消费深链的段落提示（`consumeHint()`）；
- `MapSpineView.pageContent(_:)` 的两个 case 改成页面本身；
- `VehicleHubView.swift` / `MineHubView.swift` 删除（两个文件各 62 / 50 行，
  合并后没有第二处卡表，也没有第二处 `switch tab`）；
- `sectionCards` 收成 `private` —— 它按当下的读数现算，外部**调不到**
  （让「instance member 当类型成员用」这一类错在结构上不可能再发生）。

### 这一轮之后仍然只能靠 CI 回答的

编译。这台机器上没有 Xcode、也没有任何 Swift 工具链，所以：

- `scan.py`（含新登记的两个 SDK 方法名）、风格检查、工作流内联 shell 的 `bash -n`
  与改动文件的括号配平都已全绿；
- 但**新写的两只闭包**（`accessibilityAdjustableAction` / `accessibilityScrollAction`
  的闭包形状）与**删掉两个视图文件后的引用**只有编译器能盖章。
  这一轮的改动面比上一轮小得多（三个错误点 + 一次结构合并），
  所以「一次就绿」的概率比上一轮高 —— 但那是概率，不是保证。


---

## 首页按原型重排（2026-09-23 晚）—— 「你并没有按 html 预览图做」

这一轮不改功能，只改**结构**：把 `MapSpineView` 的「现在」档逐项对回
`design-preview/stack.html` 的 `pageNow()`。对照表见 `PROTOTYPE-TO-SWIFTUI.md`。

### 改了什么

- **顶栏收掉**：`.toolbar(.hidden, for: .navigationBar)`（只对「现在」这一档）。
  原型把地图一直画到屏幕最上沿；而原来那三枚钮（刷新 / 搜索 / 回到车）
  还长在**六页每一页**上 —— 那本身就是第二个入口（搜索在条子右臂已经有了）。
- **浮动卡从三张收到两张**：现状卡（头 =「当前位置 + 上报多久了」，正文 = 地址 → 巨字续航 →
  副行 → 光带 → 四轮胎压）+ 四格读数（车速 / 电量 / 胎压 / 车锁，奇偶错开 7px）。
  原来的「图层选择卡」与「常驻操作条」不再占位。
- **多出来的四样收进车牌徽标的菜单**：四个图层（当前那层带勾）/ 重取数据 / 此刻的光 /
  回到车（iPad 上再加新车况窗口）。菜单长在原型本来就有的那个位置（`plate`）。
- **罗盘补上**（`MapCompass()`），与比例尺一起 —— 原型里这两件都在。
- **删掉 `Features/Map/MapQuickBar.swift`**：四个动作与验 PIN / FaceID 在车控那一档
  一模一样地存在（同一套 `CommandCenter`）。
- **巨字头卡补上页面名**（`StackCard(title: mode.title)`）：原型的每页首卡都有一行 `.ct`
  标出它是什么（`Trips · 今天` / `Charge · 电池`），没有它，首卡就是一行没有出处的巨字。
- **底条补上圆角裁切**（`.clipShape(RoundedRectangle(cornerRadius: barHeight * 0.31))`）：
  原型 `.strip{overflow:hidden}`。少了它，半压在条边上的那个字会漏到条外，
  「静止只露三档」这个形态就被破掉了。

### 这一轮自查出的一处**真编译错**

`layerChips` 里写着 `Image(safeSymbol: l.iconName, ...)`，而 `MapSpineLayer`
**没有** `iconName` 这个成员（它的注释里明确写着「这里曾经有一个 `icon`……留一个没人用的
图标表，下一个人就会以为模式条是该带图标的」）。它能躲过 24 项门禁，是因为
`scan.py` 的「未知成员」判据只看得懂**显式类型**的成员访问，看不出
`ForEach(...) { l in l.iconName }` 里 `l` 的推断类型。这一条只有编译器能拦 ——
也就是说：`0637fbc` 那次构建**根本没编过**，用户看到的很可能是更早的一个包。
那张卡已经随这次重排删除，这个错随之消失。

### 门禁

24 项全绿、`check_style.js` 0 问题、改动文件括号配平；`scan.py` 两种跑法
（本机 `scan/baseline/` 现场分析 / CI 用提交进仓库的 `baseline_cache.json`）都绿。
新增登记 3 个 SDK 名字，每个都对着 Apple 文档 JSON 核过：
`GeometryProxy`（一直在用，只是两种跑法认得不一样）、
`MapCompass`（iOS 17+，`externalID s:15_MapKit_SwiftUI0A7CompassV`）、
`toolbar`（iOS 16+，`externalID s:7SwiftUI4ViewPAAE7toolbar_3forQrAA10VisibilityO_AA16ToolbarPlacementVdtF`；
⚠️ 文档里 `renamed: toolbarVisibility(_:for:)`、`deprecatedAt: 27.2` ——
本项目的 iPhoneOS26.5 SDK 下不产生弃用警告，升到 27.2 之后要改用新名）。

### 仍然只有真机能答的

编译（这台机器没有 Swift 工具链）与手感：菜单嵌在地图上点开是否跟手、
两卡在真实 390pt 下的高度是否恰好不压到条子、其余五档那条空标题的导航栏看着是否别扭。

### 收尾补的三件（同一轮内）

**① 你装的那一版里根本没有这些改动。** 这一轮的所有结构改动都还在工作区 ——
`0637fbc` 之前那一版的地图页是 `bottomPanel(d, cardHeight: geo.size.height * 0.56)`：
一张 **56% 高的纸**贴在屏幕下方、条子长在**纸里**、纸顶有一根抓手。
原型不是这个形状（六页各占一整屏、条子绝对定位在离底 26pt、悬在内容之上）。
所以「结构不是」是对的 —— 那份结构从来没被推上去过。

**② 底图之上补回原型的两层压暗**（`.maptop{height:240px}` + `.mapvig{inset:0}`）。
它们是**结构**而不是装饰：没有顶上那层，浅色底图上白车牌会直接淹掉（车牌是这一屏
唯一的身份）；四角那层把视线收到车上。两者都取 `TokensPalette.scrim` ——
令牌的说明里本来就写着它「也用于光照不到的暗角」，纸主题下这块遮罩是墨不是黑。

**③ `MapSpineView` 拆出 `MapSpineLayers.swift`。** 三个图层内容（行程 / 停车 / 充电）
本来就是另一种关切：骨架管「这一屏长什么样」，内容管「图上在看哪个问题时写什么」。
拆的直接触发是 `scan/lintcfg.py`：结构重排后主文件 1206 行，越过 `file_length` 的
1200 阈值。**没有去调阈值**（那正是这条门禁在防的事：清单只减不增），而是把 117 行
挪走 —— 主文件回到 1092 行，离阈值有余量。代价是三个成员不能是 `private`
（`nav` / `chargers` / `emptyNotice`），三处都写了原因。

### 一处已知的代价，不改是因为改了更糟

原型「六页同时活着」是 DOM 意义上的便宜（六个 div，每帧只改 `opacity/transform`）。
SwiftUI 里它是**真的六页**：六棵视图树、六叠卡、五个页面的 `.task` 在启动时一起跑。
试过只实例化「可见的那几页」（`a < 0.62`），但那会把页面的 `@State` 一起销毁 ——
在充电页滑到第三张卡、去车辆页、再回来会回到第一张，而原型里 DOM 一直活着、
状态是留着的。**忠实于原型 = 保留状态；省算力 = 丢状态**，这里选了前者，
并且把它写下来：如果真机上换档发涩，第一个该看的是这里，不是玻璃材质。

---

## CI 补修（2026-09-23 深夜，`2f088df` 之后）—— `onExpand` 断线

结构重排的 CI 只报了一处错：`MapSpineView.swift:403` 的 `extra trailing closure`。
调用点给 `DSSwipeStrip` 传了 `onExpand:`，而重写后的条子**没有这个参数** ——
重写时把展开做成了条子自己的行为，但两臂让位还挂在这个不存在的回调上。
两套手势知识没有对齐：调用点是旧参数表写的，条子是新参数表写的。

**修法是让条子把这条生命周期自己长全**（`onExpand: ((Bool) -> Void)?`，单向通知）：

- 按下（`cBase == nil` 那一帧）→ 展开 + `onExpand(true)`
- 松手后**拖过**的 → 620ms 收回（原型 `setTimeout(..., 620)`，给眼睛时间看清划过哪些档）
- **没动过**（纯点按）→ 立即收回（原型 `else this.targetExpand = 0`）
- 计时器带代号：生效前手指若已回到条子上就作废 —— 原型 `if(!this.dragging)` 那一句。
  没有它，快速连按两下会被旧计时器把第二次展开收走。

调用点同时把尾随闭包改成**显式标签**：两个闭包参数并存时，尾随闭包靠扫描规则匹配，
读的人要翻定义才知道 `{ pos in }` 落在哪个参数上 —— 这次 CI 红的正是这条规则失效的形态
（传参时引用了一个不存在的标签，编译器立刻看得见）。

`expand > 0.35` 才让两臂开让（原型 `render()` 里的同一阈值）：按下瞬间条子还没长开，
两臂不用抢跑。

---

## 条子几何 / 两端停法 / 去暗层（2026-09-24，用户四条）

这一轮的四条里，有三条的真病根是**同一类错**：一个「被布局挤压后的值」
或一个「从没被赋过值的状态量」被当成了几何输入。

### ① 静止时对不上、透镜压住邻档（用户第 4 条）

`DSSwipeStrip` 的几何全由宽度推出，而那个宽度此前是**条子自己量自己**得的 ——
量到的是「HStack 分给它的那一份」：390 的屏上，两枚 50 的圆钮 + 两条 9 的中缝之后
只剩 256。于是 `gap(for:)` 认为六档装不下，把间距压到 6：

- 静止条宽算出 148（应为 190），三档挤成一团 ——「静止时对不上」；
- 节距 40 < 透镜宽 68 —— **透镜压住左右两档的字**（「选中的边框压住其他俩边」）。

现在宽度由外壳量整行得出（`MapSpineView.barRowWidth`：`.background` 里的
`GeometryReader` 量，不参与布局），条子自己的 frame 就等于算出来的条宽 ——
它不再是被挤压的弹性视图，几何与渲染因此不可能两套。
透镜宽度另按**节距**封顶（`pillWidth`）：屏幕窄到要压间距时，透镜跟着缩。

### ② 右臂：搜索 → 快捷车控（同第 4 条）

全局搜索整体从项目移除：`GlobalSearchHUD.swift`（删除）、`NavState.showSearch`、
外壳的 `fullScreenCover`、「我的」里那一行。它在结构上本来就是最弱的一个入口 ——
功能目录归底部模式条，搜索页是第二份目录，而且没有任何一条**只能**从它到达的功能。

那一格不空着，也不放第二个「去别处」的入口：相机那条右臂本来就是**动作**
（切换镜头），所以这里接的也是动作 —— 锁车 / 解锁 / 闪灯 / 鸣笛 / 远程寻车。
指令名与车控页（`ControlView` 的 `hero` / `moreCommands`）**同一批 key**，不另造一套；
成败都 toast（遥控制的提示不能只报喜）。

### ③ 两端：第一张不离开顶、最后一张不离开底（第 3 条）

先修一个从第一版起就在的错：`ArcStack.shapeScroll`（形变用的位移）
**从来没被赋过值**（恒为 0），于是淡出 / 缩放 / 玻璃 / 可否点击读的是
`targets[i] − 0` = 「这张卡离第一张多远」，而不是「它离阅读线多远」——
停在阅读线上的第四张卡透明度只有 0.68、缩到 0.9，而且因为 0.9 那个阈值**点不动**。
现在它由 `dragTo` / `settleTo` 跟着 `scroll` 走（位置立刻跟手，形变慢半拍，
落点共用同一条弹簧 —— 原型 `_smO` 与 `lagK = 0.16 / 0.34` 就是这件事）。

然后是可滚范围的两端（`ArcStack.endScroll`）：

- 首端 = 首卡顶边落在可见区上沿（`padTop` 本来就是按 `focusTop` 定的，这一端一直是对的）；
- 末端 = **末卡底边落在可见区下沿**。末卡因此不停在阅读线上（比它低），底下不留一大片空；
  末卡比可见区还高时，这个值**大于**「它吸在阅读线上」的位置 —— 多出来那一段
  就是为了把它的下半截也读得到，而不是永远被淡出带吃掉。

松手能停的位置随之变成「每一张的阅读线 + 末端那一个」（`restPoints`）：
走不到的那些落点不再留在清单里，否则松手会往一个够不着的地方弹。

### ④ 全局不要加暗层（第 1 条）

删的是**暗角**这一层，不是光：`SkyOverlay` 的 vignette（根画布与地图上都在用，
夜里 0.62、白天 0.14）与地图页的 `.mapvig` 一并去掉；地图顶上那层（`.maptop`）
从 0.72 收到 0.38、高度 240 → 200 —— 它留着不是为了好看，是因为浅色底图上白车牌
会直接淹掉（车牌是这一屏唯一的身份）。

上一轮「补回原型两层压暗」那条就此作废：它的理由是「结构不是装饰」，
而这一轮的规则更硬 —— **四角压暗不回答任何问题**（光池回答光从哪来、
颗粒回答雾 / 雨 / 湿，暗角只是同一束光被当成变暗的理由）。
`SkyLight.vignette` 这个读数留在光模型里（它是算出来的物理量），界面不再画它。

### ⑤ 地图页的玻璃卡（第 2 条）

这一条本轮**没动**浮动两卡与四格读数的版式：它们是原型 `pageNow()` 逐项量下来的
（`nowCard` + `readoutChips`，四格奇偶错开 7px 也是原型的），动它会同时动掉
「精致」的基准。它是约束而不是改动：底条这一轮的改动不许扰动那两张卡 ——
两臂与条子都长在屏幕最下沿那一行里，卡片窗的上沿一点没动。

### 仍然只有真机能答的

手感：静止形态是否真的对齐、透镜与邻档的间距、末卡停在底部时跟前一张的
间距是否自然、六页同屏在换档时的开销（上一轮写明的那个代价）。

### CI 与一条新门禁（2026-09-24）

这一轮的 CI 只报了一种错：`ArcStack` 的 `shapeScroll` 声明在重写它的注释时被写没了，
而三处使用还在（146 / 299 / 309）。它与上一轮的 `pvValue` 是**同一类**：
名字在旧版本里明明声明过，这一轮把它连同注释一起重写了，调用还在 ——
既有的检查器一个都看不见（`scan.py` 把它当成「SDK 提供的」，`scopeguard.py` 只管
静态成员越作用域，`orphans.py` 看的是反方向），能看见它的只有按 10 倍计费的 macOS runner。

于是新增 `scan/delguard.py`（已接进 CI 的静态门）：比「旧版本 vs 新版本」，
报出「旧版本里成员级声明过、新版本里没有声明了、代码里还在用」的名字。
两条判据之外只加一道降噪：名字在新版本的**其它文件**里被成员级声明就不报
（`2f088df` 把三个图层内容从 `MapSpineView` 挪进 `MapSpineLayers`，那种情况编译得过）。

它的探针就是真事故：拿历史 20 笔提交逐对比过，只报 785344b（`shapeScroll`）
与 17f00f1（`pvValue`）两笔，行号与 CI 日志逐行一致，没有任何误报。
（CI 的静态门 checkout 因此改成 `fetch-depth: 2` —— 拿不到 `HEAD~1` 时它会静默退回 `HEAD`，
而 CI 的工作区就是 `HEAD`，那就是一个恒为 0 的绿灯。）

## 暗层删净 / 地图页瘦身 / 全局精致度（2026-09-24 第二轮）

用户四条：① 全局不要加暗层（「你只删了地图页的，其他页面的也删」）
② 地图页内部下面 4 个按钮要规整 ③ 地图页顶部信息挪到下面的玻璃卡片
④ 全部页面检查精致度。

### ① 上一轮删的是「暗角」，这一轮删的是「顶部压暗」—— 而后者才是罩住每一屏的那一层

上一轮删掉的是 `SkyOverlay` 的 vignette（四角径向暗角，夜里 0.62）与地图页 `.mapvig`。
用户回来看的是**其他页面**，那就是还有一层长在主屏之外。

真正的位置是 `SkyOverlay.haze`：它里面除了那团暖雾，还有一条「顶部压暗」——
`canvasColor` 从 0.46 淡到 0，占上半屏。而 `haze` 是根画布 `AppCanvas` 的一部分
（`Design/Theme.swift`），也就是**每一屏**（六档，以及浮层背后的 `SheetCanvas`）的顶上
都被压了一次。它当时的理由是「让顶栏的药丸在图上读得清」，而顶栏早就不是浮字 ——
它是玻璃（`GlassCard` 自己的面 + 描边）。一条占半屏的压暗去服务一个已经有底的控件，
是纯亮度损失：删。

地图页最后剩的那层（`mapDims`，原型 `.maptop`，0.38 → 0，200pt）跟着一起删 ——
它服务的另一件事（车牌徽标压在瓦片上读得出来）也在同一条要求里失效了（见 ③）。

保留的是**地图自身的蒙版**（`MapStyleSpec.scrim × scrimOpacity`）：它不是装饰性的暗层，
而是「系统瓦片长不出纸与墨」时唯一的打折方案（纸 0.30 / 夜曲 0.55 / 原生 0）。
删掉它，纸主题的地图会变回系统地图 —— 那是另一个问题，这一轮不动。

### ② 四格读数：删掉原型那手奇偶错位

`.chip:nth-child(odd){translateY(-7px)}` 照搬到真机上，用户读出来只是「歪歪扭扭」。
四格现在同高、同宽、同一基线，行里不摆任何偏移（`readoutCell` 不再收 `offset` 参数，
`ForEach` 也不再需要下标）。

### ③ 顶部信息进玻璃卡

车牌 + 状态 + 上报时间搬进浮动首卡的卡头（`nowHead`），徽标菜单变成卡头上那枚图层胶囊
（`layerMenu`）。胶囊比齿轮图标好认：它写着当前在看哪一层。地图上因此只剩地名
（自带 textShadow，不吃整屏亮度）与地图自己的仪表（罗盘 / 比例尺）。

### ④ 精致度 pass：一页之内，一个事实只有一个出处

这一轮统一了三条**可判定的**规则，并把违反它们的四处全部改掉：

1. **头卡只给一个事实。** `HomeModeHead` 的「依据行」（三行键值）删掉。
   它们逐条都在紧跟着的那张卡里再说一遍：车辆档的头写「车牌 / 车架号 / 保险」，
   紧跟的「身份」卡就是这三样；充电档写「充电 / 电压电流 / 电池温度」，
   紧跟的「此刻」卡正好是同一组。删掉之后头卡就是这一页的**标题**
   （巨字 + 一行小字），依据在下面每一张卡里。
2. **同一个数不在同一页出现两次。** 充电「此刻」卡里那个 116pt 巨字电量，
   与头卡的主角是同一个 `68%` → 删；卡的正文也不再重复卡头值（充电状态已经是
   `StackCard.value`），只留上面都没有的：告警。
3. **卡头已经写了标题，正文不再写第二个标题。** 删掉四处卡内 `DSSectionHeader`：
   车辆「身份」卡里的「车辆」、充电「趋势」卡里的「趋势」（它的 `trailing`
   「车端采样」搬到卡头值）、出行「常停之地」卡里的「常来之地」（同一个东西两个名字）、
   评分卡里的「驾驶评分」。

### 仍然只有真机能答的

① 暗层删干净之后，浅色底图上的**地名**与地图仪表够不够读；
② 头卡瘦身之后，第一张卡的高度是否还撑得起「一条事实」的分量；
③ 四格规整之后与浮动首卡之间的 12pt 是否显得挤。

### 门禁

`scan.py`（24 项：未知成员 0 / 幽灵构造 0）、`enumguard.py`、`delguard.py`、`check_style.js`
全绿；本轮 7 个改动文件的括号配平自查（去掉字符串与注释后计 `{}` / `()`）全部 ±0。

## 车控那道门 / 相机条 / 叠叠乐手感 / 地图信息精简（2026-09-24 第三轮）

用户五条 + 三张相机截图。

### ① 右下角的控车不过门（用户第一条）

真事，而且根因值得记下来：车控档 `onCmd` 走 温度 → 生物识别 → 控车码 三步；
地图右臂直接调 `AppStore.sendControlCommand` —— 它从 Keychain 取出上一次存的控车码就发了。
同一个动作两套强度，安全的那条因此形同虚设（而且两处谁也不知道对方漏了什么）。

修法不是给地图再写一遍三步（那样就有两份，下次改一份又漏一份），
而是把这道门抽出来：`ControlCommandFlow`（新文件）。发起处只写
`request = ControlRequest(key:name:)`，温度、生物识别、控车码、下发全在门里。
挂它的两处：`ControlView`（指令与预设场景）与 `MapSpineView`（右臂快捷车控）。

刻意不过门的一条：`UpCarCondition`（刷新车况）—— 它不改车的任何状态，
只是把车端叫醒一次。门的成本是用户手输控车码，这份成本只该收在会改变车状态的动作上。
（把刷新也纳入，结果只会是用户干脆不刷新。）

顺手清掉两处死东西：`ControlView.tempDisplayCount`（写了从不读）、
以及那三个 sheet + 一个遮罩共 60 行（它们已经是门里的第①②③步）。

### ② 地图页信息重复（第二条）—— 一页一个事实只有一个出处（上一轮那条规则的延续）

「电量 68%」在这一页上说了**三遍**：副行文字、光带（形状）、四格里的「电量」；
「胎压」说了**两遍**：卡里四轮逐条 + 四格里的「最低那一条」。

处理：卡里删掉字号最小的那遍文字与四轮逐条。四轮细节在「车辆 → 体检」，
而四格那一格本来就取最低那条、报警也同样是 error 色 —— 所以没丢掉「哪一轮危险」
（这是删得干净的前提）。四格仍是四个一哩读数：车速 / 电量 / 胎压 / 车锁。

### ③ 末卡离页底太远（第三条）

可滚范围的末端就是消失带的上沿（`ArcStack.endScroll`），所以 `.arc.fadeBottom` 的 140
直接就是「滑到底时，末卡底边距卡片窗下沿 140pt」—— 一个手掌高的空白。收到 44。

### ④ 底部导航照相机截图改（第四条）

三张截图里能读出来的形态：外轨是**胶囊**、选中格也是**胶囊**（住在轨道里）、
选中那一档的字是**强调色**，未选中的是正文色 —— 相机用颜色而不是字重标出当前档。

于是 `DSSwipeStrip` 改三处：条子与选中格从圆角矩形换成 `Capsule()`；
标签的遮罩跟着换成胶囊（不换的话，半压在条端的字会从圆角外面漏出来）；
选中字色换成 `TokensPalette.accent`（四套主题下都读得出：夜光醏、纸上墨红、巨字近白、原生系统蓝）。
左边的车牌圆钮与右边的快捷车控圆钮本来就是相机那条 `.bottom` 的两臂，没有动。

### ⑤ 叠叠乐：吸附减弱、卡片大小差异减小（第五条）

四个数，全部在 `StackSpec`（连着「为什么」一起写在原处）：
`directionBias` 0.85 → 1.0（吸附临界点从 47% 移到正好一半）、
`flingVelocity` 550 → 900（普通滑动不再多跳一格）、
`settle` 弹簧 180/18 → 130/16（「被吸过去」→「滑过去」）、
`.arc.shrink` 0.07 → 0.03（最远只缩到 0.955，原来 0.895）。

### 仍然只有真机能答的

① 四格与浮动首卡的实际间距是否显得挤；② 六档展开时，选中胶囊还留不留得住呼吸位；
③ `fadeBottom = 44` 在不算高的机型上会不会让末卡贴得太紧。

### 门禁

`scan.py` / `enumguard.py` / `delguard.py` / `orphans.py` / `check_style.js` 全绿；
本轮 5 个改动文件的括号配平 ±0（新文件 `ControlCommandFlow.swift` 也在内）。

## 消息接口为什么「拿不到数据」（2026-09-24 第四轮）

用户：「现在重点查 为什么 消息接口拿不到数据，这是完全可以拿到数据啊」，
后面附了一份真抓包 —— `pageReceiverInfoByTime` 用一个 7 天窗口返回了 **55 条**事件。

### 根因：我们只要最近 7 天

接口没问题、token 没问题、解析没问题 —— 问题在**区间**：`messagesURL()` 从第一版起
default 就是「now − 7 天 → now」。车两天没开还能看到东西，三周没开就一条都不剩。
而「车的事件」与「由消息配出来的行程」本来就是**历史**视图
（出行页还专门有「更早」那一档分组）。用户手里那份抓包的事件是 9 月 3–4 日的，
而他提问当天（9/24）的 7 天窗口里什么都没有 —— 界面上表现为「接口拿不到数据」。

### 修法：往回切四段 7 天，而不是发一个 28 天的窗口

关键判断：我们**只验证过一种请求形状**，就是抓包里那一次（`startTime` 到 `endTime`
相隔 7 天）。服务端对更长的区间是接受、截断还是返回空，**没有任何证据** ——
而「窗口太小」与「窗口太大」在界面上完全一样（都是 0 条）。所以不赌：
把时间往回切成四段同样形状的请求、并行发出，再按 `stubId` 去重合并，
按 `createdAt` 新 → 旧（那个格式的字典序就是时间序）。

两份纯函数因此可以脱离真机被核对：`APIClient.messageWindows(weeks:now:)` 与
`APIClient.mergeMessages(_:)` —— `PureLogicTests.MessageWindowTests` 守五条：
窗口首尾相接不断档、week ≤ 0 也至少给一段、去重与倒序、缺 id 的行照收且缺时间的排最后、
合并后有上限（四周可能上千条，而那一节不是惰性列表）。

**不翻页**：文档里那条 `page`/`last` 的警告仍然成立，但一个 7 天窗口 2000 条
早已超出真实事件量（实测 55~64 条/周）—— 翻页只会多出一个没验证过的参数。

### 顺带补的两处「静默空」

1. **没有 token 时**：原先只把 `loading` 关掉，界面停在「暂无消息」，
   而真实情况是「请求根本没发」—— 两者在屏幕上一模一样。现在这一支会说清。
2. **「0 条」不再含糊**：空态直接写明窗口（「近 4 周没有事件」），
   而不是「暂无消息」同时涵盖「服务端没给」「我们没解析到」「区间里就是没有」。

### 仪器：诊断 → 原始日志

`RawLogStore` 从第一版起就在记录每一次请求与响应（已打码：token / 控车码 /
车牌 / 坐标），却**没有任何界面在读它** —— 所以每一轮「接口拿不到数据」
都只能靠猜。现在它在「我的 → 诊断」里有了一组：最近 8 条的首行直接列出，
全部可一键复制。下次再报接口问题，先看那条请求的 status 与响应长度，
一轮就能定位。（`DateFormatter` 也顺手钉上了 `en_US_POSIX`：
没钉住时，非公历的设备会打出「2569-09-24」这样的年份 → 一个不存在的区间 → 0 条。）

### 仍然只有真机能答的

① 四周窗口的首次加载耗时（四个并行请求）；② 上限 300 条时，「车的事件」那一节的行数
会不会让叠叠乐卡顿。

---

## 门禁自己拦错了人（2026-09-24 第五轮）—— 三条红，两条是我的，一条是判据过时

CI 这一轮红在 `static-gate`（ubuntu，秒级），macOS 的构建根本没启动。三条红逐条看完：

| 门禁 | 它说了什么 | 真相 |
|---|---|---|
| `oneentry.py` | 六个档位在 `HomeModeHead` 里「只出现 1 次」（需要 2 次） | **判据过时**：它的 ③ 是「巨字 hero + 依据行 facts」，而本轮「一个事实只留一个出处」恰好把依据行删了 —— 门禁在坚持旧设计 |
| `copy.py` | 两处文案含实现词「接口」 | **真 bug**：新写的空态把「我们怎么取数」写上了界面；同一个问题报两次，是因为同一句话在两个函数里各写了一遍 |
| `lintcfg.py` | `MapSpineView.swift` 1206 行 > 阈值 1200 | **真 bug**：这几轮往首页加的东西把它顶过了线 |

### 判据定义反了，就该翻过来（并留探针证据）

③ 现在守的是**恰好一次**：0 次 = 加了档位但卡头没跟上（原判据守的正是这一半）；
≥2 次 = 同一档在头卡里有两处表述（就是刚删掉的那种重复）。
按仓库自己的门禁写法约定 ⑤做双向验证：在 `HomeModeHead` 里临时注入第二个 `switch mode`
（每档再说一遍 = 旧形态的等效写法），它报出 6 条「出现了 2 次」并退出 1；
撕掉探针后 `HomeModeHead.swift` 与 HEAD **逐字节一致**（`git hash-object` = `16dfdda…`）且转绿。
两个方向都确实出声过 —— 探针与哈希写在 `oneentry.py` 文件头。

### 一两句话不该写两遍

两处空态文案收成 `Self.needLogin`（一句话两个出处，改一处必漏一处 ——
而且两遍都含实现词，于是同一个问题报两次）。改成用户看得懂的说法：
只描述他的状态（没登录）与他能做的事（去登录）。

### 拆文件，而不是抬阈值

四格读数（`readoutChips` / `readouts` / `readoutCell` + `Readout`）整块挪进
`Features/Map/MapSpineReadouts.swift`（94 行），骨架从 1206 → **1112 行**。
不选「把阈值抬到刚够」：贴着阈值的代价是下一次**任何**小改动都要先做一遍取舍 ——
这个账 `MapSpineLayers.swift` 的头注里已经写过一次。代码逐字未改，只换了文件与三处可见性
（`store` 不再是 `private`：Swift 的 `private` 作用域是文件）。

### 真正的教训：本地只跑了清单里的一半

HANDOFF §1.1 一直写着本地该跑的那个 `for s in ...` 循环，清单**与 CI 逐字同序** ——
而这一轮改完只挑了其中一半跑，于是三条红一条都没在本地出现，全部由 CI 报出。
靠「记得跑那个循环」显然不成立（它已经被写在文档里、还是漏了）。

→ 新增 `scan/all.py`：它自己**不判任何东西**，只做两件事 ——
① 从 `.github/workflows/ios-build.yml` 里**解析**出 CI 真正跑的清单（不另抄一份：
抄一份的后果是 CI 加了门禁而本地不知道，于是本地永远绿）；
② 逐条跑完**所有**条（CI 用 `bash -e`，红在第一条就停；本地要的是一次看到全部红），
最后给一张汇总表。它登记在 `paths.py` 的豁免表里并写明理由 —— 而它加进去的那一刻，
`paths.py` 的反向检查立刻报了一次「scan/ 下的脚本不在 CI 清单里」，
算是那条判据的一次实证。

### 仍然只有真机能答的

四格读数换了文件后与之前**逐像素一致**（同一段代码，只换了住处）；本地全绿也仍然不等于编得过。

---

## 消息：跨度改 30 天 + 一台自检仪器（2026-09-24 第六轮）

用户的话是两句：一句是判断（「不是这个原因，是要最近 30 天的消息」），
一句是要求（「或者写个单独的测试页，看看为什么获取不到，到底返回了啥」）。
两句都接：一句改数，一句造仪器。但得先说清一个算术：
**上一轮的 4×7 天已经覆盖了 28 天**，与 30 天只差两天 ——
所以如果车在最近 30 天里确实有过事件而界面还是空的，那就**不是区间长度的问题**，
而是别的地方（而那四种形态在界面上长得一模一样）。这句话写在代码注释与 `API-FIELD-MAP` 里，
因为下一轮看日志的人需要它。

### 把「跨度」与「形状」拆开说

之前把它们拉在一张嘴里（「四个 7 天窗口」），所以用户说「要 30 天」时，
代码里没有一个地方能回答「那形状呢」。现在两个名字分开：
`messageDays = 30`（跨度：要覆盖多少历史，用户要去拉长）与
`messageSliceDays = 7`（形状：抓包里那一次请求的样子，唯一被验证过，一个字不动）。
30 天 = 五段（7+7+7+7+2），末段不足 7 天是**有意的** —— 跨度停在 30 天，
不为凑整段而多要（`messageWindows(days:sliceDays:now:)` 是纯函数，测试逐段核）。

### 仪器：我的 → 诊断 → 消息自检

它不给结论，只把四个数并排放，因为这四种失败在界面上长得一样：
① 请求根本没发出去 ② 发出去了被拒 ③ 200 而服务端说 0 条 ④ 200 给了 55 条而我们解析成 0 条。

分家的就是那四个数：**HTTP 状态 / 响应字节数 / 服务端自报条数（`numberOfElements`）/
我们解析到的条数** —— 后两个必须同时出现：它们不一样时，凶手就在它们之间那一段。
另外还报正文里的**最旧与最新时间**（「区间对不对」一目了然）与 JSON 顶层键
（「拿到的是不是我们以为的那份东西」一眼判断）。

一次跑三种形状、七次请求：**30 天一段**（用户认为接口要的那种）/ **30 天分五段**
（App 现在真正发的形状，逐段报出每段条数）/ **7 天一段**（抓包里验证过的形状）。
三份答案放在一起，「长度是问题」与「形状是问题」当真机上一比 ——
这是真机实验，不是猜。结果可一键复制。

实现上只有一条路：`APIClient.probeMessageWindow(title:from:to:)` ——
**不合并、不兜底、不重试**（正常取数那条路在 `getMessages`，两边不相干 ——
自检要的正是「没有我们的加工」）。顶层键与条数由 `describeProbe` 纯函数读，
可以脱离真机被核对。URL 里的 token 一律打码（这一页会被人复制出去贴给别人看），
打码时短于 8 位的 token 不动 —— `replacingOccurrences(of: "")` 会把替换串插进每个字符之间。

它住在「我的 → 诊断」里、与**原始日志**并肩（`diagnosticsGroups`）：
两台仪器回答同一个问题的两半，同一个问题只该有一个地方看。

### 顺手拿掉一个多余的名字

`messageWindows` 本来用 `TimeInterval`（= `Double` 的别名），而 `scan/scan.py` 要求
每个新 SDK 名字都得在白名单里登记并附 Apple 文档 —— 为一个别名登记一次不值。
改成 `Double` + 把单位写进名字（`spanSeconds` / `sliceSeconds`）。

### 门禁自己的两个盲区（在推之前就地拦下）

过全清单时 `delguard.py` 报了绿 —— 而树里那个真错误真的在里面：`messageWeeks`
（在 `f6ff0e8` 才引入）的声明换成了 `messageDays` / `messageSliceDays`，而 3 处使用还在。
它没报，有两个原因，两个都补了：

1. **旧版本永远取 `HEAD~1`** —— 而那个名字**在 HEAD 里才引入**，拿 `HEAD~1` 比时它根本不存在，
   判据 ① 不成立。现在按工作区干不干净选：有改动（本地）→ 比 `HEAD`（手上这份的父提交）；
   干净（CI）→ 比 `HEAD~1`。
2. **「使用」只在同一个文件里找** —— 而这次是「声明在 `API.swift`、用在 `MessagesSection.swift`」。
   现在跨文件找：声明所在文件仍按原判据（无前缀也算），**其它**文件只认带前缀的用法
  （`APIClient.messageWeeks`）—— 裸名字跨文件极易撞上局部量，而一条误报就会让人开始绕过门禁。

探针就是那次真事故本身：**修前绿、修后报出「`API.swift` 的声明没了 + `MessagesSection.swift:210`
还在用」**，撕掉探针后转绿。同一条门禁第二次拿真事故校准（第一次是它诞生时用
`pvValue` / `shapeScroll` 做的双向验证）。两次都在“本地看得见”与“CI 看得见”之间省下一整轮 runner。

### 仍然只有真机能答的

三种窗口各自的状态码与条数（这一页就是为了把这三份答案交出去）；
以及 30 天分五段时的首次加载耗时（现在是五个并行请求）。

---

## 闪退而且没有日志（2026-09-24 第七轮）—— 先把路标写在死之前

用户的现象：「软件载入不到 10 秒钟就自动闪退，但是系统里面没有日志记录」。

### 「没有日志」本身就是诊断信息

先分清两类终止：

· **应用层错误**（`fatalError`、数组越界、强解包失败、ObjC 异常）—— 系统会留一份 `.ips`；
· **系统级处决**（内存回收 jetsam / 看门狗 watchdog）—— **不调用 App 里任何一行代码**，
  所以 App 自己也不会知道。而这类报告还有第二个条件：
  「设置 → 隐私与安全性 → 分析与改进 → 共享 iPhone 分析」必须开着，
  关着时 iOS 不保留第三方 App 的报告 —— 这很可能就是「系统里什么都没有」的原因。

还有第三个原因，是我们自己造成的：N38 `CrashReporter`（把崩溃写进 UserDefaults）
已在 2026-09-23 按用户「不要本机攒数据」的要求整块删掉，并写明「删掉意味着
再也拿不到自己 App 的堆栈」（见 `Services/Monitoring.swift` 头注）。

### 所以这一轮装的是轨迹，不是统计

`Services/StartupJournal.swift`：每次启动在盘上写一行行路标
（阶段名 + 相对启动的秒数 + 此刻的内存水位），12 秒后仍在运行就写一行收尾标记。
**下一次启动读它：没有收尾标记 = 上一次没走完**，最后一行就是死前到达的那一步。

打点的位置都是可命名的启动阶段：进程启动 → 启动动画结束 → 根视图出现 →
取车辆列表开始/结果 → 首页外壳出现 → 取天气 → **消息取数开始/结束或失败**。
最后那一对是故意的：消息取数是启动后最晚回来的那一段（五段窗口并行），
而用户报的闪退就发生在「载入不到 10 秒」——如果是它，轨迹会停在那一对之间。

内存水位同时在回答另一个问题：水位接近上限就是**内存被杀**（jetsam），
水位很平就要去看别的（看门狗 / 被拒 / 系统策略）。这也顺带记下了一件事：
启动链上本来就有个 10 秒节奏的定时器（`MemoryMonitor.startMonitoring(interval: 10)`）。

### 顺手修掉的：静止条上那颗「太小的玻璃体」

用户同一条消息里的第二句：「首页 选中的玻璃体太小了，大 50%」，
并指定了是底条里当前档的玻璃胶囊。根因与「静止时对不上」是**同一个病根的另一面**：
条子的间距一律按「六档能不能装下」算，而静止时只露三档 —— 于是那三档用着
为六档压出来的节距 40，而那颗选中胶囊还被「不超过节距」封了顶：38pt，
几乎就是字的宽度（看起来「没有玻璃」）。

两处一起改：
· **间距按露出档数算**，并随展开插值（静止按三档 → 宽裕；展开按全部 → 不够才压）；
· **胶囊尺寸改由格宽与条高推出**（格宽 ×1.5、条高 ×0.94），不再与节距挂钩。
  高度不再往上是因为外轨只有 46 —— 比轨还高就是「逞出来」而不是「更大」。

顺带在这里存一笔：当年顺手加的「透镜宽度按节距封顶」就是这次要拆的东西，
而它原本要治的病（压住邻居）真正的成因是标签坐标系偏移（已修）——
一个为症状写的封顶，会在症状消失之后继续制造新症状。

### 边界（与那次删除不矛盾）

三条硬边界，写进了文件头与 `HANDOFF §6.1`：不收集业务数据（没有任何车端读数）、
不累积（只留上一次与这一次，每份 4 KB 上限）、不上业务界面（只在诊断里显示与复制）。
落盘用 `String.write(to:atomically:)`（与导出/主题页同一套已登记的 API，
不为它多开 SDK 名字）；`atomically` 是故意的 —— 进程被处决也不会留下半份文件，
而半份文件的「最后一行」会骗人。

---

## 编译修复：`URL?` 与三条警告（2026-09-24 第八轮）

`beff2b5`（玻璃胶囊放大）在 CI 上编译失败，只有一条错误：
`StartupJournal.swift:92` —— `begin()` 留档上一次轨迹时，
`if let text = Self.read(cur), let prev` 只解开了「上一次」，
而下面 `removeItem(at: cur)` 里的 `cur` 还是 `URL?`。
**本机没有 Swift 工具链，这条错误只有 CI 能看见** —— 而它就长在这一轮新写的文件里。

改法是拆成两段（而不是把 `cur` 塞进同一个 `if let`）：
拿不到新迹的路径时**不能静默放过** —— 那样「上一次」永远是空的，
而空轨迹会被 `previousRun()` 读成「上一次启动是好的」，正好反了。

同一次构建还报出三条警告，一并清掉：
· `API.swift` 的 `withRefresh { [self] in }` —— 这个捕获从头到尾没被用过（编译器原话）；
· `MapSpineView.swift` 的 `Text(…​) + Text(…)` —— iOS 26 起 `+` 已弃用，合成一个插值 `Text`；
· `MapSpineView.swift` 的 `MKLocalSearch.start { }` —— 换 SDK 26 的 async 重载，
  那层「回调里再 `Task { @MainActor in … }` 跳回主线程」也随之去掉
  （函数本来就是 `@MainActor` 的 async）。

### 顺带：`scan/all.py` 在 Windows 上因为「打不出对勾」而崩

同一轮本地验证里当场发现的：这台机器的控制台是 GBK，`print("  ✅ …")` 直接
`UnicodeEncodeError` —— 一个用来保证「本地全跑」的脚本，自己先崩了。
两处改：① `stdout.reconfigure(errors="replace")`（**只改 errors，不换 encoding**：
中文在 GBK 里是能打的，打不出的只有 ✅/❌）；② 符号显式降级为 `[通过]` / `[红]` ——
若只做①，✅ 与 ❌ 会同时变成 `?`，那正是本仓库最忌讳的「红绿长得一样」。
子进程再给 `PYTHONIOENCODING=utf-8`：否则它们会因为同一件事崩，
而「子进程崩了」会被误读成「门禁红了」。
探针：临时移走 `check_style.js` → 红行打出 `[红]`、其余打出 `[通过]`，文件当场还原。

---

## 闪退仍无日志：把「死在第几秒」变成可读的（2026-09-24 第九轮）

用户原话：**「还是闪退 没有日志，咋回事」**。这一轮没有猜下去，而是先去看了
「上一次启动」那条仪器到底能看见什么 —— 结果发现它看不见。

### ① 为什么就是没有日志

三件事叠在一起，使这一个事故恰好落在所有日志之外：

· **应用层错误本来是有报告的**（`fatalError` / 越界 / 强解包 → 一份 .ips）。
  所以「什么都没有」本身就是判据：它更可能是**系统级终止** —— 内存回收（jetsam）
  或看门狗（watchdog），而那两类**不调用 App 的任何一行代码**；
· 系统自己那份报告只在 **设置 → 隐私与安全性 → 分析与改进 → 共享 iPhone 分析**
  打开时才留。关着的时候，第三方 App 的崩溃它就是不留 —— 不是没发生，是没记；
· 项目**自建**的那份崩溃上报（N38 `CrashReporter`）已在 09-23 按用户要求删除
  （理由写在 `Services/Monitoring.swift` 的头注里）。

于是能用的事实只剩一个：**死之前把路标写到盘上**。那正是 `StartupJournal` 在做的事 ——
但它第一版在关键的一段里是瞎的。

### ② 仪器自己的缺陷（这一轮真正的发现）

轨迹里所有打点都落在启动的**头一两秒**（根视图出现 / 首页外壳出现），
下一行就是第 12 秒的收尾标记。而用户报的是**「地图出现之后几秒」**自己退出 ——
那一段正好一行打点也没有。事后打开文件，最后一行是两秒前的某个阶段：
既说不出死在第几秒，也看不出死的时候主线程在不在动。
**一个事故恰好吃在自己仪器的盲区里** —— 这比没有仪器更坏，因为它看起来像有证据。

补三样：

· **心跳**：启动阶段内每 1 秒一行（`· 心跳  内存 xxx MB`），写在**后台队列**上。
  选 GCD 的 `DispatchSourceTimer` 而不是 `Timer.scheduledTimer`，理由只有一个：
  后者跑在调用它的 run loop 上，主线程一卡它自己也停了 —— 那正是要分辨的事；
· **主线程卡住判据**：每次心跳让主线程回一句话。心跳还在写、主线程却已经
  N 秒（阈值 2.5）没回话 = **卡死**；心跳自己也停了 = **进程被直接处决**。
  这两种终止在系统里都没有日志，但在轨迹里长得完全不一样；
· **地图页各步打点**：取数开始 / 取数结束 / 就绪，充电站搜索的四种结局
  （还没有车的位置 / 开始 / 失败 / 结束 N 个）分开写 ——
  「没有车的位置」与「搜到 0 个」在界面上都是空的，只有轨迹分得开。

### ③ 顺带修掉的真 bug：冷启动把同一件事问了三遍

根视图 `onAppear` 里两处（一处主取、一处兑底提示）加地图外壳的 `.task`，
三处各自调 `bootstrap()`。它们问的是同一件事，而在合并之前那是**三份**真实的
`getCars` + `getUser`，外加**三次** `cancel` / 重启预加载（每次预加载都是 6 个请求）。
冷启动头几秒本来就在抢 CPU 与网络。现在同时飞的那几趟合并成一趟；
串行重复调用（重新登录 / 下拉刷新）照旧各取一次；`logout()` 丢掉句柄，
新账号必须另起一趟（否则等于用前一个账号的请求给新账号结账）。

### ④ 怎么读下一次的轨迹

（下面这张表从 2026-09-24 第三轮起由 `StartupJournal.conclude(...)` **自己算**，
结论直接显示在「上一次启动」的第一行 —— 表留在这里是为了说明那句话的判据。）

| 轨迹最后几行 | 结论 |
|---|---|
| 末行距离额度只剩几十 MB（`距上限` 那一栏） | 内存被杀（jetsam）—— 真正要做的是减启动占用 |
| 心跳连续几行带「⚠️ 主线程 N 秒没回话」 | 主线程卡死（看门狗那种）—— 去看卡在哪一步 |
| 心跳断在某个打点之后、而距上限还剩几百 MB | 不是内存也不是卡死 —— 去看被拒 / 系统策略那头 |
| 最后一行是 `✅ 启动阶段完成` | 这一次启动是好的，退出的原因不在启动阶段 |

### ⑤ 门禁

`DispatchSourceTimer` / `makeTimerSource` / `schedule` 三个 SDK 名字已按 `scan.py` 的
规矩登记进 `VERIFIED_SDK_ADDITIONS`（登记前核过 Apple 文档：
`dispatchsourcetimer` 一页列出 `schedule(deadline:repeating:leeway:)`）。
本地：`python3 scan/all.py` **25/25 通过**，`node CarKeeper/check_style.js` **0 个问题**。
编译仍然只有 CI 能验（本机没有 Swift 工具链）。

### ⑥ 仍然缺的那份证据（需要真机）

· **我的 → 诊断 → 上一次启动** 的全文（缺最后一行 `✅` = 上一次没走完，
  最后一行就是它死前到的那一步）；
· 把 **共享 iPhone 分析** 打开，再看 设置 → 隐私与安全性 → 分析与改进 → 分析数据
  里有没有 jetsam / watchdog 条目 —— 那份才是权威的那份。

---

## 内存被杀？：「我感觉」与「一句话」（2026-09-24 同日第三轮）

用户这一轮的反馈不是现象，是一句**猜测**：
**「没闪退，我感觉是因为内存占用太多被系统杀了」**。

而仪器当时答不了这个问题：它只记常驻内存，而那个数单独看没有判据 ——
4 GB 与 8 GB 的机器、前台与后台，额度完全不同；320 MB 在有的设备上很远、
在有的设备上已经很近。**能算的东西被留成了一张要人自己推的表，于是回来的就是猜测。**

补三处（都在 `Services/StartupJournal.swift`）：

· **距上限还剩多少** —— `os_proc_available_memory()`（os 框架，iOS 13+）
  是系统直接给出的那个额度，写成每行尾部的 `（距上限 X MB）`：末行只剩 12 MB
  就是被挤死，还剩 320 MB 就**不是**内存的事；
· **系统挤压过几次** —— `didReceiveMemoryWarningNotification` 计数：
  处决之前通常先响这一声，「心跳断掉而前面挤压过三次」与「心跳断掉、一声都没有」
  指向的不是同一件事；
· **结论一句话** —— `StartupJournal.conclude(...)`：`previousRun().verdict` 给出
  「被信号终止 / 像是被内存杀掉 / 不像内存的事 / 没走完但没有读数 / 走完了」，
  显示在「上一次启动」组的第一行，并随轨迹一起被复制出去。

两个数都刻意把「没测到」与「真的不够」分开：取不到额度时写 `—`，解析不出来时返回 -1，
绝不退化成 0（0 会被读成「一兆都不剩」—— 正是本项目最贵的那个坑）。

门禁：两个 SDK 名字已按规矩登记进 `scan/scan.py` 的 `VERIFIED_SDK_ADDITIONS`
（登记前打印了 Apple 文档 JSON 的 abstract / modules / externalID / platforms）；
本地 `python3 scan/all.py` **25/25 通过**。编译仍然只有 CI 能验。

**仍然缺的那份证据没变**：要真的把「是不是内存杀的」钉死，需要真机上那份轨迹
（我的 → 诊断 → 上一次启动 → 复制轨迹），以及打开「共享 iPhone 分析」之后
分析数据里那份权威的 jetsam 记录。在那之前，仪器至少已经把话说清楚了。

---

## 真机轨迹到手的第一个结论：四秒里涨到 1.7 GB（第五轮）

用户把「上一次启动」的全文贴了回来（20:46:08 那一次，iOS 27.2）。它的价值在于
**这是第一条来自真机的完整轨迹**，而它一句话就结束了那个猜测：

| 时刻 | 事件 | 内存 |
|---|---|---|
| 0.19s | 外壳 / 根视图 / 地图页就绪 | 49 MB |
| 0.97s | 消息取数结束 227 条 | 140 MB |
| 2.01s | 心跳 | **673 MB** |
| 2.74s | 消息取数开始（**第二次**） | **1210 MB** |
| 4.01s | 心跳 | **1720 MB** |
| 5.01s | 心跳 | 1566 MB |
| 5.31s | 消息取数结束 227 条 | 1558 MB |
| — | 没有 `✅`、没有信号纸条、没有任何主线程告警 | 停在 5.3s 之后 |

### 这份轨迹排掉了三件事

· **不是我们自己的代码踩 trap**：一张纸条都没有（`fatalName` 那份文件是空的就是结论）；
· **不是看门狗**：每一秒的心跳都没有 `⚠️ 主线程 N 秒没回话` —— 主线程在死之前一直在回话；
· **不是「取数太多」**：头部写着 `地图取数[关]`（`LaunchFence.mapFetches`），
  所以地图页那三条取数根本没跑（轨迹里也没有 `地图页取数结束` / `取天气` / `充电站搜索`）——
  而这 1.7 GB 是**画出来的**，不是取出来的。

剩下的一件事就是用户的判断：内存。而它不是「占用偏高」：**四秒 +1.67 GB，均速每秒约 500 MB，
在 5.3 秒处断掉**。参照物是那次请求本身：30 天一段的响应只有 **475 KB** ——
一兆不到的报文变成了 1.7 GB 的常驻内存，放大了三千倍。

### 轨迹没说的：当时亮的是哪一屏、227 行到底画完没有

这一轮真正的收获是暴露了两个仪器盲区，都补上了：

· **哪一屏在内存里** —— 六页同屏关掉之后只建当前那一档，于是「哪一档在建」直接决定
  「谁在吃内存」。补 `亮出屏幕：<档名>`（`pageBody`）；
· **227 行画完了没** —— `MessagesSection` 的列表是普通 `VStack` + `DSGroup`**不在懒容器里**，
  227 行是一次性全建出来的；它在出行页的一张卡里，而这一页的**所有卡**由 `ArcStack` 一起建。
  补 `消息列表画到最后一行`（挂在最后一行的 `onAppear` 上，重复出现同样是信息 = 这一卡在反复重建）。
  2.74s 那第二次「消息取数开始」已经是一次旁证：那张卡的实例被重建过一次
  （新实例 → `@State` 重置 → `onAppear` 再取一次）。
· **被切走还是被处决** —— 心跳突然停掉时，jetsam、被用户划掉（SIGKILL，抓不到）、
  被切到后台挂起（定时器不再开火）在轨迹里长得一模一样。补 `进入后台` / `回到前台` 两行，
  并让 `conclude(...)` 多出一条结论：「上一次停在进入后台之后」。

### 定位：真正吃内存的是「每段行程一张真地图」

用户下一条消息把范围钉死了：**「点到出行界面就闪退，其他界面没问题」**。
而这一页与别页的差别只有一个：**它的每张卡里都有一张 `Map`**。

`MiniTripMap` 不是示意图，是一个真的 `Map(position:)`（132pt 高，带 `MapPolyline`
与起终点两个 `Annotation`）；而 `TripsEventsView.cards` 是「每段行程一张卡」，
227 条消息配出来的行程动辄几十段 —— 再把「`ArcStack` 把当页所有卡一次建出来」
和「主屏只有一张地图」两个事实摆在一起，这 1.7 GB 就是几十个 MapKit 视图
（各自的资源、图块与渲染缓冲）叠出来的。每秒半 GB 的斜率也对得上：那是图块持续进来。

修法（两层，都是「把「一次建多少」从数据量手里拿回来」）：

· **行程卡一次只建最近 5 段**（`TripsEventsView.shownTrips`），其余由
  `再放 5 段出来` 那个动作放出来；汇总数字仍用整份列表（数字要全，卡才按需）；
  时间轴那根竖线只在「确实没有藏着的段落」时才断。
· **消息一节一次只画最近 3 天**（`MessagesSection.shownDays`），早的由
  `再看早 3 天` 放出来；同时把一天之内的顺序改成**新的在上**。

两条都没有改成伪懒容器，理由写进了代码里：这一节的父级是 `ArcStack` 的卡，
而卡的高度必须先量出来 —— 在「必须先知道高度」的容器里，懒容器为了量高
会把内容全建一遍，**“看着像优化、实际一点没省”是比不优化更坏的结果**。
直接限制建多少，才是无论外层怎么摆都成立的那一刀。

### 下一步（真正的解法，还没做）

把「离阅读线多远」从 `ArcStack` 传给卡的内容：只有近处那两三张卡把地图
实例化，远的用一张静态方块占位。现在 `ArcStack` 已经按距离决定 `glassy`，
通道是现成的；那才是「既能留几十段行程、又只养两三张地图」的那一刀。
在此之前，上限由 `shownTrips` 守着。

---

## 暗层全删 + 子页面铺壁纸（2026-09-24 同日第六轮）

用户确认闪退已修（「不闪退了」），接着原话：**「每个子界面的暗层都去掉，
不要！除了地图页，其他页面的背景全部设为当前桌面的背景」**。

两个动词，两件事：

### ① 暗层：其实是三层叠的，全部删

此前只删过「地图页上的压暗层」（`.maptop` / `.mapvig`，见 2026-09-24 早些
条目），而**子界面底下那三层不透明画布一直留着**：

· `MapSpineView.body` 根部 `.background(TokensPalette.canvas)` —— 把 App 根上
  的 AppCanvas（画布 + 实时光）整个盖死；
· `pageDeck()` 六层同屏底下垫的那层 `TokensPalette.canvas.ignoresSafeArea()`
  （当初为「换档过渡不能透出地图的灰黑」加的）；
· `pageBody` 每张非地图子页各自的 `.background(TokensPalette.canvas.ignoresSafeArea())`。

三层全删。过渡期间透出的不再是「上一页的鬼影」：非地图页自己铺了壁纸图
（见 ②），地图页是瓦片本身（不透明），所以那个理由随之消失。

### ② 「当前桌面的背景」：iOS 读不到壁纸，铺一张在线风景图顶上去

先确认了事实：iOS **没有读取主屏壁纸的公开 API**（壁纸归 SpringBoard 进程管，
App 进程拿不到；刚查过 2025–2026 的资料也没有新 API）。能给用户的只有替代物，
问清楚之后用户选了「**从在线 API 拿一张**」（不是相册自选，也不是系统磨砂）。

实现（`Services/WallpaperService.swift` + 两处调用）：

· **图源**：Unsplash 官方直链（`images.unsplash.com/photo-…?w=900&q=60&fit=crop`）。
  没有走 `source.unsplash.com`（那个域名已弃用、返回 503）；
  也没有引入任何 API key（Unsplash 直链是公开 CDN，免费、不需要 key）。
· **状态**：一个 `ObservableObject` 单例（与 `StartupJournal` 同款 NSLock +
  `@unchecked Sendable`）。`index`（哪一张，UserDefaults 持久化）+ `image`
  （取到的图，幂等：已有同张早退不重发；取到旧图而索引已改，不写进来）。
· **取图失败静默**：背景回落到 AppCanvas 的画布色，不弹错、不留白屏。
· **三处消费**：
  - 五张非地图子页的 `.background(wallpaperLayer())`（`MapSpineView`，
    `@ObservedObject` 订阅同一个单例 —— 不订阅的话「换一张」要等下次换档才生效）；
  - `MineView`「应用」组里新增一行壁纸小卡：缩略图 + 「换一张」（循环）
    + 「不铺」（回落到画布色）。放在「应用」组（改 App 自己），
    不放在「设备与模式」组（改系统的）；
  - 根部的 `AppCanvas` 不动 —— 它是全 App 唯一的一束光，铺壁纸只发生在
    子页这一层。
· **门禁**：两个 SDK 名（`URLSession` / `UIImage`）登记进
  `VERIFIED_SDK_ADDITIONS`；本地 `python3 scan/all.py` **25/25 通过**，
  `node CarKeeper/check_style.js` **0 个问题**。编译仍只有 CI 能验。

观感上的代价要照实说：在线图要**联网**才有，断网/未取到时是画布底色
（和删暗层之前那层 `TokensPalette.canvas` 观感相同，只是不再是「暗层」而是
App 自己的画布）；玻璃卡压在照片上时，卡片自身的材质负责可读性
（iOS 26 的 Liquid Glass 自带折射，这是选玻璃卡而不是白卡的理由）。

---

## 在线图取不到，子页退回纯黑（2026-09-24 同日第七轮）

用户真机（深色模式）反馈原话：**「没任何变化啊，这是啥啊，根本看不清 太暗了」**。
截图里「我的」页背景是一整块纯黑 —— 上一轮那版在线壁纸图根本没取到。

### 两个叠加的错

· **Unsplash 直链在用户的网络上取不到**（静默回落，不弹错 —— 当时设计成
  「失败就当没图」，结果没图的回落色在深色模式里是 `TokensPalette.canvas`
  = `systemGroupedBackground` = 纯黑）。于是「没图」与「有图但黑背景」在屏幕上
  长得一模一样，用户看到的就是「什么都没变，还更暗了」；
· **上一轮铺壁纸之前，子页底下本来就有 AppCanvas 那束光**；删三层暗层时
  把根上的 `.background(canvas)` 也删了，而「没图」的兜底又写成了 canvas ——
  深色模式下画布就是黑，兜底等于没兜。

### 修法：在线图整个换成本地相册（同一轮直接改完，不再发第二版）

· **图源**：`PhotosPicker`（iOS 16+，`PhotosPickerItem.loadTransferable(type: Data.self)`）
  从相册选一张 —— **不依赖任何网络**。用户把桌面壁纸那张图选进来（或任意一张
  喜欢的图），存成 JPEG（0.82 质量，原始 PNG/TIFF 动辄几十 MB，铺背景用不上）
  落到 `Documents/carkeeper-wallpaper.jpg`，下次启动还在；
· **`WallpaperService` 改版**：删掉 `index` / `URLSession` / Unsplash 那套（上一轮
  刚建的 `WallpaperSource` 整个没有），只留 `image: UIImage?` + `setPhoto(_ data:)`
  + `clear()`。两个新 SDK 名（`PhotosPicker` / `PhotosPickerItem` / `loadTransferable`）
  已登记进 `VERIFIED_SDK_ADDITIONS`；
· **「我的 → 设置 → 应用」组里那一行**从「换一张（在线循环）」改成
  **「选一张」（打开相册）/「不铺」（清图 + 删文件）**；
· **「没选图」的兜底**：铺 `TokensPalette.canvas` —— 浅色模式下是浅灰（读得清），
  深色模式下还是黑，但那时 AppCanvas 的光在更底层（AppCanvas 没被删），
  观感是「App 自己的深色画布」而不是「一整块死黑」。
  深色模式想要不黑，就选一张图铺上 —— 这正是用户要的效果。

本地 `python3 scan/all.py` **25/25 通过**，`node CarKeeper/check_style.js` **0 个问题**。
编译仍然只有 CI 能验。

---

## 地图页收拢、子页全屏、底条跟手、叠法收敛、二十套主题（2026-09-24 同日第八轮）

用户原话（六条，同一天）：「地图页地下 4 个独立的读数融合进大卡片（最上面那行也删，
重复了）」「地图页全屏为什么子页面有状态栏挡着」「底部导航太拉跨，不跟手」「所有页面
间距布局不 iOS」「叠叠乐只用吸附堆叠（但要删吸附）其他全删」「艺术主题搞出 20 种
完全不一样的」。

### ① 地图页「现在」这一档：三块收成一张卡

原先「浮动两卡 + 四格读数」三块，现在只有一张 `nowCard`（`GlassCard`）：

- 卡头一行删掉（车牌 + 状态 + 上报时间与卡内正文重复），只剩**右对齐的图层胶囊**
  （`layerMenu`，它是控件不是信息，不能跟着删）；
- 四格读数（车速 / 电量 / 胎压 / 车锁）**不再单铺一层**：新增 `readoutCells`
  （`MapSpineReadouts.swift`，裸 `HStack`，不套玻璃壳）直接排进大卡的 `.now` 分支下沿；
  旧的 `readoutChips`（独立玻璃卡）保留在文件里但地图页不再调用；
- 卡内正文顺序不变：地址 → 巨字续航 → 副行 → 光带 → 四格读数。

### ② 子页面全屏（不被状态栏挡）

`MapSpineView.pageBody` 的非地图分支（五张子页）：`.background(wallpaperLayer())` +
`.ignoresSafeArea(edges: .top)` —— 壁纸/画布铺到屏顶，与地图页同一种全屏；
但**内容窗不动**，多加一条 `.safeAreaPadding(.top, 44)` 把第一张卡顶到安全区下沿，
字不压进状态栏。删掉了这一支里原先为「背景铺到屏顶」写的一个死辅助
（`DS.swift` 的 `dsFullBleedTop()`，无调用点，已删）。

### ③ 底条跟手（「不跟手」→ 按在整条任意位置都能拖）

两条手势并存：

- **`DSSwipeStrip` 内部那条**（按在胶囊上）：本条的「手」从格子 1.5 倍宽加大到
  **1.75 倍**（`loupeWidth`），端点不再夹死 —— 过界走**指数衰减**的阻尼
  （`clampC`，越界 0.5 个节距时已经衰减一半，不再是「拖过头就卡住」）；
- **`bottomBarDrag`**（挂在整条 `bottomBar` 上，`simultaneousGesture`）：手指按在
  **两侧圆钮与胶囊之间**的位置也能拖模式条 —— 这是用户说的「不跟手」的真正病根
  （原先只有胶囊上那一段跟手）。按下时记下当前档位（`barDragBase`），拖动中
  把增量按「条宽 / 5 个间隔」换算成连续档位写回 `modePosition`，拖过 8pt 同时
  展开条子（圆钮让位）。松手不清 `modePosition`（档位停在手指停的地方），
  写回 `homeModeRaw` 交给条子自己的吸附逻辑；
- 这段手势从骨架文件拆进了新文件 `MapSpineBottomBar.swift`（`MapSpineView` 一度
  涨到 1219 行，越过 `file_length` 阈值 1200；拆完骨架 1164 行）。

### ④ 叠法收敛为唯一（吸附堆叠，且删掉吸附回落）

用户原话「只用吸附堆叠（但是要删除吸附）其他都删除」：

- `StackVariant` 七个 case 只剩 `.sticky`（`StackSpec` / `StackLabView` / `DevView` / 
  `ArcStack` 全部同步改过）；旧版存进 UserDefaults 的其他叠法值由 `StackSpec.chosen`
  读到时洗回 `.sticky`（不留「还有别的叠法」的假象）；
- **「删除吸附」= 删掉松手后的弹回**：`ArcStack.drag` 的 `onEnded` 不再找吸附点、
  不再走 `settle` 弹簧、峰值速度那套整段删除（`peakVelocity` 相关机制已没）——
  手停在哪儿卡就停在哪儿，两端仍由 `StackMath.clamped` 硬限位守住；
  `settle(velocity:)` 保留给**无障碍翻页与外部换档**两条路（它们没有惯性，
  用同一条固定弹簧）；
- 对照页（`StackLabView`）不再有「七选一」，只显示一句「唯一叠法」的说明
  （文案已按 `scan/copy.py` 的 30 字上限改短）。

### ⑤ 艺术主题从 4 套扩到 20 套（每套的美来自不同的机制）

> ⚠️ **本节整节已作废（2026-09-25 第六轮）**：这 20 套、它们的切换器、由它们派生的地图样式
> 与装饰图层，全部随用户「主题用原生，其他 19 套全删了」删除。留档理由：它记着这 16 套
> 各自的美学机制与 `ArtThemeSpec` 的推导规则 —— 万一以后要恢复「多方向」，这里是出发点。

新增 16 套：玻璃 / 青釉 / 胶片 / 荧光 / 沙丘 / 雪夜 / 蓝图 / 琥珀 / 银灰 / 绛紫 /
朱砂 / 苔原 / 玄墨 / 熔炉 / 晨雾 / 霓虹。设计原则（写在 `ArtThemeSpec` 便捷构造的
头注里）：每套只给「它自己是什么」（画布 / 表面 / 字 / 强调 / 装饰 / 字重 / 明暗 /
六页个性色），其余 15+ 字段按**同一套推导规则**一次算齐 —— 规则写在一处，
二十套不会各长一套习惯；「完全不一样」体现在每套给的核心色与装饰上，
不体现在推导规则上。

- 便捷构造里的 `onAccent`（铺在强调色上的文字色）走**强调色亮度**判深/浅：
  读的是 `CGColor` 分量（`artHex` 构造的定值色 = 同一套 sRGB 数值），**不碰
  `UIColor`** —— SwiftUI 的 `Color` 没有可靠的公开 API 反解成 sRGB 分量，
  动态色 / pattern 色上 `getRed` 会失败；
- `MapStyleSpec.mapSpec` 同步加 16 个 case：全部走「`muted` + 色温蒙版」同一机制
  （MapKit 没有改瓦片颜色的公开 API，见文件头注），只差蒙版色与不透明度；
- 切换器（`ThemeGalleryView`）：20 枚胶囊一行排不下，改成**横向可滑**
  （`ScrollView(.horizontal)`，每枚自定宽）；旧版 4 值用户升级后
  `ArtThemeStore.current` 回落到 `.native`，不会崩；
- 对 `ArtTheme` 的穷举 switch 有四处（`title` / `mechanism` / `mapKitVerdict` /
  `spec`）+ `MapStyleSpec` 的一处，全部扩到 20 个 case（`scan/futureproof.py` 不覆盖
  自有枚举，但本地已逐个核对没有漏）。

### 未做（如实说明）

- **第 4 条「所有页面间距布局不符合 iOS 标准」未动**：范围太宽（全 App ~28 屏），
  没有编译器也没有真机，盲改一千行布局只会把能跑的东西改坏。需要用户指出
  具体哪几屏「不符合」，或者逐屏过（哪几屏优先）。
  → 2026-09-25 兑现了一部分：**双重内边距**那一类（卡 18pt 之上又叠一层页边距 16/20pt）
  已经拆掉（见下一节）；剩下的「字面量不在刻度上」（字号 2/3/5/6/9/10/11/14/15/18/22
  散布在 Features 里）尚未动 —— 那些多数是「大数字与单位之间的 3pt」这类**光学微调**，
  一刀切成 4/8/16 会把仪器的密度改掉，需要一屏一屏看。
- 拖动的跟手手感（节距、阻尼斜率、展开阈值 8pt）仍是量出来的值，不是调出来的 ——
  真机上若仍觉得「拉跨」，下一个要调的是 `clampC` 的斜率与 `barDragBase` 的取点。

本地 `python3 scan/all.py` **25/25 通过**，`node CarKeeper/check_style.js` **0 个问题**。
编译仍然只有 CI 能验。

## 卡片逐张核对 + 每日壁纸 + 一处门禁自身的假阳性（2026-09-25）

用户原话（承上一轮六条）：「然后全局看重复内容，尽可能的融会贯通，现在壁纸用必应和
windows 聚焦（每日的），如果需要密钥就算了，特别是卡片，每个卡片仔仔细细的核对
是否合理，内容展开后是否拥挤」。

这一轮没有新页面，只有三类修正。**全部改动都是「删重复 / 拆错层」，没有一处是
新增界面** —— 上一轮的清单已经很长，再加东西只会更难核对。

### ① 壁纸：三条路，两条是免密钥的每日图

`WallpaperSource`（`CarKeeper/Services/WallpaperService.swift`）：

| 图源 | 取法 | 付费 / 钥匙 |
|---|---|---|
| 相册自选 | `PhotosPicker`，本地，不联网 | 不要 |
| 必应每日 | `HPImageArchive.aspx?format=js&idx=0&n=1`（当天那张） | **不要** |
| Windows 聚焦 | `fd.api.iris.microsoft.com/v4/api/selection?placement=88000820&bcnt=4` | **不要** |

- 用户给的边界是「如果需要密钥就算了」，所以只做这两家：它们都是面向自己产品的
  **公开只读 JSON**（必应首页、Windows 锁屏），不需要注册。（此前试过的 Unsplash 直链
  已废：不限量的那条要 key，不要 key 的那条不稳，见上一轮。）
- 两张在线源**每天换一张**：取到就压成 JPEG 落盘（与相册那张**同一个文件**，
  「铺图」只有一条路径），`UserDefaults` 记「这是哪一天的」（`dayStamp` = UTC 天数）。
  同一天启动直接读盘，跨天才取。**取不到不删上一天那张**，`failed` 让设置行说一句
  「取图没成功，先铺画布底色」—— 静默留白等于让用户以为坏了。
- 聚焦那家返回的是 `batchrsp.items[].item`（**item 本身是一段 JSON 文本**），
  `ad` 下的资源键名随版本改过（landscape / portrait / square …），所以解析不列键名：
  在 `ad` 的每个子字典里找以 `http` 开头的 `u` / `url`，按天数取模轮播。
- 第一次取图挂在 `MapSpineView` 的 `.task` 里（`refreshIfStale()`），**故意放在
  `LaunchFence` 之外**并写明理由：它只往 Documents 落一张 JPEG，不碰车况与地图状态，
  与那一轮二分定位的「启动就退」不是同一类东西。⚠️ 若下一轮还要做启动二分实验，
  这一行要算进实验里（它是一次网络请求）。
- 设置那一行改成了 iOS 设置的值选择器形状（左标签 + 右 `.menu`），下面才是缩略图；
  「选一张」只在相册那一档出现，「不铺」只在这时才有图时出现。

### ② 卡片逐张核对：三个「页面壳套进卡里」

方法：把每个 `StackCard` 的标题与它内容里那几个子视图的标题并排看。查出来的是同一类错 ——
**这些视图当初是页面，后来被挂进卡里，页面壳没拆**。

| 视图 | 原来是 | 现在 |
|---|---|---|
| `HealthDataView`（卡「体检」） | `DSPaperPage`（自带 ScrollView + 纸面底 + 页标题「体检与数据」） | `VStack(spacing: 0)`，只有内容 |
| `MaintenanceMoneyView`（卡「保养」） | 同上（页标题「保养与钱」） | 同上 |
| `EmergencyPanel`（卡「应急」） | 卡里又加一层页边距（水平 20） | 删掉那层页边距 |

- 那一层页壳的代价是可算的：卡自己左右各 18pt，页壳再加 16pt（应急是 20pt）——
  内容距卡边 **34 / 38pt**，比全 App 任何一张卡都窄一圈，这正是「内容展开后拥挤」的
  一半。（另一半在下一节。）
- 里外两层都能滚时手势会塌给内层，而内层拿到的是无限高：它自己永远滚不动，
  却把这一块区域的拖动吃掉了（叠叠乐是**自管手势**，没有 ScrollView，见 `ArcStack`
  头注）。所以这两张卡原来在那一叠里是「拖不动」的。
- 两者都是所在那一叠的**末卡**（`.health` / `.service` 分支各自只有一张内容卡），
  而叠叠乐的末端规则是「末卡底边停在可见区下沿」—— 所以拆掉内层滚动**不会**让
  底部读不到。代价写下来：`.refreshable` 随之失效（它必须挂在 ScrollView 上），
  但两条入口本来就在（读不到时那句「重新加载」，以及页面级的重新取数）。
- **同一类里还有一个更硬的**：`MaintenanceMoneyView` 的「＋（添加保养记录）」原来只挂在
  `.toolbar` 上，而导航栏在全 App 是隐藏的 —— 那个入口从未显示过，等于这条功能
  没有入口。现在它是内容里的一个按钮，形状抄「里程记账」那张卡的「添加记录」。
- **同一类里还有两个，当时先留了一轮**：`DevView`（卡「诊断」）与 `EmergencyPanel`
  （卡「应急」）各自也包着一层 `ScrollView`。留着的理由是「它们是**中间卡**，
  底部也许够不到，内层滚动承担的正是那一段」。**这个推理是错的**，当场算了一遍：
  卡片从「吸住」到「末端」之间要走过的距离是**它自己的全高 + 它后面所有卡的总高**，
  所以任意一张卡的底边都能落到可见区下沿
  （`S_i − maxScroll = −h_末 − Σ_(j>i)(h_j + 间隙) ≤ 0`）——
  叠叠乐**本来就管得住**任何一张卡，内层滚动只是白拿一块手势。
  于是这两个也一起拆了（页标题同理：卡头已写「诊断」「应急」）。

### ③ 卡头已经写过名字，正文不再写第二遍

`DSSectionHeader.title` 改成可空（默认 `""`）。三处标题是「同一个东西两个名字」：

- 「用车提示」卡（卡头）vs 它内容里的 `DSSectionHeader(title: "用车提示")`；
- 「里程记账」卡 vs `DSSectionHeader(title: "里程记账")`；
- 「车的事件」卡 vs `DSSectionHeader(title: "车辆消息与事件")`。

三处都只剩右侧那个动作（「全部已读」）。这一条是**上一轮同一条判据的续集**
（「常来之地 / 常停之地」「驾驶评分 / 评分」），这次把它做成了 DS 层的能力而不是
逐处绕开 —— 下次不需要再想一遍。

### ④ `delguard.py` 自己的假阳性（工程侧）

改 `WallpaperService` 时把 `var image: UIImage?` 收成 `private(set) var image: UIImage?`，
`delguard.py` 当场报「声明没了、使用还在」（＝编译错误）。这是**判据本身的漏**：
它的修饰符表只有裸词（`private`），认不出带括号的 `private(set)`，于是「只改了可见性」
被当成了「删了声明」。判据已改成 `(?:public|internal|private|fileprivate)(?:\(set\))?`
（并抽成 `MODIFIER` 常量——带括号的修饰符摆进那条正则里时，括号配对本就容易数错，
抽出来以后一处一版）。

### ⑤ 间距统一（同一天补完：吸附 111 处 + 补刻度 + 新增门禁）

用户原话：「所有页面的间距布局都很不 iOS 的设计标准！！！！！！！」。这一条上一轮
以「范围太宽、没有渲染能力」挂起过一次 —— 挂起的代价是一个持续存在的观感问题，
而它其实是可以**机械地**做完的：

1. **刻度补上缺的一档**：`TokensSpacing.snug = 12`。原阶梯是 2/4/8/16/…，全 App 有
   十几处用 `10 / 11 / 12` 去凑这一档 —— 能叫出名字的值才是同一个决定。
2. **吸附**：22 个文件 **111 处**间距字面量 → `TokensSpacing`（取最近一档，平手取大，
   所以单处位移 ≤ 2pt）。四个**几何值**不动，它们不是节奏：`18`（叠叠乐卡片内边距，
   对齐用，改了会与卡片错位）、`20`（页边距在刻度里叫 `page`，不能当通用 20 用）、
   `40`（引导页正文宽度）、`108`（巨字头到屏顶的距离）；`0` 与 `1` 是排版手法（不要间距、
   1pt 贴合）。
3. **不让它再长回来**：新增门禁 `scan/spacing.py`（已进 CI 的 `for s in …` 清单，
   本地由 `scan/all.py` 自动跟上，共 **26 条**）：界面代码里出现间距字面量就报红，
   例外只有上面那六个值且逐条写明理由。这才是「做完」与「这次改完」的区别。

同时按同一判据扫到并收尾的还有：`CarKeeper/Services/FamilyAndKeySharing.swift`
（它也含界面代码 —— 仓库有两个 Services 目录，门禁的范围把两块都算上）。

### 未做（如实说明）

- **壁纸两条在线源没有在真机上取过图**：本机不跑 Swift，只能保证解析是防御式的
  （对面改形状 → 记为失败 → 保留上一天那张 → 设置行说明）。第一次上真机要看一眼
  「我的 → 应用 → 背景图」。

本地 `python3 scan/all.py` **26/26 通过**（含新增的 `spacing.py` 与 `delguard.py`
修正），`node CarKeeper/check_style.js` **0 个问题**。编译仍然只有 CI 能验。
## 地图数据改抽屉 + 底条加大 + 按 HIG 校控件尺寸（2026-09-25 同日第二轮）

用户原话：「① 地图页数据用抽屉的方式展示，默认只有续航 电量 车速，其他数据均通过拉开
抽屉展示；② 底部的滑动导航选中的宽度加大，滑动区变高，感觉现在的全界面的控件大小都很
不 iOS，ios27 的设计标准你好好读读」。

先把「设计标准」查到了手上（都是当天读的官方页面，不是凭印象）：

- **HIG · Layout**（`design/human-interface-guidelines/layout`，更新时间 2026-09-09）：
  “Use **progressive disclosure** to make layouts cleaner and easier to interact with…
  reduce how much content to initially display”，以及 “Order content by relative
  importance… place the most important items near the top” 与 “Differentiate controls
  from content. Take advantage of the **Liquid Glass** material… use a scroll edge effect”。
- **HIG · Segmented controls**：“Limit the number of segments… no more than about five
  to seven segments in a wide interface and **no more than about five segments on
  iPhone**”；“In general, **keep segment size consistent**… When all segments have equal
  width, a segmented control feels balanced”。
- **Apple「What's new · Design」**（2026-09-17 / 09-09 两条）：iOS 27 与 iPadOS 27 的设计
  套件已发布；新机型 iPhone Duo（折叠）的指引里专门讲了“工具条与 Tab 栏转到竖直轴”。
  即：iOS 26 起的 Liquid Glass 语言到 27 仍然成立，官方控件仍以「浮动玻璃栏 + 宽间距」为形。

### ① 地图那张大卡：默认三个数，其余进抽屉

`MapSpineReadouts.swift`：原来的「四格读数」（车速 / 电量 / 胎压 / 车锁）拆成两份 ——

- **默认一排**：`readoutsPrimary` = **电量 + 车速**。第三个数「续航」不在这排里，因为它是
  这张卡的**巨字**（`DSBigNumber`）—— 再摆一格「续航 412 km」就是把一个数说两遍，而这个
  仓库上一次删掉的正是同类重复（副行里那句「电量 68%」）。所以默认一屏恰好是用户点名的
  三个数：**续航（巨字）/ 电量 / 车速**。两格分一行 → 每格宽度翻倍。
- **抽屉**：`readoutsMore` = 胎压（取四轮最低那条）/ 车锁 / 充电时才有的「还要充多久」。
  没在充电时它只有两格，而不是留一格空的。
- `moreDrawer`：一道拉手（一条 3pt 横线 + 「更多读数」+ 上下箭头）。它**同时是按钮与
  拖动面**：点一下开合，上拖 12pt 开、下拖 12pt 收（12pt 与底条那条手势同一个门槛）。
  命中区按 HIG 的最小触控目标给足 **44pt**，而画出来的只有一条细线 —— 手感来自可点面积。
  收起时它**不占高度**（不是「高度 0 还在那儿」的那种）。
- 抽屉状态 `drawerOpen` 住在本档视图上（默认关），不持久化：它是「这一眼想看多少」，不是设置。

### ② 底条：选中的更宽、滑动区更高（`DSSwipeStrip`）

| 量 | 原来 | 现在 | 为什么 |
|---|---|---|---|
| 条高 `barHeight` | 46 | **54** | 用户「滑动区变高」；这条子既是显示也是它唯一的拖动面（叠叠乐/底条都没有系统 `ScrollView`），所以「更大」=「更好按」。54 也与 iOS 26/27 那批浮动玻璃栏同量级 |
| 一档宽 `slot` | 34 | **38** | 用户「控件大小都很不 iOS」+「选中的宽度加大」的另一半：它决定静止条宽（三档装得下），所以整条一起变大 |
| 选中胶囊 | 格宽 ×1.75 | 格宽 **×1.9** | 它是选中**指示器**，比它盖住的那一段宽 —— 而各段仍然等宽（HIG 那条「各段等宽」管的是分段），所以吸附与透镜计算都不受影响 |
| 底条命中区 | 只有画出来的部分 | **整条 + 离底那 26pt 空白带** | `contentShape(Rectangle())`：不改变任何画出来的东西，只是让拇指自然停放的那圈也能拖 |

连带：`armSize` 50 → 58（原型那条「圆钮 = 条高 + 4」的关系），`barTotal` 86 → **94**
（26 + 54 + 14，派生量）。

### ③ 控件尺寸：先补三个「只有一行字」的按钮

HIG 的最小触控目标是 44pt —— 而界面里最小的几枚按钮只有 13pt 高的字：

- `DSSectionHeader` 右侧那个动作（「全部已读」这类，**全 App 到处在用**）→ `minHeight: 44`；
- 「我的 → 应用 → 背景图」那三个小钮（选一张 / 重试 / 不铺）→ `minHeight: 44`；
- 地图卡里的抽屉拉手 → `minHeight: 44`（见 ①）。

**没做、且说清楚为什么**：HIG 那条「iPhone 上分段控件不超过 5 段」与现在的模式条 **6 档**
不一致。没有动它 —— 六档是这个 App 的信息架构（每一档是一个完整功能界面），
而那条指引针对的是**系统分段控件**的用法；硬压成 5 档等于删掉一个功能。
这笔账写在这里，下一轮如果要收档位，依据是它。

### 未做（如实说明）

- 控件尺寸只改了上面三处（每一处都是「点中靠运气」那种）。剩下的还有：`DSChip` 一族、
  各页里 `TokensTypo.footnote/caption` 大小的小钮。它们要一屏一屏看，而本地没有渲染能力。
- 抽屉与底条的新尺寸都**没有在真机上量过**：54/38/1.9 是照 HIG 的量级与本仓原型比例算的，
  第一次上真机要看「静止时三档露出来多少」「展开后是不是正好占满整行」。

本地 `python3 scan/all.py` **26/26 通过**（含 `spacing.py`），
`node CarKeeper/check_style.js` **0 个问题**。编译仍然只有 CI 能验。
## 展开类内容：高度一律算出来，不许猜（2026-09-25 同日第三轮）

用户原话：「所有卡片内需要展开的都要严格计算展开后的拥挤程度，完全根据数据来，不能猜」。

### 新增 `Design/CardFit.swift`：唯一的「展开后有多挤」算法

一个手写的长度常量都没有，只吃三种真实来源：

| 来源 | 取法 | 为什么不能用常量 |
|---|---|---|
| 一行的真实高度 | `UIFont.preferredFont(forTextStyle:).lineHeight` | 字档是**跟随动态字号**的：用户把系统字号调大，行高就变，任何写下来的数都跟不了 |
| 一段文字的真实折行数 | `NSString.boundingRect(with:options:attributes:context:)` | 「字数 ÷ 每行字数」在等宽、在中英混排、在放大字号下全不成立 |
| 容器真实可用高度 | `ArcStack` 量到的视口（新的环境值 `\.cardViewport`） | 屏高不是常数（SE / 折叠 / 分屏） |

由此给出两样东西：`Verdict`（展开后占几屏）与 `Plan`（`.all` / `.chunk(keep:rest:)`，
`keep` 是**逐行累加真实高度**得出的，不是「条数 × 平均行高」）。出口只有一个 ——
`DSCardMoreRow`：「还有 N 条 · 展开后约 M 屏」，摊开后同一行变「收起」（摊开与合起来
必须是同一行，否则总有一半地方只会摊开、收不回去）。

**「不知道」是第三种答案**：视口读不到（预览、第一帧、非叠叠乐宿主）就是 `.zero` →
裁决返回 `.unknown`，**不做任何分块**，也不写「约 0 屏」那种假数。本仓库的老毛病
正是「没跑」与「跑了没问题」长得一样。

### 逐处改了什么（每个数都来自数据）

- **体检 · 检测系统**（最挤的地方）：原来 `onAppear` 把 statusCls == "bad" 的**全部**展开，
  一屏里可能摊开 24 行（6 个系统 × 4 个子项）。现在：① 自动展开按算出来的高度一个个开，
  开到放不下为止；看不到视口时只开**第一个**（不猜）；② 单个系统内部的分块按
  `CardFit.plan` 走 —— 子项里「有没有检测值 / 参考范围 / 说明」决定那一行多高，**那正是数据**。
- **消息**：正文从前是 `lineLimit(isOpen ? nil : 2)` —— 收起有界、展开无界，一条长通知
  能把卡变成三屏。现在展开时按算出来的行数放，切点用二分**量出来的**（每一次都真量
  一遍那个前缀在这个宽度下占几行）。标题那一行的可用宽也是量的（整行宽 − 标签与时间
  的真实宽 − 图标列）—— 原来是「标题按 60% 宽算」，那个 0.6 才是猜的。
- **车控 · 指令历史**：历史桶上限 50 条，全列出来再摊开几条就是三屏多。现在能列几条
  是算出来的：一条收起 ≈ 两行，摊开 +4 条键值行，于是「能放几条」随摊开状态一起变。
- **导出预览**：`ScrollView { Text(…).lineLimit(8) }.frame(height: 100)` 一个人占了两件错 ——
  卡片里套滚动（叠叠乐自管手势，内层拿无限高：永远滚不动却吃掉拖动）+ 拍出来的高度。
  现在只剩一块内容撑高的块，放不下就切在量出来的行边界上。
- **车控 · 车形俯视图**：`.frame(height: 286)` → 形状定高（320:470 是画布自己的比例，
  现在是 `CarTopView.artSize` 一处声明）+ 按量到的视口封顶。286 那个数还有个具体后果：
  画布按 `min` 缩放，高度写小了就白拿一圈左右留白（380pt 宽的机器上那台车只有 195pt 宽）。

### 新增门禁 `scan/expand.py`（第 27 条）

判据只有一条：界面代码里不得出现 `frame(height: 数字)`（**只给高度、没给宽度**的那种；
`frame(width: 44, height: 44)` 是形状，不管）。例外表 11 条，键是「文件:值」，每条都要
写清「为什么这个高度是画出来的」—— 图表（Swift Charts 没有固有高度）、指示线、样例色块、
壁纸缩略图、小地图缩略图。表里**一条不成立就报红**（改了值 / 删了那块），
因为「留在表里的旧理由」会让下一个人以为「它可以写死」。

### 顺带：`ControlView` 从 1168 行降到 1101

它已经贴着 `lintcfg.py` 的 1200 行阈值，而这一轮还要往里加东西 —— 于是把
「展开后有多挤」那一块搬到同目录的 `ControlFit.swift`（81 行，一个 extension）。
三个状态（`expandedRuns` / `historyFull` / `cardViewport`）随之去掉 `private`，两处都写了原因。

### 未做 / 待真机核

- 分块**首次出现的阈值**在真机上是什么样，本机无法渲染：本地没有 Swift 工具链，
  编译与观感都只有 CI / 真机能回答。
- 几处键值行的内边距（自带上下 8）在高度模型里用 `TokensSpacing.md` 近似 ——
  单行 ±8pt 不改变裁决（裁决是按屏数分的），但「有没有这一行」必须准：那才是数据。
  这条容差写在每个调用点的注里，不是暗账。
## 地毯式对抗式审核（2026-09-25 同日第四轮）

用户原话：「再次进行全项目地毯式对抗式审核，找出不合理，往更好的设计方向做，查漏补缺」。

### 方法：先把「找什么」变成可执行的东西

不靠通读（通读的判断只生效一次）。用一次全仓扫描列出**成类的问题**，再逐类核实：

| 探针 | 命中 | 其中真的假的 |
|---|---|---|
| 弃用写法（`foregroundColor` / `cornerRadius`） | 11 处 | 6 + 3 真（另 2 处是 Swift Charts 的 `BarMark.cornerRadius`，**同名不同物**，动了就坏） |
| 静默失败（`print(`） | 2 处 | 2 真 —— 全仓仅有的两个 print，都是「提醒没发出去」 |
| `try?` 吞错 | 80 处 | 多数是「读 UserDefaults」这种不该炸的地方，一处未动 |
| 未保存的 `Timer` 返回值 | 2 处 | 2 真（存不下来 = 永远停不掉、重复启动就叠加） |
| `kSec*` 密钥串 | 1 处 | 1 真（一个文件里两个名字指同一件东西，其中一个是死的） |
| `carkeeper_*` 键：只写不读 / 只读不写 | 44 键 → 10 键可疑 | **7 个是「幽灵功能」**（`dnd_mode` 只写；`charge_notify`/`charge_complete_notify`/`current_speed`/`next_service_date`/`night_start_hour`/`night_end_hour` 只读），3 个是扫描器的假阳性（计算属性 get/set、变量式写入） |

### 查出来并修掉的（每一处都点名了「是谁在说谎」）

1. **`SmartNotificationManager`（N15–N20）整族是空的 —— 已删。** 六个通知类型的方法
   （低电量 / 充满 / 胎压 / 保养 / 行程 / 勿扰）**一处调用都没有**；它真正会做的事只有两件：
   启动时弹一次通知权限（那一次权限由真正会发通知的三条路各自申请）、注册三个分类
   （而分类上的动作——立即充电 / 查看胎压 / 关闭勿扰——全仓没有
   `UNUserNotificationCenterDelegate`，点了什么都不会发生）。留着它的唯一效果是
   启动时多一个弹窗。真正会发通知的三条路都在：`ChargingStatusMonitor`（报文驱动）、
   `MaintenanceReminderScheduler`、`InsuranceReminderScheduler`。
2. **`DataEncryption` + `SecureStorage`：一次只写不读的「加密」。** 它把车牌 AES-GCM
   加密后写进 UserDefaults（`enc_plate`），而**全仓没有一处读它**；写入失败还是静默的
   （密钥取不到就什么都不写、也不报）。而 HANDOFF 的服务表里写着「用于车牌等敏感字段」——
   文档在替它说谎。已删（连同 `AppStore` 里那一句 `savePlate` 与启动时的 `ensureKey()`），
   文档同步改成事实。
3. **「夜间模式」这个开关对界面没有任何作用 —— 已接通。** 全 App 的明暗一直来自
   `ArtThemeStore.current.spec.preferredScheme`（艺术方向自带），`NightModeManager.isDarkMode`
   除它自己那一行以外没有读者，而它 post 的 `nightModeChanged` 一个观察者都没有。
   现在：`CarKeeperApp` 两个窗口都读 `NightModeManager.schemeOverride`（选择器选「自动」时
   返回 nil = 交给艺术方向，这才是这个 App 的明暗观念）。随之删掉的是「按钟点 21:00–07:00
   自动切换」那套逻辑与它读的两个键（`carkeeper_night_start_hour` / `_end_hour`）——
   全仓没有一处写它们，而且它会把「夜光」这类**故意做成暗的主题**在白天强行翻成亮色。
   顺带修掉一个真的 bug：`isDarkMode` 的 `didSet` 会把「自动」误写成「强制深色」，
   现在已经加了条件；`setMode(.auto)` 也会把两个强制标记都清掉。
4. **`AppStore.shouldUseDarkMode()` / `isNightMode` / `forceDarkMode` / `forceLightMode`：
   「现在是不是夜间」的第二套实现，而且是死的那种。** 它把 UserDefaults 读进 `static let`
   （进程内只读一次，改了也不会变），并且全仓没有调用方。已删。
5. **`FocusModeManager.isDriving`：永远为 false 的属性。** 它读 `carkeeper_current_speed`，
   而全仓没有一处写这个键 → 永远读回 0 → `> 5` 永远不成立；它本身也没有调用方。已删
   （车速的真实来源只有一个：`VM.driveStatus(store.caches).speed`）。
6. **`enableDDrivingMode()` / `disableDDrivingMode()`（写 `carkeeper_dnd_mode`，没人读）
   与 `checkServiceDue(nextDate:)`（读 `carkeeper_next_service_date`，没人写）** —— 都在
   被删的那个文件里，随之消失。后者还带着一个死分支：`nextDay >= today && nextDay <= sevenDays`
   先判，于是 `else if nextDay == today` 那一段（「保养到期」的另一种文案）**永远到不了**。
7. **两个存不下来的定时器（`MemoryMonitor` / `NetworkQualityMonitor`）。** 返回值直接丢掉
   → 谁都无法让它停下；调两次就是两个循环各自跑。现在存下来、判重、加了 `stop()` 与 `deinit`。
8. **两处 `print(`（提醒调度失败）** → 改成写进「诊断」页正在读的那本日志
   （`RawLogStore`，会打码、限长，并同时写一条系统日志）。`print` 的问题不是吵，是**没有读者**。
9. **充电页「续航 --」** —— 无数据时画一句占位置的空话。现在三个数都没有就不出现那一行。
10. **弃用写法与形状**：6 处 `foregroundColor` → `foregroundStyle`；3 处写死圆角的
    `.cornerRadius(N)` → `Capsule()` / `RoundedRectangle(cornerRadius: TokensRadius.small)`
    （**另外 2 处同名同形的 `BarMark.cornerRadius` 是 Swift Charts 的 API，没动**）。
    文件、服务清单与文档里的漂移一并改了（HANDOFF 的服务表不再写「车牌加密」）。

### 新增门禁 `scan/printguard.py`（第 28 条）

判据：App / Services 代码里不得出现 `print(`。理由写进了它的头注：`print` 是最容易
被当成「已经处理了错误」而留下来的东西（调试器能看到的人只有开发者本人），而这个仓库
已经有两处真实事故级的东西死在这上面。例外只有一处：设计令牌页自己的调试输出。

### 仍然开着的（如实记账）

- **⚠️ 已作废（第十轮）**：下面这条说「四关全关」—— 用户 2026-09-25 回执「先正常启动试一次」，
  四个开关已**全部打开**，见本文末「第十轮」一节。原文留在这里当记录。
- **`LaunchFence` 四关全关 —— 这台机器上的 App 一直跑在「最小启动」。** 没有开场动画、
  地图不取数、那批启动服务（内存监控 / 网络质量 / 离线监听 / 摇一摇 / 专注模式 / 提醒调度 /
  远程锁定…）都没装。它是一台**临时仪器**（二分定位「载入不到 10 秒就退」），
  下一版按计划只把 `sixPageDeck` 打开跑一次就能把范围砍一半 —— 那一步必须用真机。
  这是目前唯一一处「App 不在正常形态」的地方。
- `MapSpineView.swift` **1182 行**，离 `lintcfg.py` 的 1200 阈值只剩 18 行。下一轮任何
  往里加东西的改动都会先撞上它（这一轮已经为此把 `ControlView` 拆出 `ControlFit.swift`）。
- 44 个 `carkeeper_*` 键里仍有 4 个「只读不写」的假阳性（`last_service_mileage` 走计算属性、
  `voice_enabled` 走变量式写入等）；**没有**改成门禁，因为把变量式写入也判准需要再做一层
  名字解析 —— 记账在这里，下一次要做的话从「键 → 常量 → 用法」这一段开始。

## 液态玻璃的全项目核对（2026-09-25，第 28 条门禁）

用户：「全局液态玻璃的质感全项目每个犄角旮旯方方面面都做到位了吗」。

**答案是「没有」，而且病根是名字，不是细节。** 逐处查下来是三件事：

1. **真玻璃只有 3 处** —— 卡片（`GlassCard`）、底部模式条（`DSSwipeStrip`）、地图那颗
   圆形机械钮（`MapSpineView`）。其余每一处**浮在内容之上**的表面 —— 轻提示
   （`CarKeeperApp` 的 Toast）、次操作按钮（`DSSecondaryButtonStyle`）、地图上的图层
   胶囊、分段控件的凹槽、芯片、搜索框 —— 用的都是 `TokensPalette.glassLight`，
   而那个令牌**就是 `fillSubtle`**（同一个值、两个名字，`Tokens.swift` 自己写着
   「兼容旧名」）。也就是说：一个叫 glass 的名字下面是一块**扁平色**——不折射、
   不反射、不随底下内容变。那是材质的**假象**。
2. **两处把玻璃垫在不透明的面底下**：模式条是 `Capsule().fill(fillSubtle)` 再接
   `.glassEffect(...)`；地图圆钮是 `Circle().fill(glassHighlight)` 再接玻璃。
   材质本身被那块面挡掉了 —— 看起来是「磨砂色块 + 一圈高光」。这两处恰好是
   用户最常看的两块玻璃（模式条与地图圆钮）。
3. **两个名字在说谎**：`TokensPalette.glassBorder` 其实是 `spec.hairline`（12 位用户里
   只有 4 位在给玻璃描边，其余是图表网格线、读数分隔线）；`DSSurfaceModifier.glass:`
   是「更亮的底」，与玻璃无关。`DSCard` 更干脆：它的 `glass:` 与 `hero:` 两个参数
   **存下来就没再读过**（`body` 永远填 `nightSurface`）—— 谁写 `DSCard(glass: true)`
   都会以为拿到了材质，而其实什么都没发生。

### 做了什么

- **`Design/DSGlass.swift` 成为唯一入口**（`dsGlass` / `dsGlassCapsule` /
  `dsGlassRounded` / `dsGlassLayer`）。三层规则写在文件头：浮层 → 真玻璃；**卡里不玻璃**；
  内容表面不玻璃。变体按**底下是什么**选（`.regular` / `.overMedia`），可点的表面传
  `interactive`（按下去的压缩与折射由系统演 —— 不再自己压 `opacity`）。
- **每一处浮层搬到它名下**：轻提示（原来是一块 90% 不透明的扁平色，现在底下真的透出来）、
  次操作按钮（iOS 26 的次级按钮就是玻璃胶囊）、地图图层胶囊（`.overMedia`：地图保持可见，
  只在边缘折射）、两枚圆钮（去掉假高光、改 `interactive`）。
- **模式条底下那块扁平填充删掉**（`Color.clear` 只留尺寸）。同一行三块玻璃
  （左钮 / 模式条 / 右钮）由 `dsGlassLayer(spacing: barSeam)` 包成**一层** ——
  没有容器时它们各自按自己的边界算，挨在一起边缘会互相打架。中缝那个 `9` 因此有了名字
  （`MapSpineView.barSeam`，玻璃层的合并距离与它取同一个值）。
- **令牌收干净**：删 `glassLight`（＝`fillSubtle` 的重复声明，四处调用点改用 `fillSubtle`）、
  删 `glassBorder`（＝`hairline`，12 处改名）。现在全仓**没有一个叫 glass 的扁平令牌**，
  读到 glass 就一定是真材质；剩下的 `glassHighlight` 是「玻璃**里面**那一层更亮的形状」
  （模式条上被选中的那一枚），它的注里写明了它不是拿来当底的。
- **`DSCard` 的两个死参数删掉**；`DSSurfaceModifier.glass:` → `subtle:`；
  天空面板那块本地的 `cardBackground`（「卡的面」的第三套实现）删掉，改走 `dsSurface`。
- **新增门禁 `scan/glass.py`（第 28 条）**，四条判据：别处直连 `.glassEffect`、
  别处直连 `GlassEffectContainer`、**玻璃底下垫了不透明的面**（同一条链里
  `.fill(TokensPalette.…)` 出现在 `.dsGlass` 之前）、再引入旧材质语言（`…Material`）。
  牙齿验过两种注入：直连 `.glassEffect` 报红、`Circle().fill(...)` 接 `.dsGlass` 报红；
  而「玻璃**之后**的 `.overlay { … }`」不报（那是盖在玻璃上面，正当）。
- **它当场逼出两处判据自己的错**：① `scan.py` 把**刚声明的泛型形参**当成「未声明的类型」
  （`<S: Shape>` 里的 `S` 前面正是 `<`）—— 已补 `GENERIC` 收泛型形参，并登记三个当天
  核过 Apple 文档 JSON 的 SDK 名（`Glass` s:7SwiftUI5GlassV、`GlassEffectContainer`
  s:7SwiftUI20GlassEffectContainerV、`View.glassEffect(_:in:)`）；② `orphans.py` 把
  `DSGlass.swift` 里只作参数类型出现的 `DSGlassVariant` 判成孤儿（调用点写 `.overMedia`，
  隐式成员表达式，判据看不见类型名）—— 顺手把两个纯搬运的包装类型删掉（只剩这一个），
  并在白名单里写明理由与代价。

### 仍然开着的（如实记账）

- 整屏的**观感**没人验过：本机没有 Swift 工具链，29 项本地验证全是静态的。
  第一次上真机要看的是：模式条那三块玻璃的**边缘是否真的互相折射**（这是
  `dsGlassLayer` 存在的唯一理由）、`.overMedia` 的图层胶囊在**浅色地图**上文字够不够读。
- **模式条内部那枚被选中的胶囊仍是「更亮的填充」而不是第二块玻璃**：按规则 ②，
  一块表面里不叠第二块玻璃（叠了会糊），而它是**选中指示器**。若真机上觉得它该有厚度，
  正确的做法是把它和条子一起交给同一个容器去 morph，而不是再挂一层材质。
- **主按钮没动**：`DSPrimaryButtonStyle` 仍是实心强调色胶囊（HIG 的「突出」按钮），
  不是着色玻璃 —— 这一条是选择，不是遗漏。
- 编号说明：老记录里写的「第 27 条 / 第 28 条」是当时手数的；`spacing` 插进 CI 清单中段
  之后全部后移了一位，现在以 HANDOFF §8.1 那张表（＝CI 清单顺序）为准。

## 刷新节律 + 行程上限 + 移除变私库自动化（2026-09-25）

用户一次提了四件事：「地图页车在动 2 秒刷一次、停着 1 分钟一次，其他页面 5 分钟一次，
地图页的全局刷新可以刷新全部 api」「行程页最大 30 条，其他以消息显示」
「移除变私库的自动化」，外加一句总要求「每个卡片逐个过，看还有没有更好的设计效果，
要体现人性化精致感 / iOS 27 液态玻璃 / 苹果风 / 便捷性 / 艺术感」。

### ① 刷新节律：**一个循环**，不是每页一个定时器（`Services/RefreshLoop.swift`，新增）

在那之前全 App **没有周期性刷新** —— 只有 `.task` 的一次性取数与几处手动刷新
（地图页那天「重取数据」、各页 `.onAppear`）。所以这一条不是调参，是新增一条**节律**。

为什么不做成「每页一个 `Timer`」：六页是**同时建出来**的（`MapSpineView.pageDeck`），
每页一个定时器就是六个循环各按自己的节律问同一个服务端，换一次档会把六份请求都点着。
所以节律只有一个来源，由两个输入算出来，而这两个输入各自也只有一处出：

| 何时 | 间隔 | 取什么 | 输入 |
|---|---|---|---|
| 地图页 · 车在动 | **2 s** | `fetchCore()`（车况四项） | `AppStore.isCarMoving`（`VehicleSpeed > 0`） |
| 地图页 · 车停着 | **60 s** | `fetchCore()` | 同上 |
| 其他五档 | **300 s** | `fetchVehicleData()`（含消息与体检） | `HomeMode.storageKey`（模式条写的那个键） |

三条自我约束写在文件头：**不并发**（一次取数 `await` 完了才睡下一次 —— 2 秒的节律下，
弱网里一次请求可能比间隔还长，那正是「同一秒点着两趟」最容易发生的地方）、
**没登录 / 没车不取**、**进后台不做特殊处理**（进程被挂起，`Task.sleep` 随之停摆）。

它**不在** `LaunchFence` 的四个开关里：那四个是「启动期做了哪些事」的二分实验，
而这个循环第一次取数在 2/60/300 秒之后，与「载入不到 10 秒就退」不在同一个时间窗
（这一条也写进了 `mapFetches` 的注）。

顺带把两具「曾经写上去、后来没人用」的东西清了：`AppStore` 的请求去重对
（`inFlightRequests` / `markRequestStarted` / `markRequestFinished`，全仓零调用 ——
现在「不并发」只有一处机制，就是上面那条 `await` 链）与 `DriveModel.isMoving`
（字段一直在算，没有任何读者；现在它是节律的输入）。

### ② 地图页的「全局刷新」= 全部接口（并给一句回音）

图层面板里那一项从「重取数据」改名「**全局刷新**」，走 `RefreshLoop.refreshAll()`
（`fetchVehicleData`：车况 + 消息 + 体检），不是自动那趟的加强版。刷完弹一句：
全取到就是「已取到最新数据」，有缺项就**如实说几项**（缺项来自 `saveCache` 里值为 nil
的那些键，新增 `AppStore.lastMissedSources`）。一颗按下去没有回音的按钮，
用户只会怀疑它没生效 —— 而它其实取完了。自动那趟**不弹**（每 2 秒弹一次就是噪音）。

### ③ 行程页：上限 30 段，超出的按「消息」读

`tripCardCap = 30`：一次仍只建 5 张由人点（每张行程卡里是一张**真的** `MiniTripMap`，
227 条消息能配出几十段），到 30 之后那一行**换成陈述句**而不是灰按钮 ——
「按了没反应」与「这里没有可按的东西」是两件事，而用户只会读成前者。
超出的那些**没有丢**：点火/熄火事件本来就一条条列在「车的事件」卡里（同一份消息的另一种读法）。

### ④ 移除变私库的自动化

CI 里的 `make-private` job 整个删掉（连同它 100 行的说明）。理由是两层：
① 那个 `PATCH /repos/{owner}/{repo}` 需要**仓库级 Administration 写权限**的 PAT
（`GITHUB_TOKEN` 的 permissions 清单里没有 `administration`，拿它调只会 403），
于是仓库要长期养一条流水线上权限最高的密钥；②「这个仓是不是私有」是一句**人的决定**，
不该由 CI 的终态判据去维持。`REPO_ADMIN_TOKEN` 这个 secret 现在没人读，请手动删掉。
「为额度加的三条」（concurrency / paths-ignore / timeout）留着 —— 它们省的是 runner
时间本身，与可见性无关（文档里那句「转私有后的额度」已改掉）。

### ⑤ 过卡片时改掉的几处（「更好的设计效果」里能落地的）

- **`MapSpineView.swift` 1201 行 → 1111 行**：越过 `lintcfg.py` 的 1200 阈值，
  于是把「光」表拆成 `MapSkySheet.swift`（连同共用原语 `MapNotice`）。
  **拆的是文件，界面一字未改** —— 唯一变的是「关掉这张表」：原来写宿主的
  `showSky = false`，现在写同一个状态的绑定 `isOpen = false`。
  四个图层与评分段那几处 `emptyNotice` 调用点一字未动（保留一行转发）。
- **体检卡带上取数时刻**（`at: store.cacheTime("check")`）：它读的那份读数每 5 分钟才换一次，
  不写时刻，用户没法判断「这条异常是刚才的，还是上周打开 App 时留下的」。
  **保养卡故意不加**：它的正文是本地录入的记录，挂一个「取数时刻」是误导。
- **出行空态那两行原来在说同一件事**（「还没有行程记录」/「还没有出行记录」——
  `copy.py` 拦的正是这种复述）：第二行改成**为什么**会有记录（「点火与熄火各记一次，
  配成一段行程。」）。

**没跟着改的，是一笔明账**：其余各档的卡片（充电「此刻/明细/电池/趋势」、车控「车身/指令/场景/记录」、
我的「账号/车辆/设置/关于」、车辆的「身份/用车提示/里程记账/维保照片」）逐张看过，
**没有再发现「内容不合理」或「展开后拥挤」这一类** —— 充电那四张早就带了 `at:`（同源时刻），
车辆与我的几页读的是本地记录或启动那一趟的车辆列表（没有「几点取到」可言），
所以这一轮在它们身上没有施工对象。这句是「看过了」，不是「都做完」。

**验证状态**：本地 **29/29 门禁 + 风格检查 0 问题**全绿；**编译与观感只有 CI / 真机能回答**
（本机没有 Swift 工具链）。真机上第一次要看的三件事：2 秒节律下车速/电量的跳动是否顺眼
（会不会太跳）、手动「全局刷新」那一句提示的时机、以及模式条内部那枚选中格在 2 秒刷新下的重绘开销。

## CI 红：extension 的三条铁律（2026-09-25，第 29 条门禁）

用户在 CI 日志里贴来两条错误：

```
MapSpineBottomBar.swift:71:13: error: declaration is only valid at file scope
    private extension Double {
```

`MapSpineBottomBar.swift` 是**上一轮某个 agent**为了让 `MapSpineView.swift` 回到
`lintcfg.py` 的 1200 行阈值以内，把「底条整行横拖」搬出去的新文件。它**从来没有编译过**，
而它一台戏犯了三个错：

1. **嵌套 extension** —— `private extension Double` 写在 `extension MapSpineView { … }` **体内**
   （Swift 只允许文件层）。
2. **extension 里的实例存储属性** —— `@State private var barDragBase: Double?`
   （extension 只能加计算属性与方法）。
3. **跨文件碰了别处的 `private`** —— 它读写 `modePosition` / `barOpen` / `modeIndex` /
   `barRowWidth`，四个都在 `MapSpineView.swift` 里声明为 `private`，而
   **`private` 的作用域是文件**。同一个错在 `ControlFit.swift` 里还有第二处：
   它用 `ControlView.filteredRuns`（那边也是 `private`）。

**而 29 条门禁一条都没拦住。** 这不是判据写错了，是三条判据里没有一条知道
「extension 该长什么样」—— 结构性问题里最基础的那一类，恰恰是盲区。

### 修法

- 那个文件**整体撤掉**：「底条整行横拖」搬回 `MapSpineView.swift`，与它控制的
  `barDragBase` 住在同一个类型本体里（`MapSpineView.swift` 现在 1178 行，仍在阈值内）。
  搬回来之后那四个成员**各自保持 `private`** —— 拆文件曾经的代价就是要把它降级成模块级可见。
- `ControlView.filteredRuns` 去掉 `private`（并在声明处写清为什么：`ControlFit.swift` 要用它）。
- `private extension Double` 放到**文件作用域**（`Swift.min/max` 的双向夹）。
- 顺手做了一次**更严的探针**（不限名字长度、连 `self.name` 一起查）：全仓
  **没有第三处**这一类错误。

### 新增第 29 条门禁 `scan/extguard.py`

三条判据就是上面三个错，逐条写在它的文件头里：
① extension 必须在文件层；② 直接成员层不许有实例存储属性（`static` 与
`@ViewBuilder` 这类结果构建器放行）；③ 跨文件不许碰别处的 `private` / `fileprivate` 成员。

**探针（双向验证，按本仓惯例；2026-09-25 复跑过一次）**：
· 注入一个探针文件，里面写**错①**（嵌套 extension）与**错②**（`@State` 存储属性）
  → **两条都报**、退出码 1；撤掉 → 转绿。
· 把 `filteredRuns` 临时改回 `private` → 当场报出 `ControlFit.swift:58/63`
  （这就是那次真事故本身，证明判据 ③ 不是为探针写的）。

**第一版探针写错了，记在这里**：我最初想在**同一个**探针文件里一次写全三条，
结果是 ①② 报、③ 不报 —— 而 ③ 不报**是对的**：`private` 的作用域是文件，
在同一个文件里用私有成员完全合法，我的探针把宿主与扩展放在了一起，
压根没构造出「跨文件」那个形状。

「探针不报」有两种可能：判据漏了，或者探针没造成那个形状。这一次是后者。
差点把「三条都报」写进文档 —— 那份文档会替一条**从未验过**的判据担保。
这就是本仓那条老规矩的另一面：证明要能证伪，探针自己也得先说清它造了什么形状。

**它在诞生当天就捉到了自己的两个 bug，都记在文件里**：
· 第一版把「成员层」的深度算漏了 1（没有把 extension 自己那个 `{` 算进去）——
  于是 17 处**函数体里的局部变量**被当成存储属性报红。判据错报比漏报更糟：
  它会让人把整条门禁关掉。
· 第二版收集私有成员时 `TYPE_BODY` 漏了 `re.M` —— `^` 只在文件开头匹配，
  收集到的类型数是 0，于是判据 ③ **静默全绿**。
  这正是 `scopeguard.py` 头注里记过的同一个坑，我又踩了一次 ——
  两处都写进了注释，给下一个人看。

**收窄（写在文件头）**：判据 ③ 只认裸名字（不认 `self.name` 形态）、名字短于 6 个字符不认
（`store` / `body` 这类太容易与局部变量撞名）、本文件自己也声明过同名东西时跳过；
判据 ② 只认名单里的属性包装器。这些收窄会让某些真错误漏掉 —— 而误报会让整条门禁被无视。

**验证状态**：本地 **30/30 门禁 + 风格检查 0 问题**全绿；**编译仍然只有 CI 能回答**，
但这一次的错误类型（三条例外全是静态可判的结构错）已经被门禁接管了。

## CI 第二批红：六类编译错一次看清（2026-09-25，第 30 条门禁）

上一次修完 extension 三条铁律之后，CI **第一次走过了语法层** —— 于是编译器拿回了话语权，
一口气报出 26 条错误、六种形状。这是「这个 App 很久没有编译过」的直接账：
静态门禁能替代编译器的部分早就用尽了，剩下的全是类型系统的事。

| 处数 | 错 | 根因 | 修法 |
|---|---|---|---|
| 4 | `ArtTheme.swift:340/374/410/531` —— `extra arguments at positions #3, #4, #5, #7, …` | **一条 Swift 规则**：结构体一旦自己声明了任何 `init`，编译器就不再合成隐式的 memberwise init。`75c80ce` 给 `ArtThemeSpec` 加了「二十套主题」的便捷 init（11 个参数），而那四处照旧按**全字段成员列表**（26 项）写 —— 每个标签、每个值都没错，却全部接不下 | 把**全字段 init 显式写回来**（26 个参数，顺序 = 存储属性声明顺序）。刻意**没有**改那四处去用便捷入口：夜光/纸张/字体/原生这四套主题，每个颜色旁都写着对比度**实测值**，改用推导规则等于「把量过的值换成算出来的值」—— 那是设计变更，不是修编译 |
| 1 | `DSGlass.swift:77` —— `value of type 'S' has no member 'strokeBorder'` | 泛型约束写成了 `S: Shape`，而那圈发丝线用的是 `strokeBorder`（线画在**里面**，玻璃才有厚度感）—— 它只在 `InsettableShape` 上。约束写宽了，编译器要等到用法处才发现 | 约束收窄到 `InsettableShape`。三个便捷入口（胶囊 / 圆 / 圆角矩形）与全部六个调用点都满足 —— **不损失任何调用点**，而将来传自定义形状会自己报错 |
| 1 | `HealthDataView.swift:388` —— `ambiguous use of 'opacity'` | `Color.opacity` 与 `ShapeStyle.opacity` 同名，而 `.background(_:)` 的参数是泛型 `S: ShapeStyle` —— 在那个上下文里两个候选都合法 | 把**期望类型**写成 `Color`（一个具名局部量 `let inset: Color = …`）：返回 `some ShapeStyle` 的那一支就不成立，歧义消失 |
| 2 | `MapSpineView.swift:489/516` —— `type 'MapSpineView' has no member 'barSeam'` | 那个 `9` **从未在任何提交里被声明过**：整段注释、两个使用点（`HStack(spacing:)` 与 `dsGlassLayer`）都是同一笔写进来的，只有声明那一行没进文件 | 补回 `private static let barSeam: CGFloat = 9` —— 注释早就写明了这个 9 的来历（「中缝既是视觉上的『它们是一组』，也是系统判定『多近才算挨着』的距离」） |
| 16 | `MapStyleSpec.swift:123…183` —— `static member 'mutedSpec' cannot be used on instance of type 'ArtTheme'` | `mutedSpec` 是 **static**，而用它的 `spec` 是**实例**属性；实例上下文里裸写静态成员不合法 | 十六处全改 `Self.mutedSpec`，并在声明处写清「同一个名字在同一个类型里有两种身份时，写 `Self.` 就是在说清用的是哪一种」 |
| 1 | `MessagesSection.swift:348` —— `ambiguous use of 'accessibilityHint'` | 同一个方法在 `View` 与 `ModifiedContent` 上各有一份；那条链同时要负责定下 `DSGroupRow{…}` 的泛型 `Content` 与函数的 `some View` —— 是**推断**问题，不是语义问题 | 把行的按钮拆成自己的函数 `rowButton(_:isOpen:)`。行为一字未变（无障碍那两句仍挂在同一个 Button 上），只是每一步的期望类型都明确了 |

### 两条判据被这一次逼出来 —— 都不是「再加一条规则」，是补两个洞

**① `scan.py` 的「项目类型的未知成员」看不见 `Self.`**（`barSeam` 溜过去的原因）

`MEMBER_REF` 把 `Self.barSeam` 认成「类型 `Self` 的成员 `barSeam`」，而判据遇上不在类型表里的
名字直接 `continue` —— 于是**所有 `Self.` 引用都在盲区里**。现在 `Self.x` 会归到「本文件里
最内层的那个类型」上，走同一条判据。

**探针（双向）**：把 `barSeam` 的声明临时删掉 → 当场报出 `MapSpineView.barSeam`、退出码 1；
补回来 → 绿。昨天它什么都没说，现在能抓住。

**② 新门禁 `initguard.py`（第 30 条）：调用点的实参标签必须能被某个声明的 init 接下**

`ArtThemeSpec` 那四处是这个类的典型形态：「参数全对，却没有任何一个 init 收得下」。
它静态可判，且不依赖类型推导。三条收窄（宁可漏，不可噪）写在文件头：
只判「init 写在类型**体内**」的类型（写在 extension 里**不会**抑制 memberwise init，
那时按参数表判会误报）；只判至少两个带标签实参的调用点（`Foo(x)` 与 `init(_:)` 分不开）；
同名类型出现多处就整条跳过。

**它在诞生当天被自己的两条误报教了一次**（都记进了文件头）：

· `DSSwipeStrip(items:selectedID:follow:)` —— 嵌套的 `struct Item { init(id:title:) }`
  被算成了外层的 init，而 `DSSwipeStrip` 自己**没有** init（用的是隐式 memberwise）。
· `AppStore.swift:332` 的 `TripRecord(…)` —— `TripRecord` 有**两个**：`AppStore` 里嵌套的一个、
  `Models/AppDataModel.swift` 里顶层的一个。按裸名字把两边的 init 合起来，就会把一个合法调用
  判成接不下。同一条教训的正面写法：**「裸名字对应哪一个」要看调用点上下文，文本层面不猜。**

还有一处是**共用件的洞**：`extguard.mask` 处理行注释时只清后续字符、留下开头那根 `/`，
于是 `initguard` 认不出紧跟注释之后的 `labelTertiary:`（4 个最大的调用点全被跳过、看起来
「没问题」）。已在 mask 里清掉，并写明：它不干扰 `extguard` 自己，但会弄脏**任何按表达式切分
的下游判据**。

**探针（双向）**：当前树 0 处；删掉全字段 init（= 重演 CI 那一幕）→ **恰好报出那四处**
（353 / 387 / 423 / 544，行号随补齐的注释位移），诊断与编译器同一句；注入假标签 → 也报。

**顺带**：`InsettableShape` 按本仓惯例登记进 `scan.py` 的 `VERIFIED_SDK_ADDITIONS`
（登记前核过 Apple 文档 JSON：`s:7SwiftUI15InsettableShapeP`、iOS 13.0+、
abstract「A shape type that is able to inset itself to produce another shape.」）。

**验证状态**：本地 **31/31 门禁 + 风格检查 0 问题**全绿。六类里四类的**形状**是静态可判的，
已经落成判据；另两处（`opacity` 与 `accessibilityHint` 的歧义）是类型推导的事，静态门禁够不着 ——
那两处的修法只有 CI 能回答对错。

**这一批说明的事**：CI 的第一次红停在第一行，所以「修完那一条」从来不等于「能编译」。
真正把边界推出去的办法是让 CI 尽量走到下一步 —— 而它每走一步，都在把「静态门禁替代编译器」
这层代理的天花板往上顶一寸。

## CI 第三批：26 → 2（2026-09-25）

上一批修完之后，CI 从 26 条错误降到 **2 条**。两条都记在这里，包括**我上一批猜错的那一条**。

### ① `HealthDataView.swift:385` —— `conflicting arguments to generic parameter 'Result' ('Void' vs. '(inserted: Bool, memberAfterInsert: String)')`

```
withAnimation(TokensMotion.count) { fullyOpen.insert(sys.name) }
```

根因：`Set.insert` **有返回值**（那个元组）。在 ViewBuilder 里，`withAnimation` 的泛型
`Result` 同时收到两个约束 —— 外层（ViewBuilder 的语句位置）要 `Void`，而单表达式闭包给出
那个元组，于是它们对不上。

修法：写成 `_ = fullyOpen.insert(sys.name)`。值本来就没人用（这是「按下就记住这一档」），
把它说出来之后 `Result` 就是 `Void`，两个约束合成一个。
**同一形状的四处一起写了**（体检卡的 insert / remove、消息卡的 insert / remove）——
CI 只报了一处，但另外三处的表达式形状完全相同，而这一轮已经证明「编译器走到哪一步」
是预算问题：与其等下一轮，不如把同一句话说完。

### ② `MessagesSection.swift:361` —— `ambiguous use of 'accessibilityHint'`（**上一批的修法没成**）

上一批我把那一行的按钮拆成了独立函数，理由是「推断预算」。这一轮的 CI 说：**没用，同一行还在报。**
这是一条教训（已写进那个文件的注）：

```
SwiftUI.ModifiedContent.accessibilityHint:2:25: note: found this candidate
nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Content, Modifier>
SwiftUI.View.accessibilityHint:2:25: note: found this candidate
nonisolated public func accessibilityHint(_ hint: Text) -> ModifiedContent<Self, AccessibilityAttachmentModifier>
```

`accessibilityHint` 在 `View` 与 `ModifiedContent` 上**各有一份、返回类型还不同**；当 receiver
恰好是上一步 `.accessibilityLabel` 留下的 `ModifiedContent` 时，两个候选都合法。

**决定性的测量**（这一步比推理值钱）：把全仓「无障碍标签接另一个无障碍修饰符」的链**数了一遍** ——
**28 处，其中 27 处编译得过**（`MapSpineReadouts` / `MapSpineView` / `MineView` / `ControlView` …），
只有消息这一处报歧义。这条测量同时定下了两件事：

· **不要把它变成一条全仓规矩。** 27 处合法代码，每一处都在说 VoiceOver 的事；照着一个
  推断预算的偶发结果去改它们，是把「编译器这次的心情」写进界面代码。
· **那这一处要怎么修才有定论？** 让 receiver 不再是 `ModifiedContent` 就够了。做法是一个泛型函数：

```swift
private func withHint<V: View>(_ hint: Text, _ content: () -> V) -> some View {
    content().accessibilityHint(hint)   // content() 的类型是类型参数 V，成员查找只看它的约束
}
```

`content()` 的静态类型是 `V: View`（类型参数）。**成员查找在泛型声明处做，只看约束** ——
无论调用点把 `V` 推成什么（包括 `ModifiedContent`），候选都只剩 `View` 那一支。
这与 `ViewModifier.body(content:)` 里能随手写 `content.xxx` 是同一个道理。

消息那一节现在的结构：`messageRow` → `DSGroupRow { withHint(…) { rowButton(…) } }`，
`rowButton` 只带**标签**，**提示**由调用处的 `withHint` 挂。上一批那次拆分留着 ——
它本身是对的（表达式更小、每一步的期望类型更明确），只是它**不足以**解决歧义。

**验证状态**：本地 **31/31 门禁 + 风格检查 0 问题**全绿。这一批两处都只有 CI 能判对错：
`_ =` 是语言规则层面的确定修法（有把握）；`withHint` 的把握来自「泛型声明的成员查找只看约束」
这条规则本身，但它仍然要在真编译器上过一遍才算数。

**这一轮最该记住的一件事**：上一批我在文档里写「`accessibilityHint` 是推断问题，拆开就好了」——
那是**推理**，而 CI 证明它错了。同一个怀疑，用一分钟数一遍全仓同类写法（28 处 / 1 处失败）
就变成了事实，而事实给出的结论完全不同：不是「改这一处的形状」，而是「别把它当规矩」。


---

## 2026-09-25（第七轮）三条体感：滚动、提醒、子页的顶

用户原话三条：「除了地图外其他的界面怎么滑动起来都很不 iOS？iOS 的原生流畅呢」、
「电量低于 X 的提醒挡住了底部导航」、「所有的子界面顶部要留有一定的空间吧？现在连第一个卡片的
圆角都看不到了」。

### ① 上一轮把「手感」交给了一个自己写的手势，而它连惯性都没有

那一叠（`ArcStack`）从第一版起就是**自管手势 + 自管弹簧**，头注写的理由只有一条：
`viewAligned` 以「卡片的边」为对齐基准，而当时要的是「滚到某张卡就吸住」。
**而用户 2026-09-24 已经自己把吸附删了**（「只用吸附堆叠（但是要删除吸附）」）——
理由消失，剩下的全是代价，而且每一条都能在代码里指出：

- `onEnded` 只做一件事：`dragBase = nil`。松手**没有惯性**：动量、减速曲线、甩出去的手感，
  一样都没有。那不是「手感弱」，那不是 iOS 的滚动。
- 两端是 `StackMath.clamped` 的**硬限位**：拖到头就是不动，不是橡皮筋。
- `DragGesture(minimumDistance: 6)`：先吃掉 6pt 才开始动，起步那一下是空的。
- 没有三指滚动、没有 VoiceOver 的滚动、没有滚动指示 —— 上一版把这几条当「代价」写在头注里。

修法不是把手势调得更像，而是**换回系统的 `ScrollView`**：

- 「容器顶 = 阅读线」由 `.padding(.top, m.fadeTop + focusInset)` 给出，于是
  「卡顶贴容器顶」（系统的 `scrollTo(anchor: .top)`）正好是「卡顶停在阅读线上」；
- 「内容底 = 可见区下沿」由 `.padding(.bottom, fadeBottom)` 给出 ——
  滚到内容末端就是「末卡底边停下」，与上一版算出来的那个末端是同一个位置；
- 滚动量由 `.onScrollGeometryChange` 读 `contentOffset.y`，喂给同一套形变。
  界面要的那个量是 `tops[i] − contentOffset.y`，与上一版的 `targets[i] − scroll` 同一个数。

**删干净的东西**（都是「服务对象没了」而不是「写错了」）：
`drag` / `dragTo` / `settleTo` / `shapeScroll` / `dragBase` / `endScroll` / `restPoints` /
`scrollTargets` / 整个 `StackMath`（`clamped` / `relative` / `snapIndex` / 早就没人用的 `focus`）、
`StackSpec` 的 `dockRatio` / `directionBias` / `flingVelocity` / `shapeLag` / `settle(velocity:)`
与 `StackMetrics` 的 `padTop` / `padBottom` / `stickLine` / `minCardHeight`。
`shapeScroll`（「形变慢半拍」）也一起删：系统滚动每帧都在跟手，再叠一层动画滞后只会被读成
「滚不跟手」——正是用户第 1 条。

### ② 提醒压住导航，是因为它对齐的是「屏幕底」

那是外壳（`MapShellView`）上的一个 `.overlay(alignment: .bottom)` —— 对齐屏幕底，
而模式条就长在那里（`barTotal` = 26 + 54 + 14 = 94 从屏幕底算起）。
浮层已搬进 `MapSpineView`（只有它知道条子多高），抬到 `barTotal + TokensSpacing.snug`；
`.id(UUID())` 改成 `.id(t.text)` —— 前者会让**每一次 body 求值**都换一个新身份，
而拖模式条时每帧都在求值。

顺带查出第二条**幽灵功能**：`EnhancedToastManager` 整族是**只写不读**的 ——
16 处 `show(...)` 写给一个没有任何视图渲染的 `@Published`（它的视图 `EnhancedToastView`
早在删零引用组件那一批里就没了），于是「记录已保存」「锁车指令已发送」「已摇一摇锁车」
这些提示**一条都不会出现**，而按钮看起来生效了。文件已删，16 处调用改走真正会被渲染的
`ToastManager`（与仓库里「键必须两头都在」是同一条判据：写的那头没有读者就等于没写）。

### ③ 子页顶部：字面量 44 + 一条自己忽略掉的安全区

上一版那两行是 `.ignoresSafeArea(edges: .top)` 加 `.safeAreaPadding(.top, 44)`：
前者把**内容**也顶到了屏幕最上沿（第一张 26pt 圆角的卡正好落在状态栏底下，用户看到的就是
「连圆角都看不到」），后者想把内容推回来 —— 但它加进的是「子树自己已经忽略掉的那条安全区」，
而且那个 44 是个字面量（`spacing.py` 之所以没报，是因为它只管 `padding` 族）。
现在的规则一句话：**背景忽略安全区（铺到屏顶），内容留在系统安全区里**，上面再让
`TokensSpacing.md` 一格呼吸位。铺底那张图随之拆成 `MapWallpaperLayer.swift`
（`MapSpineView.swift` 同时涨到 1212 行、越过了 `lintcfg.py` 的 1200 阈值，拆完 1191）。

### 门禁侧：一条假阳性、一条门禁自己的谎

- `delguard.py` 当场把删掉的 `StackMetrics.padTop/padBottom` 报成「声明没了、使用还在」——
  三处全是**别的类型**的同名成员（`CardFit.Row` 的、`StackSpec.Card` 的）。补了判据 ④（使用处
  文件自己声明了同名成员就不看）与⑤（`A.B.name` 里紧挨着名字的那段是项目类型就不看），
  历史那三次事故的形态（`APIClient.messageWeeks` 一段前缀）照旧报。
- 同一次核查里发现 **`delguard.py` 文件尾那两条自测是恒绿的**：文件头写着「两条都必须报出来」，
  而两个名字在旧版里的声明缩进都比 4 深（判据 ① 就找不到它们），换哪种「新版本」取法都一样。
  两条自测已换成今天真能跑的探针（删 `focusInset` / 删 `tiltDeg`，各必须报一条）。
- `scan.py` 白名单：新增 5 个名字（`ScrollViewReader` / `ScrollViewProxy` / `scrollTo` /
  `scrollIndicators` / `onScrollGeometryChange`，逐个取过 Apple 文档 JSON），
  删除 2 个不再被任何代码使用的名字（`accessibilityAction` / `accessibilityScrollAction`）——
  其中 `accessibilityScrollAction` 那条的说明文字正在替一个已经不存在的世界担保
  （「叠叠乐没有 ScrollView，不挂它 VoiceOver 用户完全无法翻页」）。

### ④ 顺手查出底条那次整行拖动是个**半成品**（三个后果都是真的）

用户第 1 条问的是「其他界面怎么滑动起来很不 iOS」。查「还有谁在自己搓滚动」时，
`MapSpineView` 里那条 `bottomBarDrag` 露出来了 —— 它自己算档位（按 `barRowWidth / 档数`
当节距写 `modePosition`），而条子的位置 `c` 只有条子自己会改：

- **条子不跟手**：手指按在条子上下的空白带里拖时，页面在换、条子一动不动。
  那条空白带是上一版**显式**算进滑动区的（「整条都算滑动区」、「这一圈恰好是拇指
  自然停放的位置」），所以这不是一条够不着的路。
- **松手没人写回档位**：`deckPos` 停在 0.5 —— 两页各半透明地叠着，直到下一次碰条子
  （条子的 `settle` 才会把 `onPosition` 打成一个整数）。
- **两臂展开后没人收回**：宿主自己 `barOpen = true`，而收回的节奏（拖过 620ms /
  纯点按立即）住在条子的松手逻辑里，那条逻辑只有条子自己的手势会走到。

修法是把**位置的唯一计算者**还给条子：新增 `DSSwipeStrip.RowDrag`（宿主转发
`translation` / `predicted` / `moved` 三样），跟手、越界阻尼、吸附、展开与收回全部
回到条子里；宿主那段自算节距的代码删掉 —— 连它唯一的读者一起：文件层那个
`private extension Double { clamped(to:) }` 随之成为「声明在、没有读者」，已删
（它当年留下的教训不在注释里，在 `scan/extguard.py` 的文件头与 HANDOFF §8 第 29 条）。

条子自己的手势在跟同一根手指时，这条转发**整个作废**并忘掉起点（`guard cBase == nil`
加清 `rowBase` / `rowMoved`）—— 两个写者的局面因此不会以另一种形式回来。

顺带把**速度**接进吸附：`snap(projected:)` 吃系统给的 `predictedEndTranslation`
（「松手后手指将到的地方」）。此前只看松手那一刻的位置，「甩」和「停」结果一样 ——
iOS 的吸附（列表、翻页、选择器）都看速度。两种跟手形态改的不是同一个量
（整行跟手改 `c`，透镜跟手直接改 `pv`），所以预测各算各的，但只有**一条**吸附。

**明账（容差）**：宿主转发绝对增量与预测落点，条子按**自己当时**的节距换算，
而展开过程中间距 `gap` 一直在插值（静止按三档、展开按六档）—— 手停在档位边界
几 pt 之内的轻甩，理论上可能与手指「想」的差一档。与上一版的区别是性质上的：
上一版是**两个写者**（真会打架），现在是**一个**，容差只来自几何插值，
而这一点只有真机能调（`slot` / `gapMax` / `pillPad` 三个数）。

### ⑤ 补了一条判据，它当场抓到两个「第二套实现」

删掉底条那段自算档位的代码后，文件层那个 `private extension Double { clamped(to:) }`
成了「声明在、没有读者」—— 而 31 条门禁**一条都没说话**。原因很具体：
`orphans.py` 只认**顶层类型**（`TOP_TYPE_RE` 是 `struct|class|enum|actor`），
「扩展在系统类型上的成员」整类都在盲区里。

补的判据就长在 `orphans.py` 里（它就是这个文件的题目：写了却没人用）：`extension X` 里
`X` **不是**项目自己声明的类型，而成员名字在全仓除声明外一次都没出现。三条收窄写进文件：
名字短于 6 个字符不看（`==` / `id` 这类撞名太多）；读者只数「名字出现过」而不看用在哪儿
（保守方向，宁可漏报）；`DerivedData/` 不算读者。

它加完当场报了两个，都是真的，而且**是同一个病**：

- `URLSession.dataTaskRetryable` + `RetryConfig`（`Services/NetworkEnhancements.swift`）——
  **第二套重试实现**，零读者；App 真正走的是 `Retrier.global`（`API.request` 里那一步，
  HANDOFF 的服务表写着它的策略）。留着它的代价不是占几行：读的人会以为网络层有两套策略。
- `UIColor.dsDynamic`（`Design/DS.swift`）—— **第二套动态色**；全 App 用的是
  `ArtTheme.nativeDynamic(light:dark:)`。

两条都**删了**，而不是登记进例外表 —— 它们不是「确实不需要被代码引用」，
是「本来就不该存在」（例外表是给前一种用的，这一点写在那张表的注释里）。

探针（双向）：注入 `extension Double { func probeDeadMember() }` → 当场报出文件与成员名；
还原后该文件哈希与注入前一致（`a34f46127605322f`）、转绿。

**验证状态**：本地 **31/31 门禁 + 风格检查 0 问题**全绿（`MapSpineView` 1169 行，
`DSSwipeStrip` 552）。本机没有 Swift 工具链，**编译与观感只有 CI / 真机能回答**；
第一次上真机要看四件事：叠叠乐那条减速曲线与橡皮筋（用户第 1 条要的东西）、
按在条子上下的空白带里拖时**条子跟不跟手**、轻甩一下能不能走过一档，
以及 Toast 抬到条子之上的间距与子页顶端那一格呼吸位够不够。

## 2026-09-25（第八轮）照 iOS 地图改抽屉与右侧两枚钮

用户原话：「你看看 ios 的这种抽屉，仅显示重要项，拉开抽屉就是剩余数据，地图页的抽屉
做成这种，再就是你看看 ios 原生 app 的感觉，真精致！地图页要像 ios 地图 app 右侧的图标
一样加入快速回到车的位置和手机的位置」，并附了两张 iOS 地图的截图（收起时三个巨数 +
一道拉手；拉开后是一组带图标的行为行）。

### ① 抽屉：从「一行文字按阷」改成 iOS 那个拉手

上一版的抽屉是「胶囊 +『更多读数 ⌃』」的文字行，行为是「拖过 12pt 整个翻过去」。
三处不像 iOS，三处都是它自己的形状决定的：

- **拉手不该带字**：iOS 的 grabber 就是「这里可以拉」这句话本身（相机 / 地图 / 备忘录
  的底部表单都靠它）；而那一行字把动作解释了一遍，代价是一整行高度，而且它自己
  长得就像一颗可按的钮（但那一行并不是钮，点哪儿都只在 44pt 命中区内有效）。
  现在是一枚居中的 36×5 短横条，命中区仍是整行 44pt（HIG 最小触控目标）。
- **拉开必须是连续量**：`drawerReveal: CGFloat`（0…1）。手指拖动时它就是手指，
  内容随手指变高；松手按**速度**吸附到两个落点（`predictedEndTranslation`，
  与底条那条手势同一个判据）。开关式的 12pt 阈值读起来就是「不跟手」。
- **「剩余数据」不能只有一排**：新增 `readoutsRest`（平均电耗 / 航向 / GPS）——
  三个都是 `MapSpineData` 里**真实存在**的字段，推不出来的整格不出现，一排都不剩
  就不占位。用户那句「拉开抽屉就是剩余数据」这才算兞现。

**高度是量出来的，不是猜的**：抽屉收起时它的框高是 0，量不出自己——
于是把**同一份内容**（`drawerContent`，量的是它、显示的也是它）不可见地放进那一排读数的
背景里（同宽、不裁剪），量到 `drawerHeight`。「拉开后多高」直接决定了「手指拉了多少
算拉满」，这个数不能猜（`CardFit` 的存在就是同一个理由）。

### ② 右侧两枚钮，以及一个一直不存在的「位置」

「回到车」本来在**图层菜单**里 —— 一个要打开才知道有的位置；它已从菜单里删掉、
搬到地图右侧那一列（`MapQuickButtons.swift`）。两枚 44×44 的 `.overMedia` 玻璃圆钮，
竖排、让开系统罗盘（与 `MapCompass` 同一列，看起来是同一个仪表盘的两颗钮）。

「手机的位置」不是搬家而是**新能力**：全仓此前没有任何 CoreLocation 代码。
新增 `Services/PhoneLocation.swift`，四条自我约束写在文件头：
按需（按下才要权限，HIG 说权限要在用到的那一刻要）、取到就停（按一次 = 移一次镜头，
不接后台定位）、如实（拒绝 / 取不到都是**状态**，界面上说得出来）、不猜
（没拿到点就是 nil，不摆一个 (0,0) —— 那个坐标在大西洋上，而地图会老老实实飞过去）。
钮的图形自己就是那个状态（`location.fill` / `location` / `location.slash`），
拿到的点作为**蓝点**画在图上（`phonePin`，与车钝是两个点：「车在哪」与「我在哪」
是两个问题）；答应权限后镜头**自动**移过去一次（`followPhoneOnce`）——
少了这一步，「按一下 → 弹权限 → 答应」之后看起来什么也没发生。

同一轮修了一个旧漂移：`NSLocationWhenInUseUsageDescription` 写的是
「用于显示车辆当前位置」—— 而车的位置是服务端给的，这句话从写下那天起就没对过。
它改成它真的做的事，并记进了 HANDOFF §11 的漂移表。

### ③ 门禁侧：一条假阳性（而这条假阳性本身值得记）

`futureproof.py`（「对系统弹性枚举穷举 switch」）把 `switch phone.status`
报成了待修 —— 因为它的主题词表里有 `status` / `phase` / `configuration` 这三个**普通名词**，
而我新写的那个 switch 主语恰好叫 `status`（`PhoneLocation.Status`，我们自己的枚举）。
**对自己的枚举补 `@unknown default` 是反的**：那会把「以后新增一档时编译器提醒你改这里」
一起关掉 —— 而那条提醒正是这个门禁想保住的东西。

修法两层：拿掉那三个普通名词；再把「主语里有没有项目声明的类型名」当成第二道条件。
代价写在文件里：真遇见「成员名叫 `status` 的系统枚举」会漏报 —— 方向是「宁可漏，不可噪」。
探针双向验过：注入一个真的 `switch scenePhase`（无 default）→ 当场报出；
还原后文件哈希与注入前一致、转绿。
（另一件小事：那个探针第一版写的是 `switch probeScenePhase` —— 它**不该报**，
因为判据按名字匹配 `\bscenePhase\b`，而 `probeScenePhase` 不匹配词界。
探针不报时先问「它造出那个形状了吗」，而不是直接改判据 —— 这条已经是第二次了，
写在 HANDOFF §11 里。）

### 验证状态

本地 **31/31 门禁 + 风格检查 0 问题**全绿。`MapSpineView.swift` 在这轮从 1211 行
降回 **1169**（拆出 `MapNowCard.swift`：卡里三个数的排版 —— 与镜头/图层/手势/抽屉无关的
一件独立的事），所以没有动 `lintcfg` 的阈值，也没往排除清单里塞文件。

本机没有 Swift 工具链，**编译与观感只有 CI / 真机能回答**。第一次上真机最该看四件事：
拉开抽屉时那张卡往上长的手感（与系统底部表单比）、拉手够不够好按、
两枚钮压在浅色地图上读不读得清（`.overMedia` 玻璃在浅瓦片上的对比度）、
以及拒绝定位权限时那枚钮说的那句话对不对得上系统里看到的设置项。

---

## 2026-09-25 第四轮：子页的滑动只剩系统滚动（壳上的三层自己画的东西拆完）

用户：「子页面上下滚动的换回 ios 原生吧，还有哪些可以换回 ios 原生的用问题问我」。

### 一件必须先说清的事：这句请求的方向上一轮已经改过，但那一轮从未编过

`ArcStack` 上一轮（09-25 第三轮）就从「自管手势 + 自管弹簧」换成了系统 `ScrollView`。
但 CI 连续三个批次红在各处类型错误上（第一批 extension、第二批 26 个类型错、第三批 2 个），
也就是说**那个改动从未编过，用户手上那个包很可能还是自管手势那一版**。
这解释了为什么他再次提同一件事 —— 不是上一轮没改，是上一轮没能到手上。

### 这一轮实际删掉的东西（逐条能对着代码指出）

方向对不等于做完了。滚动的壳上还挂着三层自己画的东西，**它们都不需要 CI，读代码就能看出不对**：

1. **消失带遮罩**（`.mask` + 渐隐）。来历是旧的「卡片转出画面」——卡片当时是斜的、
   要转出去，硬裁会在边上露直角，于是用渐隐收尾。转出在 09-24 删掉后，这条只剩一个作用：
   让一个原生滚动容器的两端平白变淡。而且那些子页铺的是**壁纸**，渐隐是往一块
   `TokensPalette.canvas` 的**不存在的底色**里淡 —— 两个错叠在一层上。
2. **每张卡的 `offset` / `rotation3DEffect` / `scaleEffect` / `opacity` / `allowsHitTesting`**。
   唯一叠法下系数全是 0/1（`tiltDeg 0`、`shrink 0`、`fadeOut 0.10`、`deckStep 0`）：
   五个修饰符里四个什么也没做，剩下那个把滚出去的卡淡成 0.9。原生滚动没有这件事。
3. **`.scrollIndicators(.hidden)`** —— 它连「你在滚动」那条指示条一起关了；系统列表是**给**的。
   以及 `.clipped()`：在遮罩删掉之后无事可做。
4. **量高度 / `tops` / 落点清单 / 两条边距**：位置归系统之后全部失去读者。
   `CardFit` 只需要宽度 —— 这件事现在写在 `ArcStack` 头注里（怕下一个读的人
   又为了「下一张在哪儿」把测量加回来）。
5. **`StackVariant` / `StackMetrics` / `StackKind` / `variantKey` / `chosen` / `remember`**：
   用户 09-24 删到只剩一种叠法；09-25 滚动也归系统后，那一种不再有任何属于自己的行为
   （它就是系统的 `VStack`）。留着的后果与「幽灵功能」同源。**要找回那七种的参数，
   看删掉它们的那次提交。**
6. **`GlassCard.glassy` + `CardSurface`**：那是「只给可见的卡挂玻璃」的性能妥协（阈值 0.9
   对准消失带开始变淡的位置）。遮罩与阅读线都没了，它的前提就不存在；
   而留着的后果比性能严重 —— 同一张卡会因为**滚动位置**换材质，滚过去那一刻最像贴图。

结果：`ArcStack` 383 → **159 行**（`ScrollView { VStack(spacing: StackSpec.Card.gap) { 卡片 } }`
+ 无障碍逐张翻页）；`StackSpec` → **56 行**（只剩 `Card` 与 `settle`）；`GlassCard` 128 行。

### 留下的唯一非系统行为，以及它的已知限制

`.accessibilityAdjustableAction`（读屏用户上下轻扫 = 上一张 / 下一张）：它是无障碍挡位、
不画东西、也不碰滚动的物理（系统的三指滚动照旧并存）。
⚠️ 它只跟「被点了几次」走 —— 手自己滚过好几张之后，下一次翻页仍从上次那个序号继续。
系统没有「你现在滚到第几张」这个数可读，这一点写进了 `ArcStack` 头注（而不是留着不说）。

### 顺带修的注释漂移

`DS.swift` / `ControlFit.swift` / `ExportDataSection.swift` / `MessagesSection.swift` /
`EmergencyPanel.swift` 五处写着「叠叠乐自管手势（没有 ScrollView）」——
**结论不变**（卡里不要套第二层滚动），但理由现在是：外面那一层是真 `ScrollView`，
卡里再套一层，那一块区域的竖向拖动会被**内层**吃掉（旧版是「手势塌给内层」）。
`PROTOTYPE-TO-SWIFTUI.md` 两节（多张玻璃的性能 / 挑叠法的地方）也一并标了「已不存在」。

### 一个被我写进文档、又被自己量倒的结论

改 `DevView` 时看到那里的 `DSGroup(footer:)` 文案很长而 `copy.py` 没报，我把
「作为参数传出去的文案逃过了 `copy.py`」当成了发现写进 HANDOFF。量了一下才反转：
`copy.py` 扫的是**每一行的字符串字面量**，与位置无关；`DevView` 没被报是因为它在
`EXEMPT_FILES` 里。量出来的数：这类中文文案 399 条，> 30 字的 **0 条**。
教训与「探针不报时先问它造出那个形状了吗」同源 —— 这次是先写结论、才想起去量。

### 同一轮的第二个改动：地图抽屉 → 系统 sheet（用户从候选里选的）

我把「还有哪些可以换回系统原生」列成一张表交给用户，三问三答：
保留相机式模式条（六档 + 两臂映不进系统页签栏）、保留玻璃叠叠乐、
**做：地图抽屉换系统 sheet + `presentationDetents`**。

删掉的东西（每一条都是「在重做系统已经做好的事，而且做得少」）：

| 上一版自画的 | 现在系统的 |
|---|---|
| 两个落点 + 手算吸附（`predictedEndTranslation`） | `presentationDetents([.medium, .large])`：档位 / 橡皮筋 / 下拉关闭 / 键盘与指针行为全归系统 |
| 自画拉手（`Capsule().fill(track).frame(width: 36, height: 5)` + 44pt 命中行） | `presentationDragIndicator(.visible)`：系统那枚 grabber（尺寸/对比度/热区随辅助功能设置走） |
| 抽屉全程盖住地图 | `presentationBackgroundInteraction(.enabled(upThrough: .medium))`：半屏时底下地图仍可拖（Apple 地图的行为） |
| `drawerReveal` + `drawerBase` + `drawerHeight` + `drawerMeasure`（把内容藏起来量自然高） | 一个 `showReadouts: Bool`（高度由系统算，不需要我们量） |

新增：`readoutsDisclosure()`（一行 disclosure：标签 + 右尖括号，整行 44pt）与
`readoutsSheet(_:)`（两排读数 + 标题；内容**不重复**卡里已经有的续航/电量/车速）。
两个新 SDK 名字对着 Apple 文档 JSON 核过后登记进 `scan/scan.py`：
`presentationBackgroundInteraction`（iOS 16.4+，externalID
`s:7SwiftUI4ViewPAAE33presentationBackgroundInteractionyQrAA012PresentationeF0VF`）、
`presentationDragIndicator`（iOS 16.0+，externalID
`s:7SwiftUI4ViewPAAE25presentationDragIndicatoryQrAA10VisibilityOF`）、
`PresentationBackgroundInteraction`（含 `enabled(upThrough:)`，externalID
`s:7SwiftUI33PresentationBackgroundInteractionV7enabled9upThroughAcA0C6DetentV_tFZ`）。
顺带删掉 `TokensMotion.reveal`（唯一的读者就是那道被删的抽屉）。

**未动的已测盲区**：`orphans.py` 只盖「系统类型扩展里的成员」，项目自己的令牌枚举
（`TokensMotion` / `TokensTypo`）里的零读者成员整类不在范围内。粗探针扫出 6 个候选，
其中 `TokensMotion.page` / `screen` 已单独核过（HEAD 与工作树都是零读者），
另外两个（`ArtTheme.changed` / `CardFit.defaultValue`）需要看上下文才能判 ——
把这条变成判据是一个独立决定，这轮没有做。

### 验证状态

本地 **31/31 门禁 + 风格检查 0 问题**全绿（`copy.py` 报的那一条已改短；
新用的两个 SDK 名字登记后 `scan.py` 由红转绿）。
本机没有 Swift 工具链，**编译与观感只有 CI / 真机能回答**。
真机第一次最该看的是：卡片的上下两端是**裁**（不再化掉）、滚动时出现系统指示条、
以及「甩一下能滑多远」是否就是别处列表的那种手感。

---

## 2026-09-25 图标重画：从「一块黑 + 两行字」到满幅三外观

触发：用户「重新设计软件图标吧！完全不符合 ios 调性！太丑了！」。

### ① 「不符合 iOS 调性」不是凭感觉说的，旧图有四条能指着的错

上一版（v1.0）的全部问题是：它**能编过、当时 31 条门禁全绿、模拟器里也正常** ——
也就是说，没有任何自动检查看得见它。四条逐一量过：

| # | 问题 | 实测 |
|---|---|---|
| ① | **底色近黑** | 1024 亮度 p05 / p50 / p95 = **0.000 / 0.096 / 0.659**（深蓝黑 `#1A1A2E→#0D0D1A`）。主屏上它就是一块黑 —— 而 iOS 的图标语言是「亮底 + 一个物体」，旧图正好反过来 |
| ② | **图上有字** | 「长安车管家」+「CHANGAN CONNECT」两行，占画面下缘约一成高；29pt 下是两团灰噪点 |
| ③ | **自己套圆角 + 内缩 4%，四角还是纯黑** | 脚本最后 `convert('RGB')` 把透明边压成 **(0,0,0)**；左右边缘中点 (0,0,0) vs 同行内侧 (255,159,0)，**色差 255**。系统还要再套一层 squircle，所以成品比邻居小一圈、遮罩里留四个黑角 |
| ④ | **没有深色 / 着色外观** | 7 张全是同一张浅色。iOS 18 起主屏有三种图标外观 |

### ② 「太丑」的正解不是「画得更精致」，是把语言换回系统的

v1.0 的立体感靠**光晕 + 两行字 + 深底**——那是一张插画的做法。系统图标的做法是
亮底、一个物体、一层很淡的高光。所以 v2.x 不是修边角，是整张重画：

- 亮琥珀→橙渐变（p05/p50/p95 = 0.561 / 0.718 / 0.957），白车，窗与轮拱是**挖空**
  （透出底色，不是画深色块），没有描边 / 阴影 / 光晕。
- 深色外观 = 暖近黑 + 琥珀车（就是 App 自己那套夜间配色）；着色外观 = 灰阶
  （系统按亮度上色，给彩色只会被压平）。
- 车身底下那道弧是 App 里「车钉外面那圈弧」（续航圈）的图形引用。
- **满幅**：模式就是 `RGB`，不带 alpha，不画圆角 —— 遮罩交给系统。8 点实测边缘 vs 内侧最大色差 **7**。

v2.0 出来后又量了一次：车只有 300 高、占画布 29%，缩到主屏是「中间一条小车、四周全是底」，
于是 v2.1 把它放大到 689 × 409（长高比 1.68），占宽 67% / 高 40% —— 只留一圈呼吸位。
放大时踩到一条硬约束：**轮心必须 `cy + R ≤ 车底线(780)`**，否则轮毂会从车底探出来
飘在底色上（v2.0 试过 `cy=700,R=84`，每个轮子下面露 32 单位）。这类约束都写进了脚本常量旁边。

### ③ 门禁侧：新立一条 `iconcheck.py`，并撞上「scan/ 里不能 import Pillow」

图标不是 Swift 文件，`design` / `lintcfg` / `eol` 那些一条都看不到它。新门禁五条判据全部当场能量：
文件都在 / 声明尺寸 × scale == 实际像素 / 每槽位有浅色·深色·着色三套 /
三张 1024 主图满幅（8 点色差 ≤ 14；为什么不是 0：底是渐变，向内 64px 本来就会变色，
实测我们这两套最多差 7，而 v1.0 一量就是几十、四角干脆是 255）/ 没有没人引用的 PNG。

写它的过程中撞到一面墙，值得记：**任何在 `scan/` 里 `import PIL` 的门禁都跑不起来**。
门禁都住 `scan/`，脚本目录会进 `sys.path`，而 `scan/copy.py`（文案门禁）与标准库 `copy` **同名** ——
Pillow 的 XML 依赖一 `import copy` 就拿错模块，当场 `AttributeError: module 'copy' has no attribute
'deepcopy'`。于是它自己写了一个 PNG 解码器（zlib + 五种过滤器，只认 8-bit RGB/RGBA、非交错），
并与 Pillow 逐点比对过（3 张主图 × 9 个采样点，结果一致）。

**探针（双向验过）**：① 换回 v1.0 的 1024 → 报出 4 条（左右边中点 (0,0,0) vs 内侧 (255,159,0)，
色差 255）；② 丢一张没人引用的 PNG 进目录 → 报出；③ 删掉某个槽位的着色条目 → 报出。
三次探针都还原，`md5sum` 与探针前一致。

### ④ 出包来源收敛成一条路

`generate_appicon.sh` 上一版先找 ImageMagick、找不到再退回 `python3 generate_appicon.py` ——
而**那个文件根本不存在**，且 ImageMagick 只能渲 SVG（只有浅色一套外观），用它刷新会得到
「一半新图一半旧图」的图标集，正是这个仓库记过的那个坑（**改了 A，真机上看到 B**）。
现在只剩 Pillow 一条路，脚本末尾顺手跑 `scan/iconcheck.py`；`AppIcon.svg` 降级为矢量对照，
不再出包。

### 验证状态

本地 `python3 scan/all.py` **32/32 全绿**（31 条门禁 + `check_style.js`）。
本机没有 Swift 工具链，**图标真实观感只有 CI / 真机能回答**；本地能给的证据是可量的事实：
像素尺寸、三套外观齐全、满幅（8 点色差 ≤ 7）、亮度分位、以及 58px 下的 ASCII 渲染能读出车形。
真机第一次最该看的是：主屏上它是否和邻居一样满、四角有无黑角、切到深色 / 着色时车是否还读得出来。
文档：`AppIcon-SPEC.md` 重写为 v2.x（含每条旧问题的实测数字），`HANDOFF.md` 新增 §15 与 §8.1 第 31 条。

## 2026-09-25 第五轮：五条真机反馈

用户一次给了五条，编号就是他给的顺序。完整版（根因 / 改法 / 证据 / 边界）在
`HANDOFF.md` §16；这里记「这一轮到底改动了什么、以及每条的根因是什么」，
外加两处被这一轮推翻的旧结论。

### ① 卡片宽度：只有「现在」与「车辆」合格

根因是 `pageBackground()` —— 名字说「页面底色」，函数体却只剩
`contentMargins(.horizontal, 20, for: .scrollContent)`（底色与光早搬去 `AppCanvas` 了）。
于是**调过它的页面**，卡叠被这 20pt 二次收窄：

| 页面 | 分组面宽 | 左右各空 |
|---|---|---|
| 车辆（没调用） | 328pt | 36pt（= 18 卡内缩 + 18 卡内边距） |
| 出行 / 车控 / 我的（调用了） | 288pt | 56pt |

改法：**整段删除**，六个调用点全清；登录页顺带修掉一个双重内缩（自己已有
`.padding(.horizontal, page)`，再叠 20 就是 40）。这一条与 02 那轮删掉的
`glass` 参数是同一类：**名字承诺一件事，函数体做另一件事**。

### ② 地图页：删大字地名 / 底部卡变抽屉 / 比例尺挂到灵动岛下

- 删 `mapPlaceLabel`（衬线 29pt，安全区下 108pt）与它读的 `MapSpineData.placeLabel`
  —— **删完就没人读了，而门禁看不到**：`scan/orphans.py` 只盖系统类型的扩展成员，
  项目自己的类型属性不在范围内。这类删法永远靠人 grep。
- 底部那张卡自己变抽屉：收起 = 拉手 + 续航/电量/车速 + 图层胶囊，拉开 = 卡的全部内容。
  巨字续航（`size 56`）随之消失 —— 它就是那三个数的第一个（不是缩水，是去重）。
- **上一轮那张系统 sheet 整块删掉**（`readoutsSheet` / `readoutsDisclosure` / `showReadouts`）：
  抽屉就是这张卡。理由不是系统 sheet 不好，是它的落点永远在屏幕底部，会盖住模式条，
  而那是全站唯一的入口（`oneentry.py` 守着）。同一个诉求的第三代写法。
- 比例尺：系统的 `MapScaleView` 位置由 MapKit 定（贴角）搬不动，所以用
  `MapReader` + `MapProxy.convert(_:from:)` 把屏幕上相距 200pt 的两点换成经纬度，
  用 `CLLocation.distance` 量地面距离 —— **量出来的，不是按镜头估的**。
  它挂在**安全区之内**（`nowLayer` 那层），所以「对齐到顶」= 灵动岛下沿；挂在地图上会
  跟着 `ignoresSafeArea(.top)` 钻到灵动岛底下。2 秒淡出，镜头每变一次重计时。

### ③ 底部模式条：点选准、滑动不准（这个不对称就是根因的指纹）

`c`（行内坐标）在**两个间距**下不是同一个数（间距随展开插值：静止按三档、展开按全部）。
点选时 `pick()` 与 `expand = 0` 同一轮发生 → `.onChange(of: selectedID)` 拿到的间距已收回 → 对；
滑动时 `snap()` 改档而条子还开着（收回推到 620ms 后），收回后间距变了**却没有谁重算 `c`**
→ 从此偏着，直到再碰一下条子。改法：加 `.onChange(of: expand)` 重新落位；手指按着时不重算。

### ④ Windows 聚焦取不到图（必应却行）

真报文里是 `ad.landscapeImage.asset` / `ad.portraitImage.asset` —— 键名 **`asset`**，
而解析器只找 `u` / `url` ⇒ `picks` 恒空；必应走的是 `urlbase`，所以只有它行。
同一函数还有第二个 bug：署名读 `copyright_text` / `title_text`，真报文叫 `copyright` / `title`
⇒ 署名那行**永远是空的**。两个都改了，并把顺序写死（竖图优先，不再遍历 `ad.values`：
Swift 字典顺序未定义，同一份报文会今天竖、明天横）。
证据：两个解析器照抄成 Python 对真实接口跑 —— 旧 **0 张 / 0 署名**，新 **4 张**（`1080x1920` 竖图，
署名 `© Ondrej Prosicky / iStock / Getty Images Plus`）。

### ⑤ 「黑颜色太突兀」：卡里的面必须与卡片同一块材质

根因是 `TokensPalette.nightSurface`（= `spec.surface`，**不透明** #1C1C1E / #FFFFFF）。
卡片自己是玻璃，卡里那层面却用它 ⇒ **玻璃中间挖一个黑洞**。用户截图里那一块块黑就是它：
`DSGroup` / `DSPlaceholder` / `DSNotice` / 搜索框 / 分段滑块 / 评分空态。
改法：新增 `TokensPalette.panel`（**当前主题 `surface` 的半透明版，0.5**），上面七处全改成它。
为什么是同一个色值的半透明版：二十套主题各自保住自己的面色（纸上主题这层仍是纸色），
而 0.5 让卡片的玻璃与底下的壁纸继续透上来 —— 它才像同一块材质的一层，不是贴上去的板。
分段滑块单独改读 `glassHighlight`（与模式条那枚透镜同一个令牌）：原先深色下是 (28,28,30)，
**比它所在的凹槽还暗**，iOS 深色下选中段本该更亮。顺带把最后一个系统 `Picker(.segmented)`
（充电页趋势周期）换成 `DSSegmented`。

**故意不做**：卡里再挂一层 `.glassEffect`。`DSGlass` 三层规则第 ② 条写着卡里不玻璃
（卡片自己已经是玻璃），`scan/glass.py` 第 ③ 条也会拦「玻璃底下垫不透明面」。
用户要的「玻璃质感」在这里是**半透明**，不是第二块材质 —— 这条写在令牌注释里，免得下次重做。

### 被这一轮推翻的两个旧结论

1. **「地图抽屉用系统 sheet 更好」**（上一轮由 `ask_questions` 拍定）：它的三条优点
   （落点更多 / 拉手随辅助功能 / 半屏时地图仍可拖）都成立，但位置永远贴屏幕底 ⇒ 盖住模式条。
   已作废，不删记录：`HANDOFF.md` §14 的原文保留并加了「已被取代」批注。
2. **「`DSGroup(footer:)` 让中文串绕过 `copy.py` 的长度门」**：上一轮据代码形状写成结论，
   这一轮**量了一遍**：399 个参数位传入的中文串，**超 30 字的 0 个**。结论是错的，
   已改。教训与第 4 条老账一样：**能量的事不要靠读代码下结论**。

### 验证状态

`python3 scan/all.py` —— **32/32 全绿**。三处门禁当场抓到东西：`scan.py` 拦下三个
未登记的 SDK 名字（`MapReader` / `MapProxy` / `convert`，对着 Apple 文档 JSON 核过后登记）、
`lintcfg.py` 拦下 `MapSpineView.swift` **1201 行**（改法是把「现在」那张卡搬进
`MapNowCard.swift`，现 1157 行 —— 不是加排除、也不是抬阈值）。

本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**。这一轮新引入的风险集中在三处：
`MapReader` / `MapProxy.convert` 的用法、抽屉的 `DragGesture` + `accessibilityElement` 组合、
`TokensPalette.panel`（`Color` 带透明度进 `fill`）。括号平衡与改动前后逐一比对过（未变），
但那不等于编译得过。
## 2026-09-25 第六轮：主题只剩原生、图标换成 040、底条只留一种跟手

用户三句话，全是**减到只剩一种**：

> 「图标用 040，主题用原生，其他 19 套全删了 选整行滚动，另外一个也删了」

每一次减都牵出一串「只服务那一种选择」的代码 —— 这一轮真正的工作量不在删，
在**删掉之后谁接住它的读者**。

---

### ① 主题：20 套 → 1 套（原生）

删掉的五处：

| 删掉的 | 它原来做什么 |
|---|---|
| `Design/ArtTheme.swift` | 20 个方向的取值表 + `ArtThemeStore` + `ArtThemeSpec` 便捷构造 |
| `Features/ThemeGalleryView.swift` | 诊断档里的主题样张页（20 枚胶囊 + 小界面样本） |
| `Design/MapStyleSpec.swift` | 把主题翻译成 MapKit 旋钮（蒙版色 / 不透明度 / `cameraHeading` / 三种车钉 / 发光开关） |
| `Design/SkyOverlay.swift` | 光池 / 雾霭 / 暗角 / 颗粒 / 发丝网格五个**装饰**图层 |
| `TokensSerif` / `CanvasDecor` / `preferredScheme` | 衬线标题 / 画布装饰 / 主题自带明暗 |

**难点是「值必须逐值搬，不能重写」**：

| 原来由主题提供 | 现在 | 为什么不能连值一起删 |
|---|---|---|
| `TokensPalette` / `TokensTypo` 的取值 | 直接写回 `Tokens.swift` | 全 App 约 800 处读者，值必须逐值相等地搬 |
| `ArtTheme.artHex` | `TokensPalette.artHex`（同实现同取值） | `pageAccents` 的六个个性色仍在读它 |
| `ArtTheme.nativeDynamic` | `TokensPalette.nativeDynamic` | 动态色是系统语义值的另一种写法，v4 起就在用 |
| `preferredScheme` | 删 | 「我的 → 夜间模式」成为**唯一**说这件事的人；nil = 跟随系统 |
| 地图蒙版 / 三种车钉 | 系统原样（`.standard` 不传参） | MapKit 本来就只有五个旋钮，那层蒙版是我们自己叠的 |

**顺带治了一处「说谎的指针」**：`SkyLight.swift` 与 `WeatherService.swift` 的文件头都写着
「命名：顶层类型，不嵌套泛用名（历史事故见 `ArtTheme.swift` 的说明）」—— 指的是一份已删的文件。
记录本身还在 `Tokens.swift` 的文件头（劫持 SwiftUI `Color` 那次事故），已改指过去。
**删文件时，指向它的注释不会自动消失**，这一条值得记。

**这条盲区仍未解决**（与 §「被这一轮推翻的旧结论」同源）：`scan/orphans.py` 只认「系统类型
扩展里没人读的成员」，**项目自己的令牌枚举整类不在范围内**。所以「19 套是不是真的删干净了」
靠的是全仓 `grep` + 每个删除点留记录，不是门禁。已记两次，仍未动。

---

### ② 图标：v2.1 → v3.0（用户挑了 040）

上一轮（第三轮）修掉的是「不符合 iOS 调性」的四条**规**，但构图是我一个人定的
（琥珀底 + 白色轿车 + 车底一道弧）。于是又做了一轮 **100 个 1024 方向的探索稿**
（自包含单页，用户在浏览器 / 真机里看），用户报回一个编号：**040「两厢 · 纸白底」**。

v3.0 = 把 040 折进正式渲染器：车形换**两厢**、底换**纸白**、车身从白换成**墨色**；
v2.1 那道车底弧**删掉**（040 里没有它）。折进来时与探索稿**逐点比对**过：

| 量 | 结果 |
|---|---|
| 完全相同的像素 | **99.76%** |
| 差 > 8 色阶 | **0.24%** —— 全落在 1px 宽的车身边缘，来自常数取整 |
| 比对查出的真参数错 | 柔影位移 `23 → 22`（23 时有 89485 个像素有差、最大 2；22 时 174 个、最大 1） |

探索稿与它的两个生成脚本**用完即弃**，只留中选的那一张 —— 留着 100 个方案，
下一个人改图标时不知道以哪个为准。`generate_appicon_pillow.py` 仍是唯一出包来源，
`scan/iconcheck.py` 仍是那五条可量的判据（实测：亮色 1024 亮度 p05/p50/p95 =
**0.136 / 0.916 / 0.980**，模式 `RGB` 满幅无 alpha）。

---

### ③ 底条：跟手形态只有一种

`DSSwipeStrip` 的 `Follow` 枚举有两个值：「整行跟手」（手指拖整行、透镜钉在正中、字从它下面
滑过）与「透镜跟手」（透镜从字上滑过去、整行基本不动）。用户定下前者，**后者连同枚举一起删**
—— 只有一个取值的参数不是参数。

顺手的好处：「松手会到哪儿」的预测原本是一个 `switch`，**两个分支就是两份预测**；
少一种跟手形态，那半套惯性逻辑也跟着没了。**这是这一轮唯一一处「删对了、顺手也对了」的地方。**

---

### 验证状态

`python3 scan/all.py` —— **32/32 全绿**（31 条门禁 + `check_style.js`）。

本机没有 Swift 工具链，**编译与真实观感只有 CI / 真机能回答**。这一轮新引入的可编译性风险
仍集中在第五轮那三处（`MapReader` / `MapProxy.convert` 的用法、抽屉的 `DragGesture` +
`accessibilityElement` 组合、`TokensPalette.panel` 带透明度 `Color` 进 `fill`），
本轮新增的则是**搬移**类风险：令牌的读者从 `TokensPalette.xxx` 改成直写值之后，
有没有哪一处仍在读已经不存在的转发层 —— 这一类本地靠 `grep` 全仓核过（0 处），但那不等于编译得过。
## 2026-09-25 第七轮：性能与流畅性（先量，后改）

用户：「再全局全项目优化性能流畅性！」。这一轮不写任何「感觉更快」的改动 ——
**先把「谁在每次界面求值时重来一遍」量出来，再改那几处。**

### ① 先把预算算清楚

| 事实 | 出处 | 结论 |
|---|---|---|
| 地图页在车动起来时 **每 2 秒**求值一次 | `RefreshLoop.Cadence.moving` | 每次求值里的浪费 × 0.5 Hz |
| 六页同屏**是关着的** | `LaunchFence.sixPageDeck = false` | 树里只有当前档 → 只优化当前页 |
| 手机定位百米精度、取到就停 | `PhoneLocation` | 非热路径 |
| 历史库上限 soc 2000 / power 1500 / tyre 760 | `HistoryStore` 的 cap | 只有 3 个读者、都带窗口 → 非热路径 |
| 壁纸只在载入/刷新时解码 | `WallpaperService` | 非热路径 |

热路径只有一条：**地图页「现在」这一档，每次求值里的那几件事。**

### ② 量出三处，都是同一个形状

同一个形状是：**每次求值重造「其实只取决于常量的东西」**。

1. **`MapSpineData.build()` 一次求值建三套** —— `body` 的 `let d`、`.onChange(of: d.carCoordinate…)`
   （条件每次求值都要算）、`nowLayer()` 各一处。而 `build()` 含行程映射、停车点映射、
   胎压、异常点与**两处聚类**。→ 收成一处：sheet 那份挪进闭包（只在弹出时求值）、
   `.onChange` 改盯车自己的读数、只留 `nowLayer`。**3 → 1。**
2. **`DateFormatter()` 9 处，三处在每次求值的路径上** —— 构造它要现装一套 ICU 格式化器，
   而同一个 `(locale, 格式)` 造出来永远一样。`MapTripLine.timeText` 是**每段行程读一次**
   （30 段 × 每 2 秒），`VM.parseDate` 一次调用最多造 **7 个**。→ 新建 `Services/DateText.swift`
   的池子（键 `locale|格式`，有界）。**locale 三种情形一个都不合并**（`zh_CN` / `en_US_POSIX` /
   系统默认），所以每一处搬迁都是**逐字一致**的：搬住处，不改行为。
3. **聚类在每次比较里造对象** —— `clusterChargers` 的判据 `firstIndex(where: { CLLocation(...) })`
   是「一枚钉子 × 已有的每一组」次分配；`clusterHotspots` 在 `for j in group` 每轮重造同一质心。
   → 每个站/每个组各造一次，质心提到循环外。比较用的仍是 `CLLocation.distance(from:)` 本尊 ——
   **判据与分组结果一字未改**（换的是分配次数，不是算法）。

### ③ 故意没动的：六页同屏

它是这份代码里**最大**的一笔开销（`LaunchFence` 的注释记着：内存 49 MB → 1.7 GB 只要四秒），
但它已经有明确开关、现在是关的。剩下能省的只有「隐藏页要不要跟着 `caches` 的写入重新求值」——
那要把隐藏页换成 `EmptyView`，**代价是每页自己的状态在换档时销毁**（滚动位置、展开的分组）。
那是设计变更，不是性能修复：真要做，得由用户决定「省 CPU」还是「保住状态」。**记在这里，不动。**

### ④ 防回归：第 32 条门禁 `scan/perf.py`

这两处**都不报错、不崩、编译全过**，只是慢 —— 而慢没有输出。按本仓惯例各立一条判据：
格式化器只许从池子里取、坐标不许造在比较闭包里。**双向探针**：注入即报、还原即绿、哈希一致。

### 验证状态

`python3 scan/all.py` —— **33/33 全绿**（32 条门禁 + `check_style.js`）。

**本机没有 Swift 工具链：编译与真实帧率只有 CI / 真机能回答。** 这一轮能站得住的证据是
**计数**（一次求值建几套派生数据 3 → 1；每次比较分配坐标对象的次数 O(n × 组数) → O(n)；
每次求值构造 `DateFormatter` 的次数 → 0），不是帧率。
## 2026-09-25 第八轮：地毯式对抗式审核（查语义层）

用户：「再次全局全项目地毯式对抗式各维度审查全项目！」。33 条门禁已经把语法与结构
扫了很多遍，所以这一轮专挑**门禁看不见的那一层**：**两处代码各自都对，
但它们关于同一件事的假设不一致** —— 编译器不报错、门禁不报错、平时也看不出来。

挑维度的判据是「**同一个事实被写在了两个地方**」。第一条当场对出了东西：

**「哪些本机键是关于账号的」（`HANDOFF.md` §6 那张表，每行标 ✅/❌）对不上
「`AppStore.logout()` 真的清了什么」—— 查出 8 个标了 ✅ 却没人清的键：**

| 漏掉的键 | 换账号后的后果 |
|---|---|
| `carkeeper_parking_points` | 地图「停车」层与「常停热区」显示前一个账号去过的地方（位置隐私）。`parkingHistory` 是**从磁盘现算**的 —— 清内存没用 |
| `carkeeper_maintenance_photos` | 前一个账号拍的保养单据照新账号看得见 |
| `carkeeper_inspections` | 年检记录跨账号可见；它有 `@Published` **内存副本**，只删键的话同一次运行里照样看得见 |
| `carkeeper_processed_event_ids` | **清派生却留台账**：`tripHistory` 清了、台账还在 → 重新登录后那 7 天窗口的行程再也生成不出来（行程页一直空） |
| `carkeeper_service_reminders` / `_current_mileage` / `_total_mileage` / `_service_timestamp` | 里程与保养基线是上一辆车的，「距下次保养」跟着错（`last_service_mileage` 当时已清 —— 只清一套里的一个等于没清） |

八条**只在换账号/换车时才看得见** —— 一个人用一台手机一个账号永远发现不了。

**比那八个键更值得记的是它们为什么能一起漏**：`logout()` 清的是「记得的那几项」，
而**没有任何一处能回答「一共该清几项」**。所以这一轮的修法有两半：
补齐八处（含给 `InspectionCalendar` 加 `resetAll()`，内存与键一起清）；
以及把 §6 那张表变成 **`scan/localstore.py` 的唯一真值**（门禁直接读那张表，
与 `all.py` 从工作流解析门禁清单同一个做法）——键的归属从今天起是**设计决定**。

顺带治掉那张表自己的两条毛病（都是对账时撞出来的）：标题写「42 个」而实际 **33 个**；
表里混着 `_points` 这种**简写**并一行塞多个键 —— 后果是**这张表根本没法机械对账**。
已重写成「一行一个键、全名、四列」。

新门禁三道判据 + 双向探针（注入新键 / 拿掉一个清理 / 塞一个幽灵键 → 各自报出、
还原哈希一致）。写它的过程里它自己被两个洞教过（不认符号常量 → 六条假阳性；
认出局部变量 `key` → 设备键被误报「已清」），两条收窄都写进了文件头。

**没下结论的**（如实记）：单位与量纲、服务端字段语义随车型变化、真并发与内存行为 ——
都需要真报文或真机，这一轮没有硬结论。这一轮的证据是**对账 + 双向探针**，不是运行时观测。

验证：`python3 scan/all.py` —— **34/34 全绿**（33 条门禁 + `check_style.js`）。

---

## 2026-09-25 第九轮：十条（玻璃通透度 / 顶部 / 卡里的灰 / 三处删除 / 三维车 / 地图七处 / 玻璃上的字）

十条一次来。它们混着**问句**与**改法**，所以先分类：问句两条（1 玻璃是不是最通透那一档、
10 玻璃上的字怎么适配）、一致性两条（2 子页顶部、3 卡里那层灰）、删除三条（4 / 6 / 7，
外加 5 的一半）、重做两条（8 车控的车、9 地图七处）。

### ① 玻璃的「通透度」不是旋钮，它跟着底下是什么走（第 1 条）

系统只有两档：`Glass.regular` 与 `Glass.clear`。`.clear` 就是最通透的那一档，
而 HIG「Materials」对它的用法写得很死：*“reserve clear Liquid Glass for components
over visually rich backgrounds.”* 本仓已有的两个变体常量就是这句话的两半 ——
地图上的三处（图层胶囊、两枚快速钮、罗盘）走 `.overMedia`（= `.clear`），
卡片走 `.regular`：卡片是「读的内容」，`.clear` 会让卡里的正文对比度跟着壁纸走。

### ② 玻璃上的字：自适应确实没开，根因是我们一直传固定色（第 10 条）

`Color(uiColor: .label)` 是**已经解析成固定值**的颜色，而系统的 vibrancy 只作用于
`foregroundStyle(.primary/.secondary/.tertiary)` 这类语义层级样式（WWDC25 与 HIG 都有明文）。
于是新增令牌 `TokensInk`（三档 `AnyShapeStyle`），只换**底下真的是玻璃**的那些调用点：
模式条、卡头、次操作按钮、轻提示、地图上三枚圆钮、图层胶囊、底条两臂。卡片里的正文不换。

### ③ 子页顶部与地图页对齐（第 2 条）

`MapSpineView` 量出「屏幕顶到这一层的顶」（`frame(in: .global).minY`，而不是在已被让开的
视图里会读到 0 的 `safeAreaInsets`）写进环境，`ArcStack` 用 `.contentMargins(.top, …)`
让第一张卡静止时让开状态栏、滑动时从时钟下连续穿过，并加 `.scrollEdgeEffectStyle(.soft, for: .top)`。

### ④ 卡里那层灰（第 3 条）

`fillSubtle` 从 `quaternarySystemFill`（为**不透明背景**定的灰，压在玻璃上就是一块灰纱）
改成 `surface.opacity(0.22)`，`panel` 从 0.5 收到 0.34 —— 卡片、分组面、控件底成了
**同一块材质的三个深浅**，而不是三种来路不同的灰。

### ⑤ 删除三条（第 4 / 6 / 7 条）

「设备与模式」整节（摇一摇 / 省电 / 夜间 / 专注四个**功能**，三个文件整份删除）、
诊断里六组 UI 相关项（含 `StackLabView` 整页）、共享密钥 / 家庭管理 / 语音播报
（`FamilyAndKeySharing.swift` 整份删除）。语音那一行删得最干净：它翻转的键
**全仓没有一个读者**，而读它的那个类型早就没了。

连带效果最能说明这仓的规矩：§6 那张本机键表要同时删七行，`scan/localstore.py` 里
指向已删文件的清理登记也要删 —— 否则门禁立刻报「这张清单在说谎」（它就是在读取时
`FileNotFoundError` 被发现的）。**删功能 = 同时删表里的行**。

### ⑥ 检查更新：令牌收成一个出处（第 5 条，⚠️ 还差用户粘贴那把 key）

新增 `Services/GithubToken.swift`：`static let value` 是 key 的**唯一**住处，
`UpdateService.githubToken` 只做只读转发（原先读 `UserDefaults`，于是每台设备都要手输一次）。
那个 Token 弹窗与它的两个 `@State` 一起删除。⚠️ 值仍是空串 —— 用户说「我之前提供过」，
但全仓与 git 全历史都搜不到该形状的字符串（`git log --all -S"ghp_"` 两次都空）。
为空时按钮照旧按得动，只是会说一句真话。

### ⑦ 车控那一屏的车（第 8 条）

`Features/Control/CarModelView.swift`（RealityKit，新文件）：代码搭的真三维车，
拖动转车（转的是模型不是镜头）、点部位控车（`.targetedToAnyEntity()`）。
可点的**只有**指令表里有的那几件 —— 后备箱点不动（它只有状态、没有开合指令），
四门点下去给一个二选一，不替用户猜。旧的线描俯视图 `CarTopView` 整块删除。

### ⑧ 地图页七处（第 9 条）

定位漂移（百米精度 + 第一个点就用 + 从没读过 `horizontalAccuracy` → 改成最高精度、
挑最准的一个、够准就用、6 秒兜底、精度如实画出来）、车钉（`body` 从来没调用过
`ringStyle`，刻度盘/电量弧/数字全是到不了的代码）、罗盘（系统控件搬不动 → 自己画一枚，
与右侧那两枚同一行）、比例尺（`.onChange(of: camera)` 不覆盖所有手势 → 换
`onMapCameraChange(frequency: .continuous)` + 6% 门槛）、抽屉（去掉「框选」的底与描边，
改成数字当头、名字在下、各格等宽平分、整行同一中轴）。

### 验证状态

`python3 scan/all.py` —— **34/34 全绿**（33 条门禁 + `check_style.js`）。这一轮没有新门禁，
但门禁当场抓出三处：`copy.py` 三条超长文案、`lintcfg.py`（`MapSpineView.swift` 又到 1207 行
→ 搬出 `MapSpineAnnotations.swift`）、`localstore.py`（§6 表里七个键已不存在）；
`scan.py` 另拦下 20 个未登记的 SDK 名字，逐个对着 Apple 文档 JSON 核过（其中当场
改掉一个真错误：`SimpleMaterial` 的 `roughness` 是 `MaterialScalarParameter` 不是 `Float`）。

本机没有 Swift 工具链：**编译与真实观感只有 CI / 真机能回答**。这一轮风险最高的三处
写在 HANDOFF §20 的验证状态里。

---

## 2026-09-25 第十轮：CI 第一次红 + 四条回执（正常启动 / 卡片更透 / 抽屉记忆 / token）

### ① CI 第一次红：三条错，一处根因

`CarModelView.swift` 三处 `value of type 'Entity' has no member 'model'` ——
`doors` / `trunk` / `headLights` 的类型写成了 `Entity`，而给它们上色走的是
`HasModel.model`（**`ModelEntity` 符合，`Entity` 不符合**）。改成造它时用的那个类型即好。
本机没有编译器时的规矩加了一条：**造出来是什么类型就写什么类型**。

### ② 用户四条回执

| 回执 | 落地 |
|---|---|
| 1 先正常启动试一次 | `LaunchFence` 四个开关全开（正式形态）；文件头改成实验记录并写明往回关的顺序 |
| 3 试试（我追求的就是液态玻璃的美感） | 卡片按底下真的是什么选变体：`EnvironmentValues.photoBackdrop`（铺照片/瓦片 → `.clear`） |
| 5 试试 | 抽屉记忆（`@AppStorage`，设备键 `carkeeper_map_drawer`）+ 呼吸（内容淡入，与高度同拍） |
| 6 私库/个人 ipa | 把用户的判断记进 `GithubToken.swift`（事实照旧：进了历史、也进 ipa） |

同一轮补上一处漏：地图右侧三枚圆钮没有包进 `GlassEffectContainer`（底条 + 两臂早就包了）。

### ③ 门禁长了一条判据

`localstore.py` 判据 ④：**§6 标题自称的键数必须等于表的行数**。
起因是新键进来时看到的那句「表 26 行、标题自称 33」—— 第九轮删了七个键，行删了、
数字没改（再往前它还错过一次：写照「42」实际 33）。「同一个事实写在两处」在本仓是第四次。
探针双向验过（改数字 / 删数字都报，还原哈希一致）。
顺带记一个自己踩的坑：判据 ④ 第一版变量名 `why` 与上面 `SETTERS` 循环的局部撞了，
于是每次都报、理由却是别人的注释 —— 变量名也是一种约定。

### 验证状态

`python3 scan/all.py` —— **34/34 全绿**。

本机没有 Swift 工具链：**编译与真实观感只有 CI / 真机能回答**。这一轮风险最高的两处：
`.clear` 玻璃（正文对比度跟着底下的照片走，回退是一行）、以及 `@AppStorage` 换掉
`@State`（抽屉的开合状态从内存搬到了磁盘）。两者都在 HANDOFF §21 里写明了代价与回退法。

---

## 2026-09-25 第十一轮：系统罗盘与系统比例尺回来了、续航圈差 1000 倍、我跑到湖里

### ① 「系统控件搬不动」被推翻 —— 它为这一屏养了整套机器

第 9 条那一轮认定 `MapCompass` / `MapScaleView` 的位置由 MapKit 定死，于是自己画罗盘、
自己量尺子。**Apple 文档里明写这两件可以当独立视图用**（`Map(scope:)` +
`MapCompass(scope:)` + `MapScaleView(anchorEdge:scope:)` + `.mapScope(_:)`）——
位置由持有它们的容器决定。删掉的是：`MapReader` / `MapProxy.convert` 测距、
`metersPerPoint` / `scaleBar` / `ruler` / `scaleRuler` / `flashScale`、
`compassButton` / `resetNorth`、6 个 `@State`、还有**一条每帧回调**
（`onMapCameraChange(frequency: .continuous)`）。

同一轮补上第 9 条的副作用：撤掉 `.mapControls { MapCompass() }` 反而把**默认控件集**放回来了
（地图转过之后自动出现一枚，贴在地图自己的角上 = 状态栏里，压住电池 —— 用户截图里有两枚罗盘）。
现在 `.mapControls { }` + `.mapControlVisibility(.hidden)`，位置改由我们给：
比例尺在左上、罗盘在右列第一格，两者都在安全区之下。

### ② 续航圈：把 km 当米用，半径差 1000 倍

车端 `RemainedPowerMile` 的单位是 **km**（`API-FIELD-MAP.md` 写着样例 204；
而且卡里那一格一直按 km 显示）—— 代码里的注释却写着「本身就是米」。
于是「续航圈」只有 243 m，看起来与「定位误差圈」一模一样（用户截图里那个虚线圆就是它）。
改法：`rangeMeters` 一处 ×1000。

### ③ 我跑到湖里：WGS-84 与 GCJ-02

手机是 WGS-84（CoreLocation 原始值），车是 GCJ-02（接口 `mapType=GCJ02`），
瓦片也是 GCJ-02（高德）—— 于是只有自己那个点偏 300–600 m，而它**自称精度 ≤20 m**。
新增 `ChinaDatum` + `PhoneLocation.mapCoordinate`，三处画图 / 移镜头的调用点改用它。

### 验证状态

`python3 scan/all.py` —— **34/34 全绿**。本机没有 Swift 工具链，编译与观感只有 CI / 真机能回答。

---

## 2026-09-25 第十二轮：九条（行程 / 健康 / 玻璃层级 / 两厢车 / 聚焦 / 更新 401）

用户一次给了九条。这一轮有三条要求**各撞上一个用 curl 量出来的事实**，
而那三个事实比改动本身更重要（详见 `HANDOFF §23`）。

### ① 三条要求背后的实测

- **行程的「道路路线」**：第一版按最自然的写法用 `MKDirections`，被 `scan/paidcap.py`
  当场拦下 —— Apple 明说非 ADP 成员（＝本项目的免费账号）不能提供路线导航。
  这不是门禁太严：那段代码在这个账号下**只是安静地失败**，看起来像网络问题。
  改用免密钥的 OSRM（与本仓「天气从 WeatherKit 换 Open-Meteo」同一条路数），
  并在请求前后做 GCJ-02 ↔ WGS-84 换算（车端坐标是 GCJ-02，OSRM 吃 WGS-84）。
- **Windows 聚焦又失败**：量出根因是**尺寸差 + 一个共用的 12 秒超时** ——
  必应那张 341 KB，聚焦那张 1.34–2.0 MB，而一张失败就整源失败。
  改成图用 45 秒 + 候选顺次顶位（索引本来就给了 4 张）。
- **检查更新 401**：那把令牌确实无效；而**仓库其实是公开库**（匿名读到 200 与 ipa），
  所以默认改走匿名。同一轮**当场**遇到匿名限流（403，60 次/小时）——
  所以令牌那个空位留着，只是不再是「必须先配」。

### ② 界面这一轮改了什么

- **评级区从「数字墙」变成一枚环**（`DSRing`：弧＝百分比，中心写分数）——
  96pt 超细巨字 + 线性光带 + 计数条这三件说同一件事的东西合并成一件。
  分系统行里那条 88pt 宽、3pt 高的迷你光带删掉（它与右边那个百分数是同一个数）。
- **底条**：未选中的字回到实色（vibrancy 的本意就是压低对比度，而这是导航），
  选中胶囊从「白色半透明扁面」换成**真玻璃**（与条子同处一个容器）。
- **`DSGroup` 不再自带一层底**：那一层 `panel` 就是用户说的「多级层 / 不通透的灰」——
  行现在直接坐在卡片的玻璃上。全站 26 处分组一起变（代价与回退都写在那一行上）。
- **文字的外发光外壳**（用户第 8 条的提议）：`dsInkGlow()`，壳色是动态令牌，
  只挂在地图这一屏压着连续画面的玻璃字上。
- **全站控件的“不换行”审核**：审下来罪犯是**共享控件**，所以修在四处
  （`DSKeyValueRow` / `DSStatRow` / `DSSegmented` / `DSSectionHeader`）+ 充电页的 `miniStat`。
- **两厢车**：总长 4.60→4.10 米而轴距不动（＝短后悬）、座舱拉到尾、尾门竖起来。

### 验证状态

`python3 scan/all.py` —— **34/34 全绿**。本机没有 Swift 工具链，编译与观感只有 CI / 真机能回答。

---

## 2026-09-25 第十三轮：地图页那一条手工 + 一份全站性能账

用户两条：①地图页默认极限 3D 视角 / 车牌名删除 / 电量删除 / 车放正 / 车用玻璃胶囊不要黑乎乎；
②底部导航点选或滑动不要「颤抖放大特效」（太耗性能），并把全站还耗性能的东西列出来。

### ① 地图页

- **3D**：`cameraPitch = 65` 三处镜头共用 + `mapStyle(.standard(elevation: .realistic))`。
  补上三处在此之前会**打回平面**的路：开机第一帧（`.automatic` 没有俯仰角）、
  「移到手机」、点充电站聚合点（这两处此前把 `pitch` 写死 `0`）。
  开机第一帧停在 `AppStore.parkingLocation`（上一次知道的车位），不是假坐标。
- **车牌名**：底条左臂从「车牌前两个字」换成 `car.fill` 图标；两个只服务它的计算属性删掉
  （其中一个**此前已经没有读者**）。
- **电量 / 车放正 / 玻璃胶囊**：车钉只剩「一枚玻璃胶囊里的一辆车」+ 接地阴影 + 车灯光晕。
  刻度盘、电量弧、盘下数字、按航向旋转、`surface` 画的实心黑底盘 —— 五件一起删。
  理由分三类，都写在 `MapCarPin` 头注：与抽屉里那一格重复、正面视角的车转过 90° 像翻了、
  深色模式下那块底盘就是一块黑。
- 钉下面那一行字（MapKit 自动画的 `Annotation` 标题）也传空串了。

### ② 颤抖放大：三处删除 + 一处根因

删掉 `pageDeck` 的 3.5% 缩放（每帧）、`DSPrimaryButtonStyle` 的按下缩放（全仓唯一一处，
且是整宽按钮）、`ArmSlot` 的 `scale(.86)`（原型那句不照搬）。

根因是**弹簧选错了**：模式条的位置量 `c` 用的是会过冲的 `TokensMotion.count`
（`dampingFraction 0.6`），而 `c` 每一帧被宿主拿去算六页的交叉过渡 `opacity` ——
过冲于是变成「六页（含活地图）的透明度来回摆」。新增 `TokensMotion.settle`
（临界阻尼、不过冲），`snap` / `settle` 改用它。顺带把**点选**与**滑动吸附**统一成同一种动效。

### ③ 全站性能账

`HANDOFF §24.3` 是一张十行的表（量级 / 现状 / 建议）。真金白银的是四条：
六页同屏、`MapSpineData.build()` 每次求值都重算（含 `parkingLocation` 每次读都解档
UserDefaults、`parkingHistory` 每条现造 `CLLocation`、`clusterHotspots` 是 O(n²)）、
列表里逐张卡的玻璃、以及「每张行程卡 = 一张真 `Map`」。
这三条是本轮**没有动**的：它们是取舍，不是修 bug，等用户从表里挑。

### 验证状态

`python3 scan/all.py` —— **34/34 全绿**。本机没有 Swift 工具链，编译与观感只有 CI / 真机能回答。

## 第十四轮（2026-09-25）：五条手工，两条量出了数

① 「行程卡片的高度没有被地图占满 才一半」→ 根因是 `ZStack` 取**较大的孩子**当自己的高度
（正面被裁在上半截），改成「背面定高度、正面铺在它上面（`overlay`）」，地图取弹性高度。
② 「全局全部字体都加层发光阴影 看看能不能在液态玻璃中看清」→ `TextRenderer` 挂在 App 根上
（`.dsTextGlow()`），三处**文字**上的逐处 `dsInkGlow()` 删掉（图形那份留着）。
代价是每条文字多一遍离屏模糊，回退是一行。
③ 「充电里面的电压/电流 拥挤了」→ `voltAmp` 拆成 `volt` / `amp`，`DSStatStrip.Item`
多一个可选的第二行（`second:`）；那一格的可写宽度算过（~75pt vs 拼句 ~110pt）。
④ 「底部导航删除车辆，因为左下角已有入口」→ `HomeMode.vehicle` 挪到 case 表**末尾**
（条子 5 档，而「叠叠乐的层号 = 条子位置」这条 identity 因此仍然成立）、`stripItems` 去掉它、
`DSSwipeStrip.index` 变 `Int?`（不高亮任何一档、透镜淡出）、车钮自己取强调色表示「此刻所在」。
⑤ 「滑动选择时左右的俩个胶囊应该消失下」→ `ArmSlot` 改成**不在场**而不是收到 0 宽
（`GlassEffectContainer` 的职责是「把玻璃变形」而不是「消失」），并搬进 `DSSwipeStrip.swift`。

同轮修掉一个真 bug：条外那次拖动的松手分支此前**无条件吸附**，于是点左臂的车钮会
「先换档、再被吸回去」。

验证：`python3 scan/all.py` —— **34/34 全绿**。本机没有 Swift 工具链，编译与观感只有 CI / 真机能回答。

## 第十五轮（2026-09-25·接上）：出行页改成两段（tab）

用户：「出行里面行程卡和消息列表的上下布局改为 tab 页」。
出行从一张长卷（总览 → 30 张行程地图卡 → 常停之地 → 评分 → 车的事件）改成
「巨字头 → 分段控件 → 当前那一段的卡」：**行程**（总览 / 行程卡 / 常停之地 / 评分）
与 **事件**（`MessagesSection`）。做法照车辆档那三段（分段控件与巨字头停在原地）。
段落词汇用现有的 `HomeSub`（新增 `journeys` / `events` + `tripsTabs`），
不另写局部枚举；懒加载只挂在「行程」那一段；四处「在下面『车的事件』」的文案同步改成
「那一段」（指示的是位置，位置换了指示也得分着换）。

验证：`python3 scan/all.py` —— **34/34 全绿**。

接上的一手：这一轮推上去的 CI（`run 8a803d9`）**只红了一条** ——
`MapSpineView.swift:681` 的三元两个分支类型不同（`TokensPalette.accent` 是 `Color`、
`TokensInk.primary` 是 `AnyShapeStyle`）。修法是把具体色装箱（`AnyShapeStyle(accent)`），
**不是**把两支都改成 `Color`（那会丢掉非当前态那一支的自适应色）。全仓混类型的三元只此一处；
这一改曾把该文件推到 1202 行（越 `lintcfg.py` 的 1200），压注释后回到 1199。

---

## 第十六轮（2026-09-26）：底条照相机重构 + 两个显示设置 + 刷新节律四档 + 镜头跟着车 + 行程卡去掉电量

一次给了六条要求，落下来是五件事（每一件的理由与边界写在 `HANDOFF.md` §27）：

1. **底部导航照相机那条模式行重建**（用户：「重新仔细研究相机 app 的逻辑，来重构我们的底部导航」）。
   形状照相机那张图：模式名在一整条**贴底的全宽横带**里、选中的套一枚胶囊，
   两枚圆钮移到**它上面一行**。连带删掉「按住展开」整套状态（`expand` / `onExpand` /
   `retractToken` / `ArmSlot` 与两条 620ms 收回计时器）—— 它存在的唯一理由是
   「静止只露三档」，而那个前提正是圆钮在挤条宽造成的。
2. **两个自定义设置**（用户：「设置文字的发光阴影程度；全局调整液态玻璃的通透度？（可行的话）」）：
   新增 `Design/DisplaySettings.swift`（三格里两格是滑杆、一格是三档分段）。
   可行的实话：系统没给材质的透明度旋钮，能选的是**用哪一档材质** ——
   于是「更透 / 标准 / 更实」换材质，滑杆调我们画的那几层半透明的底。
3. **刷新节律：地图页改成一条退避曲线**（用户：有速度 → 2 秒；停着 → 「15 秒久了，
   改用更智能的算法吧，直至最高 60 秒」；其他页 1 分钟；重 api 查看时或每 5 分钟）：
   睡眠改成**一秒一格**（换档要当场生效，那一页的重数据要当场取）。停着那一档是
   `2→4→8→16→32→60` —— 每读到一次 0 速度翻一倍、封顶 60（用户给的数），
   自变量就是「连着读到过几次 0」（读数就是自变量，不另记时刻）。
   期间否掉了两个定值形状：「停着固定 60 秒」（漏起步）与「停着固定 15 秒」
  （一停一整夜就是 240 次/小时）。
4. **镜头跟着车**（新文件 `Features/Map/MapCameraFollow.swift`）：朝向随车、
   车钉落在「地图顶 → 抽屉」那段正中（镜头中心沿**车背后**推，不是向南推）、
   人那一侧走同一个函数、车动时一律跟车。`follow` 是一个持续意图，不是「上一次按了哪个钮」。
   `centerOnCar` 与新状态一起搬出 `MapSpineView.swift`（1231 行 → 1199）。
5. **行程卡去掉电量**：`TripRecord` 加两个带默认值的 `startAddr` / `endAddr`（来自点火 / 熄火消息的
   `addrName`），正面地图下多一行「起点 → 终点」、背面把「电量 %→%」换成起点 / 终点两行；
   合并两个数据源时位置名从落选的那条补上。

验证：`python3 scan/all.py` —— **34/34 全绿**。本机没有 Swift 工具链：
编译只有 CI 能验；横带的比例、车钉落在带子里的位置、发光滑杆的手感只有真机能验。
`Glass.tint`（材质那一档）与「`@ObservedObject` 挂在 `App` 上能不能把整棵树带着重画」
是这一轮最需要 CI / 真机回答的两处。

---

## 第十七轮（2026-09-26）：上一轮那条底条**改错了**，重新量一遍再改

用户：「底部导航的改错了，你并没有仔细看相机底部导航静态和动态时的结构，先读懂，
给我看后再实施我们的改动」。于是这一轮**先只量、只读**（Pillow 按像素量三张截图），
把结论交回去确认，再动代码。

**量出来的结论（两条推翻了上一轮）**：

1. **相机静态只露当前档 ±1 共三档**。两张图放一起才看得清：同一台机器有六档
   （影效果/视频/照片/人像/空间/全景），而静态那张只画得出 视频/照片/人像；
   两图**字距一样**（190px ≈ 62pt），变的只是「露出多少」。上一轮把静态改成
   「五档等距铺满整行」—— 相机没有这个形态。
2. **两枚圆钮本来就在模式条那一行**（左下缩略图、右下翻转镜头），而「只露三档」
   正是它们的**后果** —— 上一轮把它们挪到上面另起一行，理由（「条子只剩 240pt」）
   恰恰是把后果当成了原因。

其余量到的数（都进 `HANDOFF §28`）：动态那张里带子顶边从 247px 抬到 295px、
实度从约 20% 黑到约 60% 黑、两枚圆钮不在场、可见档涨到五档半。
用户的选择：静态三档、圆钮回这一行、**跟手时带子随手指而胶囊永远居中**
（也就是不做相机那种会变高变实的动态态）。

**改了什么**：`bottomBar` 从两行改回一行（两个 `Spacer` 把圆钮推到带子两端），
新增通铺底玻璃 `band`；`DSSwipeStrip` 的条宽定成**三档派生量**（`staticSlots = 3`）、
删掉它自己那圈玻璃（底玻璃归宿主那条带子）、标签的裁剪判据整个删掉、遮罩回矩形。

**顺带修掉一个真问题**：用户答「v16（两行）也这样」—— 而我量到他那张图上
**条子内部整片平坦（起伏 < 8/255）、左钮内部也平坦（68…69），只有右钮的钥匙是白的（251）**。
两处都不显示。本机不能复现，于是把能让人「什么都不显示」的机制逐条拆掉：
标签不再靠「算出来的位置」决定画不画、初底条上的字与图形**一律实色**
（左钮的图形从 `TokensInk.primary` 换成实色）。依据是两张截图的对比（不是受控实验），
所以装上去之后 **最想要一张新截图**；若仍不见，下一个要排的是全局文字外壳 `DSTextGlow`。

**一处如实写下的偏离**：相机那条底带铺到屏幕最下沿，我们停在离底 26pt —— 
MapKit 的法律信息与「高德地图」就在这 26pt 里，盖住它比少 26pt 更糟
（要铺到底，`band` 上加一行 `.padding(.bottom, -Self.barGap)`）。

验证：`python3 scan/all.py` —— **34/34 全绿**（`MapSpineView.swift` 1199 行、`DSSwipeStrip.swift` 591 行）。
编译仍只有 CI 能验（动了两个文件的类型面）；三档窗口的疏密、带子的实度（现在由「玻璃通透度」
那根设置统一管）与 28.4 那两处是不是真回来了 —— 只有真机看得见。

---

## 第十八轮（2026-09-26）：第三批裁图定形 —— 底玻璃是**两钮之间那一条胶囊**，并补上相机的拖动态

用户第三批给的是**裁出来的干净底**（能量到边），并说清工作方式：先读懂、用 HTML 模拟给他看、他点头才改。
模拟页：`design-preview/camera-bar.html`（三张图的 1:1 复刻 + 一块能拖的 + 我们 v18 的两态）。

量到的（px @3.07 px/pt）：底玻璃 **660×144px = 215×47pt**，**胶囊**、**悬在两枚圆钮之间**；
圆钮 **144px = 47pt，与带子等高**、离屏边 33pt、中缝 9pt；字距 190px = 62pt（1.32 × 带高）、
字号 13pt；选中胶囊 **219×124px = 71×40pt（0.86 × 带高）** → 拖动 **237×144px = 77×47pt（1.0）**。
拖动那两张：**带子溶解、两枚圆钮不在场、字铺满整屏**（最外那档暗到 ~57%），
而胶囊**仍在正中** —— 跟手的字，不是胶囊。

两处推翻上一轮：① 静态不是「通铺全宽」，是**两钮之间那一段**（215pt 恰好就是它 —— 它不是常量）；
② 拖动不是「带子变高变实」而是**溶解**（那条结论来自一张没裁干净的照片）。

落进代码（几何全部推出来，没有新常量）：

- 带子搬到 `DSSwipeStrip.band(barW:)`（宽 = `availableWidth` = 两钮之间那一段），宿主的通铺矩形 `band` 删了；
- 圆钮 **58 → 54**（与条高相等）→ `stripLaneWidth` = **248pt**（相机那 215pt 的同一个量）；
- 节距 **74 → 71**（= 带高 54 × 1.32）：`slot` 38 → 36、`gapMax` → **0.65 × 带高**，
  且按 `spillWidth` 算（两张图量到的字距一样，这个数不能挂在带宽上）；
- **`staticSlots` 删了**：「静止看得见三档」现在是几何的**后果**（248 ÷ 71 = 3.5），不是输入；
- 胶囊 0.86 × 条高 → 拖动 1.0（宽 1.15 × 节距 → 1.24），尺寸变形走 `GlassEffectContainer`；
- 拖动态 = 带子淡到 0 + 胶囊长到满高 + 遮罩从条宽改到**整屏**（字因此溢出条子，而 `frame` 不动）
  + 两枚圆钮让位（`onDragging` 报给宿主）；最外那档按「离开可见带多远」渐隐到 0.55。

一处取舍写进了代码：圆钮的让位用**透明**而不是「不在场」—— 后者会把带子撑宽（带宽就是
「两钮之间那一段」），溶解到一半会跳；真机看见鬼影时的下一手是把它挪出玻璃容器。
一处偏离：相机两钮离屏边 33pt，我们仍 8pt —— 我们的条高比相机大 15%，33pt 会把 248 的带子
挤到 198，而节距 71 的三档需要 213。

验证：`python3 scan/all.py` —— **34/34 全绿**（`MapSpineView.swift` 1200 行、`DSSwipeStrip.swift` 661 行）。
只有 CI 能验：条子多了 `spillWidth` / `onDragging` 两个参数（声明顺序与调用点已核，
并删掉了一个会与函数同名的局部 `pitch`）。只有真机能验：**字溢出条子会不会被上游裁掉**、
圆钮透明后有没有鬼影、「字铺满整屏」在 390pt 上的观感。

---

## 第二十轮（2026-09-26）：卡片变大的账 + 「降低透明度」那一档 + 圆钮移出层级

用户三条，落在三处（详细的每一件写在 `HANDOFF.md` §30）：

1. **「每个界面的卡片怎么都变大了」→ 全局文字外壳的 `displayPadding`**。它返回「四面各留
   一格 = 外壳半径」——而 Apple 对这个属性写的正是「extend the drawing bounds」，
   于是**每行字高 6pt**，卡片按内容撑高就全跟着长。现在返回 `EdgeInsets()`：
   **发光是绘制，不是排版**。代价：最外一圈壳会被裁掉（字形侧边距还在）。
2. **「降低透明度」那一档由我们自己接**。量到的是：系统对手写玻璃的降法是**去掉模糊、
   只留一层淡色**（卡里能看出底下的地图纹理，只比周围亮 ~20/255），而字是白的实色 ——
   白字压淡色，同一屏每一块玻璃都变成浅色方块。相机那条底子不变，是因为它**底下没有系统
   材质**（自己画的半透明黑）。于是 `dsGlass` 多一个落点 `DSGlassSurface`（`View`）：
   那一档改画**不透明的 `TokensPalette.surface` + 同一圈发丝线**（HIG：
   *offer solid-fill alternatives at component level*）。调用点一个字未改。
3. **圆钮真的移出层级**。`GlassEffectContainer` 会把子树里的玻璃**合成成一个形状** ——
   透明度 0 在它眼里只是内容不见了（上一轮 §29.3 那条结论作废）。现在 `if barDragging`
   决定在不在（同尺寸占位），淡出交给 `.transition(.opacity)`；带子同样处理。

验证：`scan/all.py` **34/34 全绿**（`MapSpineView.swift` 1198 行、`DSSwipeStrip.swift` 670 行）。
只有 CI 能验：`DSGlassSurface` 的成员初始化器顺序、两个 `@ViewBuilder` 分支、
`@Environment(\.accessibilityReduceTransparency)` 这个名字。
只有真机能验：**容器还认不认包在包装视图里的玻璃**（唯一一处「可能白改」）、
圆钮移出层级会不会打断正在进行的拖动、以及实底那一档的观感。
