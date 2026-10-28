class_name HudWaveCountdown
extends Control

## 顶栏「第 N 波 · M:SS」倒计时 + WaveChip 底部的波进度线。构造时把 GameHUD 那颗
## WaveLabel 接进来，之后这条读数（文字 + 线 + 颜色）的唯一写者就是本控件。
##
## 为什么非要它（2026-10-11 用户提问「每回合回合有对应的倒计时提示吗」）：
## 这根表是「这一回合最长还要撑多久」的刻度：非关底波的 wave_timer 走到 0 一定收尾（顶栏原来只有整局
## 正计时 game_time，从开局往上数，玩家对「这一回合还要撑多久」完全没有刻度，而波长还会从
## 第 1 波 35.9s 一路爬到封顶 80s，中后期一整分钟没参照）。
## 2026-10-12 起它只是**上限**：WaveSpawner._tide_spent 那条提前出口会让敌潮刷尽、场上又清空
## 的波当场收尾并按余秒发「余时赏」⇒ 线没走完波也可能已经完了，别把这根表读成必须熬满。
##
## Boss/精英回合的读数口径（2026-10-22）：
## · Boss 回合整条不出现（用户当轮指令「boss 战就不用倒计时了」）—— 魔君未死就停表锁关、
##   怪继续刷，画一个会卡在 0:00 的读数只会让人以为游戏坏了。
## · 精英回合照常报时：表本身仍有意义（它决定常规刷怪何时停手与关底何时必须解决）。
##   表走完、精英还没伏诛时，读数退化成纯「第 N 波」、线收起 —— 与 Boss 回合同一留白语义，
##   但不提前把整根表藏起来（那样玩家连「这一波还有多久」都看不见）。
##
## 同源（判据 WaveCountdownCheck 钉的就是这条线）：秒数取 spawner.wave_timer、
## 线长取 spawner.wave_timer / GameBalance.wave_duration(n)，也就是真正决定这一回合结束的
## 那两个数。不另起一套计时器，不拿整局时长凑，分母也不许写死 60 —— 写死之后第 1 波
## （总长 35.9s）剩余 12.4s 会把线画成两成半长，实际应该是三成半。

const WAVE_FMT := "第 %d 波"
const TIME_FMT := "%d:%02d"
const SEP := " · "
## 进度线高度（贴在芯片内底边；芯片 content_margin 已经把两侧各让出 10，这里不再自缩）
const BAR_H := 3.0
## 最后这么多秒整颗芯片转朱砂 —— 与生命告急同一色语义：这一回合的表要见底了
const URGENT_SECS := 5
## 顶栏最坏样本取的波号：深层波次的号比关卡第 20 波更长，而波长在这里早已封顶 ⇒ 两者同时最长
const WORST_WAVE := 99

## 判据灌最坏样本时置 true：锁住刷新，免得控件每帧把 demo 文案盖回当前回合
var demo_lock: bool = false

var _label: Label = null
var _ratio: float = 0.0
var _urgent: bool = false
var _has_bar: bool = false
var _text_shown: String = ""
var _last_urgent: bool = false  ## 配色守卫：仅在 _urgent 翻转时写一次 override，不每帧刷
var _last_drawn_ratio: float = -1.0
var _last_drawn_urgent: bool = false
var _last_drawn_has_bar: bool = false
var _last_calc_wave: int = -1
var _last_calc_secs: int = -999

func _init(target: Label) -> void:
	_label = target

func _ready() -> void:
	name = "WaveCountdown"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_now()

func _process(_delta: float) -> void:
	refresh_now()

