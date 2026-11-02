# 剑士四项优化落地 — 技术规格（Spec）

> 目标：把已完成的分析转为实际代码修改，四项按序落地，每项自测后再下一项。
> 通用约束：不改无关玩法数值/平衡；保留他人未提交改动（CHANGELOG.md、tools/export_site_data.py、site/dist/）；每项有验证证据；完成写中文总结。
> 基线已建立：`python3 tools/run_test.py --core` 全绿（46.47s，Pool 103 / Layout 76 / Font 14 / BalanceSim 182 项）。

## 事项一：敌人数值进数据表

### 现状（已逐文件核实）
- `EnemyBase.gd` 有 81 个 `@export`（头注释称 49 个数值），默认值为行为开关式（0=关闭）。
- 16 个普通怪 + 6 个精英 .tscn 的数值覆写已逐行提取（见下表）；BossEnemy.tscn 数值由 `WaveSpawner._spawn_boss` 运行时注入，不在本次范围。
- 出场链路：`WaveSpawner._schedule_enemy_spawn / _spawn_elite / _spawn_looter / BossEnemy 召唤 / 蛛母产卵 / 血蛹分裂` → 全部经 `EnemyBase.acquire_or_new(scene)` → `reset_for_reuse()` → `_scale_to_wave()` → `activate()`。出厂快照 `_capture_base_stats()` 在 acquire 当刻拍，池化复用经快照回滚。
- `spawn_minion_count`/`spawn_minion_cap` 写在 WanduEliteEnemy.tscn 里但 EnemyBase 无此字段 —— 失效死配置（存量问题，本次不迁移、不修复，仅记录）。
- 赤雷兽 `ring_bolt_interval` 任何路径都不赋值（恒 0.0，`_enter_mutation` 只在 >0 时增发弹数）；elite_attack_check 有两处断言它 >0 / ==5.0 —— 基线跑测确认该判据现状（若现状即红，属存量失败，本次顺带钉真）。
- `_scale_to_wave` 里毒潭伤害/半径的回合缩放嵌套在 `stone_reward > 0` 分支内（毒妖吃不到缩放）—— 存量行为，保持原样不动。

### 决策
1. **表结构**：`EnemyData` 的 MOBS 14 行、ELITE_POOL 6 行、LOOTER_DEF 各加 `"stats": {...}` 子字典，逐值平移 tscn 数值覆写（绝对值，幂等）。新增惰性反查：
   ```gdscript
   static var _stats_by_scene: Dictionary = {}
   static func stats_for_scene(path: String) -> Dictionary
   ```
   未列字段继续吃 EnemyBase 类默认值（与 tscn 未覆写时行为一致）。
2. **应用点（唯一）**：`EnemyBase.acquire_or_new` 新鲜实例分支，`_capture_base_stats()` 之前调用 `fresh._apply_data_stats()`（新增私有方法，按 `_pool_key` 查表 `set()` 逐字段写入）。池化复用经既有快照回滚，天然同源。`_ready` 不动 —— 避免冲掉判据测试在 add_child 前手动 set 的字段（thunder/guard/kill_knockback 等）。
3. **场景瘦身**：16+6 个 tscn 删除数值覆写行（含 is_elite）；保留视觉/身份/结构行：`spritesheet_path`、`locomotion_mode`、`enemy_id`（显式身份，删除虽有 `_deduce_enemy_id` 兜底但零收益）、`split_scene`/`minion_scene`（PackedScene 结构引用）、碰撞形状/材质/灯。BossEnemy.tscn 不动。
4. **各怪 stats 全量清单**（与 tscn 逐值对账）：
   - slime 18/105/12/exp3；danbao 20/130/10/exp3 + explode90 + death_bolt 5×0.6 + heal_orb3；xiexiu 24/115/13/exp5 + range260 + bolt2.5/15 + windup0.35；leibeast 45/120/18/exp6 + charge 全套(4.0,120,450,0.8,0.75,3.2,0.25,34,1.0,0.9) + aim_lead0.14；flower 25/138/15/exp4；fengqun 12/168/6/exp2；xueyong 35/92/14/exp4 + split3；yingmei 26/105/13/exp5 + teleport4.2；lingyi 30/120/6/exp6 + range240 + heal1.6/240/6；guyao 42/85/8/exp6 + range210 + buff230×1.35；duyao 34/92/9/exp5 + poison4.5/62/0.6/3/5；zhumu 65/70/16/exp7 + minion3.5；hanpo 38/95/14/exp6 + range240 + bolt2.2/16×3 spread0.22 windup0.35 curve0.35 + death_bolt 6×0.6；mowei 78/105/18/exp8 + charge(5.2,100,380,0.9,0.6,2.8,0.2,32,1.2,0.6,0.25) + slam(4.6,95,0.8,1.15)。
   - golem 1000/82/26/exp8 + is_elite + slam(4.2,115,0.9,1.1) + rock(6.5,3,85,0.9,0.9,140,0.35)；chilei 1200/126/30/exp8 + is_elite + charge(2.1,110,480,0.68,0.8,3.8,0.28,35,1.3,0.6,0.16) + chain(2,0.55) + side_bolts1；jiansha 1100/118/26/exp8 + is_elite + range280 + bolt1.7/17×3 spread0.22 windup0.35 + field(7.0,120,0.8,0.8,3.5)；xuanming 1350/110/28/exp10 + is_elite + range250 + bolt1.9/18×2 spread0.18 windup0.35 + ring(4.8,8,160,0.75,0.4,0.45) + rock(6.2,3,85,0.9,0.9,140,0.35)；xingpan 1450/0/28/exp10 + is_elite + bolt1.45/17×4 spread0.2 windup0.3 + ring(2.6,12,175,0.75,0.35,0.65)；wandu 1250/92/25/exp10 + is_elite + range290 + minion6.0 + field(5.5,115,0.75,0.8,4.0) + poison(3.2,0.65)。
   - jinchan（LOOTER_DEF.stats）40/165/0/exp4 + always_flee + stone_reward1。
