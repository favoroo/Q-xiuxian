class_name EnemyDeathFx
extends RefCounted

## 敌人死亡解析（2026-10-24 自 EnemyBase._die 拆出）：死亡反馈分级、掉落结算、尸体演出。
## _die 本体只保留登记与清理（dying/击杀记账/死亡弹幕/分裂/预警清理），战果呈现全在这里。
##
## 纪律：首参 e 为宿主敌人（不标类型，鸭类型访问——反向硬类型引用 EnemyBase 会触发
## 循环类依赖，把场景 preload 打成空包）。BossEnemy 覆写 _die 后走 super 链，本模块对两者通用。

## 击杀反馈分级震屏（死亡爆散视觉已于 2026-10-12 整体下线：击杀反馈 = 尸体塌缩 + 跳字 + 音效）
## 2026-10-13 轻量重建：一小撮敌种主色碎屑 + 微环（JuiceEffect 侧有帧预算闸 + 视口门控，
## 不与尸体塌缩抢戏），只在伤害击杀路径放；回合末消散走 dissolve 不经过这里。
static func feedback(e) -> void:
	if e.procedural_view != null and e.procedural_view.config != null:
		JuiceEffect.spawn_death_burst(e.get_parent(), e.global_position, e.procedural_view.config.col_primary, e.is_elite)
		# 击杀余韵（2026-10-14 P1）：敌种主色贴地残晕，给每秒多次的击杀留 0.55s 地面读数。
		# 池容量 16 与寿命 0.55s 双重兜底，极高频击杀下自动复用最旧残晕，不会糊满地面
		var glow_r: float = 26.0 if not e.is_elite else 38.0
		GroundDecal.spawn_tinted(e.get_parent(), e.global_position, glow_r, e.procedural_view.config.col_primary)
		# 死亡演出（精简去躁：普通小怪死亡已有贴地残晕与塌缩消散，省去高频 DEATH_WISP 粒子；精英/Boss 保持完整灵光碎屑 + 冲击环）：
		if not e._no_drop:
			if e.is_elite or e.death_corpse_linger:
				var burst_scale: float = 1.8 if e.death_corpse_linger else 1.25
				var wave_r: float = 72.0 if e.death_corpse_linger else 48.0
				FxParticlePool.burst(FxParticlePool.DEATH_BURST, e.global_position, "gold", burst_scale)
				JuiceEffect.spawn_shockwave(e.get_parent(), e.global_position, wave_r, GameStyle.FX_HDR_GOLD, 0.22)
				# 幽魂消散（2026-10-19）：塌缩前一刻器尖/灵核蓄满再炸开，给厚血敌人一个「气数已尽」的收束
				FxParticlePool.burst(FxParticlePool.DEATH_WISP, e.global_position, "shadow", burst_scale, true)
	if e.is_elite:
		GameManager.kick_camera(e.knockback_velocity, GameBalance.DEATH_KICK_CAMERA)
		# 暴击斩杀精英/首领启用 HEAVY 档（此前预留未用）：更重的创伤/顿帧/缩放冲击
		if e._death_crit_kill:
			GameManager.feedback(GameManager.FeedbackTier.HEAVY)
		else:
			GameManager.feedback(GameManager.FeedbackTier.LARGE)
		# 击杀连击音阶：播音前登记本命音高基准并推阶梯（elite 基准抬半档与普通怪分层）
		AudioManager.register_kill_pitch(e.die_pitch_base * e.KILL_PITCH_ELITE_MULT)
		AudioManager.play_sfx("enemy_death_elite", 1.0)
	else:
		# 普通敌人死亡不推镜头，保持视野平稳；击杀确认感由死亡消散、音效与击杀连击音阶表达
		AudioManager.register_kill_pitch(e.die_pitch_base)
		AudioManager.play_sfx("enemy_death", 0.90)

