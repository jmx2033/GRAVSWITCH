extends Node

## 主场景控制器：加载关卡，统一处理死亡重生和 R 重载。
##
## 关卡只负责地形与出生点；存活流程集中在这里，换关或加状态机时不用改玩家脚本。

## 要加载的起始关卡场景。
@export var start_level: PackedScene
## 通关后自动切换到的下一关；没有下一关时留空，通关后停留在当前关。
@export var next_level: PackedScene

## 负责 Config.RESPAWN_DELAY 秒后的重生；超时后把玩家送回出生点。
@onready var _respawn_timer: Timer = $RespawnTimer

# 当前关卡实例，切关时先卸载它。
var _current_level: Node = null
# 当前关卡的玩家，通过 player 组查找；关卡重新加载后会重新获取。
var _player: Node = null
# 当前关卡的出生点，来自关卡里的 Spawn 节点。
var _spawn_position: Vector2 = Vector2.ZERO


## 初始化重生计时器并加载起始关卡。
func _ready() -> void:
	# 场景里的 wait_time 只是默认值，实际时长以 Config 为准，方便统一调整。
	_respawn_timer.wait_time = Config.RESPAWN_DELAY
	_respawn_timer.timeout.connect(_on_respawn_timer_timeout)

	if start_level == null:
		push_error("game.gd：start_level 未设置")
		return
	_load_level(start_level)


## R 键重载当前场景；放在 _unhandled_input 里，不抢 UI 的输入。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()


## 切换到指定关卡场景；传 null 时什么也不做。
func change_level(level_scene: PackedScene) -> void:
	if level_scene == null:
		return
	if is_instance_valid(_current_level):
		remove_child(_current_level)
		_current_level.queue_free()
	_respawn_timer.stop()
	_load_level(level_scene)


## 加载关卡：重置全局重力，缓存出生点，并连接玩家的 died / won 信号。
func _load_level(level_scene: PackedScene) -> void:
	# 重载场景时 autoload 不会重置；先恢复基础向下重力，避免残留上一局的合力。
	Config.gravity_acceleration = Vector2.DOWN * Config.GRAVITY
	_respawn_timer.stop()

	var level: Node = level_scene.instantiate()
	add_child(level)
	_current_level = level

	var spawn: Node2D = level.get_node_or_null("Spawn") as Node2D
	if spawn != null:
		_spawn_position = spawn.global_position
	else:
		push_warning("game.gd：关卡缺少 Spawn，重生点使用 (0, 0)")

	_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		push_error("game.gd：关卡里找不到 player 组的节点")
		return
	# 缺信号时只报错并跳过连接，避免 connect 在运行时抛错。
	if not _player.has_signal("died"):
		push_error("game.gd：玩家节点缺少 died 信号")
		return
	_player.connect("died", _on_player_died)
	if not _player.has_signal("won"):
		push_error("game.gd：玩家节点缺少 won 信号")
		return
	_player.connect("won", _on_player_won)


## 玩家死亡后启动重生计时；die() 已幂等，这里不用防重复。
func _on_player_died() -> void:
	_respawn_timer.start()


## 计时结束，把玩家送回缓存的出生点。
func _on_respawn_timer_timeout() -> void:
	if not is_instance_valid(_player):
		return
	_player.call("respawn", _spawn_position)


## 玩家通关后停掉重生计时；配置了下一关就切过去，否则停留在当前关。
func _on_player_won() -> void:
	_respawn_timer.stop()
	if next_level != null:
		change_level.call_deferred(next_level)
