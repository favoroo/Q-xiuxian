# 音乐生成 API 实测笔记（2026-10-07 实测，官方文档见文末链接）

## 结论速查

| 模型 | 端点 | 输出 | 实测耗时 |
|---|---|---|---|
| `lyria-3.5` | `/v1/chat/completions` | MP3 192kbps 44.1kHz 立体声 | ~34s，单段约 2 分钟 |

## 请求（通过 chat completions）

```bash
curl -s --noproxy '*' http://127.0.0.1:8317/v1/chat/completions \
  -H "Authorization: Bearer $MEDIA_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"lyria-3.5","messages":[{"role":"user","content":"A cheerful 8-bit chiptune game loop, upbeat adventure theme, instrumental only, no vocals"}]}'
```

## 响应与提取

MP3 以 `data:audio/mpeg;base64,...` 形式嵌在 `choices[0].message.content` 的
markdown 图片语法里（`![Generated Image](data:audio/mpeg;base64,...)`），
前缀可能带 `[[A0]]` 等分段标记，用 `lib_extract.py ... audio` 提取即可。

## 提示词写法（官方规则）

- 没有独立的 BPM/时长/负面提示参数，**全部写进提示词文本**
- 曲风/情绪/乐器/BPM 直接描述；时长与结构用段落标签（`[Verse]`、`[Chorus]`、`[Bridge]`）
  或时间戳（`[0:00 - 0:10]`）控制
- 纯音乐（游戏 BGM 必须）：写 `instrumental only, no vocals`
- 歌词会跟随提示词语言；自定义歌词直接嵌在提示词里并用段落标签隔开
- 无负面提示词：不想要的元素用正面表述绕开（如不想要人声→"instrumental only"）
- 安全过滤：点名歌手音色、受版权保护歌词会被拒
- 每次生成结果非确定性，同一提示词多生成几条挑选即可

## 游戏使用建议

- 循环播放：Godot 导入 MP3 时在 Import 面板勾选 **loop**；MP3 循环在 Godot 4 无缝可用
- 想要更严丝合缝的循环可在提示词加 "seamless loop"（效果不保证，不齐就手动剪）
- 场景配乐参考公式：`<场景用途> + <曲风> + <情绪> + <乐器> + BPM`，例：
  - 菜单：`main menu theme, warm fantasy orchestral, calm and inviting, harp and strings, 80 BPM, instrumental only`
  - 战斗：`intense battle theme, dark fantasy orchestral with percussion, driving, 140 BPM, instrumental only`
- 长版本（几分钟）与短段落可以按需混用；素材多时用 manifest.jsonl 记录用途避免重复生成

## 官方参考文档

- 音乐：<https://aistudio.google.com/docs/music-generation>
  （要点：lyria-3.5 官方走 interactions API，本网关映射为 chat completions，
  请求/响应字段以本笔记实测为准）
