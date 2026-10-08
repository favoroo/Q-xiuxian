class_name UpdateDialog
extends Control

## 应用内更新弹窗
## 对标 dudu-cocos 的 UpdateDialog：
## 三条出口：「立即更新」（应用内下载安装）、「浏览器下载」（外部浏览器兜底）、「稍后再说」（关闭）
## 进度双态：真实字节流展示（百分比/MB/速度/剩余时间）

var _info: Dictionary = {}
var _is_downloading: bool = false
var _downloaded_path: String = ""

var _panel: PanelContainer
var _title_label: Label
var _ver_label: Label
var _size_label: Label
var _notes_container: VBoxContainer
var _scroll_box: ScrollContainer

var _prog_box: VBoxContainer
var _prog_bar: ProgressBar
var _prog_label: Label
var _prog_sub: Label

var _btn_row: HBoxContainer
var _update_btn: Button
var _browser_btn: Button
var _cancel_btn: Button

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

	UpdateManager.download_progress.connect(_on_download_progress)
	UpdateManager.download_completed.connect(_on_download_completed)
	UpdateManager.download_failed.connect(_on_download_failed)

func _build_ui() -> void:
	# 全屏暗底遮罩
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# 居中主面板（P5 斜切 + 厚底边描线）
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460, 380)
	var style := GameStyle.panel(GameStyle.NAVY, GameStyle.SLANT_PLATE, Vector2(8, 10))
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 5
	style.border_color = GameStyle.BLUE_EDGE
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# 标题
	_title_label = Label.new()
	_title_label.text = "发  现  新  版  本"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameStyle.label(_title_label, 26, GameStyle.YELLOW, 0, GameStyle.INK, true)
	vbox.add_child(_title_label)

	# 版本与体积行
	var meta_row := HBoxContainer.new()
	meta_row.alignment = BoxContainer.ALIGNMENT_CENTER
	meta_row.add_theme_constant_override("separation", 16)
	vbox.add_child(meta_row)

	_ver_label = Label.new()
	_ver_label.text = "新版本: v0.0.0"
	GameStyle.label(_ver_label, 14, GameStyle.BLUE_EDGE)
	meta_row.add_child(_ver_label)

	_size_label = Label.new()
	_size_label.text = "大小: -- MB"
	GameStyle.label(_size_label, 13, GameStyle.PAPER_DIM)
	meta_row.add_child(_size_label)

	# 日志底框（凹陷槽）
	var slot_panel := PanelContainer.new()
	slot_panel.custom_minimum_size = Vector2(400, 140)
	slot_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var slot_style := GameStyle.slot()
	slot_style.content_margin_left = 14
	slot_style.content_margin_right = 14
	slot_style.content_margin_top = 10
	slot_style.content_margin_bottom = 10
	slot_panel.add_theme_stylebox_override("panel", slot_style)
	vbox.add_child(slot_panel)

	_scroll_box = ScrollContainer.new()
	_scroll_box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slot_panel.add_child(_scroll_box)

	_notes_container = VBoxContainer.new()
	_notes_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_container.add_theme_constant_override("separation", 6)
	_scroll_box.add_child(_notes_container)

	# 进度条区（平时隐藏，下载时激活）
	_prog_box = VBoxContainer.new()
	_prog_box.add_theme_constant_override("separation", 4)
	_prog_box.visible = false
	vbox.add_child(_prog_box)

	_prog_bar = ProgressBar.new()
	_prog_bar.custom_minimum_size = Vector2(0, 16)
	_prog_bar.min_value = 0.0
	_prog_bar.max_value = 100.0
	_prog_bar.step = 0.1
	_prog_bar.show_percentage = false
	var styles = GameStyle.bar_styles(GameStyle.NAVY2, GameStyle.BLUE)
	_prog_bar.add_theme_stylebox_override("background", styles[0])
	_prog_bar.add_theme_stylebox_override("fill", styles[1])
	_prog_box.add_child(_prog_bar)

	var prog_text_row := HBoxContainer.new()
	_prog_box.add_child(prog_text_row)

	_prog_label = Label.new()
	_prog_label.text = "准备下载..."
	_prog_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameStyle.label(_prog_label, 12, GameStyle.BLUE_EDGE)
	prog_text_row.add_child(_prog_label)

	_prog_sub = Label.new()
	_prog_sub.text = ""
	_prog_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	GameStyle.label(_prog_sub, 11, GameStyle.GREY)
	prog_text_row.add_child(_prog_sub)

	# 底部按钮行（三按钮同排布局）
	_btn_row = HBoxContainer.new()
	_btn_row.add_theme_constant_override("separation", 10)
	_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_btn_row)

	_update_btn = Button.new()
	_update_btn.text = "立 即 更 新"
	_update_btn.custom_minimum_size = Vector2(125, 42)
	_update_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_update_btn, GameStyle.BLUE, GameStyle.YELLOW, 14, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	_update_btn.pressed.connect(_on_update_pressed)
	_btn_row.add_child(_update_btn)

	_browser_btn = Button.new()
	_browser_btn.text = "浏览器下载"
	_browser_btn.custom_minimum_size = Vector2(125, 42)
	_browser_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_browser_btn, GameStyle.NAVY2, GameStyle.BLUE, 13, GameStyle.PAPER, 5.0)
	_browser_btn.pressed.connect(_on_browser_pressed)
	_btn_row.add_child(_browser_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "稍 后 再 说"
	_cancel_btn.custom_minimum_size = Vector2(110, 42)
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_cancel_btn, GameStyle.NAVY2, GameStyle.BAD, 13, GameStyle.PAPER, 5.0)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_btn_row.add_child(_cancel_btn)

