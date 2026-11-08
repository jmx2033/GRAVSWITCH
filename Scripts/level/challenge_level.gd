extends Node2D

## 挑战关控制器：挑战关不走 game.gd 那套四关流程，所以自己监听玩家通关并显示结算页。
##
## 与 game.gd 的分工：game.gd 管四关顺序切换与重生，这里只管「通关了 → 弹结算页 → 重开或回主菜单」。
## 结算页是同一个 Scenes/win_panel.tscn，视觉与四关通关完全一致。

## 走到终点后弹出结算页；不接 main.tscn 的通关流程。
const WIN_PANEL_SCENE := preload("res://Scenes/win_panel.tscn")

## 暂停菜单场景。四关由 game.gd 挂载；挑战关是独立场景，得自己挂一份。
const PAUSE_MENU_SCENE := preload("res://Scenes/pause_menu.tscn")

## 结算页要盖在关卡之上。
const OVERLAY_Z_INDEX := 100

@onready var _spawn: Marker2D = $Spawn
@onready var _player: Node = $Player
## 重力区容器；场景里没摆区就是 null，此时整套"区内锁"自动跳过。
@onready var _zones: Node2D = get_node_or_null("Zones") as Node2D

# 运行时实例化的结算页；默认隐藏。
var _win_panel: Control = null

## 玩家当前重叠的重力区数量。>0 时收回玩家的"主动改重力"能力。
var _zone_overlap: int = 0

## 玩家脚本是否认这个开关。不认就只警告一次，不去每帧写不存在的属性。
var _can_lock_shift: bool = false

## 重生计时器：与四关的 RespawnTimer 行为一致（Config.RESPAWN_DELAY 秒后送回出生点）。
## 四关的计时器挂在 game.gd 的主场景上；挑战关是独立场景，所以自己建一个。
var _respawn_timer: Timer = null

## 暂停菜单；四关由 game.gd 挂载，挑战关自己挂一份。
var _pause_menu: Control = null


func _ready() -> void:
	_win_panel = WIN_PANEL_SCENE.instantiate()
	add_child(_win_panel)
	_win_panel.z_index = OVERLAY_Z_INDEX
	_win_panel.retry_pressed.connect(_on_win_retry)
	_win_panel.menu_pressed.connect(_on_win_menu)
	_win_panel.get_node("%Content").visible = false
	# 挑战关根节点是 Node2D，结算页挂在它下面拿不到视口矩形，
	# anchors 会退化成 0×0 而被摆到左上角。所以显式把它铺满屏幕。
	_fit_to_viewport()
	_win_panel.resized.connect(_fit_to_viewport)

	# 暂停菜单：四关由 game.gd 挂载，挑战关是独立场景得自己挂。
	# 与结算页同样的道理——根节点是 Node2D，Control 的 anchors 拿不到父矩形，
	# 所以也显式铺满视口；z_index 用同一个覆盖层值。
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	add_child(_pause_menu)
	_pause_menu.z_index = OVERLAY_Z_INDEX
	_pause_menu.quit_to_menu.connect(_on_win_menu)
	_pin_to_rect(_pause_menu, get_viewport_rect().size)
	# 不要把它 visible 设成 false：不可见的 Control 不处理输入，暂停键就收不到了。
	# 显示由内部的 Content 容器控制（pause_menu.gd 里做）。

	if not _player.has_signal("won"):
		push_error("challenge_level.gd：玩家节点缺少 won 信号")
		return
	_player.connect("won", _on_player_won)

	# 死亡后自动复活（四关由 game.gd 的 RespawnTimer 负责，挑战关自己建一个）
	_setup_respawn()

	# 挑战关专属：授权玩家在空中按「方向 + 空格」主动改变重力方向。
	# 四关不调用这个方法，所以那边的手感与之前完全一致。
	if _player.has_method("enable_gravity_shift"):
		_player.call("enable_gravity_shift")

	# 重力区优先级：玩家在区里时临时收回上面这个能力（见 _lock_shift 的说明）。
	_bind_gravity_zones()


