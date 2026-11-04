class_name BossAttackProfile
extends RefCounted

## Boss 攻击身份表：每尊 Boss 的「弹体形态 + 主色 + 预警样式 + 起手/命中特效」。
##
## 存在理由（2026-11-04 弹幕身份化）：
##   旧版 19 尊 Boss 里 17 尊的弹幕是同一个 Vector 圆换 tint，预警圈全场只有 4 种样式，
##   结果「赤炎的火球」「雷劫的雷芒」「葬剑仙的剑」在屏幕上长得一样，玩家只能靠数扇形角度
##   认招。外观差异全部收敛到这张表，BossEnemy 只读不写 —— 行为代码里不许再按 boss_id
##   分支写颜色（那是这张表没建之前的历史债）。
##
## 硬约束：
##   1. 三元组 (bolt, accent, telegraph) 必须两两不重复（tests/boss_variety_check.gd 断言）。
##   2. 表里只有外观与特效 id，不含任何判定数值；伤害/时长仍在 BalanceWave。
##   3. 弹体形态本身不做逐帧动画（环弹一次 20+ 颗），差异靠 silhouette + 双色。
##   4. 未登记的 boss_id 返回空字典，调用方退回落默认（ORB/FILL/无特效），不许崩。

## 最终魔尊（boss_id 为空串、final_boss=true）的登记键：用一个真实 boss_id 撞不上的名字
const FINAL_KEY := "__final"

## boss_id → 身份。字段：
##   label      仅供报错/日志定位，不参与判定
##   bolt       EnemyBolt.Style：ORB / SWORD / NEEDLE / TALISMAN / FLAME / VOID
##   accent     弹体主色（同时作为本尊 _fx_color：弹幕/冲击环/预警圈同源）
##   core       弹体亮芯色（不填则 accent.lightened(0.55)）
##   telegraph  AoeTelegraph.Style：FILL / RUNE / FIRE / THUNDER / VOID
##   cast_fx    起手序列帧 id（FxSheetData，缺 id 时 FxFlipbookPool 静默返回 null）
##   impact_fx  命中/落地序列帧 id（同上）
const PROFILES := {
	# ---------------- 前期（W10~W40） ----------------
	"chiyan": {
		"label": "赤炎魔将",
		"bolt": EnemyBolt.Style.FLAME,
		"accent": Color(1.00, 0.52, 0.18),
		"core": Color(1.00, 0.90, 0.62),
		"telegraph": AoeTelegraph.Style.FIRE,
		"cast_fx": &"flame_pillar",
		"impact_fx": &"fire_ring",
	},
	"xiuluo": {
		"label": "修罗战将",
		"bolt": EnemyBolt.Style.SWORD,
		"accent": Color(0.90, 0.22, 0.30),
		"core": Color(1.00, 0.72, 0.66),
		"telegraph": AoeTelegraph.Style.THUNDER,
		"cast_fx": &"ground_slam",
		"impact_fx": &"ground_slam",
	},
	"qianji": {
		"label": "玄天千机尊",
		"bolt": EnemyBolt.Style.TALISMAN,
		"accent": Color(0.28, 0.78, 0.92),
		"core": Color(0.82, 1.00, 1.00),
		"telegraph": AoeTelegraph.Style.RUNE,
		"cast_fx": &"cast_charge",
		"impact_fx": &"void_implosion",
	},
	"wangu": {
		"label": "万骨枯冢",
		"bolt": EnemyBolt.Style.ORB,
		"accent": Color(0.84, 0.80, 0.66),
		"core": Color(1.00, 0.99, 0.90),
		"telegraph": AoeTelegraph.Style.RUNE,
		"cast_fx": &"summon_circle",
		"impact_fx": &"",
	},
	"jianpo": {
		"label": "剑魄邪修",
		"bolt": EnemyBolt.Style.SWORD,
		"accent": Color(0.94, 0.26, 0.20),
		"core": Color(1.00, 0.80, 0.70),
		"telegraph": AoeTelegraph.Style.FILL,
		"cast_fx": &"",
		"impact_fx": &"",
	},
	"xinmo": {
		"label": "九幽心魔尊",
		"bolt": EnemyBolt.Style.VOID,
		"accent": Color(0.55, 0.28, 0.95),
		"core": Color(0.90, 0.80, 1.00),
		"telegraph": AoeTelegraph.Style.VOID,
		"cast_fx": &"hex_sigil",
		"impact_fx": &"void_implosion",
	},
	# ---------------- 深层魔君（W45~W100） ----------------
	"zhaoying": {
		"label": "照影魔君",
		"bolt": EnemyBolt.Style.NEEDLE,
		"accent": Color(0.78, 0.86, 0.98),
		"core": Color(1.00, 1.00, 1.00),
		"telegraph": AoeTelegraph.Style.RUNE,
		"cast_fx": &"",
		"impact_fx": &"",
	},
	"yinhun": {
		"label": "引魂使",
		"bolt": EnemyBolt.Style.VOID,
		"accent": Color(0.38, 0.92, 0.66),
		"core": Color(0.86, 1.00, 0.90),
		"telegraph": AoeTelegraph.Style.RUNE,
		"cast_fx": &"summon_circle",
		"impact_fx": &"",
	},
	"luding": {
		"label": "焚天炉君",
		"bolt": EnemyBolt.Style.FLAME,
		"accent": Color(0.98, 0.36, 0.16),
		"core": Color(1.00, 0.86, 0.48),
		"telegraph": AoeTelegraph.Style.FIRE,
		"cast_fx": &"flame_pillar",
		"impact_fx": &"fire_ring",
	},
	"canglong": {
		"label": "太苍龙君",
		"bolt": EnemyBolt.Style.FLAME,
		"accent": Color(0.34, 0.90, 0.76),
		"core": Color(0.88, 1.00, 0.94),
		"telegraph": AoeTelegraph.Style.FIRE,
		"cast_fx": &"",
		"impact_fx": &"",
	},
	"jianzhong": {
		"label": "葬剑仙",
		"bolt": EnemyBolt.Style.SWORD,
		"accent": Color(0.76, 0.88, 1.00),
		"core": Color(1.00, 1.00, 1.00),
		"telegraph": AoeTelegraph.Style.FILL,
		"cast_fx": &"",
		"impact_fx": &"",
	},
	"leijie": {
		"label": "雷劫神君",
		"bolt": EnemyBolt.Style.NEEDLE,
		"accent": Color(1.00, 0.88, 0.38),
		"core": Color(1.00, 1.00, 0.86),
		"telegraph": AoeTelegraph.Style.THUNDER,
		"cast_fx": &"thunderclap",
		"impact_fx": &"thunderclap",
	},
	"kunwang": {
		"label": "覆海鲲王",
		"bolt": EnemyBolt.Style.ORB,
		"accent": Color(0.18, 0.48, 0.88),
		"core": Color(0.72, 0.92, 1.00),
		"telegraph": AoeTelegraph.Style.FILL,
		"cast_fx": &"ice_spikes",
		"impact_fx": &"ice_spikes",
	},
	"kuijia": {
		"label": "千臂傀王",
		"bolt": EnemyBolt.Style.TALISMAN,
		"accent": Color(0.70, 0.74, 0.80),
		"core": Color(1.00, 0.92, 0.72),
		"telegraph": AoeTelegraph.Style.RUNE,
		"cast_fx": &"summon_circle",
		"impact_fx": &"",
	},
	"fenghuang": {
		"label": "离火凤皇",
		"bolt": EnemyBolt.Style.FLAME,
		"accent": Color(1.00, 0.72, 0.20),
		"core": Color(1.00, 0.96, 0.72),
		"telegraph": AoeTelegraph.Style.FIRE,
		"cast_fx": &"fire_ring",
		"impact_fx": &"meteor_fall",
	},
	"tianmo": {
		"label": "无相天魔",
		"bolt": EnemyBolt.Style.VOID,
		"accent": Color(0.86, 0.82, 0.98),
		"core": Color(1.00, 1.00, 1.00),
		"telegraph": AoeTelegraph.Style.VOID,
		"cast_fx": &"hex_sigil",
		"impact_fx": &"",
	},
	"hundun": {
		"label": "元初兽",
		"bolt": EnemyBolt.Style.TALISMAN,
		"accent": Color(0.80, 0.74, 0.52),
		"core": Color(1.00, 0.98, 0.82),
		"telegraph": AoeTelegraph.Style.RUNE,
		"cast_fx": &"",
		"impact_fx": &"meteor_fall",
	},
	"wanjie": {
		"label": "道劫化身",
		"bolt": EnemyBolt.Style.NEEDLE,
		"accent": Color(0.92, 0.94, 1.00),
		"core": Color(1.00, 1.00, 1.00),
		"telegraph": AoeTelegraph.Style.THUNDER,
		"cast_fx": &"thunderclap",
		"impact_fx": &"thunderclap",
	},
	# ---------------- 第 20 波破境魔尊（boss_id 为空） ----------------
	FINAL_KEY: {
		"label": "极煞魔尊",
		"bolt": EnemyBolt.Style.VOID,
		"accent": Color(0.48, 0.22, 0.92),
		"core": Color(0.88, 0.76, 1.00),
		"telegraph": AoeTelegraph.Style.VOID,
		"cast_fx": &"hex_sigil",
		"impact_fx": &"void_implosion",
	},
}

