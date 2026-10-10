# 第 6 波卡顿性能优化计划

## Context（为什么改）

用户报告从第 6 波开始游戏严重卡顿。经全量探查：逻辑侧此前已有优化且 PerfProbe 判据通过（35 敌+6 弹丸物理帧 ≤8ms），剩余瓶颈集中在**渲染侧与高频分配**，且随击杀数**线性恶化**——与「越打越卡」的现象吻合：

1. **宝石堆积（主因）**：每颗掉落灵石自带 PointLight2D（[AstralGem.tscn](file:///Users/a1/Documents/01Code/Godot/t-1/scenes/entities/AstralGem.tscn) L21-25）+ [ProceduralLootRenderer.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_loot/ProceduralLootRenderer.gd) L38-41 每帧无条件 `queue_redraw()` + [AstralGem.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/AstralGem.gd) L27-29 每颗一个 `set_loops` 常驻 Tween。宝石只在玩家 96px 拾取圈或波末才回收，一场战斗可堆积 100~300 颗（精英掉 5 颗、第 6 波引入的血蛹死亡分裂增加击杀）。2D 光照 pass 成本随灯数线性涨。
2. **命中链路**：[EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd) `take_damage` L527-589 每次命中 create_tween ×2 + DamageNumber + 火花，**屏外敌人照发全套视觉**；DoT tick 也发飘字+火花。
3. **索敌每帧查询**：[Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd) `_update_weapon_targets` L546 每帧 `intersect_shape(32)`，FloatingWeapon 目标失效再查——6 武器时每帧 6~12 次物理查询。
4. **渲染设置**：Forward+ 后端 + `snap_2d_vertices_to_pixel=true`（逐顶点 CPU 对齐、破坏 canvas 批处理）对 2D 游戏偏重。

## 约束

- 打击感近期精调过（受击硬直/击退/顿帧），**squash/flash tween 手写计时化不做**；音效、硬直、击退、闪白一律保留。
- 「画多大 == 判多大」：减灯不删可见光，采用 BladeProjectile `LIGHT_CAP` 先到先得名额模式（超限灯灭但矢量辉光多边形仍在，视觉不空）。
- 每步做完可独立跑判据验证；新增判据写 `tests/perf_probe.gd` 文件头；改完写 CHANGELOG.md。
- `$G=/Applications/Godot.app/Contents/MacOS/Godot`

## 实施步骤（按序，每步独立可验）

### Step 0：先加判据（红）— tests/perf_probe.gd

新增判据 4（宝石）：120 颗宝石摆满屏 1s → `ProceduralLootRenderer.redraw_count` 增量 ≤ 120×25+余量（20Hz 节流+错相）；全移出屏 0.5s 增量 ≤ 2；点亮灯数 == `GEM_LIGHT_CAP`；两轮 acquire 第二轮 created 零增长、reused +120；场上超 `GEM_SOFT_CAP` 后最旧宝石 `target_player != null`。

### Step 1：ProceduralLootRenderer 节流+屏外剔除（P0，收益最大）

照 [HollowKnightEnemyRenderer.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_enemy/HollowKnightEnemyRenderer.gd) L37-67 现成模式：
- `REDRAW_INTERVAL := 0.05`（20Hz）、`CULL_MARGIN := 48.0`、`static var redraw_count`、`_draw_phase`（`instance_id % 97` 错相摊帧）、`_offscreen` 屏外剔除（`get_canvas_transform() * global_position`）。
- `_process`：屏外直接 return；到相才 `queue_redraw()`。
- 三个 setter（loot_type/is_waiting/chest_left_hits）的 `queue_redraw()` 改设 `_dirty = true` 插队重绘。

预期：百颗宝石重绘 60Hz→20Hz、屏外归零，约 3~5 倍降幅。

### Step 2：宝石去 Tween + 灯名额化（P0）

[AstralGem.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/AstralGem.gd)：
- 删除 `_bob_tween`（L17、27-29、42-43）；上下浮动改由 ProceduralLootRenderer._process 自驱动 `position.y = sin(_time * 4.0) * 3.0`（`_time` 已有随机相位）。
- `_physics_process` 默认关闭（`set_physics_process(false)`），`magnet_to` 时开启——静态放置的宝石不再每帧空转。
- 灯名额（照 [BladeProjectile.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/BladeProjectile.gd) L324-343 `_lit_count/_try_acquire_light/_release_light` 模式）：`static var _lit_count`、`GEM_LIGHT_CAP := 8`（与弹丸 6 盏独立）；入坑先到先得，超限 `visible=false`（矢量辉光仍在）；回收/拾取时让位。

预期：全场动态灯从 100~300 盏锁到 ≤8（+弹丸 6+角色/精英数盏）。

### Step 3：宝石实例池 + 软上限保险丝（P0）

[AstralGem.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/AstralGem.gd) 照 BladeProjectile 池模式（L31-43、250-270）：
- `static _pool/_host`、`acquire_or_new(scene, parent)`、`activate()`、`recycle()`；`POOL_CAP := 160`、`created_count/reused_count` 供探针断言。
- activate 全量重置字段（清单写进注释，照 BladeProjectile L30 惯例）：`exp_value/is_gold/灯色/速度/target_player/loot_type`。注意金宝逻辑在 [EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd) L826-828（改纹理/灯色）——纹理改的是已隐藏的 Sprite2D，实际视觉由 `is_gold` setter 驱动 loot_type，池化后统一走 activate。
- 三个掉落点改走池：[EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd) L820、[SpiritChest.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/SpiritChest.gd) L172、[BlessingObelisk.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/BlessingObelisk.gd) L313；拾取回调 [Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd) L798-803 改为调 `recycle()`。
- 保险丝：`static _active_gems` 计数，超 `GEM_SOFT_CAP := 140` 时强制最旧一颗 `magnet_to(GameManager.player)`（自动飞向玩家，**无经验损失**）。

### Step 4：索敌降频（P1）

- [Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd) `_update_weapon_targets`：加 `_search_interval := 0.1`（10Hz）+ `_search_phase` 错相（instance_id 派生），到相才执行。
- [FloatingWeapon.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/FloatingWeapon.gd) L171-178 脱程重查降到 15Hz；`is_instance_valid` 失效回退保留即时（防打空）。

预期：物理索敌查询从每帧 6~12 次降到均摊 <2 次。风险：新敌入射程最多延迟 100ms 锁定，无感。

### Step 5：命中链路屏外减负（P1）

[EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd)：
- 缓存 `_offscreen`（照 HollowKnightEnemyRenderer 同式算 canvas_transform，每帧顺手算一次）。
- `take_damage`：屏外跳过 `DamageNumber.spawn`（L561）与 `JuiceEffect.spawn_hit_sparks`（L564）；音效（L551/559）、硬直、击退、闪白、顿帧**全保留**。
- DoT tick（from_dot）不再发火花，跳字保留。

### Step 6（需用户决策，单独做可回滚）：渲染设置

- `project.godot` [rendering] 段补 `renderer/rendering_method="mobile"`：Android 官方推荐后端，2D 批处理与显存更优；项目未用 Forward+ 独有特性。风险：外观微差需真机各验一段。
- 关闭 `2d/snap/snap_2d_vertices_to_pixel`（L71）：逐顶点 CPU 对齐破坏 canvas 批处理；本项目主体是程序化矢量绘制 + 非整像素 squash 缩放，本就无整像素收益。风险：镜头移动亚像素观感微变。
- 两项各单独验证：真机/桌面第 6 波录 FPS 对比，异常即回滚。

## 验证

1. **判据**：`$G --headless --path . res://tests/PerfProbe.tscn`（新宝石判据全绿 + 原判据不回退）。
2. **全回归**：UnitRunner / SmokeRunner / PoolCheck / LayoutCheck / FontCoverageCheck / BalanceSimCheck（headless，exit 0 且 `*_RESULT: ALL PASS`）。
3. **桌面实测**（不加 --headless）：跑真实第 6 波或建满载预览（120 宝石+35 敌），对比优化前后 FPS 与绘制指令数。
4. P2 两项如实施：真机各录一段对比后由用户确认保留或回滚。
5. 每步追加 CHANGELOG.md（`## 2026-10-10 #序号`）。

## 关键文件

- [tests/perf_probe.gd](file:///Users/a1/Documents/01Code/Godot/t-1/tests/perf_probe.gd) — 判据扩展
- [scripts/entities/procedural_loot/ProceduralLootRenderer.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/procedural_loot/ProceduralLootRenderer.gd) — 节流+剔除
- [scripts/entities/AstralGem.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/AstralGem.gd) — 去 Tween/灯名额/池/保险丝
- [scripts/entities/EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd) — 掉落走池 + 屏外减负
- [scripts/entities/Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd) / [scripts/weapons/FloatingWeapon.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/FloatingWeapon.gd) — 索敌降频
- [scripts/entities/SpiritChest.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/SpiritChest.gd) / [scripts/entities/BlessingObelisk.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/BlessingObelisk.gd) — 掉落走池
- [project.godot](file:///Users/a1/Documents/01Code/Godot/t-1/project.godot) — P2 渲染设置（待确认）
