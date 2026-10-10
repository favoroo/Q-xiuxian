#!/usr/bin/env python3
"""bake_sfx.py —— 渡个劫 (Dao Trial) 音效离线烘焙（纯标准库，零模型依赖）

移植自 dudu-cocos/tools/bake-audio.ts 的合成内核，用数学而不是录音生成音效：
    tone  = 振荡器(sine/square/sawtooth/triangle + 频率指数/线性斜坡) × 指数包络 [可选 lowpass]
    noise = 白噪声(确定性填充) × RBJ 双二阶(lowpass/highpass/bandpass，截止频率可扫) × 指数包络
每条音色渲染成单声道 16-bit WAV；有 ffmpeg 时再转 ogg(vorbis) 进包体。

为什么不用 media-gen：那个技能的边界表里写明「音效 SFX ❌ 无 SFX 模型」，
只有 BGM(lyria) 和语音(TTS)。所以 BGM 走生成，短音效走本地烘焙。

用法：
    python3 tools/bake_sfx.py                 # 全量烘到 assets_raw/sfx/，并把 wav 放进 assets/audio/sfx/
    python3 tools/bake_sfx.py --ogg           # 转 ogg 进包体（需本机 ffmpeg 带 libvorbis，否则自动退回 wav）
    python3 tools/bake_sfx.py --only enemy_death,impact_blade
    python3 tools/bake_sfx.py --list
    python3 tools/bake_sfx.py --cand                        # 烘 A/B 候选（挑音色）→ assets/audio/sfx_cand/
    python3 tools/bake_sfx.py --cand --only impact_blade,whoosh_light
    python3 tools/bake_sfx.py --list-cand

短音效默认留 wav：解码零延迟、不依赖容器 seek（与 dudu-cocos 的结论一致）。
产物约定（与 AGENTS.md 一致）：assets_raw/ 是源、assets/ 是产物，勿手改产物。
脚本最后一律打印可直接粘进 AudioManager._load_audio_assets() 的注册代码。
⚠ 烘完必须跑一次编辑器导入（$G --headless --path . --editor --quit），
  否则新 wav 没有 .import，播出来是静默哑的；AudioManager.missing_paths() 为空才算落地。
⚠ 候选（--cand）不注册：挑剩的落选候选若进注册表就是一堆哑 key，会污染 sfx_keys() 与判据。
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
# 候选（A/B 挑音色用）单独一套目录：候选永远不进 AudioManager 注册表，
# 否则挑剩的落选候选会变成一堆哑 key，污染 sfx_keys() 轮播与 UnitRunner 判据。
CAND_RAW_DIR = os.path.join(ROOT, "assets_raw", "sfx_cand")
CAND_OUT_DIR = os.path.join(ROOT, "assets", "audio", "sfx_cand")

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


def fm_tone(buf, *, f0=440.0, f1=None, t0=0.0, dur=0.15, peak=0.25,
            ratio=2.0, idx0=2.0, idx1=0.15, atk=0.004, lp=0.0) -> None:
    """FM 合成：载波 × 调制器（调制比 ratio），调制指数从 idx0 衰到 idx1——
    音头亮、尾音纯，出金属铃/玉磬/符光这类「有芯子」的质感，单振荡器 tone 给不了。"""
    if f1 is None:
        f1 = f0
    start = int(round(t0 * SR))
    length = int(round(dur * SR))
    atk = min(atk, dur * 0.3)
    bq = Biquad() if lp else None
    if bq:
        bq.set("lowpass", lp, 0.8)
    c_phase = 0.0
    m_phase = 0.0
    for i in range(length):
        t = i / SR
        f = _expramp(f0, f1, t, dur)
        idx = _expramp(idx0, idx1, t, dur)
        c_phase += 2.0 * math.pi * max(20.0, f) / SR
        m_phase += 2.0 * math.pi * max(20.0, f * ratio) / SR
        if t < atk:
            env = _expramp(0.0001, peak, t, max(atk, 1e-4))
        else:
            env = _expramp(peak, 0.0001, t - atk, dur - atk)
        s = math.sin(c_phase + idx * math.sin(m_phase)) * env
        if bq:
            s = bq.process(s)
        pos = start + i
        if 0 <= pos < len(buf):
            buf[pos] += s


def shimmer(buf, *, f0=1600.0, f1=None, t0=0.0, dur=0.35, peak=0.08,
            detune=0.007, wobble=6.5, wdepth=0.4) -> None:
    """双失谐正弦 + 缓慢幅度颤：灵光/仙气/魂火消散的那层「飘」。
    两个正弦差拍出若隐若现的浮动感，叠在打击层上面当仙气尾巴。"""
    if f1 is None:
        f1 = f0
    start = int(round(t0 * SR))
    length = int(round(dur * SR))
    p1 = 0.0
    p2 = 0.0
    for i in range(length):
        t = i / SR
        f = _expramp(f0, f1, t, dur)
        p1 += 2.0 * math.pi * f / SR
        p2 += 2.0 * math.pi * f * (1.0 + detune) / SR
        if t < 0.01:
            env = _expramp(0.0001, peak, t, 0.01)
        else:
            env = _expramp(peak, 0.0001, t - 0.01, dur - 0.01)
        wob = 1.0 - wdepth * (0.5 + 0.5 * math.sin(2.0 * math.pi * wobble * t))
        s = 0.5 * (math.sin(p1) + math.sin(p2)) * env * wob
        pos = start + i
        if 0 <= pos < len(buf):
            buf[pos] += s


def space(buf, *, delay=0.09, fb=0.35, mix=0.20, hp=320.0) -> None:
    """整条 buffer 过一道反馈延迟当「早期反射」——短音效自带空间尾巴，
    播放端不用挂总线混响（安卓省性能）。湿声道高通去闷，只留空气感。"""
    n = len(buf)
    d = int(max(1, round(delay * SR)))
    bq = Biquad()
    bq.set("highpass", hp, 0.7)
    hist = [0.0] * n
    for i in range(n):
        v = buf[i]
        if i >= d:
            v += fb * hist[i - d]
        hist[i] = v
    for i in range(n):
        buf[i] += mix * bq.process(hist[i])


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
    # 命中反馈分层：普通入肉斩裂、暴击低频撕裂（Sub-Bass）、重器钝击
    "enemy_hit": [
        # 变体 1：利刃割肉撕裂瞬态 + 扎实低频身体撞击微下潜
        lambda b: (tone(b, wtype="sine", f0=115, f1=46, dur=0.08, peak=0.42),
                   noise(b, dur=0.07, peak=0.32, ftype="bandpass", f0=1800, f1=480, q=1.2),
                   tone(b, wtype="triangle", f0=1400, f1=360, dur=0.035, peak=0.18)),
        # 变体 2：沉闷切肉入骨，低频更深
        lambda b: (tone(b, wtype="sine", f0=105, f1=40, dur=0.09, peak=0.45),
                   noise(b, dur=0.08, peak=0.30, ftype="lowpass", f0=2200, f1=420, q=1.1),
                   tone(b, wtype="sawtooth", f0=880, f1=260, dur=0.04, peak=0.16, lp=800)),
        # 变体 3：快速清脆斩切，瞬态突出
        lambda b: (tone(b, wtype="sine", f0=125, f1=50, dur=0.075, peak=0.40),
                   noise(b, dur=0.065, peak=0.35, ftype="bandpass", f0=2400, f1=650, q=1.4),
                   tone(b, wtype="triangle", f0=1600, f1=420, dur=0.03, peak=0.20)),
    ],
    "enemy_hit_crit": [
        # 暴击 1：刺目金属锐鸣 + 骨裂撕裂 + 140Hz->30Hz 超低频深潜（Sub-Bass Thud）
        lambda b: (tone(b, wtype="sine", f0=140, f1=28, dur=0.22, peak=0.55),
                   noise(b, dur=0.12, peak=0.36, ftype="bandpass", f0=2600, f1=420, q=1.5),
                   tone(b, wtype="sawtooth", f0=1800, f1=320, dur=0.06, peak=0.25, lp=1200)),
        # 暴击 2：重锤砸裂，低频下潜更深厚重
        lambda b: (tone(b, wtype="sine", f0=130, f1=26, dur=0.24, peak=0.58),
                   noise(b, dur=0.14, peak=0.38, ftype="lowpass", f0=3200, f1=360, q=1.3),
                   tone(b, wtype="triangle", f0=1500, f1=280, dur=0.05, peak=0.22)),
        # 暴击 3：极速贯穿破甲，瞬态强劲
        lambda b: (tone(b, wtype="sine", f0=150, f1=32, dur=0.20, peak=0.52),
                   noise(b, dur=0.11, peak=0.35, ftype="bandpass", f0=3000, f1=500, q=1.6),
                   tone(b, wtype="sawtooth", f0=2200, f1=450, dur=0.055, peak=0.24, lp=1400)),
    ],
    "enemy_hit_heavy": [
        # 重击 1：钝器/大印轰然砸落，深沉低频震荡
        lambda b: (tone(b, wtype="sine", f0=88, f1=24, dur=0.25, peak=0.58),
                   noise(b, dur=0.16, peak=0.34, ftype="lowpass", f0=850, f1=150, q=1.6)),
        # 重击 2：沉闷地裂微震
        lambda b: (tone(b, wtype="triangle", f0=98, f1=26, dur=0.22, peak=0.54),
                   noise(b, dur=0.15, peak=0.32, ftype="bandpass", f0=1100, f1=180, q=1.3)),
        # 重击 3：沉重击退冲击音
        lambda b: (tone(b, wtype="sine", f0=80, f1=22, dur=0.26, peak=0.56),
                   noise(b, dur=0.18, peak=0.30, ftype="lowpass", f0=750, f1=130, q=1.5)),
    ],
    # 玩家受伤：闷、肉、不金属 —— 与敌人挨打音色明确区分（低频塌陷 + 皮肉钝响）
    "player_hurt": [
        lambda b: (tone(b, wtype="sine", f0=140, f1=52, dur=0.13, peak=0.38),
                   noise(b, dur=0.09, peak=0.22, ftype="lowpass", f0=760, f1=240, q=1.0),
                   tone(b, wtype="triangle", f0=210, f1=90, dur=0.07, peak=0.14)),
        lambda b: (tone(b, wtype="sine", f0=120, f1=46, dur=0.15, peak=0.40),
                   noise(b, dur=0.11, peak=0.20, ftype="lowpass", f0=620, f1=200, q=1.1),
                   tone(b, wtype="sawtooth", f0=330, f1=140, dur=0.05, peak=0.10, lp=700)),
        lambda b: (tone(b, wtype="sine", f0=155, f1=58, dur=0.12, peak=0.36),
                   noise(b, dur=0.08, peak=0.24, ftype="lowpass", f0=880, f1=260, q=0.9),
                   tone(b, wtype="triangle", f0=240, f1=105, dur=0.06, peak=0.12)),
    ],
    # 妖物死灭：扑灭一声 + 一缕魂光（shimmer 尾巴是「灵散」的仙气层）
    "enemy_death": [
        lambda b: (tone(b, wtype="sine", f0=250, f1=72, dur=0.10, peak=0.22),
                   noise(b, dur=0.07, peak=0.13, ftype="bandpass", f0=1500, f1=450, q=0.9),
                   shimmer(b, f0=2300, f1=3400, dur=0.17, peak=0.035)),
        lambda b: (tone(b, wtype="triangle", f0=410, f1=140, dur=0.09, peak=0.18),
                   noise(b, dur=0.06, peak=0.10, ftype="highpass", f0=2500, f1=1000),
                   shimmer(b, f0=2700, f1=3900, dur=0.15, peak=0.030)),
        lambda b: (tone(b, wtype="sine", f0=215, f1=62, dur=0.13, peak=0.24),
                   noise(b, dur=0.09, peak=0.11, ftype="lowpass", f0=950, f1=260, q=1.0),
                   shimmer(b, f0=1900, f1=2800, dur=0.20, peak=0.032)),
    ],
    "enemy_death_elite": [
        # 大妖殒落：低频塌陷 + 咆哮衰减 + 魂光升散
        lambda b: (tone(b, wtype="sine", f0=150, f1=30, dur=0.34, peak=0.30),
                   tone(b, wtype="sawtooth", f0=195, f1=44, dur=0.28, peak=0.17, lp=1100),
                   noise(b, dur=0.11, peak=0.17, ftype="highpass", f0=3000, f1=800, q=0.9),
                   shimmer(b, f0=1400, f1=2200, dur=0.30, peak=0.045)),
        lambda b: (tone(b, wtype="sine", f0=135, f1=34, dur=0.38, peak=0.28),
                   tone(b, wtype="sawtooth", f0=165, f1=40, dur=0.30, peak=0.15, lp=950),
                   noise(b, dur=0.26, peak=0.16, ftype="lowpass", f0=2800, f1=170, q=1.4),
                   shimmer(b, f0=1200, f1=1900, dur=0.34, peak=0.040)),
    ],
    # 攻击音按流派分开：近战破空 / 飞剑离手（替换西厨 knifeSlice）/ 符箓离指 / 落雷 / 扇风
    "sword_swing": [
        lambda b: (noise(b, dur=0.11, peak=0.16, ftype="bandpass", f0=760, f1=3000, q=0.8),
                   tone(b, wtype="triangle", f0=340, f1=140, dur=0.06, peak=0.05)),
        lambda b: (noise(b, dur=0.09, peak=0.14, ftype="bandpass", f0=1150, f1=2700, q=0.9),
                   tone(b, wtype="triangle", f0=280, f1=155, dur=0.05, peak=0.045)),
    ],
    "blade_shoot": [
        lambda b: (noise(b, dur=0.10, peak=0.17, ftype="bandpass", f0=900, f1=3400, q=0.9),
                   fm_tone(b, f0=1900, f1=1150, dur=0.06, peak=0.07, ratio=2.4, idx0=1.8),
                   tone(b, wtype="sine", f0=300, f1=130, dur=0.045, peak=0.08)),
        lambda b: (noise(b, dur=0.09, peak=0.15, ftype="bandpass", f0=1250, f1=3100, q=1.0),
                   fm_tone(b, f0=2350, f1=1400, dur=0.05, peak=0.06, ratio=2.2, idx0=1.6),
                   tone(b, wtype="sine", f0=340, f1=150, dur=0.04, peak=0.07)),
    ],
    "talisman_throw": [
        lambda b: (noise(b, dur=0.05, peak=0.11, ftype="highpass", f0=2800, f1=1900),
                   noise(b, dur=0.045, peak=0.09, ftype="bandpass", f0=1500, f1=900, q=1.4, t0=0.045),
                   fm_tone(b, f0=1350, f1=1550, dur=0.05, peak=0.06, ratio=3.0, idx0=1.4)),
        lambda b: (noise(b, dur=0.055, peak=0.10, ftype="highpass", f0=3100, f1=2100),
                   fm_tone(b, f0=1550, f1=1800, dur=0.05, peak=0.065, ratio=2.7, idx0=1.6),
                   tone(b, wtype="sine", f0=760, f1=1050, dur=0.045, peak=0.045)),
    ],
    "thunder_strike": [
        lambda b: (noise(b, dur=0.05, peak=0.24, ftype="highpass", f0=4200, f1=1400, q=0.8),
                   tone(b, wtype="sine", f0=150, f1=40, dur=0.26, peak=0.28),
                   noise(b, dur=0.30, peak=0.17, ftype="lowpass", f0=2200, f1=160, q=1.0)),
        lambda b: (noise(b, dur=0.07, peak=0.20, ftype="bandpass", f0=3200, f1=760, q=1.1),
                   tone(b, wtype="triangle", f0=185, f1=55, dur=0.19, peak=0.20),
                   noise(b, dur=0.24, peak=0.14, ftype="lowpass", f0=1700, f1=150, q=1.1)),
    ],
    "fan_gust": [
        lambda b: (noise(b, dur=0.24, peak=0.16, ftype="bandpass", f0=520, f1=1950, q=0.6),
                   noise(b, dur=0.26, peak=0.09, ftype="lowpass", f0=1400, f1=320, q=0.8)),
        lambda b: (noise(b, dur=0.20, peak=0.14, ftype="bandpass", f0=820, f1=2250, q=0.7),
                   tone(b, wtype="sine", f0=225, f1=150, dur=0.16, peak=0.05)),
    ],
    # 暖金法球触体：不谐和度低的不金属「钟」——替换冷硬的 metalClick
    "orb_hit": [
        lambda b: (noise(b, dur=0.02, peak=0.09, ftype="bandpass", f0=2200, f1=1600, q=1.6),
                   fm_tone(b, f0=523, dur=0.22, peak=0.20, ratio=2.76, idx0=3.2, idx1=0.25)),
        lambda b: (noise(b, dur=0.02, peak=0.08, ftype="bandpass", f0=2600, f1=1900, q=1.6),
                   fm_tone(b, f0=660, dur=0.20, peak=0.19, ratio=3.01, idx0=2.8, idx1=0.22)),
    ],
    # 灵石清脆晶响：双叮 + 高频灵光（引擎端保留连拾升调，清脆爽感翻倍）——替换赌场硬币
    "gem_pickup": [
        lambda b: (fm_tone(b, f0=1568, dur=0.13, peak=0.17, ratio=3.5, idx0=1.3, idx1=0.1),
                   fm_tone(b, f0=2093, dur=0.11, peak=0.11, ratio=3.2, idx0=1.1, t0=0.04),
                   shimmer(b, f0=3200, f1=3900, dur=0.15, peak=0.035)),
        lambda b: (fm_tone(b, f0=1760, dur=0.12, peak=0.16, ratio=3.3, idx0=1.2, idx1=0.1),
                   fm_tone(b, f0=2217, dur=0.11, peak=0.10, ratio=3.6, idx0=1.0, t0=0.045),
                   shimmer(b, f0=3500, f1=4300, dur=0.14, peak=0.030)),
    ],
    # 藏宝匣：木裂受击 / 开匣宝光（木腔敲击 + FM 铃琶音 + 灵光）
    "chest_hit": [
        lambda b: (noise(b, dur=0.045, peak=0.24, ftype="bandpass", f0=950, f1=520, q=1.4),
                   tone(b, wtype="triangle", f0=265, f1=195, dur=0.05, peak=0.20),
                   noise(b, dur=0.018, peak=0.10, ftype="highpass", f0=3300)),
        lambda b: (noise(b, dur=0.05, peak=0.22, ftype="bandpass", f0=1150, f1=600, q=1.5),
                   tone(b, wtype="triangle", f0=300, f1=220, dur=0.045, peak=0.19),
                   noise(b, dur=0.018, peak=0.09, ftype="highpass", f0=3600)),
    ],
    "chest_open": [
        lambda b: (noise(b, dur=0.06, peak=0.20, ftype="bandpass", f0=900, f1=420, q=1.3),
                   fm_tone(b, f0=784, dur=0.22, peak=0.12, ratio=2.2, idx0=2.0, t0=0.05),
                   fm_tone(b, f0=1046, dur=0.24, peak=0.11, ratio=2.5, idx0=1.8, t0=0.11),
                   fm_tone(b, f0=1568, dur=0.30, peak=0.10, ratio=2.8, idx0=1.5, t0=0.17),
                   shimmer(b, f0=2100, f1=3200, dur=0.38, peak=0.05, t0=0.14),
                   space(b, delay=0.11, fb=0.4, mix=0.18)),
        lambda b: (noise(b, dur=0.06, peak=0.19, ftype="bandpass", f0=1050, f1=480, q=1.4),
                   fm_tone(b, f0=698, dur=0.21, peak=0.11, ratio=2.3, idx0=1.9, t0=0.05),
                   fm_tone(b, f0=932, dur=0.23, peak=0.10, ratio=2.6, idx0=1.7, t0=0.10),
                   fm_tone(b, f0=1397, dur=0.28, peak=0.095, ratio=2.9, idx0=1.4, t0=0.16),
                   shimmer(b, f0=1900, f1=2900, dur=0.36, peak=0.045, t0=0.13),
                   space(b, delay=0.10, fb=0.38, mix=0.17)),
    ],
    # 商店与背包
    "shop_buy": [
        lambda b: (tone(b, wtype="triangle", f0=330, f1=310, dur=0.05, peak=0.15),
                   fm_tone(b, f0=1245, dur=0.14, peak=0.12, ratio=3.7, idx0=1.5, t0=0.05)),
        lambda b: (tone(b, wtype="triangle", f0=392, f1=370, dur=0.05, peak=0.14),
                   fm_tone(b, f0=1480, dur=0.13, peak=0.11, ratio=3.4, idx0=1.4, t0=0.05),
                   noise(b, dur=0.06, peak=0.04, ftype="highpass", f0=3400, f1=2200, t0=0.02)),
    ],
    "shop_reroll": [
        lambda b: (noise(b, dur=0.04, peak=0.10, ftype="bandpass", f0=1300, f1=1700, q=1.8),
                   noise(b, dur=0.04, peak=0.11, ftype="bandpass", f0=1800, f1=2400, q=1.8, t0=0.055),
                   noise(b, dur=0.05, peak=0.12, ftype="bandpass", f0=2400, f1=3100, q=1.8, t0=0.115)),
        lambda b: (tone(b, wtype="square", f0=540, f1=780, dur=0.045, peak=0.06, lp=2000),
                   tone(b, wtype="square", f0=640, f1=920, dur=0.045, peak=0.06, lp=2200, t0=0.06),
                   tone(b, wtype="square", f0=780, f1=1120, dur=0.06, peak=0.07, lp=2400, t0=0.12)),
    ],
    "shop_lock": [
        lambda b: (noise(b, dur=0.02, peak=0.09, ftype="highpass", f0=2900),
                   tone(b, wtype="square", f0=520, f1=430, dur=0.055, peak=0.07, lp=1600)),
    ],
    "sell": [
        lambda b: (tone(b, wtype="triangle", f0=1180, f1=880, dur=0.09, peak=0.10),
                   noise(b, dur=0.10, peak=0.07, ftype="lowpass", f0=1300, f1=420, q=0.9, t0=0.05)),
    ],
    "equip": [
        lambda b: (fm_tone(b, f0=880, dur=0.18, peak=0.13, ratio=2.0, idx0=2.2, idx1=0.3),
                   tone(b, wtype="triangle", f0=250, f1=180, dur=0.05, peak=0.11)),
        lambda b: (fm_tone(b, f0=740, dur=0.16, peak=0.12, ratio=2.3, idx0=2.0, idx1=0.3),
                   noise(b, dur=0.05, peak=0.05, ftype="highpass", f0=3200, t0=0.04)),
    ],
    "unequip": [
        lambda b: (tone(b, wtype="triangle", f0=720, f1=470, dur=0.09, peak=0.09),
                   noise(b, dur=0.06, peak=0.04, ftype="lowpass", f0=1000, f1=380, q=0.9, t0=0.02)),
    ],
    "merge_success": [
        lambda b: (_arp(b, [523, 659, 784, 1047], t_step=0.075, dur=0.24, peak=0.14, echo=0.04),
                   fm_tone(b, f0=2093, dur=0.24, peak=0.07, ratio=2.0, idx0=1.2, t0=0.24),
                   space(b, delay=0.10, fb=0.35, mix=0.16)),
        lambda b: (_arp(b, [659, 784, 988, 1319], t_step=0.07, dur=0.22, peak=0.13, echo=0.035),
                   noise(b, dur=0.12, peak=0.05, ftype="highpass", f0=3600, f1=2000, t0=0.2),
                   space(b, delay=0.11, fb=0.32, mix=0.15)),
    ],
    # UI：玉叩质感，去街机方波味
    "ui_click": [
        lambda b: (fm_tone(b, f0=1250, dur=0.035, peak=0.08, ratio=3.2, idx0=1.1, idx1=0.05),
                   noise(b, dur=0.012, peak=0.045, ftype="highpass", f0=5000)),
        lambda b: (fm_tone(b, f0=1400, dur=0.032, peak=0.075, ratio=3.0, idx0=1.0, idx1=0.05),
                   noise(b, dur=0.012, peak=0.040, ftype="highpass", f0=5200)),
        lambda b: (fm_tone(b, f0=1120, dur=0.038, peak=0.08, ratio=3.4, idx0=1.2, idx1=0.05),
                   noise(b, dur=0.012, peak=0.045, ftype="highpass", f0=4800)),
    ],
    # 应允/选定确认：上行两连音 + 微光 —— 从 level_up 手里接管 4 处选人/选武器滥用
    "ui_confirm": [
        lambda b: (tone(b, wtype="triangle", f0=660, dur=0.07, peak=0.11),
                   tone(b, wtype="triangle", f0=990, dur=0.10, peak=0.11, t0=0.07),
                   shimmer(b, f0=1980, f1=2400, dur=0.16, peak=0.03, t0=0.07)),
        lambda b: (tone(b, wtype="triangle", f0=587, dur=0.07, peak=0.10),
                   tone(b, wtype="triangle", f0=880, dur=0.10, peak=0.10, t0=0.07),
                   shimmer(b, f0=1760, f1=2200, dur=0.15, peak=0.028, t0=0.07)),
    ],
    "ui_back": [
        lambda b: (tone(b, wtype="triangle", f0=520, f1=360, dur=0.075, peak=0.07),),
    ],
    "ui_error": [
        lambda b: (tone(b, wtype="sine", f0=170, f1=120, dur=0.09, peak=0.17),
                   tone(b, wtype="sine", f0=150, f1=105, dur=0.11, peak=0.15, t0=0.11),
                   tone(b, wtype="sawtooth", f0=225, f1=190, dur=0.08, peak=0.045, lp=900)),
        lambda b: (tone(b, wtype="sine", f0=185, f1=130, dur=0.08, peak=0.15),
                   tone(b, wtype="sine", f0=160, f1=112, dur=0.10, peak=0.14, t0=0.10)),
    ],
    # 悟道加点：玉磬轻叩（替换 handleCoins 硬币声，跟灵石拾取区分开）
    "stat_alloc": [
        lambda b: (fm_tone(b, f0=988, dur=0.10, peak=0.14, ratio=3.0, idx0=1.5, idx1=0.1),
                   noise(b, dur=0.014, peak=0.05, ftype="highpass", f0=4200)),
        lambda b: (fm_tone(b, f0=1109, dur=0.10, peak=0.13, ratio=3.2, idx0=1.4, idx1=0.1),
                   noise(b, dur=0.014, peak=0.045, ftype="highpass", f0=4600)),
    ],
    # 阶段与状态
    "wave_start": [
        lambda b: (tone(b, wtype="sine", f0=82, f1=40, dur=0.50, peak=0.24),
                   noise(b, dur=0.18, peak=0.15, ftype="lowpass", f0=520, f1=130, q=1.0),
                   tone(b, wtype="sawtooth", f0=220, f1=233, dur=0.38, peak=0.07, lp=950, t0=0.10),
                   tone(b, wtype="sawtooth", f0=330, f1=349, dur=0.34, peak=0.05, lp=1100, t0=0.16)),
    ],
    "wave_clear": [
        lambda b: (fm_tone(b, f0=784, dur=0.20, peak=0.13, ratio=2.0, idx0=2.0, idx1=0.2),
                   fm_tone(b, f0=988, dur=0.22, peak=0.12, ratio=2.4, idx0=1.8, idx1=0.2, t0=0.09),
                   fm_tone(b, f0=1319, dur=0.28, peak=0.12, ratio=2.8, idx0=1.6, idx1=0.15, t0=0.18),
                   shimmer(b, f0=2637, f1=3200, dur=0.35, peak=0.045, t0=0.18),
                   space(b, delay=0.11, fb=0.38, mix=0.18)),
    ],
    # 巨妖临世：双失谐锯齿拍频出「兽吼」层，不再只是低鸣
    "boss_raid": [
        lambda b: (tone(b, wtype="sine", f0=70, f1=36, dur=0.70, peak=0.26),
                   tone(b, wtype="sawtooth", f0=63, f1=59, dur=0.60, peak=0.10, lp=520, t0=0.04),
                   tone(b, wtype="sawtooth", f0=67, f1=61, dur=0.60, peak=0.10, lp=520, t0=0.04),
                   noise(b, dur=0.55, peak=0.13, ftype="lowpass", f0=750, f1=120, q=1.0),
                   space(b, delay=0.13, fb=0.4, mix=0.16)),
    ],
    "dodge": [
        lambda b: (noise(b, dur=0.09, peak=0.11, ftype="bandpass", f0=1700, f1=4200, q=1.2),
                   shimmer(b, f0=2600, f1=3300, dur=0.11, peak=0.035)),
        lambda b: (tone(b, wtype="sine", f0=1500, f1=2500, dur=0.07, peak=0.07),
                   noise(b, dur=0.06, peak=0.06, ftype="highpass", f0=3600, f1=2600)),
    ],
    "heal": [
        lambda b: (tone(b, wtype="sine", f0=587, f1=880, dur=0.20, peak=0.12),
                   shimmer(b, f0=1760, f1=2200, dur=0.24, peak=0.045, t0=0.05)),
        lambda b: (_arp(b, [587, 880], t_step=0.08, dur=0.20, peak=0.11),
                   shimmer(b, f0=1480, f1=1900, dur=0.20, peak=0.035, t0=0.10)),
    ],
    "victory": [
        lambda b: (_arp(b, [523, 659, 784, 1047, 1319], t_step=0.11, dur=0.30, peak=0.15, echo=0.04),
                   fm_tone(b, f0=2093, dur=0.34, peak=0.07, ratio=2.0, idx0=1.4, t0=0.46),
                   tone(b, wtype="sine", f0=131, dur=0.36, peak=0.10, t0=0.44),
                   space(b, delay=0.12, fb=0.42, mix=0.20)),
    ],
    "defeat": [
        lambda b: (_arp(b, [440, 349, 294, 220], t_step=0.16, dur=0.32, peak=0.13),
                   tone(b, wtype="sine", f0=98, f1=58, dur=0.50, peak=0.14, t0=0.28),
                   noise(b, dur=0.40, peak=0.05, ftype="lowpass", f0=700, f1=140, q=0.9, t0=0.35),
                   space(b, delay=0.13, fb=0.4, mix=0.18)),
    ],
    # 石碑福泽：三连 FM 铃 + 灵光洒落（替换科幻 laser1）
    "obelisk_blessing": [
        lambda b: (fm_tone(b, f0=659, dur=0.30, peak=0.13, ratio=2.0, idx0=2.2, idx1=0.2),
                   fm_tone(b, f0=880, dur=0.32, peak=0.12, ratio=2.4, idx0=2.0, idx1=0.2, t0=0.06),
                   fm_tone(b, f0=1319, dur=0.38, peak=0.11, ratio=2.8, idx0=1.8, idx1=0.15, t0=0.12),
                   shimmer(b, f0=1760, f1=2600, dur=0.45, peak=0.05, t0=0.10),
                   space(b, delay=0.12, fb=0.42, mix=0.20)),
        lambda b: (fm_tone(b, f0=587, dur=0.28, peak=0.12, ratio=2.1, idx0=2.0, idx1=0.2),
                   fm_tone(b, f0=784, dur=0.30, peak=0.11, ratio=2.5, idx0=1.9, idx1=0.2, t0=0.05),
                   fm_tone(b, f0=1175, dur=0.36, peak=0.10, ratio=2.9, idx0=1.7, idx1=0.15, t0=0.10),
                   shimmer(b, f0=1568, f1=2300, dur=0.42, peak=0.045, t0=0.09),
                   space(b, delay=0.11, fb=0.40, mix=0.18)),
    ],
    # 悟道升级：境界突破（上行双锯齿滑音 + 三音和声垫 + 灵光）——替换街机 powerUp
    "level_up": [
        lambda b: (tone(b, wtype="sawtooth", f0=196, f1=392, dur=0.50, peak=0.10, lp=1300, curve="lin"),
                   tone(b, wtype="sawtooth", f0=294, f1=589, dur=0.46, peak=0.065, lp=1500, t0=0.06, curve="lin"),
                   tone(b, wtype="sine", f0=392, dur=0.30, peak=0.12, t0=0.34),
                   tone(b, wtype="sine", f0=589, dur=0.30, peak=0.09, t0=0.34),
                   tone(b, wtype="sine", f0=784, dur=0.32, peak=0.08, t0=0.36),
                   shimmer(b, f0=1568, f1=2700, dur=0.40, peak=0.05, t0=0.36),
                   space(b, delay=0.11, fb=0.4, mix=0.18)),
        lambda b: (tone(b, wtype="sawtooth", f0=175, f1=350, dur=0.48, peak=0.10, lp=1200, curve="lin"),
                   tone(b, wtype="sawtooth", f0=262, f1=524, dur=0.44, peak=0.06, lp=1400, t0=0.06, curve="lin"),
                   tone(b, wtype="sine", f0=350, dur=0.28, peak=0.11, t0=0.32),
                   tone(b, wtype="sine", f0=524, dur=0.28, peak=0.085, t0=0.32),
                   tone(b, wtype="sine", f0=700, dur=0.30, peak=0.075, t0=0.34),
                   shimmer(b, f0=1400, f1=2500, dur=0.38, peak=0.045, t0=0.34),
                   space(b, delay=0.10, fb=0.38, mix=0.17)),
    ],
    # 随行神通：瞬步是贴身风声+顿挫，增益是上行琶音+灵光，护体是非谐和钟罩，回春是暖琶音
    "skill_dash": [
        lambda b: (noise(b, dur=0.13, peak=0.19, ftype="bandpass", f0=520, f1=3800, q=0.8),
                   tone(b, wtype="sine", f0=200, f1=95, dur=0.06, peak=0.10)),
        lambda b: (noise(b, dur=0.11, peak=0.17, ftype="highpass", f0=850, f1=3000),
                   tone(b, wtype="triangle", f0=250, f1=560, dur=0.08, peak=0.075)),
    ],
    "skill_buff": [
        lambda b: (_arp(b, [587, 784, 1175], t_step=0.055, dur=0.18, peak=0.12),
                   shimmer(b, f0=2350, f1=2900, dur=0.17, peak=0.04, t0=0.12)),
        lambda b: (_arp(b, [523, 698, 1046], t_step=0.055, dur=0.18, peak=0.11),
                   noise(b, dur=0.08, peak=0.04, ftype="highpass", f0=3800, f1=2600, t0=0.12)),
    ],
    "skill_aegis": [
        lambda b: (fm_tone(b, f0=440, dur=0.30, peak=0.13, ratio=1.41, idx0=2.6, idx1=0.3),
                   fm_tone(b, f0=1245, f1=1175, dur=0.26, peak=0.08, ratio=2.0, idx0=0.8, t0=0.02),
                   noise(b, dur=0.15, peak=0.055, ftype="highpass", f0=4000, f1=2700, t0=0.01)),
        lambda b: (fm_tone(b, f0=392, dur=0.32, peak=0.12, ratio=1.5, idx0=2.4, idx1=0.3),
                   fm_tone(b, f0=1046, f1=988, dur=0.28, peak=0.075, ratio=2.0, idx0=0.7, t0=0.03)),
    ],
    "skill_heal": [
        lambda b: (_arp(b, [523, 659, 784], t_step=0.065, dur=0.22, peak=0.11),
                   shimmer(b, f0=1568, f1=2000, dur=0.26, peak=0.04, t0=0.14)),
        lambda b: (tone(b, wtype="sine", f0=523, f1=784, dur=0.24, peak=0.12),
                   tone(b, wtype="triangle", f0=1046, f1=1568, dur=0.18, peak=0.05, t0=0.08)),
    ],
}


# ---------------- 音色候选（A/B 挑定稿用） ----------------
# 争议族先各出 2-3 版，用户在 tests/AudioGallery.tscn 里用手指连发对比挑一个。
# 结构：族名 -> [(候选字母, 目标峰值, 参数说明, 配方 lambda)]，一个候选就是一条可听的声。
# meta 会随烘焙打印出来，也抄一份进 audio_gallery.gd 的 CAND_META，屏幕与 stdout 双印，
# 这样用户报「剑要 B」时能对上具体参数，不必靠形容词沟通。
# 挑定稿后：把选中候选的配方原样搬进上面的 SFX[族名]（需要几变体就复制几份改基频），
# 删掉本表该条目，再清掉 assets{,_raw}/sfx_cand 目录。

CANDIDATES = {
    # 「剑听成棍子」的主修复点：金属锋刃入体。三版差在金属芯的亮/厚与尾巴长短。
    "impact_blade": [
        ("A", 0.42, "hp4.2k瞬态 + fm2000→1500 r2.76 idx4.2 + bp2.6k→1.2k + shimmer3.4k→4.6k",
         lambda b: (noise(b, dur=0.012, peak=0.14, ftype="highpass", f0=4200),
                    fm_tone(b, f0=2000, f1=1500, dur=0.12, peak=0.20, ratio=2.76, idx0=4.2, idx1=0.25),
                    noise(b, dur=0.05, peak=0.10, ftype="bandpass", f0=2600, f1=1200, q=1.1, t0=0.012),
                    shimmer(b, f0=3400, f1=4600, dur=0.07, peak=0.030, t0=0.05))),
        ("B", 0.42, "hp3.2k瞬态 + fm1500→1000 r2.4 idx5.0 + bp1.6k→500 + saw420→180 阻力（更低更厚）",
         lambda b: (noise(b, dur=0.014, peak=0.12, ftype="highpass", f0=3200),
                    fm_tone(b, f0=1500, f1=1000, dur=0.14, peak=0.18, ratio=2.4, idx0=5.0, idx1=0.30),
                    noise(b, dur=0.06, peak=0.13, ftype="bandpass", f0=1600, f1=500, q=1.2, t0=0.014),
                    tone(b, wtype="sawtooth", f0=420, f1=180, dur=0.05, peak=0.09, lp=900, t0=0.03))),
        ("C", 0.42, "hp4.6k瞬态 + fm2350→1800 r3.1 idx3.6 + shimmer3.2k→4.4k 长尾 + space（剑鸣余振）",
         lambda b: (noise(b, dur=0.010, peak=0.13, ftype="highpass", f0=4600),
                    fm_tone(b, f0=2350, f1=1800, dur=0.11, peak=0.17, ratio=3.1, idx0=3.6, idx1=0.18),
                    noise(b, dur=0.045, peak=0.09, ftype="bandpass", f0=3000, f1=1500, q=1.0, t0=0.010),
                    shimmer(b, f0=3200, f1=4400, dur=0.16, peak=0.050, t0=0.06),
                    space(b, delay=0.07, fb=0.30, mix=0.12))),
    ],
    # 近战前摇破空层：只给空气声，低频一律留给 impact，两层才不会叠糊。
    "whoosh_light": [
        ("A", 0.30, "bp800→3400 上扫 0.075s q0.7 + hp3.2k 8ms 刃线（快薄锐）",
         lambda b: (noise(b, dur=0.075, peak=0.18, ftype="bandpass", f0=800, f1=3400, q=0.7),
                    noise(b, dur=0.008, peak=0.08, ftype="highpass", f0=3200, t0=0.055))),
        ("B", 0.30, "bp520→2400 上扫 0.115s q0.6 + hp2.6k 30ms（厚长有质量）",
         lambda b: (noise(b, dur=0.115, peak=0.16, ftype="bandpass", f0=520, f1=2400, q=0.6),
                    noise(b, dur=0.030, peak=0.06, ftype="highpass", f0=2600, t0=0.070))),
    ],
    # 钝器命中（锤/锏/盾/尺/巨印落点）：短而干，长尾让给 enemy_hit_heavy。
    "impact_blunt": [
        ("A", 0.44, "tri180→62 + lp1.5k→280 噪 + sq320→120 lp420（砸·石钝低频头）",
         lambda b: (tone(b, wtype="triangle", f0=180, f1=62, dur=0.075, peak=0.22),
                    noise(b, dur=0.05, peak=0.18, ftype="lowpass", f0=1500, f1=280, q=1.0),
                    tone(b, wtype="square", f0=320, f1=130, dur=0.035, peak=0.09, lp=420, t0=0.012))),
        ("B", 0.44, "sine150→80 更短 + lp900→260 + bp700→300（闷·木钝少尾）",
         lambda b: (tone(b, wtype="sine", f0=150, f1=80, dur=0.055, peak=0.24),
                    noise(b, dur=0.045, peak=0.16, ftype="lowpass", f0=900, f1=260, q=1.0),
                    noise(b, dur=0.030, peak=0.08, ftype="bandpass", f0=700, f1=300, q=1.3, t0=0.02))),
    ],
    # 春雷鼓的施法与落点双层共用一族，鼓 vs 雷鼓的差别在要不要给滚雷尾。
    "drum_boom": [
        ("A", 0.55, "sine165→46 鼓体 + bp400→150 掌拍 + sine173→48 微失谐拍频（纯鼓）",
         lambda b: (tone(b, wtype="sine", f0=165, f1=46, dur=0.19, peak=0.30),
                    noise(b, dur=0.06, peak=0.14, ftype="bandpass", f0=400, f1=150, q=1.1),
                    tone(b, wtype="sine", f0=173, f1=48, dur=0.17, peak=0.10, t0=0.01))),
        ("B", 0.55, "sine150→40 + bp380→140 + lp1.8k→150 0.24s 滚雷尾（雷鼓）",
         lambda b: (tone(b, wtype="sine", f0=150, f1=40, dur=0.22, peak=0.30),
                    noise(b, dur=0.05, peak=0.13, ftype="bandpass", f0=380, f1=140, q=1.2),
                    noise(b, dur=0.24, peak=0.10, ftype="lowpass", f0=1800, f1=150, q=1.0, t0=0.04))),
    ],
}


# ---------------- 响度归一 ----------------
# 配方里的 peak 只是「相对关系」，真正决定混音是否均衡的是这一步：
# 每条音色烘完都按分类目标峰值归一化，以后改配方不会改出「一个震耳一个听不见」。

TARGET_PEAK_DEFAULT = 0.22    ## UI / 拾取 / 状态反馈
TARGET_PEAK_LOUD = 0.45       ## 死亡 / 攻击 / 阶段音头
TARGET_PEAK_IMPACT = 0.65     ## 受击入肉 / 暴击重锤（确保穿透 BGM 清晰可闻）

TARGET_PEAK = {
    "enemy_hit": 0.56,
    "enemy_hit_crit": TARGET_PEAK_IMPACT,
    "enemy_hit_heavy": 0.60,
    "player_hurt": 0.50,
    "enemy_death": TARGET_PEAK_LOUD,
    "enemy_death_elite": 0.58,
    "sword_swing": TARGET_PEAK_LOUD,
    "blade_shoot": 0.34,
    "talisman_throw": TARGET_PEAK_LOUD,
    "thunder_strike": 0.55,
    "fan_gust": TARGET_PEAK_LOUD,
    "orb_hit": 0.32,
    "gem_pickup": 0.26,
    "chest_hit": 0.34,
    "chest_open": 0.40,
    "stat_alloc": 0.24,
    "ui_confirm": 0.24,
    "merge_success": TARGET_PEAK_LOUD,
    "wave_start": TARGET_PEAK_LOUD,
    "boss_raid": 0.42,
    "victory": 0.40,
    "defeat": 0.38,
    "level_up": 0.40,
    "obelisk_blessing": 0.36,
    "dodge": 0.28,
    "heal": 0.28,
    "skill_dash": 0.32,
    "skill_buff": 0.30,
    "skill_aegis": 0.32,
    "skill_heal": 0.30,
}


def _peak(buf) -> float:
    peak = 0.0
    for v in buf:
        a = -v if v < 0.0 else v
        if a > peak:
            peak = a
    return peak


def _normalize(buf, target: float) -> float:
    """预缩放：把音色抬/压到目标峰值附近，保证后面过 tanh 限幅时不压太多。"""
    peak = _peak(buf)
    if peak < 1e-4:
        return 0.0
    gain = target / peak
    for i in range(len(buf)):
        buf[i] *= gain
    return gain


# ---------------- WAV 封装与转码 ----------------

def _bake_variant(seed_name: str, idx: int, fn, target: float, raw_dir: str, stem: str):
    """渲染一条声：重播种 → 配方 → 预归一 → tanh 软限幅 → 裁尾 → 单声道 16-bit WAV。
    限幅后还要再按 target 对齐一次峰值，这样 TARGET_PEAK 就是文件里的真实峰值，
    不同 key 之间才有可比的响度（改配方不会改出「一个震耳一个听不见」）。
    seed_name 决定确定性随机种子，stem 决定文件名。返回 (path, 秒, 预归一增益)。"""
    global _seed
    _seed = (0x2F6E2B1 + sum(ord(c) for c in seed_name) * 7919 + idx * 104729) & 0xFFFFFFFF
    buf = [0.0] * int(round(SR * RENDER_WINDOW))
    fn(buf)
    gain = _normalize(buf, target)
    # 软限幅：tanh 只压需要用的峰值，小信号几乎无损，保持音色间相对响度
    k = math.tanh(1.1)
    shaped = [math.tanh(v * 1.1) / k for v in buf]
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
    os.makedirs(raw_dir, exist_ok=True)
    path = os.path.join(raw_dir, "%s.wav" % stem)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(pcm))
    return path, keep / SR, gain


def render(name: str, variants) -> list:
    target = TARGET_PEAK.get(name, TARGET_PEAK_DEFAULT)
    return [_bake_variant(name, idx, fn, target, RAW_DIR, "%s_%d" % (name, idx))
            for idx, fn in enumerate(variants, start=1)]


def render_cands(families=None) -> list:
    """烘 A/B 候选到 sfx_cand 目录：一个候选一条声，文件名 <族>_<字母>.wav。
    与正式 key 完全隔离（不进注册表、不进 print_registry）。"""
    rows = []
    for family, cands in CANDIDATES.items():
        if families and family not in families:
            continue
        for letter, target, meta, fn in cands:
            stem = "%s_%s" % (family, letter)
            path, secs, _gain = _bake_variant(stem, 1, fn, target, CAND_RAW_DIR, stem)
            placed = to_cand_asset(path)
            rows.append((stem, secs, os.path.getsize(placed) / 1024.0, target, meta))
    write_cand_manifest(rows)
    return rows


def write_cand_manifest(rows) -> None:
    """把候选的 peak/时长/配方参数写进 sfx_cand/cand_meta.json。
    试听台读这份文件印在按钮上——参数与配方同源，不在 .gd 里手抄一份（手抄会漂移）。
    --cand --only 只更新本次烘的族，其余族的条目保留，分批判也能凑齐一整页。"""
    import json
    out = os.path.join(CAND_OUT_DIR, "cand_meta.json")
    doc = {}
    if os.path.isfile(out):
        try:
            with open(out, encoding="utf-8") as f:
                doc = json.load(f)
        except (ValueError, OSError):
            doc = {}
    for stem, secs, kb, target, meta in rows:
        family, letter = stem.rsplit("_", 1)
        doc.setdefault(family, {})
        doc[family][letter] = {"stem": stem, "dur": round(secs, 3), "kb": round(kb, 1),
                               "peak": target, "meta": meta}
    with open(out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=1, sort_keys=True)


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


def to_cand_asset(wav_path: str) -> str:
    """候选复制进 assets/audio/sfx_cand/（独立目录，正式注册表永远看不见它）。"""
    import shutil
    os.makedirs(CAND_OUT_DIR, exist_ok=True)
    out = os.path.join(CAND_OUT_DIR, os.path.basename(wav_path))
    shutil.copyfile(wav_path, out)
    return out


def print_registry() -> None:
    """打印可直接粘贴的注册代码。
    形态必须与 AudioManager._load_audio_assets() 现状一致（_sfx_paths helper），
    以前这里打的是硬编码路径数组，粘进去就与文件里的 helper 简写风格漂移。"""
    print("\n--- 粘进 AudioManager._load_audio_assets() 的注册代码 ---")
    for name, variants in SFX.items():
        print('\t_register_sfx("%s", _sfx_paths("%s", %d))' % (name, name, len(variants)))


def print_cand_table(rows) -> None:
    print("\n--- 候选清单（抄进 tests/audio_gallery.gd 的 CAND_META，屏幕与 stdout 双印）---")
    for stem, secs, kb, target, meta in rows:
        print("CAND %-24s %.3fs %6.1fKB peak=%.2f | %s" % (stem, secs, kb, target, meta))
    print("\n试听: $G --path . res://tests/AudioGallery.tscn   （不加 --headless，要真出声）")


def main() -> int:
    ap = argparse.ArgumentParser(description="烘焙渡个劫音效")
    ap.add_argument("--only", help="只烘这些 key，逗号分隔")
    ap.add_argument("--ogg", action="store_true", help="转成 ogg 进包体（需要 ffmpeg 有 libvorbis）")
    ap.add_argument("--list", action="store_true", help="列出全部 key 与变体数")
    ap.add_argument("--cand", action="store_true",
                    help="只烘 A/B 候选进 assets/audio/sfx_cand/（可与 --only 组合筛族名）")
    ap.add_argument("--list-cand", action="store_true", help="列出候选族与各候选字母")
    args = ap.parse_args()

    if args.list:
        for name, variants in SFX.items():
            print("%-20s %d 变体" % (name, len(variants)))
        print("合计 %d 个 key / %d 个文件" % (len(SFX), sum(len(v) for v in SFX.values())))
        return 0

    if args.list_cand:
        for family, cands in CANDIDATES.items():
            print("%-16s %s" % (family, " ".join(c[0] for c in cands)))
        print("合计 %d 族 / %d 个候选" % (len(CANDIDATES), sum(len(v) for v in CANDIDATES.values())))
        return 0

    # 候选分支必须排在 --only 校验之前：--only 是按正式 SFX 表校验 key 的，
    # 候选族名不在那张表里，走到下面会被当成「未知 key」直接退出。
    if args.cand:
        fams = None
        if args.only:
            fams = [k.strip() for k in args.only.split(",") if k.strip()]
            unknown = [f for f in fams if f not in CANDIDATES]
            if unknown:
                print("未知候选族: %s（--list-cand 看全部）" % unknown, file=sys.stderr)
                return 2
        print_cand_table(render_cands(fams))
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
    print_registry()
    return 0


if __name__ == "__main__":
    sys.exit(main())