5. **判据测试同步迁移**（直实例化改走工厂 `EnemyBase.acquire_or_new`，一行级改动）：
   - `tests/wolf_ai_check.gd` `_spawn_wolf`；`tests/hover_intent_check.gd` `_spawn_xiexiu`；`tests/poison_pool_check.gd` `_case_duyao_windup`（断言「场景初值 62」改「表初值 62」）；`tests/boss_telegraph_check.gd` 丹爆/星盘/万毒三处；`tests/flock_separation_check.gd` `_spawn`；`tests/contact_damage_check.gd` `_case_jinchan_contact`；`tests/enemy_new_mechanics_check.gd` `_spawn_enemy`；`tests/elite_attack_check.gd` `_spawn_standalone` + `_check_scene_config`；`tests/unit/unit_content_tests.gd` `_test_jinchan_zero_damage`。
   - 不需要动：thunder/guard/elixir/dash/kill_knockback/spirit_beast/EliteHitSpark/perf_probe/entity_size_probe/pool_check e1-e3（自设字段或只看视觉帧缓存）、weapon_audio_check（LeiBeast 吐弹用类默认值，改动前后一致）。
6. **BalanceSimCheck 覆盖**：`tests/balance_sim_check.gd` 新增一段「敌种数值表 → 出厂实例」回环判据：遍历 MOBS+ELITE_POOL+LOOTER_DEF，`acquire_or_new` 后逐字段断言 `e.get(field) == stats[field]`，并钉 max_hp>0、exp_reward 与 gold_curve 口径一致；`tests/gold_curve_probe.gd` 的硬编码 info 表改从 `EnemyData` 读（消重复真话）。
7. **CHANGELOG**：`## 2026-11-02 #13`（当日已有 #12，续号），记架构变动 + wandu 死配置存量发现。

### 验证
- `python3 tools/run_test.py --core` 全绿（含新 BalanceSimCheck 段）。
- 单跑专项：wolf_ai / hover_intent / poison_pool / boss_telegraph / flock_separation / contact_damage / enemy_new_mechanics / elite_attack / gold_curve_probe。
- 对账脚本（一次性）：迁移后逐怪 acquire_or_new 打印关键字段，与迁移前 tscn 值 diff 为空。

## 事项二：取色治理（StartMenu + UI 层审计）

### 现状
- `GameStyle.gd`（1645 行）是唯一取色入口：`GOLD` 三件套为 static var，五套 `THEME_PRESETS` + `apply_theme_color()`，样式必须走注册表才跟主题。
- `StartMenu.gd` 有 88 处硬编码 `Color(`；UI 层合计 134 处 / 22 文件（GameHUD 11、CultivatorSelect 6、ShopDragDrop 5 等）。
- GameStyle.gd 是共享串行文件，改前必须 `git status --short` 查占用。

