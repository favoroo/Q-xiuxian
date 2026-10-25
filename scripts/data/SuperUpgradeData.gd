class_name SuperUpgradeData
extends RefCounted

## 超级悟道数据库（2026-10-25）：每 5 关一次、五选一（3 张流派 + 2 张通用）、不可刷新。
##
## 与 UpgradeData 的分工：
##   UpgradeData 管每条里「加多少」（apply 表是幅度唯一真话）；
##   本表只管「给哪一张卡」——每张卡绑定一件 tier 5「神通」道具（ItemData 里的 shen_*），
##   数值与 hook 机制全写在那件道具上，赠礼走 GameManager.add_item() 现有落地链路。
##   卡面标题/说明/图标/加成行一律从道具定义现取（roll_offers 注入），本表不抄第二份数字。
##
## 一局最多 3 次（第 5/10/15 关后；无尽模式 20 关后每逢 5 的倍数关再触发），
## 已拿过的卡不再出现（gm.super_cards_taken）。
##
## 流派匹配（三源并查）：卡面 need 命中「武器 tags ∪ 武器 stat_scalings 类别 ∪ 角色 item_tags」任一即算流派卡。
## 只认武器会漏掉守卫（反震）/蛮兵（怪海）/绝尘（技能）/灵植夫（回复）这些身份写在角色标签上的流派。

const RARITY := "mythic"
const RARITY_LABEL := "逆天"
const BUILD_OFFER_COUNT := 3
const GENERIC_OFFER_COUNT := 2

## 固定触发关（胜利关 20 不在此列；无尽模式另由 is_super_wave 按 5 的倍数续上）
const SUPER_WAVES: Array[int] = [5, 10, 15]

## 卡表：kind = build（流派，按 need 匹配）| generic（通用，任意构筑都能出）
## requires_pets：没有灵兽时不进候选池（与 UpgradeData 的 pet_ 前缀闸同一条口径）
const CARDS: Array[Dictionary] = [
	# ---- 武器流派 ----
	{"id": "super_jianqi", "grant_item": "shen_jianqi", "kind": "build", "need": ["melee", "sword"]},
	{"id": "super_yizhanyang", "grant_item": "shen_yizhanyang", "kind": "build", "need": ["melee"]},
	{"id": "super_zhuixing", "grant_item": "shen_zhuixing", "kind": "build", "need": ["ranged", "talisman"]},
	{"id": "super_guanchuan", "grant_item": "shen_guanchuan", "kind": "build", "need": ["ranged", "talisman"]},
	{"id": "super_wuxing", "grant_item": "shen_wuxing", "kind": "build", "need": ["elemental", "thunder"]},
	{"id": "super_zaie", "grant_item": "shen_zaie", "kind": "build", "need": ["elemental", "thunder"]},
	{"id": "super_hengsao", "grant_item": "shen_hengsao", "kind": "build", "need": ["wide"]},
	{"id": "super_wanling", "grant_item": "shen_wanling", "kind": "build", "need": ["engineering", "spirit"]},
	{"id": "super_shouxue", "grant_item": "shen_shouxue", "kind": "build", "need": ["pet"], "requires_pets": true},
	{"id": "super_huoli", "grant_item": "shen_huoli", "kind": "build", "need": ["contraption"]},
	{"id": "super_shentong", "grant_item": "shen_shentong", "kind": "build", "need": ["skill"]},
	{"id": "super_shenxing", "grant_item": "shen_shenxing", "kind": "build", "need": ["speed"]},
	# ---- 五行专精 ----
	{"id": "super_dianjin", "grant_item": "shen_dianjin", "kind": "build", "need": ["metal"]},
	{"id": "super_kumu", "grant_item": "shen_kumu", "kind": "build", "need": ["wood"]},
	{"id": "super_ruoshui", "grant_item": "shen_ruoshui", "kind": "build", "need": ["water"]},
	{"id": "super_lihuo", "grant_item": "shen_lihuo", "kind": "build", "need": ["fire"]},
	{"id": "super_houtu", "grant_item": "shen_houtu", "kind": "build", "need": ["earth"]},
	# ---- 角色流派 ----
	{"id": "super_jingji", "grant_item": "shen_jingji", "kind": "build", "need": ["thorns"]},
	{"id": "super_wanjun", "grant_item": "shen_wanjun", "kind": "build", "need": ["crowd"]},
	{"id": "super_shengsheng", "grant_item": "shen_shengsheng", "kind": "build", "need": ["heal"]},
	{"id": "super_xuehai", "grant_item": "shen_xuehai", "kind": "build", "need": ["lifesteal"]},
	# ---- 通用：新奇机制 / 数值超模 / 代价卡 ----
	{"id": "super_kaitian", "grant_item": "shen_kaitian", "kind": "generic"},
	{"id": "super_shalu", "grant_item": "shen_shalu", "kind": "generic"},
	{"id": "super_xueji", "grant_item": "shen_xueji", "kind": "generic"},
	{"id": "super_beishui", "grant_item": "shen_beishui", "kind": "generic"},
	{"id": "super_guzhu", "grant_item": "shen_guzhu", "kind": "generic"},
	{"id": "super_yijing", "grant_item": "shen_yijing", "kind": "generic"},
	{"id": "super_jubao", "grant_item": "shen_jubao", "kind": "generic"},
	{"id": "super_duobao", "grant_item": "shen_duobao", "kind": "generic"},
	{"id": "super_bumie", "grant_item": "shen_bumie", "kind": "generic"},
	{"id": "super_moyan", "grant_item": "shen_moyan", "kind": "generic"},
	{"id": "super_dixue", "grant_item": "shen_dixue", "kind": "generic"},
	{"id": "super_yixing", "grant_item": "shen_yixing", "kind": "generic"},
	{"id": "super_yucuo", "grant_item": "shen_yucuo", "kind": "generic"},
]

