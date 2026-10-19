class_name Player
extends CharacterBody2D

const BASE_PICKUP_RADIUS: float = 96.0   ## 拾取圈内径（福缘/乾坤袋按乘区放大）
const DASH_LANDING_SPEED_MUL: float = 1.35  ## 冲刺落地那帧的残留速度上限（× 常速）：只留一点前冲，不许拖出隐形滑行
const SPIRIT_HEALER_SCENE: PackedScene = preload("res://scenes/entities/SpiritHealer.tscn")  ## 治疗灵兽（renewal 附带召唤）
## 玩家基础属性三件套：全项目「玩家没生成时」的兜底读数一律引用这三个常量，
## 不许再各写一份字面量（改一个数要同步七处的旧病）。
const BASE_MAX_HEALTH: float = 120.0      ## 基础生命：CultivatorData 只有 hp_mult 乘区，这里是唯一权威基线
const BASE_SPEED: float = 210.0           ## 基础移速（乘区/技能 buff 在此之上叠加）
## 受击无敌帧（秒）。它同时是挨打频率的饱和线：1/0.55 ≈ 1.82 下/秒，
## GuardStanceData 的蓄能节流、ShadowStepData 的有效生命兑现、BalanceWave 的挨打生存论证都锚这个数 ——
## 改它之前先把那三处的注释推导一起重算，否则平衡文档会静默失真。
const BASE_INVULNERABLE_TIME: float = 0.55

@export var max_health: float = BASE_MAX_HEALTH
var current_health: float = BASE_MAX_HEALTH
var base_speed: float = BASE_SPEED
var invulnerable_time: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var sun_orb_container: Node2D = $SunOrbContainer
@onready var weapon_holder: Node2D = $WeaponHolder
@onready var pickup_area: Area2D = $PickupArea
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial
@onready var skill_vfx: PlayerSkillVfx = $SkillVfx
@onready var level_ritual: Node2D = $PlayerLevelRitual

var sun_orb_angle: float = 0.0
var idle_bob_phase: float = 0.0
var facing: String = "s":
	set(val):
		# 同值短路：_physics_process 每帧都会写本字段（照 EnemyBase 同款缓存）
		if val == facing:
			return
		facing = val
		_rebuild_anim_name_cache()
## 动画名缓存：facing 极少变化，但朝向/步态分支每物理帧都要拼接 + has_animation
## 重查，改为 facing 变更时一次性重建（与 EnemyBase 同口径）
var _anim_idle: String = "idle_s"
var _anim_run: String = "run_s"
# 移动方式：gait=步态腿帧（默认）/ hover=御剑悬浮（单姿势图集 + RunMotion.apply_hover 程序驱动）
var _motion_mode: String = "gait"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var regen_tick: float = 0.0
var squash_tween: Tween = null
var _flash_t: float = 0.0  ## 受击闪白剩余秒（帧内衰减，顶点色通道 self_modulate 承载）
var _run_state := RunMotion.RunMotionState.new()   ## 步态/悬浮状态载体（2026-10-17 去 meta 化，随实例常驻）
## 受击闪白顶点色写入（2026-10-17 与 EnemyBase 同口径）：材质共享零 uniform，
## 闪白强度由 self_modulate 提亮承载；modulate 归无敌帧频闪/护体金光，COLOR 相乘叠加。
## 玩家闪白无分级色（纯亮白），同值短路防无谓属性写。
func _write_flash_channel(flash: float) -> void:
	if flash <= 0.001:
		if anim_sprite.self_modulate != Color.WHITE:
			anim_sprite.self_modulate = Color.WHITE
		if procedural_view != null and procedural_view.self_modulate != Color.WHITE:
			procedural_view.self_modulate = Color.WHITE
		return
	var tint: Color = Color.WHITE.lerp(Color(1.8, 1.75, 1.7), clampf(flash, 0.0, 1.0))
	anim_sprite.self_modulate = tint
	if procedural_view != null:
		procedural_view.self_modulate = tint
## 定向受击反馈（2026-10-15 对齐敌人）：受力方向后仰倾角（rad）与微反冲位移（px），
## 均零 Tween 帧内衰减；tilt 并入行走侧倾的 rotation lerp 目标，jiggle 直写 position。
var _hit_tilt: float = 0.0
var _hit_jiggle_offset: Vector2 = Vector2.ZERO
## 玩家受击闪白衰减总时长：与敌人暖白衰减（0.11s）同档，无敌帧 0.55s 内必然归零
const PLAYER_FLASH_DOWN_DUR: float = 0.11
var procedural_view: ProceduralCultivatorView = null
var is_procedural: bool = false
var gait_phase_counter: float = 0.0

# ---------------- 随行技能运行时 ----------------
## 冷却账本两段式：施放先开「效果活跃窗口」（skill_active_*），窗口走完才进冷却（skill_cd_*）。
## 窗口时长按技能类型取值：加速/急速/无敌 = duration，冲刺 = iframe 无敌时长，治疗瞬发 = 0（按下即进 CD）。
var skill_cd_left: float = 0.0     ## 技能冷却剩余秒（HUD 冷却遮罩轮询这个）
var skill_cd_total: float = 1.0    ## 本次释放进入的总冷却（算遮罩比例用）
var skill_active_left: float = 0.0 ## 效果活跃窗口剩余秒（>0 = 效果进行中、冷却未开始，HUD 亮黄环）
var skill_active_total: float = 1.0 ## 本次活跃窗口总时长（HUD 活跃环比例用）
var extra_skill_cd_left: float = 0.0  ## 额外技能冷却剩余秒（药爆等带 CD 的额外技能用）
var extra_skill_cd_total: float = 1.0 ## 额外技能总冷却（算遮罩比例用）
var _skill_active_kind: int = -1   ## 活跃窗口对应的技能 Kind（收尾钩子用，-1 = 无活跃技能）
var _skill_pending_cd: float = 0.0 ## 效果结束后要进入的冷却值（施放时暂存）
var _skill_buffs: Dictionary = {}  ## 进行中的短时增益：buff id -> 剩余秒（gale / haste）
var _expired_buffs_buf: Array = [] ## 复用数组，避免 _tick_skill_buffs 每帧分配
var _gale_cap_forced: bool = false ## 神行术这轮是否把闪避上限临时抬到 1.0（影者 100% 闪避专属）
var _gale_cap_before: float = 0.0  ## 抬上限前那一帧的角色抬升值（回滚按它还原，别拿算式反推）
var _dash_time: float = 0.0        ## 冲刺剩余秒（>0 期间移动被冲刺接管）
var _dash_dir: Vector2 = Vector2.DOWN
var _dash_speed: float = 0.0
var _thunder_cd: float = 1.5       ## 天雷倒计时（雷法真君；开局 1.5s 首雷见面礼，之后按 ThunderData.INTERVAL）
var _crowd_tick: float = 0.0       ## 蛮兵·陷阵感知节流（0.2s 一数，与 HUD 读数同频）

# ---------------- 踏影（闪避出口，数值全在 ShadowStepData） ----------------
## 影层队列：每次闪避成功把「躲掉的那一刀」的原值按 FIFO 存进来，影爆（额外技能）一键全部踩碎兑现。
## 队列长度就是层数（HUD 影爆键角标与角色身上的残影都直接读这里）。
var shadow_ring: Array = []

## 阵亡谢幕进行中（演出窗口挡移动/技能/再受创）；结算触发后的收尾全走 is_game_over。
## 演出约 1s：塌伏 → 沉没消散 → trigger_game_over（结算面板自带 paused + defeat BGM）。
var _dying: bool = false
## 通关胜利演出进行中（得道飞升镜头推进 + 仙乐灵气环爆发）
var _victorious: bool = false

var floating_weapon_scene: PackedScene = preload("res://scenes/weapons/FloatingWeapon.tscn")
var sun_orb_scene: PackedScene = preload("res://scenes/weapons/SunOrb.tscn")

# ---------------- 物理帧索敌与御灵查询复用缓冲（零每帧 new） ----------------
var _target_shape: CircleShape2D = null
var _target_query: PhysicsShapeQueryParameters2D = null
var _orb_shape: CircleShape2D = null
var _orb_query: PhysicsShapeQueryParameters2D = null
var query_alloc_count: int = 0
var query_reuse_count: int = 0

var _weapons_buf: Array[FloatingWeapon] = []
## 拾取圈形状的独立副本（_ready 时 duplicate 一次常驻）：此后 _sync_pickup_radius
## 原地改 radius（物理服务器自动感知），不再走走停停每次 duplicate + 重绑
var _pickup_shape: CircleShape2D = null
## joystick.get_direction 能力缓存（避免每物理帧 has_method 字符串查表）
var _joy_get_dir_checked: bool = false
var _joy_get_dir_ok: bool = false
var _candidate_enemies_buf: Array[Node2D] = []
var _candidate_chests_buf: Array[Node2D] = []
var _candidate_targets_buf: Array[Node2D] = []
var _seen_ids_buf: Dictionary = {}
var _weapons_info_buf: Array[Dictionary] = []
var _enemies_info_buf: Array[Dictionary] = []
var _chests_info_buf: Array[Dictionary] = []
var _weapons_dict_pool: Array[Dictionary] = []
var _enemies_dict_pool: Array[Dictionary] = []
var _chests_dict_pool: Array[Dictionary] = []
var _orb_enemies_buf: Array[Dictionary] = []
var _orb_dict_pool: Array[Dictionary] = []
var _orb_angles_buf: Array[float] = []
var _target_groups_buf: Dictionary = {}

func _ready() -> void:
	current_health = max_health
	GameManager.player = self
	GameManager.player_hp_changed.emit(current_health, max_health)
	GameManager.player_leveled_up.connect(_on_leveled_up)
	GameManager.upgrade_applied.connect(_on_upgrade_applied)
	anim_base_scale = anim_sprite.scale
	_setup_sprite_frames()
	# 浮游武器在 _process 里做轨道跟随（渲染帧率），父链开了物理插值会互相打架，关闭该分支插值
	weapon_holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_search_phase = fposmod(float(get_instance_id() % 97) * 0.001, TARGET_SEARCH_INTERVAL)
	sync_drones()
	_sync_pickup_radius()

