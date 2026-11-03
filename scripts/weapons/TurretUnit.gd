class_name TurretUnit
extends Node2D

## 机关炮台/阵盘实体（2026-11-03 手动布设改版）：
## 由玩家在脚下空地手动布设（TurretHandler.deploy），一座机关 = 一把机关武器的全部编制。
## 独立索敌、**多管齐射**（★1 双管 … ★4 五管，管数 = 旧版炮台座数，总 DPS 逐星持平），
## 开火会磨损耐久：磨到四成降速、磨到底停摆，靠近长按可维修（TurretUnit.begin_repair）。
## 回合末不再消散，进入整备（耐久回满、停火），下波继续在原位工作（on_wave_end）。
##
## 伤害吃机关伤害（contraption_damage）、机关羁绊（synergy_contraption_mult）与全套玩家乘区。

@export var weapon_def_id: String = "jiguan_nu"
@export var star: int = 1

## 对象池：按场景路径分桶；消散演出走完回池，复用前由 begin_life() 统一复位可见状态。
const POOL_CAP_PER_SCENE := 12
static var _pools: Dictionary = {}

var _pool_key: String = ""
var _fire_tween: Tween = null
var _dismiss_tween: Tween = null
## 布设它的武器（FloatingWeapon）：回池时必须从宿主的 active_turrets 摘除，
## 否则该武器下次布设会摸到已被另一把武器复用的池体。
var _owner_weapon: Node = null

## 从池中取一台（优先复用出树休眠体），调用方负责 setup → add_child → begin_life
static func acquire_or_new(scene: PackedScene) -> TurretUnit:
	if scene == null:
		return null
	var key := scene.resource_path
	var bucket: Array = _pools.get(key, [])
	var turret: TurretUnit = null
	while not bucket.is_empty() and turret == null:
		var cand := bucket.pop_back() as TurretUnit
		if cand != null and is_instance_valid(cand):
			turret = cand
	if turret == null:
		turret = scene.instantiate() as TurretUnit
	turret._pool_key = key
	return turret

## 场景 teardown 统一释放休眠体（出树节点不受 free 传播，不手动清会成孤儿）
static func clear_pool() -> void:
	for key in _pools:
		var bucket: Array = _pools[key]
		for t in bucket:
			if is_instance_valid(t):
				(t as Node).free()
	_pools.clear()

var base_damage: float = 18.0
var fire_cooldown: float = 0.8
var attack_range: float = 220.0

## 耐久（0~100 百分比制）：只在真正开火时磨损；<40% 降速、=0 停摆；维修连续回填。
var durability: float = BalanceTurret.MAX_DURABILITY
## 实际耐久时长 = 表值 × 耐久乘区（「机关养护」/「机枢油」；回合间买/加点，跨回合保留的机关现读就生效）
func effective_stamina() -> float:
	return stamina_sec * maxf(0.2, GameManager.turret_stamina_mul)

## 实际维修用时 = 0.8s × 维修用时乘区（越小越快）
func repair_hold_sec() -> float:
	return BalanceTurret.repair_hold_sec(GameManager.turret_repair_haste_mul)

## 停摆兜底倍率（「恒机芯」道具给；0 = 照旧完全停工）
func broken_haste() -> float:
	return maxf(0.0, GameManager.item_hook_sum("turret_broken_haste"))

## 一次开火的齐射管数：星级管数（★1 双管…★4 五管）+ 悟道/道具的额外管数（「连环机括」+1）。
## 读侧统一出口：升级/买东西发生在回合间，机关是跨回合保留的 —— 用 getter 现读，部署时就地生效，
## 不会出现「买了齐射卡但场上那台还是老管数」。
var volley: int:
	get:
		return WeaponData.turret_volley(star) + int(GameManager.turret_volley_bonus)
## 连续开火多少秒磨到底（表字段 turret_stamina，缺省走 BalanceTurret.STAMINA_SEC）
var stamina_sec: float = BalanceTurret.STAMINA_SEC

## 索敌结果缓存：15Hz 一次查询同时喂「瞄准」与「齐射分敌」，不再每管各查一次
var _targets: Array[Node2D] = []
var current_target: Node2D = null

## 武器表与弹丸外观：setup 期一次性解析，_fire() 热路径不再走
## WeaponData.get_def + ResourceLoader.exists/load（高射速下每秒数十次纯浪费）
var _def: Dictionary = {}
var _bullet_tex: Texture2D = null
var _bullet_scale: float = 0.55
var _bullet_spins: bool = false

