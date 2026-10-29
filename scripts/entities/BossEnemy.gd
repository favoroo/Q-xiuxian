class_name BossEnemy
extends EnemyBase

## 关卡 Boss：固定 Boss 回合（第 10/20 波、无尽每 5 波）登场，参考土豆兄弟的大 Boss 与弹幕射击设计。
## 特征：
##   1. 超厚血条，HUD 底部贴边专设 Boss 血条（boss_hp_changed / boss_defeated 信号驱动，带节流防掉帧）
##   2. 7 种丰富攻击模式轮换：
##      - RING: 双层交错弧线环弹（顺/逆时针交错弧线，二阶段追加直穿环）
##      - BURST_FAN: 扇形连射狙击（逐波加速压迫横向走位）
##      - SPIRAL: 螺旋风暴弹幕（持续原地旋转喷吐弹幕走廊）
##      - SPLIT_BOMB: 分裂子母弹（慢速母弹到期爆裂为一圈高速子火球）
##      - CHARGE: 破阵冲锋 + 侧翼洒弹（预警胶囊线与扫掠判定同源，途中封路，收势派生小环）
##      - SKY_FIRE: 追踪天火连环轰炸（多处预警圈定点轰炸，严惩站桩）
##      - SLAM: 震地冲击（预警圈填满式结算，狂暴落地派生冲击环弹）
##      - SUMMON: 召唤妖群 + 弹幕掩护
##   3. 分波次递进 + 半血二阶段狂暴：
##      - 第 10 波火焰Boss：初战常态 5 招，半血狂暴解锁天火与螺旋
##      - 第 20 波极煞魔尊：全套高压招式、紫焰魔弹、四螺旋风暴与多子母弹
## 数值由 WaveSpawner 按 GameBalance 公式注入。

enum Pattern {
	RING,        ## 双层交错弧线环弹
	BURST_FAN,   ## 扇形连射狙击
	SPIRAL,      ## 螺旋风暴弹幕
	SPLIT_BOMB,  ## 分裂子母弹
	CHARGE,      ## 破阵冲锋 + 侧翼洒弹
	SKY_FIRE,    ## 追踪天火连环轰炸
	SLAM,        ## 震地冲击（附二阶段/近远派生）
	SUMMON,      ## 召唤妖群 + 弹幕掩护
	CHAIN_CHARGE, ## 多段折返连冲
	TURRET_SHIFT, ## 阵眼换桩瞬移 + 双环震爆
	HAZARD_FIELD, ## 连环禁区封锁
	BLINK_SLASH,  ## 瞬步贴脸扇形回斩
}

@export var boss_id: String = ""
@export var boss_title: String = "敌潮Boss"
@export var final_boss: bool = false      ## 第 20 波魔尊：换紫皮、放大身形、全招式全开
@export var attack_interval: float = GameBalance.BOSS_ATTACK_INTERVAL  ## 特殊攻击循环间隔

var _attack_timer: float = 2.4    ## 开场缓冲，让玩家先看清魔君登场
var _pattern_idx: int = 0
var _last_pattern: int = -1
var _phase2: bool = false
var _tint: Color = Color.WHITE    ## 常态染色（二阶段转红/紫，演出后回染）
var _purple_bolts: bool = false        ## 幽紫魔弹口径：仅旧最终Boss与九幽心魔尊使用

# 血条信号节流
var _hp_emit_acc: float = 0.0
var _hp_emit_cd: float = 0.0
var _heavy_hit_cd: float = 0.0   ## 大比例掉血镜头回应的独立冷却（take_damage 写入）

# 震地状态机
var _slam_pending: bool = false
var _slam_timer: float = 0.0
var _slam_ring: AoeTelegraph = null

# 螺旋风暴状态机
var _spiral_active: bool = false
var _spiral_timer: float = 0.0
var _spiral_step_timer: float = 0.0
var _spiral_angle: float = 0.0

## 读招姿态：上一帧是否处于「蓄力/施法」态（起手→归零的跳变发一次 recoil 爆发读数）
var _pose_casting: bool = false

## 按招式状态机维持渲染器 special_state 0→1（起手预警有真进度，引导/连射给固定读数）；
## 招式归零瞬间触发一次 recoil，区分「蓄力/爆发」两态。aim_dir 由 EnemyBase 同步段
## 持续指向玩家，蓄力中魔刃收束读数无需此处接线。
func _sync_cast_pose() -> void:
	if procedural_view == null:
		return
	var pose := 0.0
	if _slam_pending:
		pose = clampf(1.0 - _slam_timer / maxf(GameBalance.BOSS_SLAM_WINDUP, 0.001), 0.0, 1.0)
	elif _charge_windup > 0.0:
		pose = clampf(1.0 - _charge_windup / maxf(GameBalance.BOSS_CHARGE_WINDUP, 0.001), 0.0, 1.0)
	elif _spiral_active:
		pose = 0.5   # 引导喷吐：恒定收束指向态
	elif _fan_waves_left > 0 or _sky_fire_strikes_left > 0 or _hazard_fields_left > 0:
		pose = 0.35  # 连射/天火/禁区后台推进：轻收束读数
	procedural_view.special_state = pose
	var casting := pose > 0.001
	if _pose_casting and not casting:
		# 出手收势：一次后坐爆发（recoil 由渲染器自行衰减回弹）
		procedural_view.trigger_recoil()
	_pose_casting = casting

## 瞬发招式的爆发读数：无预警蓄力的招式（环弹/子母弹/召唤掩护）出手当帧
## 直接发一次 recoil 后坐，让渲染器至少区分出「爆发」一态。
func _pose_burst() -> void:
	if procedural_view != null:
		procedural_view.trigger_recoil()

# 扇形连射状态机
var _fan_waves_left: int = 0
var _fan_wave_timer: float = 0.0

# 天火连环轰炸状态机
var _sky_fire_strikes_left: int = 0
var _sky_fire_spawn_timer: float = 0.0
var _active_sky_fires: Array[Dictionary] = []

# 连环冲刺状态机
var _chain_charges_left: int = 0

# 禁区封锁状态机
var _hazard_fields_left: int = 0
var _hazard_spawn_timer: float = 0.0
var _active_hazard_fields: Array[Dictionary] = []

## 出招轮换表：按波次与阶段动态编排
var _patterns: Array = []

var _minion_scenes: Array = [
	preload("res://scenes/entities/SlimeEnemy.tscn"),
	preload("res://scenes/entities/FlowerEnemy.tscn"),
	preload("res://scenes/entities/FengQunEnemy.tscn"),
]

