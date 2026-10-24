#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
站点数据导出器：把 scripts/data/*.gd 的静态表原样导出成 site/dist/data.js + 图标。

为什么要有这个脚本：站点介绍页的角色/武器/道具/技能/灵兽是游戏内容的投影，
手抄一份必然漂（v0.0.44 那次之后武器 69→70、道具 87→103、击退系整系移除，
页面全都不知道）。本脚本每次发布后重跑一遍，页面数字与文案自动跟游戏同源。

用法：
    python3 tools/export_site_data.py            # 导出 + 拷图标 + 数量对账
    python3 tools/export_site_data.py --check    # 只对账不写盘（CI/发布前自查）

判据（数量对不上直接 exit 1，不允许静默出一份旧表）：
    武器 = WeaponData.DEFS 里带 "behavior" 的条目数
    道具 = ItemData.DEFS 条目数；角色 = CultivatorData.DEFS；技能 = SkillData.DEFS；灵兽 = PetData.DEFS
    data.js 落地后再读回来复点一遍，两头一致才算过。

文案同源口径：
    · 武器 desc/tag/desc 与角色 epithet/pros/cons 直接取表，不自己造句。
    · 道具 47 件 desc 为空（游戏内卡面靠 apply 逐行生成），站点同样从 apply 生成，
      人话名与单位走 StatInfoData.FIELDS 这张唯一对照表，不另立一套词。
    · 「三合一升星」与羁绊阶梯的规则句取游戏内原句（WaveShop / ShopWeaponTip / ManualData），
      数字取 WeaponData 常量，避免页面与局内两套说法。
"""

import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "scripts" / "data"
SITE = ROOT / "site" / "dist"
IMG = SITE / "img"
STYLE_GD = ROOT / "scripts" / "ui" / "GameStyle.gd"

# —— 期望数量：改表后这里由对账自动跟随，写死只为「骤降先报警」 ——
EXPECT_MIN = {"weapons": 60, "items": 90, "roles": 18, "skills": 6, "pets": 6}

# 站点默认主题色：改这一行就换默认档（必须是 THEME_PRESETS 里的 id）。
# 游戏内默认是品红，站点按用户要求默认走荧绿；其余四套仍可页面上一键切换。
SITE_THEME_ID = "lime"

# 角色卡首屏顺序：网页首屏只铺 2 行 × 当前列数（桌面 8 张），其余收在「展开其余 N 名」。
# 只钉首屏这几个 id，未列出的角色按 CultivatorData 表序跟在后面（新增角色自动落折叠区）。
# 顺序是站点自己的展示取向，不改游戏内选人顺序。
SITE_ROLE_TOP = ["jianchi", "juechen", "fuzhen", "jinsuanpan",
                 "meiying", "dubi", "sanxiu", "duoshe"]


# ============================================================================
# GDScript 字典字面量的轻量解析（只做站点需要的读取，不求覆盖引擎语法）
# ============================================================================

def strip_comments(src: str) -> str:
    """去掉 # 注释（字符串内的 # 保留），保持字符偏移不变。"""
    out, i, n, in_str = [], 0, len(src), False
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\":
                out.append(src[i:i + 2]); i += 2; continue
            if c == '"':
                in_str = False
            out.append(c); i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if c == "#":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j; continue
        out.append(c); i += 1
    return "".join(out)


def const_body(src: str, const_decl: str) -> str:
    """取 `const XXX ... = { ... }` 花括号内的正文（不含最外层括号）。"""
    clean = strip_comments(src)
    m = re.search(re.escape(const_decl) + r"[^{]*\{", clean)
    if not m:
        raise SystemExit(f"找不到常量块：{const_decl}")
    start = m.end()
    depth, i, n = 1, start, len(clean)
    in_str = False
    while i < n:
        c = clean[i]
        if in_str:
            if c == "\\":
                i += 2; continue
            if c == '"':
                in_str = False
        else:
            if c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return clean[start:i]
        i += 1
    raise SystemExit(f"{const_decl} 花括号未闭合")


def split_entries(body: str) -> list:
    """按 depth-1 的 `"key": { ... }` 切条目，返回 [(id, 条目正文), ...] 保持表内顺序。"""
    out, i, n = [], 0, len(body)
    while i < n:
        m = re.compile(r'"([A-Za-z0-9_]+)"\s*:\s*\{').search(body, i)
        if not m:
            break
        key, j = m.group(1), m.end()
        depth, in_str = 1, False
        while j < n:
            c = body[j]
            if in_str:
                if c == "\\":
                    j += 2; continue
                if c == '"':
                    in_str = False
            else:
                if c == '"':
                    in_str = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        break
            j += 1
        out.append((key, body[m.end():j]))
        i = j + 1
    return out


def get_str(entry: str, key: str, default: str = "") -> str:
    m = re.search(r'"%s"\s*:\s*"((?:[^"\\]|\\.)*)"' % re.escape(key), entry)
    if not m:
        return default
    return m.group(1).encode().decode("unicode_escape", "ignore") if "\\u" in m.group(1) else m.group(1)


def get_num(entry: str, key: str, default=None):
    m = re.search(r'"%s"\s*:\s*(-?\d+(?:\.\d+)?)' % re.escape(key), entry)
    if not m:
        return default
    v = float(m.group(1))
    return int(v) if v.is_integer() and "." not in m.group(1) else v


def get_raw_value(entry: str, key: str):
    """取一个标量或构造器值（数字 / 字符串 / Color(...) / Behavior.X / 数组 / 字典开头）。"""
    m = re.search(r'"%s"\s*:\s*' % re.escape(key), entry)
    if not m:
        return None
    rest = entry[m.end():]
    if rest[:1] in ("[", "{"):
        open_c, close_c = rest[0], "]" if rest[0] == "[" else "}"
        depth, j, in_str = 0, 0, False
        while j < len(rest):
            c = rest[j]
            if in_str:
                if c == "\\":
                    j += 2; continue
                if c == '"':
                    in_str = False
            else:
                if c == '"':
                    in_str = True
                elif c == open_c:
                    depth += 1
                elif c == close_c:
                    depth -= 1
                    if depth == 0:
                        return rest[:j + 1]
            j += 1
        return None
    line = rest.split("\n", 1)[0].strip().rstrip(",")
    return line


def get_arr(entry: str, key: str) -> list:
    raw = get_raw_value(entry, key)
    if not raw:
        return []
    return re.findall(r'"((?:[^"\\]|\\.)*)"', raw)


def get_dict_body(entry: str, key: str) -> str:
    raw = get_raw_value(entry, key)
    if not raw:
        return ""
    return raw[1:-1]


def color_to_hex(entry: str, key: str, default: str = "") -> str:
    """Color(r, g, b[, a]) 的 0~1 浮点 → #rrggbb（站点只要主体色）。"""
    raw = get_raw_value(entry, key) or ""
    m = re.search(r"Color\(([^)]*)\)", raw)
    if not m:
        return default
    parts = [float(x) for x in m.group(1).split(",") if x.strip()]
    if len(parts) < 3:
        return default
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(p * 255))) for p in parts[:3])


# ============================================================================
# GameStyle.gd → 站点样式令牌（颜色 / 边框 / 硬影 / 时长一律现读，页面不抄数）
# ============================================================================

def clamp01(v: float) -> float:
    return max(0.0, min(1.0, v))


def parse_color(raw: str) -> str:
    """Color("ff006e") / Color(0.78, 0.45, 0.98) / Color(0, 0, 0, 1.0) → #rrggbb"""
    if not raw:
        return ""
    m = re.search(r"Color\(([^)]*)\)", raw)
    if not m:
        return ""
    arg = m.group(1).strip()
    if arg.startswith('"'):
        return "#" + arg.strip('"').lstrip("#").lower()
    parts = [float(x) for x in arg.split(",") if x.strip()]
    if len(parts) < 3:
        return ""
    return "#%02x%02x%02x" % tuple(round(clamp01(p) * 255) for p in parts[:3])


def darken_hex(hexc: str, f: float) -> str:
    """Color.darkened(f)：各通道 ×(1-f)。"""
    r, g, b = (int(hexc[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(round(v * (1.0 - f)) for v in (r, g, b))


def _wcag_lum(hexc: str) -> float:
    r, g, b = (int(hexc[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    f = [(v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4) for v in (r, g, b)]
    return 0.2126 * f[0] + 0.7152 * f[1] + 0.0722 * f[2]


def face_text(hexc: str) -> str:
    """面色定字色：在游戏内 on_face_text「亮面墨字 / 暗面骨白字」这条口径上，按 WCAG 对比度取更优的一档。
    不直接照抄它的线性亮度阈值：品红 #ff006e 线性亮度 0.244 会被判成「配白字」（3.8:1），
    而游戏自己的标题带是显式配黑字（BaseModalDialog 的 INK_TEXT，5.5:1）—— 按对比度算两边才对得上，
    且主题一切（品红↔荧绿）时按压态那种深档不会反过来把字糊没。"""
    lum = _wcag_lum(hexc)
    on_ink = (lum + 0.05) / 0.05
    on_chalk = 1.05 / (lum + 0.05)
    return "var(--ink)" if on_ink >= on_chalk else "var(--chalk)"


def lighten_hex(hexc: str, f: float) -> str:
    """Color.lightened(f)：c + (1-c)×f。"""
    r, g, b = (int(hexc[i:i + 2], 16) for i in (1, 3, 5))
    return "#%02x%02x%02x" % tuple(round(v + (255 - v) * f) for v in (r, g, b))


def const_rhs(src: str, name: str) -> str:
    """取 `const NAME : Type = <行尾>` 的右值。"""
    m = re.search(r"^const %s\b[^=\n]*=\s*(.*)$" % re.escape(name), src, re.M)
    if not m:
        raise SystemExit(f"GameStyle.gd 里找不到 const {name} —— 样式改名了就先同步这个导出器")
    return m.group(1).strip()


def fn_body(src: str, name: str) -> str:
    """取 `static func name(...)` 到下一个顶层 static func / const 之前的源码段。"""
    m = re.search(r"^static func %s\(" % re.escape(name), src, re.M)
    if not m:
        raise SystemExit(f"GameStyle.gd 里找不到 static func {name}()")
    nxt = re.search(r"^(static func |const )", src[m.end():], re.M)
    end = m.end() + nxt.start() if nxt else len(src)
    return src[m.start():end]


def one_vec(body: str, pattern: str, label: str, idx: int = 0) -> tuple:
    """从函数体（含签名默认值）里按出现顺序取第 idx 个匹配，返回 (x, y)。"""
    hits = re.findall(pattern, body)
    if len(hits) <= idx:
        raise SystemExit(f"{label} 里没读到预期的 Vector2/数字（{pattern}）—— 工厂写法变了，先改这个导出器")
    a, b = hits[idx]
    if a is None or b is None:
        raise SystemExit(f"{label} 的 Vector2 解析失败")
    return float(a), float(b)


def one_num(text: str, pattern: str, label: str) -> float:
    m = re.search(pattern, text, re.S)
    if not m:
        raise SystemExit(f"{label} 读不到（{pattern}）")
    return float(m.group(1))


def build_style_tokens() -> tuple:
    """返回 (tokens: 有序 dict, themes: 5 套预设 list)。读不到的项一律报错，绝不静默回退成手抄数。"""
    src = strip_comments(STYLE_GD.read_text(encoding="utf-8"))

    ink = parse_color(const_rhs(src, "INK"))
    navy = parse_color(const_rhs(src, "NAVY"))
    navy2 = parse_color(const_rhs(src, "NAVY2"))
    # slot_of 的底色是「纸面挖下去一档」，暗化系数就写在它的签名默认值里
    slot_f = one_num(fn_body(src, "slot_of"), r"NAVY2\.darkened\(\s*([\d.]+)\s*\)", "slot_of 暗化系数")

    # 主题三件套：const 已改 static var，值来自 THEME_PRESETS 第一套（默认品红）
    presets = []
    for m in re.finditer(r"\{\s*\"id\":\s*&\"([a-z]+)\",\s*\"name\":\s*\"([^\"]+)\",\s*"
                         r"\"main\":\s*Color\(\"([0-9a-fA-F]+)\"\),\s*"
                         r"\"edge\":\s*Color\(\"([0-9a-fA-F]+)\"\),\s*"
                         r"\"dk\":\s*Color\(\"([0-9a-fA-F]+)\"\)\s*\}", src):
        presets.append({"id": m.group(1), "n": m.group(2),
                        "main": "#" + m.group(3).lower(), "edge": "#" + m.group(4).lower(),
                        "dk": "#" + m.group(5).lower()})
    if len(presets) < 2:
        raise SystemExit(f"THEME_PRESETS 只解出 {len(presets)} 套，站点主题切换器会缺档")
    theme = next((p for p in presets if p["id"] == SITE_THEME_ID), None)
    if theme is None:
        raise SystemExit(f"SITE_THEME_ID={SITE_THEME_ID!r} 不在 THEME_PRESETS 里（可选：{[p['id'] for p in presets]}）")
    for p in presets:
        # 每套预设自带三档面色对应的文字色，前端切主题时一并改，不留写死的黑白
        p["t"] = face_text(p["main"])
        p["te"] = face_text(p["edge"])
        p["td"] = face_text(p["dk"])

    # 工厂几何：框宽 / 硬影偏移 / 压扁位移，全部现读
    block_b = fn_body(src, "block")
    card_b = fn_body(src, "card")
    dialog_b = fn_body(src, "dialog_panel")
    side_b = fn_body(src, "side_card")
    btn_b = fn_body(src, "button")
    chip_off = one_vec(fn_body(src, "chip"), r"block\(face,\s*SLANT_BAND,\s*Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)\)", "chip()")
    mini = fn_body(src, "compact_chip")
    mini_off = one_vec(mini, r"panel\(face,\s*SLANT_BAND,\s*Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)\)", "compact_chip()")
    normal_off = one_vec(btn_b, r"_btn_block\([^,]+,\s*skew_deg,\s*Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)\)", "button() normal", 0)
    hover_off = one_vec(btn_b, r"_btn_block\([^,]+,\s*skew_deg,\s*Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)\)", "button() hover", 1)
    sink = (one_num(btn_b, r"content_margin_left = ([\d.]+)", "button() 压扁位移 X"),
            one_num(btn_b, r"content_margin_top = ([\d.]+)", "button() 压扁位移 Y"))

    out = {
        "--ink": ink,
        "--panel": navy,
        "--card": navy2,
        "--slot": darken_hex(navy2, slot_f),
        "--line": parse_color(const_rhs(src, "LINE")),
        "--paper": parse_color(const_rhs(src, "PAPER")),
        "--paper-dim": parse_color(const_rhs(src, "PAPER_DIM")),
        "--chalk": parse_color(const_rhs(src, "CHALK")),
        "--grey": parse_color(const_rhs(src, "GREY")),
        "--disabled": parse_color(const_rhs(src, "DISABLED_FACE")),
        "--hot": theme["main"],
        "--hot-edge": theme["edge"],
        "--hot-dk": theme["dk"],
        "--on-hot": theme["t"],
        "--on-hot-edge": theme["te"],
        "--on-hot-dk": theme["td"],
        "--jade": parse_color(const_rhs(src, "JADE")),
        "--jade-edge": parse_color(const_rhs(src, "JADE_EDGE")),
        "--jade-dk": parse_color(const_rhs(src, "JADE_DK")),
        "--good": parse_color(const_rhs(src, "GOOD")),
        "--good-dk": parse_color(const_rhs(src, "GOOD_DK")),
        "--bad": parse_color(const_rhs(src, "BAD")),
        "--bad-dk": parse_color(const_rhs(src, "BAD_DK")),
        "--element": parse_color(const_rhs(src, "ELEMENT")),
        # 五行色（ELEMENT_COLORS）：一色多用 —— 图标外框、图鉴签面、羁绊行头，站点沿用同一套
        **{"--m-" + k.lower(): parse_color(v) for k, v in re.findall(
            r'"(metal|wood|water|fire|earth)"\s*:\s*(Color\([^)]*\))',
            const_body(src, "const ELEMENT_COLORS"))},
        "--r-1": parse_color(const_rhs(src, "RARITY_COMMON")),
        "--r-2": parse_color(const_rhs(src, "RARITY_RARE")),
        "--r-3": parse_color(const_rhs(src, "RARITY_EPIC")),
        "--r-4": parse_color(const_rhs(src, "RARITY_LEGEND")),
        "--bw": "%dpx" % one_num(block_b, r"border_width_left = (\d+)", "block() 框宽"),
        "--bw-thin": "%dpx" % one_num(fn_body(src, "outlined_panel"), r"border_w: int = (\d+)", "outlined_panel() 框宽"),
        # CSS border-width 的四值顺序是 顶/右/底/左（与 GDScript 里 top/left/bottom/right 的读法不同）
        "--card-edge": "%dpx %dpx %dpx %dpx" % (
            one_num(card_b, r"border_width_top = (\d+)", "card() 顶带"),
            one_num(card_b, r"border_width_right = (\d+)", "card() 右框"),
            one_num(card_b, r"border_width_bottom = (\d+)", "card() 底框"),
            one_num(card_b, r"border_width_left = (\d+)", "card() 侧框")),
        "--side-edge": "%dpx %dpx %dpx %dpx" % (
            one_num(side_b, r"border_width_top = (\d+)", "side_card() 顶"),
            one_num(side_b, r"border_width_right = (\d+)", "side_card() 右"),
            one_num(side_b, r"border_width_bottom = (\d+)", "side_card() 底"),
            one_num(side_b, r"border_width_left = (\d+)", "side_card() 左竖带")),
        "--sh-panel": "%dpx %dpx 0 var(--ink)" % one_vec(fn_body(src, "panel"),
                                                         r"shadow_offset: Vector2 = Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)", "panel() 影"),
        "--sh-block": "%dpx %dpx 0 var(--ink)" % one_vec(block_b,
                        r"shadow_offset: Vector2 = Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)", "block() 影"),
        "--sh-card": "%dpx %dpx 0 var(--ink)" % one_vec(card_b,
                      r"shadow_offset: Vector2 = Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)", "card() 影"),
        "--sh-dialog": "%dpx %dpx 0 var(--ink)" % one_vec(dialog_b, r"shadow_offset: Vector2 = Vector2\((-?[\d.]+),\s*(-?[\d.]+)\)", "dialog_panel() 影"),
        "--sh-chip": "%dpx %dpx 0 var(--ink)" % chip_off,
        "--sh-mini": "%dpx %dpx 0 var(--ink)" % mini_off,
        "--sh-btn": "%dpx %dpx 0 var(--ink)" % normal_off,
        "--sh-btn-hover": "%dpx %dpx 0 var(--ink)" % hover_off,
        "--btn-sink": "%dpx %dpx" % sink,
        "--dur-press": "%gs" % float(const_rhs(src, "ANIM_PRESS")),
        "--dur-snap": "%gs" % float(const_rhs(src, "ANIM_SNAP")),
        "--dur-slam": "%gs" % float(const_rhs(src, "ANIM_SLAM")),
        "--sel-scale": "%g" % one_num(fn_body(src, "select_snap"), r"ONE \* \(([\d.]+) if on", "select_snap() 选中缩放"),
        "--slam-from": "%g" % one_num(fn_body(src, "slam_in"), r"scale = Vector2\(([\d.]+),", "slam_in() 起始缩放"),
        # 扫屏带 slash_wipe / band_wipe：整屏切换的那条直角带的时长、尾段淡出与双带错峰
        "--dur-wipe": "%gs" % one_num(fn_body(src, "slash_wipe"), r'"position:x", vp\.x \* [\d.]+, ([\d.]+)\)', "slash_wipe() 扫屏时长"),
        "--wipe-fade": "%gs" % one_num(fn_body(src, "slash_wipe"), r'"modulate:a", 0\.0, ([\d.]+)\)', "slash_wipe() 尾段淡出"),
        "--wipe-stagger": "%gs" % one_num(fn_body(src, "band_wipe"), r"slash_wipe\(host, INK, ([\d.]+)\)", "band_wipe() 双带错峰"),
    }
    for k, v in out.items():
        if not v:
            raise SystemExit(f"令牌 {k} 解出空值")
    return out, presets


def emit_tokens_css(tokens: dict, themes: list) -> str:
    lines = [
        "/* GENERATED —— 由 tools/export_site_data.py 从 scripts/ui/GameStyle.gd 现读产出，禁止手改。",
        "   游戏样式改完重跑：python3 tools/export_site_data.py",
        "   口径：新野兽派（纯黑舞台 × 宣纸白面板 × 等宽纯黑粗框 × 不透明纯黑硬偏移影 × 全直角）。",
        "   硬影一律 var(--ink)：游戏里 dialog_panel 坐在 0.85 暗幕上，站点坐在纯黑舞台，",
        "   黑压黑看不见是真实现象、不是 bug —— 舞台上的层次靠 card() 那条 accent 顶带与品红标题带表达。",
        "   主题三件套默认取 THEME_PRESETS 第一套，其余四套在 data.js meta.themes 里，由 app.js 现切。 */",
        ":root {",
    ]
    for k, v in tokens.items():
        lines.append(f"  {k}: {v};")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# ============================================================================
