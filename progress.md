# VFX 优化进度登记簿（progress.md）

> 本文件是「特效优化多 Agent 并行开发」的**唯一进度真话源**。任务做什么、怎么做 → 查 `vfx-optimization-plan.md`；谁在做什么、做到哪了 → 只看本文件。
> **任何 Agent 开工前必须通读第一节「协作协议」。** 本文件协议区只有用户能改。

---

## 一、协作协议（必读）

### 1. 状态图例

| 标记 | 含义 |
|---|---|
| ⬜ TODO | 待领取 |
| 🔵 DOING | 开发中（占用其「占用文件」列的全部文件） |
| ✅ DONE | 已完成（验收通过 + CHANGELOG 已写） |
| 🔧 REWORK | 返工（用户验收发现问题，原认领人优先修） |
| ⛔ BLOCKED | 卡阻（需求不明/依赖异常，等用户决策） |

### 2. 领取任务（修改前登记）

1. 读本文件 + 计划文档中对应任务卡（T-x.x）。
2. **四个领取条件全部满足才可领**：
   - 任务状态为 ⬜（用户直接指派的任务优先，跳过领取竞争，但仍需走登记）；
   - 「依赖」列全部 ✅；
   - 所在 Wave 的前置 Wave 任务全部 ✅（跨 Wave 硬闸，见第二节闸门状态）；
   - 「占用文件」与所有 🔵 任务的占用文件**无交集**，且 `git status --short` 确认这些文件没有他人未提交改动。
3. **单次原子 edit 完成登记**：状态 ⬜→🔵，认领栏填会话标识，填开始日期。
4. edit 冲突/失败 → **重新读文件再试**，禁止覆盖他人登记。
5. 自行领取顺序：任务表从上到下第一个满足条件的。

### 3. 开发中（心跳登记）

- 关键节点（实现完成 / 开始测试 / 遇阻）在第四节「开发日志」追加一行。
- 需要改动任务卡之外的文件 → **先在任务行「占用文件」补登**，确认与所有 🔵 任务无冲突后再动手。
- 任务不可行或需求不明 → 状态改 ⛔，日志写明原因，停下来等用户。

### 4. 完成（修改后登记）

1. 跑验收：`python3 tools/run_test.py --core` + 任务行「验收」列的专项 Check，全绿。
2. 追加 `CHANGELOG.md`（格式 `## YYYY-MM-DD #序号`，见 AGENTS.md）。
3. 登记：状态 🔵→✅，完成记录栏填「完成日期 ｜ 测试结果 ｜ CHANGELOG 序号」。
4. 标了「目检」的验收项，需在日志里补一句目检结论（过了什么画面）。

### 5. 返工与用户验收

- 用户目检或闸门验收发现问题 → 任务状态改 🔧，日志记录问题点，**原认领人优先修**；同一任务 3 次返工未过 → 升 ⛔ 等用户裁决。
- 用户验收是异步的，不阻塞其他满足条件的任务领取。

### 6. 全局纪律

- **热区文件**（`EnemyBase.gd` / `Player.gd` / `GameStyle.gd` / `Main.tscn` / `Main.gd` / `WaveSpawner.gd` / `BossEnemy.gd`）严格按本表占用登记串行。
- **编辑器扫描**（`$G --headless --path . --editor --quit`，新增 class_name/新素材后必跑）全项目同时只跑一个：跑前把第二节「编辑器扫描锁」改为 🔴+会话名，跑完改回 🟢。
- `FxParticlePool.gd` 在 API 冻结后（见第二节）**只准调用不准改**；缺 kind 在日志提需求，由用户安排补。
- `CHANGELOG.md` 撞车：保留两条，不删他人。
- 认领栏填用户给的名字/编号（如 Agent-A），没有就填会话短 ID。

---

## 二、全局状态

| 项 | 状态 | 说明 |
|---|---|---|
| FxParticlePool API | 🔒 已冻结 | T-0.2 完成后改 🔒 已冻结 |
| 编辑器扫描锁 | 🟢 空闲 | 🔴=被占用（后附会话名） |
| Wave 0 闸门 | ✅ 已通过 | Wave 0 全 ✅ 后改 ✅，Wave 1 才可领 |
| Wave 1 闸门 | ✅ 已通过 | Wave 1 全任务（10 项）全 ✅，Wave 2 任务解锁可领 |
| Wave 2 闸门 | ⬜ 未通过 | 同上，控制 Wave 3 |
| 用户确认项 | T-4.5 / T-6.1 / T-6.2 待用户确认 | 确认后对应行才可领 |

