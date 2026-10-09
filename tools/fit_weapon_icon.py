#!/usr/bin/env python3
"""把抠好透明底的法器原稿落成游戏画布，并实测「剑尖/器口」标定值。

用法:
    python3 tools/fit_weapon_icon.py <原稿.png> <产物.png> <画布宽> <画布高>
                                     [--rotate 角度] [--no-tip-align]

为什么需要它（2026-10-09，庚金飞剑返工）：
WeaponData 的 "tip" 是手打的 Vector2，标错一头（把剑柄当剑尖）代码完全发现不了 ——
FloatingWeapon 的贴图补偿与出膛点都只按这个数走，于是"剑尖永远背对敌人、弹丸从剑柄冒出来"。
本脚本让标定变成实测：落图后直接打印尖端相对画布中心的像素值，抄进 WeaponData 就是真话，
并顺手量出「尖端 vs 柄端」的粗细与上下对称度，作为朝向标反的现场证据。

--rotate 角度：把高分辨率原稿绕刃轴逆时针转该角度（正值 = 剑尖朝右上）再铺进画布。
  笔直长剑横着铺进方框只剩一条细线，斜铺才和同门方形图标一样饱满；而游戏里贴图本来就会
  被转到瞄准轴上（FloatingWeapon._apply_facing），所以图标摆哪个角度不影响在战场上的朝向。
--no-tip-align：只居中，不把尖端所在水平线压到画布中线（用于符箓/宝灯/印玺这类不成轴的素材）。
"""
import math
import sys

import numpy as np
from PIL import Image

ALPHA_CUT = 24  # 低于此 alpha 视为背景（与既有图标的软边一致）


def drop_orphans(img: Image.Image) -> tuple[Image.Image, int]:
	"""4 邻域孤点清理：生图残留的单像素碎点会把包围盒撑大、把 tip 标定带偏。"""
	a = np.array(img.convert("RGBA"))
	al = a[..., 3] > ALPHA_CUT
	neigh = np.zeros_like(al)
	for dy in (-1, 0, 1):
		for dx in (-1, 0, 1):
			if dx == 0 and dy == 0:
				continue
			neigh |= np.roll(np.roll(al, dy, 0), dx, 1)
	kill = al & ~neigh
	a[..., 3] = np.where(kill, 0, a[..., 3])
	return Image.fromarray(a), int(kill.sum())


def shift(arr: np.ndarray, dx: int, dy: int) -> np.ndarray:
	"""整幅平移，出界部分丢弃（不 wrap）。"""
	out = np.zeros_like(arr)
	h, w = arr.shape[:2]
	sy0, sy1 = max(0, -dy), min(h, h - dy)
	sx0, sx1 = max(0, -dx), min(w, w - dx)
	if sy0 >= sy1 or sx0 >= sx1:
		return out
	out[sy0 + dy:sy1 + dy, sx0 + dx:sx1 + dx] = arr[sy0:sy1, sx0:sx1]
	return out


def opaque(arr: np.ndarray) -> np.ndarray:
	return arr[..., 3] > ALPHA_CUT


def harden_and_outline(arr: np.ndarray, cut: int = 128,
		rim_mul: float = 0.30) -> np.ndarray:
	"""alpha 二值化 + 复原 1px 深色描边。

	原稿 256px 缩到 48px 时，黑色描边被平均进金色里 ⇒ 图标发灰、和同门那批
	「粗黑色描边」（STYLE.md）的饱和图标摆在一起像没抠干净。这里把边缘收硬，
	再给贴着透明侧的一圈像素压暗，等于把描边重新画回去。二值 alpha 也让
	Nearest 过滤下的旋转边缘不产生半透明晕。
	"""
	out = arr.copy()
	al = out[..., 3] > cut
	out[..., 3] = np.where(al, 255, 0).astype(np.uint8)
	touching = np.zeros_like(al)
	for dy in (-1, 0, 1):
		for dx in (-1, 0, 1):
			if dx == 0 and dy == 0:
				continue
			touching |= ~np.roll(np.roll(al, dy, 0), dx, 1)
	rim = al & touching
	rgb = out[..., :3].astype(np.float32) * rim_mul
	out[..., :3] = np.where(rim[..., None], rgb.round().clip(0, 255), out[..., :3]).astype(np.uint8)
	return out


def tip_row(al: np.ndarray) -> tuple[int, int]:
	"""(最右不透明列, 该列不透明像素的平均行) —— 尖端所在的水平线。"""
	xs = np.nonzero(al)[1]
	x = int(xs.max())
	return x, int(np.nonzero(al[:, x])[0].mean())


