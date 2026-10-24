class_name CoCreateDialog
extends MailFormDialog

## 游戏共创弹窗（2026-10-24）
##
## 首页左下角「游戏共创」打开：玩家选一个类型（角色/武器/道具/技能/其他），
## 写下想要的内容，可附一张参考图与联系方式，由 FeedbackSender 发到作者邮箱。
## 与意见反馈共用 MailFormDialog 的表单、截图与发送链路，差异：
## - 邮件主题带分类（【剑士共创·武器】）
## - 表单多一个 category 字段，作者按类整理玩家创意
## - 不带运行日志（想法类内容用不上），草稿独立落盘

const CATEGORIES := ["角色", "武器", "道具", "技能", "其他"]
const DEFAULT_CATEGORY := "角色"

var _category: String = DEFAULT_CATEGORY
var _category_btns: Array[Button] = []

func _get_title_text() -> String:
	return "游 戏 共 创"

func _get_panel_size() -> Vector2:
	# 比反馈窗高 42：多一排分类 chip
	return Vector2(720, 512)

func _get_panel_margins() -> Vector4:
	return Vector4(24, 14, 24, 14)

func _get_vbox_separation() -> int:
	return 8

func _get_close_btn_text() -> String:
	return "关 闭"

func _get_tip_text() -> String:
	return "想要新角色、新武器、新道具？把想法发给作者，被采纳的会写进更新日志。"

func _get_message_title() -> String:
	return "你的想法（必填）"

func _get_message_placeholder() -> String:
	return "说说你的想法：叫什么、有什么用、怎么玩……"

func _get_send_tag() -> String:
	return FeedbackSender.TAG_COCREATE

func _get_category() -> String:
	return _category

func _get_validate_what() -> String:
	return "想法"

func _get_copy_label() -> String:
	return "复制想法"

func _include_logs() -> bool:
	return false

func _get_draft_path() -> String:
	return FeedbackSender.COCREATE_DRAFT_PATH

# ---------------- 分类 chip ----------------

func _build_extra_body(root_vbox: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(row)

	var title := Label.new()
	title.text = "共创类型"
	GameStyle.label(title, 12, GameStyle.PAPER)
	title.custom_minimum_size = Vector2(66, 0)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	_category_btns.clear()
	for i in CATEGORIES.size():
		var btn := Button.new()
		btn.text = CATEGORIES[i]
		btn.custom_minimum_size = Vector2(76, 30)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_category_pressed.bind(i))
		row.add_child(btn)
		_category_btns.append(btn)
	_refresh_category_buttons()

func _on_category_pressed(index: int) -> void:
	if index < 0 or index >= CATEGORIES.size():
		return
	_category = CATEGORIES[index]
	_refresh_category_buttons()

## 选中项用主色实底黑字，未选中与 Tab 栏未选中态同款（深蓝底纸字）
func _refresh_category_buttons() -> void:
	for i in range(_category_btns.size()):
		var btn := _category_btns[i]
		if not is_instance_valid(btn):
			continue
		if CATEGORIES[i] == _category:
			GameStyle.button(btn, GameStyle.GOLD, GameStyle.GOLD_EDGE, 12, GameStyle.INK_TEXT, 5.0)
		else:
			GameStyle.button(btn, GameStyle.NAVY2, GameStyle.GOLD, 12, GameStyle.PAPER_DIM, 5.0, GameStyle.INK_TEXT)

func _set_extra_inputs_enabled(on: bool) -> void:
	for btn in _category_btns:
		if is_instance_valid(btn):
			btn.disabled = not on

func _clear_extra_fields() -> void:
	_category = DEFAULT_CATEGORY
	_refresh_category_buttons()