func _setup_sprite_frames() -> void:
	if GameManager.cultivator_id.is_empty():
		anim_sprite.visible = false
		if shadow_sprite != null:
			shadow_sprite.visible = false
		if procedural_view != null:
			procedural_view.visible = false
		return

	if shadow_sprite != null:
		shadow_sprite.visible = true

	# 角色独立形象：按道统读 CultivatorData.sprite 的 8 方向图集，缺图回退默认青衫角色
	var sheet_path := "res://assets/art/pawn_blue_8dir.png"
	var cdef := CultivatorData.get_def(GameManager.cultivator_id)
	_motion_mode = String(cdef.get("motion", "gait"))

	if _motion_mode == "procedural":
		is_procedural = true
		anim_sprite.visible = false
		# 双影子二选一（2026-10-14 P2）：渲染器自画矢量地影（_draw_ground_shadow，
		# 带呼吸/姿态联动），sprite 影在此分支纯叠画冗余——隐藏而非删节点，
		# 图集道统（gait/hover）回来时仍要用它（RunMotion._apply_shadow 驱动）
		if shadow_sprite != null:
			shadow_sprite.visible = false
		var init_scale := anim_base_scale * 1.5
		# 受击闪白材质真话只有一份：挂在程序化视图上吃（渲染器 use_parent_material 继承）。
		# 旧写法 tween 到已隐藏的 anim_sprite 上，玩家本体从不闪白（v0.0.33 及之前一直失效）。
		if procedural_view == null:
			procedural_view = ProceduralCultivatorView.new()
			procedural_view.high_fps_mode = true
			procedural_view.position = anim_sprite.position
			procedural_view.scale = init_scale
			procedural_view.material = hit_flash_mat
			procedural_view.setup_character_id(GameManager.cultivator_id)
			procedural_view.play_idle()
			add_child(procedural_view)
		else:
			procedural_view.high_fps_mode = true
			procedural_view.scale = init_scale
			procedural_view.material = hit_flash_mat
			procedural_view.setup_character_id(GameManager.cultivator_id)
			procedural_view.play_idle()
			procedural_view.visible = true
		# 程序化角色不加载图集：全部 19 位角色都是 procedural，而每张 960×960 图集
		# 解码后占 3.5MB，屏上实际只有约 144px（192px 格 × 0.75）
		anim_sprite.sprite_frames = null
		return

	# ---- 图集道统（休眠代码，2026-10-14 P2 钉死口径）----
	# 全员 procedural 的今天本段永不执行，但它是未来新道统（gait 腿帧步态 / hover
	# 御剑悬浮）的即插即用路径：CultivatorData.sprite + motion 字段、RunMotion 的
	# apply/apply_hover 分支、下方 SpriteFrames 构建与 RunMotion._apply_shadow 的
	# sprite 影全链路一一配套。严禁当死代码顺手清除。
	is_procedural = false
	anim_sprite.visible = true
	# 图集角色吃 RunMotion 驱动的 sprite 影（程序化角色用渲染器矢量影，二者互斥）
	if shadow_sprite != null:
		shadow_sprite.visible = true
	if procedural_view != null:
		procedural_view.visible = false

	var char_sprite := String(cdef.get("sprite", ""))
	if char_sprite != "" and ResourceLoader.exists(char_sprite):
		sheet_path = char_sprite
	var base_tex = load(sheet_path) as Texture2D
	var sf = SpriteFrames.new()
	for dir in RunMotion.DIR_ROW:
		var row: int = RunMotion.DIR_ROW[dir]
		sf.add_animation("idle_" + dir)
		sf.set_animation_speed("idle_" + dir, 1.0)
		sf.set_animation_loop("idle_" + dir, true)
		sf.add_frame("idle_" + dir, _cell_tex(base_tex, 0, row))

		sf.add_animation("run_" + dir)
		# 4 帧跑步循环（contact/passing×2 = 每循环 2 步）：8fps ≈ 每秒 4 步，
		# 像素走路循环的行业经验是 4 帧素材不超过 8fps，再高就是"原地碎步倒腾"
		sf.set_animation_speed("run_" + dir, 8.0)
		sf.set_animation_loop("run_" + dir, true)
		for c in range(1, 5):
			sf.add_frame("run_" + dir, _cell_tex(base_tex, c, row))

	anim_sprite.sprite_frames = sf
	anim_sprite.play("idle_s")
	_rebuild_anim_name_cache()

## 按 facing 重建 idle/run 动画名缓存（帧集装配与朝向变更时各调一次）
func _rebuild_anim_name_cache() -> void:
	_anim_idle = "idle_" + facing
	_anim_run = "run_" + facing

func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 192, row * 192, 192, 192)
	return at

