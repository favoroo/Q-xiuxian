#!/usr/bin/env bash
# collect_flicker.sh —— 真机闪屏日志一键收集（2026-10-20）
#
# 用途：用户插上手机后，直接跑本脚本，自动：
#   ① 检查设备连接
#   ② 安装最新 debug APK（可选，--install）
#   ③ 拉取 user://flicker_log.csv
#   ④ 同时抓一份 logcat（含引擎 ERROR/SCRIPT ERROR，排除噪音）
#   ⑤ 汇总打印关键行（非 HEARTBEAT 的 event 行 = 真正的异常帧）
#
# 用法：
#   bash tools/collect_flicker.sh                # 只拉日志
#   bash tools/collect_flicker.sh --install      # 先装 debug 包再拉
#   bash tools/collect_flicker.sh --clear        # 拉之前先清掉旧日志（推荐，避免混淆）
#
# 产物落在 build/flicker_collect_<时间戳>/ 下。

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
PKG="com.favo.qxiuxian"
APK="$REPO_ROOT/build/q-xiuxian-v0.0.60-debug-arm64-v8a.apk"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$REPO_ROOT/build/flicker_collect_$STAMP"

INSTALL=0
CLEAR=0
for a in "$@"; do
  case "$a" in
    --install) INSTALL=1 ;;
    --clear) CLEAR=1 ;;
  esac
done

say() { printf '\033[1;36m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
err() { printf '\033[1;31m%s\033[0m\n' "$*"; }

[ -x "$ADB" ] || { err "找不到 adb: $ADB"; exit 1; }

say "① 检查设备…"
DEVICES=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')
if [ -z "$DEVICES" ]; then
  err "没有已授权设备。请：手机开 USB 调试 → 插线 → 手机上点「允许」。"
  "$ADB" devices
  exit 1
fi
say "   已连接: $DEVICES"

mkdir -p "$OUT"

if [ "$INSTALL" = "1" ]; then
  say "② 安装 debug APK…"
  [ -f "$APK" ] || { err "APK 不存在: $APK"; exit 1; }
  "$ADB" install -r -d "$APK" || { err "安装失败"; exit 1; }
  say "   已安装（-r 覆盖，-d 允许降级）"
fi

if [ "$CLEAR" = "1" ]; then
  say "③ 清掉旧日志…"
  "$ADB" shell run-as "$PKG" rm -f files/flicker_log.csv 2>/dev/null || true
  # debug 包 run-as 可用；若不可用则退回外部路径
  "$ADB" shell rm -f "/sdcard/Android/data/$PKG/files/flicker_log.csv" 2>/dev/null || true
  say "   已清（若提示权限问题可忽略，旧文件会被追加覆盖场景标记）"
fi

say "④ 定位并拉取 flicker_log.csv…"
# 优先读**外部镜像**：用 release keystore 签名的包在 Android 上不是 debuggable，
# run-as 读不到内部 user://；探针已同时写一份到 /sdcard/Android/data/<pkg>/files/。
REMOTE_EXTERNAL="/sdcard/Android/data/$PKG/files/flicker_log.csv"
REMOTE_INTERNAL="/data/data/$PKG/files/flicker_log.csv"
GOT=0
if "$ADB" shell test -f "$REMOTE_EXTERNAL" 2>/dev/null; then
  "$ADB" pull "$REMOTE_EXTERNAL" "$OUT/flicker_log.csv" >/dev/null 2>&1 && GOT=1
  say "   从外部镜像读取成功（$REMOTE_EXTERNAL）"
fi
if [ "$GOT" = "0" ]; then
  if "$ADB" shell run-as "$PKG" test -f files/flicker_log.csv 2>/dev/null; then
    "$ADB" exec-out run-as "$PKG" cat files/flicker_log.csv > "$OUT/flicker_log.csv" 2>/dev/null && GOT=1
    say "   从内部存储读取成功（run-as）"
  fi
fi
if [ "$GOT" = "0" ]; then
  warn "   没找到 flicker_log.csv。可能原因："
  warn "   - 没在设置里开「闪屏探针」"
  warn "   - 探针开启后还没跑过一帧"
  warn "   - 路径变了（下面会 dump 一下目录）"
  echo "--- external ls ---" > "$OUT/ls_files.txt"
  "$ADB" shell ls -la "/sdcard/Android/data/$PKG/files/" >> "$OUT/ls_files.txt" 2>&1 || true
  echo "--- run-as ls ---" >> "$OUT/ls_files.txt"
  "$ADB" shell run-as "$PKG" ls -la files/ >> "$OUT/ls_files.txt" 2>&1 || true
  cat "$OUT/ls_files.txt"
fi

say "⑤ 抓 logcat（引擎错误 + 本进程）…"
"$ADB" logcat -d -v time 2>/dev/null | grep -iE "godot|$PKG|SCRIPT ERROR|ERROR:|E godot" > "$OUT/logcat.txt" || true
say "   已保存 logcat.txt ($(wc -l < "$OUT/logcat.txt" 2>/dev/null || echo 0) 行)"

say "⑥ 汇总…"
if [ -f "$OUT/flicker_log.csv" ]; then
  TOTAL=$(wc -l < "$OUT/flicker_log.csv")
  HB=$(grep -c "HEARTBEAT" "$OUT/flicker_log.csv" 2>/dev/null || echo 0)
  ANOM=$(grep -vcE "HEARTBEAT|^frame,|^#" "$OUT/flicker_log.csv" 2>/dev/null || echo 0)
  say "   总行数: $TOTAL   心跳: $HB   异常行: $ANOM"
  if [ "$ANOM" -gt 0 ]; then
    say "   ==== 异常行（这才是关键）===="
    grep -vE "HEARTBEAT|^frame,|^#" "$OUT/flicker_log.csv" | head -60
  else
    warn "   没有异常行 —— 阈值（显存跳2MB/draw掉35%）没抓到闪。"
    warn "   请把整份 flicker_log.csv 发我，我按逐帧数据放宽阈值/加子节点快照。"
  fi
else
  warn "   没有日志文件可汇总。"
fi

say "完成。产物目录：$OUT"
ls -la "$OUT"
