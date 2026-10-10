class_name Player
extends CharacterBody2D

const BASE_PICKUP_RADIUS: float = 96.0   ## 拾取圈内径（福缘/乾坤袋按乘区放大）
const DASH_LANDING_SPEED_MUL: float = 1.35  ## 冲刺落地那帧的残留速度上限（× 常速）：只留一点前冲，不许拖出隐形滑行

@export var max_health: float = 120.0
var current_health: float = 120.0
var base_speed: float = 210.0
var invulnerable_time: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow_sprite: Sprite2D = $Shadow
@onready var sun_orb_container: Node2D = $SunOrbContainer
@onready var weapon_holder: Node2D = $WeaponHolder
@onready var pickup_area: Area2D = $PickupArea
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial
@onready var skill_vfx: PlayerSkillVfx = $SkillVfx

var sun_orb_angle: float = 0.0
var idle_bob_phase: float = 0.0
var facing: String = "s"
# 移动方式：gait=步态腿帧（默认）/ hover=御剑悬浮（单姿势图集 + RunMotion.apply_hover 程序驱动）
var _motion_mode: String = "gait"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var regen_tick: float = 0.0
var flash_tween: Tween = null
var squash_tween: Tween = null
var dust_timer: float = 0.0
var procedural_view: ProceduralCultivatorView = null
var is_procedural: bool = false
var gait_phase_counter: float = 0.0

# ---------------- 随行神通（技能）运行时 ----------------
var skill_cd_left: float = 0.0     ## 技能冷却剩余秒（HUD 冷却遮罩轮询这个）
var skill_cd_total: float = 1.0    ## 本次释放进入的总冷却（算遮罩比例用）
var _skill_buffs: Dictionary = {}  ## 进行中的短时增益：buff id -> 剩余秒（gale / haste）
var _dash_time: float = 0.0        ## 冲刺剩余秒（>0 期间移动被冲刺接管）
var _dash_dir: Vector2 = Vector2.DOWN
var _dash_speed: float = 0.0

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
	_setup_sprite_frames()
	anim_base_scale = anim_sprite.scale
	# 浮游法器在 _process 里做轨道跟随（渲染帧率），父链开了物理插值会互相打架，关闭该分支插值
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

	# 角色独立形象：按道统读 CultivatorData.sprite 的 8 方向图集，缺图回退默认青衫修士
	var sheet_path := "res://assets/art/pawn_blue_8dir.png"
	var cdef := CultivatorData.get_def(GameManager.cultivator_id)
	_motion_mode = String(cdef.get("motion", "gait"))

	if _motion_mode == "procedural":
		is_procedural = true
		anim_sprite.visible = false
		if procedural_view == null:
			procedural_view = ProceduralCultivatorView.new()
			procedural_view.position = anim_sprite.position
			procedural_view.scale = Vector2(1.2, 1.2)
			procedural_view.setup_character_id(GameManager.cultivator_id)
			add_child(procedural_view)
		else:
			procedural_view.setup_character_id(GameManager.cultivator_id)
			procedural_view.visible = true
	else:
		is_procedural = false
		anim_sprite.visible = true
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
	if shape_node != null and shape_node.shape is CircleShape2D:
		var c_shape = shape_node.shape.duplicate() as CircleShape2D
		c_shape.radius = BASE_PICKUP_RADIUS * GameManager.pickup_range_mult
		shape_node.shape = c_shape

## 当前拾取半径：真话只有 PickupArea 那一圈碰撞形状。
## 满血待命的回复珠要问它（别抄常数），否则「圈内掉血自动飞来」会和热区不一致。
func pickup_radius() -> float:
	if pickup_area == null:
		return BASE_PICKUP_RADIUS * GameManager.pickup_range_mult
	var shape_node: Node = pickup_area.get_node_or_null("CollisionShape2D")
	if shape_node != null and shape_node.shape is CircleShape2D:
		return (shape_node.shape as CircleShape2D).radius
	return BASE_PICKUP_RADIUS * GameManager.pickup_range_mult

