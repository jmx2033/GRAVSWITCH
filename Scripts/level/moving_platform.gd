extends AnimatableBody2D
class_name MovingPlatform

## 可动平台：从摆放位置向左右各移动 2 格，按 40 px/s 水平往返。
## 节点原点是平台左上角，实体部分 96×16，图片底下 4 px 是透明留边。

## 平台初始位置，往返运动以它为中点。
var _origin: Vector2


## 记录摆放位置并启动循环。
func _ready() -> void:
	_origin = position
	_start_loop()


## 用物理帧驱动的 Tween 做水平往返。
## 三段拼成闭环（中点→左端→右端→中点），循环时不会跳位。
func _start_loop() -> void:
	var travel := float(Config.MOVING_PLATFORM_TRAVEL_TILES * Config.TILE_SIZE)
	var leg_time := travel / Config.MOVING_PLATFORM_SPEED

	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.set_loops()
	tween.tween_property(self, "position", _origin + Vector2(-travel, 0.0), leg_time)
	tween.tween_property(self, "position", _origin + Vector2(travel, 0.0), leg_time * 2.0)
	tween.tween_property(self, "position", _origin, leg_time)
