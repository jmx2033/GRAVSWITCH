"""
生成 GRAVSWITCH 的跳跃音效：清脆的小石子"哒"。
设计目标（用户三个要求）：
1. 短  ：总时长 ~0.15s
2. 干  ：无混响、无尾音 —— 指数衰减到尾部彻底无声，硬截断不拖尾
3. 不抢戏：整体峰值轻、干净，不刺耳不闷

音色（针对"像电铃""重拳发闷"两轮反馈）：
- 干净的高频"哒"：主音高基本平直、偏高、谐波规整，没有频率猛跌的"重锤"感
- 砍掉中低频撞击体感：基频不往下坠、压低低频分量，轻而不是砸
- 起音有一记清脆的"叩"噪点做敲击起始，但幅度轻
"""
# 文件名必须带 sfx_ 前缀（CI 的音频命名规则）：sfx_jump_1.wav 这种。
import wave
import numpy as np
import os

FS = 48000
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Audio", "sfx")


def make_jump(f_pitch: float, seed: int,
              dur: float = 0.24, tau: float = 0.06) -> np.ndarray:
    rng = np.random.default_rng(seed)
    N = int(FS * dur)
    t = np.arange(N) / FS

    # 1) 指数衰减包络：改长、改慢，声音圆润、带一点"闷"的余韵。
    #    tau=0.06 衰减到 ~1/10 要 ~0.14s，尾音柔、不刺耳、仍无混响
    env = np.exp(-t / tau)

    # 2) 音高基本平直，"哒"落在更低的中低频（~0.75kHz）
    freq = f_pitch * (1.0 + 0.03 * np.exp(-t / 0.03))
    phase = 2 * np.pi * np.cumsum(freq) / FS

    # 3) 谐波主体：闷 = 低频分量更重、高次泛音更少。
    #    只留基频 + 0.5× 低频泛音（加厚）+ 微量 1.5×；无 2×/3×
    sig = (np.sin(phase)
           + 0.42 * np.sin(0.5 * phase + 0.2)
           + 0.08 * np.sin(1.5 * phase + 0.6))

    # 4) 起音极轻的"叩"：高频噪点维持最低，保证不尖
    noise = rng.standard_normal(N) * np.exp(-t / 0.003) * 0.08

    out = (sig + noise) * env

    # 归一化后整体压低，清晰不抢戏
    out = out / (np.max(np.abs(out)) + 1e-9)
    out = out * 0.85

    return out


