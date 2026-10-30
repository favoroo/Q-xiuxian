class_name MenuMeteorShower
extends Control

## 首页氛围层：流星雨自左上斜滑落向右下 + 极淡闪烁星点铺底，
## 垫在纯黑底与卡片矩阵之间。
## 照 ResultFx 自绘范式：纯 _draw 不走粒子池，免依赖；
## 菜单开着时整树暂停，故 process_mode = ALWAYS，_process 自己推相位。
## 随机源一律 GameManager.rng（项目红线），headless 判据下由调用方不建本层。
## 整层 ADD 加法混合：本层只叠在纯黑底上（卡片压在其上），黑底下加法 == 普通混合，
## 流星交叠处更亮、光晕自然融合，白赚一层发光感。
## 抗锯齿口径：项目全局开了 snap_2d_vertices_to_pixel（project.godot），逐节点关不掉。
## 平滑靠素材与画法自身——①拖尾是整条连续折线 + 顶点色渐变（不是分段独立线宽，无一圈圈
## 台阶），且点密 + 每点亚像素抖动，让像素对齐误差彼此不同步、小于一像素，肉眼不可辨；
## ②头部光晕不用贴图（全局 Nearest 会把软光斑缩成马赛克），改用逐层 draw_circle 叠径向
## 渐变，天然平滑；③圆与火花都走 draw_circle 抗锯齿重绘。星点保持像素硬边不动。

## 同屏流星总配额：调低至 5 颗，常态仅 1~2 颗在屏中滑落，清爽宁静不喧宾夺主
const METEOR_COUNT := 5
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
## 拖尾采样点数：沿拖尾取多少顶点配多顶点色。拖尾画成一整条 polyline（颜色按顶点
## 渐变），不是分段独立线宽，所以没有"一圈圈"接缝；点多只为拟合平滑 + 让全局像素
## 对齐的误差分散不同步（每点再叠亚像素抖动），20 点 + 抖动后肉眼不可辨
const TRAIL_SEGMENTS := 20
## 飞出场外后再次入场的歇息区间（秒）：放宽喘息时间，流星不再扎堆接连飞过
const RESPAWN_MIN := 0.8
const RESPAWN_MAX := 2.6
## 背景星点数量：极淡慢闪，只填纯黑的空旷感
const STAR_COUNT := 42

## 火球头部外圈光晕半径（scale=1 基准，px）：柔光晕撑出"球"的体积感
const HALO_R := 12.0
## 火球实心亮核半径（px）：旧菱形本体的替代，构成流星的"燃烧核心"
const CORE_R := 2.4
## 超白 HDR 芯半径（px）：借 WorldEnvironment 泛光微微起辉，是头部的最高光点
const CORE_HDR_R := 1.3
## 噩梦态 HDR 芯：血朱超白（分量 > 1 才会起辉，红通道拉满、绿蓝压低 ⇒ 泛光也是红的）。
## 普通态仍用 GameStyle.FX_HDR_CORE（白芯），两档按 _night 逐项 lerp，不硬切。
const BLOOD_HDR_CORE := Color(2.6, 0.30, 0.22)
## 头部半径脉动幅度与角频率（小数比例 / rad·s）：
## 流星在空中明暗呼吸，比死板的固定亮核有活气
const PULSE_DEPTH := 0.08
const PULSE_SPEED := 7.0

## 拖尾主尾线宽（px）：一根连续折线从头至尾的粗细，头部粗靠顶点色、不是分段线宽
const TRAIL_WIDTH_IN := 3.0
## 拖尾外圈柔光线宽（px）：叠在主尾下的宽而淡一层，消硬边、塑彗发外圈
const TRAIL_WIDTH_OUT := 7.0
## 拖尾锥形衰减指数：尾部收得多快。用整条线的顶点 alpha 渐变做"收细"——
## >1 让远端色淡下去（视觉尾部更细更虚），1.0 是匀速，1.5 平滑收尖
const TRAIL_FALLOFF := 1.5
## 拖尾主尾头部透明度权重（相对流星整体 alpha）：头亮尾虚，收向 0
const TRAIL_ALPHA_IN := 0.6
## 拖尾外圈柔光透明度权重：更淡，只当辉光垫底
const TRAIL_ALPHA_OUT := 0.13

## 每秒每颗流星最大火花产出数（颗/s）：流量更克制，点染即止
const SPARK_RATE_MIN := 3.0
const SPARK_RATE_MAX := 9.0
## 单颗流星同屏火花上限：超出即回收最老的一颗
const SPARK_COUNT_MAX := 5
## 火花寿命区间（秒）：短促，一现即灭
const SPARK_LIFE_MIN := 0.25
const SPARK_LIFE_MAX := 0.55
## 火花侧向飞散速度区间（px/s）：沿拖尾法线左右迸溅
const SPARK_SPEED_MIN := 14.0
const SPARK_SPEED_MAX := 42.0
## 火花半径区间（px）
const SPARK_SIZE_MIN := 1.2
const SPARK_SIZE_MAX := 2.2
## 火花向白插值的比例：火星偏白，与 tint 主色拉开层次
const SPARK_WHITENESS := 0.45
## 噩梦态火花偏白比例：血雨的火星不该发白，压低到几乎同色
const NIGHT_SPARK_WHITENESS := 0.14

