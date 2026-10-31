# AGENTS.md —— 给 AI 编程助手的硬约束

> 每次开新对话，先把本文件贴进去。不贴，AI 会按 **Godot 3** 的习惯写：`KinematicBody2D`、`yield`、`export var`、`instance()`——全是 4.x 已经删掉的东西，一贴进编辑器就是一屏红色报错。

## 项目坐标

- 项目：重力主题 2D 生存（暂名，见 `docs/01_重力_核心机制与切片.md`）
- 引擎：**Godot `4.7.2-stable`**（六人共用一个 exe，不许各自升级）
- 语言：**只用 GDScript**。不要写 C#、不要混用
- 渲染：2D，默认渲染器即可，不碰自定义 shader
- 输入：走 **InputMap action**（`Input.is_action_pressed("gravity")`），**不要硬编码 `KEY_SPACE`**
- 分辨率：逻辑 1600×900，窗口缩放

## 禁止引入

- 任何 addon / 第三方插件 / Asset Library 资源
- `PhysicsBody2D` / `Area2D` 做重力计算与碰撞判定（**全部手写积分与距离判定**）
- 状态机框架、事件总线、数据驱动配置系统（这次只有 10 个功能点，写死）
- 自定义 shader、后处理、视差多层背景

## Godot 3 写法（4.x 已删除，不要写）

| 不要写 | 改成 |
|---|---|
| `KinematicBody2D` | `CharacterBody2D` |
| `yield(get_tree(), "idle_frame")` | `await get_tree().process_frame` |
| `export var x = 1` | `@export var x: int = 1` |
| `onready var n = $A` | `@onready var n: Node = $A` |
| `instance()` | `instantiate()` |
| `connect("pressed", self, "_on_pressed")` | `pressed.connect(_on_pressed)` |
| `rand_range(a, b)` | `randf_range(a, b)` |
| `OS.window_size` | `DisplayServer.window_set_size()` |
| `PoolVector2Array` | `PackedVector2Array` |
| `Spatial` / `Transform` | `Node3D` / `Transform3D` |

**不确定某个 API 在 4.7 是否还存在时，先说明不确定，不要直接写。** 不要照抄 Godot 3 时代的教程。

## 缩进（最容易踩死的一条）

**GDScript 用 Tab 缩进，且一个文件里不许混用 Tab 和空格。** 混用会直接报 `Used space character for indentation instead of tab`，报错位置还指在别处，极难查。

- 新建 `.gd` 一律 Tab
- 从聊天窗口复制代码后，先看一眼缩进是不是变成了空格

## 架构硬规则

- **重力与碰撞全部手写**：`_physics_process(delta)` 里自己积分速度与位置，不要交给物理引擎
- 所有可调数值放进 **一个 autoload 单例 `Config`**，不许散落在各个脚本里。调手感时只改这一处
- 节点之间用 **signal** 通信，不要 `get_node("../../..")` 这种深路径
- `main.tscn` 只有技术负责人能改；其他人用 `dev_<名字>.tscn`
- 一局的状态机只有四个：`READY / PLAYING / DEAD / RESULT`，写在 `game.gd` 里

## 代码风格

- 文件名 `snake_case.gd`，与节点同名：`player.gd` 挂在 `Player` 节点上
- 变量与函数 `snake_case`；`class_name` 与节点名 `PascalCase`
- 变量尽量带类型：`var speed: float = 90.0`
- 每个公开函数写一行中文 `##` 注释
- 单文件超过 150 行先说明为什么不能拆（GDScript 脚本容易膨胀，这条比 C# 更要守）
- 不用 `#region`

## 不要替我们决定的事

- **重力公式、蓄力曲线、手感数值**：这些我们自己调，AI 只给参考值
- 新增功能：先问。清单外的想法进 `docs/08_以后再说.md`
- 换引擎版本、加插件、加 shader：一律不做

## 导出

- Windows：导出预设 `Windows Desktop`，输出到 `build/win/`
- Web：导出预设 `Web`，输出到 `build/web/`（**需关掉多线程**，GitHub Pages 不支持自定义响应头）
- 命令行导出：`godot --headless --export-release "<预设名>" <输出路径>`
- **`export_templates` 没下载就导不出任何东西**。报错是「找不到导出模板」，不是代码问题
