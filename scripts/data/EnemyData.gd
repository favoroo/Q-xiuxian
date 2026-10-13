class_name EnemyData
extends RefCounted

## 敌人静态数据库（渐进版）：怪种名单 / 回合配比 / 精英称号 / 金蟾档期的唯一真话。
## 全 static 纯数据 + 纯函数，不碰节点不读 autoload（铁律 2），随机仍由调用方走 GameManager.rng。
##
## 收编范围（2026-10-13，从 WaveSpawner.gd:361-391 平移，数字逐一对账，行为零变化）：
##   - 25 个 MIX_* 配比常量 → MOBS 表行（unlock_wave + 低 roll 累计带 edge / 高 roll 带 band_lo）
##   - 3 个 LOOTER_* 常量 → LOOTER_DEF
##   - WaveSpawner 的 16 个 preload 场景变量 → MOBS 行的 scene_path（WaveSpawner 启动时缓存）
##   - 精英池与称号表 → ELITE_POOL（title 字段随行）
## 不收编（留给全量版）：EnemyBase 的 49 个 @export 数值、16 个 .tscn 覆写、BalanceWave 的
## 45 个成长公式常量、EnemyVisualConfig 的视觉工厂、EnemyBase._deduce_enemy_id 的 id 推导。
##
## 配比口径（与旧实现逐条对齐）：
##   低 roll 段（roll < 0.78 上下）是「累计带」：丹爆/邪修/雷兽/花妖按 edge 分段，闸门未解锁时
##   份额让给下一格；邪修不设闸门（第 1 波就占自己的格子，按 ramp 爬坡到 cap）。
##   高 roll 段是「保底份额切走」：新敌种各占 [band_lo, 1.0) 中自己那一段，越晚解锁越稀有，
##   闸门未开时 roll 落回史莱姆。判定顺序 = 表序（低 roll 先判，高 roll 从最稀有往回判）。

const MOBS: Dictionary = {
	"slime": {
		"display": "史莱姆",
		"scene_path": "res://scenes/entities/SlimeEnemy.tscn",
		# 保底怪种：无闸门无专属带，其他格子没人要的 roll 都落回它
	},
	"danbao": {
		"display": "丹爆傀儡",
		"scene_path": "res://scenes/entities/DanBaoEnemy.tscn",
		"unlock_wave": 3,
		"edge": 0.12,          ## 低 roll 累计带上沿（roll < edge 命中）
	},
	"xiexiu": {
		"display": "邪修",
		"scene_path": "res://scenes/entities/XieXiuEnemy.tscn",
		# 无 unlock_wave：第 1 波就登场（2026-10-08 用户指令），占比逐回合爬坡
		"ramp_start": 0.06,    ## 第 1 波的累计带上沿
		"ramp_step": 0.03,     ## 每回合上沿再涨 3%
		"ramp_cap": 0.27,      ## 上沿封顶（第 8 波爬满）
	},
	"leibeast": {
		"display": "雷兽",
		"scene_path": "res://scenes/entities/LeiBeastEnemy.tscn",
		"unlock_wave": 5,
		"edge": 0.42,          ## 低 roll 累计带上沿
	},
	"flower": {
		"display": "花妖",
		"scene_path": "res://scenes/entities/FlowerEnemy.tscn",
		"unlock_wave": 2,
		"edge_base": 0.42,     ## 低 roll 累计带下沿
		"edge_growth": 0.25,   ## 增长基数
		"edge_slope": 0.06,    ## 每回合增长斜率
		"edge_cap": 0.6,       ## 增长封顶
		"edge_step": 0.58,     ## 折算步长（基数+回合×斜率，夹到 cap，再 × step）
	},
	"fengqun": {
		"display": "蜂群精",
		"scene_path": "res://scenes/entities/FengQunEnemy.tscn",
		"unlock_wave": 3,
		"band_lo": 0.78,       ## 高 roll 带下沿（roll >= band_lo 命中；廉价群怪填密度）
	},
	"xueyong": {
		"display": "血蛹",
		"scene_path": "res://scenes/entities/XueYongEnemy.tscn",
		"unlock_wave": 6,
		"band_lo": 0.88,       ## 死亡分裂
	},
	"yingmei": {
		"display": "影魅",
		"scene_path": "res://scenes/entities/YingMeiEnemy.tscn",
		"unlock_wave": 7,
		"band_lo": 0.92,       ## 闪现侧翼
	},
	"lingyi": {
		"display": "灵医",
		"scene_path": "res://scenes/entities/LingYiEnemy.tscn",
		"unlock_wave": 8,
		"band_lo": 0.83,       ## 治疗同伴（土豆兄弟 Healer 对应位：优先击杀目标）
	},
	"guyao": {
		"display": "鼓妖",
		"scene_path": "res://scenes/entities/GuYaoEnemy.tscn",
		"unlock_wave": 9,
		"band_lo": 0.955,      ## 同伴加速光环
	},
	"duyao": {
		"display": "毒妖",
		"scene_path": "res://scenes/entities/DuYaoEnemy.tscn",
		# 走低 roll 段：它是功能怪不是稀有怪，占比要随基础怪潮一起铺开。
		# 高 roll 段 [0.78, 1.0) 已被六种怪按稀有度切满，硬插会整段吃掉影魅/鼓妖的份额
		#（判据：W14 全解锁下每种怪都必须真的选到，见 unit_wave_tests 的十一种怪断言）。
		# 而花妖累计带从 0.42 涨到 0.768 封顶，中段也没有固定空位 ⇒ 与花妖共用一个
		# 上沿（flower_edge），在下沿 0.42 ~ flower_edge 之间切走固定 35% 给毒妖，
		# 判序上排在花妖之前（见 pick_scene_key）。W6 起毒妖占 [0.42, 0.54) 一档，
		# 花妖拿剩下的 [0.54, flower_edge)，两边都随回合增长、都不消失。
		"unlock_wave": 6,
		"band_share": 0.35,    ## 与花妖共段时切走给自己的比例
	},
	"zhumu": {
		"display": "百目妖",
		"scene_path": "res://scenes/entities/ZhuMuEnemy.tscn",
		"unlock_wave": 14,
		"band_lo": 0.98,       ## 产卵孵化群怪
	},
}

