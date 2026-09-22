# 长安车联网 · 抓包逐字段全解

> 数据源：`D:\xm\ChangAnCarInfo\bin\Debug\changan_net_log_20260922.log`（另有 `…20260904.log` / `…20260917.log` 两份历史日志做交叉比对）
> 会话时间：**2026-09-22 09:56:27.747 → 09:56:45.190**（21 条请求）
> 本文档由脚本从日志原文生成字段清单（`scan/_fields.py` / `_msgs.py`），**不是凭印象回忆**；
> 其中「大小写敏感的下标」那一类已收敨成常驻门禁 `scan/keys.py`（一次性审计脚本已删）。
> 状态标记：✅ 已核实（报文可自证）｜❓ 未核实（含义待真机/官方文档确认，**界面必须显示原文，不许编中文**）｜🚫 我们代码读不到（见 §6）

**口径声明（重要）**：这份日志来自**参考实现**（`bin/Debug`，桌面版），不是我们 iOS 包的日志。
所以 §1 里的「1.5 秒轮询」是**参考实现的行为**；我们的 App **目前完全不轮询**（已核实：全库没有定位轮询循环，
`CarKeeperApp.swift:154` 的 1.5 s 只是启动闪屏延时，`275/331` 是 30 s 网络监测）。
**但报文结论对我们同样成立** —— 车端在 07:19:28 之后停报，服务端回放同一份快照，所以"主动轮询"本身在这里就是无效的。

---

## 0.1 车主已确认的事实（2026-09-22 当面确认，优先级高于我的推断）

凡本文件中的推测与本节冲突，**以本节为准**。

| # | 我问的 | 车主确认 | 由此确定的事 |
|---|---|---|---|
| 1 | 抓包那一刻车在干什么 | **刚跑完一段路停下不久**（日志佐证：06:45:18 点火 → 07:08:25 熄火 → 11 分钟后 tbox 上报 07:19:28） | ✅ 确定：**`chrgStatus:"3"` = 不在充电**（车当时刚行驶完、根本没插枪），且 `chargeStarttime/Stoptime/chargDeltMins` 三项是**上次充电（2024-05-20）的历史记录**。⚠️ **仍未核实**：`"1"`/`"2"` = 充电中/即将充满 只是代码里的推论，**需下次真充电时再抓一次才能定** |
| 2 | 空调开着吗 | **关着**，26℃ / 3 档只是上次设定 | ✅ 确定：`air.status:"0"` = **关**；`air.temperature`/`air.wind` 是**设定值而非当前值** → 文案写「已关闭 · 上次设定 26℃ · 风量 3 档」。⚠️ `"1"` = 开仍为推论（下次开空调时抓包可定） |
| 3 | 两个接口差 589 m 的坐标以谁为准 | **以 `location` 接口为准** | 地图/停车位置/距离一律读 `caches["location"]`；`control.lng/lat` 与 `pm25.carLocationResp` 只作它用（并在此备案差异）；消息事件的 `jumpParam.lat/lng` 与 location 同源 ✅ |
| 4 | 四轮胎温 67/68/69/67℃ 真实吗 | **真实**（那天刚长时间行驶过），正常显示 | 胎温单位就是 ℃、读数可信 → 照常显示，并在文案里注明「行驶后偏高」；`tireTemperatureStatus:0`（正常）与之一致 ✅ |
| 5 | 上次保养是 20100 km 做的吗 | **属实**：20100 km 做的，**间隔就是 2 万 km** | ✅ 直接用 `lastMaintainMileage` + `maintainSpaceMileage` 算（当前 53766.4 → **已超 13666 km**）；废掉硬编码 `defaultServiceInterval = 10000` |
| 6 | 保险到期情况 | **从未登记过，小程序里也看不到** | ✅ 显示【未登记】+ 保险公司/电话（`中华联合保险` / `95585`），**不算天数、不报过期**（参考实现也是这个做法，§0.2） |
| 7 | 消息有未读红点吗 | **没红点**（`new` 才是真的） | ⚠️ 红点不能用 `readStatus` —— 本次 5 条全是 `readStatus:0` 却无红点。→ 红点/未读一律以 `new` 为准（本次全 `false`，与观察一致）；`readStatus` 的真实语义待定，暂不用于 UI |
| 8 | 参考实现源码 | **已提供**（`D:\xm\ChangAnCarInfo`） | 🎉 已拿到并分析，改为 §0.2（含控车接口、cmd 枚举、1.5s/30s 轮询、`JsonOptions` 大小写策略等） |

---

## 0.2 参考实现（`D:\xm\ChangAnCarInfo\MainForm.cs`）带来的源码级结论

车主提供了参考实现的源码（WinForms 单文件 98 KB）。它是**同一批接口的另一个客户端**，所以它的映射表就是我们的"第二来源"。

| 结论 | 出处 | 影响 |
|---|---|---|
| 定位轮询 **1500 ms**、全量刷新 **30000 ms**、短信倒计时 1000 ms | `MainForm.cs:30-33` | ✅ 完美解释日志里 11 次恒 1.5 s 的定位请求 |
| **控车接口**：`{base}/api/car/control?pin=&cmd=&carId=&phoneType=&phoneId=&token=[&temperature=]` | `MainForm.cs:104-105` | 🆕 我们缺的那个接口（见 §4.9）；`OpenAir` 才带 `temperature`（默认 17） |
| `cmd` 枚举共 8 个，**带中文注释**：`UpCarCondition`(刷新车辆状态 TBOX)、`LockDoor`(锁门)、`UnLockDoor`(解锁)、`CloseAir`(关闭空调)、`OpenAir`(开启空调)、`FlashLight`(闪灯)、`Whistle`(鸣笛)、`RemoteSearchCar`(远程寻车) | `MainForm.cs:1065` | ✅ **与我们的指令串逐字一致**（已核对 `ControlView.swift:19-31`）；❌ 我们**没有** `UpCarCondition` |
| 异步指令结果从 `/api/car/getControlInfo?carId=&id={TaskId}` 轮询，字段 `TboxCmd`/`TaskId`/`CmdSendTime`/`CmdFinishTime`/`HandleStatus`/`HandleStatusDesc`/`HandleCode`；`CmdFinishTime == null` ⇒ **执行中** | `MainForm.cs:1488-1499`、`717-731`、`269-272` | ✅ 我们读的字段完全一致（`CommandCenter.swift:86-123`）→ 控车链路可直接信任 |
| **`location.status`：`2` = 熄火，非 2 = 行驶** | `MainForm.cs:693` | ✅ 消除了我标 ❓ 的枚举（§4.4/§4.6） |
| **`powerLineStatus`：`0` = 正常，非 0 = 异常** | `MainForm.cs:713` | ✅ 不是"是否插枪" |
| `air.status == "0"` → 「已关闭」 | `MainForm.cs:1060` | ✅ 与§0.1 #2 车主确认**双源吻合** |
| `chrgStatus`：1=充电中 / 2=即将完成 / 3=充电完成 / 其他=未充电；`chargeStatus`（control 的数字版）：1=充电中 / 3=完成 / 其他=未充电 | `MainForm.cs:707/827/1041` | ⚠️ 参考实现把它当"当前状态"→ 日志这次就会错误地显示"充电完成"，而车其实在跑。**我们的处理（加"上次充电"前缀）比参考实现正确** |
| `batteryHeatingStatus == 1` = 开启；`chargeReservationStatus == 1` = 已开启；`reservationBatteryHeatingStatus`/`reservationUseVehicleTime` 无映射 | `MainForm.cs:714-717` | ✅ 可照用 |
| 反序列化靠 **`PropertyNameCaseInsensitive = true` + `AllowReadingFromString`** | `MainForm.cs:26` | 🔑**关键对照**：参考实现用"解码器大小写不敏感"一次性解决；我们 Swift 侧没有这层，全靠在每处记得写 `ci*` → 所以才有§6 那 72 处（详 §6 结论） |
| 里程/保养：`MaintainSpaceMileage`、`LastMaintainMileage` 直接展示 | `MainForm.cs:671-672` | ✅ 与车主确认一致（§0.1 #5） |
| `insuranceEndDate` **零引用**（只显示保险公司/电话） | `MainForm.cs:655-656` | ✅ 与车主"没登记过"一致 → 我们也只显示公司与电话 |
| `funCode`、`stubId`、`new`、`readStatus`→只用 `ReadStatus`、`flameoutReason`、`ignitionReason`、`recordTime`、`sidAndMid`、`zjcsStatusRC`、`openPJ`… **全部零引用** | 全文 grep = 0 | ⚠️ 连参考实现都没用 → **这些含义确定无法从两侧代码推断**，必须靠官方文档/截图 |
| 参考实现**没有哨兵守卫**：`ActiveTime` 把 `0000-00-00\n\t\t00:00:00` 原样打印；`insuranceEndDate` 干脆不显示 | `MainForm.cs:662` | ✅ 我们加守卫是改进，不是重复造轮子 |
| 消息只映射 6 个字段：`Content`/`CreatedAt`/`Id`/`ReadStatus`/`RealReceiverId`/`Title` | `MainForm.cs:1444-1451` | ✅ `ReadStatus` 确为服务端字段名；`new`/`stubId` 两侧都没用 |

---

## 0. 先看结论（TL;DR）

1. **读层是分裂的**：`ciPick/ciNumber/ciString`（大小写不敏感）能用；**直接下标 `dict["Capitalized"]` 全部恒 nil —— 77 处，其中 72 处真失效**。已核实：JSON 由 `JSONSerialization` 解析、`caches[k] = 原始报文`、代码里没有任何「键名首字母大写」的规范化层。所以 `c["PlateNumber"]` 永远读不到 `plateNumber` → 车辆档案页显示「未绑定车牌」（详见 §6）。
2. **报文里的里程键是 `totalOdometer`**（`getControlStatus`，值 **53766.4**）；`getMyCars` 里同名字段是 `null`。我们唯一的写入点读的是 `["Mileage","mileage","TotalMileage"]` → 维保提醒**永远不会响**（详见 §5.1 / §6）。
3. **服务端早就把保养数据给了我们**：`maintainSpaceMileage: 20000`、`lastMaintainMileage: 20100` + 当前 53766.4 → **下次应在 40100 km，已超 13666 km（68% 的间隔）**。我们却用硬编码的 10000 km。
4. **哨兵值没有任何守卫**：`insuranceEndDate:"0000-00-00"`、`lastCheckTime:"0000-00-00"`、`activeTime:"0000-00-00\n\t\t00:00:00"`（**带换行和制表符**）、`shortTermFuelTrim:-100`、`pm25InnnerCarValue:"-1"`。
5. **`funCode` 是一张车辆能力位图**（7 组 43 个开关），我们的车控页是写死的 —— 而这辆车 `#StateWindow:0`（不支持车窗）、`#PeriodicCharge:0`（不支持定时充电）、`#StateFrontDoor:1`。显示不支持的控件 = 让用户去做一个不可能完成的动作。
6. **11 次定位请求、1.5 秒一次、11 份响应逐字节相同**：车的 `gpsTime` 恒为 `07:19:28`，而请求发生在 `09:56` → **数据龄期 2 小时 37 分**。「HTTP 200」完全不等于「有新数据」。
7. **两个接口对同一条车给出相差 589 m 的坐标**：`location` 报 (30.5222546, 114.2323020)「某地」，`control`/`pm25` 报 (00.000000, 00.000000)「泰康同济(武汉)医院内…东北96米」。**已定案：以 `location` 为准**（§0.1 #3）。
8. **这份日志本身就是活凭证**：`refresh_token` 明文，且刷新响应返回的 refresh_token **与请求完全相同 → 不轮换**（只有 access_token 有 `expires_in:86400`）。日志只打了 URL 的 `token=` 和 Authorization 头，**JSON body 全裸**（含 refreshToken / access_token / 姓名 / 手机 / 身份证 / 车牌 / VIN / 两条精确坐标 + 医院地址）。

---

## 1. 会话时间线（21 条请求，逐条）

| 时刻 | 请求 | 结果 | 说明 |
|---|---|---|---|
| 09:56:27.747 | POST `user/getUserInfoByToken` | 09:56:28.257 `code:"2" msg:"token expired"` | **HTTP 200 但业务失败** |
| 09:56:27.773 | POST `car/getMyCars?isNev=1` | 09:56:28.286 同上 `token expired` | 两个请求并发 → 两条都失败 |
| 09:56:28.467 | POST `scrm…/auth/cac/refresh` body=`{"refreshToken":"Ffr…"}` | 09:56:29.099 `code:200`，`expires_in:86400` | 换新 access_token |
| 09:56:29.121 | 重发 `getUserInfoByToken` | 09:56:29.425 ✅ | 刷新后重试成功 |
| 09:56:29.121 | 重发 `getMyCars?isNev=1` | 09:56:29.468 ✅ | |
| 09:56:29.519 | `charge/info` | 09:56:29.649 | 6 个数据源并发（29.519–29.521） |
| 09:56:29.520 | `car/pm/getCarPm25ByCarId` | 09:56:29.787 | |
| 09:56:29.520 | `cardata/getCarLocation?mapType=GCJ02` | 09:56:29.745 | |
| 09:56:29.521 | `api/car/getControlStatus`（注意：**没有 appserver 前缀**） | 09:56:29.909 | 197 字段 |
| 09:56:29.521 | `information/pageReceiverInfoByTime?actionType=2&limit=2000&startTime=…7天…&endTime=…` | 09:56:30.077 | 消息流 |
| 09:56:29.521 | `carcheck/getCheckResult?isNev=1` | 09:56:30.053 | 体检报告 |
| 09:56:31.691 → 09:56:45.190 | `cardata/getCarLocation` **×10** | 每次 HTTP 200 | **间隔恒为 1.5 s，11 份响应完全相同** |