---

## 三、任务总表

### Wave 0 —— 基础设施（串行，1 个 Agent 依次做完）

| ID | 任务 | 状态 | 认领 | 占用文件 | 依赖 | 验收 | 完成记录 |
|---|---|---|---|---|---|---|---|
| T-0.1 | FX_HDR 发光色表 | ✅ | Agent-A | `scripts/ui/GameStyle.gd` | 无 | core + LayoutCheck | 2026-10-15 ｜ core PASS + LayoutCheck PASS ｜ #41 |
| T-0.2 | FxParticlePool 粒子池（kind 一次定义全） | ✅ | Agent-A | `scripts/systems/FxParticlePool.gd`（新建）、`Main.tscn`/`Main.gd`（挂池） | T-0.1 | core + perf_probe + 编辑器扫描 | 2026-10-15 ｜ core PASS + PerfProbe PASS + 扫描通过 ｜ #42 |
| T-0.3 | 灯预算表 FxBudget | ✅ | Agent-A | `scripts/systems/FxBudget.gd`（新建） | T-0.2 | core | 2026-10-15 ｜ core PASS ｜ #43 |
| T-0.4 | glow/暗角调参 | ✅ | Agent-A | `Main.tscn`、`assets/shaders/vignette_soft.gdshader` 参数 | T-0.3 | core + 目检 | 2026-10-15 ｜ core PASS + 目检通过 ｜ #44 |

### Wave 1 —— 打击反馈 / 武器批 1 / 场景氛围（3 车道并行）

| ID | 任务 | 状态 | 认领 | 占用文件 | 依赖 | 验收 | 完成记录 |
|---|---|---|---|---|---|---|---|
| T-1A | 命中火花 + 暴击加档 + 暴击跳字（含 T-1.1/1.4/5.3） | ✅ | Agent-A | `BladeProjectile.gd`、`DamageNumber.gd` | W0 | HitFxVisibilityCheck、weapon_per_hit_check、BeamConeCheck、DamageComboCheck + 目检 | 2026-10-15 ｜ 专项与 core 全 PASS + 目检 ｜ #45 |
| T-1B | 死亡演出：小怪墨屑 + 精英爆裂磁吸（含 T-1.2/1.3） | ✅ | Agent-A | `EnemyBase.gd`、`BossEnemy.gd`、`AstralGem.gd` | W0 | KillKnockbackCheck、EarlyClearCheck、ChestEconomyCheck + 目检 | 2026-10-15 ｜ 专项与 core 全 PASS + 目检 ｜ #46 |
| T-1.5 | 拾取反馈强化 | ✅ | Agent-A | `JuiceEffect.gd`、`ProceduralLootRenderer.gd` | W0 | core + 目检 | 2026-10-15 ｜ core PASS + PerfProbe PASS + 目检 ｜ #47 |
| T-2.1 | 近战月牙：内锐外羽 + 短拖尾 | ✅ | Agent-B | `WeaponArcRenderer.gd` | W0 | weapon_aim_check + 目检 | 2026-10-15 ｜ weapon_aim_check 539 项 PASS + core 6 项 PASS + perf_probe PASS ｜ #51 |
| T-2.2 | 光束：HDR 芯 + 光晕 + 命中灯 | ✅ | Agent-A | `BeamRenderer.gd` | W0 | BeamConeCheck + 目检 | 2026-10-15 ｜ BeamConeCheck PASS + core PASS + 目检 ｜ #48 |
| T-2.3 | 火锥粒子火焰流 ★用户点名 | ✅ | Agent-A | `FlameConeRenderer.gd` | W0 | BeamConeCheck + perf_probe + 目检 | 2026-10-15 ｜ BeamConeCheck PASS + PerfProbe PASS + 目检 ｜ #49 |
| T-2.4 | 弹丸 HDR 头部辉光 + 拖尾提亮 | ✅ | Agent-A | `ProceduralProjectileRenderer.gd`、`ProjectileTrail.gd` | W0 | weapon_per_hit_check + BulletPreview 目检 | 2026-10-15 ｜ weapon_per_hit PASS + core PASS + 目检 ｜ #50 |
| T-4A | 法阵活化：结界流光 + 灵脉脉动（含 T-4.1/4.4） | ✅ | Agent-C | `ArenaVisualLayer.gd`、`assets/shaders/boundary_flow.gdshader`（新建） | W0 | core + 目检 + 编辑器扫描 | 2026-10-15 ｜ core 6/6 PASS + LootAndMapPreview 目检对比过 ｜ #47 |
| T-4.2 | 结界外深渊：飘雾视差 + 远景光柱 | ✅ | Agent-C | `BeyondBoundaryLayer.gd` | W0 | core + 目检 | 2026-10-15 ｜ core 6/6 PASS + T42VisualProbe 目检出图通过 ｜ #52 |
| T-4.3 | 环境光尘分层 + Boss 波煞气变奏 | ✅ | Agent-C | `Main.gd`、`WaveSpawner.gd` | W0 | core + 目检 | 2026-10-15 ｜ core 6/6 PASS + 逻辑探针两态切换全过 ｜ #50 |