func _on_leveled_up(_lvl: int) -> void:
	play_squash(Vector2(0.72, 1.38), 0.28)
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)

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
		w.orbit_extents = Vector2(80.0, 58.0)

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
	var current_count = sun_orb_container.get_child_count()
	if current_count < target.size():
		for i in range(target.size() - current_count):
			var orb = sun_orb_scene.instantiate()
			sun_orb_container.add_child(orb)
	elif current_count > target.size():
		var to_remove = current_count - target.size()
		for i in range(to_remove):
			var last_idx = sun_orb_container.get_child_count() - 1
			var child = sun_orb_container.get_child(last_idx)
			sun_orb_container.remove_child(child)
			child.queue_free()
	for i in range(sun_orb_container.get_child_count()):
		var orb = sun_orb_container.get_child(i) as SunOrb
		if orb != null and i < target.size():
			var d_entry = target[i]
			var d_id: String = GameManager._drone_id(d_entry)
			var d_star: int = GameManager._drone_star(d_entry)
			orb.setup(d_star, d_id)

func heal(amount: float, quiet: bool = false) -> void:
	if amount <= 0.0:
		return
	var before := current_health
	current_health = minf(max_health, current_health + amount)
	GameManager.player_hp_changed.emit(current_health, max_health)
	# 只报真正回上来的那部分；顶满时一口没回，不发挤压/音效/+X（报了就是假账）
	var gained := current_health - before
	if gained <= 0.01:
		return
	if quiet:
		return
	play_squash(Vector2(0.88, 1.16), 0.18)
	AudioManager.play_sfx("heal", 0.9)
	DamageNumber.spawn(get_parent(), global_position, int(gained), false, "+" + str(int(gained)))

# ---------------- 随行神通（技能） ----------------

## HUD 技能按钮入口。false = 没放出来（CD 中 / 战斗外 / 无技能），调用方不发反馈
func try_activate_skill() -> bool:
	var sid := GameManager.active_skill_id
	if sid.is_empty() or GameManager.is_game_over or skill_cd_left > 0.0:
		return false
	var spawner: Node = GameManager.wave_spawner
	if spawner != null and int(spawner.phase) != int(WaveSpawner.Phase.FIGHT):
		return false
	var st := SkillData.final_stats(sid, GameManager.cultivator_id)
	if st.is_empty():
		return false
	skill_cd_total = float(st["cooldown"])
	skill_cd_left = skill_cd_total
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

func _tick_skill_buffs(delta: float) -> void:
	var expired: Array = []
	for key in _skill_buffs.keys():
		_skill_buffs[key] = float(_skill_buffs[key]) - delta
		if float(_skill_buffs[key]) <= 0.0:
			expired.append(key)
	for key in expired:
		_skill_buffs.erase(key)
		# 到期精确回滚：buff 乘区与加点/羁绊乘区隔离，回 1.0 即完全无残留
		match String(key):
			"gale":
				GameManager.buff_move_speed_mult = 1.0
			"haste":
				GameManager.buff_attack_speed_mult = 1.0

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
	# 冲刺无敌覆盖位移全程再多 2 帧余量，落点瞬间不吃贴脸伤害
	invulnerable_time = maxf(invulnerable_time, _dash_time + 0.04)
	play_squash(Vector2(1.3, 0.72), 0.2)
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 14), _dash_dir * _dash_speed)
	if skill_vfx != null:
		skill_vfx.on_dash_start(_dash_dir, float(st["distance"]), _dash_time)
	if is_procedural and procedural_view != null:
		procedural_view.play_dash(_dash_time)
	AudioManager.play_sfx("skill_dash", 1.0)

