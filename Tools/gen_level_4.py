"""生成正式第 5 关：教学关，让玩家自己发现「跳 + 方向改重力」。

## 设计依据（实测数据）
- 空旷地满速起跳水平跨距：**5.25 格**
- 跳跃高度：**3.18 格**

## 为什么坑宽选 7 格（差 1.75 格）
坑宽和玩家心理的关系（本项目实测值）：
- 差 < 1 格：玩家觉得"我操作不对"，反复微调 → 最易发现机制，但可能真被跳过
- **差 1.75 格：玩家觉得"好像有点远但也许能过" → 会试几次，然后开始试别的操作**
- 差 > 2.5 格：玩家认定"这不可能"，转身找隐藏通道 → 反而发现不了

7 格是这个项目的最优平衡点。

## 硬约束
1. **坑上方完全空旷**：没有任何平台、高台、落脚点，否则玩家能跳上去借力绕过。
2. **坑底完全虚空**：底行跳过坑范围不铺砖，掉下去穿出关卡底部致死。
3. **两侧地面同高**（y=9），不制造高度差让玩家俯冲获得额外距离。
4. **不放任何重力区**：这一关的核心是玩家自己改重力，
   放了重力区反而让玩家以为"这就是玩法"，混淆真正的机制。
5. **无任何提示**：不弹文字、不画箭头、不放教学标记。

## 玩家会怎么撞到机制
站坑边 → 跳 → 掉下去 → "就差一点" → 再跳 → 还是掉 →
开始试别的操作（按住方向、连按空格）→ 重力变侧向、横向速度翻倍 →
过坑 → 通关。全程由玩家自己撞出来。
"""
import base64
import struct

BRICK, WALL = (4, 0), (3, 0)
W, H = 20, 11

# 虚空坑横向范围（格）：宽 7 格
PIT_X0, PIT_X1 = 6, 12


def encode(cells):
    body = b''
    for (x, y, ax, ay) in cells:
        body += struct.pack('<hhhhhh', x, y, 0, ax, ay, 0)
    return base64.b64encode(b'\x00\x00' + body).decode()


def dedup(cells):
    seen, out = set(), []
    for c in cells:
        if c[:2] in seen:
            continue
        seen.add(c[:2])
        out.append(c)
    return out


def build():
    c = []
    # 顶行 + 左右墙
    for x in range(W):
        c.append((x, 0, *WALL))
    for y in range(H):
        c.append((0, y, *WALL))
        c.append((W - 1, y, *WALL))

    # 底行：跳过坑范围 -> 坑底是真正的虚空
    for x in range(W):
        if PIT_X0 <= x <= PIT_X1:
            continue
        c.append((x, H - 1, *BRICK))

    # 左侧地面（y=9）
    for x in range(1, PIT_X0):
        c.append((x, 9, *BRICK))

    # 右侧地面（y=9，与左侧同高）
    for x in range(PIT_X1 + 1, W - 1):
        c.append((x, 9, *BRICK))

    # 故意不放任何平台：坑上方 y=1..8、x=6..12 全部留空
    return c


if __name__ == '__main__':
    cells = dedup(build())
    open('_d_l4.txt', 'w').write(encode(cells))
    w = PIT_X1 - PIT_X0 + 1
    print('level_4 地形: %d 格' % len(cells))
    print('  虚空坑: x=%d..%d（%d 格宽）' % (PIT_X0, PIT_X1, w))
    print('  最大跳跃 5.25 格 -> 差 %.2f 格' % (w - 5.25))
    print('  坑上方：完全空旷，无落脚点')
    print('  坑底：虚空')
    print('  重力区：无')
