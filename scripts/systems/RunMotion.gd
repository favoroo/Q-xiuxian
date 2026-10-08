class_name RunMotion
extends RefCounted

## 方向动画选择 + 代码驱动的跑步节奏动画。
## 方向图集为 5 行（s/n/e/se/ne）× 5 列（待机 + 4 帧跑步），左/左下/左上由 flip_h 补齐；
## AI 差分帧的逐格漂移在拼装管线（tools/build_run8_atlas.py）里底对齐归一化，
## 跑步的节奏感（颠簸/挤压/前倾）由这里逐帧驱动。

const LIFT := 9.0     # 腾空抬升幅度（乘精灵基础缩放）
const SQUASH := 0.05  # 触地压扁 / 腾空拉长比例
const LEAN_DEG := 4.0 # 满前倾角度（按移动方向的水平分量缩放，竖直奔跑不前倾）

## 方向图集的行序：动画后缀 → 图集行号
const DIR_ROW := {"s": 0, "n": 1, "e": 2, "se": 3, "ne": 4}

## 移动方向 → [动画后缀, 是否水平翻转]（8 象限各 45°，左系翻转入右系素材）
static func facing(dir: Vector2) -> Array:
	if dir.length_squared() < 0.0001:
		return ["", false]
	var sector := wrapi(int(floor((rad_to_deg(dir.angle()) + 22.5) / 45.0)), 0, 8)
	match sector:
		0: return ["e", false]   # 东
		1: return ["se", false]  # 东南
		2: return ["s", false]   # 南
		3: return ["se", true]   # 西南
		4: return ["e", true]    # 西
		5: return ["ne", true]   # 西北
		6: return ["n", false]   # 北
		_: return ["ne", false]  # 东北

## moving=true：须正在播放 run_<后缀>，按当前帧驱动 offset/scale/rotation
## moving=false：平滑回正 scale/rotation（offset.y 交给调用方的待机呼吸管理，不碰）
## lean_amount：移动方向的水平分量（自动钳到 0~1）
static func apply(sprite: AnimatedSprite2D, base_scale: Vector2, moving: bool, facing_left: bool, lean_amount: float, delta: float) -> void:
	if moving:
		# 4 帧循环：偶数帧触地、奇数帧腾空，frame_progress 让过渡平滑
		var f := float(sprite.frame) + sprite.frame_progress
		var step_t := fmod(f, 2.0) * 0.5
		var air := sin(step_t * PI)  # 0=触地 1=腾空中点
		sprite.offset.y = -air * LIFT * base_scale.y
		sprite.scale = Vector2(
			base_scale.x * (1.0 + SQUASH * (1.0 - air)),
			base_scale.y * (1.0 + SQUASH * (air * 2.0 - 1.0))
		)
		var lean := deg_to_rad(LEAN_DEG) * clampf(lean_amount, 0.0, 1.0) * (-1.0 if facing_left else 1.0)
		sprite.rotation = lerp_angle(sprite.rotation, lean, minf(delta * 12.0, 1.0))
	else:
		var k := minf(delta * 10.0, 1.0)
		sprite.scale = sprite.scale.lerp(base_scale, k)
		sprite.rotation = lerp_angle(sprite.rotation, 0.0, k)