var _cooldown_timer: float = 0.0
var _had_target: bool = false
var _is_dying: bool = false
var _spin_angle: float = 0.0
## 开火计数：★4 青/紫逐发交替的相位（只影响视觉配色，不参与任何判定）
var _shot_count: int = 0

## 波次在战闸：回合末整备时关掉，波次开始再打开（整备期间不索敌、不开火、不磨损）
var _wave_active: bool = true

## 维修态：HUD 按住时 begin_repair，松开/离开范围 end_repair；回填在 _process 里连续推进。
var _is_repairing: bool = false
var _repair_from: float = BalanceTurret.MAX_DURABILITY

## 索敌节流（与 FloatingWeapon 同款）：intersect_shape 最多 15Hz
const TARGET_SEARCH_INTERVAL := 0.066
var _search_timer: float = 0.0
## 索敌候选缓存（复用数组，避免每节拍小分配）
var _cand_nodes: Array[Node2D] = []
var _cand_dists: Array[float] = []

static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null

var projectile_scene: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")

@onready var core_sprite: Sprite2D = $CoreSprite
@onready var muzzle_point: Marker2D = $CoreSprite/MuzzlePoint
@onready var base_ring: Node2D = $BaseRing

var muzzle_flash: Sprite2D = null
## 矢量机关本体（批次 4：弩机/阵盘/炮管/机关兽/投石机/灯塔）。
## 非 null 时 CoreSprite 的贴图让位，由它出画面（逐批灰度：未登记 turret_shape 的仍显示旧贴图）。
var _proc_renderer: ProceduralTurretRenderer = null
## 机关元素（_ready 时从 WeaponData 推导）：底座阵缘配色/形态与枪口闪光都按它分化
var _elem: String = "metal"

## 头顶状态牌（需维修 / 停摆 / 维修中）：Node2D + Label + LabelSettings，
## 照 BlessingObelisk 的碑顶读数范式（描边保证暗底可读），只在需要时显形。
var _readout: Node2D = null
var _readout_label: Label = null
var _readout_key: String = ""
## 磨损/停摆粒子的节拍器（纯表现层，不参与判定）
var _worn_fx_timer: float = 0.0
## 耐久弧/警示环的脉动相位
var _warn_phase: float = 0.0

func setup(def_id: String, star_level: int) -> void:
	weapon_def_id = def_id
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	_def = WeaponData.get_def(def_id)
	base_damage = WeaponData.damage_for(def_id, star)
	fire_cooldown = WeaponData.turret_fire_interval(def_id, star)
	attack_range = float(_def.get("range", 220.0))
	stamina_sec = maxf(1.0, float(_def.get("turret_stamina", BalanceTurret.STAMINA_SEC)))
	# 随机相位（开火错峰/索敌错相）放在 begin_life 里吃 rng：setup 是纯数据配置，
	# 升星时会就地在役机关重跑一次 —— 在 setup 里抽 GameManager.rng 会让「升星」这件事
	# 偷偷挪动后续掉落/暴击的随机序列（AGENTS 分层铁律 3）。
	# 弹丸外观缓存：默认路径与 _fire() 旧兜底同源（bullet_gold_needle）
	var bullet_path := String(_def.get("bullet", "res://assets/art/bullet_gold_needle.png"))
	if ResourceLoader.exists(bullet_path):
		_bullet_tex = load(bullet_path) as Texture2D
	_bullet_scale = float(_def.get("bullet_scale", 0.55))
	_bullet_spins = bool(_def.get("bullet_spin", false))
	if _proc_renderer != null:
		_proc_renderer.star = star
		_proc_renderer.queue_redraw()

func _ready() -> void:
	add_to_group("turrets")
	if _def.is_empty():
		_def = WeaponData.get_def(weapon_def_id)
	_elem = WeaponData.element_of(weapon_def_id)
	if _elem == "":
		_elem = "metal"
	_build_readout()
	queue_redraw()
	_setup_proc_renderer()
	_setup_muzzle_flash()

## 头顶状态牌：Node2D 挂在机关上，Label 居中在头顶；内容变了才重写。
func _build_readout() -> void:
	_readout = Node2D.new()
	_readout.name = "ServiceReadout"
	_readout.visible = false
	_readout.z_index = 2
	add_child(_readout)
	_readout_label = Label.new()
	var ls := LabelSettings.new()
	ls.font = GameStyle.body_font()
	ls.font_size = 12
	ls.outline_size = 4
	ls.outline_color = Color(0.02, 0.03, 0.06, 0.92)
	_readout_label.label_settings = ls
	_readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout_label.custom_minimum_size = Vector2(120, 18)
	_readout_label.position = Vector2(-60, -50)
	_readout.add_child(_readout_label)

