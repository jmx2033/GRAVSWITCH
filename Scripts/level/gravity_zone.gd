@tool
extends Area2D
class_name GravityZone

## 以下绝大部分代码用于渲染占位美术素材，与player.gd的交互在文件末尾。

## 只处理这个组里的物体，避免和场景里其他物体误触发。
const PLAYER_GROUP := "player"
## direction 枚举对应的方向向量，顺序必须和 @export_enum 一致。
const DIRS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

## 磁场场体的主色（紫色）。
const FIELD_COLOR := Color("#33284D")
## 场体填充透明度；边框和四角标记保持不透明。
const FIELD_ALPHA := 0.26
## 四角标记的边长，单位像素。
const CORNER_SIZE := 4.0
## 漂移石粒的颜色。
const STONE_COLOR := Color("#fff2e0")
## 石粒透明度。
const STONE_ALPHA := 0.55
## 石粒的边长，单位像素。
const STONE_SIZE := 2.0
## 石粒沿重力方向的漂移速度，单位像素/秒。
const STONE_SPEED := 10.0
## 每格生成几颗石粒（按格数算总数）。
const STONES_PER_TILE := 3
## 单个区最多生成几颗石粒，避免大区卡顿。
const MAX_STONES := 24
## 重力指向那一侧的边界高亮色。
const EDGE_HIGHLIGHT_COLOR := Color("D9C7FF")
## 重力侧高亮边的厚度，单位像素。
const EDGE_HIGHLIGHT_WIDTH := 4.0

## 重力拉力方向：0 上、1 右、2 下、3 左。
@export_enum("重力向上", "重力向右", "重力向下", "重力向左") var direction: int = 0:
	set(value):
		direction = clampi(value, 0, DIRS.size() - 1)
		if Engine.is_editor_hint():
			queue_redraw()
## 区域尺寸（格）；节点原点是左上角，向右下扩展。
@export var size_in_tiles: Vector2i = Vector2i(6, 8):
	set(value):
		size_in_tiles = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		if Engine.is_editor_hint():
			_rebuild()

## 区域的像素尺寸，由 size_in_tiles × Config.TILE_SIZE 算出。
var _zone_size: Vector2 = Vector2.ZERO
## 每颗石粒的局部坐标，_process() 每帧更新。
var _stones: Array[Vector2] = []

## 碰撞形状节点；_rebuild() 会按区域尺寸重新生成形状。
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


## 初始化：重建碰撞盒和石粒，并监听玩家进出。
## @tool 下（编辑器里）只负责画出区域，不连信号、不生成石粒。
func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## 按 size_in_tiles 算出像素尺寸，重新生成居中的碰撞矩形并重置石粒。
func _rebuild() -> void:
	var tiles := Vector2i(maxi(size_in_tiles.x, 1), maxi(size_in_tiles.y, 1))
	_zone_size = Vector2(tiles.x * Config.TILE_SIZE, tiles.y * Config.TILE_SIZE)

	var shape := RectangleShape2D.new()
	shape.size = _zone_size
	if _collision_shape:
		_collision_shape.shape = shape
		_collision_shape.position = _zone_size * 0.5

	# 编辑器里不撒石粒（每次重绘都重新随机会闪），只画区域轮廓。
	if not Engine.is_editor_hint():
		_spawn_stones(tiles)
	queue_redraw()


## 在场内随机撒石粒；数量随面积增长，但不超过 MAX_STONES。
func _spawn_stones(tiles: Vector2i) -> void:
	_stones.clear()

	var count := mini(tiles.x * tiles.y * STONES_PER_TILE, MAX_STONES)
	var limit := _zone_size - Vector2(STONE_SIZE, STONE_SIZE)
	for _i in count:
		_stones.append(Vector2(randf_range(0.0, limit.x), randf_range(0.0, limit.y)))


## 每帧让石粒沿重力方向漂移，越界后从另一侧绕回。
## 编辑器里不动（石粒是运行时表现），但要响应属性改动重画。
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _stones.is_empty():
		return

	var pull := _pull()
	var limit := _zone_size - Vector2(STONE_SIZE, STONE_SIZE)
	for i in _stones.size():
		var p := _stones[i] + pull * STONE_SPEED * delta
		if p.x < 0.0:
			p.x = limit.x
		elif p.x > limit.x:
			p.x = 0.0
		if p.y < 0.0:
			p.y = limit.y
		elif p.y > limit.y:
			p.y = 0.0
		_stones[i] = p
	queue_redraw()


