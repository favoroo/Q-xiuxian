extends Node2D

## 祭坛灵兽（灵珑·焰形灵魄）调形台（非判据，不参与绿灯）：并排摆 悬停 / 巡航 / 濒死 / 扑击
## 四态 + 左朝向镜像 + 濒死巡航混合 + 出场辉光，供编辑器/真机直接看形 —— 画得好看不好看是
## 纯眼睛的活，调 ProceduralDroneRenderer._draw_yuan_ling() 的形准与动态节奏时改完重开即可。
## 运行（不能加 --headless，headless 不渲染）：
##   $G --path . res://tests/SpiritBeastPreview.tscn

const BG_COL := Color(0.07, 0.10, 0.16)

var _t: float = 0.0
var _cruise: ProceduralDroneRenderer = null
var _lunge: ProceduralDroneRenderer = null
var _charge: ProceduralDroneRenderer = null
var _spawn: ProceduralDroneRenderer = null
var _spawn_cd: float = 0.0
var _lunge_base: Vector2 = Vector2.ZERO
var _lunge_cd: float = 1.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COL
	bg.size = Vector2(960, 540)
	add_child(bg)

	var title := Label.new()
	title.text = "祭坛灵兽 · 灵珑调形台（ProceduralDroneRenderer.YUAN_LING）"
	title.position = Vector2(40, 16)
	GameStyle.label(title, 14, GameStyle.PAPER, 0, GameStyle.INK, true)
	add_child(title)

	_cell("悬停待机 speed=0", Vector2(130, 210), 1.0, 1.0)
	_cruise = _cell("巡航 speed 脉动 + bank", Vector2(350, 210), 1.0, 1.0)
	_cell("濒死 hp=20%", Vector2(570, 210), 1.0, 0.2)
	_lunge_base = Vector2(790, 210)
	_lunge = _cell("扑击（周期 lunge）", _lunge_base, 1.0, 1.0)
	_charge = _cell("蓄力 charge 脉动", Vector2(130, 410), 1.0, 1.0)
	_cell("左朝向镜像", Vector2(350, 410), -1.0, 1.0)
	_cell("濒死 35% + 巡航混合", Vector2(570, 410), -1.0, 0.35)
	_spawn = _cell("出场辉光（周期重现）", Vector2(790, 410), 1.0, 1.0)

	if DisplayServer.get_name() == "headless":
		print("SpiritBeastPreview: headless 无渲染意义，直接退出")
		get_tree().quit(0)
		return
	# 附带 --shot 用户参数时：渲染 2 秒后存一张整图到 /tmp 并退出（供远端出图审形）
	if "--shot" in OS.get_cmdline_user_args():
		_auto_shot()

func _auto_shot() -> void:
	await get_tree().create_timer(2.0, true, false, true).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/spirit_beast_preview.png")
	print("SAVED: /tmp/spirit_beast_preview.png")
	get_tree().quit(0)

func _process(delta: float) -> void:
	_t += delta
	if _cruise != null:
		_cruise.speed_ratio = 0.65 + 0.35 * sin(_t * 2.2)
		_cruise.bank_angle = deg_to_rad(6.5) * 0.6 * sin(_t * 0.9)
	if _charge != null:
		_charge.charge_ratio = 0.5 + 0.5 * sin(_t * 2.5)
	if _spawn != null:
		_spawn_cd -= delta
		if _spawn_cd <= 0.0:
			_spawn_cd = 1.8
			_spawn.spawn_glow = 1.0
	if _lunge != null:
		_lunge.speed_ratio = 0.4
		_lunge_cd -= delta
		if _lunge_cd <= 0.0:
			_lunge_cd = 1.6
			# 复现 SpiritBeast._try_fire 的吐息小后坐（渲染器逆弹道顿一下再弹回）
			_lunge.position = _lunge_base + Vector2(-5.0, -2.0)
			var tw := create_tween()
			tw.tween_property(_lunge, "position", _lunge_base, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	# 两排基准线：灵雾贴地处，用来目测悬浮高度与影子落点
	for y in [262.0, 462.0]:
		draw_line(Vector2(40, y), Vector2(920, y), Color(0.55, 0.85, 1.0, 0.12), 1.0, true)

func _cell(title: String, pos: Vector2, face: float, hp: float) -> ProceduralDroneRenderer:
	var r := ProceduralDroneRenderer.new()
	r.kind = ProceduralDroneRenderer.DroneKind.YUAN_LING
	r.position = pos
	r.scale.x = face
	r.hp_ratio = hp
	add_child(r)
	var lbl := Label.new()
	lbl.text = title
	lbl.position = pos + Vector2(-64, 40)
	GameStyle.label(lbl, 10, GameStyle.PAPER)
	add_child(lbl)
	return r
