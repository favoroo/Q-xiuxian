---
name: media-gen
description: 为本项目（T1 吸血鬼幸存者类游戏）生成分媒体素材：游戏美术图（角色/道具图标/立绘/头像/场景/封面，支持参考图锁定画风与抠透明底）、角色多角度转身表与表情动作差分（--grid 切表）、中文语音台词（TTS）、BGM 配乐。凡需要生成、编辑、批量产出、风格化一致的游戏图/语音/音乐素材时必须使用本技能。不含音效 SFX 与逐帧动画（边界见 references/usage-guide.md）。
---

# media-gen：T1 游戏素材生成

本机媒体网关（`http://127.0.0.1:8317/v1`）的封装：生图（Gemini）、中文语音（Gemini TTS）、
BGM（Lyria）。所有调用走脚本，脚本自动处理鉴权、重试、媒体提取、抠透明底和台账登记。

## 铁律（违反会浪费配额或产出废料）

1. **生成美术前先读 `assets_raw/style/STYLE.md`**（项目风格档案）：
   拿 `STYLE_PREFIX` 风格前缀拼进提示词、拿锚图路径传 `-r`。没有锚图 → 先走
   [工作流 1 风格锚定](references/workflow-style-lock.md)，并与用户确认画风。
2. **不要手搓 curl**，一律用脚本（返回形状不固定、代理陷阱、重试逻辑都已封装）。
3. **生成前先查台账**：`grep 关键词 assets_raw/manifest.jsonl`，能复用就不重新生成。

## 快速开始

```bash
S=.agents/skills/media-gen/scripts
# PREFIX = assets_raw/style/STYLE.md 中「风格前缀」一节的固定短语（先读档案再填）
PREFIX="<从 STYLE.md 复制风格前缀>"
ANCHOR="<从 STYLE.md 复制锚图路径>"

# 生图（自动带台账；透明图标加 --keyout 256）
$S/gen_image.sh -p "${PREFIX} 游戏道具图标：红色治疗药水" --keyout 256 -o assets_raw/images/icon_potion_red

# 参考图锁风格（锚图/角色设定图，路径取自 STYLE.md）
$S/gen_image.sh -p "${PREFIX} 蓝色法力药水图标" -r "$ANCHOR" --keyout 256 -o assets_raw/images/icon_potion_blue

# 角色多角度：转身表一条命令出三视角透明单图（详见 workflow-style-lock.md 工作流5）
$S/gen_image.sh -p "${PREFIX} 角色转身表：同一角色正面/侧面/背面，站姿等距并排，光照一致，细节一致" \
  -r assets_raw/style/char_hero.png --grid 3x1 --keyout 256 -o assets_raw/images/char_hero_turnaround

# 中文语音（音色描述登记在 STYLE.md 的 VOICES 表，同角色固定复用）
$S/gen_voice.sh -t "欢迎来到地牢！" --style "<从 STYLE.md 的 VOICES 表取该角色音色>" -o assets_raw/voice/vo_welcome

# BGM（曲风描述登记在 STYLE.md 的「音乐风格」；Godot 导入时勾 loop）
$S/gen_music.sh -p "<STYLE.md 音乐风格> dungeon crawler loop, instrumental only, no vocals" -o assets_raw/music/bgm_menu
```

> ⚠️ STYLE.md 的风格前缀与锚图为空 = 项目画风未定：**先与用户确认画风并完成
> 风格锚定（工作流 1）再生成任何正式素材**，禁止把示例 prompt 里的措辞当画风。

成功输出最后一行 `DONE: <文件路径>`；失败看 stderr 提示，处理后重跑。

## 任务路由（只读你需要的那个文件）

| 任务 | 去处 |
|---|---|
| 风格锚定 / 角色一致性 / 批量图标 / **多角度转身表** / **表情动作差分** / 改图 / 透明底管线 | `references/workflow-style-lock.md` ★先读这个 |
| 生图参数、返回格式、故障 | `references/api-image.md` |
| 语音音色控制、逐字技巧 | `references/api-voice.md` |
| BGM 提示词公式、循环播放 | `references/api-music.md` |
| 素材目录约定、Godot 导入设置、prompt 模板、能力边界 | `references/usage-guide.md` |
| 本技能的历史与迭代规则 | `CHANGELOG.md` |

## 模型选择

| 用途 | 模型 | 备注 |
|---|---|---|
| 生图（默认） | `gemini-3.1-flash-image` | 支持参考图锁定风格，11~45s |
| 生图（批量草稿/图标） | `gemini-3.1-flash-lite-image` | ~5s，1024² |
| 语音（默认） | `gemini-3.8-flash-tts` | WAV 24kHz |
| 语音（批量草稿） | `gemini-3.8-flash-lite-tts` | 更便宜 |
| 音乐 | `lyria-3.5` | MP3 44.1kHz，单段约 2 分钟。**只能写整段音乐，做不了短音效**：实测索要「0.15 秒点击音」仍返回 56 秒素材。音效请改用本项目的 `tools/bake_sfx.py`（离线合成，见 usage-guide.md 能力边界表） |
| ~~sensenova-u1.5-lite~~ | 网关上游配置错误，**暂不可用**（修好后优先用于便宜批量生图） |
| ~~gpt-image-*~~ | 通道无鉴权，不可用 |

## 已知陷阱（2026-10-07 实测）

- 本机 shell 的 `ALL_PROXY` 指向失效代理：手动 curl 必须加 `--noproxy '*'`（脚本已内置）
- 生图**没有透明通道**：一律走 `--keyout` 品红管线
- 响应里媒体位置不固定（`message.images` 或 content 内嵌 markdown），提取交给脚本
- 模型偶发只回文本不出图：脚本已自动重试 2 次
- 逐帧动画与 SFX 不是本技能能力，替代方案见 usage-guide.md 能力边界表。
  **短音效不要试图用 `gen_music.sh` 凑**（时长不受控，见 api-music.md 实测），走 `tools/bake_sfx.py` 本地烘焙
- TTS 风格指令直接写进台词**会被朗读出来**（实测）——必须走 `--style`（脚本自动
  转成不朗读的方括号舞台指令），角色音色描述登记在 STYLE.md 的 VOICES 表

## 维护规则（后续 agent 必须遵守）

- 发现 API 行为变化（端点/参数/新模型/修复的通道）→ **更新对应 `references/api-*.md`
  的实测内容，并在 `CHANGELOG.md` 追加一行**（日期 + 变更 + 你的发现）
- 修好 `sensenova-u1.5-lite` 或 gpt-image 通道后：先实测（含水印检查），再更新
  api-image.md 模型表与本文件，并把更优的透明底/批量方案写进 workflow 文档
- 新增脚本参数时同步更新脚本头注释与本文件示例
- 不要改动 `config/api.env` 格式；密钥已进 `.gitignore`，不要把密钥写进任何其他文件
