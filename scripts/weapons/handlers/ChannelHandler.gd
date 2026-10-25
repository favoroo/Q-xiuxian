class_name ChannelHandler
extends RefCounted

## 持续束流（BEAM 光束 / CONE 喷吐）行为实现（2026-10-24 自 FloatingWeapon 拆出）。
## 与六段式攻击不同：束流不设 is_attacking（不冻结轨道与朝向），起喷后由 tick
## 逐帧续命 —— 朝向本身 15rad/s 追踪目标，光束/火锥自然跟着缓慢扫动。
## 每 TICK 结算一次，tick 伤害 = 整管伤害 × TICK / 有效冷却 ⇒ 纸面 DPS（damage/cd）即实伤。
## 冷却循环到期自动续喷（CHANNEL_HOLD > 冷却 ⇒ 目标在程内连续不断）；目标死亡/脱程即收束。
##
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。
## 束流运行时状态（_channel_on/_beam_len 等）仍是武器成员（渲染节点挂武器下、判据直读），
## 本模块只读写不持有；射线/矩形查询对象是本模块静态复用（单线程顺序执行安全）。

const CHANNEL_HOLD := 1.6      ## 一次起喷持续时间（秒），冷却每转一圈回来续喷
const BEAM_TICK := 0.15        ## 光束结算间隔
const CONE_TICK := 0.21        ## 喷吐结算间隔（火葫芦 0.42 冷却 = 每周期 2 跳）
const CONE_HALF_ANGLE := 28.0  ## 喷吐锥形半角（度），视觉锥宽同源
const BEAM_HALF_WIDTH := 5.0   ## 光束判定半宽（视觉束宽同源）
## 光束判定在截断点后再探出一段：射线停在挡束者表面，不补这段则挡住光束的敌人自己
## 反而打不到（判定只到它表皮）；补段长约一个敌人受击半径，只盖挡束者、不穿墙打后排。
const BEAM_HIT_OVERHANG := 24.0
## 束长射线节流（2026-10-14）：原每渲染帧 create 参数对象 + intersect_ray（60 次/秒），
## 降到 10Hz 快照 + 参数对象复用（对齐武器 _search_query 范式），帧间 _beam_len 向快照缓动；
## 起喷当帧强制立判（武器 _beam_need_cast），首跳伤害长度不滞后。
const BEAM_CAST_INTERVAL := 0.1

## ★3 觉醒「贯日」/ ★4 极境「贯日天河」：光束判定宽度倍率。
## 判定盒与视觉束宽都从这里取——画多宽==判多宽，只改一边违反分层铁律 7。
static func beam_width_mult(w) -> float:
	return float(WeaponData.awaken_perk(WeaponData.Behavior.BEAM, w.star).get("width_mult", 1.0))

## ★3 觉醒「燎原」/ ★4 极境「焚天燎原」：喷吐锥形半角（度），判定过滤与视觉锥宽同源下发。
static func cone_half_angle(w) -> float:
	return float(WeaponData.awaken_perk(WeaponData.Behavior.CONE, w.star).get("half_angle", CONE_HALF_ANGLE))

## 束流威力倍率（dmg_mult）：加宽/扩角之外本体也升温。
## 乘在 _final_damage 之后：喷吐的灼烧从 cycle_dmg 派生所以一并放大，
## 与尺子 sustained_single_dps 的 BEAM/CONE 分支（整管 ×dmg_mult）同源。
static func star3_dmg_mult(w) -> float:
	return float(WeaponData.awaken_perk(w.behavior, w.star).get("dmg_mult", 1.0))

## 星级束色（2026-10-25）：★1/★2 保持武器本来的五行器光，★3 向鎏金混 45%，
## ★4 向电光青混 60%——宽度之外再给一条「颜色分档」的读数。
## 只混不变（保留五行身份：水镜仍是水镜，只是更烫）。
static func beam_tint(w, base: Color) -> Color:
	var star: int = int(w.star)
	if star < 3:
		return base
	var target: Color = GameStyle.star_fx_ldr(star, 0)
	var mix: float = 0.45 if star < 4 else 0.6
	return base.lerp(target, mix)

## 束流芯线色：默认幽夜紫；★4 换电光青 HDR（整束最亮那一层直接换色，泛光同源）
static func beam_core_tint(w) -> Color:
	var star: int = int(w.star)
	if star >= 3:
		return GameStyle.star_fx_color(star, 0)
	return Color(0, 0, 0, 0)

## 喷吐锥色：★3 鎏金 / ★4 电光青（火葫芦的冷焰极境）
static func cone_tint(w) -> Color:
	var star: int = int(w.star)
	if star >= 3:
		return GameStyle.star_fx_ldr(star, 0)
	return Color(0, 0, 0, 0)

