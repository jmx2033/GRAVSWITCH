extends CharacterBody2D

## 180° 反转的判定容差（弧度）。
const FLIP_ANGLE_EPSILON := 0.001
## 180° 翻转开始时，若玩家贴地，沿新重力方向给这么点初速让它离地。
## 太小会被人和地板之间继续摩擦（速度仍被刮），太大会像"被弹了一下"，12 是试出来的。

## 玩家死亡时发出，由 game.gd 或关卡脚本接住切 DEAD 状态。
signal died

## 玩家通关时发出，由 game.gd 接住切 WIN 状态或切关。
signal won

## 真正起跳时发出，由音效脚本播放跳跃声。
signal jumped

## 落地时发出，impact_speed 是沿重力方向的冲击速度。
signal landed(impact_speed: float)

## 行走状态变化时发出，由音效脚本控制脚步声。
signal walking_changed(walking: bool)

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

# 上一物理帧是否贴地，用于检测落地瞬间。
var _was_on_floor: bool = false

# 当前是否处于行走状态；变化时发 walking_changed。
var _walking: bool = false

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
	# 【11/5 修】翻转期间不要立刻把 up_direction 反过去。
	# up_direction 一反向，脚下的地板对 move_and_slide 来说就成了"墙"，
	# 它会沿墙法线把水平速度清掉 —— 这就是"走进向上重力区速度就没了"的真正原因。
	# 所以翻转那 0.12 秒继续沿用旧方向，等翻完再切成新的。
	if not _turning:
		up_direction = -g

	# 施加合力重力；_gravity_scale 是当前强度（普通 1g、向下区 2g、失重 0 等）
	velocity += g * Config.GRAVITY * _gravity_scale * delta
	
	# 左右移动。
	# 【11/5 重写】不再每帧用 g 重新分解并重构 velocity：
	# 那样在重力方向翻转时，dot 投影再反投影会丢速度，
	# 而且 fall_speed 的符号会随 g 翻转，把下落速度变成上升速度。
	# 现在改成"增量修正"：只对"垂直于重力"的分量做加减，其余分量原样保留。
	var axis: float = Input.get_axis("move_left", "move_right")

	var on_axis: bool = (
		g.is_equal_approx(Vector2.DOWN) or g.is_equal_approx(Vector2.UP)
		or g.is_equal_approx(Vector2.LEFT) or g.is_equal_approx(Vector2.RIGHT)
	)

	var right_dir: Vector2 = Vector2.RIGHT
	if g.is_equal_approx(Vector2.LEFT) or g.is_equal_approx(Vector2.RIGHT):
		# 【11/5 修】重力朝左/朝右时，角色是"躺在侧墙上"的。
		# 原来写的是 g.rotated(-PI/2)：朝右时得到 (0,-1)，也就是屏幕上方，
		# 玩家一按 D 就被沿 -y 加速，看起来就是"进了水平重力区人往上飞"。
		# 现在固定让 D 走屏幕下方（沿墙往下走）、A 走上方，两个朝向手感一致。
		right_dir = Vector2.DOWN

	var side_speed: float = velocity.dot(right_dir) if on_axis else velocity.x

	# 目标侧向速度：有输入就加速/限速，没输入就减速。
	var target_side: float = side_speed
	if axis != 0.0:
		target_side = clampf(side_speed + axis * Config.ACCEL * delta,
			-Config.MAX_SPEED, Config.MAX_SPEED)
	elif on_axis:
		target_side = move_toward(side_speed, 0.0, Config.DECEL * delta)

	# 只加差值，不重构：沿重力方向的分量原样保留，翻转时不会被吃掉。
	velocity += right_dir * (target_side - side_speed)

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
		# 先把"沿重力方向"的速度清零，再加跳跃初速——同样用增量，不重构整个速度。
		var fall_now: float = velocity.dot(g)
		velocity -= g * fall_now
		velocity += (-g) * Config.JUMP_SPEED
		jump_timer = 0.0
		coyote_timer = 0.0
		jumped.emit()
	
	# 记录撞地前的沿重力速度；move_and_slide 落地后会把速度清零。
	var impact_speed: float = velocity.dot(g)

	# 交给引擎移动
	move_and_slide()

	# 落地：从空中转到贴地的那一帧，把冲击速度交给音效脚本。
	var on_floor_now: bool = is_on_floor()
	if on_floor_now and not _was_on_floor:
		landed.emit(impact_speed)
	_was_on_floor = on_floor_now

	# 行走状态：贴地且真的在移动；变化时通知音效脚本。
	var walking: bool = (
		is_on_floor()
		and axis != 0.0
		and absf(velocity.dot(right_dir)) > 1.0
	)
	_set_walking(walking)

	# 切动画
	var fall_speed: float = velocity.dot(g)
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

		# up_direction 在翻转期间保持旧方向（见 _physics_process 开头），
		# 这样脚下的地板不会被误判成"墙"，水平速度不会被 move_and_slide 清掉。

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
		# 180° 反转：原来的做法是把强度从 1 降到 0 再升回 1，
		# 玩家感觉是"重力先没了再回来"（向上区尤其明显：中途整段失重）。
		# 现在改成保持接近满强度，只在最中间一小段（±15%）降速，
		# 既能压住侧向甩动，又不会让人觉得重力"消失"了。
		# 不再把强度降到 0 或做"浅坑"：那正是玩家感觉"重力先没了再回来"的原因。
		# 增量式速度更新已经能避免甩动，所以强度直接线性切到目标即可。
		if weight < 0.5:
			_physics_gravity = _turn_from
		else:
			_physics_gravity = _turn_to
		_gravity_scale = lerpf(_turn_start_scale, _turn_target_scale, weight)
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
	# 转向结束，把 up_direction 切到新方向（翻转期间一直是旧值）。
	up_direction = -_turn_to