**并发特性**：6 个数据源在同一毫秒发起（`29.519`–`29.521`）→ 说明参考实现是 `Task.WhenAll` 式并行；我们的 `AppStore.gather()` 用 `withTaskGroup` 并行，一致 ✅。

**证据（轮询无用）**：首次定位 `29.520` 的 `gpsTime` 就是 `2026-09-22 07:19:28`，最后一次 `45.190` 仍是 `07:19:28`；`speed: 0.0`、`heading: 550.4`、`lat/lng` 全同 → 熄火后 tbox 停报，服务端在回放同一份快照。

---

## 2. 接口总表（9 个端点 + 参数 + 我们对应的缓存键）

| # | 方法 | 路径 | 参数 | 响应形状 | 我们的缓存键 | 我们的方法 |
|---|---|---|---|---|---|---|
| 1 | POST | `/app-m/prod-api/auth/cac/refresh`（host `scrm.changan.com.cn`） | body `{"refreshToken":…}` | 对象（含 `data.status_code`） | — | `refreshOnce()` |
| 2 | POST | `/appserver/api/user/getUserInfoByToken` | `?token=` | 对象 `data`（可能是单元素数组） | `user`（属性，不入 caches） | `getUser()` |
| 3 | POST | `/appserver/api/car/getMyCars` | `?isNev=1&token=` | 数组 | `cars`（属性） | `getCars()` |
| 4 | POST | `/appserver/api/charge/info` | `?carId=&token=` | 对象 | `caches["charge"]` | `getCharge()` |
| 5 | POST | `/appserver/api/car/pm/getCarPm25ByCarId` | `?carId=&token=` | 对象（含嵌套 `carLocationResp`） | `caches["pm25"]` | `getCarPm25()` |
| 6 | POST | `/appserver/api/cardata/getCarLocation` | `?carId=&mapType=GCJ02&token=` | 对象 | `caches["location"]` | `getLocation()` |
| 7 | POST | `/api/car/getControlStatus`（**无 appserver**） | `?carId=&token=` | 对象（197 字段） | `caches["control"]` | `getControl()` |
| 8 | POST | `/appserver/api/information/pageReceiverInfoByTime` | `?actionType=2&page=&limit=2000&startTime=&endTime=&token=` | 对象（分页 + `content[]`） | `caches["messages"]` | `getMessages()` |
| 9 | POST | `/appserver/api/carcheck/getCheckResult` | `?carId=&isNev=1&token=` | 对象（含 `details[].child[]`） | `caches["check"]` | `getCarCheck()` |
| — | POST | `/api/car/control` | `?pin=&cmd=&carId=&phoneType=&phoneId=&token=[&temperature=]` | 对象（含 `data.TaskId`） | — | `sendControlCommand()`（**源码补全，见 §4.9**） |
| — | POST | `/api/car/getControlInfo` | `?carId=&id=<taskId>&token=` | 对象（`TboxCmd`/`HandleStatus`/`CmdFinishTime`…） | — | `getControlInfo()`（异步指令轮询，见 §4.9） |

**统一外壳**：前 9 个（除 refresh）都是 `{"success":bool,"code":int,"data":…,"msg":string}`；**refresh 是另一套**：`{"code":200,"msg":null,"data":{…}}`，且 `data` 里还嵌一层 `status_code`。`code` 有两种语义：**数字 0 = 成功**，**字符串 `"2"` = 业务失败**（`{"code":"2","data":"{}","msg":"token expired"}`，HTTP 仍是 200）。我们的 `API.unpack()` 必须同时认这两种 ⇒ 本次会话证明「先看 HTTP 再看 code」不够，`code:"2"` 也要能触发刷新。

---

## 3. 报文组 #1 / #2：`auth/cac/refresh`

### 3.1 请求体（1 个字段）

| 字段 | 样例 | 类型 | 含义 | 备注 |
|---|---|---|---|---|
| `refreshToken` | `***` | str | 长期刷新令牌 | **32 位、非 JWT、无过期信息**；响应里原样返回 → **不轮换** |

### 3.2 响应（顶层 9 个键 / 展平后 80 个键）

| 字段 | 样例 | 含义 | 备注 |
|---|---|---|---|
| `code` | `200` | 成功码 | ✅ 与业务接口的 `0` 不同 |
| `msg` | `null` | — | |
| `status_code` | `0` | **第二套状态码**（嵌在 `data` 里） | ✅ `0`=成功 |
| `message` | `null` | — | |
| `access_token` | `***` | 短期令牌 | 32 位；**与 `userInfo.token` 同值** |
| `refresh_token` | `***` | 刷新令牌 | **与请求入参逐字符相同 → 永不轮换** |
| `bind_token` | `null` | 绑定令牌 | ❓ |
| `new_flag` | `"0"` | 字符串 | ❓（推测：新用户标记） |
| `expires_in` | `86400` | 秒 = 24 h | ✅ 但实测会话内很快就 `token expired` → **实际有效期比 86400 短，或 tbox 侧另有判定** |

#### `userInfo.*`（27 个字段）

| 字段 | 样例 | 备注 |
|---|---|---|
| `uid` / `sid` / `cycuid` | `00000000000000000000000000000000` | **三者同值**（统一身份 ID） |
| `cycid` | `"000000000"` | 会员卡号（与 `cardNum` 同值） |
| `code` / `password` / `id` / `sysuid` / `sycid` | 全 `null` | 历史遗留字段 |
| `token` | `W73e1…` | = `access_token` |
| `refreshToken` | `FfrA…` | = `refresh_token` |
| `name` / `lastName` | `某用户` | 真实姓名（**日志里未打码**） |
| `head` / `modulus` / `smsKey` / `resultCode` / `bindToken` | 全 `null` | |
| `tel` | `138****0000` | **未打码** |
| `isExternalOwner` | `0` | ❓ |
| `cardNum` | `"000000000"` | = `cycid` |
| `thirdFlag` / `thirdUid` / `thirdOpenid` / `thirdNickname` / `thirdAvatar` | 全 `null` | 第三方（微信）绑定，未绑定 |

#### `userInfoVo.*`（44 个字段）

| 字段 | 样例 | 备注 |
|---|---|---|
| `userId` | `1573133715280646145` | **雪花 ID（int64）**，与 iov 的 UUID `userId` 不是一套 |
| `userName` / `phonenumber` | `138****0000` | 手机号即账号 |
| `nickName` / `sidName` / `lastName` | `某用户` | 三处同值 |
| `userType` | `"01"` | ❓ |
| `sex` | `"1"` | ⚠️ **与 iov 报文 `gender:"f"` 冲突**（见 §5.4） |
| `avatar` | `https://scrm.changan.com.cn/app-m/statics//2021/11/14/9b99cd46-….png` | 头像 URL |
| `status` | `"0"` | ⚠️ 与 iov 的 `status:"1"` 冲突；`"0"` 通常是「正常」 |
| `remark` / `extendId` | `null` | |
| `sid` / `cycuid` / `uid` | `842f277d…` | 同 `userInfo.uid` |
| `registrationId` | `2c8735c5a6f753229aec45789dcd3a1f4` | **推送设备 ID**（可用于定向推送/换机识别） |
| `pvState` / `cvState` | `null` | ❓ |
| `cycid` / `cardNum` | `"000000000"` | 会员卡号 |
| `globalCommentState` / `globalPostState` | `0` | 评论/发帖总开关 |
| `globalDisableCommentDate` / `globalDisablePostDate` | `null` | |
| `globalCommentReason` / `globalPostReason` | `null` | |
| `adviserId` | `null` | 专属顾问 ID（未分配） |
| `birthday` | `null` | ⚠️ 与 iov 的 `****-**-**` 冲突 → **生日以 iov 为准** |
| `scrmId` | `null` | |
| `point` | `"0"` | 积分（字符串数字） |
| `fiveAuth` | `0` | ❓（推测：五项实名/认证位） |
| `isExperienceOfficer` | `-1` | ❓（`-1` 常表「不适用」） |
| `isExternalOwner` | `0` | |
| `isOperation` | `"0"` | ❓ |
| `createTime` | `2022-09-23 10:14:40` | 注册/建档时间（**iov 的 `registerTime` 是 2021-10-30**，两套体系各自计时） |
| `sysUserLabelVos[]` | `{id:611879, userId:1573133715280646145, labelId:68, version:null, createTime:2022-09-24 20:19:07}` | 用户标签（labelId=68）→ 可做"身份标签"展示 |
| `medals` / `pinfo` / `cinfo` / `xverifyDate` | 全 `null` | 勋章 / 个人信息 / 车辆信息 / 核验日期 |

---

## 4. 逐报文逐字段

### 4.1 `user/getUserInfoByToken` → `data`（48 个字段）

| 字段 | 样例 | 含义 |
|---|---|---|
| `cycid` / `sycid` | `null` | 会员号（iov 侧为空） |
| `userId` | `00000000-0000-0000-0000-000000000000` | **iov 侧用户 UUID**（消息里的 `trackUserId` 就是它） |
| `uuid` | `null` | |
| `openId` | `00000000000000000000000000000000` | **= scrm 的 uid**，两套身份的唯一桥 |
| `tenantId` | `""` | 空串 |
| `userName` | `""` | 空串（用户名没设） |
| `userNickname` | `138****0000` | **服务端已打码的手机昵称** |
| `userFullname` | `某用户` | 实名 |
| `mobile` | `138****0000` | 手机号（明文） |
| `contactsName` / `contactsMobile` | `null` | 紧急联系人（未填） |
| `countryId` / `provinceId` / `cityId` / `distId` | `null` | 行政区 ID |
| `country` / `province` / `city` / `dist` / `community` | `""` | 地址（全空） |
| `status` | `"1"` | 账户状态（⚠️ 与 scrm `"0"` 冲突） |
| `gender` | `"f"` | **性别 `f`/`m`**（⚠️ 与 scrm `sex:"1"` 冲突） |
| `password` | `"******"` | 服务端打码 |
| `birthday` | `****-**-**` | 生日（✓ 唯一有值的一处） |
| `email` / `address` / `telephone` | `""` | 全空 |
| `idcardType` | `IDCARD` | 证件类型 |
| `idcard` | `***` | **服务端已打码**的身份证 |
| `faceImg` | `""` | |
| `registerTime` | `2021-10-30 14:21:03.0` | ⚠️ **带 `.0` 尾巴** → `DateFormatter("yyyy-MM-dd")` 解析失败 |
| `activeTime` | `null` | |
| `source` | `outsideSso` | 注册来源 |
| `lastLoginTime` | `2024-06-05 20:09:57.0` | ⚠️ 带 `.0`；**2024 年之后再没登录过**（但 tbox 在 07:18:58 登录过 → 这是"App 登录"，不是"车机登录"） |
| `deleted` / `locked` | `0` | |
| `createAt` / `token` / `brandName` / `carId` / `imUserId` / `imPassWord` / `plateNumber` / `cycuid` / `sycuid` / `authenticationType` | `null` | 未使用 |
| `realnameAuthed` | `true` | ✅ 已实名（可用来决定是否显示实名引导） |

### 4.2 `car/getMyCars` → `data[0]`（67 个字段）

