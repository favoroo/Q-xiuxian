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
## 新总 DPS = 齐射(星+1) × **同一个单发** ÷ (同一个开火间隔 × 同一个 cd_mult) —— 逐星级等价。
## 所以这里不调 turret_fire_cd、不调觉醒 cd_mult，只把「少掉的座数」换成「管数」。
## 2026-11-03 复查补偿：座数→管数只保证「改版当刻数值不缩水」，但手动布设/磨损/维修/收回
## 带来了旧版没有的站位与操作负担（有效 DPS 约打 8 折）。因此机关表 10 把武器的基础伤害
## 整体 +10%（9~20 → 10~22，见 WeaponData），这是刻意的「高操作换高回报」，不要按旧等价公式
## 把它改回去；齐射管数与 fire_cd 仍是唯一换算口径。
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
## 连续开火多少秒磨到底（2026-11-03 用户口径「耐久掉得再快一点」：40 → 30）。
## 40s 时维修几乎不用挑时机、耐久类道具也感觉不出来；30s 让 60% 预警在连续开火约 12s 就到，
## 配合更长的维修窗口，机关养护/机枢油这类道具才有存在感。
## 机关武器表 turret_stamina 逐把写值（当前 10 把统一 30），本常量是缺省兜底。
const STAMINA_SEC := 30.0
## 磨损档：耐久低于该比例开始降攻速
const WORN_RATIO := 0.40
## 提前预警档：低于该比例就进「需维修」提示态（HUD 待修芯片 / 头顶状态牌），
## 但真正降速仍要等 WORN_RATIO —— 给玩家留出走过去维修的时间，别等掉到四成才第一次提醒。
const WARN_RATIO := 0.60
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

## 需要玩家处理（磨损预警或停摆）——世界提示牌与 HUD「N 座待修」共用同一条判据。
## 注意与 is_worn 分开：needs_service 是 60% 就提示，is_worn 才是 40% 降速。
static func needs_service(durability: float) -> bool:
	return is_broken(durability) or durability_ratio(durability) < WARN_RATIO

# ---------------- 维修 ----------------

## 长按维修秒数（2026-11-03 逐次上调：0.8 → 1.6 → 2.4 → 3.5 → 5.0）。
## 口径是「0% 修到 100% 的满条时间」：按剩余缺口等比例缩短（60%→100% = 5.0×0.4 = 2.0s），
## 中途松手保留已修部分。维修时机关停火 —— 维修不再是纯白嫖，要挑安全窗口做。
## **2026-11-04 取消「站定维修」**：真机反馈站定太容易死，允许在维修圈内边走边修；
## 只要还在 INTERACT_RADIUS 内，HUD 就不断开按住。
## HUD 走针环、机关盘缘进度弧、tests/turret_check 都读它，不用改别处。
const REPAIR_HOLD_SEC := 5.0
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

## 靠近多少像素内切换「维修」态（2026-11-03 用户真机口径：90 太短 → 150 → 120 → 110 → 95）。
## 玩家最终要的是「贴到机关旁才维修」，半径放宽反而老在收回重摆时抢键；收到 95 只比最初
## 的 90 略宽松。收回不受这个半径限制，见 RECALL_RADIUS。
const INTERACT_RADIUS := 95.0
## 收回半径：**不限距离**（<=0 表示全场任意一处都能收回）。
## 2026-11-03 用户真机口径：机关打不到宝箱时玩家根本走不过去收，90px 太死，
## 收回键改成「随时可用、只收最近那一座」，走位与重摆才灵活。
const RECALL_RADIUS := -1.0
## 两座机关最近间距：布设判「落点」，维修/收回判「玩家位置」；
## 两座机关最近可相距约 64px，视觉上不会重叠。
const MIN_TURRET_SPACING := 64.0
## 布设落点相对玩家的外沿距离（沿移动反方向，避免压在人物身体上）
const DEPLOY_OFFSET := 26.0

## 落点是否为空地：落点距离最近机关 ≥ MIN_TURRET_SPACING
## nearest_dist 由调用方用 TurretCommand 现算传入（纯函数不碰节点）
static func is_open_ground(nearest_own_turret_dist: float) -> bool:
	return nearest_own_turret_dist >= MIN_TURRET_SPACING

## 落点相对玩家位置的偏移（有移动方向时落在身后，静止时落在脚下偏下）
static func deploy_offset(last_move_dir: Vector2) -> Vector2:
	if last_move_dir.length_squared() > 0.0001:
		return -last_move_dir.normalized() * DEPLOY_OFFSET
	return Vector2(0.0, DEPLOY_OFFSET)

# ---------------- 收回 ----------------

## 收回后的整备倒数：**0 = 收回当刻即可重摆**。
## 2026-11-03 用户口径：机关玩法要灵活，收回后不要等，立刻能部署。
## 防「抱着机关跑」的老顾虑改由「收回→布设」两段动画与落点空地校验承担：
## 机关落点仍要离其它机关 ≥ MIN_TURRET_SPACING，抱着跑最多是把机关往前挪一段。
## 保留这个常量与整条倒计时链路（值给 0），将来真要加冷却只改这一处。
const RECALL_COOLDOWN_SEC := 0.0