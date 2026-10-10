extends Node

## 远程弹丸「命中兑现」判据。分两段：
##
## A 段（有牙齿的那条）：场上只留一个真敌人，让它绕玩家做 300px 半径的匀速横切（对直线弹最狠的走位），
##   满槽 6 件弹丸法器连开十几秒 ⇒ 场上只有这一个目标，"打中任何一个"就等于"打中咬定的那一个"，
##   落空率量得干净。旧直线弹在这段普遍打空（离线仿真：300px 处命中约三成，横切冲刺 0%）。
## B 段（灾难兜底 + 读数）：恢复刷怪跳 12 波尸潮真打一场，报整体命中率、每发平均结算敌数、按距离档的落空分布。
##
## 为什么要单独建这条判据（2026-10-08 用户口径：「一些远程且只能击中一个敌人的武器需要加强一下，
## 火符比其他武器要弱很多」）：近战弧扫当帧结算、环绕法宝接触即伤，都不存在"打不中"；弹丸是飞过去的，
## 纸面 DPS 与真 DPS 之间有一笔看不见的税。数据表改多少数字都收不掉这笔税，所以这里量"打出去的真结到人身上没有"。
## B 段单独用会漏判 —— 怪一密，直线弹乱飞也蹭得到人（实测关掉追踪仍有 98.3%），所以牙齿必须放在 A 段。
##
## 弹丸消失方式的分类口径：lifetime 归零 = 飞完寿命一发未中（落空）；lifetime 未归零就消失 = 命中后穿透耗尽被没收。
##
## 运行: godot --headless --path . res://tests/ProjectileProbe.tscn
##       godot --headless --path . res://tests/ProjectileProbe.tscn -- --no-homing      # 反例：A 段必须红
##       ... -- --weapon xuanbing_feizhen --wave 14                                     # 换法器/波次看读数

const BANDS := ["<150", "150-250", "250-350", "350+"]

const LONE_DISTANCE := 300.0        ## A 段目标到玩家的半径：弹丸飞 0.64s，敌人已横移 70+px
const LONE_SPEED := 110.0           ## 横切线速度（史莱姆基础移速量级）
const LONE_SECONDS := 12.0
const MIN_A_HIT_RATE := 0.90        ## A 段（孤立横切目标）：追踪上线后实测 100%，关掉追踪 13.3%
const MIN_B_HIT_RATE := 0.88        ## B 段是灾难兜底：尸潮里锁定的目标常被别的法器打死（换目标要重锁），
                                   ## 实测开追踪 93.8%、关追踪 85.0% —— 下限取在两者之间
const MIN_A_SHOTS := 30
const MIN_SHOTS := 50               ## B 段样本下限（不足说明这局没打几发，判据不许静默通过）
const MIN_HITS_PER_SHOT := 0.95     ## B 段：每发平均至少结算一个敌人

var _weapon_id: String = "huoyan_fu"
var _wave: int = 12
var _star: int = 1
var _sample_seconds: float = 18.0
var _selftest: bool = false

var _c := TestCheck.new()
var _seen: Dictionary = {}          ## instance_id -> 最近一帧读到的弹丸状态
var _shots: int = 0
var _whiffs: int = 0                ## 落空发数
var _hit_units: int = 0             ## 累计结算到的敌人个数
var _band_shots: Array[int] = [0, 0, 0, 0]
var _band_whiffs: Array[int] = [0, 0, 0, 0]
var _a_shots: int = 0               ## A 段单独记账，别让尸潮把单挑的数字冲淡
var _a_whiffs: int = 0
var _phase_lone: bool = false
var _strafe: Node2D = null
var _strafe_ang: float = 0.0

func _ready() -> void:
	set_physics_process(false)
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if String(args[i]) == "--no-homing":
			_selftest = true
		elif i + 1 < args.size():
			match String(args[i]):
				"--weapon": _weapon_id = String(args[i + 1])
				"--wave": _wave = int(String(args[i + 1]))
				"--star": _star = int(String(args[i + 1]))
				"--seconds": _sample_seconds = float(String(args[i + 1]))
	BladeProjectile.homing_scale = 0.0 if _selftest else 1.0
	if _selftest:
		print("[INFO] 反例模式：homing_scale=0（退回旧的直线弹），A 段命中兑现率必须跌破下限")
	call_deferred("_run")

