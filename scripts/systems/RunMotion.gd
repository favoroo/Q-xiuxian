class_name RunMotion
extends RefCounted

## 方向动画选择 + 代码驱动的跑步节奏动画。
## 方向图集为 5 行（s/n/e/se/ne）× 5 列（待机 + 4 帧跑步），左/左下/左上由 flip_h 补齐；
## AI 差分帧的逐格漂移在拼装管线（tools/build_run8_atlas.py）里底对齐归一化，
## 跑步的节奏感（颠簸/挤压/前倾）由这里逐帧驱动。
##
## 步态相位由本类按物理帧自维护并反向驱动 sprite.frame（AnimatedSprite2D 须 pause），
## 不再读 sprite.frame + frame_progress 采样——动画帧默认在 _process 推进、
## 形变在 _physics_process 计算，两个时钟混叠会让腾空曲线与腿帧错位抖动。

const LIFT := 0.5        # 步态腾空峰值（压低贴地；影子配合缩放变淡，脚不沾地的悬浮感由此消除）
const AIR_EXP := 1.7     # 腾空曲线塑形指数：>1 让触地权重高、腾空峰值短促
const SQUASH := 0.018    # 步伐触地与腾空弹性形变比例
const LEAN_DEG := 2.6    # 奔跑前倾角度（按移动方向的水平分量缩放，竖直奔跑不前倾）
const BREATH_AMP := 0.011 # 待机呼吸幅度（仅缩放，不再上抬 offset.y）
const SPEED_SCALE_MIN := 0.85  # 步频下限：慢速时不再高频原地踏步（滑行感来源）
const SPEED_SCALE_MAX := 1.30  # 步频上限
const SHADOW_SHRINK := 0.16    # 腾空时影子最大收缩比例
const SHADOW_FADE := 0.22      # 腾空时影子最大变淡比例
const HYSTERESIS_DEG := 29.0 # 8方向扇区切换迟滞阈值（大于 22.5° 边界角，彻底消除临界角度抖动）
const HOVER_LIFT := 5.0      # 御剑悬浮基础高度（屏上像素，offset 按 base_scale 折算）
const HOVER_BOB := 0.7       # 浮沉振幅（屏上像素）
const HOVER_FREQ := 2.2      # 浮沉基频（Hz，移动时随速度略增）
const HOVER_BANK_DEG := 7.0  # 悬浮侧倾角：按**实际横向走位** bank（旧版按「面向玩家」的方向，
                             # 于是逼近与后撤倾同一个方向，两种运动看不出区别）
const HOVER_INTENT_SQUASH := 0.07  # 纵向意图形变：逼近沉身 / 后撤仰身的 scale.y 幅度（等体积反向补 x）
const HOVER_INTENT_LIFT := 3.0     # 纵向意图偏移（屏上像素）：后撤抬高、逼近压低
const HOVER_INTENT_BAND := 0.25    # |逼近度| 死区：环绕侧滑时不叠纵向形变，免得在 0 附近来回翻
const HOVER_INTENT_FOLLOW := 10.0  # 意图形变跟随速率（/s），越小越黏
const SHADOW_DRIFT := 5.0          # 影子滞后（屏上像素，云气拖在身后 = 上下走位唯一的方向线索）
const SHADOW_STRETCH := 0.28       # 影子沿移动方向拉长比例
const SLITHER_FREQ := 3.0    # 蠕动基频（Hz，移动时随速度略增）
const SLITHER_SQ := 0.06     # 蠕动伸缩幅度（scale.x/y 反向交替，蛞蝓/黏液怪的行进波）

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

## 动画集切换：manual_drive=true（跑步）时暂停自动播放，帧推进交给 apply 的相位驱动；
## false（待机）恢复自动播放。方向切换只换帧集，步态相位存在 sprite meta 上天然连续。
static func select_anim(sprite: AnimatedSprite2D, anim: String, manual_drive: bool) -> void:
	if sprite.animation != anim:
		sprite.animation = anim
	if manual_drive:
		if sprite.is_playing():
			sprite.pause()
	else:
		sprite.speed_scale = 1.0
		if not sprite.is_playing():
			sprite.play()