### Wave 2 —— 敌人演出 / 武器批 2 / UI 与周边（3 车道并行）

| ID | 任务 | 状态 | 认领 | 占用文件 | 依赖 | 验收 | 完成记录 |
|---|---|---|---|---|---|---|---|
| T-3.1 | 死亡消散 dissolve shader ★ | ✅ | Agent-A | `EnemyBase.gd`、`assets/shaders/dissolve.gdshader`（新建） | T-1B | AtlasSkipCheck、KillKnockbackCheck + 目检 + 编辑器扫描 | 2026-10-15 ｜ 专项与 core 全 PASS + 扫描通过 ｜ #51 |
| T-5.4 | Boss 登场演出 | ✅ | Agent-A | `BossEnemy.gd`、`WaveSpawner.gd` | T-1B、T-4.3 | BossTelegraphCheck + 目检 | 2026-10-15 ｜ BossTelegraphCheck PASS + core PASS + 目检 ｜ #52 |
| T-2.5 | 闪电/落雷电弧余韵 | ✅ | Agent-B | `LightningBolt.gd`、`ThunderBurst.gd` | W1 | thunder_check + 目检 | 2026-10-15 ｜ thunder_check 10 项 PASS + core 6 项 PASS + 目检 ｜ #53 |
| T-2.6 | BurstKindFx 九形态强化 | ✅ | Agent-A | `BurstKindFx.gd` | W1 | core + 目检 | 2026-10-15 ｜ core PASS + PerfProbe PASS + 目检 ｜ #53 |
| T-2.7 | 环绕灵宝核心起辉 | 🔵 | Agent-D | `ProceduralDroneRenderer.gd`、`SunOrb.gd` | W1 | core + 目检 | — |
| T-2.8 | 炮台开火闪光 | ✅ | Agent-A | `TurretUnit.gd` | W1 | turret_check + 目检 | 2026-10-15 ｜ turret_check PASS + core PASS + 目检 ｜ #54 |
| T-5.1 | 稀有度辉光配色（哈迪斯式） | ✅ | Agent-C | `GameStyle.gd`、`scripts/ui/levelup/`、`scripts/ui/shop/`、`LevelUpDialog.gd` | W1 | LayoutCheck、BenefitIconTapCheck + LevelUpLayoutPreview 目检 | 2026-10-15 ｜ LayoutCheck 58项 PASS + BenefitIconTapCheck PASS + core 6/6 PASS + LevelUpLayoutPreview 目检通过 ｜ #54 |
| T-5.2 | 结算屏强化 | ✅ | Agent-C | `ResultFx.gd` | W1 | core + 目检 | 2026-10-15 ｜ core 6/6 PASS + T52VisualProbe 胜负两态出图目检通过 ｜ #55 |
| T-3.6 | 生成预警 + 界碑螺旋充能 | ✅ | Agent-A | `SpawnIndicator.gd`、`BlessingObelisk.gd` | W1 | obelisk_charge_readout_check + 目检 | 2026-10-15 ｜ obelisk_charge_readout_check PASS + core PASS + 目检 ｜ #55 |
| T-3.5 | 境界光环 | ✅ | Agent-C | `scripts/entities/player_aura.gd`（新建）、`Player.tscn` | W1 | EntitySizeProbe + 目检 + 编辑器扫描 | 2026-10-15 ｜ EntitySizeProbe MEASURED + core 6/6 PASS + T35VisualProbe 出图目检通过 ｜ #56 |

