# 09 · C# 到 GDScript 速查

>C# 会写，这份看完就能动手，不用通读官方文档。
> 一句话：**GDScript = Python 的语法 + Godot 的几个关键字**。你缺的不是编程能力，是那几行语法糖。

## 一、先记住这句

换成 C# 也一样要学 **Node / Scene / signal / `@onready`** 这一整套 Godot 的模型。
真正花时间的从来不是语言，是这套模型。所以"换语言"的额外成本比你想的小得多——只是在这层模型外面少写点括号。

## 二、语法对照

| C# | GDScript |
|---|---|
| `public float speed = 300f;` | `@export var speed: float = 300.0` |
| `private Sprite2D _sprite;` | `@onready var _sprite: Sprite2D = $Sprite2D` |
| `void _Ready()` | `func _ready() -> void:` |
| `void Update()` | `func _process(delta: float) -> void:` |
| `void FixedUpdate()` | `func _physics_process(delta: float) -> void:` |
| `Debug.Log(x)` | `print(x)` |
| `GetNode<Sprite2D>("Sprite2D")` | `$Sprite2D` |
| `transform.position` | `position` / `global_position` |
| `Time.deltaTime` | `delta`（函数参数，单位秒） |
| `new Vector2(1, 2)` | `Vector2(1, 2)` |
| `List<T>` | `Array` |
| `Dictionary<K, V>` | `Dictionary` |
| `event Action` | `signal` |
| `Prefab.Instantiate()` | `PRE.instantiate()` |
| `Destroy(go)` | `queue_free()` |
| `&&` `\|\|` `!` | `and` `or` `not` |
| `this` | `self` |
| `null` | `null`（小写，不是 `None`） |
| `if (x) { }` | `if x:` |
| `for (int i = 0; i < 10; i++)` | `for i in range(10):` |
| `foreach (var c in children)` | `for c in get_children():` |
| `// 注释` | `# 注释` |
| `;` | **不要写** |
| `{ }` 代码块 | **靠缩进** |

## 三、Godot 专属的那几个关键字

C# 里没有对应物，也是最容易卡住的地方。

| 写法 | 作用 | 等价于 C# 里 |
|---|---|---|
| `extends CharacterBody2D` | 继承 | `: CharacterBody2D` |
| `class_name Player` | 把类注册成全局类型，别的文件能直接用 | `public class Player` |
| `@export var speed := 300.0` | 暴露到检查器面板，可拖动调 | `[SerializeField]` |
| `@onready var s = $Sprite2D` | 在 `_ready()` 时才赋值 | 在 `_Ready` 里 `GetNode` |
| `signal died(score: int)` | 声明信号 | `event Action<int>` |
| `died.emit(5)` | 触发 | `died?.Invoke(5)` |
| `died.connect(_on_died)` | 订阅 | `died += _on_died` |
| `_init()` | 构造函数 | 构造函数 |
| `queue_free()` | 延迟到帧末销毁 | `Destroy` |

## 四、五个必踩的坑

1. **缩进只能用 Tab，不能混空格。** 混了报 `Indentation error`，而且看不出哪行错。VS Code 里把 "Insert Spaces" 关掉。
2. **没有分号，也别加。** 编译不会报错，但会以为是别的错。
3. **`@onready` 的变量在 `_ready()` 之前是 `null`。** 别在 `_init()` 里碰它。
4. **`is_on_floor()` 只在 `move_and_slide()` 之后才准。** 顺序反了就永远返回 false。
5. **整数除法。** `5 / 2` 得 `2`，跟 C# 一样；要小数写 `5.0 / 2.0`。

## 五、今晚的模板（跑通这个就算过关）

```gdscript
extends CharacterBody2D
class_name Player

@export var speed: float = 260.0
@export var jump_speed: float = 620.0
const GRAVITY := 1800.0

func _physics_process(delta: float) -> void:
	# 水平移动
	var dir := Input.get_axis("move_left", "move_right")
	velocity.x = dir * speed

	# 重力：始终朝 up_direction 的反方向加速
	if not is_on_floor():
		velocity += up_direction * -GRAVITY * delta

	# 跳
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity = up_direction * jump_speed

	move_and_slide()
```

**注意 `up_direction`，不要写死 `velocity.y`。** 我们这个游戏的重力会翻转，写死 `-y` 之后一进重力区人就会往墙上撞。这一条比语法重要得多。

`up_direction` 默认是 `Vector2(0, -1)`，重力翻到侧面时把它改成对应方向，上面这段代码不用改。
