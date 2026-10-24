#!/usr/bin/env python3
"""武器 UI 图标同步：新野兽派矢量本体 → assets/art/ui/ 128px 高清变体

背景
----
战斗里的武器本体已是纯矢量（ProceduralWeaponRenderer / TurretRenderer / DroneRenderer），
但商店 / 图鉴 / 背包槽位显示的是 assets/art/ui/weapon_*.png（128px 静态贴图）。
旧链路靠 tools/reexport_all_icons_128.py 从 assets_raw/images/ 的 AI 插画重烘焙，
重绘矢量本体后那条链路不会跟着变 ⇒ 战斗是新风、UI 仍是旧风（画风断层）。

本脚本做两件事（顺序固定，别倒过来）：
  1. 调 Godot 跑 tests/WeaponIconExport.tscn，把 70 把武器的矢量本体抓成 512 透明 PNG
     （导出层保证与战斗观感零偏差；同器形同五行的武器由导出层叠「专属细节」区分）
  2. 把 512 图裁掉透明边、缩放居中贴进 128x128 画布，落 assets/art/ui/<basename>.png

战斗画布 assets/art/weapon_*.png（48x48）一律不动 —— 它的坐标系与 WeaponData.tip
剑尖坐标严格绑定，改它等于「战场武器变大」回归。

用法
----
    python3 tools/sync_weapon_ui_icons.py            # 完整同步（导出 + 落盘）
    python3 tools/sync_weapon_ui_icons.py --no-export # 只用 /tmp 已有导出图重新落盘
"""
import glob
import os
import subprocess
import sys

from PIL import Image

GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = "/tmp/weapon_icon_raw"
UI_DIR = os.path.join(PROJECT, "assets", "art", "ui")
TARGET = 128
SAFE_MARGIN = 6  # 四周安全边距（像素），避免描边被裁


def run_export() -> bool:
    """调 Godot 开窗跑导出工具，把矢量本体抓成 512 PNG。"""
    if not os.path.exists(GODOT):
        print("[Error] 找不到 Godot：%s" % GODOT)
        return False
    cmd = [
        GODOT, "--path", PROJECT,
        "res://tests/WeaponIconExport.tscn",
        "--", "--out", RAW_DIR,
    ]
    print("[Sync] 导出矢量图标 …")
    proc = subprocess.run(cmd, cwd=PROJECT, capture_output=True, text=True)
    tail = (proc.stdout or "") + (proc.stderr or "")
    for line in tail.splitlines():
        if "WeaponIconExport" in line or "ERROR" in line or "SCRIPT ERROR" in line:
            print("  " + line.strip())
    if proc.returncode != 0:
        print("[Error] 导出失败，退出码 %d" % proc.returncode)
        return False
    return True


def fit_to_128(src_path: str, dst_path: str) -> bool:
    """裁透明边 → 缩放 → 居中贴进 128x128（保留 SAFE_MARGIN 安全边距）。"""
    try:
        im = Image.open(src_path).convert("RGBA")
        bbox = im.getchannel("A").point(lambda v: 255 if v > 20 else 0).getbbox()
        if bbox:
            im = im.crop(bbox)
        inner = TARGET - SAFE_MARGIN * 2
        im.thumbnail((inner, inner), Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))
        canvas.paste(
            im,
            ((TARGET - im.size[0]) // 2, (TARGET - im.size[1]) // 2),
            im,
        )
        canvas.save(dst_path, "PNG")
        return True
    except Exception as exc:  # noqa: BLE001
        print("[Error] %s -> %s: %s" % (src_path, dst_path, exc))
        return False


def main() -> int:
    if "--no-export" not in sys.argv:
        if not run_export():
            return 1

    os.makedirs(UI_DIR, exist_ok=True)
    raws = sorted(glob.glob(os.path.join(RAW_DIR, "*.png")))
    if not raws:
        print("[Error] %s 下没有导出图，先跑一次带导出的同步" % RAW_DIR)
        return 1

    ok = 0
    for raw in raws:
        base = os.path.basename(raw)
        if fit_to_128(raw, os.path.join(UI_DIR, base)):
            ok += 1
    print("[Sync] 已同步 %d/%d 个武器 UI 图标 → assets/art/ui/ (%dpx)" % (ok, len(raws), TARGET))
    print("[Sync] 战斗画布 assets/art/weapon_*.png（48x48）未改动")
    return 0 if ok == len(raws) else 1


if __name__ == "__main__":
    raise SystemExit(main())