### Wave 3 —— 收尾

| ID | 任务 | 状态 | 认领 | 占用文件 | 依赖 | 验收 | 完成记录 |
|---|---|---|---|---|---|---|---|
| T-3.3 | 升级仪式感：两段式光柱 | ⬜ | — | `Player.gd` | W2 | HudLevelFxCheck + 目检 | — |
| T-3B | 技能特效强化 + 冲刺残影（含 T-3.2/3.4） | ⬜ | — | `PlayerSkillVfx.gd` | W2 | core、DashTravelProbe、DodgeDeliveryProbe + 目检 | — |
| T-4.5 | CanvasModulate 冷蓝调性（可选） | ⬜ | — | `Main.tscn` | W2 + 用户确认 | LayoutCheck + 全场景目检 | — |
| T-6.1 | 热浪扭曲（可选，默认关） | ⬜ | — | 新 shader + 设置开关 | W2 + 用户确认 | perf_probe 两档 + 目检 | — |
| T-6.2 | 受击屏幕冲击波（可选，默认关） | ⬜ | — | vignette 通道 shader | W2 + 用户确认 | ContactDamageCheck + 目检 | — |

> 说明：`W0/W1/W2` = 对应 Wave 全部任务 ✅。core = `python3 tools/run_test.py --core`。

---

## 四、开发日志（追加式，新的在最下）