## 掉落结算：金蟾金币、回复珠（本体/概率）、裂魂铃击杀爆炸、灵石宝石（含碎金档）。
## _no_drop（自爆/清场）整段跳过；随机一律走 GameManager.rng（玩法判定 RNG 铁律）。
static func drops(e) -> void:
	# 金蟾系：击杀额外爆金币（回合末消散/自爆不算战果）
	if e.stone_reward > 0 and not e._no_drop:
		GameManager.add_spirit_stones(e.stone_reward)
		DamageNumber.spawn(e.get_parent(), e.global_position + Vector2(0.0, -GameBalance.STONE_FLOAT_OFFSET), e.stone_reward, false, "+%d 金币" % e.stone_reward)
		AudioManager.play_sfx("gem_pickup", 0.9)

	# 精英怪专属战利品：概率掉落法宝实体 / 大额灵石偏财（无总数上限限制）
	if e.is_elite and not e._no_drop:
		var item_chance := GameBalance.elite_item_drop_chance(GameManager.luck)
		var rolled_item := false
		if GameManager.rng.randf() < item_chance:
			var item_id := ItemData.pick_id(
				GameManager.luck,
				GameManager.wave_number,
				GameManager.items_bought,
				GameManager.rng,
				GameManager.unlocked_items,
				GameManager
			)
			if not item_id.is_empty():
				rolled_item = true
				var drop_parent: Node = e.get_parent() if e.get_parent() != null else (e.get_tree().current_scene if e.get_tree() != null else null)
				if drop_parent != null:
					ItemDropEntity.spawn(drop_parent, e.global_position, item_id)
		# 未掉法宝时，按概率爆出大额灵石偏财
		if not rolled_item and GameManager.rng.randf() < GameBalance.ELITE_BONUS_STONE_CHANCE:
			var bonus_stones := GameBalance.ELITE_BONUS_STONES
			GameManager.add_spirit_stones(bonus_stones)
			var stone_parent: Node = e.get_parent() if e.get_parent() != null else (e.get_tree().current_scene if e.get_tree() != null else null)
			if stone_parent != null:
				DamageNumber.spawn(stone_parent, e.global_position + Vector2(0.0, -GameBalance.STONE_FLOAT_OFFSET), bonus_stones, false, "+%d 灵石" % bonus_stones)
			AudioManager.play_sfx("gem_pickup", 0.95)

	var gem_count = 1 if not e.is_elite else GameBalance.ELITE_GEM_COUNT
	if e._no_drop:
		gem_count = 0
	if e.heal_orb_drop > 0 and gem_count > 0:
		gem_count = 0
		# 回复珠走对象池（2026-10-11，与宝石同一条路）
		var orb := HealOrb.acquire_or_new(e.get_parent())
		orb.global_position = e.global_position
		orb.heal_amount = float(e.heal_orb_drop)
		orb.activate()
	# 灵植夫·灵药滋生：死亡按概率额外掉一颗回复珠（与本体掉落独立，不占金币位）。
	# 2026-10-21 灵草袋同走这条概率腿：角色天赋 + 道具 hook 相加后夹 100%。
	var orb_chance: float = minf(1.0, GameManager.heal_orb_chance + GameManager.item_hook_sum("heal_orb_chance"))
	if orb_chance > 0.0 and not e._no_drop and GameManager.rng.randf() < orb_chance:
		var extra_orb := HealOrb.acquire_or_new(e.get_parent())
		extra_orb.global_position = e.global_position + Vector2(
			GameManager.rng.randf_range(-GameBalance.HEAL_ORB_SCATTER_RADIUS, GameBalance.HEAL_ORB_SCATTER_RADIUS),
				GameManager.rng.randf_range(-GameBalance.HEAL_ORB_SCATTER_RADIUS, GameBalance.HEAL_ORB_SCATTER_RADIUS))
		extra_orb.heal_amount = HealOrb.BASE_HEAL
		extra_orb.activate()
	# 杀戮节奏（神通）：每次击杀返还一部分所有武器的当前冷却。
	# 与 kill_explode 同一条战果闸：回合末消散（_no_drop）不返还，清场不该白拿加速。
	# 2026-10-26：返还那一刻在每把武器根部补一记金色微闪 —— 否则玩家完全读不到
	# 「我的冷却被拉回去了」，只感觉武器好像突然变快。
	var cd_refund: float = GameManager.item_hook_sum("kill_cd_refund")
	if cd_refund > 0.0 and not e._no_drop and GameManager.player != null \
			and GameManager.player.has_method("refund_weapon_cooldowns"):
		GameManager.player.refund_weapon_cooldowns(cd_refund)
		_pulse_weapon_roots(e, GameManager.player)
	# 神通【雷劫】：尸体处向附近敌人放一道连锁闪电（固定基值 + 元素加成，见 BalanceChain）。
	# 与 kill_explode 同一条战果闸：回合末消散（_no_drop）不算击杀战果。
	# 链电自身有递归深度闸与毫秒限流：链电打死人不会再触发一层雷劫风暴。
	# 2026-10-27 电刀化：尸体只留一记小爆闪（「这具尸体炸出了电」的读数）；
	# 传导弧由 ChainLightning.strike 自动锁最近敌起跳、只画敌人↔敌人之间。
	# 旧写法从尸体向 4 个随机方向甩短弧，那些弧落在没有敌人的空气里 —— 玩家眼里的「乱线」。
	if not e._no_drop:
		var snap := StatSystem.super_hook_snapshot(GameManager)
		if float(snap.get("kill_chain_lightning", 0.0)) > 0.0:
			var hops: int = BalanceChain.MAX_HOPS + int(float(snap.get("chain_hop_bonus", 0.0)))
			var tint := GameStyle.FX_HDR_LEIJIE
			ChainLightning.strike(e.get_parent(), e.global_position, null,
				BalanceChain.kill_chain_damage(GameManager.elemental_damage), hops,
				tint, &"leijie", "chain_zap")
			JuiceEffect.spawn_bolt_pop(e.get_parent(), e.global_position, tint)
	# 裂魂铃·击杀爆炸：尸体处一记震荡，半径 = 判定（同源），伤害随元素成长（BalanceCombat 公式）。
	# 回合末消散（_no_drop）不触发：清场不算击杀战果，不该白拿爆炸链。
	# 2026-10-25 血祭盛宴重做：神通件带 kill_explode_hp_ratio（尸爆口径 —— 附加死者最大生命
	# 比例的伤害，随波封顶），裂魂铃没有该字段、仍只吃基伤 + 元素。演出升级为 ExplosionFx
	# 组合段（过曝芯 + 同源冲击环 + 血肉碎屑 + 地面焦痕），不再是一圈孤零零的细环。
	var ex_base := GameManager.item_hook_sum("kill_explode")
	if ex_base > 0.0 and not e._no_drop:
		var ex_radius := GameManager.item_hook_sum("kill_explode_radius")
		var ex_hp_ratio := GameManager.item_hook_sum("kill_explode_hp_ratio")
		var ex_dmg := BalanceCombat.kill_explode_damage(ex_base, GameManager.elemental_damage,
			float(e.max_hp), ex_hp_ratio, GameManager.wave_number) * GameManager.buff_damage_mult
		var ex_impulse := BalanceCombat.KILL_EXPLODE_IMPULSE * GameManager.knockback_mult
		var snap: Array = e._explode_snap_pool.pop_back() if not e._explode_snap_pool.is_empty() else []
		snap.append_array(GameManager.live_enemies)
		for enemy in snap:
			if enemy == null or not is_instance_valid(enemy) or enemy.dying or enemy == e:
				continue
			if enemy.is_in_group("chests") or enemy.is_in_group("herbs"):
				continue
			var ex_off: Vector2 = enemy.global_position - e.global_position
			if ex_off.length() > ex_radius:
				continue
			var ex_dir := ex_off.normalized() if ex_off.length_squared() > 0.0001 else Vector2.UP
			enemy.take_damage(ex_dmg, ex_dir * ex_impulse)
		snap.clear()
		e._explode_snap_pool.push_back(snap)
		# 演出全局限频（KILL_EXPLODE_FX_MIN_GAP_MS，2026-10-25 由 700ms 放宽到 250ms：
		# 连环爆炸正是这张卡的爽点，限太死会出现「炸了但什么都没看到」）。
		# 限频只掐演出；伤害/击退在上面照常逐次结算（玩法零改动）。
		if e._fx_gap_gate(e.KILL_EXPLODE_FX_MIN_GAP_MS, "kill_explode_fx"):
			ExplosionFx.play(e.get_parent(), e.global_position, ex_radius)
			GroundDecal.spawn(e.get_parent(), e.global_position, GroundDecal.Kind.SCORCH, ex_radius * 0.6)
			GameManager.add_trauma(0.10)
			AudioManager.play_sfx("explosion_boom", 0.8)
	for i in range(gem_count):
		# 宝石走对象池（2026-10-10 第 6 波卡顿优化）：击杀高频 instantiate/queue_free 归零
		var gem := AstralGem.acquire_or_new(e.gem_scene, e.get_tree().current_scene)
		var offset = Vector2.ZERO if gem_count == 1 else Vector2(
				GameManager.rng.randf_range(-GameBalance.GEM_SCATTER_RADIUS, GameBalance.GEM_SCATTER_RADIUS),
				GameManager.rng.randf_range(-GameBalance.GEM_SCATTER_RADIUS, GameBalance.GEM_SCATTER_RADIUS))
		gem.global_position = e.global_position + offset
		# 小怪经验走反割草补偿倍率（BalanceWave.mob_kill_exp）：预算 -20% 后单只 ×1.25 找平每波收入。
		# 精英在下面立即被 ELITE_GEM_EXP 覆写，不吃这条。金币腿（stone_value=-1 随 exp_value 同值）
		# 自动同比放大 —— 数量 ×0.8 × 单只 ×1.25 = 每波金币收入持平；碎金档显式置 1 枚不受影响。
		gem.exp_value = GameBalance.mob_kill_exp(e.exp_reward)
		gem.is_gold = e.is_elite   ## 金宝视觉统一由 is_gold 驱动（灯色在 _update_visual 里跟色）
		if e.is_elite:
			gem.exp_value = GameBalance.ELITE_GEM_EXP
		else:
			# 碎金档（2026-10-13 体验重塑）：普通怪按回合概率掉基础碎金/金砂片 ——
			# 经验腿足额给（exp_value 不动），只有金币腿折到 1，符合小怪掉零钱直觉且平抑后期通胀。
			# 精英/Boss 金宝石不 roll，保住高光时刻足额回报；碎金率见 BalanceEconomy。
			if GameManager.rng.randf() < GameBalance.gem_shard_chance(GameManager.wave_number):
				gem.is_shard = true
				gem.stone_value = GameBalance.GEM_SHARD_STONE_VALUE
		gem.activate()

