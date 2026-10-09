#!/usr/bin/env python3
"""subset_fonts.py —— MiSans 字体子集化（CJK 全量字形 → 游戏实际用到的那几千）

为什么要做：fonts/MiSans-Semibold.woff2 与 MiSans-Heavy.woff2 各 5.0 MB，进包后是
**Stored（不压缩）** 的 5.03 / 5.05 MB fontdata，两份吃满 10.1 MB —— 而游戏正文里
出现的汉字只有两千多个。按字集裁掉用不到的字形，两份共省 8.79 MB（实测 10.05 → 1.25 MB）。
这笔账比任何下载侧的优化都划算：包体小一半，同一网速下下载时间就短一半。

两个账本，别混：
    tools/font_charset.txt        字集       —— 交给 pyftsubset 的保留清单
    tools/font_exempt_chars.txt   豁免账     —— 源码里有、但 MiSans 渲染不了的字

字集口径（2026-10-08 定，见 AGENTS.md「素材生成规范」）：
    ① 源码文本里出现的每一个可渲染字符（扫 scripts/ scenes/ tests/ assets/ 等处的
       .gd/.tscn/.tres/.cfg/.godot）
    ② 并集 GB2312 一级字库（0xB0–0xD7 行，3755 个常用汉字）与 GB2312 符号区
       （0xA1–0xA9 行：全角标点、制表符、希腊/西里尔等）
② 不能省：更新弹窗里的 release notes 是**服务端下发的仓外文案**，① 永远穷举不到它。
真出到字集外的字还有 fonts/*.woff2.import 里的 allow_system_fallback 兜着 —— 大不了
换回系统字体，不会变成豆腐块。

豁免账为什么要过闸：源码里出现的字若 MiSans 没有（⇒ ⊊ ✦ 这类符号，或者注释里随手打的
怪字），它们不在字集里，判据 B 段就会红。这个差集**每次都要人看一眼**才写盘 —— 因为
差集里冒出新字，正好就是「新文案带了个 MiSans 渲染不了的字」这件需要你拍板的事。
自动吸收掉它，判据就变成哑巴了。（本项目真事：判据 B 段第一次跑就抓到它自己新写的
文档注释里那三个字 —— 在它生成字集之后才加进去的。牙齿是好的。）

用法：
    python3 tools/subset_fonts.py                  # 重扫 + 子集化（豁免账有变化时会拦下来）
    python3 tools/subset_fonts.py --accept-exempt  # 看过豁免账的增删，确认接受
    python3 tools/subset_fonts.py --charset-only   # 只重扫两个账本，不动字体

改完文案后：重跑本脚本 → 跑一次编辑器导入 → 跑 tests/FontCoverageCheck.tscn。
原字体留档在 assets_raw/fonts/，只备份一次，重复运行不会拿子集去覆盖原件。
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import unicodedata

try:
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("缺 fontTools。装一个：python3 -m pip install --user fonttools brotli")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS_DIR = os.path.join(ROOT, "fonts")
BACKUP_DIR = os.path.join(ROOT, "assets_raw", "fonts")
IMPORT_CACHE = os.path.join(ROOT, ".godot", "imported")
CHARSET_FILE = os.path.join(ROOT, "tools", "font_charset.txt")
EXEMPT_FILE = os.path.join(ROOT, "tools", "font_exempt_chars.txt")
GAMESTYLE = os.path.join(ROOT, "scripts", "ui", "GameStyle.gd")

## 进包体的两份字重，与 scripts/ui/GameStyle.gd 的 FONT_BODY/FONT_DISPLAY 对应
SUBSET_FONTS = ["MiSans-Semibold.woff2", "MiSans-Heavy.woff2"]

## 扫描口径：与 tests/font_coverage_check.gd 的 B 段同源。两边必须一致，否则判据会误报
## （判据扫的集合更宽就会凭空变红）。改这里要同步改那个判据。
SCAN_EXTS = (".gd", ".tscn", ".tres", ".cfg", ".godot")
SKIP_DIRS = {".godot", ".git", "build", "assets_raw", "android",
             ".agents", ".zcode", ".workbuddy"}

WRAP = 64  # 账本文件每行字符数（纯排版，读取方只把它当一个字符集合）


# ---------------- 字集来源 ①：扫源码文本 ----------------

def scan_source_chars() -> set:
    """递归扫工程里的文本资源，收集全部可渲染字符。"""
    chars = set()
    files = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(SCAN_EXTS):
                continue
            path = os.path.join(dirpath, fn)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as f:
                    text = f.read()
            except OSError as e:
                print(f"  跳过 {path}: {e}")
                continue
            files += 1
            chars.update(c for c in text if _renderable(c))
    print(f"  扫了 {files} 个文本文件")
    return chars


def _renderable(c: str) -> bool:
    """过滤掉没有字形的字符：\\n \\t \\r 这些控制字符不在任何字体的 cmap 里，
    留着会让两个账本与字体永远对不上（校验会假失败）。"""
    return unicodedata.category(c) != "Cc"


# ---------------- 字集来源 ②：GB2312 常用字 ----------------

def gb2312_chars() -> set:
    """逐字节 decode GB2312 的符号区（0xA1–0xA9）与一级字库（0xB0–0xD7）。

    纯标准库生成，不依赖任何外部字表；二级字库（0xD8–0xF7，3008 个生僻字）故意不要。
    """
    chars = set()
    for hi in range(0xA1, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    return chars


# ---------------- 账本读写 ----------------

def read_char_file(path: str) -> set:
    if not os.path.exists(path):
        return set()
    with open(path, "r", encoding="utf-8") as f:
        return {c for c in f.read() if _renderable(c)}


def write_char_file(path: str, chars: set, label: str) -> None:
    ordered = sorted(chars, key=ord)
    lines = ["".join(ordered[i:i + WRAP]) for i in range(0, len(ordered), WRAP)]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  写出{label} {os.path.relpath(path, ROOT)}：{len(ordered)} 个码位")


# ---------------- 字体 ----------------

def backup_original(name: str) -> str:
    """原件留档到 assets_raw/fonts/，只备份一次（重复运行不会拿子集覆盖原件）。"""
    src = os.path.join(FONTS_DIR, name)
    dst = os.path.join(BACKUP_DIR, name)
    os.makedirs(BACKUP_DIR, exist_ok=True)
    if os.path.exists(dst):
        return dst
    shutil.copy2(src, dst)
    print(f"  留档原件 → {os.path.relpath(dst, ROOT)}")
    return dst


def font_coverage(path: str) -> set:
    """字体 cmap 覆盖的码位集合。"""
    return set(TTFont(path).getBestCmap().keys())


def drop_stale_import(name: str) -> None:
    """删掉这个字重的导入产物（.fontdata / .md5）。

    这一步不能省。实测（2026-10-08）：原地换掉 woff2 后跑 --editor --quit，编辑器日志
    明明白白写着「重新导入 MiSans-Semibold.woff2」，.md5 里也记上了新文件的指纹，但
    .fontdata 还是旧字形（5,052,253 字节，与换之前的原件产物逐字节同大小，字体照旧
    报 29571 个字 = 原件 cmap 的项数）。手动删掉这对产物再扫，立刻变成 629,175 字节。
    留在这里，是因为「导入看着成功了、其实没换」这种假绿只有量尺寸才看得见。
    """
    if not os.path.isdir(IMPORT_CACHE):
        return
    prefix = name + "-"
    for fn in os.listdir(IMPORT_CACHE):
        if fn.startswith(prefix):
            os.remove(os.path.join(IMPORT_CACHE, fn))
            print(f"  清掉旧导入产物 {fn}")


def subset_font(name: str, orig_path: str, chars: set) -> tuple:
    """从备份原件裁出一份字重写回 fonts/，返回 (原件字节数, 子集字节数)。"""
    dst = os.path.join(FONTS_DIR, name)
    tmp = dst + ".subset.tmp"

    cmd = [
        sys.executable, "-m", "fontTools.subset", orig_path,
        "--output-file=" + tmp,
        "--flavor=woff2",            # woff2 体积最小，Godot 的 font_data_dynamic 直接吃
        "--text-file=" + CHARSET_FILE,
        "--layout-features=*",       # 保留全部 OpenType 特性，别让连字/替代字形走样
        "--name-IDs=*",              # 保留全部 name 记录：Godot 要靠 family name 匹配系统回退字体
        "--name-languages=*",
    ]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        if os.path.exists(tmp):
            os.remove(tmp)
        sys.exit(f"pyftsubset 失败（{name}）：\n{r.stderr or r.stdout}")

    wanted = {ord(c) for c in chars}
    missing = wanted - font_coverage(tmp)
    if missing:
        os.remove(tmp)
        sample = "".join(chr(c) for c in sorted(missing)[:20])
        sys.exit(f"子集缺字（{name}）：{len(missing)} 个码位，前 20 个「{sample}」"
                 f"\n—— 字集是本脚本算出来的，缺了说明 pyftsubset 没按预期工作，需人工查。")

    before = os.path.getsize(orig_path)
    os.replace(tmp, dst)
    after = os.path.getsize(dst)
    print(f"  {name}: {before/1e6:.2f} MB → {after/1e6:.2f} MB  (省 {(before-after)/1e6:.2f} MB)")
    drop_stale_import(name)
    return before, after


def warn_on_gamestyle_drift() -> None:
    """GameStyle 里引用了但没进 SUBSET_FONTS 的字重：要么它没被子集化（白占体积），
    要么它被 export_presets.cfg 排除了（那就直接坏字）。两种情况都值得喊一声。"""
    if not os.path.exists(GAMESTYLE):
        return
    with open(GAMESTYLE, "r", encoding="utf-8") as f:
        used = set(re.findall(r"res://fonts/([A-Za-z0-9_.-]+\.woff2)", f.read()))
    drift = sorted(u for u in used if u not in SUBSET_FONTS)
    if drift:
        print(f"  ⚠ GameStyle.gd 还引用了未纳入子集化的字重：{', '.join(drift)}")
        print(f"    把它加进本脚本的 SUBSET_FONTS，否则它要么白占包体、要么被排除后直接坏字。")


# ---------------- 入口 ----------------

def main() -> None:
    ap = argparse.ArgumentParser(description="MiSans 字体子集化")
    ap.add_argument("--charset-only", action="store_true", help="只重扫两个账本，不动字体")
    ap.add_argument("--accept-exempt", action="store_true",
                    help="确认豁免账的增删（源码里有、MiSans 渲染不了的字）")
    args = ap.parse_args()

    for n in SUBSET_FONTS:
        if not os.path.exists(os.path.join(FONTS_DIR, n)):
            sys.exit(f"fonts/ 下找不到 {n}")

    print("留档原件...")
    originals = {n: backup_original(n) for n in SUBSET_FONTS}

    print("扫描字集...")
    source_chars = scan_source_chars()
    candidate = source_chars | gb2312_chars()

    # 认准**原件**的 cmap，不看 fonts/ 里的当前文件 —— 后者第二次运行时已经是子集了。
    covered = set()
    for n in SUBSET_FONTS:
        covered |= font_coverage(originals[n])
    absent = {c for c in candidate if ord(c) not in covered}
    if absent:
        print(f"  {len(absent)} 个候选码位 MiSans 原件没有，已从字集剔除")
    charset = candidate - absent

    # 豁免账只管**源码里**出现的字：GB2312 里字体没有的那些（如 ・）不在源码里，
    # B 段压根不会问，塞进豁免账只是噪音。
    exempt = {c for c in source_chars if ord(c) not in covered}
    committed = read_char_file(EXEMPT_FILE)
    if exempt != committed:
        added = "".join(sorted(exempt - committed))
        removed = "".join(sorted(committed - exempt))
        print(f"\n豁免账有变化：")
        print(f"  新增 {len(exempt - committed)} 个「{added}」")
        print(f"  移除 {len(committed - exempt)} 个「{removed}」")
        if not args.accept_exempt:
            sys.exit("停在这里等你拍板：这些字源码里有、但 MiSans 渲染不了，只能靠系统回退字体。"
                     "\n  若它们只出现在注释里或确实可接受 → python3 tools/subset_fonts.py --accept-exempt"
                     "\n  若是新文案里带进来的、要保证字形一致 → 换字，别接受。")

    write_char_file(CHARSET_FILE, charset, "字集")
    if exempt != committed:
        write_char_file(EXEMPT_FILE, exempt, "豁免账")
    else:
        print(f"  豁免账无变化：{len(committed)} 个码位")

    if args.charset_only:
        print("只写了账本，字体未动。")
        return

    print("\n子集化...")
    warn_on_gamestyle_drift()
    before = after = 0
    for n in SUBSET_FONTS:
        b, a = subset_font(n, originals[n], chars=charset)
        before += b
        after += a

    print(f"\n完成：两份字重 {before/1e6:.2f} MB → {after/1e6:.2f} MB，省 {(before-after)/1e6:.2f} MB")
    print("下一步：")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --editor --quit")
    print("  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/FontCoverageCheck.tscn")


if __name__ == "__main__":
    main()
