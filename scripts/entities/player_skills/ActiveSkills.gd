class_name ActiveSkills
extends RefCounted

## 主动技能实现五连（2026-10-24 自 Player 拆出）：冲刺/罡风/急速/金光护体/回春。
## 分发在 Player.try_activate_skill 的 match（SkillData.Kind.*），短时乘区到期回滚在
## Player._tick_skill_buffs / _on_skill_effect_end（读侧归 Player，写侧在这里）。
##
## 纪律：首参 p 为宿主玩家（不标类型，鸭类型访问）。技能状态成员（_dash_dir/_skill_buffs/
## _gale_cap_* 等）仍是 Player 成员，本模块只读写不持有。

const SPIRIT_HEALER_SCENE: PackedScene = preload("res://scenes/entities/SpiritHealer.tscn")  ## 治疗灵兽（renewal 附带召唤）
## 落地震开的精英韧性：与 EnemyBase.HIT_KB_ELITE_SCALE 同值同口径（大体格推不动）。
## 不复用那个常量是有意的 —— ActiveSkills 已被 Player 引用，而 EnemyBase 又引用 Player，
## 这里再直引 EnemyBase 会在既有类循环上再加一条边（踩过「循环依赖把 PackedScene 打成空」的坑）。
const SHOVE_ELITE_SCALE := 0.55

## 无输入时按当前朝向给冲刺方向（facing + flip_h 还原 8 方向单位向量）
static func facing_vec(p) -> Vector2:
	var right := Vector2.LEFT if p.anim_sprite.flip_h else Vector2.RIGHT
	match p.facing:
		"n":
			return Vector2.UP
		"s":
			return Vector2.DOWN
		"e":
			return right
		"se":
			return (Vector2.DOWN + right).normalized()
		"ne":
			return (Vector2.UP + right).normalized()
	return Vector2.DOWN

static func dash(p, st: Dictionary) -> void:
	var dir: Vector2 = Vector2.ZERO
	if GameManager.joystick != null and GameManager.joystick.has_method("get_direction"):
		dir = GameManager.joystick.get_direction()
	if dir.length_squared() < 0.03:
		# 松手冲刺：沿当前惯性方向；站定则沿面朝方向
		dir = p.velocity.normalized() if p.velocity.length_squared() > 900.0 else facing_vec(p)
	p._dash_dir = dir.normalized()
	p._dash_time = float(st["duration"])
	p._dash_speed = float(st["distance"]) / maxf(0.05, p._dash_time)
	# 无敌覆盖位移全程 + 落地脱身余量（时长唯一真话在 SkillData 的 iframe 字段），落点瞬间不吃贴脸伤害
	# 影层被动：每层再加一段无敌（影在身上时冲刺更稳）——影层兑现不在这里，影爆是独立技能
	p.invulnerable_time = maxf(p.invulnerable_time,
		float(st.get("iframe", p._dash_time + 0.04)) + ShadowStepData.iframe_bonus(p.shadow_ring))
	# 冲刺攻势：起跳即开必暴窗口（roll_crit 消费，覆盖冲刺与落地追击的两拍输出）
	GameManager.force_crit_left = maxf(GameManager.force_crit_left, float(st.get("crit_window", 0.0)))
	# 技能重置普攻（薇恩 Q 式）：翻滚期间先压住武器起手，落地那一帧才清间隔放行，
	# 于是「滚动 → 落地 → A 出去」三拍分明；冲刺自带的必暴窗口正好兑现落地这一刀。
	# 字段在 SkillData，只有闪避带了这一条。
	if int(st.get("attack_reset", 0)) > 0:
		p._set_weapon_fire_held(true)
	p.play_squash(Vector2(1.3, 0.72), 0.2)
	JuiceEffect.spawn_step_dust(p.get_parent(), p.global_position + Vector2(0, 14), p._dash_dir * p._dash_speed)
	if p.skill_vfx != null:
		p.skill_vfx.on_dash_start(p._dash_dir, float(st["distance"]), p._dash_time, float(st.get("crit_window", 1.0)))
	if p.is_procedural and p.procedural_view != null:
		p.procedural_view.play_dash(p._dash_time)
	AudioManager.play_sfx("skill_dash", 1.0)

