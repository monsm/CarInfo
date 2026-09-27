#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
删声明守卫 —— 「声明被删掉/重写了，使用还在」

为什么需要它（三次真实事故；前两次各占了一整轮 macOS runner，第三次是在推上去之前
被本文件当场拦下的）：

  ① `e78a344`（DSSwipeStrip）：撤掉 `pv` 状态时顺手把 `pvValue(_:gap:)` 函数本体也删了，
     5 处调用（透镜跟手、行跟手、吸附反算）还在 —— 3 条
     `error: cannot find 'pvValue' in scope`。
  ② `55794c4`（ArcStack）：重写 `shapeScroll` 的注释时把**声明本身**写没了，
     3 处使用（形变阈值、拖动跟手、落点）还在 —— 同样 3 条
     `error: cannot find 'shapeScroll' in scope`。
  ③ 2026-09-24（消息窗口）：`messageWeeks` 的声明在 `API.swift` 里被 `messageDays` /
     `messageSliceDays` 替掉，而 `MessagesSection.swift` 里 3 处使用还在。

  三次都不是拼错名字，也不是缺类型：名字在**旧版本**里明明声明过，只是这一轮的编辑
  把它连同注释一起重写掉了。既有的检查器全都看不见这一类：
    · `scan.py` 查「用了但项目里没声明」——它看的是**当前**这一份代码，
      而这一份里确实没有这个名字，于是它把「没有声明」当成「SDK 提供」；
    · `scopeguard.py` 查跨作用域的静态成员调用，不管成员存不存在；
    · `orphans.py` 查「声明了但没人用」——正好是反方向。
  唯一能看见它的是编译器，而编译器住在按 10 倍计费的 macOS runner 上。