## 挤压与拉伸（Squash & Stretch）手感核心方法
func play_squash(target: Vector2, duration: float = 0.18) -> void:
	if squash_tween != null and squash_tween.is_valid():
		squash_tween.kill()
	juice_scale = target
	squash_tween = create_tween()
	squash_tween.tween_property(self, "juice_scale", Vector2.ONE, duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _on_upgrade_applied(up_id: String) -> void:
	if up_id == "pickup_up":
		_sync_pickup_radius()

func _sync_pickup_radius() -> void:
	var shape_node = $PickupArea/CollisionShape2D
	if shape_node == null or not (shape_node.shape is CircleShape2D):
		return
	# 形状只此一个消费者：_ready 首次调用时独立化一次，之后原地改 radius 短路复用
	# （旧写法走停边沿每次 duplicate 新 CircleShape2D + 重绑，白发分配与物理重注册）
	if _pickup_shape == null:
		_pickup_shape = shape_node.shape.duplicate() as CircleShape2D
		shape_node.shape = _pickup_shape
	var bonus := GameManager.still_pickup_bonus if (GameManager.still_time > 0.0) else 0.0
	var radius := BASE_PICKUP_RADIUS * (GameManager.pickup_range_mult + bonus)
	if is_equal_approx(_pickup_shape.radius, radius):
		return
	_pickup_shape.radius = radius

## 当前拾取半径：真话只有 PickupArea 那一圈碰撞形状。
## 满血待命的回复珠要问它（别抄常数），否则「圈内掉血自动飞来」会和热区不一致。
func pickup_radius() -> float:
	if pickup_area == null:
		var bonus := GameManager.still_pickup_bonus if (GameManager.still_time > 0.0) else 0.0
		return BASE_PICKUP_RADIUS * (GameManager.pickup_range_mult + bonus)
	var shape_node: Node = pickup_area.get_node_or_null("CollisionShape2D")
	if shape_node != null and shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius
	var bonus := GameManager.still_pickup_bonus if (GameManager.still_time > 0.0) else 0.0
	return BASE_PICKUP_RADIUS * (GameManager.pickup_range_mult + bonus)

func _on_leveled_up(_lvl: int) -> void:
	# 升级仪式两段式光柱（T-3.3）：汇聚聚灵→爆发拔起两段节奏，节点缺失时兜底单段 squash
	if level_ritual != null and level_ritual.has_method("play"):
		level_ritual.play()
	else:
		play_squash(Vector2(0.72, 1.38), 0.28)

# ---------------- 武器管理 ----------------

func add_weapon_instance(def_id: String, star: int) -> void:
	var weapon = floating_weapon_scene.instantiate() as FloatingWeapon
	weapon.setup(def_id, star)
	weapon_holder.add_child(weapon)
	_recalculate_weapon_slots()

func upgrade_weapon_instance(node: Node, new_star: int) -> void:
	if node == null or not is_instance_valid(node) or not (node is FloatingWeapon):
		return
	var w := node as FloatingWeapon
	w.setup(w.weapon_def_id, new_star)
	var tw := create_tween()
	tw.tween_property(w, "scale", Vector2(1.45, 1.45), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(w, "scale", Vector2.ONE, 0.14)

func remove_weapon_instance(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	equipped_cleanup()
	_recalculate_weapon_slots()

func equipped_cleanup() -> void:
	for i in range(weapon_holder.get_child_count() - 1, -1, -1):
		var child = weapon_holder.get_child(i)
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			weapon_holder.remove_child(child)
			child.free()

func get_weapon_count() -> int:
	equipped_cleanup()
	return weapon_holder.get_child_count()

func _recalculate_weapon_slots() -> void:
	var count = get_weapon_count()
	if count == 0:
		return
	for i in range(count):
		var w = weapon_holder.get_child(i) as FloatingWeapon
		w.base_angle = float(i) * (TAU / float(count))
		w.spread_angle = (float(i) - float(count - 1) * 0.5) * deg_to_rad(28.0)
		w.orbit_extents = FloatingWeapon.DEFAULT_ORBIT_EXTENTS

## 上阵两把悬浮武器互换位置（商店拖拽换位用）：环绕角度按次序重排，换位即换环绕方位；
## 灵宝（drones）的互换走 WeaponInventory.swap_equipped_slots，不经过这里
func reorder_weapons(i: int, j: int) -> void:
	equipped_cleanup()
	var count := weapon_holder.get_child_count()
	if i < 0 or j < 0 or i >= count or j >= count or i == j:
		return
	var ci := weapon_holder.get_child(i)
	var cj := weapon_holder.get_child(j)
	weapon_holder.move_child(ci, j)
	weapon_holder.move_child(cj, i)
	_recalculate_weapon_slots()

func get_equipped_weapons_data() -> Array[Dictionary]:
	equipped_cleanup()
	var list: Array[Dictionary] = []
	for w in weapon_holder.get_children():
		if not is_instance_valid(w):
			continue
		var def := WeaponData.get_def(w.weapon_def_id)
		list.append({
			"id": w.weapon_def_id,
			"name": def.get("name", "?"),
			"star": w.star,
			"tag": def.get("tag", ""),
			"icon": def.get("icon", ""),
			"node": w,
		})
	return list

func sync_drones() -> void:
	var target: Array = GameManager.drones
	# 期望具数 = 每条御灵按星级分身（★1=1 ★2=2 ★3=3，WeaponData.drone_orb_count）：
	# 升星补上「召唤物数量」成长轴，单武器总纸面伤害不变，贴身覆盖与占空比抬升
	var desired := 0
	for d_entry in target:
		desired += WeaponData.drone_orb_count(GameManager._drone_star(d_entry))
	var current_count = sun_orb_container.get_child_count()
	if current_count < desired:
		for i in range(desired - current_count):
			var orb = sun_orb_scene.instantiate()
			sun_orb_container.add_child(orb)
	elif current_count > desired:
		var to_remove = current_count - desired
		for i in range(to_remove):
			var last_idx = sun_orb_container.get_child_count() - 1
			var child = sun_orb_container.get_child(last_idx)
			sun_orb_container.remove_child(child)
			child.queue_free()
	# 逐条御灵下发星级/道具 id/分身具数；伤害均摊由 SunOrb.setup 自己结算
	var orb_idx := 0
	for d_entry in target:
		var d_id: String = GameManager._drone_id(d_entry)
		var d_star: int = GameManager._drone_star(d_entry)
		var orbs := WeaponData.drone_orb_count(d_star)
		for k in range(orbs):
			if orb_idx >= sun_orb_container.get_child_count():
				break
			var orb = sun_orb_container.get_child(orb_idx) as SunOrb
			if orb != null:
				orb.setup(d_star, d_id, orbs)
			orb_idx += 1

func heal(amount: float, quiet: bool = false) -> void:
	if amount <= 0.0:
		return
	var before := current_health
	current_health = minf(max_health, current_health + amount)
	# 只报真正回上来的那部分；顶满时一口没回，不发挤压/音效/+X（报了就是假账）
	var gained := current_health - before
	if gained <= 0.01:
		return
	# 满血吸血命中极频繁，信号必须过了 gained 闸再发，否则 HUD 每次命中都重建血条补间（2026-10-13 掉帧根因）
	GameManager.player_hp_changed.emit(current_health, max_health)
	GameManager.total_hp_healed += gained
	# 灵髓丹气：回复生命后触发短时增伤与加速
	var heal_dmg: float = GameManager.item_hook_sum("heal_buff_damage")
	if heal_dmg > 0.0:
		var dur: float = maxf(1.0, GameManager.item_hook_sum("heal_buff_dur"))
		GameManager.buff_damage_mult = 1.0 + heal_dmg
		GameManager.buff_move_speed_mult = 1.0 + GameManager.item_hook_sum("heal_buff_speed")
		_skill_buffs["heal_buff"] = dur
	if quiet:
		return
	play_squash(Vector2(0.88, 1.16), 0.18)
	AudioManager.play_sfx("heal", 0.9)
	DamageNumber.spawn(get_parent(), global_position, int(gained), false, "+" + str(int(gained)))

# ---------------- 随行技能 ----------------

## HUD 技能按钮入口。false = 没放出来（CD 中 / 效果活跃中 / 战斗外 / 无技能），调用方不发反馈
func try_activate_skill() -> bool:
	var sid := GameManager.active_skill_id
	if sid.is_empty() or GameManager.is_game_over or _dying or skill_cd_left > 0.0 or skill_active_left > 0.0:
		return false
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.phase) != int(WaveSpawner.Phase.FIGHT):
		return false
	var st := SkillData.final_stats(sid, GameManager.cultivator_id)
	if st.is_empty():
		return false
	# 冷却两段式：先开效果活跃窗口，窗口走完（_on_skill_effect_end）才进冷却；
	# 瞬发（治疗）窗口为 0，按下当帧直接进冷却
	_skill_pending_cd = float(st["cooldown"])
	_skill_active_kind = int(st["kind"])
	var active_dur := _skill_active_duration(st)
	if active_dur <= 0.0:
		_skill_active_kind = -1
		_begin_skill_cooldown()
	else:
		skill_active_total = active_dur
		skill_active_left = active_dur
	match int(st["kind"]):
		SkillData.Kind.DASH:
			_do_dash(st)
		SkillData.Kind.SPEED:
			_do_gale(st)
		SkillData.Kind.HASTE:
			_do_haste(st)
		SkillData.Kind.IFRAME:
			_do_aegis(st)
		SkillData.Kind.HEAL:
			_do_renewal(st)
	return true

## 效果活跃窗口时长（秒）：冲刺按无敌窗口，持续型按 duration，其余（瞬发）为 0
func _skill_active_duration(st: Dictionary) -> float:
	match int(st["kind"]):
		SkillData.Kind.DASH:
			return float(st.get("iframe", 0.0))
		SkillData.Kind.SPEED, SkillData.Kind.HASTE, SkillData.Kind.IFRAME:
			return float(st["duration"])
	return 0.0

func _begin_skill_cooldown() -> void:
	if _skill_pending_cd <= 0.0:
		skill_cd_total = 1.0
		skill_cd_left = 0.0
		return
	skill_cd_total = maxf(0.01, _skill_pending_cd)
	skill_cd_left = skill_cd_total

## 击杀或其他特质返还/预扣技能冷却（绝尘·斩灭凝神）
func refund_skill_cooldown(amount: float) -> void:
	if amount <= 0.0:
		return
	var refunded := false
	if skill_cd_left > 0.0:
		skill_cd_left = maxf(0.0, skill_cd_left - amount)
		refunded = true
	elif skill_active_left > 0.0:
		_skill_pending_cd = maxf(0.0, _skill_pending_cd - amount)
		refunded = true
	if refunded and skill_vfx != null:
		skill_vfx.on_cd_refunded()

## 效果活跃窗口走完：先做各类型收尾（回滚短时乘区），此刻才进冷却
func _on_skill_effect_end() -> void:
	skill_active_left = 0.0
	match _skill_active_kind:
		SkillData.Kind.IFRAME:
			GameManager.buff_knockback_mult = 1.0
	_skill_active_kind = -1
	_begin_skill_cooldown()

## HUD 额外技能按钮入口（随角色绑定，如影者的影爆、药王的药爆）。false = 没放出来（无技能/战斗外/CD中/资源没攒上），调用方发拒绝反馈。
## 免冷却类（BURST）由资源层门控，带冷却类（如药爆 HEAL）由 extra_skill_cd_left 门控。
func try_activate_extra_skill() -> bool:
	var sid := GameManager.extra_skill_id
	if sid.is_empty() or GameManager.is_game_over or _dying or extra_skill_cd_left > 0.0:
		return false
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.phase) != int(WaveSpawner.Phase.FIGHT):
		return false
	var st := SkillData.final_stats(sid, GameManager.cultivator_id)
	if st.is_empty():
		return false
	match int(st["kind"]):
		SkillData.Kind.HEAL:
			# 带冷却治疗/爆发类（药爆）：冷却门控，按下进 CD 并释放
			var cd := float(st.get("cooldown", 12.0))
			extra_skill_cd_total = maxf(0.01, cd)
			extra_skill_cd_left = extra_skill_cd_total
			play_squash(Vector2(1.18, 0.84), 0.18)
			if sid == "elixir":
				_release_elixir()
			return true
		SkillData.Kind.BURST:
			# 蓄能释放：没攒上按不动（按钮侧给抖动拒绝反馈），攒上随时能放、无 CD
			if not ShadowStepData.has_charge(shadow_ring):
				return false
			play_squash(Vector2(1.18, 0.84), 0.18)
			_release_shadow_step()
			return true
	return false

func _tick_skill_buffs(delta: float) -> void:
	_expired_buffs_buf.clear()
	for key in _skill_buffs:
		var left: float = float(_skill_buffs[key]) - delta
		_skill_buffs[key] = left
		if left <= 0.0:
			_expired_buffs_buf.append(key)
	if _expired_buffs_buf.is_empty():
		return
	for key in _expired_buffs_buf:
		_skill_buffs.erase(key)
		# 到期精确回滚：buff 乘区与加点/羁绊乘区隔离，回 1.0 即完全无残留
		match String(key):
			"gale":
				GameManager.buff_move_speed_mult = 1.0
				GameManager.buff_dodge = 0.0
				# 100% 闪避抬的那段上限一并还原到抬升前的角色档（90%）：只回 buff 不回上限，闪避率会
				# 停在 90%+ 而加成早已归零 ⇒ 面板读一个比实际高的数（铁律 6：渲染层只读状态）。
				# 按 cast 前快照还原而不是拿算式反推：角色抬升可能被 reset_run/换装中途改过，
				# 减去固定增量会把别人的账算到自己头上。
				if _gale_cap_forced:
					GameManager.dodge_cap_bonus = _gale_cap_before
					_gale_cap_forced = false
			"haste":
				GameManager.buff_attack_speed_mult = 1.0
			"elixir":
				GameManager.buff_damage_mult = 1.0
			"heal_buff":
				GameManager.buff_damage_mult = 1.0
				GameManager.buff_move_speed_mult = 1.0

## 无输入时按当前朝向给冲刺方向（facing + flip_h 还原 8 方向单位向量）
func _facing_vec() -> Vector2:
	var right := Vector2.LEFT if anim_sprite.flip_h else Vector2.RIGHT
	match facing:
		"n":
			return Vector2.UP
		"s":
			return Vector2.DOWN
		"e":
			return right
		"se":
			return (Vector2.DOWN + right).normalized()
		"ne":
			return (Vector2.UP + right).normalized()
	return Vector2.DOWN

func _do_dash(st: Dictionary) -> void:
	var dir: Vector2 = Vector2.ZERO
	if GameManager.joystick != null and GameManager.joystick.has_method("get_direction"):
		dir = GameManager.joystick.get_direction()
	if dir.length_squared() < 0.03:
		# 松手冲刺：沿当前惯性方向；站定则沿面朝方向
		dir = velocity.normalized() if velocity.length_squared() > 900.0 else _facing_vec()
	_dash_dir = dir.normalized()
	_dash_time = float(st["duration"])
	_dash_speed = float(st["distance"]) / maxf(0.05, _dash_time)
	# 无敌覆盖位移全程 + 落地脱身余量（时长唯一真话在 SkillData 的 iframe 字段），落点瞬间不吃贴脸伤害
	# 影层被动：每层再加一段无敌（影在身上时冲刺更稳）——影层兑现不在这里，影爆是独立技能
	invulnerable_time = maxf(invulnerable_time,
		float(st.get("iframe", _dash_time + 0.04)) + ShadowStepData.iframe_bonus(shadow_ring))
	# 冲刺攻势：起跳即开必暴窗口（roll_crit 消费，覆盖冲刺与落地追击的两拍输出）
	GameManager.force_crit_left = maxf(GameManager.force_crit_left, float(st.get("crit_window", 0.0)))
	play_squash(Vector2(1.3, 0.72), 0.2)
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 14), _dash_dir * _dash_speed)
	if skill_vfx != null:
		skill_vfx.on_dash_start(_dash_dir, float(st["distance"]), _dash_time, float(st.get("crit_window", 1.0)))
	if is_procedural and procedural_view != null:
		procedural_view.play_dash(_dash_time)
	AudioManager.play_sfx("skill_dash", 1.0)