## 更新行走状态；变化时发信号，由音效脚本负责起停。
func _set_walking(walking: bool) -> void:
	if walking == _walking:
		return
	_walking = walking
	walking_changed.emit(walking)


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


## 重算重力：把所有"正在生效的区"折算成一个合力加速度。
##
## 【11/5 重写】原来写的是"基础向下 1g + 每个区补差"：向上区补 2g、
## 左右区补 1g 水平 + 1g 向上。这套算法把"基础重力已经存在"当成前提，
## 一旦两个区同时生效，y 分量就会累加 —— 表现就是站在水平重力区里人被往上顶。
##
## 改成自洽的写法：每个区只给出"它指向的那个方向"，不再补差。
## - 没有区生效 → 世界默认向下 1g
## - 朝上 / 朝左 / 朝右 → 该方向 1g
## - 朝下 → 该方向 2g（"加重"：跳得更矮、落得更快）
## - 多个区同时生效 → 各自的加速度相加，完全相抵时就是失重（加速度 0）
func _apply_gravity_zones() -> void:
	if _gravity_dirs.is_empty():
		Config.gravity_acceleration = Vector2.DOWN * Config.GRAVITY
		return

	var total := Vector2.ZERO
	for direction in _gravity_dirs.values():
		total += _zone_gravity(direction)
	Config.gravity_acceleration = total


## 单个重力区提供的加速度（自洽，不依赖"基础重力已存在"）。
## 朝下 2g 是"加重"的设定；其余三个方向各 1g。
func _zone_gravity(direction: Vector2) -> Vector2:
	var pull: Vector2 = direction.normalized() * Config.GRAVITY
	if direction.is_equal_approx(Vector2.DOWN):
		return pull * 2.0
	return pull


## 被通关区域通知时调用，进入通关状态；之后 die() 不再生效。
func win() -> void:
	if is_won or not is_alive:
		return
	is_won = true
	velocity = Vector2.ZERO
	_set_walking(false)
	won.emit()


## 被尖刺或出界通知时调用，进入死亡状态。
func die() -> void:
	if not is_alive or is_won:
		return
	is_alive = false
	velocity = Vector2.ZERO
	_set_walking(false)
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
	_set_walking(false)
	_was_on_floor = false
	anim.rotation = 0.0
	collision.rotation = 0.0
	anim.play("idle")
