extends Node

## 判据：升级动效四件套（Lv 徽记组合动画 / 全屏金光 / 待加点徽记弹入 / 连升音调）。
## 运行: $G --headless --path . res://tests/HudLevelFxCheck.tscn
##
## 为什么立这条：升级是攒点制不打断战斗（ GameManager.add_experience 只发信号不弹面板），
## 战斗激烈的瞬间玩家唯一的「升级感」就来自这套 HUD 反馈。旧实现只有一个 1.4→1.0 的
## 缩放弹跳，且没有防重入 —— 连升多级时两段 tween 会叠着跑、颜色闪变根本不存在。
## 这条判据钉的是「动画结束后必须干净复位 + 临时光效节点必须自毁」，因为：
##  ① 徽记底色是动过的 stylebox 副本 —— 停在金色上就是永久性 UI 状态损坏；
##  ② HudLevelBadgeFx 是临时节点 —— 不自毁就是每升一级漏一个 Control；
##  ③ 待加点徽记首现必须真的弹出来（visible 闪现不算动画，但至少不能不出现）。

const CULTIVATOR := "fuzhen"
const START_WEAPON := "qingyun_sword"
## 一次喂够跨多级的大经验（链首几级需求很小，500 必然连升 ≥ 2 级）
const BIG_EXP := 500
## 动画全家总时长（徽记 0.48s / 光效 0.5s / 金光 0.34s / 弹入 0.25s）之外再放宽
const SETTLE_SEC := 1.5
## 徽记场景原配底色（GameHUD.tscn StyleBoxFlat_level_badge.bg_color）
const BADGE_BASE_BG := Color(0.22, 0.486, 0.902, 1)

var _c := TestCheck.new()
var _main: Node
var _hud: Control

func _ready() -> void:
	call_deferred("_boot")

func _boot() -> void:
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_main)
	await _settle(4)
	GameManager.cultivator_id = CULTIVATOR
	GameManager.start_run(START_WEAPON)
	get_tree().paused = false
	if GameManager.player != null:
		GameManager.player.max_health = 99999.0
		GameManager.player.current_health = 99999.0
	_hud = _main.get_node_or_null("UILayer/GameHUD") as Control
	# 徽记/槽位是 queue_free 重建的，等旧那批真离树再取样
	await _settle(10)
	await _run()
	get_tree().quit(0 if _c.report("LEVELFX_RESULT") else 1)

func _run() -> void:
	if not _c.check(_hud != null, "GameHUD 已挂到 UILayer"):
		return
	var badge: PanelContainer = _hud.get_node("TopContainer/LeftBox/LevelBadge")
	var flash: ColorRect = _hud.get_node_or_null("LevelFlash")
	var chip := _find_pending_chip()
	var pre_bg: Color = badge.get_theme_stylebox("panel").bg_color
	var level_before: int = GameManager.level

	# ---- 连升多级：走真实入口 add_experience，一次性触发全链路 ----
	GameManager.add_experience(BIG_EXP)
	var gained: int = GameManager.level - level_before
	_c.check(gained >= 2, "大经验一次连升 ≥ 2 级（实得 %d 级）" % gained)
	_c.check(_count_fx() >= 1, "升级瞬间生成光环/星屑特效节点")
	# 待加点徽记：攒点首现
	_c.check(chip != null and chip.visible, "待加点徽记随升级出现")
	if chip != null:
		_c.equals(chip.get_child(0).text, "升级 ×%d" % GameManager.pending_upgrade_points, "待加点徽记文案与攒点数同源")

	# ---- 动画播完：全部干净复位，临时光效节点自毁 ----
	await get_tree().create_timer(SETTLE_SEC).timeout
	_c.check(_count_fx() == 0, "动画结束后临时光效节点已自毁（无泄漏）")
	_c.check(badge.scale.is_equal_approx(Vector2.ONE), "徽记缩放复位（squash 回弹不留残形）")
	var after_bg: Color = badge.get_theme_stylebox("panel").bg_color
	_c.check(after_bg.is_equal_approx(pre_bg), "徽记底色复位回主蓝（金色闪变不停在错误配色上）")
	var label: Label = badge.get_node("LevelLabel")
	_c.check(label.scale.is_equal_approx(Vector2.ONE), "Lv 数字脉冲复位")
	if flash != null:
		_c.near(flash.modulate.a, 0.0, 0.001, "全屏金光熄灭（不留常亮色块）")
	else:
		_c.check(false, "全屏金光层存在于 HUD")

	# ---- 可重入：连发两次升级信号（模拟同帧连升），杀旧重播不留残形 ----
	GameManager.player_leveled_up.emit(GameManager.level)
	GameManager.player_leveled_up.emit(GameManager.level)
	await get_tree().create_timer(SETTLE_SEC).timeout
	_c.check(badge.scale.is_equal_approx(Vector2.ONE), "重入后徽记缩放仍复位")
	_c.check(badge.get_theme_stylebox("panel").bg_color.is_equal_approx(BADGE_BASE_BG), "重入后徽记底色仍复位")
	_c.check(_count_fx() == 0, "重入后光效节点仍无泄漏")

## PendingChip 是代码建的控件，贴在 Lv 徽记之后（LeftBox 第 3 格），按类型找
func _find_pending_chip() -> Control:
	var left_box: Node = _hud.get_node_or_null("TopContainer/LeftBox")
	if left_box == null:
		return null
	for node in left_box.get_children():
		if node is HudPendingChip:
			return node
	return null

func _count_fx() -> int:
	var n := 0
	for node in _hud.get_children():
		if node is HudLevelBadgeFx:
			n += 1
	return n

func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
