class_name EnemyBase
extends CharacterBody2D

@export var max_hp: float = 18.0
@export var move_speed: float = 110.0
@export var contact_damage: float = 12.0
@export var is_elite: bool = false
@export var exp_reward: int = 1
@export var enemy_id: String = ""          ## 敌种标识（为空时自动由节点名推导）
@export var spritesheet_path: String = ""
# 移动方式：gait=步态腿帧（默认）/ hover=悬浮（单姿势图集 + apply_hover 浮沉前倾）/ slither=蠕动（apply_slither 行进波）
@export var locomotion_mode: String = "gait"
# 可选行为（0 = 关闭，场景按怪种配置）
@export var preferred_range: float = 0.0   ## >0：远程怪，保持该距离环绕游走
@export var bolt_interval: float = 0.0     ## >0：每隔 N 秒向玩家发射火球
@export var bolt_damage: float = 9.0
@export var charge_interval: float = 0.0   ## >0：每隔 N 秒（含预警+冲刺的整周期）朝玩家长扑一次
@export var charge_min_range: float = 120.0  ## 长扑需要的「跑道」下沿：比这更近不起手（旧写法写死 120² 在判定里）
@export var charge_max_range: float = 450.0  ## 长扑上沿：远了不追扑（旧写法写死 450²）
@export var charge_windup_time: float = 1.2  ## 站桩预警时长
@export var charge_duration: float = 0.8     ## 冲刺时长（位移 = move_speed × charge_speed_mul × 它）
@export var charge_speed_mul: float = 3.2    ## 冲刺倍速
@export var bite_range: float = 0.0          ## >0：贴近短扑咬的触发上沿。建议与 charge_min_range 取同值 ⇒ 两带互补、中间不留空隙
@export var bite_interval: float = 2.4       ## 短扑咬冷却（同样是整周期）
@export var bite_windup_time: float = 0.35   ## 下蹲预告时长（方向在这一帧锁死，之后不追踪玩家，否则 0.35s 躲不开）
@export var bite_duration: float = 0.22      ## 起跳时长（位移 ≈ 69px，只当"咬一口"的凑身，不当跑道冲刺）
@export var bite_speed_mul: float = 2.6      ## 起跳倍速
@export var bite_hit_radius: float = 40.0    ## 咬合判定半径（狼嘴够得到的距离）
@export var bite_damage_mul: float = 1.0     ## 咬合伤害 = contact_damage × 它（与接触伤害同一条尺子，别另起一档）
@export var explode_radius: float = 0.0    ## >0：贴近玩家 40px 后点燃 0.8s 引信自爆
@export var heal_orb_drop: int = 0         ## >0：死亡掉「残丹」回血珠而非灵石
@export var bolt_count: int = 1            ## 火球扇射数量（>1 时按 bolt_spread 扇形展开）
@export var bolt_spread: float = 0.18      ## 扇射间隔角（弧度）
@export var split_count: int = 0           ## >0：血蛹系——死亡时分裂出 N 只幼体（split_scene）
@export var split_scene: PackedScene = null
@export var buff_radius: float = 0.0       ## >0：鼓妖光环——范围内同伴获得移速加成
@export var buff_speed_mult: float = 1.35  ## 光环加速倍率
@export var spawn_minion_interval: float = 0.0  ## >0：蛛母系——每隔 N 秒产一只幼体（minion_scene）
@export var minion_scene: PackedScene = null
@export var teleport_interval: float = 0.0 ## >0：影魅系——每隔 N 秒闪现到玩家侧翼

var current_hp: float = 60.0
var knockback_velocity: Vector2 = Vector2.ZERO
var hit_stun_timer: float = 0.0   ## 受击定身硬直计时（期间暂停主动追击速度，仅随击退滑行）
var hit_stun_resist: float = 1.0  ## 受击硬直倍率（小怪 1.0，精英 0.55，Boss 0.25）
var _hit_jiggle_offset: Vector2 = Vector2.ZERO  ## 受击瞬间视觉微反冲偏移
var facing: String = "s"
var anim_base_scale: Vector2 = Vector2.ONE
var juice_scale: Vector2 = Vector2.ONE
var _bolt_timer: float = 1.2
var _charge_timer: float = 0.0
var _charge_active: float = 0.0
var _charge_dir: Vector2 = Vector2.ZERO
var _charge_windup: float = -1.0   ## >=0 表示进入冲刺预警阶段
var _charge_warning_line: Line2D = null  ## 冲刺预警线节点
var _bite_timer: float = 0.0       ## 短扑咬冷却
var _bite_windup: float = -1.0     ## >=0 表示下蹲预告中
var _bite_active: float = 0.0      ## >0 表示起跳中
var _bite_dir: Vector2 = Vector2.ZERO
var _bite_warning_line: Line2D = null
var _bite_hit: bool = false        ## 这一跳已经咬到（一次起跳只结算一口）
var _fuse: float = -1.0   ## >=0 表示引信已点燃
var _no_drop: bool = false
var _minion_timer: float = 0.0     ## 产卵计时
var _teleport_timer: float = 0.0   ## 闪现计时
var _buff_timer: float = 0.0       ## 光环脉冲计时（每 0.25s 刷新一次范围内同伴）
var _aura_speed_mult: float = 1.0  ## 被鼓妖光环覆盖时的移速加成
var _aura_until_ms: int = 0        ## 光环有效期（毫秒时间戳）

