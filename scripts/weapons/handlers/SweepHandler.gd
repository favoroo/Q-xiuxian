class_name SweepHandler
extends RefCounted

## 横扫（SWEEP）行为实现（2026-10-24 自 FloatingWeapon 拆出）。
## 与近战分家（2026-10-13，用户口径：「横扫和近战玩起来没区别」）：
## 判定是「前方真扇形」——以本体为圆心查 _sweep_arc_radius() 的圆，再按角度过滤，
## 只结算 aim_dir ±SWEEP_HALF_ANGLE 里的敌人（身后的漏网，这是与近战 360° 圆判定最本质的手感差异）；
## 刀光是 WeaponArcRenderer 画的元素扇面（满亮 ±80° 与判定半角同源、外缘 124px 与近战月牙同画布约定），
## top_level 贴世界坐标 —— 扇面钉在挥出那一帧的方位上，不随本体收势转走，扇面几何 == 判定扇形。
## 节奏全面比近战沉：蓄力更深更久、前突更远、收势更慢、命中音低沉一档。
##
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。

const SWEEP_ARC_RADIUS := 88.0    ## 横扫扇形基础半径（近战圆 75，横扫手更长）
const SWEEP_HALF_ANGLE := 80.0    ## 扇形半角（度）—— 与 WeaponArcRenderer 扇面满亮张角同源，改渲染要同步改这里
const SWEEP_ART_OUTER := 124.0    ## 扇面外缘画布半径（WeaponArcRenderer.OUTER）
const SWEEP_SLASH_IN_TIME := 0.09 ## 扇面扫放（扩张 + 转正）时长
const SWEEP_SLASH_FADE := 0.09    ## 扇面淡出时长
const SWEEP_WINDUP := 0.09        ## 蓄力前摇（近战 0.05）
const SWEEP_STRIKE := 0.06        ## 横扫瞬发（近战 0.04）
const SWEEP_RECOVER := 0.17       ## 沉重收势（近战 0.13）
const SWEEP_THRUST := 30.0        ## 打击帧本体前突（近战 26）
const SWEEP_RECOIL := 6.0         ## 入肉反冲（近战 4.5）
const SWEEP_CLOSE_GRACE := 26.0   ## 贴脸宽容：距离小于它不看角度（敌人受击圈 15px，扇形顶点不许漏贴身的）
const SWEEP_ANGLE_SLACK := 6.0    ## 角度宽容（度）：扇面 80°→88° 羽化边里擦到的也算中
const SWEEP_IMPACT_PITCH := 0.9   ## 横扫命中音低沉一档，与近战的亮脆分层

## 横扫扇形半径 —— 扇面外缘与 deal_damage 的查询半径共用这一个数（画多大==判多大）
static func arc_radius(w) -> float:
	var wide_bonus: float = (1.0 + GameManager.item_hook_sum("wide_range_mult")) if WeaponData.tags_of(w.weapon_def_id).has("wide") else 1.0
	return SWEEP_ARC_RADIUS * w.arc_scale * w._range_mult() * wide_bonus

