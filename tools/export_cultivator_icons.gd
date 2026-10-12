extends Node2D

## 导出 9 大可玩道统角色的全新纯矢量 96x96 头像图标
## 直接取自 ProceduralCultivatorView 矢量模型正面视角

const CULTIVATORS := [
	"jianchi",
	"shiyue",
	"fuzhen",
	"jinsuanpan",
	"meiying",
	"dubi",
	"kuangzhan",
	"duoshe",
	"duobao",
	"lingzhifu",
	"leifa",
	"jiguan",
	"yaowang",
	"shoucainu",
	"shixue",
	"fuxiu",
	"bawang",
]

func _ready() -> void:
	_export_all_icons()

func _export_all_icons() -> void:
	for cid in CULTIVATORS:
		var svp := SubViewport.new()
		svp.size = Vector2i(96, 96)
		svp.transparent_bg = true
		svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(svp)

		var pview := ProceduralCultivatorView.new()
		pview.setup_character_id(cid)
		# 居中放置，缩放到 96x96 最佳头部+身躯视角，保留触角顶部呼吸边距
		pview.position = Vector2(48, 56)
		pview.scale = Vector2(1.5, 1.5)
		svp.add_child(pview)

		# 驯兽师专属点缀：肩侧一只青蓝护蝶，呼应"开局自带护蝶"（仅进图标）
		if cid == "fuzhen":
			var fly := Node2D.new()
			fly.position = Vector2(72, 24)
			for wing_dx in [-1.0, 1.0]:
				var wing := Polygon2D.new()
				wing.polygon = PackedVector2Array([
					Vector2(0, 0), Vector2(wing_dx * 6.0, -4.5), Vector2(wing_dx * 7.5, 2.0)
				])
				wing.color = Color(0.45, 0.85, 1.0, 0.9)
				fly.add_child(wing)
			var fly_body := Polygon2D.new()
			fly_body.polygon = PackedVector2Array([
				Vector2(-1.0, -3.0), Vector2(1.0, -3.0), Vector2(0.8, 3.0), Vector2(-0.8, 3.0)
			])
			fly_body.color = Color(0.10, 0.30, 0.45)
			fly.add_child(fly_body)
			svp.add_child(fly)

		await get_tree().process_frame
		await get_tree().process_frame

		var tex := svp.get_texture()
		if tex != null:
			var img := tex.get_image()
			if img != null and not img.is_empty():
				var out_path := "assets/art/cultivator_%s_icon.png" % cid
				img.save_png(out_path)
				print("[CultivatorIcon] 成功导出矢量头像: %s" % out_path)

		svp.queue_free()

	print("[CultivatorIcon] 全部 9 大道统头像导出完毕！")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