# 五行元素异常状态（灼烧/冰缓/剧毒）
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var _burn_tick: float = 0.0
var poison_timer: float = 0.0
var poison_dps: float = 0.0
var _poison_tick: float = 0.0
var chill_timer: float = 0.0
var chill_slow: float = 0.0

@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shadow_sprite: Sprite2D = get_node_or_null("Shadow") as Sprite2D
@onready var hit_flash_mat: ShaderMaterial = anim_sprite.material as ShaderMaterial

var gem_scene: PackedScene = preload("res://scenes/entities/AstralGem.tscn")
var gold_gem_tex: Texture2D = preload("res://assets/art/gem_gold.png")
var flash_tween: Tween = null
var squash_tween: Tween = null
var dying: bool = false
var procedural_view: ProceduralEnemyView = null

func _ready() -> void:
	current_hp = max_hp
	anim_base_scale = anim_sprite.scale
	if spritesheet_path != "" and ResourceLoader.exists(spritesheet_path):
		_setup_frames(spritesheet_path)
	else:
		if anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("idle"):
			anim_sprite.play("idle")

	var eid := enemy_id
	if eid.is_empty():
		eid = _deduce_enemy_id()
	_init_procedural_view(eid)

	# 妖物出生时的弹性跃出感
	juice_scale = Vector2(0.3, 0.3)
	play_squash(Vector2(1.18, 0.85), 0.22)

	# 出生缓冲：封顶 1.0 秒（仍然不是「出屏第一帧就扑」，玩家有 1 秒看清这只怪逼近）。
	# 旧写法直接取 charge_interval（4.0s），而狼移速 120px/s 从 380~480px 走到冲刺下沿
	# （120px）只要 2.2~3.0s ⇒ 冷却就绪时狼已贴脸进短咬带，冲刺条件 dist>120px 永远不满足。
	# 封顶 1.0s 而非 2.0s：v0.0.7 全局砍血后狼只有 45HP，2.0s+1.2s 预警=3.2s 站桩太长，
	# 中等火力下狼在预警期间就被打死了，活不到冲刺出手那一下。
	_charge_timer = minf(charge_interval, 1.0)
	_bite_timer = bite_interval
	_minion_timer = spawn_minion_interval
	_teleport_timer = teleport_interval

func _deduce_enemy_id() -> String:
	var n := name.to_lower()
	if n.begins_with("boss"):
		return "boss"
	elif n.begins_with("chilei"):
		return "chilei_elite"
	elif n.begins_with("jiansha"):
		return "jiansha_elite"
	elif n.begins_with("golem"):
		return "golem"
	elif n.begins_with("slime"):
		return "slime"
	elif n.begins_with("flower"):
		return "flower"
	elif n.begins_with("leibeast"):
		return "leibeast"
	elif n.begins_with("xiexiu"):
		return "xiexiu"
	elif n.begins_with("danbao"):
		return "danbao"
	elif n.begins_with("fengqun"):
		return "fengqun"
	elif n.begins_with("xueyong"):
		return "xueyong"
	elif n.begins_with("guyao"):
		return "guyao"
	elif n.begins_with("yingmei"):
		return "yingmei"
	elif n.begins_with("zhumu"):
		return "zhumu"
	return "slime"

func _init_procedural_view(eid: String) -> void:
	if procedural_view != null:
		procedural_view.queue_free()
	procedural_view = ProceduralEnemyView.new()
	var is_boss_enemy: bool = (eid == "boss" or self.get("final_boss") != null)
	var is_final: bool = bool(self.get("final_boss")) if self.get("final_boss") != null else false
	procedural_view.setup(eid, is_elite, is_boss_enemy, is_final)
	if anim_sprite != null:
		anim_sprite.visible = false
		procedural_view.position = anim_sprite.position
		procedural_view.scale = anim_sprite.scale
		if hit_flash_mat != null:
			procedural_view.material = hit_flash_mat
	add_child(procedural_view)

## 同种敌人的帧集合逐字节相同，按「贴图路径|是否精英」缓存：
## 原先每只敌人在 _ready 里新建一套 SpriteFrames + 8 方向 ×6 帧 AtlasTexture，
## 是长局里最大的一块分配压力（比 instantiate/free 节点本身贵得多）。
## 共享后 SpriteFrames 只读，节点级状态（scale/modulate/position/frame）互不影响。
static var _frames_cache: Dictionary = {}

## 释放共享帧缓存（退出时调用）。缓存是刻意常驻的，但不主动放开引用会被
## Godot 报成 "resources still in use at exit"，让退出日志一片假警报。
static func clear_frame_cache() -> void:
	_frames_cache.clear()

## 当前缓存的帧集合数量（调试/自动化验证用）
static func cache_size() -> int:
	return _frames_cache.size()

static func _cell_tex(tex: Texture2D, col: int, row: int) -> AtlasTexture:
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * 192, row * 192, 192, 192)
	return at

