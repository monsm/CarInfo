#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
免费账号能力纪律检查器 —— 「写了，但没有付费会员就永远用不上」

为什么需要它（真实事故，一串，不是一次）：
  本项目由 **未付费** 的 Apple 个人账号（Personal Team）安装到真机：
  CI 出未签名 IPA → 侧载工具用个人账号重新签名 → 装到手机。

  个人账号能签名，但**配不了一些能力**。我们已经因此删过四轮：
    · `CloudSyncManager`（iCloud/CloudKit）—— 构造容器就抛 ObjC 异常杀进程；
    · `BackgroundTaskManager`（BGTaskScheduler）—— 代码注释自己写着「从未生效」；
    · `CarPlay/` target —— 免费账号无法配置 CarPlay entitlement；
    · `AppClip/` target —— 调用前提是 associated-domains（已删）＋只能走 App Store 分发。

  这类东西的特征很讨厌：**编译通过、门禁全绿、UI 上也看得见入口**，
  只是点下去永远拿不到东西（或直接崩）。它们是「缝合怪」的另一种来源：
  代码里存在一个用户永远用不了的假功能，后来的人还会照着它继续写。

  权威依据：Apple《Supported capabilities (iOS)》
  <https://developer.apple.com/help/account/reference/supported-capabilities-ios>
  表里按 ADP / ADEP / Apple Developer（免费）三档列出每个能力；免费那一档拿不到
  大多数能力。同一页的注记里还写明：**非 ADP 成员可以用 MapKit，但不能提供路线导航**
  （所以 `MKDirections` 也在本检查器的黑名单里）。

判据（四类，全部对着上面那份清单）：
  ① `.entitlements` 里只准出现白名单键。目前只有一项合法的：
     `com.apple.security.application-groups`（小组件/Watch/实时活动共用车况快照）。
     其余任何键（iCloud、aps-environment、healthkit、associated-domains、
     usernotifications.*、in-app-purchase、weatherkit、homekit、nfc、wallet……）
     都是付费专属，或者是已删功能的残留。
  ② `Info.plist` 里不准出现付费能力 / 已删功能留下的键 —— 留着就是在说一件不存在的事。
  ③ 源码里不准 import / 调用付费能力：CloudKit、HealthKit、WeatherKit、StoreKit、
     PassKit、HomeKit、GameKit、NetworkExtension、SensorKit、MusicKit、CoreNFC、
     Sign in with Apple、App Attest、Family Controls、APNs 注册、MKDirections、
     BGTaskScheduler、critical/time-sensitive 通知……
  ④ `project.yml` 的 target 清单只准是这四个 + 测试：CarKeeper / WidgetBundle /
     WatchApp / WatchKitApp / CarKeeperTests。AppClip / CarPlay 不许回来。

  另外一条纪律（不是能力问题，但同一类）：**App Group 的读取点必须有兜底**。
  免费账号的签名流程可能把这份 entitlement 摘掉 —— 那时 `UserDefaults(suiteName:)`
  返回 nil。有兜底（`?? .standard` 或 `guard let ... else`）时只是小组件显示占位；
  没有兜底就是崩溃。本项目的读取点全部带兜底，这条守住它。

