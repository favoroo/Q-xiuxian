extends Node

## 伤害跳字同目标窗口聚合判据（2026-10-14）：
## 同一敌人 0.25s 滑窗内的连续伤害并成一条跳字（累计值 + ×N，任一暴击整条升鎏金），
## 解决束流/喷吐/DoT 高频命中下逐发刷屏、新字顶旧字、池 96 溢出 new+free 抖动。
##
## 断言链：
##   ① can_merge / format_combo 纯函数口径；
##   ② 同 key 窗内连击 → 池里只有一条、文本为「15×2」，暴击并入升金带「!」；
##   ③ 异 key 互不聚合；custom_text 文字类与 combo_key=0 旧调用不参与聚合；
##   ④ 窗口滑过 0.25s 后再打同一敌人 → 开新条（旧条未到期不归池，可见数 +1）；
##   ⑤ 全部到期后聚合表清零、跳字归池（无泄漏、无滞留登记）。
##
## 运行: godot --headless --path . res://tests/DamageComboCheck.tscn
## 反例（判据的牙齿）：
##   ① 把 spawn 里的 _try_merge 短路成 return false ⇒ ② 的「只有一条」与「15×2」报红；
##   ② 把 can_merge 放宽成 return true ⇒ ③ 的文字类/0-key 报红；
##   ③ 去掉 expire 判定 ⇒ ④ 开不了新条报红。

var _c := TestCheck.new()
var _world: Node2D

func _ready() -> void:
	GameManager.reset_run()
	# 本判据必须出字：强制打开跳字并穿透 memo（测试需要同帧生效）
	SettingsManager.set_val(&"display", &"damage_numbers", true)
	GameFeel.invalidate_memo()
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	call_deferred("_run")

func _run() -> void:
	# —— ① 纯函数口径 ——
	_c.check(not DamageNumber.can_merge(0, false), "combo_key=0 不参与聚合（旧调用零影响）")
	_c.check(not DamageNumber.can_merge(42, true), "文字类读数不参与聚合")
	_c.check(DamageNumber.can_merge(42, false), "带 key 的数字跳字参与聚合")
	_c.equals(DamageNumber.format_combo(128, 1), "128", "单发文本就是数字")
	_c.equals(DamageNumber.format_combo(128, 3), "128×3", "两连以上带累计与 ×N 后缀")

	var inside := get_viewport().get_visible_rect().get_center()
	var key_a := 11111
	var key_b := 22222

	# —— ② 同 key 窗内连击聚合 ——
	DamageNumber.spawn(_world, inside, 10, false, "", key_a)
	_c.equals(_visible_count(), 1, "首发正常生成")
	DamageNumber.spawn(_world, inside, 5, false, "", key_a)
	_c.equals(_visible_count(), 1, "窗内第二发并入同一条（不再新建）")
	_c.equals(_label_text(), "15×2", "聚合文本为累计值×计数")
	DamageNumber.spawn(_world, inside, 2, true, "", key_a)
	_c.equals(_visible_count(), 1, "暴击并入仍是一条")
	_c.equals(_label_text(), "17×3!", "任一暴击整条升鎏金并带感叹号")
	_c.equals(DamageNumber.combo_count(), 1, "聚合表只登记在显跳字")

	# —— ③ 异 key / 文字类 / 0-key 不聚合 ——
	DamageNumber.spawn(_world, inside, 7, false, "", key_b)
	_c.equals(_visible_count(), 2, "另一敌人开自己的聚合条")
	DamageNumber.spawn(_world, inside, 9, false, "+9 金币", key_a)
	_c.equals(_visible_count(), 3, "文字类读数逐条独立，不并入伤害条")
	DamageNumber.spawn(_world, inside, 9, false, "", 0)
	_c.equals(_visible_count(), 4, "combo_key=0 的旧调用照常独立成条")

	# —— ④ 滑窗过期后同 key 开新条（旧条 0.9s 寿命未结束，可见数 +1）——
	# 聚合窗按真实毫秒计时（Time.get_ticks_msec），而 headless 无 vsync 时 SceneTreeTimer
	# 与墙钟对不上（实测 0.32s 定时器 187ms 就返回）——等待必须按墙钟自旋帧对齐。
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 320:
		await get_tree().process_frame
	DamageNumber.spawn(_world, inside, 4, false, "", key_b)
	_c.equals(_visible_count(), 5, "窗口滑过 0.25s 后同敌人开新聚合条（旧条还在淡出）")

	# —— ⑤ 全部到期：归池 + 聚合表清零（同样按墙钟等过 0.9s 寿命 + 余量）——
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1400:
		await get_tree().process_frame
	_c.equals(_visible_count(), 0, "全部跳字归池（无节点泄漏）")
	_c.equals(DamageNumber.combo_count(), 0, "聚合表清零（无滞留登记，池复用个体身份不残留）")

	if _c.report("DAMAGECOMBO_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

## 池宿主里 visible==true 的在用跳字数（宿主未建按 0 计）
func _visible_count() -> int:
	var host := get_tree().root.find_child("DamageNumberPool", true, false)
	if host == null:
		return 0
	var n := 0
	for child in host.get_children():
		if child is DamageNumber and child.visible:
			n += 1
	return n

## 唯一在显条的文本（多条在显时返回拼接，便于失败输出定位）
func _label_text() -> String:
	var host := get_tree().root.find_child("DamageNumberPool", true, false)
	var parts: Array[String] = []
	if host != null:
		for child in host.get_children():
			if child is DamageNumber and child.visible:
				parts.append(child._label.text)
	return " | ".join(parts)