func _ready() -> void:
	if boss_id != "":
		if "BOSS_POOL" in EnemyData and EnemyData.BOSS_POOL.has(boss_id):
			var cfg: Dictionary = EnemyData.BOSS_POOL[boss_id]
			move_speed = float(cfg.get("move_speed", move_speed))
		if boss_id == "qianji":
			move_speed = 0.0
		elif boss_id == "wangu":
			preferred_range = 240.0
		_apply_boss_visuals()
	elif final_boss:
		spritesheet_path = "res://assets/art/warrior_purple_8dir.png"
		anim_sprite.scale *= 1.16
		var light := get_node_or_null("PointLight2D") as PointLight2D
		if light != null:
			light.color = Color(0.8, 0.45, 1.0)
			light.energy = 0.85
		hit_stun_resist = 0.25
		_tint = Color(1.15, 0.85, 1.35)
		anim_sprite.modulate = _tint

	# 冲刺参数配置（关闭自动长扑定时器，改由出招大脑精确派发）
	charge_hit_radius = GameBalance.BOSS_CHARGE_HIT_RADIUS
	charge_duration = GameBalance.BOSS_CHARGE_DURATION
	charge_brake_time = GameBalance.BOSS_CHARGE_BRAKE
	charge_speed_mul = GameBalance.BOSS_CHARGE_SPEED_MUL
	charge_damage_mul = GameBalance.BOSS_CHARGE_DMG_MULT
	charge_side_bolts = GameBalance.BOSS_CHARGE_SIDE_BOLTS
	charge_whiff_stagger = 0.25
	charge_interval = 999999.0
	_charge_timer = 999999.0

	# 死亡演出分级（2026-10-15）：Boss 伏诛走「倾倒 → 尸体滞留慢渐隐」，不随小怪塌缩
	death_corpse_linger = true

	_purple_bolts = final_boss and (boss_id == "" or boss_id == "xinmo")
	_setup_patterns()
	super._ready()
	if procedural_view != null and boss_id != "":
		procedural_view.setup("boss_" + boss_id, true, true, final_boss)
	# 登场即上屏：HUD 血条由此信号点亮
	GameManager.boss_hp_changed.emit(current_hp, max_hp, boss_title)
	# Boss 战 BGM 压闷制造紧张感（伏诛/转阶段由 _die 与 play_bgm_key 负责解除）
	AudioManager.set_bgm_muffle(true)

func _apply_boss_visuals() -> void:
	var light := get_node_or_null("PointLight2D") as PointLight2D
	if boss_id == "chiyan":
		_tint = Color(1.7, 0.5, 0.45)
		if light != null:
			light.color = Color(1.0, 0.45, 0.3)
			light.energy = 0.75
	elif boss_id == "xiuluo":
		_tint = Color(1.3, 0.4, 0.4)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.95, 0.25, 0.2)
			light.energy = 0.85
	elif boss_id == "qianji":
		_tint = Color(0.5, 0.85, 1.1)
		hit_stun_resist = 0.0
		if light != null:
			light.color = Color(0.35, 0.8, 0.95)
			light.energy = 0.85
	elif boss_id == "wangu":
		_tint = Color(0.5, 1.25, 0.6)
		hit_stun_resist = 0.2
		if light != null:
			light.color = Color(0.3, 0.9, 0.4)
			light.energy = 0.8
	elif boss_id == "jianpo":
		_tint = Color(0.9, 1.1, 1.3)
		hit_stun_resist = 0.15
		if light != null:
			light.color = Color(0.7, 0.9, 1.0)
			light.energy = 0.8
	elif boss_id == "xinmo" or final_boss:
		spritesheet_path = "res://assets/art/warrior_purple_8dir.png"
		if anim_sprite != null:
			anim_sprite.scale *= 1.16
		_tint = Color(1.15, 0.85, 1.35)
		hit_stun_resist = 0.25
		if light != null:
			light.color = Color(0.8, 0.45, 1.0)
			light.energy = 0.85
	if anim_sprite != null:
		anim_sprite.modulate = _tint

func _setup_patterns() -> void:
	if boss_id == "":
		if final_boss:
			# 第 20 波魔尊：全招式全面施展
			_patterns = [
				Pattern.RING,
				Pattern.BURST_FAN,
				Pattern.SKY_FIRE,
				Pattern.CHARGE,
				Pattern.SPIRAL,
				Pattern.SPLIT_BOMB,
				Pattern.SLAM,
				Pattern.SUMMON,
			]
		elif _phase2:
			# 第 10 波狂暴形态：解锁天火与螺旋
			_patterns = [
				Pattern.RING,
				Pattern.BURST_FAN,
				Pattern.SKY_FIRE,
				Pattern.CHARGE,
				Pattern.SPIRAL,
				Pattern.SLAM,
				Pattern.SUMMON,
			]
		else:
			# 第 10 波常态起手
			_patterns = [
				Pattern.RING,
				Pattern.BURST_FAN,
				Pattern.CHARGE,
				Pattern.SLAM,
				Pattern.SUMMON,
			]
		return

	match boss_id:
		"chiyan":
			if _phase2:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.SKY_FIRE, Pattern.CHARGE, Pattern.SPIRAL, Pattern.SLAM, Pattern.SUMMON]
			else:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.CHARGE, Pattern.SLAM, Pattern.SUMMON]
		"xiuluo":
			if _phase2:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SLAM, Pattern.BLINK_SLASH, Pattern.CHAIN_CHARGE, Pattern.RING, Pattern.SLAM]
			else:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SLAM, Pattern.CHARGE, Pattern.BURST_FAN, Pattern.CHAIN_CHARGE, Pattern.SLAM]
		"qianji":
			if _phase2:
				_patterns = [Pattern.SPIRAL, Pattern.SPLIT_BOMB, Pattern.SKY_FIRE, Pattern.TURRET_SHIFT, Pattern.RING, Pattern.SPIRAL, Pattern.SPLIT_BOMB]
			else:
				_patterns = [Pattern.SPIRAL, Pattern.RING, Pattern.SPLIT_BOMB, Pattern.TURRET_SHIFT, Pattern.BURST_FAN, Pattern.RING]
		"wangu":
			if _phase2:
				_patterns = [Pattern.HAZARD_FIELD, Pattern.SUMMON, Pattern.SKY_FIRE, Pattern.SPLIT_BOMB, Pattern.HAZARD_FIELD, Pattern.SPIRAL]
			else:
				_patterns = [Pattern.HAZARD_FIELD, Pattern.SUMMON, Pattern.SPLIT_BOMB, Pattern.BURST_FAN, Pattern.HAZARD_FIELD, Pattern.RING]
		"jianpo":
			if _phase2:
				_patterns = [Pattern.BLINK_SLASH, Pattern.CHAIN_CHARGE, Pattern.BURST_FAN, Pattern.BLINK_SLASH, Pattern.SKY_FIRE, Pattern.SPIRAL]
			else:
				_patterns = [Pattern.BLINK_SLASH, Pattern.BURST_FAN, Pattern.CHARGE, Pattern.BLINK_SLASH, Pattern.RING, Pattern.BURST_FAN]
		"xinmo":
			if _phase2:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.BLINK_SLASH, Pattern.SPLIT_BOMB, Pattern.HAZARD_FIELD, Pattern.SKY_FIRE, Pattern.TURRET_SHIFT, Pattern.SLAM]
			else:
				_patterns = [Pattern.CHAIN_CHARGE, Pattern.SPIRAL, Pattern.HAZARD_FIELD, Pattern.SPLIT_BOMB, Pattern.BLINK_SLASH, Pattern.SKY_FIRE, Pattern.SLAM, Pattern.RING]
		_:
			if _phase2 or final_boss:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.SKY_FIRE, Pattern.CHARGE, Pattern.SPIRAL, Pattern.SLAM, Pattern.SUMMON]
			else:
				_patterns = [Pattern.RING, Pattern.BURST_FAN, Pattern.CHARGE, Pattern.SLAM, Pattern.SUMMON]

