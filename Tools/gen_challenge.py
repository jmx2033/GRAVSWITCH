"""生成挑战关地形数据。

格坐标 <-> 像素：格 (x,y) 的像素中心是 (x*32+16, y*32+16)。
Marker2D 用像素中心；地面砖在 y=10 行。
"""
import base64, struct, sys

def encode(cells):
    body = b''
    for (x, y, ax, ay) in cells:
        body += struct.pack('<hhhhhh', x, y, 0, ax, ay, 0)
    return base64.b64encode(b'\x00\x00' + body).decode()

def dedup(cells):
    seen, out = set(), []
    for c in cells:
        if c[:2] in seen: continue
        seen.add(c[:2]); out.append(c)
    return out

BRICK, FLOOR, WALL = (4,0), (0,0), (3,0)

# ================= 关 2「重力弹球」 =================
# 核心：整片开阔空间，四周墙面都是不同方向的重力区。
# 玩家必须在空中连续改重力，在墙间反弹，最终到达顶部终点。
def build_bounce():
    W, H = 20, 11
    c = []
    # 外框：顶行 y=0 与底行 y=10 用砖，左右墙 x=0/19 用砖
    for x in range(W):
        c.append((x, 0, *WALL))
        c.append((x, H-1, *BRICK))
    for y in range(H):
        c.append((0, y, *WALL))
        c.append((W-1, y, *WALL))

    # 内部障碍：几块悬空平台，给玩家中途落脚（限制"一次滞空只能改一次"）
    # 左侧平台 y=7，x=2..4
    for x in [2, 3, 4]:
        c.append((x, 7, *FLOOR))
    # 右侧平台 y=5，x=15..17
    for x in [15, 16, 17]:
        c.append((x, 5, *FLOOR))
    # 中间上方平台 y=3，x=8..11
    for x in [8, 9, 10, 11]:
        c.append((x, 3, *FLOOR))
    # 左下角一小块，出生点下方
    for x in [1, 2, 3]:
        c.append((x, 9, *BRICK))
    # 终点在顶部中间，下方留空
    return c

# ================= 关 3「镜像」 =================
# 核心：左右完全对称，但重力方向相反。
# 玩家必须利用"同一时间只能改一次重力"的规则，在对称结构中找路径。
def build_mirror():
    W, H = 20, 11
    c = []
    for x in range(W):
        c.append((x, 0, *WALL))
        c.append((x, H-1, *BRICK))
    for y in range(H):
        c.append((0, y, *WALL))
        c.append((W-1, y, *WALL))

    # 中央一根竖直柱子（x=9,10 从 y=2 到 y=8）
    for y in range(2, 9):
        c.append((9, y, *BRICK))
        c.append((10, y, *BRICK))

    # 左右对称的阶梯平台（各三层）
    for y, xs in [(8, [2,3]), (6, [2,3,4]), (4, [1,2,3])]:
        for x in xs:
            c.append((x, y, *FLOOR))
            c.append((W-1-x, y, *FLOOR))

    # 出生点下方地板
    for x in [1, 2, 3]:
        c.append((x, 9, *BRICK))
    # 终点在顶部中央柱子上方
    return c

if __name__ == '__main__':
    for name, fn in [('challenge_1', build_bounce), ('challenge_2', build_mirror)]:
        cells = dedup(fn())
        open('_tmp_%s.txt' % name, 'w').write(encode(cells))
        print('%s: %d 格' % (name, len(cells)))
