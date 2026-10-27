class_name SuperUpgradeData
extends RefCounted

## 超级悟道数据库（2026-10-26 去阶段门控：改回纯随机卡池）
##
## 设计判据（一张卡必须能用一句话说清「你以后打起来会不一样」）：
##   纯数值放大不算超级卡 —— 那是普通悟道的活。本表只收「改变战斗规则」的机制卡
##   与「有真代价」的取舍卡。
##
## 卡池结构（2026-10-26 起）：
##   不再分阶段、不设「开道 → 延续 → 大成」的解锁链。凡是没拿过的卡，从第一次飞升
##   起就在池子里，五选一按权重随机（用户口径：roguelike 要的就是随机性，
##   「1 阶拿过才轮到 2 阶」这种顺序解锁没必要）。
##   保留的两道闸都是机制性的，不是解锁：灵兽卡要求手上已有灵兽（否则整张卡空转）；
##   共鸣卡要求 requires_lines 里每条道途各 ≥1 张 —— 这就是「共鸣」二字的定义。
##   道途（line）仍逐卡标注，只用于卡面签与作者面板筛选，不再参与门控。
##
## 与 UpgradeData 的分工不变：本表只说「给哪一张卡」，数值与机制全写在绑定的
## tier 5「神通」道具（ItemData 的 shen_*）上，赠礼走 GameManager.add_item()。
## 卡面标题/说明/图标/加成行一律从道具定义现取，本表不抄第二份数字。

const RARITY := "mythic"
const RARITY_LABEL := "逆天"

## 候选张数：五选一
const OFFER_COUNT := 5
## 同一道途在一屏里最多出现几张（纯读数友好：防「一屏全是雷法」；这不是门控，
## 只影响同屏采样，池子不够时会让位）
const MAX_PER_LINE := 2

## 固定触发关（胜利关 20 不在此列；无尽模式另由 is_super_wave 按 5 的倍数续上）
const SUPER_WAVES: Array[int] = [5, 10, 15]

## 道途名（卡面 chip 与面板提示用）
const LINE_LABELS := {
	"sword": "剑道",
	"arrow": "箭道",
	"thunder": "雷法",
	"body": "体修",
	"wuxing": "五行",
	"beast": "灵兽",
}

## 卡表字段：
##   id          卡 id（全表唯一）
##   grant_item  绑定的神通道具 id（tier5 / granted_only / no_sell）
##   line        道途键（ritual / resonance 卡没有）
##   kind        "lane"（有道途）| "resonance"（跨道共鸣）| "ritual"（仪式）
##   need        构筑亲和标签（只用来加权；命中则权重 ×1.5）
##   requires_lines  共鸣卡前置：这些道途各需 ≥1 张
##   requires_pets   灵兽卡前置：手上得有灵兽，否则整张卡空转
const CARDS: Array[Dictionary] = [
	# ==================== 剑道 ====================
	{"id": "super_jianqi", "grant_item": "shen_jianqi", "line": "sword", "kind": "lane",
		"need": ["melee", "sword", "wide"]},
	{"id": "super_wanjian_guizong", "grant_item": "shen_wanjian_guizong", "line": "sword", "kind": "lane",
		"need": ["melee", "sword"]},

	# ==================== 箭道 ====================
	{"id": "super_wanjian_qifa", "grant_item": "shen_wanjian_qifa", "line": "arrow", "kind": "lane",
		"need": ["ranged", "talisman"]},
	{"id": "super_tanmu", "grant_item": "shen_tanmu", "line": "arrow", "kind": "lane",
		"need": ["ranged", "talisman"]},
	{"id": "super_jianyu", "grant_item": "shen_jianyu", "line": "arrow", "kind": "lane",
		"need": ["ranged", "talisman"]},

	# ==================== 雷法 ====================
	{"id": "super_zidian", "grant_item": "shen_zidian", "line": "thunder", "kind": "lane",
		"need": ["elemental", "thunder"]},
	{"id": "super_leijie", "grant_item": "shen_leijie", "line": "thunder", "kind": "lane",
		"need": ["elemental", "thunder"]},
	{"id": "super_tianfa", "grant_item": "shen_tianfa", "line": "thunder", "kind": "lane",
		"need": ["crit"]},

	# ==================== 体修 ====================
	{"id": "super_fanzhen_dianchang", "grant_item": "shen_fanzhen_dianchang", "line": "body", "kind": "lane",
		"need": ["tank", "thorns"]},
	{"id": "super_xuehai", "grant_item": "shen_xuehai", "line": "body", "kind": "lane",
		"need": ["tank", "lifesteal"]},

	# ==================== 五行 ====================
	{"id": "super_wuxing_lunzhuan", "grant_item": "shen_wuxing_lunzhuan", "line": "wuxing", "kind": "lane",
		"need": ["elemental"]},
	{"id": "super_wuxing_guiyi", "grant_item": "shen_wuxing_guiyi", "line": "wuxing", "kind": "lane",
		"need": ["elemental"]},

	# ==================== 灵兽 ====================
	{"id": "super_shouxue", "grant_item": "shen_shouxue", "line": "beast", "kind": "lane",
		"need": ["pet"], "requires_pets": true},
	{"id": "super_shouqun", "grant_item": "shen_shouqun", "line": "beast", "kind": "lane",
		"need": ["pet"], "requires_pets": true},

	# ==================== 跨道共鸣（两条道各 ≥1 张） ====================
	{"id": "super_leiting_danmu", "grant_item": "shen_leiting_danmu", "kind": "resonance",
		"requires_lines": ["thunder", "arrow"], "need": ["ranged", "elemental"]},
	{"id": "super_lingyun_wuxing", "grant_item": "shen_lingyun_wuxing", "kind": "resonance",
		"requires_lines": ["beast", "wuxing"], "need": ["pet", "elemental"], "requires_pets": true},

	# ==================== 仪式（无道途，随时可出） ====================
	{"id": "super_kaitian", "grant_item": "shen_kaitian", "kind": "ritual"},
	{"id": "super_shalu", "grant_item": "shen_shalu", "kind": "ritual"},
	{"id": "super_xueji", "grant_item": "shen_xueji", "kind": "ritual"},
	{"id": "super_moyan", "grant_item": "shen_moyan", "kind": "ritual"},
	{"id": "super_dixue", "grant_item": "shen_dixue", "kind": "ritual"},
	{"id": "super_yixing", "grant_item": "shen_yixing", "kind": "ritual"},
	{"id": "super_xianji", "grant_item": "shen_xianji", "kind": "ritual"},
]

