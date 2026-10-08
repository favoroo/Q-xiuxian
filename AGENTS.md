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
| `scenes/main`、`scripts/main` | 主场景入口 |
| `scenes/entities`、`scripts/entities` | 玩家、敌人基类（`EnemyBase.gd`）与各敌种（史莱姆/丹宝/花妖/雷兽/邪修/石人）、Boss（`BossEnemy.gd`：第 10/20 波固定魔君，特殊攻击+二阶段，HUD 血条）、灵石、回血球、灵草 |
| `scenes/weapons`、`scripts/weapons` | 武器实体：浮游环绕武器、刃气弹道、日轮、雷击 |
| `scenes/ui`、`scripts/ui` | 全部 UI：HUD、开始菜单、选人、选武器、升级、商店、暂停、结算、更新弹窗、虚拟摇杆 |
| `scripts/autoload` | 单例：`GameManager`（全局状态中枢：经济/属性/武器/波次/商店）、`AudioManager`、`UpdateManager`、`Version`；另有 `UpgradeData.gd`（升级三选一数据表，放此处的原因此后改动频繁且需全局访问，详见下文） |
| `scripts/systems` | 系统层与数据表：`WaveSpawner`（刷怪）、`WeaponData`/`CultivatorData`（武器/角色数据表）、**`GameBalance.gd`（数值公式，全 static 纯函数）**、`DamageNumber`、`JuiceEffect`（打击感，两者均带对象池）、`RunMotion`、`BlessingObelisk`（界碑/边界） |
| `scripts/controllers` | `SmoothCamera`、`VirtualJoystick` |
| `assets/` | 运行时资源：`art/`（PNG 图集切片）、`audio/`（3 段 BGM：battle/shop/trial + `sfx/` 短音效 **wav** + `default_bus_layout.tres` 总线）、`shaders/`（hit_flash、sunbeams、vignette）、`fonts/`、`brand/` |
| `assets_raw/` | **源素材**（不进包体）：`images/`（AI 生成 jpg/png 原图，含 `.raw.jpg` 与处理后 png）、`sfx/`（`bake_sfx.py` 烘出的 wav 原件）、`manifest.jsonl`（来源与 prompt 记录）、`music/`、`voice/`、`style/` |
| `tools/` | Python 工具链：图集切片（`make_spritesheet.py`、atlas 打包）、品牌资源生成、**音效烘焙（`bake_sfx.py`）** |
| `tests/` | 五个 headless 场景，共用 `tests/check.gd`（`TestCheck` 断言 helper，输出 `[PASS]/[FAIL]` + `*_RESULT` + 退出码）：`SmokeRunner`（全流程冒烟）、`UnitRunner`（数值单测，不加载场景）、`PoolCheck`（帧缓存与对象池）、`ToastCheck`（更新浮层摆位，带 `-- --selftest` 反例）、`AudioGallery`（音效试听台，需要真实出声，勿加 `--headless`） |
| `build/`、`keystore/` | APK 产物与签名 |

## 开发约定

