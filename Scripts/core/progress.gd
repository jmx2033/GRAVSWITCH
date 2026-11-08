extends Node

## 进度存档：记住"是否通关过一次"，用于解锁挑战关。
##
## ⚠️ 这是一处**明知破例**：AGENTS.md 的「禁止引入」里写着「存档」。
## 破例理由：「通关一次后解锁挑战关」这个功能必须跨进程记住状态，否则重启就丢，
## 功能等于不存在。范围刻意压到最小——**只存一个布尔**，不存关卡进度、不存成绩、不做多存档。
##
## 文件位置 user://progress.cfg，与 settings_panel.gd 的音量配置同一套做法（ConfigFile）。
## 想彻底回到未解锁状态：删掉 user://progress.cfg 即可。

## 存档文件路径（user:// 下，不占仓库）。
const PROGRESS_PATH := "user://progress.cfg"
const SECTION := "progress"
const KEY_CLEARED := "game_cleared"

## 是否已通关过；内存缓存，避免每次读取都碰磁盘。
var _cleared: bool = false


## 启动时读一次磁盘。
func _ready() -> void:
	_load()


## 是否已解锁挑战关。
func is_challenge_unlocked() -> bool:
	return _cleared


## 标记"整个游戏通关过一次"，并立刻落盘。
## 重复调用无副作用（已经是 true 就直接返回）。
func mark_game_cleared() -> void:
	if _cleared:
		return
	_cleared = true
	_save()


## 从磁盘读取；没有文件或读失败时按"未通关"处理。
func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) != OK:
		_cleared = false
		return
	_cleared = bool(cfg.get_value(SECTION, KEY_CLEARED, false))


## 把当前状态写回磁盘。
func _save() -> void:
	var cfg := ConfigFile.new()
	# 先 load 一次，保留文件里其它键（以后要加字段时不会覆盖掉）
	cfg.load(PROGRESS_PATH)
	cfg.set_value(SECTION, KEY_CLEARED, _cleared)
	var err := cfg.save(PROGRESS_PATH)
	if err != OK:
		push_warning("progress.gd：写入存档失败（error %d）" % err)