## 影爆（额外技能）：把影层里存的「刚才躲掉的那几刀」按比例折成一次周身影袭还回去，同时推开一圈怪。
## 环特效半径传的就是判定半径本身（画多大 == 判多大）；镜头只给一档轻 zoom punch（低频主动技），
## 不加震屏/顿帧——同帧叠满屏乱晃的历史教训不变。
func _release_shadow_step() -> void:
	if not ShadowStepData.has_charge(shadow_ring):
		return
	var dmg := ShadowStepData.burst_damage(shadow_ring, GameManager.wave_number)
	var impulse: float = ShadowStepData.push_impulse(shadow_ring) * GameManager.knockback_mult
	# 过滤口径统一走 EnemyFilter（藏宝匣/灵草/垂死一律不算敌人）
	for e in EnemyFilter.collect(get_tree(), global_position, ShadowStepData.BURST_RADIUS):
		var off: Vector2 = e.global_position - global_position
		var dir := off.normalized() if off.length_squared() > 0.0001 else _dash_dir
		e.take_damage(dmg, dir * impulse)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, ShadowStepData.BURST_RADIUS,
		GameStyle.SHADOW, ShadowStepData.BURST_RING_DURATION)
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position + Vector2(0, -10), "shadow", 1.2, true)
	AudioManager.play_sfx("whoosh_heavy", 1.0, 0.82)
	AudioManager.play_sfx("whoosh_heavy", 0.7, 0.62)  ## 降调低频层：影爆踩碎的「闷响」
	GameFeel.zoom_punch(GameManager, ShadowStepData.BURST_ZOOM_PUNCH, 0.2)
	shadow_ring = []
	GameManager.shadow_amp_mult = 1.0
	if skill_vfx != null:
		skill_vfx.on_shadow_spent()

## 盾势爆发（守卫·全自动）：把槽里蓄的「被护甲挡下的伤害」按比例折成一次周身震荡还回去并震开。
## 与影爆同一把尺子：环特效半径传的就是判定半径；镜头只给一档轻 zoom punch（低频爆发技），不加震屏。
## 唯一触发点是 take_damage 蓄满当帧（攒/放同一写点），槽先清零再结算，爆发期间挨的刀计入下一槽。
func _release_guard_stance() -> void:
	var charge := GameManager.shield_charge
	GameManager.shield_charge = 0.0
	if skill_vfx != null:
		skill_vfx.on_guard_burst()
	var dmg := GuardStanceData.burst_damage(charge)
	var impulse: float = GuardStanceData.PUSH_IMPULSE * GameManager.knockback_mult
	# 过滤口径统一走 EnemyFilter（藏宝匣/灵草/垂死一律不算敌人）
	for e in EnemyFilter.collect(get_tree(), global_position, GuardStanceData.BURST_RADIUS):
		var off: Vector2 = e.global_position - global_position
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, GuardStanceData.BURST_RADIUS,
		GameStyle.AURUM, GuardStanceData.BURST_RING_DURATION)
	GameFeel.zoom_punch(GameManager, GuardStanceData.BURST_ZOOM_PUNCH, 0.18)
	AudioManager.play_sfx("whoosh_heavy", 0.9, 0.72)

## 天雷（雷法真君·全自动）：引雷劈向索敌圈内最近的敌人，落点小范围震荡。
## 与盾势同一把尺子：环特效半径传的就是判定半径；不加震屏——落雷由环、跳字与击退本身表达。
## 伤害只随元素伤害成长（ThunderData.bolt_damage）× 短时增益乘区——不吃武器 tag 乘区，
## 它是道统技能不是武器；返回 false = 索敌圈内无怪（调用方走短间隔重试，不空耗整轮冷却）。
func _call_thunder() -> bool:
	# 索敌：过滤口径统一走 EnemyFilter，取 SEEK_RANGE 内最近的一只
	var best := EnemyFilter.nearest(get_tree(), global_position, ThunderData.SEEK_RANGE)
	if best == null:
		return false
	var strike_pos: Vector2 = best.global_position
	var dmg: float = ThunderData.bolt_damage(GameManager.elemental_damage) * GameManager.buff_damage_mult
	var impulse: float = ThunderData.PUSH_IMPULSE * GameManager.knockback_mult
	for e in EnemyFilter.collect(get_tree(), strike_pos, ThunderData.RADIUS):
		var off: Vector2 = e.global_position - strike_pos
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)
	JuiceEffect.spawn_shockwave(get_parent(), strike_pos, ThunderData.RADIUS,
		GameStyle.GOLD_EDGE, 0.3)
	# 天雷演出：天降神雷折线电弧穿云而落（与落点冲击环结合）
	var bolt_parent: Node = get_parent() if get_parent() != null else (get_tree().current_scene if get_tree() != null else self)
	if bolt_parent != null:
		var bolt := LightningBolt.acquire(bolt_parent)
		var sky_x_offset: float = GameManager.rng.randf_range(-24.0, 24.0) if GameManager.rng != null else 0.0
		var sky_pos := strike_pos + Vector2(sky_x_offset, -260.0)
		bolt.activate(sky_pos, strike_pos, GameStyle.GOLD_EDGE, 1.35)
	if skill_vfx != null:
		skill_vfx.on_thunder_cast()
	play_squash(Vector2(1.08, 0.92), 0.12)
	AudioManager.play_sfx("thunder_strike", 0.9, 1.0)
	return true

## 药爆（药王·额外技能）：摔碎药罐——自身回复一截生命（ElixirData.HEAL_HP_RATIO），
## 药力向周身炸开对敌人造成一次性毒伤（不挂 DoT）并推开，随附短时增伤反打窗口。
func _release_elixir() -> void:
	# 1. 自身回血（小治疗，直接按当前最大生命比例回复）
	var heal_val := ElixirData.heal_amount(max_health)
	heal(heal_val)

	# 2. 周身一次性毒雾伤害（走毒系口径：随元素伤害成长 × 短时增益乘区）
	var dmg := ElixirData.burst_damage(GameManager.elemental_damage) * GameManager.buff_damage_mult
	var impulse := ElixirData.PUSH_IMPULSE * GameManager.knockback_mult
	for e in EnemyFilter.collect(get_tree(), global_position, ElixirData.BURST_RADIUS):
		var off: Vector2 = e.global_position - global_position
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)

	# 3. 药力反打短时增伤（ElixirData 数值）
	GameManager.buff_damage_mult = ElixirData.buff_mult()
	_skill_buffs["elixir"] = ElixirData.BUFF_DURATION

	# 4. 视觉与音效：冲击环（画多大==判多大，GOOD 翠绿药雾色）+ 地面药圃残辉 + 随行药爆药雾粒子
	JuiceEffect.spawn_shockwave(get_parent(), global_position, ElixirData.BURST_RADIUS,
		GameStyle.GOOD, ElixirData.BURST_RING_DURATION)
	# 地面药圃残辉：毒伤范围贴地留痕（半径 = 判定半径），让按下的那一圈在地上留一拍
	var residue := GroundDecal.spawn_tinted(get_parent(), global_position, ElixirData.BURST_RADIUS, GameStyle.GOOD)
	if residue != null:
		residue._time_left = ElixirData.GROUND_RESIDUE_SEC
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, global_position + Vector2(0, 4), "heal", 1.1, true)
	GameFeel.zoom_punch(GameManager, ElixirData.BURST_ZOOM_PUNCH, 0.2)
	if skill_vfx != null:
		skill_vfx.on_elixir_cast()
	if is_procedural and procedural_view != null:
		procedural_view.set_skill_visual("renewal", true, 1.0)
	AudioManager.play_sfx("skill_heal", 1.05, 1.1)
	AudioManager.play_sfx("whoosh_heavy", 0.85, 1.25)

func _do_gale(st: Dictionary) -> void:
	GameManager.buff_move_speed_mult = 1.0 + float(st["power"])
	# 罡风护身：加速期间身法闪避大幅提升（到期与移速乘区同帧精确归零）
	var dodge_add: float = float(st.get("dodge_add", 0.0))
	GameManager.buff_dodge = dodge_add
	# 100% 闪避（影者契合）：角色抬升只到 90% 的硬上限会把它截成 90% ⇒ 期间把上限临时
	# 抬到 1.0，buff 走完由 _tick_skill_buffs 按抬升前的原值精确还原（与 buff_dodge 同帧，不留残留）
	const FULL_DODGE_EPS := 0.0001
	_gale_cap_forced = dodge_add >= 1.0 - FULL_DODGE_EPS
	if _gale_cap_forced:
		_gale_cap_before = GameManager.dodge_cap_bonus
		GameManager.dodge_cap_bonus = maxf(GameManager.dodge_cap_bonus, 1.0 - GameManager.DODGE_CAP)
	_skill_buffs["gale"] = float(st["duration"])
	play_squash(Vector2(0.85, 1.2), 0.2)
	if skill_vfx != null:
		skill_vfx.on_gale_start(float(st["duration"]))
	AudioManager.play_sfx("skill_buff", 1.0)

