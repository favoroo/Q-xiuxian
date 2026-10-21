extends Node

## 武器 UI 图标【批量导出工具】（非判据，必须开窗跑；headless 无渲染意义）
##   $G --path . res://tests/WeaponIconExport.tscn
##   $G --path . res://tests/WeaponIconExport.tscn -- --out /tmp/weapon_icon_raw
##
## 把游戏里现成的【矢量本体渲染器】逐个渲染到透明 SubViewport，抓 512 图存 PNG。
##   · 有 shape  → ProceduralWeaponRenderer（战斗里那把武器本体同款）
##   · DRONE     → ProceduralDroneRenderer
##   · TURRET    → ProceduralTurretRenderer
## 保证与战斗观感零偏差；战斗 48px 画布与 WeaponData.tip 完全不动。
##
## 输出文件名 = WeaponData 的 icon 字段 basename（lingdie → sun_orb.png），
## 便于 Python 侧按 UI 变体路径 assets/art/ui/<basename> 落盘。
## 本工具只写原始 512 透明图到 --out（默认 /tmp），不落 assets/。

const CANVAS := 512
const CENTER := Vector2(CANVAS * 0.5, CANVAS * 0.5)
const ART_SCALE := 6.0

## 同器形同五行的武器，矢量本体完全一样 ⇒ 导出层叠一个「专属细节」区分（不碰战斗渲染器）。
## 只列需要区分的（每组基准保持原样）。kind 见 DetailMark。
const DETAILS := {
	"weapon_gold_sword": {"kind": "gem", "color": Color(0.35, 0.92, 1.0)},      # 飞剑：护手嵌青玉
	"weapon_taomu_jian": {"kind": "tassel", "color": Color(0.86, 0.20, 0.16)},   # 桃木剑：剑首红穗
	"weapon_xueyin_dao": {"kind": "blood", "color": Color(0.72, 0.06, 0.08)},    # 血饮狂刀：血槽血珠
	"weapon_jinzhen_fu": {"kind": "needle", "color": Color(0.78, 0.18, 0.12)},   # 金针符
	"weapon_gengjin_fu": {"kind": "meander", "color": Color(0.78, 0.18, 0.12)},  # 庚金符
	"weapon_xuanbing_fu": {"kind": "snow", "color": Color(0.20, 0.55, 0.85)},    # 玄冰符
	"weapon_guishui_fu": {"kind": "wave", "color": Color(0.20, 0.55, 0.85)},     # 癸水符
	"weapon_zhenhuo_fu": {"kind": "flame", "color": Color(0.80, 0.20, 0.10)},    # 真火符
	"weapon_leihuo_fu": {"kind": "bolt", "color": Color(0.80, 0.20, 0.10)},      # 雷火符
	"weapon_gudu_fu": {"kind": "worm", "color": Color(0.55, 0.35, 0.12)},        # 蛊毒符
	"weapon_jingzhe_fu": {"kind": "sprout", "color": Color(0.30, 0.62, 0.28)},   # 惊蛰符
}

var _out_dir := "/tmp/weapon_icon_raw"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(_out_dir)

	if DisplayServer.get_name() == "headless":
		print("[WeaponIconExport] headless 无渲染意义，退出")
		get_tree().quit(0)
		return

	var done := 0
	var skipped: Array[String] = []
	for wid in WeaponData.SHOP_POOL:
		var ok := await _export_one(String(wid))
		if ok:
			done += 1
		else:
			skipped.append(String(wid))
	print("[WeaponIconExport] 完成 %d 把，跳过 %d: %s" % [done, skipped.size(), str(skipped)])
	print("WEAPON_ICON_EXPORT_DONE")
	get_tree().quit(0)

func _icon_basename(def: Dictionary) -> String:
	var p := String(def.get("icon", ""))
	return p.get_file().get_basename()

