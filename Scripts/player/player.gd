extends CharacterBody2D

# 当前重力方向
var current_gravity: Vector2 = Vector2.DOWN

# 动画节点，在 _ready() 里赋值
var anim: AnimatedSprite2D

# 土狼时间倒计时
var coyote_timer: float = 0.0

# 跳预输入倒计时
var jump_timer: float = 0.0


func _ready() -> void:
	anim = $PlayerAnimated
	anim.play("idle")

func _physics_process(delta: float) -> void:
	
	#测试区域
	#if Input.is_physical_key_pressed(KEY_L):
		#if Config.gravity_direction != Vector2.RIGHT:
			#print(">>> 重力切到右边")
		#Config.gravity_direction = Vector2.RIGHT
	#elif Input.is_physical_key_pressed(KEY_I):
		#if Config.gravity_direction != Vector2.UP:
			#print(">>> 重力切到上边")
		#Config.gravity_direction = Vector2.UP
	#elif Input.is_physical_key_pressed(KEY_J):
		#if Config.gravity_direction != Vector2.LEFT:
			#print(">>> 重力切到左边")
		#Config.gravity_direction = Vector2.LEFT
	#else:
		#if Config.gravity_direction != Vector2.DOWN:
			#print(">>> 重力切回下边")
		#Config.gravity_direction = Vector2.DOWN
	#测试区域
	
	# 让当前重力朝目标平滑靠拢
	var diff: float = angle_difference(current_gravity.angle(), Config.gravity_direction.angle())
	var max_turn: float = (PI / Config.GRAVITY_TURN_TIME) * delta
	if absf(diff) <= max_turn:
		current_gravity = Config.gravity_direction
	else:
		current_gravity = current_gravity.rotated(signf(diff) * max_turn)

	# 用平滑后的方向
	var g: Vector2 = current_gravity
	up_direction = -g
	
	# 加重力，往下掉
	velocity += g * Config.GRAVITY * delta



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

	# 起跳
	if jump_timer > 0.0 and coyote_timer > 0.0:
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

	# 角色跟着重力旋转
	anim.rotation = (-current_gravity).angle() + PI / 2
