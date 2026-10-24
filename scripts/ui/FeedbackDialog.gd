class_name FeedbackDialog
extends MailFormDialog

## 意见反馈弹窗（2026-10-23，2026-10-24 抽出 MailFormDialog 后仅保留文案差异）
##
## 玩家在设置「其他」页点「建议与反馈」打开：填写文字 + 从相册选一张截图，
## 点发送后由 FeedbackSender 打包成邮件发到作者邮箱。
## 表单、截图链路、发送覆盖层、草稿与键盘避让全在 MailFormDialog，这里只声明反馈口径的文案。

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

func _get_tip_text() -> String:
	return "遇到问题或有好建议？写下来发给作者。发送时会自动附带版本、设备与最近日志，方便定位问题。"

func _get_message_title() -> String:
	return "反馈内容（必填）"

func _get_message_placeholder() -> String:
	return "请描述遇到的问题：什么时候、做了什么、出现了什么现象……"
