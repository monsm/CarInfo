# CarKeeper 重构状态（截至 2026-09-22）

一句话：**首页就是地图；一个令牌层驱动四套艺术方向；界面上的每个数字要么来自车端真实字段，要么不出现。**

---

## 1. 现在的四层结构

| 层 | 是什么 | 关键文件 |
|---|---|---|
| **设计层** | 令牌（颜色/字/间距/圆角/动效/触觉）+ 四套艺术主题 + DS 组件 | `Design/Tokens.swift`、`Design/ArtTheme.swift`、`Design/DS.swift`、`Design/Theme.swift` |
| **数据适配层** | 把 `AppStore` 的真实缓存翻译成"地图上画得出来的东西"；**没有数据就是 nil** | `Features/Map/MapSpineData.swift`、`Services/ChargeLedger.swift`、`Services/HistoryStore.swift` |
| **页面层** | 地图主屏 + 深潜页（43 个文件 → 现在 12 个面） | `Features/Map/*`、`Features/Battery/*`、`Features/Control/*`、`Features/Mine/*` |
| **系统层** | Widget / Watch / CarPlay / App Clip / Siri / 无障碍 | `Widgets/`、`WatchApp/`、`CarPlay/`、`AppClip/`、`Shared/` |

**换肤是换值，不是换名字**：`TokensPalette` / `TokensTypo` 的取值全部转发自当前主题（`ArtThemeStore.spec`），所以全 App 约 800 处调用点跟随主题切换而**零改动**。
艺术方向的入口：我的 → 开发者工具 → 艺术主题（`Features/ThemeGalleryView.swift`，四套样张各自用那套主题的令牌真渲染）。

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
| 光池有方向、暗角、颗粒 | ✅ 已落地 | `Features/Map/MapSkyOverlay.swift`；按主题档位开关（原生主题一个像素都不加） |
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

### 10.6 一处工程告警的病因确认

AppIcon 每次 CI 都报「3 unassigned children」：实测 `Contents.json` 与磁盘**一一对应**
（12 条目 / 12 文件），真正的成因是 `1x` 的 76×76 / 29×29 / 40×40 三个槽位在当前 SDK
已不再分配（数量正好是 3）。已删条目与对应的三个 PNG。

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
