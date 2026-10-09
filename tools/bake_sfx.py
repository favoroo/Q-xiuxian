#!/usr/bin/env python3
"""bake_sfx.py —— 修仙幸存者音效离线烘焙（纯标准库，零模型依赖）

移植自 dudu-cocos/tools/bake-audio.ts 的合成内核，用数学而不是录音生成音效：
    tone  = 振荡器(sine/square/sawtooth/triangle + 频率指数/线性斜坡) × 指数包络 [可选 lowpass]
    noise = 白噪声(确定性填充) × RBJ 双二阶(lowpass/highpass/bandpass，截止频率可扫) × 指数包络
每条音色渲染成单声道 16-bit WAV；有 ffmpeg 时再转 ogg(vorbis) 进包体。

为什么不用 media-gen：那个技能的边界表里写明「音效 SFX ❌ 无 SFX 模型」，
只有 BGM(lyria) 和语音(TTS)。所以 BGM 走生成，短音效走本地烘焙。

用法：
    python3 tools/bake_sfx.py                 # 全量烘到 assets_raw/sfx/，并把 wav 放进 assets/audio/sfx/
    python3 tools/bake_sfx.py --ogg           # 转 ogg 进包体（需本机 ffmpeg 带 libvorbis，否则自动退回 wav）
    python3 tools/bake_sfx.py --only enemy_death,sword_swing
    python3 tools/bake_sfx.py --list

短音效默认留 wav：解码零延迟、不依赖容器 seek（与 dudu-cocos 的结论一致）。
产物约定（与 AGENTS.md 一致）：assets_raw/ 是源、assets/ 是产物，勿手改产物。
脚本最后一律打印可直接粘进 AudioManager._load_audio_assets() 的注册代码。
"""

import argparse
import math
import os
import struct
import subprocess
import sys
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_DIR = os.path.join(ROOT, "assets_raw", "sfx")
OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
RENDER_WINDOW = 0.8          # 统一渲染窗，尾部静音会被裁掉

# ---------------- 确定性随机（烘焙可复现，diff 友好） ----------------

_seed = 0x2F6E2B1


def _srand() -> float:
    global _seed
    s = _seed & 0xFFFFFFFF
    s ^= (s << 13) & 0xFFFFFFFF
    s ^= s >> 17
    s ^= (s << 5) & 0xFFFFFFFF
    _seed = s
    return ((s % 0x7FFFFF) / 0x7FFFFF) * 2.0 - 1.0


def _urand(a: float, b: float) -> float:
    return a + (_srand() * 0.5 + 0.5) * (b - a)


# ---------------- 基本构件 ----------------

def _wave_at(wtype: str, p: float) -> float:
    p -= math.floor(p)
    if wtype == "sine":
        return math.sin(2.0 * math.pi * p)
    if wtype == "square":
        return 1.0 if p < 0.5 else -1.0
    if wtype == "sawtooth":
        return 2.0 * p - 1.0
    if wtype == "triangle":
        if p < 0.25:
            return 4.0 * p
        if p < 0.75:
            return 2.0 - 4.0 * p
        return 4.0 * p - 4.0
    raise ValueError(wtype)


def _expramp(v0: float, v1: float, t: float, dur: float) -> float:
    if dur <= 0.0:
        return v1
    t = min(1.0, max(0.0, t / dur))
    if v0 <= 0.0:
        v0 = 1e-5
    if v1 <= 0.0:
        v1 = 1e-5
    return v0 * math.pow(v1 / v0, t)


class Biquad:
    """RBJ 双二阶，与 WebAudio BiquadFilter 同族。"""

    def __init__(self):
        self.b0, self.b1, self.b2, self.a1, self.a2 = 1.0, 0.0, 0.0, 0.0, 0.0
        self.x1 = self.x2 = self.y1 = self.y2 = 0.0

    def set(self, ftype: str, f: float, q: float) -> None:
        w = 2.0 * math.pi * max(20.0, f) / SR
        cs, sn = math.cos(w), math.sin(w)
        alpha = sn / (2.0 * q)
        if ftype == "lowpass":
            b0, b1, b2 = (1.0 - cs) / 2.0, 1.0 - cs, (1.0 - cs) / 2.0
        elif ftype == "highpass":
            b0, b1, b2 = (1.0 + cs) / 2.0, -(1.0 + cs), (1.0 + cs) / 2.0
        elif ftype == "bandpass":
            b0, b1, b2 = alpha, 0.0, -alpha
        else:
            raise ValueError(ftype)
        a0, a1, a2 = 1.0 + alpha, -2.0 * cs, 1.0 - alpha
        self.b0, self.b1, self.b2 = b0 / a0, b1 / a0, b2 / a0
        self.a1, self.a2 = a1 / a0, a2 / a0

    def process(self, x: float) -> float:
        y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        return y


