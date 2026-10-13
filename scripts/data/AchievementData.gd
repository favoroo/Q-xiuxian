class_name AchievementData
extends RefCounted

## 成就里程碑与局外解锁数据库（仿土豆兄弟纯成就解锁机制）
## 全部 static 纯函数 —— 不读 autoload、不碰节点，保证单测可确定性断言。
## 设计原则：
##   1. 零局外数值膨胀：成就只解锁新角色（道统）与少量道具入池，不破坏局内难度平衡；
##   2. 初始开放 6 名代表性角色 + 51 件基础道具，其余 12 名进阶角色与 4 件高阶道具通过里程碑解锁；
##   3. 2026-10-12 重设计：成就按「试炼/流派/历练/机缘」四分类（category 字段），
##      纯荣誉成就 reward_type = "none"（只点亮、不发奖励，不碰解锁经济）。

## 危险度档位名号（D0 ~ D5）
const DANGER_NAMES: Array[String] = ["简单", "普通", "困难", "噩梦", "地狱", "极限"]

## 境界称号：按该角色通关过的最高危险度点亮（D0 炼气 ~ D5 渡劫，未通关为空）
const REALM_TITLES: Array[String] = ["炼气", "筑基", "金丹", "元婴", "化神", "渡劫"]

## 成就分类（顺序即「战绩」页分节展示顺序）
const CATEGORY_ORDER: Array[String] = ["trial", "style", "grind", "luck"]
const CATEGORY_NAMES: Dictionary = {
	"trial": "试炼",
	"style": "流派",
	"grind": "历练",
	"luck": "机缘",
}

## 初始默认解锁的 6 名角色
const DEFAULT_CULTIVATORS: Array[String] = [
	"jianchi",
	"shiyue",
	"fuzhen",
	"jinsuanpan",
	"lingzhifu",
	"leifa",
]

## 初始默认进入商店货架池的 51 件道具（高阶出现节奏由 GameBalance.item_tier_weights 回合门槛控制）
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
	"luban_suo",
	"jiguan_hexin",
	# —— 2026-10-11 扩池：以下原为已定义未入池道具（图鉴可见但货架抽不到），按档位补入 ——
	# 普通（tier 1）
	"hupi_qun",
	"lijian_shi",
	"feihuang_shi",
	"juling_fu",
	"yuling_pai",
	"manli_huwan",
	# 稀有（tier 2）
	"jinjing_shi",
	"chenxiang_mu",
	"hantan_yu",
	"dihuo_jing",
	"houtu_he",
	"liren_fu",
	"yinxue_zhu",
	"dingxing_pan",
	"jucai_dai",
	"poxu_lingfu",
	"fanzhen_tongjia",
	"lingbo_xue",
	# 史诗（tier 3）
	"potian_zhui",
	"jingang_zhuo",
	"shenxing_xue",
	"leiling_zhu",
	"juling_zhentu",
	"hunyuan_yiqifu",
	"jingang_fumo_jia",
	# 传说（tier 4）
	"zhuxian_sui",
	"xuanwu_yin",
	"tianji_pan",
	"wuji_tianchuan_zhen",
	# —— 2026-10-11 寻宝流四件（ProgressStore 末尾的 DEFAULT_ITEMS 回灌会让老档也拿到）——
	# 2026-10-12：卸匣锥（砍砸开击数）换成满匣诀（抬开箱掉落），旧 id 由 ProgressStore 读档时剔除。
	"cangbao_tu",
	"naling_zhuo",
	"manxia_jue",
	"dianjin_jue",
]

