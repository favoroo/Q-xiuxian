class_name BurstHandler
extends RefCounted

## 落雷（BURST）行为实现（2026-10-24 自 FloatingWeapon 拆出）：
## 施法演出（法牌升起蓄力、金光微颤）+ 引雷 + ThunderBurst 落点爆发。
##
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。

const CHARGE_GLOW := Color(1.45, 1.28, 0.62)   # 五雷蓄力时的金光
const BURST_CAST_SCALE := 0.7      ## 施法层响度：落点才是主角，这里只起手（2026-10-10 音色重构）

static func perform(w) -> void:
	w.is_attacking = true

	var target_pos = w.global_position + Vector2.RIGHT.rotated(w.rotation) * 30.0
	if w.current_target != null and is_instance_valid(w.current_target):
		target_pos = w.current_target.global_position

	var strike_dir: Vector2 = (target_pos - w.global_position).normalized()
	# 发射帧对准落雷点：upright 的重器（宝灯/法牌/大印）本体保持竖直，只让雷从"朝目标那一侧的器口"引出
	w._apply_facing(strike_dir.angle())
	var orig_pos: Vector2 = w.position
	var cast_pos := orig_pos + Vector2(0.0, -16.0)

	# 施法演出：法牌升起蓄力、金光微颤 → 引雷落于目标 → 前突回落
	# 旧写法在这儿硬编码 orb_hit（钟），把表里配的 thunder_strike 整个架空了 ——
	# 六把落雷系武器听起来全是「敲钟 + 祝福铃」。取音一律回表。
	AudioManager.play_sfx(WeaponData.sfx_for(w.weapon_def_id), BURST_CAST_SCALE)
	var tw = w.create_tween()
	tw.tween_property(w, "position", cast_pos, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(w, "scale", Vector2(1.22, 1.22), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	w._tw_modulate(tw, CHARGE_GLOW, 0.10)
	for i in range(3):
		tw.tween_property(w, "position", cast_pos + Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5)), 0.035)
	tw.tween_callback(func(): spawn_lightning(w, target_pos))
	# ★3 觉醒「双雷」/ ★4 极境「天劫三雷」：主雷落点后一拍，在同一落点附近追加 count 道
	# （每道 ratio 伤害，参数唯一真话在 WeaponData.STAR3_AWAKEN / STAR4_ASCEND，经 awaken_perk 取）。
	# 落点小幅偏移——几道雷完全叠在一起读着像一道粗雷，错开才读得出「多」；
	# 偏移量影响命中范围，属判定随机，走 GameManager.rng（铁律 3）。
	var perk: Dictionary = WeaponData.awaken_perk(WeaponData.Behavior.BURST, w.star)
	if not perk.is_empty():
		var echo_ratio: float = float(perk.get("ratio", 0.6))
		var echo_count: int = maxi(1, int(perk.get("count", 1)))
		for seg in range(echo_count):
			# 逐道加大错开半径：第二道在 0.4R、第三道再往外一档，三道雷铺开成三角而非一线
			var ring: float = 0.4 + 0.22 * float(seg)
			var echo_pos: Vector2 = target_pos + Vector2.RIGHT.rotated(GameManager.rng.randf() * TAU) * w.burst_radius * w._range_mult() * ring
			tw.tween_interval(0.08)
			tw.tween_callback(func(): spawn_lightning(w, echo_pos, echo_ratio))
	tw.tween_property(w, "position", orig_pos + strike_dir * 12.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	w._tw_modulate(tw, Color(1.9, 1.85, 1.45), 0.05)
	tw.tween_property(w, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(e: float) -> void:
		w.position = (orig_pos + strike_dir * 12.0).lerp(w._compute_orbit_pos(), e)
	, 0.0, 1.0, 0.15).set_trans(Tween.TRANS_SINE)
	w._tw_modulate(tw, Color.WHITE, 0.18)
	tw.tween_callback(func(): w.is_attacking = false)

## 引雷：锯齿闪电从武器射向落雷点，落雷爆发在 ThunderBurst.activate() 里结算。
## dmg_ratio：★3 觉醒「双雷」第二道的伤害系数（默认 1.0 = 主雷）；追加道电柱略细、
## 伤害/击退/异常量随系数打折（异常取 max 生效，弱化刷新盖不掉主雷的强异常）。
static func spawn_lightning(w, target_pos: Vector2, dmg_ratio: float = 1.0) -> void:
	# 屏外落点不引雷：电柱从屏内的器口一路画到屏外，屏内那一段就是「凭空一道白光」。
	# 伤害照常由 ThunderBurst 结算（落点视觉在屏外本就不可见，爆散环另有 JuiceEffect 视口兜底）。
	var player: Node2D = GameManager.player
	var battle_layer: Node = player.get_parent() if (player != null and player.get_parent() != null) else (w.get_tree().current_scene if w.get_tree() != null else w)
	if player == null or GameBalance.is_in_viewport(target_pos, player.global_position):
		var bolt: LightningBolt = LightningBolt.acquire(battle_layer)
		var w_mult: float = 1.0 + 0.18 * float(w.star - 1)
		if dmg_ratio < 1.0:
			w_mult *= 0.8
		var b_tint: Color = w.def.get("burst_tint", LightningBolt.GLOW_COLOR)
		bolt.activate(w.muzzle_point.global_position, target_pos, b_tint, w_mult)

	# 落雷走对象池（2026-10-11 第 6 波卡顿优化）：acquire → 写字段 → activate 起爆
	var burst: Node2D = ThunderBurst.acquire(battle_layer, w.burst_scene)
	burst.global_position = target_pos
	burst.radius = w.burst_radius * w._range_mult()
	var final_dmg: float = w._final_damage() * dmg_ratio
	burst.damage = final_dmg
	burst.knockback_base = WeaponData.knockback_for(w.weapon_def_id, 200.0) * dmg_ratio
	burst.tint = w.def.get("burst_tint", burst.tint)
	burst.burst_kind = String(w.def.get("burst_kind", "thunder"))
	# 落点音必须在 activate() 之前下发：activate 里就播它
	burst.sfx_impact_key = WeaponData.sfx_impact_for(w.weapon_def_id)
	if w.def.get("proc_burn", false):
		burst.proc_burn = true
		burst.burn_dps = final_dmg * float(w.def.get("burn_ratio", 0.5))
		burst.burn_dur = float(w.def.get("burn_dur", 3.0))
	if float(w.def.get("proc_chill", 0.0)) > 0.0:
		burst.proc_chill = float(w.def.get("proc_chill", 0.0))
		burst.chill_dur = float(w.def.get("chill_dur", 2.0))
	burst.activate()
