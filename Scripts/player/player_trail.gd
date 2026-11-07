extends Node2D

## 玩家拖尾：移动时身后留一串渐隐的残影。
##
## 纯代码 draw_rect 实现——AGENTS.md 禁止用粒子系统做核心表现，
## 项目里所有"动的东西"（重力区的石粒）也都是这样画的。
## 本节点挂在 Player 下，Player 是 INHERIT，所以游戏暂停时会跟着冻结。

## 最多同时留几段残影；越多尾巴越长。
const SAMPLE_COUNT := 7
## 采样间隔（秒）。60fps 下约两帧一次。
const SAMPLE_INTERVAL := 0.028
## 每段残影存活时间（秒）。
const SAMPLE_LIFE := 0.22
## 残影尺寸。**宽度刻意收得很窄**（4px，角色是 20px 宽）——
const TRAIL_SIZE := Vector2(4.0, 15.0)
## 残影颜色：用玩家的亮面青。
const TRAIL_COLOR := Color("7BFFD1")
## 最新一段残影的透明度。
const TRAIL_ALPHA := 0.28
## 速度低于这个值就不留尾——避免站着不动还抖出尾巴。
const MIN_SPEED := 24.0

## 采样点：{pos: Vector2（全局坐标）, age: float}
var _points: Array[Dictionary] = []
## 距离下次采样还有多久。
var _timer: float = 0.0
## 玩家节点（父节点）。
var _player: Node = null


func _ready() -> void:
	_player = get_parent() as Node
	# 重生会瞬移，旧残影留在原地会显得很怪，直接清掉
	if _player != null and _player.has_signal("respawned"):
		_player.connect("respawned", _on_respawned)


## 重生：清空残影，避免在死亡点留下一串假的影子。
func _on_respawned() -> void:
	_points.clear()


func _process(delta: float) -> void:
	if _player == null:
		return

	_timer -= delta
	if _timer <= 0.0:
		_timer = SAMPLE_INTERVAL
		_maybe_sample()

	# 老化，并清掉过期的
	var alive: Array[Dictionary] = []
	for p in _points:
		p["age"] = float(p["age"]) + delta
		if float(p["age"]) < SAMPLE_LIFE:
			alive.append(p)
	_points = alive

	queue_redraw()


## 玩家在移动、且还活着时才记一个采样点。
func _maybe_sample() -> void:
	if not bool(_player.get("is_alive")):
		return
	var vel: Vector2 = _player.get("velocity")
	if vel.length() < MIN_SPEED:
		return
	_points.append({"pos": _player.global_position, "age": 0.0})
	while _points.size() > SAMPLE_COUNT:
		_points.pop_front()


## 画所有残影。位置存的是全局坐标，这里转成相对自身的局部坐标。
func _draw() -> void:
	for p in _points:
		var t: float = float(p["age"]) / SAMPLE_LIFE   # 0 = 最新，1 = 最老
		var c := TRAIL_COLOR
		c.a = TRAIL_ALPHA * (1.0 - t)
		if c.a <= 0.005:
			continue
		var local: Vector2 = to_local(p["pos"])
		# 越老的残影越小，看起来像被"甩"掉
		var size := TRAIL_SIZE * (1.0 - t * 0.35)
		draw_rect(Rect2(local - size * 0.5, size), c)
