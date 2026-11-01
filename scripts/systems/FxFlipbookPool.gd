class_name FxFlipbookPool
extends Node2D

## 全局 pixelfx 贴图序列帧特效播放池
## 预实例化常驻 AnimatedSprite2D，统一执行帧预算限流、锚点偏移换算、朝向镜像与 HDR 起辉。
## 支持单发自回收与循环跟随两种模式。

const POOL_CAP := FxBudget.POOL_CAP_FLIPBOOK  ## 16 个常驻节点
const Z_OVERLAY := FxBudget.Z_OVERLAY        ## 35（角色之上，HUD 之下）
const Z_GROUND := 2                          ## 地面贴地档位（地裂/毒潭/法阵）

static var instance: FxFlipbookPool = null

static var _last_flipbook_frame: int = -1
static var _flipbook_count_this_frame: int = 0
static var _recent_positions: Array[Vector2] = []

static var _hdr_material: ShaderMaterial = null

var _available: Array[AnimatedSprite2D] = []
var _active: Array[AnimatedSprite2D] = []

# ----------------- 静态初始化与单例自愈 -----------------

static func _ensure_material() -> ShaderMaterial:
	if _hdr_material == null:
		var shader := load("res://assets/shaders/fx_sprite_hdr.gdshader") as Shader
		if shader != null:
			_hdr_material = ShaderMaterial.new()
			_hdr_material.shader = shader
	return _hdr_material

static func _ensure_instance(tree: SceneTree) -> FxFlipbookPool:
	if instance != null and is_instance_valid(instance) and instance.is_inside_tree():
		return instance
	var pool := FxFlipbookPool.new()
	pool.name = "FxFlipbookPool"
	if tree != null:
		if tree.current_scene != null:
			tree.current_scene.add_child(pool)
		elif tree.root != null:
			tree.root.add_child(pool)
	return pool

# ----------------- 生命周期 -----------------

func _ready() -> void:
	instance = self
	z_index = Z_OVERLAY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_init_pool()

func _exit_tree() -> void:
	if instance == self:
		instance = null
	_available.clear()
	_active.clear()

func _init_pool() -> void:
	FxFlipbookPool._ensure_material()
	for i in range(POOL_CAP):
		var anim := AnimatedSprite2D.new()
		anim.visible = false
		anim.centered = true
		anim.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		anim.animation_finished.connect(_on_animation_finished.bind(anim))
		add_child(anim)
		_available.append(anim)

func _on_animation_finished(anim: AnimatedSprite2D) -> void:
	if not is_instance_valid(anim):
		return
	# 如果是循环动画，不自动回收
	if anim.sprite_frames != null and anim.sprite_frames.get_animation_loop(anim.animation):
		return
	recycle(anim)

func recycle(anim: AnimatedSprite2D) -> void:
	if not is_instance_valid(anim):
		return
	anim.stop()
	anim.visible = false
	anim.set_process(false)
	anim.material = null
	if anim.has_meta("follow_target"):
		anim.remove_meta("follow_target")
	_active.erase(anim)
	if not _available.has(anim) and _available.size() < POOL_CAP:
		_available.append(anim)

# ----------------- 对外核心播放 API -----------------

## 播放 pixelfx 特效
## opts 可包含：
##   dir: Vector2          朝向（若 x < 0 自动水平翻转）
##   scale_mult: float     额外缩放倍率（与配置基础 scale 相乘）
##   modulate: Color       染色调制
##   hdr: bool             是否挂载 HDR 起辉材质（默认读取配置）
##   follow: Node2D        跟随的目标节点（常用于持续型火锥/光束）
##   z_ground: bool        是否强制放于地面层
static func play(id: StringName, pos: Vector2, opts: Dictionary = {}) -> AnimatedSprite2D:
	var conf: Dictionary = FxSheetData.get_config(id)
	if conf.is_empty():
		return null

	# 1. 物理帧限流闸
	var cur_frame := Engine.get_physics_frames()
	if cur_frame != _last_flipbook_frame:
		_last_flipbook_frame = cur_frame
		_flipbook_count_this_frame = 0
		_recent_positions.clear()
	else:
		if _flipbook_count_this_frame >= FxBudget.FRAME_BUDGET_FLIPBOOK:
			return null
		# 同一帧内距既有播放点过近（< 16px）视为重叠爆发，丢弃防糊屏
		for p in _recent_positions:
			if pos.distance_squared_to(p) < 256.0:
				return null

	_flipbook_count_this_frame += 1
	_recent_positions.append(pos)

	# 2. 获取池实例
	var pool := instance
	if pool == null or not is_instance_valid(pool) or not pool.is_inside_tree():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			pool = _ensure_instance(tree)
		if pool == null:
			return null

	return pool._spawn(id, pos, conf, opts)