## Boss 出招大脑：与 EnemyBase._physics_process 的移动/接触伤害并行运行
func _process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return
	_hp_emit_cd -= delta
	_heavy_hit_cd = maxf(0.0, _heavy_hit_cd - delta)
	# 读招姿态接线（2026-10-19）：按 Boss 招式状态机维持 procedural_view.special_state 0→1，
	# _process 在物理帧之后运行（最后写者生效），覆盖 EnemyBase 同步段的归零。
	# 震地/冲锋预警有真实前摇给满值；引导/连射类（螺旋/扇形/天火）无起手预警，
	# 用固定中位读数表「正在施法」态，与蓄力可区分；全招式都发 recoil 爆发读数。
	_sync_cast_pose()
	var player = GameManager.player
	if player == null:
		return

	# 1. 震地冲击：预警圈「填满式」倒计时 → 结算（预警期互斥锁）
	if _slam_pending:
		_slam_timer -= delta
		if _slam_ring != null:
			_slam_ring.progress = 1.0 - _slam_timer / GameBalance.BOSS_SLAM_WINDUP
		if _slam_timer <= 0.0:
			_resolve_slam(player)
		return

	# 2. 破阵冲锋锁定段：预警或冲刺中不插新技能
	if _charge_windup > 0.0 or _charge_active > 0.0 or _charge_brake > 0.0:
		return

	# 3. 螺旋风暴引导施法：引导期间原地喷射弹幕
	if _spiral_active:
		_tick_spiral(delta)
		return

	# 4. 后台招式推进（扇形连射、天火定点与禁区封锁）
	_tick_burst_fan(delta, player)
	_tick_sky_fires(delta, player)
	_tick_hazard_fields(delta, player)

	# 5. 主技能循环定时器
	_attack_timer -= delta
	if _attack_timer <= 0.0:
		var mult := GameBalance.BOSS_PHASE2_INTERVAL_MULT if _phase2 else 1.0
		_attack_timer = attack_interval * mult
		_cast_next(player)

## Boss 选招权重（AI 行为，不改伤害）：远距离偏突进/远程，贴脸偏震地/环弹；上一招降权防连发。
const PICK_WEIGHT_BASE := 1.0
const PICK_WEIGHT_FAR := 2.2
const PICK_WEIGHT_NEAR := 2.0
const PICK_WEIGHT_WRONG_RANGE := 0.3
const PICK_WEIGHT_REPEAT := 0.2
const PICK_FAR_RANGE := 320.0
const PICK_NEAR_RANGE := 140.0
const PICK_FAR_PATTERNS := [Pattern.CHARGE, Pattern.SKY_FIRE, Pattern.BURST_FAN, Pattern.CHAIN_CHARGE, Pattern.BLINK_SLASH]
const PICK_NEAR_PATTERNS := [Pattern.SLAM, Pattern.RING, Pattern.BURST_FAN]

func _pick_pattern(player: Node2D) -> int:
	var dist: float = global_position.distance_to(player.global_position)
	var best_idx: int = 0
	var best_w: float = -1.0
	var tie_count: int = 0
	for i in range(_patterns.size()):
		var pat: int = _patterns[i]
		var w: float = PICK_WEIGHT_BASE
		if dist > PICK_FAR_RANGE:
			if pat in PICK_FAR_PATTERNS:
				w = PICK_WEIGHT_FAR
			elif pat in PICK_NEAR_PATTERNS and pat != Pattern.BURST_FAN:
				w = PICK_WEIGHT_WRONG_RANGE
		elif dist < PICK_NEAR_RANGE:
			if pat in PICK_NEAR_PATTERNS:
				w = PICK_WEIGHT_NEAR
			elif pat in PICK_FAR_PATTERNS and pat != Pattern.BURST_FAN:
				w = PICK_WEIGHT_WRONG_RANGE
		if pat == _last_pattern:
			w *= PICK_WEIGHT_REPEAT
		# 同权重候选按 _pattern_idx 轮换打破平局（确定性，不抽 rng）
		if w > best_w + 0.0001:
			best_w = w
			best_idx = i
			tie_count = 1
		elif absf(w - best_w) <= 0.0001:
			tie_count += 1
			if _pattern_idx % tie_count == 0:
				best_idx = i
	return _patterns[best_idx]

func _cast_next(player: Node2D) -> void:
	if _patterns.is_empty():
		return
	var pattern: int = _pick_pattern(player)
	_last_pattern = pattern
	_pattern_idx += 1
	match pattern:
		Pattern.RING:
			_cast_ring()
		Pattern.BURST_FAN:
			_cast_burst_fan(player)
		Pattern.SPIRAL:
			_cast_spiral()
		Pattern.SPLIT_BOMB:
			_cast_split_bomb(player)
		Pattern.CHARGE:
			_cast_charge(player)
		Pattern.SKY_FIRE:
			_cast_sky_fire(player)
		Pattern.SLAM:
			_cast_slam()
		Pattern.SUMMON:
			_cast_summon(player)
		Pattern.CHAIN_CHARGE:
			_cast_chain_charge(player)
		Pattern.TURRET_SHIFT:
			_cast_turret_shift(player)
		Pattern.HAZARD_FIELD:
			_cast_hazard_field(player)
		Pattern.BLINK_SLASH:
			_cast_blink_slash(player)

# ---------------- 招式 1：双层交错弧线环弹 ----------------

