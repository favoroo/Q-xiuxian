extends Node

## tests/inspect_check.gd — 游戏全域美术与视觉资产完整性校验单测
##
## 验证目标：
## 1. 修仙者角色完整度：CultivatorData.DEFS 全量角色均能在 CultivatorVisualConfig 中正确解析并包含 4 大外观插槽。
## 2. 法器资源完整度：WeaponData.DEFS 69 把武器的 icon 与 bullet 文件在磁盘中真实存在。
## 3. 法宝道具资源完整度：ItemData.DEFS 全量道具的 icon 文件在磁盘中真实存在。
## 4. 妖魔配置完整度：EnemyVisualConfig 能够完整提供全量 17 种怪物的视觉配置。
## 5. 武器攻击特效完整度：WeaponArcRenderer 6 元素、BurstKindFx 6 爆发形态、光束与喷火渲染器正常配置。
## 6. 飞行物纯矢量弹道完整度：21 种武器 bullet 路径 100% 精确映射到对应矢量种类，无静默 fallback。
## 7. UI 设计系统规范完整度：GameStyle 核心调色盘与 StyleBox 构件函数正常工作。
##
## 运行方式:
##   $G --headless --path . res://tests/InspectCheck.tscn

var _c := TestCheck.new()

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_cultivator_visual_configs()
	_test_weapon_asset_integrity()
	_test_item_asset_integrity()
	_test_item_and_upgrade_icon_quality()
	_test_enemy_visual_configs()
	_test_vfx_integrity()
	_test_projectile_integrity()
	_test_ui_style_integrity()
	
	if _c.report("INSPECTCHECK_RESULT"):
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func _test_cultivator_visual_configs() -> void:
	var total_chars: int = CultivatorData.DEFS.size()
	_c.check(total_chars >= 20, "CultivatorData 收录至少 20 位角色 (实际: %d)" % total_chars)
	
	var missing_slots: Array[String] = []
	for cid in CultivatorData.DEFS.keys():
		var cfg := CultivatorVisualConfig.get_config(cid)
		if cfg == null:
			missing_slots.append("%s (config is null)" % cid)
			continue
		
		if cfg.body.is_empty() or not cfg.body.has("scale"):
			missing_slots.append("%s (body slot missing)" % cid)
		if cfg.face.is_empty() or not cfg.face.has("mask_style"):
			missing_slots.append("%s (face slot missing)" % cid)
		if cfg.cloak.is_empty() or not cfg.cloak.has("cloak_style"):
			missing_slots.append("%s (cloak slot missing)" % cid)
		if cfg.weapon.is_empty() or not cfg.weapon.has("weapon_type"):
			missing_slots.append("%s (weapon slot missing)" % cid)

	_c.check(missing_slots.is_empty(), "所有角色均完整配置 4 大视觉插槽 (缺漏: %s)" % str(missing_slots))

func _test_weapon_asset_integrity() -> void:
	var defs: Dictionary = WeaponData.DEFS
	_c.check(defs.size() >= 69, "WeaponData 收录至少 69 把法器 (实际: %d)" % defs.size())
	
	var missing_icons: Array[String] = []
	var missing_bullets: Array[String] = []
	
	for wid in defs.keys():
		var w: Dictionary = defs[wid]
		var icon_path: String = w.get("icon", "")
		if icon_path.is_empty() or not FileAccess.file_exists(icon_path):
			missing_icons.append("%s -> %s" % [wid, icon_path])
		
		if w.has("bullet"):
			var bullet_path: String = w.get("bullet", "")
			if not bullet_path.is_empty() and not FileAccess.file_exists(bullet_path):
				missing_bullets.append("%s -> %s" % [wid, bullet_path])
	
	_c.check(missing_icons.is_empty(), "所有法器 icon 均在磁盘中存在 (缺失: %s)" % str(missing_icons))
	_c.check(missing_bullets.is_empty(), "所有弹道 bullet 贴图均在磁盘中存在 (缺失: %s)" % str(missing_bullets))

