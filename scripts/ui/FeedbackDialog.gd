class_name FeedbackDialog
extends BaseModalDialog

## 意见反馈弹窗（2026-10-23）
##
## 玩家在设置「其他」页点「建议与反馈」打开：填写文字 + 从相册选一张截图，
## 点发送后由 FeedbackSender 打包成邮件发到作者邮箱。
##
## 交互要点：
## - 继承 BaseModalDialog：遮罩、拍桌动画、返回键/ESC 关闭全部复用。
## - 发送中锁住输入与关闭，避免重复提交；失败保留已填内容并给出原因。
## - 截图在选图时立刻压缩（长边 1600 / JPEG 0.85），发送时不再二次解码。
## - 网络失败时「复制反馈内容」可把正文+诊断+日志拷到剪贴板，玩家可手动发邮件。

const MAX_MESSAGE_CHARS := FeedbackSender.MAX_MESSAGE_CHARS
const HTTP_TIMEOUT := 25.0

var _message_edit: TextEdit
var _counter_lbl: Label
var _contact_edit: LineEdit
var _pick_btn: Button
var _remove_btn: Button
var _thumb: TextureRect
var _thumb_frame: PanelContainer
var _shot_info: Label
var _send_btn: Button
var _copy_btn: Button
var _status_lbl: Label
var _file_dialog: FileDialog
var _http: HTTPRequest

var _shot_bytes: PackedByteArray = PackedByteArray()
var _shot_name: String = ""
var _shot_mime: String = "image/jpeg"
var _shot_size: int = 0
var _sending: bool = false
var _permission_waiting: bool = false

func _get_title_text() -> String:
	return "意 见 反 馈"

func _get_panel_size() -> Vector2:
	return Vector2(720, 470)

func _get_panel_margins() -> Vector4:
	return Vector4(24, 14, 24, 14)

func _get_vbox_separation() -> int:
	return 8

func _get_close_btn_text() -> String:
	return "关 闭"

func _build_body(root_vbox: VBoxContainer) -> void:
	var tip := Label.new()
	tip.text = "遇到问题或有好建议？写下来发给作者。发送时会自动附带版本、设备与最近日志，方便定位问题。"
	GameStyle.label(tip, 12, GameStyle.PAPER_DIM)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(0, 20)
	root_vbox.add_child(tip)

	# ---------- 反馈正文 ----------
	var msg_head := HBoxContainer.new()
	msg_head.add_theme_constant_override("separation", 8)
	root_vbox.add_child(msg_head)

	var msg_title := Label.new()
	msg_title.text = "反馈内容（必填）"
	GameStyle.label(msg_title, 13, GameStyle.PAPER)
	msg_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg_head.add_child(msg_title)

	_counter_lbl = Label.new()
	_counter_lbl.text = "0 / %d" % MAX_MESSAGE_CHARS
	GameStyle.label(_counter_lbl, 11, GameStyle.GREY)
	msg_head.add_child(_counter_lbl)

	_message_edit = TextEdit.new()
	_message_edit.placeholder_text = "请描述遇到的问题：什么时候、做了什么、出现了什么现象……"
	_message_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_message_edit.custom_minimum_size = Vector2(0, 132)
	_message_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	GameStyle.text_edit(_message_edit, 13)
	_message_edit.text_changed.connect(_on_message_changed)
	root_vbox.add_child(_message_edit)

	# ---------- 截图 ----------
	var shot_row := HBoxContainer.new()
	shot_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(shot_row)
	# 网页版没有本机相册可读，整行隐藏（文字反馈仍可用）
	if OS.has_feature("web"):
		shot_row.visible = false

	_pick_btn = Button.new()
	_pick_btn.text = "◆ 从相册选择"
	_pick_btn.custom_minimum_size = Vector2(132, 32)
	_pick_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_pick_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	_pick_btn.pressed.connect(_on_pick_pressed)
	shot_row.add_child(_pick_btn)

	var thumb_frame := PanelContainer.new()
	var thumb_sb := GameStyle.outlined_panel(GameStyle.NAVY2, GameStyle.INK, 2, 0.0)
	thumb_sb.content_margin_left = 2.0
	thumb_sb.content_margin_top = 2.0
	thumb_sb.content_margin_right = 2.0
	thumb_sb.content_margin_bottom = 2.0
	thumb_frame.add_theme_stylebox_override("panel", thumb_sb)
	thumb_frame.visible = false
	shot_row.add_child(thumb_frame)

	_thumb = TextureRect.new()
	_thumb.custom_minimum_size = Vector2(84, 46)
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	thumb_frame.add_child(_thumb)
	_thumb_frame = thumb_frame

	_shot_info = Label.new()
	_shot_info.text = "未选择截图（选填）"
	GameStyle.label(_shot_info, 11, GameStyle.GREY)
	_shot_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shot_info.clip_text = true
	shot_row.add_child(_shot_info)

	_remove_btn = Button.new()
	_remove_btn.text = "移除"
	_remove_btn.custom_minimum_size = Vector2(64, 30)
	_remove_btn.focus_mode = Control.FOCUS_NONE
	_remove_btn.visible = false
	GameStyle.button(_remove_btn, GameStyle.NAVY2, GameStyle.BAD, 12, GameStyle.PAPER, 5.0, GameStyle.CHALK)
	_remove_btn.pressed.connect(_clear_screenshot)
	shot_row.add_child(_remove_btn)

	# ---------- 联系方式 ----------
	var contact_row := HBoxContainer.new()
	contact_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(contact_row)

	var contact_lbl := Label.new()
	contact_lbl.text = "联系方式（选填）"
	GameStyle.label(contact_lbl, 12, GameStyle.PAPER)
	contact_lbl.custom_minimum_size = Vector2(112, 0)
	contact_row.add_child(contact_lbl)

	_contact_edit = LineEdit.new()
	_contact_edit.placeholder_text = "QQ 或邮箱，方便作者回复你"
	_contact_edit.custom_minimum_size = Vector2(0, 32)
	_contact_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contact_edit.max_length = 80
	GameStyle.line_edit(_contact_edit, 13)
	contact_row.add_child(_contact_edit)

	# ---------- 动作条 ----------
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(action_row)

	_send_btn = Button.new()
	_send_btn.text = "发 送"
	_send_btn.custom_minimum_size = Vector2(120, 34)
	_send_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_send_btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 14, GameStyle.INK_TEXT, 5.0)
	_send_btn.pressed.connect(_on_send_pressed)
	action_row.add_child(_send_btn)

	_copy_btn = Button.new()
	_copy_btn.text = "复制反馈内容"
	_copy_btn.custom_minimum_size = Vector2(120, 34)
	_copy_btn.focus_mode = Control.FOCUS_NONE
	GameStyle.button(_copy_btn, GameStyle.NAVY2, GameStyle.GOLD, 13, GameStyle.PAPER, 5.0, GameStyle.INK_TEXT)
	_copy_btn.pressed.connect(_on_copy_pressed)
	action_row.add_child(_copy_btn)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	GameStyle.label(_status_lbl, 11, GameStyle.GOOD_DK)
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_row.add_child(_status_lbl)