def tone(buf, *, wtype="sine", f0=440.0, f1=None, t0=0.0, dur=0.12, peak=0.3,
         curve="exp", lp=0.0) -> None:
    if f1 is None:
        f1 = f0
    start = int(round(t0 * SR))
    length = int(round(dur * SR))
    atk = min(0.012, dur * 0.2)
    bq = Biquad() if lp else None
    if bq:
        bq.set("lowpass", lp, 0.8)
    phase = 0.0
    for i in range(length):
        t = i / SR
        if f1 == f0:
            f = f0
        elif curve == "exp":
            f = _expramp(f0, f1, t, dur)
        else:
            f = f0 + (f1 - f0) * min(1.0, t / dur)
        phase += 2.0 * math.pi * max(20.0, f) / SR
        if t < atk:
            env = _expramp(0.0001, peak, t, atk)
        else:
            env = _expramp(peak, 0.0001, t - atk, dur - atk)
        s = _wave_at(wtype, phase / (2.0 * math.pi)) * env
        if bq:
            s = bq.process(s)
        idx = start + i
        if 0 <= idx < len(buf):
            buf[idx] += s


NOISE_LEN = int(round(SR * 1.2))
_NOISE = [_srand() for _ in range(NOISE_LEN)]


def noise(buf, *, t0=0.0, dur=0.1, peak=0.2, ftype="bandpass", f0=1200.0, f1=None,
          q=1.2) -> None:
    if f1 is None:
        f1 = f0
    start = int(round(t0 * SR))
    length = int(round(dur * SR))
    rate = _urand(0.85, 1.15)
    pos = int(_urand(0.0, 0.5) * SR)
    bq = Biquad()
    atk = 0.006
    for i in range(length):
        t = i / SR
        bq.set(ftype, f0 if f1 == f0 else _expramp(f0, max(30.0, f1), t, dur), q)
        pos += rate
        s = _NOISE[int(pos) % NOISE_LEN]
        if t < atk:
            env = _expramp(0.0001, peak, t, atk)
        else:
            env = _expramp(peak, 0.0001, t - atk, dur - atk)
        idx = start + i
        if 0 <= idx < len(buf):
            buf[idx] += bq.process(s) * env


# ---------------- 音色配方 ----------------
# 命名 = AudioManager 里的 sfx key。同一 key 出多个变体，播放时随机挑一个再抖音高，
# 避免「连续十次击杀完全同一个音」的机械感。

def _arp(buf, freqs, *, t_step=0.09, dur=0.26, peak=0.15, wtype="triangle", echo=None):
    for i, f in enumerate(freqs):
        tone(buf, wtype=wtype, f0=f, f1=f, dur=dur, peak=peak, t0=i * t_step)
        if echo:
            tone(buf, wtype="square", f0=f * 2, f1=f * 2, dur=dur * 0.5, peak=echo,
                 t0=i * t_step)


