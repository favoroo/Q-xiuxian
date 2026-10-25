extends Node

## 魔君血条现场预览台（非判据）：把 HUD 真身摆进 SubViewport，喂一次 boss_hp_changed 截整屏 + 底部放大图。
## 运行（**不能加 --headless**，headless 不渲染拿不到图）：
##   $G --path . res://tests/BossBarPreview.tscn
## 产物 /tmp/boss_bar_shots/{full,full_p2}.png + {full,full_p2}_bar.png（底部 120 高放大 3 倍）。
##
## 为什么值得单独立一台：血条摆位是 2026-10-25 用户报「压在屏幕中间挡住东西」改的，
## 判据只能断言 rect 落在屏底，量不到「它到底挡不挡视野、和右下技能键离多远」。
## 换屏比/换分辨率时跑一次，出图一眼就能确认没回到屏心。
##
## 为什么走 SubViewport 而不是抓主窗口纹理：本机窗口渲染抓图恒黑（连历史脚本同样黑），
## 而 SubViewport + UPDATE_ALWAYS 是仓库里已被 StartMenuTagPreview 等预览台验证过的路径。

const OUT_DIR := "/tmp/boss_bar_shots"
## 血条区放大倍率：34 高的条子在 960×540 原图里读不出细节
const ZOOM := 3
## 底部裁窗高（设计单位）：够装下血条 + 手势条余量 + 一点战场
const BOTTOM_CROP := 120.0
const SHOT_SIZES: Array[Vector2i] = [Vector2i(960, 540), Vector2i(1204, 540)]

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameManager.cultivator_id = "jianchi"
	GameManager.start_run("qingyun_sword")
	for sz in SHOT_SIZES:
		var vp := SubViewport.new()
		vp.size = sz
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.disable_3d = true
		add_child(vp)

		# 战场底：纯 Ink + 一块「敌潮」色块，血条压不压视野一眼可辨
		var bg := ColorRect.new()
		bg.color = GameStyle.INK
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vp.add_child(bg)

		var hud := (load("res://scenes/ui/GameHUD.tscn") as PackedScene).instantiate() as GameHUD
		hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vp.add_child(hud)
		await get_tree().process_frame
		await get_tree().process_frame

		# 满血登场：走真信号，血条按生产方式登场（含滑入补间）
		GameManager.boss_hp_changed.emit(50000.0, 50000.0, "火焰Boss")
		await get_tree().create_timer(0.8).timeout
		await _grab(vp, "full_%d" % sz.x, sz.x)

		# 半血狂暴态：填充转紫 + 刻度闪，读得清两种状态的观感差
		GameManager.boss_hp_changed.emit(16000.0, 50000.0, "火焰Boss")
		await get_tree().create_timer(0.8).timeout
		await _grab(vp, "full_%d_p2" % sz.x, sz.x)

		vp.queue_free()
		await get_tree().process_frame
	print("已出图 → %s（full / full_p2 各配 _bar.png 底部放大 %d 倍）" % [OUT_DIR, ZOOM])
	get_tree().quit(0)

func _grab(vp: SubViewport, tag: String, w: int) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		print("[%s] 截图失败（纹理为空）" % tag)
		return
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	var f := float(img.get_width()) / float(w)
	var crop := img.get_region(Rect2i(
		Vector2i(0, int(img.get_height() - BOTTOM_CROP * f)),
		Vector2i(img.get_width(), int(BOTTOM_CROP * f))))
	crop.resize(crop.get_width() * ZOOM, crop.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	crop.save_png("%s/%s_bar.png" % [OUT_DIR, tag])
	print("%s ⇒ 屏 %dx%d" % [tag, img.get_width(), img.get_height()])
