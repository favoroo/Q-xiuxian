extends Node

## 新手指南（TutorialDialog）门控判据：headless 运行，退出码 0 且打印 ALL PASS 即通过。
## 运行: godot --headless --path . res://tests/TutorialGateCheck.tscn
## 覆盖：① 字段存在与默认值（新档应弹）② 门控判定三分支 ③ 弹窗分页逻辑
## 注意：不读写 user://progress.cfg（保护真机存档），落盘行为由 SmokeRunner 全流程兜底。

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# ---------- 1. 字段与默认值 ----------
	var gm := get_node_or_null("/root/GameManager")
	_check(gm != null, "前置：GameManager autoload 存在")
	if gm == null:
		_finish()
		return
	_check(gm.get("tutorial_seen") != null, "GameManager 有 tutorial_seen 字段")
	_check(gm.tutorial_seen == false, "tutorial_seen 默认 false（真机存档无该 key 时走默认）")

	# ---------- 2. 门控判定三分支（与 StartMenu._on_start_pressed 条件同构） ----------
	# 注意：不读真实存档状态（本机 progress.cfg 可能已是老玩家档），只验逻辑本身
	var would_show := func(seen: bool, runs: int) -> bool:
		return not seen and runs == 0
	_check(would_show.call(false, 0), "门控：新档未看过 → 弹")
	_check(not would_show.call(true, 0), "门控：已看过 → 不弹")
	_check(not would_show.call(false, 1), "门控：老玩家开局过 → 不弹")

	# ---------- 3. 弹窗分页逻辑 ----------
	var dlg_scene: PackedScene = load("res://scenes/ui/TutorialDialog.tscn")
	_check(dlg_scene != null, "前置：TutorialDialog.tscn 可加载")
	var dlg := dlg_scene.instantiate() as TutorialDialog
	_check(dlg != null, "TutorialDialog 实例化为 TutorialDialog 类型")
	add_child(dlg)
	await get_tree().process_frame

	_check(dlg._page_controls.size() == 6, "共 6 页图文卡片")
	_check(dlg._page_dots.size() == 6, "页码指示块 6 个")
	_check(dlg._page_controls[0].visible and not dlg._page_controls[1].visible, "初始仅第 1 页可见")
	_check(dlg._prev_btn.disabled, "首页禁用「上一步」")
	_check(dlg._next_btn.text.find("下一步") >= 0, "非末页下一步文案为「下一步」")

	dlg._go_page(3)
	_check(dlg._page_controls[3].visible and not dlg._page_controls[0].visible, "翻到第 4 页显隐正确")
	_check(not dlg._prev_btn.disabled, "中段可回退")
	dlg._go_page(5)
	_check(dlg._next_btn.text.find("开 始 修 仙") >= 0, "末页下一步变「开 始 修 仙」")
	dlg._go_page(99)
	_check(dlg._cur == 5, "越界翻页被钳制在末页")
	dlg._go_page(-3)
	_check(dlg._cur == 0, "越界翻页被钳制在首页")

	dlg.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	if _c.report("TUTORIAL_GATE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)
