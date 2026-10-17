class_name FlameConeRenderer
extends Node2D

## 锥形喷吐渲染器（火葫芦，2026-10-13）：三层火锥 + 锥缘火舌抖动 + 顺流火星。
## 几何契约：set_cone 的 length/half_width 就是判定锥的射程与末端半宽
## （画多宽==判多宽）——由 FloatingWeapon 按 WeaponData range 与 CONE_HALF_ANGLE 下发。
## T-2.3 锥口与锥缘叠挂 FxParticlePool EMBER 顺向流火碎屑，零动态灯；20Hz 错相重绘；起喷 0.08s 张开（_open 0→1），收喷即隐。

var length: float = 100.0
var half_width: float = 40.0

## 重绘节流按帧率档位取双档（2026-10-15 VisualRate 档位联动）：火锥几何每帧跟随弹道下发，
## 60fps 档 20Hz 是每 3 帧一画，翻倍到 40Hz；低档 20Hz 维持 perf_probe 预算。
const HZ_LOW := 20.0
const HZ_HIGH := 40.0
static func _redraw_interval() -> float:
	return VisualRate.interval(HZ_HIGH, HZ_LOW)

var _anim: float = 0.0
var _phase: float = 0.0
var _open: float = 0.0   ## 起喷张开度（0→1，0.08s 喷射展开）
var _ember_timer: float = 0.0

func _ready() -> void:
	visible = false
	set_process(false)
	_phase = fposmod(float(get_instance_id() % 97) * 0.001, _redraw_interval())

## 亮起/续命：每帧下发当前几何
func cone_on(p_length: float, p_half_width: float) -> void:
	length = p_length
	half_width = p_half_width
	if not visible:
		visible = true
		_open = 0.0
		_ember_timer = 0.0
		set_process(true)

func cone_off() -> void:
	visible = false
	set_process(false)
	_open = 0.0

func _process(delta: float) -> void:
	_anim += delta
	_open = minf(1.0, _open + delta / 0.08)
	_phase += delta
	_ember_timer -= delta

	# 锥口与锥身火舌粒子流（T-2.3）：节流喷发，局限于判定锥内
	if _ember_timer <= 0.0 and length > 20.0 and _open > 0.25:
		# 2026-10-15 视觉克制化：火星节流 0.08→0.11s。
		# 2026-10-16 攻击粒子减量：多把火葫芦同屏时 EMBER 线性叠加（现已被 FxBudget
		# FRAME_BUDGET_EMBER 收口），节拍再放慢一档 0.11→0.16s，尺寸 0.8/0.6→0.65/0.5；
		# 两发火星传锥向 dir——EMBER 原先硬编码世界 +X 方向，火星不随武器朝向转向
		_ember_timer = 0.16
		var cone_dir := global_transform.x
		var nozzle_pos := global_position
		FxParticlePool.burst(FxParticlePool.EMBER, nozzle_pos, "fire", 0.65, false, cone_dir)
		# 锥缘火舌粒子：中段随机位置，高度限制在判定锥宽度以内（绝不超过判定边缘）
		var t_pos := 0.35 + 0.45 * (float(int(_anim * 100.0) % 100) / 100.0)
		var x_l := length * t_pos
		var max_h := half_width * pow(t_pos, 0.75) * 0.7
		var y_l := ((float(int(_anim * 37.0) % 100) / 50.0) - 1.0) * max_h
		FxParticlePool.burst(FxParticlePool.EMBER, to_global(Vector2(x_l, y_l)), "fire", 0.5, false, cone_dir)
		# 热浪区上报（T-6.1，设置默认关时静态入口首行短路零开销）：锥心中段一团热，
		# 跟随火舌粒子同拍 12.5Hz 续报；hold 覆盖续报间隔的 2 倍防间隙闪断
		# 热浪层必须与世界同 viewport（2026-10-17 #06 SubViewport 化）：world_root 优先，
		# Main 不在场（测试）时退回 tree.root
		HeatDistortionFx.report(GameManager.battle_host(get_tree().root), to_global(Vector2(length * 0.55, 0.0)),
			maxf(half_width * 1.4, 46.0), 1.0, 0.16)

	var interval := _redraw_interval()
	if _phase >= interval:
		_phase -= interval
		queue_redraw()

func _draw() -> void:
	var l := length * lerpf(0.35, 1.0, _open)
	var w := half_width * lerpf(0.45, 1.0, _open)
	if l <= 4.0:
		return
	# 三层同形火锥：外暗赤 / 中炽橙 / 内炽阳超白（接 FX_HDR_FIRE 泛光起辉）
	# 2026-10-15 视觉克制化：三层透明度 0.30/0.55/0.50 → 0.24/0.45/0.40，
	# 几何 length/half_width 判定同源不动，只降叠加油墨感
	_cone_poly(l, w, Color(0.85, 0.25, 0.12, 0.24), 1.0)
	_cone_poly(l * 0.78, w * 0.66, Color(1.0, 0.55, 0.15, 0.45), 0.8)
	_cone_poly(l * 0.5, w * 0.38, GameStyle.FX_HDR_FIRE, 0.4)
	# 顺流火星：四粒火屑沿锥面向前飘，越远越小越淡
	for i in 4:
		var p := fposmod(_anim * 2.6 + float(i) * 0.29, 1.0)
		var pos := Vector2(l * p, w * 0.6 * sin(float(i) * 2.3 + p * 5.0) * p)
		draw_circle(pos, 2.0 * (1.0 - p) + 0.8, Color(1.0, 0.75, 0.35, 0.8 * (1.0 - p)))

## 锥面：根部窄口、沿程按 x^0.75 外扩、侧缘带火舌凸齿（jag 抖动作用于侧缘宽度，绝不自相交）。
## 顶点写进成员缓冲复用（_draw 每次 3 次调用 × 40Hz，原先每次新建数组 ≈ 120 次分配/秒），
## draw_colored_polygon 内部按值拷贝，缓冲可安全复用。
const POLY_STEPS := 10
var _poly_buf := PackedVector2Array()

func _cone_poly(l: float, w: float, col: Color, jag: float) -> void:
	_poly_buf.resize(POLY_STEPS * 2 + 1)
	# 上侧缘：从根部 (0,0) 向末端 (l, -w)
	for i in POLY_STEPS + 1:
		var t := float(i) / float(POLY_STEPS)
		var x := l * t
		var wave := 1.0 + jag * 0.12 * sin(_anim * 22.0 + float(i) * 2.1)
		var h := w * pow(t, 0.75) * wave
		_poly_buf[i] = Vector2(x, -h)
	# 下侧缘：从末端 (l, w) 回到根部
	for i in range(POLY_STEPS, 0, -1):
		var t := float(i) / float(POLY_STEPS)
		var x := l * t
		var wave := 1.0 + jag * 0.12 * sin(_anim * 19.0 + float(i) * 1.7 + 2.0)
		var h := w * pow(t, 0.75) * wave
		_poly_buf[POLY_STEPS + (POLY_STEPS - i) + 1] = Vector2(x, h)
	draw_colored_polygon(_poly_buf, col)
