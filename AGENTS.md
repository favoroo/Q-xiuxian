# AGENTS.md — 剑士开发指南

> 供 AI 开发 Agent 阅读。判据细节写在脚本文件头注释与 `tests/*.gd` 文件头，不在此抄录。
> **红线：除非用户明确要求修改本文件，否则严禁擅自修改 AGENTS.md。**

## 项目简介

类「土豆兄弟（Brotato）」俯视角自动攻击幸存者，修仙题材包装。

- **引擎** Godot 4.7（桌面 Forward+，Android 端 gl_compatibility）/ GDScript，主场景 `res://scenes/main/Main.tscn`
- **平台** Android APK（`export_presets.cfg` arm64-v8a，包名 `com.favo.qxiuxian`），桌面调试 960×540；另有 Web 导出预设（产物进宣传站 `site/dist/`，归 `web-deploy` skill 管）
- **版本** 见 [Version.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/Version.gd)，远端 GitHub `favoroo/Q-xiuxian` + Gitee `favo9/q-xiuxian`
- **物理** Jolt，6 层碰撞层（1 world / 2 player / 3 enemies / 4 player_projectiles / 5 loot / 6 interactables），勿改
- **核心循环** 选人 → 选武器 → 20 波战斗（`GameManager.VICTORY_WAVE`）→ 回合后统一悟道加点（一屏 `UPGRADE_OFFER_COUNT`=5 个候选、每回合 1 次免费刷新）→ 回合间金币阁（`SHOP_BASE_SLOTS`=5 格）→ 胜负结算

## 快速定位

