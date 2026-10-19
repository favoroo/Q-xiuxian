class_name SunOrb
extends Area2D

## 环绕灵宝（灵蝶/寒泉玉莲/混元古钟）：接触伤害走 WeaponData 定义，星级影响伤害/冷却/体型；
## ★2 起一具分身为二/为三（orb_count），单武器总纸面伤害不变，每具结算均摊、贴身覆盖更广

## 环绕半径与接触判定半径：只有这两个常数说了算，贴图与碰撞一起变。
## 旧写法是 .tscn 里钉 14px 碰撞 + Player 里写死 78px 轨道 ⇒ 距玩家 49px 以内是盲区，
## 而贴到玩家身上的妖正好停在 24px 处（单武器实测台 tests/WeaponProbe.tscn：灵蝶 ★1
## 只有 19 点伤/秒，纸面是 42.9）。58 ± 18 覆盖 40..76px，再算敌人受击圈 15px ⇒ 贴身到半臂都打得到。
const ORBIT_RADIUS: float = 80.0
const MIN_ORBIT_RADIUS: float = 28.0
const CONTACT_RADIUS: float = 33.0     ## 接触半径 33px：敌人受击圈 15px ⇒ 合计 ~48px 触达，弥补轨道扫掠的占空比损失（2026-10-11 用户「召唤还是弱」再放宽一档）

var star: int = 1
var drone_id: String = "lingdie"
var orb_count: int = 1          ## 所属武器的分身具数（★1/★2/★3 = 1/2/3），伤害与属性折算按具均分
var base_damage: float = 15.0
var hit_cooldown: float = 0.35
var current_radius: float = ORBIT_RADIUS ## 动态轨道当前平滑半径
var max_orbit_reach: float = 175.0       ## 该灵宝的外扩扑击上限

var _hit_ms: Dictionary = {}   ## 敌人 instance id → 上次命中时刻（毫秒）
var _last_gc_ms: int = 0       ## 上次清理过期条目的时刻
var _pulse_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var _base_sprite_scale: Vector2 = sprite.scale
var _drone_renderer: ProceduralDroneRenderer = null

## 由 Player.sync_drones 下发星级与道具 id（必须在节点可用后调用）
## orb_total：该武器分身出的灵宝具数（WeaponData.drone_orb_count）。总纸面 DPS 与单具版一致：
## 每具结算 1/N 基础与 1/N 属性折算，多具同环扫掠换更高贴身覆盖（BalanceTargeting 占空比按星抬升）。
func setup(star_level: int, weapon_id: String = "lingdie", orb_total: int = 1) -> void:
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	orb_count = maxi(1, orb_total)
	drone_id = weapon_id if not weapon_id.is_empty() else "lingdie"
	base_damage = WeaponData.damage_for(drone_id, star) / float(orb_count)
	hit_cooldown = WeaponData.cooldown_for(drone_id, star)
	var def := WeaponData.get_def(drone_id)
	max_orbit_reach = maxf(150.0, float(def.get("range", 205.0)))
	_apply_contact_radius()
	if is_inside_tree():
		_apply_star_visuals()

func _ready() -> void:
	# 错相：多枚灵宝把轮询劈到 4 个相位上，不同帧做重叠查询
	_poll_timer = float(get_instance_id() % 4) * (POLL_INTERVAL / 4.0)
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

	# 挂载纯矢量动态灵宝视觉
	if _drone_renderer == null:
		_drone_renderer = ProceduralDroneRenderer.new()
		sprite.add_child(_drone_renderer)
		sprite.self_modulate.a = 0.0
	_drone_renderer.star = star
	match drone_id:
		"hanquan_yulian":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.HANQUAN_YULIAN
		"hunyuan_zhong":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.HUNYUAN_ZHONG
		"haojin_lun":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.HAOJIN_LUN
		"lihuo_ya":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.LIHUO_YA
		"xuanwu_pei":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.XUANWU_PEI
		"jinming_ling":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.JINMING_LING
		"muling_ou":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.MULING_OU
		"bingpo_zhu":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.BINGPO_ZHU
		"chiyan_ying":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.CHIYAN_YING
		"tuling_shi":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.TULING_SHI
		"jianling":
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.JIAN_LING
		_:
			_drone_renderer.kind = ProceduralDroneRenderer.DroneKind.LINGDIE

