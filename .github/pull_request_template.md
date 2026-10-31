<!-- 标题格式：<type>(<scope>): 描述 [P编号]  例：feat(slash): 三段刃形按蓄力进度切换 [P1-1] -->
<!-- type: feat / fix / art / docs / chore / refactor / polish（共 7 个，冻结期只用 fix 与 polish）；scope: charge slash enemy ui build repo levelup -->

## 改了什么

<!-- 一句话。写"三段刃形按蓄力进度切换"，不要写"更新" -->

## 怎么验证

<!-- 在哪个场景、按什么键、应该看到什么。别人照着能复现才算填完 -->

## 截图 / 录屏

<!-- 有视觉变化必传 -->

## 自查（打勾再提交）

- [ ] 只改了属于自己的文件（归属见 `docs/03_接口契约.md`）
- [ ] 没有改 `Arena.unity`（除非你是珈百璃）
- [ ] 没有 `public` 字段，用的是 `[SerializeField] private`
- [ ] public 方法都有中文 `/// <summary>`
- [ ] 没有直接写 `Time.timeScale`，没有直接扣血
- [ ] 没有用 `FindObjectOfType` / `FindObjectsOfType`（Unity 6 已废弃）
- [ ] 没有引入 URP / 新 Input System / Cinemachine / 第三方包
- [ ] 单文件没超过 200 行（超了已在描述里说明理由）
- [ ] `git add` 之前看过 `git status`，没有 `Library/`、`.csproj`、`_Scratch/`
- [ ] **这段代码我能口述"输入什么、输出什么、谁调用它"**
