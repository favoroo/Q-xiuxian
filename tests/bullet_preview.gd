extends Node2D

## 法器弹丸出图台（非判据）：把五把弹丸法器的弹丸按真机渲染路径摆一排，与玩家/史莱姆同屏比大小，
## 存 PNG 后自动退出。为什么要有它：弹丸"像不像该法器打出来的东西"、"糊不糊成一团"只能靠眼睛验收 ——
## UnitRunner 钉得住"每把弹丸法器都配了外观且文件存在"，钉不住那张图对不对味。
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/BulletPreview.tscn      # 窗口一闪即退，产物 /tmp/bullet_render.png

const SHEET := "res://assets/art/"
const ORDER: Array = ["huoyan_fu", "gengjin_feijian", "liuye_feidao", "xuanbing_feizhen", "wanmu_lingfu"]

func _ready() -> void:
	var tile: Texture2D = load(SHEET + "courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(540.0 / tw) + 2):
		for x in range(0, int(960.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)
	_person(SHEET + "pawn_blue_8dir.png", 0.5, Vector2(150, 300))
	_person(SHEET + "pawn_red_8dir.png", 0.42, Vector2(820, 300))
	var i := 0
	for w_id in ORDER:
		var def := WeaponData.get_def(w_id)
		var p: BladeProjectile = load("res://scenes/weapons/BladeProjectile.tscn").instantiate()
		p.speed = 0.0
		p.spin = false                      # 摆拍不许转，只看法器自己的朝向
		var path: String = String(def.get("bullet", ""))
		if not path.is_empty() and ResourceLoader.exists(path):
			p.bullet_texture = load(path)
			p.bullet_scale = float(def.get("bullet_scale", 1.0))
		p.proc_burn = bool(def.get("proc_burn", false))
		p.proc_poison = bool(def.get("proc_poison", false))
		p.proc_chill = float(def.get("proc_chill", 0.0))
		p.position = Vector2(280 + i * 120, 190)
		add_child(p)
		var tex := p.bullet_texture if p.bullet_texture != null else load(SHEET + "blade.png")
		print("BULLET %s %s 贴图=%s 屏上=%s 判定半径=7px" % [
			w_id, String(def.get("name", "?")), str(tex.get_size()),
			str(tex.get_size() * (p.bullet_scale if p.bullet_texture != null else 0.45))])
		i += 1
	for f in range(6):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/bullet_render.png")
	print("SAVED ", img.get_size())
	get_tree().quit(0)

func _person(path: String, sc: float, at: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, 120, 120)
	spr.scale = Vector2(sc, sc)
	spr.position = at
	add_child(spr)