## 单次布设生命周期的开场：入场弹起 + 落地钝响。
## 新建实例由宿主在 add_child 后调用；池化复用实例同样走这里（_ready 一生只跑一次，
## 不能把可见状态复位挂在 _ready 上）。
## keep_durability ≥ 0 时沿用（收回重摆带走耐久，收回不是免费维修）；否则满耐久新机关。
func begin_life(keep_durability: float = -1.0) -> void:
	_is_dying = false
	current_target = null
	_targets.clear()
	_had_target = false
	_shot_count = 0
	_is_repairing = false
	_repair_from = BalanceTurret.MAX_DURABILITY
	_wave_active = true
	durability = clampf(keep_durability, 0.0, BalanceTurret.MAX_DURABILITY) if keep_durability >= 0.0 else BalanceTurret.MAX_DURABILITY
	# 随机相位（布设时抽一次，走玩法 RNG —— 错峰影响开火节奏，属于判定侧）
	_cooldown_timer = GameManager.rng.randf_range(0.1, 0.3)
	_search_timer = GameManager.rng.randf_range(0.0, TARGET_SEARCH_INTERVAL)
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	core_sprite.rotation = 0.0
	core_sprite.position = Vector2.ZERO
	core_sprite.modulate = Color.WHITE
	# 器形/图标随武器与星级重新对齐（同一池服务所有机关武器）
	_elem = WeaponData.element_of(weapon_def_id)
	if _elem == "":
		_elem = "metal"
	_update_core_icon()
	_setup_proc_renderer()
	if _readout != null:
		_readout.visible = false
	_readout_key = ""
	_refresh_readout()
	queue_redraw()
	if muzzle_flash != null:
		muzzle_flash.visible = false
		muzzle_flash.modulate.a = 1.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	# 布设：机关砸进地面那一记钝响。不许借用 orb_hit（那是灵宝触敌的暖金钟）
	AudioManager.play_sfx("impact_blunt", 0.9)

func _update_core_icon() -> void:
	if _def.has("icon") and ResourceLoader.exists(_def["icon"]):
		core_sprite.texture = load(_def["icon"])

## 矢量机关本体：只在本批已实现器形时挂载，并把旧贴图隐蔽。
## 坐标契约见 ProceduralTurretRenderer 头注释：器形沿 +X 画、炮口落在本地 x=16（×1.5=24），
## 与 CoreSprite/MuzzlePoint 的本地 (24,0) 同源 ⇒ 出膛点零改动。
## 池化复用：同一池服务所有机关武器，每次复出都要按新器形重配，或按 GENERIC 退回贴图。
func _setup_proc_renderer() -> void:
	var tshape := ProceduralTurretRenderer.shape_from_name(String(_def.get("turret_shape", "")))
	if tshape == ProceduralTurretRenderer.TurretShape.GENERIC:
		if _proc_renderer != null:
			_proc_renderer.visible = false
		core_sprite.self_modulate.a = 1.0
		return
	if _proc_renderer == null:
		_proc_renderer = ProceduralTurretRenderer.new()
		_proc_renderer.name = "ProcTurret"
		# 挂在 CoreSprite 下：继承它的 0.55 缩放与 rotation，索敌转向自动同拍
		core_sprite.add_child(_proc_renderer)
	_proc_renderer.configure(tshape, _elem, star)
	_proc_renderer.visible = true
	core_sprite.self_modulate.a = 0.0

func _setup_muzzle_flash() -> void:
	if muzzle_point == null:
		return
	muzzle_flash = Sprite2D.new()
	var tex := load("res://assets/art/light_radial.png") as Texture2D
	if tex == null:
		return
	muzzle_flash.texture = tex
	muzzle_flash.material = SharedMaterials.add_blend()
	muzzle_flash.z_index = 6
	muzzle_flash.visible = false
	muzzle_point.add_child(muzzle_flash)

# ---------------- 耐久 / 维修 / 整备 ----------------

## 耐久比例 0..1（HUD / 世界弧共用）
func durability_ratio() -> float:
	return BalanceTurret.durability_ratio(durability)

func needs_service() -> bool:
	return BalanceTurret.needs_service(durability)

func is_broken() -> bool:
	return BalanceTurret.is_broken(durability)

## 开始维修（HUD 按住）：已满或正在修时是空操作
func begin_repair() -> void:
	if _is_dying or _is_repairing or durability >= BalanceTurret.MAX_DURABILITY - 0.001:
		return
	_repair_from = durability
	_is_repairing = true

## 结束维修（松手/离开范围/波末）：保留已修部分
func end_repair() -> void:
	if not _is_repairing:
		return
	_is_repairing = false
	_repair_from = BalanceTurret.MAX_DURABILITY
	_refresh_readout()

