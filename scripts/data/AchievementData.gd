class_name AchievementData
extends RefCounted

## 成就里程碑与局外解锁数据库（仿土豆兄弟纯成就解锁机制）
## 全部 static 纯函数 —— 不读 autoload、不碰节点，保证单测可确定性断言。
## 设计原则：
##   1. 零局外数值膨胀：成就只解锁新角色（道统）/ 道具入池 / 武器入池，不破坏局内难度平衡；
##   2. 2026-10-25 新手节奏重做：初始只开放 4 名直观基础角色 + 86 件道具 + 64 把武器，
##      其余 17 名角色 / 16 件道具 / 6 把武器全部由成就解锁 —— **39 条成就零纯荣誉**，
##      每条达成都有实物回报，前几局几乎每局都能解锁点什么。
##   3. 2026-10-12 重设计：成就按「试炼/流派/历练/机缘」四分类（category 字段）。
##   4. 2026-10-15 幽默化重写：全量 cond_desc 文案改为幽默风格，新增 6 条趣味成就。
##   5. 2026-10-24 追加 6 条硬核挑战成就（噩梦无伤/零消费/单武器/零技能/无尽40波/零道具）。
##   6. 2026-10-25 原 18 条纯荣誉成就全部挂上实物奖励（道具/武器），reward_type = "none" 仅作兜底保留。

## 危险度档位名号（D0 ~ D3，2026-10-20 由 6 档收缩为 4 档）
const DANGER_NAMES: Array[String] = ["简单", "普通", "困难", "噩梦"]

## 境界称号：按该角色通关过的最高危险度点亮（D0 炼气 ~ D3 元婴，未通关为空）
const REALM_TITLES: Array[String] = ["炼气", "筑基", "金丹", "元婴"]

## 成就分类（顺序即「战绩」页分节展示顺序）
const CATEGORY_ORDER: Array[String] = ["trial", "style", "grind", "luck"]
const CATEGORY_NAMES: Dictionary = {
	"trial": "试炼",
	"style": "流派",
	"grind": "历练",
	"luck": "机缘",
}

## 初始默认解锁的 4 名角色（2026-10-25 新手节奏重做：8 → 4）
## 只留「机制最直白、一句话能说清」的四条入门道统：近战 / 肉盾 / 环绕 / 范围爆发。
## 原默认的商人（利息）、灵植夫（种树寻宝）、苦行僧（站定）、御兽师（灵兽栏）
## 四个进阶道统改由前几局就能达成的低门槛成就解锁 —— 见 ach_cult_jinsuanpan 等四条。
const DEFAULT_CULTIVATORS: Array[String] = [
	"jianchi",
	"shiyue",
	"fuzhen",
	"leifa",
]