## 一次算完三件事：读数文字、线长比例、告急色。三者必须来自同一次取值，
## 否则会出现「数字说 0:05、线还剩一半」这种两处各说各话的现场。
func refresh_now() -> void:
	if _label == null or demo_lock:
		return
	var fighting := _is_countdown_wave()
	var left := -1.0
	var ratio := 0.0
	if fighting:
		left = maxf(0.0, float(GameManager.wave_spawner.wave_timer))
		var total := GameBalance.wave_duration(GameManager.wave_number)
		ratio = clampf(left / total, 0.0, 1.0) if total > 0.0 else 0.0
	_has_bar = fighting
	_ratio = ratio
	var cur_secs := int(ceili(left)) if fighting else -1
	var cur_wave := GameManager.wave_number
	_urgent = fighting and cur_secs <= URGENT_SECS
	if cur_secs != _last_calc_secs or cur_wave != _last_calc_wave:
		_last_calc_secs = cur_secs
		_last_calc_wave = cur_wave
		var t := formatted(cur_wave, left)
		if t != _text_shown:
			_text_shown = t
			_label.text = t
	# 配色仅在告急翻转时写一次：每帧调 add_theme_color_override 即使值相同
	# 也触发 NOTIFICATION_THEME_CHANGED → update_minimum_size + queue_redraw，是无谓开销
	if _urgent != _last_urgent:
		_last_urgent = _urgent
		_label.add_theme_color_override("font_color", shown_color())
	# 重绘节流：仅当 bar 显隐/告急翻转/线长变化 >= 0.5px 时重绘，不无条件 60Hz queue_redraw
	var need_redraw := false
	if _has_bar != _last_drawn_has_bar or _urgent != _last_drawn_urgent:
		need_redraw = true
	elif _has_bar and absf(_ratio - _last_drawn_ratio) * maxf(size.x, 100.0) >= 0.5:
		need_redraw = true
	if need_redraw:
		_last_drawn_has_bar = _has_bar
		_last_drawn_urgent = _urgent
		_last_drawn_ratio = _ratio
		queue_redraw()

## 只有「正在打、且不是 Boss 回合」这一格才发倒计时：清场/悟道/商店阶段表是停着的，
## 画一根不动的线等于撒谎；Boss 回合要有意留白（魔君未死会锁关，表会卡在 0:00）。
## 精英回合照常报时，只有「表已走完但精英未除」的锁关期退化成纯波号（不留 0:00 假进度）。
func _is_countdown_wave() -> bool:
	var spawner: Node = GameManager.wave_spawner
	if spawner == null:
		return false
	if int(spawner.phase) != int(WaveSpawner.Phase.FIGHT):
		return false
	if GameBalance.is_boss_wave(GameManager.wave_number):
		return false
	if GameBalance.is_elite_wave(GameManager.wave_number):
		return float(spawner.wave_timer) > 0.0
	return true

## 唯一的格式化出口（left_secs 传负数 = 这一回合不给倒计时）。worst_case_text 也走它，
## 所以判据量的那串字与屏幕上那串字永远同格式。
static func formatted(wave: int, left_secs: float) -> String:
	var head := WAVE_FMT % maxi(wave, 1)
	if left_secs < 0.0:
		return head
	var secs := int(ceili(left_secs))
	return head + SEP + (TIME_FMT % [floori(secs / 60.0), secs % 60])

## 不带倒计时的纯波号（GameHUD 在控件还没建好的那一拍用，也供判据比对 Boss 回合读数）
static func wave_head(wave: int) -> String:
	return formatted(wave, -1.0)

## 最长的那条真实读数：LayoutCheck 灌顶栏最坏样本时取它，不在测试里手抄字符串
static func worst_case_text() -> String:
	return formatted(WORST_WAVE, GameBalance.wave_duration(WORST_WAVE))

## 把芯片钉成最坏样本并锁住每帧刷新（LayoutCheck 与判据共用这一个入口：
## 分两处各写「demo_lock = true + label.text = ...」就会有一处漏掉、量成当前波那条短读数）
func show_as_worst_case() -> void:
	demo_lock = true
	if _label != null:
		_label.text = worst_case_text()

# ---------------- 判据取值口（渲染层只读，判据也从这里取，不另算一套） ----------------

func readout_text() -> String:
	return _text_shown

func bar_ratio() -> float:
	return _ratio

func has_bar() -> bool:
	return _has_bar

func is_urgent() -> bool:
	return _urgent

func shown_color() -> Color:
	return GameStyle.BAD if _urgent else GameStyle.GOLD

## 画出来的那一格有多宽：线长 = 比例 × 芯片内宽（判据量这条，不量布局框）
func fill_width() -> float:
	return size.x * _ratio if _has_bar else 0.0

func _draw() -> void:
	if not _has_bar or size.x <= 0.0:
		return
	var y := size.y - BAR_H
	draw_rect(Rect2(0.0, y, size.x, BAR_H), GameStyle.LINE, true)
	draw_rect(Rect2(0.0, y, fill_width(), BAR_H), shown_color(), true)
