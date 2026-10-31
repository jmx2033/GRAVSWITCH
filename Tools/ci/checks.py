#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""闪切协议仓库 CI 静态检查器。

只依赖 Python 标准库，不跑 Unity、不需要许可证。
检查对象是「已入库的文件」（git ls-files），不是工作区里的临时文件。

用法：
    python Tools/ci/checks.py all                      # 全部静态检查
    python Tools/ci/checks.py hygiene|meta|naming|csharp|links
    python Tools/ci/checks.py commit --message "feat(slash): 三段刃形 [P1-1]"
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

COMMIT_TYPES = ("feat", "fix", "art", "docs", "chore", "refactor")
COMMIT_SCOPES = ("charge", "slash", "enemy", "ui", "build", "repo", "levelup")
# scope=repo 是仓库与工程维护，不属于 P0/P1/P2 功能分级，因此不要求 P 编号。
P_TAG_EXEMPT_SCOPES = {"repo"}
P_TAG_RE = re.compile(r"\[(?:P[012]-\d+|P0-lite)\]")

FORBIDDEN_TOP_DIRS = {
    "library", "temp", "obj", "build", "builds", "logs",
    "usersettings", "memorycaptures", ".vs", ".idea", ".workbuddy",
}
FORBIDDEN_EXTS = {
    ".exe", ".dll", ".apk", ".aab", ".unitypackage",
    ".psd", ".ai", ".blend",
    ".csproj", ".sln", ".user", ".pdb", ".mdb", ".tmp", ".log",
}
# 只有这些 Unity 资源类型强制要求同名 .meta；.md / .gitkeep 不参与。
META_REQUIRED_EXTS = {
    ".cs", ".png", ".jpg", ".jpeg", ".wav", ".mp3", ".ogg",
    ".unity", ".prefab", ".asset", ".mat", ".anim", ".controller",
    ".ttf", ".otf", ".shader",
}
ART_RE = re.compile(r"^(spr|ui|vfx|tex)_[a-z0-9_]+\.(png|jpg|jpeg)$")
AUDIO_RE = re.compile(r"^(sfx|bgm)_[a-z0-9_]+\.(wav|mp3|ogg)$")
SCRIPT_RE = re.compile(r"^[A-Z][A-Za-z0-9]*\.cs$")
BAD_NAME_CHARS = re.compile(r"[\s()]")
NON_ASCII = re.compile(r"[^\x00-\x7f]")
BAD_STEM_SUFFIX = re.compile(r"(?:^|_)(?:new|final)\d*$", re.IGNORECASE)

BANNED_CS_TOKENS = (
    ("FindObjectOfType", "Unity 6 已废弃，改用 FindFirstObjectByType"),
    ("FindObjectsOfType", "Unity 6 已废弃，改用 FindObjectsByType"),
    ("Rigidbody2D", "本项目不用物理引擎，判定手写（线段-圆距离）"),
    ("Cinemachine", "禁止引入第三方包"),
    ("DG.Tweening", "禁止引入 DOTween"),
    ("UnityEngine.InputSystem", "项目用旧版 Input Manager"),
    ("UnityEngine.Rendering.Universal", "项目用 Built-In，不上 URP"),
)
PUBLIC_FIELD_RE = re.compile(
    r"^\s*public\s+(?:static\s+|readonly\s+)?"
    r"[\w<>\[\],\.\?]+\s+\w+\s*(?:=\s*[^;]+)?;\s*$"
)
NAMESPACE_RE = re.compile(r"^\s*namespace\s+([\w\.]+)\s*([;{])", re.MULTILINE)
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
            "（例：feat(slash): 三段刃形按蓄力进度切换 [P1-1]）"
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

    needs_p = m.group("type") in {"feat", "fix", "art"} and m.group("scope") not in P_TAG_EXEMPT_SCOPES
    if needs_p and not P_TAG_RE.search(body):
        problems.append(
            "功能/修复/美术提交必须带 P 编号，如 [P0-3] [P1-4]（编号见 docs/00_范围与不做清单.md）"
        )
    return problems


# ---------------------------------------------------------------- 仓库卫生

def check_hygiene(root: Path, files: list[str], max_bytes: int = MAX_BYTES) -> list[Issue]:
    issues: list[Issue] = []
    for rel in files:
        p = Path(rel)
        top = p.parts[0].lower() if p.parts else ""
        if top in FORBIDDEN_TOP_DIRS:
            issues.append(err(rel, "引擎生成物或本地目录不应入库（Library/Build/Logs 等）"))
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


# ---------------------------------------------------------------- .meta 配对