## 统一形变与步态驱动（单一插值流，消除多处改写 scale 导致的微抖动）
## moving=true：按自维护步态相位驱动帧推进、触地微弹与身体前倾，并让影子随腾空收缩变淡
## moving=false：平滑归位并融入自然待机呼吸（breath_phase）
static func apply(
	sprite: AnimatedSprite2D,
	base_scale: Vector2,
	moving: bool,
	facing_left: bool,
	lean_amount: float,
	delta: float,
	speed_ratio: float = 1.0,
	breath_phase: float = 0.0,
	shadow: Sprite2D = null
) -> void:
	var air := 0.0
	if moving:
		# 动态匹配步频倍速，消除滑步感与机械重复感
		var target_speed_scale := clampf(lerpf(SPEED_SCALE_MIN, SPEED_SCALE_MAX, clampf(speed_ratio, 0.0, 1.5)), 0.8, 1.4)
		var speed_scale: float = lerpf(float(sprite.get_meta(&"gait_speed", 1.0)), target_speed_scale, minf(delta * 14.0, 1.0))
		sprite.set_meta(&"gait_speed", speed_scale)

		# 自维护步态相位并反向驱动帧：腾空曲线与腿帧严格同相
		var frame_count := 4
		var anim_fps := 10.0
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
			frame_count = maxi(sprite.sprite_frames.get_frame_count(sprite.animation), 1)
			anim_fps = sprite.sprite_frames.get_animation_speed(sprite.animation)
		var phase: float = fmod(float(sprite.get_meta(&"gait_phase", 0.0)) + delta * anim_fps * speed_scale, float(frame_count))
		sprite.set_meta(&"gait_phase", phase)
		sprite.set_frame_and_progress(int(phase) % frame_count, phase - floorf(phase))

		var stride_intensity := clampf(speed_ratio, 0.45, 1.25)
		var raw_air := 0.5 - 0.5 * cos(phase * PI)  # 0=触地支撑 1=腾空迈步（4 帧含 2 个步态周期）
		air = pow(raw_air, AIR_EXP)                 # 触地权重高、腾空峰值短，脚大部分时间贴地
		var sway := sin(phase * PI * 0.5)           # 左右脚交替微重心摆动（周期为 4 帧）

		var k := minf(delta * 18.0, 1.0)
		sprite.offset.y = lerpf(sprite.offset.y, -air * LIFT * stride_intensity * base_scale.y, k)

		var sq := SQUASH * stride_intensity
		var target_scale := Vector2(
			base_scale.x * (1.0 + sq * (1.0 - air * 1.6)),
			base_scale.y * (1.0 + sq * (air * 1.8 - 0.9))
		)
		sprite.scale = sprite.scale.lerp(target_scale, k)

		var dir_sign := -1.0 if facing_left else 1.0
		var lean := deg_to_rad(LEAN_DEG * clampf(lean_amount, 0.0, 1.0) * stride_intensity) * dir_sign
		var step_rock := deg_to_rad(0.65 * stride_intensity) * sway
		sprite.rotation = lerp_angle(sprite.rotation, lean + step_rock, minf(delta * 12.0, 1.0))
	else:
		sprite.set_meta(&"gait_phase", 0.0)
		sprite.set_meta(&"gait_speed", 1.0)
		var k := minf(delta * 14.0, 1.0)
		var breath := sin(breath_phase) * BREATH_AMP
		var target_idle_scale := Vector2(
			base_scale.x * (1.0 - breath * 0.45),
			base_scale.y * (1.0 + breath)
		)
		sprite.offset.y = lerpf(sprite.offset.y, 0.0, k)
		sprite.scale = sprite.scale.lerp(target_idle_scale, k)
		sprite.rotation = lerp_angle(sprite.rotation, 0.0, k)

	if shadow != null:
		_apply_shadow(shadow, air, minf(delta * 14.0, 1.0))

