extends Node

## 敌人 / 藏宝匣 / 修士「画出来到底多大」量尺（非判据现场工具，2026-10-10）
##
## 为什么要量：`.tscn` 里的 AnimatedSprite2D.scale 是像素图集时代（192px 单元格）留下的，
## 换成程序化矢量渲染后它还要再乘一遍，于是「配置里有 scale_factor、节点里有 scale、判据全绿」
## 却没人知道屏幕上一只妖实际占多少逻辑像素。这里把三样一起打出来：
##   1) 画出来的外接框（回读窗口像素，量真实那一圈，不看布局盒）
##   2) 判定用的直径（body / hurtbox）
##   3) 缩放链（view_scale × config.scale_factor）
##
## 一次启动逐个量：每只实体单独上场（画布上只有它一个）→ 等出生弹性与重绘走完 → 回读整幅
## 像素取外接框 → 撤下再换下一只。同屏摆一排会互相吃进对方的搜索窗（第一版就是这么废的）。
##
## 运行（要真实渲染，不能用 --headless）:
##   $G --path . res://tests/EntitySizeProbe.tscn
##   $G --path . res://tests/EntitySizeProbe.tscn -- --shot    # 每只另存 /tmp/size_<id>.png 裁切
##   $G --path . res://tests/EntitySizeProbe.tscn -- --only chest
##
## 口径：实体不进战斗（GameManager.player 留空 ⇒ EnemyBase._physics_process 早早返回，
## 不追击、不掉血、不会被法器打），取的是静止姿态；跑动中的 squash/bob 只有 ±几个百分点，
## 不影响这里比「大小档」。

const BG := Color(0.02, 0.03, 0.05)
const BRIGHT_EPS := 0.14  ## 亮部（骨白/鎏金/符光这类高反差描边）
const SIL_EPS := 0.02     ## 剪影：只要不是背景就算，玄铁暗色主体靠这条才量得到
const SETTLE_FRAMES := 30
const ENTITY_POS := Vector2(480, 270)  ## 逻辑画布（960×540）正中
const SCAN_HALF := 170.0               ## 每只向外量的半径（逻辑像素），顶到边会被标记

const ENEMY_SCENES = [
	"res://scenes/entities/SlimeEnemy.tscn",
	"res://scenes/entities/XieXiuEnemy.tscn",
	"res://scenes/entities/DanBaoEnemy.tscn",
	"res://scenes/entities/FengQunEnemy.tscn",
	"res://scenes/entities/FlowerEnemy.tscn",
	"res://scenes/entities/XueYongEnemy.tscn",
	"res://scenes/entities/GuYaoEnemy.tscn",
	"res://scenes/entities/YingMeiEnemy.tscn",
	"res://scenes/entities/ZhuMuEnemy.tscn",
	"res://scenes/entities/LeiBeastEnemy.tscn",
	"res://scenes/entities/GolemEnemy.tscn",
	"res://scenes/entities/ChileiEliteEnemy.tscn",
	"res://scenes/entities/JianshaEliteEnemy.tscn",
	"res://scenes/entities/BossEnemy.tscn",
]

var _world: Node2D
var _rows: Array[String] = []

func _ready() -> void:
	Engine.time_scale = 1.0
	# 窗口钉成基准画布尺寸 ⇒ 1 逻辑像素 == 1 屏幕像素，回读不用换算（换算一次错一次）
	var win := get_tree().root
	win.size = Vector2i(960, 540)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_world = Node2D.new()
	add_child(_world)

	var only := _only_filter()
	var tree := get_tree()
	var crowd := _crowd_count()
	if crowd > 0:
		# 密度现场：体型放大后同屏挤不挤，光看数字看不出，落一张图
		await _crowd_shot(crowd)
		return
	if _wanted(only, "player"):
		await _measure_one("PLAYER(修士)", _make_player, "player")
	for path in ENEMY_SCENES:
		var label := (path as String).get_file().get_basename()
		if _wanted(only, label.to_lower()):
			await _measure_one(label, _make_enemy.bind(path), label.to_lower())
	if _wanted(only, "chest"):
		await _measure_one("SpiritChest(藏宝匣)", _make_chest, "chest")

	print("PROBE_ROWS %d" % _rows.size())
	for r in _rows:
		print(r)
	print("ENTITY_SIZE_RESULT: MEASURED")
	tree.quit(0)

