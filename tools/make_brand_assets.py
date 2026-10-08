#!/usr/bin/env python3
"""修仙幸存者 品牌素材加工管线（借鉴 dudu-cocos tools/ 做法）。

输入（media-gen --keyout 产出的透明底概念图）：
  assets_raw/images/app_icon_concept.png       青衫小修士头像
  assets_raw/images/splash_emblem_concept.png  法剑+太极 emblem

输出（assets/brand/，随 APK 打包）：
  app_icon.png                 512²   Godot 项目/桌面图标（不透明）
  launcher_192.png             192²   Android 传统 launcher 图标
  adaptive_foreground_432.png  432²   自适应图标前景（主体缩进 66% 安全圆）
  adaptive_background_432.png  432²   自适应图标背景（深青黑径向底）
  splash_logo.png              1024²  启动画面（透明底 RGBA，无文字）

底色链：图标底/启动底/游戏 clearColor 同族深青黑（项目 default_clear_color ≈ #090D17），
splash 非主体区域 alpha=0，Godot boot splash 淡入全程与整屏底色无接缝。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICON_SRC = ROOT / "assets_raw/images/app_icon_concept.png"
EMBLEM_SRC = ROOT / "assets_raw/images/splash_emblem_concept.png"
OUT = ROOT / "assets/brand"

BG_CENTER = (16, 26, 46)   # #101A2E 图标底中心
BG_EDGE = (9, 13, 23)      # #090D17 图标底边缘 = 游戏 clearColor
FG_SAFE_RATIO = 0.66       # adaptive icon 安全区（直径占比）
SPLASH_CANVAS = 1024
SPLASH_SUBJECT = 560       # splash 主体最长边


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


def radial_background(size: int) -> Image.Image:
    """深青黑径向渐变底：中心略亮，边缘落到游戏 clearColor。"""
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((x - size / 2) ** 2 + (y - size / 2) ** 2) / (size / np.sqrt(2))
    t = np.clip(d, 0, 1)[..., None]
    center = np.array(BG_CENTER, dtype=np.float32)
    edge = np.array(BG_EDGE, dtype=np.float32)
    rgb = center * (1 - t) + edge * t
    return Image.fromarray(rgb.astype(np.uint8))


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


def add_bloom(img: Image.Image, threshold: int = 170, blur: int = 18) -> Image.Image:
    """高光柔光：亮部高斯模糊后 screen 叠加（仅用于不透明底的图标）。"""
    arr = np.asarray(img.convert("RGB")).astype(np.float32)
    bright = np.clip(arr - threshold, 0, 255)
    glow = Image.fromarray(bright.astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))
    g = np.asarray(glow).astype(np.float32)
    out = 255 - (255 - arr) * (255 - g) / 255
    return Image.fromarray(out.astype(np.uint8))


def add_vignette(img: Image.Image, strength: float = 0.18) -> Image.Image:
    size = img.width
    y, x = np.mgrid[0:size, 0:img.height].astype(np.float32)
    d = np.sqrt((x - size / 2) ** 2 + (y - img.height / 2) ** 2) / (size / np.sqrt(2))
    mask = (1 - strength * np.clip(d, 0, 1) ** 2)[..., None]
    arr = np.asarray(img.convert("RGB")).astype(np.float32) * mask
    return Image.fromarray(arr.astype(np.uint8))


def make_icon_master() -> Image.Image:
    subject = enhance_subject(load_trimmed(ICON_SRC))
    canvas = radial_background(1024).convert("RGBA")
    subject = fit(subject, 880, 880)
    paste_center(canvas, subject)
    icon = add_bloom(canvas.convert("RGB"))
    return add_vignette(icon)


def make_adaptive_foreground() -> Image.Image:
    subject = enhance_subject(load_trimmed(ICON_SRC))
    canvas = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    # 竖构图主体按外接圆对角线收进安全圆（0.94 余量），而非按边长适配
    limit = 432 * FG_SAFE_RATIO / 2 * 0.94
    diag = (subject.width ** 2 + subject.height ** 2) ** 0.5
    scale = limit * 2 / diag
    size = (round(subject.width * scale), round(subject.height * scale))
    paste_center(canvas, subject.resize(size, Image.LANCZOS))
    return canvas


def make_splash() -> Image.Image:
    emblem = enhance_subject(load_trimmed(EMBLEM_SRC))
    canvas = Image.new("RGBA", (SPLASH_CANVAS, SPLASH_CANVAS), (0, 0, 0, 0))
    emblem = fit(emblem, SPLASH_SUBJECT, SPLASH_SUBJECT)
    paste_center(canvas, emblem)
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
        if r > limit:
            fail(f"{path.name} 主体超出安全圆：r={r:.0f} > {limit:.0f}")
    print(f"OK: {path.relative_to(ROOT)} ({size}²)")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    master = make_icon_master()
    master.resize((512, 512), Image.LANCZOS).save(OUT / "app_icon.png")
    master.resize((192, 192), Image.LANCZOS).save(OUT / "launcher_192.png")
    make_adaptive_foreground().save(OUT / "adaptive_foreground_432.png")
    radial_background(432).save(OUT / "adaptive_background_432.png")
    make_splash().save(OUT / "splash_logo.png")

    check(OUT / "app_icon.png", 512, opaque=True)
    check(OUT / "launcher_192.png", 192, opaque=True)
    check(OUT / "adaptive_foreground_432.png", 432, opaque=False, safe_zone=True)
    check(OUT / "adaptive_background_432.png", 432, opaque=True)
    check(OUT / "splash_logo.png", SPLASH_CANVAS, opaque=False)
    print("DONE: assets/brand/ 全部素材已生成并通过自检")


if __name__ == "__main__":
    main()