func _cast_ring() -> void:
	play_squash(Vector2(1.25, 0.78), 0.5)
	_pose_burst()  # 瞬发爆发读数（渲染器后坐一态）
	var tw := create_tween()
	tw.tween_property(anim_sprite, "modulate", Color(1.6, 0.6, 1.8) if final_boss else Color(1.7, 0.5, 0.45), 0.35)
	tw.tween_callback(func(): _fire_ring_layer(1))
	tw.tween_interval(GameBalance.BOSS_RING_LAYER_DELAY)
	tw.tween_callback(func(): _fire_ring_layer(2))
	if _phase2:
		tw.tween_interval(0.24)
		tw.tween_callback(func(): _fire_ring_layer(3))
	tw.tween_property(anim_sprite, "modulate", _tint, 0.25)

func _fire_ring_layer(layer: int) -> void:
	if dying or get_parent() == null:
		return
	var count: int = GameBalance.BOSS_RING_COUNT + (GameBalance.BOSS_RING_COUNT_P2 if _phase2 else 0)
	var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_RING_DMG_MULT)
	var ang_spd := 0.0
	var offset_ang := 0.0
	var spd := GameBalance.BOSS_BOLT_SPEED * bolt_speed_mult

	if layer == 1:
		ang_spd = GameBalance.BOSS_RING_CURVE_ANG   # 顺时针弧线
		offset_ang = 0.0
	elif layer == 2:
		ang_spd = -GameBalance.BOSS_RING_CURVE_ANG  # 逆时针交错弧线
		offset_ang = TAU / float(count * 2)
	elif layer == 3:
		ang_spd = 0.0                              # 直线高速穿透环
		spd = GameBalance.BOSS_BOLT_SPEED * 1.25 * bolt_speed_mult
		offset_ang = TAU / float(count * 4)

	for i in range(count):
		var ang := offset_ang + TAU * float(i) / float(count)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = spd
		bolt.damage = dmg
		bolt.scale_factor = GameBalance.BOSS_BOLT_SCALE
		bolt.angular_speed = ang_spd
		bolt.purple_style = _purple_bolts
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.65)
	GameManager.add_trauma(0.12)

# ---------------- 招式 2：扇形连射狙击 ----------------

func _cast_burst_fan(player: Node2D) -> void:
	_fan_waves_left = GameBalance.BOSS_FAN_WAVES_P2 if _phase2 else GameBalance.BOSS_FAN_WAVES
	_fan_wave_timer = 0.0
	play_squash(Vector2(1.2, 0.82), 0.3)

func _tick_burst_fan(delta: float, player: Node2D) -> void:
	if _fan_waves_left <= 0:
		return
	_fan_wave_timer -= delta
	if _fan_wave_timer <= 0.0:
		_fan_wave_timer = GameBalance.BOSS_FAN_WAVE_INTERVAL
		_fan_waves_left -= 1
		var total_waves := GameBalance.BOSS_FAN_WAVES_P2 if _phase2 else GameBalance.BOSS_FAN_WAVES
		var wave_idx := total_waves - _fan_waves_left
		var to_p: Vector2 = player.global_position - global_position
		var base_dir: Vector2 = to_p.normalized() if to_p.length_squared() > 1.0 else Vector2.RIGHT
		var count := GameBalance.BOSS_FAN_COUNT
		var spread := GameBalance.BOSS_FAN_SPREAD
		var spd := (GameBalance.BOSS_FAN_BASE_SPEED + float(wave_idx - 1) * 45.0) * bolt_speed_mult
		var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_FAN_DMG_MULT)
		for i in range(count):
			var ang_offset := (float(i) - float(count - 1) * 0.5) * spread
			var bolt := EnemyBolt.acquire(get_parent())
			bolt.global_position = global_position
			bolt.direction = base_dir.rotated(ang_offset)
			bolt.speed = spd
			bolt.damage = dmg
			bolt.scale_factor = 1.3
			bolt.purple_style = _purple_bolts
			bolt.activate()
		AudioManager.play_sfx("enemy_bolt", 0.6, 1.0 + float(wave_idx) * 0.08)

# ---------------- 招式 3：螺旋风暴弹幕 ----------------

func _cast_spiral() -> void:
	_spiral_active = true
	_spiral_timer = GameBalance.BOSS_SPIRAL_DURATION
	_spiral_step_timer = 0.0
	_spiral_angle = 0.0
	play_squash(Vector2(0.85, 1.25), 0.4)
	var tw := create_tween()
	tw.tween_property(anim_sprite, "modulate", Color(1.7, 0.7, 1.9) if final_boss else Color(1.8, 0.5, 0.5), 0.25)
	tw.tween_interval(GameBalance.BOSS_SPIRAL_DURATION)
	tw.tween_property(anim_sprite, "modulate", _tint, 0.25)

func _tick_spiral(delta: float) -> void:
	_spiral_timer -= delta
	_spiral_step_timer -= delta
	_spiral_angle += GameBalance.BOSS_SPIRAL_ROT_SPEED * delta
	# 引导期间保持蓄力姿态
	_pp_target_vel = Vector2.ZERO
	velocity = Vector2.ZERO
	if _spiral_step_timer <= 0.0:
		_spiral_step_timer = GameBalance.BOSS_SPIRAL_INTERVAL
		var arms := GameBalance.BOSS_SPIRAL_ARMS_FINAL if (final_boss or _phase2) else GameBalance.BOSS_SPIRAL_ARMS
		var dmg := maxf(1.0, contact_damage * GameBalance.BOSS_SPIRAL_DMG_MULT)
		for arm in range(arms):
			var arm_ang := _spiral_angle + TAU * float(arm) / float(arms)
			var bolt := EnemyBolt.acquire(get_parent())
			bolt.global_position = global_position
			bolt.direction = Vector2(cos(arm_ang), sin(arm_ang))
			bolt.speed = GameBalance.BOSS_SPIRAL_BOLT_SPEED * bolt_speed_mult
			bolt.angular_speed = GameBalance.BOSS_SPIRAL_ANGULAR
			bolt.damage = dmg
			bolt.scale_factor = 1.2
			bolt.purple_style = _purple_bolts
			bolt.activate()
		AudioManager.play_sfx("enemy_bolt", 0.45)
	if _spiral_timer <= 0.0:
		_spiral_active = false

# ---------------- 招式 4：分裂子母弹 ----------------

