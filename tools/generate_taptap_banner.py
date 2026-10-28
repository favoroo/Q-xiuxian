import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def create_banner():
  w, h = 1920, 1080
  im = Image.new("RGBA", (w, h), (10, 14, 23, 255))
  draw = ImageDraw.Draw(im)

  # 1. 战阵八卦阵圆环与辐射线 (围绕角色 x=660, y=540)
  cx, cy = 660, 540

  # 径向发散微弱青光
  glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
  glow_draw = ImageDraw.Draw(glow)
  for r in range(350, 50, -10):
    alpha = int(25 * (1.0 - r / 350.0))
    glow_draw.ellipse(
        [cx - r, cy - r, cx + r, cy + r], fill=(30, 80, 120, alpha)
    )
  glow = glow.filter(ImageFilter.GaussianBlur(25))
  im = Image.alpha_composite(im, glow)
  draw = ImageDraw.Draw(im)

  # 战台同心阵线
  line_col = (70, 140, 200, 36)
  for r in [200, 320, 440, 560]:
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=line_col, width=2)

  # 8 方位阵位虚线
  for i in range(8):
    ang = i * math.pi / 4.0
    dx, dy = math.cos(ang), math.sin(ang)
    x1, y1 = cx + dx * 160, cy + dy * 160
    x2, y2 = cx + dx * 580, cy + dy * 580
    draw.line([(x1, y1), (x2, y2)], fill=(70, 140, 200, 24), width=1)
    # 外圈阵位小菱形
    draw.ellipse(
        [x2 - 4, y2 - 4, x2 + 4, y2 + 4], fill=(90, 180, 255, 60), outline=None
    )

  # 2. 环绕法器飞剑
  weapon_paths = [
      "site/dist/img/w00.webp",
      "site/dist/img/w01.webp",
      "site/dist/img/w02.webp",
      "site/dist/img/w03.webp",
      "site/dist/img/w04.webp",
  ]
  radius = 340
  for i, wp in enumerate(weapon_paths):
    if not os.path.exists(wp):
      continue
    ang = i * (2.0 * math.pi / 5.0) - 0.4
    wx = cx + math.cos(ang) * radius
    wy = cy + math.sin(ang) * radius
    wimg = Image.open(wp).convert("RGBA")
    # 旋转飞剑使其朝向外圈或切线
    rot_deg = -math.degrees(ang + math.pi / 2.0)
    wimg_rot = wimg.rotate(rot_deg, resample=Image.BICUBIC, expand=True)
    w_w, w_h = wimg_rot.size
    im.paste(wimg_rot, (int(wx - w_w / 2), int(wy - w_h / 2)), wimg_rot)

  # 3. 主角大立绘 (使用透明通道主角前景)
  hero_path = "assets/brand/adaptive_foreground_432.png"
  if os.path.exists(hero_path):
    hero = Image.open(hero_path).convert("RGBA")
    # 裁切出主体 bounding box
    bbox = hero.getbbox()
    if bbox:
      hero = hero.crop(bbox)
    # 缩放到合适大小 (高 ~ 620px)
    scale = 620.0 / hero.height
    new_w, new_h = int(hero.width * scale), int(hero.height * scale)
    hero = hero.resize((new_w, new_h), Image.Resampling.LANCZOS)
    hx = cx - new_w // 2
    hy = cy - new_h // 2 + 10
    im.paste(hero, (hx, hy), hero)

    # 4. 右侧游戏名「剑士Q」
    tx = 1120
    ty = 430
    heavy_font = ImageFont.truetype("fonts/MiSans-Heavy.woff2", 160)
    sub_font = ImageFont.truetype("fonts/MiSans-Semibold.woff2", 40)

    # 主标题「剑士Q」
    draw.text((tx + 6, ty + 6), "剑士Q", font=heavy_font, fill=(0, 0, 0, 220))
    draw.text((tx, ty), "剑士Q", font=heavy_font, fill=(251, 248, 238, 255))

    # 英文副标「SWORDSMAN」
    draw.text(
        (tx + 4, ty + 185),
        "SWORDSMAN",
        font=sub_font,
        fill=(214, 168, 71, 255),
    )

    # 金光装饰线
    draw.line(
        [(tx, ty + 250), (tx + 420, ty + 250)], fill=(214, 168, 71, 255), width=4
    )

    out_path = "/tmp/qx_store/banner_4.png"
  im.convert("RGB").save(out_path, quality=95)
  print(f"BANNER_SAVED {out_path} size={os.path.getsize(out_path)} bytes")


if __name__ == "__main__":
  create_banner()
