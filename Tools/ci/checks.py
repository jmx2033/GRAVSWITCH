#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""GRAVSWITCH 仓库 CI 静态检查器。

只依赖 Python 标准库，不跑 Unity、不需要许可证。
检查对象是「已入库的文件」（git ls-files），不是工作区里的临时文件。

用法：
    python Tools/ci/checks.py all                      # 全部静态检查
    python Tools/ci/checks.py hygiene|naming|gdscript|links
    python Tools/ci/checks.py commit --message "feat(gravity): 重力区转向 [P0-2]"
    python Tools/ci/checks.py commit --file .git/COMMIT_EDITMSG
    python Tools/ci/checks.py commits --range origin/main..HEAD

退出码：有 error 则为 1，否则为 0。warning 只提示，不拦截。
自测：python Tools/ci/test_checks.py
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MAX_BYTES = 50 * 1024 * 1024
WARN_BYTES = 10 * 1024 * 1024

# polish = 冻结期（11/7 23:00 后）只改表现、不改逻辑的提交，README 与启动方案 §6.2 都用到这个词，
# 所以它必须在这里合法，否则冻结第一天所有人的提交都会被自家钩子拦下。
COMMIT_TYPES = ("feat", "fix", "art", "docs", "chore", "refactor", "polish")
COMMIT_SCOPES = ("player", "gravity", "level", "ui", "build", "repo")
# scope=repo 是仓库与工程维护，不属于 P0/P1/P2 功能分级，因此不要求 P 编号。
P_TAG_EXEMPT_SCOPES = {"repo"}
P_TAG_RE = re.compile(r"\[(?:P[012]-\d+|P0-lite)\]")

FORBIDDEN_TOP_DIRS = {
    ".godot",                     # Godot 4.x 导入缓存，体积大、每次打开都变
    "build", "builds", "export",  # 出包产物
    "logs", ".vscode", ".idea", ".workbuddy",
}
FORBIDDEN_EXTS = {
    ".exe", ".pck", ".apk", ".aab", ".zip",
    ".psd", ".ai", ".aseprite", ".ase", ".blend",   # 源文件自己在本地留，仓库只放导出的 png
    ".dll", ".csproj", ".sln", ".user", ".pdb", ".mdb",
    ".tmp", ".log",
    ".import",                    # Godot 3 的导入文件，4.x 已不再生成
}
# Godot 的目录结构与命名前缀，见 docs/11_像素美术规格.md 第七节。
# 只查这四棵子树：docs/ 里全是中文文件名，不能按代码规则要求。
NAMING_ROOTS = ("Art/", "Audio/", "Scripts/", "Scenes/")
ART_RE = re.compile(r"^(spr|tile|bg|ui|icon)_[a-z0-9_]+\.(png|jpg|jpeg)$")
AUDIO_RE = re.compile(r"^(sfx|bgm)_[a-z0-9_]+\.(wav|mp3|ogg)$")
GD_RE = re.compile(r"^[a-z][a-z0-9_]*\.gd$")
TSCN_RE = re.compile(r"^[a-z][a-z0-9_]*\.tscn$")
BAD_NAME_CHARS = re.compile(r"[\s()]")
NON_ASCII = re.compile(r"[^\x00-\x7f]")
BAD_STEM_SUFFIX = re.compile(r"(?:^|_)(?:new|final|v\d+)$", re.IGNORECASE)

