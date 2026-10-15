class_name PlayerAura
extends Node2D

## 境界光环（T-3.5，空洞冷冽修仙风）：
## 挂在 Player 角色脚下（阴影层高度），按当前境界/悟道层数动态呈现 1-3 圈程序化细环。
## 特征：
##   ① HDR 浩然金超白细环（分量 > 1.0，WorldEnvironment glow 泛光起辉）；
##   ② 极慢正反差速自转（天地阴阳运转感）；
##   ③ 4.0s 周期呼吸明灭（sin(TAU / 4.0) 柔和律动）；
##   ④ 纯视觉零碰撞判定，show_behind_parent 确保不遮挡角色真身。

const ROT_SPEED_INNER := 0.12    ## 内环自转角速度（rad/s，约 52s/圈）
const ROT_SPEED_MID := -0.08    ## 中环反向自转（约 78s/圈）
const ROT_SPEED_OUTER := 0.05   ## 外环慢转（约 125s/圈）
const BREATH_PERIOD := 4.0      ## 呼吸明灭周期（秒，任务卡硬指标 4s）
const REDRAW_INTERVAL := 0.05   ## 重绘节流（20Hz，对齐全局 VisualRate 规范）

var _time: float = 0.0
var _redraw_timer: float = 0.0
var _rot_inner: float = 0.0
var _rot_mid: float = 0.0
var _rot_outer: float = 0.0
var _tier: int = 1              ## 境界档位（1~3 圈）

func _ready() -> void:
	show_behind_parent = true
	position = Vector2(0, 16)   ## 对齐角色脚下/阴影基准位
	_update_tier()
	if GameManager.has_signal("player_leveled_up"):
		GameManager.player_leveled_up.connect(func(_lv: int): _update_tier())
	if GameManager.has_signal("upgrade_applied"):
		GameManager.upgrade_applied.connect(func(_u: String): _update_tier())

func _process(delta: float) -> void:
	_time += delta
	_rot_inner += ROT_SPEED_INNER * delta
	_rot_mid += ROT_SPEED_MID * delta
	_rot_outer += ROT_SPEED_OUTER * delta

	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = REDRAW_INTERVAL
		queue_redraw()

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

func _draw() -> void:
	# 4s 周期柔和呼吸明灭：基础 alpha 0.22 ~ 0.52
	var breath := (sin(_time * TAU / BREATH_PERIOD) * 0.5 + 0.5) * 0.30 + 0.22
	var base_hdr := GameStyle.FX_HDR_GOLD
	var col_glow := GameStyle.with_alpha(base_hdr, breath)
	var col_faint := GameStyle.with_alpha(base_hdr, breath * 0.60)

	# --- 第 1 圈（初境）：细同心主环 + 4 方位八卦爻标 ---
	var r1 := 17.0
	draw_set_transform(Vector2.ZERO, _rot_inner, Vector2(1.0, 0.48))  # 俯视透视扁率 0.48
	draw_arc(Vector2.ZERO, r1, 0.0, TAU, 36, col_glow, 1.2, true)
	for i in 4:
		var ang := (TAU / 4.0) * float(i)
		var p1 := Vector2(cos(ang), sin(ang)) * (r1 - 2.5)
		var p2 := Vector2(cos(ang), sin(ang)) * (r1 + 2.5)
		draw_line(p1, p2, col_glow, 1.4)

	# --- 第 2 圈（中境）：外扩八方灵珠环 ---
	if _tier >= 2:
		var r2 := 24.5
		draw_set_transform(Vector2.ZERO, _rot_mid, Vector2(1.0, 0.48))
		draw_arc(Vector2.ZERO, r2, 0.0, TAU, 40, col_faint, 1.0, true)
		for j in 8:
			var ang_j := (TAU / 8.0) * float(j)
			var pt := Vector2(cos(ang_j), sin(ang_j)) * r2
			draw_circle(pt, 1.2, col_glow)

	# --- 第 3 圈（圆满）：天元十二宫阵环 ---
	if _tier >= 3:
		var r3 := 32.0
		draw_set_transform(Vector2.ZERO, _rot_outer, Vector2(1.0, 0.48))
		draw_arc(Vector2.ZERO, r3, 0.0, TAU, 48, col_faint * 0.85, 0.9, true)
		for k in 12:
			var ang_k := (TAU / 12.0) * float(k)
			var pk1 := Vector2(cos(ang_k), sin(ang_k)) * (r3 - 1.8)
			var pk2 := Vector2(cos(ang_k), sin(ang_k)) * (r3 + 1.8)
			draw_line(pk1, pk2, col_glow, 1.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