def check_meta(root: Path, files: list[str]) -> list[Issue]:
    issues: list[Issue] = []
    fileset = set(files)
    for rel in files:
        if not rel.startswith("Assets/") or rel.startswith("Assets/_Scratch/"):
            continue
        p = Path(rel)
        if p.name == ".gitkeep":
            continue
        if p.suffix == ".meta":
            target = rel[:-5]
            if target not in fileset and not (root / target).is_dir():
                issues.append(err(rel, "孤立的 .meta：对应的资源已不存在，请一并删除"))
        elif p.suffix.lower() in META_REQUIRED_EXTS and rel + ".meta" not in fileset:
            issues.append(err(rel, "缺少同名 .meta，别人拉下来会丢失引用（在 Unity 里打开一次即可生成）"))
    return issues


# ---------------------------------------------------------------- 命名规范

def check_naming(root: Path, files: list[str]) -> list[Issue]:
    issues: list[Issue] = []
    for rel in files:
        if not rel.startswith("Assets/") or rel.startswith("Assets/_Scratch/"):
            continue
        p = Path(rel)
        if p.name == ".gitkeep" or p.suffix == ".meta":
            continue
        for part in p.parts:
            if NON_ASCII.search(part):
                issues.append(err(rel, "路径含非 ASCII 字符（中文等），跨机器会出问题"))
                break
            if BAD_NAME_CHARS.search(part):
                issues.append(err(rel, "路径含空格或括号，禁止"))
                break
        stem = p.stem
        if BAD_STEM_SUFFIX.search(stem):
            issues.append(err(rel, "文件名以 new/final 结尾，禁止（用 Git 管版本，不靠文件名）"))

        under_scripts = rel.startswith("Assets/_Project/Scripts/") or rel.startswith("Assets/Editor/")
        if under_scripts and p.suffix == ".cs" and not SCRIPT_RE.match(p.name):
            issues.append(err(rel, "脚本文件名必须 PascalCase 且与类名一致，如 EnemyChaser.cs"))
        if rel.startswith("Assets/_Project/Art/") and p.suffix.lower() in {".png", ".jpg", ".jpeg"}:
            if not ART_RE.match(p.name):
                issues.append(err(rel, "美术资源命名：spr_/ui_/vfx_/tex_ 前缀 + 小写下划线，如 spr_player_base.png"))
        if rel.startswith("Assets/_Project/Audio/") and p.suffix.lower() in {".wav", ".mp3", ".ogg"}:
            if not AUDIO_RE.match(p.name):
                issues.append(err(rel, "音频命名：sfx_/bgm_ 前缀 + 小写下划线，三段蓄力音效用 tier1-3"))
    return issues


# ---------------------------------------------------------------- C# 硬约束

def strip_comments(src: str) -> list[str]:
    """去掉块注释与行注释后按行返回。字符串里的 // 会被一并截断，
    对本文件检查的关键字没有影响。"""
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    lines = []
    for line in src.splitlines():
        idx = line.find("//")
        lines.append(line[:idx] if idx != -1 else line)
    return lines


def is_public_field(line: str) -> bool:
    s = line.strip()
    if not s.startswith("public "):
        return False
    if " event " in s or s.startswith("public event "):
        return False                      # 事件是本项目推荐的跨模块通信方式
    if " const " in s or " static readonly " in s:
        return False                      # 常量允许 public
    if "=>" in s:
        return False                      # 表达式属性
    if "(" in s.split("=")[0]:
        return False                      # 方法 / 构造函数 / 委托
    return bool(PUBLIC_FIELD_RE.match(line))


def check_csharp(root: Path, files: list[str]) -> list[Issue]:
    issues: list[Issue] = []
    for rel in files:
        if not rel.startswith("Assets/") or not rel.endswith(".cs"):
            continue
        src = read_text(root / rel)
        if not src:
            continue
        lines = strip_comments(src)

        ns = NAMESPACE_RE.search(src)
        if ns is None:
            issues.append(err(rel, "缺少 namespace，所有脚本统一 namespace FlickCut"))
        elif ns.group(2) == ";":
            issues.append(err(rel, "不要用 C# 10 的 file-scoped namespace，本项目用 C# 8.0"))
        elif ns.group(1) != "FlickCut":
            issues.append(err(rel, f"命名空间是 {ns.group(1)}，必须统一为 FlickCut"))

        for lineno, line in enumerate(lines, start=1):
            if is_public_field(line):
                issues.append(err(rel, "不要用 public 字段，改 [SerializeField] private", lineno))
            for token, why in BANNED_CS_TOKENS:
                if token in line:
                    issues.append(err(rel, f"禁用 {token}：{why}", lineno))
            if "Time.timeScale" in line and Path(rel).name != "GameFlow.cs":
                issues.append(err(rel, "时间缩放只能通过 GameFlow.TimeScale，不得直接写 Time.timeScale", lineno))
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
    "meta": check_meta,
    "naming": check_naming,
    "csharp": check_csharp,
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
    ap = argparse.ArgumentParser(description="闪切协议仓库静态检查")
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