# Godot 3 的写法和 AGENTS.md 明令禁止的两条，进 4.7 会直接报错或当场撞墙。
# 三个 @ 开头的注解必须用负向后顾：`@export var` 里含有子串 `export var`，
# 纯子串匹配会把正确写法一起判死。
BANNED_GD_PATTERNS = (
    (re.compile(r"\bKinematicBody2D\b"), "KinematicBody2D", "Godot 3 类名，改 CharacterBody2D"),
    (re.compile(r"\bSpatial\b"), "Spatial", "Godot 3 类名，改 Node3D"),
    (re.compile(r"\byield\s*\("), "yield(", "Godot 3 语法，改 await"),
    (re.compile(r"(?<!@)\bexport\s+var\b"), "export var", "Godot 3 语法，改 @export var"),
    (re.compile(r"(?<!@)\bexport\s*\("), "export(", "Godot 3 语法，改 @export("),
    (re.compile(r"(?<!@)\bonready\s+var\b"), "onready var", "Godot 3 语法，改 @onready var"),
    (re.compile(r"\.instance\s*\("), ".instance(", "Godot 3 写法，改 .instantiate()"),
    (re.compile(r"\bOS\.get_ticks_msec\b"), "OS.get_ticks_msec", "改 Time.get_ticks_msec()"),
    (re.compile(r"get_tree\(\)\.change_scene\("), "get_tree().change_scene(", "改 change_scene_to_file()"),
)
VELOCITY_Y_HARDCODE = re.compile(r"velocity\.y\s*=\s*-")
DEEP_NODE_PATH = re.compile(r'(?:get_node\(\s*|\$)\s*"?((?:\.\./){2,})')
MD_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


@dataclass
class Issue:
    level: str
    path: str
    line: int
    message: str


def err(path: str, message: str, line: int = 0) -> Issue:
    return Issue("error", path, line, message)


def warn(path: str, message: str, line: int = 0) -> Issue:
    return Issue("warning", path, line, message)


def git_files(root: Path) -> list[str]:
    """只取已入库文件，避免把本地临时文件算进检查。"""
    try:
        out = subprocess.run(
            ["git", "ls-files", "-z"], cwd=root, check=True,
            capture_output=True,
        ).stdout
        return [p for p in out.decode("utf-8", "replace").split("\0") if p]
    except (subprocess.CalledProcessError, FileNotFoundError):
        return [
            p.relative_to(root).as_posix()
            for p in root.rglob("*") if p.is_file() and ".git" not in p.parts
        ]


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


# ---------------------------------------------------------------- 提交信息

def validate_subject(subject: str) -> list[str]:
    """返回该提交信息的问题列表，空列表代表合规。本地钩子与 CI 共用本规则。"""
    problems: list[str] = []
    s = subject.strip()
    if not s:
        return ["提交信息不能为空"]
    if s.startswith(("Merge ", "Revert ")):
        return problems

    pattern = (
        r"^(?P<type>" + "|".join(COMMIT_TYPES) + r")"
        r"\((?P<scope>" + "|".join(COMMIT_SCOPES) + r")\)"
        r": (?P<body>.+?)(?: \(#\d+\))?$"
    )
    m = re.match(pattern, s)
    if not m:
        return [
            "格式必须是 <type>(<scope>): <描述> [P编号]，"
            "type ∈ " + "/".join(COMMIT_TYPES) + "，"
            "scope ∈ " + "/".join(COMMIT_SCOPES) +
            "（例：feat(gravity): 重力区进入后方向平滑转向 [P0-2]）"
        ]

    body = m.group("body")
    desc = P_TAG_RE.sub("", body).strip()
    if len(desc) < 4:
        problems.append("描述太短，要说清改了什么（至少 4 个字符）")
    if desc.lower() in {"update", "test", "wip", "fix", "1", "修改", "改了一下", "最终版", "更新"}:
        problems.append(f"「{desc}」不算描述，要写清改了哪个功能")
    if desc.endswith(("。", "；", ";", ".")):
        problems.append("描述末尾不加句号")
    if len(s) > 72:
        problems.append("标题超过 72 字符，细节请写进提交正文，不要堆在标题里")

    needs_p = m.group("type") in {"feat", "fix", "art", "polish"} and m.group("scope") not in P_TAG_EXEMPT_SCOPES
    if needs_p and not P_TAG_RE.search(body):
        problems.append(
            "功能/修复/美术提交必须带 P 编号，如 [P0-3] [P1-4]（编号见 docs/00_实训硬要求.md）"
        )
    return problems


# ---------------------------------------------------------------- 仓库卫生

