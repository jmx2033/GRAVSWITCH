extends Node2D

# 定义关卡大小常量
const LEVEL_SIZE := Vector2(640, 352)

# 预设的重生点坐标
var spawn_point := Vector2(100, 100)

func _ready() -> void:
	var player_node = get_node_or_null("Player")
	
	# 连接死亡信号
	if player_node and player_node.has_signal("died"):
		player_node.died.connect(_on_player_died)
		print("系统提示：死亡信号已连接！")
	else:
		print("警告：未找到玩家节点，或者玩家节点没有 'died' 信号。")

# 处理键盘输入 (R键重置)
func _process(_delta):
	# 检测是否按下了 R 键 (Input.KEY_R)
	if Input.is_action_just_pressed("ui_text_backspace"): 
		# 这里为了保险，使用物理按键代码 KEY_R
		pass 
	
	# 检测物理按键 R
	if Input.is_action_just_pressed("restart"):
		print("检测到 R 键，正在重载场景...")
		reload_current_scene()

# 这是一个自定义函数，用来处理玩家死亡后的逻辑
func _on_player_died() -> void:
	print("玩家死亡！正在重置位置...")
	
	# 重生，这里的 await 会暂停这个函数 0.5 秒，而不影响游戏其他部分
	await get_tree().create_timer(0.5).timeout
	
	reload_current_scene()
	

# 重载当前场景的功能函数
func reload_current_scene():
	# 获取当前场景的文件路径
	var current_scene_path = get_tree().current_scene.scene_file_path
	# 重新加载并切换场景
	get_tree().change_scene_to_file(current_scene_path)
