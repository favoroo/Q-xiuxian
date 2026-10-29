class_name PlayerLevelRitual
extends Node2D

## 升级仪式感：两段式光柱（T-3.3，空洞螺旋汇聚 × 死亡细胞爆发收尾）：
##   ① 汇聚段 0.4s：金色灵气粒子从四周螺旋吸入角色身躯丹田（贝塞尔向心内卷，颗颗 HDR 起辉）；
##   ② 爆发段：脚下金色光柱（HDR 渐变双层梯形，0.3s 拔起后收）+ 冲击环 + FxParticlePool.LEVEL_PILLAR 粒子喷发。
## 特征与约束：
##   - 纯视觉零判定；光柱挂在角色脚下节点（z_index -1 衬底，通天光芒通透不遮身形）。
##   - 冲击环复用 JuiceEffect.spawn_shockwave 既有 Z_OVERLAY 层；
##   - 喷发粒子复用 FxParticlePool.LEVEL_PILLAR（已冻结基建）；
##   - 粒子数量与轨迹确定性生成，旋转相位由 instance_id 错相，不碰玩法随机源；
##   - 连升多级防重入：演出中再触发立即重置时间轴，零节点泄漏与堆叠。

const GATHER_DUR := 0.40         ## 汇聚段时长（任务卡硬指标 0.4s）
const PILLAR_UP_DUR := 0.11     ## 光柱迅速拔起时长
const PILLAR_TOTAL := 0.30      ## 光柱总时长（任务卡硬指标 0.3s）
const GATHER_RINGS := 3         ## 汇聚螺旋条数
const GATHER_DOTS := 5          ## 每条螺旋上的灵气点数（共 15 粒）
const PILLAR_BASE_W := 22.0     ## 光柱底部半宽
const PILLAR_TOP_W := 36.0      ## 光柱顶部半宽（呈通天放大梯形）
const PILLAR_CORE_BASE_W := 9.0 ## 内层超白柱芯底半宽
const PILLAR_CORE_TOP_W := 15.0 ## 内层超白柱芯顶半宽
const PILLAR_HEIGHT := 190.0    ## 光柱高度（通天挺拔）
const PILLAR_SEGMENTS := 8      ## 梯形分段数（垂直平滑插值）
const HZ := 40.0                ## 演出期间重绘节流

var _t: float = -1.0            ## 演出时间轴（<0 = 空闲）
var _burst_triggered: bool = false
var _phase_seed: float = 0.0
var _redraw_timer: float = 0.0

func _ready() -> void:
	visible = false
	show_behind_parent = true    ## 脚下光柱画在身躯后层衬托，通天柱芯穿透不遮挡脸部
	_phase_seed = fposmod(float(get_instance_id() % 89) * 0.017, TAU)

## 升级仪式唯一触发入口（Player._on_leveled_up 调用）
func play() -> void:
	_t = 0.0
	_burst_triggered = false
	visible = true
	
	# 汇聚段首拍：角色下沉蓄势吸纳天地灵气
	var pl := get_parent() as Player
	if pl != null:
		pl.play_squash(Vector2(1.08, 0.94), 0.22)
	
	queue_redraw()

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	
	var prev_t := _t
	_t += delta
	
	# 跨过 0.4s 汇聚段瞬间触发爆发一拍
	if prev_t < GATHER_DUR and _t >= GATHER_DUR and not _burst_triggered:
		_trigger_burst()
	
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / HZ
		queue_redraw()
	
	if _t >= GATHER_DUR + PILLAR_TOTAL:
		_t = -1.0
		visible = false

func _trigger_burst() -> void:
	_burst_triggered = true
	
	var feet_pos := global_position
	
	# 1. 触发一次性爆发粒子池 LEVEL_PILLAR（超白金色软光斑自脚底向上喷发）
	FxParticlePool.burst(FxParticlePool.LEVEL_PILLAR, feet_pos, GameStyle.FX_HDR_GOLD, 1.0)
	
	# 2. 地面冲击环：向外扩散金色冲击波（复用 JuiceEffect 既有通道）
	var host := get_parent()
	var arena: Node = host.get_parent() if host != null else null
	if arena != null:
		JuiceEffect.spawn_shockwave(arena, feet_pos, 72.0, GameStyle.FX_HDR_GOLD, 0.32)
	
	# 3. 角色挺立拔高动作响应
	var pl := host as Player
	if pl != null:
		pl.play_squash(Vector2(0.72, 1.38), 0.28)

func _draw() -> void:
	if _t < 0.0:
		return
	
	var gold := GameStyle.FX_HDR_GOLD
	
	# ① 汇聚段（0.0s ~ 0.4s）：金色灵气粒子螺旋吸入
	if _t < GATHER_DUR:
		_draw_gather(_t / GATHER_DUR, gold)
	
	# ② 爆发段（0.4s ~ 0.7s）：脚下金色双层梯形光柱拔起后收
	var pillar_t: float = clampf((_t - GATHER_DUR) / PILLAR_TOTAL, 0.0, 1.0)
	if pillar_t > 0.0 and pillar_t < 1.0:
		_draw_pillar(pillar_t, gold)