## 成就定义表（按 category 聚组排布；UI 按 CATEGORY_ORDER 分节展示）
## reward_type: "cultivator"（解锁新道统） | "item"（解锁新道具入池） | "none"（纯荣誉，不发奖励）
const ACHIEVEMENTS: Array[Dictionary] = [
	# ---------------- 试炼：通关与难度挑战 ----------------
	{
		"id": "ach_cult_duoshe",
		"name": "初次通关",
		"cond_desc": "使用任意角色通关1次（完成第20波）",
		"category": "trial",
		"reward_type": "cultivator",
		"reward_id": "duoshe",
		"reward_name": "学者",
		"icon": "res://assets/art/cultivator_duoshe_icon.png",
	},
	{
		"id": "ach_cult_dubi",
		"name": "极限挑战",
		"cond_desc": "通关「普通」或更高难度",
		"category": "trial",
		"reward_type": "cultivator",
		"reward_id": "dubi",
		"reward_name": "狂战士",
		"icon": "res://assets/art/cultivator_dubi_icon.png",
	},
	{
		"id": "ach_feat_nightmare",
		"name": "征服噩梦",
		"cond_desc": "通关「噩梦」或更高难度",
		"category": "trial",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_jingzhe_fu.png",
	},
	{
		"id": "ach_feat_hell",
		"name": "征服地狱",
		"cond_desc": "通关「地狱」或更高难度",
		"category": "trial",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_leihuo_fu.png",
	},
	{
		"id": "ach_feat_extreme",
		"name": "征服极限",
		"cond_desc": "通关「极限」难度",
		"category": "trial",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_jinlei_zhui.png",
	},
	{
		"id": "ach_item_pojia",
		"name": "深入敌后",
		"cond_desc": "单局抵达第15波",
		"category": "trial",
		"reward_type": "item",
		"reward_id": "pojia_zhui",
		"reward_name": "破甲针",
		"icon": "res://assets/art/item_pojia_zhui.png",
	},
	{
		"id": "ach_feat_endless",
		"name": "无尽行者",
		"cond_desc": "无尽模式抵达第25波",
		"category": "trial",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_liuhuo_feijian.png",
	},
	# ---------------- 流派：武器构筑 ----------------
	{
		"id": "ach_cult_juechen",
		"name": "心剑通神",
		"cond_desc": "单局同时上阵剑系武器达到4件",
		"category": "style",
		"reward_type": "cultivator",
		"reward_id": "juechen",
		"reward_name": "绝尘",
		"icon": "res://assets/art/cultivator_juechen_icon.png",
	},
	{
		"id": "ach_cult_fuxiu",
		"name": "万符朝宗",
		"cond_desc": "单局同时上阵弹射类武器达到4件",
		"category": "style",
		"reward_type": "cultivator",
		"reward_id": "fuxiu",
		"reward_name": "灵符子",
		"icon": "res://assets/art/cultivator_fuxiu_icon.png",
	},
	{
		"id": "ach_cult_bawang",
		"name": "横扫千军",
		"cond_desc": "单局同时上阵横扫类武器达到4件",
		"category": "style",
		"reward_type": "cultivator",
		"reward_id": "bawang",
		"reward_name": "霸王",
		"icon": "res://assets/art/cultivator_bawang_icon.png",
	},
	{
		"id": "ach_cult_jiguan",
		"name": "巧夺天工",
		"cond_desc": "单局同时上阵机关或召唤类武器达到4件",
		"category": "style",
		"reward_type": "cultivator",
		"reward_id": "jiguan",
		"reward_name": "机关师",
		"icon": "res://assets/art/cultivator_jiguan_icon.png",
	},
	{
		"id": "ach_style_thunder",
		"name": "五雷正法",
		"cond_desc": "单局同时上阵雷法类武器达到4件",
		"category": "style",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_chunlei_gu.png",
	},
	{
		"id": "ach_style_wuxing",
		"name": "五行同阵",
		"cond_desc": "单局同时上阵金木水火土五行武器各至少1件",
		"category": "style",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_jianzhen_pan.png",
	},
	# ---------------- 历练：生涯累计 ----------------
	{
		"id": "ach_cult_meiying",
		"name": "影行者",
		"cond_desc": "单局有效闪避达到35%，或累计击杀500只敌人",
		"category": "grind",
		"reward_type": "cultivator",
		"reward_id": "meiying",
		"reward_name": "影者",
		"icon": "res://assets/art/cultivator_meiying_icon.png",
	},
	{
		"id": "ach_cult_kuangzhan",
		"name": "百战不殆",
		"cond_desc": "累计击杀达到1500只",
		"category": "grind",
		"reward_type": "cultivator",
		"reward_id": "kuangzhan",
		"reward_name": "蛮兵",
		"icon": "res://assets/art/cultivator_kuangzhan_icon.png",
	},
	{
		"id": "ach_grind_kills",
		"name": "千杀灭生",
		"cond_desc": "累计击杀达到5000只",
		"category": "grind",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_kaishan_fu.png",
	},
	{
		"id": "ach_grind_wins",
		"name": "十渡天劫",
		"cond_desc": "累计通关达到10次",
		"category": "grind",
		"reward_type": "none",
		"reward_id": "",
		"reward_name": "",
		"icon": "res://assets/art/weapon_bengshan_jian.png",
	},
	{
		"id": "ach_item_kuilei",
		"name": "九死一生",
		"cond_desc": "累计游玩5局，或任意通关1次",
		"category": "grind",
		"reward_type": "item",
		"reward_id": "tisi_kuilei",
		"reward_name": "替身娃娃",
		"icon": "res://assets/art/item_tisi_kuilei.png",
	},
	{
		"id": "ach_item_wuxing",
		"name": "经验日深",
		"cond_desc": "单局等级达到15级",
		"category": "grind",
		"reward_type": "item",
		"reward_id": "wuxing_pei",
		"reward_name": "五行石",
		"icon": "res://assets/art/item_wuxing_pei.png",
	},
	# ---------------- 机缘：财富与生存 ----------------
	{
		"id": "ach_cult_duobao",
		"name": "富甲一方",
		"cond_desc": "单局金币达到250枚",
		"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "duobao",
		"reward_name": "收藏家",
		"icon": "res://assets/art/cultivator_duobao_icon.png",
	},
	{
		"id": "ach_cult_shoucainu",
		"name": "日进斗金",
		"cond_desc": "单局持有金币达到400枚",
		"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "shoucainu",
		"reward_name": "守财奴",
		"icon": "res://assets/art/cultivator_shoucainu_icon.png",
	},
	{
		"id": "ach_item_hunyuan",
		"name": "收益满载",
		"cond_desc": "单局收益达到30点",
		"category": "luck",
		"reward_type": "item",
		"reward_id": "hunyuan_zhu",
		"reward_name": "万能珠",
		"icon": "res://assets/art/item_hunyuan_zhu.png",
	},
	{
		"id": "ach_cult_yaowang",
		"name": "悬壶济世",
		"cond_desc": "单局累计生命回复达到200点",
		"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "yaowang",
		"reward_name": "药王",
		"icon": "res://assets/art/cultivator_yaowang_icon.png",
	},
	{
		"id": "ach_cult_shixue",
		"name": "浴血修罗",
		"cond_desc": "单局累计承受伤害达到25次",
		"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "shixue",
		"reward_name": "嗜血魔修",
		"icon": "res://assets/art/cultivator_shixue_icon.png",
	},
]

