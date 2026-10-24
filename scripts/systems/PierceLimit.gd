class_name PierceLimit
extends RefCounted

## 弹丸穿透上限闸（2026-10-17，用户口径：「最大穿透为3，达到之后就不会继续刷出加穿透的加点和物品」）：
## 尺子唯一真话在 WeaponData.PIERCE_CAP / capped_pierce；本文件只回答两个问题——
##   1) has_max_pierce：当前局穿透是否已到顶（按实际阵容逐把对账）
##   2) 候选过滤：悟道加点 / 金币阁道具 / 玉匣 roller 在满穿透时把穿透件从池里剔掉，
##      已在货架上的不加干涉（买了按 capped_pierce 钳位，白买一件是玩家自己的选择）
## 加成来源清单（对账用，新增穿透来源必须登记到这里）：
##   - 悟道词条 pierce_up（UpgradeData，apply.bonus_pierce）
##   - 道具 破虚符/裂空锥/洞虚针（ItemData，apply.bonus_pierce）
##   - 弹射羁绊 synergy_bonus_pierce（WeaponData.SYNERGIES.talisman，2026-10-17 起恒 +1）
##   - 剑阵盘等 turret 弹丸与普通弹丸共用同一闸（TurretUnit/FloatingWeapon 出膛钳位）
## 判定口径（2026-10-17 定稿）：从「加成合计 ≥ CAP-1」改成「实际阵容逐把对账」——
## 全部弹丸基础均 1，加成合计口径看似够用，但逐把算 capped_pierce(基础+bonus) 是否全到 CAP
## 与出膛钳位同源、防御未来新增基础≥2 的弹丸不出错。

## 穿透强化词条 id：满穿透时不进悟道候选池
const PIERCE_UPGRADE_ID := "pierce_up"

## 加穿透的道具 id 集合：满穿透时不进金币阁/玉匣道具池
const PIERCE_ITEM_IDS: Array[String] = ["poxu_lingfu", "wuji_tianchuan_zhen"]

## 当前局穿透是否已顶到上限——按【玩家实际阵容】逐把对账，与出膛钳位同源。
## 口径：对场上每一把弹丸类武器（悬浮 PROJECTILE + 机关台 TURRET，含背囊未上阵的弹丸不算
## ——买了新武器换上来时会重新 recalc 重刷货架），算 capped_pierce(基础 + bonus_pierce)；
## 全部弹丸都顶到 PIERCE_CAP 才算满 ⇒ 穿透词条/道具停刷。
## 两类阵容各自的样子（基础均 1）：
##   全基础 1 阵容 + bonus 1 → 出膛 2 < 3：不停刷（还差一层，买词条/道具才满）
##   全基础 1 阵容 + bonus 2 → 出膛 3：满，停刷
## 玩家一件弹丸都没有时（不可能开局，防御性兜底）按未满处理，照常刷。
static func has_max_pierce(gm: Node) -> bool:
	if gm.player == null or not is_instance_valid(gm.player):
		return false
	var found_pierceable := false
	for w in gm.player.get_equipped_weapons_data():
		var def := WeaponData.get_def(String(w.get("id", "")))
		if def.is_empty():
			continue
		# 只统计出膛走 capped_pierce 的两类：悬浮 PROJECTILE 与机关台 TURRET。
		# TurretUnit.gd:298 与 ProjectileHandler.gd:185 同一式子，漏掉 TURRET 会导致
		# 只带机关台的玩家被判「未满」一直刷穿透词条，但机关台实际已钳到 CAP。
		var beh := int(def.get("behavior", -1))
		if beh != WeaponData.Behavior.PROJECTILE and beh != WeaponData.Behavior.TURRET:
			continue
		found_pierceable = true
		if WeaponData.capped_pierce(int(def.get("pierce", 1)) + int(gm.bonus_pierce)) < WeaponData.PIERCE_CAP:
			return false
	# 逐把查完防未来出现基础≥2 的弹丸漏判；当前基础均 1，全满即 bonus ≥ 2。
	if not found_pierceable:
		return false
	return true

## 悟道候选过滤钩子（UpgradeData.get_random_upgrades ctx 里透传）：
## 满穿透时把 pierce_up 剔出池子；未满时原样放行。
static func filter_upgrade_id(gm: Node, uid: String) -> bool:
	if uid == PIERCE_UPGRADE_ID and has_max_pierce(gm):
		return false
	return true

## 道具候选过滤钩子（ItemData.pick_id / 玉匣 roller ctx 里透传）：
## 满穿透时把三件穿透道具剔出池子；未满时原样放行。
static func filter_item_id(gm: Node, item_id: String) -> bool:
	if item_id in PIERCE_ITEM_IDS and has_max_pierce(gm):
		return false
	return true
