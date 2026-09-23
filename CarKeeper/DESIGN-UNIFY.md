# 统一契约（DESIGN-UNIFY）

> 这份文件不是"设计说明"，是**契约**：它规定"一件东西只有一种做法"。
> 每一条后面都跟着「谁在拦」—— 违反它不再依赖人记得，而是由 CI 里的检查器出声。
>
> 2026-09-22 立。立这一版的直接原因是：仓库里同时活着**四代容器、三套行、三种标题机制、
> 两个页面边距机制**，从地图走进任一页都像换了一个 App。

---

## 0. 证据（这一版是对着数字写的，不是对着感觉）

| 维度 | 立契约前 | 立契约后（本轮） |
|---|---|---|
| 容器 | `CardBox` / `ExpandingCardBox` / `glassCard`（第二代）+ `DSCard` / `DSGroup`（第四代） | 只留 `DSCard` / `DSGroup` / `DSExpandGroup` |
| 分组容器调用点 | 旧世代 40 处（Battery 16 / Control 12 / Mine 8 / 散落 4） | **全部迁完（40/40）**；`DSExpandGroup` 现有 6 个真实调用点（电池 4 / 车控 2） |
| 行 | `KVRow`（第二代）/ `DSKeyValueRow`（第四代）/ 手写 `HStack` / `ReportRow`（第五种，只在月报里） | 只留 `DSRow` / `DSKeyValueRow` / `DSStatRow` |
| 分隔线 | `ListDivider`（`Divider().opacity(0.5)`）与 `DSDivider`/`DSSeparator` 并存 | 只留 `DSSeparator`（跟着 `DSGroupRow` 走） |
| 页面标题 | `DSPageTitle` + `dsPageTitle()`（成套，12 页）／裸 `.navigationTitle`（7 页）／什么都没有 | **30 页全部成套**：内容里 `DSPageTitle`，导航栏交给 `dsPageTitle()` |
| 页面边距 | `pageBackground()`（contentMargins 20）与手写 `.padding(.horizontal, …)`（20 或 24）并存 | 两种都指向 20pt；**DevView 原本一点横向边距都没有，已补 `pageBackground()`** |
| 字体 | 令牌 358 处 + `Theme.font(...)` 中转 + 应用内硬编码 `.font(.system(size:` 68 处 | `Theme.font` 清零；**字号字面量全库清零**（定义处之外 0 处，仅 3 处显式豁免）；`Theme.font` / `Theme.lineHeight` / `Color(hex:)` 已从代码里删掉 |
| 空态 | `DSPlaceholder`（12 处）／`PageLoadingView`+`PageErrorView`（各 1 处）／手写灰图标 | 空态一律 `DSPlaceholder`（维保记录页本轮改过来） |
| 颜色 | 令牌 631 处 + `.green`/`.orange`/`.red`/`.white`/`.black` 直用，散在 25 个文件 | **全库清零**；补了三个缺口令牌：`scrim`（遮罩/暗角/阴影）、`labelOnTint`（彩色面上的文字）、`fillSubtle` 家族 |
| 跨 target 令牌 | 小组件用 `WT.*`，AppClip/Watch 各自写死一套（合计 23 处字面量） | **AppClip 与小组件共用 `Shared/WidgetTokens.swift`**（同一份源文件）；Watch 显式豁免（理由已核实，见下） |

---

## 1. 一个页面长什么样（唯一骨架）

```
ScrollView {
    VStack(alignment: .leading, spacing: TokensSpacing.lg) {
        DSPageTitle(title: "标题", subtitle: "一句实话")   ← 原生主题下它什么都不画
        DSGroup(title: "分组") { DSGroupRow { DSRow(...) } }   ← 行在表面上，标题在画布上
        …
    }
    .padding(.horizontal, TokensSpacing.page)   ← 或者 .pageBackground()，两者都必须是 20
}
.dsPageTitle("标题")        ← 与上一行**成套**：艺术主题清导航栏，内容补标题；原生相反
```

**为什么成套**：`DSPageTitle` 在原生主题下是 `EmptyView`（原生 = 现状，逐像素不变），
`dsPageTitle()` 在艺术主题下把导航栏清空。只写一个就会：原生下没有标题，或艺术下同一句话
说两遍。这就是"三种标题机制"的根。

---

## 2. 一件东西只有一种做法

