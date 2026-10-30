extends RefCounted

## 皮肤效果族共用工具（纯静态，无 class_name —— 族模块一律按路径 preload，见 SkinFxLibrary）。
##
## 纪律：宿主渲染器首参 h 不标类型（鸭类型访问，避 AGENTS.md 坑 12/16 循环类依赖）；
## 无类型参数上严禁 `:=` 推断，含宿主成员的声明一律显式 `: 类型 =`。
##
## 随机纪律：全部效果走 _time / _idle_phase 的确定性 sin/cos 轨道，零随机，
## 天然不碰 GameManager.rng（避坑 15），预览抓拍也能复现同一帧。

## 当前相位（0~1 圈）。cycle 为色相绕行一圈的秒数，低于 1s 会闪成噪声，故钳到 1.0。
static func phase_of(h, p: Dictionary) -> float:
	return fposmod(h._time / maxf(float(p.get("cycle", 7.0)), 1.0), 1.0)

## 色相沿色环旋转：S/V 一律取自基准色快照（防多次流转后褪色/漂白）
static func hue_shift(base: Color, phase: float, offset: float, sat_mul: float = 1.0, val_mul: float = 1.0) -> Color:
	var hh := fposmod(base.h + phase + offset, 1.0)
	return Color.from_hsv(hh, clampf(base.s * sat_mul, 0.0, 1.0), clampf(base.v * val_mul, 0.0, 1.0), base.a)

## 逐顶点缘边彩虹色（色相沿轮廓一圈铺开），供各族的「环流描边」复用
static func rim_rainbow_cols(pts: PackedVector2Array, base_h: float, phase: float,
		sat: float, val: float, alpha: float) -> PackedColorArray:
	var cols := PackedColorArray()
	var n := pts.size()
	for i in range(n):
		var rh := fposmod(base_h + phase + float(i) / float(maxi(n, 1)), 1.0)
		cols.append(Color.from_hsv(rh, sat, val, alpha))
	return cols

## 沿轮廓游走的光段（彗星头）。返回 [点数组, 色数组]，段长 (2*half+1) 个顶点。
static func comet_segments(pts: PackedVector2Array, center_idx: int, half: int, base_h: float,
		phase: float, spread: float, sat: float, val: float, alpha: float) -> Array:
	var seg_pts := PackedVector2Array()
	var seg_cols := PackedColorArray()
	var n := pts.size()
	if n < 2:
		return [seg_pts, seg_cols]
	for off in range(-half, half + 1):
		var idx := (center_idx + off + n * 2) % n
		seg_pts.append(pts[idx])
		seg_cols.append(Color.from_hsv(fposmod(base_h + phase + float(off) * spread, 1.0), sat, val, alpha))
	return [seg_pts, seg_cols]