## 情绪插值时长（s）：切难度时星点/火花配色在这段时间里过渡
const MOOD_TIME := 0.6

## 流星配色（重复项 = 权重）：普通态纸白为主调，主题色/点缀黄次之，朱砂/幽紫点染。
## 噩梦态整盘换「血雨」：全档血红（亮朱 / 主血朱 / 暗血朱三段明度拉开层次）——
## 2026-10-30 用户口径：噩梦只把流星改血红，别的一概不动（角度、拖尾、星点数量全不变）。
## 两套必须等长且按位一一对应（逐项 lerp）；在飞的流星保留出生时刻的旧色，
## 随各自重生（0.8~2.6s）自然换完，不硬切。
## 注意：主题色 GOLD 已改为运行时可变（static var），不能再写进 const 数组 ⇒ 改为按需现取。
func _palette() -> Array[Color]:
	var day: Array[Color] = [
		GameStyle.CHALK,
		GameStyle.CHALK,
		GameStyle.CHALK,
		GameStyle.GOLD,
		GameStyle.GOLD,
		GameStyle.JADE,
		GameStyle.JADE,
		GameStyle.BAD,
		GameStyle.SHADOW,
	]
	var night: Array[Color] = [
		GameStyle.NIGHT_SEAL_EDGE,
		GameStyle.NIGHT_SEAL,
		GameStyle.NIGHT_SEAL,
		GameStyle.NIGHT_SEAL_EDGE,
		GameStyle.NIGHT_SEAL,
		GameStyle.NIGHT_SEAL,
		GameStyle.NIGHT_SEAL_DK,
		GameStyle.NIGHT_SEAL_DK,
		GameStyle.NIGHT_SEAL,
	]
	var out: Array[Color] = []
	for i in range(day.size()):
		out.append(day[i].lerp(night[i], _night))
	return out

## 星点配色：普通态只取冷调（纸白/主题亮边），暖色星点远看像噪点；
## 噩梦态压成暗血朱星屑，与血雨同调。
func _star_palette() -> Array[Color]:
	var day: Array[Color] = [
		GameStyle.CHALK,
		GameStyle.CHALK,
		GameStyle.GOLD_EDGE,
	]
	var night: Array[Color] = [
		GameStyle.NIGHT_SEAL,
		GameStyle.NIGHT_SEAL_DK,
		GameStyle.NIGHT_SEAL_EDGE,
	]
	var out: Array[Color] = []
	for i in range(day.size()):
		out.append(day[i].lerp(night[i], _night))
	return out


var _meteors: Array[Dictionary] = []
var _stars: Array[Dictionary] = []
var _time := 0.0
## 情绪：0 = 普通天象，1 = 噩梦血雨（切难度时补间，只影响配色/角度，不影响判定）
var _night := 0.0
var _mood_tween: Tween

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

## 切「血雨」：只动配色（流星/星点/火星偏白）的插值，不重建任何星体、不改飞行手感。
## animate=false 用于开菜单时静默对齐当前难度（不闪不补间）。
func set_nightmare(active: bool, animate: bool = true) -> void:
	var target := 1.0 if active else 0.0
	if _mood_tween != null and _mood_tween.is_valid():
		_mood_tween.kill()
		_mood_tween = null
	if not animate or absf(_night - target) < 0.001:
		_night = target
		queue_redraw()
		return
	_mood_tween = create_tween()
	_mood_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_mood_tween.tween_method(_set_mood, _night, target, MOOD_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _set_mood(v: float) -> void:
	_night = v
	queue_redraw()

func _ready() -> void:
	for i in range(METEOR_COUNT):
		_meteors.append({"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0,
			"scale": 1.0, "alpha": 0.5, "tint": GameStyle.CHALK,
			"seed": 0.0, "delay": 0.0, "active": false,
			"sparks": [], "spark_acc": 0.0})
		# 首批错峰入场，时间拉开，避免开局扎堆出现
		_meteors[i]["delay"] = GameManager.rng.randf_range(0.0, 3.5)
		# 头部脉动相位：每颗各错开，避免整屏同步呼吸
		_meteors[i]["seed"] = GameManager.rng.randf_range(0.0, TAU)
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
			# 存调色板索引而不是色值：星点常驻不重生，只有按索引逐帧取色才能跟着难度换色
			"tint_idx": GameManager.rng.randi_range(0, _star_palette().size() - 1),
		})

