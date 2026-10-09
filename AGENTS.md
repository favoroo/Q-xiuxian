# AGENTS.md — 修仙幸存者开发指南

> 供 AI 开发 Agent 阅读。判据细节写在脚本文件头注释与 `tests/*.gd` 文件头，不在此抄录。

## 项目简介

类「土豆兄弟（Brotato）」俯视角自动攻击幸存者，修仙题材包装。

- **引擎** Godot 4.7（Forward+）/ GDScript，主场景 `res://scenes/main/Main.tscn`
- **平台** Android APK（`export_presets.cfg` arm64-v8a，包名 `com.favo.qxiuxian`），桌面调试 960×540
- **版本** 见 [Version.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/Version.gd)，远端 GitHub `favoroo/Q-xiuxian` + Gitee `favo9/q-xiuxian`
- **物理** Jolt，6 层碰撞层（1 world / 2 player / 3 enemies / 4 player_projectiles / 5 loot / 6 interactables），勿改
- **核心循环** 选人 → 选武器 → 20 波战斗（`GameManager.VICTORY_WAVE`）→ 波后统一悟道加点（一屏 `UPGRADE_OFFER_COUNT`=5 个候选、每回合 1 次免费刷新）→ 波间灵石阁（`SHOP_BASE_SLOTS`=5 格）→ 胜负结算

## 快速定位