func _cast_split_bomb(player: Node2D) -> void:
	var count := GameBalance.BOSS_SPLIT_BOMB_COUNT_FINAL if (final_boss or _phase2) else GameBalance.BOSS_SPLIT_BOMB_COUNT
	var to_p: Vector2 = player.global_position - global_position
	var base_dir: Vector2 = to_p.normalized() if to_p.length_squared() > 1.0 else Vector2.RIGHT
	var base_ang := base_dir.angle()
	play_squash(Vector2(0.82, 1.25), 0.3)
	_pose_burst()  # 瞬发爆发读数（渲染器后坐一态）
	AudioManager.play_sfx("enemy_fuse", 0.75)
	for i in range(count):
		var offset := (float(i) - float(count - 1) * 0.5) * 0.32
		var dir := Vector2.from_angle(base_ang + offset)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = dir
		bolt.speed = GameBalance.BOSS_SPLIT_BOMB_SPEED * bolt_speed_mult
		bolt.scale_factor = GameBalance.BOSS_SPLIT_BOMB_SCALE
		bolt.damage = maxf(1.0, contact_damage * GameBalance.BOSS_SPLIT_BOMB_DMG_MULT)
		bolt.split_timer = GameBalance.BOSS_SPLIT_BOMB_FUSE
		bolt.split_count = GameBalance.BOSS_SPLIT_BOMB_CHILD_COUNT
		bolt.split_speed = GameBalance.BOSS_SPLIT_BOMB_CHILD_SPEED * bolt_speed_mult
		bolt.split_scale = GameBalance.BOSS_SPLIT_BOMB_CHILD_SCALE
		bolt.split_damage = maxf(1.0, contact_damage * GameBalance.BOSS_SPLIT_CHILD_DMG_MULT)
		bolt.purple_style = true
		bolt.activate()
	# 齐射瞬间给一圈幽紫冲击环：读出「这一波要散成子母弹」，与分裂时子弹出膛呼应
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 44.0, GameStyle.FX_HDR_SHADOW, 0.24)

# ---------------- 招式 5：破阵冲锋 + 侧翼洒弹 ----------------

func _cast_charge(player: Node2D) -> void:
	_charge_dir = (player.global_position - global_position).normalized()
	_charge_windup = GameBalance.BOSS_CHARGE_WINDUP
	_charge_windup_total = _charge_windup
	_charge_timer = 999999.0
	charge_interval = 999999.0
	_update_charge_warning(player)
	play_squash(Vector2(1.22, 0.78), GameBalance.BOSS_CHARGE_WINDUP)
	AudioManager.play_sfx("enemy_fuse", 0.7)

func _start_charge(dir: Vector2) -> void:
	_charge_active = charge_duration
	_charge_dir = dir
	_charge_brake = 0.0
	_charge_stagger = 0.0
	_charge_hit = false
	play_squash(Vector2(0.78, 1.24), 0.2)
	JuiceEffect.spawn_step_dust(get_parent(), global_position + Vector2(0, 12), dir)
	if charge_side_bolts > 0 and get_parent() != null:
		var base_ang := dir.angle()
		var dmg := maxf(1.0, contact_damage * 0.45)
		for side in [-1.0, 1.0]:
			for i in range(charge_side_bolts):
				var bolt := EnemyBolt.acquire(get_parent())
				bolt.global_position = global_position
				bolt.direction = Vector2.from_angle(base_ang + side * PI * 0.5 + side * float(i) * 0.22)
				bolt.damage = dmg
				bolt.scale_factor = 1.2
				bolt.purple_style = _purple_bolts
				bolt.activate()
	AudioManager.play_sfx("enemy_slam", 0.85)
	GameManager.add_trauma(0.12)
	_clear_charge_warning()

func _settle_charge_recovery() -> void:
	super._settle_charge_recovery()
	if _phase2 or final_boss:
		_fire_mini_ring(8, 255.0, 1.1)
	if _chain_charges_left > 0:
		_chain_charges_left -= 1
		var p = GameManager.player
		if p != null and not dying:
			_charge_stagger = 0.0
			_charge_dir = (p.global_position - global_position).normalized()
			var gap: float = GameBalance.BOSS_CHAIN_CHARGE_GAP
			_charge_windup = gap
			_charge_windup_total = gap
			_update_charge_warning(p)
			play_squash(Vector2(1.22, 0.78), gap)
			AudioManager.play_sfx("enemy_fuse", 0.7)
			if _chain_charges_left == 0:
				charge_whiff_stagger = 0.55
	else:
		charge_whiff_stagger = 0.25

# ---------------- 招式 9：多段折返连冲 ----------------

func _cast_chain_charge(player: Node2D) -> void:
	var total_cnt: int = GameBalance.BOSS_CHAIN_CHARGE_COUNT_P2 if (_phase2 or final_boss) else GameBalance.BOSS_CHAIN_CHARGE_COUNT
	_chain_charges_left = maxi(1, total_cnt) - 1
	charge_whiff_stagger = 0.55 if _chain_charges_left == 0 else 0.0
	_cast_charge(player)

# ---------------- 招式 10：阵眼换桩瞬移 + 双环震爆 ----------------

func _cast_turret_shift(player: Node2D) -> void:
	if dying or get_parent() == null:
		return
	var center := Vector2(480.0, 270.0)
	var p_pos := player.global_position if (player != null and is_instance_valid(player)) else center
	var from_center := (p_pos - center)
	var away_dir := -from_center.normalized() if from_center.length_squared() > 1.0 else Vector2.LEFT
	var jitter := (GameManager.rng.randf() - 0.5) * 0.7
	var new_pos := center + away_dir.rotated(jitter) * GameBalance.BOSS_TURRET_TELEPORT_RADIUS
	new_pos.x = clampf(new_pos.x, 90.0, 870.0)
	new_pos.y = clampf(new_pos.y, 90.0, 450.0)

	# 1. 原位留小环弹与震波
	JuiceEffect.spawn_shockwave(get_parent(), global_position, 60.0, GameStyle.FX_HDR_GOLD if final_boss else GameStyle.BAD, 0.26)
	_fire_mini_ring(8, 200.0, 1.0)
	AudioManager.play_sfx("enemy_fuse", 0.7)

	# 2. 瞬移到新阵点
	global_position = new_pos
	JuiceEffect.spawn_shockwave(get_parent(), new_pos, 85.0, GameStyle.FX_HDR_GOLD if final_boss else GameStyle.BAD, 0.3)
	play_squash(Vector2(0.78, 1.25), 0.25)
	_pose_burst()

	# 3. 爆一圈弧线环弹
	_fire_ring_layer(1)

# ---------------- 招式 6：追踪天火连环轰炸 ----------------