## 初始默认进入商店货架池的道具（高阶出现节奏由 GameBalance.item_tier_weights 回合门槛控制）
const DEFAULT_ITEMS: Array[String] = [
	"jubaopen",
	"mibao_luopan",
	"jifeng_xue",
	"qingxin_cha",
	"zhekou_yufu",
	"kuangxue_dan",
	"guijia_fu",
	"tongxuan_ling",
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
	"xuewen_fu",
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
	# —— 2026-10-11 寻宝流（ProgressStore 末尾的 DEFAULT_ITEMS 回灌会让老档也拿到）——
		# 2026-10-12：卸匣锥（砍砸开击数）换成满匣诀（抬开箱掉落），旧 id 由 ProgressStore 读档时剔除。
		# 2026-10-22：纳灵盘（naling_zhuo）整件移除（自动吸附掉落物对玩家无价值），旧 id 由读档剔除。
		"cangbao_tu",
		"dianjin_jue",
		# —— 2026-10-13 扩池：补齐灵兽系与 10-12 转化/站定/联动体系，彻底消灭未入池死卡 ——
		# 普通（tier 1）
		"lingshou_kouliang",
		"dazuo_putuan",
		# 稀有（tier 2）
		"yushou_ling",
		"jifeng_shoufu",
		"ruding_xiang",
		"lingsui_danqi",
		"tiangong_fatiao",
		"kaishan_jianyi",
		"ningshen_fu",
		# 史诗（tier 3）
		"wanshou_long",
		"jifeng_ren",
		"huanying_ling",
		"shanyue_jia",
		"jubao_pen",
		"ranxue_fu",
		"budong_yin",
		"taijin_jing",
		"yimu_sui",
		"xuanshui_po",
		"lihuo_shenjing",
		"houtu_shenyuan",
			"xuanwu_fashan",
			"jingang_shenxiang",
			"sanmei_guizhen",
		"liuyun_qianyin",
		"jinmang_souhun",
		"qianfu_lianhuan",
		# 2026-10-20 新增通用强力件（不挑流派，任何构筑都能吃）
		"xuantie_ling",
		# 2026-10-25 新手节奏重做：不灭金身 / 天罡战意 移出初始池，改由成就解锁（见 ach_luck_turtle / ach_grind_kills）
		# 2026-10-21 流派补齐（近战/远程/元素/召唤/机关/技能/闪避/角色专属）
		"tieshou",
		"lingyan_fu",
		"tongling",
		"pojun_fu",
		"liannu_shi",
		"wuxing_sha",
		"tongji_chi",
		"jingxin_fu",
		"huansha",
		"lingcao_dai",
		"tianji_suo",
		# 2026-10-25 新手节奏重做：万灵幡 / 战旗 / 藏真卷 / 血海符 / 道韵经 / 万石剑 移出初始池，
		# 改由成就解锁（见 ach_style_omni / ach_feat_nightmare / ach_feat_skill_abstain /
		# ach_style_rebel / ach_feat_thrift / ach_feat_lone_weapon）
		# 传说（tier 4）
		# 2026-10-25 新手节奏重做：血蟠蛊玉 / 裂魂铃 / 磐石印 / 突破蛊玉 移出初始池，改由成就解锁
		# （见 ach_grind_wins / ach_feat_endless / ach_style_loner / ach_grind_level20）
	]

## 初始默认进入商店武器池的武器（2026-10-25 新增）
## 6 把开局自选武器（WeaponData.STARTER_IDS）始终可用、不在此表也不受成就门控 ——
## 它们是每个器类的入门件，锁掉会让对应流派开局无武器可选。
## 锁定的 6 把全部是「同器类里已经有 ≥4 把别的可用」的高阶招牌件，解锁前商店抽不到；
## 由 6 条硬核挑战成就发放（见 ach_feat_nodamage 等）。
const LOCKED_WEAPONS: Array[String] = [
	"jianling",          # 剑灵 · 环绕/剑系/金 —— 金光护体（无伤通关）
	"jinlei_zhui",       # 金雷锥 · 雷法/金 —— 碎梦无痕（噩梦无伤通关）
	"bihai_chaoyindi",   # 音笛 · 雷法/水 —— 肝穿地心（无尽 40 波）
	"kuilei_shou",       # 傀儡兽 · 机关/御灵/土 —— 五雷正法（单局 4 件雷法）
	"fantian_yin",       # 巨印 · 广域/土 —— 五行同阵（单局五行各 1 件）
	"jianzhen_pan",      # 剑阵盘 · 机关/剑系/金 —— 两袖清风（通关时零法宝）
]

