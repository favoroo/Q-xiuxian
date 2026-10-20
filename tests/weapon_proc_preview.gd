extends Node2D

## 法器矢量本体预览台（非判据，必须开窗跑）：
##   $G --path . res://tests/WeaponProcPreview.tscn
##   $G --path . res://tests/WeaponProcPreview.tscn -- --out /tmp/xxx.png --weapons sword,liuye_feidao
## 可选参数（-- 之后）：
##   --out <路径>      自定义输出 PNG（默认 /tmp/weapon_proc_preview.png）
##   --weapons <csv>   只画命中项（按 法器id / shape器形名 / 中文名 匹配，逗号分隔），供单族自检
## 产物 /tmp/weapon_proc_preview.png
## 上区：批次 1（剑/刀/匕首）+ 批次 2（符/扇/印/牌/灯/鼓/铎）全部 4x 放大
##       —— 非竖置器形沿 +X，竖置重器按世界竖直画（与实机姿态一致），橙线=tip 器尖标定
## 底栏：集成契约校验（FloatingWeapon 是否挂上矢量本体、贴图是否让位、出膛点是否对齐）

const BATCH1 := [
	"qingyun_sword", "gengjin_feijian", "liuye_feidao", "chiyan_dao", "xueyin_dao",
	"qingteng_jian", "hanshuang_jian", "taomu_jian", "bengshan_jian", "liuhuo_feijian",
]
const BATCH2 := [
	"wanmu_lingfu", "huoyan_fu", "jinzhen_fu", "xuanbing_fu", "zhenshan_fu",
	"zhenhuo_fu", "leihuo_fu", "gudu_fu", "jingzhe_fu", "gengjin_fu",
	"guishui_fu", "houtu_fu", "bajiao_fan", "liaoyuan_shan", "fantian_yin",
	"wulei_paizi", "jinxiao_leiling", "fentian_baodeng", "chunlei_gu", "lieshan_duo",
]
const BATCH3 := [
	"qingmu_tengbian", "xuanwu_lingdun", "kaishan_fu", "benlang_chui", "liuling_jian",
	"jubao_chi", "jinjiao_jian", "langli_suo", "tougu_ding", "baoyu_liuhuazhen",
	"xuanbing_feizhen", "lianhuan_lingdan", "sanmei_huohu", "bihai_chaoyindi",
	"zihong_jing", "xuanming_leizhu", "jinlei_zhui", "shoulijian",
]
const CELL := 112.0
const ZOOM := 4.0

var _out_path := "/tmp/weapon_proc_preview.png"
var _filter: PackedStringArray = []

## 解析 `--` 之后的用户参数：--out <路径> / --weapons <id或器形名或中文名，逗号分隔>
func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_path = args[i + 1]
			i += 1
		elif args[i] == "--weapons" and i + 1 < args.size():
			_filter = args[i + 1].split(",", false)
			i += 1
		i += 1

## 过滤命中判定：id / shape / turret_shape / 中文名 任一相等即收
func _accept(id: String) -> bool:
	if _filter.is_empty():
		return true
	var def := WeaponData.get_def(id)
	for t in _filter:
		if id == t or String(def.get("shape", "")) == t \
				or String(def.get("turret_shape", "")) == t or String(def.get("name", "")) == t:
			return true
	return false

func _pick(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		if _accept(id):
			out.append(id)
	return out

func _ready() -> void:
	_parse_args()
	DisplayServer.window_set_size(Vector2i(1000, 1640))
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.13)
	bg.size = Vector2(1000, 1640)
	add_child(bg)

	if _filter.is_empty():
		_grid(BATCH1, 96.0, 5)
		_grid(BATCH2, 340.0, 8)
		_grid(BATCH3, 720.0, 6)
		_label(Vector2(20, 20), "法器矢量本体（4x，橙线=tip 器尖标定）")
		_label(Vector2(20, 300), "批次 2 · 符箓 / 扇 / 印 / 牌令 / 灯 / 鼓 / 铎")
		_label(Vector2(20, 680), "批次 3 · 鞭 / 盾 / 斧 / 锤 / 锏 / 尺 / 剪 / 梭 / 钉 / 针 / 弹弓 / 葫芦 / 笛 / 镜 / 珠 / 锥")
	else:
		# 过滤模式：命中项混排一个网格，供单族重绘自检
		_grid(_pick(BATCH1 + BATCH2 + BATCH3), 96.0, 8)
		_label(Vector2(20, 20), "法器矢量本体（4x，橙线=tip）过滤: %s" % ",".join(_filter))
	_real_scale_row()
	_star_row()
	_turret_row()
	_integration_check()
	# 多等几帧再截图：Control 文字（字体塑形）在系统繁忙时首几帧可能还没上屏
	for _i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out_path)
		print("SAVED %s " % _out_path, img.get_size())
	get_tree().quit(0)

func _grid(ids: Array, top: float, cols: int) -> void:
	for i in range(ids.size()):
		var c := i % cols
		var r := floori(float(i) / float(cols))
		var center := Vector2(80 + c * CELL, top + r * CELL)
		_place(center, ids[i], 1, 0.0)
		_label(Vector2(center.x - 52, center.y - 62), "%s" % WeaponData.get_def(ids[i]).get("name", "?"))

