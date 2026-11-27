#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
localstore.py —— 本机持久化键的「归属」与「换账号会不会跟着走」

为什么需要它（2026-09-25 第七轮 地毯式对抗式审核，量出来的）：

  `HANDOFF.md` §6 那张表每一行都写着**这条数据是关于「车/人」的，还是关于「这台手机」的**
  （表里叫「归属」）。而 2026-09-25 把「表里标 ✅ 的键」与「`AppStore.logout()` 真的清了
  什么」对了一遍，查出 **8 个标了 ✅ 却没人清**的键：

    · `carkeeper_parking_points`  → 地图「停车」层与「常停热区」显示上一个账号去过的地方
    · `carkeeper_maintenance_photos` → 上一个账号拍的保养单据照新账号看得见
    · `carkeeper_inspections`     → 年检记录跨账号可见（且它有 @Published 内存副本，
                                    只删键的话**同一次运行里**照样看得见）
    · `carkeeper_processed_event_ids` → **清派生却留台账**：`tripHistory` 清了、台账还在，
                                    于是重新登录后那 7 天窗口的行程再也生成不出来（页面一直空）
    · `carkeeper_service_reminders` / `_current_mileage` / `_total_mileage` / `_service_timestamp`
                                  → 里程与保养基线是上一辆车的，「距下次保养」跟着错

  这八条全都不报错、不崩、编译全过，而且**只在换账号/换车时才看得见** ——
  一个人用一台手机一个账号，永远不会发现。前一版 `logout()` 其实已经很认真
  （连 `last_service_mileage` 都清了），漏的原因是**它清的是「记得的那几项」，
  而没有任何一处能回答「一共该清几项」**。这张表就是那一处。

判据（四条，都只认这张表与代码两边的名字）：

  ① 代码里出现的每个 `carkeeper_*` 键都必须在 `HANDOFF.md` §6 的分类表里。
     （新加一个键时，门禁逼你回答「它是关于车的还是关于这台手机的」—— 这正是那个设计决定。）
  ② 标了「账号」的键必须在**退出登录**时被清掉。认三种清法：
     · 键名出现在 `AppStore.logout()` 的函数体里（直接 `removeObject`）；
     · 键名出现在某个 `CLEARERS` 里登记的函数体里，**且那个函数确实被 `logout()` 调用**
       （登记项必须写明理由 —— 与别处的例外表同一个规矩）；
     · 键名出现在 `SETTERS` 里登记的「经 setter 清」名单里，且**证人在 `logout()` 体里出现**
       （`carkeeper_parking_loc` 就是这种：它没有直接的 `removeObject`，
       而 `parkingLocation` 的 setter 在传 nil 时清键）。
  ③ 表里写着的键必须在代码里真的存在。缺了就是**这张表在说谎** ——
     它以前就说过：`carkeeper_art_theme` 随艺术主题删掉之后还在表里。
  ④ 标题里自称的那个数必须等于表的行数（`## 6. …（27 个 carkeeper_* 键）`）。
     这是**同一个事实写在两处**：删功能时表里的行删了，标题里的数字不会自己跟着变
     —— 它错过两次：先写「42」而实际 33（随艺术主题删九套），
     再写「33」而实际 26（2026-09-25 第九轮删「设备与模式」等七个键）。
     一张无法机械对账的清单，一次也没被对过。

为什么是门禁而不是「改一次就好」：这一类的错**没有输出**。清少了不会报错、不会崩，
只会在换账号那天让用户看见别人的东西（或者看不见自己的）。而「记得清」从来不是一种
工程约束。这张表 + 这道门的意思是：**加键的人先给它定性，定性完门禁会盯着清。**

表的格式（改表时照这个写）：分类表必须是 `| 键 | 它是什么 | 归属 | 退出登录清 |` 四列，
**一行一个键、写全名（不许 `_points` 这种简写）**，归属只能是「账号」或「设备」，
最后一列只能是 ✅ 或 ❌（✅ 表示退出登录会清）。

