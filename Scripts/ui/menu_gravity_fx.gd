extends Node2D

## 主菜单重力场效果：背景石粒 + 方向键晃动 / 按 S 塌陷 / 按 R 复位。
##
## ## 玩法（三件事，互不冲突）
## - **`←` `→` `↑`**：整屏 UI 被甩向该方向，轻微偏移（7px），手感反馈
## - **`↓`（S）**：塌陷一档，按满 10 次后所有 UI 落到地板并散开
## - **`R`**：全部复位，可以重新玩
##
## 晃动与塌陷是**两层独立效果**，可以叠加（一边晃一边塌）。
##
## ## 为什么这里可以有背景动态（对 docs/11 的例外）
##
## `docs/11` 规定「除了磁场里的石粒，什么都不许动」，理由是
## **满屏都在动，玩家就分不清哪个动的东西在告诉他方向**——那条针对的是**游戏进行中**。
##
## 主菜单里没有玩法、玩家不需要判断重力方向，这个理由不成立。
##
## ## 实现要点
## - 石粒：纯代码 draw_rect，**复用重力区那套视觉语言**（小方块、沿重力漂移、出界回绕）
## - 位置统一由 `_apply_layout()` 算：`原始位置 + 塌陷位移×进度 + 晃动偏移`
## - 用 Tween 做平滑过渡；塌陷每步带随机横向抖动，读起来像"塌"而不是"平移"
## - 层级：石粒在最底层（z_index 负值），不挡按钮

## 石粒数量。90 颗才够看出流动方向。
const STONE_COUNT := 90
## 石粒尺寸范围（像素）。
const STONE_SIZE_MIN := 2.0
const STONE_SIZE_MAX := 5.0
## 石粒基础漂移速度（px/s）。
const STONE_SPEED := 16.0
## 塌陷时石粒额外加速（px/s），让下落感更强。
const STONE_FALL_ACCEL := 70.0
## 石粒颜色，与游戏内一致。
const STONE_COLOR := Color("#FFF2E0")
## 石粒透明度。
const STONE_ALPHA := 0.62
## 屏幕范围（逻辑像素）。
const SCREEN := Vector2(640, 360)

## 总共塌几次就全部落地。
const COLLAPSE_STEPS := 10
## 每塌一次的过渡时间（秒）。
const STEP_TIME := 0.16
## 复位（按 R 扶回原位）的过渡时间（秒）。比塌陷慢一点，读起来像"被拎回去"。
const RESET_TIME := 0.35
## 每塌一次的随机横向抖动幅度（像素）。
const STEP_JITTER := 3.0

## 按方向键时，整屏 UI 被"甩"向该方向的位移（像素）。
## 与塌陷是**两层独立效果**：晃动管左右上，塌陷管向下，可以叠加。
const UI_SWING := 7.0
## 晃动过渡时间（秒）。
const SWING_TIME := 0.28

## 塌完之后每个元素的散落位置：`Vector2(横向偏移, 底边距屏幕底部的高度)`。
##
## **为什么不用纯随机**：随机的话每次塌完都不一样，看起来像 bug；
## 用固定表能保证"塌成什么样子"是设计好的，而且能确保彼此不重叠。
##
## 排序要求：**表里的纵向顺序必须和各元素的原始位置一致**
## （Title 最上、Quit 最下）。否则某个元素的目标位置会高于它原位，
## 被「不许往上跳」的判断拦在原地，看起来就没塌。
## 落差统一 40px（> 按钮高 36px），保证互不重叠。
const SCATTER := {
	"Title": Vector2(-30.0, 172.0),
	"ButtonChallenge": Vector2(-18.0, 132.0),
	"ButtonPlay": Vector2(24.0, 92.0),
	"ButtonSettings": Vector2(30.0, 52.0),
	"ButtonQuit": Vector2(-24.0, 12.0),
}
## 表里没登记的元素：底边贴屏幕底，横移 0。
const SCATTER_DEFAULT := Vector2(0.0, 4.0)

## 每颗石粒：{pos: Vector2, size: float}
var _stones: Array[Dictionary] = []
## 当前重力方向（石粒朝这边落），塌陷时固定朝下。
var _dir: Vector2 = Vector2.DOWN
## 当前塌陷步数（0..COLLAPSE_STEPS）。
var _step: int = 0
## 已塌陷的插值进度（0..1），驱动石粒加速。
var _sink_ratio: float = 0.0
## 当前方向偏移（按左右上触发）。与塌陷叠加：先按塌陷进度插值，再加上这个偏移。
var _swing: Vector2 = Vector2.ZERO

## 正在跑的布局动画。
## **必须只保留一个**：连按方向键/S 会不断创建新 Tween，
## 若放任旧 Tween 继续跑，多个动画同时写同一个 position，会互相打架、
## 最后停在谁都不对的位置（实测复位后残留 6px 偏差）。
var _layout_tween: Tween = null

## 每个 UI 元素：{node, from: Vector2, to: Vector2}
var _ui_moves: Array[Dictionary] = []


func _ready() -> void:
	# 石粒画在最底层
	z_index = -50
	_spawn_stones()
	_collect_ui()


## 生成初始石粒，位置随机铺满整屏。
func _spawn_stones() -> void:
	_stones.clear()
	for _i in STONE_COUNT:
		_stones.append({
			"pos": Vector2(randf() * SCREEN.x, randf() * SCREEN.y),
			"size": randf_range(STONE_SIZE_MIN, STONE_SIZE_MAX),
		})