| 要做的事 | 唯一的做法 | 不许用 |
|---|---|---|
| 一块面（带内容的分组） | `DSGroup` / `DSExpandGroup` | `CardBox` / `ExpandingCardBox` / `.glassCard()` / 手写 `RoundedRectangle` |
| 一块面（自由内容） | `DSCard` | 同上 |
| 一行 | `DSRow`（设置行）/ `DSKeyValueRow`（报文行）/ `DSStatRow`（读数行） | `KVRow` / 手写 `HStack` + `Spacer` |
| 分隔线 | `DSSeparator`（由 `DSGroupRow` 自动给） | `Divider()` / `ListDivider` |
| 分组标题 | `DSSectionHeader`（`DSGroup` 自动给） | 自己写一行大写小字 |
| 空态 | `DSPlaceholder` | 手写「图标 + 暂无记录」 |
| 加载骨架 | `DSSkeleton` | 手写灰块 |
| 提示条 | `DSNotice` | 自己拼 `HStack` + 彩色底 |
| 状态 | `DSChip` / `DSLightBar` | 彩色药丸底、彩色图标砖 |
| 颜色 | `TokensPalette.*` | `.green` / `.orange` / `.red` / `Color(red:…)` |
| 字体 | `TokensTypo.*` | `.font(.system(size:` / `Theme.font(...)` / `.font(.title2)` |
| 间距 / 圆角 | `TokensSpacing.*` / `TokensRadius.*` | 魔数 |
| 图标 | `Image(safeSymbol:)` | `Image(systemName:)`（会静默变成空白） |
| 触觉 | `TokensHaptic.*` | 直接 `UIImpactFeedbackGenerator` |
| 浮层 | `.sheet` + `.dsSheetCanvas()` | 不补光的 sheet（光只铺一半比没光更糟） |

> ⚠️ `DSExpandGroup` 是**本轮新增、暂时没有调用点**的：它是电池页 / 车控页那三处
> `ExpandingCardBox` 的替代品，下一批落地时用。留着它，是为了不让那一批再发明第五个容器。

---

## 3. 结合真实报文的设计规则（日志给出的）

这些不是配色问题，是**"界面不许说谎"**的问题。真实报文（`changan_net_log_20260922.log`）
已经把答案给了：

1. **每个数字都要带"数据龄期"。** 11 次 `getCarLocation` 间隔恒为 1.5 秒、响应一模一样
   （`gpsTime` 比请求时间早 2 小时 37 分），说明 **HTTP 200 ≠ 有新数据**。
   → 车钉/数字必须能降级：龄期超过阈值时灰掉并写明「最后一次上报 X 前」。
2. **服务端没给的，界面不许自己编。** `insuranceEndDate:"0000-00-00"`、`lastCheckTime:"0000-00-00"`、
   `activeTime:"0000-00-00\n\t\t00:00:00"`（带换行与制表符）是**哨兵值**，不是日期。
   → 日期解析必须显式拒绝 `0000-00-00`（否则会出现「保险已过期 73 万天」）。
3. **能力位图决定控件是否出现。** `getMyCars` 的 `funCode` 每辆车返回自己的开关：
   本车 `#StateWindow:0`（不支持车窗）、`#PeriodicCharge:0`（不支持定时充电）、`.SOCLimit:1`。
   → 车控页不许显示这台车做不到的动作：那是一个永远失败的按钮。
4. **行程用事件配对，不靠推断。** 消息流里有 `IGNITION` / `FLOAMEOUT` 事件，每条带
   `gpsTime` + 经纬度 + `addrName`。但一个窗口里 3 次点火只有 2 次熄火 —— 事件本身会缺对。
   → 骨架用事件，里程/SOC 差做交叉校验；两者都不足时**如实说"这段不完整"**。
5. **保养的尺度服务端已经给了。** `maintainSpaceMileage: 20000` + `lastMaintainMileage: 20100`
   + 控制报文 `totalOdometer: 53766.4` → 下次保养 40100 km，**已超 13666 km**。
   → 不许再用硬编码的 10000 km 间隔。
6. **枚举没核实就显示原文。** `chrgStatus:"3"`、`carStatus:"2"`、`air.status:"0"` 的中文含义
   没有权威来源 → 像那 60 个 SDK 名字一样建「已核实表」，未核实的显示原值，不编标签。
7. **上次充电的残留不是本次充电。** `chrgStatus:"3"` 配 `chargeStarttime:2024-05-19`：
   UI 不能把这些当"正在充电"显示。

---

## 4. 谁在拦（违反契约时会出声的东西）

| 检查器 | 拦什么 |
|---|---|
| `scan/paths.py` | spec 声明的路径不存在、CI 点名却不存在的检查器、**磁盘上有却不参与编译的 Swift 文件**、CI 没编到的 target、跨 target 同名副本漂移 |
| `scan/orphans.py` | 写了页面却没有任何入口 |
| `scan/scan.py` | 未声明的类型 / 构造 / 成员、幽灵构造、未知成员 |
| `scan/access.py` | 跨文件引用 `private` 成员（`类型.成员` 形式） |
| `scan/shadowguard.py` | 把泛用名（`Color` 之类）劫持进项目命名空间的形状 |
| `scan/unreachable.py` / `deep.py` / `eol.py` / `logic.py` / `lexguard.py` / `scenes.py` / `targets.py` / `futureproof.py` | 见各自文件头 |
| `scan/design.py` | **字号 / 颜色分量 / 色相字面量**只能出现在令牌定义文件里（`Tokens.swift` / `WidgetTokens.swift` / `ArtTheme.swift`）；豁免必须写明理由，输出 ⚠️ 而不是 ✅ |
| `CarKeeper/check_style.js` | 风格（含被删的 Tab 骨架残留） |