## 精英轮换池：按出场次数取模轮换（铁甲魔傀 → 赤雷兽 → 剑煞邪修），称号随行播报
const ELITE_POOL: Array = [
	{
		"id": "golem",
		"display": "铁甲魔傀",
		"scene_path": "res://scenes/entities/GolemEnemy.tscn",
		"title": "铁甲巨怪",
	},
	{
		"id": "chilei",
		"display": "赤雷兽",
		"scene_path": "res://scenes/entities/ChileiEliteEnemy.tscn",
		"title": "烈雷兽",
	},
	{
		"id": "jiansha",
		"display": "剑煞邪修",
		"scene_path": "res://scenes/entities/JianshaEliteEnemy.tscn",
		"title": "剑客亡灵",
	},
]

## Boss：场景与数值注入（生命/伤害公式在 BalanceWave，由 WaveSpawner._spawn_boss 运行时覆写）
const BOSS_SCENE_PATH: String = "res://scenes/entities/BossEnemy.tscn"

## 金蟾（土豆兄弟 Looter 对应位）：回合中限时刷出的逃跑宝藏怪，
## 不占刷怪预算、不吃同屏上限；存活时「提前清场」会等它。
const LOOTER_DEF: Dictionary = {
	"scene_path": "res://scenes/entities/JinChanEnemy.tscn",
	"min_wave": 3,         ## 最早出现回合
	"chance": 0.35,        ## 每回合出现概率
	"at_pct": 0.4,         ## 波长剩余 40% 时登场（中场插曲，不打断开场节奏）
}

## 怪种 key 列表（单元测试「十一种怪都真的会被选到」的口径来源）
static func mob_keys() -> Array:
	return MOBS.keys()

