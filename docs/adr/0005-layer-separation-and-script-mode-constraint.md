# 逻辑层不依赖 autoload：`data/` 与 `rules/` 必须能在 `-s` 模式下跑

代码分四层：`data/`（数据表）→ `rules/`（规则）→ `world/`（地图与世界）→
`battle/` 与 `ui/`（表现）。其中 `data/` 与 `rules/` **不得在编译期引用 autoload**
（`Game` / `EventBus` / `DebugLog` / `AudioManager`）；需要时用 `/root/XXX` 字符串查找 + 空值保护。

原因：`godot -s script.gd` 的脚本模式**不加载 autoload**。一旦 `rules/` 里直接写 `DebugLog.ev(...)`，
纯逻辑测试就会编译失败 —— 而编译失败时 `quit()` 永远不会被执行，进程空转，
表现成「测试永久卡死」。这个坑真实发生过：`combat_test` 曾经无限挂起。

## Considered Options

- 逻辑层直接用 autoload：写起来顺，但丢掉「纯逻辑可单测」这条底线
- 给逻辑层注入 logger 接口：更干净，但当时改造成本大
- 选择：字符串查找 + 判空（`.get_node_or_null("/root/DebugLog")` + 空值早返回）

## Consequences

- 10 项纯逻辑测试用 `-s` 跑（秒级），21 项场景测试用 `.tscn` 跑（有 autoload）
- 看到 `/root/DebugLog` 这类写法**不要顺手「清理」成直接引用**，那会破坏可测性
- 新增逻辑层脚本时先问：它能不能在 `-s` 下跑？跑不了就说明它该放在 `battle/` 或 `ui/`
- 同理，逻辑层脚本里不要做 `get_tree()` / `await` 之类的场景依赖
