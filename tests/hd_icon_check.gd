extends Node

## 武器图标 UI 高清变体判据（商店图标二次模糊回归的防再发线）：
##   背景：weapon_*.png 战斗画布必须 48x48（FloatingWeapon 缩放与 WeaponData.tip 剑尖
##   坐标严格绑定 48 坐标系，放大即「战场武器变大」回归），而 UI（商店/加点/背包）
##   槽位 56~64px 放大显示 48px 源就糊。修法 = assets/art/ui/weapon_*.png 128px 变体 +
##   GameStyle.icon_texture_rect 变体优先。本判据钉住四条不变量：
##   1. WeaponData 里每把武器的 icon 指向的战斗画布必须是 48x48（有人手滑改大直接红）
##   2. 有 assets_raw 高清源的武器必须已有 ui/ 128px 变体（防止重导脚本漏跑/漏图）
##   3. GameStyle._hd_icon_path 映射正确：战斗路径→ui 变体；无变体/item/外路径原样回退
##   4. icon_texture_rect 实际装载的是变体纹理（战斗 48 画布不被 UI 复用）
## 运行: godot --headless --path . res://tests/HdIconCheck.tscn
## 退出码 0 且末行 HD_ICON_RESULT: ALL PASS

var _c := TestCheck.new()

func _check(cond: bool, label: String) -> void:
	_c.check(cond, label)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_battle_canvas_is_48()
	_test_hd_variants_exist()
	_test_hd_path_mapping()
	_test_factory_loads_hd()

	if not _c.all_passed():
		print("HD_ICON_RESULT: FAILED (%d failures)" % _c.failures.size())
		get_tree().quit(1)
	else:
		print("HD_ICON_RESULT: ALL PASS (%d checks)" % _c.passed)
		get_tree().quit(0)

## 1. 所有武器战斗画布保持 48x48——tip 坐标系的地基，谁改大谁修
func _test_battle_canvas_is_48() -> void:
	var icons := _collect_icons()
	_check(icons.size() > 0, "WeaponData 至少导出一把武器的 icon（实得 %d 把）" % icons.size())
	for path: String in icons:
		var tex := load(path) as Texture2D
		if tex == null:
			_check(false, "武器贴图可加载 %s" % path)
			continue
		_check(tex.get_width() == 48 and tex.get_height() == 48,
			"战斗画布 48x48 %s（实得 %dx%d）" % [path, tex.get_width(), tex.get_height()])

## 从 DEFS 收集全部 icon 路径（含 sun_orb 这类非 weapon_ 前缀的法球）
func _collect_icons() -> Array[String]:
	var out: Array[String] = []
	for id: String in WeaponData.DEFS:
		var icon := String(WeaponData.DEFS[id].get("icon", ""))
		if not icon.is_empty() and not out.has(icon):
			out.append(icon)
	return out

## 2. 每把武器的 UI 图标必须已有 ui/ 128px 变体。
##    ⚠ 尺子读 assets/art/ui/ 的【实际存在性】，不再拿 gitignored 的 assets_raw/images/ 判源
##    （旧尺子用不入库目录判存在性，干净检出时把 57 张有变体的武器全判成"无源回退"假红）。
##    2026-10-21 起 70 把武器 UI 图标统一由 tests/weapon_icon_export 导出，全有变体，故无白名单。
func _test_hd_variants_exist() -> void:
	for path: String in _collect_icons():
		var hd := GameStyle._hd_icon_path(path)
		_check(hd != path, "武器应有 ui 变体 %s（实得 %s）" % [path, hd])
		if hd != path:
			var tex := load(hd) as Texture2D
			_check(tex != null and tex.get_width() >= 128,
				"ui 变体 ≥128px %s（实得 %s）" % [hd, "null" if tex == null else str(tex.get_width())])

## 3. _hd_icon_path 映射规则：战斗武器→变体；item/未知/非 art 路径→原样
func _test_hd_path_mapping() -> void:
	_check(GameStyle._hd_icon_path("") == "", "空路径原样返回")
	_check(GameStyle._hd_icon_path("res://assets/art/item_dianjin_jue.png")
		== "res://assets/art/item_dianjin_jue.png", "item 图标不找变体（原样回退）")
	_check(GameStyle._hd_icon_path("res://assets/art/ui/weapon_sword.png")
		== "res://assets/art/ui/weapon_sword.png", "已是 ui/ 路径不再二次映射")
	_check(GameStyle._hd_icon_path("res://assets/audio/bgm/bgm_shop.mp3")
		== "res://assets/audio/bgm/bgm_shop.mp3", "非 art 路径原样返回")
	var mapped := GameStyle._hd_icon_path("res://assets/art/weapon_sword.png")
	_check(mapped == "res://assets/art/ui/weapon_sword.png",
		"武器战斗路径映射到 ui 变体（实得 %s）" % mapped)
	# item 图标永不带 ui/ 变体（assets/art/ui/ 只有 weapon_*），映射必原样回退
	var item_fallback := GameStyle._hd_icon_path("res://assets/art/item_jubaopen.png")
	_check(item_fallback == "res://assets/art/item_jubaopen.png",
		"item 图标无变体、原样回退（实得 %s）" % item_fallback)

## 4. 工厂实际装载变体纹理：武器卡拿到的 texture 宽度是 128 而不是 48
func _test_factory_loads_hd() -> void:
	var tr := GameStyle.icon_texture_rect("res://assets/art/weapon_sword.png")
	var tex := tr.texture as Texture2D
	_check(tex != null and tex.get_width() == 128,
		"icon_texture_rect 装载 128px 变体（实得 %s）"
		% ("null" if tex == null else str(tex.get_width())))
	tr.queue_free()