func is_repairing() -> bool:
	return _is_repairing

## 键面走针环的读数：从开始维修那一刻的耐久量到满，正好 1.0
func repair_ratio() -> float:
	if not _is_repairing:
		return 0.0
	var need := BalanceTurret.MAX_DURABILITY - _repair_from
	if need <= 0.001:
		return 1.0
	return clampf((durability - _repair_from) / need, 0.0, 1.0)

## 回合末整备：停火 + 耐久回满 + 青色回满脉冲。机关不消散（跨回合保留位置）。
func on_wave_end() -> void:
	_wave_active = false
	_is_repairing = false
	_repair_from = BalanceTurret.MAX_DURABILITY
	_targets.clear()
	current_target = null
	_had_target = false
	durability = BalanceTurret.MAX_DURABILITY
	_refresh_readout()
	queue_redraw()
	_play_ready_pulse()

## 波次开始：重新接管索敌与开火
func set_wave_active(on: bool) -> void:
	_wave_active = on
	if not on:
		_is_repairing = false
		_targets.clear()
		current_target = null
		_had_target = false

func _play_ready_pulse() -> void:
	modulate = Color(1.0, 1.0, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.75, 1.35, 1.0), 0.18)
	tw.tween_property(self, "modulate", Color.WHITE, 0.28)
	# 不在这里放音效：波末收尾已经有一记 wave_clear，最多 6 台机关同帧各响一次会盖住它

func _play_repair_done() -> void:
	_is_repairing = false
	_repair_from = BalanceTurret.MAX_DURABILITY
	_refresh_readout()
	queue_redraw()
	modulate = Color.WHITE
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(0.8, 1.4, 1.05), 0.10)
	tw.tween_property(self, "modulate", Color.WHITE, 0.22)
	AudioManager.play_sfx("ui_confirm", 0.7)
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position + Vector2(0, -6), _elem, 0.5, true)

## 头顶状态牌：磨损「需维修 N%」/ 停摆「停摆」/ 维修中「维修中 N%」
func _refresh_readout() -> void:
	if _readout == null or _readout_label == null:
		return
	var text := ""
	var col: Color = GameStyle.CHALK
	if _is_repairing:
		text = "维修中 %d%%" % roundi(durability_ratio() * 100.0)
		col = GameStyle.JADE
	elif is_broken():
		text = "停摆"
		col = GameStyle.BAD
	elif BalanceTurret.needs_service(durability):
		text = "需维修 %d%%" % roundi(durability_ratio() * 100.0)
		col = GameStyle.GOLD_EDGE
	if text == _readout_key:
		_readout_label.label_settings.font_color = col
		return
	_readout_key = text
	_readout.visible = not text.is_empty()
	_readout_label.text = text
	_readout_label.label_settings.font_color = col

# ---------------- 绘制 ----------------

func _draw() -> void:
	# 冷冽几何正圆机关阵盘底座：阵缘配色与形态按元素分化（俯视不做透视压扁）。
	var r_outer := 18.0
	var r_inner := 13.0
	var edge_col: Color = _elem_edge_color()

	# 1. 贴地双层软阴影（外圈漫溢衰减 + 接触内核）
	draw_circle(Vector2(0.0, 1.5), r_outer * 1.30, Color(0.02, 0.03, 0.05, 0.25))
	draw_circle(Vector2(0.0, 1.0), r_outer * 1.08, Color(0.02, 0.03, 0.05, 0.50))

	# 2. 正圆机关阵盘底座：实心盘 + 外缘亮环 + 内圈暗环
	draw_circle(Vector2.ZERO, r_outer, Color(0.08, 0.10, 0.14, 0.90))
	draw_arc(Vector2.ZERO, r_outer, 0.0, TAU, 40, edge_col, 2.0, true)
	draw_arc(Vector2.ZERO, r_inner, 0.0, TAU, 32,
		Color(edge_col.r, edge_col.g, edge_col.b, 0.55), 1.2, true)
	_draw_elem_accents(r_outer, edge_col)

	# 3. 耐久弧（<100% 才画）：完好=元素色、磨损=橙、停摆=朱砂。
	#    「画多少 == 还剩多少」，与 HUD 的百分比读同一个 durability，不做第二套口径。
	if durability < BalanceTurret.MAX_DURABILITY - 0.01:
		var ratio := durability_ratio()
		var col: Color = _durability_color(ratio)
		var start := -PI * 0.5
		draw_arc(Vector2.ZERO, r_outer + 4.0, start, start + TAU * ratio, 40, col, 2.5, true)
	# 4. 磨损/停摆警示环：外圈脉动，一眼看出哪台要处理（纯表现层相位）
	if BalanceTurret.needs_service(durability):
		var pulse := 0.35 + 0.35 * sin(_warn_phase * 6.0)
		var warn_col: Color = GameStyle.BAD if is_broken() else GameStyle.GOLD_EDGE
		draw_arc(Vector2.ZERO, r_outer + 8.0, 0.0, TAU, 40,
			Color(warn_col.r, warn_col.g, warn_col.b, pulse), 1.6, true)

