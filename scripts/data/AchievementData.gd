class_name AchievementData
extends RefCounted

## 成就里程碑与局外解锁数据库（仿土豆兄弟纯成就解锁机制）
## 全部 static 纯函数 —— 不读 autoload、不碰节点，保证单测可确定性断言。
## 设计原则：
##   1. 零局外数值膨胀：成就只解锁新修士（道统）与高阶法宝入池，不破坏局内难度平衡；
##   2. 初始开放 4 名代表性修士 + 11 件基础法宝，其余 5 名进阶修士与 4 件高阶法宝通过里程碑解锁。

## 危险度档位名号（D0 ~ D5）
const DANGER_NAMES: Array[String] = ["简单", "普通", "困难", "噩梦", "地狱", "极限"]

## 初始默认解锁的 4 名修士
const DEFAULT_CULTIVATORS: Array[String] = [
	"jianchi",
	"shiyue",
	"fuzhen",
	"jinsuanpan",
]

## 初始默认进入灵石阁货架池的 16 件法宝
const DEFAULT_ITEMS: Array[String] = [
	"jubaopen",
	"mibao_luopan",
	"qiankun_dai",
	"jifeng_xue",
	"qingxin_cha",
	"zhekou_yufu",
	"kuangxue_dan",
	"guijia_fu",
	"tongxuan_ling",
	"leiyin_zhen",
	"yinhun_deng",
	"suoling_jia",
	"wujian_shi",
	"huichun_hulu",
	"xiuluo_pei",
	"taiyi_jindan",
]

## 成就里程碑定义表（顺序即「修仙志」展示顺序）
## reward_type: "cultivator"（解锁新道统） | "item"（解锁新法宝入池）
const ACHIEVEMENTS: Array[Dictionary] = [
	{
		"id": "ach_cult_meiying",
		"name": "影行者",
		"cond_desc": "单局有效闪避达到35%，或累计击杀500只敌人",
		"reward_type": "cultivator",
		"reward_id": "meiying",
		"reward_name": "影者",
		"icon": "res://assets/art/cultivator_meiying_icon.png",
	},
	{
		"id": "ach_cult_kuangzhan",
		"name": "百战不殆",
		"cond_desc": "累计击杀达到1500只",
		"reward_type": "cultivator",
		"reward_id": "kuangzhan",
		"reward_name": "蛮兵",
		"icon": "res://assets/art/cultivator_kuangzhan_icon.png",
	},
	{
		"id": "ach_cult_duobao",
		"name": "富甲一方",
		"cond_desc": "单局金币达到250枚",
		"reward_type": "cultivator",
		"reward_id": "duobao",
		"reward_name": "收藏家",
		"icon": "res://assets/art/cultivator_duobao_icon.png",
	},
	{
		"id": "ach_cult_duoshe",
		"name": "初次通关",
		"cond_desc": "使用任意角色通关1次（完成第20波）",
		"reward_type": "cultivator",
		"reward_id": "duoshe",
		"reward_name": "学者",
		"icon": "res://assets/art/cultivator_duoshe_icon.png",
	},
	{
		"id": "ach_cult_dubi",
		"name": "极限挑战",
		"cond_desc": "通关「困难」或更高难度",
		"reward_type": "cultivator",
		"reward_id": "dubi",
		"reward_name": "狂战士",
		"icon": "res://assets/art/cultivator_dubi_icon.png",
	},
	{
		"id": "ach_item_pojia",
		"name": "深入敌后",
		"cond_desc": "单局抵达第15波",
		"reward_type": "item",
		"reward_id": "pojia_zhui",
		"reward_name": "破甲针",
		"icon": "res://assets/art/item_pojia_zhui.png",
	},
	{
		"id": "ach_item_wuxing",
		"name": "五行齐聚",
		"cond_desc": "单局等级达到Lv.15",
		"reward_type": "item",
		"reward_id": "wuxing_pei",
		"reward_name": "五行石",
		"icon": "res://assets/art/item_wuxing_pei.png",
	},
	{
		"id": "ach_item_hunyuan",
		"name": "收益满载",
		"cond_desc": "单局收益达到30点",
		"reward_type": "item",
		"reward_id": "hunyuan_zhu",
		"reward_name": "万能珠",
		"icon": "res://assets/art/item_hunyuan_zhu.png",
	},
	{
		"id": "ach_item_kuilei",
		"name": "九死一生",
		"cond_desc": "累计游玩5局，或任意通关1次",
		"reward_type": "item",
		"reward_id": "tisi_kuilei",
		"reward_name": "替身娃娃",
		"icon": "res://assets/art/item_tisi_kuilei.png",
	},
]

