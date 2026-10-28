class_name EnemyGuideData
extends RefCounted

## 敌人图鉴文案表：id → 威胁描述 + 标签 + 攻击方式/皮实度/移速/应对。全 static 纯数据（铁律 2）。
## 名称不在这里抄：读 EnemyData（display / ELITE_POOL.title）与 BOSS/金蟾行，一个概念一个词。
## 出没波次也不抄：MOBS.unlock_wave 与固定节奏（精英 5/15、Boss 10/20）由函数现算，
## 改闸门只动 EnemyData，图鉴跟着走。
## 描述口径：只写玩家实战能观察到的行为（对照各敌人 .tscn 的行为覆写逐条核实过），
## 不写数值细节（血量伤害随波成长，写死就是撒谎）。
## 强度口径：tough/swift 是「定性档位」不是数字——由 .tscn 出厂值 + 行为开关归档，
## 档位词必须落在 TOUGH_TIERS / SPEED_TIERS 里（判据钉住，UI 按档位取色）。
## desc 里【】包的是危险机制词，详情卡渲染时染朱砂强调（与 tags 同源，不另造词）。

## 皮实度档位（从低到高）；移速档位（从快到慢）。色档字典在 ManualDialog 侧按词取色。
const TOUGH_TIERS: Array[String] = ["脆", "普通", "厚", "极厚"]
const SPEED_TIERS: Array[String] = ["极快", "快", "寻常", "慢"]

