extends Node

## 闪避「纸面概率 → 实际少掉多少血」兑现率诊断（非判据，只出数字表）
## 运行: $G --headless --path . res://tests/DodgeDeliveryProbe.tscn
##
## 为什么要有它：闪避在卡面上写的是「+7%/点、上限 90%」，看着像 1/(1-d) 倍的有效生命。
## 而 Player.take_damage 只有打中才设 0.55s 无敌帧 ⇒ 怪堆贴身时判定机会每帧都有，闪避若只
## 是「这一下不算」，落点频率仍被那道闸钉死 ⇒ 闪避价值强烈依赖**每秒有几次判定机会**：
## 判定流越稀（Boss 震地、妖狼长扑、敌弹这类离散大招）越接近纸面值，越密越接近白给。
## 2026-10-11 踏影上线后，闪避成功会换 ShadowStepData.GUARD_SEC 短无敌（本尺子跟着同源），
## 下面这张表就是它的验收读数：贴身档从 ×1.25 抬到多少，一眼看得见。
## 本脚本用同一条真公式（GameBalance.incoming_damage + GameManager.get_effective_dodge）
## 把两种战场都量一遍，并和「同样 8 点点生命」做机会成本对照。
##
## 口径：状态机逐字照抄 Player.take_damage 的「无敌帧门禁 → 闪避随机判定 → 护甲减伤 → 设帧」四步，
## 无敌帧长度与裸装气血现读真节点，减伤与闪避概率现读生产函数，不抄常量。

const WINDOW := 60.0        ## 每条样本的观测窗长（秒）
const SEEDS := 12           ## 重复种子数：气血 78 只够挨 3 下，单次存活秒数噪声太大
const DT := 1.0 / 60.0      ## 与真机 60Hz 对齐：判定机会按帧离散
const MOB_CONTACT := 14.0     ## 常用杂怪基础接触伤中位，与 BalanceSimCheck 同一档

var _iframe: float = 0.55
var _base_hp: float = 120.0
var _dodge_per: float = 0.07  ## 身法每点幅度（读 UpgradeData）
var _dodge_stacks: int = 8    ## 身法叠加上限

func _ready() -> void:
	_measure_real_runtime()
	_verify_dodge_uses_real_roll()
	print("")
	_table_survival()
	print("")
	_table_opportunity_cost()
	print("")
	_table_cap_cost()
	await _live_swarm_rate()
	get_tree().quit(0)

## 读真节点：无敌帧长度与裸装气血（与 BalanceSimCheck 同一把尺）
func _measure_real_runtime() -> void:
	var raw := _new_player(false)
	_base_hp = raw.max_health
	raw.free()
	var p := _new_player()
	p.invulnerable_time = 0.0
	p.current_health = _base_hp
	GameManager.dodge = 0.0
	GameManager.dodge_cap_bonus = 0.0
	p.take_damage(1.0)
	_iframe = p.invulnerable_time
	_dodge_per = float(_upgrade_apply("dodge_up", "dodge"))
	_dodge_stacks = int(UpgradeData.get_upgrade_def("dodge_up").get("max_stacks", 8))
	p.free()
	print("DODGE 实测口径：裸装气血 %.0f｜打中后无敌帧 %.2fs（顶格挨打 %.2f 下/秒）｜闪避成功不吃这 %.2fs" % [
		_base_hp, _iframe, 1.0 / _iframe, _iframe])

## pump_hp=false 用于读裸装气血默认值；true 时把血量灌满，避免测量中途真死
func _new_player(pump_hp: bool = true) -> Player:
	var scene: PackedScene = load("res://scenes/entities/Player.tscn")
	var p := scene.instantiate() as Player
	add_child(p)
	GameManager.is_game_over = false
	GameManager.armor = 0.0
	GameManager.synergy_armor = 0.0
	GameManager.dodge_cap_bonus = 0.0
	if pump_hp:
		p.max_health = 100000.0
		p.current_health = 100000.0
	return p

## 实证：闪避随机判定确实走 GameManager.get_effective_dodge()，且成功时不设无敌帧
func _verify_dodge_uses_real_roll() -> void:
	var p := _new_player()
	GameManager.rng = RandomNumberGenerator.new()
	GameManager.rng.seed = 20261011
	GameManager.dodge = 0.5
	var rolls := 400
	var landed := 0
	for i in range(rolls):
		p.invulnerable_time = 0.0
		var hp_before: float = p.current_health
		p.take_damage(10.0)
		if p.current_health < hp_before:
			landed += 1
	p.free()
	print("DODGE 真路径核对：dodge=50%% 时 %d 次判定实际掉血 %d 次（%.1f%%，纸面 50.0%%）⇒ 随机判定与减伤走的就是生产那一条" % [
		rolls, landed, float(landed) / float(rolls) * 100.0])

