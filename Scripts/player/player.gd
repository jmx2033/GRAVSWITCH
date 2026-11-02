extends CharacterBody2D

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
	# 1. 读重力方向
	var g: Vector2 = Config.gravity_direction
	up_direction = -g

	# 2. 加重力，往下掉
	velocity += g * Config.GRAVITY * delta

	# 3. 左右移动
	var axis: float = Input.get_axis("move_left", "move_right")
	if axis != 0.0:
		velocity.x = velocity.x + axis * Config.ACCEL * delta
		velocity.x = clamp(velocity.x, -Config.MAX_SPEED, Config.MAX_SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0.0, Config.DECEL * delta)

	# 4. 更新土狼时间
	if is_on_floor():
		coyote_timer = Config.COYOTE_TIME
	else:
		coyote_timer = coyote_timer - delta

	# 5. 更新跳预输入
	if Input.is_action_just_pressed("jump"):
		jump_timer = Config.JUMP_BUFFER_TIME
	else:
		jump_timer = jump_timer - delta

	# 6. 起跳
	if jump_timer > 0.0 and coyote_timer > 0.0:
		velocity += (-g) * Config.JUMP_SPEED
		jump_timer = 0.0
		coyote_timer = 0.0

	# 7. 交给引擎移动
	move_and_slide()

		# 8. 切动画
	if not is_on_floor():
		if anim.animation != "idle":
			anim.play("idle")
	elif axis != 0.0:
		if anim.animation != "run":
			anim.play("run")
	else:
		if anim.animation != "idle":
			anim.play("idle")

	# 9. 左右翻转：地面和空中都生效
	if axis < 0.0:
		anim.flip_h = true
	elif axis > 0.0:
		anim.flip_h = false
