# media-gen 变更记录

> 规则：任何 agent 修改本技能（脚本/参考文档/配置格式），必须在此追加一行：
> `## 日期 摘要 (agent名)` + 要点列表。

## 2026-10-07 初版 (ZCode)

- 实测打通本机网关 `http://127.0.0.1:8317/v1`，统一走 `/v1/chat/completions`：
  - 生图 `gemini-3.1-flash-image`（1408×768 JPEG，参考图风格锁定 ✓，宽高比提示词控制 ✓，无 alpha）
  - 生图 `gemini-3.1-flash-lite-image`（1024²，约 5s，批量草稿）
  - 语音 `gemini-3.8-flash-tts` / `lite-tts`（WAV 24kHz 16bit 单声道，音色靠提示词指令）
  - 音乐 `lyria-3.5`（MP3 192kbps 44.1kHz，单段约 2 分钟，~34s）
- 交付脚本：`gen_image.sh`（含 `--keyout` 品红抠透明管线 + `keyout.py`）、
  `gen_voice.sh`、`gen_music.sh`、公共库 `lib_common.sh`、提取器 `lib_extract.py`
- 素材落地：`assets_raw/{style,images,voice,music}` + `STYLE.md` 风格档案 +
  `manifest.jsonl` 台账；`assets_raw/.gdignore` 防 Godot 扫描
- 已知问题：
  - `sensenova-u1.5-lite` 网关上游报 `model is not found`（provider=openai-compatible-sensenova），待管理员修正上游模型名
  - `gpt-image-*` 通道 `auth_not_found (providers=codex)`，未配鉴权
  - `/v1beta/interactions` 原生透传存在但 proto 字段与官方文档示例不符，弃用（chat 路径全覆盖）
  - 本机 `ALL_PROXY` 指向失效代理，所有 curl 必须 `--noproxy '*'`
- 同日补充实测（TTS 语气控制专项）：
  - 发现"用XX的语气说："式指令**会被朗读**（时长对照实验：1.0s→3.1s→4.9s 随指令长度增长）
  - 定论正解：**方括号舞台指令** `[音色描述]台词`（长指令实测 0.9s≈基线，不朗读），
    `gen_voice.sh --style` 已改为自动加方括号
  - 原生 `/v1beta/interactions` + `speech_config.voice_name` 时好时坏（同请求半数 400，
    网关多上游 proto 不一致），`annotations` 全 400 → 记为实验性，勿依赖

## 2026-10-07 游戏专属工作流增强 + 去风格化 (ZCode)

- `gen_image.sh` 新增 `--grid 列x行`：宫格素材表生成后自动切分为单张 PNG
  （新增 `scripts/split_grid.py`），与 `--keyout` 同用时逐格抠透明。
  端到端测试（木制训练假人三视角转身表 → 3 张 256px 透明单图）通过；
  过程中修复两个实现 bug（切分循环通配符不匹配、`$OUT_` 被解析为变量名导致输出路径截断）
- `workflow-style-lock.md` 新增工作流 5「角色多角度（转身表）」、
  工作流 6「表情/动作差分」，含 top-down 游戏方向处理建议（4 方向 2x2、
  斜向水平翻转、背面特征需明写）
- `usage-guide.md` 模板库新增：转身表 / 表情差分 / 动作差分 / 敌人尺寸阶梯 / 稀有度变色
- **按用户要求去风格化**：`assets_raw/style/STYLE.md` 重置为空白模板
  （新增「光照方向 / 色板倾向 / 剪影要求 / 音乐风格」中性字段），
  SKILL.md 与 references 移除全部演示风格词（Q版卡通等）；
  演示素材（骑士锚图/药水/史莱姆/语音/BGM）归档至 `/tmp/media-test/demo_archive/`，
  manifest 对应行已清理。**画风未回填 STYLE.md 前禁止生成正式素材**
