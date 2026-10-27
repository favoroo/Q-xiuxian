extends Node2D

## 万剑归宗幻影剑阵出图台（非判据，必须开窗跑 —— 无头截不到真实画面）：
##   $G --path . res://tests/SwordPhantomPreview.tscn
## 产物 /tmp/sword_phantom_preview.png
##
## 本轮改动的验收点（用户口径「都没感受出来有幻象出来，改成幻象能持续一段时间」）：
##   上区  六把剑系武器的「真身 vs 幻影」并排 —— 器形/器尖/星级一致，只换元素色温 + 加色混合 + 半透明
##   中区  幻影出刀的四段关键帧（真实 SwordPhantom 实例推进到该状态后停格）：
##         凝形（灵环推开）→ 驻场 → 挥出（弧光扫放）→ 消散
##   底区  一次开阵的俯视：6 把真剑（内环 54×40）+ 6 道幻影（外环 88×68）= 12 把同场，
##         验收「幻影待得住、数得清，内外双环距离适中」

const SWORDS := [
	"qingyun_sword", "chiyan_dao", "gengjin_feijian",
	"liuye_feidao", "qingteng_jian", "bengshan_jian",
]
## 上区放大倍率（真身/幻影对比要看细节）
const ZOOM := 2.6
## 中区幻影放大倍率（实机 0.55 太小，看不清凝形环与弧光）
const STATE_ZOOM := 2.2

var _out_path := "/tmp/sword_phantom_preview.png"

func _ready() -> void:
	_parse_args()
	get_window().content_scale_size = Vector2i(1240, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DisplayServer.window_set_size(Vector2i(1240, 1080))
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.09)
	bg.size = Vector2(1240, 1080)
	add_child(bg)

	_compare_row()
	_state_row()
	_formation_row()
	_sword_qi_pips_preview()
	_label(Vector2(24, 16), "① 真身 vs 幻影：器形/器尖/星级一致，只换元素色温 + 加色混合 + 半透明")
	_label(Vector2(24, 330), "② 出刀四段：凝形（灵环推开）→ 驻场（呼吸）→ 挥出（弧光扫放）→ 消散")
	_label(Vector2(580, 660), "③ 一次开阵：6 把真剑（内环）+ 6 道幻影（外环）= 12 把同场，驻场数秒")
	_label(Vector2(24, 660), "④ 剑意 UI：头顶单柄小剑（20层逐刀充能，开阵沙漏倒计时流逝）")

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
		var base := Vector2(120 + (i % 3) * 380, 95 + floori(float(i) / 3.0) * 115.0)

		_renderer(base, wid, element, 1.0, deg_to_rad(-18.0), ZOOM)
		_label(base + Vector2(-56, 40), "真身 · %s" % def.get("name", "?"))
		_renderer(base + Vector2(140, 0), wid, element, SwordPhantom.GHOST_ALPHA,
			deg_to_rad(-18.0), ZOOM, true)
		_label(base + Vector2(106, 40), "幻影")

## ② 出刀四段（真实实体推进后停格）
func _state_row() -> void:
	var scene: PackedScene = load("res://scenes/weapons/SwordPhantom.tscn")
	var slots := [
		{"label": "凝形中（灵环推开）", "t": 0.05},
		{"label": "驻场（呼吸微光）", "t": SwordPhantom.FORM_TIME + 0.4},
		{"label": "挥出（弧光扫放）", "t": SwordPhantom.FORM_TIME + 0.4, "slash": true},
		{"label": "消散（化光）", "t": SwordPhantom.FORM_TIME + 0.4, "fade": 0.10},
	]
	for i in range(slots.size()):
		var spec: Dictionary = slots[i]
		var wrap := Node2D.new()
		wrap.position = Vector2(155 + i * 285, 500)
		wrap.scale = Vector2.ONE * STATE_ZOOM
		add_child(wrap)

		var ph := scene.instantiate() as SwordPhantom
		wrap.add_child(ph)
		ph.weapon_def_id = "qingyun_sword"
		ph.star = 1
		ph.element = "metal"
		ph.orbit_phase = 0.0
		ph.damage = 10.0
		ph.activate()
		# 剑阵里幻影朝向圈内最近敌人（或轨道外侧）；预览没有敌人，手动摆成「朝右上」这个典型姿态
		ph.rotation = deg_to_rad(-35.0)
		ph._apply_child_facing()
		# 推进到目标状态后停格（关掉物理推进，画面定在这一帧）
		var t: float = float(spec.get("t", 0.0))
		ph._age = t
		ph._life_left = SwordPhantom.FORMATION_TIME - t
		if t >= SwordPhantom.FORM_TIME:
			ph._state = SwordPhantom.STATE_IDLE
			ph.scale = Vector2.ONE
			ph.modulate.a = SwordPhantom.GHOST_ALPHA
			if bool(spec.get("slash", false)):
				# 挥出终点那一帧：弧光已扫到全尺寸、后摆归零、前突到位
				ph._swing_age = SwordPhantom.SWING_WINDUP + SwordPhantom.SWING_ACTIVE
				ph._swing_lunge = SwordPhantom.SLASH_LUNGE
				ph._swing_back = 0.0
				ph.scale = Vector2.ONE * (1.0 + SwordPhantom.SWING_PUNCH)
				ph._update_slash_arc()
			if bool(spec.get("fade", false)):
				var k: float = float(spec.get("fade", 0.0)) / SwordPhantom.FADE_TIME
				ph._state = SwordPhantom.STATE_FADE
				ph.modulate.a = SwordPhantom.GHOST_ALPHA * (1.0 - k)
				ph.scale = Vector2.ONE * lerpf(1.0, 1.28, k)
		else:
			# 凝形中：按 _tick_form 的同一组闭式解手算这一帧（activate 后 alpha 起点是 0）
			var k: float = clampf(t / SwordPhantom.FORM_TIME, 0.0, 1.0)
			var grow: float = lerpf(SwordPhantom.FORM_SCALE_IN, 1.06, k) if k < 0.82 \
				else lerpf(1.06, 1.0, (k - 0.82) / 0.18)
			ph.scale = Vector2.ONE * grow
			ph.modulate.a = SwordPhantom.GHOST_ALPHA * clampf(k / 0.45, 0.0, 1.0)
		ph.set_physics_process(false)
		ph.queue_redraw()
		_label(Vector2(80 + i * 285, 545), String(spec.get("label", "")))