func _on_opened() -> void:
	_status_lbl.text = ""
	_sending = false
	_set_inputs_enabled(true)
	# 每次打开都把焦点留在弹窗上，避免上次输入的软键盘残留
	if is_instance_valid(_message_edit):
		_message_edit.release_focus()

func _on_closed() -> void:
	_abort_pending_http()
	_set_status("", GameStyle.GOOD_DK)
	# 收掉键盘避让的位移，下次打开从正中开始
	if _center != null:
		_center.position.y = 0.0

## 发送中禁止关闭：关掉弹窗会取消请求，玩家以为发出去了其实没有。
## 遮罩点击与 ESC 最终都走 close()，这里统一拦。
func close() -> void:
	if _sending:
		_set_status("正在发送，请稍候…", GameStyle.GOLD)
		return
	super.close()

# ---------------- 键盘避让 ----------------

## 安卓软键盘弹出时把面板往上抬：只按「当前聚焦的输入框底边 vs 键盘顶边」算需要抬多少。
## 不整块硬抬 —— 面板 470 高、手机键盘常吃掉 40% 屏高，整块抬会把标题和关闭键顶出屏外。
## 键盘高度是物理像素，按「设计可视宽 / 窗口物理宽」换算成 UI 单位。
func _process(_delta: float) -> void:
	if not visible or _center == null or _panel == null:
		return
	var lift := 0.0
	if OS.has_feature("mobile"):
		var kb_px := DisplayServer.virtual_keyboard_get_height()
		if kb_px > 0:
			var view_rect := get_viewport().get_visible_rect()
			var win_w := DisplayServer.window_get_size().x
			var scale := view_rect.size.x / maxf(1.0, float(win_w))
			var kb_top := view_rect.size.y - float(kb_px) * scale
			var focus := get_viewport().gui_get_focus_owner()
			if focus != null and is_ancestor_of(focus):
				# 当前 _center 偏移已折进 global rect，先减掉才是「未抬升」的基准（否则每帧自追自抖）
				var origin_y := get_global_rect().position.y + _center.position.y
				var focus_bottom := focus.get_global_rect().end.y - origin_y
				var panel_top := _panel.get_global_rect().position.y - origin_y
				var need := focus_bottom - kb_top + 12.0
				# 上限 = 面板顶边，保证标题栏与关闭键不被顶出屏幕
				lift = -clampf(need, 0.0, maxf(0.0, panel_top))
	if not is_equal_approx(_center.position.y, lift):
		_center.position.y = lift