def make_land(seed: int,
              dur: float = 0.28, tau: float = 0.07,
              f_pitch: float = 520.0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    N = int(FS * dur)
    t = np.arange(N) / FS

    # 1) 指数衰减包络：比跳略长略慢，带"重量落定"的沉闷，无混响
    env = np.exp(-t / tau)

    # 2) 基频比跳更低（~520Hz），落地的"砰"更有分量；仍平直不下坠
    freq = f_pitch * (1.0 + 0.03 * np.exp(-t / 0.03))
    phase = 2 * np.pi * np.cumsum(freq) / FS

    # 3) 谐波主体：落地比跳更闷——低频 0.5× 分量更重，无高次泛音
    sig = (np.sin(phase)
           + 0.50 * np.sin(0.5 * phase + 0.2)
           + 0.06 * np.sin(1.5 * phase + 0.6))

    # 4) 起音一记极轻的"叩"：实体硕大，高频噪点几乎可忽略
    noise = rng.standard_normal(N) * np.exp(-t / 0.004) * 0.06

    out = (sig + noise) * env

    # 归一化后整体压低，清晰不抢戏
    out = out / (np.max(np.abs(out)) + 1e-9)
    out = out * 0.85

    return out


def jade_note(f_pitch: float, dur: float,
              amp: float = 1.0, tau_scale: float = 1.0,
              pitch_rise: float = 0.0, rise_time: float = 0.030,
              partials: list = None, fade_ms: float = 2.0) -> np.ndarray:
    """一个"玉音"音符：非整数泛音 + 每泛音独立衰减，可整体缩放衰减时间。

    - f_pitch: 基音频率
    - pitch_rise: 前 rise_time 内生高的比例（跳跃音"轻轻上扬"），0 表示不升
    - tau_scale: 衰减时间整体缩放（大块玉石衰减慢 → 大于 1）
    - 复用走音已校准的泛音组，保证所有音效是同一件"乐器"
    """
    N = int(FS * dur)
    t = np.arange(N) / FS

    # 音高：可选在前 rise_time 内轻微上扬（向上 = 离开地面）
    if pitch_rise > 0.0:
        freq = f_pitch * (1.0 + pitch_rise * np.clip(t / rise_time, 0.0, 1.0))
        phase = 2 * np.pi * np.cumsum(freq) / FS
    else:
        phase = 2 * np.pi * f_pitch * t

    if partials is None:
        partials = [
            (1.00, 1.00, 0.050),
            (2.20, 0.42, 0.036),
            (3.70, 0.22, 0.028),
            (6.10, 0.10, 0.018),
        ]

    sig = np.zeros(N)
    for ratio, p_amp, p_tau in partials:
        # 每泛音独立衰减：玉质共鸣的核心听觉特征
        sig += p_amp * np.sin(ratio * phase) * np.exp(-t / (p_tau * tau_scale))

    # 极短的玻璃质起音"叩"
    sig += 0.14 * np.sin(5.0 * phase) * np.exp(-t / (0.0040 * tau_scale))

    # 瞬时起音斜坡
    sig *= np.clip(t / 0.0010, 0.0, 1.0)

    # 收尾归零：默认 2ms；衰减尚未散尽时（如落地音）由调用方给更长淡出，
    # 避免在还有残余音量的位置硬剪出"咔"声
    fade_n = int(FS * fade_ms / 1000.0)
    if fade_n > 0 and N > fade_n:
        sig[-fade_n:] *= np.linspace(1.0, 0.0, fade_n)

    peak = np.max(np.abs(sig)) + 1e-9
    return sig * (amp / peak)


def make_walk_jade(f_pitch: float,
                   dur: float = 0.25) -> np.ndarray:
    """玉珠敲抛光石面的清脆叩击声（玉 / 水晶质感，略带东方韵）。

    规格（按用户新时代提示词）：
    - 主音 f_pitch（420/450/480/510Hz），"clean glassy tick"，中频
    - 瞬时起音，像一颗小玉珠敲在光滑石面上
    - "gentle natural resonant decay that fades out on its own"：
      自然共鸣的关键是【每个泛音各自衰减】，高频散得快、低频留得久，
      不是一个统一包络硬套所有谐波（那听起来就是"合成音"而不是"乐器"）
    - 只用自然共鸣：无房间/大厅混响、无人工空间感
    - 纯、美、像小玉珠风铃；不刺耳、无金属刮擦、无白噪、无 sub-bass
    - 总长 0.25s，避免尾部残留；中等峰值 -4dB，不削波
    """
    N = int(FS * dur)
    t = np.arange(N) / FS

    base = 2 * np.pi * f_pitch

    # 泛音结构：玉石/石材共鸣的泛音【稀疏且非整数倍】，
    # 采用近似磬（qìng）这类东方打击乐的非谐比例。
    partials = [
        (1.00, 1.00, 0.050),   # 基音：留得最久
        (2.20, 0.42, 0.036),   # 第二泛音：玻璃亮感
        (3.70, 0.22, 0.028),   # 第三泛音：清脆的"叮"
        (6.10, 0.10, 0.018),   # 极轻的高"叮"，散得最快
    ]

    sig = np.zeros(N)
    for ratio, amp, tau_p in partials:
        # 每个泛音独立衰减：这是"自然共鸣"与合成音的分界线
        sig += amp * np.sin(base * ratio * t) * np.exp(-t / tau_p)

    # 2) 极短的玻璃质"叩"瞬态：用极短的高频衰减包，不铺白噪宽带。
    #    只叠在所有泛音同一相位上，免得引入刮擦感
    tick = np.sin(base * 5.0 * t) * np.exp(-t / 0.0040) * 0.14
    sig += tick

    # 3) 瞬时起音：1ms 斜坡，保证"responsive"而不是渐入
    atk = np.clip(t / 0.0010, 0.0, 1.0)
    sig *= atk

    # 4) 自然收尾：0.25s 处已近乎无声，末尾 2ms 线性归零防止任何残跳
    fade_n = int(FS * 0.002)
    if fade_n > 0 and N > fade_n:
        sig[-fade_n:] *= np.linspace(1.0, 0.0, fade_n)

    # 5) 归一化到中等峰值（-4dB），不吵、不削波
    sig = sig / (np.max(np.abs(sig)) + 1e-9)
    sig = sig * 0.63

    return sig


def make_jump_jade(f_pitch: float = 1000.0, dur: float = 0.22) -> np.ndarray:
    """跳跃：一片玉片被敲响并抬起，1000Hz 晶体"叮"，前 30ms 轻微上扬。"""
    # 末端仍有约 -40dB 余量，给 25ms 淡出，避免硬剪出细微"咔"
    return jade_note(f_pitch, dur, amp=0.63, pitch_rise=0.08, rise_time=0.030,
                     fade_ms=25.0)


def make_land_jade(f_pitch: float = 600.0, dur: float = 0.28) -> np.ndarray:
    """落地：更厚实的玉板/小玉磬，低频 600Hz，比跳跃更有身体与重量。"""
    # tau_scale 略大 → 大块玉石衰减更慢、余韵更足；低频泛音权重抬高给"落定"的分量
    # 衰减在 280ms 处仍有约 -39dB 残余，所以给 40ms 长淡出，避免硬剪出"咔"
    heavy = [
        (1.00, 1.00, 0.075),
        (2.10, 0.30, 0.050),
        (3.40, 0.14, 0.036),
        (5.80, 0.06, 0.022),
    ]
    return jade_note(f_pitch, dur, amp=0.63, tau_scale=1.0,
                     partials=heavy, fade_ms=40.0)


def make_flip_jade(f_hi: float = 850.0, f_lo: float = 600.0,
                   dur: float = 0.30) -> np.ndarray:
    """翻转：两颗玉珠先后敲下，850Hz → 600Hz 的下落二音，与跳跃的上升相区分。"""
    N = int(FS * dur)
    out = np.zeros(N)

    def one(f: float, start_s: float, amp: float, dur_s: float) -> np.ndarray:
        seg = jade_note(f, dur_s, amp=amp)
        i = int(FS * start_s)
        n = min(len(seg), N - i)
        out[i:i + n] += seg[:n]

    # 两声并列接续，第二声略重，形成"往下坠"的手势
    one(f_hi, 0.000, 0.55, 0.16)
    one(f_lo, 0.080, 0.63, 0.22)

    # 归一化到 -4dB；尾部仍有约 -40dB，给 30ms 长淡出而非硬剪
    out = out / (np.max(np.abs(out)) + 1e-9)
    out = out * 0.63
    fade_n = int(FS * 0.030)
    out[-fade_n:] *= np.linspace(1.0, 0.0, fade_n)
    return out


def make_die_jade(f_base: float = 700.0, dur: float = 0.70) -> np.ndarray:
    """死亡：玉片碎裂——先一声 700Hz 的敲击，随后多块小碎片同时散出并渐次落定。"""
    N = int(FS * dur)
    out = np.zeros(N)

    def add(seg: np.ndarray, start_s: float) -> None:
        i = int(FS * start_s)
        n = min(len(seg), N - i)
        if i < N and n > 0:
            out[i:i + n] += seg[:n]

    # 初击：清亮的一记
    add(jade_note(f_base, 0.35, amp=0.80), 0.0)

    # 碎片：各自略不同的音高与衰减，分散在 30~200ms 之间，像是"散开"
    shards = [
        (0.030, 1180.0, 0.30, 0.30),
        (0.055,  960.0, 0.26, 0.26),
        (0.082, 1420.0, 0.22, 0.22),
        (0.110,  820.0, 0.20, 0.34),
        (0.145, 1650.0, 0.14, 0.18),
        (0.185,  640.0, 0.16, 0.38),
    ]
    for start, f, amp, d in shards:
        add(jade_note(f, d, amp=amp), start)

    out = out / (np.max(np.abs(out)) + 1e-9)
    out = out * 0.63
    out[-int(FS * 0.004):] *= np.linspace(1.0, 0.0, int(FS * 0.004))
    return out


def make_win_jade(dur: float = 0.80) -> np.ndarray:
    """通关：五声音阶（宫商角徵羽）上行的玉磬短琶音，收在一个稍作停留的高音。"""
    N = int(FS * dur)
    out = np.zeros(N)
    # 五声音阶（以 700Hz 为宫，比率按宫商角徵羽的非整数玉质泛音习惯仍用纯音高）
    notes = [700.0, 816.0, 940.0, 1052.0, 1219.0]
    times = [0.00, 0.10, 0.20, 0.30, 0.42]
    amps = [0.42, 0.46, 0.50, 0.54, 0.62]
    durs = [0.28, 0.28, 0.28, 0.30, 0.38]

    for f, st, a, d in zip(notes, times, amps, durs):
        seg = jade_note(f, d, amp=a)
        i = int(FS * st)
        n = min(len(seg), N - i)
        out[i:i + n] += seg[:n]

    out = out / (np.max(np.abs(out)) + 1e-9)
    out = out * 0.63
    out[-int(FS * 0.006):] *= np.linspace(1.0, 0.0, int(FS * 0.006))
    return out


def make_ui_hover(dur: float = 0.07) -> np.ndarray:
    """按钮悬停：一声极轻的高频玉片"叮"，只提示"焦点移到这里"。

    比跳跃音更高、更轻、更短——悬停触发很频繁，做响会烦。
    """
    # 1600Hz 高于跳跃音（1000Hz），音量压到 0.32
    return jade_note(1600.0, dur, amp=0.32, fade_ms=8.0)


def make_ui_press(dur: float = 0.12) -> np.ndarray:
    """按钮按下：比悬停低一点的确认音，有一点"按下去"的落感。

    频率低于悬停音（980 vs 1600），形成"高→低"的按下手势；
    音量略大但仍比游戏内音效轻。
    """
    return jade_note(980.0, dur, amp=0.45, fade_ms=10.0)


def write_wav(path: str, mono: np.ndarray) -> None:
    data16 = (np.clip(mono, -1, 1) * 32767).astype(np.int16)
    # 保持与原文件一致的双声道（左右相同），位深 16bit
    stereo = np.column_stack([data16, data16])
    with wave.open(path, "w") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(FS)
        w.writeframes(stereo.tobytes())


def main() -> None:
    # 全套玉音音效：走 4 条 + 跳 / 落 / 翻转 / 死亡 / 通关。
    variants = [
        ("sfx_walk_1.wav", make_walk_jade(420.0)),
        ("sfx_walk_2.wav", make_walk_jade(450.0)),
        ("sfx_walk_3.wav", make_walk_jade(480.0)),
        ("sfx_walk_4.wav", make_walk_jade(510.0)),
        ("sfx_jump_1.wav", make_jump_jade(1000.0, 0.22)),
        ("sfx_land.wav", make_land_jade(600.0, 0.28)),
        ("sfx_flip.wav", make_flip_jade(850.0, 600.0, 0.30)),
        ("sfx_die.wav", make_die_jade(700.0, 0.70)),
        ("sfx_win.wav", make_win_jade(0.80)),
        # UI：按钮悬停与按下（主菜单用，11/7 加）
        ("sfx_ui_hover.wav", make_ui_hover(0.07)),
        ("sfx_ui_press.wav", make_ui_press(0.12)),
    ]
    for name, data in variants:
        path = os.path.normpath(os.path.join(OUT_DIR, name))
        write_wav(path, data)
        print(f"{name}: {len(data)/FS:.3f}s written -> {os.path.abspath(path)}")


if __name__ == "__main__":
    main()