| 字段 | 样例 | 含义 / 我们的用法 |
|---|---|---|
| `carId` | `00000000-0000-0000-0000-000000000000` | **一切车端请求的主键** ✅ |
| `vin` | `LS6A3E039MB******` | 车架号 ✅（可显示；**日志未打码**） |
| `tenantId` | `CA_EV_TENANT` | 新能源租户 |
| `userId` | `39717783-…` | 车主 |
| `carName` | `电车` | **用户自定义车名** |
| `carNameForCar` | `电车` | 与 `carName` 同值（另一个字段） |
| `carType` | `""` | 空 |
| `oilType` | `null` | 燃油车字段（电车为空） |
| `brandId` / `brandCode` / `brandName` | `""` | 全空 → **不能用来显示品牌** |
| `seriesId` / `seriesName` | `""` | 空；但 **`seriesCode: A301-E-6`** 有值 |
| `modelId` / `modelName` | `null` / `""` | 空；但 **`modelCode: SC7001ABDBEV`** 有值 |
| `confId` / `confName` | `null` / `Level2` | **配置名 Level2 有值** |
| `confCode` | `SC7001ABDBEV.CNH2004` | 与 `carConfCode`（control）一致 ✅ |
| `img` | `""` | 无车图 |
| `engineNo` | `ENG******` | **电机号**（电车没有发动机号） |
| `color` | `null` | 颜色缺失 → 车辆档案页应显示"未登记" |
| `purchasedDate` / `factoryDate` | `null` | 购车/出厂日期缺失 |
| `oemCompanyId` | `null` | |
| `capacity` | `null` | 电池容量缺失 |
| `plateNumber` | `京A*****` | 车牌 ✅ |
| `pin` | `"exist"` | **控车码已设置**（`exist`/`none`）→ 决定操作条是"验证"还是"首次设置" |
| `insuranceEndDate` | `"0000-00-00"` | ⚠️ **哨兵值**，不是日期 |
| `insuranceCompany` | `中华联合保险` | ✅ **有值！** 到期日缺失但公司/电话在 → 应显示"保险：中华联合保险 95585（到期未登记）" |
| `insurancePhone` | `95585` | 保险公司电话 |
| `registerTime` | `2021-10-21 03:00:07` | 上牌/登记 |
| `activeTime` | `"0000-00-00\n\t\t00:00:00"` | ⚠️ **哨兵值 + 换行 + 制表符** |
| `lastCheckTime` | `"0000-00-00"` | ⚠️ 哨兵值 |
| `productTime` | `2021-10-19 16:47:46` | 生产时间（比登记早 2 天） |
| `isCaCar` | `true` | ❓（长安自营车） |
| `dealerId` / `materialId` | `null` | |
| `tserviceStatus` | `"active"` | **车联网服务状态：生效中** ✅ |
| `tserviceStarttime` | `null` | ⚠️ 有结束时间没开始时间 |
| `tserviceEndtime` | `2041-10-31 18:01:18` | **20 年后 → 等于"永久"**；UI 应显示"长期有效"而不是具体日期 |
| `lastOnlineTime` | `null` | |
| `carAuthCode` / `certifiNo` | `null` | |
| `realnameAuthStatus` | `AUTHED` | **已实名认证** ✅ |
| `realnameAuthPassTime` | `null` | |
| `source` | `"schedule"` | ❓ |
| `deleted` | `null` | |
| `maintainSpaceMileage` | `20000.0` | **保养间隔 2 万 km** ✅（我们硬编码 10000 🚫） |
| `lastMaintainMileage` | `20100.0` | **上次保养时的里程** ✅ |
| `totalOdometer` | `null` | ⚠️ **此接口里为空**；真实里程在 control（53766.4） |
| `powerPrice` | `null` | 电价（未配置 → 充电费用只能用户手填） |
| `issuedate` | `null` | |
| `isNev` | `1` | 新能源 |
| `systemCode` | `null` | |
| `isPrivacyDrvingHistory` | `1` | **隐私行车历史开关**（=1：行车轨迹不外传 → 解释了为什么没有轨迹接口） |
| `createAt` / `updateAt` / `createBy` / `updateBy` / `devices` / `imgHandlerId` / `carUniqueCode` | `null` | |
| `currentDeviceType` | `"tbox"` | 当前车机类型（T-BOX） |
| `funCode` | （JSON 字符串，见下） | **能力位图** |
| `bindedJD` | `false` | ❓（京东绑定） |

#### `funCode` 展开：7 组 / 43 个开关（**这辆车的真实能力**）

| 组 | 开（=1） | 关（=0） |
|---|---|---|
| `toolkit/newService` | `openFW`、`carManual`、`noUshare` | `noMaintenance`、`noCarManual`、`NoopenFW`、`noCartest`、`openPJ` |
| `control/remoteBaseControl`（燃油/通用遥控） | `statusBtn`、`airGradeBtnNew`、`doorStatusRC`、`airBtn`、`Statelock`、`Statetrunk`、`StateFrontDoor`、`lightStatusRC`、`humidity`、`lightBtn`、`doorBtn`、`trunkStatusRC`、`Statelight` | `EVairGradeBtn`、`冷/热档位调节空调(低、中、高)`、`zjcsStatusRC` |
| `openNative` | `isFence` | — |
| `main/index` | `#26`、`#18`、`#19`、`#0` | `#20` |
| `home/newIndex` | `battery`、`openWF`、`homepagePushChargingCard`、`openFW`、`A301BasicChargeInfo`、`operManual`、`bookChargeA301`、`chargeStateA301`、`mapTitle`、`openBY` | `A158BasicChargeInfo`、`A158ylyCharge`、`bookChargeA158-3`、`Handbook`、`chargeStateA158-3`、`openPJ`、`A158PortableChargerInfo` |
| `changeS203EV` | `chargeDischargeInfo`、`.SOCLimit`、`chargeBtn` | `PeriodicCharge` |
| `control/remoteBaseControl_XNY`（**新能源专用遥控**） | `statusBtn`、`doorStatusRC`、`Statetrunk`、`Statelock`、`bbAirBtn`、`lightStatusRC`、`StateFrontDoor`、`lightBtn`、`doorBtn`、`Statelight` | `airGradeBtnNew`、`airBtn`、`StateWindow`、`zjcsStatusRC`、`trunkStatusRC`、`EVairGradeBtnOld` |

**可直接落地的三条**：
- `#StateWindow: 0` → 本车**不上报车窗状态**，UI 不应显示「车窗 已关/开启」；
- `#PeriodicCharge: 0` → **不支持定时充电**，充电页不要放"预约充电"入口；
- `#airGradeBtnNew / #airBtn`（XNY 组为 0）→ 空调走 `#bbAirBtn`，温度档位控件该换成**温度+风量**而非"档位"。
- `toolkit/newService.#noMaintenance: 0` + `#openFW: 1` → 保养/服务入口是开的，可以做。

### 4.3 `charge/info` → `data`（12 个字段）

| 字段 | 样例 | 含义 | 备注 |
|---|---|---|---|
| `chrgStatus` | `"3"` | 充电状态（字符串） | ✅ **参考实现的映射**：`"1"`=充电中、`"2"`=即将完成、`"3"`=充电完成、**其他=未充电**（`MainForm.cs:707`）；⚠️ 但车主确认当时车在行驶、并未充电 → **它是「上次充电」的残留**，不可当实时状态（见下方警告） |
| `remainPower` | `66.0` | SOC % | ✅ 与 control `soc:66` / `remainPower:66.0` 一致 |
| `chargeReservationStatus` | `0` | 预约充电状态 | ❓（且本车不支持定时充电） |
| `chargeStarttime` | `2024-05-19 23:34:00` | **上次**充电开始 | ⚠️ **一年多前** |
| `chargeStoptime` | `2024-05-20 07:59:00` | **上次**充电结束 | ⚠️ 与 control 同字段同值 |
| `remainedPowerMile` | `204` | 剩余续航 km | ✅ |
| `powerLineStatus` | `0` | 电源线状态 | ✅ **参考实现的映射**：`0` = 正常、非 0 = 异常（`MainForm.cs:713`）—— 不是"是否插枪" |
| `batteryChargeStatus` | `0` | 电池充电状态 | ❓ 与 `chrgStatus` 并存，语义重叠 |
| `chargDeltMins` | `286` | 上次充电时长（分钟 = 4 h 46 m） | ✅ 与 23:34→07:59 的 **505 分钟不符** ⚠️ |
| `reservationBatteryHeatingStatus` | `0` | 预约电池加热 | ❓ |
| `batteryHeatingStatus` | `0` | 电池加热中 | ✅ |
| `reservationUseVehicleTime` | `null` | 预约用车时间 | ❓ |

> **已由车主确认（§0.1 #1）**：抓包时车**刚跑完一段路停下、并未在充电** → `chrgStatus:"3"` 是「不在充电」的静止态，下面三个时间戳字段是**上次充电（2024-05-20）的历史记录**。
> **界面须做到**：① 用 `chrgStatus` 判「是否在充」（**3 = 未充电已核实**；1/2 = 在充待下次真充电时抓包确认），3 显示「未充电」；② `chargeStarttime`/`Stoptime`/`chargDeltMins` 一律加前缀「上次充电：」；③ 不要因为看到 `"3"` 就写「充电完成」。
> **算术不符**：`chargDeltMins:286` vs `chargeStarttime→chargeStoptime = 505 min`。二者必有一个不是"本次"的量。

### 4.4 `cardata/getCarLocation` → `data`（13 个字段，出现 11 次，**逐字节相同**）

| 字段 | 样例 | 含义 |
|---|---|---|
| `carId` | `d2007f1c-…` | |
| `lng` | `00.000000` | 经度（**GCJ-02**，`mapType=GCJ02` 已声明；可直接投 Apple 地图中国区） |
| `lat` | `00.000000` | 纬度 |
| `speed` | `0.0` | 车速 km/h（与 control `speed`/`vehicleSpeed` 一致） |
| `heading` | `550.4` | 航向角 ⚠️ **>360°**，需 `norm360()` → 190.4°（我们已有该函数 ✅） |
| `accel` | `null` | 加速度（无） |
| `addrDesc` | `某地` | **服务端逆地理地址** ✅（可省一次地理编码） |
| `gpsTime` | `2026-09-22 07:19:28` | **车端定位时刻**（判断数据龄期的唯一依据） |
| `status` | `2` | ✅ **`2` = 熄火**（参考实现：`data.Status == 2 ? "熄火" : "行驶"`，`MainForm.cs:693`）→ 与 control 的 `status:"2"` 是同一个量 |
| `locationImgurl` | `null` | 周边图像（无） |
| `thumbnailLocationImgUrl` | `null` | 缩略图（无） |
| `locationImgActionTime` | `null` | 图像动作时间（无） |
| `validGps` | `true` | GPS 有效 |

### 4.5 `car/pm/getCarPm25ByCarId` → `data`（顶层 6 / 展开 19 个字段）

| 字段 | 样例 | 含义 | 备注 |
|---|---|---|---|
| `pm25InnnerCarValue` | `"-1"` | 车内 PM2.5 | ⚠️ **字符串，`-1` = 无数据哨兵**（我们已按 `-1 → "--"` 处理 ✅） |
| `pm25OuterCarValue` | `"20.0"` | 车外 PM2.5 | 字符串数字 |
| `vehicleTemperature` | `0` | 车内温度 | ⚠️ **0 = 无数据**（我们已按 0 → "--" 处理 ✅）；真实车内温度在 control 的 `air.temperature = "26"` |
| `environmentalTemperature` | `0` | 车外温度 | ⚠️ 同样为 0（无数据） |
| `updateTime` | `2026-09-22 07:19:28.967` | 数据时刻 | 与 control `lastUpdatedTime` 同值 |
| `carLocationResp` | （13 字段，见下） | **第二份定位** | ⚠️ 与 location 接口差 589 m，且无 `gpsTime` |

#### `carLocationResp`（13 个字段）

| 字段 | 样例 | 备注 |
|---|---|---|
| `carId` / `speed` / `heading` / `accel` / `gpsTime` / `validGps` | 全 `null` | **这个子对象里除坐标和地址外几乎全空** |
| `lng` / `lat` | `00.000000` / `00.000000` | ⚠️ **与 location 接口和 control 一致（control 也是这两个值）** |
| `addrDesc` | `某地` | 更精细的 POI 级地址 |
| `status` | `0` | 与 location 的 `status:2` 不同 |
| `locationImgurl` / `thumbnailLocationImgUrl` / `locationImgActionTime` | `null` | |

> **两票对一票**：`control` + `pm25` 一致（00.000000 / 00.000000），`location` 单独（114.232302 / 30.522255），相距 **589 m**。且 `location` 把车放在医院主体、`pm25` 放在院内某酒店东北 96 m。**建议**：地图用 `location`（它有 `gpsTime`、`speed`、`heading`、`validGps` 完整且带逆地理），但**必须**在文档/代码里写明「另一接口给出的坐标差约 600 m」，否则下次有人换源会以为是两个地点。

### 4.6 `api/car/getControlStatus` → `data`（顶层 **177** 键 / 展平 **201** 键）

> 这是全App 的体检数据源。下表**逐字段**（含样例），并按语义分组。`❓` = 枚举含义未核实。

#### A. 时间与版本（8）

| 字段 | 样例 | 含义 |
|---|---|---|
| `terminalTime` | `2026-09-22 07:19:28` | 车机时钟 |
| `deviceTime` | `2026-09-22 07:19:28` | 车机上报时刻 |
| `gpsTime` | `2026-09-22 07:19:28` | 定位时刻 |
| `serverTime` | `2026-09-22 07:19:28.967` | 服务端时刻（**带毫秒**） |
| `lastUpdatedTime` | `2026-09-22 07:19:28.967` | **数据新鲜度的权威字段** ✅ → 应作为"最后上报 xx 分钟前"的依据 |
| `recordTime` | `2025-04-29 17:31:14.270` | ⚠️ **一年半前**，不是"最后记录时间"，语义 ❓ |
| `ignitionTime` | `2026-09-22 06:45:18` | **最近一次点火**（与消息流 `IGNITION` 事件逐秒吻合 ✅ 交叉验证通过） |
| `protocolVer` | `200` | 协议版本（❓ 2.0.0？） |

#### B. 状态与档位（8）

| 字段 | 样例 | 含义 |
|---|---|---|
| `status` | `"2"` | ✅ **`"2"` = 熄火**（同 location `status:2`，参考实现的映射；字符串/数字两种写法） |
| `carStatus` | `2` | ❓ 数字状态（与上面并存） |
| `carMode` | `1` | ❓ |
| `shiftPosition` | `0` | 档位（0 = P，我们已映射 `0→P/驻车` ✅） |
| `shiftPositionStatus` | `0` | ❓ 与 `shiftPosition` 并存 |
| `vehicleSpeed` / `speed` | `0.0` / `0.0` | 车速（**同一概念两个字段**） |
| `conditionidle` | `0` | ❓（怠速条件？） |
| `powerStatusFeedBack` | `0` | ❓ 电源状态回馈 |
| `fireStatus` | `"2"` | **点熄火状态**；我们映射 `1=启动 2=熄火` ✅（我们的读取走 `ciString` → 大小写不敏感，**能用**） |

#### C. 门 / 窗 / 锁 / 舱盖（24）