func _crowd_count() -> int:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--crowd="):
			return String(a).substr(8).to_int()
	return 0

## 密度现场：随机撒 n 只普通妖（固定种子，位置可复现），只关心「放大之后挤不挤」
func _crowd_shot(n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var mob_count := 10
	for i in range(n):
		var path := String(ENEMY_SCENES[i % mob_count])
		var e := (load(path) as PackedScene).instantiate() as EnemyBase
		e.global_position = ENTITY_POS + Vector2(
			rng.randf_range(-170.0, 170.0), rng.randf_range(-110.0, 110.0))
		_world.add_child(e)
		for l in e.find_children("*", "Light2D", true, false):
			(l as Light2D).enabled = false
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := "/tmp/size_crowd_%d.png" % n
	img.save_png(out)
	print("CROWD_SHOT %s (%d 只普通妖, 种子 20261010)" % [out, n])
	print("ENTITY_SIZE_RESULT: MEASURED")
	get_tree().quit(0)

func _only_filter() -> String:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--only="):
			return String(a).substr(7).to_lower()
	return ""

func _wanted(only: String, key: String) -> bool:
	return only == "" or only == key or key.begins_with(only)

func _make_player() -> Node2D:
	var view := ProceduralCultivatorView.new()
	# 与 Player.gd:104-107 同一处取值：程序化视图挂在 anim_sprite 位置上，整体 ×1.2
	view.scale = Vector2(1.2, 1.2)
	view.setup_character_id(GameManager.cultivator_id)
	return view

func _make_enemy(path: String) -> Node2D:
	var packed := load(path) as PackedScene
	return packed.instantiate() as Node2D

func _make_chest() -> Node2D:
	return SpiritChest.new()

## 单只实体上场：摆到画布中心，等稳定，整幅回读，量完撤下
func _measure_one(label: String, factory: Callable, file_key: String) -> void:
	var node := factory.call() as Node2D
	_world.add_child(node)
	node.global_position = ENTITY_POS
	# PointLight2D 会把暗底整片照亮，剪影阈值就废了；量的是画出来的形体，不是灯
	for l in node.find_children("*", "Light2D", true, false):
		(l as Light2D).enabled = false
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var vp := get_viewport()
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		_rows.append("%s | !! 像素回读失败（不要用 --headless）" % label)
		node.queue_free()
		await get_tree().process_frame
		return
	var scale := float(img.get_width()) / 960.0
	var sil := _bbox(img, scale, SIL_EPS)
	var bright := _bbox(img, scale, BRIGHT_EPS)
	var body_r := _node_radius(node, "CollisionShape2D")
	var hurt_r := _node_radius(node, "Hurtbox/CollisionShape2D")
	if hurt_r <= 0.0:
		hurt_r = _first_area_radius(node)
	var view_scale := 0.0
	var cfg_scale := 0.0
	var view := node.get_node_or_null("AnimatedSprite2D")
	if view is CanvasItem:
		view_scale = (view as CanvasItem).scale.x
	var pe := node as EnemyBase
	if pe != null and pe.procedural_view != null and pe.procedural_view.config != null:
		view_scale = pe.procedural_view.scale.x
		cfg_scale = pe.procedural_view.config.scale_factor
	# 运行时缩放链：画出来的尺寸到底是被哪一层吃掉的
	var kids := ""
	for ch in node.get_children():
		var ci := ch as CanvasItem
		if ci != null and not ci.visible:
			kids += "%s:hidden " % String(ch.name)
		elif ci != null:
			kids += "%s:%.2f " % [String(ch.name), ci.global_transform.get_scale().x]
	if OS.get_cmdline_user_args().has("--shot"):
		var crop := _crop(img, sil, scale)
		if crop != null:
			crop.save_png("/tmp/size_%s.png" % file_key)
	_rows.append("%s | 画出 %.0fx%.0f (亮部 %.0fx%.0f, 面积 %.0f) | body %.0f hurt %.0f | 缩放链 %.2f x %.2f%s%s [子件 %s][dbg scale=%.3f 偏差=%d,%d 框=%d,%d..%d,%d 窗=%d,%d..%d,%d]" % [
		label, sil["w"], sil["h"], bright["w"], bright["h"], sil["count"],
		body_r * 2.0, hurt_r * 2.0, view_scale, cfg_scale,
		" [顶到搜索窗]" if bool(sil["clipped"]) else "",
		" | /tmp/size_%s.png" % file_key if OS.get_cmdline_user_args().has("--shot") else "",
		kids,
		scale,
		int(roundf((float(sil["sx0"]) + float(sil["sx1"])) * 0.5 - ENTITY_POS.x * scale)),
		int(roundf((float(sil["sy0"]) + float(sil["sy1"])) * 0.5 - ENTITY_POS.y * scale)),
		int(sil["sx0"]), int(sil["sy0"]), int(sil["sx1"]), int(sil["sy1"]),
		int(sil["wx0"]), int(sil["wy0"]), int(sil["wx1"]), int(sil["wy1"]),
	])
	node.queue_free()
	await get_tree().process_frame

func _content_scale() -> float:
	var win := get_tree().root
	var s: float = win.get_content_scale_factor()
	return s if s > 0.01 else 1.0

func _crop(img: Image, bbox: Dictionary, scale: float) -> Image:
	if int(bbox["count"]) == 0:
		return null
	var pad := 8.0
	var x0 := int(maxf(0.0, (float(bbox["x0"]) - pad) * scale))
	var y0 := int(maxf(0.0, (float(bbox["y0"]) - pad) * scale))
	var x1 := mini(img.get_width() - 1, int(ceilf((float(bbox["x1"]) + pad) * scale)))
	var y1 := mini(img.get_height() - 1, int(ceilf((float(bbox["y1"]) + pad) * scale)))
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))