SFX = {
    # 妖物死灭：以前普通敌人死亡是全静音的，而击杀是本作最高频的事件
    "enemy_death": [
        lambda b: (tone(b, wtype="sine", f0=300, f1=90, dur=0.10, peak=0.18),
                   noise(b, dur=0.06, peak=0.10, ftype="bandpass", f0=1400, f1=500, q=0.9)),
        lambda b: (tone(b, wtype="triangle", f0=430, f1=140, dur=0.08, peak=0.15),
                   noise(b, dur=0.05, peak=0.08, ftype="highpass", f0=2200, f1=900)),
        lambda b: (tone(b, wtype="sine", f0=220, f1=68, dur=0.13, peak=0.20),
                   noise(b, dur=0.08, peak=0.09, ftype="lowpass", f0=820, f1=220, q=1.0)),
    ],
    "enemy_death_elite": [
        lambda b: (tone(b, wtype="sawtooth", f0=200, f1=40, dur=0.26, peak=0.24),
                   tone(b, wtype="sine", f0=120, f1=32, dur=0.30, peak=0.26),
                   noise(b, dur=0.22, peak=0.20, ftype="lowpass", f0=3200, f1=180, q=1.6)),
        lambda b: (tone(b, wtype="sawtooth", f0=170, f1=45, dur=0.30, peak=0.22),
                   tone(b, wtype="square", f0=1500, f1=1150, dur=0.13, peak=0.07, t0=0.04),
                   noise(b, dur=0.26, peak=0.18, ftype="lowpass", f0=2600, f1=160, q=1.4)),
    ],
    # 攻击音按流派分开（原来四种法器共用一个 blade_shoot）
    "sword_swing": [
        lambda b: (noise(b, dur=0.12, peak=0.12, ftype="bandpass", f0=800, f1=2800, q=0.7),
                   tone(b, wtype="triangle", f0=320, f1=130, dur=0.07, peak=0.05)),
        lambda b: (noise(b, dur=0.10, peak=0.10, ftype="bandpass", f0=1200, f1=2300, q=0.8),
                   tone(b, wtype="triangle", f0=260, f1=150, dur=0.06, peak=0.045)),
    ],
    "talisman_throw": [
        lambda b: (noise(b, dur=0.09, peak=0.09, ftype="highpass", f0=2600, f1=1400),
                   tone(b, wtype="sine", f0=900, f1=1450, dur=0.06, peak=0.05)),
        lambda b: (tone(b, wtype="square", f0=1250, f1=1750, dur=0.05, peak=0.055),
                   noise(b, dur=0.06, peak=0.06, ftype="bandpass", f0=3000, f1=1800, q=1.5)),
    ],
    "thunder_strike": [
        lambda b: (noise(b, dur=0.22, peak=0.20, ftype="highpass", f0=3200, f1=800, q=0.8),
                   tone(b, wtype="sine", f0=130, f1=42, dur=0.24, peak=0.20),
                   tone(b, wtype="square", f0=4200, f1=3200, dur=0.06, peak=0.06)),
        lambda b: (noise(b, dur=0.14, peak=0.17, ftype="bandpass", f0=2500, f1=650, q=1.2),
                   tone(b, wtype="triangle", f0=180, f1=60, dur=0.16, peak=0.14)),
    ],
    "fan_gust": [
        lambda b: (noise(b, dur=0.26, peak=0.15, ftype="lowpass", f0=1300, f1=300, q=0.8),),
        lambda b: (noise(b, dur=0.22, peak=0.13, ftype="bandpass", f0=900, f1=1800, q=0.6),
                   tone(b, wtype="sine", f0=200, f1=140, dur=0.18, peak=0.05)),
    ],
    # 商店与背包
    "shop_buy": [
        lambda b: (tone(b, wtype="square", f0=988, f1=988, dur=0.09, peak=0.10),
                   tone(b, wtype="square", f0=1319, f1=1319, dur=0.16, peak=0.09, t0=0.08)),
        lambda b: (tone(b, wtype="triangle", f0=660, f1=990, dur=0.10, peak=0.12),
                   tone(b, wtype="square", f0=1320, f1=1760, dur=0.14, peak=0.07, t0=0.08),
                   noise(b, dur=0.10, peak=0.04, ftype="highpass", f0=3200, f1=1400, t0=0.02)),
    ],
    "shop_reroll": [
        lambda b: (noise(b, dur=0.045, peak=0.09, ftype="bandpass", f0=1200, f1=1600, q=1.6),
                   noise(b, dur=0.045, peak=0.10, ftype="bandpass", f0=1700, f1=2200, q=1.6, t0=0.06),
                   noise(b, dur=0.05, peak=0.11, ftype="bandpass", f0=2300, f1=2900, q=1.6, t0=0.13)),
        lambda b: (tone(b, wtype="square", f0=520, f1=760, dur=0.05, peak=0.06),
                   tone(b, wtype="square", f0=620, f1=900, dur=0.05, peak=0.06, t0=0.07),
                   tone(b, wtype="square", f0=760, f1=1100, dur=0.07, peak=0.07, t0=0.14)),
    ],
    "shop_lock": [
        lambda b: (tone(b, wtype="square", f0=520, f1=430, dur=0.06, peak=0.07),
                   noise(b, dur=0.03, peak=0.05, ftype="highpass", f0=2400)),
    ],
    "sell": [
        lambda b: (tone(b, wtype="square", f0=1180, f1=880, dur=0.10, peak=0.09),
                   tone(b, wtype="triangle", f0=880, f1=660, dur=0.12, peak=0.07, t0=0.06)),
    ],
    "equip": [
        lambda b: (tone(b, wtype="triangle", f0=620, f1=930, dur=0.10, peak=0.11),
                   tone(b, wtype="sine", f0=1240, f1=1860, dur=0.08, peak=0.05, t0=0.04)),
        lambda b: (tone(b, wtype="triangle", f0=520, f1=780, dur=0.09, peak=0.10),
                   noise(b, dur=0.05, peak=0.04, ftype="highpass", f0=3000, t0=0.05)),
    ],
    "unequip": [
        lambda b: (tone(b, wtype="triangle", f0=900, f1=560, dur=0.10, peak=0.09),),
    ],
    "merge_success": [
        lambda b: (_arp(b, [523, 659, 784, 1047], t_step=0.075, dur=0.24, peak=0.15, echo=0.04),
                   tone(b, wtype="sine", f0=2093, f1=2093, dur=0.22, peak=0.06, t0=0.24)),
        lambda b: (_arp(b, [659, 784, 988, 1319], t_step=0.07, dur=0.22, peak=0.14, echo=0.035),
                   noise(b, dur=0.12, peak=0.05, ftype="highpass", f0=3600, f1=2000, t0=0.2)),
    ],
    # UI
    "ui_click": [
        lambda b: (tone(b, wtype="square", f0=660, f1=880, dur=0.05, peak=0.06),),
        lambda b: (tone(b, wtype="square", f0=780, f1=980, dur=0.045, peak=0.055),),
        lambda b: (tone(b, wtype="triangle", f0=880, f1=1100, dur=0.05, peak=0.06),),
    ],
    "ui_back": [
        lambda b: (tone(b, wtype="square", f0=440, f1=300, dur=0.07, peak=0.06),),
    ],
    "ui_error": [
        lambda b: (tone(b, wtype="sawtooth", f0=220, f1=180, dur=0.08, peak=0.10),
                   tone(b, wtype="sawtooth", f0=190, f1=150, dur=0.10, peak=0.09, t0=0.10)),
        lambda b: (tone(b, wtype="square", f0=300, f1=240, dur=0.07, peak=0.08),
                   tone(b, wtype="square", f0=250, f1=200, dur=0.09, peak=0.07, t0=0.09)),
    ],
    # 阶段与状态
    "wave_start": [
        lambda b: (tone(b, wtype="sawtooth", f0=294, f1=294, dur=0.30, peak=0.10, lp=1800),
                   tone(b, wtype="sawtooth", f0=440, f1=440, dur=0.34, peak=0.08, t0=0.10, lp=1800),
                   tone(b, wtype="sine", f0=147, f1=147, dur=0.50, peak=0.10, t0=0.0)),
    ],
    "wave_clear": [
        lambda b: (_arp(b, [784, 659, 523], t_step=0.10, dur=0.22, peak=0.11),),
    ],
    "boss_raid": [
        lambda b: (tone(b, wtype="sine", f0=92, f1=58, dur=0.55, peak=0.22),
                   tone(b, wtype="sawtooth", f0=138, f1=110, dur=0.50, peak=0.10, lp=900, t0=0.05),
                   noise(b, dur=0.45, peak=0.10, ftype="lowpass", f0=600, f1=180, q=1.0)),
    ],
    "dodge": [
        lambda b: (noise(b, dur=0.08, peak=0.07, ftype="bandpass", f0=2000, f1=3600, q=1.4),),
        lambda b: (tone(b, wtype="sine", f0=1500, f1=2400, dur=0.07, peak=0.06),),
    ],
    "heal": [
        lambda b: (tone(b, wtype="sine", f0=660, f1=880, dur=0.20, peak=0.10),
                   tone(b, wtype="triangle", f0=1320, f1=1760, dur=0.16, peak=0.05, t0=0.06)),
        lambda b: (_arp(b, [587, 880], t_step=0.08, dur=0.20, peak=0.10),),
    ],
    "victory": [
        lambda b: (_arp(b, [523, 659, 784, 1047, 1319], t_step=0.11, dur=0.30, peak=0.16, echo=0.04),),
    ],
    # 随行神通：冲刺是贴身风声，增益是上行琶音，护体是金属罩鸣，回春是柔和上行
    "skill_dash": [
        lambda b: (noise(b, dur=0.14, peak=0.16, ftype="bandpass", f0=600, f1=3400, q=0.8),
                   tone(b, wtype="sine", f0=180, f1=420, dur=0.10, peak=0.08)),
        lambda b: (noise(b, dur=0.12, peak=0.15, ftype="highpass", f0=900, f1=2800),
                   tone(b, wtype="triangle", f0=240, f1=520, dur=0.08, peak=0.07)),
    ],
    "skill_buff": [
        lambda b: (_arp(b, [660, 880, 1174], t_step=0.06, dur=0.18, peak=0.12),),
        lambda b: (_arp(b, [587, 784, 1046], t_step=0.06, dur=0.18, peak=0.11),
                   noise(b, dur=0.08, peak=0.04, ftype="highpass", f0=3600, f1=2400, t0=0.12)),
    ],
    "skill_aegis": [
        lambda b: (tone(b, wtype="square", f0=220, f1=180, dur=0.18, peak=0.10, lp=1400),
                   tone(b, wtype="sine", f0=1245, f1=1175, dur=0.26, peak=0.08, t0=0.02),
                   noise(b, dur=0.16, peak=0.06, ftype="highpass", f0=4200, f1=2600, t0=0.01)),
        lambda b: (tone(b, wtype="square", f0=196, f1=165, dur=0.20, peak=0.09, lp=1200),
                   tone(b, wtype="sine", f0=1046, f1=988, dur=0.28, peak=0.08, t0=0.03)),
    ],
    "skill_heal": [
        lambda b: (tone(b, wtype="sine", f0=523, f1=784, dur=0.24, peak=0.11),
                   tone(b, wtype="triangle", f0=1046, f1=1568, dur=0.18, peak=0.05, t0=0.08)),
        lambda b: (_arp(b, [523, 659, 880], t_step=0.07, dur=0.22, peak=0.10),),
    ],
    "defeat": [
        lambda b: (_arp(b, [392, 330, 262], t_step=0.14, dur=0.30, peak=0.13),
                   tone(b, wtype="sine", f0=131, f1=128, dur=0.5, peak=0.10, t0=0.30)),
    ],
}


