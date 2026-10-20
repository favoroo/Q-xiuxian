extends Node

## 新手指南「开局自动弹」门控判据：headless 运行，退出码 0 且打印 ALL PASS 即通过。
## 运行: $G --headless --path . res://tests/TutorialGateCheck.tscn
##       $G --headless --path . res://tests/TutorialGateCheck.tscn -- --selftest
##
## 为什么立这条（用户 2026-10-11：指南卡片加「下次不弹出」勾选框，勾了下次不弹，
## 否则每次开始游戏都弹）：
##  ① 旧门控读 GameManager.tutorial_seen（progress.cfg，看过一次就永远不弹），现在换成
##     SettingsManager.tutorial_muted（settings.cfg 偏好，勾了才不弹）。条件写反（把 muted
##     当 seen 用）表现为「永远不弹」或「勾了还弹」，两种都不崩不报错，只有真开一局才发现。
##  ② 勾选框要点得动：按下走引擎拾取（root.push_input 真发按下/抬起），绝不 emit_signal
##     ——emit 绕过拾取，热区是死的也照样全绿。
##  ③ 点完要真落盘：回读 user://settings.cfg，否则下次开机又弹（用户看到的还是同一个 bug）。
## 尺子走生产入口：门控调 StartMenu._auto_show_tutorial() 本体、开局那一下调
## StartMenu._on_start_pressed() 本体，不在此重抄条件；分页逻辑仍直接开 TutorialDialog。
## 注意：全程只动 tutorial_muted 一个键，收尾还原开发机原值（保护 user://settings.cfg）。

const JITTER := 4.0