func _physics_process(delta: float) -> void:
	_scan()
	if _phase_lone and _strafe != null and is_instance_valid(_strafe) and GameManager.player != null:
		# 匀速圆周横切：位置逐帧覆写，敌人自己的 AI（move_speed 已钉 0）插不上手
		_strafe_ang += (LONE_SPEED / LONE_DISTANCE) * delta
		_strafe.global_position = GameManager.player.global_position \
			+ Vector2(cos(_strafe_ang), sin(_strafe_ang)) * LONE_DISTANCE

## 从 root 递归扫 BladeProjectile：本 runner 把 Main 挂在 root 下，而弹丸是
## add_child 到池宿主（挂 current_scene 下），只扫 main 会一个都扫不到。
## 池化后（2026-10-10）弹丸实例会休眠复用：跳过回池的（visible=false），并按
## launch_id 而不是 instance_id 记账 —— 同一实例的第二次发射是一发新弹。
func _scan() -> void:
	var found: Dictionary = {}
	_collect(get_tree().root, found)
	for id in found.keys():
		var p: BladeProjectile = found[id]
		if not _seen.has(id):
			_seen[id] = {
				"life": p.lifetime,
				"p0": p.pierce_left, "b0": p.bounce_left,
				"pierce": p.pierce_left, "bounce": p.bounce_left,
				"aim": _nearest_enemy_dist(p.global_position),
				"phase": _phase_lone,
			}
			_shots += 1
			_band_shots[_band_of(float(_seen[id]["aim"]))] += 1
			if _phase_lone:
				_a_shots += 1
		else:
			_seen[id]["life"] = p.lifetime
			_seen[id]["pierce"] = p.pierce_left
			_seen[id]["bounce"] = p.bounce_left
	for id in _seen.keys().duplicate():
		if found.has(id):
			continue
		var rec: Dictionary = _seen[id]
		_seen.erase(id)
		# 弹丸可能「出膛→命中→回收」全发生在两次扫描之间，pf 缓存读不到终值；
		# _recycle 会把真实终值登记到 _final_stats，优先用它结账
		var pf: int = int(rec["pierce"])
		var bf: int = int(rec["bounce"])
		var final: Dictionary = BladeProjectile._final_stats.get(id, {})
		if not final.is_empty():
			pf = int(final["pierce"])
			bf = int(final["bounce"])
			BladeProjectile._final_stats.erase(id)
		var hits: int = (int(rec["p0"]) - pf) + (int(rec["b0"]) - bf)
		_hit_units += hits
		if hits == 0:
			_whiffs += 1
			_band_whiffs[_band_of(float(rec["aim"]))] += 1
			if bool(rec["phase"]):
				_a_whiffs += 1
			if OS.has_environment("PERF_DEBUG"):
				print("[WHIFF] id=%s p0=%s pf=%s b0=%s bf=%s aim=%.0f" % [
					str(id), str(rec["p0"]), str(pf), str(rec["b0"]), str(bf), float(rec["aim"])])

func _collect(node: Node, out: Dictionary) -> void:
	for ch in node.get_children():
		if ch is BladeProjectile and is_instance_valid(ch) and not ch._pooled and ch.launch_id >= 0:
			out[ch.launch_id] = ch
		_collect(ch, out)

func _nearest_enemy_dist(from: Vector2) -> float:
	var best := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			var d := from.distance_to((e as Node2D).global_position)
			if d < best:
				best = d
	return best

func _band_of(dist: float) -> int:
	if dist < 150.0:
		return 0
	if dist < 250.0:
		return 1
	if dist < 350.0:
		return 2
	return 3

