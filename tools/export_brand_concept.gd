extends Node2D

## 一次性工具：用游戏内 ProceduralCultivatorView 本体渲染青云剑修正面像，
## 高分辨率导出为 App 图标概念图（assets_raw/images/app_icon_concept.png），
## 供 tools/make_brand_assets.py 重建全套品牌素材。
## 运行（非 headless，需真实渲染上下文）：
##   $G --path . res://tools/ExportBrandConcept.tscn
## 输出：1024² 透明底全身立绘（上半身裁切由 Python 后处理完成）

const OUT_PATH := "assets_raw/images/app_icon_concept.png"
const VIEW := 1024
const SCALE := 14.0          # 角色绘制单位 → 像素 的放大倍数
const ORIGIN := Vector2(512, 628)  # 角色原点（脚底）在画布上的位置：头顶约 40px 边距

func _ready() -> void:
	var svp := SubViewport.new()
	svp.size = Vector2i(VIEW, VIEW)
	svp.transparent_bg = true
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(svp)

	var pview := ProceduralCultivatorView.new()
	pview.setup_character_id("jianchi")
	pview.position = ORIGIN
	pview.scale = Vector2(SCALE, SCALE)
	svp.add_child(pview)

	# 只画 武器|斗篷|头 三层：去地影与周天灵气粒子，图标更干净
	if pview.get("renderer") != null:
		pview.renderer.debug_layers = 4 | 8 | 16

	await get_tree().process_frame
	await get_tree().process_frame

	var tex := svp.get_texture()
	if tex == null:
		push_error("SubViewport 无纹理")
		get_tree().quit(1)
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		push_error("渲染结果为空")
		get_tree().quit(1)
		return
	img.save_png(OUT_PATH)
	print("[BrandConcept] 已导出 %s (%dx%d)" % [OUT_PATH, img.get_width(), img.get_height()])
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