# 各表读取
# ============================================================================

def read(path: Path) -> str:
    return (DATA / path).read_text(encoding="utf-8") if not path.is_absolute() else path.read_text(encoding="utf-8")


def load_stat_fields() -> dict:
    """StatInfoData.FIELDS：加点字段 → 人话名 + 单位（道具幅度文案唯一对照表）。"""
    body = const_body((DATA / "StatInfoData.gd").read_text(encoding="utf-8"), "const FIELDS: Dictionary =")
    fields = {}
    for m in re.finditer(r'"([a-z0-9_]+)"\s*:\s*\{([^}]*)\}', body):
        name = re.search(r'"name"\s*:\s*"([^"]*)"', m.group(2))
        unit = re.search(r'"unit"\s*:\s*"([^"]*)"', m.group(2))
        fields[m.group(1)] = (name.group(1) if name else m.group(1),
                              unit.group(1) if unit else "pt")
    return fields


def apply_to_lines(entry: str, fields: dict) -> list:
    """道具 apply 字典 → 「武器伤害 +10%」这类人话行，折算规则与游戏内卡片同源：
    pct   = 增量 ×100；pctmul = (乘数 -1) ×100；pt/rate/times/stone = 原值。"""
    body = get_dict_body(entry, "apply")
    lines = []
    for m in re.finditer(r'"([a-z0-9_]+)"\s*:\s*(-?\d+(?:\.\d+)?)', body):
        key, val = m.group(1), float(m.group(2))
        name, unit = fields.get(key, (key, "pt"))
        if unit == "pct":
            txt = "%+d%%" % round(val * 100) if abs(val) < 10 else "%+d%%" % round(val)
        elif unit == "pctmul":
            txt = "%+d%%" % round((val - 1.0) * 100)
        elif unit == "rate":
            txt = "+%s/秒" % fmt(val)
        else:
            txt = "%s" % fmt_signed(val)
        lines.append(f"{name} {txt}")
    return lines


