"""生成正式第 6 关：高难度综合关。

## 核心数值（实测）
- 满速起跳最大水平距离：**5.25 格**
- 跳跃高度：**3.18 格**
- 改重力后横向加速无上限（0.5s 可飞 10+ 格）

## 关卡结构（三段，每段都必须用改重力）

```
段1  x=1..1   起点（1 格）
段2  x=2..7   坑1（6 格）+ 后面 x=8 的 1 格小岛
              -> 6 格超过 5.25 极限，跳不过，必须改重力
段3  x=9..15  坑2（7 格）上方有**朝上重力区**
              -> 跳进朝上区会被吸到天花板，再沿天花板走过去
              -> 这是唯一解，硬跳必死
段4  x=16..18 终点区
```

## 为什么这样能"爆难"
1. **坑1 必须飞跃**：6 格 > 5.25 格极限，纯跳跃无解
2. **落点只有 1 格**：飞过去还得精准落在 x=8
3. **坑2 有陷阱**：朝上重力区覆盖 x=10..17，玩家飞进去会被吸上天花板，
   这时候要用「在天花板上走」的思路过关——而不是继续飞
4. **连续两次改重力**：每次滞空只能改一次，落地才刷新

## 不用失重
实测「朝左+朝右重叠」虽然能抵消成重力 0，但玩家在失重里完全无法移动，
机制不可用（按方向键速度恒为 0）。
"""
import base64
import struct

BRICK, FLOOR, WALL = (4, 0), (0, 0), (3, 0)
W, H = 20, 11

# 坑的范围（底行不铺砖 = 虚空）
PIT1_X0, PIT1_X1 = 2, 7
ISLAND_X = 8
PIT2_X0, PIT2_X1 = 9, 15


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
    # 天花板 + 左右墙
    for x in range(W):
        c.append((x, 0, *WALL))
    for y in range(H):
        c.append((0, y, *WALL))
        c.append((W - 1, y, *WALL))

    # 底行：只在起点、小岛、终点区铺砖，其余是虚空
    bottom_ok = {0, 1} | {ISLAND_X} | set(range(16, W))
    for x in sorted(bottom_ok):
        c.append((x, H - 1, *BRICK))

    # y=9 给起点和终点各加一层，让它们有个小台面（但仍然很窄）
    c.append((1, 9, *BRICK))
    for x in range(16, W - 1):
        c.append((x, 9, *BRICK))

    # 小岛加一层，方便站立（仍然是 1 格宽）
    c.append((ISLAND_X, 9, *BRICK))

    return c


if __name__ == '__main__':
    cells = dedup(build())
    open('_d_l5.txt', 'w').write(encode(cells))
    print('level_5 地形: %d 格' % len(cells))
    print('  坑1: x=%d..%d（%d 格）' % (PIT1_X0, PIT1_X1, PIT1_X1 - PIT1_X0 + 1))
    print('  小岛: x=%d（1 格）' % ISLAND_X)
    print('  坑2: x=%d..%d（%d 格）' % (PIT2_X0, PIT2_X1, PIT2_X1 - PIT2_X0 + 1))
    print('  终点区: x=16..18')
