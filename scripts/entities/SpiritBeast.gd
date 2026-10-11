class_name SpiritBeast
extends CharacterBody2D

## 祭坛灵兽（2026-10-11 祭坛强化）：祭坛激活时召唤的近战追击撕咬型友军。
##
## 组与碰撞（两条铁律，动了会被全场武器追着打 / 波末被清场）：
##   - 只挂 "allies" 组 —— 绝不进 enemies/turrets/gems/chests，那四组 WaveSpawner.end_wave 全清；
##     正因为它不在那四组里，血量不耗尽就跨波次一直在场。
##   - 本体在 layer 2（player 层）：敌人身体（mask 含 player）会物理撞上它，
##     敌人的嘲讽追击与接触伤害（EnemyBase._taunt_target / _resolve_contact_damage）借此咬到它；
##     玩家武器索敌全走 mask=4（enemies 层），打不到它 —— 灵兽不会被自家法器误伤。
##
## 血量是它的寿命：受击有无敌帧（HIT_INVINCIBLE，敌人接触伤害逐帧结算，没它一秒被磨没），
## 血量耗尽即消散；没有波间回血 ——「血量没耗完就一直在场」。
## 血量不挂血条：受击时把 hp_ratio 灌给渲染器，由玄鹤本体传达（灵光/丹顶/灵目转暗、濒死裂纹闪烁）。
## 伤害吃召唤伤害乘区（engineering_damage + synergy_engineering_damage，与御灵/炮台同链路）。
## 索敌读 GameManager.live_enemies 登记表，不做物理查询（最多 3 只，10Hz 重索节流）。

var max_hp: float = 100.0
var current_hp: float = 100.0
var current_target: Node2D = null

var _wave: int = 1
var _dying: bool = false
var _attack_timer: float = 0.0
var _search_timer: float = 0.0
var _invincible_timer: float = 0.0
var _hit_flash: float = 0.0
var _face_sign: float = 1.0
var _renderer: ProceduralDroneRenderer = null

func _ready() -> void:
	add_to_group("allies")
	collision_layer = 2   # player 层（铁律见文件头，别改）
	collision_mask = 1    # 只与世界撞；不与敌人互挤（敌人自己会撞上它）
	_wave = maxi(GameManager.wave_number, 1)
	max_hp = GameBalance.spirit_beast_max_hp(_wave)
	current_hp = max_hp

	_renderer = ProceduralDroneRenderer.new()
	_renderer.kind = ProceduralDroneRenderer.DroneKind.XUAN_HE
	add_child(_renderer)

	GameManager.register_ally(self)

	# 出场弹起
	scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_attack_timer = GameManager.rng.randf_range(0.2, 0.5)
	_search_timer = GameManager.rng.randf_range(0.0, GameBalance.SPIRIT_BEAST_SEARCH_INTERVAL)

func _exit_tree() -> void:
	GameManager.unregister_ally(self)

func _physics_process(delta: float) -> void:
	if GameManager.is_game_over or _dying:
		return

	if _invincible_timer > 0.0:
		_invincible_timer -= delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
		if _hit_flash <= 0.0:
			modulate = Color.WHITE
	_attack_timer -= delta

	# 索敌节流：目标死了不当帧重查，下一节拍再找
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = GameBalance.SPIRIT_BEAST_SEARCH_INTERVAL
		if current_target == null or not is_instance_valid(current_target) or current_target.dying:
			current_target = _find_target()

	var move_dir := Vector2.ZERO
	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		var dist := to_target.length()
		if dist > 0.001:
			move_dir = to_target / dist
		if dist > GameBalance.SPIRIT_BEAST_ATTACK_RANGE:
			velocity = move_dir * GameBalance.SPIRIT_BEAST_MOVE_SPEED
		else:
			velocity = Vector2.ZERO
			_try_attack(move_dir)
	else:
		# 无敌人时巡游回玩家身边站着
		var p := GameManager.player
		if p != null and global_position.distance_to(p.global_position) > GameBalance.SPIRIT_BEAST_IDLE_FOLLOW_DIST:
			move_dir = (p.global_position - global_position).normalized()
			velocity = move_dir * GameBalance.SPIRIT_BEAST_MOVE_SPEED * 0.8
		else:
			velocity = velocity.move_toward(Vector2.ZERO, 600.0 * delta)

	move_and_slide()
	var lim: float = GameManager.MAP_HALF_EXTENT - 20.0
	global_position = global_position.clamp(Vector2(-lim, -lim), Vector2(lim, lim))

	if _renderer != null:
		# 朝向翻转带滞回：只有走向明确与当前朝向相反（反向分量 > 0.25）才翻面，
		# 竖直方向追击（move_dir.x≈0）与临界抖动都不翻
		if move_dir.x * _face_sign < -0.25:
			_face_sign = -_face_sign
		_renderer.scale.x = _face_sign
		_renderer.speed_ratio = clampf(velocity.length() / GameBalance.SPIRIT_BEAST_MOVE_SPEED, 0.0, 1.0)
		# 悬浮侧倾：按朝向系下的横向走位 bank（与悬浮怪同款 ~6.5°），镜像由 scale.x 承担
		_renderer.bank_angle = deg_to_rad(6.5) * clampf(velocity.x * _face_sign / GameBalance.SPIRIT_BEAST_MOVE_SPEED, -1.0, 1.0)

## 索敌：读 live_enemies 登记表取最近活体（含濒死未清的要跳过）
func _find_target() -> Node2D:
	var nearest: Node2D = null
	var min_dist_sq := 99999999.0
	for e in GameManager.live_enemies:
		if e == null or not is_instance_valid(e) or e.dying:
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < min_dist_sq:
			min_dist_sq = d
			nearest = e
	return nearest

## 撕咬：冷却到才出手；伤害吃召唤伤害乘区，击杀掉落等全走敌人 take_damage 那一条
func _try_attack(dir: Vector2) -> void:
	if _attack_timer > 0.0:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	_attack_timer = GameBalance.SPIRIT_BEAST_ATTACK_INTERVAL
	var dmg: float = GameBalance.spirit_beast_damage(_wave) * (1.0 + GameManager.engineering_damage + GameManager.synergy_engineering_damage)
	current_target.take_damage(dmg, dir * GameBalance.SPIRIT_BEAST_KNOCK_FORCE, false)
	# 扑咬小凑身（纯视觉，不改判定）
	if _renderer != null:
		_renderer.position = dir * 5.0
		var lunge := create_tween()
		lunge.tween_property(_renderer, "position", Vector2.ZERO, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("enemy_claw", 0.45, GameManager.rng.randf_range(0.95, 1.1))

## 受击（敌人接触/短咬/自爆的口子）：无敌帧挡逐帧接触结算，闪白 + 灵息转暗（hp_ratio 灌给渲染器）
func take_damage(amount: float) -> void:
	if _dying or _invincible_timer > 0.0:
		return
	_invincible_timer = GameBalance.SPIRIT_BEAST_HIT_INVINCIBLE
	current_hp -= amount
	_hit_flash = 0.12
	modulate = Color(1.8, 1.8, 1.8)
	if _renderer != null:
		_renderer.hp_ratio = clampf(current_hp / max_hp, 0.0, 1.0)
	if current_hp <= 0.0:
		_die()

func _die() -> void:
	_dying = true
	set_physics_process(false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	JuiceEffect.spawn_death_burst(get_parent(), global_position, false)
	AudioManager.play_sfx("enemy_death", 0.8)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)