func _run() -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _c.check(is_instance_valid(main), "主场景已进树"):
		_finish()
		return

	GameManager.cultivator_id = "fuzhen"
	GameManager.start_run(_weapon_id)
	get_tree().paused = false
	if not _c.check(GameManager.player != null and is_instance_valid(GameManager.player), "玩家已生成（本命法器已上阵）"):
		_finish()
		return
	if GameManager.player != null:
		GameManager.player.max_health = 999999.0
		GameManager.player.current_health = 999999.0
	var def := WeaponData.get_def(_weapon_id)
	print("PROBE weapon=%s(%s) behavior=%s star=%d dmg=%.0f cd=%.2f pierce=%s count=%s homing_scale=%.2f" % [
		_weapon_id, def.get("name", "?"), str(int(def.get("behavior", -1))), _star,
		WeaponData.damage_for(_weapon_id, _star), WeaponData.cooldown_for(_weapon_id, _star),
		str(def.get("pierce", "-")), str(def.get("projectile_count", "-")), BladeProjectile.homing_scale])
	if int(def.get("behavior", -1)) != WeaponData.Behavior.PROJECTILE:
		_c.check(false, "本判据只量弹丸类法器，%s 的 behavior=%s" % [_weapon_id, str(def.get("behavior", "-"))])
		_finish()
		return

	await _phase_a()
	await _phase_b()
	_finish()

## A 段：清场 → 只留一个做圆周横切的真敌人 → 满槽弹丸连开 LONE_SECONDS 秒
func _phase_a() -> void:
	GameManager.wave_spawner.set_physics_process(false)
	GameManager.wave_spawner.set_process(false)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node2D:
			(e as Node2D).queue_free()
	for i in range(3):
		await get_tree().process_frame
	if GameManager.player != null:
		GameManager.player.global_position = Vector2.ZERO
	GameManager.joystick = null      # 玩家站定（摘掉摇杆后 Player 回落读键盘 = 零输入），几何才可控
	while GameManager.slots_used() < GameManager.max_weapon_slots():
		if not GameManager.add_weapon(_weapon_id, _star):
			break
	var enemy = load("res://scenes/entities/SlimeEnemy.tscn").instantiate()
	enemy.max_hp = 999999.0
	enemy.exp_reward = 0             # 单挑段不许攒修为，免得升级弹窗把这一段的火力换掉
	enemy.move_speed = 0.0           # AI 不许自己走，走位由本判据逐帧覆写
	GameManager.wave_spawner.get_parent().add_child(enemy)
	_strafe = enemy as Node2D
	_strafe_ang = 0.0
	_strafe.global_position = GameManager.player.global_position + Vector2(LONE_DISTANCE, 0)
	set_physics_process(true)
	_phase_lone = true
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < LONE_SECONDS:
		await get_tree().create_timer(0.2).timeout
		_dismiss_dialogs()
	_phase_lone = false
	set_physics_process(false)
	if is_instance_valid(_strafe):
		_strafe.queue_free()
	_strafe = null
	for i in range(3):
		await get_tree().process_frame
	if _a_shots <= 0:
		_c.check(false, "A 段一发没打：弹丸法器没上阵或索敌失效（在场槽位 %d）" % GameManager.slots_used())
		return
	var rate_a := float(_a_shots - _a_whiffs) / float(_a_shots)
	print("PROBE[A 单挑横切 %dpx@%.0fpx/s] shots=%d whiffs=%d hit_rate=%.1f%% slots=%d" % [
		int(LONE_DISTANCE), LONE_SPEED, _a_shots, _a_whiffs, rate_a * 100.0, GameManager.slots_used()])
	_c.check(_a_shots >= MIN_A_SHOTS, "A 段样本充足：打出 %d 发（下限 %d）" % [_a_shots, MIN_A_SHOTS])
	_c.check(rate_a >= MIN_A_HIT_RATE,
		"A 段命中兑现率 %.1f%% ≥ %.0f%%（目标只做匀速横切，直线弹在这个距离普遍打空）" % [rate_a * 100.0, MIN_A_HIT_RATE * 100.0])

