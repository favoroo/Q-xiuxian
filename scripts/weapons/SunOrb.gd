class_name SunOrb
extends Area2D

## 环绕灵宝（灵蝶/寒泉玉莲/混元古钟）：接触伤害走 WeaponData 定义，星级影响伤害/冷却/体型

## 环绕半径与接触判定半径：只有这两个常数说了算，贴图与碰撞一起变。
## 旧写法是 .tscn 里钉 14px 碰撞 + Player 里写死 78px 轨道 ⇒ 距玩家 49px 以内是盲区，
## 而贴到玩家身上的妖正好停在 24px 处（单武器实测台 tests/WeaponProbe.tscn：灵蝶 ★1
## 只有 19 点伤/秒，纸面是 42.9）。58 ± 18 覆盖 40..76px，再算敌人受击圈 15px ⇒ 贴身到半臂都打得到。
const ORBIT_RADIUS: float = 58.0
const MIN_ORBIT_RADIUS: float = 28.0
const CONTACT_RADIUS: float = 20.0     ## 基础接触半径提升至 20px，配合动态伸缩杜绝盲区

var star: int = 1
var drone_id: String = "lingdie"
var base_damage: float = 15.0
var hit_cooldown: float = 0.35
var current_radius: float = ORBIT_RADIUS ## 动态轨道当前平滑半径
var max_orbit_reach: float = 125.0       ## 该灵宝的外扩扑击上限

var _hit_ms: Dictionary = {}   ## 敌人 instance id → 上次命中时刻（毫秒）
var _last_gc_ms: int = 0       ## 上次清理过期条目的时刻
var _pulse_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var _base_sprite_scale: Vector2 = sprite.scale

## 由 Player.sync_drones 下发星级与法宝 id（必须在节点可用后调用）
func setup(star_level: int, weapon_id: String = "lingdie") -> void:
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	drone_id = weapon_id if not weapon_id.is_empty() else "lingdie"
	base_damage = WeaponData.damage_for(drone_id, star)
	hit_cooldown = WeaponData.cooldown_for(drone_id, star)
	var def := WeaponData.get_def(drone_id)
	max_orbit_reach = maxf(110.0, float(def.get("range", 125.0)))
	_apply_contact_radius()
	if is_inside_tree():
		_apply_star_visuals()

func _ready() -> void:
	_apply_star_visuals()

## 判定半径逐实例重建：.tscn 里的 SubResource 在同一份 PackedScene 的多个实例间是共享的，
## 直接改会把 ★1 与 ★3 的灵宝捏成同一个圆
func _apply_contact_radius() -> void:
	if collision == null:
		return
	var shape := CircleShape2D.new()
	shape.radius = CONTACT_RADIUS * (1.0 + 0.14 * float(star - 1))
	collision.shape = shape

func _apply_star_visuals() -> void:
	_apply_contact_radius()
	var def := WeaponData.get_def(drone_id)
	if def.has("icon") and ResourceLoader.exists(def["icon"]):
		sprite.texture = load(def["icon"])
	# 高星灵宝更大更金：★1 青/原色 → ★2 偏金 → ★3 金亮
	sprite.scale = _base_sprite_scale * (1.0 + 0.14 * float(star - 1))
	var tint := Color(1, 1, 1)
	if star >= 2:
		tint = Color(1.0, 0.95, 0.72) if star == 2 else Color(1.0, 0.88, 0.45)
	sprite.modulate = tint

## 接触伤害必须"贴着就持续结算"：只挂 area_entered ⇒ 进入那一帧打一下，
## 敌人挂在环上不再触发第二下，纸面 42.9 DPS 实测只有 11~19。
## 冷却按每个敌人独立计（_try_damage 里的 _hit_ms），逐帧轮询不会变成每秒 60 下。
func _physics_process(_delta: float) -> void:
	for area in get_overlapping_areas():
		_try_damage(area)

func _on_area_entered(area: Area2D) -> void:
	_try_damage(area)

func _try_damage(area: Area2D) -> void:
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		var id: int = enemy.get_instance_id()
		var now: int = Time.get_ticks_msec()
		var eff_cd: float = maxf(0.08, hit_cooldown * GameManager.attack_speed_mult * GameManager.synergy_haste_mult)
		var cd_ms: int = maxi(1, int(round(eff_cd * 1000.0)))
		if _hit_ms.has(id) and now - int(_hit_ms[id]) < cd_ms:
			return
		_hit_ms[id] = now
		if _hit_ms.size() > 48 and now - _last_gc_ms > cd_ms:
			_last_gc_ms = now
			for k in _hit_ms.keys():
				if now - int(_hit_ms[k]) >= cd_ms:
					_hit_ms.erase(k)
		var def := WeaponData.get_def(drone_id)
		var stat_bonus := GameManager.get_weapon_stat_bonus(drone_id, star)
		var total_base := base_damage + stat_bonus
		var is_crit = GameManager.rng.randf() < GameManager.get_crit_rate()
		var crit_m := GameManager.crit_mult + GameManager.synergy_crit_mult
		var dmg = total_base * GameManager.weapon_damage_mult * GameManager.synergy_damage_mult * GameManager.cultivator_damage_mult(drone_id) * GameManager.element_damage_mult(drone_id) * GameManager.elite_damage_mult_for(enemy) * (crit_m if is_crit else 1.0)
		var knock_force := WeaponData.knockback_for(drone_id, 165.0)
		var knockback = GameManager.knockback_vec(global_position, enemy.global_position, knock_force)
		enemy.take_damage(dmg, knockback, is_crit)

		if def.get("proc_burn", false) and enemy.has_method("apply_burn"):
			enemy.apply_burn(dmg * float(def.get("burn_ratio", 0.4)), float(def.get("burn_dur", 3.0)))
		if float(def.get("proc_chill", 0.0)) > 0.0 and enemy.has_method("apply_chill"):
			enemy.apply_chill(float(def.get("proc_chill")), float(def.get("chill_dur", 2.5)))
		if def.get("proc_poison", false) and enemy.has_method("apply_poison"):
			enemy.apply_poison(dmg * float(def.get("poison_ratio", 0.3)), float(def.get("poison_dur", 2.5)))

		GameManager.try_lifesteal()
		_play_hit_pulse()
		AudioManager.play_sfx(WeaponData.sfx_for(drone_id), 1.0)

## 触敌反馈：法宝扑闪一下（压扁弹回 + 亮闪）
func _play_hit_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	sprite.modulate = Color(1.7, 1.7, 1.35)
	sprite.scale = _base_sprite_scale * Vector2(1.25, 0.8) * (1.0 + 0.14 * float(star - 1))
	_pulse_tween = create_tween()
	_pulse_tween.set_parallel(true)
	_pulse_tween.tween_property(sprite, "modulate", _star_tint(), 0.16)
	_pulse_tween.tween_property(sprite, "scale", _base_sprite_scale * (1.0 + 0.14 * float(star - 1)), 0.16)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _star_tint() -> Color:
	if star >= 3:
		return Color(1.0, 0.88, 0.45)
	if star == 2:
		return Color(1.0, 0.95, 0.72)
	return Color.WHITE
