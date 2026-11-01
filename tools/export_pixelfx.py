#!/usr/bin/env python3
"""pixelfx 精灵表导出与 Godot 资源构建管线。

功能：
1. 读取 tools/pixelfx_manifest.json 配置
2. 调用 vendored node render.mjs 导出透明帧
3. 自动剔除全透明冗余帧、按 max_frames 均匀抽稀、排布紧凑网格
4. 输出 assets/art/fx_pixelfx/<out_name>.png、<out_name>.json 以及标准的 <out_name>.tres (SpriteFrames)
"""

import os
import sys
import json
import math
import subprocess
from pathlib import Path
from PIL import Image

ROOT_DIR = Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT_DIR / "tools" / "pixelfx_manifest.json"
OUT_ART_DIR = ROOT_DIR / "assets" / "art" / "fx_pixelfx"
NODE_RENDER_SCRIPT = ROOT_DIR / "tools" / "pixelfx" / "tools" / "render.mjs"

# 调色板映射（与 pixelfx src/core/color.js PAL 保持一致）
PALETTES = {
    "fire": ["#1f0b10", "#4a1118", "#8c1d1c", "#cc3a1a", "#f2701f", "#ffae35", "#ffe27a", "#fff8d6"],
    "ember": ["#1a0a0e", "#3d1012", "#701a14", "#a8301a", "#e0561e", "#ff8a2a", "#ffc46a"],
    "ice": ["#0c1430", "#162c5c", "#1f4f94", "#2f7fcc", "#58b4ec", "#9bdcff", "#d8f4ff", "#ffffff"],
    "water": ["#081830", "#0e2e5a", "#14508c", "#1c76bc", "#36a2e0", "#78ccf4", "#c4ecff", "#ffffff"],
    "electric": ["#0a0f2e", "#172a78", "#2550d0", "#3f8cff", "#7cc8ff", "#c8f0ff", "#ffffff"],
    "volt": ["#24160a", "#5e3a0c", "#a8680f", "#e8a218", "#ffd23c", "#fff08a", "#ffffff"],
    "poison": ["#0d1a0c", "#173a14", "#265e18", "#3f8a1e", "#6cb82a", "#a8e04a", "#e0ff8a"],
    "holy": ["#2a1c08", "#5a3e10", "#9a6c18", "#d8a428", "#ffd84a", "#fff09a", "#fffbe6", "#ffffff"],
    "heal": ["#08201a", "#0f3f2c", "#17663e", "#24924e", "#3ec466", "#7ee88a", "#c8ffc4", "#ffffff"],
    "arcane": ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"],
    "shadow": ["#050308", "#0f0a18", "#1c1230", "#2c1a4a", "#432468", "#5e3290", "#8048b8", "#a970e0"],
    "earth": ["#140e0a", "#2a1e14", "#47321e", "#69492a", "#8e6638", "#b88a52", "#dcb47c"],
    "gold": ["#1e1206", "#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"],
    "metal": ["#0c0e14", "#1c2230", "#2e3648", "#4a5468", "#6e7a90", "#9aa6ba", "#d0d8e6", "#ffffff"],
}


def is_frame_empty(img_frame: Image.Image) -> bool:
    """检查单帧是否完全透明"""
    if img_frame.mode != "RGBA":
        img_frame = img_frame.convert("RGBA")
    extrema = img_frame.getextrema()
    # extrema[3] 为 alpha 通道 (min_alpha, max_alpha)
    return extrema[3][1] == 0