func _export_one(wid: String) -> bool:
	var def := WeaponData.get_def(wid)
	if def.is_empty():
		push_warning("未找到武器: " + wid)
		return false

	var vp := SubViewport.new()
	vp.size = Vector2i(CANVAS, CANVAS)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.disable_3d = true
	add_child(vp)

	var holder := Node2D.new()
	holder.position = CENTER
	holder.scale = Vector2(ART_SCALE, ART_SCALE)
	vp.add_child(holder)

	var behavior := int(def.get("behavior", 0))
	var element := WeaponData.element_of(wid)
	if element == "" and WeaponData.tags_of(wid).has("thunder"):
		element = "thunder"

	var node: Node2D = null
	if behavior == WeaponData.Behavior.DRONE:
		node = _make_drone(wid)
		holder.rotation = 0.0
	elif behavior == WeaponData.Behavior.TURRET:
		node = _make_turret(def, element)
		holder.rotation = deg_to_rad(-25.0)
	else:
		node = _make_weapon(def, element, wid)
		holder.rotation = 0.0 if bool(def.get("upright", false)) else deg_to_rad(-35.0)

	if node == null:
		push_warning("无渲染器: " + wid)
		vp.queue_free()
		return false
	holder.add_child(node)

	# 专属细节（导出层，仅武器，画在画布中心坐标系；holder 已缩放到 ART_SCALE，故本地坐标 = 画布像素）
	var bn := _icon_basename(def)
	if behavior != WeaponData.Behavior.DRONE and behavior != WeaponData.Behavior.TURRET and DETAILS.has(bn):
		var mark := DetailMark.new()
		mark.cfg = DETAILS[bn]
		holder.add_child(mark)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out_dir, bn])
	vp.queue_free()
	return true

func _make_weapon(def: Dictionary, element: String, wid: String) -> Node2D:
	var shape_name := String(def.get("shape", ""))
	var wshape := ProceduralWeaponRenderer.shape_from_name(shape_name)
	if wshape == ProceduralWeaponRenderer.WeaponShape.GENERIC:
		return null
	var r := ProceduralWeaponRenderer.new()
	var tip: Vector2 = def.get("tip", Vector2(20, 0))
	r.configure(wshape, element, tip.length(), 1, bool(def.get("upright", false)), wid)
	return r

func _make_drone(wid: String) -> Node2D:
	var r := ProceduralDroneRenderer.new()
	r.star = 1
	match wid:
		"hanquan_yulian": r.kind = ProceduralDroneRenderer.DroneKind.HANQUAN_YULIAN
		"hunyuan_zhong": r.kind = ProceduralDroneRenderer.DroneKind.HUNYUAN_ZHONG
		"haojin_lun": r.kind = ProceduralDroneRenderer.DroneKind.HAOJIN_LUN
		"lihuo_ya": r.kind = ProceduralDroneRenderer.DroneKind.LIHUO_YA
		"xuanwu_pei": r.kind = ProceduralDroneRenderer.DroneKind.XUANWU_PEI
		"jinming_ling": r.kind = ProceduralDroneRenderer.DroneKind.JINMING_LING
		"muling_ou": r.kind = ProceduralDroneRenderer.DroneKind.MULING_OU
		"bingpo_zhu": r.kind = ProceduralDroneRenderer.DroneKind.BINGPO_ZHU
		"chiyan_ying": r.kind = ProceduralDroneRenderer.DroneKind.CHIYAN_YING
		"tuling_shi": r.kind = ProceduralDroneRenderer.DroneKind.TULING_SHI
		"jianling": r.kind = ProceduralDroneRenderer.DroneKind.JIAN_LING
		_: r.kind = ProceduralDroneRenderer.DroneKind.LINGDIE
	return r

func _make_turret(def: Dictionary, element: String) -> Node2D:
	var tshape := ProceduralTurretRenderer.shape_from_name(String(def.get("turret_shape", "")))
	if tshape == ProceduralTurretRenderer.TurretShape.GENERIC:
		return null
	var r := ProceduralTurretRenderer.new()
	r.configure(tshape, element, 1)
	return r

