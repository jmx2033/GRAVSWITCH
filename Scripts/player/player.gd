extends CharacterBody2D

## 180° 反转的判定容差（弧度）。
const FLIP_ANGLE_EPSILON := 0.001

## 玩家死亡时发出，由 game.gd 或关卡脚本接住切 DEAD 状态。
signal died

## 玩家通关时发出，由 game.gd 接住切 WIN 状态或切关。
signal won

## 玩家是否活着；死后停掉输入和重力。
var is_alive: bool = true

## 玩家是否已通关；通关后停掉输入和重力，die() 不再生效。
var is_won: bool = false

# 显示用的重力方向：只驱动角色贴图旋转，不影响物理。
var current_gravity: Vector2 = Vector2.DOWN

# 实际参与物理的重力方向；180° 反转时保持原方向，等强度降到 0 后再翻向。
var _physics_gravity: Vector2 = Vector2.DOWN

# 当前物理重力强度倍率（以 Config.GRAVITY 为 1g）：
# 无区为 1，向下区为 2，失重为 0；转向时在旧/新强度之间过渡。
var _gravity_scale: float = 1.0

# 当前转向状态
var _turning: bool = false  # 是否正在转向
var _turn_is_flip: bool = false  # 本次是否为 180° 反转
var _turn_from: Vector2 = Vector2.DOWN  # 转向起点方向
var _turn_to: Vector2 = Vector2.DOWN  # 转向终点方向
var _turn_angle: float = 0.0  # 起点到终点的有符号夹角
var _turn_elapsed: float = 0.0  # 已转向时间，用于计算进度
var _turn_start_scale: float = 1.0  # 转向开始时的重力强度
var _turn_target_scale: float = 1.0  # 转向结束时的重力强度

# 动画节点，在 _ready() 里赋值
var anim: AnimatedSprite2D

# 碰撞盒节点，在 _ready() 里赋值
var collision: CollisionShape2D

# 土狼时间倒计时
var coyote_timer: float = 0.0

# 跳预输入倒计时
var jump_timer: float = 0.0

# 玩家当前重叠的重力区 -> 拉力方向；叠加时按各区的加速度贡献计算
var _gravity_dirs: Dictionary = {}


func _ready() -> void:
	anim = $PlayerAnimated
	anim.play("idle")
	collision = $CollisionShape2D

