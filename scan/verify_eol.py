#!/usr/bin/env python3
"""提交前的安全闸：逐个文件确认「工作区 vs HEAD 只差换行表示」。

判定口径：把 CR / LF / CRLF / CRCRLF 统一按一个换行折叠后比较。
折叠后不一致 ⇒ 内容真的改了（应该只有本轮手工改过的那几个文件）。
"""
import re
import subprocess
import sys
import pathlib

REPO = pathlib.Path(".")


def collapse(b):
    t = b.decode("utf-8", "replace")
    t = re.sub(r"\r+\n", "\n", t)
    return re.sub(r"\r", "\n", t)


def tracked():
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD"],
                         cwd=REPO, capture_output=True, text=True, check=True).stdout
    return [f for f in out.split("\n") if f.endswith(".swift")]


def main():
    only_eol, real, missing = [], [], []
    for rel in tracked():
        fp = REPO / rel
        if not fp.exists():
            missing.append(rel)
            continue
        head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=REPO,
                              capture_output=True).stdout
        if collapse(head) == collapse(fp.read_bytes()):
            only_eol.append(rel)
        else:
            real.append(rel)
    print(f"=== 只差换行（可以安全提交）: {len(only_eol)} 个 ===")
    print(f"=== 内容真有改动: {len(real)} 个 ===")
    for r in real:
        print("   •", r)
    if missing:
        print(f"=== 工作区缺失: {len(missing)} 个 ===")
        for r in missing:
            print("   ?", r)
    print("\n预期：内容有改动的应当恰好是本轮修过的那几个文件。")


main()
