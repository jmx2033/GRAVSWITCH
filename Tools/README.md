# Tools —— 构建与辅助脚本

## CI 检查器（`Tools/ci/`）

| 文件 | 作用 |
|---|---|
| `checks.py` | 静态检查：仓库卫生 / 命名 / 提交信息与文档链接。**只用 Python 标准库** |
| `test_checks.py` | 检查器自测（含"不该报的不能报"）。CI 每次先跑自测再查仓库 |
| `commit-msg` | 本地提交信息钩子，**只用 bash + grep + sed，不需要 Python** |
| `install-hooks.sh` | 把钩子装进 `.git/hooks/`，装完自动做正反两次自检 |

**六个人 clone 后都要执行一次：**

```bash
bash Tools/ci/install-hooks.sh
```

有 Python 的话也可以本地跑全量检查（没有就交给 PR 上的 CI）：

```bash
python Tools/ci/checks.py all
python Tools/ci/checks.py commits --range origin/main..HEAD
```

规则与误报处理见 `docs/工程规范.md` §5.2、§5.10。**改检查器必须同时补自测。**

> 两项 Unity 时期的规则（`.meta` 配对、C# 硬约束）已停用：仓库里已无 `Assets/`，不会命中。
> GDScript 版规则待重写，候选：禁用 `get_node("../../..")` 硬编码路径、禁止在 `_process` 里 `load()`。

## 出包

**Godot 不需要构建脚本，也不需要 Unity 那套 `-executeMethod`。** 点菜单或敲一行命令就行。

### 图形界面（推荐给非程序）

1. **先确认导出模板已下载**：`编辑器 → 管理导出模板 → 4.7.2 → 下载并安装`（约 900 MB）
2. `项目 → 导出`，第一次会提示"添加预设"，选 **Windows Desktop**
3. `导出项目`，输出目录选 `build/win/`

### 命令行（给自己出包用）

```bash
godot --headless --export-release "Windows Desktop" build/win/GRAVSWITCH.exe
```

Web 版：

```bash
godot --headless --export-release "Web" build/web/index.html
```

**注意**：Web 预设必须**关掉多线程**（`Thread Support` 取消勾选），否则 GitHub Pages 因为不支持自定义响应头，页面打开是黑的。

不要各写一套出包命令——六个人六种出包方式，是这类项目最常见的分叉点。

## 产物检查

出包后确认 `build/win/` 下这几样都在，缺一个就是"双击没反应"：

```
GRAVSWITCH.exe
GRAVSWITCH.pck
```

**拷贝给别人时整个目录一起打包，只发 exe 会缺 pck。**

Web 版目录里应该至少有 `index.html` / `index.pck` / `index.wasm` 三样。

## 参考基线

空工程 Windows 包约 45–60 MB（Godot 4.7，未压缩）。有美术资源后会涨，别把这个当最终包的预期。

## 曾经踩过的坑（勿重犯）

| 现象 | 真实原因 |
|---|---|
| 导出报「找不到导出模板」 | 模板没下完，或者下的是别的版本（必须 4.7.2） |
| 六个人打不开同一个工程 | 有人用了 4.8 / 4.7.1，`.tscn` 有版本标记 |
| Web 版打开是黑屏 | 没关多线程 |
| 双击 exe 没反应 | 只拷了 exe，没拷 `.pck` |
| 工程目录里一堆冲突 | 项目放在 OneDrive / 网盘同步目录里，`.godot/` 被同步搞坏 |
