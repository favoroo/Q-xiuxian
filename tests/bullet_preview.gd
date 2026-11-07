extends Node2D

## 法器弹丸出图台（非判据）：把全部 31 种「会打出去的弹丸」按族铺开，1:1 实际屏上尺寸，
## 走真实链路（BladeProjectile → activate），存 PNG 后自动退出。
##
## 为什么要有它：弹丸"像不像该法器打出来的东西"、"糊不糊成一团"、"机关和法器分不分得开"
## 只能靠眼睛验收 —— UnitRunner 钉得住"每把弹丸法器都配了外观且文件存在"、
## InspectCheck 钉得住"器形键可解析 / 批顶点预算"，都钉不住那张图对不对味。
##
## 2026-11-07 改造：从「6 把一行」扩成按族全量对账 ——
##   ① 机关 10 把：本次新增的专属器形（器械语言），必须与下面两行一眼分得开；
##   ② 符纸 11 把：整张符按五行染纸 + 独立剪影（3 组原本撞形的已换形）；
##   ③ 针 3 把（银/金/冰）+ 锋刃奇物 7 把：针类原本都是「一根线 + 一个点」，现已分家。
##
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/BulletPreview.tscn                 # 产物 /tmp/bullet_render.png
##   $G --path . res://tests/BulletPreview.tscn -- --zoom 3     # 再出一张近邻放大图，看细节
## 判读口径：先看 1:1 图（这才是玩家看到的），细节再用放大图确认。

const SHEET := "res://assets/art/"
const PROJ_SCENE := "res://scenes/weapons/BladeProjectile.tscn"
const SAVE_PATH := "/tmp/bullet_render.png"
const SAVE_ZOOM_PATH := "/tmp/bullet_render_zoom.png"

## 按「器形族」分组（不是按 tags）：每行是一个族，行内按 WeaponData 的登记顺序。
## 注意 jinzhen_fu 是符箓器类但弹丸是金针，按器形归到针行；shoulijian 同理归锋刃。
const GROUPS := [
	{
		"title": "机关 · 器械语言（直角/铆钉/铜铁底 + 元素锋尖）",
		"ids": ["jiguan_nu", "jianzhen_pan", "penhuo_jiguanshou", "hanquan_shou", "tengluo_jiguan",
			"leishi_jiguan", "kuilei_shou", "qingmu_pao", "ningbing_nu", "fenghuo_tai"],
	},
	{
		"title": "符纸 · 保留母题（五行染纸 + 互不撞形的剪影）",
		"ids": ["wanmu_lingfu", "huoyan_fu", "xuanbing_fu", "zhenshan_fu", "zhenhuo_fu", "leihuo_fu",
			"gudu_fu", "jingzhe_fu", "gengjin_fu", "guishui_fu", "houtu_fu"],
	},
	{
		"title": "针类（银=三缕雨丝尾 / 金=大环首 / 冰=晶体）＋ 锋刃·奇物",
		"ids": ["baoyu_liuhuazhen", "jinzhen_fu", "xuanbing_feizhen",
			"gengjin_feijian", "liuhuo_feijian", "liuye_feidao", "shoulijian",
			"tougu_ding", "lianhuan_lingdan", "langli_suo"],
	},
]

var _zoom := 1.0
var _vp := Vector2(1280, 720)

func _ready() -> void:
	_parse_zoom()
	_vp = get_viewport_rect().size
	_draw_floor()
	_title("弹丸出图台 · 1:1 实际屏上尺寸", Vector2(28, 18))
	_scale_ruler(Vector2(28, 40))
	# 大小标尺放在底栏：早先塞在行首会压住第一列弹丸（暴雨针几乎看不见）
	_person(SHEET + "pawn_blue_8dir.png", 0.42, Vector2(52, _vp.y - 44))
	_centered("角色本体（作大小参照）", 52, _vp.y - 16.0, 8, GameStyle.GREY)
	_person(SHEET + "pawn_red_8dir.png", 0.42, Vector2(_vp.x - 52, _vp.y - 44))

	var top := 76.0
	var bottom := _vp.y - 82.0
	var row_h := (bottom - top) / float(GROUPS.size())
	var y := top
	for g in GROUPS:
		_group_label(String(g["title"]), Vector2(28, y))
		_mount_row(g["ids"], y + 22.0, row_h - 22.0)
		y += row_h

	for f in range(8):
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png(SAVE_PATH)
			print("SAVED ", SAVE_PATH, " ", img.get_size())
			if _zoom > 1.0:
				_export_zoom(img)
	get_tree().quit(0)

func _parse_zoom() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--zoom" and i + 1 < args.size():
			_zoom = clampf(float(args[i + 1]), 1.0, 4.0)
		elif args[i].begins_with("--zoom="):
			_zoom = clampf(float(args[i].trim_prefix("--zoom=")), 1.0, 4.0)