func _do_gale(st: Dictionary) -> void:
	GameManager.buff_move_speed_mult = 1.0 + float(st["power"])
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
	play_squash(Vector2(0.82, 1.22), 0.24)
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, Vector2.UP, true)
	if skill_vfx != null:
		skill_vfx.on_aegis_start(dur)
	AudioManager.play_sfx("skill_aegis", 1.0)

func _do_renewal(st: Dictionary) -> void:
	heal(max_health * float(st["power"]), true)
	play_squash(Vector2(0.88, 1.16), 0.18)
	DamageNumber.spawn(get_parent(), global_position, int(max_health * float(st["power"])), false, "+" + str(int(max_health * float(st["power"]))) + " HP")
	if skill_vfx != null:
		skill_vfx.on_renewal_cast()
	AudioManager.play_sfx("skill_heal", 1.0)

# ---------------- 主循环 ----------------

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over:
		return

	# 技能冷却与短时增益倒计时（与加点乘区隔离，到期精确回滚）
	if skill_cd_left > 0.0:
		skill_cd_left -= delta
	if not _skill_buffs.is_empty():
		_tick_skill_buffs(delta)

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

	# 灵愈心法 + 青木羁绊：持续回血
	var total_regen := GameManager.hp_regen + GameManager.synergy_hp_regen
	if total_regen > 0.0 and current_health < max_health:
		current_health = minf(max_health, current_health + total_regen * delta)
		regen_tick += delta
		if regen_tick >= 0.5:
			regen_tick = 0.0
			GameManager.player_hp_changed.emit(current_health, max_health)

	# 1. 移动输入与高响应加减速平滑
	var dir: Vector2 = Vector2.ZERO
	if GameManager.joystick != null and GameManager.joystick.has_method("get_direction"):
		dir = GameManager.joystick.get_direction()
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

	# 灵田界碑边界
	var lim: float = GameManager.MAP_HALF_EXTENT - 26.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 2. 奔跑步伐微尘
	if is_moving and actual_speed_sq > 1600.0:
		dust_timer -= delta
		if dust_timer <= 0.0:
			dust_timer = 0.22
			JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 14), velocity)
	else:
		dust_timer = 0.0

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
			if gait_phase_counter > 1.0:
				gait_phase_counter -= 1.0
			# 土豆兄弟式步态弹性（Squash & Stretch）：垂直弹跳与横向挤压形变
			var bounce_amp := 0.065 * clampf(speed_ratio, 0.6, 1.25)
			var hover_bob := sin(gait_phase_counter * TAU) * bounce_amp
			procedural_view.scale = current_base * 1.5 * Vector2(1.0 - hover_bob * 0.7, 1.0 + hover_bob)
			procedural_view.set_facing_dir(facing, anim_sprite.flip_h)
			# 土豆兄弟式御风灵动侧倾：水平移速驱动 4.8° 弹性倾角，转向灵动自然
			var target_bank := deg_to_rad(4.8) * clampf(effective_dir.x, -1.0, 1.0) * clampf(speed_ratio, 0.0, 1.2)
			procedural_view.rotation = lerp_angle(procedural_view.rotation, target_bank, minf(delta * 14.0, 1.0))
			procedural_view.play_run(gait_phase_counter, sin(gait_phase_counter * TAU), speed_ratio, target_bank)
			if shadow_sprite != null:
				# 影子跟随移速方向自然拉伸拖尾与呼吸
				var shadow_pulse := 1.0 - sin(gait_phase_counter * TAU) * 0.08
				shadow_sprite.scale = Vector2(0.85, 0.85) * (1.0 + 0.15 * speed_ratio) * shadow_pulse
		elif _motion_mode == "hover":
			# 御剑悬浮：不切腿帧（图集各列同一姿势），浮沉/前倾由程序驱动
			RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
			RunMotion.apply_hover(anim_sprite, current_base, true, effective_dir, delta, speed_ratio, shadow_sprite)
		else:
			var run_anim: String = "run_" + facing
			RunMotion.select_anim(anim_sprite, run_anim, true)

			var lean_axis: float = absf(effective_dir.x)
			RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, lean_axis, delta, speed_ratio, 0.0, shadow_sprite)
	else:
		var idle_anim: String = "idle_" + facing
		if is_procedural and procedural_view != null:
			procedural_view.scale = current_base * 1.5
			procedural_view.rotation = lerp_angle(procedural_view.rotation, 0.0, minf(delta * 10.0, 1.0))
			procedural_view.set_facing_dir(facing, anim_sprite.flip_h)
			procedural_view.play_idle()
			if shadow_sprite != null:
				shadow_sprite.scale = Vector2(0.85, 0.85)
		elif _motion_mode == "hover":
			RunMotion.select_anim(anim_sprite, idle_anim, false)
			RunMotion.apply_hover(anim_sprite, current_base, false, Vector2.ZERO, delta, 1.0, shadow_sprite)
		else:
			RunMotion.select_anim(anim_sprite, idle_anim, false)
			idle_bob_phase += delta * 2.2
			RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta, 1.0, idle_bob_phase, shadow_sprite)

	# 4. 灵蝶环绕运算
	_process_sun_orbs(delta)

	# 5. 随行神通（技能）角色身上动效更新
	if skill_vfx != null:
		skill_vfx.update_vfx(delta, is_moving, velocity)

	# 6. 统一调度各法器索敌目标（多向分流 + 贴身危急集火 + 动态扇形展开）
	# 10Hz 节流 + 错相（2026-10-10 第 6 波卡顿优化）：敌人位置连续，索敌无需逐帧
	# intersect_shape；新目标入射程最多延迟 100ms 锁定，肉眼无感
	_search_phase -= delta
	if _search_phase <= 0.0:
		_search_phase = TARGET_SEARCH_INTERVAL
		_update_weapon_targets()

