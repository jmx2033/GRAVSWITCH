# AGENTS.md —— 给 AI 编程助手的硬约束

> 每次开新对话，先把本文件贴进去。不贴，AI 会按 **Godot 3** 的习惯写：`KinematicBody2D`、`yield`、`export var`、`instance()`——全是 4.x 已经删掉的东西，一贴进编辑器就是一屏红色报错。

## 项目坐标

- 项目：**GRAVSWITCH（重力开关）** —— 2D 像素平台跳跃解谜，玩法见 `docs/01_重力_核心机制与切片.md`
- 引擎：**Godot `4.7.2-stable`**（六人共用一个 exe，不许各自升级）
- 语言：**只用 GDScript**。不要写 C#、不要混用（标准版编辑器打不开带 `.cs` 的工程）
- 渲染：**Compatibility 渲染器**（不是 Forward+，也不是 Mobile）。**Web 导出只支持 Compatibility**，选错 11/8 网页版就没了
- 分辨率：**逻辑 640×360**，整数缩放到窗口（1280×720 为 2×，1920×1080 为 3×）
- 关卡：**20 × 11 格，一屏一关，不做相机跟随**

## 建工程那一刻就要定死的三项（后面改很贵）

| 项 | 值 | 选错的后果 |
|---|---|---|
| 渲染器 | **Compatibility** | Forward+ 的 Web 导出不可用；中途换渲染器要重导素材、重调光照 |
| 视口 + 拉伸 | 视口 **640 × 360**；拉伸模式 `canvas_items`；宽高比 `keep`；缩放模式 `integer`（4.2 之后有这一项） | 非整数缩放，像素图被插值糊成一团 |
| 默认纹理过滤 | **Nearest**（项目设置 `rendering/textures/canvas_textures/default_texture_filter`） | 像素图默认被双线性插值糊掉，且要一个 sprite 一个 sprite 去改 |

三项都由技术负责人在建工程时设置，设完不再改。像素游戏里这三项错了，整套美术素材等于白画。

**另外两项建工程时一并定掉：**

- **窗口覆盖尺寸** `display/window/size/window_width_override` = `1280`、`window_height_override` = `720`。视口还是 640×360，这只是让窗口以 2× 显示；不设的话窗口只有 640×360，投到投影仪上巴掌大。**这一项默认藏在「高级设置」开关后面，不开看不到**
- **主场景** `application/run/main_scene` 必须设。空工程没有主场景时，导出的 exe 双击会直接报错退出，不是「开个空窗口」

## 输入（只有三个动词）

| action | 键 |
|---|---|
| `move_left` / `move_right` | `A` `D` / `←` `→` |
| `jump` | `空格` |
| `restart` | `R` |

走 **InputMap action**，**不要硬编码 `KEY_SPACE`**。没有攻击、冲刺、抓取、二段跳、能力切换——多一个动词这个游戏就不是它了。

## 物理与碰撞（和上一版规则相反，注意）

- 角色用 **`CharacterBody2D` + `move_and_slide()`**，**不要手写积分**。平台跳跃的手感靠引擎原生的贴地判定，手写只会更难调
- 重力区用 **`Area2D`** 检测玩家进入/离开，允许使用
- **起跳方向必须写 `up_direction * JUMP_SPEED`，不许写死 `velocity.y = -620`。** 这个游戏的重力会翻转，写死 `-y` 之后一进重力区人就往墙上撞
- 同一时刻**只认一个重力区**（重叠时取最后进入的），不做多区权重混合

## 禁止引入

- 任何 addon / 第三方插件 / Asset Library 资源
- 状态机框架、事件总线、数据驱动配置系统（这次只有 4 关，写死）
- 自定义 shader、后处理、视差多层背景、粒子系统做核心表现
- 存档、排行榜、联机、关卡编辑器

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

- 所有可调数值放进 **一个 autoload 单例 `Config`**，不许散落在各个脚本里。调手感时只改这一处
- **跳跃参数（重力加速度、跳跃初速、最大速度、土狼时间、跳预输入、转向过渡）只有技术负责人能改**，改完全队重测
- 节点之间用 **signal** 通信，不要 `get_node("../../..")` 这种深路径
- 状态只有四个：`MENU / PLAYING / DEAD / WIN`，写在 `game.gd` 里
- 关卡用 `level_0.tscn` … `level_3.tscn`，主场景只负责切关

## 代码风格

- 文件名 `snake_case.gd`，与节点同名：`player.gd` 挂在 `Player` 节点上
- 变量与函数 `snake_case`；`class_name` 与节点名 `PascalCase`
- 变量尽量带类型：`var speed: float = 240.0`
- 每个公开函数写一行中文 `##` 注释
- 单文件超过 150 行先说明为什么不能拆
- 不用 `#region`

## 不要替我们决定的事

- **跳跃参数、重力转向过渡时长、关卡格子布局**：这些我们自己调，AI 只给参考值
- 新增功能：先问。清单外的想法进 `docs/08_以后再说.md`
- 换引擎版本、加插件、加 shader：一律不做

## 导出

- Windows：导出预设 `Windows Desktop`，输出到 `build/win/`
- Web：导出预设 `Web`，输出到 `build/web/`。**前提是渲染器为 Compatibility**；并且必须关掉多线程（GitHub Pages 不支持自定义响应头）
- 命令行导出：`godot --headless --export-release "<预设名>" <输出路径>`
- **`export_templates` 没下载就导不出任何东西**。报错是「找不到导出模板」，不是代码问题
