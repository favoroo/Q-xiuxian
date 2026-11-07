# 生图 API 实测笔记（2026-10-07 实测，官方文档见文末链接）

## 结论速查

| 模型 | 端点 | 默认输出 | 实测耗时 | 用途 |
|---|---|---|---|---|
| `gemini-3.1-flash-image` | `/v1/chat/completions` | JPEG 1408×768 | 11~45s | 质量/立绘/参考图锁定（默认） |
| `gemini-3.1-flash-lite-image` | `/v1/chat/completions` | JPEG 1024×1024 | ~5s | 快速草稿/批量图标 |
| `sensenova-u1.5-lite` | — | — | — | **不可用**，见"已知问题" |
| `gpt-image-*` | `/v1/images/generations` | — | — | **不可用**，codex 通道无鉴权 |

## 请求（通过 chat completions）

纯文生图：

```bash
curl -s --noproxy '*' http://127.0.0.1:8317/v1/chat/completions \
  -H "Authorization: Bearer $MEDIA_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"gemini-3.1-flash-image","messages":[{"role":"user","content":"生成一个游戏图标：红色苹果，卡通风格，白色背景"}]}'
```

带参考图（图生图/风格锁定，`image_url` 可放多块，官方上限 14 张）：

```json
{"model":"gemini-3.1-flash-image","messages":[{"role":"user","content":[
  {"type":"image_url","image_url":{"url":"data:image/jpeg;base64,<B64>"}},
  {"type":"text","text":"以参考图完全一致的艺术风格，生成：<内容描述>"}
]}]}
```

中文提示词实测可用。宽高比靠提示词文字控制（实测 9:16 → 768×1376，
横版默认 1408×768，方形（lite 模型）1024×1024）。

## 响应（形状不固定，必须用 lib_extract.py 提取）

图片 base64 出现在**两种位置之一**：
- `choices[0].message.images[0].image_url.url` → `data:image/jpeg;base64,...`
- `choices[0].message.content` 内嵌 markdown：`![Generated Image](data:image/jpeg;base64,...)`

偶发只回文本不出图（约 1/10），重试即可（脚本已内置 2 次重试）。

## 关键实测事实

- **无 alpha 通道**：明确要求透明底也返回 JPEG（components 3）。
  透明底走 `--keyout` 品红管线，见 workflow-style-lock.md。
- 图内含 C2PA 内容凭证元数据（jumd/c2pa 段），属正常，Godot 导入无影响。
- 参考图风格延续效果很好（实测苹果→药水瓶，线条/光泽/阴影/母题全继承）。

## 已知问题（2026-10-07）

1. `sensenova-u1.5-lite`：网关 `/v1/models` 有名单，但转发上游报
   `5: model is not found`（provider=openai-compatible-sensenova）。
   → 需网关管理员修正上游模型名；修好后请实测并更新本文件与 CHANGELOG。
2. `gpt-image-1.5/2/2.5`（含原生透明底能力）：报
   `auth_not_found (providers=codex)`，通道未配鉴权。若日后配好，
   透明底可改走 `/v1/images/generations` 的 `background:"transparent"`，优先级高于品红管线。
3. `/v1beta/interactions` 原生透传存在，但其 `speech_config`/voice 的 proto 结构与
   官方文档示例不符（报 `Cannot find field`），未继续攻坚——chat 路径已覆盖全部需求。
4. `/v1/images/generations`、`/v1/audio/speech`、`/v1/interactions` 对本技能模型均 404/不支持。

## 备用通道：magpie 网关的 images 端点（2026-11-06 实测）

`config/api.env` 的 `IMAGE_API_*` 指向 `http://127.0.0.1:3425`（key `magpie`），
`gen_image.sh` 会改用 OpenAI 风格的 images 端点：

```bash
# 纯文生图
curl -s --noproxy '*' http://127.0.0.1:3425/v1/images/generations \
  -H "Authorization: Bearer $IMAGE_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"gemini-3.1-flash-image","prompt":"红色药水图标","size":"1024x1024"}'
# → {"created":...,"data":[{"b64_json":"...","mime_type":"image/jpeg"}]}

# 参考图（风格锁定）：multipart，可多个 image 字段
curl -s --noproxy '*' http://127.0.0.1:3425/v1/images/edits \
  -H "Authorization: Bearer $IMAGE_API_KEY" \
  -F "model=gemini-3.1-flash-image" -F "prompt=以参考图一致画风，生成蓝色药水" \
  -F "image=@assets_raw/style/ref_pawn_red.png"
```

实测结论：

- **`/v1/models` 里没有任何图像模型**（65 个全是文本），别用列表判断；能画图的只有
  `gemini-3.1-flash-image`（也可写全名 `antigravity/gemini-3.1-flash-image`）。
  逐个探测 404 的：`gemini-3.1-flash-lite-image`（上游 `Requested entity was not found`）、
  `gemini-3.1-flash-image-mix`、`gpt-image-1.5/2/2.5`、`agnes-image-2.5-flash`、
  `ai-studio/*`、`auto/*`；`gemini-web/*` 在 magpie 里是关闭状态。
- **`/v1/chat/completions` 会吞图**：HTTP 200 但 `message.content=null`、无 `images` 字段，
  usage 却记满 completion tokens。生图必须走 images 两个端点。
- 尺寸：`size` 参数生效（`1024x1024` → 1024²，`1408x768` → 1376×768，模型取最接近的合法比例）。
- 参考图风格延续正常（像素风锚图 → 同画风蓝药水），`--keyout` 品红管线和 `--grid` 切表均验证通过。
- 响应里的 `b64_json` 由 `lib_extract.py` 统一提取（已支持该形状）。

## 官方参考文档

- 生图：<https://aistudio.google.com/docs/image-generation>
  （要点：参考图上限 14 张、多轮编辑 previous_interaction_id、
  response_format 的 aspect_ratio/image_size 参数——chat 通道不透传这些参数，
  一律用提示词控制）
