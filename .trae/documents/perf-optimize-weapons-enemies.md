# 性能优化：法器多 + 敌人多时的卡顿

## Context（为什么改）

用户实测：身上法器（剑）一多、敌人一多就严重卡顿。排查结论——跳字池（DamageNumber）与特效池（JuiceEffect）已池化良好，真正的热点有四类：

1. **头号：敌人程序化矢量渲染每帧全量重绘**
   [HollowKnightEnemyRenderer.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_enemy/HollowKnightEnemyRenderer.gd#L29-L31) `_process` 无条件 `queue_redraw()`，`_draw()` 每只怪重建 40~120 条矢量指令（多边形+描边+每只眼 3 层软辉光圆，且每帧 new `PackedVector2Array`）。35 只怪 = 每帧几千条 draw command 重建 + 数百次数组分配，且每只怪独立批次无法合批 → **敌人一多就卡的主因**。
2. **二号：每发弹丸一盏 PointLight2D**
   [BladeProjectile.tscn](file:///Users/a1/Documents/01Code/Godot/t-1/scenes/weapons/BladeProjectile.tscn#L22-L26) 每弹丸挂一盏 2D 动态灯，6 剑齐射常驻 10~20 盏 → 2D 光照 pass 逐灯叠加 → **剑一多就卡的渲染主因**。
3. **三号：弹丸无池化** — 每发 `instantiate()` + `_ready`（new ProceduralProjectileRenderer + 无限循环 spin Tween）+ `queue_free()`，三发齐射高频开火时每秒 10+ 次节点生命周期全套。
4. **四号：FloatingWeapon 每次攻击/索敌 new 查询对象** — [FloatingWeapon.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/FloatingWeapon.gd#L389-L398) `_deal_melee_damage`/`_find_target`/`_volley_targets` 三处每次 `CircleShape2D.new()` + `PhysicsShapeQueryParameters2D.new()`（BladeProjectile 侧已做 static 复用，此处没做）。

规模参数：`MAX_SLOTS=6`（WeaponData）、`max_enemies=35`（WaveSpawner，还乘 danger 倍率）。

## 方案（按收益排序）

### 1. 敌人重绘节流 + 错相 + 屏外剔除（改动最大收益点，仅一个文件）

`scripts/entities/procedural_enemy/HollowKnightEnemyRenderer.gd`：

- **降频重绘**：普通怪重绘间隔 `1/20s`（小怪本身是 10fps 帧动画风格，20fps 矢量动画无感）；精英/Boss 保持每帧（数量少、动作重）。`_process` 里 `_time += delta` 照旧推进，仅按间隔发 `queue_redraw()`。
- **错相**：每实例随机初始化 `_draw_phase ∈ [0, interval)`，把 35 只的重绘摊到不同帧，避免「每 N 帧一次尖峰」。
- **屏外剔除**：`get_viewport().get_canvas_transform() * global_position` 得屏幕坐标，出屏（四周留 64px 余量）则跳过 `queue_redraw`（`_time` 照常推进，回屏即恢复）。
- 加 static 重绘计数器 `redraw_count`（性能探针断言用）。
- `flip_h`/`config` setter 里的 `queue_redraw()` 保留，并顺带把 `_draw_phase` 归零保证状态变化立刻可见。

预期：35 敌同屏时重绘次数 ≈ 35×60 降到 ≈ 35×20（且屏外的直接归零），GDScript 侧 draw 重建开销降 2/3 以上。

### 2. 弹丸灯光上限

`scripts/weapons/BladeProjectile.gd`：

- static `_lit_count` + `LIGHT_CAP := 6`；`_ready`（或池化后的 acquire）时 `_lit_count < LIGHT_CAP` 才显示 `glow` 并登记，销毁/回池时释放。
- 超限弹丸灯灭但本体矢量辉光（ProceduralProjectileRenderer 自带光晕多边形）仍在，视觉不空。

### 3. BladeProjectile 对象池化（照抄 JuiceEffect/DamageNumber 池模式）

`scripts/weapons/BladeProjectile.gd`：

- static `_pool: Array[BladeProjectile]` + `_host`（挂场景根）+ `POOL_CAP := 64`；首次 `instantiate` 场景做实例，`release` 时 `visible=false` + `set_physics_process(false)` + 碰撞禁用回池，不再 `queue_free`。
- **复用必须全量重置**（列进代码注释防漏）：`direction/speed/damage/knockback_base/lifetime/pierce_left/bounce_left/spin/homing_target/acquire_left/proc_burn/burn_dps/burn_dur/proc_chill/chill_dur/proc_poison/poison_dur/bullet_texture/bullet_scale`，重调 `_apply_elemental_tint()`，`sprite.texture/scale/self_modulate.a`、renderer kind 更新 + `queue_redraw()`，glow 灯按灯光上限重新登记。
- spin 的无限循环 Tween 顺手改成 `_physics_process` 手写自转（`sprite.rotation += delta * TAU / 0.45`），复用时零重建。

### 4. FloatingWeapon 查询对象 static 复用

`scripts/weapons/FloatingWeapon.gd` 三处（`_find_target` / `_volley_targets` / `_deal_melee_damage`）照抄 [BladeProjectile.gd L22-L25](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/BladeProjectile.gd#L22-L25) 的 `_search_shape`/`_search_query` 复用模式（单线程使用，安全；radius/transform 每次重设）。

### 不做的事（明确排除）

- 不重构 ProceduralEnemyView 为烘焙贴图（大改，先看 1~4 的效果）。
- 不动 `take_damage` 的 flash/squash Tween（命中峰值每秒 30 个 Tween 有感但非主因，列为下一批候选）。
- 不动刷怪上限、伤害数值、受击反馈节奏（纯性能优化不改手感）。

## 修改文件

| 文件 | 改动 |
|---|---|
| `scripts/entities/procedural_enemy/HollowKnightEnemyRenderer.gd` | 重绘节流+错相+屏外剔除+redraw_count |
| `scripts/weapons/BladeProjectile.gd` | 灯上限 + 对象池 + spin 手写 |
| `scripts/weapons/FloatingWeapon.gd` | 3 处查询对象 static 复用 |
| `tests/PerfProbe.tscn` + `tests/PerfProbe.gd`（新增） | 性能判据探针 |
| `CHANGELOG.md` | 追加记录 |

## 验证

1. **新增 `tests/PerfProbe.tscn`**（headless 可跑，判据见文件头）：布 6 剑 + 35 敌（含持续命中），跑 ~5 秒统计
   - `HollowKnightEnemyRenderer.redraw_count`：断言每秒重绘次数 ≤ 敌数 × 25（证明节流生效）；
   - physics 帧均耗时：断言 ≤ 6ms（headless 逻辑侧，阈值留余量后可调）；
   - 弹丸池复用计数：断言 acquire 复用 > 0、`created` 不随发射次数增长。
2. **回归基线**：`UnitRunner` / `SmokeRunner` / `PoolCheck` / `BalanceSimCheck` 全绿（新增 class 无需扫描，改的都是已有脚本；若探针声明 class_name 则先跑 `$G --headless --path . --editor --quit`）。
3. **桌面实测**：不带 `--headless` 跑 Main，中期波次 6 剑满配下目测帧率对比（灯上限与渲染节流的渲染侧收益只能在真渲染下验证）。
