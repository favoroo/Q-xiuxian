extends Node

## 非判据现场工具：灵石阁陈列行（上阵 + 背包 + 法宝）横滑两相出图。
## 运行（别加 --headless，要真渲染）：
##   $G --path . res://tests/ShopRowScrollPreview.tscn --resolution 1202x540
## 出图：/tmp/shop_row_left.png（刚开面板，滑到最左）与 /tmp/shop_row_right.png（划到底）。
## 看三件事：① 满仓最右那几件（法宝徽位）划到底看不看得见；② 滑到最左时首格有没有被
## 滚动区边界削掉；③ 那根滑条露脸的强度合不合这块面板的气质（GameStyle.scrollable 调的就是它）。

const OUT_L := "/tmp/shop_row_left.png"
const OUT_R := "/tmp/shop_row_right.png"

var _shop: WaveShop

func _ready() -> void:
	get_tree().root.size = Vector2i(1202, 540)
	GameManager.reset_run()
	GameManager.spirit_stones = 1256
	GameManager.wave_number = 12
	GameManager.roll_shop(true)
	_seed_full()
	_shop = load("res://scenes/ui/WaveShop.tscn").instantiate()
	add_child(_shop)
	await get_tree().process_frame
	_shop._on_shop_opened()
	get_tree().paused = false
	await _settle(20)
	await _shot(OUT_L)
	_shop.owned_scroll.scroll_horizontal = 100000
	await _settle(12)
	await _shot(OUT_R)
	var row: HBoxContainer = _shop.owned_container
	var scroll: ScrollContainer = _shop.owned_scroll
	print("SHOP_ROW_PREVIEW 陈列行 内容宽=%.0f 可视宽=%.0f 可滑=%d 滑条高=%.0f → %s / %s" % [
		row.get_combined_minimum_size().x, scroll.size.x, scroll.scroll_horizontal,
		scroll.get_h_scroll_bar().size.y, OUT_L, OUT_R])
	get_tree().quit(0)

## 满仓样本：headless 不建 Player，与 LayoutCheck / ShopRowScrollCheck 同一手法
## （drones 当上阵、stash 当背包、items 当法宝）。
func _seed_full() -> void:
	GameManager.drones.clear()
	for i in range(WeaponData.MAX_SLOTS):
		GameManager.drones.append({"id": "lingdie", "star": 1})
	GameManager.stash.clear()
	for wid in ["qingyun_sword", "huoyan_fu", "chiyan_dao", "liuye_feidao", "wulei_paizi",
			"gengjin_feijian", "bajiao_fan", "fantian_yin", "fentian_baodeng"]:
		var wdef: Dictionary = WeaponData.get_def(wid)
		if wdef.is_empty():
			continue
		GameManager.stash.append({"id": wid, "name": wdef.get("name", "?"), "star": 1,
			"icon": wdef.get("icon", ""), "tag": wdef.get("tag", "")})
	GameManager.items.clear()
	for id in ItemData.all_ids():
		GameManager.add_item(String(id))
	GameManager.recalc_synergies()

func _shot(path: String) -> void:
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)

func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