func _respawn(m: Dictionary) -> void:
	var vp := _vp_size()
	# 下倾角两档共用：2026-10-30 起噩梦只改配色，不改飞行手感
	var ang := deg_to_rad(GameManager.rng.randf_range(ANGLE_MIN, ANGLE_MAX))
	var speed := GameManager.rng.randf_range(SPEED_MIN, SPEED_MAX)
	m["vx"] = cos(ang) * speed
	m["vy"] = sin(ang) * speed
	m["scale"] = GameManager.rng.randf_range(SCALE_MIN, SCALE_MAX)
	m["alpha"] = GameManager.rng.randf_range(ALPHA_MIN, ALPHA_MAX)
	m["tint"] = _palette()[GameManager.rng.randi_range(0, _palette().size() - 1)]
	# 七成自顶边落入、三成自左边划入，覆盖左上半区
	if GameManager.rng.randf() < 0.7:
		m["x"] = GameManager.rng.randf_range(-vp.x * 0.1, vp.x * 0.9)
		m["y"] = -30.0
	else:
		m["x"] = -30.0
		m["y"] = GameManager.rng.randf_range(-vp.y * 0.1, vp.y * 0.5)
	# 上一程的火花不许带到新流星上，否则会在新位置凭空炸开
	(m["sparks"] as Array).clear()
	m["spark_acc"] = 0.0
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
		_emit_sparks(m, delta)
		_step_sparks(m, delta)
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
	# 一帧只算一次调色板：42 颗星逐颗现算会白白摊出 42 份数组
	var pal := _star_palette()
	for st in _stars:
		var tw := 0.5 + 0.5 * sin(_time * st["tw_speed"] + st["phase"])
		var a: float = st["base_a"] * (0.35 + 0.65 * tw)
		draw_circle(Vector2(st["u"] * vp.x, st["v"] * vp.y), st["size"],
			GameStyle.with_alpha(pal[int(st["tint_idx"])], a))

func _draw_meteor(m: Dictionary) -> void:
	var head := Vector2(m["x"], m["y"])
	var vel := Vector2(m["vx"], m["vy"])
	var dir := vel.normalized()
	var alpha: float = m["alpha"]
	var sc: float = m["scale"]
	var tint: Color = m["tint"]
	# 头部半径随时间轻微呼吸，避免死板的固定亮核
	var seed: float = m["seed"]
	var pulse := 1.0 + PULSE_DEPTH * sin(_time * PULSE_SPEED + seed)

	# 拖尾双层锥形：外圈宽而淡的柔光晕 + 内层亮芯，都画成"一整条连续折线"，
	# 粗细恒定、只让顶点 alpha 沿尾向衰减（外圈更快）→ 视觉上头粗尾虚、整条线颜色
	# 平滑插值，没有分段接缝的一圈圈台阶
	var trail_len := vel.length() * TRAIL_TIME
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var cols_in := PackedColorArray()
	for i in range(TRAIL_SEGMENTS + 1):
		var t := float(i) / TRAIL_SEGMENTS
		# taper 0→1：头部满 alpha，尾部指数式压向 0，锥形收尖全靠这条顶点色渐变
		var taper := 1.0 - pow(t, TRAIL_FALLOFF)
		# 每点亚像素抖动：全局像素对齐下各段对齐误差彼此不同步、且小于一像素，
		# 拖尾不会整段一起钉格显锯齿（确定性抖动，不吃 rng）
		var jx := 0.12 if (i % 2 == 0) else -0.12
		var jy := 0.1 if (i % 3 == 0) else -0.07
		pts.append(head - dir * trail_len * t + Vector2(jx, jy))
		cols.append(GameStyle.with_alpha(tint, alpha * TRAIL_ALPHA_OUT * taper))
		cols_in.append(GameStyle.with_alpha(tint, alpha * TRAIL_ALPHA_IN * taper))
	draw_polyline_colors(pts, cols, TRAIL_WIDTH_OUT * sc, true)
	draw_polyline_colors(pts, cols_in, TRAIL_WIDTH_IN * sc, true)

	# 火球头部：外圈柔光晕 + 实心亮核 + HDR 芯。
	# 光晕用逐层 draw_circle 叠径向渐变（不碰贴图，天然无锯齿、不受全局 Nearest 影响）
	var halo_r := HALO_R * sc * pulse
	_draw_radial_halo(head, halo_r, tint, alpha * 0.5)
	# 圆走抗锯齿重绘，避免低级多边形硬边。
	# 噩梦态把「向白插值」压掉、HDR 芯也从超白换血朱超白 —— 否则白芯压过红尾，
	# 整条流星读成白流星只在边上带点红（血雨的核心卖点就是"红到发亮"）。
	var with_white := lerpf(0.30, 0.06, _night)
	draw_circle(head, CORE_R * sc * pulse,
		GameStyle.with_alpha(tint.lerp(Color.WHITE, with_white), alpha), true)
	var hdr_core: Color = GameStyle.FX_HDR_CORE.lerp(BLOOD_HDR_CORE, _night)
	draw_circle(head, CORE_HDR_R * sc * pulse, GameStyle.with_alpha(hdr_core, alpha * 0.9), true)

	_draw_sparks(m)

