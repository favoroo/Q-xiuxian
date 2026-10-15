class_name HeatDistortionFx
extends CanvasLayer

## 热浪扭曲总管（T-6.1，可选高档位，默认关）：屏幕空间折射的设置开关与热区登记处。
## 架构：不进 Main.tscn/Main.gd（并行热区让路），由首个热源上报时经静态 report()
## 惰性挂到 root；自带 BackBufferCopy(COPY_MODE_VIEWPORT) + 全屏 ColorRect
## (heat_distort.gdshader)。全项目 back buffer copy 预算仅此一处（性能红线 ≤1 且可关）。
##
## 数据流（零信号、零每帧分配）：
##   FlameConeRenderer 火舌节拍(12.5Hz) / ThunderBurst fire_rain 起爆一拍
##   → HeatDistortionFx.report(root, world_pos, radius, strength, hold)
##   → _process 把世界坐标换算屏幕归一坐标写进 4 槽 uniform → shader 热区内抖 UV 折射。
## 设置关闭（默认）时：report 首行短路，BackBufferCopy/ColorRect 根本不创建——零开销。

const MAX_SLOTS := 4
## 热区半径折算屏幕归一时按 960×540 设计视口纵横比还原圆形衰减（stretch=canvas_items+expand，
## SCREEN_UV 在此模式即设计视口归一坐标，与 Main.tscn 渲染规格一致）
const DESIGN_ASPECT := 1.7777

## 每帧一读的开关 memo（照 GameFeel 模式：get_val 每次分配 2 个 String，火锥 12.5Hz
## 上报频次虽低，多把火葫芦同屏时也按帧缓存归零）
static var _enabled_memo: bool = false
static var _enabled_memo_frame: int = -1

## 惰性单例（挂 root，layer=1：只折射 layer 0 世界画面，不碰 vignette(2) 与 UI(10)）
static var _inst: HeatDistortionFx = null

var _copy: BackBufferCopy = null
var _rect: ColorRect = null
var _mat: ShaderMaterial = null
## 热区槽（Array 池，避免每帧分配）：[world_pos, radius, strength, until_ms]
var _slots: Array = []
var _phase: float = 0.0

## 静态上报入口（火锥/火雨唯一调用面）：
## world_pos 世界坐标热心、radius 世界半径、strength 0..1 强度、hold 无续报时热区存活秒数。
static func report(root: Node, world_pos: Vector2, radius: float, strength: float, hold: float) -> void:
	var f := Engine.get_process_frames()
	if f != _enabled_memo_frame:
		_enabled_memo_frame = f
		_enabled_memo = bool(SettingsManager.get_val(&"display", &"heat_distortion", false))
	if not _enabled_memo:
		return
	if _inst == null or not is_instance_valid(_inst):
		_inst = null
		for c in root.get_children():
			if c is HeatDistortionFx:
				_inst = c
				break
		if _inst == null:
			var fx := HeatDistortionFx.new()
			fx.name = "HeatDistortionFx"
			root.add_child(fx)
			_inst = fx
	_inst._report(world_pos, radius, strength, hold)

func _ready() -> void:
	layer = 1
	for i in MAX_SLOTS:
		_slots.append([Vector2.ZERO, 0.0, 0.0, 0])
	_rebuild_channels()
	SettingsManager.setting_changed.connect(_on_setting_changed)

func _exit_tree() -> void:
	if _inst == self:
		_inst = null
	if SettingsManager.setting_changed.is_connected(_on_setting_changed):
		SettingsManager.setting_changed.disconnect(_on_setting_changed)

## 设置开关变化（或首次 ready）：开着就建 BackBufferCopy + ColorRect，关了整通道拆掉
func _rebuild_channels() -> void:
	var want := enabled()
	if want and _rect == null:
		_copy = BackBufferCopy.new()
		_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(_copy)
		_rect = ColorRect.new()
		_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://assets/shaders/heat_distort.gdshader")
		_mat.set_shader_parameter("heats", _zero_params())
		_rect.material = _mat
		add_child(_rect)
	elif not want and _rect != null:
		_rect.queue_free()
		_rect = null
		_mat = null
		if _copy != null:
			_copy.queue_free()
			_copy = null

## 开关读侧（_rebuild_channels 一次性调用，非热路径）
static func enabled() -> bool:
	return bool(SettingsManager.get_val(&"display", &"heat_distortion", false))

## 强制下帧首读重新穿透（测试同帧切开关用；正常游戏流 memo 帧号 TTL 自然过期）
static func invalidate_memo_for_test() -> void:
	_enabled_memo_frame = -1

func _report(world_pos: Vector2, radius: float, strength: float, hold: float) -> void:
	if _rect == null:
		return
	var until_ms := Time.get_ticks_msec() + int(hold * 1000.0)
	# 同位热源合并（150px 内算同一团热）：强者覆盖半径与强度，存活期取更晚者
	for s in _slots:
		if s[2] <= 0.0:
			continue
		if (s[0] as Vector2).distance_to(world_pos) > 150.0:
			continue
		if strength >= s[2]:
			s[0] = world_pos
			s[1] = radius
			s[2] = strength
		s[3] = maxi(s[3], until_ms)
		return
	# 空槽优先，全满顶掉最弱
	var target := -1
	var weakest := 0
	for i in MAX_SLOTS:
		if _slots[i][2] <= 0.0:
			target = i
			break
		if _slots[i][2] < _slots[weakest][2]:
			weakest = i
	if target < 0:
		target = weakest
	var s: Array = _slots[target]
	s[0] = world_pos
	s[1] = radius
	s[2] = strength
	s[3] = until_ms

func _process(delta: float) -> void:
	if _rect == null or _mat == null:
		return
	_phase += delta
	var vp := get_viewport()
	if vp == null:
		return
	var canvas_xform: Transform2D = vp.get_canvas_transform()
	var vs := vp.get_visible_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var now := Time.get_ticks_msec()
	var params: Array = []
	params.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		var s: Array = _slots[i]
		if (s[2] as float) <= 0.0 or (s[3] as int) <= now:
			params[i] = Vector4.ZERO
			continue
		# 世界坐标 → 设计视口归一坐标（stretch canvas_items 下与 SCREEN_UV 同基）
		var screen_pos: Vector2 = canvas_xform * (s[0] as Vector2)
		var norm := screen_pos / vs
		# 屏外（30% 容差）清零，shader 循环里 w<=0 直接跳过
		if norm.x < -0.3 or norm.x > 1.3 or norm.y < -0.3 or norm.y > 1.3:
			params[i] = Vector4.ZERO
			continue
		var r_norm: float = (s[1] as float) / ((vs.x + vs.y) * 0.5)
		params[i] = Vector4(norm.x, norm.y, maxf(r_norm, 0.02), s[2])
	_mat.set_shader_parameter("heats", params)
	_mat.set_shader_parameter("wave", Vector2(_phase, fposmod(_phase * 0.37, 1.0)))

static func _zero_params() -> Array:
	var a: Array = []
	a.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		a[i] = Vector4.ZERO
	return a

func _on_setting_changed(section: StringName, key: StringName, _val: Variant) -> void:
	if section == &"display" and key == &"heat_distortion":
		_rebuild_channels()