func _do_haste(st: Dictionary) -> void:
	GameManager.buff_attack_speed_mult = maxf(GameManager.ATTACK_SPEED_FLOOR, 1.0 - float(st["power"]))
	_skill_buffs["haste"] = float(st["duration"])
	play_squash(Vector2(1.12, 0.9), 0.18)
	if skill_vfx != null:
		skill_vfx.on_haste_start(float(st["duration"]))
	AudioManager.play_sfx("skill_buff", 1.1)

func _do_aegis(st: Dictionary) -> void:
	var dur: float = float(st["duration"])
	invulnerable_time = maxf(invulnerable_time, dur)
	# 金光罡风：无敌期间武器击退力度大幅提升（活跃窗口走完由 _on_skill_effect_end 回 1.0）
	GameManager.buff_knockback_mult = float(st.get("knockback_boost", 1.0))
	play_squash(Vector2(0.82, 1.22), 0.24)
	if skill_vfx != null:
		skill_vfx.on_aegis_start(dur)
	AudioManager.play_sfx("skill_aegis", 1.0)

func _do_renewal(st: Dictionary) -> void:
	heal(max_health * float(st["power"]), true)
	play_squash(Vector2(0.88, 1.16), 0.18)
	DamageNumber.spawn(get_parent(), global_position, int(max_health * float(st["power"])), false, "+" + str(int(max_health * float(st["power"]))) + " HP")
	_summon_spirit_healer(st)
	if skill_vfx != null:
		skill_vfx.on_renewal_cast()
	AudioManager.play_sfx("skill_heal", 1.0)
	AudioManager.play_sfx("heal", 0.65, 1.15)  ## 回血确认音（heal 走了 quiet 通道吞掉原音，这里低声叠回）

## 治疗灵兽：治疗技能附带召唤（SkillData renewal 的 pet_* 字段），跟随玩家周期回血；重施按组替换旧灵
func _summon_spirit_healer(st: Dictionary) -> void:
	var pet_pct := float(st.get("pet_heal_pct", 0.0))
	var pet_life := float(st.get("pet_duration", 0.0))
	if pet_pct <= 0.0 or pet_life <= 0.0:
		return
	var old := get_tree().get_first_node_in_group("spirit_healers")
	if old != null:
		# 先出组再销毁：queue_free 要到帧末才真正释放，同帧重施必须立刻能拿到新灵
		old.remove_from_group("spirit_healers")
		old.queue_free()
	var pet := SPIRIT_HEALER_SCENE.instantiate() as SpiritHealer
	if pet == null:
		return
	pet.heal_pct = pet_pct
	pet.lifetime = pet_life
	pet.target = self
	get_parent().add_child(pet)
	pet.global_position = global_position + Vector2(0, -SpiritHealer.HEIGHT_OFFSET)

# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	# 阵亡或通关谢幕期：不再推进移动/技能，只剩演出 tween 在跑
	if _dying or _victorious:
		return

	# 技能冷却两段式：先走效果活跃窗口（归零即收尾+进冷却），再走冷却与短时增益倒计时
	# （与加点乘区隔离，到期精确回滚）
	if skill_active_left > 0.0:
		skill_active_left -= delta
		if skill_active_left <= 0.0:
			_on_skill_effect_end()
	if skill_cd_left > 0.0:
		skill_cd_left -= delta
	if extra_skill_cd_left > 0.0:
		extra_skill_cd_left -= delta
	if not _skill_buffs.is_empty():
		_tick_skill_buffs(delta)
	if GameManager.force_crit_left > 0.0:
		GameManager.force_crit_left -= delta

	# 雷法真君·天雷：周期落雷（有怪才落，落完按 ThunderData.INTERVAL 重计；无怪短间隔重试）
	if GameManager.thunder_strike > 0.0:
		_thunder_cd -= delta
		if _thunder_cd <= 0.0:
			_thunder_cd = ThunderData.INTERVAL if _call_thunder() else ThunderData.RETRY_INTERVAL

	# 受击无敌帧倒计时与频闪反馈
	if invulnerable_time > 0.0:
		invulnerable_time -= delta
		# 金光护体期间图集角色泛金光高亮，程序化角色由矢量渲染器精细驱动局部流光与高光
		var is_aegis := skill_vfx != null and skill_vfx.aegis_active
		var sprite_mod := Color(1.3, 1.25, 0.85, 0.95) if is_aegis else Color(1, 1, 1, 0.55 if fmod(invulnerable_time, 0.12) > 0.06 else 1.0)
		anim_sprite.modulate = sprite_mod
		if is_procedural and procedural_view != null:
			# 程序化角色在金光护体期间保持清晰白底（由眼睛/斗篷/道印高精流光点亮），普通受击时正常频闪提示
			var proc_mod := Color.WHITE if is_aegis else Color(1, 1, 1, 0.55 if fmod(invulnerable_time, 0.12) > 0.06 else 1.0)
			procedural_view.modulate = proc_mod
	else:
		anim_sprite.modulate = Color.WHITE
		if is_procedural and procedural_view != null:
			procedural_view.modulate = Color.WHITE

	# 受击闪白衰减：顶点色通道（self_modulate 承载，2026-10-17 与 EnemyBase 同口径改造，
	# 材质共享零 uniform；modulate 仍归无敌帧频闪/护体金光业务，COLOR 相乘叠加互不覆盖）
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
		_write_flash_channel(clampf(_flash_t / PLAYER_FLASH_DOWN_DUR, 0.0, 1.0))

	# 定向受击反馈衰减（与敌人 _tick_hit_visuals 同速率）：后仰 14/s 回正、微反冲 24px/s 归零。
	# 放在移动分支之前：rotation 的 lerp 目标在下方行走/待机分支消费 _hit_tilt，必须先衰减再合成
	if _hit_tilt != 0.0:
		_hit_tilt = lerpf(_hit_tilt, 0.0, minf(delta * 14.0, 1.0))
		if absf(_hit_tilt) < 0.001:
			_hit_tilt = 0.0
	if _hit_jiggle_offset != Vector2.ZERO:
		_hit_jiggle_offset = _hit_jiggle_offset.move_toward(Vector2.ZERO, delta * 24.0)
		anim_sprite.position = _hit_jiggle_offset
		if is_procedural and procedural_view != null:
			procedural_view.position = _hit_jiggle_offset

	# 灵愈心法 + 青木羁绊：持续回血（软顶折算与面板读数同源，BalanceCombat 唯一算式）
	var total_regen := BalanceCombat.effective_hp_regen(GameManager.hp_regen + GameManager.synergy_hp_regen)
	if total_regen > 0.0 and current_health < max_health:
		var before_regen := current_health
		current_health = minf(max_health, current_health + total_regen * delta)
		var regen_gained := current_health - before_regen
		GameManager.total_hp_healed += maxf(0.0, regen_gained)
		regen_tick += delta
	if regen_tick >= 0.5:
		regen_tick = 0.0
		GameManager.player_hp_changed.emit(current_health, max_health)

	# 1. 移动输入与高响应加减速平滑
	var dir: Vector2 = Vector2.ZERO
	var joy = GameManager.joystick
	if joy != null:
		if not _joy_get_dir_checked:
			_joy_get_dir_checked = true
			_joy_get_dir_ok = joy.has_method("get_direction")
		if _joy_get_dir_ok:
			dir = joy.get_direction()
		else:
			dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	else:
		dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	var target_speed := base_speed * (GameManager.move_speed_mult + GameManager.synergy_move_speed_mult) * GameManager.buff_move_speed_mult
	var target_velocity := dir * target_speed
	# 冲刺接管移动：不吃加减速插值，匀速直射，途中刀枪不入（无敌在 _do_dash 里已给）
	if _dash_time > 0.0:
		_dash_time -= delta
		target_velocity = _dash_dir * _dash_speed
		velocity = target_velocity
		if _dash_time <= 0.0:
			# 落地即收速：不收回的话最后一帧的速度还是 distance/duration 的峰值
			# （旧写法 260/0.16 = 1625 px/s），之后要 0.6~0.8s 才掉回常速 ⇒ 纸面 260 实际冲出去 830+
			# （约 1.5 个屏高）。收速后位移与数据表同源，只留一点前冲余量。
			velocity = _dash_dir * minf(velocity.length(), target_speed * DASH_LANDING_SPEED_MUL)
			target_velocity = dir * target_speed
	var input_moving := dir.length_squared() > 0.03
	var actual_speed_sq := velocity.length_squared()
	# 松手减速到目标速度的 35% 以下立即切待机：否则腿在原地踏步而身体还在滑行（悬浮感来源）
	var stop_threshold := maxf(30.0, target_speed * 0.35)
	var is_moving := input_moving or actual_speed_sq > stop_threshold * stop_threshold
	var accel := 2200.0 if input_moving else 2800.0
	velocity = velocity.move_toward(target_velocity, accel * delta)
	move_and_slide()

	# 站定/入定流账本：打坐蒲团、入定香、玄武法坛、不动明王印、磐石印、金刚神像或苦行僧在场才计时；脚底一动立刻清零
	if GameManager.has_still_mechanic():
		var was_still := GameManager.still_time > 0.0
		GameManager.player_is_moving = is_moving
		GameManager.still_time = 0.0 if is_moving else GameManager.still_time + delta
		var is_now_still := GameManager.still_time > 0.0
		if was_still != is_now_still and GameManager.still_pickup_bonus > 0.0:
			_sync_pickup_radius()
		if not is_moving:
			var regen_pct: float = GameManager.item_hook_sum("still_regen_pct")
			if regen_pct > 0.0 and current_health < max_health:
				heal(max_health * regen_pct * delta, true)
	else:
		GameManager.player_is_moving = is_moving

	# 蛮兵·陷阵：节流数感知圈内的敌人（crowd_damage_radius = 0 时整块零开销）
	if GameManager.crowd_damage_radius > 0.0:
		_crowd_tick -= delta
		if _crowd_tick <= 0.0:
			_crowd_tick = 0.2
			GameManager.nearby_enemy_count = EnemyFilter.count_in_range(
				get_tree(), global_position, GameManager.crowd_damage_radius)

	# 灵田界碑边界
	var lim: float = GameManager.MAP_HALF_EXTENT - 26.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 2. 奔跑步伐微尘：已在步相推进点（下方 procedural 分支）随「脚落地帧」同步放尘，
	# 与身体垂直弹跳/影子脉冲三者同源 gait_phase_counter，不再用独立定时器错拍

	# 3. Sprite 方向 & 动画（带迟滞滤波 + 移速步频自适应 + 统一形变插值流）
	var current_base := anim_base_scale * juice_scale
	var current_speed := velocity.length()
	var speed_ratio: float = (current_speed / target_speed) if target_speed > 0.0 else 1.0

	if is_moving:
		# 使用带迟滞区间的 8 方向平滑算法，彻底消除摇杆临界角度导致的快速抽搐
		var effective_dir := dir if input_moving else velocity.normalized()
		var face: Array = RunMotion.facing_stable(effective_dir, facing, anim_sprite.flip_h, 29.0)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

		if is_procedural and procedural_view != null:
			gait_phase_counter += delta * 2.4 * clampf(speed_ratio, 0.7, 1.4)
			# 步伐微尘与步相同拍（2026-10-14 P1）：一个步循环 0→1 跨两步，半循环过零点
			# 即「脚落地帧」——身体垂直弹跳、影子脉冲、脚下尘三者同源不再错拍；
			# 移速越快步频越快，放尘密度随之自适应（旧 0.22s 定时器删）
			if gait_phase_counter >= 0.5:
				gait_phase_counter -= 0.5
				JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 14), velocity)
			# 土豆兄弟式步态弹性（Squash & Stretch）：垂直弹跳与横向挤压形变
			var bounce_amp := 0.065 * clampf(speed_ratio, 0.6, 1.25)
			var hover_bob := sin(gait_phase_counter * TAU) * bounce_amp
			procedural_view.scale = current_base * 1.5 * Vector2(1.0 - hover_bob * 0.7, 1.0 + hover_bob)
			procedural_view.set_facing_dir(facing, anim_sprite.flip_h)
			# 土豆兄弟式御风灵动侧倾：水平移速驱动 4.8° 弹性倾角，转向灵动自然
			# 受击后仰（_hit_tilt）作为加性项并入 lerp 目标，随上方衰减自然回正，不与行走侧倾抢写
			var target_bank := deg_to_rad(4.8) * clampf(effective_dir.x, -1.0, 1.0) * clampf(speed_ratio, 0.0, 1.2)
			procedural_view.rotation = lerp_angle(procedural_view.rotation, target_bank + _hit_tilt, minf(delta * 14.0, 1.0))
			procedural_view.play_run(gait_phase_counter, sin(gait_phase_counter * TAU), speed_ratio, target_bank)
		elif _motion_mode == "hover":
			# 御剑悬浮：不切腿帧（图集各列同一姿势），浮沉/前倾由程序驱动
			RunMotion.select_anim(anim_sprite, _anim_idle, false)
			RunMotion.apply_hover(_run_state, anim_sprite, current_base, true, effective_dir, delta, speed_ratio, shadow_sprite)
		else:
			RunMotion.select_anim(anim_sprite, _anim_run, true)

			var lean_axis: float = absf(effective_dir.x)
			RunMotion.apply(_run_state, anim_sprite, current_base, true, anim_sprite.flip_h, lean_axis, delta, speed_ratio, 0.0, shadow_sprite)
	else:
		if is_procedural and procedural_view != null:
			procedural_view.scale = current_base * 1.5
			procedural_view.rotation = lerp_angle(procedural_view.rotation, _hit_tilt, minf(delta * 10.0, 1.0))
			procedural_view.set_facing_dir(facing, anim_sprite.flip_h)
			procedural_view.play_idle()
		elif _motion_mode == "hover":
			RunMotion.select_anim(anim_sprite, _anim_idle, false)
			RunMotion.apply_hover(_run_state, anim_sprite, current_base, false, Vector2.ZERO, delta, 1.0, shadow_sprite)
		else:
			RunMotion.select_anim(anim_sprite, _anim_idle, false)
			idle_bob_phase += delta * 2.2
			RunMotion.apply(_run_state, anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta, 1.0, idle_bob_phase, shadow_sprite)

	# 4. 攻击本体联动 + 灵蝶环绕运算
	_tick_attack_react()
	_process_sun_orbs(delta)

	# 5. 随行技能角色身上动效更新
	if skill_vfx != null:
		if GameManager.frenzy_enabled > 0.0:
			skill_vfx.sync_frenzy(GameManager.frenzy_stacks, FrenzyData.MAX_STACKS)
		skill_vfx.update_vfx(delta, is_moving, velocity)

	# 6. 统一调度各武器索敌目标（多向分流 + 贴身危急集火 + 动态扇形展开）
	# 10Hz 节流 + 错相（2026-10-10 第 6 波卡顿优化）：敌人位置连续，索敌无需逐帧
	# intersect_shape；新目标入射程最多延迟 100ms 锁定，肉眼无感
	_search_phase -= delta
	if _search_phase <= 0.0:
		_search_phase = TARGET_SEARCH_INTERVAL
		_update_weapon_targets()