## 径向柔光晕：由外向内逐层叠圆（外层大而淡、内层小而实），层间 alpha 连续过渡。
## 用 _draw 叠圆而非贴图：贴图受全局 snap/过滤影响会出锯齿或马赛克，叠圆则完全平滑
func _draw_radial_halo(center: Vector2, radius: float, tint: Color, alpha: float) -> void:
	const LAYERS := 10
	for i in range(LAYERS):
		# r 由外（i=0，最淡）向内收，alpha 随内收递增；末层 i=LAYERS-1 最接近实心
		var k := float(LAYERS - i) / LAYERS
		var r := radius * (float(i + 1) / LAYERS)
		# 外层薄、内层厚：alpha 按层位渐变，整体中心亮、边缘溶到 0
		var layer_a := alpha * 0.14 * pow(k, 1.6)
		draw_circle(center, r, GameStyle.with_alpha(tint, layer_a), true)

## 按规整流量沿拖尾迸溅火花：快而大的流星火花更密
func _emit_sparks(m: Dictionary, delta: float) -> void:
	var vel := Vector2(m["vx"], m["vy"])
	var sc: float = m["scale"]
	var fast: float = (vel.length() - SPEED_MIN) / (SPEED_MAX - SPEED_MIN)
	var rate: float = lerpf(SPARK_RATE_MIN, SPARK_RATE_MAX, clampf(fast, 0.0, 1.0)) * sc
	m["spark_acc"] = m["spark_acc"] + rate * delta
	var sparks: Array = m["sparks"]
	while m["spark_acc"] >= 1.0:
		m["spark_acc"] = m["spark_acc"] - 1.0
		if sparks.size() >= SPARK_COUNT_MAX:
			sparks.pop_front()
		_spawn_spark(m)

func _spawn_spark(m: Dictionary) -> void:
	var vel := Vector2(m["vx"], m["vy"])
	var dir := vel.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var sc: float = m["scale"]
	var trail_len := vel.length() * TRAIL_TIME
	# 出生点取拖尾上一处 + 法线微偏移，让火花贴尾而不全压在中线上
	var p := Vector2(m["x"], m["y"]) - dir * trail_len * GameManager.rng.randf()
	p += perp * GameManager.rng.randf_range(-1.6, 1.6) * sc
	var sp := GameManager.rng.randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX) * sc
	var side := 1.0 if GameManager.rng.randf() < 0.5 else -1.0
	var life := GameManager.rng.randf_range(SPARK_LIFE_MIN, SPARK_LIFE_MAX)
	m["sparks"].append({
		"x": p.x, "y": p.y,
		# 侧向飞散为主，再叠一点顺流向后飘的拖尾惯性
		"vx": perp.x * sp * side - dir.x * sp * 0.35,
		"vy": perp.y * sp * side - dir.y * sp * 0.35,
		"life": life, "life_max": life,
		"size": GameManager.rng.randf_range(SPARK_SIZE_MIN, SPARK_SIZE_MAX) * sc,
	})

func _step_sparks(m: Dictionary, delta: float) -> void:
	var sparks: Array = m["sparks"]
	var i := sparks.size() - 1
	while i >= 0:
		var sp: Dictionary = sparks[i]
		sp["x"] = sp["x"] + sp["vx"] * delta
		sp["y"] = sp["y"] + sp["vy"] * delta
		sp["life"] = sp["life"] - delta
		if sp["life"] <= 0.0:
			sparks.remove_at(i)
		i -= 1

## 火花：沿拖尾迸出的小辉点，随寿命缩到一点，偏白显火星
func _draw_sparks(m: Dictionary) -> void:
	# 血雨的火星不该发白：偏白比例随情绪压向 NIGHT_SPARK_WHITENESS
	var hot: Color = m["tint"].lerp(Color.WHITE, lerpf(SPARK_WHITENESS, NIGHT_SPARK_WHITENESS, _night))
	var alpha: float = m["alpha"]
	for sp: Dictionary in m["sparks"]:
		var life_max: float = sp["life_max"]
		var k: float = clampf(sp["life"] / life_max, 0.0, 1.0)
		draw_circle(Vector2(sp["x"], sp["y"]), sp["size"] * k,
			GameStyle.with_alpha(hot, alpha * k * 0.95), true)

func _vp_size() -> Vector2:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0:
		vp = Vector2(960, 540)
	return vp
