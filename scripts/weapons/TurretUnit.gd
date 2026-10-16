class_name TurretUnit
extends Node2D

## 机关炮台/阵盘实体：由机关类武器（Behavior.TURRET）按冷却布设于地面
## 独立索敌、自动向射程内敌人开火，寿命结束后消散。
## 伤害吃机关伤害（contraption_damage）、机关羁绊（synergy_contraption_mult）与全套玩家乘区。

@export var weapon_def_id: String = "jiguan_nu"
@export var star: int = 1

var base_damage: float = 18.0
var fire_cooldown: float = 0.8
var attack_range: float = 220.0
var lifetime: float = 12.0
var current_target: Node2D = null

var _cooldown_timer: float = 0.0
var _lifetime_timer: float = 0.0
var _is_dying: bool = false
var _spin_angle: float = 0.0

## 索敌节流（2026-10-11，与 FloatingWeapon 同款）：intersect_shape 最多 15Hz
const TARGET_SEARCH_INTERVAL := 0.066
var _search_timer: float = 0.0

static var _search_shape: CircleShape2D = null
static var _search_query: PhysicsShapeQueryParameters2D = null

var projectile_scene: PackedScene = preload("res://scenes/weapons/BladeProjectile.tscn")

@onready var core_sprite: Sprite2D = $CoreSprite
@onready var muzzle_point: Marker2D = $CoreSprite/MuzzlePoint
@onready var base_ring: Node2D = $BaseRing

var muzzle_flash: Sprite2D = null
## 机关元素（_ready 时从 WeaponData 推导）：底座阵缘配色/形态与枪口闪光都按它分化
var _elem: String = "metal"

func setup(def_id: String, star_level: int) -> void:
	weapon_def_id = def_id
	star = clampi(star_level, 1, WeaponData.MAX_STAR)
	var def := WeaponData.get_def(def_id)
	base_damage = WeaponData.damage_for(def_id, star)
	fire_cooldown = float(def.get("turret_fire_cd", 0.8))
	attack_range = float(def.get("range", 220.0))
	lifetime = float(def.get("turret_lifetime", 12.0))
	_lifetime_timer = lifetime
	_cooldown_timer = GameManager.rng.randf_range(0.1, 0.3)
	# 错相：多台炮台把索敌查询劈散到不同帧
	_search_timer = GameManager.rng.randf_range(0.0, TARGET_SEARCH_INTERVAL)

func _ready() -> void:
	add_to_group("turrets")
	var def := WeaponData.get_def(weapon_def_id)
	_elem = WeaponData.element_of(weapon_def_id)
	if _elem == "":
		_elem = "metal"
	queue_redraw()
	if def.has("icon") and ResourceLoader.exists(def["icon"]):
		core_sprite.texture = load(def["icon"])
	# 出场微小弹起动画
	scale = Vector2(0.2, 0.2)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	# 布设：机关砸进地面那一记钝响。不许借用 orb_hit（那是灵宝触敌的暖金钟）
	AudioManager.play_sfx("impact_blunt", 0.9)
	_setup_muzzle_flash()

func _setup_muzzle_flash() -> void:
	if muzzle_point == null:
		return
	muzzle_flash = Sprite2D.new()
	var tex := load("res://assets/art/light_radial.png") as Texture2D
	if tex == null:
		return
	muzzle_flash.texture = tex
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	muzzle_flash.material = mat
	muzzle_flash.z_index = 6
	muzzle_flash.visible = false
	muzzle_point.add_child(muzzle_flash)