## 杀戮节奏：冷却返还那一刻在每把武器根部点一记金色微闪（2026-10-26）。
## 走 JuiceEffect 的 IMPACT_POP 帧预算（6/帧），一次击杀最多点亮几把，不糊屏。
static func _pulse_weapon_roots(e, player: Node2D) -> void:
	if player == null or not is_instance_valid(player):
		return
	var holder := player.get("weapon_holder") as Node
	if holder == null or not is_instance_valid(holder):
		return
	var host: Node = e.get_parent()
	if host == null or not is_instance_valid(host):
		return
	for w in holder.get_children():
		var node := w as Node2D
		if node == null or not is_instance_valid(node):
			continue
		JuiceEffect.spawn_impact_pop(host, node.global_position, GameStyle.FX_HDR_GOLD)

## 尸体演出：停物理断碰撞、就地归位受击视觉残留，分级塌缩（小怪快/精英踉跄/Boss 滞留淡出）。
## 倾倒方向跟随致命一刀的受力侧（_hit_tilt 符号：后仰角与击退水平分量同号），垂直击杀默认右倾。
static func corpse(e) -> void:
	e.set_physics_process(false)
	e.get_node("CollisionShape2D").set_deferred("disabled", true)
	e.get_node("Hurtbox/CollisionShape2D").set_deferred("disabled", true)
	# 尸体停帧后 _tick_hit_fx / _tick_hit_visuals 都不再跑：闪白、挤压、受击微反冲一律就地归位，
	# 别让尸体挂着半截闪白或歪着半格消散
	e._squash_t = 0.0
	e.juice_scale = Vector2.ONE
	e._flash_t = 0.0
	e._flash_swap_t = 0.0
	e._hit_jiggle_offset = Vector2.ZERO
	e.anim_sprite.position = Vector2.ZERO
	if e.procedural_view != null:
		e.procedural_view.position = Vector2.ZERO
	e._write_flash_channel(0.0)

	# 死灭动画分级（2026-10-15）：小怪保持「膨胀 0.045s → 塌缩 0.14s」快节奏（高频事件不宜加重）；
	# 精英膨胀后多一段踉跄倾倒再塌缩（慢半拍，倒地有重量感）；Boss 倾倒后尸体滞留慢渐隐
	#（不缩零，谢幕读数更足）。安全性：进本段前物理/碰撞已断，回合末 dissolve() 对 dying 短路，
	# 拉长演出只多留几帧绘制，不影响回收与清场。
	var topple_sign := signf(e._hit_tilt) if e._hit_tilt != 0.0 else 1.0
	var tw = e.create_tween()
	var swell_scale: Vector2 = e.anim_base_scale * Vector2(GameBalance.CORPSE_SWELL_SCALE, GameBalance.CORPSE_SWELL_SCALE)
	tw.tween_property(e.anim_sprite, "scale", swell_scale, 0.045)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if e.procedural_view != null:
		tw.parallel().tween_property(e.procedural_view, "scale", swell_scale, 0.045)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if e.is_elite or e.death_corpse_linger:
		# 踉跄/倾倒段：精英与 Boss 共有的「慢半拍」
		var topple_rad: float = GameBalance.BOSS_DEATH_TOPPLE_RAD if e.death_corpse_linger else GameBalance.ELITE_DEATH_TOPPLE_RAD
		var topple_dur: float = 0.15 if e.death_corpse_linger else GameBalance.ELITE_DEATH_STAGGER_DUR
		tw.chain().tween_property(e.anim_sprite, "rotation", topple_sign * topple_rad, topple_dur)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if e.procedural_view != null:
			tw.parallel().tween_property(e.procedural_view, "rotation", topple_sign * topple_rad, topple_dur)\
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if e.death_corpse_linger:
		# Boss：倒地后尸体滞留一停，再只淡出不塌缩（「大妖伏诛」1.2s 消融）
		tw.chain().tween_interval(GameBalance.BOSS_DEATH_LINGER_DUR)
		tw.set_parallel(true)
		var fade_dur: float = 1.2
		tw.tween_property(e.anim_sprite, "modulate:a", 0.0, fade_dur)
		if e.procedural_view != null:
			tw.tween_property(e.procedural_view, "modulate:a", 0.0, fade_dur)
		if e.shadow_sprite != null and e.shadow_sprite.visible:
			tw.tween_property(e.shadow_sprite, "modulate:a", 0.0, fade_dur)
		e._start_dissolve(fade_dur, GameStyle.FX_HDR_GOLD, tw)
	else:
		# 小怪（0.4s）/精英（0.8s）：原地消融塌缩消散（T-3.1 接入 dissolve shader）
		var collapse_dur: float = 0.8 if e.is_elite else 0.4
		var edge_col: Color = GameStyle.FX_HDR_GOLD if e.is_elite else GameStyle.FX_HDR_SHADOW
		tw.set_parallel(true)
		tw.tween_property(e.anim_sprite, "scale", Vector2.ZERO, collapse_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(e.anim_sprite, "modulate:a", 0.0, collapse_dur)
		if e.procedural_view != null:
			tw.tween_property(e.procedural_view, "scale", Vector2.ZERO, collapse_dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_property(e.procedural_view, "modulate:a", 0.0, collapse_dur)
		e._start_dissolve(collapse_dur, edge_col, tw)
	# 尸体不再沿击退方向滑出：致命一刀既已击杀，就不该再有击退位移 ——
	# 原地塌缩才是「这一下打死了」的读数（旧斩杀击飞会在消散中把尸体推出最多 42px）
	tw.chain().tween_callback(e._recycle_or_free)
