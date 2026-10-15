class_name FxBudget
extends RefCounted

## 全局视觉特效与光照预算权威登记簿（Forward+ 性能红线收口）
## 在 Forward+ 2D 下，PointLight2D 与活跃 GPUParticles2D 是主要 GPU 开销源。
## 全项目任何新增动态光源/粒子发射器必须在此登记名额，严禁私自放量。

# ==============================================================================
# 一、动态灯预算（PointLight2D）：全场动态灯硬上限 ≤ 20
# ==============================================================================

## 全局同屏动态 PointLight2D 严格硬上限（任何时刻全场总和 ≤ 20）
const GLOBAL_LIGHT_CAP := 20

## 1. 掉落灵玉/灵石（AstralGem.gd）：大量击杀掉落时常驻灯名额
const LIGHT_CAP_GEM := 8

## 2. 玩家弹丸（BladeProjectile.gd）：多飞剑齐射时的动态光照名额
const LIGHT_CAP_PROJECTILE := 6

## 3. 场景祭坛界碑（BlessingObelisk.gd）：东/西/中三座界碑常驻柔光
const LIGHT_CAP_OBELISK := 3

## 4. 环绕灵宝阳珠（SunOrb.gd）：至阳真火环绕体常驻光晕
const LIGHT_CAP_SUN_ORB := 1

## 5. 妖皇魔首（BossEnemy.gd）：Boss 级敌人常驻威压魔光
const LIGHT_CAP_BOSS := 1

## 6. 瞬态落雷演出（ThunderBurst.gd）：天雷震落瞬间爆发光照
const LIGHT_CAP_THUNDER := 1

## 7. 武器光束命中端/后续新增预留（如 T-2.2 紫虹镜光束命中端）
const LIGHT_CAP_BEAM_RESERVED := 1

# 合计预分配总灯数：8 + 6 + 3 + 1 + 1 + 1 + 1 = 21（其中 Boss 与雷击/光束命中为条件互斥，常态 ≤ 20）

# ==============================================================================
# 二、粒子发射器与爆发预算（GPUParticles2D / CPUParticles2D）
# ==============================================================================

## 同屏活跃粒子发射器硬上限（FxParticlePool 预实例化 24 个）
const MAX_ACTIVE_EMITTERS := 30

## 单次瞬发粒子数上限（碎屑与软光斑爆发量，保持死亡细胞颗粒手感）
const MAX_BURST_PARTICLES := 16

## 命中火花单物理帧限流闸（同帧最多放行处数，防止高穿透齐射糊屏脱锚）
const FRAME_BUDGET_HIT_SPARK := 6

## 死亡爆散单物理帧限流闸（同帧最多放行处数，群杀时宁缺勿糊）
const FRAME_BUDGET_DEATH_BURST := 3

# ==============================================================================
# 三、重绘与排序铁律常量
# ==============================================================================

## 地面贴地特效强制 Y 深度（GroundDecal / PoisonPool 同款钉死层深）
const GROUND_SORT_Y := -100000.0

## 特效视觉层级（角色/敌人之上，HUD 之下）
const Z_OVERLAY := 35

## 获取已分配的常态动态灯总数
static func get_allocated_light_cap() -> int:
	return LIGHT_CAP_GEM + LIGHT_CAP_PROJECTILE + LIGHT_CAP_OBELISK + LIGHT_CAP_SUN_ORB + LIGHT_CAP_BOSS
