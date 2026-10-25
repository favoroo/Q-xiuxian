class_name HudAuthorHold
extends RefCounted

## 暂停键长按作者模式入口：与 StartMenu 设置徽章同一套隐藏彩蛋（长按 2 秒切换作者模式）。
## 战斗 HUD 与金币阁/悟道面板的顶栏暂停键共用：面板是暂停式模态（打开即树暂停），
## 按住计时走 TWEEN_PAUSE_PROCESS 才走得动。按住过程刻意零视觉反馈（不动文案不动色）
## ——入口是隐藏彩蛋，不能给旁人任何提示；手指滑出按钮（mouse_exited）即作废计时；
## 长按完成后的那一下松手 pressed 由 consume_press() 吃掉，不再打开暂停菜单。

const HOLD_SEC := 2.0

var _owner: Node = null
var _tween: Tween = null
var _fired := false

## 接线到任意按钮：button_down 起计时，button_up / mouse_exited 作废。
## 返回助手实例，宿主用 consume_press() 在 pressed 里收口长按后的松手。
static func attach(owner: Node, btn: Button) -> HudAuthorHold:
	var hold := HudAuthorHold.new()
	hold._owner = owner
	btn.button_down.connect(hold._on_button_down)
	btn.button_up.connect(hold._on_button_up)
	btn.mouse_exited.connect(hold._on_mouse_exited)
	return hold

## 长按完成后的那一下 pressed 是否该被吃掉（一次性消费，不吃就会连开暂停菜单）。
func consume_press() -> bool:
	if not _fired:
		return false
	_fired = false
	return true

func _on_button_down() -> void:
	_fired = false
	_cancel()
	if _owner == null or not is_instance_valid(_owner):
		return
	_tween = _owner.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_interval(HOLD_SEC)
	_tween.tween_callback(_on_hold_complete)

func _on_button_up() -> void:
	_cancel()

func _on_mouse_exited() -> void:
	if _tween != null and _tween.is_valid():
		_cancel()

func _cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _on_hold_complete() -> void:
	_tween = null
	# 宿主已不可见（面板被关掉/被上层模态顶掉）就不切换：入口只在宿主还亮着时生效。
	# 刻意不判树暂停 —— 金币阁/悟道本来就是暂停式模态，判暂停会把面板入口整个堵死。
	if _owner == null or not is_instance_valid(_owner) or not _owner.is_visible_in_tree():
		return
	_fired = true
	GameManager.set_author_mode(not GameManager.author_mode)
	GameManager.announcement_triggered.emit(
		"◆ 作者模式已开启 ◆" if GameManager.author_mode else "作者模式已关闭")
	AudioManager.play_sfx("ui_confirm", 0.9)