## enemy_id 推导前缀表：EnemyBase._deduce_enemy_id 遍历它，新增怪种只需在此登记一行。
## 原先 EnemyBase 里是 16 分支 begins_with 链，加一种怪要同时改这里和 EnemyBase 两处，
## 漏改 EnemyBase 那处就静默降级成史莱姆外观（无任何报错）。
## key = enemy_id，value = 场景根节点名/文件名的前缀（两者一致，池化复用不改名）。
## 精英两个 id 带 _elite 后缀（EnemyBase._enter_mutation 与外观派发都认这个后缀），
## 故 ELITE_POOL 的 id 字段与这里的 key 不同形 —— 单测钉住这个差集恰好是这两个。
const ID_PREFIXES: Dictionary = {
	"boss": "boss",
	"golem": "golem",
	"slime": "slime",
	"flower": "flower",
	"leibeast": "leibeast",
	"xiexiu": "xiexiu",
	"danbao": "danbao",
	"fengqun": "fengqun",
	"xueyong": "xueyong",
	"guyao": "guyao",
	"duyao": "duyao",
	"yingmei": "yingmei",
	"zhumu": "zhumu",
	"lingyi": "lingyi",
	"jinchan": "jinchan",
	"chilei_elite": "chilei",
	"jiansha_elite": "jiansha",
}

## 配比判定：纯函数（给定回合与 roll ∈ [0,1) 返回怪种 key），被闸门锁住的种把份额让给下一格。
## 与旧 WaveSpawner.pick_scene_key 逐行等价；判定顺序写死在这里，表序变化不影响它。
static func pick_scene_key(wave: int, roll: float) -> String:
	var w := maxi(wave, 1)
	if w >= MOBS["danbao"]["unlock_wave"] and roll < MOBS["danbao"]["edge"]:
		return "danbao"
	if roll < xiexiu_edge(w):
		return "xiexiu"
	if w >= MOBS["leibeast"]["unlock_wave"] and roll < MOBS["leibeast"]["edge"]:
		return "leibeast"
	# 毒妖与花妖共段（[0.42, flower_edge)），毒妖判在前面 ⇒ 切走下沿一档给自己的固定比例。
	# 共段而不是另开段的原因见 MOBS["duyao"] 注释：高 roll 段已切满、花妖带涨到封顶，
	# 中段没有固定空位。两边共享同一条增长曲线，回合推进时一起变宽、谁也不消失。
	if w >= MOBS["duyao"]["unlock_wave"] and roll < duyao_edge(w):
		return "duyao"
	if w >= MOBS["flower"]["unlock_wave"] and roll < flower_edge(w):
		return "flower"
	# 高 roll 段：从最稀有往回判（百目妖 0.98 → … → 蜂群 0.78），闸门未开自动让位给下一格
	if w >= MOBS["zhumu"]["unlock_wave"] and roll >= MOBS["zhumu"]["band_lo"]:
		return "zhumu"
	if w >= MOBS["guyao"]["unlock_wave"] and roll >= MOBS["guyao"]["band_lo"]:
		return "guyao"
	if w >= MOBS["yingmei"]["unlock_wave"] and roll >= MOBS["yingmei"]["band_lo"]:
		return "yingmei"
	if w >= MOBS["xueyong"]["unlock_wave"] and roll >= MOBS["xueyong"]["band_lo"]:
		return "xueyong"
	if w >= MOBS["lingyi"]["unlock_wave"] and roll >= MOBS["lingyi"]["band_lo"]:
		return "lingyi"
	if w >= MOBS["fengqun"]["unlock_wave"] and roll >= MOBS["fengqun"]["band_lo"]:
		return "fengqun"
	return "slime"

## 邪修在第 wave 波占到的累计带上沿（爬坡线，单测钉这条）
static func xiexiu_edge(wave: int) -> float:
	var x := MOBS["xiexiu"]
	var w := maxi(wave, 1)
	return minf(x["ramp_cap"], x["ramp_start"] + x["ramp_step"] * float(w - 1))

## 花妖在第 wave 波占到的累计带上沿（下沿 + 增长段，旧 MIX_FLOWER_* 折算式原样平移）
static func flower_edge(wave: int) -> float:
	var f := MOBS["flower"]
	var w := maxi(wave, 1)
	return f["edge_base"] + minf(f["edge_growth"] + w * f["edge_slope"], f["edge_cap"]) * f["edge_step"]

## 毒妖在第 wave 波占到的累计带上沿（切走 0.42 到 flower_edge 之间的 band_share 份额）
static func duyao_edge(wave: int) -> float:
	var fe := flower_edge(wave)
	var lo := float(MOBS["leibeast"]["edge"])
	if fe <= lo:
		return lo
	return lo + (fe - lo) * float(MOBS["duyao"]["band_share"])
