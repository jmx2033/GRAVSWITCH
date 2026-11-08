"""生成正式第 6 关（level_5.tscn）：综合关，把改重力机制全用上。

## 设计原则（负责人 11/8 要求）
1. **不能只是元素堆叠**：每一段都要考一个机制，段与段之间要能接上。
2. **每种元素要重复出现**，不是各出现一次就走。
3. 第 6 关是**综合关**：改重力 + 多种方向的重力区 + 移动平台 + 尖刺阵，
   全部机制串联一遍。

## 关键数值（实测）
- 满速起跳最大水平距离：**5.25 格**
- 跳跃高度：**3.02 格**
- 1g 滞空 0.656s；2g（朝下加重区）滞空 0.328s
- **朝左 + 朝右 重力区相消 = 失重**（实测失重中玩家无法移动，机制不可用，禁用）

## 五段结构

```
A 段  x=1..3    「阶梯」：两级台阶，每级一排尖刺，必须靠改重力做长跳。
                 考：空中改重力 + 距离判断。
                 元素：尖刺 x6、矿石 x3、碎石 x2、水晶柱 x2

B 段  x=4..7    「右墙」：右侧有一面朝右的重力区墙，
                 玩家跳进墙里会被推向右墙，可以借它"挂"在墙上横移。
                 考：重力区把重力改成水平方向。
                 元素：尖刺 x4、水晶柱 x3、矿石 x3、碎石 x2

C 段  x=8..11   「天井」：朝上重力区，玩家跳进去被吸到天花板横穿。
                 考：改重力 + 天花板路线。
                 元素：尖刺 x4、水晶柱 x4、矿石 x3、碎石 x3

D 段  x=12..15  「夹缝」：左右两侧各一个朝内推的重力区（不能相消），
                 玩家在中缝里靠改重力穿过去。
                 考：同时感受两个重力区 + 改重力。
                 元素：尖刺 x6、水晶柱 x4、矿石 x4、碎石 x4

E 段  x=16..18  「冲刺」：靠移动平台摆渡过最后的坑，落地就是终点。
                 考：改重力 + 移动平台 + 精准落点。
                 元素：移动平台 x2、旗 x2、尖刺 x4、矿石 x2、碎石 x2
"""

import base64
import struct

BRICK, WALL = (4, 0), (3, 0)
W, H = 20, 11

ART = {
    'crystal': ('uid://6of1qploqh23', 'res://Art/tiles/spr_crystal.png'),
    'flag': ('uid://vqyiexh02203', 'res://Art/tiles/spr_flag.png'),
    'ore': ('uid://c6a8rchwxnnj4', 'res://Art/tiles/spr_ore.png'),
    'rocks': ('uid://ddxwcjlydoly4', 'res://Art/tiles/spr_rocks.png'),
}