## 武器 stat_scalings 键 → 构筑标签（与角色 item_tags / 武器 tags 同一套词表）
const SCALING_TAGS := {
	"melee_damage": "melee",
	"ranged_damage": "ranged",
	"elemental_damage": "elemental",
	"engineering_damage": "engineering",
	"contraption_damage": "contraption",
	"move_speed_bonus": "speed",
	"cdr_bonus": "skill",
	"range_bonus": "range",
	"crit_rate": "crit",
	"crit_mult_bonus": "crit",
	"armor": "tank",
	"max_hp_bonus": "tank",
	"lifesteal": "lifesteal",
	"hp_regen": "heal",
}

static func get_def(card_id: String) -> Dictionary:
	for d in CARDS:
		if String(d.get("id", "")) == card_id:
			return d
	return {}

static func all_ids() -> Array:
	var out: Array = []
	for d in CARDS:
		out.append(String(d.get("id", "")))
	return out

## 本关是否该弹超级悟道：固定 5/10/15，或无尽模式 20 关后每逢 5 的倍数关。
static func is_super_wave(wave: int, endless: bool) -> bool:
	if wave in SUPER_WAVES:
		return true
	return endless and wave > 20 and wave % 5 == 0

## 当前构筑标签集合：武器 tags ∪ 武器 scaling 类别 ∪ 角色 item_tags（三源并查）。
static func build_tag_set(gm: Node) -> Dictionary:
	var tags: Dictionary = {}
	if gm == null:
		return tags
	for wid in BalanceBuildFilter.weapon_ids(gm):
		var wdef := WeaponData.get_def(String(wid))
		if wdef.is_empty():
			continue
		for t in WeaponData.tags_of(String(wid)):
			tags[String(t)] = true
		var scalings: Dictionary = wdef.get("stat_scalings", {})
		for k in scalings.keys():
			var tag := String(SCALING_TAGS.get(String(k), ""))
			if not tag.is_empty():
				tags[tag] = true
	var item_tags: Array = CultivatorData.item_tags_of(String(gm.cultivator_id))
	for t in item_tags:
		tags[String(t)] = true
	if not (gm.get("pets") as Array).is_empty() or String(gm.cultivator_id) == "yushou":
		tags["pet"] = true
	return tags

static func card_matches_build(card: Dictionary, tags: Dictionary) -> bool:
	for t in (card.get("need", []) as Array):
		if tags.has(String(t)):
			return true
	return false