## 取（或首次构建）某种怪共享的 SpriteFrames
static func _shared_frames(path: String, elite: bool) -> SpriteFrames:
	var key := "%s|%s" % [path, elite]
	if _frames_cache.has(key):
		return _frames_cache[key]
	var tex = load(path) as Texture2D
	if tex == null:
		return null
	var sf := SpriteFrames.new()
	for dir in RunMotion.DIR_ROW:
		var row: int = RunMotion.DIR_ROW[dir]
		sf.add_animation("idle_" + dir)
		sf.set_animation_speed("idle_" + dir, 1.0)
		sf.set_animation_loop("idle_" + dir, true)
		sf.add_frame("idle_" + dir, _cell_tex(tex, 0, row))

		sf.add_animation("run_" + dir)
		sf.set_animation_speed("run_" + dir, 10.0 if not elite else 8.5)
		sf.set_animation_loop("run_" + dir, true)
		for c in range(1, 5):
			sf.add_frame("run_" + dir, _cell_tex(tex, c, row))
	_frames_cache[key] = sf
	return sf

func _setup_frames(path: String) -> void:
	var sf := _shared_frames(path, is_elite)
	if sf == null:
		return
	anim_sprite.sprite_frames = sf
	anim_sprite.play("run_s")

## 挤压与拉伸形变回弹（Squash & Stretch）
func play_squash(target: Vector2, duration: float = 0.16) -> void:
	if squash_tween != null and squash_tween.is_valid():
		squash_tween.kill()
	juice_scale = target
	squash_tween = create_tween()
	squash_tween.tween_property(self, "juice_scale", Vector2.ONE, duration)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or dying:
		return

	var player = GameManager.player
	if player == null:
		return

	# 0. 五行元素异常状态结算（灼烧/剧毒/冰缓）
	if burn_timer > 0.0:
		burn_timer -= delta
		_burn_tick += delta
		if _burn_tick >= GameBalance.DOT_TICK_INTERVAL:
			_burn_tick = 0.0
			var b_dmg := GameBalance.burn_tick_damage(burn_dps, GameManager.elemental_damage, GameManager.synergy_burn_mult)
			take_damage(b_dmg, Vector2.ZERO, false, true)
			if dying:
				return
		if burn_timer <= 0.0:
			burn_dps = 0.0
	if poison_timer > 0.0:
		poison_timer -= delta
		_poison_tick += delta
		if _poison_tick >= GameBalance.DOT_TICK_INTERVAL:
			_poison_tick = 0.0
			var p_dmg := GameBalance.poison_tick_damage(poison_dps, GameManager.elemental_damage)
			take_damage(p_dmg, Vector2.ZERO, false, true)
			if dying:
				return
		if poison_timer <= 0.0:
			poison_dps = 0.0
	var eff_speed: float = move_speed
	if chill_timer > 0.0:
		chill_timer -= delta
		eff_speed = move_speed * (1.0 - chill_slow)
		if _fuse < 0.0:
			anim_sprite.modulate = Color(0.68, 0.88, 1.05)
		if chill_timer <= 0.0:
			chill_slow = 0.0
			if _fuse < 0.0:
				anim_sprite.modulate = Color.WHITE
	# 鼓妖光环：被覆盖期间加速，过期待遇自动失效
	if _aura_speed_mult != 1.0 and Time.get_ticks_msec() > _aura_until_ms:
		_aura_speed_mult = 1.0
	eff_speed *= _aura_speed_mult

	# 1. 击退速度指数衰减与受击硬直定身
	var is_in_hit_stun := hit_stun_timer > 0.0
	if is_in_hit_stun:
		hit_stun_timer -= delta

	# 硬直期间衰减略微平缓保留滑行手感，硬直结束后快速收尾
	var decay_rate := 9.0 if is_in_hit_stun else 14.0
	if knockback_velocity.length_squared() > 10.0:
		knockback_velocity = knockback_velocity.lerp(Vector2.ZERO, minf(delta * decay_rate, 1.0))
	else:
		knockback_velocity = Vector2.ZERO

	# 2. 追击玩家（平滑加速度 + 贴身防旋转抽搐）
	var to_player: Vector2 = player.global_position - global_position
	var dist_sq: float = to_player.length_squared()
	var dir: Vector2 = to_player.normalized() if dist_sq > 0.0001 else Vector2.ZERO

	# 引入轻微加减速平滑，消除突然转向时的身躯瞬间硬切；
	# 受击硬直（hit-stun）期间主动追击速度归零，位移纯由击退速度主导，呈现土豆兄弟式的受击定身与推开感
	var target_vel := Vector2.ZERO if is_in_hit_stun else (dir * eff_speed)

	# 远程怪：保持距离，近了退、远了进、合适距离环绕游走
	if not is_in_hit_stun and preferred_range > 0.0:
		var dist := sqrt(dist_sq)
		if dist < preferred_range - 30.0:
			target_vel = -dir * eff_speed * 0.8
		elif dist <= preferred_range + 30.0:
			target_vel = Vector2(-dir.y, dir.x) * eff_speed * 0.5

	# 妖狼系的两套扑击（共用同一个移动出口 target_vel，靠 elif 链天然互斥）：
	#   长扑 = 跑道够（charge_min_range ~ charge_max_range）→ 站桩预警 → 直线冲刺
	#   短咬 = 贴进 charge_min_range 以内 → 下蹲预告（方向当帧锁死、之后不追踪）→ 小幅跃击咬一口
	# 旧版只有长扑，且触发带下沿写死 120px：贴着脸它整个技能就不出手，只剩毫无预告的
	# 接触伤害一路蹭（2026-10-08 用户现场：「近距离一直追着我、远距离才扑」）。
	# 两带以 charge_min_range 为界互补 ⇒ 任何距离都有一个看得见预告的威胁。
	if charge_interval > 0.0 or bite_range > 0.0:
		_charge_timer -= delta
		_bite_timer -= delta
		var min_sq: float = charge_min_range * charge_min_range
		var max_sq: float = charge_max_range * charge_max_range
		
		# 预警阶段：原地不动，画预警线
		if _charge_windup > 0.0:
			_charge_windup -= delta
			target_vel = Vector2.ZERO
			_update_charge_warning(player)
			if _charge_windup <= 0.0:
				# 预警期间玩家贴进了「没跑道」的距离 ⇒ 就地转成短咬：它已经站桩预警了
				# 1.2s、玩家看得很清楚，所以不再补一次下蹲预告，直接跳。
				# 旧写法不复查距离，症状是「都贴脸了还往前冲 300px、从玩家身上碾过去」
				if bite_range > 0.0 and dist_sq < min_sq:
					_clear_charge_warning()
					_launch_bite(dir)
				else:
					_start_charge(dir)
		
		# 冲刺阶段
		elif _charge_active > 0.0:
			_charge_active -= delta
			target_vel = _charge_dir * move_speed * charge_speed_mul
			_clear_charge_warning()
		
		# 短咬：下蹲预告。方向在锁死那一帧定、之后不追踪玩家（0.35s 还追踪就躲不开了）
		elif _bite_windup > 0.0:
			_bite_windup -= delta
			target_vel = Vector2.ZERO
			if _bite_windup <= 0.0:
				_launch_bite(_bite_dir)

		# 短咬：起跳。一次起跳只结算一口，伤害与接触伤害同一把尺子（走玩家那套无敌帧，
		# 所以贴着它被蹭到的那一下不会和这一口叠加）
		elif _bite_active > 0.0:
			_bite_active -= delta
			target_vel = _bite_dir * move_speed * bite_speed_mul
			if not _bite_hit and dist_sq < bite_hit_radius * bite_hit_radius:
				_bite_hit = true
				player.take_damage(contact_damage * bite_damage_mul)
				# 不在这里再发一次反馈：player.take_damage 已经按「玩家受创」这个节点给过
				# 大创伤 + 顿帧 + 红晕，两边都发就是同一下挨打震两回
			if _bite_active <= 0.0:
				_clear_bite_warning()

		# 空闲：冷却到 + 跑道够 → 长扑预警
		elif charge_interval > 0.0 and _charge_timer <= 0.0 and dist_sq > min_sq and dist_sq < max_sq:
			_charge_timer = charge_interval
			_charge_windup = charge_windup_time

		# 空闲：冷却到 + 玩家已贴进 bite_range → 短咬下蹲
		# （bite_range 与 charge_min_range 取同值 ⇒ 两带互补，中间不留"谁都不出手"的缝）
		elif bite_range > 0.0 and _bite_timer <= 0.0 and dist_sq > 16.0 and dist_sq <= bite_range * bite_range:
			_bite_timer = bite_interval
			_bite_windup = bite_windup_time
			_bite_dir = dir
			_show_bite_warning(dir)
			play_squash(Vector2(1.24, 0.76), bite_windup_time)
			AudioManager.play_sfx("sword_swing", 0.55, GameManager.rng.randf_range(0.92, 1.08))

	# 丹爆傀儡：贴近点燃引信，原地颤抖后自爆
	if explode_radius > 0.0:
		if _fuse < 0.0:
			if dist_sq < 1600.0:
				_fuse = 0.8
				anim_sprite.modulate = Color(2.2, 0.9, 0.6)
				play_squash(Vector2(1.2, 0.82), 0.3)
				AudioManager.play_sfx("orb_hit", 1.3)
		else:
			_fuse -= delta
			target_vel = Vector2.ZERO
			anim_sprite.position.x = randf_range(-1.6, 1.6)
			if _fuse <= 0.0:
				anim_sprite.position.x = 0.0
				_explode(player)
				return

	# 御剑邪修：保持距离的同时周期性发射火球
	if bolt_interval > 0.0 and _fuse < 0.0:
		_bolt_timer -= delta
		if _bolt_timer <= 0.0 and dist_sq < 396900.0:
			_bolt_timer = bolt_interval
			_fire_bolt(player)

	# 蛛母系：周期性产卵（受同屏上限约束，不冲破刷怪口的上限）
	if spawn_minion_interval > 0.0 and minion_scene != null and _fuse < 0.0:
		_minion_timer -= delta
		if _minion_timer <= 0.0:
			_minion_timer = spawn_minion_interval
			if get_tree().get_nodes_in_group("enemies").size() < 45:
				_spawn_minion()

	# 鼓妖光环：每 0.25s 给范围内同伴刷新一次加速
	if buff_radius > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_buff_timer = 0.25
			_pulse_buff_aura()

	# 影魅系：周期性闪现到玩家侧翼（自爆引信点燃时不闪现，避免爆点漂移）
	if teleport_interval > 0.0 and _fuse < 0.0:
		_teleport_timer -= delta
		if _teleport_timer <= 0.0:
			_teleport_timer = teleport_interval
			_teleport_near_player(player)

	if is_in_hit_stun and _charge_active <= 0.0 and _bite_active <= 0.0:
		velocity = knockback_velocity
	else:
		velocity = velocity.move_toward(target_vel, 900.0 * delta) + knockback_velocity
	move_and_slide()

	# 界碑拦阻
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	# 受击视觉微反冲回弹（非自爆抖动期间生效）
	if _hit_jiggle_offset.length_squared() > 0.01:
		_hit_jiggle_offset = _hit_jiggle_offset.lerp(Vector2.ZERO, minf(delta * 24.0, 1.0))
	else:
		_hit_jiggle_offset = Vector2.ZERO
	if _fuse < 0.0:
		anim_sprite.position = _hit_jiggle_offset

	# 3. Sprite 方向 & 动画（带迟滞滤波 + 贴近锁定 + 移速步频自适应）
	# 当怪物与玩家极度贴近（小于 18px）时锁定原有朝向，避免围绕玩家中心旋转时的抽风风扇效应
	if dist_sq > 324.0 and dir.length_squared() > 0.01:
		var face: Array = RunMotion.facing_stable(dir, facing, anim_sprite.flip_h, 32.0)
		if face[0] != "":
			facing = face[0]
			anim_sprite.flip_h = face[1]

	var current_base := anim_base_scale * juice_scale
	var current_speed := velocity.length()
	var speed_ratio: float = (current_speed / move_speed) if move_speed > 0.0 else 1.0
	# 实际位移足够才播跑步动画：远程怪环绕游走/贴身减速时不再原地空踏步（滑行悬浮感来源）
	var is_moving := current_speed > maxf(20.0, move_speed * 0.2)

	if locomotion_mode == "hover":
		# 悬浮：不切腿帧（单姿势图集），浮沉/侧倾/纵向意图由程序驱动。
		# 侧倾喂**实际位移方向**而不是「面向玩家」的方向：邪修这类带 preferred_range 的
		# 远程怪会后退放风筝，用面向方向 bank 的话，逼近与后撤倾同一个方向，玩家分不清
		#（2026-10-09 用户现场：「踩着黑雾的为什么背对着走向我」——它其实在往后撤）。
		# advance = 位移与面向的夹角余弦：+1 压过来 / -1 后撤 / ≈0 环绕侧滑。
		# 受击定身期间归零：那一拍已有 play_squash + 微反冲在发反馈，不叠第二处。
		var vel_dir := Vector2.ZERO
		if is_moving and current_speed > 0.01:
			vel_dir = velocity / current_speed
		var advance := 0.0
		if not is_in_hit_stun:
			advance = vel_dir.dot(dir)
		RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
		RunMotion.apply_hover(anim_sprite, current_base, is_moving, vel_dir, delta, speed_ratio, shadow_sprite, advance)
	elif locomotion_mode == "slither":
		# 蠕动：贴地行进波（scale 伸缩），无悬浮无前倾
		RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
		RunMotion.apply_slither(anim_sprite, current_base, is_moving, delta, speed_ratio, shadow_sprite)
	elif anim_sprite.sprite_frames != null and anim_sprite.sprite_frames.has_animation("run_" + facing):
		if is_moving:
			var run_anim: String = "run_" + facing
			RunMotion.select_anim(anim_sprite, run_anim, true)
			RunMotion.apply(anim_sprite, current_base, true, anim_sprite.flip_h, absf(dir.x), delta, speed_ratio, 0.0, shadow_sprite)
		else:
			RunMotion.select_anim(anim_sprite, "idle_" + facing, false)
			RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta, 1.0, 0.0, shadow_sprite)
	else:
		RunMotion.apply(anim_sprite, current_base, false, anim_sprite.flip_h, 0.0, delta)

	# 3.5 同步程序化矢量视图
	if procedural_view != null:
		procedural_view.facing = facing
		procedural_view.flip_h = anim_sprite.flip_h
		procedural_view.scale = anim_sprite.scale
		procedural_view.modulate = anim_sprite.modulate
		procedural_view.is_moving = is_moving
		procedural_view.speed_ratio = speed_ratio
		if locomotion_mode == "hover":
			var vel_dir := Vector2.ZERO
			if is_moving and current_speed > 0.01:
				vel_dir = velocity / current_speed
			procedural_view.bank_angle = deg_to_rad(vel_dir.x * 6.5)
			if not is_in_hit_stun:
				procedural_view.advance = vel_dir.dot(dir)
		if _fuse >= 0.0:
			procedural_view.special_state = 1.0
		elif _charge_windup >= 0.0 or _bite_windup >= 0.0:
			procedural_view.special_state = 1.0
		else:
			procedural_view.special_state = 0.0

		# 4. 玩家接触伤害判定
	for i in range(get_slide_collision_count()):
		var col = get_slide_collision(i)
		var collider = col.get_collider()
		if collider is Player:
			var hp_before: float = collider.current_health
			collider.take_damage(contact_damage)
			# 石岳反震：实际被打中才反弹（闪避/无敌帧不触发）
			if GameManager.thorns_pct > 0.0 and collider.current_health < hp_before:
				take_damage(contact_damage * GameManager.thorns_pct, Vector2.ZERO, false)

