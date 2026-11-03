extends CharacterBody2D

## 180° 反转的判定容差（弧度）。
const FLIP_ANGLE_EPSILON := 0.001

## 玩家死亡时发出，由 game.gd 或关卡脚本接住切 DEAD 状态。
signal died

## 玩家是否活着；死后停掉输入和重力。
var is_alive: bool = true

# 显示用的重力方向：只驱动角色贴图旋转，不影响物理。
var current_gravity: Vector2 = Vector2.DOWN

# 实际参与物理的重力方向；180° 反转时保持原方向，等强度降到 0 后再翻向。
var _physics_gravity: Vector2 = Vector2.DOWN

# 物理重力强度倍率：普通转向始终为 1；
# 180° 反转时按 1 → 0 → 1 变化，避免过渡期间出现侧向重力。
var _gravity_scale: float = 1.0

# 当前转向状态
var _turning: bool = false  # 是否正在转向
var _turn_is_flip: bool = false  # 本次是否为 180° 反转
var _turn_from: Vector2 = Vector2.DOWN  # 转向起点
var _turn_to: Vector2 = Vector2.DOWN  # 转向终点
var _turn_angle: float = 0.0  # 起点到终点的有符号夹角
var _turn_elapsed: float = 0.0  # 已转向时间，用于计算进度

# 动画节点，在 _ready() 里赋值
var anim: AnimatedSprite2D

# 碰撞盒节点，在 _ready() 里赋值
var collision: CollisionShape2D

# 土狼时间倒计时
var coyote_timer: float = 0.0

# 跳预输入倒计时
var jump_timer: float = 0.0

# 当前生效的重力区；只认最后进入的那个
var _active_zone: Area2D = null


func _ready() -> void:
	anim = $PlayerAnimated
	anim.play("idle")
	collision = $CollisionShape2D

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_update_gravity(delta)


	# 物理计算统一使用 _physics_gravity：
	# 180° 反转时它保持原方向，等强度降到 0 后才翻向，
	# 所以过渡期间不会产生侧向拉力。
	var g: Vector2 = _physics_gravity
	up_direction = -g

	# 加重力，往下掉；_gravity_scale 只在 180° 反转时小于 1
	velocity += g * Config.GRAVITY * _gravity_scale * delta

	# 左右移动（沿"垂直于重力"的方向，不是世界 x 轴）
	var right_dir: Vector2 = g.rotated(-PI / 2)
	var axis: float = Input.get_axis("move_left", "move_right")

	# 把速度拆成两部分：沿重力方向的下落速度、垂直于重力方向的横移速度
	var side_speed: float = velocity.dot(right_dir)
	var fall_speed: float = velocity.dot(g)

	if axis != 0.0:
		side_speed = side_speed + axis * Config.ACCEL * delta
		side_speed = clamp(side_speed, -Config.MAX_SPEED, Config.MAX_SPEED)
	else:
		side_speed = move_toward(side_speed, 0.0, Config.DECEL * delta)

	# 再拼回去
	velocity = right_dir * side_speed + g * fall_speed

	# 更新土狼时间
	if is_on_floor():
		coyote_timer = Config.COYOTE_TIME
	else:
		coyote_timer = coyote_timer - delta

	# 更新跳预输入
	if Input.is_action_just_pressed("jump"):
		jump_timer = Config.JUMP_BUFFER_TIME
	else:
		jump_timer = jump_timer - delta

	# 起跳（180° 反转的失重期不许跳，否则会顺着翻转后的重力飞出去）
	if jump_timer > 0.0 and coyote_timer > 0.0 and not _turn_is_flip:
		fall_speed = -Config.JUMP_SPEED
		velocity = right_dir * side_speed + g * fall_speed
		jump_timer = 0.0
		coyote_timer = 0.0
	
	# 交给引擎移动
	move_and_slide()

	# 切动画
	if not is_on_floor():
		if anim.animation != "idle":
			anim.play("idle")
	elif axis != 0.0:
		if anim.animation != "run":
			anim.play("run")
	else:
		if anim.animation != "idle":
			anim.play("idle")

	# 左右翻转：地面和空中都生效
	if axis < 0.0:
		anim.flip_h = true
	elif axis > 0.0:
		anim.flip_h = false

	# 角色贴图跟随显示方向旋转；180° 反转时会平滑转半圈
	anim.rotation = (-current_gravity).angle() + PI / 2
	collision.rotation = anim.rotation


