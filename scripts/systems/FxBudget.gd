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
const LIGHT_CAP_GEM := 5

## 2. 玩家弹丸（BladeProjectile.gd）：多飞剑齐射时的动态光照名额
const LIGHT_CAP_PROJECTILE := 6

## 3. 场景祭坛界碑（BlessingObelisk.gd）：东/西/中三座界碑常驻柔光
const LIGHT_CAP_OBELISK := 3

## 4. 环绕灵宝阳珠（SunOrb.gd）：至阳真火环绕体常驻光晕
const LIGHT_CAP_SUN_ORB := 1

## 5. 妖皇魔首（BossEnemy.gd）：Boss 级敌人常驻威压魔光
const LIGHT_CAP_BOSS := 1

## 6. 精英妖兽/魔偶（EnemyBase.gd）：赤雷/剑煞/石魔偶同屏常驻魔光名额
const LIGHT_CAP_ELITE := 2

## 7. 瞬态落雷演出（ThunderBurst.gd）：天雷震落瞬间爆发光照
const LIGHT_CAP_THUNDER := 1

## 8. 武器光束命中端/后续新增预留（如 T-2.2 紫虹镜光束命中端）
const LIGHT_CAP_BEAM_RESERVED := 1

# 合计预分配总灯数：5 + 6 + 3 + 1 + 1 + 2 + 1 + 1 = 20（= GLOBAL_LIGHT_CAP）
# 满载最坏情形（Boss 波 6 弹丸+Boss+2 精英+落雷+光束命中+5 灵玉+3 界碑+阳珠）恰好 20。

# ==============================================================================
# 二、粒子发射器与爆发预算（GPUParticles2D / CPUParticles2D）
# ==============================================================================

## 同屏活跃粒子发射器硬上限（FxParticlePool 预实例化 24 个）
const MAX_ACTIVE_EMITTERS := 30

## 单次瞬发粒子数上限（碎屑与软光斑爆发量，保持死亡细胞颗粒手感）
const MAX_BURST_PARTICLES := 16

## 命中火花单物理帧限流闸（同帧最多放行处数，防止高穿透齐射糊屏脱锚）
## 2026-10-16 攻击粒子减量：6→4，多武器齐射时同帧火花密度收敛一档
const FRAME_BUDGET_HIT_SPARK := 4

## 死亡爆散单物理帧限流闸（同帧最多放行处数，群杀时宁缺勿糊）
const FRAME_BUDGET_DEATH_BURST := 3

## 小怪墨色魂屑单物理帧限流闸（群杀时平滑分散，宁缺勿糊）
const FRAME_BUDGET_DEATH_WISP := 4

## 灵气凝聚微粒单物理帧限流闸（仅精英/魔君凝聚，防止刷怪同帧抢占池）
const FRAME_BUDGET_SOUL_ORB := 2

## 火锥碎屑单物理帧限流闸（2026-10-16 补挂：EMBER 原先无闸，
## 是唯一随火葫芦数量线性叠加的无上限持续粒子源）
const FRAME_BUDGET_EMBER := 3

## 五行异常体表粒子单物理帧限流闸（灼烧火星/剧毒雾斑/冰霜晶屑三系共用一闸，
## DoT 存续期每敌约 0.45s 一发，高感电配装下同帧多只并发时宁缺勿糊）
const FRAME_BUDGET_STATUS_AURA := 2

# ==============================================================================
# 三、重绘与排序铁律常量
# ==============================================================================

## 地面贴地特效强制 Y 深度（GroundDecal / PoisonPool 同款钉死层深）
const GROUND_SORT_Y := -100000.0

## 特效视觉层级（角色/敌人之上，HUD 之下）
const Z_OVERLAY := 35

## 获取已分配的动态灯总数（含全部 8 类，应 ≤ GLOBAL_LIGHT_CAP）
static func get_allocated_light_cap() -> int:
	return LIGHT_CAP_GEM + LIGHT_CAP_PROJECTILE + LIGHT_CAP_OBELISK + LIGHT_CAP_SUN_ORB + LIGHT_CAP_BOSS + LIGHT_CAP_ELITE + LIGHT_CAP_THUNDER + LIGHT_CAP_BEAM_RESERVED

# ==============================================================================
# 四、拥挤档（2026-10-17 性能专项）：同屏敌量驱动的灯/glow 动态降档
# ==============================================================================
## 高压战斗（同屏敌 ≥ 24）时 GPU 填充吃紧（原生分辨率 + glow + 20 灯全开），
## 掉落/弹丸两类「可再生物」（死了还会掉、射了还会亮）灯名额减半，让位给带宽；
## 界碑/Boss/精英/落雷等「演出承诺」类名额不动。敌潮退去自动回满，玩家无感。
## 全局状态由 WaveSpawner 每秒采样翻转（_tick_crowd_tier），消费方读这里。
static var crowded: bool = false

## 拥挤档下生效的掉落灵玉灯名额（5 → 2）
static func gem_light_cap() -> int:
	return LIGHT_CAP_GEM >> 1 if crowded else LIGHT_CAP_GEM

## 拥挤档下生效的弹丸灯名额（6 → 3）
static func projectile_light_cap() -> int:
	return LIGHT_CAP_PROJECTILE >> 1 if crowded else LIGHT_CAP_PROJECTILE

## 拥挤档下 glow 强度（0.4 → 0.25：超白起辉仍在，只是峰值压一档；阈值不动保 FX_HDR 色表）
const GLOW_INTENSITY_NORMAL := 0.4
const GLOW_INTENSITY_CROWDED := 0.25
static func glow_intensity() -> float:
	return GLOW_INTENSITY_CROWDED if crowded else GLOW_INTENSITY_NORMAL

## 拥挤判定阈值（同屏敌数，含预警中的 SpawnIndicator）
const CROWDED_ENEMY_THRESHOLD := 24
## 拥挤退出阈值（滞回，2026-10-17 真机 UI 频闪治理）：进入 24 / 退出 20。
## 无滞回时敌量在 24 附近波动会让 crowded 每秒翻转，glow_intensity（0.4 与 0.25 互跳）与
## 弹丸灯名额随之每秒跳变，亮 UI（纸白/金高亮）的辉光每秒脉冲一次，观感即「UI 在闪」。
const CROWDED_EXIT_THRESHOLD := 20