**注意**：这些脚本能可靠抓的是**结构**（跨文件 private、未声明成员、路径缺失、孤儿页面）。
一旦伸到**类型语义**就变成噪音 —— 已经试过一次：扫"可选值传给非可选参数"得到 36 条命中、
真的 0 条。所以契约里"类型级"的条款（如 `TokensTypo.data(13)` 这种写法）只能靠编译器。

---

## 5. 字号与颜色的唯一来源（本轮补完的口子）

### 三个令牌文件，各管一段

| 文件 | 管什么 | 谁用 |
|---|---|---|
| `CarKeeper/Design/Tokens.swift` | App 内的全部取值（颜色/字号/间距/圆角/字距/尺寸/发丝线） | App target |
| `Shared/WidgetTokens.swift` | **世界面**的取值（系统语义色真值）+ `VehicleSnapshot` 数据契约 | 小组件、AppClip、App |
| `Design/ArtTheme.swift` | 艺术主题（原生/夜光/纸上/巨字）的**取值表**：换主题 = 换这里的值 | App target 经 `TokensPalette` 读 |

**为什么小组件不直接用 `TokensPalette`**：扩展不编译 App 的 `Design/`。所以 v4 的做法是
「值只写在 `WT` 一处，App 的 `TokensPalette` 从那里转发」—— 两边由**编译器**保证不漂移。
本轮把 AppClip 也接进这一份（只加 `- path: Shared/WidgetTokens.swift` 一个文件，
不加整个 `Shared/`：`ChargingActivityAttributes` 需要 ActivityKit，车机与 AppClip 不该把它编进来）。

### 字号只有两条路

1. **文字** → 系统语义阶梯（`TokensTypo.title/body/footnote/caption…`）。它们跟随 Dynamic Type。
2. **零件**（图钉、药丸、图标字形、环内读数）→ `TokensTypo.fixed(N, weight:)`。**不跟随** Dynamic Type
   —— 画布是几何图形，放大就会撑破它。尺寸仍然只从令牌文件出（`grep "fixed("` 就是全 App 的定尺清单）。

数字另有 `display(N) / metric(N) / data / dataSmall / digits(N)` —— 它们等宽，换数值时不跳动。

### 颜色只有一条路

`TokensPalette.*`。本轮补的三个口子值得单独说，因为它们是「同一件事被做了很多次」的典型：

- `scrim` —— 遮罩 / 暗角 / 落地阴影。**它不是一个全局的黑**：纸主题里它是墨（纯黑在暖纸上发蓝）。
  调用点只给不透明度。
- `labelOnTint` —— 铺在**彩色面之上**的文字色。琥珀底配白字只有 1.9:1，所以它必须是主题的一部分。
- `fillSubtle` / `glassLight` / `glassHighlight` —— 浅填充与玻璃高光边（三者本来就是同一个值的两个名字，已合并取值）。

### Watch 为什么豁免（已核实，不是偷懒）

`WT.Palette` 里的系统语义色在 watchOS 上**不存在**：Apple 文档 JSON 里
`secondarySystemGroupedBackground` 的 `platforms` = iOS / iPadOS / Mac Catalyst / visionOS，**无 watchOS**。
所以手表不能共享这份文件，它的 19 处字面量是它自己 155pt 画布的阶梯 ——
豁免理由是**平台事实**，写在了 `scan/design.py` 的 `EXEMPT` 里。

---

## 6. 主框架 = Apple Maps + 相机 App 的融合（2026-09-22 定）

自创的导航结构（Tab 栏 / 顶部胶囊图层条 / 平行的一等页面）全部拆掉了。
现在**只有两个原生 App 的语法**拼出来的一个框架：

