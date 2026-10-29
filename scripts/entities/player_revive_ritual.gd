class_name PlayerReviveRitual
extends Node2D

## 还魂仪式（复活专属演出，2026-10-23）：与升级仪式分开的独立时间轴。
##   ① 凝魂段 0.50s：脚下还魂阵双环逆向旋转（八阵眼）+ 两圈灵环由外向内收拢
##      + 十二粒金白魂火螺旋归入丹田（比升级汇聚更慢更庄重）；
##   ② 还魂爆发：金白双层通灵光柱拔地而起（高出升级柱）+ 金/玉双环错峰炸开 + LEVEL_PILLAR 粒子；
##      Player 侧同步顿帧/震屏/定音，动作归位由 Player 的身躯凝形补间完成；
##   ③ 护体余韵：复活无敌期内脚下保持一圈呼吸金环，把「无敌中」读出来，无敌结束自动收。
## 约束：纯视觉零判定；相位由 instance_id 错相，不碰玩法随机源；演出中重复触发立即重置时间轴，
## 零节点泄漏（本节点常驻 Player 下，只切 visible 与绘制相位）。

const GATHER_DUR := 0.50        ## 凝魂段时长
const PILLAR_UP_DUR := 0.10     ## 光柱拔起时长
const PILLAR_TOTAL := 0.42      ## 光柱总时长（拔起+收束）
const PILLAR_HEIGHT := 240.0    ## 光柱高度（高于升级柱的 190，还魂通天）
const PILLAR_BASE_W := 26.0     ## 光柱外层底部半宽
const PILLAR_TOP_W := 46.0      ## 光柱外层顶部半宽
const PILLAR_CORE_BASE_W := 11.0
const PILLAR_CORE_TOP_W := 19.0
const PILLAR_SEGMENTS := 8
const ARRAY_R_IN := 34.0        ## 还魂阵内环半径
const ARRAY_R_OUT := 46.0       ## 还魂阵外环半径
const ARRAY_RUNES := 8          ## 阵眼数量
const SOUL_ARMS := 3            ## 魂火螺旋臂
const SOUL_DOTS := 4            ## 每条臂魂火数（共 12 粒）
const GUARD_MIN_TIME := 0.6     ## 无敌剩余时间高于此值才画护体金环（避开普通受击无敌帧）
const HZ := 40.0                ## 演出期间重绘节流

var _t: float = -1.0            ## 演出时间轴（<0 = 空闲）
var _burst_triggered: bool = false
var _phase_seed: float = 0.0
var _redraw_timer: float = 0.0

func _ready() -> void:
	visible = false
	show_behind_parent = true   ## 光柱/阵纹衬在身躯后层，通天柱芯不遮挡脸部
	_phase_seed = fposmod(float(get_instance_id() % 97) * 0.013, TAU)

## 复活演出唯一入口（Player.revive_from_death 调用）
func play() -> void:
	_t = 0.0
	_burst_triggered = false
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	var prev_t := _t
	_t += delta

	if prev_t < GATHER_DUR and _t >= GATHER_DUR and not _burst_triggered:
		_trigger_burst()

	# 光柱收束后进入护体余韵：无敌结束（或被普通受击墙挡住）才收场
	var ritual_end := GATHER_DUR + PILLAR_TOTAL
	if _t > ritual_end and not _is_guarding():
		_t = -1.0
		visible = false
		return

	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / HZ
		queue_redraw()

## 爆发拍：粒子/冲击环一次性发射（视觉与判定解耦，伤害与无敌由 Player 处理）
func _trigger_burst() -> void:
	_burst_triggered = true
	var feet := global_position
	FxParticlePool.burst(FxParticlePool.LEVEL_PILLAR, feet, GameStyle.FX_HDR_GOLD, 1.0)
	var host := get_parent()
	var arena: Node = host.get_parent() if host != null else null
	if arena != null:
		# 内金外玉错峰：金色环短促内爆，玉色环更慢更大，呈双重还魂涟漪
		JuiceEffect.spawn_shockwave(arena, feet, 88.0, GameStyle.FX_HDR_GOLD, 0.38)
		JuiceEffect.spawn_shockwave(arena, feet, 132.0, GameStyle.JADE, 0.62)
	if host != null:
		GameFeel.vibrate(90, 0.9)

