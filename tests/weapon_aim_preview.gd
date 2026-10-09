extends Node2D

## 法器「朝向 + 出膛点」出图台（非判据）：把 12 件会转/会射的法器按 4 个瞄准方向各摆一份，
## 每件都在它自己标定的剑尖/器口上摆一颗真弹丸，旁边画一条瞄准轴和靶心 —— 用眼睛验收
## "剑尖有没有对着敌人、东西是不是从剑尖出来的"。
##
## 为什么判据全绿了还要它：tests/WeaponAimCheck.tscn 钉的是几何关系（角度差、像素差），
## 钉不出"这个尖到底是剑尖还是剑格""重器横过来没有""弹丸大小对不对味" —— 那些只能看。
## 摆位用的就是运行时那两个数：w._apply_facing(θ) 与 w.muzzle_point.global_position，
## 弹丸贴图/缩放/朝向也直接读 WeaponData，不另编一套参数。
##
## 运行（不能加 --headless，headless 不渲染、拿不到图）：
##   $G --path . res://tests/WeaponAimPreview.tscn      # 产物 /tmp/weapon_aim_render.png

const COLS := ["qingyun_sword", "gengjin_feijian", "liuye_feidao", "qingmu_tengbian",
	"wanmu_lingfu", "bajiao_fan", "xuanbing_feizhen", "huoyan_fu",
	"chiyan_dao", "fentian_baodeng", "wulei_paizi", "fantian_yin"]
const ROWS_DEG := [0.0, 90.0, 180.0, -90.0]
const CELL := 120.0
const AIM_LEN := 46.0

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(int(COLS.size() * CELL), int(40.0 + ROWS_DEG.size() * CELL)))
	_add_bg()
	for c in range(COLS.size()):
		var def_id: String = COLS[c]
		var def := WeaponData.get_def(def_id)
		for r in range(ROWS_DEG.size()):
			var aim := deg_to_rad(float(ROWS_DEG[r]))
			var cell := Node2D.new()
			cell.position = Vector2(c * CELL + CELL * 0.5, 40.0 + r * CELL + CELL * 0.5)
			add_child(cell)
			_aim_guide(cell, aim)
			_place_weapon(cell, def_id, aim)
		var lab := Label.new()
		lab.text = "%s·%s" % [String(def.get("name", "?")), "竖直" if bool(def.get("upright", false)) else "转向"]
		GameStyle.label(lab, 13, GameStyle.PAPER)
		lab.position = Vector2(c * CELL + 4, 2)
		lab.size = Vector2(CELL - 8, 20)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(lab)
	for f in range(8):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/weapon_aim_render.png")
	print("SAVED /tmp/weapon_aim_render.png ", img.get_size())
	get_tree().quit(0)

func _add_bg() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.11, 0.16)
	bg.size = Vector2(COLS.size() * CELL, 40.0 + ROWS_DEG.size() * CELL)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

## 瞄准轴 + 靶心：弹丸该落在这条线的尽头
func _aim_guide(cell: Node2D, aim: float) -> void:
	var line := Line2D.new()
	line.width = 1.0
	line.default_color = Color(1, 1, 1, 0.22)
	line.points = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT.rotated(aim) * AIM_LEN])
	cell.add_child(line)
	var dot := Polygon2D.new()
	dot.polygon = _circle_pts(4.0)
	dot.color = Color(1, 0.85, 0.3, 0.9)
	dot.position = Vector2.RIGHT.rotated(aim) * AIM_LEN
	cell.add_child(dot)

func _circle_pts(r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(12):
		out.append(Vector2.RIGHT.rotated(TAU * float(i) / 12.0) * r)
	return out

## 真法器节点 + 真发射点：摆位完全走运行时的 _apply_facing / muzzle_point
func _place_weapon(cell: Node2D, def_id: String, aim: float) -> void:
	var def := WeaponData.get_def(def_id)
	var w: FloatingWeapon = load("res://scenes/weapons/FloatingWeapon.tscn").instantiate()
	w.setup(def_id, 1)
	cell.add_child(w)
	w.set_process(false)
	w._apply_facing(aim)
	if int(def.get("behavior", -1)) != WeaponData.Behavior.PROJECTILE:
		return
	var bullet_path := String(def.get("bullet", ""))
	if bullet_path.is_empty() or not ResourceLoader.exists(bullet_path):
		push_warning("%s 没配弹丸外观" % def_id)
		return
	var p: BladeProjectile = load("res://scenes/weapons/BladeProjectile.tscn").instantiate()
	p.speed = 0.0
	p.spin = false                       # 摆拍不许转，只看它出膛那一刻的朝向
	p.bullet_texture = load(bullet_path)
	p.bullet_scale = float(def.get("bullet_scale", 1.0))
	p.direction = Vector2.RIGHT.rotated(aim)
	# 与 FloatingWeapon._perform_projectile_attack 同一处取值：出膛点 = 标定好的剑尖/器口
	add_child(p)
	p.global_position = w.muzzle_point.global_position
	w.muzzle_flash.visible = true
	w.muzzle_flash.modulate = Color(1, 0.9, 0.55, 0.55)
	w.muzzle_flash.scale = Vector2.ONE * 0.5