```
┌─ 一张满屏地图（MapKit，真瓦片真手势）─────────────┐
│                                                   │
│                    车钉 / 行程线 / 常停圈 / 充电站   │
│                                                   │
│  ┌─ 底部操作条（玻璃合法：浮在内容之上）─────────┐  │  ← 相机 App 的「快门行」
│  │ 锁车 · 解锁 · 空调 · 寻车                 │  │     高频动作不离开这张图
│  └────────────────────────────────────────┘  │
│  ┌─ 贴着底边的纸（TokensPalette.surface）─────┐  │  ← Apple Maps 的 sheet
│  │        ▔▔▔ 抓手                            │  │
│  │ 现在 车辆 健康 电池 车控 出行 保养 我的 应急 诊断 │  │  ← 一级模式条（可手拖/吸附/中心放大）
│  │ ─────────────────────────────── │  │
│  │ 12345 km  ← 巨字：这一档的一个事实   │  │  ← 02 的卡头（HomeModeHead）
│  │  ──────────────────────────────────────────│  │
│  │  这一档的内容（随模式变，图不变）           │  │
│  └────────────────────────────────────────┘  │
└───────────────────────────────────────────────────┘
```

### 从相机 App 学到的四条（就是「模式」的全部定义）

1. **换档不离开取景框**：没有页面推入、没有遮罩、没有 Tab。变的只是「这张纸此刻是哪个功能界面」。
2. **每一项只有文字**：没有图标、没有底、没有描边；选中只靠颜色与字重（相机靠黄色，我们靠主题的 accent——全 App 唯一的强调色）。
3. **条子可手拖、松手吸附、中心项放大**：实现是 `Design/DSSwipeStrip.swift`，一档定宽（92pt）
   ——定宽是吸附与居中放大的几何前提，不是审美选择。拖动时宿主按**连续位置**做内容的
   淡入与 26pt 视差，所以换档是过渡，不是闪一下。
4. **条子的位置与高度在每一档里一字不动**：因此纸的高度**固定**（`max(292, 屏高 × 0.56)`），
   内容多了就**在纸里滚**，而不是把纸撞高。

### 两级模式条，不要再混

| 级别 | 控件 | 档位 | 回答的问题 |
|---|---|---|---|
| 一级 | `modeBar`（`HomeMode`） | 现在 / 车辆 / 健康 / 电池 / 车控 / 出行 / 保养 / 我的 / 应急 / 诊断 | 看哪个**功能界面** |
| 二级 | `layerStrip`（`MapSpineLayer`） | 现在 / 行程 / 停车 / 充电 | 「现在」那一档内部，地图在回答哪个问题 |

一级是**全站唯一的入口**。收归到这一条的过程分两步：

1. 四套入口先去到一条（Tab 栏 / 顶部图层胶囊 / 索引页 / 「我的」27 个磁贴）；
2. 再把**最后一份目录**也拆掉：地图工具栏那个格子按钮与整张「全部功能」索引页已删，
   原来只在那里能找到的「应急」现在是条子上的一档（紧急入口不该埋在一层目录里），
   原来指向档位的 push（卡片动作块 / 「看全部…」/「我的」链接行 / 搜索六组结果）
   全部改走 `nav.openMode`：**拨条子，不 push 第二份页面**。

加页面 = 在 `HomeMode` 加一档 + `pageContent` 加一个 case + `HomeModeHead` 加一个 case
（巨字 + 依据行）。别处不再有入口清单，而且这条现在由 `scan/oneentry.py` 逐条守着 ——
它会在 CI 上把「又长出第二个入口」的改动拦下来。

### 一条刻意**没有**照搬的

相机 App 里左右滑取景框就换档。但地图的横向拖拽是**平移** —— 抢掉它会让「拖地图」变成
「换档」，那比少一个手势糟得多。所以第 3 条只落在条子自身上。
（`DSSwipeStrip` 的注释里写了这一条，免得下一轮有人“补齐”它。）

### 顺带删掉的两处「同一件事的第二个入口」

- 顶部的**图层胶囊条**（四个胶囊 + 图标）：既不像地图（Maps 把模式选择放在纸的上沿，紧挨它控制的内容），
  也不像相机（模式条在内容下沿），还和同步状态抢同一条视线。→ 删，顶部只留「数据新不新」。
- 索引页里的**「地图上的地方」**四行（四个图层的第二个入口）。→ 删，索引页当时只剩一件事：
  列**离开地图**的深潜页。（2026-09-23 再进一步：那份目录本身也删了 —— 它就是第二份功能清单，
  而模式条上每一档都能到。工具栏那个格子按钮、`indexSheet` / `indexGroup` / `indexRow` /
  `deeplinkTitle` 四件零件一起不在代码里了。）
  `MapSpineLayer.icon` 随之删除（模式条不带图标，留着它只会让下一轮以为该带）。

### 一个待真机确认的决定

模式条现在长在**纸的上沿**（Maps 的位置）。相机里它在屏幕最下沿，而那张纸也是贴底的 ——
两者都想占底边。选上沿的理由是「模式条必须紧挨它控制的内容」（相机与 Maps 共有的那条），
且纸因此保持「贴底」。在真机上如果觉得它应该在屏幕最下沿，**那是一行的事**（把 `modeBar`
从 `bottomPanel` 里提到 `MapQuickBar` 下面）—— 改之前先看一眼再改。