| 字段 | 样例 | 含义 |
|---|---|---|
| `door` | `"0"` | **字符串**总门状态 |
| `driverDoor` / `passengerDoor` / `leftFrontDoor` / `rightFrontDoor` / `leftRearDoor` / `rightRearDoor` | 全 `0` | 六门各自状态 |
| `leftFrontDoorStatus` / `rightFrontDoorStatus` / `leftRearDoorStatus` / `rightRearDoorStatus` | 全 `0` | **同义第二套**（status 后缀） |
| `driverDoorLock` / `passengerDoorLock` / `leftFrontDoorLock` / `rightFrontDoorLock` / `leftRearDoorLock` / `rightRearDoorLock` | 全 `0` | 锁状态（**0 = 已锁**） |
| `hood` / `trunk` / `sunroof` | 全 `0` | 引擎盖 / 后备箱 / 天窗 |
| `window` | `"0"` | **字符串**总车窗状态 |
| `leftFrontDoorrWindow` / `rightFrontDoorrWindow` | `0` | ⚠️ **服务端拼写错误 `Doorr`**（少一个 r 就永远读不到） |
| `leftRearDoorrWindow` | `0` | ⚠️ 同上拼写错误 |
| `leftAnteriorWindowDegree` / `rightAnteriorWindowDegree` / `leftRearWindowDegree` / `rightRearWindowDegree` | 全 `0.0` | 四窗**开度**（度） |
| `leftRearWindow` / `rightRearWindow` | `0` | 后窗状态 |

#### D. 车灯（10）

| 字段 | 样例 | 含义 |
|---|---|---|
| `light` | `"0"` | **字符串**总灯状态 |
| `lowBeam` / `highBeam` | `0` / `0` | 近光 / 远光 |
| `positionLight` / `positionLamp` | `0` / `0` | 示宽灯（**两个字段名**） |
| `frontFogLight` / `rearFogLight` | `0` / `0` | 雾灯（新命名） |
| `frontFoglamp` / `rearFoglamp` | `0` / `0` | 雾灯（**旧命名，同义重复**） |
| `leftTurnSignal` / `rightTurnSignal` | `0` / `0` | 转向灯（新命名） |
| `turnLndicator` / `turnLndicatorLeft` / `turnLndicatorRight` | `0` / `0` / `0` | 转向灯（**旧命名 + 拼写错误 `Lndicator`**） |
| `batteryChargeLightStatus` | `0` | 充电指示灯 |

> **同一件事被服务端给了 2–4 个字段**：雾灯 ×2 组、转向灯 ×2 组、示宽灯 ×2、门状态 ×2、车窗 ×3。**代码必须只认一组**（建议认新命名），否则会出现"左边说亮右边说灭"。

#### E. 座椅 / 空调 / 空气（10）

| 字段 | 样例 | 含义 |
|---|---|---|
| `air.temperature` | `"26"` | **空调设定温度（字符串！）** — 车主确认（§0.1 #2）当时**空调关着**，26℃ 是**上次设定值**；真实的"车外温度"字段反而是 0（无数据） |
| `air.status` | `"0"` | 空调开关（字符串；**`0`=关已核实**，1=开为推论，§0.1 #2） |
| `air.wind` | `"3"` | 风量档（字符串 `"3"`，不是数字） |
| `driverSeatHeatStatus` / `passengerSeatHeatStatus` | `0` / `0` | 座椅加热 |
| `driverSeatAirStatus` / `passengerSeatAirStatus` | `0` / `0` | 座椅通风 |
| `airPurifierStatus` | `0` | 空气净化器 |
| `pm25` | `0` | 车内 PM2.5（**=0 无数据**，与 pm25 接口的 `-1` 哨兵不同！） |

> ⚠️ `air` 是**嵌套对象**，键名全小写。我们的 `nestedObject(control, "Air")` **大小写错 → 永远 nil** → 空调永远是"暂无数据"（🚫 §6）。

#### F. 胎压 / 胎温 / 车身姿态（12）

| 字段 | 样例 | 含义 |
|---|---|---|
| `lfTyrePressure` / `rfTyrePressure` / `lrTyrePressure` / `rrTyrePressure` | `227 / 227 / 226 / 230` | 胎压 **kPa**（左前/右前/左后/右后）— 注意：**不是 bar**，227 kPa ≈ 2.27 bar ✅ 合理 |
| `lfPressureWarning` / `rfPressureWarning` / `lrPressureWarning` / `rrPressureWarning` | 全 `0` | 四轮气压告警（0 = 正常） |
| `leftFrontTireTemperature` / `rightFrontTireTemperature` / `leftRearTireTemperature` / `rightRearTireTemperature` | `68 / 67 / 69 / 67` | 胎温 ℃ ✅ **可信**（车主已确认当日刚长时间行驶过，§0.1 #4）；停车 11 分钟后仍偏高属正常余温。`tireTemperatureStatus:0`（正常）与之一致 ✅ 照常显示 + 注「行驶后偏高」 |
| `tireTemperatureStatus` | `0` | 胎温状态 |
| `alti` | `26.0` | 海拔米（武汉 ~26 m ✅ 合理） |
| `satNum` | `5` | 可见卫星数 |

#### G. 电池 / 充电（22）

| 字段 | 样例 | 含义 |
|---|---|---|
| `soc` / `remainPower` / `currentElectricity` | `66` / `66.0` / `66` | **三个字段同一个 SOC**（重载字段） |
| `remainedPowerMile` | `204` | 剩余续航 km（**与 charge 接口一致** ✅） |
| `totalVoltage` | `335.8` | 总电压 V（≈ 88 节 × 3.8156 = 335.85 ✅ 自洽） |
| `totalCurrent` | `0.0` | 总电流 A（静置 0 ✅） |
| `maxVoltageBattery` / `minVoltageBattery` | `3.823` / `3.8000000000000003` | 最高/最低单体电压（**压差 23 mV**）— 注意浮点残留值 |
| `maxVoltageBatteryNum` / `minVoltageBatteryNum` | `3` / `56` | 最高/最低单体**序号**（1-based）→ 可做"第 56 号电芯偏低" |
| `driveMotorNum` / `driveMotorData[]` | 见下 | 电机数量与详表 |
| `minTemperatureProbe` / `maxTemperatureProbe` | `1` / `3` | 最低/最高温探针序号 |
| `minTemperatureValue` / `maxTemperatureValue` | `23` / `24` | 电池温度区间 |
| `minTemperatureSubSystemNum` / `maxTemperatureSubSystemNum` | `1` / `1` | 子系统号（单包） |
| `minVoltageBatterySubSystemNum` / `maxVoltageBatterySubSystemNum` | `1` / `1` | |
| `insulateResistance` | `20000` | **绝缘电阻 Ω**（20 kΩ，正常）|
| `batteryConsistencyDifferenceAlarm` | `0` | 压差告警（23 mV → 0 ✅ 自洽） |
| `singleBatteryOverVoltageAlarm` / `singleBatteryUnderVoltageAlarm` | `0` / `0` | 单体过压/欠压 |
| `socHighAlarm` / `socLowAlarm` / `socJumpAlarm` | `0` / `0` / `0` | SOC 告警 |
| `batteryAlarm` / `batteryPowerSystemStatus` / `batteryHeatingStatus` / `batteryChargeStatus` / `batteryHeatingStatus` | 全 `0` | 电池总告警 / 系统状态 / 加热 / 充电 |
| `chargeStatus` | `3` | **数字**版充电状态（charge 接口是字符串 `"3"`）⚠️ 同一概念两种类型 |
| `chargeReservationStatus` / `powerLineStatus` | `0` / `0` | 与 charge 接口重名同值 |
| `chargeStarttime` / `chargeStoptime` / `chargDeltMins` | `2024-05-19 23:34:00` / `2024-05-20 07:59:00` / `286` | ⚠️ **control 里也带这三个"上次充电"字段**，值同 charge 接口 |
| `nevChargeSystemVoltageDtoList[]` | 见下（7 字段） | **88 节电芯电压明细** |
| `nevChargeSystemTemperatureDtoList[]` | 见下（3 字段） | **26 个温度探针** |
| `dcStatus` / `dcdcStatusAlarm` / `dcdcTemperatureAlarm` | `1` / `0` / `0` | DC-DC 状态/告警 |
| `vehiclePureDeviceTypeOvercharge` | `0` | 过充 |
| `rechargeableStorageDevicesFaultCount` | `0` | 储能装置故障数 |
| `rechargeableStorageDevicesFaultCodes` | `""` | 故障码串（空） |
| `rechargeableStorageDeviceMismatchAlarm` | `0` | 不匹配告警 |
| `vehicleStorageDeviceUndervoltageAlarm` / `vehicleStorageDeviceOvervoltageAlarm` | `0` / `0` | 储能欠压/过压 |
| `highVoltageInterlockStateAlarm` | `0` | 高压互锁 |
| `insulationAlarm` | `0` | 绝缘告警 |

##### `nevChargeSystemVoltageDtoList[0]`（7 字段）——**我们零引用，但可以画出真电池图** 🚫

| 字段 | 样例 | 含义 |
|---|---|---|
| `currentBatteryStartNum` | `1` | 本节流起始电芯号 |
| `batteryVoltage` | `list[88]`：`3.821, 3.820, 3.823, …, 3.800, …, 3.820` | **88 节单体电压**（min 3.800 / max 3.823 / 均值 3.8164 / **压差 23 mV**） |
| `chargeSystemVoltage` | `335.80002` | 系统电压（与 `totalVoltage:335.8` ✅） |
| `currentBatteryCount` / `batteryCount` | `88` / `88` | 已上报/总电芯数 |
| `childSystemNum` | `1` | 子系统数（单包，无级联） |
| `chargeSystemCurrent` | `0.2` | 系统电流 A（浮点，静置 0.2 是采样噪声） |

##### `nevChargeSystemTemperatureDtoList[0]`（3 字段）

| 字段 | 样例 | 含义 |
|---|---|---|
| `probeTemperatures` | `list[26]`：`23,23,24,24,…,24` | **26 个探针**，23–24℃ |
| `chargeTemperatureProbeNum` | `26` | 探针总数 |
| `childSystemNum` | `1` | 子系统数 |

##### `driveMotorData[0]`（11 字段）

| 字段 | 样例 | 含义 |
|---|---|---|
| `controllerInputVoltage` | `46.0` | 控制器输入电压 V ⚠️（与总压 335.8 V 不同量级 → 疑为低压系统或故障；配合 `motorSystemStatus:0` 判为正常） |
| `controllerTemperature` | `31` | 控制器温度 ℃ |
| `temperature` | `37` | 电机温度 ℃ |
| `revolutionSpeed` | `0` | 转速 rpm（静止） |
| `num` | `1` | 电机序号 |
| `controllerDcBusCurrent` | `0.0` | 母线电流 |
| `torque` | `0.0` | 扭矩 |
| `state` | `4` | ❓ 电机状态 |
| `type` | `0` | ❓ 电机类型 |
| `length` | `0` | ❓ |
| `MAX_BYTE_VALUE` | `127` | **协议常量（byte 上限），不是数据** → UI/导出都不应显示 |

#### H. 告警与故障统计（14）

| 字段 | 样例 | 含义 |
|---|---|---|
| `maxAlarmLevel` | `0` | 最高告警等级（0 = 无告警）→ **总览页"是否有问题"的唯一权威** |
| `engineFaultCount` / `engineFaultCodes` | `0` / `""` | 发动机故障（电车恒 0） |
| `driveMotorFaultCount` / `driveMotorFaultCodes` | `0` / `""` | 电机故障 |
| `otherFaultCount` / `otherFaultCodes` | `0` / `""` | 其它故障 |
| `keyAlarm` / `keyLowPower` | `0` / `0` | 钥匙告警 / 钥匙低电 |
| `temperatureDifferenceAlarm` | `0` | 温差告警 |
| `driveMotorTemperatureAlarm` / `driveMotorControllerTemperatureAlarm` | `0` / `0` | 电机/控制器过温 |
| `motorSystemStatus` | `0` | 电机系统（0 正常） |
| `airbagSystemStatus` | `0` | 气囊系统 |
| `brakeSystemAlarm` | `0` | 制动系统 |
| `engineFuelCutOffFlag` | `0` | 断油标志（电车无意义） |
| `isInValidGps` / `isValidGps` / `validGps` | `0` / `true` / `true` | **三份同一个含义的字段，且都不是 `null`** |

#### I. 定位 / 环境 / 其它（12）

| 字段 | 样例 | 含义 |
|---|---|---|
| `lng` / `lat` | `00.000000` / `00.000000` | 坐标（⚠️ 与 `location` 接口差 589 m） |
| `heading` | `550.4` | 航向（>360°，需 `norm360`） |
| `vin` / `seriesCode` / `carConfCode` | `LS6A3E039MB******` / `A301-E-6` / `SC7001ABDBEV.CNH2004` | 车辆标识（与 car 接口 ✅） |
| `tenantId` / `carId` / `userId` | 同其它接口 | |
| `tuid` | `00000000000000000000000000000000` | **车机 TUID**（消息 `jumpParam.logId` 前缀就是它） |
| `sidAndMid` | `"5,100"` | ❓（卫星/模块 ID？） |
| `deviceType` | `"tbox"` | 车机类型 |
| `requestId` | `2026092207192858` | 服务端请求号（= 时间戳 + 序列） |
| `containerName` | `carbond-tu-api-5cbf6f4f7-pp7qx` | ⚠️ **K8s 容器名 → 泄漏内网架构**，UI/导出必须过滤 |
| `lastLoginTime` | `2026-09-22 07:18:58` | **车机登录平台时间**（≠ user 接口的 App 登录时间 2024-06-05） |
| `isValidGps` / `isHistoryPoi` / `forwardFlag` / `accPedal` / `brakePedal` / `cutchPedal`（拼写错误：clutch）/ `gearDriveForce` | 全 `0` | ⚠️ `cutchPedal` 是服务端拼写错误 |
| `shortTermFuelTrim` | `-100` | 燃油修正（纯电车无意义，**`-100` 是"不适用"哨兵**） |
| `hood` / `trunk` / `sunroof` | `0` | （已列于 C 组） |