var _c := TestCheck.new()
var _main: Node
var _menu: Node
var _tut: TutorialDialog
var _sel: Control
var _mute_chk: CheckBox
## 开发机原值，收尾原样写回
var _muted0: bool = false

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	_muted0 = SettingsManager.tutorial_muted()
	get_tree().root.size = Vector2i(960, 540)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(4)
	_menu = _main.get_node_or_null("UILayer/StartMenu")
	_tut = _main.get_node_or_null("UILayer/TutorialDialog") as TutorialDialog
	_sel = _main.get_node_or_null("UILayer/CultivatorSelect") as Control
	if _tut != null:
		_mute_chk = _tut.get("_mute_chk") as CheckBox
	if "--selftest" in OS.get_cmdline_user_args():
		await _selftest()
	else:
		await _run()
	SettingsManager.set_tutorial_muted(_muted0)
	if _c.report("TUTORIAL_GATE_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

# ================================ 正判 ================================

func _run() -> void:
	_check(_menu != null and _tut != null and _sel != null,
		"现场：真 Main 场景里的 StartMenu / TutorialDialog / CultivatorSelect 都在")
	if _menu == null or _tut == null or _sel == null:
		return

	# ---------- 1. 存档位迁移：旧的「看过一次就不弹」字段已退役 ----------
	var gm: Node = get_node_or_null("/root/GameManager")
	_check(gm != null, "前置：GameManager autoload 存在")
	_check(gm != null and gm.get("tutorial_seen") == null,
		"旧的 GameManager.tutorial_seen 已删除（留着就是没人读的死字段）")

	# ---------- 2. 开局门控：只有勾过「下次不弹出」才不弹 ----------
	SettingsManager.set_tutorial_muted(false)
	_check(_menu._auto_show_tutorial(), "没勾 → 点开始游戏要弹指南（每次开局都弹）")
	SettingsManager.set_tutorial_muted(true)
	_check(not _menu._auto_show_tutorial(), "勾了「下次不弹出」→ 开局不弹")
	SettingsManager.set_tutorial_muted(false)

	# ---------- 3. 勾选框：开弹窗读存档态，真点一下写存档，门控跟着翻 ----------
	_check(_mute_chk != null, "指南卡片底部有「下次不弹出」勾选框（TutorialDialog._mute_chk）")
	if _mute_chk == null:
		return
	SettingsManager.set_tutorial_muted(true)
	_tut.open()
	await _settle(4)
	_check(_mute_chk.button_pressed, "已勾过的档：打开指南时框是勾上的（看得见，也才取消得了）")
	_check(_mute_chk.get_theme_color("font_hover_pressed_color") == GameStyle.PAPER,
		"已勾选时 hover_pressed 状态字色为墨字（不回退为全白）")
	_check(_mute_chk.get_theme_color("font_focus_color") == GameStyle.PAPER,
		"已勾选时 focus 状态字色为墨字（不回退为全白）")
	_tut.close()
	await _wait_closed()
	SettingsManager.set_tutorial_muted(false)
	_tut.open()
	await _settle(4)
	_check(not _mute_chk.button_pressed, "没勾的档：框是空的")
	_check(_mute_chk.get_theme_color("font_hover_pressed_color") == GameStyle.PAPER_DIM,
		"未勾选时 hover_pressed 状态字色为次要深灰字（不回退为全白）")

	await _tap(_mute_chk)
	_check(SettingsManager.tutorial_muted(), "真点一下 → 偏好写成「下次不弹出」")
	_check(_mute_chk.button_pressed, "点完框自己显示勾上（反馈与存档同源，不是按了没反应）")
	_check(_mute_chk.get_theme_color("font_hover_pressed_color") == GameStyle.PAPER,
		"点按后即时回刷字色：hover_pressed 立即切为已勾选墨字")
	_check(not _menu._auto_show_tutorial(), "点完之后门控立刻改口：开局不再弹")
	_check(_disk_muted() == true, "勾选态已落 user://settings.cfg（重启进程还在）")

	await _tap(_mute_chk)
	_check(not SettingsManager.tutorial_muted(), "再点一下取消勾选 → 恢复每次开局都弹")
	_check(_mute_chk.get_theme_color("font_hover_pressed_color") == GameStyle.PAPER_DIM,
		"取消勾选后即时回刷字色：hover_pressed 立即切回次要深灰字")
	_check(_disk_muted() == false, "取消也落盘")

	# ---------- 4. 开局那一下：弹指南 → 关掉才进选角；one-shot 不许让后面每次关闭都跳选角 ----
	SettingsManager.set_tutorial_muted(false)
	_sel.visible = false
	_menu._on_start_pressed()
	await _settle(30)
	_check(_tut.visible, "点开始游戏 → 指南真的弹出来了（不是只改了个变量）")
	_check(not _sel.visible, "指南还开着时不提前进选角")
	_tut.close()
	await _wait_closed()
	await _settle(8)
	_check(_sel.visible, "关掉指南 → 进选角（closed 串接生效）")

	_sel.visible = false
	_tut.open()
	await _settle(4)
	_tut.close()
	await _wait_closed()
	await _settle(8)
	_check(not _sel.visible, "之后手动翻开指南再关掉，不会再跳一次选角（串接是 one-shot）")

	# ---------- 4b. 「〈 返 回」：反悔退出回主菜单，不进选角、不落「下次不弹出」 ----------
	# 为什么立这条：跳过与返回都走 close()→closed，若 _after_tutorial 不看标记，
	# 返回会被当成「跳过」直接进选角（玩家点了返回却被推进开局），且不报错只有真机看得出。
	var back_btn: Button = _tut.get("_back_btn")
	_check(back_btn != null, "指南顶栏有「〈 返 回」按钮（TutorialDialog._back_btn）")
	_check(back_btn != null and back_btn.get_parent() == _tut.get("_top_bar"),
		"返回键挂在顶栏上（与右上「跳 过」同一条栏）")
	_check(back_btn != null and _tut.get("_top_bar").get_child(0) == back_btn,
		"返回键排在顶栏最左（在标题块之前）")
	if back_btn != null:
		SettingsManager.set_tutorial_muted(false)
		_sel.visible = false
		_menu.visible = false
		_menu._on_start_pressed()
		await _settle(30)
		_check(_tut.visible, "返回判据现场：点开始游戏后指南已弹出")
		_check(not bool(_tut.get("left_via_back")), "刚打开时返回标记为假（每次 open 复位）")
		await _tap(back_btn)
		await _wait_closed()
		await _settle(10)
		_check(_menu.visible, "点「〈 返 回」→ 回到主菜单（不是被推进选角）")
		_check(not _sel.visible, "点「〈 返 回」不会顺带进选角")
		_check(not SettingsManager.tutorial_muted(),
			"点「〈 返 回」不落「下次不弹出」（下次开局仍会弹）")
		_check(not bool(_tut.get("left_via_back")), "返回标记已被 StartMenu 读走并复位")
		_menu.visible = false
		_sel.visible = false

	# ---------- 5. 分页逻辑（原有判据，翻页与门控在同一条卡片链上） ----------
	_tut.open()
	await _settle(3)
	var pages: Array = _tut.get("_page_controls")
	var dots: Array = _tut.get("_page_dots")
	_check(pages.size() == 5, "共 5 页图文卡片（欢迎页已去掉）")
	_check(dots.size() == 5, "页码指示块 5 个")
	_check(pages[0].visible and not pages[1].visible, "初始仅第 1 页可见")
	var prev: Button = _tut.get("_prev_btn")
	var next: Button = _tut.get("_next_btn")
	_check(prev.disabled, "首页禁用「上一步」")
	_check(next.text.find("下一步") >= 0, "非末页下一步文案为「下一步」")
	_tut._go_page(2)
	_check(pages[2].visible and not pages[0].visible, "翻到第 3 页显隐正确")
	_check(not prev.disabled, "中段可回退")
	_tut._go_page(4)
	_check(next.text.find("开 始 修 仙") >= 0, "末页下一步变「开 始 修 仙」")
	_tut._go_page(99)
	_check(int(_tut.get("_cur")) == 4, "越界翻页被钳制在末页")
	_tut._go_page(-3)
	_check(int(_tut.get("_cur")) == 0, "越界翻页被钳制在首页")
	_check(prev.disabled and next.text.find("下一步") >= 0, "钳回首页后按钮态同步")
	_tut.close()
	await _wait_closed()

# ================================ 反例 ================================

## 判据自己得拦得住东西：造一颗「只画了框、没接落盘」的勾选框（就是「按了没反应」那一类），
## 打同一枪必须量出偏好纹丝不动；紧接着打真那颗必须动 ——
## 否则上面的「没动」可能只是落点打歪，而落点到了没有由那颗框自己的 button_pressed 作证。
func _selftest() -> void:
	if _mute_chk == null:
		_check(false, "反例现场：指南卡片里的勾选框存在")
		return
	SettingsManager.set_tutorial_muted(false)
	_tut.open()
	await _settle(4)

	var bare := CheckBox.new()
	bare.text = "下次不弹出"
	bare.custom_minimum_size = Vector2(150, 36)
	(_mute_chk.get_parent() as Control).add_child(bare)
	await _settle(3)
	var lp := _center(bare)
	await _press(lp)
	await _release(lp + Vector2(0, -JITTER))
	await _settle(2)
	_check(bare.button_pressed,
		"反例落点：这一枪真送到了诱饵框身上（否则「没落盘」不算判定）")
	_check(not SettingsManager.tutorial_muted(),
		"反例：没接落盘的框点完偏好纹丝不动 —— 尺子认的是写盘，不是框自己变蓝")

	await _tap(_mute_chk)
	_check(SettingsManager.tutorial_muted(),
		"正例：真那颗在同一类坐标上点完必须写盘 —— 反例的「没动」不是事件没人收到")
	bare.free()
	SettingsManager.set_tutorial_muted(false)

# ================================ 工具 ================================

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

## 落盘回读：直接开 settings.cfg 问引擎「这个键真在文件里吗」
func _disk_muted() -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SettingsManager.SETTINGS_PATH) != OK:
		return null
	if not cfg.has_section_key("ui", "tutorial_muted"):
		return null
	return bool(cfg.get_value("ui", "tutorial_muted", false))

## 真发一次「按下 → 抬起」：CheckBox 由 BaseButton 在抬起那一下才 emit pressed
func _tap(c: Control) -> void:
	var pos := _center(c)
	await _press(pos)
	await _release(pos + Vector2(0, -JITTER))
	await _settle(2)

func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()

func _press(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_tree().root.push_input(e)
	await get_tree().process_frame

func _release(pos: Vector2) -> void:
	var p := _to_input(pos)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	get_tree().root.push_input(e)
	await get_tree().process_frame

## 画布坐标 → 窗口坐标：root.size 与视口不同尺时不打折就打歪（实测踩过）
func _to_input(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

## 基类 close() 有 0.16s 淡出，等它真关严（visible=false）再断言下一步
func _wait_closed() -> void:
	for _i in range(60):
		if not _tut.visible:
			return
		await get_tree().process_frame

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