---

## 7. 合并映射（功能一个不丢，页面集合变小）

方向已定：**重写表面、保留地基**（数据层 / 令牌 / 门禁不动）。
每批 = 一个提交 + 一次 CI。目标是把约 20 个页面收到 **地图 + 6 个面**：

| 目标面 | 吸收什么 | 删掉什么 | 状态 |
|---|---|---|---|
| **地图**（主屏） | 底部模式条（一级入口）+「现在」里的四个图层 + 地图上的操作条 + 搜索 + 数据龄期 | 顶部胶囊图层条、索引页的图层组、索引页本身 | ✅ |
| **车控**（页 + 操作条共用执行路径） | 车控 + **指令历史**（筛选/成功率/展开详情） | `CommandHistoryView.swift` | ✅ |
| **车**（车辆档案） | 车辆档案 + 里程记账 + 用车提示 | `MileageJournalView` / `VehicleTipsView` | ✅ |
| **保养与钱** | 维保记录 + 保险/年检 + 充电账本 + 车辆估值 + 导出 | `ExportDataView` + 三个弹层（`InspectionCalendarView` / `VehicleValuationView` / `ChargeBillSheet`） | ✅ |
| **体检与数据** | 健康报告 + 全量数据（结论 + 依据） | `DataView` | ✅ |
| **车与账号** | 账号 / 车辆切换 / 隐私 / 关于 / 设备与模式 / 应用 | 它自己那份与索引页逐行重复的功能目录 | ✅ |
| **出行** | 行程时间轴 + 常停之地 + **驾驶评分** + **消息事件流**（点/熄火事件本来就是行程的骨架） | `MessagesView` / `DrivingScorePage` | ✅ |

已删页面（合计）：`CommandHistoryView` · `MileageJournalView` · `VehicleTipsView` ·
`ExportDataView` · `MessagesView` · `DrivingScorePage`，以及整张「全部功能」索引页
（`indexSheet` / `indexGroup` / `indexRow` / `deeplinkTitle`）与「我的」里那份重复的功能目录。
深链别名（指向别的页，不占屏幕）：`.dashboard` / `.score` / `.parking` → 出行页。

### 刻意保留为独立屏幕的三个（写清理由，不是漏掉）

- **电池与充电**（`BatteryView`）：它是地图「充电」层的**深度视图**（充电流水、电芯、
  充电账本的完整版），并进车辆档案会把那一页变成两页。
- **应急面板**（`EmergencyPanel`）：拖车 / 保险 / 救援电话。它是**紧急入口** ——
  埋进别的页面里滚着找，就失去了意义。
- **开发者工具**（`DevView`）：主题样张 / 令牌清单 / 设计语言说明 —— 它不是用户功能，
  是**这个仓库的说明书**，放在用户页面里只会让用户困惑。

**最终屏幕数**：地图（家）+ 9 个深潜面（车 / 电池与充电 / 车控 / 体检与数据 / 出行 /
保养与钱 / 应急面板 / 车与账号 / 开发者工具）。改造前约 20 个页面。

---

## 8. 数据层接线：本轮落地了什么（2026-09-22 第二轮）

「功能一个不丢、全部融合」这一半做完了（§7）；**「界面在说谎」这一半本轮开始动手**，
原则不变：不加新页面，全部落进现有的「地图 + 9 个深潜面」。

