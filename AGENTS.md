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
| `scenes/entities`、`scripts/entities` | 玩家、敌人基类（`EnemyBase.gd`）与各敌种（史莱姆/丹宝/花妖/雷兽/邪修/石人 + 批三新增：蜂群精/血蛹/鼓妖/影魅/蛛母，精英池轮换 石人→赤雷兽→剑煞邪修）、Boss（`BossEnemy.gd`：第 10/20 波固定魔君，特殊攻击+二阶段，HUD 血条）、灵石、回血球、灵草 |
| `scenes/weapons`、`scripts/weapons` | 武器实体：浮游环绕武器、刃气弹道、日轮、雷击 |
| `scenes/ui`、`scripts/ui` | 全部 UI：HUD、开始菜单、选人、选武器、升级、商店、暂停、结算、更新弹窗、虚拟摇杆 |
| `scripts/autoload` | 单例：`GameManager`（全局状态中枢：经济/属性/武器/波次/商店）、`AudioManager`、`UpdateManager`、`Version`；另有 `UpgradeData.gd`（升级三选一数据表，放此处的原因此后改动频繁且需全局访问，详见下文） |
| `scripts/systems` | 系统层与数据表：`WaveSpawner`（刷怪）、`WeaponData`/`CultivatorData`（武器/角色数据表）、`ItemData`（法宝=被动道具数据表）、**`GameBalance.gd`（数值公式，全 static 纯函数）**、`DamageNumber`、`JuiceEffect`（打击感，两者均带对象池）、`RunMotion`、`BlessingObelisk`（界碑/边界） |
| `scripts/controllers` | `SmoothCamera`、`VirtualJoystick` |
| `assets/` | 运行时资源：`art/`（PNG 图集切片）、`audio/`（3 段 BGM：battle/shop/trial + `sfx/` 短音效 **wav** + `default_bus_layout.tres` 总线）、`shaders/`（hit_flash、sunbeams、vignette）、`fonts/`、`brand/` |
| `assets_raw/` | **源素材**（不进包体）：`images/`（AI 生成 jpg/png 原图，含 `.raw.jpg` 与处理后 png）、`sfx/`（`bake_sfx.py` 烘出的 wav 原件）、`manifest.jsonl`（来源与 prompt 记录）、`music/`、`voice/`、`style/` |
| `tools/` | Python 工具链：图集切片（`make_spritesheet.py`）、8 方向行走图拼装（`build_run8_atlas.py`，CHARS 注册角色/妖种后 `python3 tools/build_run8_atlas.py <char>...`，联系人表出图到 /tmp 供肉眼复查）、品牌资源生成、**音效烘焙（`bake_sfx.py`）** |
| `tests/` | 九个 headless 判据场景，共用 `tests/check.gd`（`TestCheck` 断言 helper，输出 `[PASS]/[FAIL]` + `*_RESULT` + 退出码）：`SmokeRunner`（全流程冒烟）、`UnitRunner`（数值单测，不加载场景）、`PoolCheck`（帧缓存与对象池）、`ToastCheck`（更新浮层摆位，带 `-- --selftest` 反例）、`StatsTipCheck`（属性面板点按详解：文案表自洽 + 逐个热区真发一次左键松开看弹不弹得出卡 + 卡与面板逐档屏宽不出屏，带 `-- --selftest` 八份反例）、`KnockProbe`（震退方向活体判据：真跑一局番天镇岳印，逐帧查每个敌人的震退速度方向永不指向玩家，并把新旧两条方向规则在同一批真实落点几何上对照计数）、`LayoutCheck`（UI 摆位：十块面板 × 三档屏宽，量「不出屏 + 每一行文字装得下」，顶栏灌最宽读数与五枚徽记的最坏样本，带 `-- --selftest` 十三份反例）、`ProjectileProbe`（弹丸命中兑现活体判据：A 段清场只留一个真敌人绕玩家 300px 匀速横切，量「打出去的真结到那一个没有」——牙齿在这段，尸潮太密时直线弹乱飞也蹭得到人、关追踪仍有 98.3%，所以 B 段只作灾难兜底与距离档读数，带 `-- --no-homing` 反例）；另有两个**非判据**的现场工具：`AudioGallery`（音效试听台，需要真实出声，勿加 `--headless`）、`BoltPreview`（敌方火球出图台，同上，存 PNG 后自退） |
| `build/`、`keystore/` | APK 产物与签名 |

## 开发约定

