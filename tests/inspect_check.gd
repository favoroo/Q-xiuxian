extends Node

## tests/inspect_check.gd — 美术与视觉资产完整性校验单测
##
## 验证目标：
## 1. 修仙者角色完整度：CultivatorData.DEFS 全量角色均能在 CultivatorVisualConfig 中正确解析并包含 4 大外观插槽。
## 2. 法器资源完整度：WeaponData.DEFS 68 把武器的 icon 与 bullet 文件在磁盘中真实存在。
## 3. 法宝道具资源完整度：ItemData.DEFS 全量道具的 icon 文件在磁盘中真实存在。
## 4. 妖魔配置完整度：EnemyVisualConfig 能够完整提供全量怪物/精英/Boss 的视觉配置。
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
	_test_enemy_visual_configs()
	
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
	_c.check(defs.size() >= 68, "WeaponData 收录至少 68 把法器 (实际: %d)" % defs.size())
	
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

func _test_enemy_visual_configs() -> void:
	var enemies := [
		"slime", "xiexiu", "danbao", "fengqun", "flower",
		"xueyong", "guyao", "duyao", "yingmei", "zhumu",
		"leibeast", "golem", "chilei_elite", "jiansha_elite", "boss", "lingyi", "jinchan"
	]
	var missing: Array[String] = []
	for eid in enemies:
		var cfg := EnemyVisualConfig.get_config(eid)
		if cfg == null:
			missing.append(eid)
		elif cfg.col_primary == null or cfg.display_name.is_empty():
			missing.append("%s (bad fields)" % eid)
			
	_c.check(missing.is_empty(), "全量敌人视觉配置正常提供 (异常: %s)" % str(missing))