## 护体余韵判定：父级 Player 的复活无敌仍有一段可观余量
func _is_guarding() -> bool:
	var pl := get_parent() as Player
	if pl == null:
		return false
	return pl.invulnerable_time > GUARD_MIN_TIME

func _draw() -> void:
	if _t < 0.0:
		return
	var gold := GameStyle.FX_HDR_GOLD
	var core := GameStyle.FX_HDR_CORE

	# ① 凝魂段
	if _t < GATHER_DUR:
		var p := _t / GATHER_DUR
		_draw_array(p, gold, core)
		_draw_soul_spiral(p, gold, core)
		_draw_converging_rings(p, gold)
		_draw_gather_core(p, gold, core)

	# ② 还魂光柱
	var pillar_t: float = clampf((_t - GATHER_DUR) / PILLAR_TOTAL, 0.0, 1.0)
	if pillar_t > 0.0 and pillar_t < 1.0:
		_draw_pillar(pillar_t, gold, core)

	# ③ 护体余韵：无敌期呼吸金环（光柱收束后接棒，读数连续）
	if _t > GATHER_DUR + PILLAR_TOTAL * 0.6 and _is_guarding():
		_draw_guard_ring(gold, core)

## 还魂阵：双环逆向旋转的断续圆弧 + 八枚阵眼，地面透视压扁
func _draw_array(p: float, gold: Color, core: Color) -> void:
	var spin := p * 1.5
	var fade_in := clampf(p / 0.15, 0.0, 1.0)
	var fade_out := 1.0 - clampf((p - 0.85) / 0.15, 0.0, 1.0)
	var a := fade_in * fade_out
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))

	# 内环顺时针 6 段弧
	for i in 6:
		var start := _phase_seed + spin + float(i) * TAU / 6.0
		draw_arc(Vector2.ZERO, ARRAY_R_IN, start, start + TAU / 6.0 * 0.62, 10,
			Color(gold, 0.42 * a), 1.6)
	# 外环逆时针 8 段弧（阵眼对齐段间隙）
	for i in ARRAY_RUNES:
		var start := -_phase_seed - spin * 0.7 + float(i) * TAU / ARRAY_RUNES
		draw_arc(Vector2.ZERO, ARRAY_R_OUT, start, start + TAU / ARRAY_RUNES * 0.55, 12,
			Color(core, 0.30 * a), 1.2)
	# 八枚阵眼：外环段间隙处的超白金点
	for i in ARRAY_RUNES:
		var ang := -_phase_seed - spin * 0.7 + float(i) * TAU / ARRAY_RUNES + TAU / ARRAY_RUNES * 0.78
		var rp := Vector2(cos(ang), sin(ang)) * ARRAY_R_OUT
		AdaptiveDraw.circle(self, rp, 1.8, Color(core, 0.75 * a), 3.2)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 魂火螺旋：3 臂 × 4 粒金白魂火，从外圈缓慢内卷归入丹田（近身加速）
func _draw_soul_spiral(p: float, gold: Color, core: Color) -> void:
	var ease_p := p * p * p
	var alpha_in := clampf(p / 0.18, 0.0, 1.0)
	var center := Vector2(0.0, -12.0)
	for arm in SOUL_ARMS:
		var arm_ang := _phase_seed + float(arm) * TAU / float(SOUL_ARMS) + p * 2.6
		for d in SOUL_DOTS:
			var dp: float = clampf(ease_p * 1.16 - float(d) * 0.06, 0.0, 1.0)
			if dp <= 0.0:
				continue
			var r := lerpf(70.0, 3.0, dp)
			var ang := arm_ang + float(d) * 0.30
			var pos := center + Vector2(cos(ang) * r, sin(ang) * r * 0.55)
			var a := alpha_in * (0.9 - 0.28 * float(d) / float(SOUL_DOTS)) * (1.0 - dp * 0.45)
			var sz := 3.2 - 1.2 * dp
			AdaptiveDraw.circle(self, pos, sz, Color(gold, a * 0.75), 3.2)
			AdaptiveDraw.circle(self, pos, sz * 0.44, Color(core, a * 0.95), 3.2)

