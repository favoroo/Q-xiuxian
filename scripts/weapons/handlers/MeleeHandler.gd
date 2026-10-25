class_name MeleeHandler
extends RefCounted

## 近战（MELEE）行为实现（2026-10-24 自 FloatingWeapon 拆出）。
## 三段式节奏：前摇微撤蓄势 → 极速瞬扫 → 弹性卸力回正；判定是「圆心前突的 360° 圆」。
## 挥空门控：月牙/材质声/反冲只在真咬到肉时发，空挥保留完整动作与破空声。
##
## 纪律：首参 w 为宿主武器（不标类型，鸭类型访问——武器侧硬类型引用会触发
## 循环类依赖，把弹丸 preload 打成空 PackedScene，项目坑 12）。
## 演出状态（slash_sprite/_slash_tween 等）仍是武器成员，本模块只读写不持有。

## 近战"画多大==判多大"（2026-10-09）：判定是一个圆 —— 圆心在本体前突 MELEE_LUNGE、
## 半径 MELEE_ARC_RADIUS × arc_scale × 射程乘区。弧光由 WeaponArcRenderer 纯矢量绘制
## （2026-10-13 取代 slash_effect.png 贴图）：围绕自身轴心、半径 124 画布像素、张角 ±70°
## 的一弯细月牙，所以把月牙轴心摆到判定圆心、缩放取
## 判定半径 / SLASH_ART_OUTER ⇒ 月牙外缘正好压在判定圆的边界上。
const MELEE_LUNGE := 30.0
const MELEE_ARC_RADIUS := 75.0
const SLASH_ART_OUTER := 124.0

## 剑气出鞘扫放（2026-10-11，用户口径：「范围叠高后，剑挥一下，很远才出现一道剑气，很怪」）：
## 月牙不再出生即钉在判定外缘，而是内缘贴剑尖出生、SLASH_SWEEP_TIME 内扫放到判定几何再淡出
## —— 剑气是从剑上劈出去的，不是凭空悬在远处。终态仍是上面那条"外缘==判定半径"的同源
## 不变量，判定数值一字不动。月牙贴图的不透明带贴在外缘（0° 方向实测 102—127px、89px 起
## 半透明淡入），出生缩放按"内缘压住剑尖屏上位置 muzzle_len"反解。
const SLASH_ART_INNER := 114.0  ## 月牙中心内缘画布半径（== WeaponArcRenderer.MELEE_INNER，锥形月牙中心厚度 10px），出生"贴剑尖"反解用
const SLASH_SPAWN_INSET := 2.0  ## 出生内缘再往前探 2px，让剑尖埋进剑气里
const SLASH_SWEEP_TIME := 0.10  ## 剑气从剑尖扫放到判定外缘的时长（期间保持全亮）
const SLASH_FADE_TIME := 0.08   ## 抵达判定外缘后的淡出时长 —— 落点先亮一拍再散
const MELEE_THRUST := 26.0      ## 打击帧本体前突距离
const MELEE_STRETCH_MAX := 2.0  ## 突刺随射程乘区的前突上限倍数（只往前够，不缩水）

## 近战双层相对响度（2026-10-10 音色重构）：
## 前摇破空是「动作」，无条件播、当铺垫层，所以压低；命中材质是「战果」，只在真打中时补一记。
## 旧写法只有一层，且写在打击帧 —— 一声纯空气破空挂在命中 moment，剑听上去就是棍子。
const MELEE_WHOOSH_SCALE := 1.0
const MELEE_IMPACT_SCALE := 1.0    ## 压在 enemy_hit（0.56 峰值）之下，三层同帧才不糊（2026-10-22 抬到 1.0，配合材质声峰值 +8）

## 近战判定圆半径 —— 弧光外缘与 deal_damage 的查询圆共用这一个数
static func arc_radius(w) -> float:
	var wide_bonus: float = (1.0 + GameManager.item_hook_sum("wide_range_mult")) if WeaponData.tags_of(w.weapon_def_id).has("wide") else 1.0
	return MELEE_ARC_RADIUS * w.arc_scale * w._range_mult() * wide_bonus

## 打击帧前突倍数：范围叠得越高剑往前送得越远，剑才追得上外扩的剑气（上限 2 倍防乱飘）
static func thrust_mult(w) -> float:
	return clampf(w._range_mult(), 1.0, MELEE_STRETCH_MAX)