# 重力区方向枚举（gravity_zone.gd）：0=上 1=右 2=下 3=左
DIR_UP, DIR_RIGHT, DIR_DOWN, DIR_LEFT = 0, 1, 2, 3


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
    terrain, spikes, sprites = [], [], []
    zones, platforms = [], []
    uid = [200000]

    def nid():
        uid[0] += 1
        return uid[0]

    def sprite(kind, gx, gy, ox=0.0, oy=0.0):
        sprites.append({
            'kind': kind,
            'pos': (gx * 32 + 16 + ox, gy * 32 + 16 + oy),
            'uid': nid(),
        })

    # ================= 地形 =================
    # A 段：两级台阶
    for x in range(1, 3):
        terrain.append((x, 9, *BRICK))
    for x in range(3, 5):
        terrain.append((x, 8, *BRICK))
    # B 段：地面（y=8）
    for x in range(5, 8):
        terrain.append((x, 8, *BRICK))
    # C 段：天井地面
    for x in range(8, 12):
        terrain.append((x, 8, *BRICK))
    # D 段：夹缝地面
    for x in range(12, 16):
        terrain.append((x, 8, *BRICK))
    # E 段：终点地面
    for x in range(17, 19):
        terrain.append((x, 8, *BRICK))
    # E 段起跳台阶
    terrain.append((16, 8, *BRICK))

    # 外框
    for x in range(W):
        terrain.append((x, 0, *WALL))
    for y in range(H):
        terrain.append((0, y, *WALL))
        terrain.append((W - 1, y, *WALL))

    # B 段的右墙（竖直的一列，给朝右重力区当载体）
    for y in [3, 4, 5, 6, 7]:
        terrain.append((8, y, *WALL))
    # C 段天井的右壁
    for y in [5, 6, 7]:
        terrain.append((12, y, *WALL))
    # D 段走廊的左壁（给朝左重力区当载体）
    for y in [3, 4]:
        terrain.append((12, y, *WALL))

    # ================= A 段：阶梯 =================
    for x in [1, 2]:
        spikes.append((x, 8))
    for x in [3, 4]:
        spikes.append((x, 7))
    sprite('ore', 1, 8)
    sprite('ore', 2, 8)
    sprite('ore', 3, 7)
    sprite('rocks', 4, 7)
    sprite('crystal', 2, 8, oy=-8)
    sprite('crystal', 4, 7, oy=-8)

    # ================= B 段：右墙重力区 =================
    # 朝右的重力区（x=7..8, y=3..7），玩家跳进去被推向右墙
    zones.append({
        'name': 'ZoneRight', 'pos': (7 * 32, 3 * 32),
        'size': (1, 5), 'dir': DIR_RIGHT, 'uid': nid(),
    })
    for x in [5, 6, 7]:
        spikes.append((x, 7))
    sprite('ore', 5, 7)
    sprite('ore', 6, 7)
    sprite('ore', 7, 7)
    sprite('rocks', 5, 7)
    sprite('rocks', 7, 7)
    sprite('crystal', 5, 7, oy=-8)
    sprite('crystal', 6, 7, oy=-8)
    sprite('crystal', 7, 7, oy=-8)

    # ================= C 段：天井（朝上） =================
    zones.append({
        'name': 'ZoneUp', 'pos': (8 * 32, 1 * 32),
        'size': (4, 3), 'dir': DIR_UP, 'uid': nid(),
    })
    for x in [8, 9, 10, 11]:
        spikes.append((x, 7))
    for x in [8, 9, 10, 11]:
        sprite('crystal', x, 1, oy=-6)
    sprite('ore', 8, 1, oy=4)
    sprite('ore', 10, 1, oy=4)
    sprite('ore', 11, 1, oy=4)
    sprite('rocks', 9, 1, oy=6)
    sprite('rocks', 10, 1, oy=6)

    # ================= D 段：加速走廊 =================
    # **不能做「两侧朝内推」的夹缝**：朝右 1g + 朝左 1g 相消 = 失重，
    # 而实测失重中玩家完全无法移动（速度恒 0、位置不变），机制不可用。
    # 改成**单个朝左的区**：玩家进区后重力被推向左墙，
    # 必须靠改重力（空中按 →）才能挣脱继续往右走。
    zones.append({
        'name': 'ZonePushLeft', 'pos': (13 * 32, 3 * 32),
        'size': (3, 5), 'dir': DIR_LEFT, 'uid': nid(),
    })
    for x in [12, 13, 14, 15]:
        spikes.append((x, 7))
    sprite('ore', 12, 7)
    sprite('ore', 13, 7)
    sprite('ore', 14, 7)
    sprite('ore', 15, 7)
    sprite('rocks', 12, 7)
    sprite('rocks', 13, 7)
    sprite('rocks', 14, 7)
    sprite('rocks', 15, 7)
    sprite('crystal', 12, 7, oy=-8)
    sprite('crystal', 13, 7, oy=-8)
    sprite('crystal', 14, 7, oy=-8)
    sprite('crystal', 15, 7, oy=-8)

    # ================= E 段：冲刺 =================
    for x in [16]:
        spikes.append((x, 7))
    # 两个移动平台在坑里摆渡
    platforms.append({'pos': (16 * 32 + 16, 7 * 32 + 16), 'uid': nid()})
    platforms.append({'pos': (17 * 32 + 16, 7 * 32 + 16), 'uid': nid()})
    sprite('flag', 17, 7, oy=-14)
    sprite('flag', 18, 7, oy=-14)
    sprite('ore', 17, 7)
    sprite('ore', 18, 7)
    sprite('rocks', 17, 7)
    sprite('rocks', 18, 7)

    # 尖刺在 build 里就分配好 uid（render 里拿不到 nid）
    spike_list = [{'pos': sp, 'uid': nid()} for sp in dedup(spikes)]

    return {
        'terrain': dedup(terrain),
        'spikes': spike_list,
        'sprites': sprites,
        'zones': zones,
        'platforms': platforms,
        'spawn': (48, 8 * 32 + 16),
        'goal': (18 * 32, 7 * 32 + 16),
    }


