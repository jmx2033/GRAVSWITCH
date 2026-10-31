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
    check_csharp, check_hygiene, check_links, check_meta,
    check_naming, is_public_field, validate_subject,
)

VALID_CS = """using UnityEngine;
namespace FlickCut
{
    public class PlayerController : MonoBehaviour
    {
        [SerializeField] private float moveSpeed = 5f;
        public const int MaxEnemyCount = 30;
        public static readonly int MaxTier = 3;
        public event System.Action OnDeath;
        public int Hp { get; private set; }
        public string DisplayName => name;
        /// <summary>按输入方向移动。</summary>
        public void Move() { }
        private void Bind()
        {
            var manager = FindFirstObjectByType<EnemyManager>();
            var all = FindObjectsByType<EnemyChaser>();
        }
    }
}
"""

BAD_CS = """using UnityEngine;
namespace FlickCut
{
    public class Foo : MonoBehaviour
    {
        public int hp;
        public float speed = 3f;
        public System.Collections.Generic.List<int> enemies;
        private Rigidbody2D rb;
        private void A() { var e = FindObjectOfType<Foo>(); }
        private void B() { Time.timeScale = 0.2f; }
    }
}
"""


class TestCommitSubject(unittest.TestCase):
    def test_valid(self):
        valid = [
            "feat(slash): 三段刃形按蓄力进度切换 [P1-1]",
            "fix(enemy): 敌人死亡后经验球未回收 [P0-4]",
            "art(ui): 卡面描边加粗到 2px [P1-5]",
            "docs(repo): 补全员必装清单",
            "chore(repo): 忽略 Library 与 _Scratch",
            "refactor(charge): 抽出蓄力进度计算 [P0-2]",
            "polish(ui): 卡面描边加粗到 2px [P1-5]",
            "polish(charge): 蓄力音效尾巴缩短 [P1-4]",
            "fix(repo): .gitignore 的 Build 规则误伤模块",
            "feat(slash): 三段刃形 [P1-1] (#12)",
        ]
        for s in valid:
            self.assertEqual(validate_subject(s), [], f"不应报错：{s}")

    def test_invalid(self):
        invalid = [
            "update",
            "改了一下",
            "feat: 没有 scope",
            "feat(slash): 缺 P 编号",
            "feat(slash):改前没空格 [P1-1]",
            "feat(slash): 最终版 [P1-1]",
            "fix(enemy): 修好了。 [P0-4]",
            "feat(other): scope 不在表里 [P0-1]",
            "feat(slash): 短 [P1-1]",
            "polish(ui): 卡面描边加粗到 3px",
            "",
        ]
        for s in invalid:
            self.assertTrue(validate_subject(s), f"应当报错：{s}")

    def test_merge_and_revert_skipped(self):
        self.assertEqual(validate_subject("Merge branch 'main' into x"), [])
        self.assertEqual(validate_subject('Revert "feat(slash): x [P1-1]"'), [])


class TestPublicField(unittest.TestCase):
    def test_not_fields(self):
        safe = [
            "public class PlayerController : MonoBehaviour",
            "public void Move() { }",
            "public int Hp { get; private set; }",
            "public string DisplayName => name;",
            "public const int MaxEnemyCount = 30;",
            "public static readonly int MaxTier = 3;",
            "public event System.Action OnDeath;",
            "public delegate void SlashHandler(Vector2 dir);",
            "    [SerializeField] private float speed = 5f;",
            "private int hp;",
            "public enum Tier { One, Two }",
        ]
        for line in safe:
            self.assertFalse(is_public_field(line), f"误报：{line}")

    def test_real_fields(self):
        bad = [
            "public int hp;",
            "    public float speed = 3f;",
            "public List<Enemy> enemies;",
            "public static int counter;",
            "public EnemyChaser chaser = null;",
        ]
        for line in bad:
            self.assertTrue(is_public_field(line), f"漏报：{line}")


