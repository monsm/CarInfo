#!/usr/bin/env python3
"""scenes.py — 多窗口/分屏接线门禁（#47）

拦的是「静默无反应」型故障：编译通过、运行不崩，只是点了按钮什么都没有。

  1. `openWindow(id: X)` 的 X 找不到对应场景声明（`WindowGroup(id:)` / `Window(id:)`）
     → 系统不知道要开哪个场景，什么都不发生。
  2. 有 openWindow 调用，但 Info.plist 没声明
     `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes = true`
     → 系统按「app 不支持多场景」直接拒绝，同样什么都不发生。
     （注意必须嵌在 UIApplicationSceneManifest 里；写成顶层键系统读不到。）
  3. `UIRequiresFullScreen: true` 仍在 → 明确让 iPad app 退出多任务与动态缩放，
     而该键已于 iOS 26.0 被弃用（TN3192），与多窗口目标直接冲突。

用法：
    python scan/scenes.py [--root DIR]
"""
import re
import sys
import pathlib

ROOT = pathlib.Path('.')
if '--root' in sys.argv:
    ROOT = pathlib.Path(sys.argv[sys.argv.index('--root') + 1])

# project.yml 在 CarKeeper/ 下（不是仓库根）—— 这是 xcodegen 的工作目录
YML = ROOT / 'CarKeeper' / 'project.yml'

# 不参与扫描的目录：构建产物与检查器自身
SKIP_DIRS = {'scan', 'DerivedData', '.git', '.selftest'}

problems = []


# ---------------------------------------------------------------- 常量与场景声明

def swift_files():
    """仓库内所有 Swift 文件。跳过目录按「相对 ROOT 的第一段」判定 ——
    按绝对路径段判定会让 --root 指向的目录自己叫 scan/.selftest 时整棵树被跳过。"""
    out = []
    for p in ROOT.rglob('*.swift'):
        rel = p.relative_to(ROOT)
        if rel.parts and rel.parts[0] in SKIP_DIRS:
            continue
        out.append(p)
    return sorted(out)


# SceneID 之类的场景标识常量：enum SceneID { static let detail = "detail" }
consts = {}
for f in swift_files():
    text = f.read_text(encoding='utf-8', errors='replace')
    for block in re.findall(r'enum\s+SceneID\s*\{(.*?)\n\}', text, re.S):
        consts.update(dict(re.findall(r'static\s+let\s+(\w+)\s*=\s*"([^"]*)"', block)))

# 场景声明：WindowGroup(id: X) / Window(id: X)
scenes = []
# 打开调用：openWindow(id: X)
opens = []


def resolve_arg(arg):
    """把 id 表达式解析成字符串值。返回 (值, 是否确定)。"""
    arg = arg.strip()
    lit = re.match(r'^"([^"]*)"$', arg)
    if lit:
        return lit.group(1), True
    ref = re.match(r'^SceneID\.(\w+)$', arg)
    if ref:
        name = ref.group(1)
        if name in consts:
            return consts[name], True
        return f'SceneID.{name}', False
    return arg, False


for f in swift_files():
    rel = f.relative_to(ROOT)
    text = f.read_text(encoding='utf-8', errors='replace')
    for lineno, line in enumerate(text.splitlines(), 1):
        if line.lstrip().startswith('//'):
            continue
        for m in re.finditer(r'\b(WindowGroup|Window)\s*\(\s*id:\s*([^)]+?)\s*\)', line):
            val, certain = resolve_arg(m.group(2))
            scenes.append((str(rel), lineno, val, certain, m.group(1)))
        for m in re.finditer(r'\bopenWindow\s*\(\s*id:\s*([^)]+?)\s*\)', line):
            val, certain = resolve_arg(m.group(1))
            opens.append((str(rel), lineno, val, certain))

declared_ids = {s[2] for s in scenes}

for path, lineno, val, certain in opens:
    if not certain:
        problems.append(f'{path}:{lineno} 无法静态解析的 id 表达式「{val}」—— '
                        f'请用字符串字面量或 SceneID 常量，否则这条门禁管不到它')
    elif val not in declared_ids:
        problems.append(f'{path}:{lineno} openWindow(id: "{val}") 找不到对应场景声明 '
                        f'（现有：{sorted(declared_ids) or "无"}）→ 点击不会有任何反应')


# ---------------------------------------------------------------- Info.plist 多场景声明

def yaml_props():
    if not YML.is_file():
        return None
    try:
        import yaml
    except ImportError:
        return None
    try:
        d = yaml.safe_load(YML.read_text(encoding='utf-8'))
        return d['targets']['CarKeeper']['info']['properties']
    except Exception:
        return None


if not YML.is_file():
    problems.append(f'找不到 {YML} —— 路径不对，门禁什么都没查（不要把它当成通过）')

props = yaml_props()
if props is not None:
    source = 'project.yml'
    manifest = props.get('UIApplicationSceneManifest')
    multi = manifest.get('UIApplicationSupportsMultipleScenes') if isinstance(manifest, dict) else None
    full_screen = props.get('UIRequiresFullScreen')
else:
    # 无 pyyaml / 解析失败时的文本兜底
    source = f'{YML}（文本兜底）'
    text = YML.read_text(encoding='utf-8') if YML.is_file() else ''
    block = re.search(r'UIApplicationSceneManifest:\s*\n((?:[ \t]+.*\n)+)', text)
    multi = None
    if block and re.search(r'UIApplicationSupportsMultipleScenes:\s*true', block.group(1)):
        multi = True
    full_screen = bool(re.search(r'^[ \t]+UIRequiresFullScreen:\s*true', text, re.M))
    if text and not block:
        problems.append(f'{source} 找不到 UIApplicationSceneManifest 键 —— '
                        f'UIApplicationSupportsMultipleScenes 必须是它的子键，裸顶层键系统读不到')

if opens and multi is not True:
    problems.append(f'{source}: 存在 {len(opens)} 处 openWindow 调用，但 '
                    f'UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes 不是 true → '
                    f'系统会以「app does not support multiple scenes」拒绝开窗（静默无反应）')

if full_screen:
    problems.append(f'{source}: UIRequiresFullScreen 仍为 true —— 它让 iPad app 退出多任务与动态缩放，'
                    f'与该键配套的多窗口目标冲突，且已于 iOS 26.0 被弃用（TN3192）')


# ---------------------------------------------------------------- 报告

print(f'扫描 {len(swift_files())} 个 Swift 文件')
print(f'场景声明 {len(scenes)} 处' + (f'（{sorted(declared_ids)}）' if scenes else '（无）'))
print(f'openWindow 调用 {len(opens)} 处' +
      (f'（{", ".join(f"{p}:{l}" for p, l, _, _ in opens)}）' if opens else '（无）'))
if scenes and not opens:
    print('  ℹ️ 有场景声明但没有任何打开入口 —— 场景注册了却无法被打开')
print(f'多场景声明（{source}）: UIApplicationSupportsMultipleScenes = {multi}')

if problems:
    print()
    for p in problems:
        print(f'  ❌ {p}')
    sys.exit(1)

print()
print('✅ 分屏接线自洽（每个 openWindow 都有对应场景，且 plist 已声明多场景、未退出多任务）')
