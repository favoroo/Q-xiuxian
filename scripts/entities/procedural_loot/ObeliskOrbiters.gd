class_name ObeliskOrbiters
extends Node2D

## 祭坛「召唤印记」环绕灵火（2026-11-02）：累计成功召唤一次就多一枚环绕小火苗，
## 与祭坛阶数解耦 —— 水晶大小/结构看阶数，火苗数量看真正召唤过几次。
##
## 视觉：pixelfx `fire/spirit-flame`（导出为 gold 调色板）常驻 loop，不走 FxFlipbookPool
## 的一次性回收；单坛最多 8 枚，超出部分不再加数量（上限之外只保留最强读数）。
## 轨道：以水晶核心为基准下移 24px 落在晶身中下段，扁椭圆（y × 0.38）慢速环绕；
## 绕到后方的火苗 z_index = -1（z_as_relative=false）让水晶压住，前方的 +1 浮在水晶之上。
## 耗尽灰相：火苗降亮度、降速，下一回合复燃时随祭坛一起重亮。
## 纯表现层：不读玩法 RNG、不参与任何判定。

const MAX_ORBITERS := 8
const ORBIT_BASE_RADIUS := 66.0
const ORBIT_RADIUS_PER_ORB := 3.0
const ORBIT_Y_SQUASH := 0.38
const ORBIT_SPEED := 0.55              ## 基础角速度（rad/s）
const ORBIT_CENTER_OFFSET := Vector2(0.0, 24.0)  ## 相对水晶核心下移到晶身中下段
const FLAME_BASE_SCALE := 0.40
const FLAME_TIER_SCALE_STEP := 0.025
const FLAME_ALPHA := 0.90
const SPENT_ALPHA := 0.24
const SPENT_SPEED_RATIO := 0.30
const SPAWN_POP_TIME := 0.35

var summon_count: int = 0
var tier: int = 1
var is_spent: bool = false
## 轨道中心（相对祭坛本地坐标）：由 BlessingObelisk 每帧灌入水晶核心 + 下移偏移
var orbit_center: Vector2 = ORBIT_CENTER_OFFSET

var _time: float = 0.0
var _sprites: Array[AnimatedSprite2D] = []
var _phases: Array[float] = []
var _spawn_at: Array[float] = []
var _hdr_material: ShaderMaterial = null

func _ready() -> void:
	z_index = 1
	_hdr_material = FxFlipbookPool.get_hdr_material()

## 设置累计召唤数（= 本局成功启动祭坛次数）：只增删火苗数量，不改任何数值
func set_count(count: int) -> void:
	var target: int = clampi(count, 0, MAX_ORBITERS)
	if target == summon_count and _sprites.size() == target:
		return
	var frames := FxSheetData.get_sprite_frames(&"spirit_flame")
	if frames == null:
		# 资源未导入时不动 summon_count，下一次激活还会再试
		return
	# 超出上限 / 回退：从尾部摘掉
	while _sprites.size() > target:
		var old: AnimatedSprite2D = _sprites.pop_back()
		_phases.pop_back()
		_spawn_at.pop_back()
		if is_instance_valid(old):
			old.queue_free()
	# 新增：逐枚建 AnimatedSprite2D，共享同一份 SpriteFrames
	for i in range(_sprites.size(), target):
		var s := AnimatedSprite2D.new()
		s.sprite_frames = frames
		s.animation = &"default"
		s.centered = true
		s.offset = Vector2.ZERO
		s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# z 轴绝对值：全部浮在水晶之上（后方不沉到地砖层下面，否则整枚火苗会消失）
		s.z_as_relative = false
		s.z_index = 1
		if _hdr_material != null and not FxBudget.crowded:
			s.material = _hdr_material
		_phases.append(TAU * float(i) / float(maxi(target, 1)))
		_spawn_at.append(_time)
		add_child(s)
		_sprites.append(s)
		s.play(&"default")
	summon_count = target
	_redistribute_phases()

## 阶数：只影响火苗尺寸/亮度（阶越高火越旺），不改变数量
func set_tier(new_tier: int) -> void:
	tier = clampi(new_tier, 1, 4)

## 灰相/复燃：耗尽时降亮度、降速；复燃时恢复
func set_spent(spent: bool) -> void:
	is_spent = spent

## 当前实际持有的火苗数量（判据读它）
func orbiter_count() -> int:
	return _sprites.size()

func _redistribute_phases() -> void:
	var n: int = maxi(_sprites.size(), 1)
	for i in range(_phases.size()):
		_phases[i] = TAU * float(i) / float(n)

func _process(delta: float) -> void:
	_time += delta
	var count: int = _sprites.size()
	if count == 0:
		return
	var speed: float = ORBIT_SPEED * (SPENT_SPEED_RATIO if is_spent else 1.0)
	var radius: float = ORBIT_BASE_RADIUS + ORBIT_RADIUS_PER_ORB * float(maxi(count - 1, 0))
	var base_scale: float = FLAME_BASE_SCALE + FLAME_TIER_SCALE_STEP * float(tier - 1)
	var alpha_target: float = SPENT_ALPHA if is_spent else FLAME_ALPHA
	for i in range(count):
		var s: AnimatedSprite2D = _sprites[i]
		if not is_instance_valid(s):
			continue
		_phases[i] = fposmod(_phases[i] + speed * delta, TAU)
		var a: float = _phases[i]
		var p: Vector2 = orbit_center + Vector2(
			cos(a) * radius,
			sin(a) * radius * ORBIT_Y_SQUASH + sin(_time * 2.2 + float(i) * 1.3) * 1.5)
		s.position = p
		# 后方火苗用「缩一点 + 暗一点」做深度，不再用 z=-1（会沉到地砖层之下整枚消失）
		var behind: bool = sin(a) < 0.0
		var depth: float = 0.82 if behind else 1.0
		# 出生弹起 + 呼吸：不额外建 Tween，直接用 _spawn_at 算缓出
		var age: float = _time - _spawn_at[i]
		var pop: float = clampf(age / SPAWN_POP_TIME, 0.0, 1.0)
		var pop_e: float = 1.0 - pow(1.0 - pop, 3.0)
		var breathe: float = 0.92 + 0.08 * sin(_time * 3.1 + float(i) * 1.7)
		var sc: float = base_scale * breathe * lerpf(0.2, 1.0, pop_e) * depth
		s.scale = Vector2(sc, sc)
		var alpha: float = alpha_target * pop_e * (0.68 if behind else 1.0)
		s.modulate = Color(1.0, 1.0, 1.0, alpha)