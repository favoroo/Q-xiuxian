class_name ItemDropEntity
extends Area2D

## 掉落法宝实体（方案 B）：击败精英怪或打破玉匣时爆出的地面战利品实体。
## 1. 纯代码程序化自绘：八边形呼吸法阵框 + 双层旋转菱形灵宝晶核 + 悬浮品阶微签牌；
## 2. 磁吸拾取：玩家走近时吸附飞入袖中，波末清场自动磁吸入包兜底，绝不漏捡；
## 3. 拾取反馈：入包生效、记入 wave_loot_items、发斩获公告横幅、播放装备音效与冲击波。

const PICKUP_DIST := 22.0          ## 飞抵玩家后的拾取距离阈值
const SHAPE_RADIUS := 16.0         ## 拾取判定半径（Layer 5: loot）
const BASE_PULL_SPEED := -50.0     ## 被吸附初期的微反冲初速
const MAX_PULL_SPEED := 750.0      ## 磁吸最大飞行速度
const PULL_ACCELERATION := 950.0   ## 磁吸飞行加速度

var item_id: String = ""
var tier: int = 1
var tier_color: Color = Color.WHITE
var item_name: String = ""
var target_player: Node2D = null

var _time: float = 0.0
var _pop_time: float = 0.25        ## 落地弹出持续时间（秒）
var _pop_vel: Vector2 = Vector2.ZERO
var _current_speed: float = BASE_PULL_SPEED
var _collected: bool = false
var _trail_line: Line2D = null
var _col_shape: CollisionShape2D = null

## 静态工厂创建方法：负责挂载、定点与注入数据
static func spawn(parent: Node, pos: Vector2, id: String) -> ItemDropEntity:
	if parent == null or not is_instance_valid(parent):
		return null
	var drop := ItemDropEntity.new()
	drop.item_id = id
	drop.global_position = pos
	parent.add_child(drop)
	return drop

func _init() -> void:
	collision_layer = 16  ## Layer 5: loot 拾取层
	collision_mask = 0
	add_to_group("gems")  ## 与金币/葫芦同一组，波末清场自动统一磁吸收包

func _ready() -> void:
	_setup_collision()
	_setup_data()
	_setup_pop()

func _setup_collision() -> void:
	_col_shape = CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SHAPE_RADIUS
	_col_shape.shape = circle
	add_child(_col_shape)

func _setup_data() -> void:
	if item_id.is_empty():
		return
	var def: Dictionary = ItemData.get_def(item_id)
	tier = clampi(int(def.get("tier", 1)), 1, 5)
	tier_color = ItemData.tier_color(tier)
	item_name = String(def.get("name", item_id))

func _setup_pop() -> void:
	if GameManager.rng != null:
		var angle := GameManager.rng.randf_range(0.0, TAU)
		var spd := GameManager.rng.randf_range(110.0, 180.0)
		_pop_vel = Vector2(cos(angle), sin(angle)) * spd
	else:
		_pop_vel = Vector2(0.0, -100.0)
	_pop_time = 0.25

func _ensure_trail() -> void:
	if _trail_line != null and is_instance_valid(_trail_line):
		return
	_trail_line = Line2D.new()
	_trail_line.top_level = true
	_trail_line.width = 2.8
	_trail_line.default_color = tier_color
	_trail_line.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_trail_line.visible = false
	add_child(_trail_line)

## 满足 Player.PickupArea 与 WaveSpawner._collect_gems_batched 的契约接口
func magnet_to(player: Node2D) -> void:
	if target_player == null and not _collected:
		target_player = player
		_current_speed = BASE_PULL_SPEED
		_ensure_trail()
		if _trail_line != null:
			_trail_line.default_color = tier_color
			_trail_line.clear_points()
			_trail_line.visible = true

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _physics_process(delta: float) -> void:
	# 出生抛物线弹跳段
	if _pop_time > 0.0:
		_pop_time -= delta
		global_position += _pop_vel * delta
		_pop_vel = _pop_vel.move_toward(Vector2.ZERO, 550.0 * delta)

	# 磁吸追踪段
	if target_player != null and is_instance_valid(target_player):
		var to_player := target_player.global_position - global_position
		var dist := to_player.length()
		var dir := to_player.normalized()
		_current_speed = minf(MAX_PULL_SPEED, _current_speed + PULL_ACCELERATION * delta)
		global_position += dir * _current_speed * delta

		if _trail_line != null and _trail_line.visible:
			_trail_line.add_point(global_position)
			if _trail_line.get_point_count() > 6:
				_trail_line.remove_point(0)

		if dist < PICKUP_DIST:
			_collect(target_player)

