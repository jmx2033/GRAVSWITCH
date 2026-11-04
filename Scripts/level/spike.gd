extends Area2D
class_name Spike

## 尖刺：玩家碰到后调用玩家的 die()，由玩家发出 died 信号。
##
## 占位图与碰撞多边形同为 32×32 的三角轮廓；
## 碰撞层是 spike（物理层 4），只探测玩家的物理层 2。

const PLAYER_GROUP := "player"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## 只处理玩家；其他物理体不触发死亡。
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(PLAYER_GROUP):
		body.call("die")
