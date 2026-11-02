extends CharacterBody2D

@onready var anim: AnimatedSprite2D = $PlayerAnimated

var _coyote: float = 0.0
var _buffer: float = 0.0

func _physics_process(delta: float) -> void:
	var g: Vector2 = Config.gravity_direction
	up_direction = -g

	velocity += g * Config.GRAVITY * delta

	var axis := Input.get_axis("move_left", "move_right")
	var target := axis * Config.MAX_SPEED
	var rate := Config.ACCEL if absf(axis) > 0.01 else Config.DECEL
	velocity.x = move_toward(velocity.x, target, rate * delta)

	if is_on_floor():
		_coyote = Config.COYOTE_TIME
	else:
		_coyote -= delta

	if Input.is_action_just_pressed("jump"):
		_buffer = Config.JUMP_BUFFER_TIME
	else:
		_buffer -= delta

	if _buffer > 0.0 and _coyote > 0.0:
		velocity += -g * Config.JUMP_SPEED
		_buffer = 0.0
		_coyote = 0.0

	move_and_slide()
	_update_animation(axis)

func _update_animation(axis: float) -> void:
	if not is_on_floor():
		anim.animation = "idle"
	elif absf(axis) > 0.01:
		anim.animation = "run"
	else:
		anim.animation = "idle"
