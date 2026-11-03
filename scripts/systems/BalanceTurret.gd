class_name BalanceTurret
extends RefCounted

## 机关（Behavior.TURRET）阵地玩法数值（2026-11-03 手动布设改版）。
##
## 旧口径：每把武器按冷却自动布设 `turret_cap + (星-1)` 座（★1 两座、★4 五座），
## 炮台 10~12 秒自灭 —— 机关是一条「不用操作的被动 DPS 线」，没有站位与维护。
## 新口径：每把武器只给 1 座机关，玩家脚下空地手动落位；机关连续开火会磨损，
## 磨损后降速、磨到底停摆，靠近长按维修、也可收回重摆。
##
## 伤害换算（关键）：旧总 DPS = 座数(星+1) × 单发 ÷ (开火间隔 × 觉醒 cd_mult)；
## 新总 DPS = 齐射(星+1) × **同一个单发** ÷ (同一个开火间隔 × 同一个 cd_mult) —— 逐星级完全相等。
## 所以这里不调 damage、不调 turret_fire_cd、不调觉醒 cd_mult，只把「少掉的座数」换成「管数」。
##
## 全部 static 纯函数，与 GameBalance 同规约：不读 autoload、不碰节点、不调全局 randf()。

# ---------------- 编制与齐射 ----------------

## 每把机关武器同时只能在场的机关数（2026-11-03：cap 字段废弃，固定 1）
const TURRETS_PER_WEAPON := 1

## 齐射管数在 WeaponData.turret_volley(star)（属武器表口径，随 damage_for 一族）：
## 这里不重复实现，也不反向引用 WeaponData —— WeaponData.sustained_single_dps 会调
## GameBalance，两个 class_name 互相引用会踩项目坑 12 的循环类依赖。

# ---------------- 耐久 / 磨损 ----------------

## 耐久上限（百分比制，UI 与判定同一个刻度）
const MAX_DURABILITY := 100.0
## 连续开火多少秒磨到底。波长约 36~80s，按接敌占空比折算每波长波也就修 1 次。
const STAMINA_SEC := 40.0
## 磨损档：耐久低于该比例开始降攻速，并进入「需维修」提示态
const WORN_RATIO := 0.40
## 磨损档的开火间隔倍率（攻速 -33%）。维修一档即可恢复。
const WORN_FIRE_INTERVAL_MULT := 1.5

## 单发磨损量：按「本次开火间隔」折算，等价于连续开火每秒固定掉 1/stamina_sec 满条。
## 用有效开火间隔（含攻速、含磨损降速）传入，保证「每秒钟的磨损」与攻速无关。
## stamina_sec 缺省走表外的统一档；机关武器可在数据表用 turret_stamina 覆盖。
static func wear_per_shot(eff_fire_interval: float, stamina_sec: float = STAMINA_SEC) -> float:
	return MAX_DURABILITY * maxf(0.0, eff_fire_interval) / maxf(1.0, stamina_sec)

## 耐久比例（0..1）
static func durability_ratio(durability: float) -> float:
	return clampf(durability / MAX_DURABILITY, 0.0, 1.0)

## 是否进入磨损档（<40% 且还没停摆）
static func is_worn(durability: float) -> bool:
	return durability > 0.0 and durability_ratio(durability) < WORN_RATIO

## 是否停摆（耐久归零，完全不开火）
static func is_broken(durability: float) -> bool:
	return durability <= 0.0

## 开火间隔倍率：完好 1.0 / 磨损 1.5 / 停摆不参与（由调用方闸掉）
static func fire_interval_mult(durability: float) -> float:
	return WORN_FIRE_INTERVAL_MULT if is_worn(durability) else 1.0

## 需要玩家处理（磨损或停摆）——世界提示牌与 HUD「N 座待修」共用同一条判据
static func needs_service(durability: float) -> bool:
	return is_worn(durability) or is_broken(durability)

# ---------------- 维修 ----------------

## 长按维修秒数：与聚灵阵充能同 0.8s（同一套肌肉记忆）。
## 真机觉得太松改这里一处即可，判据读同一个常量。
const REPAIR_HOLD_SEC := 0.8
## 维修用时乘区下限：叠满「机关养护」也不会快到瞬间修完（0.2 = ×5 上限）
const REPAIR_HASTE_FLOOR := 0.2

## 每秒回填的耐久（连续回填，松手保留已修部分，不是「充满才算」）。
## haste_mul = 维修用时乘区（GameManager.turret_repair_haste_mul，<1 = 更快）。
static func repair_per_sec(haste_mul: float = 1.0) -> float:
	var hold := REPAIR_HOLD_SEC * maxf(REPAIR_HASTE_FLOOR, haste_mul)
	return MAX_DURABILITY / maxf(0.05, hold)

## 维修实际用时（HUD 走针环 / 判据读同一个数）
static func repair_hold_sec(haste_mul: float = 1.0) -> float:
	return REPAIR_HOLD_SEC * maxf(REPAIR_HASTE_FLOOR, haste_mul)

## 停摆兜底（道具「恒机芯」）：耐久耗尽后以该倍率继续运转，<=0 表示照旧完全停工。
## 0.5 = 半速；下限 0.2 防止叠出「停摆比完好还快」。
const BROKEN_HASTE_FLOOR := 0.2

# ---------------- 交互半径 / 落点 ----------------

## 靠近多少像素内切换「维修 / 收回」态
const INTERACT_RADIUS := 90.0
## 布设空地半径 = 交互半径（2026-11-03 统一口径）：判断的是「玩家站的地方」离最近一座
## 自己的机关够不够远，而不是「落点」。两者若各用各的数，就会出现「按钮显示布设、按下去
## 却被拒」的死带（90~106px 那一圈）；现在布设态显示 ⟺ 一定放得下。
## 落点本身仍沿移动反方向外沿偏移，所以两座机关实测最近可相距 ~64px（视觉上不重叠）。
const MIN_TURRET_SPACING := INTERACT_RADIUS
## 布设落点相对玩家的外沿距离（沿移动反方向，避免压在人物身体上）
const DEPLOY_OFFSET := 26.0

## 落点是否为空地：玩家所在位置与最近一座自己机关的距离必须 ≥ MIN_TURRET_SPACING
## nearest_dist 由调用方用 TurretCommand 现算传入（纯函数不碰节点）
static func is_open_ground(nearest_own_turret_dist: float) -> bool:
	return nearest_own_turret_dist >= MIN_TURRET_SPACING

## 落点相对玩家位置的偏移（有移动方向时落在身后，静止时落在脚下偏下）
static func deploy_offset(last_move_dir: Vector2) -> Vector2:
	if last_move_dir.length_squared() > 0.0001:
		return -last_move_dir.normalized() * DEPLOY_OFFSET
	return Vector2(0.0, DEPLOY_OFFSET)

# ---------------- 收回 ----------------

## 收回后该武器进入「整备冷却」：复用武器表的 cooldown（3.5~4.5s）× 有效攻速。
## 不设冷却就能「抱着机关跑」，阵地玩法会退化成随身炮台。
static func recall_cooldown(base_cooldown: float, attack_speed_mult: float) -> float:
	return maxf(0.5, base_cooldown * maxf(0.1, attack_speed_mult))