### 决策
1. **分类口径**：①面板/文字/主色相关 → 必须走 GameStyle 注册表（现有常量或新增注册常量）；②菜单装饰特效色（流星雨、氛围粒子等纯表现、不随主题的）→ 收进 StartMenu 顶部 `const` 区命名常量，注明「装饰特效色不随主题」。判断标准：该色是否与 INK/NAVY/PAPER/GOLD 语义重合、主题切换时是否应跟随。
2. **执行**：先 StartMenu（88 处逐一分类替换），再按数量降序审计其余 21 文件，同类处理。新增注册色时优先复用现有常量；确需新增走 GameStyle 注册表模式（static var + 主题联动）。
3. **不改视觉**：替换后逐文件 diff 渲染值（Color 字面量 → 同名常量等值），不允许改色相。
4. **CHANGELOG**：`## 2026-11-02 #14`。

### 验证
- `python3 tools/run_test.py --core`（LayoutCheck 覆盖摆位）；`menu_meteor_shower_preview` / `start_menu_composition_probe` 专项。
- 主题跟随验证：跑编辑器或用 LayoutCheck 自检外，加一条运行期断言（如 start_menu_composition_probe 已有结构探测）—— 若无法自动化验证五套主题逐一截图，写明限制并以「所有替换色均走注册表 ⇒ 结构性跟随」为证据。

## 事项三：新手引导情境提示

### 现状
- `DetailTip.gd` 是现成「这是什么」点按气泡；`TutorialDialog.gd` 有「首次进入弹窗 + 设置入口 + 下次不弹出」偏好存储模式可复用。
- 触发点：首次进入商店（WaveShop）、首遇宝箱（SpiritChest）/聚灵阵（BlessingObelisk）/精英怪（WaveSpawner._spawn_elite 播报点）。

### 决策
1. 新增轻量情境气泡（不打断战斗、非模态、几秒自消或点按关闭），复用 DetailTip 视觉与「不再提示」偏好存储（SettingsManager/ProgressStore 现有键位模式）。
2. 四个触发点各一条文案（简短口语，遵守「同一概念只用一个词」）：商店=「金币阁：回合间隙花金币买武器道具」；宝箱=「藏宝匣：打碎掉装备」；聚灵阵=「聚灵阵：站进去充能领灵兽」；精英=「精英怪：血厚招狠，击杀掉好货」。
3. 每个提示各自独立的「已看过」键；设置里可重置（若 TutorialDialog 已有重置入口则挂同一处）。
4. **CHANGELOG**：`## 2026-11-02 #15`；改文案后跑 `subset_fonts.py` + FontCoverageCheck。

### 验证
- 新增/扩展判据（tutorial_gate_check 已有门控模式可参考）或运行时冒烟：首触发弹出、二次不弹、偏好键落盘。
- `--core` 回归。

## 事项四：EnemyBase 拆分（AI 状态机外移）

### 现状
- EnemyBase.gd 3135 行；AI 行为支路：火球/长扑/自爆引信/闪现/产卵/治疗/光环/投毒/震地/落石/雷环/雷剑域/链冲/瞬身回斩/金蟾逃窜（扑咬已在 EnemyLunge 独立文件，死亡解析已在 enemy_death/ 为先例）。
- 坑 16：外移静态模块首参传宿主且不标类型；宿主常量经无类型实例访问；无类型参数上禁用 `:=` 推断。
- 坑 12：禁硬引用 EnemyBase。

### 决策
1. 新目录 `scripts/entities/enemy_ai/`，按行为族拆静态模块（参照 weapons/handlers 模式）：建议 `EnemyAiRanged.gd`（火球+雷环+瞬身回斩）、`EnemyAiCharge.gd`（长扑+链冲）、`EnemyAiAoe.gd`（震地+落石+雷剑域+投毒+自爆）、`EnemyAiSupport.gd`（治疗+光环+产卵+闪现+金蟾逃窜）。宿主 EnemyBase 只留 tick 分发与状态字段。
2. 逐行平移不改逻辑；行为常量随实现走（写进对应模块）；`_physics_process` 里原 `_tick_*` 调用改为模块调用。
3. **CHANGELOG**：`## 2026-11-02 #16`。

### 验证
- `--core` 全绿 + 专项：wolf_ai / elite_attack / enemy_new_mechanics / poison_pool / boss_telegraph / flock_separation / enemy_ai 相关判据（按 tests/ 目录实扫选定）。
- 行为一致性证据：上述判据全绿即「行为完全一致」的可验证部分；无法自动覆盖的（真机手感）写明限制。

## 交付顺序与门禁
t1 →（自测绿）→ t2 → t3 → t4 → 中文 Markdown 总结（事项→改了什么→验证结果→残留风险，结论先行）。每完成一项更新 TodoWrite 并追加 CHANGELOG。