## 道统功名里程碑（每角色渡劫成功次数档位，2026-10-10 修仙志升级）
## 称号达标自动点亮（纯展示），灵石囊需在修仙志手动领取，开局时一次性兑入灵石
const MILESTONE_WINS: Array[int] = [1, 3, 5, 10]
const MILESTONE_TITLES: Array[String] = ["初学者", "进阶者", "老手", "大师"]
const MILESTONE_STONES: Array[int] = [30, 60, 100, 200]

## 每角色里程碑定义表：{id: "cid_次数", cultivator_id, wins, title, stones}
static func milestones_of(cid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(MILESTONE_WINS.size()):
		var w := MILESTONE_WINS[i]
		out.append({
			"id": "%s_%d" % [cid, w],
			"cultivator_id": cid,
			"wins": w,
			"title": MILESTONE_TITLES[i],
			"stones": MILESTONE_STONES[i],
		})
	return out

## 渡劫成功次数对应的最高称号（0 次返回空串）
static func title_for_wins(wins: int) -> String:
	var title := ""
	for i in range(MILESTONE_WINS.size()):
		if wins >= MILESTONE_WINS[i]:
			title = MILESTONE_TITLES[i]
	return title

## 单条里程碑当前是否可领取（达标且未领过）
static func is_milestone_claimable(mile_def: Dictionary, wins: int, claimed: Array) -> bool:
	if String(mile_def.get("id", "")) in claimed:
		return false
	return wins >= int(mile_def.get("wins", 999999))

## 是否存在任意可领取的里程碑（供修仙志入口红点）
static func any_claimable(records: Dictionary, claimed: Array) -> bool:
	for cid in records:
		var wins := int(records[cid].get("wins", 0)) if records[cid] is Dictionary else 0
		for m in milestones_of(String(cid)):
			if is_milestone_claimable(m, wins, claimed):
				return true
	return false

static func danger_name(d: int) -> String:
	return DANGER_NAMES[clampi(d, 0, DANGER_NAMES.size() - 1)]

static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for a in ACHIEVEMENTS:
		out.append(String(a["id"]))
	return out

static func get_def(ach_id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.get("id", "") == ach_id:
			return a
	return {}

## 反查某名修士对应的解锁成就（初始默认解锁的修士返回空字典）
static func cultivator_unlock_achievement(cid: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.get("reward_type", "") == "cultivator" and a.get("reward_id", "") == cid:
			return a
	return {}

## 反查某件法宝对应的解锁成就（初始默认入池的法宝返回空字典）
static func item_unlock_achievement(item_id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.get("reward_type", "") == "item" and a.get("reward_id", "") == item_id:
			return a
	return {}

## 判定单条成就在当前局与生涯累计下是否达成
## run_ctx 字段：victory(bool), danger(int), wave(int), level(int), kills(int),
##              max_stones(int), max_dodge(float), max_harvest(float)
## career_stats 字段：total_runs(int), total_wins(int), total_kills(int), best_wave(int)
static func is_condition_met(ach_id: String, run_ctx: Dictionary, career_stats: Dictionary) -> bool:
	var victory := bool(run_ctx.get("victory", false))
	var danger := int(run_ctx.get("danger", 0))
	var wave := int(run_ctx.get("wave", 0))
	var level := int(run_ctx.get("level", 1))
	var max_stones := int(run_ctx.get("max_stones", 0))
	var max_dodge := float(run_ctx.get("max_dodge", 0.0))
	var max_harvest := float(run_ctx.get("max_harvest", 0.0))

	var total_runs := int(career_stats.get("total_runs", 0))
	var total_wins := int(career_stats.get("total_wins", 0))
	var total_kills := int(career_stats.get("total_kills", 0))
	var best_wave := maxi(wave, int(career_stats.get("best_wave", 0)))

	match ach_id:
		"ach_cult_meiying":
			return max_dodge >= 0.35 - 0.0001 or total_kills >= 500
		"ach_cult_kuangzhan":
			return total_kills >= 1500
		"ach_cult_duobao":
			return max_stones >= 250
		"ach_cult_duoshe":
			return victory or total_wins >= 1
		"ach_cult_dubi":
			return (victory and danger >= 1)
		"ach_item_pojia":
			return best_wave >= 15
		"ach_item_wuxing":
			return level >= 15
		"ach_item_hunyuan":
			return max_harvest >= 30.0 - 0.0001
		"ach_item_kuilei":
			return total_runs >= 5 or victory or total_wins >= 1
	return false

## 评估本局新达成的成就 ID 列表（已在 already_unlocked 中的不重复返回）
static func evaluate_new_unlocks(run_ctx: Dictionary, career_stats: Dictionary, already_unlocked: Array) -> Array[String]:
	var newly: Array[String] = []
	for a in ACHIEVEMENTS:
		var aid := String(a["id"])
		if aid in already_unlocked:
			continue
		if is_condition_met(aid, run_ctx, career_stats):
			newly.append(aid)
	return newly
