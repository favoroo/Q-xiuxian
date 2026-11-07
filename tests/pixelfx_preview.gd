extends Node2D

## pixelfx 首批核心特效现场画廊预览台（非判据）
## 排布 12 种核心特效（天罚、火花、暴击、电结、刀光、火锥、光束、冰刺、地裂、开匣、拾取、光柱）
## 运行：godot --path . res://tests/PixelfxPreview.tscn
## 在第 14 帧自动抓图存至 /tmp/pixelfx_preview.png

const ITEMS: Array[Dictionary] = [
	{"id": &"lightning_strike", "name": "天罚落雷", "col": 0, "row": 0},
	{"id": &"hit_spark", "name": "命中火花", "col": 1, "row": 0},
	{"id": &"crit_hit", "name": "暴击破片", "col": 2, "row": 0},
	{"id": &"zap_hit", "name": "雷劫电结", "col": 3, "row": 0},

	# 已下线：WeaponArcRenderer 自绘的月牙刀光已是挥砍读数，叠这张就是两弯月牙。仅留档。
	{"id": &"sword_slash", "name": "月牙刀光(已下线)", "col": 0, "row": 1},
	{"id": &"fire_breath", "name": "烈焰火锥", "col": 1, "row": 1},
	{"id": &"arcane_beam", "name": "紫虹光束", "col": 2, "row": 1},
	{"id": &"ice_spikes", "name": "玄冥冰刺", "col": 3, "row": 1},

	{"id": &"earth_spike", "name": "裂山地裂", "col": 0, "row": 2},
	# 已下线：这张 sheet 自带整只匣子 + 一排骨币，叠在真匣子上就是「第二只箱子 + 假金币长条」，
	# 破匣/祭坛两处接入点均已撤掉（见 ChestBurstFx 文件头）。只在本预览台留档。
	{"id": &"chest_open", "name": "宝匣破开(已下线)", "col": 1, "row": 2},
	{"id": &"collect_burst", "name": "灵宝拾取", "col": 2, "row": 2},
	{"id": &"loot_beam", "name": "法宝光柱", "col": 3, "row": 2},

	# —— 2026-11-07 线条圈通刷新增 ——
	# 祭坛曾用 rune_circle/blessing_cone，同日「去花」下线（常驻祭坛不挂循环特效）；
	# rune_circle 仍被炮塔阵盘/玩家光环/敌环/刷怪预告使用，blessing_cone 已整包删除。
	{"id": &"rune_circle", "name": "金符环", "col": 0, "row": 3},
	{"id": &"spawn_portal", "name": "刷怪裂隙", "col": 2, "row": 3},
	{"id": &"sonic_ring", "name": "音波环", "col": 3, "row": 3},
	{"id": &"kill_blast", "name": "击杀灵爆", "col": 0, "row": 4},
	{"id": &"toxic_puddle", "name": "毒潭液面", "col": 1, "row": 4},
	{"id": &"ember_pool", "name": "火池液面", "col": 2, "row": 4},
	{"id": &"blood_ward", "name": "血海护罩", "col": 3, "row": 4},
	{"id": &"heal_aoe", "name": "治疗法阵", "col": 0, "row": 5},
]

var _frame: int = 0
var _anim_sprites: Array[AnimatedSprite2D] = []

func _ready() -> void:
	# 黑色舞台
	var bg := ColorRect.new()
	bg.size = Vector2(960, 540)
	bg.color = Color(0.06, 0.07, 0.10)
	add_child(bg)

	# 标题
	var title := Label.new()
	title.text = "【pixelfx 特效总览】天罚/近战/元素/爆散 + 线条圈通刷 21 项预览"
	title.position = Vector2(30, 16)
	title.modulate = Color(0.9, 0.85, 0.6)
	add_child(title)

	var col_width := 230.0
	var row_height := 160.0
	var start_pos := Vector2(120, 120)

	# 2026-11-07 线条圈通刷后条目涨到 21 项（6 行），540 高视口装不下 ——
	# 全部内容挂进一块自适应缩放的内容板：按最深的行算出 fit 系数整体缩小。
	var max_row := 0
	for item in ITEMS:
		max_row = maxi(max_row, int(item["row"]))
	var board := Node2D.new()
	var content_h := start_pos.y + float(max_row + 1) * row_height + 60.0
	board.scale = Vector2.ONE * minf(1.0, 528.0 / content_h)
	board.position = Vector2(0.0, 0.0)
	add_child(board)

	for item in ITEMS:
		var pos := start_pos + Vector2(item["col"] * col_width, item["row"] * row_height)

		# 网格定位点与边框
		var marker := Label.new()
		marker.text = item["name"] + "\n(" + String(item["id"]) + ")"
		marker.position = pos + Vector2(-60, 48)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.modulate = Color(0.65, 0.70, 0.80, 0.85)
		board.add_child(marker)

		# 创建并播放特效节点
		var anim := AnimatedSprite2D.new()
		var sf := FxSheetData.get_sprite_frames(item["id"])
		if sf != null:
			anim.sprite_frames = sf
			anim.animation = &"default"
			anim.global_position = pos
			anim.offset = FxSheetData.get_offset(item["id"])
			var conf := FxSheetData.get_config(item["id"])
			anim.scale = Vector2.ONE * conf.get("scale", 1.0)
			if conf.get("hdr", true):
				var mat := FxFlipbookPool._ensure_material()
				anim.material = mat
			board.add_child(anim)
			anim.play(&"default")
			_anim_sprites.append(anim)

func _process(_delta: float) -> void:
	_frame += 1
	# 让动画跑到关键帧（第 12 帧左右，各特效正在绽放高峰）
	if _frame == 15:
		var img := get_viewport().get_texture().get_image()
		img.save_png("/tmp/pixelfx_preview.png")
		print("PIXELFX_PREVIEW_SAVED /tmp/pixelfx_preview.png")
		get_tree().quit(0)