## 起喷亮闪色：★3 鎏金 / ★4 电光青 HDR，低星保留原本的淡紫白
static func channel_cast_color(star: int) -> Color:
	if star >= 3:
		return GameStyle.star_fx_color(star, 0)
	return Color(1.4, 1.25, 1.5)

## 光束长度射线与判定矩形的静态复用对象（单线程使用安全，尺寸/变换每次调用重设）
static var _beam_ray_query: PhysicsRayQueryParameters2D = null
static var _beam_shape: RectangleShape2D = null
static var _beam_query: PhysicsShapeQueryParameters2D = null

## 束流起喷：不冻结轨道（不设 is_attacking），挂上持续时长与起手反馈；
## 冷却循环每转一圈回来续喷，所以起手音只在从收束态点燃时放（连续喷不叠音）
static func perform_channel(w) -> void:
	if not w._channel_on:
		w._channel_on = true
		w._beam_need_cast = true
		StrikeFx.fire_sfx(w, WeaponData.sfx_for(w.weapon_def_id), 0.9)
		w._flash_sprite(channel_cast_color(w.star), 0.14)
	w._channel_left = CHANNEL_HOLD

static func stop(w) -> void:
	w._channel_on = false
	w._channel_left = 0.0
	if w.beam_renderer != null:
		w.beam_renderer.beam_off()
	if w.cone_renderer != null:
		w.cone_renderer.cone_off()

static func tick(w, delta: float) -> void:
	w._channel_left -= delta
	if w._channel_left <= 0.0 or w.current_target == null or not is_instance_valid(w.current_target):
		stop(w)
		return
	var reach: float = w.attack_range * w._range_mult()
	w._channel_tick -= delta
	if w.behavior == WeaponData.Behavior.BEAM:
		w._beam_cast_phase -= delta
		if w._beam_need_cast:
			w._beam_need_cast = false
			w._beam_cast_phase = BEAM_CAST_INTERVAL
			w._beam_len = cast_beam_length(w, reach)
			w._beam_len_target = w._beam_len
		elif w._beam_cast_phase <= 0.0:
			w._beam_cast_phase = BEAM_CAST_INTERVAL
			w._beam_len_target = cast_beam_length(w, reach)
		w._beam_len = lerpf(w._beam_len, w._beam_len_target, minf(delta * 14.0, 1.0))
		# 星升视觉膨胀收一档（2026-10-15 克制化 0.18→0.08）：判定盒（deal_beam_damage
		# 恒 BEAM_HALF_WIDTH*2.0）本就不乘它，纯视觉；★3 视觉宽 13.6→11.6，不再比判定宽出 1/3
		# 2026-10-24 ★3 觉醒「贯日」：判定盒本身 ×beam_width_mult（deal_beam_damage 同源），
		# 视觉 = 新判定宽 × w_mult（±16% 辉光宽容照旧）。
		var w_mult: float = 1.0 + 0.08 * float(w.star - 1)
		# 2026-10-25 ★3/★4 束色分档：三层（光晕/主束/芯/端头灯）全从 tint+core 派生，
		# 只在这一处下发即可整束换色——旧写法只变宽不变色，极境光束读着只是「粗了一点的普通束」。
		w.beam_renderer.beam_on(w._beam_len, BEAM_HALF_WIDTH * 2.0 * beam_width_mult(w) * w_mult,
			beam_tint(w, w._get_aura_color()), beam_core_tint(w))
		if w._channel_tick <= 0.0:
			w._channel_tick = BEAM_TICK
			deal_beam_damage(w)
	else:
		# 锥长从器口起算：判定圆心 == 器口、半径 == 锥长，渲染器同源下发
		# （锥角经 cone_half_angle 下发：★3 觉醒「燎原」判定与视觉同步加宽）
		var cone_len: float = maxf(40.0, reach - w.muzzle_len)
		w.cone_renderer.cone_on(cone_len, cone_len * tan(deg_to_rad(cone_half_angle(w))), cone_tint(w))
		if w._channel_tick <= 0.0:
			w._channel_tick = CONE_TICK
			deal_cone_damage(w, cone_len)

## 光束长度：从器口沿发射帧 +X 打射线，命中首个受击区即截断（光束被第一个敌人挡住），
## 否则打满射程。返回值为判定与渲染的唯一真话（画多远==判多远）。
static func cast_beam_length(w, reach: float) -> float:
	var max_len: float = maxf(40.0, reach - w.muzzle_len)
	var from: Vector2 = w.muzzle_point.global_position
	var dir: Vector2 = Vector2.RIGHT.rotated(w.global_rotation)
	if _beam_ray_query == null:
		_beam_ray_query = PhysicsRayQueryParameters2D.create(from, from + dir * max_len, 4, [])
		_beam_ray_query.collide_with_areas = true
		_beam_ray_query.hit_from_inside = true
	else:
		_beam_ray_query.from = from
		_beam_ray_query.to = from + dir * max_len
	var hit: Dictionary = w.get_world_2d().direct_space_state.intersect_ray(_beam_ray_query)
	if hit.is_empty():
		return max_len
	return maxf(8.0, from.distance_to(hit["position"]))