func _cast_sky_fire(player: Node2D) -> void:
	_sky_fire_strikes_left = GameBalance.BOSS_SKY_FIRE_COUNT_P2 if _phase2 else GameBalance.BOSS_SKY_FIRE_COUNT
	_sky_fire_spawn_timer = 0.0
	play_squash(Vector2(0.9, 1.2), 0.3)

func _tick_sky_fires(delta: float, player: Node2D) -> void:
	if _sky_fire_strikes_left > 0:
		_sky_fire_spawn_timer -= delta
		if _sky_fire_spawn_timer <= 0.0:
			_sky_fire_spawn_timer = GameBalance.BOSS_SKY_FIRE_INTERVAL
			_sky_fire_strikes_left -= 1
			var lead: Vector2 = player.velocity * 0.18 if (player is CharacterBody2D) else Vector2.ZERO
			var strike_pos: Vector2 = player.global_position + lead
			var tg := AoeTelegraph.new()
			tg.radius = GameBalance.BOSS_SKY_FIRE_RADIUS
			tg.progress = 0.0
			get_parent().add_child(tg)
			tg.global_position = strike_pos
			_active_sky_fires.append({
				"telegraph": tg,
				"timer": GameBalance.BOSS_SKY_FIRE_WINDUP,
				"pos": strike_pos
			})
			AudioManager.play_sfx("enemy_fuse", 0.6)

	var i := 0
	while i < _active_sky_fires.size():
		var fire: Dictionary = _active_sky_fires[i]
		fire.timer -= delta
		var tg: AoeTelegraph = fire.telegraph
		if tg != null and is_instance_valid(tg):
			tg.progress = 1.0 - fire.timer / GameBalance.BOSS_SKY_FIRE_WINDUP
		if fire.timer <= 0.0:
			_resolve_single_sky_fire(fire.pos, player)
			if tg != null and is_instance_valid(tg):
				tg.queue_free()
			_active_sky_fires.remove_at(i)
		else:
			i += 1

func _resolve_single_sky_fire(pos: Vector2, player: Node2D) -> void:
	if dying or get_parent() == null:
		return
	var c := Color(0.85, 0.35, 0.95) if final_boss else GameStyle.BAD
	JuiceEffect.spawn_shockwave(get_parent(), pos, GameBalance.BOSS_SKY_FIRE_RADIUS, c)
	# 落点留焦痕（纯视觉贴花，判定已在下方结算）
	GroundDecal.spawn(get_parent(), pos, GroundDecal.Kind.SCORCH, GameBalance.BOSS_SKY_FIRE_RADIUS * 0.6)
	AudioManager.play_sfx("enemy_slam", 0.9)
	if player != null and is_instance_valid(player) and player.global_position.distance_to(pos) <= GameBalance.BOSS_SKY_FIRE_RADIUS:
		player.take_damage(maxf(1.0, contact_damage * GameBalance.BOSS_SKY_FIRE_DMG_MULT), pos)
		GameManager.trigger_screen_shockwave(player.global_position)

# ---------------- 招式 7：震地冲击（含近远派生） ----------------

func _cast_slam() -> void:
	_slam_pending = true
	_slam_timer = GameBalance.BOSS_SLAM_WINDUP
	if _slam_ring == null:
		_slam_ring = AoeTelegraph.new()
		_slam_ring.radius = GameBalance.BOSS_SLAM_RADIUS
		add_child(_slam_ring)
	_slam_ring.progress = 0.0
	_slam_ring.visible = true
	AudioManager.play_sfx("enemy_fuse", 0.7)
	play_squash(Vector2(0.82, 1.2), 0.4)

func _resolve_slam(player: Node2D = null) -> void:
	_slam_pending = false
	if _slam_ring != null:
		_slam_ring.visible = false
	if dying:
		return
	var c := Color(0.85, 0.35, 0.95) if final_boss else GameStyle.BAD
	JuiceEffect.spawn_shockwave(get_parent(), global_position, GameBalance.BOSS_SLAM_RADIUS, c)
	# 落点留震裂（纯视觉贴花，判定已在下方结算）
	GroundDecal.spawn(get_parent(), global_position, GroundDecal.Kind.CRACK, GameBalance.BOSS_SLAM_RADIUS)
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	AudioManager.play_sfx("enemy_slam", 1.1)
	if player == null:
		player = GameManager.player
	if player != null and is_instance_valid(player) and player.global_position.distance_to(global_position) <= GameBalance.BOSS_SLAM_RADIUS:
		player.take_damage(maxf(1.0, contact_damage * GameBalance.BOSS_SLAM_DMG_MULT), global_position)
		GameManager.trigger_screen_shockwave(player.global_position)
	# 二阶段或魔尊：震地炸裂顺发 12 颗外散冲击火球
	if _phase2 or final_boss:
		_fire_mini_ring(12, 280.0, 1.2)

# ---------------- 招式 8：召唤妖群 + 弹幕掩护 ----------------

func _cast_summon(player: Node2D) -> void:
	if GameManager.enemy_count < GameBalance.BOSS_SUMMON_CAP:
		var count: int = GameBalance.BOSS_SUMMON_COUNT + (1 if _phase2 else 0)
		var hp_mult := GameBalance.enemy_hp_mult(GameManager.wave_number) * GameBalance.danger_hp_mult(GameManager.danger_level)
		var dmg_mult := GameBalance.enemy_dmg_mult(GameManager.wave_number) * GameBalance.danger_dmg_mult(GameManager.danger_level)
		for i in range(count):
			var scene: PackedScene = _minion_scenes[i % _minion_scenes.size()]
			var minion := EnemyBase.acquire_or_new(scene)
			if minion == null:
				continue
			minion.reset_for_reuse()
			var ang := GameManager.rng.randf() * TAU
			minion.global_position = global_position + Vector2(cos(ang), sin(ang)) * 110.0
			minion.add_to_group("enemies")
			minion.max_hp = ceilf(minion.max_hp * hp_mult)
			minion.contact_damage = ceilf(minion.contact_damage * dmg_mult)
			minion.activate()
			get_parent().add_child(minion)
		play_squash(Vector2(1.18, 0.85), 0.25)
		AudioManager.play_sfx("wave_start", 0.7)
	# 召唤同时朝玩家打出一组掩护火球
	_fire_cover_spread(player)
	_pose_burst()  # 瞬发爆发读数（掩护齐射的渲染器后坐一态）

# ---------------- 辅助弹幕发射 ----------------

func _fire_mini_ring(count: int, spd: float, scl: float) -> void:
	if dying or get_parent() == null:
		return
	var dmg := maxf(1.0, contact_damage * 0.45)
	for i in range(count):
		var ang := TAU * float(i) / float(count)
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2(cos(ang), sin(ang))
		bolt.speed = spd * bolt_speed_mult
		bolt.damage = dmg
		bolt.scale_factor = scl
		bolt.purple_style = _purple_bolts
		bolt.activate()