const GUIDE: Dictionary = {
	# —— 常规怪（顺序 = EnemyData.MOBS 表序）——
	"slime": {
		"desc": "最常见的妖，贴上来就【撞】。",
		"tags": ["接触"],
		"attack": "接触撞击",
		"tough": "普通",
		"swift": "寻常",
		"counter": "顺手清掉，别攒成堆",
	},
	"danbao": {
		"desc": "贴近会点燃【引信】【自爆】，看到地上【预警圈】立刻离开。引信中途点碎它会【溅射一圈丹火】。",
		"tags": ["自爆", "预警圈"],
		"attack": "贴身自爆·被杀溅射",
		"tough": "普通",
		"swift": "快",
		"counter": "预警圈亮起就走；要在远处打它，打完记得躲开溅出的丹火",
	},
	"xiexiu": {
		"desc": "远远扔【火球】的邪修，出手前会【提亮蓄力】，别让它安心【站桩】。",
		"tags": ["远程"],
		"attack": "远程火弹",
		"tough": "普通",
		"swift": "寻常",
		"counter": "它发亮就是要出手，横向走两步就躲开；贴身打断更稳",
	},
	"leibeast": {
		"desc": "蓄势后【直线猛冲】，冲的方向会【算上你的跑位】，匀速直线跑要吃亏。",
		"tags": ["冲撞", "预判"],
		"attack": "冲撞撕咬",
		"tough": "厚",
		"swift": "寻常",
		"counter": "预警带【定住】就是要冲了，急停或变向就能躲开",
	},
	"flower": {
		"desc": "跑得快的花妖，成群【黏人】。",
		"tags": ["高速"],
		"attack": "高速撞击",
		"tough": "普通",
		"swift": "快",
		"counter": "成群黏人，用范围伤害清",
	},
	"fengqun": {
		"desc": "又脆又快的小群怪，靠【数量】填场地。",
		"tags": ["群", "脆"],
		"attack": "群涌撞击",
		"tough": "脆",
		"swift": "极快",
		"counter": "单个很脆，范围伤害收一片",
	},
	"xueyong": {
		"desc": "死后【裂成小怪】，尽量在边缘位置击杀它。",
		"tags": ["分裂"],
		"attack": "接触·死亡分裂",
		"tough": "厚",
		"swift": "慢",
		"counter": "在场地边缘杀，别让它裂进人群",
	},
	"yingmei": {
		"desc": "会【闪现】到身侧的影魅，注意背后。",
		"tags": ["闪现"],
		"attack": "闪现贴身",
		"tough": "普通",
		"swift": "寻常",
		"counter": "留意背后，闪现落地就拉开",
	},
	"lingyi": {
		"desc": "【治疗】周围妖群的灵医，优先点掉。",
		"tags": ["治疗", "优先击杀"],
		"attack": "群体治疗",
		"tough": "普通",
		"swift": "寻常",
		"counter": "优先点掉，别让妖群回血",
	},
	"guyao": {
		"desc": "擂鼓给同伴【加速】的鼓妖，先杀它减速敌潮。",
		"tags": ["加速光环"],
		"attack": "加速光环",
		"tough": "厚",
		"swift": "慢",
		"counter": "先杀它，敌潮速度立刻掉下来",
	},
	"duyao": {
		"desc": "往你脚下扔【毒潭】的毒妖，站进去会持续掉血。",
		"tags": ["持续伤害", "地面区域"],
		"attack": "投毒·持续伤害区域",
		"tough": "普通",
		"swift": "慢",
		"counter": "看到绿圈预告就走开，别站在毒里打",
	},
	"zhumu": {
		"desc": "不断【产卵】的百目妖，拖久了场地全是小怪。",
		"tags": ["召唤"],
		"attack": "召唤小怪",
		"tough": "极厚",
		"swift": "慢",
		"counter": "越早杀越好，拖久全场小怪",
	},
	"hanpo": {
		"desc": "周身环绕冰魄的寒魄妖，射出【三连冰魄剑气】，被击破时【溅射冰晶】。",
		"tags": ["远程", "弧线", "溅射"],
		"attack": "三连冰魄剑·死后溅射",
		"tough": "普通",
		"swift": "寻常",
		"counter": "横向绕走躲开弧线冰魄，击杀后注意规避溅射冰晶",
	},
	"mowei": {
		"desc": "重装持盾的血煞魔卫，擅长【预判冲撞】与近身【重震地】。",
		"tags": ["重装", "冲撞", "震地"],
		"attack": "预判冲撞·震地波",
		"tough": "极厚",
		"swift": "快",
		"counter": "看清冲刺预警线变向，震地预警亮起立刻远离",
	},
	# —— 精英（ELITE_POOL 轮换：铁甲 → 赤雷 → 剑煞 → 玄冥）——
	"golem": {
		"desc": "血厚体壮的铁甲魔傀，【残血变异】后会原地震地。",
		"tags": ["精英", "厚血", "震地"],
		"attack": "重拳·残血震地",
		"tough": "极厚",
		"swift": "慢",
		"counter": "慢慢磨，残血变异后注意离地",
	},
	"chilei": {
		"desc": "凶暴狂怒的赤雷巨兽，连续发动【多段折返突进】，冲撞附带预判且伤害极高。",
		"tags": ["精英", "冲撞", "连冲"],
		"attack": "多段折返突进",
		"tough": "极厚",
		"swift": "快",
		"counter": "看清每次定身预警的转向，折返连续变向规避，切忌直线逃跑",
	},
	"jiansha": {
		"desc": "【三连剑气】压场的剑煞邪修，别站直线。",
		"tags": ["精英", "远程"],
		"attack": "三连剑气",
		"tough": "极厚",
		"swift": "寻常",
		"counter": "别站直线，绕开剑气再贴",
	},
	"xuanming": {
		"desc": "玄冥魔尊身负冥雷环与落石大阵，【残血变异】后招式狂暴并施展【瞬身回斩】。",
		"tags": ["精英", "环弹", "落石", "瞬身"],
		"attack": "冥雷环·落石·瞬身",
		"tough": "极厚",
		"swift": "寻常",
		"counter": "保持横向机动避开落石，狂暴后警惕身侧瞬身回斩",
	},
	"xingpan": {
		"desc": "锚定场中【寸步不动】的玄天星盘，持续喷吐【旋转弧线弹幕环】与扇形星矢，残血后加召星陨落石。",
		"tags": ["精英", "炮台", "弹幕环"],
		"attack": "旋转星环·连射",
		"tough": "极厚",
		"swift": "慢",
		"counter": "它不会移动，看准弧线弹幕缝隙贴近全力拆毁",
	},
	"wandu": {
		"desc": "远距游走的万毒祭司，频繁铺设【剧毒沼泽】与【雷煞禁区】割裂场地，并召唤毒傀护卫。",
		"tags": ["精英", "毒阵", "召唤"],
		"attack": "毒沼·禁区·唤傀",
		"tough": "极厚",
		"swift": "寻常",
		"counter": "拖久了全场无处落脚，优先突进斩首祭司本体",
	},
	# —— 魔君 ——
	"boss": {
		"desc": "镇守十波大关与无尽深层的诸天魔君（赤炎、修罗、千机、万蛊、剑魄、心魔），各有专属杀招与【半血狂暴】质变。",
		"tags": ["Boss", "狂暴"],
		"attack": "多段招式·狂暴",
		"tough": "极厚",
		"swift": "慢",
		"counter": "半血后更密，留好位移和回复",
	},
	# —— 金蟾 ——
	"jinchan": {
		"desc": "叼着宝就【跑】的招财金蟾，击杀爆金币；追不上不必硬追。",
		"tags": ["宝藏", "逃跑"],
		"attack": "逃跑不接战",
		"tough": "普通",
		"swift": "极快",
		"counter": "追不上别硬追，杀掉爆金币",
	},
}

## 图鉴展示顺序：常规 → 精英 → 魔君 → 金蟾
static func catalog_ids() -> Array:
	# 顺序必须与 EnemyData.MOBS 表序一致（判据 EnemyCodexCheck 钉这条：图鉴与配比表漂移
	# 会让新怪静默不出现在图鉴里）
	return ["slime", "danbao", "xiexiu", "leibeast", "flower", "fengqun",
		"xueyong", "yingmei", "lingyi", "guyao", "duyao", "zhumu",
		"hanpo", "mowei",
		"golem", "chilei", "jiansha", "xuanming", "xingpan", "wandu", "boss", "jinchan"]

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
	if eid in ["golem", "chilei", "jiansha", "xuanming", "xingpan", "wandu"]:
		return "出没：第 5 / 15 波起 精英劫"
	if eid == "boss":
		return "出没：第 10 到 40 波及无尽魔君劫"
	if eid == "jinchan":
		return "出没：第 %d 波起 逢场出现" % int(EnemyData.LOOTER_DEF["min_wave"])
	return ""
