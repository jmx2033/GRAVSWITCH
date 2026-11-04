extends Node

const TILE_SIZE: int = 32
const GRAVITY: float = 1800.0
const JUMP_SPEED: float = 590.0
const MAX_SPEED: float = 240.0
const ACCEL: float = 2400.0
const DECEL: float = 3200.0
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.12
const GRAVITY_TURN_TIME: float = 0.12
const LEVEL_SIZE: Vector2 = Vector2(640, 352)
## 死亡后多久回到起点。die 动画 16 帧 @ 10fps = 1.6 秒，再留 0.2 秒看清最后一帧。
const RESPAWN_DELAY: float = 1.8
## 可动平台的移动速度，单位像素/秒。
const MOVING_PLATFORM_SPEED: float = 40.0
## 可动平台从摆放位置向左右各移动的格数。
const MOVING_PLATFORM_TRAVEL_TILES: int = 2

## 当前所有重力来源的合力加速度（像素/秒²）；无重力区时是基础向下重力 g。
var gravity_acceleration: Vector2 = Vector2.DOWN * GRAVITY