### 4.7 `information/pageReceiverInfoByTime`（消息流）

#### 分页外壳（本次观测）

| 字段 | 值 | 备注 |
|---|---|---|
| `number` | `0` | 当前页（0-based） |
| `numberOfElements` | `56` | 本页元素数（**7 天窗口 56 条事件**） |
| `size` | `2000` | 我们请求的 `limit` |
| `totalPages` | `3` | ❓ 与 `size:2000`、`numberOfElements:56` 三者不自洽（`last:false` 也说还有下一页）→ **不要用它做"是否还有更多"的判断**，应看 `last` |
| `last` | `false` | ❓ 同上矛盾 |
| `sort` | `null` | |
| `content[]` | 数组（见下） | |

> 我们请求 `page=`（空）：服务端用默认页（第 0 页）。`limit=2000` + 7 天窗口一次拿全（实测 56 条）。**但如果某天事件 > 2000，`page=`/`last` 都没被我们使用 → 会静默丢数据**。

#### `content[i]`（24 个字段/条）

| 字段 | 样例 | 含义 |
|---|---|---|
| `readStatus` | `0` | **未读**（本次 5 条全是 `0`）⚠️ 与 `new` 字段矛盾（见 §5.5） |
| `new` | `false` | ⚠️ 与 `readStatus:0` 矛盾 |
| `infoTypeId` | `FLAMEOUT` / `IGNITION` | **事件类型** ✅（可枚举） |
| `infoTypeName` | `车辆熄火` / `车辆点火` | 中文名（服务端给的）✅ |
| `infoTypeFullPath` | `APP-CONTROL-FLAMEOUT` | 分类路径 → 可做图标/分组 |
| `infoTypeFullName` | `手机app/点熄火/车辆熄火` | 三级路径中文 |
| `infoTypeImg` | `http://incallcdn.changan.com.cn/static/cdnshamdown/prod/85ec4ac4….png` | 事件图标 URL |
| `infoStatus` | `null` | |
| `title` | `熄火信息` | |
| `content` / `summary` | `您的爱车"京A*****"于07:08:25，在某地熄火。…` | **两字段内容相同**（且含车牌原文） |
| `createdAt` | `2026-09-22 07:08:25` | 事件时间（**与 `jumpParam.gpsTime` 秒级一致**） |
| `updatedAt` | `2026-09-22 07:08:26` | 写入时间（晚 1 s） |
| `senderId` / `senderName` | `admin` / `系统管理员` | 系统发出 |
| `createdBy` / `updatedBy` | `admin` / `null` | |
| `trackUserId` | `39717783-…` | = iov `userId`（**不是** openId） |
| `realReceiverId` | `d2007f1c-…`（carId） | 接收方 = 车 → **我们已用它映射车牌** ✅ |
| `id` | `39717783-…|2|3209967893016` | 复合主键（`userId|actionType|序号`） |
| `stubId` | `1:e0b5c3e9-4688-4d4c-bdbc-2f4c9cd996e7:20260922070826.984:9174` | **天然幂等键**（我们零引用 🚫）→ 去重/已读同步都可以用它 |
| `delFlag` | `"0"` | 删除标记（字符串） |
| `actionType` | `2` | ❓（我们的请求也带 `actionType=2`） |
| `fromSystem` | `event-message` | 来源系统 |
| `jumpParam` | （JSON 字符串，见下） | **事件的地理与毫秒时间** |
| `titleImg` | `null` | |

#### `jumpParam` 解析后（16 个字段）——**行程的骨架就在这里** ✅

| 字段 | 样例 | 含义 |
|---|---|---|
| `action` | `INNER_JUMP` | 跳转方式 |
| `uri` | `toolkit/messageAmap.html` | 参考实现的页内路由（我们不需要） |
| `uriParams.logId` | `00000000000000000000000000000000:20260922070826929:6787` | 事件日志号（前缀 = `tuid`） |
| `uriParams.carId` | `d2007f1c-…` | |
| `uriParams.carNum` | `京A*****` | 车牌 |
| `uriParams.deviceTime` | `1790032105926` | **毫秒 epoch** → 校验：+UTC+8 = `2026-09-22 07:08:25.926` ✅ 与同条 `gpsTime` 同刻 |
| `uriParams.serverTime` | `1790032106926` | 毫秒 epoch，比 deviceTime 晚 **1 秒** |
| `uriParams.eventActionTime` | `1790032105000` | **事件发生时刻**（秒级 07:08:25）→ 三份时间戳可互相校验 |
| `uriParams.gpsTime` | `2026-09-22 07:08:25` | |
| `uriParams.lat` / `lng` | `00.000000` / `00.000000` | **事件发生地坐标（= location 接口那份！）** |
| `uriParams.addrName` | `某地` | 事件地址 |
| `uriParams.coordType` | `GCJ02` | 坐标系 |
| `uriParams.validGps` | `true` | |
| `uriParams.flameoutReason` | `0` | 熄火原因（**仅 FLAMEOUT 事件有**）❓ |
| `uriParams.ignitionReason` | `0` | 点火原因（**仅 IGNITION 事件有**）❓ |
| `uriParams.tuid` | `00000000000000000000000000000000` | 车机 TUID |

#### 本次可见的 5 条事件（日志被截断，`content` 实际 56 条）

| createdAt | 类型 | 地点 | 与前后配对 |
|---|---|---|---|
| 2026-09-22 07:08:25 | FLAMEOUT | 某地 | ← 配对 06:45:18 点火（**23 min 07 s**） |
| 2026-09-22 06:45:18 | IGNITION | 某地 | |
| 2026-09-21 17:47:02 | IGNITION | 某地 | ⚠️ **无对应熄火** |
| 2026-09-21 17:43:01 | FLAMEOUT | 沌口安可酒店 | ← 配对 17:37:17 点火（**5 min 44 s**） |
| 2026-09-21 17:37:17 | IGNITION | （日志截断未给地址） | |

**结论（回答"行程怎么算"）**：
- 事件对配对 = **能用**：`IGNITION` → `FLAMEOUT` 之间就是一次行程；地点、时长、起终点坐标全有。
- 但**事件流本身不完整**（可见 5 条里 3 点火 / 2 熄火，有 1 次点火没有配对熄火；且 7 天窗口共 56 条，日志只留了 5 条）→ **纯事件配对会漏行程**。
- 正确做法：**事件做骨架 + `totalOdometer` 差做校验**（里程键已确认是 `totalOdometer`；本次会话里程恒为 53766.4，说明车没动，可作反例校验）。
- `insertionTime` 上没有"行程"接口 → `tripHistory` 在 App 侧只能这样合成。

### 4.8 `carcheck/getCheckResult` → `data`（顶层 13 / 展平 47）

| 字段 | 样例 | 含义 |
|---|---|---|
| `checkHistoryId` | `2102215430740377600` | 体检记录 ID（雪花） |
| `userId` / `carId` | 同上 | |
| `status` | `normal` | **总状态**（`normal`） |
| `score` | `100` | **评分 100** ✅ |
| `normalCount` / `riskCount` / `faultCount` | `5` / `0` / `0` | 三类计数（**5 = 子项总数**，与 `details[].child` 数量吻合） |
| `carDataUpdateTime` | `2026-09-22 07:19:28.967` | **它检的是哪一刻的车况** → 与 control `lastUpdatedTime` 一致 ✅（体检不是"现在"，是 2.5 小时前） |
| `checkTime` | `2026-09-22 09:56:30` | **体检发起时刻**（服务端现算） |
| `createAt` | `null` | |
| `deviceType` | `null` | |
| `details[]` | 3 个大类（见下） | |
| `details[0].checkResultId` 等 | `null` | 父级字段全空，**只有 `itemName` / `itemCode` 有值** |

#### `details[]` 结构（3 大类 / 5 子项）

| 父项 `itemName` | `itemCode` | 子项 `itemName` | 子项 `itemCode` | `status` | `description` | `detectValue` | `normalValue` | `suggest` |
|---|---|---|---|---|---|---|---|---|
| 电器系统 | `electricSystem` | 安全气囊系统状态 | `airbagSystemStatus` | `normal` | 正常 | `"0"` | 正常 | `0：正常 1：故障` |
| 动力系统 | `powerSystem` | 电机系统状态 | `motorSystemStatus` | `normal` | 电机系统正常 | `"0"` | 电机系统正常 | `0：正常 1：故障` |
| 底盘系统 | `chassisSystem` | ABS防抱死系统 | `absStatus` | `normal` | （空） | `null` | `null` | `""` |
| 底盘系统 | `chassisSystem` | 胎压状态 | `tyrePressureStatus` | `normal` | 正常 | `""` | 正常 | `0：正常 1：异常` |
| 底盘系统 | `chassisSystem` | 助力转向系统 | `assistantSteeringStatus` | `normal` | （空） | `null` | `null` | `""` |

子项字段（18 个）：`checkResultId`、`checkHistoryId`、`userId`、`carId`、`itemId`、`itemName`、`itemCode`、`description`、`status`、`detectValue`、`mapValue`、`normalValue`、`suggest`、`suggestAction`、`suggestActionUrl`、`createAt`、`child`（子项里恒 `null`）。

> ⚠️ **`detectValue` 不总是有值**：气囊与电机是 `"0"`，胎压是 `""`，ABS/助力转向是 `null`。UI 里"实测值"一栏必须能显示"未提供"，不能默认 `0`。
> ⚠️ `normalValue: "正常"` + `detectValue: "0"` → **不能直接把 `detectValue` 当数值渲染**（它有时是枚举码，有时是空）。
> ⚠️ 体检的子项**只有 5 个**（气囊/电机/ABS/胎压/转向），车机 `getControlStatus` 能给 197 个字段 → **体检页可以自算更多项，但服务端只背书这 5 项**。

### 4.9 控车指令 API（🆕 本次日志里没有，从参考实现源码补全）

**下发指令**（与既有 9 个接口不同，它不在 `appserver` 下）：

```
POST {base}/api/car/control?pin={控制码}&cmd={Command}&carId={carId}&phoneType=&phoneId=&token={token}
     └─ OpenAir 时额外带 &temperature={17..30}（不传默认 17）
```

| `cmd` 取值 | 中文（参考实现 `Description`） | 备注 |
|---|---|---|
| `UpCarCondition` | **刷新车辆状态(TBOX)** | 🎯 **唯一的"让车立即上报"手段** —— 解决"数据 2h37m 旧"的正解（比频繁拉 `getCarLocation` 有效得多） |
| `LockDoor` | 锁门 | 我们已发 ✅ |
| `UnLockDoor` | 解锁 | 我们已发 ✅（注意大小写：`UnLockDoor`，不是 `UnlockDoor`） |
| `CloseAir` | 关闭空调 | 我们已发 ✅ |
| `OpenAir` | 开启空调 | 我们已发 ✅（带 `temperature`） |
| `FlashLight` | 闪灯 | 我们已发 ✅ |
| `Whistle` | 鸣笛 | 我们已发 ✅ |
| `RemoteSearchCar` | 远程寻车 | 我们已发 ✅ |

> 已核对：我们的 8 个名字与参考实现**逐字一致**（错一个字母就会静默失败），但**缺 `UpCarCondition`**。

**立即回包**：`{code, msg, success, data:{…}}`，`data.TaskId` 是后续轮询的钥匙。

**取结果**：`POST /api/car/getControlInfo?carId=&id={TaskId}&token=` → `data` 字段：

| 字段 | 样例/含义 |
|---|---|
| `TaskId` | 任务 ID |
| `TboxCmd` | 指令名（同上枚举，参考实现用它反查中文） |
| `CmdSendTime` / `CmdFinishTime` | 下发时间 / 完成时间——**`CmdFinishTime` 为空 = 还在执行**（参考实现就靠这个判"执行中"） |
| `HandleStatus` / `HandleStatusDesc` | 执行状态 / 状态描述 ❓ **取值集合未核实**（参考实现也只原样显示，**没有任何枚举映射**） |
| `HandleCode` | 错误码 |
| `SenderDevice` / `SenderType` | 下发设备 / 下发者类型 ❓ |
| `CarId` / `UserId` / `Tuid` / `RequestId` | 车辆/用户/车机/请求号 |

**轮询节奏（双侧一致 ✅）**：参考实现 `maxRetryCount = 12` × `intervalSeconds = 5`（`MainForm.cs:475-476`）；
我们 `CommandCenter.swift:104-136` 也是 **12 次 × 5 秒 = 60 秒**，完全吻合。