**代码风格**
- 全部 GDScript，缩进 Tab（Godot 默认），静态类型标注（`var x: float`、`func f() -> void`）。
- 注释用中文，关键常量/字段写 `##` 文档注释（现有代码风格即标准，照着写）。
- 信号驱动解耦：全局状态一律走 `GameManager` 的 signal，UI/实体只监听不直接改对方；实体间不互相引用，通过组（group）或 GameManager 中转。
- 数值是资源/常量，不写魔法数字：属性上限放 `GameManager` 顶部常量区（如 `DODGE_CAP`）；武器/角色数据放 `scripts/systems/WeaponData.gd`/`CultivatorData.gd`；升级三选一数据放 `scripts/autoload/UpgradeData.gd`（与其它 `*Data.gd` 分开，因其升级表需在局内被多处 autoload 直接读取，故单独放 autoload）。
- **公式放 `GameBalance.gd`**：经验曲线、护甲减伤、波次缩放、商店定价、灵韵复利、稀有度权重、羁绊档位、权重抽奖都在那里，全部 `static` 纯函数——不读 autoload、不碰节点、不调全局 `randf()`。要随机就把 `GameManager.rng` 或已抽好的 roll 传进去，这样单测能固定种子复现。玩法相关的随机一律走 `GameManager.rng`，不要用全局 `randf()`（否则测试钉不住结果，`Array.pick_random()` 同理，用 `GameManager.rng_pick()`）。
- 升级项的**生效幅度写在 `UpgradeData` 每项的 `"apply"` 字典里**（字段白名单见 `GameBalance.upgrade_fields()`），文案里的 +8%/+25 与它同源；`GameManager.apply_upgrade()` 只负责「往哪个字段加、上限怎么夹」，不再重复写数字。
- **法宝（被动道具）系统**（仿土豆兄弟 Items）：数据表在 `ItemData.gd`（tier 1~4 档位定价格/权重/解锁波次），与升级三选一**共用同一条属性链路**（`GameManager._apply_stat_fields()` + 同一个白名单）；`unique: true` 每局限购一件；独特机制走 hook 字段（`wave_heal_pct` 波末回血、`revive` 替死免死），由 GameManager 对应系统消费。商店货架 = 法器/法宝/回气丹三 kind 混抽（概率常量在 GameBalance：`POTION_CHANCE`/`ITEM_CHANCE`）。
- **角色形象**：每名修士在 `CultivatorData` 带 `sprite` 字段（5 行×5 列 192px 8 方向图集，行序见 `RunMotion.DIR_ROW`），`Player._setup_sprite_frames()` 按道统加载、缺图回退 `pawn_blue`；新角色图集走 media-gen 生成 5 张方向差分条带（`run8_<char>_<dir>`）→ `build_run8_atlas.py` 拼装，**拼完必看 /tmp 联系人表**，坏条带重生成或在图集上补格（cellectomy 脚本先例见 git 历史）。
- **危险度系统**（仿土豆兄弟 Danger 0~5）：`GameBalance.danger_*_mult()` 三组公式，`WaveSpawner` 刷怪量/血/攻与 Boss 消费；通关当前最高档解锁下一档，`GameManager` 落盘 `user://progress.cfg`；选择器在开始菜单（`StartMenu._build_danger_row`）。`danger_level` 不属于局内状态，`reset_run()` 不动它。
- 新增可生成实体：场景放 `scenes/entities/`，脚本放 `scripts/entities/`，由 `WaveSpawner` 注册；敌人继承 `EnemyBase`（行为开关式：突进/短咬/远程弹幕/自爆/分裂/光环/产卵/闪现全部走 `@export`，配比表是纯函数 `WaveSpawner.pick_scene_key(wave, roll)`，新敌种在低/高 roll 段加带并在 `unit_runner._test_enemy_mix` 钉线）。

**场景与节点**
- `.tscn` 与 `.gd` 同名配对，目录镜像（`scenes/x` ↔ `scripts/x`）。
- 物理分层已定义（1 world / 2 player / 3 enemies / 4 player_projectiles / 5 loot / 6 interactables），新增碰撞体必须按层设置，1–6 勿改；如有新用途，从第 7 层起新增并在此处补记。
- 像素对齐已开启（snap 2d transforms/vertices），纹理过滤为 Nearest，素材按像素画规格制作。