判据（只收窄到能给出确定结论的一条）：

  对每个源文件，取**旧版本**（默认 `HEAD~1`，拿不到就 `HEAD`）与**新版本**（工作区）：

  ① 旧版本里 **成员级**声明过这个名字（缩进 ≤ 4 空格的 `let` / `var` / `func` ——
     类型自己的属性、方法、`@State` 之类；函数体里的局部量缩进更深，不算）；
  ② 新版本里**没有**任何同名成员级声明；
  ③ 新版本里这个名字**还在代码里出现**（`//`、`///`、`/* */` 里的提及不算；
     把它当局部量声明的那些行也不算 —— 那种情况下它解析到局部量，编译得过）。

  三条同时成立 = 「这条声明被删了，但还有人调用它」。Swift 里这是编译错误，
  没有例外 —— 所以这里直接失败，而不是警告。

  ③ 的消息也在同一个文件里吗？不在 —— `messageWeeks` 声明在 `API.swift`、
  使用在 `MessagesSection.swift`。所以「使用」那一半必须**跨文件**看，
  否则本文件会从自己的盲区旁边走过去（2026-09-24 本地实测：三条判据全成立，
  却因为只在同文件里找使用而报了绿）。它当场被补成了双向：
    · 声明所在文件：无前缀的裸名字也算（同一类型 / 同文件的写法）；
    · **其它**文件：只认带前缀的用法（`APIClient.messageWeeks` / `nav.openMode`）——
      裸名字跨文件极易撞上局部量（另一个函数里的 `let`），而一条误报就会让人
      开始绕过这个门禁。

  另加一道**降噪**：如果这个名字在新版本的**其它文件**里被成员级声明了，就不报。
  它对应真实的一类编辑：把几个成员从骨架文件挪进内容文件（`2f088df` 把三个图层内容
  从 `MapSpineView` 挪进 `MapSpineLayers`）——同一个类型的 extension 在另一个文件里，
  调用照旧编译得过。代价是「同名成员真的落在别的类型上」这种错会漏（宁可漏，不可噪：
  一条误报就会让人开始绕过这个门禁）。

  旧版本取哪一个，看工作区干不干净（这一点是被一次**假绿**逼出来的）：

    · 工作区干净（CI 上就是这样，工作区**就是** HEAD）→ 比 `HEAD~1`：
      它看的是「这次提交改掉了什么」。代价是 checkout 要 `fetch-depth: 2`
     （见 `.github/workflows/ios-build.yml`）。
    · 工作区有改动（本地）→ 比 **`HEAD`**：手上这份改动就是**未来的那一笔**，
      而它的父提交是 HEAD，所以「旧版本」正是 HEAD。

  为什么后者非改不可：`messageWeeks` 在 `f6ff0e8`（= HEAD）里才引入，
  下手把它的声明删了、三处使用还在 —— 而拿 `HEAD~1` 当旧版本时，
  那个名字在 `HEAD~1` 里**根本不存在**，判据 ① 不成立，于是本地一片绿，
  只有编译器看得见。这正是本文件要防的那一类错误，它却从本文件旁边走了过去。
  两个模式都打印「旧版本取的是谁、为什么」，不让它默默退回去。

  2026-09-25 的假阳性（两条收窄就是这么来的）：删掉 `StackMetrics.padTop/padBottom`
  （自管排版时代的死字段）时，它报了三处用法 —— 全部是**另一个类型**的同名成员：
  `CardFit.Row.padTop/padBottom`（嵌套类型，缩进 8）与 `StackSpec.Card.padTop`。
  两处都不该报，而「名字一样」正是这个守门人无法自行分辨的东西。于是各加一条收窄：

  ④ **使用处所在的文件**自己就声明了同名成员 → 不报（`CardFit.swift` 里
     `self.padTop = padTop` 那两行）。判据 ① 的 `global_new` 只看缩进 ≤ 4 的声明，
     而嵌套类型在 8 —— 同一条道理，只是把「本文件」也算进来看。
  ⑤ 嵌套类型前缀：`A.B.name` 里紧挨着名字的那一段若是**项目里声明过的类型**
     （`StackSpec.Card.padTop` 里的 `Card`）→ 不报。它是**另一个类型**的成员；
     而 `APIClient.messageWeeks`（一段）与 `APIClient.shared.messageWeeks`
     （`shared` 不是类型）照旧报 —— 历史那三次都在后两种形状里。

  两条都是「宁可漏，不可噪」那一侧的：一条误报就足以让人开始绕过这个门禁。

  2026-09-26 的第三条假阳性（判据 ⑦）：
  删掉 `Design/DSGlass.swift` 里那个只为读 `@Environment` 而存在的泛型 `View` 包装
  （`DSGlassSurface`）时，它那两个存储属性 `variant` / `interactive` 跟着一起没了 ——
  而同一个函数 `dsGlass(in:variant:interactive:hairline:)` 的**形参**一直叫这两个名字
  （它们的缩进是 8，`MEMBER_DECL` 只认 ≤ 4，于是「新版本里没有声明」这一条被误判）。
  本文件把三行报成了编译错误，而它们本来就有一个声明：函数签名里那一行。
  **形参是声明**，这一点不该由缩进来决定 —— 所以补一条收集器，并把它接在判据 ④
  那一侧：**使用处所在的文件**自己声明了同名的形参 → 不报。
  （没接在 `global_new` 上：那一侧是全项目的「有声明就不报」，而形参的名字与类型名
    一样常见（`style` / `pad` / `row`），放进去会把这一类真错永远遮住。）

  2026-09-26 的第四条假阳性（判据 ⑧）：「完全删除文字发光」那一轮把 `TokensHalo`
  整个删掉，而它里面有一个成员叫 `scale` —— 新版本里唯一还在用 `scale` 的地方是
  `CarModelView` 的 `body.scale = […]`（`body` 是一个 RealityKit 实体，
  `Entity.scale` 是**系统的**成员）。本文件把一个同名（而已）的成员当成了
  「项目里被删的那个」。
  于是补一条：**这个名字同时是苹果 SDK 的符号名（`scan/sdk_cache.json`），
  而每一条使用都是 `小写值.name`（`body.scale`）→ 不报**。
  为什么必须同时满足两条：只有前者的话，几乎每个短名字都是 SDK 名（那张表是整个
  SDK 的符号），会把真错遮光；只有后者的话，一个叫 `foo.scale` 的项目成员被删
  （`foo` 是项目类型的一个**值**）也会漏。两条一起，命中面就只剩
  「这个名字属于某个我们叫不出类型的值」——而那正是本门禁无从判定的东西。

  自测（同一轮实测）：删 `TokensHalo.scale` → 必须**不**报；
  反面：删 `StackSpec.Card.padBottom` → 必须**报**（它的使用带项目类型前缀）。

  2026-09-25 的第二条假阳性（判据 ⑥，同一天加的）：删掉 `MapCarPin.style` /
  `MapSpotPin.style`（车钉那三套艺术样式的选择器）时，它报了六处用法 ——
  全部是**参数标签**：`RoundedRectangle(cornerRadius: 3, style: .continuous)`、
  `stroke(…, style: StrokeStyle(…))`。参数标签解析的是**被调用者的**参数名，
  与「这个名字的成员」没有关系，而 `style` 是系统 API 里最常见的参数名之一。
  于是：**一行里这个名字的每一次出现都是「紧跟 `:`，且前面是 `(` / `,` 或者整行只有缩进」
  的形状 → 不算使用**（后半句管多行调用的续行：`style: StrokeStyle(…)` 自己占一行，
  它前面没有 `(`）；只要有一处是真正的成员访问（`x.style` / `style = …`）照旧报。

