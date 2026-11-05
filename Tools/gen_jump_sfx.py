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
              dur: float = 0.15, tau: float = 0.028) -> np.ndarray:
    rng = np.random.default_rng(seed)
    N = int(FS * dur)
    t = np.arange(N) / FS

    # 1) 指数衰减包络：打击后干净收尾，不留拖音
    env = np.exp(-t / tau)

    # 2) 音高基本平直、轻微上挑一丁点，"哒"的本嗓保持高频
    #    不做大下滑（下滑=低频重锤感）
    freq = f_pitch * (1.0 + 0.06 * np.exp(-t / 0.02))
    phase = 2 * np.pi * np.cumsum(freq) / FS

    # 3) 谐波主体：规整的谐波泛音 = 干净、亮、脆；不谐泛音会发闷
    #    二次谐波轻，避免太尖；无低频基波累积
    sig = (np.sin(phase)
           + 0.28 * np.sin(2 * phase + 0.5)
           + 0.10 * np.sin(3 * phase + 1.0))

    # 4) 起音轻轻一记"叩"：高频噪声瞬态，幅度轻、衰减极快
    #    它给出敲击起始感，又不带中低频撞击
    noise = rng.standard_normal(N) * np.exp(-t / 0.002) * 0.30

    out = (sig + noise) * env

    # 归一化后整体压低，轻而清晰，不抢戏
    out = out / (np.max(np.abs(out)) + 1e-9)
    out = out * 0.82

    return out


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
    variants = [
        ("sfx_jump_1.wav", make_jump(1500.0, seed=11)),
        ("sfx_jump_2.wav", make_jump(1250.0, seed=37)),
        ("sfx_jump_3.wav", make_jump(1400.0, seed=73)),
    ]
    for name, data in variants:
        path = os.path.normpath(os.path.join(OUT_DIR, name))
        write_wav(path, data)
        print(f"{name}: {len(data)/FS:.3f}s written -> {os.path.abspath(path)}")


if __name__ == "__main__":
    main()