## 画布中心 ±SCAN_HALF 逻辑像素内，「不是背景」的像素外接框，换算回逻辑像素
func _bbox(img: Image, scale: float, eps: float) -> Dictionary:
	var half_px := int(SCAN_HALF * scale)
	var cx := int(roundf(ENTITY_POS.x * scale))
	var cy := int(roundf(ENTITY_POS.y * scale))
	var x0 := maxi(0, cx - half_px)
	var x1 := mini(img.get_width() - 1, cx + half_px)
	var y0 := maxi(0, cy - half_px)
	var y1 := mini(img.get_height() - 1, cy + half_px)
	var min_x := x1 + 1
	var max_x := x0 - 1
	var min_y := y1 + 1
	var max_y := y0 - 1
	var count := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := img.get_pixel(x, y)
			var d := maxf(absf(c.r - BG.r), maxf(absf(c.g - BG.g), absf(c.b - BG.b)))
			if d > eps:
				count += 1
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
	if count == 0:
		return {"w": 0.0, "h": 0.0, "count": 0.0, "x0": 0.0, "y0": 0.0, "x1": 0.0, "y1": 0.0,
			"sx0": 0, "sy0": 0, "sx1": 0, "sy1": 0, "wx0": x0, "wy0": y0, "wx1": x1, "wy1": y1,
			"clipped": false}
	var clipped := min_x <= x0 or max_x >= x1 or min_y <= y0 or max_y >= y1
	return {
		"w": float(max_x - min_x + 1) / scale,
		"h": float(max_y - min_y + 1) / scale,
		"count": float(count) / (scale * scale),
		"x0": float(min_x) / scale,
		"y0": float(min_y) / scale,
		"x1": float(max_x) / scale,
		"y1": float(max_y) / scale,
		"sx0": min_x, "sy0": min_y, "sx1": max_x, "sy1": max_y,
		"wx0": x0, "wy0": y0, "wx1": x1, "wy1": y1,
		"clipped": clipped,
	}

func _node_radius(node: Node, path: String) -> float:
	return _shape_radius(node.get_node_or_null(path) as CollisionShape2D)

## 代码建的判定盒（SpiritChest）没有固定节点名，按子节点类型找第一个 Area2D 里的圆
func _first_area_radius(node: Node) -> float:
	for ch in node.get_children():
		var area := ch as Area2D
		if area == null:
			continue
		for sub in area.get_children():
			var r := _shape_radius(sub as CollisionShape2D)
			if r > 0.0:
				return r
	return 0.0

func _shape_radius(cs: CollisionShape2D) -> float:
	if cs == null or cs.shape == null:
		return 0.0
	var circle := cs.shape as CircleShape2D
	if circle != null:
		return circle.radius
	var rect := cs.shape as RectangleShape2D
	if rect != null:
		var ext: Vector2 = rect.extents
		return maxf(ext.x, ext.y)
	return 0.0