def fit(src: str, dst: str, cw: int, ch: int, rot_deg: float = 0.0,
		tip_align: bool = True, outline: bool = True) -> None:
	im = Image.open(src).convert("RGBA")
	im, dropped = drop_orphans(im)
	mask = im.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
	bbox = mask.getbbox()
	if bbox is None:
		sys.exit(f"错误: {src} 没有不透明内容")
	im = im.crop(bbox)

	if rot_deg:
		# 先在高分辨率下把刃轴摆到画布正中，再绕该点旋转 —— 低分辨率转会有锯齿台阶
		a = np.array(im)
		row = tip_row(opaque(a))[1]
		side = max(im.size)
		square = np.zeros((side, side, 4), np.uint8)
		square[(side - im.height) // 2:(side - im.height) // 2 + im.height,
			(side - im.width) // 2:(side - im.width) // 2 + im.width] = a
		square = shift(square, 0, (side // 2) - ((side - im.height) // 2 + row))
		im = Image.fromarray(square).rotate(rot_deg, resample=Image.BICUBIC,
			expand=True, center=(side / 2 - 0.5, side / 2 - 0.5))
		mask = im.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0)
		bb = mask.getbbox()
		im = im.crop(bb) if bb else im

	# 长边铺满画布（留 1px 边距，与「主体不接触画面边缘」同一条纪律）
	scale = min((cw - 2) / im.width, (ch - 2) / im.height)
	im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)

	canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
	canvas.paste(im, ((cw - im.width) // 2, (ch - im.height) // 2), im)
	arr = np.array(canvas)

	if tip_align and not rot_deg:
		x, row = tip_row(opaque(arr))
		arr = shift(arr, 0, ch // 2 - row)  # 让尖端落在画布中线 ⇒ tip.y == 0
	if outline:
		arr = harden_and_outline(arr)

	Image.fromarray(arr).save(dst)

	al = opaque(arr)
	ys, xs = np.nonzero(al)
	cx, cy = cw / 2 - 0.5, ch / 2 - 0.5
	x, row = tip_row(al)  # 最右列那一头 = 作者画的尖端朝向往的那边
	tip = (x - cx, row - cy)
	ang = math.atan2(tip[1], tip[0])
	ux, uy = math.cos(ang), math.sin(ang)   # 刃轴单位向量
	vx, vy = -uy, ux                          # 垂直于刃轴
	pts = list(zip(xs.tolist(), ys.tolist()))
	proj = lambda p: (p[0] - cx) * ux + (p[1] - cy) * uy
	t_max, t_min = max(map(proj, pts)), min(map(proj, pts))

	def hit(px: float, py: float) -> bool:
		ix, iy = int(round(px)), int(round(py))
		return 0 <= ix < cw and 0 <= iy < ch and bool(al[iy, ix])

	def width_at(t: float) -> int:
		"""刃轴上 t 那一处，垂直方向连着数得有多宽（0 = 该处没有像素）。"""
		bx, by = cx + ux * t, cy + uy * t
		if not hit(bx, by):
			for k in range(1, 13):
				if hit(bx + vx * k, by + vy * k):
					bx, by = bx + vx * k, by + vy * k
					break
				if hit(bx - vx * k, by - vy * k):
					bx, by = bx - vx * k, by - vy * k
					break
			else:
				return 0
		n = 1
		for s in (1, -1):
			k = 1.0
			while hit(bx + vx * s * k, by + vy * s * k):
				n += 1
				k += 1.0
		return n

	def profile(t_ext: float) -> str:
		return " ".join(str(width_at(t_ext * f)) for f in (1.0, 0.75, 0.5, 0.25))

	top, bot = int(cy - ys.min()), int(ys.max() - cy)
	print(f"WROTE {dst} canvas={cw}x{ch} dropped_orphans={dropped} rotate={rot_deg}°")
	print(f"  bbox      x[{xs.min()}..{xs.max()}] y[{ys.min()}..{ys.max()}]  占画布对角 {math.hypot(xs.max()-xs.min(), ys.max()-ys.min()):.0f}px")
	print(f"  tip       Vector2({tip[0]:.0f}, {tip[1]:.0f})   # 离中心 {math.hypot(*tip):.1f}px，方位 {math.degrees(ang):.1f}°")
	# 刃轴宽度剖面（外→内四档）。剑应当"尖端 1~2px 收细、往里才是 6~7px 的剑身"。
	# 注意：圆剑首那一头端点同样细（实测旧图两端都是 1~2px），所以这两条剖面只能证明
	# "你量的是一根有尖刃的轴"，认不出哪头是尖 —— 朝向标没标反要看 WeaponAimPreview 出的图。
	print(f"  宽度剖面  最右那头(外→内) {profile(t_max)}   最左那头(外→内) {profile(t_min)}")
	print(f"          轴长 {t_max:.0f}px / {t_min:.0f}px")
	print(f"  symmetry  上{top}px / 下{bot}px  差={abs(top-bot)}px  ← 朝左时 flip_v 镜像，差太大就是两把剑")


if __name__ == "__main__":
	pos: list[str] = []
	rot, align, outline = 0.0, True, True
	skip = False
	for i, a in enumerate(sys.argv[1:]):
		if skip:
			skip = False
			continue
		if a == "--no-tip-align":
			align = False
		elif a == "--no-outline":
			outline = False
		elif a == "--rotate":
			rot = float(sys.argv[i + 2])
			skip = True
		else:
			pos.append(a)
	if len(pos) != 4:
		sys.exit(__doc__)
	fit(pos[0], pos[1], int(pos[2]), int(pos[3]), rot, align, outline)