自测（2026-09-25 重新实测过 —— 原来那两条 `--from/--to` 命令是**恒绿**的：
两个名字在旧版里的声明缩进都比 4 深，判据 ① 当场就找不到它们。
所以换成两条**今天真能跑**的探针：把某个成员声明删掉，必须当场报出来）：

  删 `CarKeeper/Design/ArcStack.swift` 里的 `focusInset`  -> 必须报 focusInset
  删 `CarKeeper/Design/StackSpec.swift` 里的 `tiltDeg`      -> 必须报 tiltDeg

  反面（判据 ④/⑤）：删 `StackSpec.Card.padBottom`（它有同名成员在别的类型上）
  -> 必须**不**报 —— 它在 2026-09-25 之前会报（两条收窄就是为它加的）。
  反面（判据 ⑥）：删 `MapCarPin.style`（它有六处参数标签同形）
  -> 必须**不**报 —— 它在 2026-09-25 之前会报六处 `style:`（系统 API 的标签）。
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 报告范围：编进 App 主 target 的源码目录（与 scan/anorphans.py 同一套）
SCOPE_DIRS = [
    "CarKeeper/CarKeeper",
    "CarKeeper/Services",
    #  顶层 `CarKeeper/Models` 已删（2026-09-26）。它下面的 `os.walk` 对不存在的目录
    #  不报错 —— 那就是这份清单最容易变成“恒为 0 的绿灯”的地方。
    "CarKeeper/Design",
]

# 苹果 SDK 的符号名（含成员）。判据 ⑧ 的输入 —— 它只用来把「名字本来就是 SDK 的
# 一个成员」这一种从误报里摘出去（见文件头那一段）。
SDK_CACHE = os.path.join(PROJECT_ROOT, "scan", "sdk_cache.json")


# 成员级声明：缩进 ≤ 4 空格，且行内有 let / var / func + 名字。
# 为什么卡缩进：函数体里的局部量缩进 ≥ 8，把它当成「声明」会让判定立刻失真
#（局部量被改名、成员还在，是最常见的一类假阳性）。
#
# 2026-09-25：修饰符表里原来只有裸词，`private(set) var image` 这种**带括号的**
# 修饰符一个都认不出来 —— 于是把成员从 `var image` 收窄到 `private(set) var image`
# （同一次改动里只动了可见性）会被判成「声明没了、使用还在」的编译错误。
# 这是真漏报的反面：**假阳性**，而假阳性会让守门人学会忽略这条门。
# 括号形式排在裸词前面只是可读性；正则回溯保证两者都能匹配。
# 成员声明前的修饰符。拆成一个常量是为了让括号配对一个头两个大：
# 这份名单里的 `private(set)` 自己带括号，直接摆进上面那条正则里时，
# 人眼很难看出到底少了/多了哪一对。
MODIFIER = (r"(?:public|internal|private|fileprivate)(?:\(set\))?"
            r"|open|final|static|class|lazy|nonisolated|weak|unowned"
            r"|override|mutating")

