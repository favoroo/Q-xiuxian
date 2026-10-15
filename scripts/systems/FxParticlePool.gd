class_name FxParticlePool
extends Node2D

## 全局瞬发特效粒子池（Death Cells 碎屑颗粒感 × Hollow Knight 冷冽灵光）
## 一次性爆发粒子的统一管控入口：池化预实例化 24 个 GPUParticles2D，严格限流防糊屏。
## 挂载于 Main 场景 entities 之上（Z_INDEX = 35），不做 autoload，测试解耦。

enum Kind {
	HIT_SPARK = 0,    ## 命中火花（死亡细胞式碎屑，初速高，0.25s 衰减，6-10 粒）
	DEATH_WISP = 1,   ## 小怪死亡墨色魂屑（空洞骑士式向上缓飘，0.4s，4-6 粒，无 HDR）
	DEATH_BURST = 2,  ## 精英/Boss死亡爆裂（两段式灵光碎屑，0.35s，10-14 粒，HDR起辉）
	EMBER = 3,        ## 火锥/火舌碎屑（0.35s，顺向喷发，6-12 粒）
	SOUL_ORB = 4,     ## 拾取灵光/灵珠吸附微粒（软光斑，0.25s，4-8 粒）
	LEVEL_PILLAR = 5, ## 升级仪式灵气光柱粒子（金色超白，0.4s，12-16 粒）
}

const HIT_SPARK := Kind.HIT_SPARK
const DEATH_WISP := Kind.DEATH_WISP
const DEATH_BURST := Kind.DEATH_BURST
const EMBER := Kind.EMBER
const SOUL_ORB := Kind.SOUL_ORB
const LEVEL_PILLAR := Kind.LEVEL_PILLAR

const POOL_CAP := 24                 ## 常驻发射器池上限（硬红线 ≤30）
const Z_OVERLAY := 35                ## 特效渲染层级（在角色与怪物之上，在 HUD 之下）

## 帧限流预算闸（同物理帧宁缺勿糊，历史教训防糊屏）
const HIT_FRAME_BUDGET := 6          ## 同物理帧最多 6 处命中火花
const BURST_FRAME_BUDGET := 3        ## 同物理帧最多 3 处死亡爆散

static var instance: FxParticlePool = null

static var _tex_soft_dot: ImageTexture = null
static var _tex_square_chip: ImageTexture = null

static var _last_hit_frame: int = -1
static var _hit_count_this_frame: int = 0
static var _last_burst_frame: int = -1
static var _burst_count_this_frame: int = 0

var _available_emitters: Array[GPUParticles2D] = []
var _active_emitters: Array[GPUParticles2D] = []

# ----------------- 静态贴图生成 -----------------

static func _ensure_textures() -> void:
	if _tex_soft_dot != null and _tex_square_chip != null:
		return
	
	# 1. 径向软光斑（32×32，供光珠/魂屑/光柱使用）
	var img_dot := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var center := Vector2(15.5, 15.5)
	for y in range(32):
		for x in range(32):
			var dist := Vector2(x, y).distance_to(center)
			var t := clampf(dist / 15.5, 0.0, 1.0)
			var alpha := pow(1.0 - t, 2.2)
			img_dot.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_tex_soft_dot = ImageTexture.create_from_image(img_dot)

	# 2. 小方块碎屑（32×32，死亡细胞式颗粒感，中心 18×18 纯白带 2px 边缘羽化）
	var img_chip := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(32):
			var dx := absf(float(x) - 15.5)
			var dy := absf(float(y) - 15.5)
			var max_d := maxf(dx, dy)
			var alpha := 0.0
			if max_d <= 9.0:
				alpha = 1.0
			elif max_d <= 12.0:
				alpha = clampf((12.0 - max_d) / 3.0, 0.0, 1.0)
			img_chip.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_tex_square_chip = ImageTexture.create_from_image(img_chip)

# ----------------- 生命周期与初始化 -----------------

func _ready() -> void:
	instance = self
	z_index = Z_OVERLAY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	FxParticlePool._ensure_textures()
	_init_pool()

func _exit_tree() -> void:
	if instance == self:
		instance = null
	_available_emitters.clear()
	_active_emitters.clear()

static func clear_cache() -> void:
	instance = null
	_last_hit_frame = -1
	_hit_count_this_frame = 0
	_last_burst_frame = -1
	_burst_count_this_frame = 0