## 未登记时的兜底外观：与旧版完全一致（ORB 圆弹 + 填满圈 + 无序列帧）
const FALLBACK := {
	"label": "敌潮Boss",
	"bolt": EnemyBolt.Style.ORB,
	"accent": Color(0, 0, 0, 0),   # alpha=0 → 调用方沿用 _fx_color
	"core": Color(0, 0, 0, 0),
	"telegraph": AoeTelegraph.Style.FILL,
	"cast_fx": &"",
	"impact_fx": &"",
}

## 取身份：boss_id 为空串且是最终魔尊时走 FINAL_KEY；未登记返回 FALLBACK（不是空字典，
## 调用方不用到处判空 —— 但 tests/boss_variety_check 仍会把「未登记」判红，防止新 Boss 漏表）。
static func for_boss(boss_id: String, is_final: bool = false) -> Dictionary:
	var key := FINAL_KEY if boss_id == "" else boss_id
	if PROFILES.has(key):
		return PROFILES[key]
	if is_final and boss_id == "":
		return PROFILES[FINAL_KEY]
	return FALLBACK

## 是否已登记（测试用；FALLBACK 不算登记）
static func has_profile(boss_id: String, is_final: bool = false) -> bool:
	var key := FINAL_KEY if boss_id == "" else boss_id
	return PROFILES.has(key)

## 已登记的键（测试遍历用）
static func registered_keys() -> Array:
	return PROFILES.keys()