func _draw() -> void:
	# 冷冽几何八角机关阵盘底座：阵缘配色与形态按元素分化（2026-10-13，
	# 旧写法 10 把机关共用同一金边八角盘，喷火兽和凝冰弩摆下去长得一模一样）
	var r_outer := 18.0
	var r_inner := 13.0
	var edge_col: Color = _elem_edge_color()
	var pts_outer := PackedVector2Array()
	var pts_inner := PackedVector2Array()
	for i in range(8):
		var ang := float(i) * TAU / 8.0
		pts_outer.append(Vector2(cos(ang), sin(ang)) * r_outer)
		pts_inner.append(Vector2(cos(ang), sin(ang)) * r_inner)
	draw_colored_polygon(pts_outer, Color(0.08, 0.10, 0.14, 0.85))
	pts_outer.append(pts_outer[0])
	draw_polyline(pts_outer, edge_col, 2.0)
	pts_inner.append(pts_inner[0])
	draw_polyline(pts_inner, Color(edge_col.r, edge_col.g, edge_col.b, 0.55), 1.2)
	_draw_elem_accents(r_outer, edge_col)

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

func _process(delta: float) -> void:
	if GameManager.is_game_over:
		return
	if _is_dying:
		return

	_lifetime_timer -= delta
	_cooldown_timer -= delta
	_spin_angle += delta * 1.5

	if _lifetime_timer <= 0.0:
		dismiss()
		return

	# 寿命最后 2 秒微弱频闪提示
	if _lifetime_timer < 2.0:
		modulate.a = 0.5 + 0.5 * sin(_lifetime_timer * 16.0)

	# 索敌与瞄准：15Hz 节流（2026-10-11 第 6 波卡顿优化，照 FloatingWeapon 先例）——
	# 目标失效不再当帧立即重查，下一节拍再找；炮弹冷却远长于 66ms，火力读数无感
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = TARGET_SEARCH_INTERVAL
		if current_target == null or not is_instance_valid(current_target) or not _is_target_in_range(current_target):
			current_target = _find_target()

	if current_target != null and is_instance_valid(current_target):
		var target_angle := (current_target.global_position - global_position).angle()
		core_sprite.rotation = lerp_angle(core_sprite.rotation, target_angle, minf(delta * 12.0, 1.0))
	else:
		core_sprite.rotation = _spin_angle

	if _cooldown_timer <= 0.0 and current_target != null and is_instance_valid(current_target):
		_fire()

## 射程乘区（攻击范围词条 + 剑系/广域羁绊）：照 FloatingWeapon._range_mult 同一口径——
## 详情卡/商店卡展示的「攻击范围 = 基础 × 该乘区」，机关台实际索敌必须同源（2026-10-11 补漏：
## 旧写法用定值 attack_range，面板显示 240 实际只索 220，加点攻击范围对机关台完全不生效）
func _eff_range() -> float:
	return attack_range * GameManager.attack_range_mult * GameManager.synergy_range_mult

func _is_target_in_range(t: Node2D) -> bool:
	var eff := _eff_range()
	return global_position.distance_squared_to(t.global_position) <= eff * eff

func _find_target() -> Node2D:
	if _search_shape == null or _search_query == null:
		_search_shape = CircleShape2D.new()
		_search_query = PhysicsShapeQueryParameters2D.new()
		_search_query.shape = _search_shape
		_search_query.collision_mask = 4
		_search_query.collide_with_areas = true
	_search_shape.radius = _eff_range()
	_search_query.transform = Transform2D(0.0, global_position)
	var results := get_world_2d().direct_space_state.intersect_shape(_search_query, 24)

	var nearest: Node2D = null
	var min_dist_sq := 99999999.0
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent as Node2D
			if enemy == null or enemy.is_in_group("herbs") or enemy.is_in_group("chests"):
				continue
			var d := global_position.distance_squared_to(enemy.global_position)
			if d < min_dist_sq:
				min_dist_sq = d
				nearest = enemy
	return nearest

func _final_damage() -> float:
	var stat_bonus: float = GameManager.get_weapon_stat_bonus(weapon_def_id, star)
	var syn_contraption := float(GameManager.get("synergy_contraption_mult")) if GameManager.get("synergy_contraption_mult") != null else 1.0
	return (base_damage + stat_bonus) * GameManager.get_weapon_damage_mult() * GameManager.synergy_damage_mult * GameManager.shadow_amp_mult * syn_contraption * GameManager.cultivator_damage_mult(weapon_def_id) * GameManager.element_damage_mult(weapon_def_id) * GameManager.get_multi_weapon_damage_mult()