def fmt(v: float) -> str:
    return str(int(v)) if float(v).is_integer() else str(v)


def fmt_signed(v: float) -> str:
    s = fmt(abs(v))
    return ("+" if v >= 0 else "-") + s


def weapon_cn_behavior(raw: str) -> str:
    """Behavior.PROJECTILE → 远程弹丸 这类人话攻击方式（与卡面「t」字段同词）。"""
    table = {
        "MELEE": "近战", "PROJECTILE": "远程", "BURST": "爆发", "DRONE": "环绕",
        "TURRET": "炮台", "SWEEP": "横扫", "BEAM": "光束", "CONE": "喷吐",
    }
    m = re.search(r"Behavior\.([A-Z]+)", raw or "")
    return table.get(m.group(1), "") if m else ""


# ============================================================================
# 图标落地
# ============================================================================

def copy_icon(res_path: str, dest: Path, size: int = 0) -> str:
    """res://x/y.png → site/dist/img/xxx.webp（无损），返回站点相对路径；size>0 时等比缩到该边长。

    图标全是平涂色块 + 硬描边，WebP 无损比 PNG 体积小 30%~40% 且零画质损失，
    站点首屏要滚二十来张卡（武器/道具/角色各一批），一批批省下来就是几百 KB。
    """
    if not res_path.startswith("res://"):
        return ""
    src = ROOT / res_path[len("res://"):]
    if not src.exists():
        print(f"  ! 图标缺失：{src}", file=sys.stderr)
        return ""
    dest = (IMG / dest.name).with_suffix(".webp")
    from PIL import Image
    with Image.open(src) as im:
        im = im.convert("RGBA")
        if size:
            im.thumbnail((size, size), Image.LANCZOS)
        im.save(dest, "WEBP", lossless=True, method=6)
    return f"img/{dest.name}"


