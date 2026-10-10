extends Node2D

## 聚灵阵充能读数出图台（非判据，不参与绿灯）：同一张地砖上并排摆四座界碑，
## 分别钉在 25% / 50% / 85% / 100% 四档进度上，各存一张整图后自动退出。
## 为什么要有它：「进度画在阵法上到底看不看得出来」是纯眼睛的活 ——
## 判据能钉住 ratio 三处同源、钉不住「拇指挡着按钮时，这一圈够不够醒目」。
## 运行（不能加 --headless，headless 不渲染、get_image 拿到空图）：
##   $G --path . res://tests/ObeliskChargePreview.tscn
## 产物 /tmp/obelisk_charge_all.png（四档同屏）与 /tmp/obelisk_charge_<档>.png（单碑特写）

const OBELISK := preload("res://scenes/entities/BlessingObelisk.tscn")
## 四档进度：没充（基线，用来比对灌灵到底改变了什么）/ 三成 / 六成半 / 满格那一帧
const STEPS: Array[float] = [0.0, 0.3, 0.65, 1.0]
const ROW_Y := 262.0
const COL_X: Array[float] = [132.0, 372.0, 612.0, 852.0]

var _nodes: Array[BlessingObelisk] = []
var _hud: GameHUD = null

func _ready() -> void:
	var tile: Texture2D = load("res://assets/art/courtyard_tile.png")
	var tw := int(tile.get_width())
	for y in range(0, int(540.0 / tw) + 2):
		for x in range(0, int(960.0 / tw) + 2):
			var s := Sprite2D.new()
			s.texture = tile
			s.position = Vector2(x * tw + tw / 2.0, y * tw + tw / 2.0)
			add_child(s)
	for i in range(STEPS.size()):
		var ob: BlessingObelisk = OBELISK.instantiate()
		ob.position = Vector2(COL_X[i], ROW_Y)
		add_child(ob)
		_nodes.append(ob)
	for i in range(6):
		await get_tree().process_frame
	# 走真实链路到满，再逐档把读数钉住（_show_readout / _set_readout_ratio 就是
	# 充能期间每帧在跑的那两个函数，这里只是把某一帧按住不动给人看）
	for i in range(STEPS.size()):
		var pinned := _nodes[i]
		pinned.is_player_inside = true
		pinned.start_charge()
		pinned.is_charging = false
		pinned._set_readout_ratio(STEPS[i])
		pinned.light.energy = 1.2 + STEPS[i] * 2.3
		pinned.circle_sprite.rotation = STEPS[i] * 2.4
		if STEPS[i] > 0.0:
			pinned._charge_particles.emitting = true
			pinned._show_readout()
		else:
			## 第 0 列当基线：完全没充过的样子，用来比对灌灵到底改变了碑身哪一段
			pinned._hide_readout()
	await get_tree().create_timer(0.4, true, false, true).timeout
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
		return
	_shoot("all")
	# 特写按真实出图分辨率换算：窗口 1280×720 时设计坐标要乘 4/3 才裁得准
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 960.0
	for i in range(STEPS.size()):
		_shoot("step%d" % i, Rect2(Vector2((COL_X[i] - 100.0) * k, (ROW_Y - 150.0) * k),
				Vector2(200.0 * k, 240.0 * k)))
	# 再关一轮灯重拍：PointLight2D 会把碑身整个洗亮，灌灵那条液面在灯下量不出来
	for ob in _nodes:
		ob.light.enabled = false
	await get_tree().process_frame
	_shoot("nolit")
	for i in range(STEPS.size()):
		_shoot("dark%d" % i, Rect2(Vector2((COL_X[i] - 100.0) * k, (ROW_Y - 150.0) * k),
				Vector2(200.0 * k, 240.0 * k)))
	await _shoot_hud()
	for i in range(STEPS.size()):
		var shot := _nodes[i]
		print("STEP %d%%  readout_ratio=%.3f  fill=%.3f  shown=%s  arc_ratio=%.3f  label=%s" % [
			int(STEPS[i] * 100), shot.readout_ratio(),
			float(shot.stone_mat.get_shader_parameter("fill_ratio")),
			str(shot.is_readout_shown()), shot._readout_arc.ratio, shot._readout_label.text,
		])
	print("HUD 键 %s / 键面充能条 %s" % [str(_hud._obelisk_btn.get_global_rect()),
			str(_hud._obelisk_bar.get_global_rect())])
	get_tree().quit(0)