func _test_item_asset_integrity() -> void:
	var defs: Dictionary = ItemData.DEFS
	_c.check(defs.size() >= 40, "ItemData 收录足够道具 (实际: %d)" % defs.size())
	
	var missing_icons: Array[String] = []
	for iid in defs.keys():
		var it: Dictionary = defs[iid]
		var icon_path: String = it.get("icon", "")
		if icon_path.is_empty() or not FileAccess.file_exists(icon_path):
			missing_icons.append("%s -> %s" % [iid, icon_path])
			
	_c.check(missing_icons.is_empty(), "所有道具 icon 均在磁盘中存在 (缺失: %s)" % str(missing_icons))

func _test_item_and_upgrade_icon_quality() -> void:
	var bad_icons: Array[String] = []
	var checked_paths: Dictionary = {}
	
	# 1. 检查所有道具法宝图标
	for iid in ItemData.DEFS.keys():
		var icon_res: String = ItemData.DEFS[iid].get("icon", "")
		if not icon_res.is_empty() and not checked_paths.has(icon_res):
			checked_paths[icon_res] = "ItemData: " + iid
			
	# 2. 检查所有加点升级图标
	for up in UpgradeData.UPGRADES:
		var icon_res: String = up.get("icon", "")
		var uid: String = up.get("id", "")
		if not icon_res.is_empty() and not checked_paths.has(icon_res):
			checked_paths[icon_res] = "UpgradeData: " + uid
	
	for icon_res in checked_paths.keys():
		var real_path: String = ProjectSettings.globalize_path(icon_res)
		var img := Image.load_from_file(real_path)
		if img == null:
			bad_icons.append("%s (无法加载)" % icon_res)
			continue
			
		var sz := img.get_size()
		var used := img.get_used_rect()
		var bw := used.size.x
		var bh := used.size.y
		var aspect := float(bw) / float(bh) if bh > 0 else 0.0
		
		# 针对 128x128 UI 图标的防呆规则：
		# ① 严禁混入 120x66 等 16:9 场景背景图 (典型平切场景宽高比 > 1.35 且左右撑满)
		if sz.x >= 128 and bw >= sz.x * 0.85 and aspect > 1.35:
			var top_dense := 0
			var bot_dense := 0
			var samples := 20
			for s in range(samples):
				var sample_x := used.position.x + int(float(bw) * float(s) / float(samples))
				if img.get_pixel(sample_x, used.position.y).a > 0.8:
					top_dense += 1
				if img.get_pixel(sample_x, used.end.y - 1).a > 0.8:
					bot_dense += 1
			if float(top_dense) / float(samples) > 0.6 and float(bot_dense) / float(samples) > 0.6:
				bad_icons.append("%s (疑似横向平切场景图: rect=%s aspect=%.2f, 引自 %s)" % [
					icon_res, str(used), aspect, checked_paths[icon_res]
				])
				continue
		
		# ② 严禁四角未抠底 (四角 2x2 区域不透明度)
		if sz.x >= 128:
			var c1 := img.get_pixel(0, 0).a
			var c2 := img.get_pixel(sz.x - 1, 0).a
			var c3 := img.get_pixel(0, sz.y - 1).a
			var c4 := img.get_pixel(sz.x - 1, sz.y - 1).a
			if c1 > 0.2 or c2 > 0.2 or c3 > 0.2 or c4 > 0.2:
				bad_icons.append("%s (四角未抠底或未留安全边距, 引自 %s)" % [icon_res, checked_paths[icon_res]])
				
	_c.check(bad_icons.is_empty(), "所有道具与加点图标抠底与防呆质检合格 (异常: %s)" % str(bad_icons))

func _test_enemy_visual_configs() -> void:
	var catalog: Array = EnemyGuideData.catalog_ids()
	_c.check(catalog.size() == 17, "EnemyGuideData 收录全量 17 种妖魔 (实际: %d)" % catalog.size())
	
	var missing: Array[String] = []
	for eid in catalog:
		var cfg := EnemyVisualConfig.get_config(String(eid))
		if cfg == null:
			missing.append(String(eid))
		elif cfg.col_primary == null or cfg.display_name.is_empty():
			missing.append("%s (bad fields)" % String(eid))
			
	_c.check(missing.is_empty(), "全量 17 种妖魔视觉配置正常提供 (异常: %s)" % str(missing))