def ui_icon_path(res_path: str) -> str:
    """优先取商店/图鉴口径的 128px 变体（`assets/art/ui/` 同名文件）。

    WeaponData 里的 icon 指向战斗画布 `assets/art/weapon_*.png`（48x48，与 tip 剑尖坐标绑定，
    不能放大改画布）；矢量重绘后的新画风只落在 ui/ 变体里（`tools/sync_weapon_ui_icons.py` 产出），
    站点按 48px 拷过去在高分屏上就是糊的旧图。ui/ 有就用 ui/，没有才退回原路径。
    """
    if not res_path.startswith("res://"):
        return res_path
    rel = Path(res_path[len("res://"):])
    ui_rel = rel.parent / "ui" / rel.name
    return "res://" + ui_rel.as_posix() if (ROOT / ui_rel).exists() else res_path


def prune_stale_icons(used: set) -> None:
    """删掉 data.js 已经不再引用的旧 PNG（图标改成 .webp 后，同名旧图必须清掉）。

    只清打印机产物（武器/角色/道具/技能图标）；`pet_*`（tools/crop_site_pet_icons.py 切图）、
    `app_icon`、`shot_field.png`（og:image 社交抓取，爬虫不认 webp，而正文用的是 .webp）是独立素材，
    不在导出链路里生成，一律保留。
    """
    keep = ("pet_", "app_icon", "shot_field.png")
    for p in IMG.glob("*.png"):
        if p.name.startswith(keep):
            continue
        if f"img/{p.name}" not in used:
            p.unlink()
            print(f"  清掉过期图标 {p.name}")


