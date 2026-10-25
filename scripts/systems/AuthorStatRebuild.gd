class_name AuthorStatRebuild
extends RefCounted

## 作者模式专用：把属性层**从初值重放一遍**，让「删除悟道加点 / 撤销超级悟道」后的读数精确回落。
##
## 为什么不能走撤销（StatSystem.revert_stat_fields）：它是增量 +=/*= 架构上的反向操作，
## 对被上限夹过的字段采取「宁可少扣」（undo_capped_add：cur >= cap 时原样返回）——
## 暴击堆到 CRIT_RATE_CAP 后再删加点，读数会永远卡在 cap 上降不下来。测试台读数失真就废了。
##
## 唯一可靠的路：apply 算式是确定性的，把所有来源按固定顺序重放，结果与真实到账一致，
## 且与「删哪一层、什么顺序删」无关。来源与顺序（与真实开局链路同构）：
##   ① RunReset.reset_stat_fields  属性初值（与开局复位同一份，不会漂）
##   ② CultivatorSystem.apply_stat_mods  角色流派数值 mods（只数值，无开局副作用）
##   ③ gm.items                    逐件 apply（超级悟道的神通道具就在这里面）
##   ④ gm.upgrade_counts           逐项 ×count apply（超级卡的 id 不在 UpgradeData，自然跳过——
##                                   它的属性落在赠予的神通道具上，③ 已覆盖）
##   ⑤ gm._wave_end_growth         回合末永久成长（突破古玉的累积台账，照值重放）
##   ⑥ 生命上限单独算：BASE × hp_mult + Σmax_hp，羁绊 hp 由 ⑦ 的差值法补上
##   ⑦ SynergySystem.recalc_synergies  羁绊全量重算（它本来就全量）
##
## 不参与重放的一次性/路径依赖值：
##   - spirit_stones：一次性到账，重放等于印钱（当前表里没有任何卡用这个键，纯防御）
##   - hp_heal：买时那口治疗已经发生，重放不该再回血
##   - max_hp：剥出来单独累加，最后一次性写上限（不走 increase_max_hp，无跳字无挤压）
##   - harvest：每回合 harvest_next 复利，重放会抹掉累积增长 ⇒ 保留现值；
##     删采气卡时由 AuthorMode 按名义值扣减补偿
## revive_charges 正常重放（与 RunSave 口径一致：存档不存它，读档按 upgrades 回放）。
##
## 重放顺序与真实逐次购买/加点的交错顺序不同：上限夹取类字段不受影响（重放复现夹取），
## 只有乘区撞地板的极端情形可能有极微小差异（攻速/物价/灵兽冷却地板）。
##
## ⚠ 调用方必须是 ui/author 侧（AuthorAllocView），不能让 AuthorMode 引用本文件：
## Player.gd 引用 AuthorMode（god_mode 读侧短路），本文件又要 StatSystem/Player，
## AuthorMode → 本文件这条边会构成循环类依赖（坑 12），Player.gd 直接解析失败。

## 重放时要剥掉的一次性/路径依赖键：
##   spirit_stones 一次性到账（重放=印钱）；max_hp 剥出来单独累加；hp_heal 不重放治疗；
##   harvest 由 rebuild 整体保留现值（跨回合复利值，重放会双重累加）——见 rebuild 内注释。
const REPLAY_SKIP_KEYS: Array[String] = ["spirit_stones", "max_hp", "hp_heal", "harvest"]

## 重放整条属性层。只碰「apply 层」字段 + 玩家生命上限 + 羁绊层；
## 等级/金币/道具列表/灵兽/武器/会话状态一概不动。
static func rebuild(gm: Node) -> void:
	var harvest_keep: float = float(gm.harvest)
	RunReset.reset_stat_fields(gm)
	CultivatorSystem.apply_stat_mods(gm)
	# harvest 整体保留现值，**在 apply_stat_mods 之后写回**：mods 里的角色采气加成已含在
	# 现值里，重放再加就双算了（删采气卡由 AuthorMode 按名义值扣，见其头注）
	gm.harvest = harvest_keep

	var hp_delta := 0.0
	# ③ 道具：按 items 现有清单逐件重放（add_item 当时怎么落，这里就怎么落）
	for item_id in gm.items:
		hp_delta += apply_filtered(gm, ItemData.get_def(String(item_id)).get("apply", {}),
				"rebuild:item:" + String(item_id))
	# ④ 悟道加点：upgrade_counts 逐项逐层（超级卡 id 查不到定义 → 空 apply → 跳过）
	for uid in gm.upgrade_counts.keys():
		var def := UpgradeData.get_upgrade_def(String(uid))
		if def.is_empty():
			continue
		for _i in range(int(gm.upgrade_counts[uid])):
			hp_delta += apply_filtered(gm, def.get("apply", {}), "rebuild:upgrade:" + String(uid))
	# ⑤ 回合末永久成长：突破古玉等累积台账照值重放（max_hp 不治疗，与原应用路径的差异只在这）
	var growth: Dictionary = gm._wave_end_growth
	hp_delta += float(growth.get("max_hp", 0.0))
	if float(growth.get("hp_regen", 0.0)) != 0.0:
		apply_filtered(gm, {"hp_regen": float(growth.get("hp_regen", 0.0))}, "rebuild:wave_growth")
	if float(growth.get("lifesteal", 0.0)) != 0.0:
		apply_filtered(gm, {"lifesteal": float(growth.get("lifesteal", 0.0))}, "rebuild:wave_growth")

	_set_player_max_hp(gm, hp_delta)
	# ⑦ 羁绊层：先清台账再全量重算，apply_synergy_hp 会把羁绊生命加成整份补上
	gm._applied_hp_bonus = 0.0
	SynergySystem.recalc_synergies(gm)
	invalidate_caches(gm)

## 把一份 apply 落到 gm 上，剥掉一次性键；返回这份 apply 里的 max_hp 名义值（供上限累加）
static func apply_filtered(gm: Node, apply: Dictionary, source: String) -> float:
	if apply.is_empty():
		return 0.0
	var hp := 0.0
	var filtered := {}
	for key in apply.keys():
		if String(key) in REPLAY_SKIP_KEYS:
			if String(key) == "max_hp":
				hp += float(apply[key])
			continue
		filtered[key] = apply[key]
	if not filtered.is_empty():
		StatSystem.apply_stat_fields(gm, filtered, source)
	return hp

## 生命上限 = 基础 × 角色 hp_mult + Σ max_hp（加点/道具/回合末成长）。
## 羁绊 hp 不在这里：recalc_synergies 走 _applied_hp_bonus 差值法补。
static func _set_player_max_hp(gm: Node, hp_delta: float) -> void:
	var p = gm.player
	if p == null or not is_instance_valid(p):
		return
	var hp_mult := float(CultivatorData.get_def(String(gm.cultivator_id)).get("mods", {}).get("hp_mult", 1.0))
	var target := maxf(1.0, Player.BASE_MAX_HEALTH * hp_mult + hp_delta)
	p.max_health = target
	p.current_health = minf(p.current_health, target)
	gm.player_hp_changed.emit(p.current_health, p.max_health)

## 属性字典 memo 与三类 hook 缓存统一失效（与 add_item/sell_item/RunReset 同一套失效点）
static func invalidate_caches(gm: Node) -> void:
	gm._stat_dict_frame = -1
	gm._still_cache_valid = false
	gm._hook_cache.clear()
	gm._hook_cache_items_size = -1
	gm._super_hook_snap.clear()
	gm._super_hook_stamp = -1
	gm._mark_stats_dirty()