| # | 做了什么 | 落在哪个面 | 依据 |
|---|---|---|---|
| ✅1 | **读层大小写清零**：77 处大小写敏感下标 → `ci*`/`ciPick`（含 4 处**变量键**：`sub[itemKey]`/`control?[codeKey]`/`presKey`/`tempKey`）；新增门禁 **`scan/keys.py`**（441 个真实报文键内置，直接下标写错大小写就红） | 全局 | §0.2、§6 |
| ✅2 | **里程接对**：`carkeeper_current_mileage` 改读 `control.totalOdometer`（原来读 `Mileage/mileage/TotalMileage` 三个**不存在**的键）；同时写 `totalMileage` → 手表/小组件的里程从恒 0 变成真实 | 车 / 小组件 / 表盘 | §4.7 |
| ✅3 | **保养计划唯一来源** `VM.maintenancePlan`：`maintainSpaceMileage`(20000) + `lastMaintainMileage`(20100) + `totalOdometer` → 下次 40100 km、已超 13666 km；地图/车 / 保养三处共用 | 地图 + 车 + 保养与钱 | §0.1 #3 |
| ✅4 | **真实充电功率** `VM.chargePowerKW` = `totalVoltage × totalCurrent`（报文里根本没有 `ChargPower`），一处算法供能量卡/曲线/账本/小组件 | 地图 + 保养与钱 + 小组件 | §11.1 #1 |
| ✅5 | **哨兵值守卫** `VM.antiSentinel`：`0000-00-00` / `0000-00-00\n\t\t00:00:00` 一律不当日期；保险到期显示**未登记**（不再打印零年零月） | 车 + 地图 | §0.1 #2、§5 |
| ✅6 | **数据龄期一等公民** `VM.reportAge`：「在线 · 车端 2 小时前上报」+ 地图新增一条 freshness 理由（>30 min 转 warn） | 地图主屏 | §5.4 |
| ✅7 | **车控终态改用有依据的判据**：`CmdFinishTime` 非空 = 已到终态；`HandleStatus` 不认识时新增**第三态「未确认」**（不再自编字符串表判成败，也不再把它记成失败） | 车控 + 指令历史 | §0.2 #9 |
| ✅8 | **补上 `UpCarCondition`**（让车端立刻上报）—— 车端停报时刷页面没用，服务端只会回放同一份快照 | 车控「低频指令」 | §0.2 #8 |
| ✅9 | **`chrgStatus:"3"` 不再写成「充电完成」**（车主确认车静止时就是 "3"）→ 「未在充电」；`chargeStart/Stoptime` 明确为**上一次**充电 | 地图 + 电池 | §0.1 #1 |
| ✅10 | **日期解析补上带时分秒的格式**：`tserviceEndtime`（`2041-10-31 18:01:18`）以前**静默解析失败** → 车联网服务到期日从不显示 | 车 + 我的 | §4.9 |
| ✅11 | **顺手修掉的三处「静默 nil」**：`VehicleView.lastServiceMiles` 用 `string(forKey:)` 读一个 Int 键（恒 nil → 那一节从未显示）；`API.parseMessages` 为补偿大小写缺陷而**双写** `realReceiverId`/`RealReceiverId`；`sub[itemKey]` 的 if/else 两个分支**完全相同** | 车 / 消息 | §6 |
| ✅12 | 修正一句「比现实更勤快」的注释：`AppStore` 里写的「车况每 60 秒轮询一次」并不存在 | — | §8 #13 |

### 第三轮：能力位图、告警总灯、88 节完整落图（2026-09-22 第三轮）

| # | 做了什么 | 落在哪个面 | 依据 |
|---|---|---|---|
| ✅13 | **告警总灯**：报警位表收成唯一来源 `VM.alarmFlags` / `VM.activeAlarms`（16 个 `*Alarm`，**非 0 即亮**，0 与缺失都不算）；`VM.maxAlarmLevel` 只在 >0 时返回（不把「没上报」显示成「等级 0 = 一切正常」）；地图主屏新增一条 `alarm` 理由，**只在真的亮着时出现** —— 每次刷新都写一句「无报警」只会训练人忽略这一栏 | 地图主屏 + 电池 | §4.8 / §5.1 |
| ✅14 | **电池页功率的重复算法删掉**：`Analysis.batteryModel` 仍在读**不存在**的 `ChargPower`/`ChargingPower`（上一轮只把 `VM.chargePowerKW` 接给了能量卡/账本/小组件），所以电池页的功率一直是 `--` | 电池 | §11.1 #1 |
| ✅15 | **88 节完整落图**：`AN.barsOf` 的采样上限 64 → 128（本车 88 节，64 的步长是 2，**会丢掉一半电芯**，而那张图就是拿来看「哪一节低」的）；极值加上**节号**：「最低·第56节 3.800 V」（来自 `maxVoltageBatteryNum`/`minVoltageBatteryNum`） | 电池「一致性」 | §4.7 |
| ✅16 | **能力位图进开发者工具**：`VM.capabilities` 解析 `funCode`（7 组 43 开关，两组键各自排序 → 两次运行行序一致、截图可比），每个分组一块折叠区，标题行给「on/total」，行内容只有**原文键名 + 1/0** | 开发者工具 | §4.2 |

**为什么这一轮**没有**「按 `funCode` 隐藏控件」** —— 这是刻意的决定，不是漏做：

1. 43 个缩写里只有少数能自证（`StateWindow`=车窗、`Statelock`=门锁、`airBtn`=空调按钮），
   其余（`zjcsStatusRC`/`openPJ`/`openBY`/`isFence`/`#18`/`#26`…）零依据，参考实现也零引用。
2. 更要紧的是**两组同名开关互相矛盾**：本车 `control/remoteBaseControl.airBtn = 1`，
   而 `control/remoteBaseControl_XNY.airBtn = 0`（XNY = 新能源那组），无从判断哪一组作准。
3. 按一个可能是错的值去隐藏控件，会**藏掉真能用的功能** —— 这比多显示一个按钮更糟
   （用户会以为车没有这个能力），而多显示一个按钮最坏就是按下去失败。

