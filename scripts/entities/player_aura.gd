class_name PlayerAura
extends Node2D

## 境界光环（T-3.5，空洞冷冽修仙风）：
## 挂在 Player 角色脚下（阴影层高度），按当前境界/悟道层数动态呈现 1-3 圈程序化细环。
## 特征：
##   ① HDR 浩然金超白细环（WorldEnvironment glow 泛光起辉）——基亮分档，峰值有效分量
##      1.44~1.82 稳过 glow 阈值 1.0，境界越高越亮（2026-10-24 前谷值 0.22 时 1 圈档近乎不可见）；
##   ② 前后分层环绕（2026-10-24）：环弧固定屏幕朝向劈成两半——后弧留在角色身后
##      （show_behind_parent 子树序），前弧由 RingFrontLayer 以相对 z_index=+1 画到角色脚前；
##      自转改到装饰件（爻标/灵珠）沿环公转，按 sin(角) 判定前后归属，绕行到两侧极点自然换层；
##      环弧本体自转极慢（52s+ 一圈）本就难察觉，冻结后换层切割线恒在屏幕水平轴上不穿帮；
##   ③ 4.0s 周期呼吸明灭（sin(TAU / 4.0) 柔和律动，摆幅收窄保底可见）；
##   ④ 境界突破脉冲：升档瞬间一圈高亮从丹田扩散 0.6s + 全环短暂提亮（纯视觉零判定）；
##   ⑤ 纯视觉零碰撞判定。
## 【注意】2026-10-16：圆/弧接 AdaptiveDraw 自适应段数（半径 17~36px 圆环 36~48 段虚耗，自适应后 6~32 段）。
## 【坑】前弧禁止用负 z 调层——EntitiesLayer 全员 z=0，负 z 会整体掉进 MapLayer 不透明地砖之下
## （FloatingWeapon 同款教训）；前弧只许 +z，后弧只许子树序/show_behind_parent，不动 z。
## 目检预览台：tests/AuraPreview.tscn（真渲染三档对比 + 呼吸双相位 + 突破脉冲 + 4 倍特写，不接判据）。

const ROT_SPEED_INNER := 0.12    ## 内环爻标公转角速度（rad/s，约 52s/圈）
const ROT_SPEED_MID := -0.08    ## 中环灵珠公转（反向，约 78s/圈）
const ROT_SPEED_OUTER := 0.05   ## 外环双爻公转（约 125s/圈）
const BREATH_PERIOD := 4.0      ## 呼吸明灭周期（秒，任务卡硬指标 4s）
const REDRAW_INTERVAL := 0.05   ## 重绘节流（20Hz，对齐全局 VisualRate 规范）
const RING_R: Array[float] = [17.0, 26.0, 36.0]           ## 三档圈半径（拉开圈距，实机一眼可数）
const TIER_BASE_ALPHA: Array[float] = [0.40, 0.48, 0.56]  ## 分档基亮：境界越高谷值也保持可见
const BREATH_AMP := 0.20        ## 呼吸摆幅（峰值 = 基亮 + 摆幅）
const PULSE_DUR := 0.6          ## 突破脉冲时长（秒）
const PULSE_R0 := 6.0           ## 突破脉冲扩散起始半径（丹田）
const FRONT_Z := 1              ## 前弧相对层级（>0 压过角色本体与同级实体，见文件头「坑」）

var _time: float = 0.0
var _redraw_timer: float = 0.0
var _rot_inner: float = 0.0
var _rot_mid: float = 0.0
var _rot_outer: float = 0.0
var _tier: int = 1              ## 境界档位（1~3 圈）
var _pulse_t: float = -1.0      ## 突破脉冲时间轴（<0 空闲）
var _front: RingFrontLayer = null

func _ready() -> void:
	show_behind_parent = true
	position = Vector2(0, 16)   ## 对齐角色脚下/阴影基准位
	_update_tier()
	if GameManager.has_signal("player_leveled_up"):
		GameManager.player_leveled_up.connect(_on_player_leveled_up)
	if GameManager.has_signal("upgrade_applied"):
		GameManager.upgrade_applied.connect(_on_upgrade_applied)
	_front = RingFrontLayer.new()
	_front.aura = self
	_front.z_index = FRONT_Z
	add_child(_front)

func _on_player_leveled_up(_lv: int) -> void:
	_advance_tier()

func _on_upgrade_applied(_u: String) -> void:
	_advance_tier()

func _process(delta: float) -> void:
	_time += delta
	_rot_inner += ROT_SPEED_INNER * delta
	_rot_mid += ROT_SPEED_MID * delta
	_rot_outer += ROT_SPEED_OUTER * delta
	if _pulse_t >= 0.0:
		_pulse_t += delta
		if _pulse_t > PULSE_DUR:
			_pulse_t = -1.0

	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()
		if _front != null:
			_front.queue_redraw()

## 计算当前境界光环档位（1-3 圈）：
## 依据角色等级与已加点数综合评定
##   1 圈（初入道途）：初始常驻
##   2 圈（渐入佳境）：等级 ≥ 6 或 加点 ≥ 4
##   3 圈（道法圆满）：等级 ≥ 12 或 加点 ≥ 8
func _update_tier() -> void:
	var lv := GameManager.level
	var total_upgrades := 0
	for count in GameManager.upgrade_counts.values():
		total_upgrades += int(count)
	if lv >= 12 or total_upgrades >= 8:
		_tier = 3
	elif lv >= 6 or total_upgrades >= 4:
		_tier = 2
	else:
		_tier = 1

