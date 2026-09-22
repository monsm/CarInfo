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

- 地图**标注聚合**未做（现在只取最近 12 个充电站）。
- **充电回放已做**（功率采样曲线，数据与账本同源）；**行程回放做不了** —— `TripRecord` 只有起终点、没有逐点轨迹，这是数据现状，界面里已照实写明。
- 各页仍有约 56 处有意保留的系统色/写死色：Widget（语义色）、App Clip 与 Watch（独立 target，没有主题）、模态遮罩、阴影、`ArtTheme.swift` 里的取值定义本身。
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
| 真实云量/天气/实测辐照度 | ⚠️ 没有 | App 里没有天气数据源。现在给的是**晴空模型**，界面上照实写「不是实测」 |
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
