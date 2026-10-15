#!/usr/bin/env python3
"""bake_ambience.py —— 战场环境音（深渊罡风 + 灵气流响）无缝循环烘焙

与 bake_sfx.py 同源（复用其 Biquad/确定性噪声），但目标是 24s 无缝垫底循环而非短音效：
  - 噪声源就是 bake_sfx 的 1.2s 周期 _NOISE，滤波器预滚一个噪声周期进入稳态后再录音，
    录音窗取整数个 LFO 周期，首尾采样严格对齐 → OGG 循环无咔哒（MP3 容器有间隙，禁用）。
  - 罡风层：低通噪声，截止频率/振幅双 LFO 慢扫（阵风起伏）。
  - 灵气流响层：两条失谐正弦差拍 + 极轻高频带通噪声，若隐若现的「仙气底噪」。

产物约定与 bake_sfx 一致：assets_raw/ 是源（wav），assets/audio/ 是产物（ogg，需 ffmpeg）。
⚠ 烘完必须跑一次编辑器导入（$G --headless --path . --editor --quit）。
"""

import math
import os
import struct
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bake_sfx import Biquad, SR, _NOISE, NOISE_LEN  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets_raw", "sfx")
OUT_DIR = os.path.join(ROOT, "assets", "audio")

LOOP_SEC = 24.0          ## 循环长：1.2s 噪声周期的 20 倍，整数 LFO 周期保证无缝
GUST_CYCLES = 3          ## 阵风 LFO 在循环内的整周期数
BREATH_CYCLES = 5        ## 呼吸 LFO 整周期数
SHIMMER_CYCLES = 7       ## 灵气流响起伏整周期数


def render_wind() -> list:
    """渲染 24s 无缝罡风 + 灵气流响。返回 float 采样列表。"""
    total = int(round(LOOP_SEC * SR))
    preroll = NOISE_LEN  # 预滚一个噪声周期，让滤波器进入周期稳态
    buf = [0.0] * (total + preroll)

    wind_lp = Biquad()
    shim_bp = Biquad()
    shim_lp = Biquad()
    shim_lp.set("lowpass", 5200.0, 0.7)
    p1 = 0.0
    p2 = 0.0

    for i in range(len(buf)):
        t = (i - preroll) / SR  # 录音窗内 t ∈ [0, LOOP_SEC)，预滚段 t < 0 只喂滤波器
        n = _NOISE[i % NOISE_LEN]

        # 罡风：截止 220~900Hz 双 LFO 叠加慢扫，振幅同步起伏（周期均为 LOOP_SEC 的整数分频）
        gust = 0.5 + 0.5 * math.sin(2.0 * math.pi * GUST_CYCLES * t / LOOP_SEC)
        breath = 0.5 + 0.5 * math.sin(2.0 * math.pi * BREATH_CYCLES * t / LOOP_SEC + 1.3)
        cutoff = 220.0 + 680.0 * (0.55 * gust + 0.45 * breath)
        wind_lp.set("lowpass", cutoff, 0.9)
        wind = wind_lp.process(n) * (0.16 + 0.22 * gust * breath)

        # 灵气流响：1320Hz / 1329Hz 失谐差拍（9Hz 拍频），振幅走 7 周期慢门
        gate = 0.5 + 0.5 * math.sin(2.0 * math.pi * SHIMMER_CYCLES * t / LOOP_SEC + 0.6)
        p1 += 2.0 * math.pi * 1320.0 / SR
        p2 += 2.0 * math.pi * 1329.0 / SR
        bells = 0.5 * (math.sin(p1) + math.sin(p2)) * 0.028 * gate * gate
        # 极轻高频风嘶，给流响层一点空气感
        shim_bp.set("bandpass", 3400.0 + 900.0 * gate, 1.4)
        hiss = shim_lp.process(shim_bp.process(n)) * 0.05 * gate

        buf[i] = wind + bells + hiss

    out = buf[preroll:]
    peak = max(1e-9, max(abs(s) for s in out))
    gain = 0.6 / peak
    return [s * gain for s in out]


def write_wav(path: str, samples: list) -> None:
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(
            struct.pack("<h", max(-32768, min(32767, int(round(s * 32767.0)))))
            for s in samples
        ))


def main() -> int:
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    samples = render_wind()
    raw_path = os.path.join(RAW_DIR, "ambience_wind.wav")
    write_wav(raw_path, samples)

    r = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True)
    if r.returncode == 0 and "libvorbis" in r.stdout:
        out_path = os.path.join(OUT_DIR, "ambience_wind.ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw_path,
                        "-c:a", "libvorbis", "-q:a", "4", out_path], check=True)
        kb = os.path.getsize(out_path) / 1024.0
        print("✓ ambience_wind.ogg  %.1fs  %.0f KB → %s" % (LOOP_SEC, kb, out_path))
    else:
        # 与 bake_sfx 同口径：本机 ffmpeg 没有 libvorbis 就退 wav（项目 SFX 全 wav 先例）
        out_path = os.path.join(OUT_DIR, "ambience_wind.wav")
        write_wav(out_path, samples)
        kb = os.path.getsize(out_path) / 1024.0
        print("✓ ambience_wind.wav  %.1fs  %.0f KB → %s（ffmpeg 无 libvorbis，退 wav）" % (LOOP_SEC, kb, out_path))
    print("⚠ 记得跑一次编辑器导入：$G --headless --path . --editor --quit")
    return 0


if __name__ == "__main__":
    sys.exit(main())