所以位图先当**证据**摆在开发者工具里；等某组位与真实车控失败一一对应，再让
`VM.Capability.on` 去驱动界面。同理，`#PeriodicCharge:0`（`changeS203EV`）与
`#bookChargeA301:1`（`home/newIndex`）也互相矛盾，因此电池页的「预约充电」只做**只读状态**，不给开关。

### 还没做的（不装作完成）


1. ✅ **行程 / 停车已接上**：`AppStore.ingestEvents` 把点火/熄火事件对喂给 `startTrip`/`endTrip`/
   `saveParkingLocation`（幂等键 = 服务端 `stubId`，坐标与地址读 `jumpParam`）。
   两条诚实的保留：① 报文里消息是**倒序**，代码先按时刻升序（否则熄火会被当成点火）；
   ② 里程差只在「同一次会话内」才算 —— 历史事件的 `currentMileage` 两端都是今天的值，
   那就写 0，**不编一个估算里程**。
2. ✅ **两处假数据已删**：`MonthlyReportGenerator` 不再写死 `1250 km / 14.5 / 8 次 / 65% / 85 分`
   （没记录就直说「本月还没有记录」，并告诉用户怎么产生记录）；
   AppClip 不再编「特斯拉 Model 3 / 85% / 420km」，改为读共享快照，取不到就不显示。
3. ✅ **`funCode` 已接（上一轮的表 #16），但刻意不开合控件**：位图已解析并显示在开发者工具；
   不隐藏控件的理由（两组同名开关互相矛盾 + 藏掉真能用的功能更糟）写在上面那张表的下面。
6. ✅ **已接**（对照用）：`stubId`（幂等键）、`jumpParam`（行程骨架）、`new`（红点判据）、
   `maxAlarmLevel`（告警总灯，表 #13）、88 节单体电压（表 #15，整 88 节落图 + 极值带节号）。
   仍未引用：`pin`（控车码）。
8. ✅ **已修**：`maintainSpaceMileage`/`lastMaintainMileage`/`totalOdometer` 已接上（见上表 #2/#3）。
   （旧条目保留在此仅作对照，勿再重复实现。）
8b. ✅ **服务端已给、以前零引用的数据都已接上**：`funCode`（表 #16）、`maintainSpaceMileage`(20000)/
   `lastMaintainMileage`(20100)（表 #3）、88 节单体电压 + 26 个温度探针（表 #15）、`insulateResistance`、
   `insuranceCompany`/`insurancePhone`、`tserviceStatus`、消息 `stubId`（幂等键）、`jumpParam`（行程骨架）、
   `maxAlarmLevel` + 16 个 `*Alarm`（表 #13）。**仍零引用**：`pin`（控车码）、`sidAndMid`、`recordTime`、
   `carMode`/`dcStatus`、`flameoutReason`/`ignitionReason` —— 这几个**含义未核实，不编**。
9. **未核实枚举禁止编中文**：`chrgStatus`/`carStatus`/`dcStatus`/`air.status` 等一律显示原文。
10. ✅ **已修**：令牌已迁 **Keychain**（含旧 UserDefaults 值的自动迁移；退出登录时**两处都清**，
    因为只删 UserDefaults 会让凭证留在设备上）；`RawLogStore.redact()` 补上 `vin`/`idcard`/姓名/`tuid`/
    坐标/地址文本/K8s 容器名等 12 类。仍成立的一条事实：`refresh_token` 服务端**不轮换**
    （请求与响应逐字符相同，见 API-FIELD-MAP §0）。

11. ✅ **已修**（见上表 #7/#8）：`UpCarCondition` 已补进车控「低频指令」；指令终态改用 `CmdFinishTime` 非空，
    并在 `HandleStatus` 不认识时给出第三态「未确认」。
12. ✅ **门禁已加，但归一化刻意没做**：新增 `scan/keys.py`（禁大小写敏感的直接下标）；
    而“在 `saveCache` 入口把键名一律小写”**没有采用** —— 理由：归一化只能救「已经写对的那个小写形式」，
    对 `["RemainPower"]` 这种写法毫无帮助，却会让两类写法在不同路径下时灵时不灵（更难查）；
    门禁把同一个错误变成「提交前就红」，作用面反而更大。
13. ✅ **已修**：`AppStore` 里那句「车况每 60 秒轮询一次」已改成现实（没有轮询循环，
    只有指令结果轮询 12×5 s、短信倒计时、后台刷新 15/30 min）。