## 单条样本：给定闪避与判定密度，量「每秒实际挨几下」（气血与伤害量不影响状态机，只数落点）
## cap_bonus 默认按影者的上限抬升（0.6 + 0.3 = 0.9），否则高档位会被常规上限截断
func _hit_rate(dodge: float, roll_rate: float, horizon: float, seeds: int, cap_bonus: float = 0.30) -> float:
	GameManager.dodge = dodge
	GameManager.dodge_cap_bonus = cap_bonus
	var d := GameManager.get_effective_dodge()
	var hits := 0
	var per_step: float = roll_rate * DT
	for s in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + s
		var invuln := 0.0
		var t := 0.0
		while t < horizon:
			t += DT
			invuln = maxf(0.0, invuln - DT)
			if invuln > 0.0:
				continue
			if rng.randf() >= per_step:
				continue
			if rng.randf() < d:
				# 闪避成功：不掉血，换一段「残影」短无敌（与 Player.take_damage 同读一个常量）
				invuln = maxf(invuln, ShadowStepData.GUARD_SEC)
				continue
			hits += 1
			invuln = _iframe
	return float(hits) / (horizon * float(seeds))

func _dodge_ladder() -> Array:
	var out: Array = []
	out.append([0.0, "0%（默认修士裸装）"])
	for s in range(0, _dodge_stacks + 1):
		out.append([0.30 + _dodge_per * float(s), "30%%+%d点 = %.0f%%" % [s, (0.30 + _dodge_per * s) * 100.0]])
	out.append([0.92, "8点身法+凌波靴 = 顶到 90%"])
	return out

func _table_survival() -> void:
	var hp: float = _base_hp * 0.65      ## 影者气血
	var raw := _raw(20)
	var per_hit: float = GameBalance.incoming_damage(raw, 0.0)
	print("DODGE 兑现率（影者气血 %.0f = 裸装 %.0f×0.65｜护甲 0（加点锁死）｜第 20 波单下 %.0f｜危险度 0）" % [
		hp, _base_hp, per_hit])
	print("  读数 = 每秒实际挨几下（%.0fs × %d 种子均值，影者上限已抬到 %.0f%%）｜有效生命倍率 = 闪避0的挨打频率 ÷ 本档频率" % [
		WINDOW, SEEDS, (GameManager.DODGE_CAP + 0.30) * 100.0])
	print("  %-26s %-20s %-20s %-20s" % ["闪避", "稀疏 2 次判定/秒", "中密 10 次/秒", "贴身怪群 60 次/秒"])
	for row in _dodge_ladder():
		var d: float = float(row[0])
		var line: String = "  %-26s" % String(row[1])
		for rate in [2.0, 10.0, 60.0]:
			var h0: float = _hit_rate(0.0, rate, WINDOW, SEEDS)
			var h: float = _hit_rate(d, rate, WINDOW, SEEDS)
			var mult := h0 / maxf(0.0001, h)
			line += " %4.2f下/s ×%4.2f" % [h, mult]
		line += "  纸×%.2f" % (1.0 / maxf(0.02, 1.0 - minf(d, 0.90)))
		print(line)
	print("  ⇒ 判定越密，实测倍率离纸面越远：这一段无敌只是把落点往后推，推得越多说明闪得越勤")
	print("  ⇒ 换成存活秒数（%.0f 血 ÷ 单下 %.0f）：贴身怪群里 0%% 闪避活 %.1fs、86%% 活 %.1fs；" % [hp, per_hit,
		hp / per_hit / _hit_rate(0.0, 60.0, WINDOW, SEEDS), hp / per_hit / _hit_rate(0.86, 60.0, WINDOW, SEEDS)])
	print("     稀疏战场（2 次/秒）同一档闪避从 %.1fs 到 %.1fs ⇒ 闪避值多少，取决于你让不让怪贴上来" % [
		hp / per_hit / _hit_rate(0.0, 2.0, WINDOW, SEEDS), hp / per_hit / _hit_rate(0.86, 2.0, WINDOW, SEEDS)])

