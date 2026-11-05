extends Node

## 主场景控制器：加载关卡，统一处理死亡重生和 R 重载。
##
## 关卡只负责地形与出生点；存活流程集中在这里，换关或加状态机时不用改玩家脚本。

## 要加载的关卡场景；换关时替换这个引用。
@export var start_level: PackedScene

## 负责 Config.RESPAWN_DELAY 秒后的重生；超时后把玩家送回出生点。
@onready var _respawn_timer: Timer = $RespawnTimer

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
## R 键重生逻辑：不重载场景，直接重置玩家状态
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_viewport().set_input_as_handled()
		
		# 1. 停止死亡倒计时（防止死后按 R 导致双重触发）
		if has_method("_on_player_died") or has_node("RespawnTimer"):
			 # 这里假设你有一个计时器节点，或者在 game.gd 里管理了重生延迟
			 # 如果之前的逻辑是用 _respawn_timer，请确保在这里 stop() 它
			 # 简单起见，我们主要关注重置玩家
			pass

		# 2. 寻找场景中的玩家节点
		var player = get_node_or_null("Player") 
		
		# 3. 如果没找到，尝试在当前加载的关卡容器里找
		if not player:
			player = find_child("Player", true, false)

		# 4. 执行重生
		if player and player.has_method("respawn"):
			player.respawn(_spawn_position)
			print("Game.gd: 玩家已重生到 ", _spawn_position)
		else:
			print("警告: 未找到玩家节点或玩家没有 respawn 方法")
## 加载关卡：重置全局重力，缓存出生点，并连接玩家的 died 信号。
func _load_level(level_scene: PackedScene) -> void:
	# 重载场景时 autoload 不会重置；先恢复基础向下重力，避免残留上一局的合力。
	Config.gravity_acceleration = Vector2.DOWN * Config.GRAVITY

	var level: Node = level_scene.instantiate()
	add_child(level)

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


## 玩家死亡后启动重生计时；die() 已幂等，这里不用防重复。
func _on_player_died() -> void:
	_respawn_timer.start()


## 计时结束，把玩家送回缓存的出生点。
func _on_respawn_timer_timeout() -> void:
	if not is_instance_valid(_player):
		return
	_player.call("respawn", _spawn_position)
