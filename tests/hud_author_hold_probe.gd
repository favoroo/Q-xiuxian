extends Node

## 临时探针（不纳入回归基线）：验证三处暂停键长按作者模式入口的接线与消费逻辑
## （战斗 HUD GameHUD / 金币阁 WaveShop / 悟道面板 LevelUpDialog，超级悟道继承后者）。
## headless 无鼠标，按住计时的真实路径没法全跑，这里直接驱动回调验证关键分支：
## 1. 长按完成 → 作者模式切换
## 2. 紧随的 pressed 被 _on_pause_pressed 吃掉（不发 pause_requested），且标记一次性
## 3. 普通点按仍发 pause_requested（暂停键本职不丢）
## 4. 面板是暂停式模态：树暂停 + 宿主可见 → 照常切换；宿主不可见 → 不切换

func _ready() -> void:
	var stat := {"n": 0, "fail": 0}
	var ok := func(cond: bool, msg: String) -> void:
		stat.n += 1
		if not cond:
			stat.fail += 1
		print(("PASS " if cond else "FAIL ") + msg)
	var orig: bool = GameManager.author_mode

	# ---- 1. 战斗 HUD（树运行态）----
	var hud: Node = (load("res://scenes/ui/GameHUD.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	await _check_host(hud, "HUD", ok)
	# HUD 宿主不可见时长按完成：不切换、不置位（面板被关/被顶掉的兜底）
	var hold: RefCounted = hud.get("_pause_author_hold")
	hud.visible = false
	hold._on_hold_complete()
	await ok.call(GameManager.author_mode == orig, "宿主不可见时长按完成不切作者模式")
	await ok.call(hold.consume_press() == false, "宿主不可见时长按完成不置位")
	hud.free()

	# ---- 2. 金币阁（暂停式模态：树暂停 + 宿主可见也要能切）----
	get_tree().paused = true
	var shop: Node = (load("res://scenes/ui/WaveShop.tscn") as PackedScene).instantiate()
	add_child(shop)
	shop.visible = true
	await get_tree().process_frame
	await _check_host(shop, "商店", ok)
	get_tree().paused = false
	shop.free()

	# ---- 3. 悟道面板（超级悟道继承同一套）----
	get_tree().paused = true
	var lvl: Node = (load("res://scenes/ui/LevelUpDialog.tscn") as PackedScene).instantiate()
	add_child(lvl)
	lvl.visible = true
	await get_tree().process_frame
	await _check_host(lvl, "悟道", ok)
	get_tree().paused = false
	lvl.free()

	# 复位：探针不改会话外的任何状态
	GameManager.set_author_mode(orig)
	var all_pass: bool = stat.fail == 0
	print("HUD_HOLD_PROBE_RESULT: %s（%d 项）" % ["ALL PASS" if all_pass else "HAS FAIL", stat.n])
	get_tree().quit(0 if all_pass else 1)

## 单个宿主的通用四分支：接线存在 / 长按切换+松手被吃 / 正常点按本职 / 树暂停下照常切。
## 宿主需已入树且可见；树暂停状态由调用方按宿主语义摆好（面板两处摆暂停、HUD 不摆）。
func _check_host(host: Node, tag: String, ok: Callable) -> void:
	var hold: RefCounted = host.get("_pause_author_hold")
	await ok.call(hold != null, tag + "暂停键长按助手已创建")
	if hold == null:
		return

	var pause_count := {"v": 0}
	host.pause_requested.connect(func(): pause_count.v += 1)

	# 长按完成 → 切换；松手被吃；标记一次性；随后点按恢复本职
	var before: bool = GameManager.author_mode
	hold._on_hold_complete()
	await ok.call(GameManager.author_mode == (not before), tag + "长按完成切换作者模式")

	host._on_pause_pressed()
	await ok.call(pause_count.v == 0, tag + "长按后的松手不开暂停菜单")
	await ok.call(hold.consume_press() == false, tag + "消费标记已随吃掉那一下清除")
	host._on_pause_pressed()
	await ok.call(pause_count.v == 1, tag + "随后的正常点按开暂停菜单")

	# 树暂停（面板常态）+ 宿主可见：照常切换，松手同样被吃（面板入口的命根，别判树暂停）
	get_tree().paused = true
	hold._on_hold_complete()
	await ok.call(GameManager.author_mode == before, tag + "树暂停时长按完成照常切换")
	host._on_pause_pressed()
	await ok.call(pause_count.v == 1, tag + "树暂停切换后的松手同样被吃掉")
	get_tree().paused = false

	# 宿主级复位：两轮 toggle 后回到进来前的模式
	GameManager.set_author_mode(before)