## 两圈灵环由外向内收拢：复活是「聚」不是「散」，与冲击波方向相反
func _draw_converging_rings(p: float, gold: Color) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	for k in 2:
		var rp: float = clampf(p * 1.35 - float(k) * 0.22, 0.0, 1.0)
		if rp <= 0.0 or rp >= 1.0:
			continue
		var r := lerpf(78.0, 8.0, rp)
		var a := (1.0 - rp) * 0.5
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(gold, a), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 凝魂后程：丹田超白金核凝聚，预备爆发
func _draw_gather_core(p: float, gold: Color, core: Color) -> void:
	if p <= 0.62:
		return
	var cp := (p - 0.62) / 0.38
	var center := Vector2(0.0, -12.0)
	AdaptiveDraw.circle(self, center, 5.0 + 6.0 * cp, Color(gold, 0.55 * cp), 3.2)
	AdaptiveDraw.circle(self, center, 2.4 + 3.2 * cp, Color(core, 0.95 * cp), 3.2)

## 还魂光柱：金白双层梯形（底亮顶消），拔起 0.10s 后平滑收束 + 脚底透视光盘
func _draw_pillar(p: float, gold: Color, core: Color) -> void:
	var up_norm := PILLAR_UP_DUR / PILLAR_TOTAL
	var h_ratio: float
	var fade: float
	if p < up_norm:
		h_ratio = 1.0 - pow(1.0 - p / up_norm, 2.2)
		fade = 1.0
	else:
		h_ratio = 1.0
		fade = 1.0 - pow((p - up_norm) / (1.0 - up_norm), 1.6)
	if fade <= 0.001:
		return

	var h := PILLAR_HEIGHT * h_ratio
	if h <= 2.0:
		return

	# 脚底光盘
	var disk_r := 32.0 * (1.0 - 0.20 * p)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, disk_r, Color(gold, fade * 0.50))
	draw_circle(Vector2.ZERO, disk_r * 0.5, Color(core, fade * 0.85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var seg_h := h / float(PILLAR_SEGMENTS)
	var w_base := PILLAR_BASE_W * (1.0 - 0.20 * p)
	var w_top := PILLAR_TOP_W
	var c_base := PILLAR_CORE_BASE_W * (1.0 - 0.20 * p)
	var c_top := PILLAR_CORE_TOP_W
	for s in PILLAR_SEGMENTS:
		var t0 := float(s) / float(PILLAR_SEGMENTS)
		var t1 := float(s + 1) / float(PILLAR_SEGMENTS)
		var y0 := -seg_h * float(s)
		var y1 := -seg_h * float(s + 1)
		var seg_decay := (pow(1.0 - t0, 1.3) + pow(1.0 - t1, 1.3)) * 0.5

		var w0_out := lerpf(w_base, w_top, t0)
		var w1_out := lerpf(w_base, w_top, t1)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-w0_out, y0), Vector2(w0_out, y0),
			Vector2(w1_out, y1), Vector2(-w1_out, y1)
		]), Color(gold, fade * 0.42 * seg_decay))

		var w0_core := lerpf(c_base, c_top, t0)
		var w1_core := lerpf(c_base, c_top, t1)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-w0_core, y0), Vector2(w0_core, y0),
			Vector2(w1_core, y1), Vector2(-w1_core, y1)
		]), Color(core, fade * 0.90 * seg_decay))

## 护体金环：无敌期内脚下呼吸环 + 四枚环上阵眼（缓慢旋转），无敌结束自然消失
func _draw_guard_ring(gold: Color, core: Color) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var pulse := 0.5 + 0.5 * sin(now * 3.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	var r := 20.0 + 2.0 * pulse
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(gold, 0.26 + 0.14 * pulse), 1.8)
	for i in 4:
		var ang := now * 1.6 + float(i) * TAU / 4.0
		var rp := Vector2(cos(ang), sin(ang)) * (r + 3.0)
		AdaptiveDraw.circle(self, rp, 1.6, Color(core, 0.55 + 0.25 * pulse), 3.2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