func take_damage(amount: float, knockback: Vector2, is_crit: bool = false, from_dot: bool = false) -> void:
	if dying:
		return
	current_hp -= amount
	var elite_scale: float = 0.55 if is_elite else 1.0
	knockback_velocity = knockback * elite_scale * GameManager.synergy_knockback_mult

	# 土豆兄弟风格受击硬直定身（hit-stun）：
	# 受击瞬间暂停主动 AI 追击速度，由纯击退冲量主导位移；DoT tick 不触发硬直以保手感纯粹
	if not from_dot:
		var base_stun: float = 0.14 if is_crit else 0.075
		hit_stun_timer = maxf(hit_stun_timer, base_stun * elite_scale * hit_stun_resist)

	# 1. 声音与跳字
	# DoT tick（灼烧/剧毒）每 0.5s × N 敌各播一声 enemy_hit 会糊成一片爆响，故 tick 走静音路径，只留跳字/视觉反馈。
	if is_crit:
		if not from_dot:
			AudioManager.play_sfx("enemy_hit", 1.35, randf_range(1.16, 1.32))
		# 暴击给顿帧不给震屏：命中是本作最高频的事件，一旦发创伤，镜头整局都停不下来。
		# 只有打在精英/首领身上的暴击才值得抖一下（低频，且是「打狠了」的读数）
		GameManager.hit_stop(0.035, 0.08)
		if is_elite:
			GameManager.add_trauma(0.12)
	elif not from_dot:
		var pitch: float = randf_range(0.94, 1.08) if not is_elite else 0.85
		AudioManager.play_sfx("enemy_hit", 1.05 if not is_elite else 0.85, pitch)

	DamageNumber.spawn(get_parent(), global_position, int(amount), is_crit)

	# 2. 受击定向火花与定向挤压形变
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, knockback, is_crit)
	var squash_target := _calculate_hit_squash(knockback, is_crit)
	play_squash(squash_target, 0.16)

	# 受击微反冲视觉位移（Jiggle Recoil）：受击当帧精灵向击退方向微颤
	if not from_dot and knockback.length_squared() > 10.0:
		_hit_jiggle_offset = knockback.normalized() * (3.6 if is_crit else 2.2)

	# 3. 闪白 Shader
	if hit_flash_mat != null:
		if flash_tween != null and flash_tween.is_valid():
			flash_tween.kill()
		flash_tween = create_tween()
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 1.0, 0.025)
		flash_tween.tween_property(hit_flash_mat, ^"shader_parameter/flash_modifier", 0.0, 0.10)

	if current_hp <= 0.0:
		_die()