## 抽本次超级悟道候选：3 张流派（匹配构筑优先）+ 2 张通用，任何一侧不足时用另一侧池兜底，
## 绝不让候选变少（同 UpgradeData._collect_pool 的两段式回退样板）。
## 随机走 GameManager.rng（玩法判定 RNG 铁律）。返回已注入卡面数据的字典数组。
static func roll_offers(gm: Node) -> Array[Dictionary]:
	var taken: Array = gm.get("super_cards_taken")
	var tags := build_tag_set(gm)
	var build_matched: Array = []
	var build_other: Array = []
	var generic: Array = []
	for d in CARDS:
		var card: Dictionary = d
		var cid := String(card.get("id", ""))
		if cid in taken:
			continue
		if bool(card.get("requires_pets", false)) and not tags.has("pet"):
			continue
		if String(card.get("kind", "generic")) == "build":
			if card_matches_build(card, tags):
				build_matched.append(card_payload(card))
			else:
				build_other.append(card_payload(card))
		else:
			generic.append(card_payload(card))
	var offers: Array[Dictionary] = []
	var rng: RandomNumberGenerator = gm.rng
	_take_random(build_matched, BUILD_OFFER_COUNT, offers, rng)
	if offers.size() < BUILD_OFFER_COUNT:
		_take_random(build_other, BUILD_OFFER_COUNT - offers.size(), offers, rng)
	if offers.size() < BUILD_OFFER_COUNT:
		_take_random(generic, BUILD_OFFER_COUNT - offers.size(), offers, rng)
	_take_random(generic, GENERIC_OFFER_COUNT, offers, rng)
	if offers.size() < BUILD_OFFER_COUNT + GENERIC_OFFER_COUNT:
		var rest: Array = build_other.duplicate()
		rest.append_array(generic)
		_take_random(rest, BUILD_OFFER_COUNT + GENERIC_OFFER_COUNT - offers.size(), offers, rng)
	return offers

## 卡面数据只从绑定道具现取：title/desc/icon/apply 全在 ItemData（数值唯一真话），
## 卡上再挂 rarity 两字段让 LevelUpCardFactory 直接吃逆天红。
static func card_payload(card: Dictionary) -> Dictionary:
	var gid := String(card.get("grant_item", ""))
	var idef := ItemData.get_def(gid)
	return {
		"id": String(card.get("id", "")),
		"grant_item": gid,
		"kind": String(card.get("kind", "generic")),
		"title": String(idef.get("name", card.get("id", ""))),
		"desc": String(idef.get("desc", "")),
		"icon": String(idef.get("icon", "")),
		"apply": idef.get("apply", {}),
		"rarity": RARITY,
		"rarity_label": RARITY_LABEL,
		"border_color": GameStyle.RARITY_MYTHIC,
	}

static func _take_random(pool: Array, count: int, out: Array, rng: RandomNumberGenerator) -> void:
	var n: int = mini(count, pool.size())
	for i in n:
		var idx: int = rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)

## 落地：赠送绑定的神通道具（数值 + hook 一次到位），并把它记进升级记录页签。
static func apply(gm: Node, card_id: String) -> bool:
	var card := get_def(card_id)
	if card.is_empty():
		return false
	var gid := String(card.get("grant_item", ""))
	if gid.is_empty() or ItemData.get_def(gid).is_empty():
		return false
	if not gm.add_item(gid):
		return false
	var prev_count: int = int(gm.upgrade_counts.get(card_id, 0)) + 1
	gm.upgrade_counts[card_id] = prev_count
	if not (card_id in gm.super_cards_taken):
		gm.super_cards_taken.append(card_id)
	var idef := ItemData.get_def(gid)
	gm.upgrade_history.append({
		"id": card_id,
		"title": String(idef.get("name", card_id)),
		"rarity": RARITY,
		"rarity_label": RARITY_LABEL,
		"icon": String(idef.get("icon", "")),
		"desc": String(idef.get("desc", "")),
		"border_color": GameStyle.RARITY_MYTHIC,
		"level": gm.level,
		"time": gm.game_time,
		"count": prev_count,
	})
	gm.upgrade_applied.emit(card_id)
	return true