> 以上第 2–13 条的**逐字段证据**（含每个字段的样例值、我们代码的读法、交叉矛盾）见
> **[`API-FIELD-MAP.md`](./API-FIELD-MAP.md)** —— 逐字段证据（每个字段的样例值、我们代码的读法、
> 报文之间互相矛盾之处），由 `scan/_fields.py` / `_msgs.py` 从日志原文生成，可复跑复现；
> 它的 §12 是「字段 → 代码接线表」。
>
> 其中「大小写敏感的下标」这一类（以前是 77 处）已收敛成常驻门禁 **[`scan/keys.py`](../scan/keys.py)**：
> 内置 441 个真实报文键，写错大小写直接红。一次性审计脚本已删除（它们只活了一轮）。

---

### 第四轮：全界面风格统一（2026-09-22 第四轮）

| # | 做了什么 | 落在哪个面 |
|---|---|---|
| ✅17 | **字体字面量清零**：`BatteryView` / `DevView` / `EmergencyPanel` / `HealthDataView` / `MaintenanceMoneyView` / `MineView` / `MapQuickBar` / `CarKeeperApp` / `MileageJournalSection` / `EnhancedToastManager` / `FamilyAndKeySharing` 全部改用 `TokensTypo.fixed(N)` / `.caption` / `.title2` 等语义阶梯；AppClip 改用 `WT.Typo`（不破坏其命名空间隔离） | 全部深潜面 |
| ✅18 | **图标一律 `safeSymbol`**：全库 `Image(systemName:)` 替换为 `Image(safeSymbol: N, fallback: N)`，防止主题切换时 icon 静默消失 | 全部深潜面 |
| ✅19 | **颜色字面量清零**：`.fill(.secondary)` / `.foregroundStyle(.secondary)` / `.foregroundColor(.secondary)` 全部改走 `TokensPalette.secondary`（换主题时自动跟随） | `ControlView`（两处指示条）+ `FamilyAndKeySharing` + `EnhancedToastManager` |

**门禁同步**：`scan/design.py` 已能拦截 `.font(.system(size: N)` 和 `.fill(.secondary)` 这类用法；`check_style.js` 与 `scan/keys.py` 不变。全库 `Image(systemName:)` 从原来散在 Design 组件里的合法用例（`DS.swift` 里 2 处设计层内部调用）+ 业务层的 40+ 处 → 业务层全部换成 `safeSymbol`；Design 层的 2 处保留（因为它们是设计系统的**实现细节**，不是界面调用）。

> ⚠️ `ThemeGalleryView.swift` 仍豁免：它的职责是展示主题的真实取值，**必须用原始字号**。
> ⚠️ Watch 仍豁免：watchOS 有自己的字号阶梯，不共享 `TokensTypo`。

### 第五轮：消息 API 修复 + 电池页框框背景（2026-09-22 第五轮）

| # | 做了什么 | 落在哪个面 |
|---|---|---|
| ✅20 | **messages 消息流**：修三处根因——① `AppStore.needsRefresh` 类型检查只认 `[String: Any]` 不认 `[[String: Any]]`，导致消息永远不缓存；② `MessagesSection.loadIfNeeded` 里 `items.isEmpty` 会误触发无限刷新循环；③ 新增 `onChange(of: store.carId)` 监听，解决 bootstrap 未完成时进入页面永远空白的问题。同时改为只缓存非空列表（空列表 = 重试，不缓存） | 出行页 > 消息节 |
| ✅21 | **电池页「框框背景」**：BatteryView 的 8 个卡片（`verdictCard`/`consistencyCard`/`chargeCard`/`motorCard`/`faultCard`/`alarmCard` 等）各自用 `DSExpandGroup`/`DSGroup`，每个都有独立的 `nightSurface` 背景矩形，叠在一起出现多框视觉效果。修复：新增 `DSSection`（与 `DSExpandGroup` 相同的标题行 + 折叠交互，但无背景）；`BatteryView.sections` 改为 `socHero` + `detailsGroup()` 两栏，`detailsGroup` 用 `dsSurface()` 包一层统一背景 | 电池页 |

**门禁同步**：无新增门禁，复用 `scan/keys.py` / `scan/design.py`。

### 第六轮：CI 修复 + CarPlay 实时地图（2026-09-22 第六轮）

| # | 做了什么 | 落在哪个面 |
|---|---|---|
| ✅22 | **CI 修复**：① `DSSection` 补上 `footer: String?` 参数（`insulationCard` 调用时缺此参数）；② `ControlView.tempButton` 里 `\(sym).circle.fill` 是字符串插值语法误出现在字符串外（之前 sed 批量替换残留），还原为 `sym + ".circle.fill"` | DS.swift / ControlView.swift |
| ✅23 | **CarPlay 已移除**：因免费账号无法配置 CarPlay entitlement，相关 target / 源码 / CI 步骤 / 文档已全部清理。保留 `VehicleSnapshot.lat/lng` 字段（主 App 地图仍用），删除 `CarPlay/` 目录 | WidgetTokens.swift / AppStore.swift |

**门禁同步**：无新增门禁。