def subset_site_fonts() -> None:
    """把站点字体裁到「页面真正用到的字」，产出 fonts/MiSans-*-subset.woff2（CSS 引用它）。

    两个字体各 625KB，但全站文案只有约一千个不同的字（CJK 959），九成字形白下载。
    字符集从落盘的 index.html / app.js / data.js 现扫，文案一改字集自动跟着改；再补可打印
    ASCII 兜住运行时拼的数字与符号。**原始 woff2 不许就地覆盖**——子集是不可逆截断，
    原地裁完以后新增的字就永久丢了；所以全量字体放 `site/fonts/`（不进部署目录），
    每次都从它重新裁出 `site/dist/fonts/*-subset.woff2`。

    子集化走子进程 `python -m fontTools.subset`：`-m` 的 sys.path[0] 是仓库根而非 `tools/`，
    脚本目录永远不会抢先命中同名模块。历史上 `tools/` 曾有一个同名的 `inspect.py` 符号链接，
    在 Python 3.14 下连 `import argparse` 都会被它劫持（argparse 启动时 import dataclasses→inspect），
    该链接已于 2026-10-24 删除；子进程写法保留，作为不再依赖 cwd 的隔离手段。
    """
    try:
        import fontTools  # noqa: F401
    except ImportError:
        print("  ! 没装 fontTools/brotli，跳过字体子集化", file=sys.stderr)
        return

    chars = {chr(c) for c in range(0x20, 0x7F)}
    for name in ("index.html", "app.js", "data.js", "tokens.css"):
        p = SITE / name
        if p.exists():
            chars |= set(p.read_text(encoding="utf-8"))
    chars = {c for c in chars if c.isprintable() and not c.isspace()}
    text = "".join(sorted(chars))

    txt = SITE / ".font_charset.tmp"
    txt.write_text(text, encoding="utf-8")
    out_dir = SITE / "fonts"
    out_dir.mkdir(parents=True, exist_ok=True)
    for src in sorted((SITE.parent / "fonts").glob("MiSans-*.woff2")):
        out = out_dir / (src.stem + "-subset.woff2")
        tmp = out.with_suffix(".tmp")
        proc = subprocess.run(
            [sys.executable, "-m", "fontTools.subset", str(src), f"--text-file={txt}",
             f"--output-file={tmp}", "--flavor=woff2", "--layout-features=*",
             "--no-hinting", "--desubroutinize"],
            cwd=str(ROOT), capture_output=True, text=True,
        )
        if proc.returncode != 0:
            print(f"  ! {src.name} 子集化失败：{(proc.stderr or proc.stdout).strip()[:200]}",
                  file=sys.stderr)
            tmp.unlink(missing_ok=True)
            continue
        tmp.replace(out)
        print(f"  字体 {out.name}: {src.stat().st_size // 1024}KB → {out.stat().st_size // 1024}KB（{len(text)} 字）")
    txt.unlink(missing_ok=True)



