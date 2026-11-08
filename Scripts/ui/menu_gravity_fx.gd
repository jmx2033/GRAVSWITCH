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
## 石粒改流向的过渡速度（每秒）。越大越跟手，越小越像"重力慢慢转过来"。
const DIR_SWITCH_SPEED := 4.0
## 晃动过渡时间（秒）。
const SWING_TIME := 0.28

## 塌完之后每个元素的落点：`Vector2(横向偏移, 底边距屏幕底的高度)`。
##
## **语义是「底边距底」**：这样不管元素多高，塌完都**贴到屏幕底部**。
## 之前用「下移量」的话，高矮不一的元素会停在不同高度——
## 标题（高 87）和按钮（高 36）差得远，看着就像"没塌到底"。
##
## **为什么不用纯随机**：随机的话每次塌完都不一样，看起来像 bug；
## 用固定表能保证"塌成什么样子"是设计好的。
const SCATTER := {
	# 标题：压在最上面一层，横向左移
	"Title": Vector2(-40.0, 100.0),
	# 四个按钮：纵向差 40px（> 按钮高 36，所以目标位置互不重叠），
	# 横向再错开一点形成斜列
	"ButtonPlay": Vector2(-60.0, 4.0),
	"ButtonChallenge": Vector2(-20.0, 44.0),
	"ButtonSettings": Vector2(20.0, 84.0),
	"ButtonQuit": Vector2(60.0, 124.0),
}
## 表里没登记的元素：底边贴屏幕底，横移 0。
const SCATTER_DEFAULT := Vector2(0.0, 0.0)

## 按钮碰撞求解器：让塌落的按钮互相推开、不重叠、不抖动。
const COLLISION_SOLVER := preload("res://Scripts/ui/button_collision_solver.gd")

## 每颗石粒：{pos: Vector2, size: float}
var _stones: Array[Dictionary] = []
## 当前重力方向（石粒朝这边落）。按方向键会改它，石粒随之改流向。
var _dir: Vector2 = Vector2.DOWN
## 目标重力方向，_dir 朝它平滑过渡（硬切的话石粒会瞬移，不像"重力变了"）。
var _dir_target: Vector2 = Vector2.DOWN
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
## 收集需要跟着塌的 UI 元素，并算好它们各自的"落地目标"。
##
## 11/8 说明：按钮已经改回**直接挂在主菜单下**（不用 VBoxContainer），
## 这样布局不会重排它们，直接改 position 就生效。
## 收集只取主菜单的**直接子节点**——设置面板、选关面板里的按钮平时是隐藏的，
## 它们跟着塌会露出来。
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
		if not c.is_visible_in_tree():
			continue
		var from := c.position
		# 查表拿散落位置：x 是横向偏移，y 是底边距屏幕底的高度
		var spec: Vector2 = SCATTER.get(c.name, SCATTER_DEFAULT)
		# 目标 = 底边落在 SCREEN.y - spec.y 的位置
		var to := Vector2(
			from.x + spec.x,
			SCREEN.y - spec.y - c.size.y
		)
		# 已经在下面的元素不要往上跳
		if to.y < from.y:
			to.y = from.y
		_ui_moves.append({"node": c, "from": from, "to": to})


## 让所有收集到的元素脱离布局控制。
##
## 必须在**全部位置都采集完之后**统一做：设 top_level 的瞬间，
## 该按钮会脱离容器、位置被重置，所以要逐个写回它自己的原位。
func _detach_from_layout() -> void:
	for m in _ui_moves:
		var c: Control = m["node"]
		if not is_instance_valid(c):
			continue
		var from: Vector2 = m["from"]
		c.top_level = true
		c.global_position = from



## 每帧做一次按钮排斥：挤在一起的按钮互相推开，不重叠、不抖动。
##
## 为什么每帧做：排斥只在动画开始时算一次的话，动画途中按钮会互相穿过去；
## 每帧都算就能保证任何时刻都不重叠。
##
## 排斥算的是**全局坐标**（按钮可能不在同一个父节点下），
## 算完再换算回各自的父容器局部坐标再写回。
func _resolve_button_collisions() -> void:
	var button_items := []
	for m in _ui_moves:
		var node: Node = m["node"]
		if not is_instance_valid(node):
			continue
		if not (node is Button):
			continue
		var ctrl: Control = node as Control
		button_items.append({"node": ctrl, "to": ctrl.global_position})
	if button_items.size() < 2:
		return

	var solver = COLLISION_SOLVER.new()
	var solved: Dictionary = solver.solve(button_items)
	for node2 in solved:
		var c2: Control = node2 as Control
		if not is_instance_valid(c2):
			continue
		var parent_xform: Transform2D = c2.get_parent().get_global_transform().affine_inverse()
		c2.position = parent_xform * solved[node2]


func _process(delta: float) -> void:
	# 石粒方向朝目标平滑过渡
	_dir = _dir.lerp(_dir_target, clampf(delta * DIR_SWITCH_SPEED, 0.0, 1.0))
	if _dir.length() < 0.01:
		_dir = _dir_target
	else:
		_dir = _dir.normalized()

	# 石粒基础漂移
	var step: Vector2 = _dir * STONE_SPEED * delta
	# 塌得越多，下落越快
	step.y += STONE_FALL_ACCEL * _sink_ratio * delta

	_resolve_button_collisions()

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
	# 石粒也跟着改流向：这是「按 WASD 改主界面重力」的核心表现
	_dir_target = dir
	_apply_layout(SWING_TIME, false)


## 复位：晃动清空、塌陷归零，所有元素回原位。
func _reset() -> void:
	_step = 0
	_sink_ratio = 0.0
	_swing = Vector2.ZERO
	# 石粒方向也回到默认（朝下）
	_dir_target = Vector2.DOWN
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

	# 先算所有按钮的目标位置
	var targets := {}
	var items := []
	for m in _ui_moves:
		var node: Node = m["node"]
		if not is_instance_valid(node):
			continue
		var from: Vector2 = m["from"]
		var to: Vector2 = m["to"]
		var target := from.lerp(to, _sink_ratio) + _swing
		if jitter:
			target.x += randf_range(-STEP_JITTER, STEP_JITTER)
		targets[node] = target
		items.append({"node": node, "to": target})

	# 应用位置
	for node3 in targets:
		# 用 position（相对父容器）：按钮直接挂在主菜单下，
		# 父节点不是 Container，位置不会被布局重排，可以自由改。
		_layout_tween.tween_property(node3, "position", targets[node3], duration)
