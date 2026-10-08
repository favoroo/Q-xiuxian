extends Node2D

## 敌方火球出图台（非判据，不参与三条绿灯）：把 EnemyBolt 按真机渲染路径摆一排，
## 与玩家/施法者同屏比大小，存 PNG 后自动退出。
## 为什么要有它：火球的口径是「画出来的圆 == 判定圆」（见 EnemyBolt.gd 头注），
## 而这条只能靠眼睛验收 —— 单测能钉住 radius 与碰撞体同源，钉不住「看着是不是太小/太糊」。
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/BoltPreview.tscn      # 窗口一闪即退，产物 /tmp/bolt_render.png
## 会顺带打印普通火球与 Boss 环弹的实际判定半径，用来核对 scale_factor 有没有走通。

const SHEET := "res://assets/art/"

func _ready() -> void:
	var tile: Texture2D = load(SHEET + "courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(540.0 / tw) + 2):
		for x in range(0, int(960.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)
	_person(SHEET + "warrior_purple_8dir.png", 0.5, Vector2(480, 300), Color.WHITE)
	_person(SHEET + "pawn_red_8dir.png", 0.42, Vector2(250, 180), Color(0.75, 0.55, 1.25))
	var first: EnemyBolt = null
	for pos in [Vector2(600, 240), Vector2(400, 150), Vector2(665, 420), Vector2(300, 400)]:
		var bolt := EnemyBolt.new()
		bolt.speed = 0.0
		bolt.position = pos
		add_child(bolt)
		if first == null:
			first = bolt
	var big := EnemyBolt.new()
	big.speed = 0.0
	big.scale_factor = GameBalance.BOSS_BOLT_SCALE
	big.position = Vector2(520, 430)
	add_child(big)
	for i in range(4):
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/bolt_render.png")
	print("SAVED ", img.get_size(), " normal_r=", first.radius, " boss_r=", big.radius)
	get_tree().quit(0)

func _person(path: String, sc: float, at: Vector2, mod: Color) -> void:
	var tex: Texture2D = load(path)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.region_enabled = true
	spr.region_rect = Rect2(0, 0, 120, 120)
	spr.scale = Vector2(sc, sc)
	spr.modulate = mod
	spr.position = at
	add_child(spr)
