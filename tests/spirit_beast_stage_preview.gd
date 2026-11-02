extends Node2D

## 祭坛灵兽「四阶形态」调形台（非判据，不参与绿灯）：并排摆 1~4 阶的灵珑，
## 体型按 BalanceSpiritBeast.stage_body_scale 缩放，剪影按 ProceduralDroneRenderer.stage
## 追加灵尘/双角/灵环/足下地环（2 阶飘带经用户反馈已下线）。供改 _draw_yuan_ling 的阶段分支时直接看形。
## 运行（不能加 --headless，headless 不渲染）：
##   $G --path . res://tests/SpiritBeastStagePreview.tscn
## 附带 --shot 时渲染 2 秒后存一张整图到 /tmp/spirit_beast_stages.png 并退出。

const BG_COL := Color(0.07, 0.10, 0.16)
const GROUND_Y := 360.0
const X_STEP := 220.0

var _cells: Array[ProceduralDroneRenderer] = []
var _t: float = 0.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COL
	bg.size = Vector2(960, 540)
	add_child(bg)

	var title := Label.new()
	title.text = "祭坛灵兽 · 四阶形态调形台（ProceduralDroneRenderer.stage）"
	title.position = Vector2(40, 16)
	GameStyle.label(title, 14, GameStyle.CHALK, 0, GameStyle.INK, true)
	add_child(title)

	# 地面基准线：四只灵兽同一落地点，方便比较体型
	var floor_line := Line2D.new()
	floor_line.points = PackedVector2Array([Vector2(40, GROUND_Y + 16), Vector2(920, GROUND_Y + 16)])
	floor_line.width = 1.0
	floor_line.default_color = Color(0.28, 0.38, 0.50, 0.55)
	add_child(floor_line)

	for i in range(4):
		var stage: int = i + 1
		var x: float = 140.0 + X_STEP * float(i)
		var r := ProceduralDroneRenderer.new()
		r.kind = ProceduralDroneRenderer.DroneKind.YUAN_LING
		r.stage = stage
		r.palette_idx = 0
		r.speed_ratio = 0.35
		r.hp_ratio = 1.0
		var body_scale: float = GameBalance.spirit_beast_body_scale(stage)
		r.scale = Vector2(body_scale, body_scale)
		r.position = Vector2(x, GROUND_Y)
		add_child(r)
		_cells.append(r)

		var lbl := Label.new()
		lbl.text = "%d 阶 · %s" % [stage, _stage_name(stage)]
		lbl.position = Vector2(x - 80.0, GROUND_Y + 74.0)
		lbl.size = Vector2(160, 24)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		GameStyle.label(lbl, 14, GameStyle.CHALK, 0, GameStyle.INK, true)
		add_child(lbl)

	if DisplayServer.get_name() == "headless":
		print("SpiritBeastStagePreview: headless 无渲染意义，直接退出")
		get_tree().quit(0)
		return
	if "--shot" in OS.get_cmdline_user_args():
		_auto_shot()

func _stage_name(stage: int) -> String:
	match stage:
		1:
			return "灵珑"
		2:
			return "灵兽"
		3:
			return "精怪"
		_:
			return "巨灵"

func _auto_shot() -> void:
	await get_tree().create_timer(2.0, true, false, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/spirit_beast_stages.png")
	print("SAVED: /tmp/spirit_beast_stages.png")
	get_tree().quit(0)

func _process(delta: float) -> void:
	_t += delta
	for i in range(_cells.size()):
		var r := _cells[i]
		r.speed_ratio = 0.25 + 0.20 * sin(_t * 2.0 + float(i))
		r.bank_angle = deg_to_rad(6.5) * 0.5 * sin(_t * 1.1 + float(i) * 0.7)
		r.charge_ratio = 0.35 + 0.35 * sin(_t * 2.4 + float(i))