## 权重：共鸣最高（凑齐两条道后才出现，本身就是回报）> 道途卡 > 仪式卡；命中构筑 ×1.5
const W_RESONANCE := 6.0
const W_LANE := 2.0
const W_RITUAL := 1.0
const W_BUILD_BONUS := 1.5

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

static func line_label(line_key: String) -> String:
	return String(LINE_LABELS.get(line_key, ""))

## 本关是否该弹超级悟道：固定 5/10/15，或无尽模式 20 关后每逢 5 的倍数关。
static func is_super_wave(wave: int, endless: bool) -> bool:
	if wave in SUPER_WAVES:
		return true
	return endless and wave > 20 and wave % 5 == 0

## 当前构筑标签集合：武器 tags ∪ 武器 scaling 类别 ∪ 角色 item_tags（三源并查）。
## 用途已从「硬性配比」改为「加权」：命中构筑的卡更容易出现，但不再占死名额。
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

## 已行道途计数：{line: 已拿张数}。只用于共鸣前置与面板「已行」读数，不再是阶段门控。
static func lane_counts(gm: Node) -> Dictionary:
	var taken: Array = gm.get("super_cards_taken")
	var counts: Dictionary = {}
	for cid in taken:
		var def := get_def(String(cid))
		if def.is_empty():
			continue
		var line := String(def.get("line", ""))
		if line.is_empty():
			continue
		counts[line] = int(counts.get(line, 0)) + 1
	return counts

## 一张卡当前是否可选。2026-10-26 去阶段门控后只剩两道真闸：
##   · 灵兽闸 —— requires_pets 的卡手上必须有灵兽（否则 pet_slots / 灵兽链电全是空转）
##   · 共鸣闸 —— requires_lines 里每条道途各已 ≥1 张（「共鸣」二字的定义）
## 其余卡一律可选，不分阶、不分先后。已拿过剔除由调用方（roll_offers）负责。
static func is_card_available(card: Dictionary, counts: Dictionary, has_pets: bool) -> bool:
	if bool(card.get("requires_pets", false)) and not has_pets:
		return false
	if String(card.get("kind", "ritual")) != "resonance":
		return true
	for line in (card.get("requires_lines", []) as Array):
		if int(counts.get(String(line), 0)) < 1:
			return false
	return true

## 卡在当前局面的权重：只看卡类型（道途卡同权，不再分阶）+ 是否命中构筑
static func card_weight(card: Dictionary, tags: Dictionary) -> float:
	var kind := String(card.get("kind", "ritual"))
	var w := W_RITUAL
	match kind:
		"resonance":
			w = W_RESONANCE
		"ritual":
			w = W_RITUAL
		_:
			w = W_LANE
	if card_matches_build(card, tags):
		w *= W_BUILD_BONUS
	return w

