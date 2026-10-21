extends Node

## 受益装备热区出图台（非判据）：把「点图标弹装备详解」这一步真渲染一遍，存 PNG 用眼睛验收。
## 运行（不能加 --headless，headless 不渲染、拿不到图）：
##   $G --path . res://tests/BenefitTipPreview.tscn      # 产物 /tmp/benefit_tip_<档>.png
##
## 为什么要有它：判据量的是「这一枪送到了谁身上、弹出的卡标题对不对、卡整块在不在视口内」，
## 量不了「这排格子像不像一颗按得动的键」「弹出来的卡有没有压住别的卡」。
## 摆位与格子尺寸不另编一套：走 LevelUpDialog 自己的 _layout_for_viewport() 与 BF_CELL_*。
## 六把法器凑满上阵，让窄那一档真走到「格子摊不开要换行」。

const SIZES: Array[Vector2i] = [Vector2i(1536, 690), Vector2i(960, 540)]
const TAGS: Array[String] = ["20_9", "16_9"]
const WEAPONS: Array[String] = [
	"qingyun_sword", "gengjin_feijian", "huoyan_fu", "wanmu_lingfu", "hunyuan_zhong", "lingdie"]
const OFFERS: Array[String] = ["atk_up", "melee_up", "luck_up", "haste_up", "range_up"]

var _holder: Control

func _ready() -> void:
	DisplayServer.window_set_size(SIZES[0])
	await get_tree().process_frame
	_holder = Control.new()
	_holder.name = "PreviewHolder"
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(_holder)
	await _seed()
	for i in range(SIZES.size()):
		DisplayServer.window_set_size(SIZES[i])
		get_tree().root.size = SIZES[i]
		await _settle(3)
		var screen: Vector2 = get_tree().root.get_visible_rect().size
		var node: LevelUpDialog = (load("res://scenes/ui/LevelUpDialog.tscn") as PackedScene)\
			.instantiate() as LevelUpDialog
		node.visible = true
		_holder.add_child(node)
		await _settle(2)
		node._on_alloc_opened()
		get_tree().paused = false
		await get_tree().create_timer(0.8).timeout
		node._select_card(0)
		await get_tree().create_timer(0.4).timeout
		await _settle(2)
		var cells := _cells(node)
		print("===== %s · 设计可视 %.0fx%.0f · 卡宽 %.1f 内宽 %.1f =====" % [
			TAGS[i], screen.x, screen.y, node._card_w,
			LevelUpDialog.card_inner_w(node._card_w)])
		print("  第 1 张卡受益格 %d 颗" % cells.size())
		for ci in range(cells.size()):
			var c := cells[ci]
			print("    %s %s" % [String(c.name), str(c.get_global_rect())])
		if not cells.is_empty():
			node.open_benefit_tip(cells[0], _summary()[0] as Dictionary,
				GameManager.alloc_offers[0])
			await get_tree().create_timer(0.35).timeout
			await _settle(2)
			var tip := DetailTip.live(node)
			if tip != null:
				print("  详情卡 %s 标题「%s」" % [str(tip.card_rect()),
					String(tip.payload.get("title", ""))])
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			var tex := get_viewport().get_texture()
			var img := tex.get_image() if tex != null else null
			if img != null:
				var path := "/tmp/benefit_tip_%s.png" % TAGS[i]
				img.save_png(path)
				print("  SAVED %s %s" % [path, img.get_size()])
		node.queue_free()
		await _settle(3)
	print("\nBENEFIT_TIP_PREVIEW_DONE")
	get_tree().quit(0)

func _seed() -> void:
	GameManager.reset_run()
	GameManager.cultivator_id = "jianchi"
	var p := (load("res://scenes/entities/Player.tscn") as PackedScene).instantiate() as Player
	_holder.add_child(p)
	GameManager.player = p
	await _settle(3)
	for wid in WEAPONS:
		GameManager.add_weapon(wid)
	await _settle(3)
	GameManager.pending_upgrade_points = 2
	GameManager.open_alloc_session()
	var offers: Array[Dictionary] = []
	for uid in OFFERS:
		var d: Dictionary = UpgradeData.get_upgrade_def(uid).duplicate()
		d["border_color"] = UpgradeData.RARITY_COLORS.get(d.get("rarity", "common"), Color.WHITE)
		offers.append(d)
	GameManager.alloc_offers = offers

func _summary() -> Array:
	return GameManager.get_weapons_summary()

func _cells(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	for ch in n.get_children():
		var c := ch as Control
		if c == null:
			continue
		if String(c.name).begins_with("BenefitCell"):
			out.append(c)
		out.append_array(_cells(c))
	return out

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