## B 段：恢复刷怪，跳指定波次的尸潮真打一场，报整体命中率与按距离档的落空分布
func _phase_b() -> void:
	GameManager.wave_spawner.set_physics_process(true)
	GameManager.wave_spawner.set_process(true)
	var kite := KiteJoystick.new()
	GameManager.joystick = kite
	add_child(kite)
	if _wave > 1:
		GameManager.wave_spawner.start_wave(_wave)
		await get_tree().create_timer(1.0).timeout
		_dismiss_dialogs()
	var shots_before := _shots
	var whiffs_before := _whiffs
	set_physics_process(true)
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < _sample_seconds:
		await get_tree().create_timer(0.2).timeout
		_dismiss_dialogs()     # 升级/商店弹窗会暂停整棵树，边等边清，否则采样会断
	set_physics_process(false)
	var secs := float(Time.get_ticks_msec() - start_ms) / 1000.0
	var b_shots := _shots - shots_before
	var b_whiffs := _whiffs - whiffs_before
	print("PROBE[B 尸潮 %d 波] seconds=%.1f shots=%d whiffs=%d hit_units=%d enemies=%d kills=%d wave=%d" % [
		_wave, secs, b_shots, b_whiffs, _hit_units,
		get_tree().get_nodes_in_group("enemies").size(), GameManager.kills, GameManager.wave_number])
	if b_shots > 0:
		print("PROBE[B] hit_rate=%.1f%% hits_per_shot=%.2f shots_per_sec=%.2f" % [
			100.0 * float(b_shots - b_whiffs) / float(b_shots),
			float(_hit_units) / float(maxi(_shots, 1)), float(b_shots) / maxf(secs, 0.001)])
	for i in range(BANDS.size()):
		if _band_shots[i] > 0:
			print("PROBE[B] band %s px: shots=%d whiff=%d (%.0f%% 落空)" % [
				BANDS[i], _band_shots[i], _band_whiffs[i],
				100.0 * float(_band_whiffs[i]) / float(_band_shots[i])])
	_c.check(b_shots >= MIN_SHOTS, "B 段样本充足：打出 %d 发（下限 %d）" % [b_shots, MIN_SHOTS])
	if b_shots >= MIN_SHOTS:
		var rate_b := float(b_shots - b_whiffs) / float(b_shots)
		_c.check(rate_b >= MIN_B_HIT_RATE, "B 段命中兑现率 %.1f%% ≥ %.0f%%" % [rate_b * 100.0, MIN_B_HIT_RATE * 100.0])
		var per_shot := float(_hit_units) / float(maxi(_shots, 1))
		_c.check(per_shot >= MIN_HITS_PER_SHOT,
			"每发平均结算 %.2f 个敌人 ≥ %.2f（穿透与弹射的账要真结到人数上）" % [per_shot, MIN_HITS_PER_SHOT])

func _finish() -> void:
	if _selftest:
		var a_failed := false
		for f in _c.failures:
			if String(f).begins_with("A 段"):
				a_failed = true
		if a_failed:
			print("[PASS] 反例成立：关掉追踪后 A 段命中兑现塌了 ⇒ 这条判据真在管事")
			_c.failures.clear()     # 反例只要求 A 段红；B 段在密集成群的敌人里蹭得到人，不参与判定
			_c.passed += 1
		else:
			print("[FAIL] 反例不成立：关掉追踪后 A 段仍然全绿 —— 判据没牙齿")
			_c.failures.append("反例：关掉追踪后 A 段必须报错")
	BladeProjectile.homing_scale = 1.0
	GameManager.joystick = null
	if _c.report("PROJECTILE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _dismiss_dialogs() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false


class KiteJoystick:
	extends Node
	## 假装是 VirtualJoystick：让玩家往「敌人重心的反方向」跑，就是幸存者玩法的标准走位。
	## B 段必须有走位 —— 玩家站着不动时敌人基本径向靠近，直线弹也能中，量的就是假数据。
	var _t: float = 0.0

	func get_direction() -> Vector2:
		var centroid := Vector2.ZERO
		var n := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if e is Node2D:
				centroid += (e as Node2D).global_position
				n += 1
		if GameManager.player == null or n == 0:
			return Vector2.ZERO
		var away: Vector2 = GameManager.player.global_position - centroid / float(n)
		if away.length_squared() < 25.0:
			_t += 0.016
			return Vector2.RIGHT.rotated(_t * 0.7)
		return away.normalized()