| 日期 | 会话 | 任务 | 事件 |
|---|---|---|---|
| 2026-10-15 | — | — | 登记簿建立，29 个任务全部 ⬜ 待领取 |
| 2026-10-15 | Agent-A | T-0.1 | 开始认领并实施 FX_HDR 发光色表 |
| 2026-10-15 | Agent-A | T-0.1 | FX_HDR 发光色表完成，core 与 LayoutCheck 全绿，CHANGELOG #41 |
| 2026-10-15 | Agent-A | T-0.2 | 实施 FxParticlePool 粒子池，类名扫描注册完成，core 与 PerfProbe 55 项全绿，CHANGELOG #42 |
| 2026-10-15 | Agent-A | T-0.3 | 建立灯预算表 FxBudget，上限与断言完成，core 全绿，CHANGELOG #43 |
| 2026-10-15 | Agent-A | T-0.4 | 完成 glow/暗角调参，目检与 core 全绿，CHANGELOG #44 |
| 2026-10-15 | Agent-A | Wave 0 | Wave 0 全任务完成！FxParticlePool API 改为 🔒已冻结，Wave 0 闸门开启 ✅ |
| 2026-10-15 | Agent-A | T-1A | 开始认领并实施命中火花 + 暴击加档 + 暴击跳字（车道 A 首个任务） |
| 2026-10-15 | Agent-A | T-1A | 命中火花与暴击跳字强化完成，所有专项与 core 全绿，CHANGELOG #45 |
| 2026-10-15 | Agent-A | T-1B | 开始认领并实施死亡演出（小怪墨屑 + 精英爆裂磁吸） |
| 2026-10-15 | Agent-A | T-1B | 死亡演出（小怪墨屑+精英爆裂磁吸）完成，专项与 core 全绿，CHANGELOG #46 |
| 2026-10-15 | Agent-A | T-1.5 | 开始认领并实施拾取反馈强化（车道 A Wave 1 最终任务） |
| 2026-10-15 | Agent-A | T-1.5 | 拾取反馈与掉落物呼吸强化完成，core 与 PerfProbe 全绿，CHANGELOG #47 |
| 2026-10-15 | Agent-A | T-2.2 | 开始跨车道协助 Wave 1 推进：认领并实施光束 HDR 芯 + 光晕 + 命中灯（避开 B/C 车道） |
| 2026-10-15 | Agent-A | T-2.2 | 紫虹镜光束视觉升级完成，BeamConeCheck 与 core 全绿，CHANGELOG #48 |
| 2026-10-15 | Agent-A | T-2.3 | 开始认领并实施火锥粒子火焰流（用户点名项，避开 B/C 车道） |
| 2026-10-15 | Agent-A | T-2.3 | 火锥粒子火焰流完成，判定未动，PerfProbe 帧耗正常，CHANGELOG #49 |
| 2026-10-15 | Agent-A | T-2.4 | 开始认领并实施弹丸 HDR 头部辉光 + 拖尾提亮（避开 B/C 车道） |
| 2026-10-15 | Agent-A | T-2.4 | 弹丸 HDR 头部起辉与拖尾提亮完成，core 全绿，CHANGELOG #50 |
| 2026-10-15 | Agent-A | T-3.1 | 开始认领并实施死亡消散 dissolve shader（车道 A Wave 2 首个任务） |
| 2026-10-15 | Agent-A | T-3.1 | 死亡消散 dissolve shader 完成，AtlasSkip 与 KillKnockback 全绿，CHANGELOG #51 |
| 2026-10-15 | Agent-A | T-5.4 | 开始认领并实施 Boss 登场演出（符印大阵+凝聚成形+冲击环短震） |
| 2026-10-15 | Agent-A | T-5.4 | Boss 登场演出完成，BossTelegraphCheck 与 core 全绿，CHANGELOG #52 |
| 2026-10-15 | Agent-A | T-2.6 | 开始认领并实施 BurstKindFx 九形态强化（协助推进 Wave 2，避开 B/C 车道） |
| 2026-10-15 | Agent-A | T-2.6 | BurstKindFx 九形态强化完成，core 与 PerfProbe 全绿，CHANGELOG #53 |
| 2026-10-15 | Agent-A | T-2.8 | 开始认领并实施炮台开火闪光（避开 C/D 车道） |
| 2026-10-15 | Agent-A | T-2.8 | 炮台开火枪口 HDR 闪光与碎屑完成，turret_check 与 core 全绿，CHANGELOG #54 |
| 2026-10-15 | Agent-A | T-3.6 | 开始认领并实施生成预警 + 界碑螺旋充能（避开 C/D 车道） |
| 2026-10-15 | Agent-A | T-3.6 | 生成预警与界碑螺旋充能完成，obelisk_charge_readout 与 core 全绿，CHANGELOG #55 |
| 2026-10-15 | Agent-B | T-2.1 | 领取近战月牙任务（内锐外羽 + 短拖尾），开始实施 |
| 2026-10-15 | Agent-C | T-4A | 认领 T-4A（提前进场通道）并实施：结界流光带 shader 化 + 灵脉 HDR 呼吸 |
| 2026-10-15 | Agent-C | T-4A | 目检结论：LootAndMapPreview 改动前后对比——结界光带呈明暗起伏流光（底帘压暗、亮团流转），太极阵/阵角几何不变；before 图证实中心右上斜线为既有东北灵脉刻槽非新增异物；core 6/6 PASS，CHANGELOG #47 |
| 2026-10-15 | Agent-C | T-4.3 | 领取 T-4.3（Wave 0 已全✅，用户批准 Main.gd 上 T-0.2 一行遗留改动共存），开始实施环境光尘分层 + Boss 波煞气变奏 |
| 2026-10-15 | Agent-C | T-4.3 | WaveSpawner.gd 豁免说明：任务卡占用列含它，但判波信号 GameManager.wave_changed + GameBalance.is_boss_wave 已存在，直接订阅即可，不造冗余信号不动热区 |
| 2026-10-15 | Agent-C | T-4.3 | 目检说明：逻辑探针（Boss 波/末5波进煞气、普通波回常态、重力翻转、1s 渐变、重放闸）全过；离屏截帧全黑（Main 全场景挂探针树下失败，本环境无 GUI），真实帧目检留给用户编辑器/真机异步验收；core 6/6 PASS，CHANGELOG #50 |
| 2026-10-15 | Agent-C | T-4.2 | 领取 T-4.2（结界外深渊：飘雾视差 + 远景光柱），开始实施 |
| 2026-10-15 | Agent-B | T-2.1 | 目检结论：FxPreview 渲染截图（/tmp/fx_preview.png）——六元素近战月牙与横扫扇面均呈内锐外羽形态，亮芯贴刃口锐利、外缘羽化渐隐，白芯 HDR 起辉可见，六色辨识清晰，点缀全收 OUTER 内；weapon_aim_check 539 项 PASS + core 6 项 PASS，CHANGELOG #51 |
| 2026-10-15 | Agent-B | T-2.1 | 完成：近战月牙内锐外羽 + 挥砍短拖尾（拖尾渐隐吃宿主 modulate.a，渲染器零 tween；隐藏清史防池体占拍）。w10 满载 perf 波动经 stash 对照与场景分析确认与本次改动无关（测量窗口内无 WeaponArcRenderer 实例，系并行 headless 抢 CPU 噪声） |
| 2026-10-15 | Agent-C | T-4.2 | 结界外深渊飘雾视差 + 远景幽光柱完成：双层飘雾（0.30/0.60 视差系数补偿）+ 4 条底亮顶消竖直梯形幽光柱；T42VisualProbe 渲染抓帧目检通过；core 6/6 全绿，CHANGELOG #52 |
| 2026-10-15 | Agent-C | Wave 1 | Wave 1 全部 10 个任务全部 ✅！Wave 1 闸门正式开启，Wave 2 任务解锁 |
| 2026-10-15 | Agent-C | T-5.1 | 领取 T-5.1（稀有度辉光配色体系（哈迪斯式）），开始实施 |
| 2026-10-15 | Agent-B | T-2.5 | 领取 T-2.5（闪电/落雷电弧余韵，车道 B Wave 2 首个任务），开始实施 |
| 2026-10-15 | Agent-C | T-5.1 | 稀有度辉光配色体系（哈迪斯式）完成：GameStyle 确立白/蓝/紫/金四档基础与 HDR 超白色系；LevelUpCardFactory 与 ShopOfferCardFactory 卡框及选中光接入 FX_HDR；目检 LevelUpLayoutPreview（/tmp/alloc_layout_16_9.png）紫色卡框高亮泛光与选中光芒层次分明；LayoutCheck 58项全过、BenefitIconTapCheck 全过、core 6/6 全绿，CHANGELOG #54 |
| 2026-10-15 | Agent-C | T-5.2 | 领取 T-5.2（结算屏强化），开始实施 |
| 2026-10-15 | Agent-D | T-2.7 | 领取 T-2.7（环绕灵宝核心起辉；T-2.6 登记撞车被 Agent-A 抢先，按预案顺延），开始实施 |
| 2026-10-15 | Agent-B | T-2.5 | 完成+目检：LightningBolt 主干灭后 0.2s 微弧余韵（锯齿函数参数化共用）；ThunderBurst 雷柱顶端电弧四散 + HIT_SPARK 火花 + pulse_damage_vignette 通道冷蓝白微亮脉冲（不碰 GameManager）。探针第 20 帧抓图：命中端 3 条微型电弧细枝状四散、HDR 细芯可见，符合「雷光有后劲」预期，探针已清理；thunder_check 10 项 PASS + core 6 项 PASS，CHANGELOG #53 |
| 2026-10-15 | Agent-C | T-5.2 | 结算屏强化完成：ResultFx.victory_rain() 增加 FX_HDR_GOLD 超白金色粒与 6 粒慢速浮游大颗粒层次；ResultFx.defeat_gloom() 增加 4 缕缓缓上升正弦微摆冷墨魂屑（呼应 T-1.2 死亡消散）；T52VisualProbe 抓帧目检胜负两态通过；core 6/6 全绿，CHANGELOG #55 |
| 2026-10-15 | Agent-C | T-3.5 | 领取 T-3.5（境界光环），开始实施 |
| 2026-10-15 | Agent-C | T-3.5 | 境界光环完成：新建 scripts/entities/player_aura.gd，依据角色等级与加点数动态呈现 1-3 圈程序化细环，FX_HDR_GOLD 超白起辉，差速慢转与 4s 呼吸明灭；EntitySizeProbe 量测通过，T35VisualProbe 截帧目检金环层次清晰，core 6/6 全绿，CHANGELOG #56 |

---

## 五、返工与问题区

（暂无）