## ③ 6 真剑内环 + 6 幻影外环（压扁的椭圆，整体收在 980 高度内）
func _formation_row() -> void:
	var center := Vector2(880, 880)
	# 内环：真剑轨道 54×40；外环：幻影轨道 88×68（收近后内外环距更紧凑，按同一俯视比例压扁 0.52）
	for i in range(SWORDS.size()):
		var wid: String = SWORDS[i]
		var def := WeaponData.get_def(wid)
		if def.is_empty():
			continue
		var element := WeaponData.element_of(wid)
		var ang := TAU * float(i) / float(SWORDS.size()) - PI * 0.5
		var dir := Vector2(cos(ang), sin(ang) * 0.52)
		_renderer(center + dir * 70.0, wid, element, 1.0, ang, 1.5)
		_renderer(center + dir * 115.0, wid, element, SwordPhantom.GHOST_ALPHA, ang, 1.5, true)

## ④ 剑意 UI 单柄小剑展示（逐刀充能、满层金芒、开阵沙漏倒计时流逝）
func _sword_qi_pips_preview() -> void:
	var samples := [
		{"charge": 0, "form": false, "ratio": 0.0, "label": "0/20 初始空槽"},
		{"charge": 6, "form": false, "ratio": 0.0, "label": "6/20 剑意充能 30%"},
		{"charge": 14, "form": false, "ratio": 0.0, "label": "14/20 剑意充能 70%"},
		{"charge": 20, "form": false, "ratio": 0.0, "label": "20/20 满层金芒脉冲"},
		{"charge": 20, "form": true, "ratio": 0.60, "label": "剑阵运转 沙漏流逝 60%"},
		{"charge": 20, "form": true, "ratio": 0.20, "label": "剑阵将尽 沙漏流逝 20%"},
	]
	for i in range(samples.size()):
		var s: Dictionary = samples[i]
		var col_idx := i % 2
		var row_idx := int(float(i) / 2.0)
		var pos := Vector2(85 + col_idx * 230, 750 + row_idx * 100)
		var wrap := Node2D.new()
		# vfx 内部以 -38.0 为头顶基准，加 38.0 补偿让小剑恰好落在 pos 上
		wrap.position = pos + Vector2(0.0, 38.0 * 2.2)
		wrap.scale = Vector2.ONE * 2.2   # 放大看清细节
		add_child(wrap)
		var vfx := PlayerSkillVfx.new()
		wrap.add_child(vfx)
		vfx.sync_sword_qi(int(s["charge"]), 20, bool(s["form"]), float(s["ratio"]), true)
		_label(pos + Vector2(-60, 22), String(s["label"]))

## 画一把器形（ghost=true 时走幻影口径：光晕外壳 + 元素 HDR + 加色混合 + 半透明）
func _renderer(pos: Vector2, wid: String, element: String, alpha: float,
		angle: float, zoom: float, ghost: bool = false) -> void:
	var def := WeaponData.get_def(wid)
	var shape := ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
	var upright := bool(def.get("upright", false))
	var tip: Vector2 = def.get("tip", Vector2(22, 0))
	if ghost:
		var halo := ProceduralWeaponRenderer.new()
		halo.configure(shape, element, tip.length(), 1, upright, wid)
		halo.material = SharedMaterials.add_blend()
		halo.scale = Vector2.ONE * (zoom * 0.55 * SwordPhantom.HALO_SCALE_MULT)
		halo.position = pos
		halo.rotation = angle
		var h_tint := GameStyle.fx_hdr_element(element)
		h_tint.a = alpha * SwordPhantom.HALO_ALPHA
		halo.modulate = h_tint
		add_child(halo)

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