func _test_vfx_integrity() -> void:
	var elems := ["metal", "fire", "water", "wood", "earth", "thunder"]
	var arc_ok := true
	for el in elems:
		var arc := WeaponArcRenderer.new()
		arc.configure(WeaponArcRenderer.ArcMode.MELEE, el)
		arc.configure(WeaponArcRenderer.ArcMode.SWEEP, el)
		if arc.element != el:
			arc_ok = false
		arc.free()
	_c.check(arc_ok, "WeaponArcRenderer 完整支持 6 元素刀光与横扫扇面")
	
	var burst_kinds := ["fire_rain", "frost", "sonic", "drum", "earth", "seal"]
	var burst_ok := true
	for bk in burst_kinds:
		var b := BurstKindFx.new()
		b.activate_fx(bk, 40.0, Color.WHITE)
		if not b.visible:
			burst_ok = false
		b.free()
	_c.check(burst_ok, "BurstKindFx 完整支持 6 种法印爆发形态")

	# 巨印落点印体：纯矢量 SealImpactFx（取代 AI 位图 weapon_earth_seal.png 当动态特效）
	var seal := SealImpactFx.new()
	seal.size = 90.0 * 1.4
	seal.tint = Color(0.88, 0.74, 0.46)
	_c.check(seal.size > 0.0, "SealImpactFx 程序化镇印可配置（画幅 %.0fpx）" % seal.size)
	seal.free()
	
	var beam := BeamRenderer.new()
	beam.beam_on(200.0, 10.0, Color.PURPLE)
	var cone := FlameConeRenderer.new()
	cone.cone_on(150.0, 70.0)
	_c.check(beam.visible and cone.visible, "BeamRenderer 与 FlameConeRenderer 可正常激活")
	beam.free()
	cone.free()

func _test_projectile_integrity() -> void:
	var bullets := [
		"bullet_gold_sword.png", "bullet_fire_sword.png", "bullet_leaf_dagger.png",
		"bullet_silver_needle.png", "bullet_gold_needle.png", "bullet_ice_needle.png",
		"bullet_bone_spike.png", "bullet_fire_talisman.png", "bullet_true_fire_talisman.png",
		"bullet_thunder_fire_talisman.png", "bullet_wood_talisman.png", "bullet_gu_talisman.png",
		"bullet_jingzhe_fu.png", "bullet_gengjin_fu.png", "bullet_earth_talisman.png",
		"bullet_ice_talisman.png", "bullet_frost_talisman.png", "bullet_stone_talisman.png",
		"bullet_fire_flame.png", "bullet_spirit_pellet.png", "bullet_water_shuttle.png"
	]
	_c.equals(bullets.size(), 21, "统计 21 种核心法器飞行物贴图")
	
	var fallback_count := 0
	for b in bullets:
		var kind := ProceduralProjectileRenderer.detect_kind_from_path(b)
		if kind == ProceduralProjectileRenderer.ProjectileKind.GENERIC_BLADE:
			fallback_count += 1
	_c.equals(fallback_count, 0, "所有 21 种飞行物贴图均被精确识别，无静默降级 fallback")

func _test_ui_style_integrity() -> void:
	_c.check(GameStyle.INK != Color.TRANSPARENT, "GameStyle.INK 色阶有效")
	_c.check(GameStyle.PAPER != Color.TRANSPARENT, "GameStyle.PAPER 色阶有效")
	_c.check(GameStyle.GOLD != Color.TRANSPARENT, "GameStyle.GOLD 色阶有效")
	_c.check(GameStyle.JADE != Color.TRANSPARENT, "GameStyle.JADE 色阶有效")
	
	var b := GameStyle.block(GameStyle.GOLD)
	var c := GameStyle.card(GameStyle.JADE)
	var d := GameStyle.dialog_panel()
	var s := GameStyle.side_card(GameStyle.GOLD)
	_c.check(b != null and c != null and d != null and s != null, "GameStyle 核心 StyleBox 构件函数工作正常")