## 光束 tick 结算：矩形沿束查询，线上敌人一起吃；tick 伤害 = 整管 × TICK/有效冷却
static func deal_beam_damage(w) -> void:
	if _beam_shape == null or _beam_query == null:
		_beam_shape = RectangleShape2D.new()
		_beam_query = PhysicsShapeQueryParameters2D.new()
		_beam_query.shape = _beam_shape
		_beam_query.collision_mask = 4
		_beam_query.collide_with_areas = true
		_beam_query.collide_with_bodies = false  # 只查敌人 Hurtbox(Area)，不扫 body 层
	var from: Vector2 = w.muzzle_point.global_position
	var dir: Vector2 = Vector2.RIGHT.rotated(w.global_rotation)
	var judge_len: float = w._beam_len + BEAM_HIT_OVERHANG
	# ★3 觉醒「贯日」判定盒加宽：与 beam_on 的视觉束宽同一倍率出口（beam_width_mult）
	_beam_shape.size = Vector2(judge_len, BEAM_HALF_WIDTH * 2.0 * beam_width_mult(w))
	_beam_query.transform = Transform2D(w.global_rotation, from + dir * judge_len * 0.5)
	var results: Array = w.get_world_2d().direct_space_state.intersect_shape(_beam_query, 16)
	var eff_cd: float = maxf(0.05, w.attack_cooldown * GameManager.get_effective_attack_speed_mult())
	var tick_dmg: float = w._final_damage() * BEAM_TICK / eff_cd * star3_dmg_mult(w)
	var kb_force: float = WeaponData.knockback_for(w.weapon_def_id, 60.0) * 0.15  # 持续束只留一点点推感
	# 机制快照整个 tick 取一次（束流每 tick 打多个目标，逐敌读 hook 是最高频浪费）
	var mech := OnHitEffects.snapshot()
	var has_mech: bool = OnHitEffects.any_enabled()
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			var dmg := tick_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock: Vector2 = GameManager.knockback_vec(w.global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			GameManager.try_lifesteal(w.behavior)
			# 超级悟道机制卡的命中后效果（束流同一入口）。束流是 tick 结算、每秒十几次，
			# 链电/落雷由 ChainLightning 自己的毫秒闸限流，不会刷屏。
			if has_mech:
				OnHitEffects.on_weapon_hit(w, enemy, dmg, is_crit, mech)

## 喷吐 tick 结算：器口为圆心查锥长半径的圆，再按半角过滤（贴脸宽容与横扫同口径），
## 命中挂灼烧。tick 伤害同源折算 ⇒ 纸面 dmg/cd + 常驻灼烧即实伤。
static func deal_cone_damage(w, cone_len: float) -> void:
	var from: Vector2 = w.muzzle_point.global_position
	var aim_dir: Vector2 = Vector2.RIGHT.rotated(w.global_rotation)
	# 锥角经 cone_half_angle 取：★3 觉醒「燎原」判定与视觉锥宽同源加宽
	var half_ang := deg_to_rad(cone_half_angle(w))
	var results: Array = w._query_enemies(cone_len, from, 24)
	var eff_cd: float = maxf(0.05, w.attack_cooldown * GameManager.get_effective_attack_speed_mult())
	var cycle_dmg: float = w._final_damage() * star3_dmg_mult(w)
	var tick_dmg: float = cycle_dmg * CONE_TICK / eff_cd
	var kb_force: float = WeaponData.knockback_for(w.weapon_def_id, 95.0) * 0.25
	var proc_burn: bool = w.def.get("proc_burn", false)
	var burn_dps: float = cycle_dmg * float(w.def.get("burn_ratio", 0.4))
	var burn_dur: float = float(w.def.get("burn_dur", 2.5))
	var mech := OnHitEffects.snapshot()
	var has_mech: bool = OnHitEffects.any_enabled()
	for res in results:
		var col = res["collider"]
		var parent = col.get_parent() if col != null else null
		if parent != null and parent.has_method("take_damage"):
			var enemy = parent
			var to_enemy: Vector2 = enemy.global_position - from
			if to_enemy.length() > SweepHandler.SWEEP_CLOSE_GRACE and absf(aim_dir.angle_to(to_enemy)) > half_ang:
				continue
			var dmg := tick_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock: Vector2 = GameManager.knockback_vec(w.global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			ProcStatus.apply(enemy, proc_burn, burn_dps, burn_dur, 0.0, 0.0, false, 0.0, 0.0)
			GameManager.try_lifesteal(w.behavior)
			if has_mech:
				OnHitEffects.on_weapon_hit(w, enemy, dmg, is_crit, mech)
