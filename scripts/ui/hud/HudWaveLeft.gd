class_name HudWaveLeft
extends PanelContainer

## 「余妖 N/M」芯片：本波还剩多少妖要对付 / 本波敌数总额。
## 数据唯一来源是 WaveSpawner.wave_left_count()/wave_total_count()，与提前清场判定
## _tide_spent 逐枝同源（未刷预算 + 凝聚预警 + 场上活妖含尸体 + 未到场精英/魔君 + 金蟾档期），
## 所以「显示剩 0」与「波当场收尾」永不错位。
##
## 为什么放第二排右缘而不是塞进顶栏（2026-10-13）：LayoutCheck 实测顶栏灌满最坏样本
## 已是 975 宽 > 960、两头各出 8px（生命块少半截、暂停键整个没了那次的老问题），
## 任何新芯片都会重现「顶部 UI 出屏」。第二排右缘与「击杀/金币」列垂直对齐，
## 语义仍接在战况读数区之下；右锚定使宽度随视口走，永不与左起流式的羁绊徽记排争位。
##
## 只在 FIGHT 阶段上屏：清场/悟道/商店阶段读数是停着的，画一个不动的数等于撒谎
## （与 HudWaveCountdown「只有正在打才发倒计时」同一口径）。
## Boss 回合照常显示（倒计时不给 Boss 波是因为表会卡在 0:00，而敌数在锁关期恰恰最有用：
## 「魔君未死敌潮不退」时玩家要看得见还剩几个）。
##
## 5Hz 轮询两个 int 读数，不订阅高频信号、严禁 get_nodes_in_group（v0.0.13 掉帧教训）。

const LEFT_FMT := "余妖 %d/%d"
## 轮询间隔（秒）：敌数变化节奏远慢于帧率，5Hz 足够跟手又不每帧写 Label
const POLL_INTERVAL := 0.2
## LayoutCheck 灌最坏样本的真实上界：预算封顶 90 × 危险度极档 2.08 × 狂战蛮修 1.5 ≈ 194。
## 改乘数曲线时这里跟着走，判据不许另抄一份。
const WORST_LEFT := 194
const WORST_TOTAL := 194
## 第二排纵位与右边距：与羁绊徽记排同带（66..88），贴右缘（顶栏边距同值 22）
const ROW_TOP := 66.0
const ROW_BOTTOM := 88.0
const EDGE_X := 22.0

## 判据灌最坏样本时置 true：锁住轮询刷新，免得控件每 0.2s 把 demo 文案盖回当前回合
var demo_lock: bool = false

var _label: Label = null
var _acc: float = 0.0
var _text_shown: String = ""

func _ready() -> void:
	name = "WaveLeftChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_top = ROW_TOP
	offset_bottom = ROW_BOTTOM
	offset_right = -EDGE_X
	# 样式与同排 KillsChip 一致：黑底斜切芯片，纸白字（不抢波次蓝与金币黄的主次）
	add_theme_stylebox_override("panel", GameStyle.chip(Color(0, 0, 0, 1)))
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", GameStyle.PAPER)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_fit_right()
	visible = false
	refresh_now()

## 右锚贴第二排右缘，左缘按内容最小宽现算。锚点若把左缘也钉在右界（offset_left=-22），
## 容器从 0 宽向右长肉、整颗芯片出屏（LayoutCheck 实测 rect=938 97x29 出屏 75px 的现场）。
func _fit_right() -> void:
	var min_w := get_combined_minimum_size().x
	offset_left = offset_right - maxf(min_w, 40.0)

func _process(delta: float) -> void:
	_acc += delta
	if _acc < POLL_INTERVAL:
		return
	_acc = 0.0
	refresh_now()

func refresh_now() -> void:
	if demo_lock:
		return
	visible = _is_fighting()
	if not visible:
		return
	var spawner: Node = GameManager.wave_spawner
	if spawner == null:
		return
	var t := formatted(spawner.wave_left_count(), spawner.wave_total_count())
	if t != _text_shown:
		_text_shown = t
		_label.text = t

func _is_fighting() -> bool:
	var spawner: Node = GameManager.wave_spawner
	if spawner == null:
		return false
	return int(spawner.phase) == int(WaveSpawner.Phase.FIGHT)

## 唯一格式化出口（判据与屏幕同格式）
static func formatted(left: int, total: int) -> String:
	return LEFT_FMT % [left, total]

## 最长真实读数：LayoutCheck 灌最坏样本取它
static func worst_case_text() -> String:
	return formatted(WORST_LEFT, WORST_TOTAL)

## 把芯片钉成最坏样本并锁住轮询（与 HudWaveCountdown.show_as_worst_case 同一入口约定）
func show_as_worst_case() -> void:
	demo_lock = true
	visible = true
	if _label != null:
		_label.text = worst_case_text()
		_fit_right()

# ---------------- 判据取值口 ----------------

func readout_text() -> String:
	return _text_shown if _label != null else ""

func is_showing() -> bool:
	return visible