# ---------------- 响度归一 ----------------
# 配方里的 peak 只是「相对关系」，真正决定混音是否均衡的是这一步：
# 每条音色烘完都按分类目标峰值归一化，以后改配方不会改出「一个震耳一个听不见」。

TARGET_PEAK_DEFAULT = 0.20    ## UI / 拾取 / 状态反馈
TARGET_PEAK_LOUD = 0.30       ## 死亡 / 攻击 / 阶段音头

TARGET_PEAK = {
    "enemy_death": TARGET_PEAK_LOUD,
    "enemy_death_elite": TARGET_PEAK_LOUD,
    "sword_swing": TARGET_PEAK_LOUD,
    "talisman_throw": TARGET_PEAK_LOUD,
    "thunder_strike": TARGET_PEAK_LOUD,
    "fan_gust": TARGET_PEAK_LOUD,
    "merge_success": TARGET_PEAK_LOUD,
    "wave_start": TARGET_PEAK_LOUD,
    "boss_raid": TARGET_PEAK_LOUD,
    "victory": TARGET_PEAK_LOUD,
    "defeat": TARGET_PEAK_LOUD,
    "dodge": 0.24,
    "heal": 0.24,
    "skill_dash": 0.24,
    "skill_buff": 0.24,
    "skill_aegis": 0.24,
    "skill_heal": 0.24,
}