func _sort_candidate_by_dist(a: Node2D, b: Node2D) -> bool:
	var a_on := GameBalance.is_in_viewport(a.global_position, global_position)
	var b_on := GameBalance.is_in_viewport(b.global_position, global_position)
	if a_on != b_on:
		return a_on
	var da := GameBalance.elliptical_distance(a.global_position - global_position)
	var db := GameBalance.elliptical_distance(b.global_position - global_position)
	return da < db

func _acquire_pooled_dict(pool: Array[Dictionary], idx: int) -> Dictionary:
	while pool.size() <= idx:
		pool.append({})
	return pool[idx]

## 索敌节流（2026-10-10 第 6 波卡顿优化）：10Hz + instance_id 错相
const TARGET_SEARCH_INTERVAL := 0.1
var _search_phase: float = 0.0

func _update_weapon_targets() -> void:
	equipped_cleanup()
	var count = weapon_holder.get_child_count()
	if count == 0:
		return

	_weapons_buf.clear()
	var max_range: float = 0.0
	for i in range(count):
		var w = weapon_holder.get_child(i) as FloatingWeapon
		if w != null and is_instance_valid(w):
			_weapons_buf.append(w)
			var w_range = w.attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
			if w_range > max_range:
				max_range = w_range

	if _weapons_buf.is_empty() or max_range <= 0.0:
		return

	var space_state = get_world_2d().direct_space_state
	if _target_shape == null or _target_query == null:
		_target_shape = CircleShape2D.new()
		_target_query = PhysicsShapeQueryParameters2D.new()
		_target_query.shape = _target_shape
		_target_query.collision_mask = 4
		_target_query.collide_with_areas = true
		query_alloc_count += 1
	else:
		query_reuse_count += 1
	_target_shape.radius = max_range
	_target_query.transform = Transform2D(0.0, global_position)
	var results = space_state.intersect_shape(_target_query, 32)

	_candidate_enemies_buf.clear()
	_candidate_chests_buf.clear()
	_seen_ids_buf.clear()
	for res in results:
		var col = res.get("collider")
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent as Node2D
			if not is_instance_valid(enemy):
				continue
			var is_chest := enemy.is_in_group("chests")
			# 匣子与妖怪共用 4 号层，同一圈查询两个都捞得到；匣子另册登记，只接闲着的武器
			if is_chest and not _candidate_chests_buf.has(enemy):
				_candidate_chests_buf.append(enemy)
				continue
			if enemy.is_in_group("herbs"):
				continue
			var eid := enemy.get_instance_id()
			if _seen_ids_buf.has(eid):
				continue
			_seen_ids_buf[eid] = true
			_candidate_enemies_buf.append(enemy)

	# 按距玩家从近到远排序，保证贴身危急判定与同向优先级稳定（命名方法避免每帧生成闭包）
	_candidate_enemies_buf.sort_custom(_sort_candidate_by_dist)
	_candidate_chests_buf.sort_custom(_sort_candidate_by_dist)

	_weapons_info_buf.clear()
	for i in range(_weapons_buf.size()):
		var w := _weapons_buf[i]
		var prev_id := 0
		if w.current_target != null and is_instance_valid(w.current_target):
			prev_id = w.current_target.get_instance_id()
		var w_range := w.attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult
		var wd := _acquire_pooled_dict(_weapons_dict_pool, i)
		wd["base_angle"] = w.base_angle
		wd["range"] = w_range
		wd["prev_id"] = prev_id
		_weapons_info_buf.append(wd)

	_enemies_info_buf.clear()
	for i in range(_candidate_enemies_buf.size()):
		var e := _candidate_enemies_buf[i]
		var offset := e.global_position - global_position
		var ed := _acquire_pooled_dict(_enemies_dict_pool, i)
		ed["id"] = e.get_instance_id()
		ed["dist"] = GameBalance.elliptical_distance(offset)
		ed["angle"] = offset.angle()
		ed["on_screen"] = GameBalance.is_in_viewport(e.global_position, global_position)
		_enemies_info_buf.append(ed)

	_chests_info_buf.clear()
	for i in range(_candidate_chests_buf.size()):
		var c := _candidate_chests_buf[i]
		var offset := c.global_position - global_position
		var cd := _acquire_pooled_dict(_chests_dict_pool, i)
		cd["id"] = c.get_instance_id()
		cd["dist"] = GameBalance.elliptical_distance(offset)
		cd["angle"] = offset.angle()
		cd["on_screen"] = GameBalance.is_in_viewport(c.global_position, global_position)
		_chests_info_buf.append(cd)

	# 两段式：妖怪先分完，剩下无事可做的武器才去砸匣子（见 GameBalance.assign_targets_with_chests）
	var assignments: Array = GameBalance.assign_targets_with_chests(_weapons_info_buf, _enemies_info_buf, _chests_info_buf)
	_candidate_targets_buf.clear()
	_candidate_targets_buf.append_array(_candidate_enemies_buf)
	_candidate_targets_buf.append_array(_candidate_chests_buf)

	# 按实际共享同一目标的武器分组计算扇形错开角：独自迎敌时不偏移，共享目标时扇形展开
	_target_groups_buf.clear()
	for i in range(_weapons_buf.size()):
		var t_idx := int(assignments[i])
		if t_idx >= 0:
			if not _target_groups_buf.has(t_idx):
				_target_groups_buf[t_idx] = []
			_target_groups_buf[t_idx].append(i)

	for i in range(_weapons_buf.size()):
		var w := _weapons_buf[i]
		var t_idx := int(assignments[i])
		if t_idx >= 0 and t_idx < _candidate_targets_buf.size():
			var group: Array = _target_groups_buf[t_idx]
			var group_size := group.size()
			var pos_in_group := group.find(i)
			w.spread_angle = (float(pos_in_group) - float(group_size - 1) * 0.5) * deg_to_rad(24.0)
			if not w.is_attacking:
				w.current_target = _candidate_targets_buf[t_idx]
		else:
			w.spread_angle = 0.0
			if not w.is_attacking:
				w.current_target = null