## 根据受击方向计算定向挤压形变
func _calculate_hit_squash(knockback: Vector2, is_crit: bool) -> Vector2:
	if knockback.length_squared() < 10.0:
		return Vector2(1.36, 0.70) if is_crit else Vector2(1.24, 0.80)
	var k_norm := knockback.normalized()
	if absf(k_norm.x) >= absf(k_norm.y):
		# 水平冲击为主：水平压扁、竖直拉伸
		return Vector2(0.68, 1.38) if is_crit else Vector2(0.76, 1.26)
	else:
		# 垂直冲击为主：竖直压扁、水平拉伸
		return Vector2(1.38, 0.68) if is_crit else Vector2(1.26, 0.76)

## 施加【离火灼烧】：按秒持续扣血，受离火羁绊与元素伤害增伤，多源叠加共鸣
func apply_burn(dps: float, duration: float) -> void:
	if dying:
		return
	var active_dps: float = burn_dps if burn_timer > 0.0 else 0.0
	burn_dps = GameBalance.stack_burn_dps(active_dps, dps)
	burn_timer = maxf(burn_timer, duration)

## 施加【玄水冰缓】：降低移动速度并附加冰蓝色温
func apply_chill(slow_pct: float, duration: float) -> void:
	if dying:
		return
	chill_slow = maxf(chill_slow, clampf(slow_pct, 0.1, 0.7))
	chill_timer = maxf(chill_timer, duration)