## 接触伤害必须"贴着就持续结算"：只挂 area_entered ⇒ 进入那一帧打一下，
## 敌人挂在环上不再触发第二下，纸面 42.9 DPS 实测只有 11~19。
## 冷却按每个敌人独立计（_try_damage 里的 _hit_ms），轮询不会变成每秒 60 下。
## 轮询节流（2026-10-11 第 6 波卡顿优化）：get_overlapping_areas 15Hz + instance_id 错相，
## _on_area_entered 信号照旧即时兜住"刚贴上"的第一下；持续贴着的补刀最坏延迟 66ms，
## 而伤害独立冷却下限 80ms —— 不会漏掉任何一次本该发生的结算。
const POLL_INTERVAL := 0.066
var _poll_timer: float = 0.0
var _cached_stat_bonus: float = 0.0
var _cached_multi_mult: float = 1.0
var _dmg_cache_valid: bool = false

func _refresh_dmg_cache() -> void:
	_cached_stat_bonus = GameManager.get_weapon_stat_bonus(drone_id, star) / float(orb_count)
	_cached_multi_mult = GameManager.get_multi_weapon_damage_mult()
	_dmg_cache_valid = true

func _physics_process(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = POLL_INTERVAL
	var areas := get_overlapping_areas()
	if areas.is_empty():
		return
	_refresh_dmg_cache()
	for area in areas:
		_try_damage(area)

func _on_area_entered(area: Area2D) -> void:
	if not _dmg_cache_valid:
		_refresh_dmg_cache()
	_try_damage(area)

func _try_damage(area: Area2D) -> void:
	var enemy = area.get_parent()
	if enemy and enemy.has_method("take_damage"):
		var id: int = enemy.get_instance_id()
		var now: int = Time.get_ticks_msec()
		var eff_cd: float = maxf(0.08, hit_cooldown * GameManager.get_effective_attack_speed_mult())
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
		if not _dmg_cache_valid:
			_refresh_dmg_cache()
		var total_base := base_damage + _cached_stat_bonus
		var is_crit: bool = GameManager.roll_crit()
		var crit_m := GameManager.get_crit_mult()
		var dmg = total_base * GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult * GameManager.shadow_amp_mult * GameManager.cultivator_damage_mult(drone_id) * GameManager.element_damage_mult(drone_id) * _cached_multi_mult * GameManager.elite_damage_mult_for(enemy) * (crit_m if is_crit else 1.0)
		var knock_force := WeaponData.knockback_for(drone_id, 165.0)
		var knockback = GameManager.knockback_vec(global_position, enemy.global_position, knock_force)
		enemy.take_damage(dmg, knockback, is_crit)

		ProcStatus.apply(enemy,
			bool(def.get("proc_burn", false)), dmg * float(def.get("burn_ratio", 0.4)), float(def.get("burn_dur", 3.0)),
			float(def.get("proc_chill", 0.0)), float(def.get("chill_dur", 2.5)),
			bool(def.get("proc_poison", false)), dmg * float(def.get("poison_ratio", 0.3)), float(def.get("poison_dur", 2.5)))

		GameManager.try_lifesteal(WeaponData.Behavior.DRONE)
		_play_hit_pulse()
		AudioManager.play_sfx(WeaponData.sfx_for(drone_id), 1.0)

## 触敌反馈：道具扑闪一下（压扁弹回 + 亮闪）；0.16s 内连扫多敌不重复分配 Tween
func _play_hit_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_running():
		return
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