func _spawn(id: StringName, pos: Vector2, conf: Dictionary, opts: Dictionary) -> AnimatedSprite2D:
	var anim: AnimatedSprite2D = null
	if not _available.is_empty():
		anim = _available.pop_back()
	elif _active.size() < POOL_CAP + 4: # 允许少量应急溢出
		anim = AnimatedSprite2D.new()
		anim.centered = true
		anim.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		anim.animation_finished.connect(_on_animation_finished.bind(anim))
		add_child(anim)
	else:
		# 达到上限，复用最老的一个
		anim = _active[0]
		recycle(anim)
		if not _available.is_empty():
			anim = _available.pop_back()

	if anim == null:
		return null

	var sf := FxSheetData.get_sprite_frames(id)
	if sf == null:
		_available.append(anim)
		return null

	anim.sprite_frames = sf
	anim.animation = &"default"
	anim.global_position = pos

	# 锚点与朝向换算
	var offset := FxSheetData.get_offset(id)
	var dir: Vector2 = opts.get("dir", Vector2.ZERO)
	var flip: bool = false
	if dir != Vector2.ZERO:
		flip = FxSheetData.should_flip_h(id, dir)
	anim.flip_h = flip
	if flip:
		offset.x = -offset.x
	anim.offset = offset

	# 缩放
	var base_scale: float = conf.get("scale", 1.0)
	var scale_mult: float = opts.get("scale_mult", 1.0)
	anim.scale = Vector2.ONE * (base_scale * scale_mult)

	# 颜色与发光
	anim.modulate = opts.get("modulate", Color.WHITE)
	var use_hdr: bool = opts.get("hdr", conf.get("hdr", true))
	# 双档策略：如果处于拥挤档，或配置无需 HDR，则不挂材质节省开销
	if use_hdr and not FxBudget.crowded:
		anim.material = _hdr_material
	else:
		anim.material = null

	# 层级
	var is_ground: bool = opts.get("z_ground", conf.get("z_ground", false))
	anim.z_index = Z_GROUND if is_ground else Z_OVERLAY

	# 跟随逻辑
	var follow_node: Node2D = opts.get("follow", null)
	if follow_node != null and is_instance_valid(follow_node):
		anim.set_meta("follow_target", follow_node)
		anim.set_process(true)
	else:
		anim.set_process(false)

	anim.visible = true
	anim.play(&"default")
	_active.append(anim)

	return anim

func _process(_delta: float) -> void:
	# 处理跟随节点的特效
	for anim in _active:
		if is_instance_valid(anim) and anim.has_meta("follow_target"):
			var target = anim.get_meta("follow_target")
			if is_instance_valid(target) and target is Node2D:
				anim.global_position = target.global_position
			else:
				recycle(anim)

## 停止并归还特定特效（针对循环动画）
static func stop(anim: AnimatedSprite2D) -> void:
	if anim == null or not is_instance_valid(anim):
		return
	if instance != null and is_instance_valid(instance):
		instance.recycle(anim)

## 清空缓存（测试与换场景重置使用）
static func clear_cache() -> void:
	_last_flipbook_frame = -1
	_flipbook_count_this_frame = 0
	_recent_positions.clear()
	if instance != null and is_instance_valid(instance):
		for a in instance._active.duplicate():
			instance.recycle(a)
