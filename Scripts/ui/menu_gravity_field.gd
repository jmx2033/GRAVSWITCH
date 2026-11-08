extends "res://Scripts/level/gravity_zone_visuals.gd"

## 主菜单的「重力场」视觉：**继承**游戏内重力区的视觉层，只改两处。
##
## ## 为什么是继承而不是「另写一套」或「实例化再调用」
##
## 游戏内重力区的视觉在 `gravity_zone_visuals.gd`（纯 `_draw()`，无 shader/粒子），
## 场体渐变、出口辉光、呼吸与游走全在里面。
## - 另写一套 → 两套效果迟早跑偏
## - 实例化再 `call("_draw_exit_glow")` → 那是**它自己**的绘制上下文，
##   画不到本节点上来（`_draw` 必须在节点自己的 canvas item 里画）
##
## 继承则能直接覆盖 `_draw()`，在**本节点**的上下文里调用父类的画法，
## 辉光就画在正确的位置。
##
## ## 改了两处
##
## 1. **不画场体渐变**：主菜单背景已经有洞穴图，再铺一层紫色场体太重。
##    只留出口辉光，让「当前重力朝哪边」一眼可见。
## 2. **辉光强度压到 0.55**：主菜单的辉光是背景之上的点缀，
##    不是关卡里的主要视觉，不该抢戏。

## 出口辉光相对场体的强度倍率。
const GLOW_SCALE := 1.35

## 主菜单视口尺寸（场体铺满整个屏幕）。
const SCREEN := Vector2(640, 360)


func _ready() -> void:
	# 场体铺满视口，默认重力朝下
	set_zone(SCREEN, Vector2.DOWN, false)
	set_stones([])
	set_glow_scale(GLOW_SCALE)


## 推进动画时钟：辉光的呼吸与游走、晶核的漂移与脉动都靠它。
func _process(delta: float) -> void:
	advance_time(delta)


## 设置重力方向（主菜单按方向键时调用）。
func set_pull_dir(dir: Vector2) -> void:
	if dir.length() < 0.01:
		return
	set_zone(SCREEN, dir.normalized(), false)


## 画辉光（不画场体渐变）。
func _draw() -> void:
	if _zone_size == Vector2.ZERO:
		return
	_draw_exit_glow()
	# 晶核（随机游走的白色柔光斑）—— 与关卡里同一套画法
	_draw_cores()
	# 一圈极淡的描边，和关卡里一致，交代出「这里是个场」的边界
	var frame_color := EDGE_HIGHLIGHT_COLOR
	frame_color.a = FRAME_ALPHA
	draw_rect(Rect2(Vector2.ZERO, _zone_size), frame_color, false, 1.0)
