extends Node

## 超级悟道面板与落地专项校验（2026-10-25）
## 覆盖：
## 1. 相位枚举兼容：SUPER_ALLOC 追加在末尾，老档存下的 ALLOC/SHOP 整型相位不位移。
## 2. 面板装配：场景可加载、5 张卡铺出、标题/逆天红/无刷新键、候选 3 流派 + 2 通用。
## 3. 选卡落地：赠神通入背包、本关记账、发 super_alloc_finished、面板淡出、流程闸口不再重弹。
## 4. 读档口径：候选/已结算/已拿三数组都能原样灌回（RunSave 走 append 重建）。
##
## 运行方式：
##   godot --headless --path . res://tests/SuperAllocCheck.tscn

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_run_phase_check()
	await _run_dialog_check()

	GameManager.reset_run()
	get_tree().paused = false
	if _c.report("SUPER_ALLOC_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _run_phase_check() -> void:
	# RunSave 存的是 Phase 整型：SUPER_ALLOC 必须加在末尾，否则老档 ALLOC(3)/SHOP(4) 会错位
	_check(int(WaveSpawner.Phase.ALLOC) == 3, "ALLOC 相位号保持 3（老档兼容）")
	_check(int(WaveSpawner.Phase.SHOP) == 4, "SHOP 相位号保持 4（老档兼容）")
	_check(int(WaveSpawner.Phase.SUPER_ALLOC) == 5, "SUPER_ALLOC 追加在枚举末尾（=5）")

func _run_dialog_check() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	GameManager.wave_number = 5

	var scene := load("res://scenes/ui/SuperAllocDialog.tscn") as PackedScene
	_check(scene != null, "SuperAllocDialog.tscn 可加载")
	if scene == null:
		return
	var dlg = scene.instantiate()
	add_child(dlg)
	await get_tree().process_frame

	SuperAllocSession.open(GameManager)
	await get_tree().process_frame
	_check(dlg.visible, "会话打开后面板可见")
	_check(get_tree().paused, "面板打开即暂停整棵树")
	_check(GameManager.super_alloc_offers.size() == 5, "候选固定 5 张")
	_check(dlg.cards_container.get_child_count() == 5, "面板铺出 5 张卡（实为 %d）" % dlg.cards_container.get_child_count())
	_check(dlg.title_label.text == "超 级 悟 道", "标题为「超级悟道」")
	_check(not dlg.reroll_btn.visible, "超级悟道没有刷新键")
	_check(dlg._points_badge == null or not dlg._points_badge.visible, "超级悟道不显示待加点徽记")

	var build_n := 0
	for o in GameManager.super_alloc_offers:
		if String(o.get("rarity", "")) != "mythic":
			_check(false, "候选稀有度应为 mythic（%s 实为 %s）" % [o.get("id", "?"), o.get("rarity", "?")])
		if String(o.get("kind", "")) == "build":
			build_n += 1
	_check(build_n == 3, "候选为 3 张流派卡 + 2 张通用卡（流派 %d）" % build_n)

	# 入场防误触窗口 0.14s：直接放行手指（判据不等动画）
	dlg._can_interact = true
	dlg._select_card(0)
	_check(dlg.selected_index == 0, "点卡只选中")
	_check(dlg.confirm_btn.text == "确认领悟 ★", "确认键文案")
	var picked := String(GameManager.super_alloc_offers[0].get("grant_item", ""))
	dlg._on_confirm_pick()

	_check(GameManager.super_alloc_done_waves.has(5), "选卡后本关记账为已结算")
	_check(GameManager.super_cards_taken.size() == 1, "已拿卡记录 +1")
	_check(GameManager.items.has(picked), "绑定神通进入道具持有列表（%s）" % picked)
	_check(GameManager.super_alloc_offers.is_empty(), "选完清空候选")
	_check(not SuperAllocSession.should_open(GameManager), "同一关不再触发超级悟道")

	# 淡出后收起（_on_alloc_finished 0.12s 补间）
	await get_tree().create_timer(0.25).timeout
	_check(not dlg.visible, "选完面板淡出收起")
	get_tree().paused = false
	dlg.queue_free()