func _durability_color(ratio: float) -> Color:
	if is_broken():
		return GameStyle.BAD
	if ratio < BalanceTurret.WORN_RATIO:
		return GameStyle.BAD.lerp(GameStyle.GOLD_EDGE, ratio / BalanceTurret.WORN_RATIO)
	return _elem_edge_color()

## 阵缘元素色（黑底上要够亮才读得出）
func _elem_edge_color() -> Color:
	match _elem:
		"fire":
			return Color(1.0, 0.52, 0.22, 0.9)
		"water":
			return Color(0.45, 0.78, 1.0, 0.9)
		"wood":
			return Color(0.45, 0.88, 0.50, 0.9)
		"earth":
			return Color(0.88, 0.68, 0.38, 0.9)
		_:
			return Color(0.88, 0.74, 0.42, 0.9)

## 阵缘元素形态点缀：金=弩机弦线 火=三处喷口 水=四枚晶刺 木=缠藤弧 土=方形垛口
func _draw_elem_accents(r_outer: float, edge_col: Color) -> void:
	match _elem:
		"fire":
			# 三处喷口：外缘缺口里的火舌小三角
			for deg in [30.0, 150.0, 270.0]:
				var a := deg_to_rad(deg)
				var dir := Vector2(cos(a), sin(a))
				var tan := Vector2(-sin(a), cos(a))
				var base := dir * (r_outer + 1.0)
				draw_colored_polygon(PackedVector2Array([
					base + tan * 3.0, base - tan * 3.0, dir * (r_outer + 7.0)]),
					Color(1.0, 0.6, 0.25, 0.85))
		"water":
			# 四枚晶刺立在外缘
			for deg in [45.0, 135.0, 225.0, 315.0]:
				var a := deg_to_rad(deg)
				var dir := Vector2(cos(a), sin(a))
				var tan := Vector2(-sin(a), cos(a))
				var base := dir * r_outer
				draw_colored_polygon(PackedVector2Array([
					base + tan * 2.2, base - tan * 2.2, dir * (r_outer + 6.0)]),
					Color(0.75, 0.92, 1.0, 0.85))
		"wood":
			# 两段缠藤弧攀在阵缘上
			for start_deg in [100.0, 280.0]:
				var arc := PackedVector2Array()
				for k in 7:
					var a := deg_to_rad(start_deg + float(k) * 8.0)
					arc.append(Vector2(cos(a), sin(a)) * (r_outer + 1.5 + sin(float(k) * 1.8) * 1.2))
				draw_polyline(arc, Color(0.5, 0.9, 0.5, 0.7), 1.2)
		"earth":
			# 方形垛口：四角的垒石齿
			for deg in [0.0, 90.0, 180.0, 270.0]:
				var a := deg_to_rad(deg)
				var dir := Vector2(cos(a), sin(a))
				var tan := Vector2(-sin(a), cos(a))
				var base := dir * (r_outer + 1.5)
				draw_colored_polygon(PackedVector2Array([
					base + tan * 2.5, base - tan * 2.5,
					base - tan * 2.5 + dir * 3.5, base + tan * 2.5 + dir * 3.5]),
					Color(0.8, 0.62, 0.35, 0.85))
		_:
			# 金系弩机：两道弦线交叉在盘面
			draw_line(Vector2(-r_outer + 3.0, 0), Vector2(r_outer - 3.0, 0),
				Color(edge_col.r, edge_col.g, edge_col.b, 0.35), 0.9)
			draw_line(Vector2(0, -r_outer + 3.0), Vector2(0, r_outer - 3.0),
				Color(edge_col.r, edge_col.g, edge_col.b, 0.35), 0.9)

