extends Node2D

## 随行灵兽调形台（非判据，不参与绿灯）：上排 7 只常态，下排 7 只受激闪白态，
## 供编辑器/真机直接看形 —— 调 SpiritPet._draw / _draw_decor 的形准与动态节奏时改完重开即可。
## 运行（不能加 --headless，headless 不渲染）：
##   $G --path . res://tests/SpiritPetPreview.tscn
## 附带 --shot 用户参数时：渲染 2 秒后存一张整图到 /tmp 并退出（供远端出图审形）

const BG_COL := Color(0.07, 0.10, 0.16)

var _t: float = 0.0
var _flash_row: Array[SpiritPet] = []
var _shot_frames: int = -1

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COL
	bg.size = Vector2(960, 540)
	add_child(bg)

	var title := Label.new()
	title.text = "随行灵兽调形台（SpiritPet：上排常态 / 下排受激）"
	title.position = Vector2(40, 16)
	GameStyle.label(title, 14, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title)

	var ids: Array = PetData.all_ids()
	for i in range(ids.size()):
		var col := i % 7
		# 上排常态
		var pos := Vector2(90 + col * 130, 190)
		_spawn_pet(String(ids[i]), i, pos)
		# 下排受激闪白态
		var pos2 := Vector2(90 + col * 130, 400)
		_flash_row.append(_spawn_pet(String(ids[i]), i, pos2))
		# 标签
		var def := PetData.get_def(String(ids[i]))
		var lbl := Label.new()
		lbl.text = String(def.get("name", ids[i]))
		lbl.position = pos + Vector2(-30, 40)
		GameStyle.label(lbl, 11, GameStyle.PAPER_DIM)
		add_child(lbl)

	if DisplayServer.get_name() == "headless":
		print("SpiritPetPreview: headless 无渲染意义，直接退出")
		get_tree().quit(0)
		return
	if "--shot" in OS.get_cmdline_user_args():
		_shot_frames = 120

## 生成一只静态展示的灵兽（不传主人：_physics_process 找不到 target 会原地待命，正好用于摆拍）
func _spawn_pet(p_id: String, idx: int, pos: Vector2) -> SpiritPet:
	var pet := SpiritPet.new()
	pet.setup(p_id, idx, 7, null)
	pet.position = pos
	add_child(pet)
	return pet

func _process(delta: float) -> void:
	_t += delta
	# 下排周期性受激闪白（0.3s 亮 / 1.4s 灭）
	var phase: float = fposmod(_t, 1.7)
	for pet in _flash_row:
		pet._flash_timer = 0.15 if phase < 0.3 else 0.0
	if _shot_frames > 0:
		_shot_frames -= 1
		if _shot_frames == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png("/tmp/spirit_pet_preview.png")
			print("SAVED: /tmp/spirit_pet_preview.png")
			get_tree().quit(0)