## 施加【青木剧毒】：持续毒素侵蚀，受元素伤害增伤
func apply_poison(dps: float, duration: float) -> void:
	if dying:
		return
	var active_dps: float = poison_dps if poison_timer > 0.0 else 0.0
	poison_dps = GameBalance.stack_poison_dps(active_dps, dps)
	poison_timer = maxf(poison_timer, duration)

## 自爆结算：范围内伤玩家，不掉落、不计击杀奖励
func _explode(player: Node2D) -> void:
	if dying:
		return
	JuiceEffect.spawn_death_burst(get_parent(), global_position, true)
	GameManager.feedback(GameManager.FeedbackTier.MEDIUM)
	AudioManager.play_sfx("enemy_death_elite", 0.9)
	if player.global_position.distance_to(global_position) <= explode_radius:
		player.take_damage(contact_damage * 2.0)
	_no_drop = true
	_die()

## 开始冲刺（预警结束后调用）
func _start_charge(dir: Vector2) -> void:
	_charge_active = charge_duration
	_charge_dir = dir
	play_squash(Vector2(0.78, 1.24), 0.2)
	_clear_charge_warning()

## 更新冲刺预警线（预警期间每帧调用）
func _update_charge_warning(player: Node2D) -> void:
	if _charge_warning_line == null:
		_charge_warning_line = Line2D.new()
		_charge_warning_line.width = 3.0
		_charge_warning_line.default_color = Color(1.0, 0.4, 0.2, 0.6)
		add_child(_charge_warning_line)
	
	# 更新端点：画「真撞得到的那一段」，不是画到玩家身上。
	# 旧写法线恒等于当前距离，玩家站在 450px 时线长 450、而冲刺只有 ~307px
	# ⇒ 预告虚报 143px（看得见的那条线必须就是它真能撞到的范围）
	_charge_warning_line.clear_points()
	_charge_warning_line.add_point(Vector2.ZERO)
	var local_target: Vector2 = player.global_position - global_position
	var reach: float = charge_duration * move_speed * charge_speed_mul
	if local_target.length() > reach:
		local_target = local_target.normalized() * reach
	_charge_warning_line.add_point(local_target)
	
	# 闪烁效果：alpha 在 0.3~0.8 之间正弦波动
	var alpha: float = 0.55 + 0.25 * sin(_charge_windup * 12.0)
	_charge_warning_line.default_color.a = alpha