# ---------------- 每帧 ----------------

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	if _is_dying:
		return
	if not _wave_active:
		return

	_cooldown_timer -= delta
	_spin_angle += delta * 1.5
	_warn_phase += delta

	# 维修：连续回填（松手保留已修部分）；满了收工
	if _is_repairing:
		durability = minf(BalanceTurret.MAX_DURABILITY,
			durability + BalanceTurret.repair_per_sec(GameManager.turret_repair_haste_mul) * delta)
		var ratio := repair_ratio()
		if _readout_label != null:
			_readout_key = "维修中 %d%%" % roundi(ratio * 100.0)
			_readout.visible = true
			_readout_label.text = _readout_key
			_readout_label.label_settings.font_color = GameStyle.JADE
		if durability >= BalanceTurret.MAX_DURABILITY - 0.001:
			durability = BalanceTurret.MAX_DURABILITY
			_play_repair_done()
		queue_redraw()
	# 磨损/停摆的体表提示：橙环/红环脉动重画 + 低频碎屑（纯表现层，走帧预算闸）
	if BalanceTurret.needs_service(durability):
		queue_redraw()
		_worn_fx_timer -= delta
		if _worn_fx_timer <= 0.0:
			_worn_fx_timer = 0.55 if is_broken() else 0.8
			var ember_col: Color = Color(0.5, 0.5, 0.52, 0.45) if is_broken() else Color(0.95, 0.62, 0.25, 0.5)
			FxParticlePool.burst(FxParticlePool.EMBER, global_position + Vector2(0, -6),
				ember_col, 0.35, true)

	# 停摆：默认完全停工（索敌也停，省掉每节拍一次物理查询），警示环继续脉动。
	# 「恒机芯」道具（item hook turret_broken_haste）改为降半速继续运转 —— 容错件，
	# 不改变「维修才有满速」的主线，只是让跑位期不至于整条火力归零。
	if is_broken() and broken_haste() <= 0.0:
		current_target = null
		_targets.clear()
		_had_target = false
		if _cooldown_timer < 0.0:
			_cooldown_timer = 0.0
		return

	# 索敌与瞄准：15Hz 节流；一次查询拿到最多「齐射管数」个最近的敌人
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = TARGET_SEARCH_INTERVAL
		_refresh_targets()
		if _targets.is_empty():
			current_target = null
		else:
			current_target = _targets[0]

	# 空闲期冷却钳制与接敌首拍错峰（2026-11-03）：
	# 无目标时冷却扣成负数钳到 0，避免空场蓄力齐射；接敌瞬间由闲转战补 0~0.15s 随机错峰，
	# 避免空场后所有机关同帧齐射。
	var has_target: bool = current_target != null and not _targets.is_empty()
	if _cooldown_timer < 0.0 and not has_target:
		_cooldown_timer = 0.0
	if has_target and not _had_target:
		_cooldown_timer = maxf(_cooldown_timer, GameManager.rng.randf_range(0.0, 0.15))
	_had_target = has_target

	if current_target != null and is_instance_valid(current_target):
		var target_angle := (current_target.global_position - global_position).angle()
		core_sprite.rotation = lerp_angle(core_sprite.rotation, target_angle, minf(delta * 12.0, 1.0))
	else:
		core_sprite.rotation = _spin_angle

	if _cooldown_timer <= 0.0 and not _targets.is_empty():
		_fire()

## 射程乘区（攻击范围词条 + 剑系/广域羁绊）：照 FloatingWeapon._range_mult 同一口径——
## 详情卡/商店卡展示的「攻击范围 = 基础 × 该乘区」，机关台实际索敌必须同源。
func _eff_range() -> float:
	return attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult

## 一次查询同时刷新「瞄准目标」与「齐射分敌表」：取最近的 volley 个敌人，按距离升序。
## 旧写法每座炮台各自查一次最近敌人 —— 现在一把武器只有一台机关，一台要覆盖 N 个目标，
## 所以查询从「每 66ms 一次取 1 个」变成「每 66ms 一次取 N 个」，总量反而比旧版
## （最多 6 武器 × 5 座）低一个量级。
func _refresh_targets() -> void:
	_targets.clear()
	if _search_shape == null or _search_query == null:
		_search_shape = CircleShape2D.new()
		_search_query = PhysicsShapeQueryParameters2D.new()
		_search_query.shape = _search_shape
		_search_query.collision_mask = 4
		_search_query.collide_with_areas = true
		_search_query.collide_with_bodies = false  # 只查敌人 Hurtbox(Area)，不扫 body 层
	_search_shape.radius = _eff_range()
	_search_query.transform = Transform2D(0.0, global_position)
	var results := get_world_2d().direct_space_state.intersect_shape(_search_query, 24)

	_cand_nodes.clear()
	_cand_dists.clear()
	var want := volley   # getter 现读一次，循环里不再重复取（齐射管数可被悟道/道具加成）
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent == null or not parent.has_method("take_damage"):
			continue
		var enemy = parent as Node2D
		if enemy == null or enemy.is_in_group("herbs") or enemy.is_in_group("chests"):
			continue
		var d := global_position.distance_squared_to(enemy.global_position)
		# 插入排序只维护前 want 个（want ≤ 6，24 个候选最多 144 次比较）
		var pos := _cand_dists.size()
		while pos > 0 and _cand_dists[pos - 1] > d:
			pos -= 1
		if pos >= want:
			continue
		_cand_dists.insert(pos, d)
		_cand_nodes.insert(pos, enemy)
		if _cand_dists.size() > want:
			_cand_dists.pop_back()
			_cand_nodes.pop_back()
	_targets.clear()
	_targets.append_array(_cand_nodes)