> ✅ 我们读的就是 `TaskId` → `HandleStatus`/`HandleStatusDesc`/`HandleCode`/`CmdFinishTime`（`ciString` + 兜底），与参考实现一致。
> ⚠️ **一处我们需要修正**：我们判断"终态"用的是自编字符串表 `["Success","Completed","RunFailure","Failed","Timeout",…]`（大写/小写共 10 个）
> —— 但**服务端到底返回哪些字符串没有任何依据**（参考实现都不敢判，只显示原文）。若真实取值不在表里（比如 `"2"`、`"RUN_FAILURE"`），
> 每条指令都会走到 "结果待确认（60 秒未收到车辆终态）"。**建议改成有源码依据的判据**：`CmdFinishTime` 非空 = 已到达终态（参考实现就靠它区分"执行中"），再用 `HandleCode` 判成败。
> 💡 另一改进：补 `UpCarCondition` 按钮（"让车立即上报"，比刷得更勤有效）。

---

## 5. 交叉核对：报文之间互相矛盾 / 需要注意的地方

### 5.1 里程（🔴 最关键）
| 来源 | 字段 | 值 |
|---|---|---|
| `car/getMyCars` | `totalOdometer` | `null` ← 这里没有 |
| `api/car/getControlStatus` | `totalOdometer` | **53766.4** ← 唯一有值的地方 |
| 我们代码 | `ciNumber(control, ["Mileage","mileage","TotalMileage"])` | 🚫 永远 nil → `carkeeper_current_mileage` 恒 0 → 维保提醒永不触发 |
| 我们代码 | `control?["TotalOdometer"]`（`VM.driveStatus`） | 🚫 nil，且该函数**零调用点**（死代码）→ 全 App **没有任何地方读到真实里程** |

### 5.2 保养
`maintainSpaceMileage:20000` + `lastMaintainMileage:20100` + 当前 `53766.4` → 下次 **40100 km**，**已超 13666 km（68% 间隔）**。我们硬编码 `defaultServiceInterval = 10000` + UserDefaults 里 `carkeeper_last_service_mileage`（只有用户手填才非 0）→ 提醒要么不响，要么给错数。

### 5.3 坐标（**已由车主定案：以 `location` 为准**）
`location` (30.5222546, 114.2323020) vs `control`/`pm25` (00.000000, 00.000000) = **589 m**。消息事件里的坐标 = `location` 那份。
→ **地图 / 停车位置 / 距我多远 一律读 `caches["location"]`**（字段也最全：`gpsTime`/`speed`/`heading`/`validGps`/`addrDesc`）；
`control.lng/lat` 与 `pm25.carLocationResp` 不再是备选数据源，此差异在此备案，避免下一个人换源。
（`control.heading:550.4` 可直接用，但要过 `norm360` → 190.4°。）

### 5.4 用户身份
| 字段 | scrm (`userInfoVo`) | iov (`getUserInfoByToken`) |
|---|---|---|
| 性别 | `sex: "1"` | `gender: "f"` ⚠️ 冲突 |
| 状态 | `status: "0"` | `status: "1"` ⚠️ 冲突 |
| 生日 | `birthday: null` | `birthday: ****-**-**` |
| 登录时间 | — | `lastLoginTime: 2024-06-05`（App）；control 另有车机 `lastLoginTime: 2026-09-22 07:18:58` |
| 注册 | `createTime: 2022-09-23` | `registerTime: 2021-10-30` ⚠️ 差一年 |
| ID | `uid = 842f277d…`（= iov `openId`） | `userId = 39717783-…` |

**结论**：以 **iov 报文为准**（它是车端鉴权方）；scrm 只用于头像/积分/标签；`sex:"1"` 与 `gender:"f"` 必有一个是错的 → 性别**建议不显示**。

### 5.5 消息已读
`readStatus: 0`（未读）与 `new: false`（非新）在**同一条记录里同时出现** → 两者语义不同（`readStatus` = 用户是否已读；`new` = 参考实现本次是否新拉取？）。**不要用 `new` 判断红点**。

### 5.6 时间戳三件套
`eventActionTime`（秒级 epoch，事件发生）→ `deviceTime`（毫秒 epoch，车机上报）→ `serverTime`（毫秒 epoch，服务端入库，晚 1 s）→ `updatedAt`（"yyyy-MM-dd HH:mm:ss"，晚 1 s）。三者**互相可校验** ✅。

### 5.7 数据龄期
车端最后一次上报 `07:19:28`，请求发生在 `09:56`，**差 2 h 37 min**。而 11 次请求全部 HTTP 200。**「200」不能当作「有数据」**。

---

## 6. 我们的读法审计：**72 处恒 nil**

方法：从日志取真实键集合 → 扫描 Swift 里 `obj["Key"]` 形态的下标 → 找「与真实键只差大小写」的（已排除数组字面量等误报；`ciPick/ciNumber/ciString/ciBool` 家族大小写不敏感，**不计入**）。

**分布：`ViewModels.swift` 67 处 / `Analysis.swift` 10 处（含 5 处已写小写兜底）**

| 函数 | 调用点 | 失效读数 | 用户可见后果 |
|---|---|---|---|
| `VM.energy`（在 `vnumOf` 组内） | **15**（首页能量卡、电池页 ×4、地图、小组件…） | `ChrgStatus`、`TotalVoltage`、`TotalCurrent`、`Min/MaxTemperatureValue`、`InsulateResistance`、`ChargeStarttime/Stoptime`、`ChargDeltMins`、`LastUpdatedTime`、`DeviceTime` | 充电态恒"未充电"；`335.8V / 0.0A` 恒 `--`；电池温度恒 `--`；绝缘恒 `--`；**在线态恒"离线"**（因为 `c["LastUpdatedTime"] != nil` 永远 false） |
| `VM.bodyStatus`（在 `mk` 组内） | **4** | `Door`、`Window`、`Trunk`、`Sunroof`、`DriverDoorLock` | ⚠️ **最会骗人的一处**：`num(nil)` 返回 **0**，而判据是 `num(...) == 0` → **无论真实状态如何，永远显示"车门/车窗/后备箱/天窗 已关、车锁 已锁"** |
| `VM.comfortStatus` | 2 | `Status`（air）、`Pm25InnnerCarValue`、`Pm25OuterCarValue`、座椅 4 项 | 空调恒"暂无数据"（`nestedObject(control,"Air")` 亦大小写错）、PM2.5 恒 `--`、座椅恒"关" |
| `VM.healthModel` | 1（体检页） | `Status`×4、`CheckTime`、`CheckHistoryId`×2、`NormalCount`、`RiskCount`、`FaultCount`、`CarDataUpdateTime` | 体检页三个计数恒 `--`、时间空白；**服务端算好的 100 分用不上** |
| `VM.userModel` | 1（我的） | `UserFullname`、`UserNickname`×3、`Mobile`、`Gender`、`LastLoginTime`、`Source`、`Birthday` | 账号卡片姓名/手机/性别/生日空白 |
| `VM.vehicleSummary` | **4**（车辆档案、搜索、我的） | `Pin`×2、`InsuranceEndDate`×2、`TserviceEndtime`×2、`CarName`、`PlateNumber`、`Vin`、`Color`、`ModelCode`、`ConfName`、`IsNev` | **车辆档案页显示「未绑定车牌」「未绑定车辆」**、VIN `--`、车型不显示、控车码 `--`、保险/服务到期不显示 |
| `VM.driveStatus` | **0（死代码）** | `VehicleSpeed`×2、`TotalOdometer`、`ShiftPosition`×3 | 无（但**它曾是我们以为的"里程读数"来源**，事实是它从未被调用） |
| `AN.summarize`（充电子域等） | 2（电池页、体检原始数据） | `InsuranceEndDate`、`TserviceEndtime`、`ChrgStatus`、`RemainPower`、`RemainedPowerMile`、`ChargDeltMins`、`ChargeStarttime/Stoptime`、`ReservationUseVehicleTime` | 电池页/原始数据里充电域全 `--` |

**已兜底（5 处，不算 bug）**：`carSel` 的 `["CarId"] ?? ["carId"]`、`["CarName"] ?? ["carName"]`、`["PlateNumber"] ?? ["plateNumber"]`、`energy` 里同款 2 处。
**修法（一次性）**：把 `VM`/`AN` 里所有 `dict["X"]` 换成 `ciPick/ciString/ciNumber`（大小写不敏感），或**在缓存入口做一次小写归一化**（但那样 `ciPick` 依然工作、且 `FireStatus` 之类旧写法的兜底也不受影响）；同时给 `scan/` 加一条门禁：**禁止 `obj["Capitalized"]` 形态的字面量下标**（**本轮已落地**：`scan/keys.py` —— 内置 441 个真实报文键，写错大小写直接红）。

**为什么参考实现从没踩这个坑（§0.2 已核实）**：它的 `JsonSerializerOptions` 写着 `PropertyNameCaseInsensitive = true`
+ `AllowReadingFromString`（`MainForm.cs:26`）—— **大小写不敏感下沉到了解码器**，所以它写 `CarMode`、`ChrgStatus` 随便什么大小写都能读到，
而且字符串/数字互相兼容也是解码器给的。我们 Swift 侧没有这一层，就退化成"靠在每个调用点记得写 `ci*`" → 一定会漏。
**推荐正解**：在 `caches` 写入处做一次**小写归一化**（`saveCache` 里把 `[String:Any]` 的键全 `lowercased()`），
那时 `ciPick` 仍能工作（它也 lowercases）、`obj["carStatus"]` 这类**已经写对的**下标也继续有效（只是不再依赖大小写），
而写错大小写的旧代码要么继续靠 `ci*`、要么会被门禁抓出来——**两个方向的错都变成可测的**。

**另一个"注释说谎"**：`AppStore.swift:672` 写着"车况每 60 秒轮询一次"，但全库**没有任何车辆轮询循环**
（已核实：只有 `CommandCenter` 的指令结果轮询、短信倒计时、以及 `BackgroundTaskManager` 的 15/30 分钟 BG 刷新）。
注释把行为说成比现实更勤快，跟界面上"在线"永远亮着是一类错。

---

## 7. 报文里有、我们**零引用**的字段 → 能立刻开的功能

| 字段 | 能做什么 | 成本 |
|---|---|---|
| `funCode`（43 个开关） | 按能力位图开合控件（`#StateWindow:0` 就别显示车窗） | 低 |
| `maintainSpaceMileage` / `lastMaintainMileage` | **真实维保里程提醒**（替换硬编码 10000） | 低 |
| `nevChargeSystemVoltageDtoList`（88 节） | 电池页画**真实单体电压柱状图** + "第 56 号电芯偏低 23 mV" | 中 |
| `nevChargeSystemTemperatureDtoList`（26 探针） | 电池温度热区图 | 中 |
| `insulateResistance` / `totalVoltage` / `totalCurrent` | 三电健康卡片（绝缘 20 kΩ 是重要安全指标） | 低 |
| `insuranceCompany` / `insurancePhone` | 保险卡片（到期日缺失也能显示"中华联合保险 95585"） | 低 |
| `tserviceStatus` / `tserviceEndtime` | "我的"里显示"车联网服务 生效中" | 低 |
| `realnameAuthStatus` / `realnameAuthed` | 实名状态（决定是否引导实名） | 低 |
| `isPrivacyDrvingHistory` | 解释"为什么没有轨迹"（=1 表示不外传） | 低 |
| `pin: "exist"` | 操作条区分"首次设置控车码"/"输入已有控车码" | 低 |
| `stubId` | 消息**幂等去重**（我们零引用 → 重复消息会重复插入） | 低 |
| `last`（分页） | 消息分页正确性（现在只看第一页） | 低 |
| `uriParams.*` | **行程自动生成**（事件对配对 + 起终点 + 时长）—— `startTrip/endTrip` 已写好但**零调用点**（§11.0） | 中 |
| `ignitionTime` | "最近一次点火"（首页可显示"23 分钟前熄火"） | 低 |
| `deviceTime`/`gpsTime`/`serverTime`/`lastUpdatedTime` | **数据龄期降级**（车钉变灰 + "最后上报 2 小时前") | 低 |
| `satNum` / `alti` | 定位质量（5 颗星 · 海拔 26 m） | 低 |
| `air.temperature` / `air.wind` | 空调**设定值**（不是 pm25 的 0；已确认当时空调关着） | 低 |
| `UpCarCondition`（控车指令） | **让 TBOX 立即上报** —— 正解"数据 2h37m 旧"（不是刷得更勤） | 低 |
| `CmdFinishTime` / `HandleStatus` / `HandleCode` | 指令结果判到"真的完成 / 真的失败"（含错误码） | 低 |
| `maxAlarmLevel` + 一批 `*Alarm` | 总览"是否有问题"的权威判据（别自己拼） | 低 |
| `score` / `normalCount` / `details[].child[]` | 体检页（现在读不到 → 显示 `--`） | 低（同 §6 修复） |

---

## 8. 未核实枚举清单（🚫 不许编中文，界面显示原文）