## 机会成本：同样 8 点点在哪，影者在三种战场各得多少
func _table_opportunity_cost() -> void:
	var hp_per: float = _upgrade_apply("hp_up", "max_hp")
	var hp: float = _base_hp * 0.65
	var raw := _raw(20)
	var per_hit: float = GameBalance.incoming_damage(raw, 0.0)
	var dodge_full: float = minf(0.90, 0.30 + _dodge_per * float(_dodge_stacks))
	var armor_per: float = _upgrade_apply("armor_up", "armor")
	print("DODGE 机会成本（8 点悟道点花在生存上，第 20 波单下 %.0f，存活秒数 = 气血 ÷（单下 × 每秒挨打数））" % per_hit)
	print("  %-14s %-14s %-14s %-14s" % ["判定密度", "只吃初始30%", "8点身法→86%", "8点生命→+200"])
	for rate in [2.0, 10.0, 60.0]:
		var t0: float = hp / per_hit / maxf(0.0001, _hit_rate(0.30, rate, WINDOW, SEEDS))
		var t_dodge: float = hp / per_hit / maxf(0.0001, _hit_rate(dodge_full, rate, WINDOW, SEEDS))
		var t_hp: float = (hp + float(_dodge_stacks) * hp_per) / per_hit \
			/ maxf(0.0001, _hit_rate(0.30, rate, WINDOW, SEEDS))
		print("  %-14s %-14s %-14s %-14s" % ["%.0f 次/秒" % rate,
			"%.1fs" % t0, "%.1fs ×%.2f" % [t_dodge, t_dodge / t0], "%.1fs ×%.2f" % [t_hp, t_hp / t0]])
	var t0d: float = hp / per_hit / maxf(0.0001, _hit_rate(0.30, 10.0, WINDOW, SEEDS))
	var t_armor: float = hp / maxf(1.0, GameBalance.incoming_damage(raw, float(_dodge_stacks) * armor_per)) \
		/ maxf(0.0001, _hit_rate(0.30, 10.0, WINDOW, SEEDS))
	print("  对照（影者锁死的那条）：8 点护甲(+%.0f) 在 10 次/秒战场 = %.1fs ×%.2f ⇒ 他被锁的正是性价比最高的生存点" % [
		float(_dodge_stacks) * armor_per, t_armor, t_armor / t0d])

## 上限 90% 的票价
func _table_cap_cost() -> void:
	var item_dodge: float = float(ItemData.DEFS.get("lingbo_xue", {}).get("apply", {}).get("dodge", 0.0))
	var total_picks := 19                       ## BalanceSimCheck 口径：第 20 波前共 19 次悟道
	var need_raw := int(ceilf((0.90 - 0.30) / _dodge_per))
	var need_with_item := int(ceilf((0.90 - 0.30 - item_dodge) / _dodge_per))
	var to_normal := int(ceilf((0.60 - 0.30) / _dodge_per))
	print("DODGE 上限票价：身法每点 +%.0f%%、max_stacks %d ⇒ 影者 30%% 起叠满 = %.0f%%" % [
		_dodge_per * 100.0, _dodge_stacks, (0.30 + _dodge_per * float(_dodge_stacks)) * 100.0])
	print("  顶到 90%% 需 %d 点身法%s；再加凌波靴 +%.0f%% 也只要 %d 点" % [
		need_raw, "（超 max_stacks，必须靠法宝补差额）" if need_raw > _dodge_stacks else "",
		item_dodge * 100.0, need_with_item])
	print("  一局约 %d 次悟道 ⇒ 光闪避吃 %.0f%% 的加点次数；而到常规上限 60%% 只需 %d 点" % [
		total_picks, float(mini(need_with_item, _dodge_stacks)) / float(total_picks) * 100.0, to_normal])
	print("  ⇒ 「上限 90%%」比「上限 60%%」多出的那 30%% 额度，票价是 %d 点悟道 = 全局加点的 %.0f%%" % [
		need_with_item - to_normal, float(need_with_item - to_normal) / float(total_picks) * 100.0])

func _raw(wave: int) -> float:
	return ceilf(MOB_CONTACT * GameBalance.enemy_dmg_mult(wave) * GameBalance.danger_dmg_mult(0))

func _upgrade_apply(upgrade_id: String, field: String) -> float:
	var apply: Dictionary = UpgradeData.get_upgrade_def(upgrade_id).get("apply", {})
	return float(apply.get(field, 0.0))

# ---------------- 活体标定：真怪群里每秒实际挨几下 ----------------