MEMBER_DECL = re.compile(
    r"^ {0,4}(?:@[A-Za-z_][\w.]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:" + MODIFIER + r")\s+)*"
    r"(?:let|var|func)\s+([A-Za-z_]\w*)\b",
    re.M,
)

# 「这个字出现在这一行」用词边界；短名字（< 5）不查 —— 它们太容易撞上局部量
#（`nav` / `row` 这类），收窄的代价是漏掉极短的成员，收益是零误报（scopeguard 同一条取舍）。
MIN_NAME_LEN = 5

# 把它当**局部量**声明的行：`let x =` / `if let x` / `for x in` / `guard var x` …
LOCAL_BINDING = r"(?:let|var|for)\s+%s\b"


def run_git(args):
    """跑一条 git 命令；失败返回 None（浅克隆里 HEAD~1 不存在就是这种情况）。"""
    try:
        p = subprocess.run(["git"] + args, cwd=PROJECT_ROOT,
                           capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
    except OSError:
        return None
    return p.stdout if p.returncode == 0 else None


def strip_comments(text):
    """去掉 `/* */`、`//`、`///` —— 注释里提到某个名字不是编译错误。

    ⚠️ 只做「文档与注释不算」这一件事，不碰字符串：字符串插值里用了一个被删的名字
    同样是编译错误，所以字符串**照查**。
    """
    text = re.sub(r"/\*(?:.|\n)*?\*/", "", text)
    text = re.sub(r"(?m)//.*$", "", text)
    return text


def member_names(text):
    """这个文件里成员级声明的名字（去注释后，只看缩进 ≤ 4 的 let/var/func）。"""
    return set(MEMBER_DECL.findall(strip_comments(text)))


def only_argument_labels(line, name):
    """这一行里这个名字的每一次出现都是**参数标签**形状吗（至少出现一次）。

    判据 ⑥。参数标签（`f(style: …)` / `f(a: 1, style: …)`）解析到的是**被调用者**
    的参数名，不是这个名字的成员 —— 所以它不是「使用」。只要有一处不是这种形状
    （`x.style`、`.style = …`、裸 `style`），整行就仍算使用（宁可漏，不可噪）。
    """
    hits = list(re.finditer(r"\b%s\b" % re.escape(name), line))
    if not hits:
        return False
    for m in hits:
        before, after = line[:m.start()], line[m.end():]
        # 标签的形状：紧跟 `:`，且它前面是 `(` / `,` **或者这一行只有缩进**
        #（后者是多行调用的续行 —— `style:` 自己单独占一行）。
        # 行首 + 紧跟 `:` 只可能是参数标签：真正的成员访问要么带前缀（`x.style`），
        # 要么后面接 `=` / `.` / `(`，不会有裸 `style: ` 这种形状。
        if not re.match(r"\s*:", after):
            return False
        if re.search(r"[\(,]\s*$", before) or before.strip() == "":
            continue
        return False
    return True


def only_value_member(line, name):
    """这一行里这个名字的每一次出现都是 `某个小写值.name` 吗（判据 ⑧ 的输入）。

    `body.scale` → 是（那个成员属于 `body` 的类型，本门禁叫不出那个类型）；
    `TokensHalo.scale` → 不是（前缀是大写的**类型名**，正是本门禁要抓的形状）；
    裸 `scale` / `scale = 1` → 不是。

    形状学的是 `qualified_uses_of` 那条正则，只是把前缀收窄到小写标识符：
    大写开头的前缀在这个仓里就是类型名（`TokensPalette` / `StackSpec`…），
    而类型名正是判据 ⑤ 那一侧管的事。
    """
    hits = list(re.finditer(r"\b%s\b" % re.escape(name), line))
    if not hits:
        return False
    for m in hits:
        #  只看名字**前面**：必须紧跟在 `.` 后面，而且那个 `.` 的接收者是一个
        # 小写标识符（`body.scale`）。大写开头的前缀是本仓的类型名（`TokensPalette`
        # / `StackSpec`…）—— 那一种正是本门禁要抓的形状，不能放它走。
        before = line[:m.start()]
        if not re.search(r"(?<![A-Za-z0-9_.])[a-z_]\w*\s*\.\s*$", before):
            return False
    return True


def sdk_member_names():
    """`scan/sdk_cache.json` 里的名字集合。

    ⚠️ 读不到就当**失败**，不静默放行：这张表是判据 ⑧ 唯一的输入，
    缺它就等于那条判据不存在 —— 而「没检查」与「没问题」在输出上长得一样。
    """
    with io.open(SDK_CACHE, encoding="utf-8") as f:
        return set(json.load(f))


def uses_of(name, text):
    """新版本里**仍在代码中**用到这个名字的行号（注释不算，局部量声明行也不算）。"""
    body = strip_comments(text)
    binding = re.compile(LOCAL_BINDING % re.escape(name))
    hit = re.compile(r"\b%s\b" % re.escape(name))
    out = []
    for i, line in enumerate(body.split("\n"), start=1):
        if not hit.search(line):
            continue
        if binding.search(line):      # 这一行是在**声明**同名局部量，不是使用
            continue
        if only_argument_labels(line, name):   # 判据 ⑥：参数标签不算使用
            continue
        out.append((i, line.strip()))
    return out


# 类型声明（`struct` / `enum` / `class` / `actor` / `protocol`）—— 缩进不卡：
# 嵌套类型（`StackSpec.Card`）缩进 8，而那正是本文件要认出来的东西（见判据 ⑤）。
TYPE_DECL = re.compile(
    r"^[ \t]*(?:@[A-Za-z_][\w.]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:" + MODIFIER + r")\s+)*"
    r"(?:struct|enum|class|actor|protocol)\s+([A-Za-z_]\w*)\b",
    re.M,
)

# 任意缩进的成员级声明（`let` / `var` / `func` / `case`）—— 只给判据 ④ 用。
# 它是**未编译**的模板：名字得先填进去（`ANY_DECL_SRC % 名字`）。
ANY_DECL_SRC = (
    r"^[ \t]*(?:@[A-Za-z_][\w.]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:" + MODIFIER + r")\s+)*"
    r"(?:let|var|func|case)\s+%s\b"
)

# 函数签名（判据 ⑦）：`func 名字`+ 可选的泛型子句 + `(`。
# 泛型子句的写法与 `scan.py` 的 GENERIC 一致（不带尖括号/括号），本仓就那一种。
FUNC_SIG = re.compile(
    r"^[ \t]*(?:@[A-Za-z_][\w.]*(?:\([^)]*\))?\s+)*"
    r"(?:(?:" + MODIFIER + r")\s+)*"
    r"func\s+[A-Za-z_]\w*\s*(?:<[^<>{}()]*>)?\(",
    re.M,
)

# 形参名：参数表里「标识符 + `:`」的每一个。**故意宽** —— 它只往「新版本声明过」
# 那一侧加名字（宁可漏，不可噪），所以把 `in shape: S` 里的 `shape` 与默认值里
# 可能出现的标签一起收进来也没关系；反过来（漏掉一个真形参）就是一条假阳性。
PARAM_LABEL = re.compile(r"(?<![\w.])([a-z_]\w*)\s*:")


def param_names(text):
    """这个文件里**函数形参**的名字（判据 ⑦）。

    括号配对是逐字符数的（默认值里还会嵌括号，如 `.opacity(0.3)`）—— 与 `scan.py`
    「不猜」的取法一致：只用到签名里那一个 `(` 与与它配对的 `)` 之间那一段。
    """
    body = strip_comments(text)
    names = set()
    for m in FUNC_SIG.finditer(body):
        i = m.end() - 1                      # 签名里那个 `(`
        depth, j = 0, i
        while j < len(body):
            if body[j] == "(":
                depth += 1
            elif body[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        names |= set(PARAM_LABEL.findall(body[i + 1:j]))
    return names


def type_names(text):
    """这个文件里声明过的类型名（含嵌套类型）—— 判据 ⑤ 的输入。"""
    return set(TYPE_DECL.findall(strip_comments(text)))


def declares_anywhere(text, name):
    """这个文件自己声明了同名成员吗（任意缩进）—— 判据 ④ 的输入。"""
    return re.search(ANY_DECL_SRC % re.escape(name), strip_comments(text), re.M) is not None


def qualified_uses_of(name, text, project_types):
    """别的文件里**带前缀**的用法：`X.name` / `Self.name` / `foo().name`。

    为什么跨文件另立一条：无前缀的裸名字极易撞上局部量（另一个函数里的 `let name`），
    而本文件头的取舍是「宁可漏，不可噪」—— 一条误报会让整条门禁被绕过。
    判据 ⑤（嵌套类型前缀）也在这里 —— 它是同一条取舍的延续。
    """
    body = strip_comments(text)
    hit = re.compile(r"(?:\b[A-Za-z_]\w*|\))\s*\.\s*%s\b" % re.escape(name))
    chain = re.compile(r"((?:\b[A-Za-z_]\w*\s*\.\s*)+)%s\b" % re.escape(name))
    binding = re.compile(LOCAL_BINDING % re.escape(name))
    out = []
    for i, line in enumerate(body.split("\n"), start=1):
        if binding.search(line):
            continue
        m = chain.search(line)
        if m:
            comps = re.findall(r"[A-Za-z_]\w*", m.group(1))
            # `A.B.name` 里紧挨着名字的那一段是类型 → 那是**另一个类型**的成员，不报。
            if len(comps) >= 2 and comps[-1] in project_types:
                continue
        if hit.search(line):
            out.append((i, line.strip()))
    return out


def scope_files():
    """范围内的 .swift 文件（相对仓库根，用 / 分隔）。"""
    out = []
    for d in SCOPE_DIRS:
        root = os.path.join(PROJECT_ROOT, d)
        for dirpath, _dirnames, filenames in os.walk(root):
            for f in filenames:
                if f.endswith(".swift"):
                    full = os.path.join(dirpath, f)
                    out.append(os.path.relpath(full, PROJECT_ROOT).replace("\\", "/"))
    return sorted(out)


def pick_base(args):
    """→ (旧版本 rev, 为什么)。打印这个选择，不让它默默退回 HEAD~1。"""
    if args.base:
        return args.base, "--base 指定"
    dirty = run_git(["status", "--porcelain", "--"] + SCOPE_DIRS) or ""
    if dirty.strip():
        return "HEAD", "工作区有改动 → 比 HEAD（手上这份的父提交）"
    if run_git(["rev-parse", "--verify", "HEAD~1"]) is None:
        return "HEAD", "没有 HEAD~1（浅克隆 / 首个提交）"
    return "HEAD~1", "工作区干净 → 比 HEAD~1（就是 CI 的那一笔）"


def workspace_texts():
    """工作区里范围内的全部正文（「新版本」那一侧）。

    为什么自测模式（`--from/--to`）也从工作区取，而不是从 `--to` 那一份取：
    两者是不同的东西。从 `--to` 取的话，自测就变成「重放了一遍历史」——
    而 2026-09-25 实测：文件头原来写着「两条都必须报出来」的那两条命令
    在**两种取法下都是绿的**，原因也不在取哪一份（①`pvValue` 在旧版里的声明
    缩进比 4 深，判据 ① 就找不到；②`shapeScroll` 在新版里还声明着）。
    所以没有改取法，只把文件尾那两条自测换成了**今天真能跑的**两条
    （删 `focusInset` / 删 `tiltDeg`，两条都必须报）。
    """
    out = {}
    for rel in scope_files():
        try:
            with open(os.path.join(PROJECT_ROOT, rel), encoding="utf-8") as fh:
                out[rel] = fh.read()
        except OSError:
            continue
    return out


def old_and_new(args):
    """→ [(相对路径, 旧文本, 新文本)]。只比**真的会变**的那些文件。"""
    pairs = []
    if args.rev_from and args.rev_to:
        changed = run_git(["diff", "--name-only", args.rev_from, args.rev_to]) or ""
        for rel in changed.split("\n"):
            rel = rel.strip()
            if not rel.endswith(".swift") or not os.path.exists(os.path.join(PROJECT_ROOT, rel)):
                continue
            old = run_git(["show", "%s:%s" % (args.rev_from, rel)])
            new = run_git(["show", "%s:%s" % (args.rev_to, rel)])
            if old is not None and new is not None:
                pairs.append((rel, old, new))
        return pairs

    base, why = pick_base(args)
    if run_git(["rev-parse", "--verify", base]) is None:
        base, why = "HEAD", "%s（但 %s 不存在，退回 HEAD）" % (why, base)
    print("旧版本：%s — %s" % (base, why))
    for rel in scope_files():
        old = run_git(["show", "%s:%s" % (base, rel)])
        if old is None:
            continue
        try:
            with open(os.path.join(PROJECT_ROOT, rel), encoding="utf-8") as fh:
                new = fh.read()
        except OSError:
            continue
        if old != new:
            pairs.append((rel, old, new))
    return pairs


def main():
    ap = argparse.ArgumentParser(description="删声明守卫")
    ap.add_argument("--base", help="旧版本（默认 HEAD~1，取不到就退回 HEAD）")
    ap.add_argument("--from", dest="rev_from", help="自测用：旧提交")
    ap.add_argument("--to", dest="rev_to", help="自测用：新提交")
    args = ap.parse_args()

    pairs = old_and_new(args)
    if not pairs:
        print("本次没有变化的 Swift 文件 —— 没有「删了声明、使用还在」的名字")
        return 0

    # 新版本的全部正文 —— **不只变了的那些文件**：一个名字可能在 A 里被删，
    # 而使用它的地方在 B（`messageWeeks` 就是这样：声明在 `API.swift`、
    # 用在 `MessagesSection.swift`）。「旧版本里声明过」与「现在还在用」本来就跨文件。
    new_texts = workspace_texts()

    # 新版本全项目的成员名（含被挪到别的文件的那些）—— 见文件头的「降噪」。
    # 它与 `new_texts` 同源（同一份工作区）。
    global_new = set()
    for text in new_texts.values():
        global_new |= member_names(text)

    # 判据 ⑦ 的输入：每个文件里**函数形参**的名字（一次算好，循环里不再逐名字扫全文）。
    params_in = {rel: param_names(text) for rel, text in new_texts.items()}

    # 判据 ⑤ 的输入：项目里声明过的**全部**类型名（含嵌套类型）。
    project_types = set()
    for text in new_texts.values():
        project_types |= type_names(text)

    # 判据 ⑧ 的输入：SDK 的符号名。
    sdk = sdk_member_names()

    bad = []
    for rel, old, _new in pairs:
        old_names = member_names(old)
        for name in sorted(old_names):
            if len(name) < MIN_NAME_LEN or name in global_new:
                continue
            # 判据 ④：使用处所在的文件自己声明了同名成员 → 不报。
            hits = []
            # 判据 ④ + ⑦：本文件自己声明了同名成员 / 同名形参 → 不报。
            if not (declares_anywhere(new_texts.get(rel, ""), name)
                    or name in params_in.get(rel, set())):
                hits += [(rel, n, t) for n, t in uses_of(name, new_texts.get(rel, ""))]
            for other, text in new_texts.items():
                if other == rel or declares_anywhere(text, name):
                    continue
                if name in params_in.get(other, set()):
                    continue
                for n, t in qualified_uses_of(name, text, project_types):
                    hits.append((other, n, t))
            # 判据 ⑧：名字同时是 SDK 的成员名，而**每一条使用**都是 `小写值.name`
            # （见文件头那一段）→ 那些使用属于某个我们叫不出类型的值。
            if name in sdk and hits and all(only_value_member(t, name) for _, _, t in hits):
                hits = []
            if hits:
                bad.append((rel, name, hits))

    print("比对了 %d 个文件" % len(pairs))
    if not bad:
        print("✅ 没有「删了声明、使用还在」的名字")
        return 0

    for rel, name, hits in bad:
        print("\n`%s`：旧版本里 %s 有它的成员级声明，新版本里项目内已经没有了，"
              "但这些行还在用它：" % (name, rel))
        for file, lineno, text in hits[:8]:
            print("  %s:%d  %s" % (file, lineno, text))
        if len(hits) > 8:
            print("  …还有 %d 行" % (len(hits) - 8))
    print("\n❌ %d 个名字「声明没了、使用还在」—— 这是编译错误，不用等 macOS runner"
          % len(bad))
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