## 御剑/悬浮模式：不切腿帧（单姿势图集），浮沉/侧倾/前倾全程序驱动。
## 待机也保持低速浮沉（始终悬在剑上），移动时浮沉加速并按走位侧倾。
## move_dir 传**实际位移方向**（不是「面向玩家」的方向）：侧倾按走位 bank，
## 「压过来」和「后撤放风筝」的倾斜方向才天然相反。
## advance = 实际位移与「面向目标」向量的点积（+1 逼近 / -1 后撤 / ≈0 环绕侧滑）。
## 加它的原因（用户现场 2026-10-09：「踩着黑雾的为什么背对着走向我」）：悬浮怪永远只播
## idle 单姿势，逼近/环绕/后撤三种运动在旧版长得一模一样（只剩一条上下浮），玩家只能靠猜。
## 缺省 0.0 ⇒ 玩家不叠纵向意图（他自己就是「面向 = 走位」），悬浮玩家的手感保持原样。
static func apply_hover(
	sprite: AnimatedSprite2D,
	base_scale: Vector2,
	moving: bool,
	move_dir: Vector2,
	delta: float,
	speed_ratio: float = 1.0,
	shadow: Sprite2D = null,
	advance: float = 0.0
) -> void:
	var freq_mult := 1.0 + 0.4 * clampf(speed_ratio, 0.0, 1.5) if moving else 1.0
	var phase: float = float(sprite.get_meta(&"hover_phase", 0.0)) + delta * TAU * HOVER_FREQ * freq_mult
	sprite.set_meta(&"hover_phase", fmod(phase, TAU * 1000.0))
	var bob := sin(phase)

	var k := minf(delta * 14.0, 1.0)
	var scale_safe := maxf(base_scale.y, 0.01)

	# 纵向意图：带死区 + 一阶跟随，避免在「环绕」边界上抖
	var intent := 0.0
	if moving and absf(advance) > HOVER_INTENT_BAND:
		intent = signf(advance) * minf(absf(advance), 1.0)
	var cur_intent: float = float(sprite.get_meta(&"hover_intent", 0.0))
	cur_intent = lerpf(cur_intent, intent, minf(delta * HOVER_INTENT_FOLLOW, 1.0))
	sprite.set_meta(&"hover_intent", cur_intent)

	# 后撤（intent<0）抬身、逼近（intent>0）沉身
	var lift := HOVER_INTENT_LIFT * cur_intent
	sprite.offset.y = lerpf(sprite.offset.y, -(HOVER_LIFT + bob * HOVER_BOB) / scale_safe + lift / scale_safe, k)

	# 整体呼吸极轻；纵向意图形变等体积反向补到 x（沉身变宽、仰身变窄）
	var breathe := 1.0 + bob * 0.006
	var squash_y := 1.0 - HOVER_INTENT_SQUASH * cur_intent
	sprite.scale = sprite.scale.lerp(
		Vector2(base_scale.x * (2.0 - squash_y), base_scale.y * breathe * squash_y), k)

	var bank := 0.0
	if moving:
		bank = deg_to_rad(HOVER_BANK_DEG) * clampf(move_dir.x, -1.0, 1.0) * clampf(speed_ratio, 0.0, 1.3)
	sprite.rotation = lerp_angle(sprite.rotation, bank, minf(delta * 10.0, 1.0))

	if shadow != null:
		# 上下走位时 bank≈0，方向只能靠影子被拖长 + 滞后来说 ⇒ 竖直方向唯一的方向线索
		var streak := move_dir if moving else Vector2.ZERO
		_apply_shadow(shadow, 0.62 + 0.30 * bob, k, streak, clampf(speed_ratio, 0.0, 1.3))

## 蠕动/滑行模式：贴地无悬浮无前倾（史莱姆、血蛹等无腿软体），
## 行进波全靠 scale.x/y 反向交替伸缩；待机时慢速微动，影子保持稳定。
static func apply_slither(
	sprite: AnimatedSprite2D,
	base_scale: Vector2,
	moving: bool,
	delta: float,
	speed_ratio: float = 1.0,
	shadow: Sprite2D = null
) -> void:
	var freq_mult := 1.0 + 0.5 * clampf(speed_ratio, 0.0, 1.5) if moving else 0.4
	var amp_mult := 1.0 if moving else 0.4
	var phase: float = float(sprite.get_meta(&"hover_phase", 0.0)) + delta * TAU * SLITHER_FREQ * freq_mult
	sprite.set_meta(&"hover_phase", fmod(phase, TAU * 1000.0))
	var wave := sin(phase) * SLITHER_SQ * amp_mult

	var k := minf(delta * 14.0, 1.0)
	sprite.offset.y = lerpf(sprite.offset.y, 0.0, k)
	sprite.scale = sprite.scale.lerp(Vector2(base_scale.x * (1.0 + wave), base_scale.y * (1.0 - wave * 0.8)), k)
	sprite.rotation = lerp_angle(sprite.rotation, 0.0, k)

	if shadow != null:
		_apply_shadow(shadow, 0.0, k)

## 影子贴地反馈：腾空时影子收缩变淡（脚离地的视觉补偿），触地/待机时恢复基准。
## streak/drift 非零时再叠一层「行进拖影」：沿移动方向拉长、并向后滞后一点（云气被拖在身后）。
static func _apply_shadow(
	shadow: Sprite2D,
	air: float,
	k: float,
	streak: Vector2 = Vector2.ZERO,
	drift: float = 0.0
) -> void:
	if not shadow.has_meta(&"gait_base"):
		shadow.set_meta(&"gait_base", [shadow.scale, shadow.modulate.a, shadow.position])
	var base: Array = shadow.get_meta(&"gait_base")
	var base_scale: Vector2 = base[0]
	var base_alpha: float = base[1]
	var base_pos: Vector2 = base[2]
	var stretch := Vector2(1.0 + SHADOW_STRETCH * absf(streak.x), 1.0 + SHADOW_STRETCH * absf(streak.y))
	shadow.scale = shadow.scale.lerp(base_scale * (1.0 - SHADOW_SHRINK * air) * stretch, k)
	shadow.modulate.a = lerpf(shadow.modulate.a, base_alpha * (1.0 - SHADOW_FADE * air), k)
	shadow.position = shadow.position.lerp(base_pos - streak * SHADOW_DRIFT * drift, k)