func _init_pool() -> void:
	for i in range(POOL_CAP):
		var emitter := GPUParticles2D.new()
		emitter.name = "Emitter_%d" % i
		emitter.one_shot = true
		emitter.explosiveness = 0.9
		emitter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		emitter.emitting = false
		emitter.visible = false
		
		var mat := ParticleProcessMaterial.new()
		mat.particle_flag_disable_z = true
		mat.gravity = Vector3(0, 0, 0)
		emitter.process_material = mat
		
		emitter.finished.connect(_on_emitter_finished.bind(emitter))
		add_child(emitter)
		_available_emitters.append(emitter)

func _on_emitter_finished(emitter: GPUParticles2D) -> void:
	emitter.visible = false
	emitter.emitting = false
	_active_emitters.erase(emitter)
	if not _available_emitters.has(emitter):
		_available_emitters.append(emitter)

# ----------------- 颜色与限流解析 -----------------

static func _resolve_color(element: Variant, default_color: Color) -> Color:
	if element is Color:
		return element
	if element is String:
		var elem_str := (element as String).to_lower()
		if elem_str == "crit":
			return GameStyle.FX_HDR_CRIT
		elif elem_str == "heal":
			return GameStyle.FX_HDR_HEAL
		elif elem_str == "shadow":
			return GameStyle.FX_HDR_SHADOW
		elif elem_str == "lightning":
			return GameStyle.FX_HDR_LIGHTNING
		elif elem_str == "gold":
			return GameStyle.FX_HDR_GOLD
		elif elem_str != "" and elem_str != "none":
			return GameStyle.fx_hdr_element(elem_str, default_color)
	elif element is int:
		var elem_int: int = element
		match elem_int:
			1: return GameStyle.FX_HDR_METAL
			2: return GameStyle.FX_HDR_WOOD
			3: return GameStyle.FX_HDR_WATER
			4: return GameStyle.FX_HDR_FIRE
			5: return GameStyle.FX_HDR_EARTH
			6: return GameStyle.FX_HDR_CRIT
			7: return GameStyle.FX_HDR_SHADOW
			8: return GameStyle.FX_HDR_LIGHTNING
	return default_color

# ----------------- 核心爆发接口 -----------------

## 一次性爆发粒子的统一对外 API
## kind: Kind 枚举
## pos: 爆发绝对世界坐标
## element: 颜色语义，支持 String（如 "fire" / "crit"）、int（五行索引）或指定 Color
## scale_factor: 缩放倍率（暴击/精英死亡可适当放大）
static func burst(kind: int, pos: Vector2, element: Variant = "none", scale_factor: float = 1.0) -> void:
	if instance == null or not is_instance_valid(instance):
		return
	
	# 物理帧限流检查
	var cur_frame := Engine.get_physics_frames()
	if kind == Kind.HIT_SPARK:
		if cur_frame != _last_hit_frame:
			_last_hit_frame = cur_frame
			_hit_count_this_frame = 0
		_hit_count_this_frame += 1
		if _hit_count_this_frame > HIT_FRAME_BUDGET:
			return
	elif kind == Kind.DEATH_BURST:
		if cur_frame != _last_burst_frame:
			_last_burst_frame = cur_frame
			_burst_count_this_frame = 0
		_burst_count_this_frame += 1
		if _burst_count_this_frame > BURST_FRAME_BUDGET:
			return
	
	instance._trigger_burst(kind, pos, element, scale_factor)