## 攻击本体联动（2026-10-14）：开火全由 FloatingWeapon 完成，本体原先完全静止，像「武器自己在打」。
## 武器文件在并行协作热区不动它：这里每物理帧轮询各武器 is_attacking 边沿（0→1 即开火帧），
## 朝开火武器的瞄准方向给本体直接叠一记 3.5° 侧倾；跑步/待机分支每帧的 lerp 回正
## （target_bank / 0.0）就是天然衰减通道，脉冲叠加一次即被缓慢拉回，无需自管状态。
const ATTACK_REACT_BANK := deg_to_rad(3.5)   ## 开火脉冲侧倾角
var _weapons_attacking_buf: Array[bool] = [] ## 上一帧各武器 is_attacking 快照（边沿检测）
## 灵珠子节点缓存（count 变化时重建，避免每帧 get_child 轮询）
var _orbs_buf: Array[SunOrb] = []
var _orbs_buf_count: int = -1

func _tick_attack_react() -> void:
	if not is_procedural or procedural_view == null:
		return
	# 复用 _update_weapon_targets（10Hz）填充的 _weapons_buf，避免每帧 get_child_count + get_child 轮询
	var count := _weapons_buf.size()
	if count == 0:
		return
	_weapons_attacking_buf.resize(count)
	for i in range(count):
		var w := _weapons_buf[i]
		if w == null or not is_instance_valid(w):
			_weapons_attacking_buf[i] = false
			continue
		var now_attacking: bool = w.is_attacking
		if now_attacking and not _weapons_attacking_buf[i]:
			# 开火边沿：武器本体 rotation == 真实瞄准方向（FloatingWeapon 侧铁律），
			# 水平分量定左右侧倾；垂直开火不倾斜（正面朝相机下看不出意义，免得乱晃）
			var aim_x := cos(w.rotation)
			if absf(aim_x) > 0.2:
				procedural_view.rotation += ATTACK_REACT_BANK * signf(aim_x)
		_weapons_attacking_buf[i] = now_attacking

func _process_sun_orbs(delta: float) -> void:
	var count := sun_orb_container.get_child_count()
	if count == 0:
		return
	# count 变化时重建灵珠缓存，避免每帧两次 get_child 轮询
	if count != _orbs_buf_count:
		_orbs_buf_count = count
		_orbs_buf.clear()
		_orbs_buf.resize(count)
		for i in range(count):
			_orbs_buf[i] = sun_orb_container.get_child(i) as SunOrb

	var range_mult: float = GameManager.attack_range_mult * GameManager.synergy_range_mult
	var base_radius: float = SunOrb.ORBIT_RADIUS * range_mult
	var min_radius: float = SunOrb.MIN_ORBIT_RADIUS
	var max_reach: float = 175.0
	var max_star: int = 1
	for i in range(count):
		var orb_child := _orbs_buf[i]
		if orb_child != null:
			if orb_child.max_orbit_reach > max_reach:
				max_reach = orb_child.max_orbit_reach
			if orb_child.star > max_star:
				max_star = orb_child.star
	var eff_max_reach: float = max_reach * range_mult

	# 扫描御灵感知圈内的敌人（复用查询与字典缓冲）：10Hz 快照（2026-10-11 第 6 波卡顿优化）
	_orb_scan_phase -= delta
	if _orb_scan_phase <= 0.0:
		_orb_scan_phase = ORB_SCAN_INTERVAL
		_scan_orb_enemies(eff_max_reach)

	_orb_angles_buf.clear()
	for i in range(count):
		_orb_angles_buf.append(wrapf(sun_orb_angle + float(i) * (TAU / float(count)), -PI, PI))

	var orbit_res: Dictionary = GameBalance.compute_spirit_orbit(
		_orb_angles_buf, _orb_enemies_buf, base_radius, min_radius, eff_max_reach
	)
	var in_combat: bool = bool(orbit_res.get("in_combat", false))
	var target_radii: Array = orbit_res.get("radii", [])

	var angular_speed: float = GameBalance.spirit_orbit_angular_speed(
		GameBalance.SPIRIT_BASE_ANGULAR_SPEED,
		GameManager.attack_speed_mult,
		GameManager.synergy_haste_mult,
		in_combat,
		max_star,
		count
	) * (1.0 + GameManager.item_hook_sum("drone_spin_speed"))
	sun_orb_angle += delta * angular_speed

	for i in range(count):
		var orb := _orbs_buf[i]
		if orb == null:
			continue
		var a: float = sun_orb_angle + float(i) * (TAU / float(count))
		var tgt_r: float = float(target_radii[i]) if i < target_radii.size() else base_radius
		orb.current_radius = lerpf(orb.current_radius, tgt_r, minf(delta * 12.0, 1.0))
		orb.position = Vector2(cos(a), sin(a)) * orb.current_radius
		# 随切线横向分量的轻微侧倾（既灵动又不倒立）
		orb.rotation = clampf(-sin(a) * 0.25, -0.30, 0.30)

## 御灵扫描节流（2026-10-11 第 6 波卡顿优化）：物理查询 10Hz 快照，轨道公式与位置插值
## 仍逐帧跑（吃快照）；与武器索敌同款待遇 —— 敌人入圈最多延迟 100ms 被扑击，肉眼无感
const ORB_SCAN_INTERVAL := 0.1
var _orb_scan_phase: float = 0.05   ## 初相偏移：与武器索敌的 10Hz 错开，避免同帧叠加物理查询

## 御灵感知圈敌人快照（原 _process_sun_orbs 每帧段原样搬移，唯一变化是改由节流器调用）
func _scan_orb_enemies(eff_max_reach: float) -> void:
	_orb_enemies_buf.clear()
	var space_state := get_world_2d().direct_space_state
	if space_state != null:
		if _orb_shape == null or _orb_query == null:
			_orb_shape = CircleShape2D.new()
			_orb_query = PhysicsShapeQueryParameters2D.new()
			_orb_query.shape = _orb_shape
			_orb_query.collision_mask = 4
			_orb_query.collide_with_areas = true
			query_alloc_count += 1
		else:
			query_reuse_count += 1
		_orb_shape.radius = eff_max_reach + 24.0
		_orb_query.transform = Transform2D(0.0, global_position)
		var results := space_state.intersect_shape(_orb_query, 32)
		_seen_ids_buf.clear()
		var idx := 0
		for res in results:
			var col = res.get("collider")
			var parent = col.get_parent() if col != null else null
			if parent != null and parent.has_method("take_damage"):
				var enemy := parent as Node2D
				if not is_instance_valid(enemy) or enemy.is_in_group("chests") or enemy.is_in_group("herbs"):
					continue
				var eid := enemy.get_instance_id()
				if _seen_ids_buf.has(eid):
					continue
				_seen_ids_buf[eid] = true
				var offset := enemy.global_position - global_position
				var od := _acquire_pooled_dict(_orb_dict_pool, idx)
				od["dist"] = offset.length()
				od["angle"] = offset.angle()
				_orb_enemies_buf.append(od)
				idx += 1