# ============================================================================
# 导出
# ============================================================================

def build() -> dict:
    fields = load_stat_fields()

    # —— 样式令牌 + 主题预设（GameStyle.gd 是唯一真话源） ——
    tokens, presets = build_style_tokens()
    presets_for_meta = presets

    # —— 版本 ——
    ver = ""
    vm = re.search(r'const APP_VERSION: String = "([^"]+)"',
                   (ROOT / "scripts" / "autoload" / "Version.gd").read_text(encoding="utf-8"))
    if vm:
        ver = vm.group(1)

    # —— 武器 ——
    wbody = const_body((DATA / "WeaponData.gd").read_text(encoding="utf-8"), "const DEFS: Dictionary =")
    weapons = []
    for idx, (wid, e) in enumerate(split_entries(wbody)):
        if "behavior" not in e:      # DEFS 里混有分组注释条目，只认带 behavior 的真武器
            continue
        tag_raw = get_raw_value(e, "tags")
        tags = [t for t in re.findall(r'"([a-z0-9_]+)"', tag_raw or "")]
        weapons.append({
            "id": wid,
            "n": get_str(e, "name"),
            "d": get_str(e, "desc"),
            "t": get_str(e, "tag"),
            "b": weapon_cn_behavior(get_raw_value(e, "behavior") or ""),
            "g": tags,
            "p": get_num(e, "price", 0),
            "i": copy_icon(ui_icon_path(get_str(e, "icon")), IMG / f"w{idx:02d}.png"),
        })

    # —— 羁绊（器类 + 五行 11 组，名字与阈值直接取表） ——
    wsrc_all = (DATA / "WeaponData.gd").read_text(encoding="utf-8")
    # 五行键从 ELEMENTS 数组声明现读。注意别用 const_body()：那是给花括号块用的，
    # 方括号常量会一路吞到下一个 {，把 DEFS 里的 tags 全当成五行键（11 个系全被判成 element）
    elem_m = re.search(r"const ELEMENTS: Array\[String\]\s*=\s*\[(.*?)\]", strip_comments(wsrc_all), re.S)
    if not elem_m:
        raise SystemExit("WeaponData.gd 里读不到 ELEMENTS 数组")
    elem_keys = re.findall(r'"([a-z_]+)"', elem_m.group(1))
    sbody = const_body((DATA / "WeaponData.gd").read_text(encoding="utf-8"), "const SYNERGIES: Dictionary =")
    cats = []
    for sid, e in split_entries(sbody):
        thresholds = [int(float(x)) for x in re.findall(r"-?\d+(?:\.\d+)?", (get_raw_value(e, "thresholds") or "[]")[1:-1])]
        labels = re.findall(r'"label"\s*:\s*"([^"]*)"', get_raw_value(e, "effects") or "")
        cats.append({"k": sid, "n": get_str(e, "name"), "kind": "element" if sid in elem_keys else "class",
                     "th": thresholds, "ef": list(dict.fromkeys(labels))})
    # 器类/五行必须两边都认得出：全判成一边就是 ELEMENTS 读歪了（前端色签与筛选会一起错）
    if {c["kind"] for c in cats} != {"class", "element"}:
        raise SystemExit("羁绊分组 kind 判定异常（器类/五行没分干净）：" + str({c["kind"] for c in cats}))

    # —— 技能（先于角色解析：角色卡的「额外技能」要把 id 换成人话名） ——
    ksrc = (DATA / "SkillData.gd").read_text(encoding="utf-8")
    kbody = const_body(ksrc, "const DEFS: Dictionary =")
    # OFFER_IDS 是无引号常量名，get_raw_value 那套（面向 "key":）拿不到，直接按声明行取
    offer_m = re.search(r"const OFFER_IDS[^=]*=\s*\[(.*?)\]", ksrc, re.S)
    offer_ids = re.findall(r'"([a-z_]+)"', offer_m.group(1)) if offer_m else []
    skills = []
    for sid, e in split_entries(kbody):
        icon_res = get_str(e, "icon")
        skills.append({
            "id": sid,
            "n": get_str(e, "name"),
            "g": get_str(e, "glyph"),
            "d": get_str(e, "desc"),
            "cd": get_num(e, "cooldown", 0),
            "dur": get_num(e, "duration", 0),
            "offer": sid in offer_ids,      # 5 选 1 的可携技能 / 角色绑定的额外技能
            "i": copy_icon(icon_res, IMG / Path(icon_res).name) if icon_res else "",
        })
    skill_name = {s["id"]: s["n"] for s in skills}

    # —— 角色 ——
    cbody = const_body((DATA / "CultivatorData.gd").read_text(encoding="utf-8"), "const DEFS: Dictionary =")
    roles = []
    for rid, e in split_entries(cbody):
        ex = get_str(e, "extra_skill")
        roles.append({
            "id": rid,
            "n": get_str(e, "name"),
            "e": get_str(e, "epithet"),
            "p": get_arr(e, "pros"),
            "c": get_arr(e, "cons"),
            "kit": get_str(e, "start_equip"),                    # 开局自带，如「★2 护蝶 ×1」
            "ex": skill_name.get(ex, "") if ex else "",          # 角色绑定的第二个技能名
            "i": copy_icon(get_str(e, "icon"), IMG / f"c_{Path(get_str(e, 'icon')).name}"),
        })

    # 首屏这 8 张按 SITE_ROLE_TOP 排，缺 id 说明角色被改名/删表，直接报错不静默换位
    role_by_id = {r["id"]: r for r in roles}
    missing_top = [rid for rid in SITE_ROLE_TOP if rid not in role_by_id]
    if missing_top:
        raise SystemExit("SITE_ROLE_TOP 里的角色 id 不在 CultivatorData.DEFS：" + ", ".join(missing_top))
    top_set = set(SITE_ROLE_TOP)
    roles = [role_by_id[rid] for rid in SITE_ROLE_TOP] + [r for r in roles if r["id"] not in top_set]

    # —— 道具 ——
    ibody = const_body((DATA / "ItemData.gd").read_text(encoding="utf-8"), "const DEFS: Dictionary =")
    tier_labels = {}
    tl_body = const_body((DATA / "ItemData.gd").read_text(encoding="utf-8"), "const TIER_LABELS")
    for m in re.finditer(r'(\d+)\s*:\s*"([^"]+)"', tl_body):
        tier_labels[int(m.group(1))] = m.group(2)
    items = []
    for iid, e in split_entries(ibody):
        desc = get_str(e, "desc")
        rows = apply_to_lines(e, fields)
        items.append({
            "id": iid,
            "n": get_str(e, "name"),
            "tier": get_num(e, "tier", 1),
            "tl": tier_labels.get(get_num(e, "tier", 1), ""),
            "price": get_num(e, "price", 0),
            "d": desc,
            "r": rows,          # desc 为空时站点用 apply 生成的幅度行兜底
            "i": copy_icon(get_str(e, "icon"), IMG / f"item_{iid}.png", 64),
        })

    # —— 灵兽 ——
    pbody = const_body((DATA / "PetData.gd").read_text(encoding="utf-8"), "const DEFS: Dictionary =")
    role_body = const_body((DATA / "PetData.gd").read_text(encoding="utf-8"), "const ROLES")
    role_cn = dict(re.findall(r'"([a-z_]+)"\s*:\s*"([^"]+)"', role_body))
    pets = []
    for pid, e in split_entries(pbody):
        role = get_str(e, "role")
        # 灵兽在游戏内没有贴图（SpiritPet._draw 程序化光灵），站点图标由 tools/crop_site_pet_icons.py
        # 从调形台实拍切出来；没切过就留空，前端拿 PetData 的 color/halo 画 CSS 灵球兜底。
        orb = IMG / f"pet_{pid}.png"
        pets.append({
            "id": pid,
            "n": get_str(e, "name"),
            "role": role,
            "rn": role_cn.get(role, role),
            "d": get_str(e, "desc"),
            "cd": get_num(e, "base_cooldown", 0),
            "price": get_num(e, "base_price", 0),
            "color": color_to_hex(e, "color", "#ffffff"),
            "halo": color_to_hex(e, "halo_color", "#ffffff"),
            "decor": get_str(e, "decor"),
            "i": f"img/{orb.name}" if orb.exists() else "",
        })

    # —— 规则句与玩法节奏（数字全部现读常量，页面 copy 里不许再手抄秒数） ——
    wsrc = (DATA / "WeaponData.gd").read_text(encoding="utf-8")
    gm_src = (ROOT / "scripts" / "autoload" / "GameManager.gd").read_text(encoding="utf-8")
    bw_src = (ROOT / "scripts" / "systems" / "BalanceWave.gd").read_text(encoding="utf-8")
    inv_src = (ROOT / "scripts" / "autoload" / "WeaponInventory.gd").read_text(encoding="utf-8")

    def gconst(src, name, where):
        m = re.search(r"const %s[^=]*=\s*(-?\d+(?:\.\d+)?)" % name, src)
        if not m:
            raise SystemExit(f"{where} 里读不到常量 {name}")
        v = float(m.group(1))
        return int(v) if v.is_integer() else v

    merge_m = re.search(r"count_copies\([^)]*\)\s*<\s*(\d+)", inv_src)
    if not merge_m:
        raise SystemExit("WeaponInventory.gd 里读不到合成所需件数")
    merge_need = int(merge_m.group(1))

    # 波时长公式：min(BASE + 波次 × PER, CAP)，第 1 波四舍五入后就是站点写的那个数
    w_base = gconst(bw_src, "WAVE_DURATION_BASE", "BalanceWave")
    w_per = gconst(bw_src, "WAVE_DURATION_PER_WAVE", "BalanceWave")
    w_cap = gconst(bw_src, "WAVE_DURATION_MAX", "BalanceWave")

    rules = {
        "star": {
            "need": merge_need,
            "max": gconst(wsrc, "MAX_STAR", "WeaponData"),
            "dmg": gconst(wsrc, "STAR_DAMAGE_MULT", "WeaponData"),
            "cd": gconst(wsrc, "STAR_COOLDOWN_MULT", "WeaponData"),
            "slots": gconst(wsrc, "MAX_SLOTS", "WeaponData"),
            "stash": gconst(wsrc, "MAX_STASH_SLOTS", "WeaponData"),
        },
        "play": {
            "victory": gconst(gm_src, "VICTORY_WAVE", "GameManager"),
            "first_seconds": round(w_base + w_per),
            "max_seconds": w_cap,
            "offer": gconst(gm_src, "UPGRADE_OFFER_COUNT", "GameManager"),
            "free_reroll": gconst(gm_src, "ALLOC_FREE_REROLLS", "GameManager"),
            "shop_slots": gconst(gm_src, "SHOP_BASE_SLOTS", "GameManager"),
        },
    }

    return {
        "meta": {
            "version": ver,
            "themes": presets_for_meta,
            "theme_default": SITE_THEME_ID,
            "counts": {"roles": len(roles), "weapons": len(weapons), "items": len(items),
                       "skills": len(skills), "pets": len(pets), "cats": len(cats)},
        },
        "tokens": tokens,
        "cats": cats,
        "weapons": weapons,
        "roles": roles,
        "items": items,
        "skills": skills,
        "pets": pets,
        "rules": rules,
    }