| 字段 | 观测值 | 处理建议 |
|---|---|---|
| ~~`chrgStatus` / `chargeStatus`~~ | `"3"` / `3` | ✅ **已核实**（§0.1 #1）：3 = 不在充电；时间戳字段是「上次充电 2024-05-20」 |
| ~~`status`~~ | `"2"` / `2` | ✅ **已核实 = 熄火**（§0.2，参考实现 `Status == 2 ? "熄火" : "行驶"`）；且能自证：当时 06:45 点火→07:08 熄火 |
| `carStatus` / `carMode` / `dcStatus` | `2` / `1` / `1` | ❓ 仍无映射（参考实现也没映射，只存不显）→ 显示原文 |
| `fireStatus` | `"2"` | ✅ 已核实：`1`=启动 `2`=熄火（与消息 `IGNITION`/`FLAMEOUT` 事件逐秒交叉验证） |
| `HandleStatus` / `HandleStatusDesc` / `HandleCode`（控车轮询） | 未观测到取值 | ❓ 参考实现全零映射；⚠️ 我们代码里的 10 个终态字符串是**自编的**（见 §4.9）→ 改用 `CmdFinishTime` 非空作终态判据 |
| `SenderDevice` / `SenderType` | 未观测 | ❓ 不显示 |
| `readStatus`（消息） | `0` | ❓ **车主确认无红点** → 不用作未读；红点以 `new` 为准（§0.1 #7） |
| ~~`air.status`~~ | `"0"` | ✅ **已核实**（§0.1 #2）：**0 = 关**（1 = 开仍为推论）；`temperature`/`wind` 是设定值 → 「空调 已关闭 · 上次设定 26℃ · 风量 3 档」 |
| `fireStatus` | `"2"` | 代码里已有 `1=启动 2=熄火` 映射（**与 `ignitionTime` 交叉验证一致** ✅ 可用） |
| `motorSystemStatus` / `state`(电机) / `type`(电机) | `0` / `4` / `0` | 原文 |
| `flameoutReason` / `ignitionReason` | `0` | 原文 |
| `sidAndMid` | `"5,100"` | 原文 |
| `source` / `realnameAuthStatus` / `tserviceStatus` / `pin` | `schedule` / `AUTHED` / `active` / `exist` | 这几组**语义已核实** ✅（来源/已实名/生效中/已设置） |
| `vehiclePureDeviceTypeOvercharge`、`isHistoryPoi`、`forwardFlag`、`conditionidle`、`powerStatusFeedBack`、`keyAlarm`、`temperatureDifferenceAlarm` … | 全 `0` | **一律不显示**（0 = 无告警是唯一安全解释），或显示原文 |
| ~~`tireTemperature`~~ | `67–69℃` | ✅ **已核实**（§0.1 #4）：读数可信，照常显示 + 注「行驶后偏高」 |

**规则**：像我们已有的 60 个 SDK 名字那样，建一张「已核实 / 未核实」字段表；未核实的显示原文。

---

## 9. 数据质量与安全

### 9.1 哨兵值（必须过滤，否则界面说谎）
| 字段 | 哨兵 | 症状 |
|---|---|---|
| `insuranceEndDate` / `lastCheckTime` | `"0000-00-00"` | `parseDate` 全格式失败 → nil（"保险已过期 73 万天"的来源） |
| `activeTime` | `"0000-00-00\n\t\t00:00:00"` | 含**换行 + 制表符** |
| `shortTermFuelTrim` | `-100` | 燃油修正无意义 |
| `pm25InnnerCarValue` | `"-1"` | 无数据（我们已处理 ✅） |
| `vehicleTemperature` / `environmentalTemperature` / `pm25`(control) | `0` | **0 = 无数据**（车内真实温度在 `air.temperature`） |
| `recordTime` | 一年前的值 | 不是"最后记录" |
| `tserviceStarttime` | `null` + 结束 2041 | 显示"长期有效" |

### 9.2 服务端字段名缺陷（我们若按"正确拼写"读就永远读不到）
`leftFrontDoorrWindow`、`rightFrontDoorrWindow`、`leftRearDoorrWindow`（多一个 r）｜`cutchPedal`（clutch）｜`turnLndicator` / `turnLndicatorLeft` / `turnLndicatorRight`（Indicator）｜`pm25InnnerCarValue`（Inner）｜`isPrivacyDrvingHistory`（Driving）｜`chargDeltMins`（charge）｜`ChargPower`(我们代码里的猜测，报文未出现)。
→ **建议把这些拼写错误做成一张常量表并注明"服务端原文如此"**，避免下一个人"顺手修正"后再也读不到。

### 9.3 类型混用
- **字符串 vs 数字**：`status:"2"`/`carStatus:2`、`door:"0"`/`leftFrontDoor:0`、`window:"0"`、`light:"0"`、`fireStatus:"2"`、`air.*` 全字符串、`chrgStatus:"3"`/`chargeStatus:3`。
- **0/1 vs true/false**：`validGps:true`/`isValidGps:true`/`isInValidGps:0`。
→ 一律走 `ciString/ciNumber/ciBool`（大小写不敏感 + 类型宽松）✅ 我们已有这层。

### 9.4 安全
| 项 | 现状 | 处置 |
|---|---|---|
| `refresh_token` 不轮换 | 请求与响应逐字符相同 → **泄露一次 = 长期有效** | 只能本地加密保存；绝不出现在日志/导出 |
| 令牌存储 | ✅ **已修**：`TokenStore` 已迁 **Keychain**（含旧 UserDefaults 值的自动迁移；退出登录时两处都清 —— 只删 UserDefaults 会让凭证留在设备上） | — |
| 日志脱敏（我们自己的 `RawLogStore`） | ✅ **已补**：原覆盖 `token/pin/refreshToken/accessToken/password/pwd/csrfToken` + `phone/mobile/tel/plate/plateNumber/plateNo` + 裸 11 位手机号，**本轮新增** `vin`、`idcard`、`certifiNo`、`userFullname`/`name`/`lastName`/`nickName`、`tuid`、`userId`/`openId`/`cycuid`、`avatar`、`carNum`、坐标 `lat/lng`、`addrDesc`/`addrName`、`containerName` | 消息 `content`（**含车牌的中文句子**）只能在展示层再脱；白名单式过滤比黑名单更稳 |
| 本次日志文件 | 打码只覆盖 URL `token=` 与 Authorization 头，**JSON body 全裸**（含 refresh/access token、姓名、手机、身份证、车牌、VIN、精确坐标、医院名） | 该文件**不可外发**；若要当问题反馈，先按 §9.4 全字段清洗 |

---

## 10. 行动清单（按"代价低 × 收益高"排序）

> **状态（2026-09-22 第三轮）**：1–10 **全部已落地**（逐条对应见 §11.1b 与
> `DESIGN-UNIFY.md` §8 的两张表）。第 5 条是唯一的例外：能力位图已接（`VM.capabilities`），
> 但**没有**拿它隐藏控件 —— 理由见 §11.1b #17。下面保留原始清单以便核对口径。

1. **修读层大小写**（§6，72 处）：`VM`/`AN` 的直接下标 → `ci*` 系列；顺手删掉死代码 `VM.driveStatus` 或接到界面上。加一条 `scan/` 门禁禁止 `["Capitalized"]` 下标。→ 一次性修好「未绑定车牌 / 恒已锁 / 恒离线 / 体检计数 `--` / 空调暂无数据」。
2. **里程与保养**（§4.2/§5.1/§5.2）：写入点改读 `totalOdometer`；间隔改用 `maintainSpaceMileage`；上次保养用 `lastMaintainMileage`。
3. **哨兵值守卫**（§9.1）：`daysUntil` 前置 `0000-00-00` / `-1` / `0` / 含空白 的判断，统一返回 nil → UI 显示"未登记"。
4. **数据龄期**（§5.7）：以 `lastUpdatedTime`/`gpsTime` 为准，超过阈值就把车钉降级为灰虚 + "最后上报 xx 前"；自适应轮询（数据未推进就退避）。
5. **能力位图开合控件**（§4.2 funCode）：`#StateWindow:0` 隐藏车窗、`#PeriodicCharge:0` 隐藏定时充电。
6. **消息用 `stubId` 去重 + `readStatus` 判红点**（§4.7/§5.5），并用 `jumpParam` 合成行程（§4.7）。
7. **保险/服务卡片**（`insuranceCompany`/`insurancePhone`/`tserviceStatus`）。
8. **电池明细图**（88 节 + 26 探针 + 绝缘）。
9. **未核实枚举表 + 显示原文**（§8）。
10. **安全**（§9.4）：Keychain 迁移；日志脱敏补齐 12 类字段；本地历史日志清理策略。

---

## 11. 结合这些数据，我们还能做什么（功能候选）

> 判断依据：① 字段是否真的在报文里（§4）；② 车载端是否**上报**（不支持的字段会恒 0/null）；③ 我们是否已有接收器（有接收器、只差数据源的，代价最低）。

### 11.0 先说一个通用现象：**接收器已写好，但零调用点 / 数据源被读错**

| 已存在的东西 | 状态 | 它需要的数据 |
|---|---|---|
| `AppStore.startTrip()/endTrip()` | **零调用点** | 点火/熄火事件（消息流已有） |
| `AppStore.saveParkingLocation()` | **零调用点** | 熄火事件坐标（消息流已有） |
| `parkingHistory` | 只被读（热区/常停） | 同上 |
| `chargingPowerHistory` | 只在 `pow > 0.1` 时写 → **永远是空** | 充电功率（见 11.1 #1） |
| `carkeeper_current_mileage` | 读取方还在，写入点**读错了键** | `totalOdometer` |
| `carkeeper_total_mileage` | **零写入点**（setter 从未被调） | `totalOdometer` |
| `MaintenanceReminderScheduler` / `ChargingStatusMonitor` / `ChargeLedger` | 已实现、已被调用 | 上两行的真实数据 |

→ **结论：好几个"新功能"其实是"把现成接收器接上真实数据源"**，不是从零开发。

### 11.1 A 组：数据已在手，不需任何新接口（现在就能做）

| # | 功能 | 用到的真实字段 | 现在为什么是空的/错的 |
|---|---|---|---|
| 1 | **真实充电功率与充电曲线** | `totalVoltage`(335.8 V) × `totalCurrent`(A) ÷ 1000 = kW | 我们只认 `ChargPower`/`ChargingPower`（**报文里不存在这两个键**）→ 功率恒 nil → 曲线/账本/小组件功率全空。静止时 `totalCurrent = 0.0`（噪声 0.2 A）正好说明"没在充电" |
| 2 | **88 节电芯图 + 一致性趋势** | `nevChargeSystemVoltageDtoList[0].batteryVoltage`(88 节)、`maxVoltageBatteryNum:3`/`minVoltageBatteryNum:56`、`batteryConsistencyDifferenceAlarm` | 零引用。可画柱状图 + "第 56 号最低 3.800 V，压差 23 mV（正常）"；把压差写进 `HistoryStore` 就是**电池一致性趋势**（30 天内从 X 漂到 23 mV） |
| 3 | **电池温度分区图** | `nevChargeSystemTemperatureDtoList[0].probeTemperatures`(26 个)、`min/maxTemperatureProbe`、`min/maxTemperatureValue` | 零引用。行驶/充电后温差能看散热是否正常 |
| 4 | **绝缘电阻（安全）** | `insulateResistance:20000`、`insulationAlarm`、`highVoltageInterlockStateAlarm` | 零引用。电车最重要的安全指标之一，可做阈值告警 + 趋势 |
| 5 | **真实维保计划** | `maintainSpaceMileage:20000`、`lastMaintainMileage:20100`、`totalOdometer:53766.4` | 现在硬编码 10000 + 一个永远写不进去的键 → **已超 13666 km 却不提醒** |
| 6 | **小组件 / 手表的里程** | `totalOdometer` | `carkeeper_total_mileage` 零写入 → 手表与小组件的里程**恒为 0** |
| 7 | **让车立即上报 + 数据龄期一等公民** | 指令 `UpCarCondition`（§4.9）+ `lastUpdatedTime`/`gpsTime` | 现在既不主动刷新，也不标注"数据 2h37m 旧" → 用户看着 200 以为是最新的 |
| 8 | **行程自动生成** | `IGNITION`/`FLAMEOUT` 事件对 + `jumpParam.{gpsTime,lat,lng,addrName,deviceTime,eventActionTime}` + `ignitionTime` + `totalOdometer` 差 + `soc` 差 | `startTrip/endTrip` 零调用。⚠️ **只能得到"起终点 + 时长 + 里程/SOC 差"，没有轨迹点**（`isPrivacyDrvingHistory:1` → 轨迹不外传），不要假装画路径 |
| 9 | **停过哪儿 / 常停之地** | 熄火事件坐标 + `status:2` | `parkingHistory` 零写入 → 热区/"上次停车位置"永远是空 |
| 10 | **行程电耗评分（真的评分）** | 行程的 `soc` 差 + 里程 | 已有 `ScoreSection`，但它诚实地说"还没有一段行程留下能耗读数"→ 一旦 #8 落地就自动点亮。💡 **"每 1% SOC 跑多少 km"不需要电池容量**（`capacity` 是 null），这比现在硬编码 `15 kWh` 正确 |
| 11 | **四轮压力/温度趋势 + 告警** | `lf/rf/lr/rr TyrePressure`、四个 `*PressureWarning`、四个 `*TireTemperature`、`tireTemperatureStatus` | 胎压已在采样；胎温与四个 warning 零引用 → 可加"<200 或 >280 kPa 提醒"、"行驶后偏高"说明 |
| 12 | **空调/座椅/空气真实状态** | `air.{temperature,wind,status}`、`driverSeatAirStatus`/`driverSeatHeatStatus`、`passengerSeat*`、`airPurifierStatus`、`pm25`(control)、pm25 接口的 `pm25OuterCarValue` | `nestedObject(control,"Air")` 大小写错 → 空调恒"暂无数据"（§6） |
| 13 | **一车一灯的告警总览** | `maxAlarmLevel` + 26 个 `*Alarm` + `*FaultCount`/`*FaultCodes`/`otherFaultCount` + `keyLowPower` | 现在体检页只看服务端的 5 项；`maxAlarmLevel` 是"是否有问题"的权威依据 |
| 14 | **体检报告的"依据透明"** | `carDataUpdateTime`（07:19 的车况）、`score`、`normal/risk/faultCount`、`details[].child`（5 项） | 可展示"服务端背书 5 项 + 我们自算 N 项（绝缘/压差/胎压）"，并标明体检依据的车况时刻 |
| 15 | **消息 → 地图联动 + 幂等去重** | `jumpParam.{lat,lng,addrName}`、`infoTypeId`、`stubId`、`new`（红点） | 点事件可"飞到那个点"；`stubId` 去重；红点用 `new`（§0.1 #7） |
| 16 | **权益与服务卡** | `tserviceStatus`/`tserviceEndtime`（显示"长期有效"）、`insuranceCompany`/`insurancePhone`、`realnameAuthStatus`、`pin`、`isPrivacyDrvingHistory` | 均零引用；`isPrivacyDrvingHistory` 还能解释"为什么没有轨迹" |
| 17 | **能力位图驱动的界面** | `funCode` 里**语义明确**的 12 个：`StateWindow`/`StateFrontDoor`/`Statelock`/`Statetrunk`/`Statelight`/`airBtn`/`airGradeBtnNew`/`lightBtn`/`doorBtn`/`humidity`/`PeriodicCharge`/`SOCLimit`/`chargeBtn` | 本车 `#StateWindow:0`、`#PeriodicCharge:0` → 不应显示车窗/定时充电 |

