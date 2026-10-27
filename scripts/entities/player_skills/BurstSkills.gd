class_name BurstSkills
extends RefCounted

## 全自动/额外技能的周身爆发四件套（2026-10-24 自 Player 拆出）：
## 影爆（影者额外技能）/ 盾势（守卫全自动）/ 天雷（雷法全自动）/ 药爆（药王额外技能）。
## 四者是同一代码形状：EnemyFilter 圈定 → 周身 take_damage → 冲击环演出（画多大==判多大）。
## 触发点分三类：HUD 额外技能按钮（Player.try_activate_extra_skill）、蓄满当帧
## （Player.take_damage → release_guard_stance）、计时轮询（Player._physics_process → call_thunder）。
##
## 纪律：首参 p 为宿主玩家（不标类型，鸭类型访问）。技能状态成员（shadow_ring 等）
## 仍是 Player 成员，本模块只读写不持有。

## 影爆（额外技能）：把影层里存的「刚才躲掉的那几刀」按比例折成一次周身影袭还回去，同时推开一圈怪。
## 环特效半径传的就是判定半径本身（画多大 == 判多大）；镜头只给一档轻 zoom punch（低频主动技），
## 不加震屏/顿帧——同帧叠满屏乱晃的历史教训不变。
static func release_shadow_step(p) -> void:
	if not ShadowStepData.has_charge(p.shadow_ring):
		return
	var dmg: float = ShadowStepData.burst_damage(p.shadow_ring, GameManager.wave_number)
	var impulse: float = ShadowStepData.push_impulse(p.shadow_ring) * GameManager.knockback_mult
	# 过滤口径统一走 EnemyFilter（藏宝匣/灵草/垂死一律不算敌人）
	for e in EnemyFilter.collect(GameManager.live_enemies, p.global_position, ShadowStepData.BURST_RADIUS):
		var off: Vector2 = e.global_position - p.global_position
		var dir: Vector2 = off.normalized() if off.length_squared() > 0.0001 else p._dash_dir
		e.take_damage(dmg, dir * impulse)
	JuiceEffect.spawn_shockwave(p.get_parent(), p.global_position, ShadowStepData.BURST_RADIUS,
		GameStyle.SHADOW, ShadowStepData.BURST_RING_DURATION)
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, p.global_position + Vector2(0, -10), "shadow", 1.2, true)
	AudioManager.play_sfx("whoosh_heavy", 1.0, 0.82)
	AudioManager.play_sfx("whoosh_heavy", 0.7, 0.62)  ## 降调低频层：影爆踩碎的「闷响」
	GameFeel.zoom_punch(GameManager, ShadowStepData.BURST_ZOOM_PUNCH, 0.2)
	p.shadow_ring = []
	GameManager.shadow_amp_mult = 1.0
	if p.skill_vfx != null:
		p.skill_vfx.on_shadow_spent()

## 盾势爆发（守卫·全自动）：把槽里蓄的「被护甲挡下的伤害」按比例折成一次周身震荡还回去并震开。
## 与影爆同一把尺子：环特效半径传的就是判定半径；镜头只给一档轻 zoom punch（低频爆发技），不加震屏。
## 唯一触发点是 take_damage 蓄满当帧（攒/放同一写点），槽先清零再结算，爆发期间挨的刀计入下一槽。
static func release_guard_stance(p) -> void:
	var charge: float = GameManager.shield_charge
	GameManager.shield_charge = 0.0
	if p.skill_vfx != null:
		p.skill_vfx.on_guard_burst()
	var dmg: float = GuardStanceData.burst_damage(charge)
	var impulse: float = GuardStanceData.PUSH_IMPULSE * GameManager.knockback_mult
	# 过滤口径统一走 EnemyFilter（藏宝匣/灵草/垂死一律不算敌人）
	for e in EnemyFilter.collect(GameManager.live_enemies, p.global_position, GuardStanceData.BURST_RADIUS):
		var off: Vector2 = e.global_position - p.global_position
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)
	JuiceEffect.spawn_shockwave(p.get_parent(), p.global_position, GuardStanceData.BURST_RADIUS,
		GameStyle.AURUM, GuardStanceData.BURST_RING_DURATION)
	GameFeel.zoom_punch(GameManager, GuardStanceData.BURST_ZOOM_PUNCH, 0.18)
	AudioManager.play_sfx("whoosh_heavy", 0.9, 0.72)