def check(data: dict) -> list:
    """与 .gd 源文件的独立计数对账（不用 build 的中间值，防解析漏条目）。"""
    problems = []
    srcs = {
        "weapons": (("WeaponData.gd",), r'"behavior":'),
        "items": (("ItemData.gd",), r'"tier":'),
        "roles": (("CultivatorData.gd",), r'"epithet":'),
        "skills": (("SkillData.gd",), r'"glyph":'),
        "pets": (("PetData.gd",), r'"decor":'),
    }
    for key, (files, pat) in srcs.items():
        want = sum(len(re.findall(pat, (DATA / f).read_text(encoding="utf-8"))) for f in files)
        got = data["meta"]["counts"][key]
        if want != got:
            problems.append(f"{key}: 源表 {want} 条 / 导出 {got} 条")
        if got < EXPECT_MIN[key]:
            problems.append(f"{key}: 导出 {got} 条低于下限 {EXPECT_MIN[key]}（表被删了？）")
    return problems


def check_tokens(tokens: dict, themes: list, staleness: bool = True) -> list:
    """令牌侧对账：①磁盘上的 tokens.css 必须等于按 GameStyle 现值重算的那份（防改了游戏忘重跑）；
    ②styles.css 里用到的每个 var(--x) 都得有声明（防改名后页面静默掉色 —— 只有截图才看得见那种坑）。
    写盘那一趟跳过①（本次就是要把它更新），落盘后再补对一遍。"""
    problems = []
    fresh = emit_tokens_css(tokens, themes)
    disk = SITE / "tokens.css"
    if staleness and disk.exists() and disk.read_text(encoding="utf-8") != fresh:
        problems.append("tokens.css 与 GameStyle.gd 现值不一致（重跑 python3 tools/export_site_data.py）")
    css_src = (SITE / "styles.css").read_text(encoding="utf-8") if (SITE / "styles.css").exists() else ""
    # app.js 用 setProperty 现挂到节点上的自定义属性（灵兽主色等）算「已声明」
    js_src = (SITE / "app.js").read_text(encoding="utf-8") if (SITE / "app.js").exists() else ""
    declared = (set(re.findall(r"(--[a-z0-9-]+)\s*:", fresh))
                | set(re.findall(r"(--[a-z0-9-]+)\s*:", css_src))
                | set(re.findall(r'setProperty\(["\'](--[a-z0-9-]+)["\']', js_src)))
    used = set(re.findall(r"var\((--[a-z0-9-]+)\)", css_src)) | set(re.findall(r"var\((--[a-z0-9-]+)\)", fresh))
    missing = sorted(used - declared)
    if missing:
        problems.append("styles.css 用了没声明的令牌：" + " ".join(missing))
    # CSS 的 border 简写只吃一个线宽：写成 border: var(--四值宽度) solid X 会被整条丢弃，
    # 框直接变 0px（DOM 与 class 全对，只有像素量得出来）。四值宽度必须走 border-width 长写法。
    for m in re.finditer(r"border:\s*var\((--[a-z0-9-]+)\)\s+[^;]+;", css_src):
        var = m.group(1)
        widths = re.findall(r"(-?[\d.]+)px", tokens.get(var, ""))
        if len(widths) > 1:
            problems.append(f"styles.css 用 border 简写套了多值宽度令牌 {var}"
                            "（CSS 会整条丢弃 → 框变 0px），改成 border-style + border-width + border-color")
    return problems