## 清理预警线
func _clear_charge_warning() -> void:
	if _charge_warning_line != null:
		_charge_warning_line.queue_free()
		_charge_warning_line = null

## 短咬起跳（下蹲预告结束、或长扑预警中被玩家贴掉跑道时调用）
func _launch_bite(dir: Vector2) -> void:
	_bite_active = bite_duration
	_bite_dir = dir
	_bite_hit = false
	play_squash(Vector2(0.72, 1.3), 0.18)
	AudioManager.play_sfx("sword_swing", 0.8, GameManager.rng.randf_range(0.92, 1.08))

## 画短咬预告线：长度 = 这一跳真跳得出去的位移（bite_hit_radius 是终点附近的咬合半径，
## 不另画圈 —— 判定就落在看得见这条线的落点上，"特效范围 = 判定范围"）
func _show_bite_warning(dir: Vector2) -> void:
	_clear_bite_warning()
	if dir.length_squared() < 0.01:
		return
	_bite_warning_line = Line2D.new()
	_bite_warning_line.width = 5.0
	_bite_warning_line.default_color = Color(1.0, 0.72, 0.15, 0.8)
	add_child(_bite_warning_line)
	_bite_warning_line.add_point(Vector2.ZERO)
	_bite_warning_line.add_point(dir * (bite_duration * move_speed * bite_speed_mul))

## 清理短咬预告线（一次起跳只画一条，落点即结束）
func _clear_bite_warning() -> void:
	if _bite_warning_line != null:
		_bite_warning_line.queue_free()
		_bite_warning_line = null

## 发射火球（御剑邪修；bolt_count>1 时按 bolt_spread 扇形展开，剑煞邪修三连击）
func _fire_bolt(player: Node2D) -> void:
	var base_dir: Vector2 = (player.global_position - global_position).normalized()
	for i in range(maxi(1, bolt_count)):
		var bolt := EnemyBolt.new()
		bolt.global_position = global_position
		var offset_ang := 0.0
		if bolt_count > 1:
			offset_ang = (float(i) - float(bolt_count - 1) * 0.5) * bolt_spread
		bolt.direction = base_dir.rotated(offset_ang)
		bolt.damage = bolt_damage * (contact_damage / 13.0)  # 随波次缩放比例与接触伤害一致（基准取邪修基础值 13）
		get_parent().add_child(bolt)
	play_squash(Vector2(1.16, 0.84), 0.16)
	AudioManager.play_sfx("blade_shoot", 0.6)

## 鼓妖光环：范围内同伴获得短时加速（0.4s 有效期，光环脉冲每 0.25s 续期）
func _pulse_buff_aura() -> void:
	var radius_sq := buff_radius * buff_radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or not (e is EnemyBase) or e.dying:
			continue
		if global_position.distance_squared_to(e.global_position) <= radius_sq:
			e.receive_aura(buff_speed_mult, 400)

## 被鼓妖光环覆盖：取最高倍率，过期待遇由 _physics_process 自动清除
func receive_aura(mult: float, duration_ms: int) -> void:
	if dying:
		return
	_aura_speed_mult = maxf(_aura_speed_mult, mult)
	_aura_until_ms = Time.get_ticks_msec() + duration_ms