## 画整个重力区：半透明场体、边框、四角标记、重力侧高亮边和石粒。
func _draw() -> void:
	if _zone_size == Vector2.ZERO:
		return

	var field := FIELD_COLOR
	field.a = FIELD_ALPHA
	draw_rect(Rect2(Vector2.ZERO, _zone_size), field)

	# 编辑器里边框画粗一点、再加个方向箭头，方便摆位时一眼认出这块是什么。
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, _zone_size), EDGE_HIGHLIGHT_COLOR, false, 2.0)
		_draw_corners()
		_draw_pull_edge()
		_draw_editor_arrow()
		return

	draw_rect(Rect2(Vector2.ZERO, _zone_size), FIELD_COLOR, false, 2.0)
	_draw_corners()
	_draw_pull_edge()
	_draw_stones()


## 编辑器专用：在场中央画一个方向箭头，标明这个区会把重力推向哪。
func _draw_editor_arrow() -> void:
	var c := _zone_size * 0.5
	var pull := _pull()
	# 箭头主体：从中心反向延伸到尖端
	var tail := c - pull * 20.0
	var head := c + pull * 20.0
	draw_line(tail, head, EDGE_HIGHLIGHT_COLOR, 3.0)
	# 箭头两翼
	var perp := pull.rotated(PI * 0.5)
	draw_line(head, head - pull * 10.0 + perp * 8.0, EDGE_HIGHLIGHT_COLOR, 3.0)
	draw_line(head, head - pull * 10.0 - perp * 8.0, EDGE_HIGHLIGHT_COLOR, 3.0)


## 在场体四个角各画一个 4×4 实心方块，强调区域边界。
func _draw_corners() -> void:
	var corner := Vector2(CORNER_SIZE, CORNER_SIZE)
	draw_rect(Rect2(Vector2.ZERO, corner), FIELD_COLOR)
	draw_rect(Rect2(Vector2(_zone_size.x - CORNER_SIZE, 0.0), corner), FIELD_COLOR)
	draw_rect(Rect2(Vector2(0.0, _zone_size.y - CORNER_SIZE), corner), FIELD_COLOR)
	draw_rect(Rect2(_zone_size - corner, corner), FIELD_COLOR)


## 画出所有石粒（STONE_SIZE × STONE_SIZE 像素）。
func _draw_stones() -> void:
	var stone_color := STONE_COLOR
	stone_color.a = STONE_ALPHA
	for stone in _stones:
		draw_rect(Rect2(stone.round(), Vector2(STONE_SIZE, STONE_SIZE)), stone_color)


## 在重力指向的一侧画一条更亮更粗的边界，代替箭头。
func _draw_pull_edge() -> void:
	var edge := Rect2(Vector2.ZERO, _zone_size)
	match clampi(direction, 0, DIRS.size() - 1):
		0:
			edge.size = Vector2(_zone_size.x, EDGE_HIGHLIGHT_WIDTH)
		1:
			edge.position = Vector2(_zone_size.x - EDGE_HIGHLIGHT_WIDTH, 0.0)
			edge.size = Vector2(EDGE_HIGHLIGHT_WIDTH, _zone_size.y)
		2:
			edge.position = Vector2(0.0, _zone_size.y - EDGE_HIGHLIGHT_WIDTH)
			edge.size = Vector2(_zone_size.x, EDGE_HIGHLIGHT_WIDTH)
		3:
			edge.size = Vector2(EDGE_HIGHLIGHT_WIDTH, _zone_size.y)
	draw_rect(edge, EDGE_HIGHLIGHT_COLOR)


## 把 direction 枚举换成对应的单位向量（重力拉力方向）。 
func _pull() -> Vector2:
	var pull: Vector2 = DIRS[clampi(direction, 0, DIRS.size() - 1)]
	return pull


## 玩家进入时通知玩家，并带上本区的重力拉力方向。
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		# 用 call，保持重力区不依赖玩家族的具体脚本类型
		body.call("enter_gravity_zone", self, _pull())


## 玩家离开时通知玩家；是否真的恢复重力由玩家判断。
func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		body.call("exit_gravity_zone", self)
