class_name NightmareFogOverlay
extends ColorRect

## 噩梦难度专属视野迷雾与方位微光引导：
## 挂载在 PostProcessLayer（SoftVignette 前，UILayer 下，不遮挡任何 UI）。
## 仅在 GameManager.danger_level >= 1 且局内战斗时启用。
## 在视野限制的同时，在内圈边缘为迷雾外的聚灵阵/藏宝匣绘制轻量微光指引，防止迷路。

const FOG_SHADER := preload("res://assets/shaders/nightmare_fog.gdshader")
const INDICATOR_RADIUS := 150.0  ## 指引图标绘制在清晰视野内沿（像素）
const FAR_THRESHOLD := 175.0     ## 超过此世界距离视作身处迷雾外

## 作者模式/调试下强制开启迷雾视野预览（普通模式下也能随时打开测试）
static var force_fog_preview: bool = false

var _mat: ShaderMaterial = null
var _time_acc: float = 0.0
var _suspended: bool = false

# 缓存场上目标（节流扫描，每 0.3s 扫一次）
var _scan_cd: float = 0.0
var _cached_obelisks: Array[Node2D] = []
var _cached_chests: Array[Node2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchors_preset = Control.PRESET_FULL_RECT
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	var vp := get_viewport()
	if vp != null:
		var vs := vp.get_visible_rect().size
		custom_minimum_size = vs

	_mat = ShaderMaterial.new()
	_mat.shader = FOG_SHADER
	_mat.set_shader_parameter("clear_ratio", GameBalance.NIGHTMARE_FOG_CLEAR_RADIUS / 540.0)
	_mat.set_shader_parameter("feather_ratio", GameBalance.NIGHTMARE_FOG_FEATHER_RADIUS / 540.0)
	_mat.set_shader_parameter("max_alpha", GameBalance.NIGHTMARE_FOG_MAX_ALPHA)
	material = _mat
	visible = false

	if not GameManager.shop_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.shop_opened.connect(_on_fullscreen_ui_opened)
	if not GameManager.alloc_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.alloc_opened.connect(_on_fullscreen_ui_opened)
	if not GameManager.game_over_triggered.is_connected(_on_fullscreen_ui_opened):
		GameManager.game_over_triggered.connect(_on_fullscreen_ui_opened)
	if not GameManager.shop_closed.is_connected(_on_fullscreen_ui_closed):
		GameManager.shop_closed.connect(_on_fullscreen_ui_closed)
	if not GameManager.alloc_finished.is_connected(_on_fullscreen_ui_closed):
		GameManager.alloc_finished.connect(_on_fullscreen_ui_closed)
	if not GameManager.wave_changed.is_connected(_on_wave_changed):
		GameManager.wave_changed.connect(_on_wave_changed)
	if GameManager.has_signal("danger_changed") and not GameManager.danger_changed.is_connected(_on_danger_changed):
		GameManager.danger_changed.connect(_on_danger_changed)

func _exit_tree() -> void:
	if GameManager.shop_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.shop_opened.disconnect(_on_fullscreen_ui_opened)
	if GameManager.alloc_opened.is_connected(_on_fullscreen_ui_opened):
		GameManager.alloc_opened.disconnect(_on_fullscreen_ui_opened)
	if GameManager.game_over_triggered.is_connected(_on_fullscreen_ui_opened):
		GameManager.game_over_triggered.disconnect(_on_fullscreen_ui_opened)
	if GameManager.shop_closed.is_connected(_on_fullscreen_ui_closed):
		GameManager.shop_closed.disconnect(_on_fullscreen_ui_closed)
	if GameManager.alloc_finished.is_connected(_on_fullscreen_ui_closed):
		GameManager.alloc_finished.disconnect(_on_fullscreen_ui_closed)
	if GameManager.wave_changed.is_connected(_on_wave_changed):
		GameManager.wave_changed.disconnect(_on_wave_changed)
	if GameManager.has_signal("danger_changed") and GameManager.danger_changed.is_connected(_on_danger_changed):
		GameManager.danger_changed.disconnect(_on_danger_changed)

func _on_fullscreen_ui_opened() -> void:
	_suspended = true
	visible = false

func _on_fullscreen_ui_closed() -> void:
	_suspended = false
	_check_visibility()

func _on_wave_changed(_n: int) -> void:
	_suspended = false
	_check_visibility()

func _on_danger_changed(_d: int) -> void:
	_check_visibility()

func _check_visibility() -> void:
	var active: bool = ((GameManager.danger_level >= 1 or force_fog_preview)
		and GameManager.run_started 
		and GameManager.wave_number >= 1 
		and not _suspended 
		and not GameManager.is_game_over)
	visible = active

func _process(delta: float) -> void:
	_check_visibility()
	if not visible:
		return

	_time_acc += delta
	var vp := get_viewport()
	if vp == null:
		return

	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x > 0.0 and vs.y > 0.0:
		custom_minimum_size = vs
		var aspect: float = vs.x / vs.y
		_mat.set_shader_parameter("aspect_ratio", aspect)

	var player = GameManager.player
	var p_uv := Vector2(0.5, 0.5)
	if player != null and is_instance_valid(player) and vs.x > 0.0 and vs.y > 0.0:
		var xform: Transform2D = vp.get_canvas_transform()
		var p_scr: Vector2 = xform * player.global_position
		p_uv = Vector2(clampf(p_scr.x / vs.x, 0.0, 1.0), clampf(p_scr.y / vs.y, 0.0, 1.0))

	_mat.set_shader_parameter("player_screen_uv", p_uv)
	_mat.set_shader_parameter("time_val", _time_acc)

	# 节流扫描场上交互物
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = 0.3
		_refresh_targets()

	queue_redraw()

func _refresh_targets() -> void:
	_cached_obelisks.clear()
	_cached_chests.clear()
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("obelisks"):
		if node is BlessingObelisk and is_instance_valid(node) and not (node as BlessingObelisk).spent_this_wave:
			_cached_obelisks.append(node)
	for node in tree.get_nodes_in_group("chests"):
		if node is SpiritChest and is_instance_valid(node) and not (node as SpiritChest).dying:
			_cached_chests.append(node)

func _draw() -> void:
	if not visible:
		return
	var player = GameManager.player
	var vp := get_viewport()
	if player == null or not is_instance_valid(player) or vp == null:
		return

	var xform: Transform2D = vp.get_canvas_transform()
	var p_screen: Vector2 = xform * player.global_position
	var pulse: float = 0.8 + 0.2 * sin(_time_acc * 3.5)

	# 1. 聚灵阵指引（青玉灵芒）
	for ob in _cached_obelisks:
		if ob == null or not is_instance_valid(ob):
			continue
		var to_target: Vector2 = ob.global_position - player.global_position
		if to_target.length() >= FAR_THRESHOLD:
			var dir := to_target.normalized()
			var tip_pos := p_screen + dir * INDICATOR_RADIUS
			_draw_beacon_pip(tip_pos, dir, Color(0.35, 0.85, 1.0, 0.85 * pulse), 7.0)

	# 2. 藏宝匣指引（琥珀金芒）
	for chest in _cached_chests:
		if chest == null or not is_instance_valid(chest):
			continue
		var to_target: Vector2 = chest.global_position - player.global_position
		if to_target.length() >= FAR_THRESHOLD:
			var dir := to_target.normalized()
			var tip_pos := p_screen + dir * (INDICATOR_RADIUS - 8.0)
			_draw_beacon_pip(tip_pos, dir, Color(1.0, 0.82, 0.35, 0.80 * pulse), 5.5)

## 绘制贴在内沿方向的小菱形灵光标
func _draw_beacon_pip(pos: Vector2, dir: Vector2, col: Color, sz: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([
		pos + dir * (sz * 1.3),
		pos + perp * (sz * 0.7),
		pos - dir * (sz * 0.8),
		pos - perp * (sz * 0.7)
	])
	draw_colored_polygon(pts, col)