def generate_godot_sprite_frames(tres_path: Path, png_rel_path: str, frames_rects: list, fps: float, loop: bool):
    """直接生成标准 Godot 4.7 SpriteFrames .tres 资源文件"""
    lines = [
        '[gd_resource type="SpriteFrames" format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{png_rel_path}" id="1_tex"]',
        ""
    ]

    for idx, (rx, ry, rw, rh) in enumerate(frames_rects):
        lines.append(f'[sub_resource type="AtlasTexture" id="AtlasTexture_{idx}"]')
        lines.append('atlas = ExtResource("1_tex")')
        lines.append(f"region = Rect2({rx}, {ry}, {rw}, {rh})")
        lines.append("")

    lines.append("[resource]")
    lines.append("animations = [{")
    lines.append('"frames": [')
    frame_entries = []
    for idx in range(len(frames_rects)):
        frame_entries.append(
            '{\n"duration": 1.0,\n"texture": SubResource("AtlasTexture_' + str(idx) + '")\n}'
        )
    lines.append(", ".join(frame_entries))
    lines.append("],")
    lines.append(f'"loop": {"true" if loop else "false"},')
    lines.append('"name": &"default",')
    lines.append(f'"speed": {fps:.1f}')
    lines.append("}]")

    tres_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def export_item(item: dict, tmp_dir: Path) -> dict:
    fx_id = item["id"]
    out_name = item["out_name"]
    fps = item.get("fps", 24)
    max_frames = item.get("max_frames", 30)
    loop = item.get("loop", False)
    scale = item.get("scale", 1.0)
    palette_key = item.get("palette_key", "")
    anchor = item.get("anchor", "center")

    opts = {}
    if palette_key in PALETTES:
        opts["palette"] = PALETTES[palette_key]

    render_out_dir = tmp_dir / out_name
    render_out_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        "node",
        str(NODE_RENDER_SCRIPT),
        fx_id,
        "--sheet",
        "--no-actor",
        "--fps", str(fps),
        "--out", str(render_out_dir)
    ]
    if opts:
        cmd.extend(["--opts", json.dumps(opts)])

    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=str(ROOT_DIR))
    if res.returncode != 0:
        raise RuntimeError(f"render.mjs failed for {fx_id}:\n{res.stderr}\n{res.stdout}")

    # 寻找生成的 json 与 png
    json_candidates = list(render_out_dir.glob("*/*/*.json")) + list(render_out_dir.glob("*/*.json"))
    if not json_candidates:
        raise FileNotFoundError(f"No JSON found in {render_out_dir}")
    raw_json_path = json_candidates[0]
    raw_png_path = raw_json_path.with_suffix(".png")

    with open(raw_json_path, "r", encoding="utf-8") as f:
        meta = json.load(f)

    raw_frames = meta["frames"]
    raw_pixelfx_meta = meta["meta"]["pixelfx"]
    fw, fh = raw_pixelfx_meta["frameSize"]
    pivot = raw_pixelfx_meta.get("pivot", [fw // 2, fh // 2])

    sheet_img = Image.open(raw_png_path).convert("RGBA")

    # 提取每一帧
    frames_img = []
    for f_info in raw_frames:
        r = f_info["frame"]
        box = (r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])
        frame_crop = sheet_img.crop(box)
        frames_img.append(frame_crop)

    # 剔除尾部纯透明帧（若非 loop）
    if not loop and len(frames_img) > 1:
        while len(frames_img) > 2 and is_frame_empty(frames_img[-1]):
            frames_img.pop()

    total_extracted = len(frames_img)

    # 抽稀：若帧数仍超过 max_frames，按等距均匀抽取（必须包含第 0 帧和最后一帧）
    if total_extracted > max_frames:
        sampled_indices = []
        for i in range(max_frames):
            idx = int(round(i * (total_extracted - 1) / (max_frames - 1)))
            if not sampled_indices or idx != sampled_indices[-1]:
                sampled_indices.append(idx)
        # 补全或修正
        final_frames = [frames_img[i] for i in sampled_indices]
    else:
        final_frames = frames_img

    n_frames = len(final_frames)
    cols = min(n_frames, max(1, math.ceil(math.sqrt((n_frames * fh) / fw))))
    rows = math.ceil(n_frames / cols)

    final_sheet = Image.new("RGBA", (cols * fw, rows * fh), (0, 0, 0, 0))
    frame_rects = []
    for idx, f_img in enumerate(final_frames):
        c = idx % cols
        r = idx // cols
        px = c * fw
        py = r * fh
        final_sheet.paste(f_img, (px, py))
        frame_rects.append((px, py, fw, fh))

    # 输出文件
    OUT_ART_DIR.mkdir(parents=True, exist_ok=True)
    out_png_path = OUT_ART_DIR / f"{out_name}.png"
    out_tres_path = OUT_ART_DIR / f"{out_name}.tres"
    out_meta_path = OUT_ART_DIR / f"{out_name}.json"

    final_sheet.save(out_png_path, "PNG", optimize=True)

    godot_res_path = f"res://assets/art/fx_pixelfx/{out_name}.png"
    generate_godot_sprite_frames(out_tres_path, godot_res_path, frame_rects, fps, loop)

    out_meta = {
        "id": fx_id,
        "out_name": out_name,
        "frame_size": [fw, fh],
        "pivot": pivot,
        "anchor": anchor,
        "scale": scale,
        "fps": fps,
        "loop": loop,
        "frames_count": n_frames,
        "palette_key": palette_key,
        "png_bytes": out_png_path.stat().st_size,
        "vram_kb": (cols * fw * rows * fh * 4) // 1024
    }
    with open(out_meta_path, "w", encoding="utf-8") as f:
        json.dump(out_meta, f, indent=2, ensure_ascii=False)

    return out_meta


def main():
    if not MANIFEST_PATH.exists():
        print(f"Error: manifest not found at {MANIFEST_PATH}")
        sys.exit(1)

    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    effects = manifest.get("effects", [])
    print(f"=== 开始导出 pixelfx 特效 ({len(effects)} 项) ===")

    tmp_dir = Path("/tmp/pixelfx_export_tmp")
    tmp_dir.mkdir(parents=True, exist_ok=True)

    results = []
    total_vram_kb = 0
    total_png_kb = 0

    for item in effects:
        print(f"-> 导出 {item['out_name']} ({item['id']})...", end=" ", flush=True)
        res = export_item(item, tmp_dir)
        results.append(res)
        total_vram_kb += res["vram_kb"]
        total_png_kb += res["png_bytes"] // 1024
        print(f"完成! {res['frames_count']}f {res['frame_size'][0]}x{res['frame_size'][1]} PNG: {res['png_bytes']//1024}KB, VRAM: {res['vram_kb']}KB")

    print("\n================ 汇总统计 ================")
    print(f"总效果项数: {len(results)}")
    print(f"总磁盘占用 (PNG): {total_png_kb} KB (~{total_png_kb / 1024:.2f} MB)")
    print(f"总显存预估 (VRAM): {total_vram_kb} KB (~{total_vram_kb / 1024:.2f} MB)")
    print(f"单效果最大显存: {max(r['vram_kb'] for r in results)} KB")
    print(f"产物目录: {OUT_ART_DIR}")
    print("==========================================")


if __name__ == "__main__":
    main()