func _final_damage() -> float:
	var stat_bonus: float = GameManager.get_weapon_stat_bonus(weapon_def_id, star)
	# 2026-10-17 性能专项：反射 get() 每次开火 2 次字符串查改直接字段访问
	return (base_damage + stat_bonus) * GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult * GameManager.shadow_amp_mult * GameManager.synergy_contraption_mult * GameManager.cultivator_damage_mult(weapon_def_id) * GameManager.element_damage_mult(weapon_def_id) * GameManager.get_multi_weapon_damage_mult()

## 开火间隔有效值：装备/加点层 × 羁绊层 × 疾风咒 buff 层 × 站定神像 × 磨损档降速。
## 磨损档乘在最后（乘在中间会被攻速钳位吞掉）；返回值同时是本次磨损量的时间基准，
## 所以「每秒磨损」与攻速无关 —— 加速只是更快把这段时间走完，不会更快磨坏。
func _eff_fire_cd() -> float:
	var turret_haste: float = 1.0 - GameManager.item_hook_sum("turret_haste")
	var base := fire_cooldown * GameManager.get_effective_attack_speed_mult() * maxf(0.2, turret_haste)
	var mult := BalanceTurret.fire_interval_mult(durability)
	if is_broken():
		var bh := broken_haste()
		if bh > 0.0:
			mult *= 1.0 / clampf(bh, BalanceTurret.BROKEN_HASTE_FLOOR, 1.0)
	return base * mult

func _fire() -> void:
	var interval := maxf(0.12, _eff_fire_cd())
	var valid: Array[Node2D] = []
	for t in _targets:
		if t != null and is_instance_valid(t):
			valid.append(t)
	if valid.is_empty():
		# 缓存里那几只在这 66ms 内全死了：这一拍不开火，也不扣耐久/不进冷却
		_targets.clear()
		current_target = null
		_cooldown_timer = 0.0
		return
	_cooldown_timer = interval
	# 磨损：按本次实际开火间隔折算 ⇒ 连续开火正好「实际耐久时长」秒磨到底
	durability = maxf(0.0, durability - BalanceTurret.wear_per_shot(interval, effective_stamina()))

	var primary: Node2D = valid[0]
	var aim_dir := (primary.global_position - muzzle_point.global_position).normalized()
	var final_dmg := _final_damage()
	for i in volley:
		# 一管一个目标（不足 N 个则余下全部打最近的那个）——对应旧版 N 座各自锁最近敌人
		var target: Node2D = valid[i] if i < valid.size() else primary
		_fire_one(target, final_dmg,
			(target.global_position - muzzle_point.global_position).normalized())
	_refresh_readout()
	queue_redraw()
	_fire_feedback(aim_dir)

## 单管出膛：弹丸参数照旧，独立取池（与旧版每座炮台各发一枚完全等价）
func _fire_one(target: Node2D, final_dmg: float, aim_dir: Vector2) -> void:
	var p := BladeProjectile.acquire_or_new(projectile_scene, get_tree().current_scene)
	p.global_position = muzzle_point.global_position
	p.direction = aim_dir
	p.homing_target = target
	p.damage = final_dmg
	p.knockback_base = WeaponData.knockback_for(weapon_def_id, 120.0)
	p.pierce_left = WeaponData.capped_pierce(int(_def.get("pierce", 1)) + GameManager.bonus_pierce)
	p.bounce_left = int(_def.get("bounce_count", 0))
	p.bullet_texture = _bullet_tex
	p.bullet_scale = _bullet_scale
	p.spin = _bullet_spins
	# 吸血分档：机关炮台出的弹按高频接触档
	p.source_behavior = WeaponData.Behavior.TURRET

	# 五行异常（2026-11-03 补漏）：旧写法只接了灼烧，寒泉兽/凝冰机弩的冰缓与藤萝机关的
	# 叠毒在数据表与文案里都承诺了、运行时却从未生效。口径照 ProjectileHandler 三段复制。
	if _def.get("proc_burn", false):
		p.proc_burn = true
		p.burn_dps = final_dmg * float(_def.get("burn_ratio", 0.4))
		p.burn_dur = float(_def.get("burn_dur", 2.5))
	if float(_def.get("proc_chill", 0.0)) > 0.0:
		p.proc_chill = float(_def.get("proc_chill", 0.35))
		p.chill_dur = float(_def.get("chill_dur", 2.0))
	if _def.get("proc_poison", false):
		p.proc_poison = true
		p.poison_dps = final_dmg * float(_def.get("poison_ratio", 0.3))
		p.poison_dur = float(_def.get("poison_dur", 2.5))

	p.activate()
	# ★3/★4 极境弹丸染色：必须在 activate 之后——activate 会把池化残值洗回 WHITE。
	# 逐管推进相位：一次齐射里青/紫交替，读得出「多管」而不是同一发画了 N 遍。
	if star >= 3:
		p.modulate = GameStyle.star_fx_color(star, _shot_count)
	_shot_count += 1
	# 寿命按索敌半径补齐：叠了范围的机关要锁得到也飞得到
	p.lifetime = maxf(p.lifetime, _eff_range() / p.speed + 0.05)