## 收集需要跟着塌的 UI 元素，并算好它们各自的"落地目标"。
## 可重复调用：会先清空再重收，避免重复加入同一元素。
##
## 目标位置来自 `SCATTER` 表：每个元素有自己的高度与横向偏移，
## 所以塌完是**散落**成一片，而不是全部叠在屏幕底部同一处。
func _collect_ui() -> void:
	_ui_moves.clear()
	var root := get_parent()
	if root == null:
		return
	for child in root.get_children():
		if not (child is Control):
			continue
		if not (child is Button or child is TextureRect):
			continue
		var c := child as Control
		var from := c.position
		# 查表拿散落位置：x 是横向偏移，y 是底边距屏幕底部的高度
		var spec: Vector2 = SCATTER.get(c.name, SCATTER_DEFAULT)
		var to := Vector2(
			from.x + spec.x,
			SCREEN.y - spec.y - c.size.y
		)
		# 已经在下面的元素不要往上跳
		if to.y < from.y:
			to.y = from.y
		_ui_moves.append({"node": c, "from": from, "to": to})


func _process(delta: float) -> void:
	# 石粒基础漂移
	var step: Vector2 = _dir * STONE_SPEED * delta
	# 塌得越多，下落越快
	step.y += STONE_FALL_ACCEL * _sink_ratio * delta

	for s in _stones:
		var p: Vector2 = s["pos"] + step
		var size: float = s["size"]
		if p.x < -size:
			p.x = SCREEN.x + size
		elif p.x > SCREEN.x + size:
			p.x = -size
		if p.y < -size:
			p.y = SCREEN.y + size
		elif p.y > SCREEN.y + size:
			p.y = -size
		s["pos"] = p

	queue_redraw()


## 画石粒：与游戏内重力区同一套视觉。
func _draw() -> void:
	for s in _stones:
		var size: float = s["size"]
		var c := STONE_COLOR
		c.a = STONE_ALPHA
		draw_rect(Rect2(s["pos"] - Vector2(size, size) * 0.5, Vector2(size, size)), c)


## 输入处理：四个方向键各管一件事。
##
## - `←` `→` `↑`：整屏 UI 被甩向该方向（轻微偏移），只是手感反馈
## - `↓`（S）：塌陷一档，按满 COLLAPSE_STEPS 次全部落到地板
## - `R`：全部复位
##
## 晃动与塌陷是**两层叠加**的：晃动是 ±7px 的瞬时偏移，塌陷是累积的位移，
## 两者互不干扰，所以可以一边晃一边塌。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		if _step > 0 or _swing != Vector2.ZERO:
			_reset()
		return

	# 方向晃动（左/右/上）
	if event.is_action_pressed("move_left"):
		get_viewport().set_input_as_handled()
		_swing_to(Vector2.LEFT)
		return
	if event.is_action_pressed("move_right"):
		get_viewport().set_input_as_handled()
		_swing_to(Vector2.RIGHT)
		return
	if event.is_action_pressed("move_up"):
		get_viewport().set_input_as_handled()
		_swing_to(Vector2.UP)
		return

	# 向下（S）：塌陷
	if not event.is_action_pressed("move_down"):
		return
	get_viewport().set_input_as_handled()
	if _step >= COLLAPSE_STEPS:
		return
	_step += 1
	_sink_ratio = float(_step) / float(COLLAPSE_STEPS)
	_collapse()


## 整屏朝指定方向轻轻一晃。
func _swing_to(dir: Vector2) -> void:
	_swing = dir * UI_SWING
	_apply_layout(SWING_TIME, false)


## 复位：晃动清空、塌陷归零，所有元素回原位。
func _reset() -> void:
	_step = 0
	_sink_ratio = 0.0
	_swing = Vector2.ZERO
	_apply_layout(RESET_TIME, false)


## 塌陷一档：按总进度插值，并加一点横向抖动。
func _collapse() -> void:
	_apply_layout(STEP_TIME, true)


## 统一摆放所有 UI 元素。
##
## 位置 = 原始位置 + 塌陷位移 × 进度 + 晃动偏移
## 这样两层效果互不覆盖，可以同时存在。
##
## jitter 为 true 时给每步加随机横向抖动，读起来像"塌"而不是"平移"。
func _apply_layout(duration: float, jitter: bool) -> void:
	# 先干掉上一个动画：否则多个 Tween 同时写 position 会互相覆盖，
	# 最后停在错误位置。新动画会从「当前位置」平滑走向新目标，所以不会有跳变。
	if _layout_tween != null and _layout_tween.is_valid():
		_layout_tween.kill()

	_layout_tween = create_tween()
	_layout_tween.set_parallel(true)
	_layout_tween.set_trans(Tween.TRANS_QUAD)
	# 塌陷用 EASE_IN（越塌越快），晃动和复位用 EASE_OUT（一触即达再缓下来）
	_layout_tween.set_ease(Tween.EASE_IN if jitter else Tween.EASE_OUT)

	for m in _ui_moves:
		var node: Control = m["node"]
		if not is_instance_valid(node):
			continue
		var from: Vector2 = m["from"]
		var to: Vector2 = m["to"]
		var target := from.lerp(to, _sink_ratio) + _swing
		if jitter:
			target.x += randf_range(-STEP_JITTER, STEP_JITTER)
		_layout_tween.tween_property(node, "position", target, duration)
