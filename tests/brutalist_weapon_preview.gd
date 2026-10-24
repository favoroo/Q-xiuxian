extends Control

## 新野兽派武器重绘【样稿对比预览】（非判据，必须开窗跑）
##   $G --path . res://tests/BrutalistWeaponPreview.tscn -- --export
##
## 同器形 · 同五行 · 同 tip_len 对照：
##   左半 = 现行冷冽矢量画法（ProceduralWeaponRenderer 原样实例化，含辉光/渐变/星点）；
##   右半 = 新野兽派样稿（平涂色块 + 粗墨描边 + 硬偏移投影，零辉光零渐变零装饰纹）。
## 每把画两遍：实战尺寸（scale 0.55，与 FloatingWeapon 一致）+ 放大（2.0）。
## 导出 tests/styles/brutalist_weapon_preview.png 后退出。

const OUT_PATH := "tests/styles/brutalist_weapon_preview.png"
const TIP_LEN := 26.0
const STAR := 2

const SAMPLES := [
	{"name": "长剑", "shape": "sword", "element": "metal", "upright": false},
	{"name": "狂刀", "shape": "saber", "element": "fire", "upright": false},
	{"name": "灵符", "shape": "talisman", "element": "wood", "upright": true},
	{"name": "折扇", "shape": "fan", "element": "water", "upright": false},
	{"name": "重锤", "shape": "hammer", "element": "earth", "upright": true},
	{"name": "战鼓", "shape": "drum", "element": "fire", "upright": true},
]

const BIG_SCALE := 1.9
const CELL_W := 145.0
const CELL_X0 := 90.0
const ROW_CUR := 130.0
const ROW_NEW := 345.0


func _ready() -> void:
	custom_minimum_size = Vector2(960, 540)
	size = Vector2(960, 540)
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	_export_image()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "武器重绘样稿 · 现行冷冽矢量（上）vs 新野兽派（下）"
	title.position = Vector2(16, 10)
	GameStyle.label(title, 16, Color(0.93, 0.94, 0.98))
	add_child(title)

	var note := Label.new()
	note.text = "新野兽派要点：平涂色块 · 粗墨描边 · 硬投影 · 去掉辉光/渐变/星点/装饰纹（每格：大=放大看形，小=实战尺寸）"
	note.position = Vector2(16, 36)
	GameStyle.label(note, 10, GameStyle.GREY)
	add_child(note)

	_add_row_header("现行画法", ROW_CUR)
	_add_row_header("新野兽派", ROW_NEW)

	# 新旧分界横线
	var div := ColorRect.new()
	div.color = Color(0.25, 0.35, 0.50, 0.6)
	div.position = Vector2(12, 238)
	div.size = Vector2(936, 1)
	add_child(div)

	for i in range(SAMPLES.size()):
		var s: Dictionary = SAMPLES[i]
		var x0 := CELL_X0 + float(i) * CELL_W
		for row in [ROW_CUR, ROW_NEW]:
			var name_lbl := Label.new()
			name_lbl.text = String(s["name"])
			name_lbl.position = Vector2(x0 + CELL_W * 0.5 - 14.0, row - 78.0)
			GameStyle.label(name_lbl, 11, GameStyle.GOLD)
			add_child(name_lbl)
		_mount_current(s, Vector2(x0 + 88.0, ROW_CUR), BIG_SCALE)
		_mount_current(s, Vector2(x0 + 26.0, ROW_CUR + 52.0), 0.55)
		_mount_brutalist(s, Vector2(x0 + 88.0, ROW_NEW), BIG_SCALE)
		_mount_brutalist(s, Vector2(x0 + 26.0, ROW_NEW + 52.0), 0.55)


func _add_row_header(text: String, cy: float) -> void:
	var l := Label.new()
	l.text = text
	l.position = Vector2(12, cy - 8)
	GameStyle.label(l, 13, Color(0.93, 0.94, 0.98))
	add_child(l)


func _mount_current(s: Dictionary, pos: Vector2, sc: float) -> void:
	var wr := ProceduralWeaponRenderer.new()
	wr.configure(
		ProceduralWeaponRenderer.shape_from_name(String(s["shape"])),
		String(s["element"]), TIP_LEN, STAR, bool(s["upright"]))
	wr.position = pos
	wr.scale = Vector2.ONE * sc
	add_child(wr)


func _mount_brutalist(s: Dictionary, pos: Vector2, sc: float) -> void:
	var bw := BrutalistWeapon.new()
	bw.shape = String(s["shape"])
	bw.element = String(s["element"])
	bw.upright = bool(s["upright"])
	bw.tip_len = TIP_LEN
	bw.position = pos
	bw.scale = Vector2.ONE * sc
	add_child(bw)