## 打开更新弹窗
func popup_update(info: Dictionary) -> void:
	_info = info
	_is_downloading = false
	_downloaded_path = ""

	_ver_label.text = "新版本: %s" % info.get("tag_name", "v0.0.0")
	var size_text: String = str(info.get("file_size_text", ""))
	_size_label.text = "大小: %s" % size_text if not size_text.is_empty() else ""
	_size_label.visible = not size_text.is_empty()

	_render_release_notes(str(info.get("release_notes", "")))

	_prog_box.visible = false
	_update_btn.text = "立 即 更 新"
	_cancel_btn.text = "稍 后 再 说"

	visible = true
	_panel.pivot_offset = _panel.custom_minimum_size * 0.5
	_panel.scale = Vector2(0.85, 0.85)
	modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func close() -> void:
	if _is_downloading:
		UpdateManager.cancel_download()
		_is_downloading = false

	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		visible = false
	)

func _render_release_notes(raw_notes: String) -> void:
	for c in _notes_container.get_children():
		c.queue_free()

	var lines := raw_notes.split("\n")
	var count := 0
	for line in lines:
		var s := line.strip_edges()
		if s.is_empty() or s.begins_with("---") or s.begins_with("***"):
			continue
		if s.to_lower().begins_with("sha-256") or s.to_lower().begins_with("**sha-256"):
			continue
		if s.begins_with("##") and ("v0." in s or "v1." in s):
			continue

		var lbl := Label.new()
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		if s.begins_with("### ") or s.begins_with("## "):
			var text = s.trim_prefix("### ").trim_prefix("## ")
			lbl.text = "【" + text + "】"
			GameStyle.label(lbl, 13, GameStyle.YELLOW)
		elif s.begins_with("- ") or s.begins_with("* "):
			var text = s.substr(2).trim_prefix("**").trim_suffix("**")
			lbl.text = " · " + text
			GameStyle.label(lbl, 12, GameStyle.PAPER)
		else:
			lbl.text = s
			GameStyle.label(lbl, 12, GameStyle.PAPER_DIM)

		_notes_container.add_child(lbl)
		count += 1
		if count >= 8:
			break

	if count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "优化游戏体验，修复若干已知问题。"
		GameStyle.label(empty_lbl, 12, GameStyle.PAPER_DIM)
		_notes_container.add_child(empty_lbl)

func _on_update_pressed() -> void:
	if not _downloaded_path.is_empty():
		# 已下载完成，再次调起安装
		var ok := UpdateManager.install_apk(_downloaded_path)
		if not ok:
			_prog_sub.text = "调起安装失败，请点击「浏览器下载」"
		return

	if _is_downloading:
		return

	# Web 环境或无 APK 时退回网页
	if not OS.has_feature("android") and not OS.has_feature("editor") and not OS.has_feature("standalone"):
		OS.shell_open(_info.get("download_url", ""))
		close()
		return

	if not _info.get("has_apk", false):
		OS.shell_open(_info.get("release_url", ""))
		close()
		return

	# 开始应用内下载
	_is_downloading = true
	_prog_box.visible = true
	_prog_bar.value = 0.0
	_prog_label.text = "正在连接下载源..."
	_prog_sub.text = ""
	_update_btn.text = "下 载 中..."
	_cancel_btn.text = "取 消 下 载"

	UpdateManager.start_download(_info)

func _on_browser_pressed() -> void:
	var url: String = str(_info.get("release_url", ""))
	if url.is_empty():
		url = str(_info.get("download_url", ""))
	if not url.is_empty():
		OS.shell_open(url)

func _on_cancel_pressed() -> void:
	close()

func _on_download_progress(loaded: int, total: int, percent: float, speed: float, eta_sec: float) -> void:
	_prog_bar.value = percent
	var loaded_str := Version.format_bytes(loaded)
	var total_str := Version.format_bytes(total)
	_prog_label.text = "下载中: %.0f%% (%s / %s)" % [percent, loaded_str, total_str]

	var speed_str := "%s/s" % Version.format_bytes(int(speed))
	var eta_str := "剩余约 %.0f 秒" % eta_sec if eta_sec > 0.0 else ""
	_prog_sub.text = "%s  %s" % [speed_str, eta_str]

func _on_download_completed(path: String) -> void:
	_is_downloading = false
	_downloaded_path = path
	_prog_bar.value = 100.0
	_prog_label.text = "下载完成，正在调起安装..."
	_prog_sub.text = "安装包已就绪"
	_update_btn.text = "立 即 安 装"
	_cancel_btn.text = "关  闭"

	var ok := UpdateManager.install_apk(path)
	if not ok:
		_prog_sub.text = "自动调起受阻，请点击「立即安装」或「浏览器下载」"

func _on_download_failed(err_msg: String) -> void:
	_is_downloading = false
	_prog_label.text = "下载中断: %s" % err_msg
	_prog_sub.text = "可尝试「浏览器下载」获取安装包"
	_update_btn.text = "重 试 下 载"
	_cancel_btn.text = "稍 后 再 说"
