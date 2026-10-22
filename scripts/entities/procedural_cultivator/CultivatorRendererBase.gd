class_name CultivatorRendererBase
extends Node2D

## 程序化修仙角色绘制抽象基类
## 规范全动作状态机（Idle/Run/Dash/Attack/Hit）与三向视角（Front/Side/Back）的统一绘制接口

enum Action {
	IDLE,   ## 待机浮沉
	RUN,    ## 步态奔跑
	DASH,   ## 极速冲刺
	ATTACK, ## 拔剑斩击
	HIT     ## 受击硬直
}

enum Angle {
	FRONT, ## 正面视角
	SIDE,  ## 3/4 侧面视角
	BACK   ## 背面视角
}
## 口径（2026-10-15 恢复）：实机恒为 FRONT（土豆兄弟式纯正面朝相机，见
## ProceduralCultivatorView.set_facing_dir 唯一赋值点，全方向移动纯正面+水平翻转），
## SIDE/BACK 两套绘制只被画廊预览（CultivatorGalleryPreview / CloakFramesPreview 的三向验收）消费。
## 严禁当死代码删除——画廊导出与 SKILL.md 四步拓展流程的验收环节依赖它们。

## 分层渲染开关（仅供像素判据取掩码用，0 表示不过滤＝游戏内正常全画）
## 判据需要单独拿到「只有武器」「只有头部」这两圈真实画出来的像素，
## 所以过滤必须发生在渲染器自己的绘制入口上，不能在测试里另画一套。
enum Layer {
	SHADOW = 1,   ## 地影
	MOTES  = 2,   ## 周天灵气/眼尾拖影
	WEAPON = 4,   ## 背负本命武器
	CLOAK  = 8,   ## 斗篷与胸饰
	HEAD   = 16,  ## 面壳 + 首服 + 眼
	FX     = 32,  ## 斩痕/受击闪光
}

## 位掩码；0 = 全开。非 0 时只画被选中的层。
var debug_layers: int = 0

func _layer_on(layer: int) -> bool:
	return debug_layers == 0 or (debug_layers & layer) != 0

@export var config: CultivatorVisualConfig:
	set(val):
		config = val
		_on_config_changed()
		_dirty = true
		queue_redraw()

func _on_config_changed() -> void:
	pass

var current_action: Action = Action.IDLE:
	set(val):
		if current_action == val:
			return
		current_action = val
		_dirty = true
		queue_redraw()

var current_angle: Angle = Angle.FRONT:
	set(val):
		if current_angle == val:
			return
		current_angle = val
		_dirty = true
		queue_redraw()

var flip_h: bool = false:
	set(val):
		if flip_h == val:
			return
		flip_h = val
		_dirty = true
		queue_redraw()

## 动画驱动物理参数（由 ProceduralCultivatorView 注入）
var gait_phase: float = 0.0
var air: float = 0.0
var speed_ratio: float = 1.0
var dash_progress: float = 0.0   # 0.0 到 1.0
var attack_progress: float = 0.0 # 0.0 到 1.0
var hit_progress: float = 0.0    # 0.0 到 1.0
var lean_angle: float = 0.0
## 归一化移动方向（世界系，"n"=向上远离镜头为 -y）。斗篷风向响应输入；
## 渲染器仅在 RUN 状态消费它并向零平滑衰减，静止残留值无需外部清零。
var move_dir: Vector2 = Vector2.ZERO

## 技能动态外观修饰参数（支持眼睛变色、斗篷反光流光、道印激活等）
var skill_aura_type: String = ""
var eye_override_color: Color = Color.TRANSPARENT
var eye_glow_boost: float = 0.0
var cloak_shimmer_color: Color = Color.TRANSPARENT
var cloak_shimmer_intensity: float = 0.0
var sigil_boost: float = 0.0
var motes_boost: float = 0.0

# —— 重绘节流（参考敌人渲染器节流规范）——
## 选角界面同屏 19 个程序化角色每帧全量重绘是严重卡顿热点。
## 普通展示/UI 头像走 20Hz 节流 + 错相；玩家等高精度个体走 30Hz 节流
## （2026-10-14：原每帧全量重绘是逻辑帧最大单一开销——444 处 draw_ 调用
## × 60fps，降为 30Hz 省一半，动画流畅度轻微可感，经用户确认接受）。
## 60fps 档保持 30Hz 不解锁（2026-10-15 计划决策）：主角位置平滑由 60fps 渲染插值提供，
## 绘制内容 30Hz 是「画面细节」不是「位置」的台阶；每帧全量重绘正是 #05 治理前
## 逻辑帧头号热点（444 处 draw_ × 60fps），仅玩家 1 实例解锁也要 ~7.4k draw_ 指令/秒，
## 60fps 预算下不值。若真机验收仍有分离感，再把 REDRAW_INTERVAL_HIGHFPS 按档翻到 0.0167。
const REDRAW_INTERVAL := 0.05
const REDRAW_INTERVAL_HIGHFPS := 0.0333
static var redraw_count: int = 0

var high_fps_mode: bool = false:
	set(val):
		high_fps_mode = val
		_dirty = true