## 横扫三段：深蓄力（0.09s）→ 大幅扫出（0.06s，本体扫过整片 160° 扇形）→ 沉重收势（0.17s）。
## 挥空门控与近战同口径：扇面/材质声/反冲只在真咬到肉时发，空挥保留完整动作与破空声。
static func perform(w) -> void:
	w.is_attacking = true

	var aim_dir: Vector2 = Vector2.RIGHT.rotated(w.rotation)
	if w.current_target != null:
		aim_dir = (Vector2(w.current_target.global_position) - w.global_position).normalized()
	var aim_angle := aim_dir.angle()
	var orig_pos: Vector2 = w.position
	var windup_pos: Vector2 = orig_pos - aim_dir * 12.0
	var thrust_pos: Vector2 = orig_pos + aim_dir * (SWEEP_THRUST * MeleeHandler.thrust_mult(w))

	# 起手预置到扇形前缘，打击帧扫到后缘 —— 横扫本体真的扫过整片扇形
	var half_ang := deg_to_rad(SWEEP_HALF_ANGLE)
	w._apply_facing(aim_angle - half_ang)
	if w._sweep_slash_tween != null and w._sweep_slash_tween.is_valid():
		w._sweep_slash_tween.kill()  # 与近战 _slash_tween 同一防抢道约定
	var reach: float = arc_radius(w)
	if w.sweep_sprite != null:
		w.sweep_sprite.visible = false
		w.sweep_sprite.modulate.a = 0.0

	AudioManager.play_sfx(WeaponData.sfx_for(w.weapon_def_id), MeleeHandler.MELEE_WHOOSH_SCALE)
	var tw = w.create_tween()
	# 1. 蓄力前摇：重器后撤更深、压扁拉长更夸张（横扫的「沉」先在蓄力里交代）
	tw.tween_property(w, "position", windup_pos, SWEEP_WINDUP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(w, "scale", Vector2(0.88, 1.12), SWEEP_WINDUP)
	# 2. 横扫瞬发：先结算扇形判定，咬到肉才亮金色扇面 + 低沉材质声 + 反冲
	tw.chain().tween_callback(func():
		w._flash_sprite(Color(1.5, 1.5, 1.5), 0.14)
		var hits: int = deal_damage(w, aim_dir)
		if hits > 0:
			StrikeFx.try_spawn_earth_crack(w, w.global_position + aim_dir * (reach * 0.55), reach * 0.75)
			if w.sweep_sprite != null:
				# 扇面从判定几何的 50% 扩张扫放到 100%、同时从偏前缘 18° 转正到瞄准轴 ——
				# 「一扫一大片」的拖扫感；终态外缘 == 判定半径、张角 == 判定半角（同源不变量）
				w.sweep_sprite.global_position = w.global_position
				w.sweep_sprite.global_rotation = aim_angle - deg_to_rad(18.0)
				w.sweep_sprite.scale = Vector2.ONE * (reach / SWEEP_ART_OUTER) * 0.5
				w.sweep_sprite.visible = true
				w.sweep_sprite.modulate.a = 1.0
				w._sweep_slash_tween = w.create_tween()
				w._sweep_slash_tween.set_parallel(true)
				w._sweep_slash_tween.tween_property(w.sweep_sprite, "scale", Vector2.ONE * (reach / SWEEP_ART_OUTER), SWEEP_SLASH_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				w._sweep_slash_tween.tween_property(w.sweep_sprite, "global_rotation", aim_angle, SWEEP_SLASH_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				w._sweep_slash_tween.chain().tween_property(w.sweep_sprite, "modulate:a", 0.0, SWEEP_SLASH_FADE)
				w._sweep_slash_tween.chain().tween_callback(func(): w.sweep_sprite.visible = false)
				AudioManager.play_sfx(WeaponData.sfx_impact_for(w.weapon_def_id), MeleeHandler.MELEE_IMPACT_SCALE, SWEEP_IMPACT_PITCH)
				w.position -= aim_dir * SWEEP_RECOIL
	)
	tw.tween_property(w, "position", thrust_pos, SWEEP_STRIKE).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(w, "rotation", aim_angle + half_ang, SWEEP_STRIKE).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(w, "scale", Vector2(1.22, 0.85), SWEEP_STRIKE)
	# 3. 沉重收势：回弹时间比近战长一档；终点同样取实时轨道位
	tw.chain().tween_callback(func(): w._begin_recover(SWEEP_RECOVER, Tween.TRANS_BACK))

## 横扫扇形结算：圆形查询后按角度过滤 —— 只结算 aim_dir ±（半角+宽容）内的敌人
## （贴脸 SWEEP_CLOSE_GRACE 不看角度），身后的怪这一扫够不着。返回值语义同近战 = 可见命中数，
## 打击帧回调拿它门控扇面/材质声/反冲。属性管线、暴击、异常、吸血与近战同一份代码形状。
static func deal_damage(w, aim_dir: Vector2) -> int:
	var origin: Vector2 = w.global_position
	var half_ang := deg_to_rad(SWEEP_HALF_ANGLE + SWEEP_ANGLE_SLACK)
	var results: Array = w._query_enemies(arc_radius(w), origin, 24)
	var hit_count := 0
	var player: Node2D = GameManager.player
	var vp_center: Vector2 = player.global_position if player != null else w.global_position
	var base_dmg: float = w._final_damage()
	# 2026-10-14 风险溢价：横扫击退兜底 240→300（重控场分支，与表内 340—680 一致）
	var kb_force: float = WeaponData.knockback_for(w.weapon_def_id, 300.0)
	var proc_burn: bool = w.def.get("proc_burn", false)
	var proc_chill: float = float(w.def.get("proc_chill", 0.0))
	var proc_poison: bool = w.def.get("proc_poison", false)
	var any_proc: bool = proc_burn or proc_chill > 0.0 or proc_poison
	var flat_ls: float = GameManager.item_hook_sum("melee_lifesteal_flat")
	var can_flat_heal: bool = flat_ls > 0.0 and player != null and is_instance_valid(player) and player.has_method("heal")

	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			# 扇形过滤：横扫只打正前方弧面（身后的漏网是横扫与近战的本质差异）
			var to_enemy: Vector2 = enemy.global_position - origin
			if to_enemy.length() > SWEEP_CLOSE_GRACE and absf(aim_dir.angle_to(to_enemy)) > half_ang:
				continue
			var dmg := base_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock = GameManager.knockback_vec(w.global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			if GameBalance.is_in_viewport(enemy.global_position, vp_center):
				hit_count += 1
			# 命中火花（前 SWEEP_SPARK_MAX 个目标，横扫扫一片也只出几朵）
			if hit_count <= StrikeFx.SWEEP_SPARK_MAX:
				StrikeFx.spawn_hit_spark(w, enemy, knock, is_crit)
			if any_proc:
				ProcStatus.apply(enemy, proc_burn,
					dmg * float(w.def.get("burn_ratio", 0.45)), float(w.def.get("burn_dur", 3.0)),
					proc_chill, float(w.def.get("chill_dur", 2.5)),
					proc_poison, dmg * float(w.def.get("poison_ratio", 0.35)), float(w.def.get("poison_dur", 3.0)))
			GameManager.try_lifesteal(w.behavior)
			# 开山重刃谱：横扫同属近身挥砍，吸血钩子照旧生效
			if can_flat_heal:
				player.heal(flat_ls, true)
	return hit_count