## 落地震开（用户现场 2026-10-24：闪到怪脸上 → 无敌余量只剩 ~0.19s → 帧末立刻吃接触伤）。
## 落点圈内的敌人沿「远离玩家」方向推开并短时定身，把「落地即挨打」换成「有一拍脱身」。
## 只推不伤，位移走 EnemyBase.apply_vortex_pin（受击硬直滑行段 + 钉身）：
## 不走 take_damage(0.0, ...) —— 那条路会给目标记一次集火保护（0.22s 内下一刀 ×0.70），
## 正好削掉闪避落地那记必暴刀，还会跳「0」字、放命中音。数值与判定半径在 SkillData.dash 的
## land_push_* 字段；环特效半径 = 判定半径（画多大 == 判多大）。
static func dash_land_shove(p) -> void:
	var st := SkillData.final_stats("dash", GameManager.cultivator_id)
	var radius: float = float(st.get("land_push_radius", 0.0))
	var impulse: float = float(st.get("land_push_impulse", 0.0))
	var stun: float = float(st.get("land_push_stun", 0.0))
	if radius <= 0.0 or impulse <= 0.0 or stun <= 0.0:
		return
	var push: float = impulse * GameManager.knockback_mult
	var shoved := 0
	# 过滤口径统一走 EnemyFilter（藏宝匣/灵草/垂死一律不算敌人）
	for e in EnemyFilter.collect(GameManager.live_enemies, p.global_position, radius):
		var off: Vector2 = e.global_position - p.global_position
		# 与玩家重合时没有径向可言：沿冲刺朝向推（与影爆的退化口径一致，绝不会推向玩家）
		var dir: Vector2 = off.normalized() if off.length_squared() > 0.0001 else p._dash_dir
		# 精英/Boss 抗震开：与武器击退同一把尺子（大体格推不动），硬直同时打折
		var resist: float = SHOVE_ELITE_SCALE if e.is_elite else 1.0
		if e.death_corpse_linger:  # Boss 标记（基类不反向引用 BossEnemy，同 EnemyBase._die 口径）
			resist *= GameBalance.BOSS_KNOCKBACK_RESIST
		e.apply_vortex_pin(dir * push * resist, stun * resist)
		shoved += 1
	if shoved <= 0:
		return
	var parent_node: Node = p.get_parent() if p.get_parent() != null else (p.get_tree().current_scene if p.get_tree() != null else p)
	if parent_node != null:
		JuiceEffect.spawn_shockwave(parent_node, p.global_position, radius,
			Color(GameStyle.FX_HDR_WATER.r, GameStyle.FX_HDR_WATER.g, GameStyle.FX_HDR_WATER.b, 0.6), 0.20)

static func gale(p, st: Dictionary) -> void:
	GameManager.buff_move_speed_mult = 1.0 + float(st["power"])
	# 罡风护身：加速期间身法闪避大幅提升（到期与移速乘区同帧精确归零）
	var dodge_add: float = float(st.get("dodge_add", 0.0))
	GameManager.buff_dodge = dodge_add
	# 100% 闪避（影者契合）：角色抬升只到 90% 的硬上限会把它截成 90% ⇒ 期间把上限临时
	# 抬到 1.0，buff 走完由 Player._tick_skill_buffs 按抬升前的原值精确还原（与 buff_dodge 同帧，不留残留）
	const FULL_DODGE_EPS := 0.0001
	p._gale_cap_forced = dodge_add >= 1.0 - FULL_DODGE_EPS
	if p._gale_cap_forced:
		p._gale_cap_before = GameManager.dodge_cap_bonus
		GameManager.dodge_cap_bonus = maxf(GameManager.dodge_cap_bonus, 1.0 - GameManager.DODGE_CAP)
	p._skill_buffs["gale"] = float(st["duration"])
	p.play_squash(Vector2(0.85, 1.2), 0.2)
	if p.skill_vfx != null:
		p.skill_vfx.on_gale_start(float(st["duration"]))
	AudioManager.play_sfx("skill_buff", 1.0)