func _fire_cover_spread(player: Node2D) -> void:
	if dying or get_parent() == null or player == null:
		return
	var base_dir := (player.global_position - global_position).normalized()
	var dmg := maxf(1.0, contact_damage * 0.45)
	for ang in [-0.28, 0.0, 0.28]:
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = base_dir.rotated(ang)
		bolt.speed = 260.0 * bolt_speed_mult
		bolt.damage = dmg
		bolt.scale_factor = 1.2
		bolt.purple_style = _purple_bolts
		bolt.activate()

# ---------------- 招式 11：连环禁区封锁 ----------------

func _cast_hazard_field(player: Node2D) -> void:
	_hazard_fields_left = GameBalance.BOSS_HAZARD_FIELD_COUNT_P2 if (_phase2 or final_boss) else GameBalance.BOSS_HAZARD_FIELD_COUNT
	_hazard_spawn_timer = 0.0
	play_squash(Vector2(0.9, 1.2), 0.3)
	_pose_burst()

func _tick_hazard_fields(delta: float, player: Node2D) -> void:
	if _hazard_fields_left > 0:
		_hazard_spawn_timer -= delta
		if _hazard_spawn_timer <= 0.0:
			_hazard_spawn_timer = 0.18
			_hazard_fields_left -= 1
			var total_cnt: int = GameBalance.BOSS_HAZARD_FIELD_COUNT_P2 if (_phase2 or final_boss) else GameBalance.BOSS_HAZARD_FIELD_COUNT
			var idx: int = total_cnt - _hazard_fields_left
			var p_pos := player.global_position if (player != null and is_instance_valid(player)) else global_position
			var p_vel: Vector2 = player.velocity if (player is CharacterBody2D) else Vector2.ZERO
			var offset := Vector2.ZERO
			if idx > 1:
				if p_vel.length_squared() > 100.0:
					offset = p_vel.normalized() * (60.0 * float(idx - 1)) + Vector2.from_angle(float(idx) * 2.3) * 35.0
				else:
					offset = Vector2.from_angle(float(idx) * 2.1) * (80.0 + float(idx) * 25.0)
			var target_pos := p_pos + offset
			target_pos.x = clampf(target_pos.x, 90.0, 870.0)
			target_pos.y = clampf(target_pos.y, 90.0, 450.0)

			var tg := AoeTelegraph.new()
			tg.radius = GameBalance.BOSS_HAZARD_FIELD_RADIUS
			tg.progress = 0.0
			get_parent().add_child(tg)
			tg.global_position = target_pos
			_active_hazard_fields.append({
				"telegraph": tg,
				"timer": GameBalance.BOSS_HAZARD_FIELD_WINDUP,
				"pos": target_pos
			})
			AudioManager.play_sfx("enemy_fuse", 0.6)

	var i := 0
	while i < _active_hazard_fields.size():
		var field: Dictionary = _active_hazard_fields[i]
		field.timer -= delta
		var tg: AoeTelegraph = field.get("telegraph")
		if tg != null and is_instance_valid(tg):
			tg.progress = 1.0 - field.timer / GameBalance.BOSS_HAZARD_FIELD_WINDUP
		if field.timer <= 0.0:
			_resolve_single_hazard_field(field.pos)
			if tg != null and is_instance_valid(tg):
				tg.queue_free()
			_active_hazard_fields.remove_at(i)
		else:
			i += 1

func _resolve_single_hazard_field(pos: Vector2) -> void:
	if dying or get_parent() == null:
		return
	var pool := PoisonPool.acquire(get_parent())
	pool.global_position = pos
	pool.damage = maxf(1.0, contact_damage * GameBalance.BOSS_HAZARD_FIELD_DMG_MULT)
	pool.duration = GameBalance.BOSS_HAZARD_FIELD_DURATION
	pool.scale_factor = GameBalance.BOSS_HAZARD_FIELD_RADIUS / PoisonPool.RADIUS
	pool.activate()
	pool.modulate = Color(1.55, 0.45, 0.55) if (final_boss or boss_id == "xinmo") else Color(0.35, 1.35, 0.55)
	JuiceEffect.spawn_shockwave(get_parent(), pos, GameBalance.BOSS_HAZARD_FIELD_RADIUS, GameStyle.BAD, 0.28)
	AudioManager.play_sfx("enemy_poison", 1.0, 0.85)

# ---------------- 招式 12：瞬步贴脸扇形回斩 ----------------

func _cast_blink_slash(player: Node2D) -> void:
	if dying or get_parent() == null or player == null or not is_instance_valid(player):
		return
	var p_pos := player.global_position
	var p_vel: Vector2 = player.velocity if (player is CharacterBody2D) else Vector2.ZERO
	var behind_dir: Vector2
	if p_vel.length_squared() > 100.0:
		behind_dir = -p_vel.normalized().rotated((GameManager.rng.randf() - 0.5) * 0.8)
	else:
		behind_dir = Vector2.from_angle(GameManager.rng.randf() * TAU)
	var target_pos := p_pos + behind_dir * GameBalance.BOSS_BLINK_SLASH_DIST
	target_pos.x = clampf(target_pos.x, 90.0, 870.0)
	target_pos.y = clampf(target_pos.y, 90.0, 450.0)

	JuiceEffect.spawn_shockwave(get_parent(), global_position, 50.0, GameStyle.BAD, 0.22)
	global_position = target_pos
	JuiceEffect.spawn_shockwave(get_parent(), target_pos, 60.0, GameStyle.FX_HDR_GOLD if final_boss else GameStyle.BAD, 0.25)
	AudioManager.play_sfx("enemy_slam", 0.85)
	play_squash(Vector2(1.25, 0.8), 0.2)
	_pose_burst()

	var bolts_count: int = GameBalance.BOSS_BLINK_SLASH_BOLTS_P2 if (_phase2 or final_boss) else GameBalance.BOSS_BLINK_SLASH_BOLTS
	var to_p: Vector2 = (player.global_position - global_position).normalized()
	var base_ang := to_p.angle()
	var spread: float = GameBalance.BOSS_BLINK_SLASH_SPREAD
	var spd: float = GameBalance.BOSS_BLINK_SLASH_SPEED * bolt_speed_mult
	var dmg: float = maxf(1.0, contact_damage * GameBalance.BOSS_BLINK_SLASH_DMG_MULT)
	for i in range(bolts_count):
		var ang_offset := (float(i) - float(bolts_count - 1) * 0.5) * spread
		var bolt := EnemyBolt.acquire(get_parent())
		bolt.global_position = global_position
		bolt.direction = Vector2.from_angle(base_ang + ang_offset)
		bolt.speed = spd
		bolt.damage = dmg
		bolt.scale_factor = 1.25
		bolt.sword_style = true
		bolt.purple_style = _purple_bolts
		bolt.activate()
	AudioManager.play_sfx("enemy_bolt", 0.7, 1.1)