退出码：0 = 表与代码一致；1 = 有键没定性 / 账号键没被清 / 表里有不存在的键 /
标题自称的键数与表行数不一致。
"""

import os
import re
import sys

from _roots import assert_roots

APP = os.path.join("CarKeeper", "CarKeeper")
SERVICES = os.path.join("CarKeeper", "Services")
HANDOFF = os.path.join("CarKeeper", "HANDOFF.md")
LOGOUT_FILE = os.path.join(APP, "AppStore.swift")

TOP_DIRS = [APP, SERVICES]

HEADER = "| 键 | 它是什么 | 归属 | 退出登录清 |"
HEADING = "## 6. 本机持久化清单"

CLEARERS = [
    ("clear", os.path.join(APP, "Services", "HistoryStore.swift"),
     "三条曲线（soc / power / tyre）是账号的车端采样，`clear()` 一起清内存与三个键"),
    ("resetAll", os.path.join(SERVICES, "BillingAndCalendar.swift"),
     "年检记录有 `@Published` 内存副本，只删键的话同一次运行里照样看得见"),
]

SYMBOL_DECL = re.compile(r"(?:static\s+)?(?:let|var)\s+(\w*Key)\s*(?::[^=]+)?=\s*\"(carkeeper_[a-z0-9_]+)\"")

SETTERS = {
    "carkeeper_parking_loc": (
        "parkingLocation = nil",
        "`parkingLocation` 的 setter 在传 nil 时清键（那个 setter 自己的注释写着为什么必须真的清）"),
}

KEY = re.compile(r"carkeeper_[a-z0-9_]+")


def swift_files():
    out = []
    for base in TOP_DIRS:
        if not os.path.isdir(base):
            continue
        for dp, dn, fn in os.walk(base):
            for f in sorted(fn):
                if f.endswith(".swift"):
                    out.append(os.path.join(dp, f).replace("\\", "/"))
    return sorted(out)


def cut_comment(line):
    """砍掉行注释，**保留字符串内容** —— 键就住在字符串字面量里。

    （写这道门时第一版把这个函数写反了：它把字符串内容也丢掉，于是只剩注释里的
      键被数出来 —— 33 个真实键变成 9 个假键。掩码函数本身是本仓一个反复出错的点，
      `extguard.mask` 也在这里留过一根多余的 `/`。）
    """
    i = 0
    in_str = False
    while i < len(line):
        ch = line[i]
        if in_str:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_str = False
            i += 1
            continue
        if ch == '"':
            in_str = True
            i += 1
            continue
        if ch == "/" and i + 1 < len(line) and line[i + 1] == "/":
            return line[:i]
        i += 1
    return line


def body_of(text, signature):
    """返回 `signature` 那个函数的花括号体（按配对扫）。找不到返回 None。"""
    at = text.find(signature)
    if at < 0:
        return None
    i = text.find("{", at)
    if i < 0:
        return None
    depth = 0
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[at:i + 1]
        i += 1
    return None


def parse_table():
    """解析 §6 的分类表。**只认那张四列表**（§6.0 那张「漏掉的键」表也是 `| \\`carkeeper_`
    开头，所以不能满仓库找行 —— 那样会把 5 行说明当成 33 行分类）。"""
    text = open(HANDOFF, encoding="utf-8").read()
    at = text.find(HEADER)
    if at < 0:
        print(f"❌ 在 {HANDOFF} 里找不到分类表头：{HEADER}")
        print("   这张表是本次判据的唯一真值，表头被改掉就等于判据失效。")
        sys.exit(1)
    rows = {}
    order = []
    for line in text[at:].split("\n")[1:]:
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 4:
            continue
        raw_key, _, owner, cleared = cells
        m = re.fullmatch(r"`(carkeeper_[a-z0-9_]+)`", raw_key)
        if not m:
            continue
        key = m.group(1)
        rows[key] = (owner, cleared)
        order.append(key)
    return rows


def heading_count():
    r"""§6 标题里自称的键数（`（27 个 `carkeeper_*` 键）`）。

    读不到就返回 None + 理由：标题被改掉等于这个数字没人管了，那也是一种失真。
    """
    text = open(HANDOFF, encoding="utf-8").read()
    at = text.find(HEADING)
    if at < 0:
        return None, f"在 {HANDOFF} 里找不到 §6 的标题（那句 `{HEADING}`）"
    line = text[at:].split("\n")[0]
    m = re.search(r"（(\d+) 个", line)
    if not m:
        return None, f"§6 的标题里没有「（N 个 ……）」那个数字：{line}"
    return int(m.group(1)), None


def main():
    assert_roots(TOP_DIRS)

    table = parse_table()
    claim, claim_why = heading_count()
    account = {k for k, (owner, _) in table.items() if owner == "账号"}
    device = {k for k, (owner, _) in table.items() if owner == "设备"}
    bad_owner = {k: v[0] for k, v in table.items() if v[0] not in ("账号", "设备")}
    bad_flag = {k: v[1] for k, v in table.items() if v[1] not in ("✅", "❌")}
    marked_account = {k for k, (owner, flag) in table.items() if owner == "账号" and flag == "✅"}
    marked_device = {k for k, (owner, flag) in table.items() if owner == "设备" and flag == "❌"}

    code_keys = {}
    symbol_keys = {}
    symbol_home = {}
    for path in swift_files():
        for n, raw in enumerate(open(path, encoding="utf-8", errors="ignore"), 1):
            code = cut_comment(raw)
            for k in set(KEY.findall(code)):
                code_keys.setdefault(k, []).append(f"{os.path.basename(path)}:{n}")
            for sym, k in SYMBOL_DECL.findall(code):
                symbol_keys.setdefault(sym, set()).add(k)
                symbol_home.setdefault(sym, set()).add(path)

    def keys_cleared_in(body, home):
        """这个函数体里被清的键（含一层符号间接）。

        `home` = 这个体所在的文件：同一个文件里裸名就算，跨文件必须带限定（见 SYMBOL_DECL 注释）。
        """
        out = set(KEY.findall(body))
        for sym, ks in symbol_keys.items():
            if home in symbol_home.get(sym, set()):
                if re.search(r"\b" + re.escape(sym) + r"\b", body):
                    out |= ks
            elif re.search(r"\b[A-Za-z_]\w*\." + re.escape(sym) + r"\b", body):
                out |= ks
        return out

    logout_src = open(LOGOUT_FILE, encoding="utf-8").read()
    logout = body_of(logout_src, "func logout()")
    if not logout:
        print(f"❌ 找不到 `func logout()`（{LOGOUT_FILE}）—— 判据 ② 无从判起")
        return 1

    cleared = keys_cleared_in(logout, LOGOUT_FILE.replace("\\", "/"))
    used_cleaners = []
    for name, path, why in CLEARERS:
        if not re.search(r"\.\s*" + name + r"\s*\(", logout):
            print(f"❌ 登记的清理函数 `{name}()` 没有被 `logout()` 调用（{path}）")
            print(f"   {why}")
            print("   —— 登记的清法必须真的在退出这条路上，否则它只是文档里的一句话。")
            return 1
        src = open(path, encoding="utf-8").read()
        bodies = []
        pos = 0
        while True:
            at = src.find(f"func {name}(", pos)
            if at < 0:
                break
            body = body_of(src[at:], f"func {name}(")
            if body:
                bodies.append(body)
            pos = at + 1
        if not bodies:
            print(f"❌ 登记的清理函数 `{name}()` 在 {path} 里找不到")
            return 1
        for body in bodies:
            cleared |= keys_cleared_in(body, path.replace("\\", "/"))
        used_cleaners.append(f"{name}×{len(bodies)}")

    for key, (witness, why) in SETTERS.items():
        if witness in logout:
            cleared.add(key)
        else:
            print(f"⚠️  {key} 登记为「经 setter 清」，但证人 `{witness}` 不在 `logout()` 体里")
            print(f"   {why}")

    print(f"HANDOFF §6 分类表：{len(table)} 个键（账号 {len(account)} / 设备 {len(device)}）"
          f"，标题自称 {claim if claim is not None else '?'} 个")
    print(f"代码里出现的键：{len(code_keys)} 个")
    print(f"退出登录这条路覆盖的键：{len(cleared)} 个"
          f"（cleaners: {', '.join(sorted(set(used_cleaners))) or '无'}）")

    problems = 0

    if claim_why or claim != len(table):
        problems += 1
        print("\n❌ §6 标题里那个数与表里的行数对不上：")
        if claim_why:
            print(f"   {claim_why}")
        else:
            print(f"   标题写着 {claim} 个，表里实际 {len(table)} 行")
        print("   数字写在两处就会漂（它漂过两次：42→33→标题没跟着变）。")
        print("   改法是改标题里的那个数 —— 或者是删掉这个数字，改判据 ④ 就一起改。")

    if bad_owner:
        problems += 1
        print("\n❌ 归属列只许写「账号」或「设备」：")
        for k, v in sorted(bad_owner.items()):
            print(f"   {k} 写的是「{v}」")
    if bad_flag:
        problems += 1
        print("\n❌ 最后一列只许写 ✅ 或 ❌：")
        for k, v in sorted(bad_flag.items()):
            print(f"   {k} 写的是「{v}」")

    missing = sorted(set(code_keys) - set(table))
    if missing:
        problems += 1
        print(f"\n❌ {len(missing)} 个键在代码里出现，但 §6 那张表没给它定性：")
        for k in missing:
            print(f"   {k}   （{code_keys[k][0]}）")
        print("   加一行到 `HANDOFF.md` §6 的分类表：**关于车/人的写「账号」，")
        print("   关于这台手机的写「设备」** —— 标了账号的门禁会接着盯它被清掉。")

    stale = sorted(set(table) - set(code_keys))
    if stale:
        problems += 1
        print(f"\n❌ {len(stale)} 个键表里有、代码里没有（这张清单在说谎）：")
        for k in stale:
            print(f"   {k}")
        print("   键真的删了 → 从表里删掉，并把它移进「已删除、不要加回来」那段。")

    not_cleared = sorted(marked_account - cleared)
    if not_cleared:
        problems += 1
        print(f"\n❌ {len(not_cleared)} 个「账号」键退出登录时没被清：")
        for k in not_cleared:
            print(f"   {k}")
        print("   换账号后它会跟着走：要么是隐私泄漏（前一个账号的位置/照片/记录），")
        print("   要么是拿上一个账号的数当自己的用（里程基线、保养台账）。")
        print("   清法是三选一（见 `logout()`）：直接 `removeObject`、调一个 `CLEARERS` 里")
        print("   登记过的清理函数、或经 setter 清（登记进 `SETTERS` 并留下证人）。")
        print("   注意：**有内存副本的（@Published）只删键不够** —— 同一次运行里照样看得见。")

    wrongly_kept = sorted(marked_device & cleared)
    if wrongly_kept:
        print(f"\n⚠️  {len(wrongly_kept)} 个「设备」键也被清掉了（不是错，但要确认是有意的）：")
        for k in wrongly_kept:
            print(f"   {k}")

    if problems:
        return 1

    print("\n✅ 每个本机键都有归属，标「账号」的在退出登录时都会被清")
    return 0


if __name__ == "__main__":
    sys.exit(main())