func _physics_process(delta: float) -> void:
	if not is_alive or is_won:
		return
	_update_gravity(delta)


	# 物理计算统一使用 _physics_gravity：
	# 180° 反转时它保持原方向，等强度降到 0 后才翻向，
	# 所以过渡期间不会产生侧向拉力。
	var g: Vector2 = _physics_gravity
	up_direction = -g

	# 施加合力重力；_gravity_scale 是当前强度（普通 1g、向下区 2g、失重 0 等）
	velocity += g * Config.GRAVITY * _gravity_scale * delta
	
	# 左右移动（沿"垂直于重力"的方向，不是世界 x 轴）
	# 重力正上/正下时固定为屏幕右：倒立站天花板后按 D 仍然往右走，
	# 不跟着角色朝向反向，操作习惯不变。
	#
	# 转向过渡期的 g 是斜的，此时不能做"沿 g / 垂直 g"的分解：
	# 那样会把原来的速度投影到斜轴上，水平和竖直分量都缩水（表现为"一进区就不动了"）。
	# 所以过渡期只加重力、保持 velocity 原样，等 g 回到主轴再分解。
	var axis: float = Input.get_axis("move_left", "move_right")
	var fall_speed: float = velocity.dot(g)
	# 侧向速度提到外层：起跳那一段要重新拼 velocity 时也得用它。
	var side_speed: float = 0.0
	var right_dir: Vector2 = Vector2.RIGHT

	var on_axis: bool = (
		g.is_equal_approx(Vector2.DOWN) or g.is_equal_approx(Vector2.UP)
		or g.is_equal_approx(Vector2.LEFT) or g.is_equal_approx(Vector2.RIGHT)
	)

	if on_axis:
		if g.is_equal_approx(Vector2.DOWN) or g.is_equal_approx(Vector2.UP):
			right_dir = Vector2.RIGHT
		else:
			right_dir = g.rotated(-PI / 2)

		# 把速度拆成两部分：沿重力方向的下落速度、垂直于重力方向的横移速度
		side_speed = velocity.dot(right_dir)

		if axis != 0.0:
			side_speed = side_speed + axis * Config.ACCEL * delta
			side_speed = clamp(side_speed, -Config.MAX_SPEED, Config.MAX_SPEED)
		else:
			side_speed = move_toward(side_speed, 0.0, Config.DECEL * delta)

		# 再拼回去
		velocity = right_dir * side_speed + g * fall_speed
	else:
		# 过渡期：g 是斜的，不能按"沿 g / 垂直 g"分解（会把速度投影缩水）。
		# 但按键不能失灵——所以在世界 X 轴上直接加减速度，
		# 不做分解、也不重拼，速度大小不会被这次转向吃掉。
		var vx: float = velocity.x
		if axis != 0.0:
			vx = vx + axis * Config.ACCEL * delta
			vx = clampf(vx, -Config.MAX_SPEED, Config.MAX_SPEED)
		else:
			vx = move_toward(vx, 0.0, Config.DECEL * delta)
		velocity.x = vx

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
	# 过渡期 g 是斜的，此时拼 velocity 会把侧向速度拆歪，所以只在主轴上拼。
	if jump_timer > 0.0 and coyote_timer > 0.0 and not _turn_is_flip and on_axis:
		fall_speed = -Config.JUMP_SPEED
		velocity = right_dir * side_speed + g * fall_speed
		jump_timer = 0.0
		coyote_timer = 0.0
	
	# 交给引擎移动
	move_and_slide()

	# 切动画
	if not is_on_floor():
		# 空中分两种：还往上冲（fall_speed < 0）播 jump，往下掉播 fall。
		# fall_speed 是"沿重力方向"的速度，负值代表在跟重力反着走 = 上升。
		if fall_speed < 0.0:
			if anim.animation != "jump":
				anim.play("jump")
		else:
			if anim.animation != "fall":
				anim.play("fall")
	elif axis != 0.0:
		if anim.animation != "run":
			anim.play("run")
	else:
		if anim.animation != "idle":
			anim.play("idle")

	# 左右翻转：地面和空中都生效
	# 倒立（重力朝上）时要把翻转反过来：
	# 旋转 180° 后精灵自身的"右"在屏幕上变成了"左"。
	var upside_down: bool = _physics_gravity.y < 0.0
	if axis < 0.0:
		anim.flip_h = not upside_down
	elif axis > 0.0:
		anim.flip_h = upside_down
	
	# 角色贴图跟随显示方向旋转；180° 反转时会平滑转半圈
	anim.rotation = (-current_gravity).angle() + PI / 2

	# 180° 反转期间碰撞箱不跟转：
	# 旋转中的包围盒会短暂变化，让重力区误判玩家进出，把目标重力改回去。
	if not _turn_is_flip:
		collision.rotation = anim.rotation


## 推进重力转向。
## 目标加速度由基础重力和所有重叠区叠加得到：方向负责旋转，强度负责加速度大小。
## 180° 反转时前半程沿旧方向衰减到 0，后半程沿新方向增强，避免侧向甩动。
func _update_gravity(delta: float) -> void:
	var target_accel: Vector2 = Config.gravity_acceleration

	# 合力为 0：失重。保留当前朝向，但不再产生重力加速度。
	if target_accel.is_zero_approx():
		_physics_gravity = current_gravity
		_gravity_scale = 0.0
		_turning = false
		_turn_is_flip = false
		return

	var target: Vector2 = target_accel.normalized()
	var target_strength: float = target_accel.length() / Config.GRAVITY

	if _turning:
		if not target.is_equal_approx(_turn_to):
			_turning = false
		else:
			_turn_target_scale = target_strength

	# 没有正在进行的转向时，检查是否需要开始新的一次转向
	if not _turning:
		# 方向已经一致：只更新强度，不需要转向
		if target.is_equal_approx(_physics_gravity):
			current_gravity = _physics_gravity
			_gravity_scale = target_strength
			# 180° 反转前半程离开重力区时，目标会变回旧方向；
			# 这里提前返回，必须清掉禁止起跳标记，否则会永久不能跳
			_turning = false
			_turn_is_flip = false
			return
		# 记录转向的起点、终点、夹角和强度
		_turn_from = _physics_gravity
		_turn_to = target
		_turn_angle = _turn_from.angle_to(_turn_to)
		_turn_elapsed = 0.0
		_turn_start_scale = _gravity_scale
		_turn_target_scale = target_strength
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
		# 180° 反转：前半程沿旧方向把强度降到 0，
		# 后半程沿新方向把强度升到目标值。
		if weight < 0.5:
			_physics_gravity = _turn_from
			_gravity_scale = lerpf(_turn_start_scale, 0.0, weight * 2.0)
		else:
			_physics_gravity = _turn_to
			_gravity_scale = lerpf(0.0, _turn_target_scale, (weight - 0.5) * 2.0)
	else:
		# 小于 180° 的转向：物理方向跟随显示方向，强度同步插值
		_physics_gravity = current_gravity
		_gravity_scale = lerpf(_turn_start_scale, _turn_target_scale, weight)

	# 到达终点，结束本次转向并精确对齐目标
	if _turn_elapsed >= turn_time:
		_finish_gravity_turn()


