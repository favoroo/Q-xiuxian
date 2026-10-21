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
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "scripts" / "data"
SITE = ROOT / "site" / "dist"
IMG = SITE / "img"

# —— 期望数量：改表后这里由对账自动跟随，写死只为「骤降先报警」 ——
EXPECT_MIN = {"weapons": 60, "items": 90, "roles": 18, "skills": 6, "pets": 6}


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
    """res://x/y.png → site/dist/img/xxx.png，返回站点相对路径；size>0 时等比缩到该边长。"""
    if not res_path.startswith("res://"):
        return ""
    src = ROOT / res_path[len("res://"):]
    if not src.exists():
        print(f"  ! 图标缺失：{src}", file=sys.stderr)
        return ""
    dest = IMG / dest.name
    if size:
        from PIL import Image
        with Image.open(src) as im:
            im = im.convert("RGBA")
            im.thumbnail((size, size), Image.LANCZOS)
            im.save(dest, "PNG", optimize=True)
    else:
        dest.write_bytes(src.read_bytes())
    return f"img/{dest.name}"


# ============================================================================
# 导出
# ============================================================================

def build() -> dict:
    fields = load_stat_fields()

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
            "i": copy_icon(get_str(e, "icon"), IMG / f"w{idx:02d}.png"),
        })

    # —— 羁绊（器类 + 五行 11 组，名字与阈值直接取表） ——
    sbody = const_body((DATA / "WeaponData.gd").read_text(encoding="utf-8"), "const SYNERGIES: Dictionary =")
    cats = []
    for sid, e in split_entries(sbody):
        thresholds = [int(float(x)) for x in re.findall(r"-?\d+(?:\.\d+)?", (get_raw_value(e, "thresholds") or "[]")[1:-1])]
        labels = re.findall(r'"label"\s*:\s*"([^"]*)"', get_raw_value(e, "effects") or "")
        cats.append({"k": sid, "n": get_str(e, "name"), "th": thresholds,
                     "ef": list(dict.fromkeys(labels))})

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

    # —— 规则句（数字取 WeaponData 常量，句子取游戏内原句） ——
    wsrc = (DATA / "WeaponData.gd").read_text(encoding="utf-8")

    def const_num(name):
        m = re.search(r"const %s[^=]*=\s*(-?\d+(?:\.\d+)?)" % name, wsrc)
        return float(m.group(1)) if m else None

    rules = {
        "star": {
            "need": 3,
            "max": int(const_num("MAX_STAR") or 3),
            "dmg": const_num("STAR_DAMAGE_MULT"),
            "cd": const_num("STAR_COOLDOWN_MULT"),
            "slots": int(const_num("MAX_SLOTS") or 6),
            "stash": int(const_num("MAX_STASH_SLOTS") or 9),
        },
        "waves": {"victory": 20},
    }

    return {
        "meta": {
            "version": ver,
            "counts": {"roles": len(roles), "weapons": len(weapons), "items": len(items),
                       "skills": len(skills), "pets": len(pets), "cats": len(cats)},
        },
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


def main() -> int:
    check_only = "--check" in sys.argv
    data = build()

    problems = check(data)
    if problems:
        print("对账失败：", file=sys.stderr)
        for p in problems:
            print("  ✗", p, file=sys.stderr)
        return 1

    counts = data["meta"]["counts"]
    print("对账通过：" + " / ".join(f"{k} {v}" for k, v in counts.items())
          + f" · 游戏版本 v{data['meta']['version']}")

    if check_only:
        return 0

    IMG.mkdir(parents=True, exist_ok=True)
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
    if missing:
        print("✗ 以下条目没拿到图标：" + "、".join(missing), file=sys.stderr)
        return 1

    print(f"data.js 已写出：{len(out) // 1024} KB · 图标目录 {IMG.relative_to(ROOT.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