# ---------------- 输入与截图 ----------------

func _on_message_changed() -> void:
	if _message_edit.text.length() > MAX_MESSAGE_CHARS:
		var caret := _message_edit.get_caret_column()
		_message_edit.text = _message_edit.text.substr(0, MAX_MESSAGE_CHARS)
		_message_edit.set_caret_column(mini(caret, MAX_MESSAGE_CHARS))
	_counter_lbl.text = "%d / %d" % [_message_edit.text.length(), MAX_MESSAGE_CHARS]

func _on_pick_pressed() -> void:
	if _sending:
		return
	if OS.has_feature("android"):
		_ensure_media_permission_then_pick()
	else:
		_open_file_dialog()

## Android 相册读取需要运行时权限：Android 13+ 是 READ_MEDIA_IMAGES，旧版是 READ_EXTERNAL_STORAGE。
## 即使玩家拒绝也继续打开系统选择器：SAF 选中的文件通常仍可读，失败时 _apply_screenshot 会给出原因。
func _ensure_media_permission_then_pick() -> void:
	if _permission_waiting:
		return
	var granted := OS.get_granted_permissions()
	if granted.has("android.permission.READ_MEDIA_IMAGES") \
			or granted.has("android.permission.READ_MEDIA_VISUAL_USER_SELECTED") \
			or granted.has("android.permission.READ_EXTERNAL_STORAGE"):
		_open_file_dialog()
		return
	# Android 13（API 33）起 READ_EXTERNAL_STORAGE 对图片失效，只申请新权限；旧系统反之。
	# OS.get_version() 在 Android 上是 Build.VERSION.RELEASE（如 "13" / "14.0"），
	# String.to_int() 取前导数字，兼容带后缀的 ROM 版本串。
	var major := OS.get_version().to_int()
	var perm := "android.permission.READ_MEDIA_IMAGES" if major >= 13 \
		else "android.permission.READ_EXTERNAL_STORAGE"
	_permission_waiting = true
	get_tree().on_request_permissions_result.connect(_on_permission_result, CONNECT_ONE_SHOT)
	if OS.request_permission(perm):
		# 权限早就授过了：request_permission 返回 true 且不会再发结果信号，自己把一次性连接摘掉
		if get_tree().on_request_permissions_result.is_connected(_on_permission_result):
			get_tree().on_request_permissions_result.disconnect(_on_permission_result)
		_permission_waiting = false
		_open_file_dialog()
		return
	# 兜底：部分 ROM 在「已拒绝且不再询问」时既不弹窗也不发结果信号。
	# 1.2 秒后无论有没有回调都打开系统选择器 —— SAF 选中的文件通常仍可读，
	# 读不到时 _on_file_selected 会给出明确原因，不能让按钮静默卡死。
	get_tree().create_timer(1.2, true).timeout.connect(func() -> void:
		if not _permission_waiting:
			return
		_permission_waiting = false
		if get_tree().on_request_permissions_result.is_connected(_on_permission_result):
			get_tree().on_request_permissions_result.disconnect(_on_permission_result)
		if visible:
			_open_file_dialog()
	)

func _on_permission_result(_permission: String, _granted: bool) -> void:
	_permission_waiting = false
	if visible:
		_open_file_dialog()

func _open_file_dialog() -> void:
	if _file_dialog == null or not is_instance_valid(_file_dialog):
		_file_dialog = FileDialog.new()
		_file_dialog.title = "选择一张截图"
		_file_dialog.use_native_dialog = true
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.filters = PackedStringArray([
			"*.png, *.jpg, *.jpeg, *.webp ; 图片文件 ; image/png, image/jpeg, image/webp"
		])
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(720, 460))