## 拾取飞抵生效
func _collect(player: Node2D) -> void:
	if _collected:
		return
	_collected = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	if _col_shape != null and is_instance_valid(_col_shape):
		_col_shape.set_deferred("disabled", true)

	if _trail_line != null and is_instance_valid(_trail_line):
		_trail_line.clear_points()
		_trail_line.visible = false

	# 道具入包并记账
	if not item_id.is_empty():
		GameManager.add_item(item_id)
		GameManager.wave_loot_items.append(item_id)
		# 屏幕斩获公告横幅
		GameManager.announcement_triggered.emit("◆ 缴获法宝 · 得【%s】◆" % item_name)

	# 视听反馈：装备音效 + 冲击环 + 拾取火花
	AudioManager.play_sfx("item_equip", 1.0)
	var parent_node := get_parent()
	if parent_node != null and is_instance_valid(parent_node):
		JuiceEffect.spawn_shockwave(parent_node, global_position, 56.0, tier_color, 0.24)
		JuiceEffect.spawn_pickup_pop(parent_node, global_position, true)

	remove_from_group("gems")
	queue_free()

func _draw() -> void:
	if _collected:
		return

	# 1. 地面椭圆暗影（随浮动微缩放）
	var float_y: float = sin(_time * 4.2) * 3.5 - 9.0
	var shadow_scale: float = 1.0 - (float_y + 9.0) * 0.04
	var shadow_col := Color(0.05, 0.05, 0.08, 0.35)
	var shadow_pts := PackedVector2Array([
		Vector2(-12.0 * shadow_scale, 2.0),
		Vector2(0.0, -1.0 * shadow_scale + 2.0),
		Vector2(12.0 * shadow_scale, 2.0),
		Vector2(0.0, 5.0 * shadow_scale + 2.0)
	])
	draw_colored_polygon(shadow_pts, shadow_col)

	var center := Vector2(0.0, float_y)

	# 2. 外层八边形灵光法阵框（呼吸起伏）
	var ring_r := 16.0 + sin(_time * 5.0) * 1.5
	var ring_col := Color(tier_color.r, tier_color.g, tier_color.b, 0.45 + sin(_time * 4.0) * 0.25)
	var oct_pts := PackedVector2Array()
	var angle_offset := _time * 0.8
	for i in range(8):
		var a := angle_offset + float(i) * (TAU / 8.0)
		oct_pts.append(center + Vector2(cos(a), sin(a)) * ring_r)
	oct_pts.append(oct_pts[0])
	draw_polyline(oct_pts, ring_col, 1.2, false)

	# 3. 四正位公转灵光小符
	var orb_angle := -_time * 1.6
	var orb_dist := 18.5
	for i in range(4):
		var a := orb_angle + float(i) * (PI * 0.5)
		var p := center + Vector2(cos(a), sin(a)) * orb_dist
		draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0)), tier_color)

	# 4. 核心双层旋转晶核
	var rot := sin(_time * 2.2) * 0.18
	var cos_r := cos(rot)
	var sin_r := sin(rot)

	# 外菱形
	var w1 := 10.0
	var h1 := 15.0
	var poly_outer := PackedVector2Array([
		center + Vector2(-w1 * cos_r, -w1 * sin_r),
		center + Vector2(h1 * sin_r, -h1 * cos_r),
		center + Vector2(w1 * cos_r, w1 * sin_r),
		center + Vector2(-h1 * sin_r, h1 * cos_r)
	])
	var body_col := Color(tier_color.r * 0.75, tier_color.g * 0.75, tier_color.b * 0.75, 0.85)
	draw_colored_polygon(poly_outer, body_col)
	draw_polyline(PackedVector2Array([poly_outer[0], poly_outer[1], poly_outer[2], poly_outer[3], poly_outer[0]]), tier_color, 1.5, false)

	# 内菱形（高光核）
	var w2 := 5.0
	var h2 := 8.0
	var poly_inner := PackedVector2Array([
		center + Vector2(-w2 * cos_r, -w2 * sin_r),
		center + Vector2(h2 * sin_r, -h2 * cos_r),
		center + Vector2(w2 * cos_r, w2 * sin_r),
		center + Vector2(-h2 * sin_r, h2 * cos_r)
	])
	draw_colored_polygon(poly_inner, Color(1.0, 1.0, 1.0, 0.9))

	# 5. 悬浮品阶微签牌（新野兽派黑底品阶框 + 墨白微字）
	if not item_name.is_empty():
		var font: Font = GameStyle.body_font()
		var label_str := "【%s】" % item_name
		var text_sz := font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		var tag_y := center.y - 20.0
		var tag_rect := Rect2(Vector2(-text_sz.x * 0.5 - 3.0, tag_y - text_sz.y - 1.0), Vector2(text_sz.x + 6.0, text_sz.y + 2.0))
		draw_rect(tag_rect, GameStyle.INK)
		draw_rect(tag_rect, tier_color, false, 1.0)
		var text_pos := Vector2(-text_sz.x * 0.5, tag_y - 2.0)
		draw_string(font, text_pos, label_str, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, tier_color)