func _export_zoom(base_img: Image) -> void:
	# 1:1 图上做近邻放大（与游戏 Nearest 过滤同款），不重渲染、不引入缩放差异
	var zoomed := base_img.duplicate() as Image
	zoomed.resize(int(base_img.get_width() * _zoom), int(base_img.get_height() * _zoom),
		Image.INTERPOLATE_NEAREST)
	zoomed.save_png(SAVE_ZOOM_PATH)
	print("SAVED ", SAVE_ZOOM_PATH, " ", zoomed.get_size())

# ------------------------------ 排版 ------------------------------

func _draw_floor() -> void:
	var tile: Texture2D = load(SHEET + "courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(_vp.y / tw) + 2):
		for x in range(0, int(_vp.x / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			s.modulate = Color(0.82, 0.82, 0.82, 0.55)
			add_child(s)

## 20px 标尺：弹丸本体只有 12~19px，没有参照物很容易把「大」和「清楚」搞混
func _scale_ruler(at: Vector2) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([at, at + Vector2(20, 0)])
	line.width = 1.0
	line.default_color = GameStyle.CHALK
	add_child(line)
	for dx in [0.0, 20.0]:
		var tick := Line2D.new()
		tick.points = PackedVector2Array([at + Vector2(dx, -4), at + Vector2(dx, 4)])
		tick.width = 1.0
		tick.default_color = GameStyle.CHALK
		add_child(tick)
	_centered("20px（屏上弹丸本体约 12~19px）", at.x + 130.0, at.y - 8.0, 9, GameStyle.CHALK)

func _title(text: String, at: Vector2) -> void:
	_centered(text, at.x + 260.0, at.y, 13, GameStyle.CHALK)

func _group_label(text: String, at: Vector2) -> void:
	_centered(text, at.x + 300.0, at.y, 11, GameStyle.GOLD)
	var line := Line2D.new()
	line.points = PackedVector2Array([at + Vector2(0, 18), at + Vector2(_vp.x - 56, 18)])
	line.width = 1.0
	line.default_color = Color(0.72, 0.62, 0.34, 0.35)
	add_child(line)

func _mount_row(ids: Array, y: float, row_h: float) -> void:
	var n := ids.size()
	var margin := 56.0
	var bullet_y := y + row_h * 0.5
	for i in range(n):
		var w_id := String(ids[i])
		var def := WeaponData.get_def(w_id)
		var x := margin + (_vp.x - margin * 2.0) * (float(i) + 0.5) / float(n)
		_spawn_bullet(w_id, def, Vector2(x, bullet_y))
		var nm := String(def.get("name", w_id))
		_centered(nm, x, bullet_y - 34.0, 10, GameStyle.CHALK)
		_centered(WeaponData.element_of(w_id), x, bullet_y + 20.0, 8, GameStyle.GREY)

## 居中对齐的标签：不套容器，直接给固定宽度 + CENTER 对齐
func _centered(text: String, cx: float, y: float, size: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	GameStyle.label(l, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(cx - 140.0, y)
	l.size = Vector2(280.0, float(size) + 8.0)
	add_child(l)

# ------------------------------ 出弹 ------------------------------

## 走真实链路：字段照 ProjectileHandler/TurretUnit 的写法填，然后 activate()，
## 再把物理关掉做静态摆拍（activate 是唯一会铺视觉的地方，_ready 只跑一次）。
func _spawn_bullet(w_id: String, def: Dictionary, at: Vector2) -> BladeProjectile:
	var p: BladeProjectile = load(PROJ_SCENE).instantiate()
	var bullet_path := String(def.get("bullet", ""))
	if not bullet_path.is_empty() and ResourceLoader.exists(bullet_path):
		p.bullet_texture = load(bullet_path)
	p.bullet_scale = float(def.get("bullet_scale", 1.0))
	p.bullet_art = String(def.get("bullet_art", ""))
	p.spin = false                      # 摆拍不转，只看法器自己的朝向
	p.speed = 0.0
	p.direction = Vector2.RIGHT
	p.proc_burn = bool(def.get("proc_burn", false))
	p.proc_poison = bool(def.get("proc_poison", false))
	p.proc_chill = float(def.get("proc_chill", 0.0))
	p.element_name = WeaponData.element_of(w_id)
	p.element_tint = GameStyle.ELEMENT_COLORS.get(p.element_name, Color.WHITE)
	p.position = at
	add_child(p)
	p.activate()
	p.set_physics_process(false)        # 生命/移动冻结，停在原地摆拍
	p.lifetime = 999.0

	var kind_name := "?"
	if p._vector_renderer != null:
		kind_name = String(ProceduralProjectileRenderer.ProjectileKind.keys()[p._vector_renderer.kind])
	print("BULLET %-20s %-8s kind=%-18s scale=%.2f art=%s" % [
		w_id, String(def.get("name", "?")), kind_name, p.bullet_scale, p.bullet_art])
	return p

func _person(path: String, sc: float, at: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, 120, 120)
	spr.scale = Vector2(sc, sc)
	spr.position = at
	add_child(spr)