def main() -> int:
    check_only = "--check" in sys.argv
    data = build()
    tokens = data.pop("tokens")
    themes = data["meta"]["themes"]

    problems = check(data) + check_tokens(tokens, themes, staleness=check_only)
    if problems:
        print("对账失败：", file=sys.stderr)
        for p in problems:
            print("  ✗", p, file=sys.stderr)
        return 1

    counts = data["meta"]["counts"]
    print("对账通过：" + " / ".join(f"{k} {v}" for k, v in counts.items())
          + f" · 游戏版本 v{data['meta']['version']} · 样式令牌 {len(tokens)} 项 · 主题 {len(themes)} 套")

    if check_only:
        return 0

    IMG.mkdir(parents=True, exist_ok=True)
    (SITE / "tokens.css").write_text(emit_tokens_css(tokens, themes), encoding="utf-8")
    out = "window.GAME_DATA = " + json.dumps(data, ensure_ascii=False, separators=(",", ":")) + ";\n"
    (SITE / "data.js").write_text(out, encoding="utf-8")

    # 读回来复点一遍：落地的 data.js 必须与内存里那份同数量
    back = json.loads((SITE / "data.js").read_text(encoding="utf-8").split("=", 1)[1].strip().rstrip(";"))
    for key, arr in (("weapons", back["weapons"]), ("items", back["items"]), ("roles", back["roles"]),
                     ("skills", back["skills"]), ("pets", back["pets"])):
        if len(arr) != counts[key]:
            print(f"✗ data.js 里 {key} 落地 {len(arr)} 条 ≠ 内存 {counts[key]} 条", file=sys.stderr)
            return 1

    # 缺图检查：有 icon 字段但没落地成文件的，一律报红（旧版本静默给空 src，页面露白块）
    missing = [w["n"] for w in back["weapons"] if not w["i"]]
    missing += [i["n"] for i in back["items"] if not i["i"]]
    missing += [r["n"] for r in back["roles"] if not r["i"]]
    missing += [p["n"] for p in back["pets"] if not p["i"]]
    if missing:
        print("✗ 以下条目没拿到图标：" + "、".join(missing), file=sys.stderr)
        return 1

    # 落盘后再对一遍令牌（这次带陈检查）：写完的 tokens.css 必须与 GameStyle 现值逐字节相同
    late = check_tokens(tokens, themes)
    if late:
        for p in late:
            print("✗", p, file=sys.stderr)
        return 1

    print(f"data.js {len(out) // 1024} KB · tokens.css {len(tokens)} 项 · 图标目录 {IMG.relative_to(ROOT.parent)}")

    used_icons = {item["i"] for key in ("weapons", "items", "roles", "skills", "pets") for item in back[key]}
    prune_stale_icons(used_icons)
    subset_site_fonts()
    return 0


if __name__ == "__main__":
    sys.exit(main())