## 结束转向，把方向和强度精确复位到目标值。
func _finish_gravity_turn() -> void:
	_physics_gravity = _turn_to
	current_gravity = _turn_to
	_gravity_scale = _turn_target_scale
	_turning = false
	_turn_is_flip = false


## 进入重力区：记录该区的拉力方向，并重算所有重叠区的合力。
func enter_gravity_zone(zone: Area2D, gravity_direction: Vector2) -> void:
	if gravity_direction == Vector2.ZERO:
		return
	_gravity_dirs[zone] = gravity_direction
	_apply_gravity_zones()


## 离开重力区：移除该区的拉力，并重算剩余重叠区的合力。
func exit_gravity_zone(zone: Area2D) -> void:
	_gravity_dirs.erase(zone)
	_apply_gravity_zones()


## 重算重力：基础向下重力 + 所有重叠区的贡献。
func _apply_gravity_zones() -> void:
	var total := Vector2.DOWN * Config.GRAVITY
	for direction in _gravity_dirs.values():
		var pull: Vector2 = direction
		total += _zone_gravity(pull)
	Config.gravity_acceleration = total


## 单个重力区提供的加速度：
## 向上区 2g（多出的 1g 抵消基础重力，净向上 1g）；
## 向下区 1g；
## 左/右区 1g 水平 + 1g 向上（抵消基础重力，净水平 1g）。
func _zone_gravity(direction: Vector2) -> Vector2:
	var pull: Vector2 = direction * Config.GRAVITY
	if direction.is_equal_approx(Vector2.UP):
		return pull * 2.0
	if direction.is_equal_approx(Vector2.DOWN):
		return pull
	return pull + Vector2.UP * Config.GRAVITY


## 被通关区域通知时调用，进入通关状态；之后 die() 不再生效。
func win() -> void:
	if is_won or not is_alive:
		return
	is_won = true
	velocity = Vector2.ZERO
	won.emit()


## 被尖刺或出界通知时调用，进入死亡状态。
func die() -> void:
	if not is_alive or is_won:
		return
	is_alive = false
	velocity = Vector2.ZERO
	# 死亡动画：不循环，播完停在最后一帧（人形消散后是泡沫）。
	anim.play("die")
	died.emit()


## 重开时调用，把玩家恢复到指定位置并重置所有状态。
func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	current_gravity = Vector2.DOWN
	_physics_gravity = Vector2.DOWN
	Config.gravity_acceleration = Vector2.DOWN * Config.GRAVITY
	_gravity_scale = 1.0
	_turning = false
	_turn_is_flip = false
	coyote_timer = 0.0
	jump_timer = 0.0
	is_alive = true
	is_won = false
	_gravity_dirs.clear()
	anim.rotation = 0.0
	collision.rotation = 0.0
	anim.play("idle")





#测试区域
# 按 R
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		if is_alive:
			print(">>> 调用 die()")
			die()
		else:
			print(">>> 调用 respawn()")
			respawn(Vector2(50, 300))
