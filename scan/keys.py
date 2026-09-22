#!/usr/bin/env python3
"""报文键纪律（Payload key discipline）—— 让「读错键」从「静默零值」变成「红」。

## 这个门禁为什么存在

2026-09-22 那份真实抓包（`changan_net_log_20260922.log`）证明：服务端报文的键**一律
首字母小写**（`remainPower` / `totalOdometer` / `driverDoorLock` …），而我们的 Swift 读层
一度写成 `["RemainPower"]` 这种首字母大写。Swift 的 `[String: Any]` 下标是**大小写敏感**的
（`JSONSerialization` 原样保留键名，我们也没有任何键名归一化层），于是：

    control["DriverDoorLock"]  →  nil  →  `num(nil)` 返回 0  →  界面显示「已锁」

**这是最坏的一类 bug**：它不报错、不崩溃、看起来像正常数据。地图上那排状态灯因此
在**任何车况下**都显示「已锁 / 已关」；车辆档案页显示「未绑定车牌」；空调恒「暂无数据」。

对照：参考实现（`D:/xm/ChangAnCarInfo`，C#）从没踩过这个坑，因为它的
`JsonSerializerOptions { PropertyNameCaseInsensitive = true }` 把大小写不敏感**下沉在解码器里**。
我们 Swift 侧没有那一层，只能靠「每个调用点都记得用 ci* 取键」—— 而「每个调用点都记得」
从来不是一种工程约束，它是一场必然会输的赌。所以需要这道门。

## 规则

**① 大小写敏感的直接下标** ❌

    形如  expr["CapitalizedKey"]      （`[` 前面是标识符 / `)` / `]`，即真正的下标）
    且该字面量与真实报文键**仅差大小写**  →  ❌ 退出码 1

    合规写法：`ciString(control, ["DriverDoorLock"])`、`ciNumber(charge, ["RemainPower"])`
    —— ci* 家族自己折叠大小写（它们的键列表是**实参**：`, ["Key"]`，不是下标）。

**② 只有 `ci*` 家族可以承载报文键**（提示级 ⚠️）

    形如  someCall(obj, ["CapitalizedKey"])  且 someCall 不是 ci*/vnum* 家族
    →  该键是**实参**，是否折叠大小写取决于被调函数；门禁不判错，但列为待确认。

豁免必须写明理由（与 paths.py / design.py 同一约定），输出成 ⚠️ 而不是静默通过。

## 键集合的来源

下面这份 `API_KEYS` 是从**真实报文**里抽出来的（360 个键，含嵌套一层），不是手写清单 ——
手写清单会随服务端加字段而腐坏，而腐坏的方向恰好是「漏报」。要更新它，重跑
`scan/_fields.py` 的抽取逻辑并替换本常量（键名一律小写）。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- 真实报文键集合（小写；来源：2026-09-22 抓包，360 键） ---------------------
API_KEYS = set("""
accpedal accel access_token activetime addrdesc address adviserid air airpurifierstatus
airbagsystemstatus alti authenticationtype avatar batteryalarm batterychargelightstatus
batterychargestatus batteryconsistencydifferencealarm batteryheatingstatus
batterypowersystemstatus bindtoken bind_token bindedjd birthday brakepedal brakesystemalarm
brandcode brandid brandname capacity carauthcode carconfcode cardataupdatetime carid
carlocationresp carmode carname carnameforcar carstatus cartype caruniquecode cardnum
certifino chargdeltmins chargereservationstatus chargestarttime chargestatus chargestoptime
checkhistoryid checktime chrgstatus cinfo city cityid code color community conditionidle
confcode confid confname contactsmobile contactsname containername country countryid
createat createby createtime currentdevicetype currentelectricity cutchpedal cvstate cycid
cycuid data dcstatus dcdcstatusalarm dcdctemperaturealarm dealerid deleted details
devicetime devicetype devices dist distid door drivemotorcontrollertemperaturealarm
drivemotordata drivemotorfaultcodes drivemotorfaultcount drivemotornum
drivemotortemperaturealarm driverdoor driverdoorlock driverseatairstatus driverseatheatstatus
email enginefaultcodes enginefaultcount enginefuelcutoffflag engineno environmentaltemperature
expires_in extendid faceimg factorydate faultcount firestatus fiveauth forwardflag
frontfoglight frontfoglamp funcode geardriveforce gender globalcommentreason globalcommentstate
globaldisablecommentdate globaldisablepostdate globalpostreason globalpoststate gpstime head
heading highbeam highvoltageinterlockstatealarm hood id idcard idcardtype ignitiontime
impassword imuserid img imghandlerid insulatorresistance insulationalarm insurancecompany
insuranceenddate insurancephone iscacar isexperienceofficer isexternalowner ishistorypoi
isinvalidgps isnev isoperation isprivacydrvinghistory isvalidgps issuedate keyalarm keylowpower
lastchecktime lastlogintime lastmaintainmileage lastname lastonlinetime lastupdatedtime lat
leftanteriorwindowdegree leftfrontdoor leftfrontdoorlock leftfrontdoorstatus leftfrontdoorrwindow
leftfronttiretemperature leftreardoor leftreardoorlock leftreardoorstatus leftreardoorrwindow
leftreartiretemperature leftrearwindowdegree leftturnsignal lfpressurewarning lftyrepressure
light lng locationimgactiontime locationimgurl locked lowbeam lrpressurewarning lrtyrepressure
maintainspacemileage materialid maxalarmlevel maxtemperatureprobe maxtemperaturesubsystemnum
maxtemperaturevalue maxvoltagebattery maxvoltagebatterynum maxvoltagebatterysubsystemnum medals
message mintemperatureprobe mintemperaturesubsystemnum mintemperaturevalue minvoltagebattery
minvoltagebatterynum minvoltagebatterysubsystemnum mobile modelcode modelid modelname modulus
motorsystemstatus msg name nevchargesystemtemperaturedtolist nevchargesystemvoltagedtolist
new_flag nickname normalcount oemcompanyid oiltype openid otherfaultcodes otherfaultcount
passengerdoor passengerdoorlock passengerseatairstatus passengerseatheatstatus password
phonenumber pin pinfo platenumber pm25 pm25innnercarvalue pm25outercarvalue point positionlamp
positionlight powerbatterystatus powerlinestatus powerprice powerstatusfeedback producttime
protocolver province provinceid purchaseddate pvstate realnameauthpasstime realnameauthstatus
realnameauthed rearfoglight rearfoglamp rechargeablestoragedevicemismatchalarm
rechargeablestoragedevicesfaultcodes rechargeablestoragedevicesfaultcount recordtime
refreshtoken refresh_token registertime registrationid remainpower remainedpowermile remark
requestid reservationbatteryheatingstatus reservationusevehicletime resultcode rfpressurewarning
rftyrepressure rightanteriorwindowdegree rightfrontdoor rightfrontdoorlock rightfrontdoorstatus
rightfrontdoorrwindow rightfronttiretemperature rightreardoor rightreardoorlock
rightreardoorstatus rightreartiretemperature rightrearwindow rightrearwindowdegree
rightturnsignal riskcount rrpressurewarning rrtyrepressure satnum score scrmid seriescode
seriesid seriesname servertime sex shiftposition shiftpositionstatus shorttermfueltrim sid
sidandmid sidname singlebatteryovervoltagealarm singlebatteryundervoltagealarm smskey soc
sochighalarm socjumpalarm soclowalarm source speed status status_code success sunroof sycid
sycuid sysuserlabelvos systemcode sysuid tel telephone temperature temperaturedifferencealarm
tenantid terminaltime thirdavatar thirdflag thirdnickname thirdopenid thirduid
thumbnaillocationimgurl tiretemperaturestatus token totalcurrent totalodometer totalvoltage trunk
tserviceendtime tservicestarttime tservicestatus tuid turnlndicator turnlndicatorleft
turnlndicatorright uid updateat updateby updatetime userfullname userid userinfo userinfovo
username usernickname usertype uuid validgps vehiclepuredevicetypeovercharge vehiclespeed
vehiclestoragedeviceovervoltagealarm vehiclestoragedeviceundervoltagealarm vehicletemperature
vin wind window xverifydate

