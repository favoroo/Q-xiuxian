extends Node2D

## 法器矢量本体预览台（非判据，必须开窗跑）：
##   $G --path . res://tests/WeaponProcPreview.tscn
## 产物 /tmp/weapon_proc_preview.png
## 左区：批次 1 的 10 把剑/刀，0° 朝向 4x 放大 + 橙色 tip 标定线（应精确落在器尖）
## 右区：同一把剑 ★1/★2/★3 的结构强化对比
## 底栏：集成契约校验（FloatingWeapon 是否挂上矢量本体、贴图是否让位、出膛点是否对齐）

const BATCH1 := [
	"qingyun_sword", "gengjin_feijian", "liuye_feidao", "chiyan_dao", "xueyin_dao",
	"qingteng_jian", "hanshuang_jian", "taomu_jian", "bengshan_jian", "liuhuo_feijian",
]
const CELL := 150.0
const ZOOM := 4.0

func _ready() -> void:
	var cols := 5
	var rows := 2
	DisplayServer.window_set_size(Vector2i(960, 660))
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.13)
	bg.size = Vector2(960, 660)
	add_child(bg)

	for i in range(BATCH1.size()):
		var c := i % cols
		var r := floori(float(i) / float(cols))
		var center := Vector2(90 + c * CELL, 100 + r * CELL)
		_place(center, BATCH1[i], 1, 0.0)
		_label(Vector2(center.x - 70, center.y - 66), "%s" % WeaponData.get_def(BATCH1[i]).get("name", "?"))

	# 星级对比
	var sx := 830.0
	for s in range(3):
		var center := Vector2(sx, 100 + s * 150.0)
		_place(center, "qingyun_sword", s + 1, 0.0)
		_label(Vector2(sx - 40, center.y - 62), "★%d" % (s + 1))
	_label(Vector2(770, 20), "升星结构强化 →")

	# 旧贴图 vs 新矢量（并排，同 4x 尺度）
	_label(Vector2(20, 400), "旧 AI 贴图（4x）  vs  新矢量本体（4x）")
	var cmp := ["qingyun_sword", "chiyan_dao", "liuye_feidao"]
	for i in range(cmp.size()):
		var y := 430.0 + i * 62.0
		var tex := load(String(WeaponData.get_def(cmp[i]).get("icon", ""))) as Texture2D
		if tex != null:
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp.scale = Vector2.ONE * (ZOOM * 0.55)
			sp.position = Vector2(70, y + 20)
			add_child(sp)
		var r2 := ProceduralWeaponRenderer.new()
		var d := WeaponData.get_def(cmp[i])
		r2.configure(ProceduralWeaponRenderer.shape_from_name(String(d.get("shape", ""))),
			WeaponData.element_of(cmp[i]), (d.get("tip", Vector2.ZERO) as Vector2).length(), 1)
		r2.scale = Vector2.ONE * (ZOOM * 0.55)
		r2.position = Vector2(210, y + 20)
		add_child(r2)
		_label(Vector2(300, y + 14), "%s" % d.get("name", "?"))

	_label(Vector2(20, 20), "批次1 · 法器矢量本体（4x，橙线=tip 器尖标定）")
	_integration_check()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/weapon_proc_preview.png")
		print("SAVED /tmp/weapon_proc_preview.png ", img.get_size())
	get_tree().quit(0)

func _place(center: Vector2, id: String, star: int, angle: float) -> void:
	var def := WeaponData.get_def(id)
	var shape := ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
	var tip: Vector2 = def.get("tip", Vector2(22, 0))
	var r := ProceduralWeaponRenderer.new()
	r.configure(shape, WeaponData.element_of(id), tip.length(), star)
	r.scale = Vector2.ONE * (ZOOM * 0.55)
	r.position = center
	r.rotation = angle
	add_child(r)
	# tip 标定线：从中心到器尖（本地 +X * tip_len，经节点变换）
	var tip_world: Vector2 = center + Vector2(tip.length(), 0).rotated(angle) * (ZOOM * 0.55)
	var ln := Line2D.new()
	ln.add_point(center)
	ln.add_point(tip_world)
	ln.default_color = Color(1.0, 0.55, 0.1, 0.85)
	ln.width = 1.0
	add_child(ln)
	var dot := Line2D.new()
	dot.add_point(tip_world + Vector2(-3, 0))
	dot.add_point(tip_world + Vector2(3, 0))
	dot.add_point(tip_world + Vector2(0, -3))
	dot.add_point(tip_world + Vector2(0, 3))
	dot.add_point(tip_world + Vector2(-3, 0))
	dot.default_color = Color(1.0, 0.8, 0.2)
	dot.width = 1.0
	add_child(dot)

func _label(pos: Vector2, text: String) -> void:
	var lab := Label.new()
	lab.text = text
	GameStyle.label(lab, 11, GameStyle.PAPER)
	lab.position = pos
	add_child(lab)

## 集成契约：FloatingWeapon 对批次 1 必须挂上矢量本体并隐蔽贴图，器尖==出膛点
func _integration_check() -> void:
	var y := 600.0
	var ok := 0
	var total := 0
	for id in BATCH1:
		total += 1
		var w: FloatingWeapon = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
		w.setup(id, 1)
		add_child(w)
		var has_renderer: bool = w._proc_renderer != null
		var sprite_hidden: bool = is_equal_approx(w.sprite.self_modulate.a, 0.0)
		var tip_len: float = (WeaponData.get_def(id).get("tip", Vector2.ZERO) as Vector2).length()
		var expect_muzzle: float = tip_len * w.sprite.scale.x
		var muzzle_ok: bool = absf(w.muzzle_point.position.x - expect_muzzle) < 0.01
		if has_renderer and sprite_hidden and muzzle_ok:
			ok += 1
		else:
			_label(Vector2(20, y + 18), "契约不符: %s renderer=%s hidden=%s muzzle=%s" % [id, has_renderer, sprite_hidden, muzzle_ok])
		w.queue_free()
	var msg := "集成契约: %d/%d 通过（挂载矢量本体 + 贴图让位 + 出膛点=tip×0.55）" % [ok, total]
	_label(Vector2(20, y), msg)
	print(msg)
	# 未登记 shape 的武器应保持贴图（灰度不破现状）
	var w2: FloatingWeapon = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	w2.setup("wulei_paizi", 1)
	add_child(w2)
	var fallback_ok: bool = w2._proc_renderer == null and not is_equal_approx(w2.sprite.self_modulate.a, 0.0)
	print("灰度回退（雷牌应保留贴图）: ", fallback_ok)
	_label(Vector2(20, y + 22), "灰度回退（雷牌保留贴图）: %s" % ("OK" if fallback_ok else "FAIL"))
	w2.queue_free()