## 一次齐射只做一套反馈（枪口闪/后坐/音效/碎屑），N 管共用一个节拍，
## 否则 ★4 五管会把同帧粒子预算吃光。
func _fire_feedback(aim_dir: Vector2) -> void:
	core_sprite.modulate = GameStyle.star_fx_color(star, _shot_count) if star >= 3 else Color(1.4, 1.35, 1.2)
	core_sprite.position = -aim_dir * 3.5
	_fire_tween = create_tween()
	var tw := _fire_tween
	tw.set_parallel(true)
	if muzzle_flash != null:
		muzzle_flash.rotation = randf() * TAU
		muzzle_flash.scale = Vector2.ONE * randf_range(0.35, 0.45)
		var flash_col := GameStyle.fx_hdr_element(_elem, GameStyle.FX_HDR_CORE)
		if star >= 3:
			flash_col = GameStyle.star_fx_color(star, _shot_count)
		muzzle_flash.modulate = flash_col
		muzzle_flash.visible = true
		tw.tween_property(muzzle_flash, "scale", Vector2.ONE * 0.75, 0.08)
		tw.tween_property(muzzle_flash, "modulate:a", 0.0, 0.08)
	tw.tween_property(core_sprite, "modulate", Color.WHITE, 0.1)
	tw.tween_property(core_sprite, "position", Vector2.ZERO, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if muzzle_flash != null:
		tw.chain().tween_callback(func(): muzzle_flash.visible = false)

	FxParticlePool.burst(FxParticlePool.HIT_SPARK, muzzle_point.global_position, _elem, 0.45, true, aim_dir)
	StrikeFx.fire_sfx(self, WeaponData.sfx_for(weapon_def_id), 0.95)

# ---------------- 消散 / 回池 ----------------

## fold = true 时是「收回」：折叠上浮后回池（编制返还由调用方处理）。
func dismiss(fold: bool = false) -> void:
	if _is_dying:
		return
	_is_dying = true
	_is_repairing = false
	_had_target = false
	if _fire_tween != null and _fire_tween.is_valid():
		_fire_tween.kill()
	if muzzle_flash != null:
		muzzle_flash.visible = false
	if _readout != null:
		_readout.visible = false
	_dismiss_tween = create_tween()
	_dismiss_tween.set_parallel(true)
	if fold:
		_dismiss_tween.tween_property(self, "position", position + Vector2(0.0, -14.0), 0.18)
		_dismiss_tween.tween_property(self, "scale", Vector2(0.35, 0.35), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		_dismiss_tween.tween_property(self, "scale", Vector2(0.2, 0.2), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_dismiss_tween.tween_property(self, "modulate:a", 0.0, 0.2)
	_dismiss_tween.chain().tween_callback(_recycle)

## 消散演出结束：回池休眠（出树 + 停处理），池满才真正释放
func _recycle() -> void:
	if _dismiss_tween != null and _dismiss_tween.is_valid():
		_dismiss_tween.kill()
	if _fire_tween != null and _fire_tween.is_valid():
		_fire_tween.kill()
	current_target = null
	_targets.clear()
	if _owner_weapon != null and is_instance_valid(_owner_weapon):
		var owned: Array = _owner_weapon.active_turrets
		owned.erase(self)
	_owner_weapon = null
	if _pool_key.is_empty():
		queue_free()
		return
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	var bucket: Array = _pools.get(_pool_key, [])
	if bucket.size() >= POOL_CAP_PER_SCENE:
		free()
		return
	bucket.append(self)
	_pools[_pool_key] = bucket