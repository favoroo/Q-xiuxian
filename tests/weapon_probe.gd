extends Node

## 单武器实测台（非判据，只打读数）：一件法器一个进程 —— 只上这一件 ★1、跳指定波次、
## 玩家按幸存者玩法拉着怪走，量固定窗口内「真打到妖身上多少血」（总伤害）与收掉多少只。
##
## 为什么不用数据表的 DPS 排名：sustained_single_dps 只说"对一个孤立敌人"的纸面强度，
## 而每把法器的射程、单发可结算数、异常伤害、命中兑现、以及"够不够得着人"都不一样。
## 为什么不用"站定挨打"（本台的第一版）：敌人会堆在玩家身上（实测贴到 24px），而环绕法宝的环
## 在 78px 半径上、接触判定只有 14px —— 它扫不到自己怀里那圈，40 秒只打掉 75/2720 点血。
## 量出来的是站位几何的亏，不是法器的强度。走位才是这游戏的真实工况：玩家一直在跑，
## 妖在身后拉成一条线，各法器的射程档才有各自的活。
## 为什么量总伤害而不是清场时间：清场要等刷怪供给，会被"没怪可杀"卡住；
## 血账 = Σ(首次见到时的血量 − 最后见到时的血量)，与供给无关、与是否打死无关。
##
## 运行: godot --headless --path . res://tests/WeaponProbe.tscn -- --only lingdie
##       ... -- --wave 10 --seconds 12                # 换波次/窗口
##       一件一进程（同一进程里连开多局会互相污染：上一局的玩家没生成干净，
##       下一局的相机每帧报 'player' on Nil，读数全是 0）
## 修士默认「魅影·幽娘」：她的 mods 只碰闪避/气血，不吃伤害乘区（符阵灵童"非灵蝶法器 -30%"、
## 剑痴"剑系 +60%"、石岳有反震，都会把法器的账算脏）；血量钉满 ⇒ 闪避与气血也不参与。

var _wave: int = 10
var _seconds: float = 12.0
var _copies: int = 1
var _cultivator: String = "meiying"
var _only: String = ""
var _mode: String = "circle"       ## circle=绕着怪群转圈（环绕流的标准动作）/ kite=直线拉开 / stand=站定

var _seen: Dictionary = {}      ## 血账：instance_id -> {first, last}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match String(args[i]):
			"--wave": _wave = int(String(args[i + 1]))
			"--seconds": _seconds = float(String(args[i + 1]))
			"--copies": _copies = int(String(args[i + 1]))
			"--cultivator": _cultivator = String(args[i + 1])
			"--only": _only = String(args[i + 1])
			"--mode": _mode = String(args[i + 1])
	call_deferred("_run")

func _run() -> void:
	var ids: Array = [_only] if not _only.is_empty() else WeaponData.SHOP_POOL
	for w_id in ids:
		await _measure(String(w_id))
	get_tree().quit(0)

func _measure(w_id: String) -> void:
	var main = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.cultivator_id = _cultivator
	GameManager.danger_level = 0
	GameManager.start_run(w_id)
	get_tree().paused = false
	GameManager.xp_gain_mult = 0.0          # 不许攒修为：升级弹窗会往场上塞第二件法器，账就脏了
	for i in range(maxi(_copies, 1) - 1):
		GameManager.add_weapon(w_id, 1)
	var player: Node2D = GameManager.player
	if player == null:
		print("WP %-16s 玩家没生成（这一件法器没上成场），跳过" % w_id)
		return
	# 不许把 max_health 钉成 999999：混元古钟的伤害按「额外气血」转化（max_hp_bonus 0.12），
	# 那样量出来的是 10 万 DPS 的假数。改成每拍把血回满 —— 玩家死不了，属性表还是原样。
	var kite := KiteJoystick.new()
	kite.turn_off = (_mode != "circle")
	GameManager.joystick = kite
	add_child(kite)
	_dismiss()

	GameManager.wave_spawner.start_wave(_wave)
	await get_tree().create_timer(2.5).timeout
	_dismiss()

	_seen.clear()
	var kills_before: int = GameManager.kills
	var start_ms := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - start_ms) / 1000.0 < _seconds:
		await get_tree().create_timer(0.1).timeout
		player.set("current_health", player.get("max_health"))
		_tally()
		_dismiss()
	var secs := maxf(0.001, float(Time.get_ticks_msec() - start_ms) / 1000.0)
	var dealt := 0.0
	for id in _seen.keys():
		dealt += float(_seen[id]["first"]) - float(_seen[id]["last"])
	var kills: int = GameManager.kills - kills_before
	var def := WeaponData.get_def(w_id)
	print("WP %-16s %s(%s) 伤害=%.0f (%.1f/s)\t击杀=%d\t接触过的妖=%d\t槽=%d" % [
		w_id, String(def.get("name", "?")), _class_label(def),
		dealt, dealt / secs, kills, _seen.size(), GameManager.slots_used()])
	GameManager.joystick = null
	GameManager.reset_run()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## 每 0.1 秒采一次每只妖的血量：第一次见到的当满血，之后刷新"最后见到的血量"；
## 节点被释放（打死/波末消散）就停在最后一次读数 ⇒ 差值就是这件法器真打掉的。
func _tally() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is Node2D) or not ("current_hp" in e):
			continue        # 组里还挂着敌人的碰撞子节点，它们没有 current_hp
		var id: int = e.get_instance_id()
		var cur: float = float(e.current_hp)
		if not _seen.has(id):
			_seen[id] = {"first": cur, "last": cur}
		else:
			_seen[id]["last"] = cur

func _class_label(def: Dictionary) -> String:
	match int(def.get("behavior", -1)):
		WeaponData.Behavior.MELEE: return "近战"
		WeaponData.Behavior.PROJECTILE: return "弹丸"
		WeaponData.Behavior.BURST: return "落雷"
		WeaponData.Behavior.DRONE: return "环绕"
	return "?"

func _dismiss() -> void:
	for node_name in ["LevelUpDialog", "WaveShop", "PlayerStatsDialog", "PauseMenu", "SettingsDialog"]:
		var n := get_node_or_null("/root/Main/UILayer/" + node_name)
		if n != null and n.visible:
			n.visible = false
	get_tree().paused = false


class KiteJoystick:
	extends Node
	## 假装是 VirtualJoystick。默认往「敌人重心的反方向偏 60°」跑 ⇒ 轨迹是绕着怪群的大圈：
	## 直线拉开时玩家（150px/s）会跑赢史莱姆（105px/s），怪永远落在 78px 的环绕半径之外，
	## 环绕法宝被量成"废"是站位几何的亏；转圈才会被怪群贴到侧翼，三档器类才都在工况里。
	var _t: float = 0.0
	var turn_off: bool = false

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
		away = away.normalized()
		return away.rotated(deg_to_rad(60.0)) if not turn_off else away