## 汇聚段：3 条螺旋臂共 15 粒金色灵气珠，向修士丹田身躯中心 (0, -12) 加速螺旋吸入
func _draw_gather(p: float, gold: Color) -> void:
	var ease_p := p * p * p  ## ease-in：近身吸入加速度
	var center := Vector2(0.0, -12.0)  ## 对齐角色丹田身躯中心
	var alpha_in := clampf(p / 0.18, 0.0, 1.0)
	
	for arm in GATHER_RINGS:
		var arm_ang := _phase_seed + float(arm) * TAU / float(GATHER_RINGS) + p * 3.2
		for d in GATHER_DOTS:
			var dp: float = clampf(ease_p * 1.18 - float(d) * 0.048, 0.0, 1.0)
			if dp <= 0.0:
				continue
			var r := lerpf(56.0, 2.5, dp)
			var ang := arm_ang + float(d) * 0.26
			# 2.5D 透视扁率 0.55，呈现立体环绕内卷
			var pos := center + Vector2(cos(ang) * r, sin(ang) * r * 0.55)
			var a := alpha_in * (0.92 - 0.30 * float(d) / float(GATHER_DOTS)) * (1.0 - dp * 0.5)
			var sz := (3.0 - 1.0 * dp)
			
			# 外层浩然金光斑 + 内层超白亮核（WorldEnvironment glow 颗颗起辉）
			AdaptiveDraw.circle(self, pos, sz, Color(gold, a * 0.85), 3.2)
			AdaptiveDraw.circle(self, pos, sz * 0.45, Color(GameStyle.FX_HDR_CORE, a * 0.95), 3.2)
	
	# 汇聚后程（p > 0.7）：丹田中心凝聚超白金核，预备爆发
	if p > 0.70:
		var core_p := (p - 0.70) / 0.30
		AdaptiveDraw.circle(self, center, 4.0 + 4.5 * core_p, Color(gold, 0.65 * core_p), 3.2)
		AdaptiveDraw.circle(self, center, 2.0 + 2.5 * core_p, Color(GameStyle.FX_HDR_CORE, 0.90 * core_p), 3.2)

## 爆发段：脚下金色 HDR 双层梯形光柱（0.11s 拔起直冲天际，后程平滑收束）+ 脚底透视光盘
func _draw_pillar(p: float, gold: Color) -> void:
	# 拔起高度比例：前 0.11s 极速拔起
	var up_norm := PILLAR_UP_DUR / PILLAR_TOTAL
	var h_ratio: float
	if p < up_norm:
		var up := p / up_norm
		h_ratio = 1.0 - pow(1.0 - up, 2.2)
	else:
		h_ratio = 1.0
	
	# 收束淡出：后段整体收合平滑渐隐
	var fade: float
	if p < up_norm:
		fade = 1.0
	else:
		var fp := (p - up_norm) / (1.0 - up_norm)
		fade = 1.0 - pow(fp, 1.6)
	
	if fade <= 0.001:
		return
	
	var h := PILLAR_HEIGHT * h_ratio
	if h <= 2.0:
		return
	
	# 1. 底部脚下透视光盘（随拔起展开、收束淡出）
	var disk_r := 28.0 * (1.0 - 0.22 * p)
	var disk_a := fade * 0.65
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, disk_r, Color(gold, disk_a * 0.45))
	draw_circle(Vector2.ZERO, disk_r * 0.5, Color(GameStyle.FX_HDR_CORE, disk_a * 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	
	# 2. 金色梯形光柱（分段平滑插值，底亮顶消）
	var seg_h := h / float(PILLAR_SEGMENTS)
	var w_base := PILLAR_BASE_W * (1.0 - 0.22 * p)
	var w_top := PILLAR_TOP_W
	var c_base := PILLAR_CORE_BASE_W * (1.0 - 0.22 * p)
	var c_top := PILLAR_CORE_TOP_W
	
	for s in PILLAR_SEGMENTS:
		var t0 := float(s) / float(PILLAR_SEGMENTS)
		var t1 := float(s + 1) / float(PILLAR_SEGMENTS)
		var y0 := -seg_h * float(s)
		var y1 := -seg_h * float(s + 1)
		
		# 梯形半宽插值（呈下收上放的通天光束）
		var w0_out := lerpf(w_base, w_top, t0)
		var w1_out := lerpf(w_base, w_top, t1)
		var w0_core := lerpf(c_base, c_top, t0)
		var w1_core := lerpf(c_base, c_top, t1)
		
		# 垂直衰减（底亮顶消）
		var decay0 := pow(1.0 - t0, 1.35)
		var decay1 := pow(1.0 - t1, 1.35)
		var seg_decay := (decay0 + decay1) * 0.5
		
		# 外层浩然金光幕
		var poly_out := PackedVector2Array([
			Vector2(-w0_out, y0), Vector2(w0_out, y0),
			Vector2(w1_out, y1), Vector2(-w1_out, y1)
		])
		var col_out := Color(gold, fade * 0.46 * seg_decay)
		draw_colored_polygon(poly_out, col_out)
		
		# 内层超白通天柱芯（WorldEnvironment glow 强起辉）
		var poly_core := PackedVector2Array([
			Vector2(-w0_core, y0), Vector2(w0_core, y0),
			Vector2(w1_core, y1), Vector2(-w1_core, y1)
		])
		var col_core := Color(GameStyle.FX_HDR_CORE, fade * 0.88 * seg_decay)
		draw_colored_polygon(poly_core, col_core)