def _peak(buf) -> float:
    peak = 0.0
    for v in buf:
        a = -v if v < 0.0 else v
        if a > peak:
            peak = a
    return peak


def _normalize(buf, name: str) -> float:
    """预缩放：把音色抬/压到目标分类附近，保证后面过 tanh 限幅时不压太多。"""
    peak = _peak(buf)
    target = TARGET_PEAK.get(name, TARGET_PEAK_DEFAULT)
    if peak < 1e-4:
        return 0.0
    gain = target / peak
    for i in range(len(buf)):
        buf[i] *= gain
    return gain


# ---------------- WAV 封装与转码 ----------------

def render(name: str, variants) -> list:
    paths = []
    target = TARGET_PEAK.get(name, TARGET_PEAK_DEFAULT)
    for idx, fn in enumerate(variants, start=1):
        global _seed
        _seed = (0x2F6E2B1 + sum(ord(c) for c in name) * 7919 + idx * 104729) & 0xFFFFFFFF
        buf = [0.0] * int(round(SR * RENDER_WINDOW))
        fn(buf)
        gain = _normalize(buf, name)
        # 软限幅：tanh 只压需要用的峰值，小信号几乎无损，保持音色间相对响度
        k = math.tanh(1.1)
        shaped = [math.tanh(v * 1.1) / k for v in buf]
        # 限幅会整体抬一点电平（除以 tanh(1.1)），所以峰值匹配放在限幅之后做，
        # 这样 TARGET_PEAK 就是文件里的真实峰值，不同 key 之间才有可比的响度。
        sp = _peak(shaped)
        if sp > 1e-6:
            trim = target / sp
            shaped = [v * trim for v in shaped]
        pcm = bytearray()
        for v in shaped:
            s = -1.0 if v < -1.0 else (1.0 if v > 1.0 else v)
            pcm += struct.pack("<h", int(s * 32767))
        # 裁尾部静音（留 30ms 余量）
        end = len(buf) - 1
        while end > 0 and abs(buf[end]) < 0.0008:
            end -= 1
        keep = min(len(buf), end + int(round(SR * 0.03)) + 1)
        pcm = pcm[:keep * 2]
        path = os.path.join(RAW_DIR, "%s_%d.wav" % (name, idx))
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(bytes(pcm))
        paths.append((path, keep / SR, gain))
    return paths


