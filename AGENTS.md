# AGENTS.md — 修仙幸存者

> 写给后续开发（人或 AI 协作者）的入场须知。保持简洁，读完即可上手。

## 项目简介

- **游戏类型**：类「土豆兄弟（Brotato）」的俯视角自动攻击幸存者（Survivors-like），修仙题材包装。
- **引擎**：Godot 4.7（Forward+），GDScript，主场景 `res://scenes/main/Main.tscn`。
- **目标平台**：Android（已有 export_presets 与 keystore），桌面调试 960×540 视口（窗口 1280×720）。
- **当前状态**：**雏形阶段**。核心循环已跑通（选人 → 选武器 → 20 波战斗 → 波间商店 → 胜负结算），数值、内容、表现都会大改，不要为现状写死假设。
- **核心循环**：玩家移动躲避敌潮，武器自动攻击 → 击杀掉灵石/经验 → 升级三选一 → 波间商店买装备/合成武器 → 撑过第 20 波（`GameManager.VICTORY_WAVE`）获胜。

## 目录结构

| 路径 | 内容 |
|---|---|
| `scenes/main` `scripts/main` | 主场景入口 |
| `scenes/entities` `scripts/entities` | 玩家、敌人基类（`EnemyBase.gd`）与各敌种（史莱姆/丹宝/花妖/雷兽/邪修/石人）、灵石、回血球、灵草 |
| `scenes/weapons` `scripts/weapons` | 武器实体：浮游环绕武器、刃气弹道、日轮、雷击 |
| `scenes/ui` `scripts/ui` | 全部 UI：HUD、开始菜单、选人、选武器、升级、商店、暂停、结算、更新弹窗、虚拟摇杆 |
| `scripts/autoload` | 单例：`GameManager`（全局状态中枢：经济/属性/武器/波次/商店）、`AudioManager`、`UpdateManager`、`Version`；另有数据表 `UpgradeData.gd` |
| `scripts/systems` | 系统层：`WaveSpawner`（刷怪）、`WeaponData`/`CultivatorData`（数据表）、`DamageNumber`、`JuiceEffect`（打击感）、`RunMotion`、`BlessingObelisk`（界碑/边界） |
| `scripts/controllers` | `SmoothCamera`、`VirtualJoystick` |
| `assets/` | 运行时资源：`art/`（PNG 图集切片）、`audio/`（BGM + `sfx/`）、`shaders/`（hit_flash、sunbeams、vignette）、`fonts/`、`brand/` |
| `assets_raw/` | **源素材**（AI 生成的 jpg/png 原图 + `manifest.jsonl` 记录 + `music/`、`voice/`、`style/`），不进包体 |
| `tools/` | Python 工具链：图集切片（`make_spritesheet.py`、atlas 打包）、品牌资源生成 |
| `tests/` | 冒烟测试场景（`SmokeRunner`）与更新反馈测试 |
| `build/`、`keystore/` | APK 产物与签名 |

## 开发约定

**代码风格**
- 全部 GDScript，缩进 Tab（Godot 默认），静态类型标注（`var x: float`、`func f() -> void`）。
- 注释用中文，关键常量/字段写 `##` 文档注释（现有代码风格即标准，照着写）。
- 信号驱动解耦：全局状态一律走 `GameManager` 的 signal，UI/实体只监听不直接改对方；实体间不互相引用，通过组（group）或 GameManager 中转。
- 数值是资源/常量，不写魔法数字：属性上限放 `GameManager` 顶部常量区（如 `DODGE_CAP`），武器/角色/升级数据放 `scripts/systems/*Data.gd` 与 `UpgradeData.gd` 数据表。
- 新增可生成实体：场景放 `scenes/entities/`，脚本放 `scripts/entities/`，由 `WaveSpawner` 注册；敌人继承 `EnemyBase`。

**场景与节点**
- `.tscn` 与 `.gd` 同名配对，目录镜像（`scenes/x` ↔ `scripts/x`）。
- 物理分层已定义（1 world / 2 player / 3 enemies / 4 player_projectiles / 5 loot / 6 interactables），新增碰撞体必须按层设置，不改全局层定义。
- 像素对齐已开启（snap 2d transforms/vertices），纹理过滤为 Nearest，素材按像素画规格制作。

**验证**
- 改完跑冒烟测试 `tests/SmokeRunner.tscn`；涉及更新逻辑跑 `TestUpdateFeedback`。
- 导出前确认 `export_presets.cfg` 与 keystore 路径未失效。

## UI 规范（P5 大色块风格）

统一入口是 **`scripts/ui/GameStyle.gd`——所有 UI 样式必须从它取色、取字体、取斜率，禁止散落硬编码**。设计语言（源自 Persona 5 式大色块，移植自 dudu-cocos 的斜切语言）：

- **无圆角、无渐变、无柔光**；面板/按钮是**斜切平行四边形**，四档斜率：`SLANT_PLATE 3 / SLANT_BLOCK 5 / SLANT_BUTTON 6 / SLANT_BAND 10`。
- **硬错位投影 + 同色压暗厚底边**（`*_DK` 色做底边/阴影），营造剪纸式立体感。
- 配色：深蓝底（`INK/NAVY/NAVY2/LINE`）+ 纸白文字（`PAPER`）+ **主蓝**（`BLUE`，主行动）+ **点缀黄**（`YELLOW`，货币/选中/星级）+ 绿（增益）/红（危险）语义色。
- 字体：正文 `MiSans-Semibold`（微加粗 0.12），大标题 `MiSans-Heavy`，经 `GameStyle.body_font()/display_font()` 获取。
- 新 UI 面板先看 `GameHUD`/`WaveShop`/`LevelUpDialog` 的现有用法，复用 GameStyle 的绘制函数。

## 素材生成规范

- **流程**：AI 生成原图 → 存 `assets_raw/images/`（含 `.raw.jpg` 原件与处理后 png）→ `tools/` 切片/打包 → 输出到 `assets/art/` → Godot 内引用。**`assets_raw` 是源，`assets` 是产物，勿直接改产物。**
- `assets_raw/manifest.jsonl` 记录每批生成素材的来源与 prompt，新增素材要补记录。
- 风格：像素风 sprite（角色为 8 方向行走图，命名 `xxx_8dir.png`），色块干净、轮廓清晰、高对比，与 UI 的蓝白黄大色块基调协调；透明底 PNG，Nearest 过滤。
- 角色图集统一 192 帧规格（参考 `cultivator_sheet_192.png`），用 `make_spritesheet.py` 切片。
- 音频：BGM 放 `assets/audio/`，短音效放 `assets/audio/sfx/`（ogg），由 `AudioManager` 统一播放，不在场景里各自加载。
- 图标类素材需成对提供浅色描边版以便压暗厚底边处理。

## 设计基调（模仿土豆兄弟）

- 波次制 + 波间商店，局内成长为主：升级三选一（`UpgradeData`）、多武器槽与武器合成（`GameManager` 管理）、属性加点有上限防失控。
- 单局短平快（20 波），重可复玩性：多角色（`CultivatorData`）× 多武器（`WeaponData`）组合。
- 打击感优先：受击闪白（`hit_flash` shader）、伤害数字、屏幕震动等 Juice 统一走 `JuiceEffect.gd`，新增反馈别另起炉灶。
- 雏形阶段原则：**先验证玩法再堆内容**；改数值优先改数据表，改结构前先更新本文档。
