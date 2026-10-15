class_name MenuMeteorShower
extends Control

## 首页氛围层：菱形流星雨自左上斜滑落向右下 + 极淡闪烁星点铺底，
## 垫在纯黑底与卡片矩阵之间。
## 照 ResultFx 自绘范式：纯 _draw 不走粒子池，免依赖、保像素硬边；
## 菜单开着时整树暂停，故 process_mode = ALWAYS，_process 自己推相位。
## 随机源一律 GameManager.rng（项目红线），headless 判据下由调用方不建本层。
## 整层 ADD 加法混合：本层只叠在纯黑底上（卡片压在其上），黑底下加法 == 普通混合，
## 流星交叠处更亮、光晕自然融合，白赚一层发光感。

## 同屏流星数量：多了糊屏，少了没质感
const METEOR_COUNT := 9
## 滑落速度区间（px/s）：每颗不同，快慢错落
const SPEED_MIN := 150.0
const SPEED_MAX := 340.0
## 水平下倾角区间（度）：左上 → 右下，每颗略有差异
const ANGLE_MIN := 20.0
const ANGLE_MAX := 38.0
## 体型区间（倍率）
const SCALE_MIN := 0.8
const SCALE_MAX := 1.6
## 整体透明度区间：克制，点到为止
const ALPHA_MIN := 0.35
const ALPHA_MAX := 0.70
## 拖尾时长（秒）：拖尾长度 = 速度 × 该值，快星尾更长
const TRAIL_TIME := 0.28
## 拖尾分段数：渐隐渐细（段少了能看出一节节，10 段肉眼即连续）
const TRAIL_SEGMENTS := 10
## 飞出场外后再次入场的歇息区间（秒）
const RESPAWN_MIN := 0.3
const RESPAWN_MAX := 1.5
## 背景星点数量：极淡慢闪，只填纯黑的空旷感
const STAR_COUNT := 42

## 菱晶本地坐标（+X 为飞行方向，scale=1 基准）：前尖长、后尖短的拉长菱形
const GEM_FRONT := 9.0
const GEM_BACK := 5.0
const GEM_HALF_W := 3.2

## 流星配色（重复项 = 权重）：纸白为主调，天蓝/点缀黄次之，朱砂/幽紫点染
const PALETTE: Array[Color] = [
	GameStyle.PAPER,
	GameStyle.PAPER,
	GameStyle.PAPER,
	GameStyle.GOLD,
	GameStyle.GOLD,
	GameStyle.JADE,
	GameStyle.JADE,
	GameStyle.BAD,
	GameStyle.SHADOW,
]

## 星点配色：只取冷调（纸白/天蓝亮边），暖色星点远看像噪点
const STAR_PALETTE: Array[Color] = [
	GameStyle.PAPER,
	GameStyle.PAPER,
	GameStyle.GOLD_EDGE,
]

## 头部径向光晕贴图（项目现成软光斑）
const TEX_HALO := preload("res://assets/art/light_radial.png")

var _meteors: Array[Dictionary] = []
var _stars: Array[Dictionary] = []
var _time := 0.0

static func install(host: Control) -> MenuMeteorShower:
	var fx := MenuMeteorShower.new()
	fx.name = "MenuMeteorShower"
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.process_mode = Node.PROCESS_MODE_ALWAYS
	# 加法混合： glow 感与交叠加亮的来源（本层之下恒为纯黑底，无反色风险）
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx.material = mat
	# 装饰层部分星体在屏外，非布局内容，判据放行（同 ResultFx / slash_wipe 惯例）
	fx.set_meta("layout_bleed", true)
	host.add_child(fx)
	return fx

func _ready() -> void:
	for i in range(METEOR_COUNT):
		_meteors.append({"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0,
			"scale": 1.0, "alpha": 0.5, "tint": GameStyle.PAPER,
			"delay": 0.0, "active": false})
		# 首批错峰入场，避免开局齐刷刷一排
		_meteors[i]["delay"] = GameManager.rng.randf_range(0.0, 2.4)
	_seed_stars()

func _seed_stars() -> void:
	# 归一化坐标存星位，窗口尺寸变化时自然铺满
	for i in range(STAR_COUNT):
		_stars.append({
			"u": GameManager.rng.randf(),
			"v": GameManager.rng.randf(),
			"size": GameManager.rng.randf_range(0.7, 1.7),
			"base_a": GameManager.rng.randf_range(0.10, 0.30),
			"tw_speed": GameManager.rng.randf_range(0.5, 1.6),
			"phase": GameManager.rng.randf_range(0.0, TAU),
			"tint": STAR_PALETTE[GameManager.rng.randi_range(0, STAR_PALETTE.size() - 1)],
		})