## 让结算页铺满整个视口。
##
## 挑战关根节点是 Node2D，结算页挂它下面拿不到父容器的矩形，而 .tscn 里用的是
## anchors_preset=15（四边拉满），没有可参照的父矩形时尺寸会退化成 0×0，
## 面板就被摆到左上角。所以这里把 anchors 清掉、改成纯绝对尺寸。
## （必须先改 anchors：否则 Godot 会在 _ready 之后按 anchors 重算尺寸，覆盖掉设值。）
func _fit_to_viewport() -> void:
	if _win_panel == null:
		return
	var vp_size := get_viewport_rect().size
	_pin_to_rect(_win_panel, vp_size)
	var content: Control = _win_panel.get_node("%Content")
	_pin_to_rect(content, vp_size)


## 把一个 Control 钉成 (0,0)–size 的绝对矩形，不受 anchors 影响。
func _pin_to_rect(ctrl: Control, rect_size: Vector2) -> void:
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctrl.position = Vector2.ZERO
	ctrl.size = rect_size


## 通关音效响多久之后再弹结算页；与 game.gd 的 WIN_PANEL_DELAY 保持一致。
const WIN_PANEL_DELAY := 0.3


## 玩家通关：等通关音效先响一下，再冻结整棵树并显示结算页。
## 与四关通关的观感一致：先听到琶音，画面才压暗。
func _on_player_won() -> void:
	# 停掉重生倒计时：通关瞬间若刚好在死亡倒计时里，等人回来会被拽回出生点
	_stop_respawn_timer()
	# 计时器参数 process_always 默认 true，暂停后也会照常走完。
	await get_tree().create_timer(WIN_PANEL_DELAY).timeout
	get_tree().paused = true
	_win_panel.get_node("%Content").visible = true
	_win_panel.open()


## 点「再玩一次」：挑战关只有这一关，所以重开本关。
## 重开用 respawn 而不是重新加载场景，避免结算页实例被销毁后信号断掉。
func _on_win_retry() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	if not is_instance_valid(_player):
		return
	_player.call("respawn", _spawn.global_position)
	# 重开时复位区锁状态，与死亡复活的处理保持一致
	_zone_overlap = 0
	_set_shift_locked(false)


## 点「回主菜单」：解除暂停并切回主菜单。
func _on_win_menu() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	Transition.transition(
		func() -> void: get_tree().change_scene_to_file("res://Scenes/mainmenu.tscn"),
		true
	)


## 绑定 Zones 下所有重力区的进出信号。
##
## 本项目的 Zones 节点下只放重力区，所以按 Area2D 判断即可，
## 不依赖 gravity_zone.gd 的 class_name（改脚本名也不会让这里解析失败）。
func _bind_gravity_zones() -> void:
	if _zones == null:
		return
	# 玩家脚本里是 _gravity_shift_enabled: bool，默认 false，所以用 get() 判存在：
	# 属性不存在时 get() 返回 null，存在时一定是 true/false。
	_can_lock_shift = _player.get("_gravity_shift_enabled") != null
	if not _can_lock_shift:
		push_warning("challenge_level.gd：玩家脚本没有 _gravity_shift_enabled，重力区压不住主动改重力")
		return
	for zone in _zones.get_children():
		if zone is Area2D:
			zone.body_entered.connect(_on_zone_body_entered)
			zone.body_exited.connect(_on_zone_body_exited)


## 玩家进入某个重力区：计数加一，并收回主动改重力能力。
func _on_zone_body_entered(body: Node2D) -> void:
	if body != _player:
		return
	_zone_overlap += 1
	_set_shift_locked(true)


## 玩家离开某个重力区：计数减一，全部离开后才恢复能力。
## 用计数而不是布尔，是为了覆盖两个区首尾相接、走出去的瞬间已经站在另一个区里的情况。
func _on_zone_body_exited(body: Node2D) -> void:
	if body != _player:
		return
	_zone_overlap = maxi(_zone_overlap - 1, 0)
	if _zone_overlap == 0:
		_set_shift_locked(false)