const SWARM_N := 14          ## 围上来的小怪数
const SWARM_WAVE := 12       ## 按第 12 波缩放
const SWARM_SEC := 5.0      ## 每轮采样窗长（秒）
const WARM_SEC := 1.0       ## 包围预热，不计入采样
const REPS := 2             ## 轮数（headless 下 physics 不吃 time_scale，轮数只能少）
const TIME_SCALE := 1.0      ## 实测 headless 下 physics 不跟 time_scale 走，保持 1.0 免得读数口径骗人

## 站进怪群里不动，量「实际落点频率」。这条决定上面那张表该看哪一列：
## 若实测 ≈ 1/0.55 = 1.82 下/秒 ⇒ 无敌帧已经饱和，闪避只兑现「右列」那点；
## 若实测远低于 1.82 ⇒ 判定流本来就稀，闪避接近纸面值。
func _live_swarm_rate() -> void:
	SettingsManager.set_val(&"display", &"hit_stop", false, false)
	Engine.time_scale = TIME_SCALE
	var world := Node2D.new()
	world.name = "SwarmWorld"
	add_child(world)          # 挂自己名下：root 此刻还在 _ready 里摆子节点
	await get_tree().physics_frame

	var player: Player = load("res://scenes/entities/Player.tscn").instantiate() as Player
	world.add_child(player)
	player.global_position = Vector2.ZERO
	player.max_health = 999999.0
	player.current_health = 999999.0
	GameManager.is_game_over = false
	GameManager.wave_number = SWARM_WAVE
	GameManager.armor = 0.0
	GameManager.synergy_armor = 0.0
	GameManager.dodge_cap_bonus = 0.30
	await get_tree().physics_frame

	print("DODGE 活体标定：%d 只杂怪围住站着不动的玩家（第 %d 波缩放，护甲 0，%.0f 游戏秒采样）" % [
		SWARM_N, SWARM_WAVE, SWARM_SEC])
	for i in range(SWARM_N):
		var e: EnemyBase = load("res://scenes/entities/SlimeEnemy.tscn").instantiate() as EnemyBase
		var ang := TAU * float(i) / float(SWARM_N)
		e.global_position = player.global_position + Vector2(cos(ang), sin(ang)) * 150.0
		e.max_hp = ceilf(e.max_hp * GameBalance.enemy_hp_mult(SWARM_WAVE))
		e.contact_damage = ceilf(e.contact_damage * GameBalance.enemy_dmg_mult(SWARM_WAVE))
		e.add_to_group("enemies")
		world.add_child(e)
	await get_tree().physics_frame

	var samples := {0.0: [], 0.86: []}
	for rep in range(REPS):
		for key in [0.0, 0.86]:
			GameManager.dodge = key
			player.current_health = 999999.0
			player.invulnerable_time = 0.0
			GameManager.total_damage_taken_count = 0
			var warm := 0.0
			while warm < WARM_SEC:                 # 先让怪挤上来，别把包围过程算进采样
				await get_tree().physics_frame
				warm += get_physics_process_delta_time()
			var t := 0.0
			while t < SWARM_SEC:
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
				player.current_health = 999999.0   # 只数落点，不让死掉清场
			samples[key].append(float(GameManager.total_damage_taken_count) / maxf(0.001, t))

	var saturation := 1.0 / _iframe
	var means := {}
	for key in [0.0, 0.86]:
		var arr: Array = samples[key]
		var mean := 0.0
		var detail := ""
		for v in arr:
			mean += float(v)
			detail += " %.2f" % float(v)
		means[key] = mean / float(arr.size())
		print("  闪避 %-5s 实测 %.2f 下/秒（%d 轮:%s）｜无敌帧饱和线 %.2f 下/秒 ⇒ 已用掉 %.0f%%" % [
			"86%" if key > 0.0 else "0%", means[key], arr.size(), detail.strip_edges(),
			saturation, means[key] / saturation * 100.0])
	print("  ⇒ 站进怪群里，闪避 0%% 与 86%% 的落点频率 %.2f vs %.2f 下/秒（差 %.0f%%，纸面写着差 86%%）" % [
		means[0.0], means[0.86], (1.0 - means[0.86] / maxf(0.001, means[0.0])) * 100.0])
	print("  ⇒ 闪避 0% 就贴着饱和线 = 贴身时每帧都在判定；抬上去后落点频率降了多少，"
		+ "就是那段残影无敌真正买到的东西（纸面概率在这里只算一次，不重复计价）")
	Engine.time_scale = 1.0
	player.queue_free()
	world.queue_free()
	await get_tree().physics_frame