## 通关过的最高危险度对应的境界称号（-1 未通关返回空串）
static func realm_for_danger(d: int) -> String:
	if d < 0:
		return ""
	return REALM_TITLES[clampi(d, 0, REALM_TITLES.size() - 1)]

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

## 反查某名角色对应的解锁成就（初始默认解锁的角色返回空字典）
static func cultivator_unlock_achievement(cid: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.get("reward_type", "") == "cultivator" and a.get("reward_id", "") == cid:
			return a
	return {}

## 反查某件道具对应的解锁成就（初始默认入池的道具返回空字典）
static func item_unlock_achievement(item_id: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.get("reward_type", "") == "item" and a.get("reward_id", "") == item_id:
			return a
	return {}

## 判定单条成就在当前局与生涯累计下是否达成
## run_ctx 字段：victory(bool), endless(bool), danger(int), wave(int), level(int), kills(int),
##              max_stones(int), max_dodge(float), max_harvest(float),
##              max_class_counts(Dictionary {器类tag: 同时上阵峰值}),
##              max_element_spread(int 单局同时上阵的五行元素种数峰值)
## career_stats 字段：total_runs(int), total_wins(int), total_kills(int), best_wave(int)
static func is_condition_met(ach_id: String, run_ctx: Dictionary, career_stats: Dictionary) -> bool:
	var victory := bool(run_ctx.get("victory", false))
	var endless := bool(run_ctx.get("endless", false))
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
		"ach_cult_duoshe":
			return victory or total_wins >= 1
		"ach_cult_dubi":
			return (victory and danger >= 1)
		"ach_feat_nightmare":
			return victory and danger >= 3
		"ach_feat_hell":
			return victory and danger >= 4
		"ach_feat_extreme":
			return victory and danger >= 5
		"ach_item_pojia":
			return best_wave >= 15
		"ach_feat_endless":
			return endless and wave >= 25
		"ach_cult_juechen":
			return int(Dictionary(run_ctx.get("max_class_counts", {})).get("sword", 0)) >= 4
		"ach_cult_fuxiu":
			return int(Dictionary(run_ctx.get("max_class_counts", {})).get("talisman", 0)) >= 4
		"ach_cult_bawang":
			return int(Dictionary(run_ctx.get("max_class_counts", {})).get("wide", 0)) >= 4
		"ach_cult_jiguan":
			return int(run_ctx.get("max_summons", 0)) >= 4
		"ach_style_thunder":
			return int(Dictionary(run_ctx.get("max_class_counts", {})).get("thunder", 0)) >= 4
		"ach_style_wuxing":
			return int(run_ctx.get("max_element_spread", 0)) >= 5
		"ach_cult_meiying":
			return max_dodge >= 0.35 - 0.0001 or total_kills >= 500
		"ach_cult_kuangzhan":
			return total_kills >= 1500
		"ach_grind_kills":
			return total_kills >= 5000
		"ach_grind_wins":
			return total_wins >= 10
		"ach_item_kuilei":
			return total_runs >= 5 or victory or total_wins >= 1
		"ach_item_wuxing":
			return level >= 15
		"ach_cult_duobao":
			return max_stones >= 250
		"ach_cult_shoucainu":
			return max_stones >= 400
		"ach_item_hunyuan":
			return max_harvest >= 30.0 - 0.0001
		"ach_cult_yaowang":
			return float(run_ctx.get("hp_healed", 0.0)) >= 200.0 - 0.0001
		"ach_cult_shixue":
			return int(run_ctx.get("damage_taken_count", 0)) >= 25
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
