extends Area2D
class_name LevelGoal

## 通关判定：透明的 32×32 区域，玩家碰到后调用玩家的 win()。
##
## 节点原点是格子左上角，区域恰好覆盖一个 tile；
## 没有美术素材，也不显示任何图形。

const PLAYER_GROUP := "player"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## 只处理玩家；其他物理体不触发通关。
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		body.call("win")
