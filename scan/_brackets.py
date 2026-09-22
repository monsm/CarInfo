#!/usr/bin/env python3
"""括号配平（临时工具）：去掉字符串与注释后统计 (), {}, [] 是否成对。"""
import io
import sys

FILES = [
    "CarKeeper/CarKeeper/Models/ViewModels.swift",
    "CarKeeper/CarKeeper/Models/Analysis.swift",
    "CarKeeper/CarKeeper/Models/ApiModels.swift",
    "CarKeeper/CarKeeper/Features/Battery/BatteryView.swift",
    "CarKeeper/CarKeeper/Features/Map/MapSpineData.swift",
    "CarKeeper/CarKeeper/Features/Dev/DevView.swift",
    "CarKeeper/CarKeeper/AppStore.swift",
    "CarKeeper/AppClip/AppClipEntrance.swift",
]

BS = chr(92)
QUOTE = '"'


def strip(src):
    out = []
    i, n, in_str = 0, len(src), False
    while i < n:
        c = src[i]
        if in_str:
            if c == BS:
                i += 2
                continue
            if c == QUOTE:
                in_str = False
            out.append(" ")
            i += 1
            continue
        if c == QUOTE:
            in_str = True
            out.append(" ")
            i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            out.append("\n")
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i += 2
            out.append(" ")
            continue
        out.append(c)
        i += 1
    return "".join(out)


def main():
    bad = 0
    for f in FILES:
        s = strip(io.open(f, encoding="utf-8").read())
        res = dict((k, s.count(k)) for k in "(){}[]")
        ok = res["("] == res[")"] and res["{"] == res["}"] and res["["] == res["]"]
        print(("OK  " if ok else "BAD ") + f, res)
        if not ok:
            bad = 1
    if bad:
        print("括号不配平")
        return 1
    print("全部配平")
    return 0


if __name__ == "__main__":
    sys.exit(main())