**验证**
- 改完跑七条 headless 命令（`G=/Applications/Godot.app/Contents/MacOS/Godot`），七条全绿才算完成；判据都由 `tests/check.gd`（`TestCheck`）输出 `[PASS]/[FAIL]` + `*_RESULT` + 退出码：
  ```bash
  $G --headless --path . res://tests/UnitRunner.tscn   # 数值单测（不加载场景）
  $G --headless --path . res://tests/PoolCheck.tscn    # 帧缓存 / 对象池
  $G --headless --path . res://tests/SmokeRunner.tscn  # 全流程冒烟（选人→战斗→升级→商店→结算→UI）
  $G --headless --path . res://tests/StatsTipCheck.tscn  # 属性面板点按详解（热区/文案/摆位，带 -- --selftest）
  $G --headless --path . res://tests/KnockProbe.tscn  # 震退方向活体判据：真跑一局镇岳印，逐帧查每个敌人的震退方向不指向玩家（会打印旧规则对照次数）
  $G --headless --path . res://tests/LayoutCheck.tscn   # UI 摆位（十块面板 × 三档屏宽：不出屏 + 每行文字装得下，带 -- --selftest 十三份反例）
  $G --headless --path . res://tests/ProjectileProbe.tscn  # 弹丸命中兑现活体判据：A 段单挑横切（牙齿在这）+ B 段尸潮读数，带 -- --no-homing 反例
  ```
  退出码 0 且末行 `*_RESULT: ALL PASS`。试听音效用 `AudioGallery.tscn`（要真实出声，别加 `--headless`）；弹丸/特效「看着多大」这类只能靠眼睛验收的东西用 `BoltPreview.tscn` 出图（同样不能 headless，跑完自动存 `/tmp/bolt_render.png` 并自退）。
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
- **「这是什么」一律点按可得，别指望 `tooltip_text`**：目标是 Android，触屏没有 hover，tooltip 在真机上永远不会出现。通用浮层是 `scripts/ui/DetailTip.gd`（`DetailTip.show_over(host, anchor, payload)`：薄遮罩 + 贴着条目的详情卡，同宿主同时只一张、收起即 destroy）。三条口径：① 热区要**整行/整格可点**——裸 `Control` 默认 `MOUSE_FILTER_STOP` 会当隐形挡板（把它改 IGNORE），`Container` 默认 PASS、`Label` 默认 IGNORE，所以包一层 `PanelContainer` 设 STOP 才是正解；② 判定只认**鼠标左键松开**（真机上触摸会再合成一份鼠标事件，两个分支都认就是一次点击走两遍）；③ 卡开着时给触发那一行压蓝底（`sb_on`/`sb_flat` 两份 stylebox 走 meta + `DetailTip.closed` 信号），触屏没有悬停态，这就是「卡讲的是哪一行」的唯一指路。范例见 `PlayerStatsDialog`（属性行 / 法器格含空格 / 纳戒仓库 / 悟道流水四类热区），判据 `StatsTipCheck`。
- **折行的控件必须钉 `custom_minimum_size.x`**：autowrap Label / RichTextLabel 的「最小宽」只有一个词，容器按那个宽度算「最小高」⇒ 一个词一行、浮层高度能冲到两千多像素。可用宽要显式给（`DetailTip.INNER_W`）。这类毛病不崩不报错，`StatsTipCheck` 量 rect 才看得见。
- **中文长句要自己切好硬换行，别把折行交给引擎**（2026-10-08 用户真机图：「都显示在一行里面叠在一起，都看不清了」）：`TextServer.AUTOWRAP_WORD` 只在**词间断点**处折行，一句不带空格的中文在它眼里可以是一个词 —— 同一份代码 macOS 上折三行、Android 真机上整行不折压到邻卡上（卡片仍是 156 宽、面板仍在 y=22，只有文字没折；字体度量两边逐像素一致）。唯一出口是 `GameStyle.wrap_cjk(text, font, size, 可用宽)`：按量出来的宽度切 `\n`，并做中文排版的两条禁则（收尾标点不许行首 / 开括号不许行尾），切完再 `custom_minimum_size.x` 钉住 + `AUTOWRAP_WORD_SMART` 兜底（BBCode 那种没法插硬换行的至少也要 SMART）。判据 `LayoutCheck` 量的是**每一行的宽**，不是「整段文字 + autowrap 开关有没有打开」—— 后者在真机上会全绿而画面是坏的。
- **一排卡片不许按死宽度摆**：`CultivatorSelect` 曾把 210 钉在每张卡上，修士加到 9 名后横着 1890 单位远超 20:9 屏的 1202 可视宽、两头卡出屏，文案折行后又要 591 高 > 540 屏高、「拜入此门」整排在屏外点不到。现在按 `get_viewport().get_visible_rect()` 现算（`fit_card_w` / `text_col_w` 两个纯函数），装不下就换成可上下滑的名单（横向滚动禁用 ⇒ 判据只放行「竖着滑出去」）。顶栏同理：五枚羁绊徽记挂进顶栏会把整条撑到 1125 宽、两头各出屏 82，已挪到顶栏之下单独一排，中间那组改 `SIZE_SHRINK_CENTER` 让两侧各拿一半 —— 顶栏的让位量还吃 `safe_insets()`（刘海/圆角，桌面窗口化恒为 0）。

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
- **远程的账要「真结到敌人身上」才算数**（2026-10-08 用户口径：「一些远程且只能击中一个敌人的武器需要加强一下，火符比其他武器要弱很多」）：近战弧扫当帧结算、环绕法宝接触即伤，天生没有"打不中"这一项；弹丸是飞过去的 —— 弹速 470 飞 300px 要 0.64s，敌人已经横移 70+px，而判定只有 7px + 受击圈 15px，旧直线弹在活体单挑横切场景实测只有 **13%** 兑现。现在：弹丸带有限转向追踪（`BladeProjectile.HOMING_TURN_RATE 3.6` ⇒ 最小转弯半径约 130px，看得见符在拐但不是制导导弹；400px 外打冲刺中的雷兽仍只有三成命中，高速怪的走位克制保留），一次多发的法器逐发各锁一个敌人（`FloatingWeapon._volley_targets`，把「扇形疾射…贯穿群敌」按文案兑现，只剩一个敌人时三发都归它）。兑现率由 `ProjectileProbe` 活体钉住；档位关系由 `UnitRunner::_test_ranged_focus_dps` 配 `WeaponData.sustained_single_dps()` / `is_focus_ranged()` 钉住 —— **单发最多结算 2 敌的「点杀位」远程，单体 DPS 必须 ≥ 全表非远程法器的单体 DPS 中位数**（参照点现算不写死，近战/环绕以后改数值这条下限跟着走）。本轮补强：火焰符 20→28 且 0.9→0.85、庚金飞剑 28→38 且 1.05→0.9、万木灵符 18→26；玄冰飞针/柳叶飞刀只吃追踪这一笔，数字不动。
- **范围类视觉必须与判定同源**（2026-10-08 用户口径：「攻击范围是多大就显示多大，不要透明/虚化的效果」）：弹丸、预警圈画出来的直径 == 判定直径，不许拿 additive 辉光把威胁糊大几倍（旧 `EnemyBolt` 用 128px `light_radial` 当外焰、判定半径只有 8px 就是反面教材）。大小只由一个常数/一个 `radius` 决定（`EnemyBolt.RADIUS`、`BossEnemy.SlamRing`），外观与碰撞一起变。
- **震屏只发给「值得看的节点」**（2026-10-08 用户口径：「一直摇不太好，这效果要留着特殊场景用」）：普通命中与普通小怪死亡**一律不加创伤**，打击感交给挤压形变 + 受击火花 + 跳字 + 顿帧；`add_trauma`/`feedback`/`shake_camera` 只允许用在玩家受创、精英与首领的登场/震地/伏诛、界碑聚灵阵、落雷命中之类。同一次挨打只许**一处**发放反馈——武器侧不再补一份（旧代码里 `BladeProjectile`/`FloatingWeapon` 和 `EnemyBase.take_damage` 各发一遍，就是镜头一直摇的直接来源）。公式与预算都在 `GameBalance`「打击感：镜头创伤」段：每秒预算 0.75 ÷ 衰减 2.2 ⇒ 最坏稳态创伤 0.34（±1.4px 轻颤），拿高频事件乱刷也晃不起来。档位（关闭/轻/标准/强）在 `SettingsManager.shake_intensity`，倍率经 `SmoothCamera._intensity` 乘到位移、滚转与缩放冲击上；判据 `UnitRunner::_test_screen_shake_budget`。要现场看数字就用 `tests/ShakeProbe.tscn`（**非判据**，只打读数）：`$G --headless --path . res://tests/ShakeProbe.tscn -- --wave 12`，输出「创伤发放次数/秒 + 看得见在动的帧占比 + 峰值位移」，2026-10-08 实测 12 波：改前 2.7 次/秒、27.4% 帧在动、峰值 11.1px、创伤顶格 1.00 → 改后 0.6 次/秒、1.8% 帧在动、峰值 1.4px。
- 雏形阶段原则：**先验证玩法再堆内容**；改数值优先改数据表，改结构前先更新本文档。