## 实机尺度对照：按真实 0.55 缩放排两行（这是玩家实际看到的大小），
## 用来确认矢量本体在 20~30px 尺度下仍认得出来、不被 HDR 起辉糊掉。
func _real_scale_row() -> void:
	var ids: Array = _pick(BATCH1 + BATCH2 + BATCH3)
	if ids.is_empty():
		return
	var y := 1046.0
	_label(Vector2(20, y - 20), "实机尺度（×0.55，玩家实际所见大小）")
	for i in range(ids.size()):
		var def := WeaponData.get_def(ids[i])
		var shape := ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
		var upright := bool(def.get("upright", false))
		var tip: Vector2 = def.get("tip", Vector2(22, 0))
		var r := ProceduralWeaponRenderer.new()
		r.configure(shape, WeaponData.element_of(ids[i]), tip.length(), 1, upright, ids[i])
		r.scale = Vector2.ONE * 0.55
		r.position = Vector2(46 + (i % 30) * 30, y + 12 + floori(float(i) / 30.0) * 30.0)
		add_child(r)

## 升星结构强化（★1/★2/★3）：横置扇 + 竖置令牌各一组
func _star_row() -> void:
	var show := _pick(["liaoyuan_shan", "wulei_paizi", "fentian_baodeng", "jinjiao_jian"])
	if show.is_empty():
		return
	var y := 1120.0
	_label(Vector2(20, y - 18), "升星结构强化（★1 / ★2 / ★3）")
	for i in range(show.size()):
		for s in range(3):
			var def := WeaponData.get_def(show[i])
			var shape := ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
			var upright := bool(def.get("upright", false))
			var tip: Vector2 = def.get("tip", Vector2(22, 0))
			var r := ProceduralWeaponRenderer.new()
			r.configure(shape, WeaponData.element_of(show[i]), tip.length(), s + 1, upright, show[i])
			r.scale = Vector2.ONE * 0.55
			r.position = Vector2(70 + i * 200 + s * 52, y + 22)
			add_child(r)

func _place(center: Vector2, id: String, star: int, angle: float) -> void:
	var def := WeaponData.get_def(id)
	var shape := ProceduralWeaponRenderer.shape_from_name(String(def.get("shape", "")))
	var upright := bool(def.get("upright", false))
	var tip: Vector2 = def.get("tip", Vector2(22, 0))
	var r := ProceduralWeaponRenderer.new()
	r.configure(shape, WeaponData.element_of(id), tip.length(), star, upright, id)
	r.scale = Vector2.ONE * (ZOOM * 0.55)
	r.position = center
	r.rotation = angle
	add_child(r)
	# tip 标定线：从中心到器尖（本地 +X * tip_len，经节点变换；竖置整体转 -90°）
	var local_tip := Vector2(tip.length(), 0.0).rotated(-PI * 0.5 if upright else 0.0)
	var tip_world: Vector2 = center + local_tip.rotated(angle) * (ZOOM * 0.55)
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
	# 深底亮字必须用 CHALK（PAPER 二次换肤后已是深墨字，深底下不可读）
	GameStyle.label(lab, 11, GameStyle.CHALK)
	lab.position = pos
	add_child(lab)

## 机关炮台（批次 4）：弩机/阵盘/炮管/机关兽/投石机/灯塔 六种器形 × 元素配色
const TURRETS := [
	"jiguan_nu", "ningbing_nu", "jianzhen_pan", "qingmu_pao", "penhuo_jiguanshou",
	"hanquan_shou", "kuilei_shou", "leishi_jiguan", "tengluo_jiguan", "fenghuo_tai",
]

func _turret_row() -> void:
	var ids := _pick(TURRETS)
	if ids.is_empty():
		return
	var y := 1210.0
	_label(Vector2(20, y - 18), "批次 4 · 机关炮台（弩机 / 阵盘 / 炮管 / 机关兽 / 投石机 / 灯塔）")
	for i in range(ids.size()):
		var def := WeaponData.get_def(ids[i])
		var ts := ProceduralTurretRenderer.shape_from_name(String(def.get("turret_shape", "")))
		var r := ProceduralTurretRenderer.new()
		r.configure(ts, WeaponData.element_of(ids[i]), 1)
		r.scale = Vector2.ONE * (ZOOM * 0.55 * 0.78)
		var cx := 80 + (i % 5) * 190
		var cy := y + 40 + floori(float(i) / 5.0) * 140.0
		r.position = Vector2(cx, cy)
		add_child(r)
		_label(Vector2(cx - 44, cy + 70), "%s" % def.get("name", "?"))

## 集成契约：全部悬浮法器（批次 1/2/3）必须挂上矢量本体并隐蔽贴图，器尖==出膛点
func _integration_check() -> void:
	var y := 1560.0
	var ok := 0
	var total := 0
	for id in _pick(BATCH1 + BATCH2 + BATCH3):
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
	# 覆盖率：悬浮法器已全量矢量化；御灵/机关走 SunOrb / TurretUnit，本渲染器不接管（灰度开关保留）
	var covered := 0
	var floating := 0
	for def_id in WeaponData.DEFS.keys():
		var b := int((WeaponData.DEFS[def_id] as Dictionary).get("behavior", -1))
		if b == WeaponData.Behavior.DRONE or b == WeaponData.Behavior.TURRET:
			continue
		floating += 1
		if ProceduralWeaponRenderer.shape_from_name(String(WeaponData.DEFS[def_id].get("shape", ""))) != ProceduralWeaponRenderer.WeaponShape.GENERIC:
			covered += 1
	var cov_ok := covered == floating
	print("悬浮法器矢量化覆盖率: %d/%d" % [covered, floating])
	_label(Vector2(20, y + 22), "悬浮法器矢量化覆盖率: %d/%d（御灵/机关另走 SunOrb/TurretUnit）: %s" % [covered, floating, "OK" if cov_ok else "FAIL"])