## 受创入口。source_pos = 伤害来源位置（Boss 震地/丹爆自爆等 AoE 传入），
## 受击火花据此指向真实来向；未传（接触/弹丸等贴脸伤害本就有实体因果）时保持向上。
func take_damage(amount: float, source_pos: Vector2 = Vector2.INF) -> void:
	if invulnerable_time > 0.0 or GameManager.is_game_over or _dying or _victorious:
		return

	# 流云身法：闪避成功不掉血，换一段「残影」短无敌，并把躲掉的这一刀存进影里等着还回去。
	# 为什么必须给这段无敌：不给的话下一帧又是一次判定，闪避只是把「这一下」推迟几帧，
	# 落点频率仍被 0.55s 无敌帧钉死 ⇒ 加这段之前实测 86% 闪避在贴身怪群只兑现 ×1.25 有效生命
	#（尺子见 tests/DodgeDeliveryProbe.tscn，机制判据见 tests/ShadowStepCheck.tscn）。
	if GameManager.rng.randf() < GameManager.get_effective_dodge():
		DamageNumber.spawn(get_parent(), global_position, 0, false, "闪避")
		AudioManager.play_sfx("dodge", 1.0)
		invulnerable_time = maxf(invulnerable_time, ShadowStepData.GUARD_SEC)
		# 影层是影者专属机制（闸=是否绑定影爆额外技能，与 HUD 额外按钮显隐同一把尺）：
		# 其他角色靠加点/道具/神行术也能闪，但没处兑现影爆，只涨层等于白送 ×1.50 永久增伤。
		if GameManager.extra_skill_id == "shadowburst":
			shadow_ring = ShadowStepData.push_ring(shadow_ring, amount)
			# 攒着就增伤：影层乘区跟着队列长度走（满层 ×1.50），落地兑现清空时回 1.0
			GameManager.shadow_amp_mult = ShadowStepData.amp_mult(shadow_ring)
			if skill_vfx != null:
				skill_vfx.on_shadow_gained(ShadowStepData.stacks_of(shadow_ring))
		# 流云潜影玉：闪避成功概率回血
		var dodge_heal_chance: float = GameManager.item_hook_sum("dodge_heal_chance")
		if dodge_heal_chance > 0.0 and GameManager.rng.randf() < dodge_heal_chance:
			heal(GameManager.item_hook_sum("dodge_heal_hp"))
		return

	var reduced := GameBalance.incoming_damage(amount, GameManager.get_effective_armor())
	current_health = maxf(0.0, current_health - reduced)
	invulnerable_time = BASE_INVULNERABLE_TIME
	GameManager.on_player_hit(reduced)

	# 守卫·盾势：被护甲挡下的那部分伤害存进盾势槽，蓄满当帧自动爆发（全自动，不用学操作）。
	# 蓄能天然被受击无敌帧（BASE_INVULNERABLE_TIME）节流，贴身怪群也不会超频连炸；数值全在 GuardStanceData。
	if GameManager.guard_stance > 0.0:
		GameManager.shield_charge = GuardStanceData.add_charge(
			GameManager.shield_charge, amount - reduced, max_health)
		if skill_vfx != null and skill_vfx.has_method("on_guard_charge_updated"):
			skill_vfx.on_guard_charge_updated(GameManager.shield_charge, GuardStanceData.cap_of(max_health))
		if GuardStanceData.is_full(GameManager.shield_charge, max_health):
			_release_guard_stance()
	GameManager.player_hp_changed.emit(current_health, max_health)

	# game-feel 复合打击反馈：相机大创伤 + 顿帧 + 屏幕边缘红晕脉冲 + 玩家受力挤压 + 触觉震感
	GameManager.feedback(GameManager.FeedbackTier.LARGE)
	GameFeel.vibrate(40, 0.85)
	GameManager.pulse_damage_vignette(Color(0.85, 0.12, 0.12, 0.65))
	# 定向受击形变（2026-10-15 对齐敌人那套）：有来源位置时按受力方向选挤压轴向，
	# 并叠 14° 后仰 + 2.8px 微反冲。玩家受击是低频大事件，一律走暴击档强度（旧硬编码
	# (1.35,0.72) 就是暴击档数值）；无来源位置（旧调用残留）退化为默认水平压扁。
	var hit_dir := Vector2.ZERO
	if source_pos != Vector2.INF:
		hit_dir = global_position - source_pos
	play_squash(GameBalance.hit_squash_target(hit_dir, true), 0.22)
	if hit_dir.length_squared() > 10.0:
		var k_norm := hit_dir.normalized()
		_hit_tilt = -k_norm.x * deg_to_rad(14.0)
		_hit_jiggle_offset = k_norm * 2.8
		anim_sprite.position = _hit_jiggle_offset
		if is_procedural and procedural_view != null:
			procedural_view.position = _hit_jiggle_offset
	if is_procedural and procedural_view != null:
		procedural_view.play_hit(0.2)
	AudioManager.play_sfx("player_hurt", 0.9)

	# 受击闪白：帧内衰减（零 Tween 分配，与 EnemyBase 同款）。顶点色通道版：
	# self_modulate 承载闪白（材质共享，渲染器 use_parent_material 继承父级顶点色）
	_write_flash_channel(1.0)
	_flash_t = PLAYER_FLASH_DOWN_DUR

	DamageNumber.spawn(get_parent(), global_position, int(reduced), false)

	if current_health <= 0.0:
		# 替死傀儡挡劫：消耗一件免死回半血，挡不了才真正倒下
		if GameManager.try_revive():
			return
		_play_death_sequence()

## 阵亡演出（2026-10-15 优化）：镜头平滑推入特写 + 塌落化光消散 + 结算弹窗无缝衔接。
## 期间 _dying 挡住移动/技能/再受创，敌人照常行动（不暂停整场，只谢幕玩家本体）；
## 镜头推近放大（1.35x）聚焦于倒地修士，消散谢幕后才 trigger_game_over。
func _play_death_sequence() -> void:
	if _dying:
		return
	_dying = true
	_dash_time = 0.0
	velocity = Vector2.ZERO
	invulnerable_time = 9999.0  # 谢幕期不再吃任何判定
	# 停帧后定向受击反馈的衰减不再跑：就地归位，别让尸体挂着半截反冲位移谢幕
	#（后仰倾角保留——倒在受力方向上正是「被这一下打倒」的读数）
	_hit_tilt = 0.0
	_hit_jiggle_offset = Vector2.ZERO
	anim_sprite.position = Vector2.ZERO
	if is_procedural and procedural_view != null:
		procedural_view.position = Vector2.ZERO

	# 1. 镜头平滑推进特写（0.55s CUBIC_OUT 放大 1.35x 聚焦玩家倒地位置）
	GameFeel.focus_camera(GameManager, global_position, 1.35, 0.55)

	# 2. 倒地姿态与初阶受击反馈
	play_squash(Vector2(1.32, 0.62), 0.55)
	if is_procedural and procedural_view != null:
		procedural_view.play_hit(0.55)
	# 灵气初散：一圈纸白微环 + 落点微尘
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 32.0, GameStyle.CHALK, 0.45)
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 14), Vector2.UP * 30.0)
	GameFeel.vibrate(80, 1.0)

	var fade_target: Node2D = anim_sprite
	if is_procedural and procedural_view != null:
		fade_target = procedural_view

	var tw := create_tween()
	# 0.5s 伏地定格，让特写镜头清晰展现修士倒地姿势
	tw.tween_interval(0.5)
	tw.tween_callback(func():
		# 灵气消散：一圈略大的空灵微环散开
		JuiceEffect.spawn_shockwave(get_parent(), global_position, 48.0, GameStyle.CHALK, 0.55)
	)
	# 随后 0.45s 沉地淡出，灵韵归虚
	tw.tween_property(fade_target, "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(fade_target, "scale", Vector2(0.35, 0.16), 0.45)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(shadow_sprite, "modulate:a", 0.0, 0.4)
	# 留白 0.2s 呼吸静默，让空场稍有沉淀，再无缝呼出结算屏
	tw.tween_interval(0.2)
	tw.tween_callback(func():
		if not GameManager.is_game_over:
			GameManager.trigger_game_over(false))

## 通关胜利演出（2026-10-15）：荡平妖潮·得道飞升。
## 镜头平滑推入特写（1.4x）+ 角色微浮升空 + 金玉双色灵气环爆发 + 仙乐定音，随后唤起通关结算。
func play_victory_sequence() -> void:
	if _victorious or _dying:
		return
	_victorious = true
	_dash_time = 0.0
	velocity = Vector2.ZERO
	invulnerable_time = 9999.0

	_hit_tilt = 0.0
	_hit_jiggle_offset = Vector2.ZERO
	anim_sprite.position = Vector2.ZERO
	if is_procedural and procedural_view != null:
		procedural_view.position = Vector2.ZERO
		procedural_view.rotation = 0.0
		procedural_view.play_idle()
	else:
		RunMotion.select_anim(anim_sprite, _anim_idle, false)

	# 1. 镜头平滑推入特写（0.65s CUBIC_OUT 放大 1.4x 聚焦玩家身位）
	GameFeel.focus_camera(GameManager, global_position, 1.4, 0.65)

	# 2. 仙乐定音与触觉反馈
	AudioManager.play_sfx("obelisk_blessing", 1.0)
	GameFeel.vibrate(60, 0.8)

	# 3. 得道飞升姿态：修仙真身微浮升空 + 金玉双环绽放
	play_squash(Vector2(0.85, 1.22), 0.55)
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 64.0, GameStyle.GOLD, 0.65)
	JuiceEffect.spawn_heal_rise(get_parent(), global_position)

	var target_node: Node2D = anim_sprite
	if is_procedural and procedural_view != null:
		target_node = procedural_view

	var tw := create_tween()
	# 角色微升 10px 宛如得道凌空浮起，微泛仙灵暖光
	tw.tween_property(target_node, "position:y", -10.0, 0.55)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(target_node, "modulate", Color(1.25, 1.2, 0.95), 0.55)

	# 0.45s 时爆出第二重澄澈玉色灵气环（象征大乘圆满）
	tw.tween_callback(func():
		JuiceEffect.spawn_shockwave(get_parent(), global_position, 96.0, GameStyle.JADE, 0.7)
	)

	# 留白定格 ~0.55s 尽显真身风采，随后 trigger_game_over(true)
	tw.tween_interval(0.55)
	tw.tween_callback(func():
		if not GameManager.is_game_over:
			GameManager.trigger_game_over(true)
	)

## 胜利状态复位（从结算弹窗选择「继续无尽」时调用，恢复正常物理与移动）
func reset_victory_state() -> void:
	_victorious = false
	invulnerable_time = 0.0
	anim_sprite.position = Vector2.ZERO
	anim_sprite.modulate = Color.WHITE
	if is_procedural and procedural_view != null:
		procedural_view.position = Vector2.ZERO
		procedural_view.modulate = Color.WHITE
		procedural_view.rotation = 0.0

func increase_max_hp(amount: float, heal_amount: float) -> void:
	max_health += amount
	current_health = minf(max_health, current_health + heal_amount)
	GameManager.player_hp_changed.emit(current_health, max_health)
	play_squash(Vector2(0.82, 1.25), 0.24)
	DamageNumber.spawn(get_parent(), global_position, int(heal_amount), false, "+" + str(int(heal_amount)) + " HP")

## 出售回退上限（StatSystem.revert_stat_fields 的 max_hp 分支）：只把上限缩回去、当前血截平。
## 买的时候那一口治疗不退回来 —— 血已经回了；但超出新上限的那一截必须削平，
## 否则顶栏与商店那颗生命徽记会读出「145/120」这种假数（读数必须与判定同源）。
func decrease_max_hp(amount: float) -> void:
	max_health = maxf(1.0, max_health - amount)
	current_health = minf(current_health, max_health)
	GameManager.player_hp_changed.emit(current_health, max_health)

func _on_pickup_area_area_entered(area: Area2D) -> void:
	# 认实现了 magnet_to 的掉落物（金币与回复葫芦）。葫芦自带满血门控（满血不飞）。
	if area.has_method("magnet_to"):
		area.magnet_to(self)
	elif area.get_parent() and area.get_parent().has_method("magnet_to"):
		area.get_parent().magnet_to(self)