func _sort_candidate_by_dist(a: Node2D, b: Node2D) -> bool:
	return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position)

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
		if col and col.get_parent() and col.get_parent().has_method("take_damage"):
			var enemy = col.get_parent() as Node2D
			if not is_instance_valid(enemy):
				continue
			var is_chest := enemy.is_in_group("chests")
			# 匣子与妖怪共用 4 号层，同一圈查询两个都捞得到；匣子另册登记，只接闲着的法器
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
		ed["dist"] = offset.length()
		ed["angle"] = offset.angle()
		_enemies_info_buf.append(ed)

	_chests_info_buf.clear()
	for i in range(_candidate_chests_buf.size()):
		var c := _candidate_chests_buf[i]
		var offset := c.global_position - global_position
		var cd := _acquire_pooled_dict(_chests_dict_pool, i)
		cd["id"] = c.get_instance_id()
		cd["dist"] = offset.length()
		cd["angle"] = offset.angle()
		_chests_info_buf.append(cd)

	# 两段式：妖怪先分完，剩下无事可做的法器才去砸匣子（见 GameBalance.assign_targets_with_chests）
	var assignments: Array = GameBalance.assign_targets_with_chests(_weapons_info_buf, _enemies_info_buf, _chests_info_buf)
	_candidate_targets_buf.clear()
	_candidate_targets_buf.append_array(_candidate_enemies_buf)
	_candidate_targets_buf.append_array(_candidate_chests_buf)

	# 按实际共享同一目标的法器分组计算扇形错开角：独自迎敌时不偏移，共享目标时扇形展开
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