func _on_file_selected(path: String) -> void:
	var result := FeedbackSender.compress_image_for_upload(path)
	if not bool(result.get("ok", false)):
		_set_status(String(result.get("error", "图片读取失败")), GameStyle.BAD)
		UpdateManager.show_toast("◆ " + String(result.get("error", "图片读取失败")) + " ◆", GameStyle.BAD)
		return
	_shot_bytes = result.get("bytes", PackedByteArray())
	_shot_name = FeedbackSender.build_attachment_filename()
	_shot_mime = String(result.get("mime", "image/jpeg"))
	_shot_size = _shot_bytes.size()
	var img := Image.new()
	if img.load_jpg_from_buffer(_shot_bytes) == OK:
		_thumb.texture = ImageTexture.create_from_image(img)
	_thumb_frame.visible = true
	_remove_btn.visible = true
	_shot_info.text = "%s · %d×%d · %s" % [
		_shot_name, int(result.get("width", 0)), int(result.get("height", 0)),
		Version.format_bytes(_shot_size),
	]
	_shot_info.add_theme_color_override("font_color", GameStyle.PAPER)
	_set_status("截图已就绪，发送时会一起带上", GameStyle.GOOD_DK)

func _clear_screenshot() -> void:
	_shot_bytes = PackedByteArray()
	_shot_name = ""
	_shot_mime = "image/jpeg"
	_shot_size = 0
	_thumb.texture = null
	_thumb_frame.visible = false
	_remove_btn.visible = false
	_shot_info.text = "未选择截图（选填）"
	_shot_info.add_theme_color_override("font_color", GameStyle.GREY)

# ---------------- 发送与复制 ----------------

func _on_send_pressed() -> void:
	if _sending:
		return
	var message := _message_edit.text
	var err := FeedbackSender.validate_message(message)
	if not err.is_empty():
		_set_status(err, GameStyle.BAD)
		UpdateManager.show_toast("◆ " + err + " ◆", GameStyle.BAD)
		return
	_sending = true
	_set_inputs_enabled(false)
	_set_status("正在发送，请稍候…", GameStyle.GOLD)

	var fields := FeedbackSender.build_fields(message, _contact_edit.text)
	var attachment := {}
	if not _shot_bytes.is_empty():
		attachment = {
			"bytes": _shot_bytes,
			"name": _shot_name,
			"mime": _shot_mime,
		}

	_abort_pending_http()
	_http = HTTPRequest.new()
	_http.timeout = HTTP_TIMEOUT
	_http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_http)

	var result: Dictionary = await FeedbackSender.send_feedback(_http, fields, attachment)
	if not is_instance_valid(self) or not visible:
		return
	_abort_pending_http()
	_sending = false
	_set_inputs_enabled(true)
	if bool(result.get("ok", false)):
		if bool(result.get("activation_required", false)):
			# FormSubmit 的激活邮件只发给收件邮箱（作者），玩家点不了。
			# 发布前作者必须先激活一次；这里如实提示并保留内容，避免玩家以为已送达。
			_set_status("反馈通道尚未激活（需作者先在邮箱点确认链接）。内容已保留，可先点「复制反馈内容」备份。", GameStyle.BAD)
			UpdateManager.show_toast("◆ 反馈通道未激活，内容已保留 ◆", GameStyle.BAD, 3.5)
		else:
			UpdateManager.show_toast("◆ 反馈已发送，感谢道友 ◆", GameStyle.GOOD)
			close()
	else:
		var reason := String(result.get("error", "发送失败"))
		_set_status("发送失败：" + reason + "。可点「复制反馈内容」手动发送。", GameStyle.BAD)
		UpdateManager.show_toast("◆ 发送失败：" + reason + " ◆", GameStyle.BAD, 3.5)

func _on_copy_pressed() -> void:
	var message := _message_edit.text.strip_edges()
	if message.is_empty():
		_set_status("请先填写反馈内容", GameStyle.BAD)
		return
	var text := FeedbackSender.build_report_text(message, _contact_edit.text)
	if DisplayServer.has_method("clipboard_set"):
		DisplayServer.clipboard_set(text)
	_set_status("反馈内容已复制到剪贴板，可手动发送到 favoro@qq.com", GameStyle.GOOD_DK)
	UpdateManager.show_toast("◆ 反馈内容已复制 ◆", GameStyle.GOOD)

func _set_inputs_enabled(on: bool) -> void:
	if is_instance_valid(_message_edit):
		_message_edit.editable = on
	if is_instance_valid(_contact_edit):
		_contact_edit.editable = on
	if is_instance_valid(_pick_btn):
		_pick_btn.disabled = not on
	if is_instance_valid(_remove_btn):
		_remove_btn.disabled = not on
	if is_instance_valid(_send_btn):
		_send_btn.disabled = not on
	if is_instance_valid(_copy_btn):
		_copy_btn.disabled = not on
	if is_instance_valid(_close_btn):
		_close_btn.disabled = not on

func _set_status(text: String, color: Color) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = text
		_status_lbl.add_theme_color_override("font_color", color)

func _abort_pending_http() -> void:
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
	_http = null
