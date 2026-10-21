extends Node

## 新手指南实机截图台（非判据）：驱动真实游戏到各状态，viewport 截 PNG 供 TutorialDialog 当教学配图。
## 运行（不能加 --headless，headless 不渲染拿不到图）：
##   $G --path . res://tools/TutorialShot.tscn
## 产物 /tmp/tutorial_shots/*.png，验收后拷入 assets_raw/tutorial_shots/（源）与 assets/art/tutorial/（引用）。

const OUT_DIR := "/tmp/tutorial_shots"

## 出图色彩校准：桌面默认 HDR2D + ACES 会把画面压暗、把品红偏成纯红，
## 与手机（移动端强制 LDR）真机观感不一致。开拍前统一切 LDR 直出，见 capture_ldr.gd。
const CaptureLdr = preload("res://tools/capture_ldr.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# 主题色钉死为游戏默认档（现为主行动色「荧绿」）：不跟着本机 user://settings.cfg 走，
	# 否则同一脚本在不同机器上会截出品红/天青版，教学配图与站点截图就和游戏对不上了。
	# 只调 GameStyle 原地换色，不写 SettingsManager 存档位（玩家自选色不许被工具改掉）。
	GameStyle.apply_theme_color(SettingsManager.THEME_DEFAULT)
	# 窗口钉到桌面调试口径 960×540（AGENTS.md）：与设计分辨率 1:1，避掉 1280×720 override 窗口下
	# 视口外圈露白底的问题（shop/alloc 弹窗截过一圈白边，2026-10-11）。
	DisplayServer.window_set_size(Vector2i(960, 540))
	# 真实主场景：UILayer/HUD/祭坛/宝箱/商店/悟道全套都在里面
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 跳过开始菜单直接开局（不走 _on_start_pressed，避开新手指南门控）
	main.get_node("UILayer/StartMenu").visible = false
	# StageBackdrop 是选人链路的纯黑幕布（Main._setup_stage_backdrop 开局即显示）：
	# 不关掉它，field/combat 两帧会被整屏黑幕盖住，截出来是纯黑（2026-10-21 实测踩过）。
	# 与 Main.resume_from_save 同口径：正式开局后由对局接管，幕布隐藏。
	var backdrop := main.get_node_or_null("UILayer/StageBackdrop") as Control
	if backdrop != null:
		backdrop.visible = false
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	get_tree().paused = false

	# 出图色彩校准（切 LDR 直出 + LDR 起辉阈值）：必须在开局后、首拍截图前，
	# 否则桌面 HDR2D/ACES 会把场景拍得又暗又红（与手机真机不符）。切完等两帧让帧缓冲重建。
	CaptureLdr.apply(get_viewport(), main)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. 场景：第 1 波进行中，中央聚灵阵在画内（等开场横幅淡掉）
	# 摇杆平时只在手指按下的位置浮出（VirtualJoystick._start_joystick），静态出图看不到它；
	# 但这一页讲的正是「左下摇杆走位」——走真实入口把底座点亮在左下，图文才对得上。
	_show_joystick(main)
	await get_tree().create_timer(3.0).timeout
	await _snap("shot_field.png")

	# 2. 战斗：敌潮围拢 + HUD + 右下神通按钮 + 摇杆
	await get_tree().create_timer(5.0).timeout
	_show_joystick(main)
	await _snap("shot_combat.png")

	# 3. 羁绊：塞两件火系点亮加成，开属性面板（右侧羁绊栏）
	GameManager.add_weapon("chiyan_dao")
	GameManager.add_weapon("huoyan_fu")
	await get_tree().process_frame
	var stats: Control = main.get_node("UILayer/PlayerStatsDialog")
	stats.open(false)
	await get_tree().create_timer(0.7).timeout
	await _snap("shot_synergy.png")
	stats.visible = false
	get_tree().paused = false
	await get_tree().process_frame

	# 4. 商店：roll_shop 不发 shop_opened 信号（那由波次状态机发），像 shop_layout_preview
	#    一样直调 _on_shop_opened()（锁定/重掷/出战/陈列星标可见）
	GameManager.add_spirit_stones(300)
	GameManager.roll_shop(true)
	var shop: Control = main.get_node("UILayer/WaveShop")
	shop._on_shop_opened()
	await get_tree().create_timer(0.9).timeout
	await _snap("shot_shop.png")
	shop.visible = false
	get_tree().paused = false
	await get_tree().process_frame

	# 5. 悟道：攒 5 点开加点会（5 张候选 + 免费刷新按钮）
	GameManager.pending_upgrade_points = 5
	GameManager.open_alloc_session()
	await get_tree().create_timer(0.9).timeout
	await _snap("shot_alloc.png")

	print("TUTORIAL_SHOTS_DONE")
	get_tree().quit(0)

## 出图专用：把摇杆底座摆到左下常见握持位并点亮（正常游戏里它只在手指按下处浮出，
## 静态截图拍不到；本页文案讲「左下摇杆走位」，缺了它图文对不上）。只改显示，不参与判定。
func _show_joystick(main: Node) -> void:
	var joy = main.get_node_or_null("UILayer/VirtualJoystick")
	if joy == null:
		return
	joy.visible = true
	var base: Control = joy.get_node_or_null("Base")
	if base == null:
		return
	var vp := get_viewport().get_visible_rect().size
	base.visible = true
	base.global_position = Vector2(vp.x * 0.15, vp.y * 0.86) - base.size * 0.5
	var knob: Control = joy.get_node_or_null("Base/Knob")
	if knob != null:
		knob.position = (base.size - knob.size) * 0.5
	joy.modulate.a = 0.85
	base.queue_redraw()
	if knob != null:
		knob.queue_redraw()

func _snap(fname: String) -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		print("SHOT skip (headless) ", fname)
		return
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT FAIL(null) ", fname)
		return
	img.save_png(OUT_DIR + "/" + fname)
	print("SHOT saved ", fname)