## 写玩家脚本里的开关。locked 为 true 就是"区内禁止主动改重力"。
##
## 为什么用 set() 而不给 player.gd 加方法：四关共用 player.gd，
## 这次只允许改挑战关，所以宁愿在挑战关这边写一下私有字段，
## 也不去动会被四关一起影响的共享脚本。
## 关掉之后 player.gd 的 _try_gravity_shift() 第一行就返回 false，
## 按「方向 + 空格」会照常走跳跃流程——不会被吃掉，也不会把方向
## 排队到出区之后再翻过去。
func _set_shift_locked(locked: bool) -> void:
	if not _can_lock_shift or not is_instance_valid(_player):
		return
	_player.set("_gravity_shift_enabled", not locked)


## 处理 R 键重开。
##
## 四关的 R 是「重新加载整关场景」（game.gd 的 change_level）；挑战关不能这么干——
## 重新加载会把运行时创建的结算页、暂停菜单、重生计时器全销毁，信号连接断掉。
## 所以这里改成「把玩家送回出生点」，观感上等价于重开本关。
##
## 放在 _unhandled_input 里，不抢 UI 的输入；暂停时本节点被冻结，
## 所以要重开得先按 Esc 恢复（与四关一致）。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("restart"):
		return
	get_viewport().set_input_as_handled()
	_restart_level()


## 重开本关：送回出生点并复位所有临时状态。
##
## 和四关的 R 一样走 Transition 过渡：黑幕盖满那一刻才把玩家挪回出生点，
## 否则复位那一帧会直接露在画面上（瞬移感）。
## _respawn_player() 里已经清了区锁状态，这里不用重复清。
func _restart_level() -> void:
	# 计时器要立刻停：死亡后按 R 时，重生计时还可能在跑，
	# 让它和过渡各自复活一次会把玩家挪两次。
	_stop_respawn_timer()
	Transition.transition(_respawn_player)


## 建重生计时器并接上玩家的 died 信号。
##
## 挑战关是独立场景，不像四关那样有 game.gd 的 RespawnTimer，
## 所以这里自己建一个，时长与四关一致（Config.RESPAWN_DELAY）。
func _setup_respawn() -> void:
	if not _player.has_signal("died"):
		push_error("challenge_level.gd：玩家节点缺少 died 信号，死亡后不会自动复活")
		return
	_respawn_timer = Timer.new()
	_respawn_timer.name = "RespawnTimer"
	_respawn_timer.wait_time = Config.RESPAWN_DELAY
	_respawn_timer.one_shot = true
	add_child(_respawn_timer)
	_respawn_timer.timeout.connect(_on_respawn_timer_timeout)
	_player.connect("died", _on_player_died)


## 玩家死亡：发起过渡，重生发生在黑幕全黑的那一刻。
## die() 本身幂等，这里不用防重复触发。
func _on_player_died() -> void:
	Transition.transition(_respawn_player)


## 把玩家送回出生点。由 Transition 在黑幕全黑时调用。
## 用 respawn() 而不是重载场景——重载会销毁结算页实例、把信号连接全断掉。
func _respawn_player() -> void:
	if not is_instance_valid(_player):
		return
	_player.call("respawn", _spawn.global_position)
	# 复活后清掉区锁计数，避免带着旧状态进去（身体已经不在原来那个区里了）
	_zone_overlap = 0
	_set_shift_locked(false)


## 倒计时结束的回调。
## 【11/7】重生时机已交由过渡接管，这个 Timer 不再启动；保留是为了不删场景里的节点。
func _on_respawn_timer_timeout() -> void:
	_respawn_player()


## 通关：停掉重生计时，否则通关后若刚好在倒计时里会把人拽回出生点。
func _stop_respawn_timer() -> void:
	if _respawn_timer != null:
		_respawn_timer.stop()