## 成就定义表（按 category 聚组排布；UI 按 CATEGORY_ORDER 分节展示）
## reward_type: "cultivator"（解锁新道统） | "item"（解锁新道具入池） | "weapon"（解锁新武器入池）
##              | "none"（纯荣誉，不发奖励 —— 2026-10-25 起已无条目使用，保留作兜底）
const ACHIEVEMENTS: Array[Dictionary] = [
	# ---------------- 试炼：通关与难度挑战 ----------------
		{
			"id": "ach_cult_duoshe",
			"name": "羽化初登",
			"cond_desc": "第一次在第20波活下来——恭喜，你终于不是炮灰了",
			"category": "trial",
		"reward_type": "cultivator",
		"reward_id": "duoshe",
		"reward_name": "学者",
		"icon": "res://assets/art/cultivator_duoshe_icon.png",
	},
		{
			"id": "ach_cult_dubi",
			"name": "明知山有虎",
			"cond_desc": "通关「普通」或更高难度——修仙哪有不疯的，你先疯了一步",
			"category": "trial",
		"reward_type": "cultivator",
		"reward_id": "dubi",
		"reward_name": "狂战士",
		"icon": "res://assets/art/cultivator_dubi_icon.png",
	},
		{
			"id": "ach_feat_nightmare",
			"name": "噩梦常客",
			"cond_desc": "通关「噩梦」难度——你在梦里杀怪，醒着也一样",
			"category": "trial",
			"reward_type": "item",
			"reward_id": "zhanqi",
			"reward_name": "战旗",
			"icon": "res://assets/art/weapon_jingzhe_fu.png",
		},
		{
			"id": "ach_item_pojia",
			"name": "深入敌后",
			"cond_desc": "单局打到第15波——怪潮怀疑你开了挂",
			"category": "trial",
		"reward_type": "item",
		"reward_id": "pojia_zhui",
		"reward_name": "破甲针",
		"icon": "res://assets/art/item_pojia_zhui.png",
	},
		{
			"id": "ach_feat_endless",
			"name": "肝帝降临",
			"cond_desc": "无尽模式打到第25波——肝在哭，但你在笑",
			"category": "trial",
			"reward_type": "item",
			"reward_id": "liehun_ling",
			"reward_name": "裂魂铃",
			"icon": "res://assets/art/weapon_liuhuo_feijian.png",
		},
		{
			"id": "ach_feat_nodamage",
			"name": "金光护体",
			"cond_desc": "无伤通关一整局——怪物打你像在给护体金光抛光",
			"category": "trial",
			"reward_type": "weapon",
			"reward_id": "jianling",
			"reward_name": "剑灵",
			"icon": "res://assets/art/item_jingang_fumo_jia.png",
		},
		{
			"id": "ach_feat_nightmare_flawless",
			"name": "碎梦无痕",
			"cond_desc": "在「噩梦」难度下无伤通关——怪物打不到你，只好回去写检讨",
			"category": "trial",
			"reward_type": "weapon",
			"reward_id": "jinlei_zhui",
			"reward_name": "金雷锥",
			"icon": "res://assets/art/item_jingang_shenxiang.png",
		},
		{
			"id": "ach_feat_endless_40",
			"name": "肝穿地心",
			"cond_desc": "无尽模式打到第40波——肝已经捐给修仙界了，署名还是你",
			"category": "trial",
			"reward_type": "weapon",
			"reward_id": "bihai_chaoyindi",
			"reward_name": "音笛",
			"icon": "res://assets/art/weapon_liuhuo_feijian.png",
		},
		# ---------------- 新手起步：前几局就能达成，让新玩家一直有「下一次解锁」 ----------------
		{
			"id": "ach_cult_yushou",
			"name": "初入山门",
			"cond_desc": "单局打到第5波——山门刚开，你就知道路怎么走了",
			"category": "trial",
			"reward_type": "cultivator",
			"reward_id": "yushou",
			"reward_name": "御兽师",
			"icon": "res://assets/art/cultivator_yushou_icon.png",
		},
		{
			"id": "ach_cult_lingzhifu",
			"name": "渐入佳境",
			"cond_desc": "单局打到第8波——开始有点修仙的样子了",
			"category": "trial",
			"reward_type": "cultivator",
			"reward_id": "lingzhifu",
			"reward_name": "灵植夫",
			"icon": "res://assets/art/cultivator_lingzhifu_icon.png",
		},
	# ---------------- 流派：武器构筑 ----------------
		{
			"id": "ach_cult_juechen",
			"name": "心剑通神",
			"cond_desc": "单局同时上阵4件剑系武器——你已与剑合为一体",
			"category": "style",
		"reward_type": "cultivator",
		"reward_id": "juechen",
		"reward_name": "绝尘",
		"icon": "res://assets/art/cultivator_juechen_icon.png",
	},
		{
			"id": "ach_cult_fuxiu",
			"name": "万符朝宗",
			"cond_desc": "单局同时上阵4件弹射类武器——弹丸满天飞，怪看不清路",
			"category": "style",
		"reward_type": "cultivator",
		"reward_id": "fuxiu",
		"reward_name": "灵符子",
		"icon": "res://assets/art/cultivator_fuxiu_icon.png",
	},
		{
			"id": "ach_cult_bawang",
			"name": "横扫千军",
			"cond_desc": "单局同时上阵4件横扫类武器——你不是在战斗，是在打扫卫生",
			"category": "style",
		"reward_type": "cultivator",
		"reward_id": "bawang",
		"reward_name": "霸王",
		"icon": "res://assets/art/cultivator_bawang_icon.png",
	},
		{
			"id": "ach_cult_jiguan",
			"name": "巧夺天工",
			"cond_desc": "单局同时上阵4件机关或召唤类武器——你不再是修士，你是包工头",
			"category": "style",
		"reward_type": "cultivator",
		"reward_id": "jiguan",
		"reward_name": "机关师",
		"icon": "res://assets/art/cultivator_jiguan_icon.png",
	},
		{
			"id": "ach_style_thunder",
			"name": "五雷正法",
			"cond_desc": "单局同时上阵4件雷法类武器——令尊是雷公本人？",
			"category": "style",
			"reward_type": "weapon",
			"reward_id": "kuilei_shou",
			"reward_name": "傀儡兽",
			"icon": "res://assets/art/weapon_chunlei_gu.png",
		},
		{
			"id": "ach_style_wuxing",
			"name": "五行同阵",
			"cond_desc": "单局金木水火土五行各带1件——五行相生相克，你是中间那个",
			"category": "style",
			"reward_type": "weapon",
			"reward_id": "fantian_yin",
			"reward_name": "巨印",
			"icon": "res://assets/art/weapon_jianzhen_pan.png",
		},
		{
			"id": "ach_style_rebel",
			"name": "万法由心",
			"cond_desc": "自由搭配随行技能通关3次——万法无常，随心而动",
			"category": "style",
			"reward_type": "item",
			"reward_id": "xuehai_fu",
			"reward_name": "血海符",
			"icon": "res://assets/art/skill_gale.png",
		},
		{
			"id": "ach_style_loner",
			"name": "独行侠",
			"cond_desc": "不带任何召唤或机关武器通关——一个人修仙，一个人渡劫",
			"category": "style",
			"reward_type": "item",
			"reward_id": "panshi_yin",
			"reward_name": "磐石印",
			"icon": "res://assets/art/weapon_liuhuo_feijian.png",
		},
		{
			"id": "ach_style_omni",
			"name": "万器宗师",
			"cond_desc": "单局同时拥有全部六系武器——武器架比万宝楼还全",
			"category": "style",
			"reward_type": "item",
			"reward_id": "wanling_fan",
			"reward_name": "万灵幡",
			"icon": "res://assets/art/weapon_jianzhen_pan.png",
		},
		{
			"id": "ach_cult_sanxiu",
			"name": "百家杂艺",
			"cond_desc": "单局同时上阵4种不同器类的武器——哪派都沾一点，哪派都不深交",
			"category": "style",
			"reward_type": "cultivator",
			"reward_id": "sanxiu",
			"reward_name": "散修",
			"icon": "res://assets/art/cultivator_sanxiu_icon.png",
		},
		{
			"id": "ach_feat_lone_weapon",
			"name": "孤剑走天涯",
			"cond_desc": "只带一件武器通关——武器栏空得能跑马",
			"category": "style",
			"reward_type": "item",
			"reward_id": "wanshi_jian",
			"reward_name": "万矢箭",
			"icon": "res://assets/art/weapon_qingteng_jian.png",
		},
		{
			"id": "ach_feat_skill_abstain",
			"name": "手指休假",
			"cond_desc": "通关全程一次技能键都没按——手指说它这局只负责拿手机",
			"category": "style",
			"reward_type": "item",
			"reward_id": "cangzhen_juan",
			"reward_name": "藏珍卷",
			"icon": "res://assets/art/skill_dash.png",
		},
		{
			"id": "ach_feat_no_items",
			"name": "两袖清风",
			"cond_desc": "通关时一件法宝都没带——背包比脸还干净",
			"category": "style",
			"reward_type": "weapon",
			"reward_id": "jianzhen_pan",
			"reward_name": "剑阵盘",
			"icon": "res://assets/art/item_wujian_shi.png",
		},
	# ---------------- 历练：生涯累计 ----------------
		{
			"id": "ach_cult_meiying",
			"name": "影行者",
			"cond_desc": "单局闪避率35%以上，或累计击杀500只——跑得比兔子快，咬得比蛇狠",
			"category": "grind",
		"reward_type": "cultivator",
		"reward_id": "meiying",
		"reward_name": "影者",
		"icon": "res://assets/art/cultivator_meiying_icon.png",
	},
		{
			"id": "ach_cult_kuangzhan",
			"name": "百战不殆",
			"cond_desc": "累计击杀1500只——你数不清送走了多少怪，怪也数不清",
			"category": "grind",
		"reward_type": "cultivator",
		"reward_id": "kuangzhan",
		"reward_name": "蛮兵",
		"icon": "res://assets/art/cultivator_kuangzhan_icon.png",
	},
		{
			"id": "ach_grind_kills",
			"name": "千杀灭生",
			"cond_desc": "累计击杀5000只——你就是这片修仙界的瘟疫，好消息那种",
			"category": "grind",
			"reward_type": "item",
			"reward_id": "tiangang_zhanyi",
			"reward_name": "天罡战意",
			"icon": "res://assets/art/weapon_kaishan_fu.png",
		},
		{
			"id": "ach_grind_wins",
			"name": "十渡天劫",
			"cond_desc": "累计通关10次——老天爷劈了你十次都没劈死，开始考虑换人了",
			"category": "grind",
			"reward_type": "item",
			"reward_id": "xuepan_guyu",
			"reward_name": "血盘古玉",
			"icon": "res://assets/art/weapon_bengshan_jian.png",
		},
		{
			"id": "ach_item_kuilei",
			"name": "九死一生",
			"cond_desc": "累计游玩5局，或通关1次——死了很多次，但活下来了，这就是修仙",
			"category": "grind",
		"reward_type": "item",
		"reward_id": "tisi_kuilei",
		"reward_name": "替身娃娃",
		"icon": "res://assets/art/item_tisi_kuilei.png",
	},
		{
			"id": "ach_item_wuxing",
			"name": "经验日深",
			"cond_desc": "单局升到15级——经验珠吃得比饭还多",
			"category": "grind",
		"reward_type": "item",
		"reward_id": "wuxing_pei",
		"reward_name": "五行石",
		"icon": "res://assets/art/item_wuxing_pei.png",
		},
		{
			"id": "ach_grind_level20",
			"name": "升级狂魔",
			"cond_desc": "单局升到20级——你的经验槽怕不是连了水管",
			"category": "grind",
			"reward_type": "item",
			"reward_id": "tupo_guyu",
			"reward_name": "突破古玉",
			"icon": "res://assets/art/weapon_bengshan_jian.png",
		},
	# ---------------- 机缘：财富与生存 ----------------
		{
			"id": "ach_cult_duobao",
			"name": "富甲一方",
			"cond_desc": "单局攒够250枚金币——你修的不是仙，是钱包",
			"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "duobao",
		"reward_name": "收藏家",
		"icon": "res://assets/art/cultivator_duobao_icon.png",
	},
		{
			"id": "ach_cult_shoucainu",
			"name": "日进斗金",
			"cond_desc": "单局持有400枚金币——这么多钱花不出去，急死个人",
			"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "shoucainu",
		"reward_name": "守财奴",
		"icon": "res://assets/art/cultivator_shoucainu_icon.png",
	},
		{
			"id": "ach_item_hunyuan",
			"name": "收益满载",
			"cond_desc": "单局收益达到30点——你这是修仙还是搞理财？",
			"category": "luck",
		"reward_type": "item",
		"reward_id": "hunyuan_zhu",
		"reward_name": "万能珠",
		"icon": "res://assets/art/item_hunyuan_zhu.png",
	},
		{
			"id": "ach_cult_yaowang",
			"name": "悬壶济世",
			"cond_desc": "单局累计回复200点生命——你救的人比害的还多，这不科学",
			"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "yaowang",
		"reward_name": "药王",
		"icon": "res://assets/art/cultivator_yaowang_icon.png",
	},
		{
			"id": "ach_cult_shixue",
			"name": "浴血修罗",
			"cond_desc": "单局挨打25次——你不是在挨打，是在收集勋章",
			"category": "luck",
		"reward_type": "cultivator",
		"reward_id": "shixue",
		"reward_name": "嗜血魔修",
		"icon": "res://assets/art/cultivator_shixue_icon.png",
		},
		{
			"id": "ach_luck_turtle",
			"name": "铁王八",
			"cond_desc": "单局挨打50次还能通关——你到底是肉做的还是铁打的？",
			"category": "luck",
			"reward_type": "item",
			"reward_id": "bumie_jinshen",
			"reward_name": "不灭金身",
			"icon": "res://assets/art/cultivator_shixue_icon.png",
		},
		{
			"id": "ach_feat_thrift",
			"name": "一毛不拔",
			"cond_desc": "通关全程一枚金币都没花——铁公鸡见了你都得递烟",
			"category": "luck",
			"reward_type": "item",
			"reward_id": "daoyun_jing",
			"reward_name": "道蕴镜",
			"icon": "res://assets/art/item_jubaopen.png",
		},
		# ---------------- 新手起步：前几局就能达成 ----------------
		{
			"id": "ach_cult_jinsuanpan",
			"name": "小有积蓄",
			"cond_desc": "单局攒下100枚金币——会省钱的人，运气都不会太差",
			"category": "luck",
			"reward_type": "cultivator",
			"reward_id": "jinsuanpan",
			"reward_name": "商人",
			"icon": "res://assets/art/cultivator_jinsuanpan_icon.png",
		},
		{
			"id": "ach_cult_kuxingseng",
			"name": "勤修不辍",
			"cond_desc": "累计游玩3局——修仙这件事，来都来了",
			"category": "luck",
			"reward_type": "cultivator",
			"reward_id": "kuxingseng",
			"reward_name": "苦行僧",
			"icon": "res://assets/art/cultivator_kuxingseng_icon.png",
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

## 反查某把武器对应的解锁成就（默认入池与开局自选武器返回空字典）
static func weapon_unlock_achievement(wid: String) -> Dictionary:
	for a in ACHIEVEMENTS:
		if a.get("reward_type", "") == "weapon" and a.get("reward_id", "") == wid:
			return a
	return {}

## 无收录途径条目的兜底文案：定义在数据表但没有任何解锁成就/不入商店池时，
## 图鉴与战绩卡不许静默无提示——「暂无收录途径」是全项目唯一口径。
## const 与函数共用，前缀由各调用方传入（ManualDialog 用「收录条件：」、CareerDialog 用「达成成就」句式）。
const NO_UNLOCK_HINT := "暂无收录途径"

## 统一收录条件文案：有反查成就则 prefix + cond_desc，否则兜底 NO_UNLOCK_HINT。
## is_item=true 走道具反查、false 走角色反查；ManualDialog/CareerDialog 共用，判空只写一遍。
static func unlock_hint_text(id: String, is_item: bool, prefix: String) -> String:
	var ach := item_unlock_achievement(id) if is_item else cultivator_unlock_achievement(id)
	if not ach.is_empty():
		return prefix + String(ach.get("cond_desc", ""))
	return NO_UNLOCK_HINT

## 武器收录条件文案（图鉴武器页未解锁时用）：有反查成就给条件，否则兜底。
static func weapon_unlock_hint_text(wid: String, prefix: String) -> String:
	var ach := weapon_unlock_achievement(wid)
	if not ach.is_empty():
		return prefix + String(ach.get("cond_desc", ""))
	return NO_UNLOCK_HINT

## 初始默认进入商店武器池的武器 = 全部武器 − 锁定清单（2026-10-25）
## 开局自选武器（WeaponData.STARTER_IDS）恒可用，即便出现在 LOCKED_WEAPONS 里也不受影响。
## 纯函数只读 WeaponData 的静态表，不碰 autoload。
static func default_weapons() -> Array[String]:
	var out: Array[String] = []
	for wid in WeaponData.DEFS.keys():
		if not (String(wid) in LOCKED_WEAPONS):
			out.append(String(wid))
	return out

## 成就奖励的展示名：解锁哪一类就报哪一类的对象名（结算屏/战绩卡共用，别处不再拼字符串）
static func reward_label(ach: Dictionary) -> String:
	var rtype := String(ach.get("reward_type", ""))
	match rtype:
		"cultivator":
			return "新角色"
		"item":
			return "新道具"
		"weapon":
			return "新武器"
	return ""

## 判定单条成就在当前局与生涯累计下是否达成
## run_ctx 字段：victory(bool), endless(bool), danger(int), wave(int), level(int), kills(int),
##              max_stones(int), max_dodge(float), max_harvest(float),
##              damage_taken_count(int), hp_healed(float),
##              stones_spent(int 本局花掉金币), skill_casts(int 主动技能次数),
##              weapon_count(int 结算时持有武器总数), item_count(int 结算时法宝数),
##              max_summons(int), max_class_counts(Dictionary {器类tag: 同时上阵峰值}),
##              max_element_spread(int 单局同时上阵的五行元素种数峰值)
## career_stats 字段：total_runs(int), total_wins(int), total_kills(int), best_wave(int),
##              wins_no_skill_enhance(int 无契合技能通关累计次数)
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
		# 新手起步四条：前几局就能达成，负责把「第一次解锁」提前到第 1~3 局
		"ach_cult_yushou":
			return best_wave >= 5
		"ach_cult_lingzhifu":
			return best_wave >= 8
		"ach_cult_jinsuanpan":
			return max_stones >= 100
		"ach_cult_kuxingseng":
			return total_runs >= 3
		"ach_feat_nightmare":
			return victory and danger >= 3
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
		"ach_feat_nodamage":
			return victory and int(run_ctx.get("damage_taken_count", 0)) == 0
		"ach_feat_nightmare_flawless":
			return victory and danger >= 3 and int(run_ctx.get("damage_taken_count", 0)) == 0
		"ach_feat_endless_40":
			return endless and wave >= 40
		"ach_feat_lone_weapon":
			return victory and int(run_ctx.get("weapon_count", 0)) == 1
		"ach_feat_skill_abstain":
			return victory and int(run_ctx.get("skill_casts", -1)) == 0
		"ach_feat_no_items":
			return victory and int(run_ctx.get("item_count", -1)) == 0
		"ach_feat_thrift":
			return victory and int(run_ctx.get("stones_spent", -1)) == 0
		"ach_style_rebel":
			return int(career_stats.get("wins_no_skill_enhance", 0)) >= 3
		"ach_style_loner":
			return victory and int(run_ctx.get("max_summons", 0)) == 0
		"ach_style_omni":
			var mcc := Dictionary(run_ctx.get("max_class_counts", {}))
			for cls in WeaponData.CLASSES:
				if int(mcc.get(cls, 0)) < 1:
					return false
			return true
		"ach_cult_sanxiu":
			# 散修解锁：单局同时持有 ≥4 种不同器类（与 ach_style_omni 同一份 max_class_counts 账本）
			var sanxiu_mcc := Dictionary(run_ctx.get("max_class_counts", {}))
			var sanxiu_kinds := 0
			for cls in WeaponData.CLASSES:
				if int(sanxiu_mcc.get(cls, 0)) >= 1:
					sanxiu_kinds += 1
			return sanxiu_kinds >= 4
		"ach_grind_level20":
			return level >= 20
		"ach_luck_turtle":
			return victory and int(run_ctx.get("damage_taken_count", 0)) >= 50
	return false

## 成就进度短句：按生涯统计给出「当前进度」一句，供选人页解锁提示与成就卡点按详情复用。
## 纯函数 —— 只读入参 career_stats，不碰 autoload，与 is_condition_met 同一套数值口径。
## 读的 career_stats["best_*"] 是「单局生涯最佳」，由 ProgressStore 结算时并入并落盘；
## 无量化口径的成就（如无尽行者）返回空串，调用方不显示进度行。
static func progress_text(aid: String, career_stats: Dictionary) -> String:
	var cc: Dictionary = career_stats.get("best_class_counts", {})
	var stones := int(career_stats.get("best_stones", 0))
	var dodge := float(career_stats.get("best_dodge", 0.0))
	var harvest := float(career_stats.get("best_harvest", 0.0))
	var healed := float(career_stats.get("best_healed", 0.0))
	var hits := int(career_stats.get("best_hits_taken", 0))
	var summons := int(career_stats.get("best_summons", 0))
	var spread := int(career_stats.get("best_element_spread", 0))
	var level := int(career_stats.get("best_level", 0))
	var dg := int(career_stats.get("best_danger_cleared", -1))
	var runs := int(career_stats.get("total_runs", 0))
	var wins := int(career_stats.get("total_wins", 0))
	var kills := int(career_stats.get("total_kills", 0))
	var best_wave := int(career_stats.get("best_wave", 0))
	match aid:
		"ach_cult_duoshe":
			return "已通关 %d 次" % wins
		"ach_cult_dubi":
			if dg >= 0:
				return "最高通关「%s」" % danger_name(dg)
			return "尚未通关任意难度"
		"ach_cult_yushou":
			return "最高抵达第 %d/5 波" % best_wave
		"ach_cult_lingzhifu":
			return "最高抵达第 %d/8 波" % best_wave
		"ach_cult_jinsuanpan":
			return "单局最佳 %d/100 金币" % stones
		"ach_cult_kuxingseng":
			return "已游玩 %d/3 局" % runs
		"ach_cult_juechen":
			return "单局最佳 %d/4 件" % int(cc.get("sword", 0))
		"ach_cult_fuxiu":
			return "单局最佳 %d/4 件" % int(cc.get("talisman", 0))
		"ach_cult_bawang":
			return "单局最佳 %d/4 件" % int(cc.get("wide", 0))
		"ach_cult_jiguan":
			return "单局最佳 %d/4 个" % summons
		"ach_style_thunder":
			return "单局最佳 %d/4 件" % int(cc.get("thunder", 0))
		"ach_style_wuxing":
			return "单局最佳 %d/5 行" % spread
		"ach_cult_sanxiu":
			# 进度按「单局同时持有最多的器类种数」报，复用 best_class_counts 里 ≥1 件的系计数
			var sanxiu_kinds := 0
			for cls in WeaponData.CLASSES:
				if int(cc.get(cls, 0)) >= 1:
					sanxiu_kinds += 1
			return "单局最佳 %d/4 系" % sanxiu_kinds
		"ach_cult_meiying":
			return "闪避峰值 %d%% · 击杀 %d/500" % [int(dodge * 100.0), kills]
		"ach_cult_kuangzhan":
			return "累计击杀 %d/1500" % kills
		"ach_grind_kills":
			return "累计击杀 %d/5000" % kills
		"ach_grind_wins":
			return "累计通关 %d/10" % wins
		"ach_item_kuilei":
			return "已玩 %d/5 局 · 通关 %d 次" % [runs, wins]
		"ach_item_wuxing":
			return "单局最高 Lv.%d/15" % level
		"ach_item_pojia":
			return "最高抵达第 %d 波" % best_wave
		"ach_cult_duobao":
			return "单局最佳 %d/250 金币" % stones
		"ach_cult_shoucainu":
			return "单局最佳 %d/400 金币" % stones
		"ach_item_hunyuan":
			return "单局最佳 %.0f/30 收益" % harvest
		"ach_cult_yaowang":
			return "单局最佳 %.0f/200 回复" % healed
		"ach_cult_shixue":
			return "单局承伤 %d/25 次" % hits
		"ach_style_rebel":
			var wne := int(career_stats.get("wins_no_skill_enhance", 0))
			return "通关 %d/3 次" % wne
		"ach_grind_level20":
			return "单局最高 Lv.%d/20" % level
		"ach_luck_turtle":
			return "单局承伤 %d/50 次" % hits
	return ""

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