class TestCSharp(unittest.TestCase):
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
        rel = self.write("Assets/_Project/Scripts/Player/PlayerController.cs", VALID_CS)
        self.assertEqual(check_csharp(self.root, [rel]), [])

    def test_violations_all_reported(self):
        rel = self.write("Assets/_Project/Scripts/Combat/Foo.cs", BAD_CS)
        messages = "\n".join(i.message for i in check_csharp(self.root, [rel]))
        for expected in ["public 字段", "Rigidbody2D", "FindObjectOfType", "Time.timeScale"]:
            self.assertIn(expected, messages)
        self.assertEqual(len(check_csharp(self.root, [rel])), 6)

    def test_timescale_allowed_in_gameflow(self):
        src = "namespace FlickCut\n{\n    public class GameFlow\n    {\n        private void Slow() { Time.timeScale = 0.2f; }\n    }\n}\n"
        rel = self.write("Assets/_Project/Scripts/Core/GameFlow.cs", src)
        self.assertEqual(check_csharp(self.root, [rel]), [])

    def test_wrong_namespace_and_file_scoped(self):
        rel = self.write("Assets/_Project/Scripts/Core/A.cs", "namespace FlashCut\n{\n    public class A { }\n}\n")
        self.assertTrue(any("FlickCut" in i.message for i in check_csharp(self.root, [rel])))
        rel2 = self.write("Assets/_Project/Scripts/Core/B.cs", "namespace FlickCut;\npublic class B { }\n")
        self.assertTrue(any("file-scoped" in i.message for i in check_csharp(self.root, [rel2])))

    def test_commented_out_code_not_reported(self):
        src = "namespace FlickCut\n{\n    public class C\n    {\n        // var x = FindObjectOfType<C>();\n        /* Rigidbody2D rb; */\n    }\n}\n"
        rel = self.write("Assets/_Project/Scripts/Core/C.cs", src)
        self.assertEqual(check_csharp(self.root, [rel]), [])


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
        good = self.touch("Assets/_Project/Scripts/Build/CardPool.cs")
        issues = check_hygiene(self.root, [bad, good])
        self.assertEqual(len(issues), 2)          # Build/ 目录 + .exe 后缀
        self.assertTrue(all(i.path == bad for i in issues))

    def test_meta_pairing(self):
        lonely = self.touch("Assets/_Project/Art/Player/spr_player_base.png")
        issues = check_meta(self.root, [lonely])
        self.assertEqual(len(issues), 1)
        self.touch(lonely + ".meta")
        self.assertEqual(check_meta(self.root, [lonely, lonely + ".meta"]), [])
        orphan = self.touch("Assets/_Project/Art/Player/spr_gone.png.meta")
        self.assertEqual(len(check_meta(self.root, [lonely, lonely + ".meta", orphan])), 1)

    def test_gitkeep_needs_no_meta(self):
        keep = self.touch("Assets/_Project/Scenes/.gitkeep")
        self.assertEqual(check_meta(self.root, [keep]), [])

    def test_naming(self):
        final = self.touch("Assets/_Project/Art/Player/spr_player_final.png")
        renew = self.touch("Assets/_Project/Audio/SFX/sfx_renew.wav")
        lower = self.touch("Assets/_Project/Scripts/Enemy/chaser.cs")
        chinese = self.touch("Assets/_Project/Art/Player/玩家.png")
        good = self.touch("Assets/_Project/Art/Player/spr_player_base.png")
        good2 = self.touch("Assets/_Project/Audio/SFX/sfx_slash_tier1.wav")
        paths = [final, renew, lower, chinese, good, good2]
        flagged = {i.path for i in check_naming(self.root, paths)}
        self.assertEqual(flagged, {final, lower, chinese})
        self.assertNotIn(renew, flagged)          # renew 结尾不是 _new，不应误报

    def test_links(self):
        self.touch("docs/target.md", b"# t")
        good = self.touch("docs/a.md", b"[ok](target.md) [web](https://example.com) [anchor](#top)")
        bad = self.touch("docs/b.md", b"[missing](nope.md)")
        issues = check_links(self.root, [good, bad])
        self.assertEqual(len(issues), 1)
        self.assertEqual(issues[0].path, bad)

    def test_size_limit(self):
        big = self.touch("Assets/big.png", b"x" * 2048)
        issues = check_hygiene(self.root, [big], max_bytes=1024)
        self.assertTrue(any("超过上限" in i.message for i in issues))


if __name__ == "__main__":
    unittest.main(verbosity=2)
