# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [2.0.0] — 2026-07-26

### 🐛 Bug 修复

- **`local -n` 在 macOS 自带 bash 3.2 上直接崩溃**：README 曾声称支持 macOS，但
  nameref 需要 bash ≥ 4.3。现在启动时显式检查版本并给出可执行的修复提示。
- **`100.0%` 丢包判断失效**：旧代码用字符串比较 `[[ "$loss" == "100" ]]`，
  而 BSD/macOS ping 输出的是 `100.0%`，导致 TCP 降级探测永远不会触发。
  现在统一走数值比较。
- **中文目标名导致表格错位**：`printf %-22s` 按字节计数，`Baidu 百度` 被算成
  11 而非 9 列。新增按 UTF-8 显示宽度对齐的 `pad_wide`。
- **ping 变体检测不可靠**：旧代码用 `ping -W 1 -c 1 127.0.0.1` 是否成功来区分
  GNU / BSD，但两者对 localhost 都会成功，导致 macOS 上把毫秒当秒传给 `-W`。
  现在通过 `ping -V` 与 `uname` 判断。
- **参数完全没有校验**：`-c abc` 会被原样传给 ping。现在全部校验并给出明确报错。
- **`-t` 在 BSD 上语义错误**：BSD 的 `-t` 是总 deadline 而非单包超时，旧代码混用了。
- **ANSI 宽度靠 `sed` 事后剥离**：改为先按纯文本对齐、再包裹颜色，逻辑更可靠。

### 🔒 二次审计追加修复（同版本内）

- **`> "${OUTPUT:-/dev/stdout}"` 会截断调用方的输出文件**：bash 打开 `/dev/stdout`
  时会以 `O_TRUNC` 重新打开目标文件，即使用 `>>` 追加也会清空原有内容，并让后续
  写入错位。改为仅在指定 `-o` 时才重定向。
- **未锁定 locale 导致数值全错**：在逗号小数点 locale（de/fr/pt_BR 等）下，awk 把
  `10.100` 截断成 `10`，并输出 `10,00`，使 JSON 无法解析、CSV 列数错乱。现在脚本
  开头 `export LC_ALL=C`。
- **`-j 08` 触发算术错误并静默退化为串行**：`(( 08 ))` 按八进制解析。改为
  `JOBS=$((10#$JOBS))`。
- **Ctrl-C 会残留 ping/curl 孤儿进程**：`jobs -pr` 只列出直接子 shell，真正的
  ping 在更深一层的命令替换子 shell 里。新增递归 `kill_tree`。
- **清理函数会执行两次**：`INT` 处理器里的 `exit` 又触发了 `EXIT` 处理器，第二次
  `kill` 可能命中已被回收复用的 PID。现在在 `cleanup` 首行 `trap - EXIT INT TERM`。
- **`-4/-6` 在 BSD/macOS 上被静默忽略**：现在 `-6` 会改用 `ping6`。
- **`awk -v s=...` 会解释反斜杠转义**：自定义目标名里的 `\t` 会被少算 1 列。改为
  通过 `ENVIRON` 传递。
- **bootstrap：`$HOME` 未设置时（docker/cron/systemd）安装成功后仍退出 1**。
- **bootstrap：`printf '%b'` 会解释路径中的转义**（`\c` 甚至会截断后续输出），改为 `%s`。
- **bootstrap：`exec` 绕过 EXIT trap，每次安装泄漏一个临时文件**。


### ✨ 新功能

- **并发探测**（`-j/--jobs`，默认自动 8–24）：35 个目标从 ~3 分钟降到 ~15 秒。
- **完整统计**：新增 min / max / jitter，不再只有平均值。
- **多种输出格式**（`-f table|json|csv`）与 `-o/--output` 写文件。
- **分组筛选** `-g/--group` 与**自定义目标文件** `-T/--targets`（支持自定义分组）。
- **排序** `-s none|latency|name`，不可达项始终排在最后。
- **IPv4 / IPv6 强制**（`-4` / `-6`）。
- **解析 IP 列**（`--ip`）。
- **汇总统计**：可达/不可达计数、探测方式分布、平均延迟、最快/最慢 Top 3。
- **颜色自动检测**：非 TTY、`NO_COLOR`、`TERM=dumb`、输出到文件时自动关闭；
  `--color always|never` 可强制。
- **进度条**：并发探测时显示实时进度（仅 TTY）。
- **明确的退出码**：`0` 全部可达 / `1` 参数或依赖错误 / `2` 存在不可达目标。
- **长选项**：所有短选项都有 `--long` 形式。

### 🔧 改进

- Ctrl-C / 异常退出时清理临时目录、结束子进程、恢复光标。
- ping 增加总 deadline（`-w`），避免单个目标卡死整轮测试。
- ping 加 `-n` 关闭反解，避免 DNS 反查拖慢测量。
- 内部使用 `\x1f` 作为字段分隔符——tab 属于 IFS 空白，`read` 会折叠连续 tab，
  会让不可达行的空字段串位。
- `bootstrap.sh`：不再强依赖 git（改用 curl/wget 直接拉脚本）；非 root 时安装到
  `~/.local/share` 而非 `/opt`；下载后校验 shebang、长度与 `bash -n` 才落盘；
  不再无条件 `rm -rf` 目标目录；支持 `INSTALL_DIR` / `REF` / `--no-run`；
  新增 pacman / brew 支持。
- 新增 ShellCheck + 冒烟测试的 GitHub Actions。

### ⚠️ 破坏性变更

- 最低要求 bash **4.3**（原 README 写 4.0，但实际代码就需要 4.3）。
- 默认 ping 包数由 5 改为 **4**，超时由 3s 改为 **2s**（并发后总耗时已大幅下降）。
- 表格列有增删（新增 Jitter / Via，可选 IP），逐列解析旧输出的脚本需要调整。
  建议改用 `-f json` 或 `-f csv`。

## [1.4.0]

- 加入 curl TCP 降级探测。

## [1.3.0]

- 初始公开版本：35 个目标、彩色表格输出。
