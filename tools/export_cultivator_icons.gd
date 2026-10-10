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
	"duobao"
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
