<!-- 标题格式：<type>(<scope>): 描述 [P编号]  例：feat(gravity): 进入重力区后角色贴天花板 [P0-2] -->
<!-- type: feat / fix / art / docs / chore / refactor / polish（共 7 个，冻结期只用 fix 与 polish） -->
<!-- scope: player gravity level ui build repo（共 6 个，仓库与文档类一律用 repo） -->

## 改了什么

<!-- 一句话。写"重力区进入后方向平滑转向 0.12 秒"，不要写"更新" -->

## 怎么验证

<!-- 在哪个场景、按什么键、应该看到什么。别人照着能复现才算填完 -->

## 截图 / 录屏

<!-- 有视觉变化必传 -->

## 自查（打勾再提交）

- [ ] 只改动自己负责的模块（分工见 `README.md`「分工」一表）
- [ ] 没有改别人的 `.tscn` / `.tres`（要改先说过）
- [ ] **起跳方向写的是 `up_direction * JUMP_SPEED`，没有写死 `velocity.y`**
- [ ] 没有直接改 `config.gd` 里的跳跃参数（只有珈百璃能改）
- [ ] 缩进全是 Tab，没有混空格
- [ ] 没有用 `get_node("../../..")` 这种深路径，跨节点用 signal
- [ ] 没有引入 addon / 第三方插件 / shader
- [ ] 单文件没超过 150 行（超了已在描述里说明理由）
- [ ] `git add` 之前看过 `git status`，没有 `.godot/`、`build/`、`.exe`、`_scratch/`
- [ ] **这段代码我能口述"输入什么、输出什么、谁调用它"**