## 最后一张给人看键面：真 GameHUD + 真按下（push_input 打键的中心），
## 充到六成半那一档定格 —— 同屏比「阵法上的进度」与「键面上的进度条」是不是一个数
func _shoot_hud() -> void:
	for ob in _nodes:
		ob.light.enabled = true
	_hud = (load("res://scenes/ui/GameHUD.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var target := _nodes[0]
	target.is_player_inside = true
	## 接线照 Main.gd：键面上的条是 charge_progress_updated 驱动的，不接就是根空槽
	target.charge_started.connect(_hud.on_obelisk_charge_started)
	target.charge_progress_updated.connect(_hud.on_obelisk_charge_progress)
	target.charge_cancelled.connect(_hud.on_obelisk_charge_cancelled)
	target.blessing_triggered.connect(_hud.on_obelisk_blessing_triggered)
	_hud.show_obelisk_activation(target)
	await get_tree().create_timer(0.3, true, false, true).timeout
	## push_input 打的是**窗口像素**坐标，而控件矩形是设计分辨率（960×540）下的坐标，
	## canvas_items 拉伸下要乘 content_scale_factor 才落得准（判据那条 headless 跑法里
	## 窗口就是 960×540，比例 1，所以那边不用换算）
	var s := _hud.get_window().content_scale_factor
	var center: Vector2 = _hud._obelisk_btn.get_global_rect().get_center() * s
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = center
	ev.global_position = center
	get_tree().root.push_input(ev)
	await get_tree().create_timer(0.1, true, false, true).timeout
	if not target.is_charging:
		## 拾取没落到键上（窗口/缩放组合变了）就直接走那颗键自己的处理函数：
		## 出图台要的是「按住那一刻键面长什么样」，不是再验一遍拾取（拾取由判据钉）
		print("[INFO] push_input 没落进键面（scale=%.3f），改走 gui_input 同一条处理函数" % s)
		_hud._on_obelisk_btn_input(ev)
	var guard := 0
	while target.readout_ratio() < 0.65 and guard < 600:
		await get_tree().process_frame
		guard += 1
	_shoot("hud")
	# 键面特写要在**还按着**的时候拍：一抬起 stop_charge() 就把条归零、文案回「聚 灵」
	_key_crop()
	ev.pressed = false
	_hud._on_obelisk_btn_input(ev)
	get_tree().root.push_input(ev)
	await get_tree().create_timer(0.3, true, false, true).timeout
	print("HUD shot ratio=%.3f bar=%.3f 按住的键=%s" % [
		target.readout_ratio(), _hud._obelisk_bar.value, str(target.is_charging)])

## 键面特写：连键外一圈底板一起裁，量得出条有没有探出斜切边
func _key_crop() -> void:
	var img := get_viewport().get_texture().get_image()
	var k := float(img.get_width()) / 960.0
	var r: Rect2 = _hud._obelisk_btn.get_global_rect()
	_shoot("hud_key", Rect2(Vector2((r.position.x - 30.0) * k, (r.position.y - 16.0) * k),
			Vector2(180.0 * k, 96.0 * k)))

func _shoot(tag: String, crop: Rect2 = Rect2()) -> void:
	var img := get_viewport().get_texture().get_image()
	if not crop.size.is_zero_approx():
		img = img.get_region(Rect2i(Vector2i(crop.position), Vector2i(crop.size)))
	var path := "/tmp/obelisk_charge_%s.png" % tag
	img.save_png(path)
	print("SAVED ", path, " ", img.get_size())