## 开火间隔有效值：与 FloatingWeapon/SunOrb 同口径——装备/加点层 × 羁绊层 × 疾风咒 buff 层 × 站定神像
## （漏乘 buff 层则疾风期间炮台不加速，玩家直觉与实际不符）
func _eff_fire_cd() -> float:
	var turret_haste: float = 1.0 - GameManager.item_hook_sum("turret_haste")
	return fire_cooldown * GameManager.get_effective_attack_speed_mult() * maxf(0.2, turret_haste)

func _fire() -> void:
	_cooldown_timer = maxf(0.12, _eff_fire_cd())

	var def := WeaponData.get_def(weapon_def_id)
	var aim_dir := Vector2.RIGHT.rotated(core_sprite.rotation)
	if current_target != null and is_instance_valid(current_target):
		aim_dir = (current_target.global_position - muzzle_point.global_position).normalized()

	var final_dmg := _final_damage()
	var bullet_path := String(def.get("bullet", "res://assets/art/bullet_gold_needle.png"))
	var bullet_tex: Texture2D = null
	if ResourceLoader.exists(bullet_path):
		bullet_tex = load(bullet_path) as Texture2D

	var p := BladeProjectile.acquire_or_new(projectile_scene, get_tree().current_scene)
	p.global_position = muzzle_point.global_position
	p.direction = aim_dir
	p.homing_target = current_target if (current_target != null and is_instance_valid(current_target)) else null
	p.damage = final_dmg
	p.knockback_base = WeaponData.knockback_for(weapon_def_id, 120.0)
	p.pierce_left = int(def.get("pierce", 1)) + GameManager.bonus_pierce
	p.bounce_left = int(def.get("bounce_count", 0))
	p.bullet_texture = bullet_tex
	p.bullet_scale = float(def.get("bullet_scale", 0.55))
	p.spin = bool(def.get("bullet_spin", false))

	if def.get("proc_burn", false):
		p.proc_burn = true
		p.burn_dps = final_dmg * float(def.get("burn_ratio", 0.4))
		p.burn_dur = float(def.get("burn_dur", 2.5))

	p.activate()

	# 开火反馈（T-2.8）：枪口 HDR 闪光起辉 + 2-3 粒元素碎屑 + 核心亮闪 + 后坐抖动与音效
	if muzzle_flash != null:
		muzzle_flash.rotation = randf() * TAU
		muzzle_flash.scale = Vector2.ONE * randf_range(0.35, 0.45)
		var flash_col := GameStyle.fx_hdr_element(_elem, GameStyle.FX_HDR_CORE)
		muzzle_flash.modulate = flash_col
		muzzle_flash.visible = true
		var mtw := create_tween()
		mtw.set_parallel(true)
		mtw.tween_property(muzzle_flash, "scale", Vector2.ONE * 0.75, 0.08)
		mtw.tween_property(muzzle_flash, "modulate:a", 0.0, 0.08)
		mtw.chain().tween_callback(func(): muzzle_flash.visible = false)

	# 炮口微粒喷射（绕过受击限流闸，不抢占命中火花名额；2026-10-16 减量 scale 0.6→0.45 并顺向）
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, muzzle_point.global_position, _elem, 0.45, true, aim_dir)

	core_sprite.modulate = Color(1.4, 1.35, 1.2)
	var ftw := create_tween()
	ftw.tween_property(core_sprite, "modulate", Color.WHITE, 0.1)

	core_sprite.position = -aim_dir * 3.5
	var rtw := create_tween()
	rtw.tween_property(core_sprite, "position", Vector2.ZERO, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx(WeaponData.sfx_for(weapon_def_id), 0.95)

func dismiss() -> void:
	if _is_dying:
		return
	_is_dying = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)