func _trigger_burst(kind: int, pos: Vector2, element: Variant, scale_factor: float) -> void:
	var emitter: GPUParticles2D = null
	if not _available_emitters.is_empty():
		emitter = _available_emitters.pop_back()
	elif not _active_emitters.is_empty():
		# 满载时抢占最早启动的发射器
		emitter = _active_emitters.pop_front()
		emitter.emitting = false
	else:
		return
	
	_active_emitters.append(emitter)
	emitter.global_position = pos
	emitter.visible = true
	
	var mat := emitter.process_material as ParticleProcessMaterial
	if mat == null:
		mat = ParticleProcessMaterial.new()
		mat.particle_flag_disable_z = true
		emitter.process_material = mat
	
	# 重置方向基础值
	emitter.rotation = 0.0
	
	match kind:
		Kind.HIT_SPARK:
			emitter.texture = _tex_square_chip
			emitter.amount = 8
			emitter.lifetime = 0.25
			emitter.explosiveness = 0.92
			mat.direction = Vector3(0, 0, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 180.0 * scale_factor
			mat.initial_velocity_max = 320.0 * scale_factor
			mat.gravity = Vector3(0, 100.0, 0)
			mat.damping_min = 160.0
			mat.damping_max = 240.0
			mat.scale_min = 0.16 * scale_factor
			mat.scale_max = 0.32 * scale_factor
			mat.color = _resolve_color(element, GameStyle.FX_HDR_CORE)
			
		Kind.DEATH_WISP:
			emitter.texture = _tex_soft_dot
			emitter.amount = 5
			emitter.lifetime = 0.4
			emitter.explosiveness = 0.55
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 40.0
			mat.initial_velocity_min = 25.0 * scale_factor
			mat.initial_velocity_max = 50.0 * scale_factor
			mat.gravity = Vector3(0, -18.0, 0)
			mat.damping_min = 10.0
			mat.damping_max = 25.0
			mat.scale_min = 0.22 * scale_factor
			mat.scale_max = 0.42 * scale_factor
			# 墨色魂屑：暗冷灰蓝/不加 HDR
			mat.color = Color(0.18, 0.20, 0.28, 0.72)
			
		Kind.DEATH_BURST:
			emitter.texture = _tex_square_chip
			emitter.amount = 12
			emitter.lifetime = 0.35
			emitter.explosiveness = 0.95
			mat.direction = Vector3(0, 0, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 220.0 * scale_factor
			mat.initial_velocity_max = 380.0 * scale_factor
			mat.gravity = Vector3(0, 60.0, 0)
			mat.damping_min = 180.0
			mat.damping_max = 280.0
			mat.scale_min = 0.24 * scale_factor
			mat.scale_max = 0.48 * scale_factor
			mat.color = _resolve_color(element, GameStyle.FX_HDR_GOLD)
			
		Kind.EMBER:
			emitter.texture = _tex_square_chip
			emitter.amount = 10
			emitter.lifetime = 0.35
			emitter.explosiveness = 0.85
			mat.direction = Vector3(1, 0, 0)
			mat.spread = 45.0
			mat.initial_velocity_min = 150.0 * scale_factor
			mat.initial_velocity_max = 260.0 * scale_factor
			mat.gravity = Vector3(0, -35.0, 0)
			mat.damping_min = 80.0
			mat.damping_max = 160.0
			mat.scale_min = 0.16 * scale_factor
			mat.scale_max = 0.34 * scale_factor
			mat.color = _resolve_color(element, GameStyle.FX_HDR_FIRE)
			
		Kind.SOUL_ORB:
			emitter.texture = _tex_soft_dot
			emitter.amount = 6
			emitter.lifetime = 0.25
			emitter.explosiveness = 0.88
			mat.direction = Vector3(0, 0, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 80.0 * scale_factor
			mat.initial_velocity_max = 160.0 * scale_factor
			mat.gravity = Vector3(0, 0, 0)
			mat.damping_min = 120.0
			mat.damping_max = 180.0
			mat.scale_min = 0.2 * scale_factor
			mat.scale_max = 0.38 * scale_factor
			mat.color = _resolve_color(element, GameStyle.FX_HDR_WATER)
			
		Kind.LEVEL_PILLAR:
			emitter.texture = _tex_soft_dot
			emitter.amount = 16
			emitter.lifetime = 0.4
			emitter.explosiveness = 0.85
			mat.direction = Vector3(0, -1, 0)
			mat.spread = 25.0
			mat.initial_velocity_min = 120.0 * scale_factor
			mat.initial_velocity_max = 240.0 * scale_factor
			mat.gravity = Vector3(0, -50.0, 0)
			mat.damping_min = 50.0
			mat.damping_max = 90.0
			mat.scale_min = 0.28 * scale_factor
			mat.scale_max = 0.55 * scale_factor
			mat.color = _resolve_color(element, GameStyle.FX_HDR_GOLD)
			
		_:
			emitter.texture = _tex_square_chip
			emitter.amount = 8
			emitter.lifetime = 0.25
			emitter.explosiveness = 0.9
			mat.direction = Vector3(0, 0, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 150.0
			mat.initial_velocity_max = 250.0
			mat.color = GameStyle.FX_HDR_CORE

	emitter.restart()
	emitter.emitting = true