def have_vorbis() -> bool:
    r = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True)
    return "libvorbis" in (r.stdout or "")


def to_ogg(wav_path: str) -> str:
    out = os.path.join(OUT_DIR, os.path.splitext(os.path.basename(wav_path))[0] + ".ogg")
    os.makedirs(OUT_DIR, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path,
         "-c:a", "libvorbis", "-q:a", "3", "-ac", "1", out],
        check=True,
    )
    return out


def to_wav_asset(wav_path: str) -> str:
    """把烘好的 wav 复制进包体目录。

    短音效留 wav 是有意的（与 dudu-cocos 同一结论）：解码零延迟、不依赖容器 seek，
    而且本机 ffmpeg 没有 libvorbis。想要 ogg 省体积就装带 libvorbis 的 ffmpeg 再加 --ogg。
    """
    import shutil
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, os.path.basename(wav_path))
    shutil.copyfile(wav_path, out)
    return out


def print_registry(ext: str) -> None:
    base = "res://assets/audio/sfx"
    print("\n--- 粘进 AudioManager._load_audio_assets() 的注册代码 ---")
    for name, variants in SFX.items():
        paths = ", ".join('"%s/%s_%d.%s"' % (base, name, i, ext) for i in range(1, len(variants) + 1))
        print('\t_register_sfx("%s", [%s])' % (name, paths))


def main() -> int:
    ap = argparse.ArgumentParser(description="烘焙修仙幸存者音效")
    ap.add_argument("--only", help="只烘这些 key，逗号分隔")
    ap.add_argument("--ogg", action="store_true", help="转成 ogg 进包体（需要 ffmpeg 有 libvorbis）")
    ap.add_argument("--list", action="store_true", help="列出全部 key 与变体数")
    args = ap.parse_args()

    if args.list:
        for name, variants in SFX.items():
            print("%-20s %d 变体" % (name, len(variants)))
        print("合计 %d 个 key / %d 个文件" % (len(SFX), sum(len(v) for v in SFX.values())))
        return 0

    keys = list(SFX.keys())
    if args.only:
        keys = [k.strip() for k in args.only.split(",") if k.strip()]
        unknown = [k for k in keys if k not in SFX]
        if unknown:
            print("未知 key: %s（--list 看全部）" % unknown, file=sys.stderr)
            return 2

    use_ogg = args.ogg and have_vorbis()
    if args.ogg and not use_ogg:
        print("（本机 ffmpeg 没有 libvorbis，退回 wav）", file=sys.stderr)

    os.makedirs(RAW_DIR, exist_ok=True)
    total_kb = 0.0
    for name in keys:
        for path, secs, gain in render(name, SFX[name]):
            kb = os.path.getsize(path) / 1024.0
            line = "✓ %-22s %.2fs  %6.1f KB (raw)  归一 ×%.2f" % (os.path.basename(path), secs, kb, gain)
            if use_ogg:
                placed = to_ogg(path)
                ext = "ogg"
            else:
                placed = to_wav_asset(path)
                ext = "wav"
            pkb = os.path.getsize(placed) / 1024.0
            total_kb += pkb
            line += " → %6.1f KB (%s)" % (pkb, ext)
            print(line)
    print("\n音效共 %.0f KB → %s" % (total_kb, OUT_DIR))
    print_registry(ext if keys else "wav")
    return 0


if __name__ == "__main__":
    sys.exit(main())