def check_hygiene(root: Path, files: list[str], max_bytes: int = MAX_BYTES) -> list[Issue]:
    issues: list[Issue] = []
    for rel in files:
        p = Path(rel)
        top = p.parts[0].lower() if p.parts else ""
        if top in FORBIDDEN_TOP_DIRS:
            issues.append(err(rel, "引擎生成物或本地目录不应入库（.godot/build/logs 等）"))
        if p.suffix.lower() in FORBIDDEN_EXTS:
            issues.append(err(rel, f"{p.suffix} 文件不应入库（出包产物 / IDE 缓存 / 大型源素材）"))
        full = root / rel
        if full.is_file():
            size = full.stat().st_size
            if size > max_bytes:
                issues.append(err(rel, f"单文件 {size / 1048576:.1f}MB 超过上限，大文件走 Release 附件"))
            elif size > WARN_BYTES:
                issues.append(warn(rel, f"单文件 {size / 1048576:.1f}MB 偏大，确认是否需要进仓库"))
    return issues


# ---------------------------------------------------------------- 命名规范

def check_naming(root: Path, files: list[str]) -> list[Issue]:
    """只查 Art/ Audio/ Scripts/ Scenes/ 四棵子树。

    docs/ 里本来就全是中文文件名，所以不做全局非 ASCII 拦截，
    否则每篇文档都会被自己的检查器判死。
    """
    issues: list[Issue] = []
    for rel in files:
        if not rel.startswith(NAMING_ROOTS):
            continue
        p = Path(rel)
        if p.name == ".gitkeep" or p.suffix.lower() in {".uid", ".import"}:
            continue
        for part in p.parts:
            if NON_ASCII.search(part):
                issues.append(err(rel, "路径含非 ASCII 字符（中文等），跨机器会出问题"))
                break
            if BAD_NAME_CHARS.search(part):
                issues.append(err(rel, "路径含空格或括号，禁止"))
                break
        if BAD_STEM_SUFFIX.search(p.stem):
            issues.append(err(rel, "文件名带 new/final/_v2，禁止（改用 Git 管版本）"))

        low = p.suffix.lower()
        if rel.startswith("Art/") and low in {".png", ".jpg", ".jpeg"}:
            if not ART_RE.match(p.name):
                issues.append(err(rel, "美术命名：spr_/tile_/bg_/ui_/icon_ 前缀 + 小写下划线，如 spr_player.png"))
        elif rel.startswith("Audio/") and low in {".wav", ".mp3", ".ogg"}:
            if not AUDIO_RE.match(p.name):
                issues.append(err(rel, "音频命名：sfx_/bgm_ 前缀 + 小写下划线，如 sfx_jump.wav"))
        elif rel.startswith("Scripts/") and low == ".gd":
            if not GD_RE.match(p.name):
                issues.append(err(rel, "脚本名必须 snake_case 且与节点同名，如 player.gd、gravity_zone.gd"))
        elif rel.startswith("Scenes/") and low == ".tscn":
            if not TSCN_RE.match(p.name):
                issues.append(err(rel, "场景名必须 snake_case，如 level_0.tscn、player.tscn"))
    return issues


# ---------------------------------------------------------------- GDScript 硬约束

def strip_gd_comments(src: str) -> list[str]:
    """去掉 GDScript 的行注释后按行返回。

    逐字符判断引号，所以 `"http://x"` 里的 `//`、`"a#b"` 里的 `#`
    都不会被当成注释截断。
    """
    lines = []
    for line in src.splitlines():
        quote = ""
        cut = len(line)
        for i, ch in enumerate(line):
            if quote:
                if ch == quote:
                    quote = ""
            elif ch in "\"'":
                quote = ch
            elif ch == "#":
                cut = i
                break
        lines.append(line[:cut])
    return lines