## 推进重力转向。
## 90° 转向：物理方向和显示方向一起匀速旋转。
## 180° 反转：显示方向平滑转半圈，物理重力沿原轴按 1 → 0 → 1 衰减再反向，
## 中点是失重状态，不会出现把角色往侧面拉的横向重力。
func _update_gravity(delta: float) -> void:
	var target: Vector2 = Config.gravity_direction
	if target == Vector2.ZERO:
		return
	target = target.normalized()
	
	if _turning and not target.is_equal_approx(_turn_to):
		_turning = false
	
	# 没有正在进行的转向时，检查是否需要开始新的一次转向
	if not _turning:
		# 已经与目标一致，不需要转向
		if target.is_equal_approx(_physics_gravity):
			current_gravity = _physics_gravity
			_gravity_scale = 1.0
			return
		# 记录转向的起点、终点和夹角
		_turn_from = _physics_gravity
		_turn_to = target
		_turn_angle = _turn_from.angle_to(_turn_to)
		_turn_elapsed = 0.0
		# 夹角接近 180° 时按翻转处理
		_turn_is_flip = absf(_turn_angle) > PI - FLIP_ANGLE_EPSILON
		_turning = true

	# 转向时长与转角成正比，保证角速度与 GRAVITY_TURN_TIME 一致：
	# 90° 用时 GRAVITY_TURN_TIME / 2，180° 用时 GRAVITY_TURN_TIME。
	var turn_time: float = Config.GRAVITY_TURN_TIME * absf(_turn_angle) / PI
	if turn_time <= 0.0:
		_finish_gravity_turn()
		return
	_turn_elapsed = minf(_turn_elapsed + delta, turn_time)
	var weight: float = _turn_elapsed / turn_time

	# 显示方向始终平滑旋转，180° 时贴图会跟着转半圈
	current_gravity = _turn_from.rotated(_turn_angle * weight).normalized()

	if _turn_is_flip:
		# 180° 反转：signed_scale 从 1 线性降到 -1。
		# 前半程物理方向仍是起点，经过 0 后换成终点，
		# 因此重力始终沿同一条轴，只是先减弱到 0 再反向增强。
		var signed_scale: float = lerpf(1.0, -1.0, weight)
		_gravity_scale = absf(signed_scale)
		_physics_gravity = _turn_from if signed_scale >= 0.0 else _turn_to
	else:
		# 90° 转向：物理方向跟随显示方向，强度保持不变
		_gravity_scale = 1.0
		_physics_gravity = current_gravity

	# 到达终点，结束本次转向并精确对齐目标
	if _turn_elapsed >= turn_time:
		_finish_gravity_turn()


## 结束转向，把方向和强度精确复位到目标值。
func _finish_gravity_turn() -> void:
	_physics_gravity = _turn_to
	current_gravity = _turn_to
	_gravity_scale = 1.0
	_turning = false
	_turn_is_flip = false


## 进入重力区：记录当前区，并把目标重力切到该区的拉力方向。
func enter_gravity_zone(zone: Area2D, gravity_direction: Vector2) -> void:
	if gravity_direction == Vector2.ZERO:
		return
	_active_zone = zone
	Config.gravity_direction = gravity_direction


## 离开重力区：只有离开当前生效的区，才把目标重力恢复为向下。
func exit_gravity_zone(zone: Area2D) -> void:
	if zone != _active_zone:
		return
	_active_zone = null
	Config.gravity_direction = Vector2.DOWN


## 被尖刺或出界通知时调用，进入死亡状态。
func die() -> void:
	if not is_alive:
		return
	is_alive = false
	velocity = Vector2.ZERO
	anim.pause()
	died.emit()


## 重开时调用，把玩家恢复到指定位置并重置所有状态。
func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	current_gravity = Vector2.DOWN
	_physics_gravity = Vector2.DOWN
	Config.gravity_direction = Vector2.DOWN
	_gravity_scale = 1.0
	_turning = false
	_turn_is_flip = false
	coyote_timer = 0.0
	jump_timer = 0.0
	is_alive = true
	_active_zone = null
	anim.rotation = 0.0
	collision.rotation = 0.0
	anim.play("idle")





##测试区域
## 按 R
#func _input(event: InputEvent) -> void:
	#if event.is_action_pressed("restart"):
		#if is_alive:
			#print(">>> 调用 die()")
			#die()
		#else:
			#print(">>> 调用 respawn()")
			#respawn(Vector2(320, 200))