## 卡面边签文案：现在只有共鸣卡带专属签（道途卡的签就是道途名本身，仪式卡不带签）
static func lane_chip(card: Dictionary) -> String:
	return "共鸣" if String(card.get("kind", "ritual")) == "resonance" else ""

## 抽本次飞升悟道候选。
## 算法（2026-10-26 去阶段门控后是纯随机）：
##   ① 可用池 = 全表 − 已拿过 − 未过闸（灵兽闸 / 共鸣前置）
##   ② 加权随机补满 5 张，同道途同屏最多 MAX_PER_LINE 张
##   ③ 池子不够时放宽同道途上限补满（同屏仍不重复），绝不让候选变少
## 没有保底、没有「已行之道优先」—— 上一轮选什么不影响这一轮抽什么。
## 随机走 GameManager.rng（玩法判定 RNG 铁律）。
static func roll_offers(gm: Node) -> Array[Dictionary]:
	var taken: Array = gm.get("super_cards_taken")
	var counts := lane_counts(gm)
	var tags := build_tag_set(gm)
	var has_pets: bool = not (gm.get("pets") as Array).is_empty() or String(gm.cultivator_id) == "yushou"
	var rng: RandomNumberGenerator = gm.rng

	var pool: Array = []
	for d in CARDS:
		var card: Dictionary = d
		if String(card.get("id", "")) in taken:
			continue
		if not is_card_available(card, counts, has_pets):
			continue
		pool.append(card)

	var offers: Array[Dictionary] = []
	var used_ids: Dictionary = {}
	var line_in_screen: Dictionary = {}
	var guard := 0
	while offers.size() < OFFER_COUNT and guard < 200:
		guard += 1
		var candidates: Array = []
		for card in pool:
			if used_ids.has(String(card.get("id", ""))):
				continue
			var line := String(card.get("line", ""))
			if not line.is_empty() and int(line_in_screen.get(line, 0)) >= MAX_PER_LINE:
				continue
			candidates.append(card)
		if candidates.is_empty():
			break
		var picked := _weighted_pick(candidates, tags, rng)
		if picked.is_empty():
			break
		offers.append(card_payload(picked))
		used_ids[String(picked.get("id", ""))] = true
		var pline := String(picked.get("line", ""))
		if not pline.is_empty():
			line_in_screen[pline] = int(line_in_screen.get(pline, 0)) + 1

	# ③ 池子不足 5 张：放宽同道途上限补满（同屏仍不重复）
	if offers.size() < OFFER_COUNT:
		for card in pool:
			if offers.size() >= OFFER_COUNT:
				break
			if used_ids.has(String(card.get("id", ""))):
				continue
			offers.append(card_payload(card))
			used_ids[String(card.get("id", ""))] = true

	return offers

static func _weighted_pick(candidates: Array, tags: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	var weights: Array = []
	for c in candidates:
		var w: float = card_weight(c, tags)
		weights.append(w)
		total += w
	if total <= 0.0:
		return {}
	var roll: float = rng.randf() * total
	var acc := 0.0
	for i in candidates.size():
		acc += float(weights[i])
		if roll <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]

## 卡面数据只从绑定道具现取：title/desc/icon/apply 全在 ItemData（数值唯一真话），
## 卡上再挂 rarity + lane_label 让 LevelUpCardFactory 直接吃逆天红与道途签。
## is_super 是飞升悟道（原超级悟道）的显式卡面标记：普通悟道 payload 没有这个键，
## 卡工厂据它染淡红卡底、加粗红框、红图标框；普通卡一条分支都不进。
static func card_payload(card: Dictionary) -> Dictionary:
	var gid := String(card.get("grant_item", ""))
	var idef := ItemData.get_def(gid)
	var line := String(card.get("line", ""))
	return {
		"id": String(card.get("id", "")),
		"is_super": true,
		"grant_item": gid,
		"kind": String(card.get("kind", "ritual")),
		"line": line,
		"lane_label": line_label(line),
		"lane_chip": lane_chip(card),
		"title": String(idef.get("name", card.get("id", ""))),
		"desc": String(idef.get("desc", "")),
		"icon": String(idef.get("icon", "")),
		"apply": idef.get("apply", {}),
		"rarity": RARITY,
		"rarity_label": RARITY_LABEL,
		"border_color": GameStyle.RARITY_MYTHIC,
	}

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
