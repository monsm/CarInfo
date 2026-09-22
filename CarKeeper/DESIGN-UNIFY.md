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
| 跨 target 令牌 | 小组件用 `WT.*`，CarPlay/AppClip/Watch 各自写死一套（合计 39 处字面量） | **CarPlay / AppClip 与小组件共用 `Shared/WidgetTokens.swift`**（同一份源文件）；Watch 显式豁免（理由已核实，见下） |

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
| `Shared/WidgetTokens.swift` | **世界面**的取值（系统语义色真值）+ `VehicleSnapshot` 数据契约 | 小组件、CarPlay、AppClip、App |
| `Design/ArtTheme.swift` | 艺术主题（原生/夜光/纸上/巨字）的**取值表**：换主题 = 换这里的值 | App target 经 `TokensPalette` 读 |

**为什么小组件不直接用 `TokensPalette`**：扩展不编译 App 的 `Design/`。所以 v4 的做法是
「值只写在 `WT` 一处，App 的 `TokensPalette` 从那里转发」—— 两边由**编译器**保证不漂移。
本轮把 CarPlay 与 AppClip 也接进这一份（各自只加 `- path: Shared/WidgetTokens.swift` 一个文件，
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

## 6. 下一批（未完成，写明数量，不装作完成）

1. **行程 / 停车的数据缺口**：`tripHistory` / `parkingHistory` 全库**没有任何写入点**，
   所以「行程」层与时间轴必然是空的 —— 先按第 3 节第 4 条接事件配对。
2. **假数据**：`MonthlyReportGenerator` 现在是写死的 `1250 km / 14.5 / 8 次 / 65% / 85 分`
   （代码注释写着"模拟生成"）→ 接 `tripHistory` + `ChargeLedger`。
   AppClip 那一屏的「特斯拉 Model 3 / 85% / 420km」同理（它连车型都是编的）。
3. **车控按 `funCode` 开合控件**（本车不支持车窗/定时充电，现在照样显示按钮）。
4. **数据龄期降级**（`gpsTime` 判断"有没有新数据"，而不是看 HTTP 200）。
5. **`0000-00-00` 哨兵日期拒绝**（`daysUntil` 现在会算出「已过期 73 万天」）。
6. **里程键修复**：`AppStore` 写 `carkeeper_current_mileage` 时读的键名与真实报文
   （`totalOdometer`）不匹配 → 维保提醒永远不会响。
