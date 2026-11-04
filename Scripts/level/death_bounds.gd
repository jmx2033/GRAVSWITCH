extends Node

## 出界死亡组件：每物理帧检查玩家中心点是否离开关卡矩形。
##
## 关卡矩形由 Config.LEVEL_SIZE 定义（20×11 格 = 640×352），
## 不是屏幕的 640×360；四条边都可以出界。

# 当前关卡的玩家，通过 player 组查找；关卡重载后会自动重新获取。
var _player: Node2D = null


## 玩家中心点越过任意一条边时调用 die()；die() 已幂等，这里不用防重复。
func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return

	# global_position 是碰撞箱中心；出界按中心点判定，不按碰撞箱边缘。
	# 边界是 0..640 / 0..352，恰好贴线不算出界。
	var center: Vector2 = _player.global_position
	if center.x < 0.0 or center.x > Config.LEVEL_SIZE.x:
		_player.die()
	elif center.y < 0.0 or center.y > Config.LEVEL_SIZE.y:
		_player.die()