def render(d):
    L = []
    A = L.append
    A('[gd_scene format=4 uid="uid://df2dbifp0v45d"]')
    A('')
    A('[ext_resource type="TileSet" uid="uid://dpphdnueb46dl" path="res://Scenes/tileset_cave.tres" id="1_tiles"]')
    A('[ext_resource type="PackedScene" uid="uid://b11hj8ncr5db5" path="res://Scenes/player.tscn" id="2_player"]')
    A('[ext_resource type="PackedScene" uid="uid://u7jbmkf7gqyg" path="res://Scenes/tile/gravity_zone.tscn" id="3_zone"]')
    A('[ext_resource type="PackedScene" uid="uid://bcc0efq3yy18v" path="res://Scenes/tile/level_goal.tscn" id="4_goal"]')
    A('[ext_resource type="Texture2D" uid="uid://rmo458s4itmk" path="res://Art/bg/bg_cave.png" id="6_bg"]')
    A('[ext_resource type="PackedScene" uid="uid://cnnosxglxyvx3" path="res://Scenes/tile/spike.tscn" id="7_spike"]')
    A('[ext_resource type="PackedScene" uid="uid://bqom0xe37pje3" path="res://Scenes/moving_platform.tscn" id="8_plat"]')
    for key in ['crystal', 'flag', 'ore', 'rocks']:
        uidv, path = ART[key]
        A('[ext_resource type="Texture2D" uid="%s" path="%s" id="9_%s"]' % (uidv, path, key))
    A('')
    A('[node name="Level5" type="Node2D" unique_id=1738421000]')
    A('')
    A('[node name="Background" type="Sprite2D" parent="." unique_id=290255064]')
    A('z_index = -100')
    A('texture_filter = 1')
    A('position = Vector2(320, 180)')
    A('scale = Vector2(1.125, 1.125)')
    A('texture = ExtResource("6_bg")')
    A('')
    A('[node name="Terrain" type="TileMapLayer" parent="." unique_id=1644837531]')
    A('tile_map_data = PackedByteArray("%s")' % encode(d['terrain']))
    A('tile_set = ExtResource("1_tiles")')
    A('')
    A('[node name="Deco" type="TileMapLayer" parent="." unique_id=1096113299]')
    A('tile_map_data = PackedByteArray("")')
    A('tile_set = ExtResource("1_tiles")')
    A('collision_enabled = false')
    A('')
    A('[node name="Zones" type="Node2D" parent="." unique_id=903087701]')
    for z in d['zones']:
        A('')
        A('[node name="%s" parent="Zones" unique_id=%d instance=ExtResource("3_zone")]' % (
            z['name'], z['uid']))
        A('position = Vector2(%d, %d)' % z['pos'])
        A('size_in_tiles = Vector2i(%d, %d)' % z['size'])
        A('direction = %d' % z['dir'])
    for i, p in enumerate(d['platforms']):
        A('')
        A('[node name="MovingPlatform%d" parent="." unique_id=%d instance=ExtResource("8_plat")]' % (
            i + 1, p['uid']))
        A('position = Vector2(%d, %d)' % p['pos'])
    for s in d['sprites']:
        A('')
        A('[node name="Spr%s%d" type="Sprite2D" parent="." unique_id=%d]' % (
            s['kind'].capitalize(), s['uid'], s['uid']))
        A('position = Vector2(%d, %d)' % s['pos'])
        A('texture = ExtResource("9_%s")' % s['kind'])
    A('')
    A('[node name="Spikes" type="Node2D" parent="." unique_id=976300751]')
    for i, sp in enumerate(d['spikes']):
        A('')
        A('[node name="Spike%d" parent="Spikes" unique_id=%d instance=ExtResource("7_spike")]' % (
            i + 1, sp['uid']))
        A('position = Vector2(%d, %d)' % (sp['pos'][0] * 32 + 16, sp['pos'][1] * 32 + 16))
    A('')
    A('[node name="LevelGoal" parent="." unique_id=833299112 instance=ExtResource("4_goal")]')
    A('position = Vector2(%d, %d)' % d['goal'])
    A('')
    A('[node name="Spawn" type="Marker2D" parent="." unique_id=1976273592]')
    A('position = Vector2(%d, %d)' % d['spawn'])
    A('')
    A('[node name="Player" parent="." unique_id=969211626 instance=ExtResource("2_player")]')
    A('')
    return '\n'.join(L)


if __name__ == '__main__':
    d = build()
    open('Scenes/level/normal/level_5.tscn', 'w',
         encoding='utf-8', newline='\n').write(render(d))
    print('地形 %d / 尖刺 %d / 精灵 %d / 重力区 %d / 平台 %d' % (
        len(d['terrain']), len(d['spikes']), len(d['sprites']),
        len(d['zones']), len(d['platforms'])))
    from collections import Counter
    print('精灵种类:', dict(Counter(s['kind'] for s in d['sprites'])))
    print('重力区:', [(z['name'], z['pos'][0]//32, z['pos'][1]//32, z['size'], z['dir']) for z in d['zones']])