退出码：0 = 没有付费专属能力；1 = 有（或扫描失败）。
"""

import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCAN_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    "CarKeeper/Models",
    "CarKeeper/Design",
    "CarKeeper/Shared",
    "CarKeeper/Widgets",
    "CarKeeper/WatchApp",
]

# 合法 entitlement：允许的键 -> 为什么它在这里
ENTITLEMENT_ALLOWED = {
    "com.apple.security.application-groups":
        "小组件 / Watch / 实时活动共用车况快照；读取点全部有兜底，"
        "签名流程摘掉它时只是显示占位，不会崩",
}

# Info.plist 里禁止的键 -> 为什么
PLIST_BANNED = {
    "UIBackgroundModes": "后台模式（后台刷新那套代码已删）",
    "BGTaskSchedulerPermittedIdentifiers": "BGTaskScheduler（免费账号没有该能力）",
    "NSHealthShareUsageDescription": "HealthKit 用途说明（读健康数据的代码已删）",
    "NSHealthUpdateUsageDescription": "HealthKit 用途说明（写健康数据的代码已删）",
    "CKCloudKitEnabled": "CloudKit 残留开关（同步那套代码已删）",
    "NSAppClip": "App Clip 已删",
    "aps-environment": "远程推送（ADP 专属）",
    "com.apple.developer.weatherkit": "WeatherKit（ADP 专属；天气已改用 Open-Meteo）",
    "com.apple.developer.healthkit": "HealthKit（已删）",
    "com.apple.developer.icloud-container-identifiers": "iCloud（已删）",
}

# 源码里禁止的 import -> 能力
BANNED_IMPORTS = {
    "cloudkit": "iCloud/CloudKit（ADP 专属）",
    "healthkit": "HealthKit（需注册能力）",
    "weatherkit": "WeatherKit（ADP 专属；天气用 Open-Meteo）",
    "storekit": "In-App Purchase（ADP 专属）",
    "passkit": "Wallet / Apple Pay（ADP 专属）",
    "homekit": "HomeKit（ADP 专属）",
    "gamekit": "Game Center（ADP 专属）",
    "networkextension": "Network Extensions（ADP 专属）",
    "sensorkit": "SensorKit（需单独申请）",
    "musickit": "MusicKit（需注册能力）",
    "corenfc": "NFC 读卡（ADP 专属）",
    "devicecheck": "DeviceCheck / App Attest（ADP 专属）",
    "authenticationservices": "Sign in with Apple（ADP 专属）",
    "familycontrols": "Family Controls（需单独申请）",
    "deviceactivity": "DeviceActivity（需单独申请）",
    "managedsettings": "ManagedSettings（需单独申请）",
    "backgroundtasks": "BGTaskScheduler（已删）",
    "pushkit": "PushKit（ADP 专属）",
}

# 源码里禁止的 API -> 为什么
BANNED_APIS = {
    r"registerForRemoteNotifications": "远程推送注册（ADP 专属；本地通知才是免费的）",
    r"didRegisterForRemoteNotifications": "远程推送回调（ADP 专属）",
    r"MKDirections": "MapKit 路线导航 —— Apple 明说非 ADP 成员不能提供导航方向",
    r"BGTaskScheduler": "后台任务调度（已删）",
    r"CKContainer|CKDatabase|CKRecord": "CloudKit 容器（构造即抛异常）",
    r"HKHealthStore": "HealthKit 存储（已删）",
    r"interruptionLevel\s*[:=]\s*\.(critical|timeSensitive)":
        "critical / time-sensitive 通知（需注册能力，ADP 专属）",
    r"SKPaymentQueue|SKProduct": "内购（ADP 专属）",
    r"NSUbiquitousKeyValueStore": "iCloud 键值存储（已删）",
    r"requestAlwaysAuthorization": "常驻定位（需要 background location 能力）",
    r"beginBackgroundTask": "后台执行申请（在侧载 + 免费账号下拿不到时间片）",
}

ALLOWED_TARGETS = {"CarKeeper", "WidgetBundle", "WatchApp", "WatchKitApp", "CarKeeperTests"}

APP_GROUP = re.compile(r"UserDefaults\(suiteName:")
APP_GROUP_FALLBACK = re.compile(r"\?\?|else")


def read(path):
    with open(os.path.join(PROJECT_ROOT, path), encoding="utf-8", errors="ignore") as fh:
        return fh.read()


def in_scope(rel):
    """把它排除掉，不是因为它们不重要，而是因为它们**不该被当前纪律追着改**：

      · `scan/baseline/**` 是**冻结的旧树快照**（`scan.py` 拿它做名字解析基线）——
        它是某个历史提交的复印件，不参与编译，里面当然还留着 healthkit /
        associated-domains 这些当年还没清掉的东西；
      · `scan/**` 是检查器自身；
      · `.git/**` 是仓库内部。

    第一次跑这条检查器就是被 baseline 快照误伤的（它报了 5 处“残留”，
    而那 5 处正是我们当初要删的东西 —— 删对了，只是不该由这份复印件来记。）。
    """
    rel = rel.replace(os.sep, "/")
    return not (rel.startswith("scan/") or rel.startswith(".git/"))


def swift_files():
    out = []
    for d in SCAN_DIRS:
        root = os.path.join(PROJECT_ROOT, d)
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            for f in filenames:
                if f.endswith(".swift"):
                    rel = os.path.relpath(os.path.join(dirpath, f), PROJECT_ROOT)
                    if in_scope(rel):
                        out.append(rel.replace(os.sep, "/"))
    return sorted(set(out))


def all_files(suffixes):
    out = []
    for dirpath, _, filenames in os.walk(PROJECT_ROOT):
        if "/.git" in dirpath or dirpath.endswith("/.git"):
            continue
        for f in filenames:
            if any(f.endswith(s) for s in suffixes):
                rel = os.path.relpath(os.path.join(dirpath, f), PROJECT_ROOT)
                if in_scope(rel):
                    out.append(rel.replace(os.sep, "/"))
    return sorted(set(out))


def scan_entitlements(problems):
    files = all_files([".entitlements"])
    keys = 0
    for rel in files:
        text = read(rel)
        for m in re.finditer(r"<key>([^<]+)</key>", text):
            key = m.group(1)
            keys += 1
            if key not in ENTITLEMENT_ALLOWED:
                problems.append((rel, f"① entitlement `{key}` 不在白名单里",
                                 "免费账号配置不了它；如果确实已不需要，删掉这一项"))
    return files, keys


def scan_plist(problems):
    files = all_files(["Info.plist"])
    for rel in files:
        text = read(rel)
        for key, why in PLIST_BANNED.items():
            if f"<key>{key}</key>" in text:
                problems.append((rel, f"② Info.plist 里有 `{key}`", why))
    return files


def scan_sources(problems):
    files = swift_files()
    for rel in files:
        for i, raw in enumerate(read(rel).splitlines(), 1):
            line = raw.split("//")[0]
            low = line.lower()
            for name, why in BANNED_IMPORTS.items():
                if re.search(r"^\s*import\s+%s\b" % name, low):
                    problems.append((f"{rel}:{i}", f"③ `import {name}`", why))
            for pat, why in BANNED_APIS.items():
                if re.search(pat, line):
                    problems.append((f"{rel}:{i}", f"③ `{pat}`", why))
            if APP_GROUP.search(line) and not APP_GROUP_FALLBACK.search(line):
                problems.append((f"{rel}:{i}", "④ App Group 读取没有兜底",
                                 "签名流程可能摘掉这份 entitlement，那时 suiteName 返回 nil —— "
                                 "写 `?? .standard` 或 `guard let … else`"))
    return files


def scan_targets(problems):
    text = read("CarKeeper/project.yml")
    block = re.search(r"(?ms)^targets:\n(.*?)(?=^\S|\Z)", text)
    if not block:
        problems.append(("CarKeeper/project.yml", "找不到 targets: 段", "路径或写法变了？"))
        return set()
    names = set(re.findall(r"(?m)^  ([A-Za-z][A-Za-z0-9_]*):\s*$", block.group(1)))
    for n in sorted(names - ALLOWED_TARGETS):
        problems.append(("CarKeeper/project.yml", f"④ target `{n}` 不在白名单里",
                         "免费账号配不了它需要的能力（AppClip / CarPlay 就是这么删的）"))
    return names


def main():
    problems = []
    ent_files, ent_keys = scan_entitlements(problems)
    plist_files = scan_plist(problems)
    src_files = scan_sources(problems)
    targets = scan_targets(problems)

    print("免费账号能力纪律（Apple《Supported capabilities (iOS)》的免费那一档）")
    print(f"  · entitlements {len(ent_files)} 份，{ent_keys} 个键（白名单 {len(ENTITLEMENT_ALLOWED)}）")
    print(f"  · Info.plist {len(plist_files)} 份（禁 {len(PLIST_BANNED)} 个键）")
    print(f"  · Swift 源码 {len(src_files)} 个（禁 {len(BANNED_IMPORTS)} 个 import、"
          f"{len(BANNED_APIS)} 类 API）")
    print(f"  · target {len(targets)} 个：{' / '.join(sorted(targets))}")

    if problems:
        print("\n❌ 发现免费账号用不了的东西：\n")
        for where, what, why in problems:
            print(f"   {where}")
            print(f"      {what} —— {why}")
        print("\n   两种修法：删掉它（多数情况，用户永远用不上）；"
              "\n   或者给出「免费账号下也能工作」的实现（例：天气从 WeatherKit 换 Open-Meteo）。")
        return 1

    print("\n✅ 没有付费会员专属能力（entitlements / Info.plist / 源码 / target 四处一致）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