### 11.1b 已落地（2026-09-22 第三轮）：上表哪几条已经变成代码

> 每一条都注明**唯一的取数点**，方便下一个人找到“真正的那个地方”。

| §11.1 # | 落地位置（唯一取数点） |
|---|---|
| 1 | `VM.chargePowerKW`（`totalVoltage × totalCurrent`）—— 已接到能量卡 / 充电曲线 / 账本 kWh / 小组件 / **电池页**（电池页以前还在读不存在的 `ChargPower`，本轮修好） |
| 2 | `AN.barsOf` 采样上限 64 → **128**（本车 88 节，步长 2 会丢一半电芯）+ 电池「一致性」显示 **最低·第56节 / 最高·第3节**（`minVoltageBatteryNum`/`maxVoltageBatteryNum`） |
| 3 | 电池「一致性」里的温度探针图（26 个 `probeTemperatures`） |
| 4 | 电池新增「高压安全」卡：`insulateResistance`（以前 `EnergyModel.insulate` 算好了但**没有任何视图读**） |
| 5 | `VM.maintenancePlan`（间隔 / 上次保养来自服务端 `maintainSpaceMileage` / `lastMaintainMileage`） |
| 6 | `totalOdometer` → `carkeeper_current_mileage` + `carkeeper_total_mileage`（手表 / 小组件里程不再恒 0） |
| 7 | 指令 `UpCarCondition`（车控「低频指令」）+ `VM.reportAge` + 地图 freshness 理由 |
| 8/9/10 | `AppStore.ingestEvents` → `startTrip`/`endTrip`/`saveParkingLocation`（幂等键 `stubId`，坐标/地址读 `jumpParam`）；行程一旦有数据，`ScoreSection` 自动点亮 |
| 11 | 四轮胎压 + 四个 `*PressureWarning`（胎温按车主确认照常显示，并注明“行驶后偏高”） |
| 12 | `VM.energy` 的空调文案：「已关闭 · 上次设定 26℃ · 风量 3 档」（不再把上次设定值说成“当前”） |
| 13 | `VM.alarmFlags` / `VM.activeAlarms` / `VM.maxAlarmLevel` → 地图主屏**告警总灯** + 电池「电池告警」**共用同一张表**（非 0 即亮；只在真的亮着时才出现） |
| 14 | 体检与数据页的「依据透明」（服务端 5 项 + `carDataUpdateTime`） |
| 15 | `MessagesSection`：`stubId` 去重 + 红点用 `new` + `jumpParam` 坐标 → 地图 fly-to |
| 16 | **部分落地**：保险（`insuranceCompany`/`insurancePhone`，到期日哨兵 → 「未登记」）、车联网服务到期（`tserviceEndtime`，修复了带时分秒的日期解析）、控车码 `pin`。仍未接：`realnameAuthStatus`、`isPrivacyDrvingHistory`（后者就是“为什么没有轨迹”的解释） |
| 17 | **刻意不落地**：`funCode` 已解析（`VM.capabilities`）并显示在开发者工具，但**不隐藏控件** —— 两组同名开关互相矛盾（本车 `remoteBaseControl.airBtn = 1` vs `remoteBaseControl_XNY.airBtn = 0`），按可能是错的值隐藏会藏掉真能用的功能。理由全文见 `DESIGN-UNIFY.md` §8「第三轮」 |

### 11.2 B 组：方向明确，但需要新抓包（我们手上没有的接口）

| # | 功能 | 线索 | 需要拓什么 |
|---|---|---|---|
| 18 | **SOC 上限设置** | `funCode.changeS203EV.".SOCLimit":1`（**支持**） | 抓"设置 SOC 上限"的接口（参考实现也没有，只有 8 条指令） |
| 19 | **对外放电 / 充放电信息** | `funCode.changeS203EV."#chargeDischargeInfo":1`、`"#chargeBtn":1` | 抓放电开关/放电页接口 |
| 20 | **更多车控指令** | 参考实现只实现了 8 条；`funCode` 说明还有 `#zjcsStatusRC`、`#StateFrontDoor`、`#Statetrunk`、`#humidity` 等能力位 | 用小程序把每个按钮都点一次并抓包，得到完整 `cmd` 枚举 |
| 21 | **家庭成员 / 钥匙共享** | `FamilyAndKeySharing.swift` 已存在（待核:是否为本地壳） | 服务端接口未知 → 需抓包 |
| 22 | **电价 / 充电费用官方数据** | `powerPrice: null`（**字段存在但为空**） | 去小程序里找"电价设置"→ 若有，设置后再抓一次 |
| 23 | **轨迹历史** | `isPrivacyDrvingHistory:1` | 在设置里把它置 0，看是否出现 POI/轨迹接口 |
| 24 | **车辆位置图（`locationImgurl`）** | 三字段恒 `null`（未开通） | 若某天有值就是"车位照"，直接可用 |

### 11.3 C 组：需你确认才能做（未知枚举）

| # | 待确认 | 它挡住的功能 |
|---|---|---|
| 25 | `HandleStatus` 的取值集合 | 指令成败判定（现在靠**自编字符串表**，风险见 §4.9） |
| 26 | `carStatus` / `carMode` / `dcStatus` | 首页"车辆模式"卡片 |
| 27 | `flameoutReason` / `ignitionReason` 枚举 | 事件文案（钥匙/远程/自动？） |
| 28 | `readStatus` 的真实语义 | 消息中心能否做"已读/未读筛选" |
| 29 | `tireTemperature` 与环境温差的关系（你已确认可信） | 是否加"胎温异常"阈值告警（多少度算高？） |

### 11.4 D 组：数据不支持，**不建议做**（做了就是说谎）

| 想法 | 为什么不行 |
|---|---|
| 行程轨迹回放 / 轨迹线 | 没有轨迹点；`isPrivacyDrvingHistory:1` → 车端不外传 |
| 电池 SOH / 容量估算 | `capacity: null`，且只有当前电压快照 → 只能算"一致性"，不能算健康度 |
| "正在充电" 按钮态（单看 `chrgStatus`） | 残留值（§0.1 #1）→ 必须结合 SOC 趋势/功率 |
| 剩余充电时间 | `chargDeltMins` 是**上次**的；等 11.1 #1 功率真实化后，用"剩余 kWh ÷ 功率"估，并标明"估算" |
| 车外温度 / 车内 PM2.5 / 年检到期 | `environmentalTemperature:0`、`pm25InnnerCarValue:"-1"`、`lastCheckTime:"0000-00-00"` → 一律显示"无数据" |
| 燃油/油耗相关 | `shortTermFuelTrim:-100`、`engineFuelCutOffFlag`、`oilType:null` → 纯电无意义 |
| 仪表盘级实时电流/功率（停车时） | `totalCurrent:0.0` 静止 → 没数据就是没数据，不要用 SOC 差值造一个 |

---

## 12. 字段 → 代码接线表（2026-09-22 第二轮落地）

下表只列**本轮真正接上**的字段；「落在哪」一列写的是现有的面（不新增页面）。

| 字段（报文原文） | 以前 | 现在（唯一取数点） | 落在哪 |
|---|---|---|---|
| `control.totalOdometer` = 53766.4 | 读 `Mileage/mileage/TotalMileage`（**三个键都不存在**）→ 恒 0 | `AppStore.recordHistory` → `carkeeper_current_mileage` + `totalMileage` | 车 / 小组件 / 表盘 / 保养提醒 |
| `car.maintainSpaceMileage` = 20000 | 硬编码 `defaultServiceInterval = 10000` | `VM.maintenancePlan` | 地图理由 / 车 / 保养与钱 / Dev |
| `car.lastMaintainMileage` = 20100 | 本机键（且 `VehicleView` 用 `string(forKey:)` 读 Int 键 → **恒 nil**） | 同上 | 同上 |
| `control.totalVoltage` × `control.totalCurrent` | 读不存在的 `ChargPower/ChargingPower` → 功率恒 nil | `VM.chargePowerKW`（一处算法） | 能量卡 / 充电曲线 / 账本 kWh / 小组件 / 充电推送 |
| `control.lastUpdatedTime` / `deviceTime` | 只当「在线」，不显示龄期 | `VM.reportAge` →「在线 · 车端 2 小时前上报」+ 地图 freshness 理由 | 地图主屏 / 能量卡 |
| `car.insuranceEndDate` = `"0000-00-00"` | 原样打印（「保险到期 0000-00-00」） | `VM.antiSentinel` → 「未登记（小程序里没有填）」 | 车 / 我的 |
| `car.tserviceEndtime` = `2041-10-31 18:01:18` | 日期格式表里没有带时分秒这一档 → **静默解析失败**，到期日从不显示 | `parseDate` 新增 `yyyy-MM-dd HH:mm:ss` | 车 / 我的 |
| `car.activeTime` = `"0000-00-00\n\t\t00:00:00"` | 原样打印（带制表符） | `antiSentinel` → 整行不显示 | 车 |
| `charge.chrgStatus` = `"3"` | 写成「充电完成」 | 「未在充电」（车主确认静止时即 "3"，§0.1 #1） | 地图 / 电池 |
| `charge.chargeStarttime/Stoptime/chargDeltMins` | 只在 "1"/"2" 时展示 ✓ | 语义写明「**上一次**充电」（2024-05-20） | 电池 |
| `CmdFinishTime` / `HandleCode` / `HandleStatus` | 自编 10 字符串表判终态与成败 | `CmdFinishTime` 非空 = 终态；`VM.controlOutcome` 三态（成功/失败/**未确认**） | 车控 + 指令历史（新增「未确认」筛选） |
| （新增指令）`UpCarCondition` | 全库没有 | 车控「低频指令」：「刷新车况 · 让车端立刻上报一次状态」 | 车控 |
| `nevChargeSystemVoltageDtoList`（88 节）/ `…TemperatureDtoList`（26 探针）/ `driveMotorData` / `control.maxAlarmLevel` 回执块 | 全部直接下标 `["Cap"]` → 恒 --（电池页整块是空的） | `ciPick` 读取（电池页原有的电芯/电机/温度 UI 立刻有数）；**告警总览仍未做** | 电池 |

### 12.1 门禁：`scan/keys.py`

本轮的「读层修复」不是靠一次性改完，而是靠**让它不能再犯**：

* 内置 **441 个真实报文键**（从这份日志抽的，含数组元素里那一层：`driveMotorData` / `nevChargeSystem*DtoList` / 消息 / 体检明细）；
* 规则：`expr["CapitalizedKey"]` 与真实键只差大小写 → ❌ 退出码 1（并指出真实键名）；
* `ci*` 家族的**实参**键列表合法（它们自己折叠大小写）；非 `ci*` 函数的实参键列为待确认；
* 已接入 `.github/workflows/ios-build.yml` 的门禁列表（现有 16 个）。

### 12.2 仍未接（明确不做或未做）

`funCode` 能力位图驱动界面（43 个缩写里只有少数语义可核）｜`stubId` 幂等去重｜`jumpParam` 行程骨架｜
`new` 红点｜`maxAlarmLevel` 告警总览｜88 节电芯**列表**（现在只出 min/max）｜`pin` 控车码已有 ✓（不在此列）。

---

*附：本文档所有字段/数值均由脚本从日志原文生成（`scan/_fields.py` 字段清单、`scan/_msgs.py` 消息事件流），可复跑复现。三份历史日志（`0904`/`0917`/`0922`）端点覆盖一致（各 9 个端点），字段清单以 `0922` 为准。*

*一次性审计脚本（`_keyaudit.py` / `_keyctx.py` / `_facts.py`）已删除：它们的结论已经变成常驻门禁 [`scan/keys.py`](../scan/keys.py) 与常驻文档（本文 §6、§12）。*

*第二来源（源码，只读参考）：`D:\xm\ChangAnCarInfo\MainForm.cs`（WinForms，98 KB）+ `MainForm.Designer.cs` + `bin/Debug/changan_net_log_*.log`；引用行号以 2026-09-22 的副本为准。*