| 要做什么 | 去哪里看 |
|---------|---------|
| 调数值/公式 | `scripts/systems/` 的 `Balance*.gd` 主题类（Wave/Economy/Combat/Targeting/BuildFilter/Recommend/SpiritBeast/SpiritPet/Chest，全 `static` 纯函数）；[GameBalance.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/GameBalance.gd) 只是无状态转发门面，新公式进主题类、别进门面 |
| 调全局状态/上限常量 | [GameManager.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/GameManager.gd) 顶部常量区 |
| 调悟道加点表 | [UpgradeData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/UpgradeData.gd)（`"apply"` 字典是生效幅度唯一真话） |
| 改武器/角色/道具/技能数据 | `scripts/data/`（[WeaponData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/WeaponData.gd) / [CultivatorData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/CultivatorData.gd) / [ItemData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/ItemData.gd) / [SkillData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/SkillData.gd)） |
| 改图鉴/成就/属性说明数据 | `scripts/data/`（[ManualData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/ManualData.gd) / [AchievementData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/AchievementData.gd) / [StatInfoData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/data/StatInfoData.gd)） |
| 改回合后加点/商店节奏 | [WaveSpawner.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/WaveSpawner.gd) `_enter_wave_break` + [LevelUpDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/LevelUpDialog.gd) + [WaveShop.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/WaveShop.gd) |
| 改刷怪/回合配比 | [WaveSpawner.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/WaveSpawner.gd) |
| 改玩家/敌人/Boss/场景交互物 | `scripts/entities/`（[Player.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/Player.gd) / [EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd) / [BossEnemy.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/BossEnemy.gd) / [BlessingObelisk.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/BlessingObelisk.gd) / [SpiritChest.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/SpiritChest.gd)） |
| 改武器/弹丸追踪 | `scripts/weapons/`（[FloatingWeapon.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/FloatingWeapon.gd) / [BladeProjectile.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/BladeProjectile.gd)；七种攻击行为实现与手感常量在 `scripts/weapons/handlers/` 静态模块） |
| 重绘/新增武器器形 | `scripts/weapons/shapes/` 族模块（[WeaponShapeLibrary.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/shapes/WeaponShapeLibrary.gd) 按 `_FAMILIES` 优先级调度；只改对应族文件，族模块一律按路径 preload **不加 `class_name`**，别动库与宿主 `ProceduralWeaponRenderer`） |
| 改打击感/震屏 | [JuiceEffect.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/JuiceEffect.gd) → `GameFeel.gd` → [SmoothCamera.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/controllers/SmoothCamera.gd)（创伤预算闸在 `BalanceCombat.trauma_grant`；受击火花/死亡爆散已整体下线，别顺手复活） |
| 改 UI 样式/配色/字体 | [GameStyle.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/GameStyle.gd)（**唯一取色入口**） |
| 改音效/BGM | [AudioManager.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/AudioManager.gd) |
| 改应用内更新 | [UpdateManager.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/UpdateManager.gd) |
| 烘焙音效 | [tools/bake_sfx.py](file:///Users/a1/Documents/01Code/Godot/t-1/tools/bake_sfx.py)（media-gen 不含 SFX） |
| 子集化字体 | [tools/subset_fonts.py](file:///Users/a1/Documents/01Code/Godot/t-1/tools/subset_fonts.py) + `font_charset.txt` |
| 生成美术/语音/BGM | [.agents/skills/media-gen/](file:///Users/a1/Documents/01Code/Godot/t-1/.agents/skills/media-gen/SKILL.md) |
| 查历史改动 | [CHANGELOG.md](CHANGELOG.md)（已纳入版本控制） |
| 发版/打 APK | [.agents/skills/xiuxian-release/](file:///Users/a1/Documents/01Code/Godot/t-1/.agents/skills/xiuxian-release/SKILL.md)（管 Android）；Web 导出/部署用 [.agents/skills/web-deploy/](file:///Users/a1/Documents/01Code/Godot/t-1/.agents/skills/web-deploy/SKILL.md)，两者互不干扰 |
| 角色程序化美术 | [.agents/skills/hollow-cultivator/](file:///Users/a1/Documents/01Code/Godot/t-1/.agents/skills/hollow-cultivator/SKILL.md) 流水线规范；实现落 `scripts/entities/procedural_cultivator/` 等 procedural_* 子目录 |

## 分层铁律

1. **数值只进数据表/常量区**，不写魔法数字。
2. **`GameBalance.gd` 全 `static` 纯函数** — 不读 autoload、不碰节点、不调全局 `randf()`。
3. **玩法判定随机走 `GameManager.rng`** — 掉落/伤害/选择等影响判定的随机不用全局 `randf()`/`pick_random()`，否则测试钉不住。纯表现层随机（VFX 粒子、电弧抖动、音效变体）可用全局/本地 RNG，但不得影响判定数值；成段演出随机用本地 RNG 以 `instance_id` 播种（样板 `ChestBurstFx.gd`），禁碰 `GameManager.rng`。
4. **信号驱动解耦** — 全局状态走 `GameManager` signal，实体间不互引。
5. **有场景的实体类 `.tscn` 与 `.gd` 同名配对**，目录镜像（`scenes/x` ↔ `scripts/x`）；纯脚本/工厂/控件类不需要配场景。
6. **渲染层只读状态** — 范围视觉与判定同源。

## 开发规范

- GDScript Tab 缩进，静态类型标注，注释中文，关键常量写 `##` 文档注释。
- 新增 `class_name` 脚本或新素材后先跑编辑器扫描，否则类名解析不到、新资源不算已导入：
  ```bash
  $G --headless --path . --editor --quit
  ```
- 升级项生效幅度在 `UpgradeData` 的 `"apply"` 字典，文案数字与它同源；道具与升级共用同一条属性链路。
- `snap_2d_vertices_to_pixel` 已关（逐顶点 CPU 对齐破坏 canvas 批处理，2026-10-17 性能治理）；纹理 Nearest 过滤仍开。

## UI 规范

统一入口 **`GameStyle.gd`**（取色/取字体/取斜率，禁止散落硬编码）：

- 新野兽派（2026-10-19 换肤）：无圆角无渐变无柔光，全直角；四档斜率常量 `SLANT_PLATE/BLOCK/BUTTON/BAND` 已归零（常量保留、调用点不动，别再按 3/5/6/10 理解）。
- 配色：纯黑舞台（`INK`）+ 宣纸白面板（`NAVY` 系）+ 纸面墨字（`PAPER`）；主色 `GOLD` 三件套是 `static var`，玩家可在设置里五套主题色自选（`GameStyle.THEME_PRESETS` + `apply_theme_color()`，样式必须走注册表换色才跟得上）。角色另有六套主题皮肤（`SkinData.gd`，按最高通关难度解锁）。字体 `MiSans-Semibold`/`MiSans-Heavy`。
- 按钮 sfx 在 `GameStyle.button()` 统一挂。
- **「这是什么」点按可得**（`DetailTip`），别用 `tooltip_text`（Android 无 hover）。
- **中文长句用 `GameStyle.wrap_cjk()` 切硬换行** — 引擎 `AUTOWRAP_WORD` 在中文真机上不可靠。
- 卡片不按死宽度摆，按 viewport 现算。
- **游戏文本保持简短、通俗易懂** — 同一概念全项目只用一个词（金币/道具/角色/技能/回合/经验/生命/商店/灵兽），不造生僻雅称；该解释的机制用小字补一句，不堆长句。

## 素材管线

- AI 生成 → 源图 → `tools/` 切片 → `assets/art/` → Godot 引用。images 源图已整体外迁 `~/AssetsLibrary/qxiuxian-raw/`（见 `assets_raw/README.md`），`assets` 是产物，勿直接改产物。
- `assets_raw/manifest.jsonl` 记录来源与 prompt，新增素材要补记。
- 音效走 `bake_sfx.py`，BGM/语音才用 media-gen。BGM 入包前 `ffmpeg -b:a 64k` CBR 重编码（真机听感验收不达标才回 96k）。
- 加完音效 key 要把脚本打印的 `_register_sfx(...)` 粘进 `AudioManager._load_audio_assets()`，再跑编辑器导入 + `UnitRunner`。
- 改了 UI 文案后重跑 `subset_fonts.py` + `FontCoverageCheck`。

## 回归测试

`G=/Applications/Godot.app/Contents/MacOS/Godot`。所有判据场景均位于 `tests/`，headless 运行退出码 0 且打印 `*_RESULT: ALL PASS` 即通过。

### 核心基线（每次改动必跑）

```bash
# 推荐一键运行全量核心基线（~25s，内置看门狗防无头死锁）：
python3 tools/run_test.py --core
# 其余模式：--quick（仅 UnitRunner）/ --soak（SoakCheck 长跑）/ --all（自动扫 tests/*.tscn 全量，
# 内置跳过 *Preview / AudioGallery 等名单）/ --clean-zombies（清 Godot 僵尸进程）/ --auto-import。
# 个别慢测试有独立超时表（SmokeRunner 60s / ManualHotzoneCheck 140s / SoakCheck 240s），排 hang 先看它。

# 亦可单独运行各判据场景（优先用 python3 tools/run_test.py <测试名>，或直接调 Godot）：
$G --headless --path . res://tests/UnitRunner.tscn        # 数值与公式单测
$G --headless --path . res://tests/SmokeRunner.tscn       # 全流程冒烟
$G --headless --path . res://tests/PoolCheck.tscn         # 帧缓存/对象池
$G --headless --path . res://tests/LayoutCheck.tscn       # UI 摆位（自检可带 -- --selftest）
$G --headless --path . res://tests/FontCoverageCheck.tscn # 字体子集覆盖
$G --headless --path . res://tests/BalanceSimCheck.tscn   # 伤害与生命平衡仿真
```

push/PR 到 main 会触发 CI 门禁（`.github/workflows/tests.yml` 跑 `--core`，Godot 4.7.2 headless + `.godot` 导入缓存）；本地绿 CI 红多半是导入缓存问题，用 `--auto-import` 重扫。

### 专项测试与预览工具（按改动模块选跑）

- **专项判据（`tests/*Check.tscn` / `tests/*Probe.tscn`）**：覆盖 AI、技能、武器朝向、弹丸命中、震退、回复珠、聚灵阵、藏宝匣、手势/滚动等专项逻辑。具体参数（如 `-- --selftest`）见对应 `tests/*.gd` 文件头注释。`LayoutCheck` 报红时可跑 `res://tests/LayoutBleedProbe.tscn` 查看边界诊断数据。
- **非判据现场预览（`tests/*Preview.tscn` / `AudioGallery.tscn`）**：需要真实出声/出图，运行时**不加 `--headless`**。
- **约定**：新增测试直接放入 `tests/` 即可，**禁止将新增测试命令追加到本文件**。

## 并行协作约定（多 Agent 并行开发）

本项目常由多个 Agent 并行修改，按此约定避让以减少文件冲突：

- **共享串行文件**（同一时间全局只允许一个 Agent 改，改前先 `git status --short` 看是否已被占用）：`export_presets.cfg`、`project.godot`、`scripts/autoload/Version.gd`、`assets_raw/manifest.jsonl`、`tools/font_charset.txt` + `fonts/MiSans-*.woff2`、`scripts/ui/GameStyle.gd`（唯一取色入口）。
- **核心热区大文件**（`GameManager.gd` / `Player.gd` / `EnemyBase.gd` / `GameHUD.gd` / `WaveShop.gd` / `LevelUpDialog.gd`）历史共改率最高，改前必须确认无人占用；新需求优先落子目录新文件，不再往大文件里堆。2026-10-24 拆分后 `FloatingWeapon`（行为已拆 handlers/，本体只留轨道/索敌/冷却分发/开火视觉状态机）、`Player`（技能实现已拆 player_skills/，`_physics_process` 已切成 `_tick_*` 切片）、`EnemyBase`（死亡解析已拆 enemy_death/，`_tick_behaviors` 已切成 15 个敌型 `_tick_*`）冲突面显著缩小，改行为/技能/死亡优先去对应子目录。武器侧三件套（`FloatingWeapon` / `BladeProjectile` / `ThunderBurst` / `SunOrb`）是第二冲突区，五行异常施加一律走 `scripts/weapons/ProcStatus.gd`，不再手写 `has_method` 三行块。`tests/unit_runner.gd` 已拆成纯调度器，不再是热区；单测热区在 `tests/unit/unit_content_tests.gd` / `unit_infra_tests.gd`。
- **static 伪 autoload**（`scripts/autoload/` 下 `extends RefCounted` 的 static 纯类，project.godot 未注册，经 `GameManager` 薄壳转发调用）：`StatSystem` / `ShopSystem` / `GameFeel` / `RunSave` / `RunReset` / `ProgressStore` / `CultivatorSystem` / `PetSystem` / `SynergySystem` / `RecommendSystem` / `AllocSession` / `WeaponInventory`。新子系统照这个模式建新文件，别往 `GameManager.gd` 里堆。
- **子目录归属**（拆分落位后的归属约定）：`scripts/ui/hud/` 战斗 HUD 控件；`scripts/ui/shop/` 金币阁卡工厂与槽位；`scripts/ui/levelup/` 悟道卡工厂（`LevelUpCardFactory`，宿主 LevelUpDialog 只留面板流程）；`scripts/ui/stats/` 属性面板 builder；`scripts/ui/codex/` 图鉴卡工厂与敌形捕获；`scripts/ui/author/` 作者面板；`scripts/weapons/shapes/` 武器形状族模块；`scripts/weapons/handlers/` 攻击行为静态模块（Melee/Sweep/Projectile/Burst/Turret/Channel + 共用 StrikeFx，首参传宿主武器、鸭类型访问，行为常量随实现走）；`scripts/entities/player_skills/` 技能实现（ActiveSkills 主动五连 / BurstSkills 周身爆发四件套）；`scripts/entities/enemy_death/` 死亡解析（EnemyDeathFx 的 feedback/drops/corpse）；`scripts/entities/procedural_cultivator/` `procedural_enemy/` `procedural_loot/` 程序化渲染族；`scripts/systems/Balance*.gd` 数值公式；`scripts/autoload/StatSystem.gd` 属性落地与读侧投影（item_hook_sum / 属性字典）；`tests/unit/` 单测主题模块（wave/combat/economy/upgrade/targeting/content/infra/consistency/spiritbeast/spiritpet/flock 共 11 个）。
- `CHANGELOG.md` 为追加式，正常往上加即可，冲突面小。

## 变更日志（每次改代码必读必写）

改完追加写入 [CHANGELOG.md](CHANGELOG.md)（已纳入版本控制，2026-10-24 起，333 条根因记录是排查知识库）。**格式 `## YYYY-MM-DD #序号`**（如 `## 2026-10-09 #01`），序号当日从 01 起、**不记时间点**、**新的在上面**。每条一句话概述改了什么 + 关键文件路径；**只记对排查问题有用的根因、陷阱与架构变动**——Bug 用 `Fixed:` 标出根因，新系统/重构点出涉及文件。**不记**：逐项 `Added`/`Changed`/`Verified` 标签流水账、测试项数与 exit 状态明细、selftest 细节、用户原话、设计推导、临时出图路径。无论是否提交都要记。

## 必须知道的坑

1. **Godot 编辑器 GUI 对自动化封闭** — 走 CLI + 文件直改。
2. **ZCode 内置浏览器跑不了 Godot** — 用真机或编辑器预览。
3. **Bash curl 走系统代理** — 访问 localhost 加 `--noproxy '*'`。
4. **中文 autowrap 真机不可靠** — 必须 `GameStyle.wrap_cjk()` 切硬换行。
5. **新增 class_name 或素材后先跑编辑器扫描** — `$G --headless --path . --editor --quit`，否则类名/资源解析不到。
6. **震屏只给特殊场景** — 普通命中不加创伤，同一次挨打只许一处发反馈。
7. **范围视觉与判定同源** — 画多大 == 判多大，别用辉光糊大。
8. **APK 文件名写死 v0.0.1 是正常的** — 实际版本由 `Version.gd` + `release.py` 处理。
9. **WebFetch 工具在本环境不可用** — 需要抓网页时改用 `curl`（访问 localhost 加 `--noproxy '*'`）配合 `python3` 解析。
10. **滚动条改不动 stylebox，只吃 `modulate`** — Godot 4.7 的 `ScrollBar` 无视 `scroll_grabber` / `scroll_background`；统一走 `GameStyle.scrollable()`。
11. **滚动区里的槽位别用 `Button`** — `BaseButton` 会吞按下事件导致划不动整排；可滚动槽位统一用 `PanelContainer + GameStyle.tap()`。
12. **武器/弹丸脚本严禁硬引用 `EnemyBase`** — 在 `FloatingWeapon`/`BladeProjectile`/`TurretUnit` 里写 `as EnemyBase` 或类型化调用会触发循环类依赖，把 `preload(BladeProjectile.tscn)` 打成空 PackedScene（弹丸静默 null，测试只报泛化错误不报错因）。本仓武器侧遍地 `has_method` 鸭类型就是在躲这条，新增判定照抄。
13. **池化实体出树休眠时保持三件套同拍** — 在树、`GameManager.live_*` 登记表、碰撞组（如 "enemies"）必须同时进同时出，池体一样都不许占，否则回合末清场/索敌会摸到休眠体；出厂字段快照要在 instantiate 当刻拍（`_scale_to_wave`/变异会原地改导出字段），复用整备以「是否装配过」为闸（新实例 @onready 还是 null）。
14. **Godot headless 遇 Parse Error 不退出与后台任务止损铁律** — 
    - **无头死锁根因**：Godot `--headless` 依赖脚本显式 `get_tree().quit()`。若遇到未声明类名、语法解析错误或资源缺失，引擎会抛错但主循环不会退出，而是在后台无限空转（nanosleep）。严禁在缺少 `.godot/imported` 缓存的裸目录（如 git worktree）直接跑测试；跑测试一律优先使用自带看门狗的 `python3 tools/run_test.py`。
    - **严禁对后台任务连续调用 `TaskOutput(block=true)` 死等**：当命令进入后台执行时，若单次等待超时（30s）或无有效进展，**严禁再次重复阻塞等待**！必须立即调用 `TaskStop` 终止卡死任务，并用 `ps aux | grep Godot` 排查。优先通过 `Read` 查看 output-file，绝不允许原地轮询等待十几分钟。
15. **成段演出随机禁碰 `GameManager.rng`** — 破匣/爆散等演出段的随机若用玩法 RNG，会挪动后续掉落/伤害随机序列，判据钉不住；用本地 `RandomNumberGenerator` 以 `instance_id` 播种（样板 `scripts/entities/ChestBurstFx.gd`）。
16. **外移实现的静态模块（weapons/handlers / entities/player_skills / enemy_death）首参一律传宿主且不标类型** —— 模块里 `as EnemyBase`/`as FloatingWeapon` 这类硬类型引用会构成循环类依赖（同坑 12 机制）；宿主常量经无类型实例访问（`e.KILL_PITCH_ELITE_MULT`），别写类名前缀。另：无类型参数上的 `:=` 类型推断必炸（`Cannot infer the type`），搬移时含宿主成员的声明改显式 `: 类型 =`。
17. **HUD 键位提示的平台判定口径** — `mobile/android/ios` 任一命中即视为触屏藏键位；网页里的手机浏览器必须再查 `web_android`/`web_ios`（浏览器内不声明 android/ios，光查它们会漏手机网页），见 `SkillButtonView.key_hint_enabled()`。