static func perform(w) -> void:
	w.is_attacking = true

	var aim_dir = Vector2.RIGHT.rotated(w.rotation)
	if w.current_target != null:
		aim_dir = (w.current_target.global_position - w.global_position).normalized()

	var aim_angle = aim_dir.angle()
	var orig_pos = w.position
	var windup_pos = orig_pos - aim_dir * 8.0
	var thrust_pos = orig_pos + aim_dir * (MELEE_THRUST * thrust_mult(w))

	# 挥砍弧光：终态 = 月牙轴心摆在判定圆心、缩放取 判定半径/月牙外缘 ⇒ 月牙外缘 == 那一帧查询圆的边界。
	# 月牙自身张角 ±70°，本体从 aim-swing 扫到 aim+swing（swing ≤ 60°）时它一直罩着瞄准轴，
	# 所以打出去的那一下和看得到的那一片是同一处。
	# 出生几何反解成"内缘贴剑尖"（muzzle_len），打击帧再扫放到终态 —— 剑气出鞘，不是远处凭空冒出。
	var swing: float = deg_to_rad(45.0) * w.arc_scale
	w._apply_facing(aim_angle - swing)
	if w._slash_tween != null and w._slash_tween.is_valid():
		w._slash_tween.kill()  # 极速攻速下上一次扫放没走完就得让位，防新旧两个 tween 抢同一个节点
	var slash_scale_end: float = arc_radius(w) / SLASH_ART_OUTER
	var slash_scale_in: float = clampf(slash_scale_end * 0.35, 26.0 / SLASH_ART_OUTER, slash_scale_end)
	var slash_pos_end := Vector2(MELEE_LUNGE, 0.0)
	var slash_pos_in: Vector2 = Vector2(w.muzzle_len + SLASH_SPAWN_INSET - SLASH_ART_INNER * slash_scale_in, 0.0)
	w.slash_sprite.visible = false
	w.slash_sprite.modulate.a = 0.0
	w.slash_sprite.position = slash_pos_in
	w.slash_sprite.scale = Vector2.ONE * slash_scale_in
	w.slash_sprite.rotation = 0.0

	# 三段式近战节奏：前摇微撤蓄势 (0.05s) → 极速瞬扫涂抹 (0.04s) → 弹性卸力回正 (0.13s)
	# 音效跟着这套节奏分两层：起手一声破空（动作，挥空也得有），咬到肉才补材质声（战果）。
	# 旧写法只有一层、且挂在打击帧 —— 于是一把剑和一根棍子听起来完全一样。
	StrikeFx.fire_sfx(w, WeaponData.sfx_for(w.weapon_def_id), MELEE_WHOOSH_SCALE)
	var tw = w.create_tween()
	# 1. 蓄力前摇（Anticipation）：刀身轻微后撤、微缩积蓄张力
	tw.tween_property(w, "position", windup_pos, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(w, "scale", Vector2(0.92, 1.08), 0.05)

	# 2. 打击瞬发（Active）：爆发极速横扫，先结算伤害、再只在咬到肉时点亮月牙刀光
	# 2026-10-11 挥空门控：旧写法先亮月牙后结算，于是一整片剑气先在空地上冒出来 ——
	# 空挥时（目标在前摇 0.05s 里被另一把武器打死或击飞出判定圆，或 15Hz 脱程重查窗口里
	# 仍锁着 1.2× 射程外的目标）月牙照样满亮扫放，「打空气」全在这一句。
	# 判定几何一个字没动（画多大==判多大）：空挥保留完整突刺动作、器身闪光与破空声，
	# 命中才补月牙/材质声/反冲。
	tw.chain().tween_callback(func():
		w._flash_sprite(Color(1.5, 1.5, 1.5), 0.12)
		var hits: int = deal_damage(w, aim_dir)
		if hits > 0:
			StrikeFx.try_spawn_earth_crack(w, w.global_position + aim_dir * MELEE_LUNGE, arc_radius(w) * 0.85)
			w.slash_sprite.visible = true
			w.slash_sprite.modulate.a = 1.0
			# 剑气出鞘：从剑尖处全亮扫放到判定几何（终态 == 查询圆边界），落点亮一拍再急速淡出；
			# 显隐生命周期整段归这条 tween 管（收招回调不再代管隐藏，防把淡出拦腰截断）
			w._slash_tween = w.create_tween()
			w._slash_tween.set_parallel(true)
			w._slash_tween.tween_property(w.slash_sprite, "position", slash_pos_end, SLASH_SWEEP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			w._slash_tween.tween_property(w.slash_sprite, "scale", Vector2.ONE * slash_scale_end, SLASH_SWEEP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			w._slash_tween.chain().tween_property(w.slash_sprite, "modulate:a", 0.0, SLASH_FADE_TIME)
			w._slash_tween.chain().tween_callback(func(): w.slash_sprite.visible = false)
			# 材质层只在真咬到肉时响；空挥只剩 50ms 前那一声破空
			AudioManager.play_sfx(WeaponData.sfx_impact_for(w.weapon_def_id), MELEE_IMPACT_SCALE)
			# 刀刃入肉阻力感：武器微反冲回弹
			w.position -= aim_dir * 4.5
	)
	tw.tween_property(w, "position", thrust_pos, 0.04).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(w, "rotation", aim_angle + swing, 0.04).set_trans(Tween.TRANS_EXPO)
	tw.parallel().tween_property(w, "scale", Vector2(1.15, 0.92), 0.04)

	# 3. 卸力后仰（Recovery）：TRANS_BACK 弹性回正 —— 终点是「实时」轨道位，不再弹回挥砍前的旧快照
	tw.chain().tween_callback(func(): w._begin_recover(0.13, Tween.TRANS_BACK))

	# 4. ★3 觉醒「回风斩」/ ★4 极境「绝影三连」：主斩落点紧接若干段反向回旋斩
	# （每段 ratio 伤害，参数唯一真话在 WeaponData.STAR3_AWAKEN / STAR4_ASCEND，经 awaken_perk 取）。
	# 回调与收招同拍起跑（收招 tween 只动 position/scale，rotation 归这条链，
	# 整段仍压在 is_attacking 窗口内，待机朝向插值不会来抢）；
	# 追加月牙走 w.get_echo_slash 独立节点——主斩剑光此刻仍在扫放/淡出，共用会被拦腰截断。
	var perk: Dictionary = WeaponData.awaken_perk(WeaponData.Behavior.MELEE, w.star)
	if not perk.is_empty():
		var echo_ratio: float = float(perk.get("ratio", 0.5))
		var echo_count: int = maxi(1, int(perk.get("count", 1)))
		for seg in range(echo_count):
			# 段与段之间来回摆：偶数段反向、奇数段正向（0 段 = -swing，与主斩同向回锋）
			var seg_sign: float = -1.0 if seg % 2 == 0 else 0.85
			tw.chain().tween_callback(func():
				AudioManager.play_sfx(WeaponData.sfx_for(w.weapon_def_id), MELEE_WHOOSH_SCALE * 0.6)
				var echo_hits: int = deal_damage(w, aim_dir, echo_ratio)
				if echo_hits > 0:
					w._flash_sprite(echo_glow_color(w.star, seg), 0.10)
					play_echo_slash(w, slash_scale_end, w.star, seg)
					AudioManager.play_sfx(WeaponData.sfx_impact_for(w.weapon_def_id), MELEE_IMPACT_SCALE * 0.7)
			)
			tw.tween_property(w, "rotation", aim_angle + swing * seg_sign, 0.09).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

## 追加斩的闪光色温：★3 觉醒鎏金 / ★4 太虚霓虹青紫逐段交替（与刀光同源，别处不再各写一份）。
## 色值统一在 GameStyle.star_fx_color（2026-10-25：唯一取色入口，五族共用）。
static func echo_glow_color(star: int, seg: int = 0) -> Color:
	return GameStyle.star_fx_color(star, seg)

## 追加斩的月牙色：★3 暖金，★4 电光青/太虚紫逐段交替（UI 与战斗同色语言）
static func echo_slash_color(star: int, seg: int = 0) -> Color:
	var col: Color = GameStyle.star_fx_color(star, seg)
	col.a = 1.0
	return col

## ★3 觉醒 / ★4 极境追加斩的月牙：直接在判定外缘亮起（主斩的"出鞘扫放"已经演过一遍，
## 追加段要的是"回锋"的干脆——亮一拍即散），略小半号区分主次。
## seg 为追加段号：★4 两段青紫交替，读得出"第几段"。
static func play_echo_slash(w, scale_end: float, star: int = 3, seg: int = 0) -> void:
	var spr: WeaponArcRenderer = w.get_echo_slash(WeaponArcRenderer.ArcMode.MELEE)
	spr.visible = true
	spr.modulate = echo_slash_color(star, seg)
	spr.position = Vector2(MELEE_LUNGE, 0.0)
	spr.scale = Vector2.ONE * scale_end * 0.9
	spr.rotation = 0.0
	var etw: Tween = w.create_tween()
	etw.tween_interval(0.06)
	etw.tween_property(spr, "modulate:a", 0.0, SLASH_FADE_TIME)
	etw.tween_callback(func(): spr.visible = false)

## dmg_ratio：★3 觉醒追加打击的伤害系数（默认 1.0 = 主斩）。追加段吸血/固定回血不重复结算，
## 击退与异常伤害随系数等比缩小（灼烧/剧毒取 max 生效，弱化刷新不会盖掉主斩的强异常）。
static func deal_damage(w, aim_dir: Vector2, dmg_ratio: float = 1.0) -> int:
	var results: Array = w._query_enemies(arc_radius(w), w.global_position + aim_dir * MELEE_LUNGE, 24)
	var hit_count := 0
	# 返回值语义 = 「可见命中数」：屏外目标的伤害/击退/异常照常结算，但不计入计数——
	# 打击帧回调拿它门控月牙/材质声/反冲，咬到看不见的目标时不许在屏内亮刀光
	var player: Node2D = GameManager.player
	var vp_center: Vector2 = player.global_position if player != null else w.global_position
	# 整刀属性管线只算一次：同刀乘区为常量（最多 24 目标共享），避免逐目标重算 _final_damage（9-13 次 item_hook_sum + 20 键 dict + equipped_cleanup 全子节点遍历）
	var base_dmg: float = w._final_damage() * dmg_ratio
	# 2026-10-14 风险溢价：近战击退兜底 240→280（贴脸换控场），弹丸仍 140
	var kb_force: float = WeaponData.knockback_for(w.weapon_def_id, 280.0) * dmg_ratio
	# 五行异常开关与近战吸血同为整刀常量：原来逐目标 item_hook_sum 全量遍历 items，
	# 24 目标 × 8 武器每挥砍近千次字典查找。注意异常施加保持 has_method 鸭类型——
	# 武器脚本硬引用 EnemyBase（as EnemyBase）实测会把弹丸 preload 打成空 PackedScene（循环类依赖坑）
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
			var dmg := base_dmg
			var is_crit: bool = GameManager.roll_crit()
			if is_crit:
				dmg *= GameManager.get_crit_mult()
			dmg *= GameManager.elite_damage_mult_for(enemy)
			var knock = GameManager.knockback_vec(w.global_position, enemy.global_position, kb_force)
			enemy.take_damage(dmg, knock, is_crit)
			if GameBalance.is_in_viewport(enemy.global_position, vp_center):
				hit_count += 1
			# 命中火花（前 MELEE_SPARK_MAX 个目标，防扫一片全冒）
			if hit_count <= StrikeFx.MELEE_SPARK_MAX:
				StrikeFx.spawn_hit_spark(w, enemy, knock, is_crit)
			if any_proc:
				ProcStatus.apply(enemy, proc_burn,
					dmg * float(w.def.get("burn_ratio", 0.45)), float(w.def.get("burn_dur", 3.0)),
					proc_chill, float(w.def.get("chill_dur", 2.5)),
					proc_poison, dmg * float(w.def.get("poison_ratio", 0.35)), float(w.def.get("poison_dur", 3.0)))
			# 吸血与固定回血只在主斩结算（追加打击不双计）
			if dmg_ratio >= 1.0:
				GameManager.try_lifesteal(w.behavior)
				# 开山重刃谱：近战命中额外吸收生命
				if can_flat_heal:
					player.heal(flat_ls, true)
	# 一挥扫中一片也只算「打了几下」，不是「打了几件事」：
	# 震屏与顿帧由 EnemyBase.take_damage 按目标重要性发放，武器侧不再重复叠加
	return hit_count