**代码风格**
- 全部 GDScript，缩进 Tab（Godot 默认），静态类型标注（`var x: float`、`func f() -> void`）。
- 注释用中文，关键常量/字段写 `##` 文档注释（现有代码风格即标准，照着写）。
- 信号驱动解耦：全局状态一律走 `GameManager` 的 signal，UI/实体只监听不直接改对方；实体间不互相引用，通过组（group）或 GameManager 中转。
- 数值是资源/常量，不写魔法数字：属性上限放 `GameManager` 顶部常量区（如 `DODGE_CAP`）；武器/角色数据放 `scripts/systems/WeaponData.gd`/`CultivatorData.gd`；升级三选一数据放 `scripts/autoload/UpgradeData.gd`（与其它 `*Data.gd` 分开，因其升级表需在局内被多处 autoload 直接读取，故单独放 autoload）。
- **公式放 `GameBalance.gd`**：经验曲线、护甲减伤、波次缩放、商店定价、灵韵复利、稀有度权重、羁绊档位、权重抽奖都在那里，全部 `static` 纯函数——不读 autoload、不碰节点、不调全局 `randf()`。要随机就把 `GameManager.rng` 或已抽好的 roll 传进去，这样单测能固定种子复现。玩法相关的随机一律走 `GameManager.rng`，不要用全局 `randf()`（否则测试钉不住结果，`Array.pick_random()` 同理，用 `GameManager.rng_pick()`）。
- 升级项的**生效幅度写在 `UpgradeData` 每项的 `"apply"` 字典里**（字段白名单见 `GameBalance.upgrade_fields()`），文案里的 +8%/+25 与它同源；`GameManager.apply_upgrade()` 只负责「往哪个字段加、上限怎么夹」，不再重复写数字。
- 新增可生成实体：场景放 `scenes/entities/`，脚本放 `scripts/entities/`，由 `WaveSpawner` 注册；敌人继承 `EnemyBase`。

**场景与节点**
- `.tscn` 与 `.gd` 同名配对，目录镜像（`scenes/x` ↔ `scripts/x`）。
- 物理分层已定义（1 world / 2 player / 3 enemies / 4 player_projectiles / 5 loot / 6 interactables），新增碰撞体必须按层设置，1–6 勿改；如有新用途，从第 7 层起新增并在此处补记。
- 像素对齐已开启（snap 2d transforms/vertices），纹理过滤为 Nearest，素材按像素画规格制作。

**验证**
- 改完跑三条 headless 命令（`G=/Applications/Godot.app/Contents/MacOS/Godot`），三条全绿才算完成；判据都由 `tests/check.gd`（`TestCheck`）输出 `[PASS]/[FAIL]` + `*_RESULT` + 退出码：
  ```bash
  $G --headless --path . res://tests/UnitRunner.tscn   # 数值单测（不加载场景）
  $G --headless --path . res://tests/PoolCheck.tscn    # 帧缓存 / 对象池
  $G --headless --path . res://tests/SmokeRunner.tscn  # 全流程冒烟（选人→战斗→升级→商店→结算→UI）
  ```
  退出码 0 且末行 `*_RESULT: ALL PASS`。试听音效用 `AudioGallery.tscn`（要真实出声，别加 `--headless`）。
- **新增 `class_name` 脚本或新素材后，先跑一次编辑器扫描再跑测试**，否则全局类名解析不到（`Could not resolve class ...`）、新资源不算已导入（`未注册的音效 key`）：`$G --headless --path . --editor --quit`。
- 涉及应用内更新逻辑（`UpdateManager`）的改动：浮层（Toast）摆位有判据 `tests/ToastCheck.tscn`（文案 × 屏宽逐档量 rect：不出屏/居中/装得下，`-- --selftest` 验判据有牙齿）；下载与安装链路仍无自动化，需在真机或编辑器内手动走一次"检测 → 下载 → 重启"确认。
- 导出前确认 `export_presets.cfg` 与 keystore 路径未失效。

## UI 规范（P5 大色块风格）

统一入口是 **`scripts/ui/GameStyle.gd`——所有 UI 样式必须从它取色、取字体、取斜率，禁止散落硬编码**。设计语言（源自 Persona 5 式大色块，移植自 dudu-cocos 的斜切语言）：

