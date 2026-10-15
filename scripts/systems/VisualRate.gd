class_name VisualRate
extends RefCounted

## 帧率档位的唯一读取入口（2026-10-15 帧率机制优化）：
## 「流畅模式」开 = 渲染 60fps + 物理 60Hz，关 = 30/30（省电）。
## Main._apply_fps_limit 是唯一切档点；headless 判据不切档（恒为低档，
## PerfProbe 的重绘预算钉在低档口径）。
## 渲染器的重绘节流在这里按档位取值：30fps 档维持 2026-10-14 调好的
## 20/30Hz（33.3ms 帧长下降档才有真实节流收益），60fps 档统一翻倍——
## 否则「位置 60fps 顺滑、画面每 3 帧才画一次」的分离感比纯 30fps 更难受。

static var high_fps: bool = false

## 重绘/采样间隔（秒）：按当前档位从两个目标频率里取
static func interval(hz_high: float, hz_low: float) -> float:
	return 1.0 / (hz_high if high_fps else hz_low)
