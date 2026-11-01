#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""checks.py 的自测：防止检查器本身误报（冤枉合规代码）或漏报（放过违规代码）。

CI 会先跑这个自测，再跑真实仓库检查。
本地：python Tools/ci/test_checks.py
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from checks import (  # noqa: E402
    check_gdscript, check_hygiene, check_links, check_naming, validate_subject,
)

VALID_GD = """extends CharacterBody2D

@export var jump_speed: float = 590.0
@onready var sprite: Sprite2D = $Sprite2D
@onready var coyote: float = 0.0

var gravity_scale: float = 1.0


## 每帧按当前重力方向移动。
func _physics_process(delta: float) -> void:
    var g: Vector2 = get_gravity()
    velocity += g * gravity_scale * delta
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity += up_direction * jump_speed
    move_and_slide()
"""

BAD_GD = """extends KinematicBody2D

export var speed = 200
onready var sprite = get_node("../../Sprite")

func _physics_process(delta):
    velocity.y = -620
    var other = $../../Player
"""


class TestCommitSubject(unittest.TestCase):
    def test_valid(self):
        valid = [
            "feat(level): 教学关重力区改成朝上 [P1-1]",
            "fix(level): 出界后没有触发死亡 [P0-3]",
            "art(ui): 重力区色块描边加粗到 2px [P1-3]",
            "docs(repo): 补全员必装清单",
            "chore(repo): 忽略 .godot 与导出产物",
            "refactor(player): 抽出重力方向插值 [P0-2]",
            "polish(ui): 重力区色块描边加粗到 2px [P1-3]",
            "polish(player): 翻转音效尾巴缩短 [P1-4]",
            "fix(repo): .gitignore 的 build 规则误伤模块",
            "feat(level): 教学关重力区 [P1-1] (#12)",
        ]
        for s in valid:
            self.assertEqual(validate_subject(s), [], f"不应报错：{s}")

    def test_invalid(self):
        invalid = [
            "update",
            "改了一下",
            "feat: 没有 scope",
            "feat(level): 缺 P 编号",
            "feat(level):改前没空格 [P1-1]",
            "feat(level): 最终版 [P1-1]",
            "fix(level): 修好了。 [P0-3]",
            "feat(other): scope 不在表里 [P0-1]",
            "feat(level): 短 [P1-1]",
            "polish(ui): 重力区色块描边加粗到 3px",
            "",
        ]
        for s in invalid:
            self.assertTrue(validate_subject(s), f"应当报错：{s}")

    def test_merge_and_revert_skipped(self):
        self.assertEqual(validate_subject("Merge branch 'main' into x"), [])
        self.assertEqual(validate_subject('Revert "feat(level): x [P1-1]"'), [])


class TestGDScript(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, content):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        return rel

    def test_valid_script_passes(self):
        rel = self.write("Scripts/player/player.gd", VALID_GD)
        self.assertEqual(check_gdscript(self.root, [rel]), [])

    def test_violations_all_reported(self):
        rel = self.write("Scripts/player/bad_player.gd", BAD_GD)
        messages = "\n".join(i.message for i in check_gdscript(self.root, [rel]))
        for expected in ["KinematicBody2D", "export var", "onready var", "velocity.y", "深路径"]:
            self.assertIn(expected, messages)
        self.assertEqual(len(check_gdscript(self.root, [rel])), 6)

    def test_commented_out_code_not_reported(self):
        src = (
            "extends CharacterBody2D\n\n"
            "func _ready() -> void:\n"
            "    # velocity.y = -620\n"
            "    # onready var x = $../../Y\n"
            "    pass\n"
        )
        rel = self.write("Scripts/player/ok.gd", src)
        self.assertEqual(check_gdscript(self.root, [rel]), [])

    def test_hash_inside_string_not_treated_as_comment(self):
        src = 'extends Node\n\nfunc _ready() -> void:\n    print("a#b")\n'
        rel = self.write("Scripts/core/log.gd", src)
        self.assertEqual(check_gdscript(self.root, [rel]), [])


class TestRepoRules(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def touch(self, rel, content=b"x"):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(content)
        return rel

    def test_root_build_forbidden_but_module_allowed(self):
        bad = self.touch("Build/app.exe")
        good = self.touch("Scripts/level/level_builder.gd")
        issues = check_hygiene(self.root, [bad, good])
        self.assertEqual(len(issues), 2)          # Build/ 目录 + .exe 后缀
        self.assertTrue(all(i.path == bad for i in issues))

    def test_godot_cache_dir_forbidden(self):
        bad = self.touch(".godot/imported/spr_player.png-abc.ctex")
        self.assertEqual(len(check_hygiene(self.root, [bad])), 1)

    def test_naming(self):
        final = self.touch("Art/player/spr_player_final.png")
        pascal = self.touch("Scripts/player/GravityZone.gd")
        chinese = self.touch("Art/player/玩家.png")
        good = self.touch("Art/player/spr_player.png")
        good2 = self.touch("Art/tiles/tile_cave.png")
        good3 = self.touch("Audio/sfx/sfx_jump.wav")
        good4 = self.touch("Scripts/player/gravity_zone.gd")
        good5 = self.touch("Scenes/level_0.tscn")
        paths = [final, pascal, chinese, good, good2, good3, good4, good5]
        flagged = {i.path for i in check_naming(self.root, paths)}
        self.assertEqual(flagged, {final, pascal, chinese})

    def test_uid_and_font_not_flagged(self):
        uid = self.touch("Scripts/player/player.gd.uid")
        font = self.touch("Art/fonts/SmileySans.ttf")
        self.assertEqual(check_naming(self.root, [uid, font]), [])

    def test_import_file_not_forbidden(self):
        """.import 是 Godot 每次导入生成的正常文件，必须能提交。"""
        imp = self.touch("Art/tiles/tile_cave.png.import")
        self.assertEqual(check_hygiene(self.root, [imp]), [])

    def test_docs_chinese_names_not_checked(self):
        doc = self.touch("docs/11_像素美术规格.md", b"# x")
        self.assertEqual(check_naming(self.root, [doc]), [])

    def test_links(self):
        self.touch("docs/target.md", b"# t")
        good = self.touch("docs/a.md", b"[ok](target.md) [web](https://example.com) [anchor](#top)")
        bad = self.touch("docs/b.md", b"[missing](nope.md)")
        issues = check_links(self.root, [good, bad])
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].path, bad)

    def test_size_limit(self):
        big = self.touch("Art/player/spr_big.png", b"x" * 2048)
        issues = check_hygiene(self.root, [big], max_bytes=1024)
        self.assertTrue(any("超过上限" in i.message for i in issues))


if __name__ == "__main__":
    unittest.main(verbosity=2)