def check_gdscript(root: Path, files: list[str]) -> list[Issue]:
    issues: list[Issue] = []
    for rel in files:
        if not rel.endswith(".gd"):
            continue
        src = read_text(root / rel)
        if not src:
            continue
        for lineno, line in enumerate(strip_gd_comments(src), start=1):
            for pattern, label, why in BANNED_GD_PATTERNS:
                if pattern.search(line):
                    issues.append(err(rel, f"禁用 {label}：{why}", lineno))
            if VELOCITY_Y_HARDCODE.search(line):
                issues.append(err(
                    rel,
                    "跳跃不要写死 velocity.y 负数：重力翻转后会朝墙里撞。"
                    "用 up_direction * JUMP_SPEED（见 AGENTS.md 物理一节）",
                    lineno,
                ))
            if DEEP_NODE_PATH.search(line):
                issues.append(err(
                    rel,
                    "禁止 ../../ 深路径取节点：父节点一改就全断。用 signal 或 @onready 引用同级节点",
                    lineno,
                ))
    return issues


# ---------------------------------------------------------------- 文档链接

def check_links(root: Path, files: list[str]) -> list[Issue]:
    issues: list[Issue] = []
    for rel in files:
        if not rel.endswith(".md"):
            continue
        for lineno, line in enumerate(read_text(root / rel).splitlines(), start=1):
            for target in MD_LINK_RE.findall(line):
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                path_part = target.split("#")[0]
                if not path_part:
                    continue
                resolved = (root / path_part.lstrip("/")) if path_part.startswith("/") \
                    else (root / rel).parent / path_part
                if not resolved.exists():
                    issues.append(err(rel, f"链接指向不存在的路径：{target}", lineno))
    return issues


CHECKS = {
    "hygiene": check_hygiene,
    "naming": check_naming,
    "gdscript": check_gdscript,
    "links": check_links,
}


def run_checks(root: Path, files: list[str], names=None, max_bytes: int = MAX_BYTES) -> list[Issue]:
    issues: list[Issue] = []
    for name in (names or list(CHECKS)):
        fn = CHECKS[name]
        if name == "hygiene":
            issues += fn(root, files, max_bytes=max_bytes)
        else:
            issues += fn(root, files)
    return issues


def emit(issues: list[Issue]) -> tuple[int, int]:
    github = os.environ.get("GITHUB_ACTIONS") == "true"
    errors = sum(1 for i in issues if i.level == "error")
    warnings = len(issues) - errors
    for i in issues:
        if github:
            print(f"::{i.level} file={i.path},line={i.line or 1}::{i.message}")
        else:
            loc = f"{i.path}:{i.line}" if i.line else i.path
            print(f"[{i.level.upper()}] {loc} — {i.message}")
    print(f"\n检查完成：{errors} 个错误，{warnings} 个提示")
    return errors, warnings


def main() -> int:
    ap = argparse.ArgumentParser(description="GRAVSWITCH 仓库静态检查")
    ap.add_argument("mode", choices=list(CHECKS) + ["all", "commit", "commits"])
    ap.add_argument("--message")
    ap.add_argument("--file")
    ap.add_argument("--range", dest="commit_range")
    args = ap.parse_args()

    if args.mode == "commit":
        if args.message is not None:
            subject = args.message
        elif args.file:
            subject = read_text(Path(args.file)).splitlines()[0] if read_text(Path(args.file)) else ""
        else:
            subject = sys.stdin.readline()
        problems = validate_subject(subject)
        for p in problems:
            print(f"[ERROR] commit — {p}")
        if not problems:
            print("提交信息格式合规")
        return 1 if problems else 0

    if args.mode == "commits":
        if not args.commit_range:
            print("需要 --range，例如 origin/main..HEAD")
            return 2
        out = subprocess.run(
            ["git", "log", "--no-merges", "--format=%s", args.commit_range],
            cwd=ROOT, capture_output=True, text=True,
        )
        if out.returncode != 0:
            print(out.stderr)
            return 2
        subjects = [s for s in out.stdout.splitlines() if s.strip()]
        if not subjects:
            print("该范围内没有提交，跳过")
            return 0
        failed = 0
        for s in subjects:
            problems = validate_subject(s)
            for p in problems:
                print(f"[ERROR] {s} — {p}")
                failed += 1
        print(f"\n共检查 {len(subjects)} 条提交信息，{failed} 处问题")
        return 1 if failed else 0

    files = git_files(ROOT)
    names = None if args.mode == "all" else [args.mode]
    errors, _ = emit(run_checks(ROOT, files, names))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