# ---------------- 二阶段与死亡结算 ----------------

func _enter_phase2() -> void:
	_phase2 = true
	if boss_id == "xiuluo":
		_tint = Color(1.7, 0.3, 0.3)
	elif boss_id == "qianji":
		_tint = Color(0.6, 1.1, 1.4)
	elif boss_id == "wangu":
		_tint = Color(0.6, 1.5, 0.7)
	elif boss_id == "jianpo":
		_tint = Color(1.1, 1.3, 1.6)
	elif boss_id == "xinmo" or final_boss:
		_tint = Color(1.5, 0.5, 1.8)
	else:
		_tint = Color(1.4, 0.6, 0.6)
	if anim_sprite != null:
		anim_sprite.modulate = _tint

	if boss_id == "qianji":
		move_speed = 0.0
		attack_interval *= 0.8
	else:
		move_speed *= GameBalance.BOSS_PHASE2_SPEED_MULT

	_setup_patterns()
	play_squash(Vector2(1.3, 0.75), 0.35)
	GameManager.announcement_triggered.emit("◆ %s · 狂暴形态 ◆" % boss_title)
	AudioManager.play_sfx("boss_raid", 1.15)
	# 狂暴是全游戏最高光的瞬间之一，给最强档（HEAVY 自带更大创伤/顿帧/缩放，内部单发，
	# 不再叠第二处反馈 —— 「同一次事件只许一处发反馈」口径）。
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false, from_dot: bool = false, chain_tint: Color = Color(0, 0, 0, 0)) -> void:
	if dying:
		return
	# Boss 抗击退：几乎推不动，走位压力全靠技能（千机尊完全不动）
	var kb: Vector2 = Vector2.ZERO if boss_id == "qianji" else (knockback * GameBalance.BOSS_KNOCKBACK_RESIST)
	super.take_damage(amount, kb, is_crit, from_dot, chain_tint)
	if dying:
		return
	# 大比例掉血的镜头回应（2026-10-14）：Boss 挨一刀超过最大生命该比例时给一笔轻创伤，
	# 让「砍疼 Boss」这件事有回响（此前 Boss 被打几乎 silent，只有自己的招式发反馈）。
	# 冷却按 Boss 独立计时；trauma 仍受全局每秒预算闸保护，群攻刷伤不会变持续抖屏。
	# 暴击走 EnemyBase 的暴击创伤，同一事件不双发（本闸排除暴击）。
	if not from_dot and not is_crit and _heavy_hit_cd <= 0.0 and amount >= max_hp * GameBalance.BOSS_HEAVY_HIT_PCT:
		_heavy_hit_cd = GameBalance.BOSS_HEAVY_HIT_COOLDOWN
		GameManager.add_trauma(GameBalance.BOSS_HEAVY_HIT_TRAUMA)
		if not _phase2 and current_hp <= max_hp * GameBalance.boss_phase2_hp_pct(GameManager.danger_level):
			_enter_phase2()
	_hp_emit_acc += amount
	if _hp_emit_acc >= max_hp * 0.005 or _hp_emit_cd <= 0.0:
		_hp_emit_acc = 0.0
		_hp_emit_cd = 0.1
		GameManager.boss_hp_changed.emit(current_hp, max_hp, boss_title)

func _die() -> void:
	if dying:
		return
	_slam_pending = false
	_spiral_active = false
	_fan_waves_left = 0
	_sky_fire_strikes_left = 0
	_hazard_fields_left = 0
	_chain_charges_left = 0
	_clear_charge_warning()
	if _slam_ring != null:
		_slam_ring.visible = false
	for fire in _active_sky_fires:
		var tg: AoeTelegraph = fire.get("telegraph")
		if tg != null and is_instance_valid(tg):
			tg.queue_free()
	_active_sky_fires.clear()
	for field in _active_hazard_fields:
		var tg: AoeTelegraph = field.get("telegraph")
		if tg != null and is_instance_valid(tg):
			tg.queue_free()
	_active_hazard_fields.clear()

	GameManager.add_spirit_stones(GameBalance.BOSS_STONE_REWARD)
	GameManager.feedback(GameManager.FeedbackTier.HEAVY)
	# Boss 伏诛也进击杀连击音阶（低音巨物基准压半档），阶梯高位时斩杀音顺势冲顶
	AudioManager.register_kill_pitch(0.8)
	AudioManager.play_sfx("enemy_death_elite", 0.75)
	GameManager.announcement_triggered.emit("◆ %s · 已击杀 ◆" % boss_title)
	# Boss 伏诛：一局一次的屏幕级暖白脉冲，不走限流闸
	GameManager.pulse_damage_vignette(Color(1.0, 0.95, 0.78, 0.6), 0.45)
	AudioManager.set_bgm_muffle(false)
	GameManager.boss_defeated.emit(boss_title)
	super._die()

## Boss 登场凝聚成形演出（T-5.4）：
## 1. 材质切换为 dissolve.gdshader，dissolve_amount 从 1.0 (全隐) 缓动到 0.0 (凝实)；
## 2. 凝聚成形完毕时恢复 hit_flash_mat，爆发金色冲击环 + 短震屏与创伤反馈。
func play_spawn_sequence(on_complete: Callable = Callable()) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _get_dissolve_shader()
	mat.set_shader_parameter("noise_texture", _get_noise_texture())
	mat.set_shader_parameter("dissolve_amount", 1.0)
	mat.set_shader_parameter("edge_width", 0.08)
	mat.set_shader_parameter("edge_color", GameStyle.FX_HDR_GOLD)
	if procedural_view != null:
		procedural_view.material = mat
	anim_sprite.material = mat

	scale = Vector2.ONE * 0.4
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		mat.set_shader_parameter("dissolve_amount", v)
	, 1.0, 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.chain().tween_callback(func():
		if procedural_view != null and hit_flash_mat != null:
			procedural_view.material = hit_flash_mat
		anim_sprite.material = hit_flash_mat
		var parent := get_parent()
		if parent != null:
			JuiceEffect.spawn_shockwave(parent, global_position, 96.0, GameStyle.FX_HDR_GOLD, 0.35)
		GameManager.shake_camera(8.0, 0.38)
		GameManager.add_trauma(0.35)
		if on_complete.is_valid():
			on_complete.call()
	)