static func haste(p, st: Dictionary) -> void:
	GameManager.buff_attack_speed_mult = maxf(GameManager.ATTACK_SPEED_FLOOR, 1.0 - float(st["power"]))
	p._skill_buffs["haste"] = float(st["duration"])
	p.play_squash(Vector2(1.12, 0.9), 0.18)
	if p.skill_vfx != null:
		p.skill_vfx.on_haste_start(float(st["duration"]))
	AudioManager.play_sfx("skill_buff", 1.1)

static func aegis(p, st: Dictionary) -> void:
	var dur: float = float(st["duration"])
	p.invulnerable_time = maxf(p.invulnerable_time, dur)
	# 金光护体：无敌期间武器击退力度大幅提升、吸血触发概率提升（活跃窗口走完由 _on_skill_effect_end 精确回滚）
	GameManager.buff_knockback_mult = float(st.get("knockback_boost", 1.0))
	GameManager.buff_lifesteal_boost = float(st.get("lifesteal_boost", 0.50))
	p.play_squash(Vector2(0.82, 1.22), 0.24)
	if p.skill_vfx != null:
		p.skill_vfx.on_aegis_start(dur)
	AudioManager.play_sfx("skill_aegis", 1.0)
	# 护体罡风爆发：开启瞬间主动震开周身贴身敌人并造成金光震荡伤害
	repel_aegis_surroundings(p)

## 金光护体震开周身敌人并造成金光震荡伤害（开盾瞬间解围脱困）
static func repel_aegis_surroundings(p) -> void:
	var repel_radius := 120.0
	var impulse: float = 280.0 * GameManager.knockback_mult
	var dmg: float = 20.0 * GameManager.get_weapon_damage_mult() * GameManager.buff_damage_mult
	for e in EnemyFilter.collect(GameManager.live_enemies, p.global_position, repel_radius):
		var off: Vector2 = e.global_position - p.global_position
		var dir := off.normalized() if off.length_squared() > 0.0001 else Vector2.UP
		e.take_damage(dmg, dir * impulse)
	var parent_node: Node = p.get_parent() if p.get_parent() != null else (p.get_tree().current_scene if p.get_tree() != null else p)
	if parent_node != null:
		JuiceEffect.spawn_shockwave(parent_node, p.global_position, repel_radius, GameStyle.GOLD_FX_EDGE, 0.28)

static func renewal(p, st: Dictionary) -> void:
	p.heal(p.max_health * float(st["power"]), true)
	p.play_squash(Vector2(0.88, 1.16), 0.18)
	DamageNumber.spawn(p.get_parent(), p.global_position, int(p.max_health * float(st["power"])), false, "+" + str(int(p.max_health * float(st["power"]))) + " HP")
	summon_spirit_healer(p, st)
	if p.skill_vfx != null:
		p.skill_vfx.on_renewal_cast()
	AudioManager.play_sfx("skill_heal", 1.0)
	AudioManager.play_sfx("heal", 0.65, 1.15)  ## 回血确认音（heal 走了 quiet 通道吞掉原音，这里低声叠回）

## 治疗灵兽：治疗技能附带召唤（SkillData renewal 的 pet_* 字段），跟随玩家周期回血；重施按组替换旧灵
static func summon_spirit_healer(p, st: Dictionary) -> void:
	var pet_pct := float(st.get("pet_heal_pct", 0.0))
	var pet_life := float(st.get("pet_duration", 0.0))
	if pet_pct <= 0.0 or pet_life <= 0.0:
		return
	var old: Node = p.get_tree().get_first_node_in_group("spirit_healers")
	if old != null:
		# 先出组再销毁：queue_free 要到帧末才真正释放，同帧重施必须立刻能拿到新灵
		old.remove_from_group("spirit_healers")
		old.queue_free()
	var pet := SPIRIT_HEALER_SCENE.instantiate() as SpiritHealer
	if pet == null:
		return
	pet.heal_pct = pet_pct
	pet.lifetime = pet_life
	pet.target = p
	p.get_parent().add_child(pet)
	pet.global_position = p.global_position + Vector2(0, -SpiritHealer.HEIGHT_OFFSET)