## 天雷（雷法真君·全自动）：引雷劈向索敌圈内最近的敌人，落点小范围震荡。
## 与盾势同一把尺子：环特效半径传的就是判定半径；不加震屏——落雷由环、跳字与击退本身表达。
## 伤害只随元素伤害成长（ThunderData.bolt_damage）× 短时增益乘区——不吃武器 tag 乘区，
## 它是道统技能不是武器；返回 false = 索敌圈内无怪（调用方走短间隔重试，不空耗整轮冷却）。
static func call_thunder(p) -> bool:
	# 索敌：过滤口径统一走 EnemyFilter，取 SEEK_RANGE 内最近的一只
	var best := EnemyFilter.nearest(GameManager.live_enemies, p.global_position, ThunderData.SEEK_RANGE)
	if best == null:
		return false
	var strike_pos: Vector2 = best.global_position
	var dmg: float = ThunderData.bolt_damage(GameManager.elemental_damage) * GameManager.buff_damage_mult
	var impulse: float = ThunderData.PUSH_IMPULSE * GameManager.knockback_mult
	for e in EnemyFilter.collect(GameManager.live_enemies, strike_pos, ThunderData.RADIUS):
		var off: Vector2 = e.global_position - strike_pos
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)
	JuiceEffect.spawn_shockwave(p.get_parent(), strike_pos, ThunderData.RADIUS,
		GameStyle.GOLD_EDGE, 0.3)
	# 天雷演出：天降神雷折线电弧穿云而落（与落点冲击环结合）
	# 2026-10-27 电刀化收尾：雷柱禁分支/余韵（allow_branch=false），空气里只留一条贯顶主干；
	# 落点补缠身电，电落在敌人身上。落点横向抖动是纯表现，改走全局 randf ——
	# 旧写法碰 GameManager.rng 会挪动后续掉落/伤害的随机序列（铁律 15）。
	var bolt_parent: Node = p.get_parent() if p.get_parent() != null else (p.get_tree().current_scene if p.get_tree() != null else p)
	if bolt_parent != null:
		var bolt := LightningBolt.acquire(bolt_parent)
		var sky_x_offset := randf_range(-24.0, 24.0)
		var sky_pos := strike_pos + Vector2(sky_x_offset, -260.0)
		bolt.activate(sky_pos, strike_pos, GameStyle.GOLD_EDGE, 1.35, Color(0, 0, 0, 0), false)
		JuiceEffect.spawn_body_arcs(bolt_parent, strike_pos, GameStyle.GOLD_EDGE)
	if p.skill_vfx != null:
		p.skill_vfx.on_thunder_cast()
	p.play_squash(Vector2(1.08, 0.92), 0.12)
	AudioManager.play_sfx("thunder_strike", 0.9, 1.0)
	return true

## 药爆（药王·额外技能）：摔碎药罐——自身回复一截生命（ElixirData.HEAL_HP_RATIO），
## 药力向周身炸开对敌人造成一次性毒伤（不挂 DoT）并推开，随附短时增伤反打窗口。
static func release_elixir(p) -> void:
	# 1. 自身回血（小治疗，直接按当前最大生命比例回复）
	var heal_val: float = ElixirData.heal_amount(p.max_health)
	p.heal(heal_val)

	# 2. 周身一次性毒雾伤害（走毒系口径：随元素伤害成长 × 短时增益乘区）
	var dmg: float = ElixirData.burst_damage(GameManager.elemental_damage) * GameManager.buff_damage_mult
	var impulse: float = ElixirData.PUSH_IMPULSE * GameManager.knockback_mult
	for e in EnemyFilter.collect(GameManager.live_enemies, p.global_position, ElixirData.BURST_RADIUS):
		var off: Vector2 = e.global_position - p.global_position
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)

	# 3. 药力反打短时增伤（ElixirData 数值）
	GameManager.buff_damage_mult = ElixirData.buff_mult()
	p._skill_buffs["elixir"] = ElixirData.BUFF_DURATION

	# 4. 视觉与音效：冲击环（画多大==判多大，GOOD 翠绿药雾色）+ 地面药圃残辉 + 随行药爆药雾粒子
	JuiceEffect.spawn_shockwave(p.get_parent(), p.global_position, ElixirData.BURST_RADIUS,
		GameStyle.GOOD, ElixirData.BURST_RING_DURATION)
	# 地面药圃残辉：毒伤范围贴地留痕（半径 = 判定半径），让按下的那一圈在地上留一拍
	var residue: Node2D = GroundDecal.spawn_tinted(p.get_parent(), p.global_position, ElixirData.BURST_RADIUS, GameStyle.GOOD)
	if residue != null:
		residue._time_left = ElixirData.GROUND_RESIDUE_SEC
	FxParticlePool.burst(FxParticlePool.HIT_SPARK, p.global_position + Vector2(0, 4), "heal", 1.1, true)
	GameFeel.zoom_punch(GameManager, ElixirData.BURST_ZOOM_PUNCH, 0.2)
	if p.skill_vfx != null:
		p.skill_vfx.on_elixir_cast()
	if p.is_procedural and p.procedural_view != null:
		p.procedural_view.set_skill_visual("renewal", true, 1.0)
	AudioManager.play_sfx("skill_heal", 1.05, 1.1)
	AudioManager.play_sfx("whoosh_heavy", 0.85, 1.25)
