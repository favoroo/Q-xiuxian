class_name EnemyGuideData
extends RefCounted

## 敌人图鉴文案表：id → 一句话威胁描述 + 标签。全 static 纯数据（铁律 2）。
## 名称不在这里抄：读 EnemyData（display / ELITE_POOL.title）与 BOSS/金蟾行，一个概念一个词。
## 出没波次也不抄：MOBS.unlock_wave 与固定节奏（精英 5/15、Boss 10/20）由函数现算，
## 改闸门只动 EnemyData，图鉴跟着走。
## 描述口径：只写玩家实战能观察到的行为（对照各敌人 .tscn 的行为覆写逐条核实过），
## 不写数值细节（血量伤害随波成长，写死就是撒谎）。

const GUIDE: Dictionary = {
	# —— 常规怪（顺序 = EnemyData.MOBS 表序）——
	"slime": {
		"desc": "最常见的妖，贴上来就撞。",
		"tags": ["接触"],
	},
	"danbao": {
		"desc": "贴近会点燃引信自爆，看到地上预警圈立刻离开。",
		"tags": ["自爆", "预警圈"],
	},
	"xiexiu": {
		"desc": "远远扔火球的邪修，别让它安心站桩。",
		"tags": ["远程"],
	},
	"leibeast": {
		"desc": "蓄势后直线猛冲，侧身躲掉冲撞再反击。",
		"tags": ["冲撞"],
	},
	"flower": {
		"desc": "跑得快的花妖，成群黏人。",
		"tags": ["高速"],
	},
	"fengqun": {
		"desc": "又脆又快的小群怪，靠数量填场地。",
		"tags": ["群", "脆"],
	},
	"xueyong": {
		"desc": "死后裂成小怪，尽量在边缘位置击杀它。",
		"tags": ["分裂"],
	},
	"yingmei": {
		"desc": "会闪现到身侧的影魅，注意背后。",
		"tags": ["闪现"],
	},
	"lingyi": {
		"desc": "治疗周围妖群的灵医，优先点掉。",
		"tags": ["治疗", "优先击杀"],
	},
	"guyao": {
		"desc": "擂鼓给同伴加速的鼓妖，先杀它减速敌潮。",
		"tags": ["加速光环"],
	},
	"zhumu": {
		"desc": "不断产卵的百目妖，拖久了场地全是小怪。",
		"tags": ["召唤"],
	},
	# —— 精英（ELITE_POOL 轮换：铁甲 → 赤雷 → 剑煞）——
	"golem": {
		"desc": "血厚体壮的铁甲魔傀，残血变异后会原地震地。",
		"tags": ["精英", "厚血", "震地"],
	},
	"chilei": {
		"desc": "频繁长距离突进的赤雷兽，冲撞伤害极高。",
		"tags": ["精英", "冲撞"],
	},
	"jiansha": {
		"desc": "三连剑气压场的剑煞邪修，别站直线。",
		"tags": ["精英", "远程"],
	},
	# —— 魔君 ——
	"boss": {
		"desc": "每逢整十大波破阵的魔君，半血进入狂暴形态，招式更多更快。",
		"tags": ["Boss", "狂暴"],
	},
	# —— 金蟾 ——
	"jinchan": {
		"desc": "叼着宝就跑的招财金蟾，击杀爆金币；追不上不必硬追。",
		"tags": ["宝藏", "逃跑"],
	},
}

## 图鉴展示顺序：常规 → 精英 → 魔君 → 金蟾
static func catalog_ids() -> Array:
	return ["slime", "danbao", "xiexiu", "leibeast", "flower", "fengqun",
		"xueyong", "yingmei", "lingyi", "guyao", "zhumu",
		"golem", "chilei", "jiansha", "boss", "jinchan"]

## 卡面名称：与播报/数据表同一个词，图鉴不另起花名
static func display_name(eid: String) -> String:
	if EnemyData.MOBS.has(eid):
		return String(EnemyData.MOBS[eid]["display"])
	for e in EnemyData.ELITE_POOL:
		if String(e["id"]) == eid:
			return String(e["display"])
	if eid == "boss":
		return "魔君"
	if eid == "jinchan":
		return "金蟾"
	return eid

## 首次出没波次文案：常规怪读闸门；精英 5/15 波；魔君 10/20 波；金蟾第 3 波起逢场出现
static func first_seen_text(eid: String, endless: bool = false) -> String:
	if EnemyData.MOBS.has(eid):
		var w := int(EnemyData.MOBS[eid].get("unlock_wave", 1))
		return "出没：第 %d 波起" % w if w > 1 else "出没：第 1 波起"
	if eid in ["golem", "chilei", "jiansha"]:
		return "出没：第 5 / 15 波精英劫"
	if eid == "boss":
		return "出没：第 10 / 20 波魔君劫"
	if eid == "jinchan":
		return "出没：第 %d 波起 逢场出现" % int(EnemyData.LOOTER_DEF["min_wave"])
	return ""