func _process_sun_orbs(delta: float) -> void:
	var count := sun_orb_container.get_child_count()
	if count == 0:
		return

	var range_mult: float = GameManager.attack_range_mult * GameManager.synergy_range_mult
	var base_radius: float = SunOrb.ORBIT_RADIUS * range_mult
	var min_radius: float = SunOrb.MIN_ORBIT_RADIUS
	var max_reach: float = 120.0
	var max_star: int = 1
	for i in range(count):
		var orb_child := sun_orb_container.get_child(i) as SunOrb
		if orb_child != null:
			if orb_child.max_orbit_reach > max_reach:
				max_reach = orb_child.max_orbit_reach
			if orb_child.star > max_star:
				max_star = orb_child.star
	var eff_max_reach: float = max_reach * range_mult

	# 扫描御灵感知圈内的敌人（复用查询与字典缓冲）
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
			if col and col.get_parent() and col.get_parent().has_method("take_damage"):
				var enemy := col.get_parent() as Node2D
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
		max_star
	)
	sun_orb_angle += delta * angular_speed

	for i in range(count):
		var orb := sun_orb_container.get_child(i) as SunOrb
		if orb == null:
			continue
		var a: float = sun_orb_angle + float(i) * (TAU / float(count))
		var tgt_r: float = float(target_radii[i]) if i < target_radii.size() else base_radius
		orb.current_radius = lerpf(orb.current_radius, tgt_r, minf(delta * 12.0, 1.0))
		orb.position = Vector2(cos(a), sin(a)) * orb.current_radius
		# 随切线横向分量的轻微侧倾（既灵动又不倒立）
		orb.rotation = clampf(-sin(a) * 0.25, -0.30, 0.30)

func take_damage(amount: float) -> void:
	if invulnerable_time > 0.0 or GameManager.is_game_over:
		return

	# 流云身法：闪避成功不掉血、不消耗无敌帧
	if GameManager.rng.randf() < GameManager.get_effective_dodge():
		DamageNumber.spawn(get_parent(), global_position, 0, false, "闪避")
		AudioManager.play_sfx("dodge", 1.0)
		return

	var reduced := GameBalance.incoming_damage(amount, GameManager.get_effective_armor())
	current_health = maxf(0.0, current_health - reduced)
	invulnerable_time = 0.55
	GameManager.player_hp_changed.emit(current_health, max_health)

	# game-feel 复合打击反馈：相机大创伤 + 顿帧 + 屏幕边缘红晕脉冲 + 玩家受力挤压 + 触觉震感
	GameManager.feedback(GameManager.FeedbackTier.LARGE)
	GameFeel.vibrate(40, 0.85)
	GameManager.pulse_damage_vignette(Color(0.85, 0.12, 0.12, 0.65), 0.24)
	play_squash(Vector2(1.35, 0.72), 0.22)
	if is_procedural and procedural_view != null:
		procedural_view.play_hit(0.2)
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, Vector2.UP, false)
	AudioManager.play_sfx("enemy_hit", 0.8)

	if hit_flash_mat != null:
		if flash_tween != null and flash_tween.is_valid():
			flash_tween.kill()
		flash_tween = create_tween()
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 1.0, 0.03)
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 0.0, 0.1)

	DamageNumber.spawn(get_parent(), global_position, int(reduced), false)

	if current_health <= 0.0:
		# 替死傀儡挡劫：消耗一件免死回半血，挡不了才真正倒下
		if GameManager.try_revive():
			return
		GameManager.trigger_game_over(false)

func increase_max_hp(amount: float, heal_amount: float) -> void:
	max_health += amount
	current_health = minf(max_health, current_health + heal_amount)
	GameManager.player_hp_changed.emit(current_health, max_health)
	play_squash(Vector2(0.82, 1.25), 0.24)
	DamageNumber.spawn(get_parent(), global_position, int(heal_amount), false, "+" + str(int(heal_amount)) + " HP")

func _on_pickup_area_area_entered(area: Area2D) -> void:
	# 只认实现了 magnet_to 的掉落物（灵石）。残丹/回春葫芦故意不实现它：那颗要人贴上去才入口。
	if area.has_method("magnet_to"):
		area.magnet_to(self)
	elif area.get_parent() and area.get_parent().has_method("magnet_to"):
		area.get_parent().magnet_to(self)
