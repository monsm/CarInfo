# CarKeeper 重构状态（截至 2026-09-22）

一句话：**首页就是地图；一个令牌层驱动四套艺术方向；界面上的每个数字要么来自车端真实字段，要么不出现。**

---

## 1. 现在的四层结构

| 层 | 是什么 | 关键文件 |
|---|---|---|
| **设计层** | 令牌（颜色/字/间距/圆角/动效/触觉）+ 四套艺术主题 + DS 组件 | `Design/Tokens.swift`、`Design/ArtTheme.swift`、`Design/DS.swift`、`Design/Theme.swift` |
| **数据适配层** | 把 `AppStore` 的真实缓存翻译成"地图上画得出来的东西"；**没有数据就是 nil** | `Features/Map/MapSpineData.swift`、`Services/ChargeLedger.swift`、`Services/HistoryStore.swift` |
| **页面层** | 地图主屏 + 深潜页（43 个文件 → 现在 12 个面） | `Features/Map/*`、`Features/Battery/*`、`Features/Control/*`、`Features/Mine/*` |
| **系统层** | Widget / Watch / App Clip / Siri / 无障碍 | `Widgets/`、`WatchApp/`、`AppClip/`、`Shared/` |

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
| 标题 | 7 个裸 `.navigationTitle` 的页面（全量数据 / 设计令牌 / 驾驶评分 / 健康报告 / 艺术主题 / 行程 / 车辆档案）改成 `DSPageTitle` + `dsPageTitle()` **成套**；`DevView` 连横向页面边距都没有，补了 `pageBackground()` |
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