## 升档解析：境界抬升才放突破脉冲（同档内反复升级/加点只重算不脉冲）
func _advance_tier() -> void:
	var prev := _tier
	_update_tier()
	if _tier > prev:
		_pulse_t = 0.0

func _draw() -> void:
	draw_rings(self, false)

## 三环绘制主体：宿主画后弧（屏幕上半，y≤0），RingFrontLayer 回调画前弧（下半，y>0）。
## 环弧固定屏幕朝向、装饰件公转并按 sin(角) 分层，切割线恒在水平轴不穿帮（见文件头②）。
func draw_rings(target: CanvasItem, front: bool) -> void:
	# 4s 周期呼吸明灭：基亮随档位抬升、谷值保底可见；峰值 alpha 0.60~0.76 × HDR 金 2.4
	# ⇒ 有效分量 1.44~1.82 稳过 glow 阈值 1.0，泛光真正起辉（原 0.22~0.52 只有 0.53~1.25）
	var wave := sin(_time * TAU / BREATH_PERIOD) * 0.5 + 0.5
	var breath: float = TIER_BASE_ALPHA[_tier - 1] + wave * BREATH_AMP
	if _pulse_t >= 0.0:
		breath *= 1.0 + 0.35 * (1.0 - _pulse_t / PULSE_DUR)  # 突破瞬间全环提亮，随脉冲衰减归零
	var base_hdr := GameStyle.FX_HDR_GOLD
	var col_glow := GameStyle.with_alpha(base_hdr, breath)
	var col_faint := GameStyle.with_alpha(base_hdr, breath * 0.60)

	# 弧段角域：后弧 π..TAU（y≤0 藏身后），前弧 0..π（y>0 画到脚前）
	var arc_a := 0.0 if front else PI
	var arc_b := PI if front else TAU

	# --- 突破脉冲：升档瞬间一圈 2px 高亮从丹田扩散到新境界外缘（前后弧同劈，垫在三环下） ---
	if _pulse_t >= 0.0:
		var k := _pulse_t / PULSE_DUR
		var ease_out := 1.0 - (1.0 - k) * (1.0 - k)
		var pulse_r: float = lerpf(PULSE_R0, RING_R[_tier - 1] + 12.0, ease_out)
		var pulse_a: float = pow(1.0 - k, 1.5) * 0.85
		target.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.48))
		AdaptiveDraw.arc(target, Vector2.ZERO, pulse_r, arc_a, arc_b, GameStyle.with_alpha(base_hdr, pulse_a), 2.0, true)

	# --- 第 1 圈（初境）：细同心主环 + 4 方位八卦爻标（公转，过底即入前弧） ---
	var r1: float = RING_R[0]
	target.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.48))  # 俯视透视扁率 0.48
	AdaptiveDraw.arc(target, Vector2.ZERO, r1, arc_a, arc_b, col_glow, 1.2, true)
	for i in 4:
		var ang := (TAU / 4.0) * float(i) + _rot_inner
		if (sin(ang) > 0.0) == front:
			_draw_tick(target, r1, ang, col_glow, 1.4, 2.5)

	# --- 第 2 圈（中境）：外扩八方灵珠环（灵珠公转，绕到下方时压过脚前） ---
	if _tier >= 2:
		var r2: float = RING_R[1]
		AdaptiveDraw.arc(target, Vector2.ZERO, r2, arc_a, arc_b, col_faint, 1.0, true)
		for j in 8:
			var ang_j := (TAU / 8.0) * float(j) + _rot_mid
			if (sin(ang_j) > 0.0) == front:
				AdaptiveDraw.circle(target, Vector2(cos(ang_j), sin(ang_j)) * r2, 1.8, col_glow)

	# --- 第 3 圈（圆满）：天元四正双爻阵环（4 组双短线公转，少而粗一眼可数） ---
	if _tier >= 3:
		var r3: float = RING_R[2]
		AdaptiveDraw.arc(target, Vector2.ZERO, r3, arc_a, arc_b, col_faint * 0.85, 0.9, true)
		for k in 4:
			var base_ang := (TAU / 4.0) * float(k) + _rot_outer
			for s: float in [-1.0, 1.0]:
				var ang_k: float = base_ang + s * 0.10
				if (sin(ang_k) > 0.0) == front:
					_draw_tick(target, r3, ang_k, col_glow, 1.4, 2.6)

	target.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 沿环径向短爻标：ang 处从 r-off 画到 r+off（调用方已按 sin(角) 分好前后层）
func _draw_tick(target: CanvasItem, r: float, ang: float, col: Color, width: float, off: float) -> void:
	var p1 := Vector2(cos(ang), sin(ang)) * (r - off)
	var p2 := Vector2(cos(ang), sin(ang)) * (r + off)
	target.draw_line(p1, p2, col, width)

## 前弧子层：相对 z_index=+1 压过角色本体；_draw 只回借宿主画前半环（状态/绘制主体全在宿主）
class RingFrontLayer extends Node2D:
	var aura = null  ## 宿主 PlayerAura，鸭子引用避免同类名自引

	func _draw() -> void:
		if aura != null and is_instance_valid(aura):
			aura.draw_rings(self, true)