var _time: float = 0.0
var _draw_phase: float = 0.0
var _dirty: bool = true
## 待机个体错相 + 体型调频基准（2026-10-14 P1）：全角色同频同相的浮沉会让同屏待机
## 的角色像拷贝；instance_id 错开相位，体型缩放反比调频率——大个子沉缓、小个子轻快
var _idle_phase: float = 0.0

func _ready() -> void:
	_draw_phase = fposmod(float(get_instance_id() % 97) * 0.001, REDRAW_INTERVAL)
	_idle_phase = fposmod(float(get_instance_id() % 61) * 0.173, TAU)

func _process(delta: float) -> void:
	_time += delta
	if _dirty or _draw_phase <= 0.0:
		_dirty = false
		_draw_phase = REDRAW_INTERVAL_HIGHFPS if high_fps_mode else REDRAW_INTERVAL
		redraw_count += 1
		_on_before_redraw()
		queue_redraw()
	else:
		_draw_phase -= delta

## 重绘前钩子（虚方法）：炫彩皮肤在此按 _time 重算缓存色，普通皮肤空实现零开销
func _on_before_redraw() -> void:
	pass

func _draw() -> void:
	# 根据动作状态机分发到具体绘制函数
	match current_action:
		Action.IDLE:
			_draw_idle(current_angle)
		Action.RUN:
			_draw_run(current_angle, gait_phase, air)
		Action.DASH:
			_draw_dash(current_angle, dash_progress)
		Action.ATTACK:
			_draw_attack(current_angle, attack_progress)
		Action.HIT:
			_draw_hit(current_angle, hit_progress)

# ----------------- 虚拟接口（由具体风格渲染器实现） -----------------

func _draw_idle(_angle: Angle) -> void:
	pass

func _draw_run(_angle: Angle, _phase: float, _air: float) -> void:
	pass

func _draw_dash(_angle: Angle, _progress: float) -> void:
	pass

func _draw_attack(_angle: Angle, _progress: float) -> void:
	pass

func _draw_hit(_angle: Angle, _progress: float) -> void:
	pass

# ----------------- 实用矢量与几何绘制工具 -----------------

## 自适应圆/弧段数（2026-10-14 性能优化）：内置 draw_circle 固定 64 段，
## 小至 1px 的眸光点也付 64 三角形的钱；渲染器的 draw_circle/draw_arc 统一走这两个包装，
## 按半径与弧角张量自适应 6~32 段。静态缓冲复用，_draw 在主线程串行执行，无重入风险。
static var _circle_buf := PackedVector2Array()
static var _stroke_buf := PackedVector2Array()

func _circle(center: Vector2, radius: float, col: Color) -> void:
	var seg := clampi(int(radius * 1.4), 6, 28)
	_circle_buf.resize(seg)
	for i in range(seg):
		var ang := float(i) * TAU / float(seg)
		_circle_buf[i] = center + Vector2(cos(ang), sin(ang)) * radius
	draw_colored_polygon(_circle_buf, col)

func _arc(center: Vector2, radius: float, start_angle: float, end_angle: float, _point_count: int, color: Color, width: float = 1.0, antialiased: bool = false) -> void:
	var seg := clampi(int(radius * absf(end_angle - start_angle) * 0.22), 6, 32)
	draw_arc(center, radius, start_angle, end_angle, seg, color, width, antialiased)

func draw_stroked_polygon(pts: PackedVector2Array, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	if pts.size() < 3:
		return
	draw_colored_polygon(pts, fill_col)
	var n := pts.size()
	_stroke_buf.resize(n + 1)
	for i in range(n):
		_stroke_buf[i] = pts[i]
	_stroke_buf[n] = pts[0]
	draw_polyline(_stroke_buf, stroke_col, stroke_w, true)

func draw_stroked_circle(center: Vector2, radius: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0) -> void:
	_circle(center, radius, fill_col)
	_arc(center, radius, 0, TAU, 32, stroke_col, stroke_w, true)

func draw_stroked_ellipse(center: Vector2, rx: float, ry: float, fill_col: Color, stroke_col: Color, stroke_w: float = 2.0, segments: int = 0) -> void:
	if segments <= 0:
		segments = clampi(int(maxf(rx, ry) * 1.2), 10, 28)
	_circle_buf.resize(segments)
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		_circle_buf[i] = center + Vector2(cos(theta) * rx, sin(theta) * ry)
	draw_stroked_polygon(_circle_buf, fill_col, stroke_col, stroke_w)

func draw_filled_ellipse(center: Vector2, rx: float, ry: float, col: Color, segments: int = 0) -> void:
	if segments <= 0:
		segments = clampi(int(maxf(rx, ry) * 1.2), 10, 24)
	_circle_buf.resize(segments)
	for i in range(segments):
		var theta := (float(i) / float(segments)) * TAU
		_circle_buf[i] = center + Vector2(cos(theta) * rx, sin(theta) * ry)
	draw_colored_polygon(_circle_buf, col)

func draw_soft_glow(center: Vector2, radius: float, col: Color, layers: int = 3) -> void:
	for i in range(layers):
		var r := radius * (1.0 + float(i) * 0.45)
		var a := col.a / float(i + 1.8)
		_circle(center, r, Color(col.r, col.g, col.b, a))