# ---- 第二层：数组元素里的键（driveMotorData / nevChargeSystem*DtoList / 消息 / 体检明细）
# 抽取时只到了嵌套一层，而这些键就住在数组元素里 —— 它们同样是**静态报文键**，
# 所以不能漏：Analysis.swift 的电机块原本写 m["Temperature"]，正是这类。
controllerinputvoltage controllertemperature revolutionspeed num controllerdcbuscurrent
length temperature torque state type max_byte_value
currentbatterystartnum batteryvoltage chargesystemvoltage currentbatterycount batterycount
childsystemnum chargesystemcurrent probetemperatures chargetemperatureprobenum
logid devicetime eventactiontime flameoutreason ignitionreason carnum addrname coordtype
readstatus infotypefullpath titleimg infotypeid infostatus jumpparam delflag title content
createdat senderid sendername trackuserid fromsystem updatedat summary new updatedby
realreceiverid infotypename actiontype createdby infotypeimg stubid
checkresultid itemid itemname itemcode description detectvalue mapvalue normalvalue
suggest suggestaction suggestactionurl child
number last numberofelements size totalpages sort
status_code message bind_token new_flag expires_in devices sysuserlabelvos
sidname cardnum isoperation sysuid sycid
""".split())

# 少数全大写 / 含下划线的键：它们的“真实写法”不是「首字母小写」，不能按规则推断
UPPERCASE_KEYS = {"MAX_BYTE_VALUE"}


def suggest(lit):
    """真实键的写法：报文键一律首字母小写（camelCase），所以修法就是把首字母降下来。

    只降首字母、其余原样，是因为**我们无法从扁平化的小写键集合反推内部大写边界**
    （`carname` 反推不出 `carName`）—— 而“首字母大写”恰好是这里唯一的错误形态。
    """
    return lit[0].lower() + lit[1:]


def is_violation(lit):
    if lit in UPPERCASE_KEYS:
        return False
    if not lit[0].isupper():
        return False
    return lit.lower() in API_KEYS

# ci* 家族：自己折叠大小写，因此它们的**实参**键列表是合规的
CI_FAMILY = re.compile(r"\b(?:ci[A-Za-z]*|vnumOf|vnum|ciVal)\s*\(")

# ---- 显式豁免：必须写出理由，输出成 ⚠️ 而不是 ✅ -----------------------------
EXEMPT = {
    # 例：{"CarKeeper/xxx.swift": "为什么这里只能直接下标"},
}

SKIP_DIRS = ("scan/", "scan\\", ".git/")


def swift_files():
    out = []
    base = os.path.join(ROOT, "CarKeeper")
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in filenames:
            if fn.endswith(".swift"):
                out.append(os.path.relpath(os.path.join(dirpath, fn), ROOT).replace("\\", "/"))
    return sorted(out)


# 找到形如 `expr["Key"]` 的**下标**（不是 `call(obj, ["Key"])` 这种实参）
SUBSCRIPT = re.compile(r'(?<![,\s(])\["([A-Za-z_][A-Za-z0-9_]*)"\]')
ARGUMENT = re.compile(r'[,(]\s*\["([A-Za-z_][A-Za-z0-9_]*)"\]')


def is_argument(line, pos):
    """`[` 之前（跳过空格）若是 `,` 或 `(`，说明这是实参键列表，不是下标。"""
    i = pos - 1
    while i >= 0 and line[i] == " ":
        i -= 1
    return i < 0 or line[i] in ",("


def main():
    problems = []
    hints = []
    exempt_used = set()
    print("报文键纪律（大小写敏感的直接下标 = 静默零值）\n")
    print(f"  真实报文键集合：{len(API_KEYS)} 个（来源：2026-09-22 抓包）\n")

    for rel in swift_files():
        if rel.startswith(SKIP_DIRS):
            continue
        try:
            text = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        hits, soft = [], []
        for lineno, raw in enumerate(text.splitlines(), 1):
            code = raw.split("//")[0]
            for m in SUBSCRIPT.finditer(code):
                if is_argument(code, m.start()):
                    continue
                lit = m.group(1)
                if not is_violation(lit):
                    continue
                hits.append((lineno, lit, suggest(lit), raw.strip()))
            for m in ARGUMENT.finditer(code):
                lit = m.group(1)
                if not is_violation(lit):
                    continue
                if CI_FAMILY.search(code):
                    continue
                soft.append((lineno, lit, suggest(lit), raw.strip()))
        if hits:
            if rel in EXEMPT:
                exempt_used.add(rel)
                print(f"  ⚠️  {rel}（已显式豁免）—— {EXEMPT[rel]}")
                print(f"      仍有 {len(hits)} 处直接下标")
            else:
                print(f"  ❌ {rel}")
                for lineno, lit, real, src in hits:
                    print(f"       {rel}:{lineno}  写的是 [\"{lit}\"]，报文键是 \"{real}\"（永远读不到）  {src[:88]}")
                problems.append((rel, hits))
        if soft:
            hints.append((rel, soft))

    print()
    for rel in sorted(set(EXEMPT) - exempt_used):
        print(f"  ⚠️  豁免名单里的 {rel} 已不需要豁免（或文件不存在）—— 这条豁免该删了")

    if hints:
        print("\n⚠️  待确认（字面量键作为**实参**传给 ci* 家族之外的函数 —— 是否折叠大小写取决于被调函数）：")
        for rel, soft in hints:
            for lineno, lit, real, src in soft[:4]:
                print(f"       {rel}:{lineno}  [\"{lit}\"]（报文键 \"{real}\"）  {src[:80]}")
            if len(soft) > 4:
                print(f"       {rel}：另有 {len(soft) - 4} 处")

    if problems:
        print("\n❌ 高嫌疑：")
        for rel, hits in problems:
            print(f"   {rel}：{len(hits)} 处大小写敏感的直接下标 —— 这些键**永远读不到**，"
                  f"读不到就是 nil，而 nil 经过 num() 往往变成 0（界面会显示成一种「正常状态」）")
        print("   合规写法：ciString(obj, [\"DriverDoorLock\"]) / ciNumber(obj, [\"RemainPower\"])")
        print("   若某处**确实**需要直接下标，请写进 scan/keys.py 的 EXEMPT 并说明理由。")
        return 1

    print("\n✅ 报文键只通过 ci* 家族读取（没有大小写敏感的直接下标）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