func _respawn(m: Dictionary) -> void:
	var vp := _vp_size()
	var ang := deg_to_rad(GameManager.rng.randf_range(ANGLE_MIN, ANGLE_MAX))
	var speed := GameManager.rng.randf_range(SPEED_MIN, SPEED_MAX)
	m["vx"] = cos(ang) * speed
	m["vy"] = sin(ang) * speed
	m["scale"] = GameManager.rng.randf_range(SCALE_MIN, SCALE_MAX)
	m["alpha"] = GameManager.rng.randf_range(ALPHA_MIN, ALPHA_MAX)
	m["tint"] = PALETTE[GameManager.rng.randi_range(0, PALETTE.size() - 1)]
	# 七成自顶边落入、三成自左边划入，覆盖左上半区
	if GameManager.rng.randf() < 0.7:
		m["x"] = GameManager.rng.randf_range(-vp.x * 0.1, vp.x * 0.9)
		m["y"] = -30.0
	else:
		m["x"] = -30.0
		m["y"] = GameManager.rng.randf_range(-vp.y * 0.1, vp.y * 0.5)
	m["active"] = true

func _process(delta: float) -> void:
	# 菜单关掉后 StartMenu 隐藏，装饰层别再空转重绘
	if not is_visible_in_tree():
		return
	_time += delta
	var vp := _vp_size()
	for m in _meteors:
		if not m["active"]:
			m["delay"] = m["delay"] - delta
			if m["delay"] <= 0.0:
				_respawn(m)
			continue
		m["x"] = m["x"] + m["vx"] * delta
		m["y"] = m["y"] + m["vy"] * delta
		# 星体拖尾一起出界后歇一会再续下一颗
		var margin := 40.0 + Vector2(m["vx"], m["vy"]).length() * TRAIL_TIME
		if m["x"] - m["vx"] * TRAIL_TIME > vp.x + margin or m["y"] - m["vy"] * TRAIL_TIME > vp.y + margin:
			m["active"] = false
			m["delay"] = GameManager.rng.randf_range(RESPAWN_MIN, RESPAWN_MAX)
	queue_redraw()

func _draw() -> void:
	_draw_stars()
	for m in _meteors:
		if m["active"]:
			_draw_meteor(m)

## 背景星点：极淡小圆，各自慢闪（alpha 呼吸），铺出纯黑的空间纵深
func _draw_stars() -> void:
	var vp := _vp_size()
	for st in _stars:
		var tw := 0.5 + 0.5 * sin(_time * st["tw_speed"] + st["phase"])
		var a: float = st["base_a"] * (0.35 + 0.65 * tw)
		draw_circle(Vector2(st["u"] * vp.x, st["v"] * vp.y), st["size"],
			GameStyle.with_alpha(st["tint"], a))

func _draw_meteor(m: Dictionary) -> void:
	var head := Vector2(m["x"], m["y"])
	var dir := Vector2(m["vx"], m["vy"]).normalized()
	var alpha: float = m["alpha"]
	var sc: float = m["scale"]
	var tint: Color = m["tint"]

	# 拖尾双层：先铺一层宽而淡的柔光底（消硬线感），再叠渐隐渐细的亮芯
	var trail_len := Vector2(m["vx"], m["vy"]).length() * TRAIL_TIME
	var seg_len := trail_len / TRAIL_SEGMENTS
	for i in range(TRAIL_SEGMENTS):
		var t0 := float(i) / TRAIL_SEGMENTS
		var t1 := float(i + 1) / TRAIL_SEGMENTS
		var p0 := head - dir * seg_len * i
		var p1 := head - dir * seg_len * (i + 1)
		draw_line(p0, p1, GameStyle.with_alpha(tint, alpha * 0.16 * (1.0 - t1)),
			lerpf(4.6, 1.2, t0) * sc, true)
		draw_line(p0, p1, GameStyle.with_alpha(tint, alpha * 0.55 * (1.0 - t1)),
			lerpf(1.8, 0.4, t0) * sc, true)

	# 头部软光晕：径向贴图加法混合，天然无锯齿，顺便软化菱形轮廓
	var halo_r := 11.0 * sc
	draw_texture_rect(TEX_HALO, Rect2(head - Vector2(halo_r, halo_r), Vector2(halo_r * 2.0, halo_r * 2.0)),
		false, GameStyle.with_alpha(tint, alpha * 0.38))

	# 星体：沿飞行方向的拉长菱形；draw_colored_polygon 无 AA，
	# 补一圈同色抗锯齿描边收边，轮廓即平滑
	var xf := Transform2D(dir.angle(), head)
	var gem := PackedVector2Array([
		Vector2(GEM_FRONT, 0.0) * sc,
		Vector2(0.0, -GEM_HALF_W) * sc,
		Vector2(-GEM_BACK, 0.0) * sc,
		Vector2(0.0, GEM_HALF_W) * sc,
	])
	for i in range(gem.size()):
		gem[i] = xf * gem[i]
	draw_colored_polygon(gem, GameStyle.with_alpha(tint, alpha))
	var outline := gem + PackedVector2Array([gem[0]])
	draw_polyline(outline, GameStyle.with_alpha(tint, alpha * 0.9), 1.0 * sc, true)

	# 星核一点超白，借 WorldEnvironment 泛光微微起辉（克制，不糊）
	draw_circle(head, 1.6 * sc, GameStyle.with_alpha(GameStyle.FX_HDR_CORE, alpha * 0.55))

func _vp_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return vp