- **无圆角、无渐变、无柔光**；面板/按钮是**斜切平行四边形**，四档斜率：`SLANT_PLATE 3 / SLANT_BLOCK 5 / SLANT_BUTTON 6 / SLANT_BAND 10`。
- **硬错位投影 + 同色压暗厚底边**（`*_DK` 色做底边/阴影），营造剪纸式立体感。
- 配色：深蓝底（`INK/NAVY/NAVY2/LINE`）+ 纸白文字（`PAPER`）+ **主蓝**（`BLUE`，主行动）+ **点缀黄**（`YELLOW`，货币/选中/星级）+ 绿（增益）/红（危险）语义色。
- 字体：正文 `MiSans-Semibold`（微加粗 0.12），大标题 `MiSans-Heavy`，经 `GameStyle.body_font()/display_font()` 获取。
- 新 UI 面板先看 `GameHUD`/`WaveShop`/`LevelUpDialog` 的现有用法，复用 GameStyle 的绘制函数。
- **按钮点击音在 `GameStyle.button()` 里统一挂**（样式入口即反馈入口，靠 `sfx_wired` meta 防重复连接），各界面不要再自己写 `play_sfx("ui_click")`。反馈要跟着结果走：动作没成就播 `ui_error`，别在按下那一刻就先播成功音。

## 素材生成规范

- **流程**：AI 生成原图 → 存 `assets_raw/images/`（含 `.raw.jpg` 原件与处理后 png）→ `tools/` 切片/打包 → 输出到 `assets/art/` → Godot 内引用。**`assets_raw` 是源，`assets` 是产物，勿直接改产物。**
- `assets_raw/manifest.jsonl` 记录每批生成素材的来源与 prompt，新增素材要补记录。
- 风格：像素风 sprite（角色为 8 方向行走图，命名 `xxx_8dir.png`），色块干净、轮廓清晰、高对比，与 UI 的蓝白黄大色块基调协调；透明底 PNG，Nearest 过滤。
- 角色图集统一 192 帧规格（参考 `assets_raw/images/cultivator_sheet_192.png`），用 `tools/make_spritesheet.py` 切片后输出到 `assets/art/` 再由 Godot 引用。
- 音频分两条路，别混：**短音效本地烘焙，BGM/语音才用 media-gen**。
  - 音效：`python3 tools/bake_sfx.py`（纯标准库离线合成，移植自 dudu-cocos 的 `bake-audio.ts`：振荡器+指数包络+RBJ 双二阶+白噪声，固定种子可复现）→ wav 原件进 `assets_raw/sfx/`，产物进 `assets/audio/sfx/<key>_<n>.wav`。media-gen 的能力边界表写明 **不含 SFX**，别拿它生成音效。加完 key 要把脚本末尾打印的 `_register_sfx(...)` 行粘进 `AudioManager._load_audio_assets()`，并跑一次编辑器导入 + `UnitRunner`（它断言注册表与素材不漂移）。
  - BGM：`assets_raw/music/` 里的 lyria 产物约 4 MB/首，**必须重编码再入库**（APK 已经很紧）：`ffmpeg -i in.mp3 -ac 1 -ar 44100 -b:a 128k assets/audio/bgm_x.mp3`。用 CBR（`-b:a`）而不是 `-q:a`，VBR 会让 `AudioStreamMP3.loop` 循环不齐。
  - 播放一律走 `AudioManager`，不在场景里各自 `load()`。总线分 Master/BGM/SFX/Voice，玩家音量在 `PauseMenu` 调、落盘 `user://audio.cfg`。BGM 用 `play_bgm_key("battle"|"shop"|"trial")` 状态机切换（带交叉淡化），不要直接 `play_bgm(stream)`。
- 图标类素材需成对提供浅色描边版以便压暗厚底边处理。

## 设计基调（模仿土豆兄弟）

- 波次制 + 波间商店，局内成长为主：升级三选一（`UpgradeData`）、多武器槽与武器合成（`GameManager` 管理）、属性加点有上限防失控。
- 单局短平快（20 波），重可复玩性：多角色（`CultivatorData`）× 多武器（`WeaponData`）组合。
- 打击感优先：受击闪白（`hit_flash` shader）、伤害数字、屏幕震动等 Juice 统一走 `JuiceEffect.gd`，新增反馈别另起炉灶。
- 雏形阶段原则：**先验证玩法再堆内容**；改数值优先改数据表，改结构前先更新本文档。
