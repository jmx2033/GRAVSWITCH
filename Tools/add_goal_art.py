"""给各关卡的终点加 Sprite2D 贴图（拱门）。

## 为什么需要这个脚本
终点场景 `level_goal.tscn` 是**所有关卡共享**的，只做触发判定（Area2D）。
之前把 `spr_arch.png` 硬绑在那个共享场景里，等于**强制所有关卡的终点
都显示同一张图** —— 想换图就得改共享场景，会影响全部关卡。

## 现在的做法
`level_goal.tscn` 保持纯触发器，图形由**各关卡自己**用一个 Sprite2D 摆在终点旁边。
这样每关想用拱门、想用别的图、想完全不放，都由该关自己决定。

## 跑法
    python Tools/add_goal_art.py
"""

import re
from pathlib import Path

# 拱门贴图
ARCH_UID = 'uid://dgy7cjbu1dbs2'
ARCH_PATH = 'res://Art/tiles/spr_arch.png'
# 拱门 28x40，中心对齐；往上偏 4px 让它底部贴着终点格
ARCH_OFFSET = (16.0, -4.0)

LEVELS = [
    'Scenes/level/normal/level_0.tscn',
    'Scenes/level/normal/level_1.tscn',
    'Scenes/level/normal/level_2.tscn',
    'Scenes/level/normal/level_3.tscn',
    'Scenes/level/normal/level_4.tscn',
    'Scenes/challenge_0.tscn',
    'Scenes/challenge_1.tscn',
    'Scenes/challenge_2.tscn',
    'Scenes/challenge_3.tscn',
]


def add_goal_art(path: str) -> bool:
    p = Path(path)
    t = p.read_text(encoding='utf-8')

    # 已经加过就跳过
    if 'GoalArch' in t:
        print('  %-42s 已有，跳过' % path)
        return False

    # 1) ext_resource：找一个没被用的 id
    used = set(re.findall(r'id="([^"]+)"', t))
    res_id = '20_arch'
    while res_id in used:
        res_id = '%02d_arch' % (int(res_id[:2]) + 1)

    # 插到最后一个 ext_resource 之后
    lines = t.split('\n')
    last_ext = max(i for i, l in enumerate(lines) if l.startswith('[ext_resource'))
    lines.insert(last_ext + 1,
                 '[ext_resource type="Texture2D" uid="%s" path="%s" id="%s"]'
                 % (ARCH_UID, ARCH_PATH, res_id))
    t = '\n'.join(lines)

    # 2) 找终点节点，在它后面插 Sprite2D
    m = re.search(
        r'(\[node name="LevelGoal[^\]]*\]\nposition = Vector2\((\d+), (\d+)\)\n)',
        t)
    if not m:
        print('  %-42s 没找到终点节点，跳过' % path)
        return False
    gx, gy = int(m.group(2)), int(m.group(3))
    # 拱门摆在终点格子的中心，底部对齐格底
    sx = gx + ARCH_OFFSET[0]
    sy = gy + ARCH_OFFSET[1]

    sprite = (
        '\n[node name="GoalArch" type="Sprite2D" parent="."]\n'
        'position = Vector2(%d, %d)\n'
        'texture = ExtResource("%s")\n'
        % (sx, sy, res_id)
    )
    t = t[:m.end()] + sprite + t[m.end():]

    p.write_text(t, encoding='utf-8', newline='\n')
    print('  %-42s 已加终点贴图 @ (%d, %d)' % (path, sx, sy))
    return True


if __name__ == '__main__':
    print('给各关卡终点加拱门贴图：')
    n = 0
    for lv in LEVELS:
        if Path(lv).exists() and add_goal_art(lv):
            n += 1
    print()
    print('共处理 %d 个关卡' % n)
