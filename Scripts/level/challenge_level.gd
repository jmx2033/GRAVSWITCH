extends Node2D

## 挑战关控制器：挑战关不走 game.gd 那套四关流程，所以自己监听玩家通关并显示结算页。
##
## 与 game.gd 的分工：game.gd 管四关顺序切换与重生，这里只管「通关了 → 弹结算页 → 重开或回主菜单」。
## 结算页是同一个 Scenes/win_panel.tscn，视觉与四关通关完全一致。

## 走到终点后弹出结算页；不接 main.tscn 的通关流程。
const WIN_PANEL_SCENE := preload("res://Scenes/win_panel.tscn")

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

	if not _player.has_signal("won"):
		push_error("challenge_level.gd：玩家节点缺少 won 信号")
		return
	_player.connect("won", _on_player_won)

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


## 点「回主菜单」：解除暂停并切回主菜单。
func _on_win_menu() -> void:
	get_tree().paused = false
	_win_panel.get_node("%Content").visible = false
	get_tree().change_scene_to_file("res://Scenes/mainmenu.tscn")


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
