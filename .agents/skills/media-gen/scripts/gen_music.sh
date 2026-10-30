#!/bin/bash
# gen_music.sh —— 生成 BGM 配乐（主 lyria-3.5，未出音频自动回退备用 lyria-3-pro-preview；
#                 输出 44.1kHz 立体声 MP3，单段约 2 分钟）
#
# 用法:
#   gen_music.sh -p "音乐描述" [-o 输出前缀] [-m 模型] [--fallback 备用模型] [--timeout 秒]
#
# 参数:
#   -p        音乐描述（必填）。写清：曲风/情绪/节奏BPM/主要乐器；
#             BGM 加 "instrumental only, no vocals"；结构可用 [Verse]/[Chorus] 等段落标签
#   -o        输出前缀（默认 assets_raw/music/bgm_时间戳），最终文件为 <前缀>.mp3
#   -m        主模型（默认 lyria-3.5）
#   --fallback 备用模型（默认 lyria-3-pro-preview；主模型两次尝试均未出音频时自动改用；
#             传 none 关闭回退，与 -m 相同或为空时也不回退）
#   --timeout 单次请求超时秒数（默认 300，实测一首约 35~60s）
#
# 循环播放: Godot 导入 MP3 时在 Import 面板勾选 loop 即可无缝循环；
#           也可在提示词里要求 "seamless loop"（效果不保证，结尾不齐时手动剪辑）。
#
# 输出: 成功时最后一行打印 "DONE: <mp3 路径>"

set -eo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib_common.sh"

MODEL="lyria-3.5"; FALLBACK="lyria-3-pro-preview"; PROMPT=""; OUT=""; TIMEOUT=300
while [ $# -gt 0 ]; do
  case "$1" in
    -p) PROMPT="$2"; shift 2 ;;
    -o) OUT="$2"; shift 2 ;;
    -m) MODEL="$2"; shift 2 ;;
    --fallback) FALLBACK="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) echo "未知参数: $1（用法见文件头注释）" >&2; exit 2 ;;
  esac
done
[ -n "$PROMPT" ] || { echo "缺少 -p 音乐描述" >&2; exit 2; }
[ -n "$OUT" ] || OUT="$RAW/music/bgm_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$(dirname "$OUT")"

# 模型链：主模型 + 备用模型（回退关闭/为空/与主模型相同则只用主模型）
MODELS="$MODEL"
case "$FALLBACK" in
  ""|none) ;;
  *) [ "$FALLBACK" = "$MODEL" ] || MODELS="$MODEL $FALLBACK" ;;
esac

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

GOT=""; USED_MODEL=""
for M in $MODELS; do
  [ "$M" = "$MODEL" ] || echo "主模型 $MODEL 未返回音频，回退备用模型 $M ..." >&2
  MODEL="$M" PROMPT="$PROMPT" python3 - > "$T/payload.json" <<'PY'
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
}))
PY
  for ATTEMPT in 1 2; do
    curl -s -m "$TIMEOUT" --noproxy '*' "$MEDIA_API_BASE/v1/chat/completions" \
      -H "Authorization: Bearer $MEDIA_API_KEY" -H "Content-Type: application/json" \
      -d @"$T/payload.json" -o "$T/resp.json" || true
    GOT="$(python3 "$SCRIPT_DIR/lib_extract.py" "$T/resp.json" "$T/media" audio 2>/dev/null | head -1 || true)"
    [ -n "$GOT" ] && { USED_MODEL="$M"; break 2; }
    echo "模型 $M 第 $ATTEMPT 次尝试未返回音频" >&2
    sleep 2
  done
done
[ -n "$GOT" ] || { echo "生成失败：${MODELS} 各两次尝试均未拿到音频" >&2; exit 1; }

EXT="${GOT##*.}"
cp "$GOT" "$OUT.$EXT"
FINAL="$OUT.$EXT"

manifest_append music "$USED_MODEL" "$PROMPT" "" "$FINAL" >/dev/null
echo "DONE: $FINAL"
