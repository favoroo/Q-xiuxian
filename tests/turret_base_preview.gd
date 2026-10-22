extends Node2D

## 机关炮台底座视觉预览（非判据，必须开窗跑）：
##   $G --path . res://tests/TurretBasePreview.tscn
## 产物 /tmp/turret_base_preview.png
## 上区 4x 放大看底座圆度；下区实机尺度（×1.0，玩家实际所见）。

const TURRETS := [
	"jiguan_nu", "ningbing_nu", "jianzhen_pan", "qingmu_pao", "penhuo_jiguanshou",
	"hanquan_shou", "kuilei_shou", "leishi_jiguan", "tengluo_jiguan", "fenghuo_tai",
]

var _out_path := "/tmp/turret_base_preview.png"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]

	DisplayServer.window_set_size(Vector2i(1280, 760))
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.16)  # 近石砖地面中灰，便于看阴影与阵盘边缘
	bg.size = Vector2(1280, 760)
	add_child(bg)

	_label(Vector2(20, 16), "机关炮台底座 · 4x 放大（真圆阵盘 + 正圆机座）")
	var stage := Node2D.new()
	stage.scale = Vector2.ONE * 4.0
	add_child(stage)
	for i in range(TURRETS.size()):
		var t: TurretUnit = load("res://scenes/weapons/TurretUnit.tscn").instantiate()
		t.setup(TURRETS[i], 1)
		var cx := 30.0 + (i % 5) * 50.0
		var cy := 25.0 + floori(float(i) / 5.0) * 55.0
		stage.add_child(t)
		t.global_position = Vector2(cx * 4.0, cy * 4.0)  # 放到 stage 缩放前的画布坐标
		_label(Vector2(cx * 4.0 - 55.0, cy * 4.0 + 80.0), "%s" % WeaponData.get_def(TURRETS[i]).get("name", "?"))

	_label(Vector2(20, 360), "实机尺度 · ×1.0（玩家实际所见大小）")
	var row := Node2D.new()
	add_child(row)
	for i in range(TURRETS.size()):
		var t2: TurretUnit = load("res://scenes/weapons/TurretUnit.tscn").instantiate()
		t2.setup(TURRETS[i], 1)
		row.add_child(t2)
		t2.global_position = Vector2(55.0 + i * 95.0, 460.0)
		_label(Vector2(55.0 + i * 95.0 - 48.0, 510.0), "%s" % WeaponData.get_def(TURRETS[i]).get("name", "?"))

	# 等入场 tween 收尾（0.22s）再截图，否则底座还在 0.2~1.0 缩放中
	await get_tree().create_timer(0.6).timeout
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out_path)
		print("SAVED %s " % _out_path, img.get_size())
	get_tree().quit(0)

func _label(pos: Vector2, text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 13)
	lab.add_theme_color_override("font_color", GameStyle.CHALK)
	lab.position = pos
	add_child(lab)
