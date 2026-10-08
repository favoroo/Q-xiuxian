#!/usr/bin/env python3
"""修仙幸存者 品牌素材加工管线（借鉴 dudu-cocos tools/ 做法）。

输入（media-gen --keyout 产出的透明底概念图）：
  assets_raw/images/app_icon_concept.png       青衫小修士头像

输出（assets/brand/，随 APK 打包）：
  app_icon.png                 512²   Godot 项目/桌面图标 + Godot boot splash（不透明白底）
  launcher_192.png             192²   Android 传统 launcher 图标
  adaptive_foreground_432.png  432²   自适应图标前景（主体外接圆撑满 66% 安全圆）
  adaptive_background_432.png  432²   自适应图标背景（纯白）

底色链：图标底 / Android 系统 splash 圆标底 / Godot boot splash 底全为纯白，
启动全程（系统圆标 → boot splash → 进游戏）只出现一个视觉主体（白底修士头像），无切图感。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

ROOT = Path(__file__).resolve().parent.parent
ICON_SRC = ROOT / "assets_raw/images/app_icon_concept.png"
OUT = ROOT / "assets/brand"

FG_SAFE_RATIO = 0.66       # adaptive icon 安全区（直径占比）
WHITE = (255, 255, 255)    # 纯白底：无边框、无渐变、无暗角


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def load_trimmed(path: Path) -> Image.Image:
    if not path.exists():
        fail(f"缺少概念图 {path}，先运行 media-gen gen_image.sh")
    img = Image.open(path).convert("RGBA")
    bbox = img.getchannel("A").getbbox()
    if bbox is None:
        fail(f"{path.name} 完全没有不透明像素")
    return img.crop(bbox)


def solid_background(size: int) -> Image.Image:
    """纯白底：无渐变、无暗角，避免任何边框感。"""
    return Image.new("RGB", (size, size), WHITE)


def fit(img: Image.Image, max_w: int, max_h: int) -> Image.Image:
    scale = min(max_w / img.width, max_h / img.height)
    size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
    return img.resize(size, Image.LANCZOS)


def paste_center(base: Image.Image, fg: Image.Image) -> Image.Image:
    base.alpha_composite(fg, ((base.width - fg.width) // 2, (base.height - fg.height) // 2))
    return base


def enhance_subject(img: Image.Image) -> Image.Image:
    """色彩提纯（对齐 dudu 的 Color 1.10 / Contrast 1.04），只调 RGB 不动 alpha。"""
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(1.10)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.04)
    rgb.putalpha(img.getchannel("A"))
    return rgb


def make_icon_master() -> Image.Image:
    subject = enhance_subject(load_trimmed(ICON_SRC))
    canvas = solid_background(1024).convert("RGBA")
    # 人物撑满画布：上下不留底色空白（用户要求图标下方无留白）
    subject = fit(subject, 1024, 1024)
    paste_center(canvas, subject)
    return canvas


def make_adaptive_foreground() -> Image.Image:
    subject = enhance_subject(load_trimmed(ICON_SRC))
    canvas = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    # 竖构图主体按外接圆对角线撑满安全圆（无余量），减少圆标裁切时的四周/底部留白
    limit = 432 * FG_SAFE_RATIO / 2
    diag = (subject.width ** 2 + subject.height ** 2) ** 0.5
    scale = limit * 2 / diag
    size = (round(subject.width * scale), round(subject.height * scale))
    paste_center(canvas, subject.resize(size, Image.LANCZOS))
    return canvas


def check(path: Path, size: int, opaque: bool, safe_zone: bool = False) -> None:
    img = Image.open(path)
    if img.size != (size, size):
        fail(f"{path.name} 尺寸 {img.size} != {size}²")
    a = np.asarray(img.convert("RGBA"))[..., 3]
    corners = [a[0, 0], a[0, -1], a[-1, 0], a[-1, -1]]
    if opaque and a.min() < 255:
        fail(f"{path.name} 应完全不透明")
    if not opaque and max(corners) != 0:
        fail(f"{path.name} 四角 alpha 必须为 0，实际 {corners}")
    if safe_zone:
        ys, xs = np.where(a > 8)
        half = size / 2
        r = np.sqrt((xs - half) ** 2 + (ys - half) ** 2).max()
        limit = size * FG_SAFE_RATIO / 2
        if r > limit + 0.5:  # 0.5px 容差：主体按外接圆撑满安全圆时恰好贴边
            fail(f"{path.name} 主体超出安全圆：r={r:.0f} > {limit:.0f}")
    print(f"OK: {path.relative_to(ROOT)} ({size}²)")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    master = make_icon_master()
    master.resize((512, 512), Image.LANCZOS).save(OUT / "app_icon.png")
    master.resize((192, 192), Image.LANCZOS).save(OUT / "launcher_192.png")
    make_adaptive_foreground().save(OUT / "adaptive_foreground_432.png")
    solid_background(432).save(OUT / "adaptive_background_432.png")

    check(OUT / "app_icon.png", 512, opaque=True)
    check(OUT / "launcher_192.png", 192, opaque=True)
    check(OUT / "adaptive_foreground_432.png", 432, opaque=False, safe_zone=True)
    check(OUT / "adaptive_background_432.png", 432, opaque=True)
    print("DONE: assets/brand/ 全部素材已生成并通过自检")


if __name__ == "__main__":
    main()
