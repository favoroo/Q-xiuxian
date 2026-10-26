extends Node2D

## 万剑归宗幻影出图台（非判据，必须开窗跑 —— 无头截不到真实画面）：
##   $G --path . res://tests/SwordPhantomPreview.tscn
## 产物 /tmp/sword_phantom_preview.png
##
## 三区：
##   上区  六把剑系武器的「真身 vs 幻影」并排 —— 验收「显示效果有一点点区别」：
##         器形/器尖/星级完全一致，只换元素 HDR 色 + 加色混合 + 半透明。
##   中区  凝形 → 疾射 → 消散的关键帧定格（真实 SwordPhantom 实例推进到该状态后停格），
##         验收出场/消失动画读不读得出来。
##   底区  一次开阵的真实俯视：6 把真剑（内环）+ 6 道幻影（外环同角）= 12 把同场，
##         验收「万剑归宗」的视觉密度。

const SWORDS := [
	"qingyun_sword", "chiyan_dao", "gengjin_feijian",
	"liuye_feidao", "qingteng_jian", "bengshan_jian",
]
## 上区放大倍率（真身/幻影对比要看细节）
const ZOOM := 2.6
## 中区幻影放大倍率（实机 0.55 太小，看不清凝形环）
const STATE_ZOOM := 3.2

var _out_path := "/tmp/sword_phantom_preview.png"

func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(Vector2i(1100, 940))
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.size = Vector2(1100, 940)
	add_child(bg)

	_compare_row()
	_state_row()
	_volley_row()
	_label(Vector2(24, 18), "① 真身 vs 幻影：器形/器尖/星级一致，只换元素色温 + 加色混合 + 半透明")
	_label(Vector2(24, 330), "② 出场与消失：凝形（灵环推开）→ 全尺寸 → 疾射（拖尾）→ 消散")
	_label(Vector2(24, 590), "③ 一次开阵：6 把真剑（内环）+ 6 道幻影（外环同角）= 12 把同场")

	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out_path)
		print("SAVED %s " % _out_path, img.get_size())
	get_tree().quit(0)

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]
			i += 1
		i += 1

## ① 每把剑左真身右幻影，同缩放同角度
func _compare_row() -> void:
	for i in range(SWORDS.size()):
		var wid: String = SWORDS[i]
		var def := WeaponData.get_def(wid)
		if def.is_empty():
			continue
		var element := WeaponData.element_of(wid)
		var base := Vector2(120 + (i % 3) * 350, 100 + floori(float(i) / 3.0) * 115.0)

		_renderer(base, wid, element, 1.0, deg_to_rad(-18.0), ZOOM)
		_label(base + Vector2(-46, 40), "真身 · %s" % def.get("name", "?"))
		_renderer(base + Vector2(130, 0), wid, element, SwordPhantom.GHOST_ALPHA,
			deg_to_rad(-18.0), ZOOM, true)
		_label(base + Vector2(96, 40), "幻影")

## ② 三段关键帧（真实实体推进后停格）
func _state_row() -> void:
	var scene: PackedScene = load("res://scenes/weapons/SwordPhantom.tscn")
	var slots := [
		{"label": "凝形中（灵环推开）", "t": 0.045},
		{"label": "凝形成型", "t": SwordPhantom.FORM_TIME},
		{"label": "疾射（拖尾）", "t": SwordPhantom.FORM_TIME, "dash": true},
		{"label": "消散（化光）", "t": SwordPhantom.FORM_TIME, "dash": true, "fade": 0.09},
	]
	for i in range(slots.size()):
		var spec: Dictionary = slots[i]
		var wrap := Node2D.new()
		wrap.position = Vector2(135 + i * 245, 455)
		wrap.scale = Vector2.ONE * STATE_ZOOM
		add_child(wrap)

		var ph := scene.instantiate() as SwordPhantom
		wrap.add_child(ph)
		ph.weapon_def_id = "qingyun_sword"
		ph.star = 1
		ph.element = "metal"
		ph.direction = Vector2.RIGHT
		ph.damage = 10.0
		ph.activate()
		# 推进到目标状态后停格（关掉物理推进，画面定在这一帧）
		var t: float = float(spec.get("t", 0.0))
		ph._t = t
		if t >= SwordPhantom.FORM_TIME:
			ph._state = SwordPhantom.STATE_READY
			ph.scale = Vector2.ONE
			ph.modulate.a = SwordPhantom.GHOST_ALPHA
			if bool(spec.get("dash", false)):
				ph._state = SwordPhantom.STATE_DASH
			if bool(spec.get("fade", false)):
				var k: float = float(spec.get("fade", 0.0)) / SwordPhantom.FADE_TIME
				ph._state = SwordPhantom.STATE_FADE
				ph.modulate.a = SwordPhantom.GHOST_ALPHA * (1.0 - k)
				ph.scale = Vector2.ONE * lerpf(1.0, 1.25, k)
		else:
			# 凝形中：按 _tick_form 的同一组闭式解手算这一帧（activate 后 alpha 起点是 0）
			var k: float = clampf(t / SwordPhantom.FORM_TIME, 0.0, 1.0)
			var grow: float = lerpf(SwordPhantom.FORM_SCALE_IN, 1.06, k) if k < 0.82 \
				else lerpf(1.06, 1.0, (k - 0.82) / 0.18)
			ph.scale = Vector2.ONE * grow
			ph.modulate.a = SwordPhantom.GHOST_ALPHA * clampf(k / 0.45, 0.0, 1.0)
		ph.set_physics_process(false)
		ph.queue_redraw()
		_label(Vector2(78 + i * 245, 490), String(spec.get("label", "")))

## ③ 6 真剑内环 + 6 幻影外环同角（压扁的椭圆环，整体收在 940 高度内）
func _volley_row() -> void:
	var center := Vector2(550, 730)
	for i in range(SWORDS.size()):
		var wid: String = SWORDS[i]
		var def := WeaponData.get_def(wid)
		if def.is_empty():
			continue
		var element := WeaponData.element_of(wid)
		var ang := TAU * float(i) / float(SWORDS.size()) - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang) * 0.52)
		_renderer(center + dir * 88.0, wid, element, 1.0, ang, 1.8)
		_renderer(center + dir * 172.0, wid, element, SwordPhantom.GHOST_ALPHA, ang, 1.8, true)

## 画一把器形（ghost=true 时走幻影口径：元素 HDR + 加色混合 + 半透明）
func _renderer(pos: Vector2, wid: String, element: String, alpha: float,
		angle: float, zoom: float, ghost: bool = false) -> void:
	var def := WeaponData.get_def(wid)
	var shape := ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
	var upright := bool(def.get("upright", false))
	var tip: Vector2 = def.get("tip", Vector2(22, 0))
	var r := ProceduralWeaponRenderer.new()
	r.configure(shape, element, tip.length(), 1, upright, wid)
	r.scale = Vector2.ONE * (zoom * 0.55)
	r.position = pos
	r.rotation = angle
	if ghost:
		r.material = SharedMaterials.add_blend()
		var tint := GameStyle.fx_hdr_element(element)
		tint.a = alpha
		r.modulate = tint
	add_child(r)

func _label(pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 0.86, 0.90))
	add_child(l)
