class_name RunMotion
extends RefCounted

## 方向动画选择 + 代码驱动的跑步节奏动画。
## 方向图集为 5 行（s/n/e/se/ne）× 5 列（待机 + 4 帧跑步），左/左下/左上由 flip_h 补齐；
## AI 差分帧的逐格漂移在拼装管线（tools/build_run8_atlas.py）里底对齐归一化，
## 跑步的节奏感（颠簸/挤压/前倾）由这里逐帧驱动。

const LIFT := 1.4      # 步态起伏高度（双脚踩点与腾空节奏分明）
const SQUASH := 0.018  # 步伐触地与腾空弹性形变比例
const LEAN_DEG := 2.6  # 奔跑前倾角度（按移动方向的水平分量缩放，竖直奔跑不前倾）
const BREATH_AMP := 0.011 # 待机呼吸幅度
const HYSTERESIS_DEG := 29.0 # 8方向扇区切换迟滞阈值（大于 22.5° 边界角，彻底消除临界角度抖动）

## 方向图集的行序：动画后缀 → 图集行号
const DIR_ROW := {"s": 0, "n": 1, "e": 2, "se": 3, "ne": 4}

## 8 扇区配置表：扇区编号 0..7 → [动画后缀, 是否水平翻转, 扇区中心角(度)]
const SECTOR_TABLE := [
	["e", false, 0.0],     # 0: 东 (0°)
	["se", false, 45.0],   # 1: 东南 (45°)
	["s", false, 90.0],    # 2: 南 (90°)
	["se", true, 135.0],   # 3: 西南 (135°)
	["e", true, 180.0],    # 4: 西 (180°/-180°)
	["ne", true, -135.0],  # 5: 西北 (-135°)
	["n", false, -90.0],   # 6: 北 (-90°)
	["ne", false, -45.0],  # 7: 东北 (-45°)
]

## 移动方向 → [动画后缀, 是否水平翻转]（无状态兼容接口）
static func facing(dir: Vector2) -> Array:
	return facing_stable(dir, "", false)

## 带迟滞滤波（Hysteresis）的 8 方向判定：
## 当输入角度仍在当前扇区中心 ±HYSTERESIS_DEG (29°) 范围内时保持原方向不变，
## 彻底根治摇杆或追击向量在 22.5° 象限交界处引起的朝向/flip_h 每帧高频抽搐。
static func facing_stable(dir: Vector2, cur_facing: String, cur_flip: bool, threshold_deg: float = HYSTERESIS_DEG) -> Array:
	if dir.length_squared() < 0.0025:
		return [cur_facing, cur_flip]

	var angle_deg := rad_to_deg(dir.angle())

	# 若已有合法朝向，检查当前角度是否仍在迟滞维持区内
	if cur_facing != "":
		var cur_sector := _find_sector(cur_facing, cur_flip)
		if cur_sector >= 0:
			var center_deg: float = SECTOR_TABLE[cur_sector][2]
			var diff := absf(_angle_diff_deg(angle_deg, center_deg))
			if diff <= threshold_deg:
				return [cur_facing, cur_flip]

	var sector := wrapi(int(floor((angle_deg + 22.5) / 45.0)), 0, 8)
	var entry: Array = SECTOR_TABLE[sector]
	return [entry[0], entry[1]]

static func _find_sector(anim_dir: String, flip_h: bool) -> int:
	for i in range(8):
		if SECTOR_TABLE[i][0] == anim_dir and SECTOR_TABLE[i][1] == flip_h:
			return i
	return -1

static func _angle_diff_deg(a: float, b: float) -> float:
	var d := fmod(a - b + 180.0, 360.0)
	if d < 0.0:
		d += 360.0
	return d - 180.0

## 统一形变与步态驱动（单一插值流，消除多处改写 scale 导致的微抖动）
## moving=true：按当前跑步帧相位 + 速度比驱动步伐起伏、触地微弹与身体前倾
## moving=false：平滑归位并融入自然待机呼吸（breath_phase）
static func apply(
	sprite: AnimatedSprite2D,
	base_scale: Vector2,
	moving: bool,
	facing_left: bool,
	lean_amount: float,
	delta: float,
	speed_ratio: float = 1.0,
	breath_phase: float = 0.0
) -> void:
	if moving:
		# 动态匹配动画播放倍速，消除滑步感与机械重复感
		var target_speed_scale := clampf(lerpf(0.62, 1.28, clampf(speed_ratio, 0.0, 1.5)), 0.55, 1.45)
		sprite.speed_scale = lerpf(sprite.speed_scale, target_speed_scale, minf(delta * 14.0, 1.0))

		# 4 帧循环：连续余弦波 (0..4 帧对应 2 个完整左右脚交替步态周期)
		var f := float(sprite.frame) + sprite.frame_progress
		var stride_intensity := clampf(speed_ratio, 0.45, 1.25)
		var air := 0.5 - 0.5 * cos(f * PI)  # 0=触地支撑 1=腾空迈步，C1 连续无尖角
		var sway := sin(f * PI * 0.5)       # 左右脚交替微重心摆动（周期为 4 帧）

		var target_offset_y := -air * LIFT * stride_intensity * base_scale.y
		sprite.offset.y = lerpf(sprite.offset.y, target_offset_y, minf(delta * 18.0, 1.0))

		var sq := SQUASH * stride_intensity
		var target_scale := Vector2(
			base_scale.x * (1.0 + sq * (1.0 - air * 1.6)),
			base_scale.y * (1.0 + sq * (air * 1.8 - 0.9))
		)
		sprite.scale = sprite.scale.lerp(target_scale, minf(delta * 18.0, 1.0))

		var dir_sign := -1.0 if facing_left else 1.0
		var lean := deg_to_rad(LEAN_DEG * clampf(lean_amount, 0.0, 1.0) * stride_intensity) * dir_sign
		var step_rock := deg_to_rad(0.65 * stride_intensity) * sway
		sprite.rotation = lerp_angle(sprite.rotation, lean + step_rock, minf(delta * 12.0, 1.0))
	else:
		sprite.speed_scale = lerpf(sprite.speed_scale, 1.0, minf(delta * 12.0, 1.0))
		var k := minf(delta * 14.0, 1.0)
		var breath := sin(breath_phase) * BREATH_AMP
		var target_idle_scale := Vector2(
			base_scale.x * (1.0 - breath * 0.45),
			base_scale.y * (1.0 + breath)
		)
		var target_idle_offset_y := -maxf(0.0, breath) * 0.4 * base_scale.y
		sprite.offset.y = lerpf(sprite.offset.y, target_idle_offset_y, k)
		sprite.scale = sprite.scale.lerp(target_idle_scale, k)
		sprite.rotation = lerp_angle(sprite.rotation, 0.0, k)