| 要做什么 | 去哪里看 |
|---------|---------|
| 调数值/公式 | [GameBalance.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/GameBalance.gd)（全 `static` 纯函数） |
| 调全局状态/上限常量 | [GameManager.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/GameManager.gd) 顶部常量区 |
| 调悟道加点表 | [UpgradeData.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/UpgradeData.gd)（`"apply"` 字典是生效幅度唯一真话） |
| 改波后加点/商店节奏 | [WaveSpawner.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/WaveSpawner.gd) `_enter_wave_break` + [LevelUpDialog.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/LevelUpDialog.gd) |
| 改武器/角色/法宝数据表 | [WeaponData](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/WeaponData.gd) / [CultivatorData](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/CultivatorData.gd) / [ItemData](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/ItemData.gd) |
| 改刷怪/波次配比 | [WaveSpawner.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/WaveSpawner.gd) |
| 改敌人/Boss | [EnemyBase.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/EnemyBase.gd) / [BossEnemy.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/entities/BossEnemy.gd) |
| 改弹丸追踪 | [BladeProjectile.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/weapons/BladeProjectile.gd) |
| 改打击感/震屏 | [JuiceEffect.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/systems/JuiceEffect.gd) + GameBalance 镜头创伤段 + [SmoothCamera.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/controllers/SmoothCamera.gd) |
| 改 UI 样式/配色/字体 | [GameStyle.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/ui/GameStyle.gd)（**唯一取色入口**） |
| 改音效/BGM | [AudioManager.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/AudioManager.gd) |
| 改应用内更新 | [UpdateManager.gd](file:///Users/a1/Documents/01Code/Godot/t-1/scripts/autoload/UpdateManager.gd) |
| 烘焙音效 | [tools/bake_sfx.py](file:///Users/a1/Documents/01Code/Godot/t-1/tools/bake_sfx.py)（media-gen 不含 SFX） |
| 子集化字体 | [tools/subset_fonts.py](file:///Users/a1/Documents/01Code/Godot/t-1/tools/subset_fonts.py) + `font_charset.txt` |
| 生成美术/语音/BGM | [.agents/skills/media-gen/](file:///Users/a1/Documents/01Code/Godot/t-1/.agents/skills/media-gen/SKILL.md) |
| 查历史改动 | [CHANGELOG.md](CHANGELOG.md)（仅本地） |
| 发版/打 APK | [.agents/skills/xiuxian-release/](file:///Users/a1/Documents/01Code/Godot/t-1/.agents/skills/xiuxian-release/SKILL.md) |

## 分层铁律

1. **数值只进数据表/常量区**，不写魔法数字。
2. **`GameBalance.gd` 全 `static` 纯函数** — 不读 autoload、不碰节点、不调全局 `randf()`。
3. **玩法随机走 `GameManager.rng`** — 不用全局 `randf()`/`pick_random()`，否则测试钉不住。
4. **信号驱动解耦** — 全局状态走 `GameManager` signal，实体间不互引。
5. **`.tscn` 与 `.gd` 同名配对**，目录镜像（`scenes/x` ↔ `scripts/x`）。
6. **渲染层只读状态** — 范围视觉与判定同源。

## 开发规范

- GDScript Tab 缩进，静态类型标注，注释中文，关键常量写 `##` 文档注释。
- **严禁自动 `git commit`/`push`** — 只有用户明确指示才执行。
- 新增 `class_name` 脚本或新素材后先跑编辑器扫描，否则类名解析不到、新资源不算已导入：
  ```bash
  $G --headless --path . --editor --quit
  ```
- 升级项生效幅度在 `UpgradeData` 的 `"apply"` 字典，文案数字与它同源；法宝与升级共用同一条属性链路。
- 像素对齐已开（`snap_2d_vertices` + Nearest 过滤）。

## UI 规范

统一入口 **`GameStyle.gd`**（取色/取字体/取斜率，禁止散落硬编码）：

- 无圆角无渐变无柔光，斜切平行四边形，四档斜率 `PLATE 3 / BLOCK 5 / BUTTON 6 / BAND 10`。
- 配色：深蓝底 + 纸白 + 主蓝（行动）+ 点缀黄（货币/选中）。字体 `MiSans-Semibold`/`MiSans-Heavy`。
- 按钮 sfx 在 `GameStyle.button()` 统一挂。
- **「这是什么」点按可得**（`DetailTip`），别用 `tooltip_text`（Android 无 hover）。
- **中文长句用 `GameStyle.wrap_cjk()` 切硬换行** — 引擎 `AUTOWRAP_WORD` 在中文真机上不可靠。
- 卡片不按死宽度摆，按 viewport 现算。

## 素材管线

- AI 生成 → `assets_raw/images/` → `tools/` 切片 → `assets/art/` → Godot 引用。`assets_raw` 是源，`assets` 是产物，勿直接改产物。
- `assets_raw/manifest.jsonl` 记录来源与 prompt，新增素材要补记。
- 音效走 `bake_sfx.py`，BGM/语音才用 media-gen。BGM 入包前 `ffmpeg -b:a 128k` CBR 重编码。
- 加完音效 key 要把脚本打印的 `_register_sfx(...)` 粘进 `AudioManager._load_audio_assets()`，再跑编辑器导入 + `UnitRunner`。
- 改了 UI 文案后重跑 `subset_fonts.py` + `FontCoverageCheck`。

## 回归测试

`G=/Applications/Godot.app/Contents/MacOS/Godot`。判据场景 headless，退出码 0 且 `*_RESULT: ALL PASS`：

```bash
$G --headless --path . res://tests/UnitRunner.tscn       # 数值单测
$G --headless --path . res://tests/PoolCheck.tscn        # 帧缓存/对象池
$G --headless --path . res://tests/SmokeRunner.tscn      # 全流程冒烟
$G --headless --path . res://tests/StatsTipCheck.tscn    # 属性面板点按（带 -- --selftest）
$G --headless --path . res://tests/KnockProbe.tscn       # 震退方向
$G --headless --path . res://tests/LayoutCheck.tscn      # UI 摆位（带 -- --selftest）
$G --headless --path . res://tests/ProjectileProbe.tscn  # 弹丸命中（带 -- --no-homing）
$G --headless --path . res://tests/FontCoverageCheck.tscn # 字体子集覆盖
$G --headless --path . res://tests/WolfAiCheck.tscn       # AI 行为
```

非判据现场工具（要真实出声/出图，别加 `--headless`）：`AudioGallery` / `BoltPreview` / `BulletPreview` / `ShakeProbe`。

## 变更日志（每次改代码必读必写）

改完追加写入 [CHANGELOG.md](CHANGELOG.md)（gitignored，仅本地）。**格式 `## YYYY-MM-DD #序号`**（如 `## 2026-10-09 #01`），序号当日从 01 起、**不记时间点**、**新的在上面**。头一句话概述，子项用 `Added`/`Changed`/`Fixed`/`Removed`/`Verified` + 文件路径。每子项一句话。未提交也要记。

## 必须知道的坑

1. **Godot 编辑器 GUI 对自动化封闭** — 走 CLI + 文件直改。
2. **ZCode 内置浏览器跑不了 Godot** — 用真机或编辑器预览。
3. **Bash curl 走系统代理** — 访问 localhost 加 `--noproxy '*'`。
4. **中文 autowrap 真机不可靠** — 必须 `GameStyle.wrap_cjk()` 切硬换行。
5. **新增 class_name 或素材后先跑编辑器扫描** — `$G --headless --path . --editor --quit`，否则类名/资源解析不到。
6. **震屏只给特殊场景** — 普通命中不加创伤，同一次挨打只许一处发反馈。
7. **范围视觉与判定同源** — 画多大 == 判多大，别用辉光糊大。
8. **APK 文件名写死 v0.0.1 是正常的** — 实际版本由 `Version.gd` + `release.py` 处理。
9. **WebFetch 工具在本环境不可用** — 辅助小模型的 reasoning effort 配置冲突会导致调用报错；需要抓网页时改用 `curl`（访问 localhost 加 `--noproxy '*'`），再用 `python3` 解析 HTML。