## 导出层专属细节标记：画在画布中心坐标系（holder 已 ART_SCALE，本地坐标=画布像素）。
## 只用于给同器形同五行的武器做区分，不参与战斗渲染。
class DetailMark extends Node2D:
	var cfg: Dictionary = {}

	func _draw() -> void:
		var kind := String(cfg.get("kind", ""))
		var col: Color = cfg.get("color", Color.WHITE)
		var dark := Color(0.10, 0.08, 0.08, 0.9)
		match kind:
			"gem":
				# 剑格处嵌一枚小菱形宝石（青，偏暗）；剑格在 x≈+2
				_poly([Vector2(2, -3.2), Vector2(4.6, 0), Vector2(2, 3.2), Vector2(-0.6, 0)], dark)
				_poly([Vector2(2, -2.2), Vector2(3.7, 0), Vector2(2, 2.2), Vector2(0.3, 0)], col.darkened(0.1))
			"tassel":
				# 剑首红结：柄端一枚小红圆结（不画长线，避免读成筷子）
				draw_circle(Vector2(-13, 0), 2.6, Color(0.10, 0.08, 0.08, 0.9))
				draw_circle(Vector2(-13, 0), 1.9, col)
			"blood":
				# 刀身血槽：中脊一道暗红长线 + 两滴血珠
				draw_line(Vector2(-18, 0), Vector2(20, 0), Color(col.r, col.g, col.b, 0.75), 1.8, true)
				draw_circle(Vector2(6, 4), 2.4, col)
				draw_circle(Vector2(13, -3), 1.8, col)
			"needle":
				# 金针符：三道细针
				for i in range(3):
					var oy := -4.0 + i * 4.0
					draw_line(Vector2(-8, oy), Vector2(8, oy), col, 1.1, true)
			"meander":
				# 庚金符：回纹曲尺
				draw_polyline(PackedVector2Array([Vector2(-6,-6),Vector2(6,-6),Vector2(6,6),Vector2(-2,6),Vector2(-2,-2),Vector2(2,-2)]), col, 1.4, true)
			"snow":
				# 玄冰符：六向雪花
				for i in range(3):
					var a := PI * i / 3.0
					var dv := Vector2(cos(a), sin(a)) * 7.0
					draw_line(-dv, dv, col, 1.3, true)
			"wave":
				# 癸水符：三道波纹
				for i in range(3):
					var oy := -4.0 + i * 4.0
					draw_polyline(PackedVector2Array([Vector2(-7,oy),Vector2(-2,oy-2),Vector2(2,oy+2),Vector2(7,oy)]), col, 1.2, true)
			"flame":
				# 真火符：一簇小火舌
				_poly([Vector2(0,-9),Vector2(4,-1),Vector2(2,5),Vector2(-2,5),Vector2(-4,-1)], col)
			"bolt":
				# 雷火符：闪电折线
				draw_polyline(PackedVector2Array([Vector2(3,-9),Vector2(-3,0),Vector2(1,0),Vector2(-4,9)]), col, 1.6, true)
			"worm":
				# 蛊毒符：S 形虫纹
				draw_polyline(PackedVector2Array([Vector2(-6,4),Vector2(-2,-3),Vector2(2,3),Vector2(6,-4)]), col, 1.4, true)
			"sprout":
				# 惊蛰符：嫩芽
				draw_line(Vector2(0,6), Vector2(0,-2), col, 1.4, true)
				draw_line(Vector2(0,-2), Vector2(-5,-7), col, 1.3, true)
				draw_line(Vector2(0,-2), Vector2(5,-7), col, 1.3, true)

	func _poly(pts: Array, c: Color) -> void:
		draw_colored_polygon(PackedVector2Array(pts), c)
