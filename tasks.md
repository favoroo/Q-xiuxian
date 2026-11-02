# 四项优化落地 — 任务清单

## T1 敌人数值进数据表
- [x] 1.1 EnemyData.gd：MOBS/ELITE_POOL/LOOTER_DEF 加 `"stats"` 子字典（按 spec 全量清单逐值平移）+ `stats_for_scene()` 惰性反查 + 头注释更新
- [x] 1.2 EnemyBase.gd：新增 `_apply_data_stats()`，在 `acquire_or_new` 快照前调用
- [x] 1.3 16 普通+6 精英 tscn 删数值覆写（保留 spritesheet_path/locomotion_mode/enemy_id/split_scene/minion_scene/视觉节点）
- [x] 1.4 判据测试迁移到 acquire_or_new：wolf_ai/hover_intent/poison_pool/boss_telegraph/flock/contact_damage/enemy_new_mechanics/elite_attack(_spawn_standalone+_check_scene_config)/unit_content jinchan
- [x] 1.5 balance_sim_check.gd 新增敌种数值表回环判据；gold_curve_probe.gd 改读 EnemyData
- [x] 1.6 验证：--core 全绿 + 上述专项单跑全绿；acquire 对账 diff 为空（225 字段全一致；elite_attack/boss_telegraph 为存量红，改动前后失败项完全一致）
- [x] 1.7 CHANGELOG `## 2026-11-02 #13`

## T2 取色治理
- [x] 2.1 `git status --short` 确认 GameStyle.gd 无他人占用
- [x] 2.2 StartMenu.gd 88 处 Color( 分类：87 处冗余包裹剥除 + 1 处字面量改 TRANSPARENT（审计发现真硬编码极少）
- [x] 2.3 其余文件审计替换（HudWaveLeft/HudBossBar/SettingsDialog/DetailTip/WaveLootSummary/GameHUD/HudShieldBar/MergeFx/CultivatorSelect，GameStyle.gd 零改动）
- [x] 2.4 验证：--core + StartMenuCompositionProbe + NightmareMenuCheck 全绿；主题跟随结构性论证
- [x] 2.5 CHANGELOG `## 2026-11-02 #16`（因他 Agent 抢占 #14 而顺延）

## T3 新手引导情境提示
- [x] 3.1 情境气泡实现（HudContextTips + SettingsManager 偏好键 ui/ctx_tip_*）
- [x] 3.2 四触发点接入：首进商店 / 首遇宝箱 / 聚灵阵 / 精英怪（GameManager.context_tip_requested 信号，门控在显示侧）
- [x] 3.3 无新字符（font_charset 零改动）+ 新增 ContextTipGateCheck 29 项
- [x] 3.4 验证：--core 全绿 + 首触发/二次不弹/落盘回读判据全绿
- [x] 3.5 CHANGELOG `## 2026-11-02 #17`

## T4 EnemyBase AI 拆分
- [x] 4.1 新建 scripts/entities/enemy_ai/ 四个静态模块（Ranged/Charge/Aoe/Support），首参传宿主不标类型
- [x] 4.2 EnemyBase 只留 tick 分发与状态字段；逐行平移（3146→2162 行）
- [x] 4.3 编辑器扫描 + --core + AI 专项判据全绿（elite_attack/boss_telegraph 存量红前后逐字一致）
- [x] 4.4 CHANGELOG `## 2026-11-02 #15`（按完成顺序实际续号）

## T5 总结
- [x] 中文 Markdown：事项 → 改了什么 → 验证结果 → 残留风险，结论先行（见对话最终输出）