func _export_image() -> void:
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("tests/styles")
		var img := get_viewport().get_texture().get_image()
		if img != null and not img.is_empty():
			img.save_png(OUT_PATH)
			print("[BrutalistWeaponPreview] 导出 %s" % OUT_PATH)
	print("BRUTALIST_WEAPON_PREVIEW_DONE")
	get_tree().quit(0)


## ============ 新野兽派样稿画法（仅样稿，不入生产） ============
## 与现行画法同一坐标契约：画布像素空间沿 +X 画，器尖落 (tip_len, 0)，upright 转 -90°。
## 三件套：硬偏移投影（纯黑 40%，右下 2px）→ 粗墨描边（贴形外线）→ 平涂色块。
## 配色纪律：每把 = 五行主色一块 + 撞色块一处 + 墨黑；无第二种渐变、无辉光、无装饰纹。
class BrutalistWeapon:
	extends Node2D

	const INK := Color(0.07, 0.08, 0.11)
	const PAPER := Color(0.93, 0.91, 0.85)
	const CINNABAR := Color(0.72, 0.14, 0.10)
	const SHADOW := Color(0.0, 0.0, 0.0, 0.40)

	const PAL := {
		"metal": {"body": Color(0.90, 0.91, 0.94), "accent": Color(1.00, 0.78, 0.18)},
		"wood": {"body": Color(0.42, 0.74, 0.36), "accent": Color(0.80, 0.93, 0.30)},
		"water": {"body": Color(0.26, 0.58, 0.94), "accent": Color(0.50, 0.93, 1.00)},
		"fire": {"body": Color(0.90, 0.28, 0.14), "accent": Color(1.00, 0.72, 0.12)},
		"earth": {"body": Color(0.70, 0.55, 0.34), "accent": Color(0.98, 0.60, 0.16)},
	}

	var shape: String = "sword"
	var element: String = "metal"
	var tip_len: float = 26.0
	var upright: bool = false

	func _draw() -> void:
		if upright:
			draw_set_transform(Vector2.ZERO, -PI * 0.5, Vector2.ONE)
		match shape:
			"sword":
				_sword()
			"saber":
				_saber()
			"talisman":
				_talisman()
			"fan":
				_fan()
			"hammer":
				_hammer()
			"drum":
				_drum()

	func _pal() -> Dictionary:
		return PAL.get(element, PAL["metal"])

	## 平涂块：硬投影 + 粗墨描边 + 纯色填充
	func _flat(pts: PackedVector2Array, fill: Color, ow: float = 2.2) -> void:
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(2.0, 2.0))
		draw_colored_polygon(sh, SHADOW)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, INK, ow + 2.4, true)
		draw_colored_polygon(pts, fill)

	## 粗杆（柄/骨）：投影 + 墨描 + 纯色芯
	func _bar(a: Vector2, b: Vector2, w: float, col: Color) -> void:
		draw_line(a + Vector2(2.0, 2.0), b + Vector2(2.0, 2.0), SHADOW, w + 2.4, true)
		draw_line(a, b, INK, w + 2.4, true)
		draw_line(a, b, col, w, true)

	## 方钉/方首
	func _square(c: Vector2, half: float, col: Color, ow: float = 1.4) -> void:
		_flat(PackedVector2Array([
			c + Vector2(-half, -half), c + Vector2(half, -half),
			c + Vector2(half, half), c + Vector2(-half, half),
		]), col, ow)

	# ---------------- 直剑：平行刃 + 斜切硬尖 + 一字格 ----------------
	func _sword() -> void:
		var pal := _pal()
		var L := tip_len
		var w := 4.6
		_flat(PackedVector2Array([
			Vector2(L, 0.0), Vector2(L - 5.0, -w), Vector2(0.0, -w),
			Vector2(0.0, w), Vector2(L - 5.0, w),
		]), pal["body"])
		# 尖部撞色块（唯一的装饰）
		_flat(PackedVector2Array([
			Vector2(L, 0.0), Vector2(L - 5.0, -w), Vector2(L - 5.0, w),
		]), pal["accent"], 1.4)
		# 一字剑格
		_flat(PackedVector2Array([
			Vector2(-0.5, -8.0), Vector2(1.5, -8.0), Vector2(1.5, 8.0), Vector2(-0.5, 8.0),
		]), pal["accent"], 1.6)
		# 柄 + 方首
		_bar(Vector2(-1.0, 0.0), Vector2(-10.0, 0.0), 3.0, INK)
		_square(Vector2(-11.5, 0.0), 2.2, pal["body"])

	# ---------------- 弯刀：直背 + 鼓腹硬折线 + 背脊撞色条 ----------------
	func _saber() -> void:
		var pal := _pal()
		var L := tip_len
		_flat(PackedVector2Array([
			Vector2(0.0, -4.6), Vector2(L - 4.0, -4.6), Vector2(L, -1.0),
			Vector2(L - 3.0, 3.4), Vector2(L * 0.55, 6.2), Vector2(1.5, 4.8),
		]), pal["body"])
		_flat(PackedVector2Array([
			Vector2(0.6, -4.6), Vector2(L - 5.0, -4.6), Vector2(L - 5.8, -2.4), Vector2(1.2, -2.2),
		]), pal["accent"], 1.2)
		_flat(PackedVector2Array([
			Vector2(-0.5, -7.0), Vector2(1.5, -7.0), Vector2(1.5, 7.0), Vector2(-0.5, 7.0),
		]), pal["accent"], 1.6)
		_bar(Vector2(-1.0, 0.0), Vector2(-10.0, 0.0), 3.0, INK)
		_square(Vector2(-11.5, 0.0), 2.2, pal["body"])

	# ---------------- 灵符：纸白符身 + 符头色带 + 朱砂大印 + 一笔粗墨 ----------------
	func _talisman() -> void:
		var pal := _pal()
		var L := tip_len
		var hw := 7.5
		_flat(PackedVector2Array([
			Vector2(L * 0.82, -hw), Vector2(-L * 0.82, -hw),
			Vector2(-L * 0.82, hw), Vector2(L * 0.82, hw),
		]), PAPER, 2.4)
		_flat(PackedVector2Array([
			Vector2(L * 0.82, -hw), Vector2(L * 0.55, -hw),
			Vector2(L * 0.55, hw), Vector2(L * 0.82, hw),
		]), pal["accent"], 1.2)
		_square(Vector2(-L * 0.42, 0.0), 3.4, CINNABAR)
		# 一笔符：一横一竖一挑，粗墨
		draw_line(Vector2(L * 0.30, -hw * 0.55), Vector2(-L * 0.06, -hw * 0.55), INK, 1.8, true)
		draw_line(Vector2(L * 0.30, -hw * 0.55), Vector2(L * 0.30, hw * 0.25), INK, 1.8, true)
		draw_line(Vector2(L * 0.30, hw * 0.25), Vector2(-L * 0.10, hw * 0.60), INK, 1.8, true)

	# ---------------- 折扇：低分段硬边扇面 + 撞色环带 + 三根粗骨 ----------------
	func _fan() -> void:
		var pal := _pal()
		var R: float = maxf(tip_len, 22.0) * 1.02
		var half := deg_to_rad(52.0)
		const SEG := 10
		var pts := PackedVector2Array([Vector2.ZERO])
		for i in range(SEG + 1):
			var a := -half + 2.0 * half * float(i) / float(SEG)
			pts.append(Vector2(cos(a), sin(a)) * R)
		_flat(pts, pal["body"], 2.4)
		# 外缘撞色环带
		var band := PackedVector2Array()
		for i in range(SEG + 1):
			var a := -half + 2.0 * half * float(i) / float(SEG)
			band.append(Vector2(cos(a), sin(a)) * R)
		for i in range(SEG, -1, -1):
			var a := -half + 2.0 * half * float(i) / float(SEG)
			band.append(Vector2(cos(a), sin(a)) * R * 0.80)
		_flat(band, pal["accent"], 1.2)
		# 三根粗扇骨
		for i in range(3):
			var a := -half + 2.0 * half * float(i) / 2.0
			draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * R * 0.78, INK, 2.2, true)
		_bar(Vector2.ZERO, Vector2(-R * 0.35, 0.0), 3.2, INK)
		_square(Vector2.ZERO, 2.4, pal["accent"])

	# ---------------- 重锤：粗柄 + 方头 + 撞面撞色 ----------------
	func _hammer() -> void:
		var pal := _pal()
		var L := tip_len
		_bar(Vector2(-L * 0.78, 0.0), Vector2(L * 0.45, 0.0), 4.0, PAPER.darkened(0.25))
		_flat(PackedVector2Array([
			Vector2(L * 0.40, -8.5), Vector2(L, -8.5), Vector2(L, 8.5), Vector2(L * 0.40, 8.5),
		]), pal["body"], 2.4)
		_flat(PackedVector2Array([
			Vector2(L * 0.76, -8.5), Vector2(L, -8.5), Vector2(L, 8.5), Vector2(L * 0.76, 8.5),
		]), pal["accent"], 1.2)
		_square(Vector2(-L * 0.82, 0.0), 2.4, pal["accent"])

	# ---------------- 战鼓：平涂鼓面 + 撞色环 + 方鼓心 ----------------
	func _drum() -> void:
		var pal := _pal()
		var r := tip_len * 0.80
		draw_circle(Vector2(2.0, 2.0), r, SHADOW)
		draw_circle(Vector2.ZERO, r, INK)
		draw_circle(Vector2.ZERO, r - 2.4, pal["body"])
		draw_arc(Vector2.ZERO, r * 0.62, 0.0, TAU, 24, pal["accent"], 3.6, true)
		_square(Vector2.ZERO, 2.6, INK, 1.0)