## 蛛母产卵：幼体在自身周围落点，血量/伤害按当前波次同公式缩放（与 WaveSpawner._scale_to_wave 同一把尺子）
func _spawn_minion() -> void:
	var m := minion_scene.instantiate() as EnemyBase
	if m == null:
		return
	var angle := GameManager.rng.randf() * TAU
	m.global_position = global_position + Vector2(cos(angle), sin(angle)) * 34.0
	m.max_hp = ceilf(m.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number))
	m.contact_damage = ceilf(m.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number))
	m.add_to_group("enemies")
	get_parent().call_deferred("add_child", m)
	play_squash(Vector2(1.22, 0.78), 0.2)
	AudioManager.play_sfx("enemy_death", 0.5, 1.3)

## 影魅闪现：瞬移到玩家侧翼 210px 处（落点受界碑约束），原地留一簇火花当残影
func _teleport_near_player(player: Node2D) -> void:
	JuiceEffect.spawn_hit_sparks(get_parent(), global_position, Vector2.UP, false)
	var angle := GameManager.rng.randf() * TAU
	var pos: Vector2 = player.global_position + Vector2(cos(angle), sin(angle)) * 210.0
	var lim: float = GameManager.MAP_HALF_EXTENT - 40.0
	global_position = pos.clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	play_squash(Vector2(1.3, 0.7), 0.2)
	AudioManager.play_sfx("dodge", 0.7, 0.8)

## 血蛹分裂：死亡时裂出 N 只幼体（幼体按当前波次缩放；自爆/消散不触发）
func _split_offspring() -> void:
	for i in range(split_count):
		var child := split_scene.instantiate() as EnemyBase
		if child == null:
			continue
		var angle := TAU * float(i) / float(split_count) + GameManager.rng.randf() * 0.5
		child.global_position = global_position + Vector2(cos(angle), sin(angle)) * 26.0
		child.max_hp = ceilf(child.max_hp * GameBalance.enemy_hp_mult(GameManager.wave_number))
		child.contact_damage = ceilf(child.contact_damage * GameBalance.enemy_dmg_mult(GameManager.wave_number))
		child.add_to_group("enemies")
		get_parent().call_deferred("add_child", child)

## 波次结束时的消散：不掉落、不计数
func dissolve() -> void:
	if dying:
		return
	dying = true
	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.4)
	tw.tween_property(anim_sprite, "scale", anim_sprite.scale * 0.6, 0.4)
	if procedural_view != null:
		tw.tween_property(procedural_view, "modulate:a", 0.0, 0.4)
		tw.tween_property(procedural_view, "scale", procedural_view.scale * 0.6, 0.4)
	tw.chain().tween_callback(queue_free)

func _die() -> void:
	if dying:
		return
	dying = true
	GameManager.register_kill(is_elite)

	# 血蛹系：临死分裂出幼体（自爆/波末消散不触发）
	if split_count > 0 and split_scene != null and not _no_drop:
		_split_offspring()

	# 清理预警线（如果存在）
	_clear_charge_warning()
	_clear_bite_warning()

	# 击杀视觉爆散与分级震屏
	JuiceEffect.spawn_death_burst(get_parent(), global_position, is_elite)
	if is_elite:
		GameManager.feedback(GameManager.FeedbackTier.LARGE)
		AudioManager.play_sfx("enemy_death_elite", 1.0)
	else:
		# 普通妖物死亡不再发创伤：尸潮里每秒十几二十次，叠起来镜头就永远摇个不停。
		# 读数交给爆散环 + 死亡音（击杀是本作最高频的反馈事件，以前它甚至是静音的）
		AudioManager.play_sfx("enemy_death", 0.85)

	var gem_count = 1 if not is_elite else 5
	if _no_drop:
		gem_count = 0
	if heal_orb_drop > 0 and gem_count > 0:
		gem_count = 0
		var orb := HealOrb.new()
		orb.global_position = global_position
		orb.heal_amount = float(heal_orb_drop)
		get_parent().call_deferred("add_child", orb)
	for i in range(gem_count):
		var gem = gem_scene.instantiate() as AstralGem
		var offset = Vector2.ZERO if gem_count == 1 else Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
		gem.global_position = global_position + offset
		gem.exp_value = exp_reward
		if is_elite:
			gem.is_gold = true
			gem.exp_value = 8
			gem.get_node("Sprite2D").texture = gold_gem_tex
			gem.get_node("PointLight2D").color = Color(1.0, 0.82, 0.35)
		get_parent().call_deferred("add_child", gem)

	set_physics_process(false)
	$CollisionShape2D.set_deferred("disabled", true)
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	if squash_tween != null and squash_tween.is_valid():
		squash_tween.kill()

		# 死灭动画：先微幅膨胀（Anticipation）再塌缩消散
		var tw = create_tween()
		tw.tween_property(anim_sprite, "scale", anim_base_scale * Vector2(1.28, 1.28), 0.045)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if procedural_view != null:
			tw.parallel().tween_property(procedural_view, "scale", anim_base_scale * Vector2(1.28, 1.28), 0.045)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.set_parallel(true)
		tw.tween_property(anim_sprite, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(anim_sprite, "modulate:a", 0.0, 0.14)
		if procedural_view != null:
			tw.tween_property(procedural_view, "scale", Vector2.ZERO, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(procedural_view, "modulate:a", 0.0, 0.14)
		tw.chain().tween_callback(queue_free)
