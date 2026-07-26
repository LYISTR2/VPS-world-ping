# 🌐 VPS Latency Test

<div align="center">

![Version](https://img.shields.io/badge/version-2.0.0-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![Shell](https://img.shields.io/badge/bash-%E2%89%A5%204.3-orange?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS*-lightgrey?style=flat-square)

**轻量、并发、开箱即用的 VPS 全球网络延迟测试工具**

[快速开始](#-快速开始) · [功能特性](#-功能特性) · [使用方法](#-使用方法) · [输出格式](#-输出格式) · [测试目标](#-测试目标) · [常见问题](#-常见问题)

</div>

---

## 📸 效果预览

```text
  VPS LATENCY TEST v2.0.0
  ------------------------------------------------------------------------------
  Packets  : 4 per host    Timeout : 2s    Parallel: 16
  Hostname : hk-node-01
  Public IP: 203.0.113.77
  Started  : 2026-07-26 19:04:11 CST

  Global · Core Infrastructure & Tech
  ------------------------------------------------------------------------------
  Target                Host                      Avg           Jitter     Loss     Via
  Google                google.com                42.31 ms      1.02 ms    0.0%     icmp
  Cloudflare DNS        1.1.1.1                   2.14 ms       0.11 ms    0.0%     icmp
  GitHub                github.com                168.90 ms     4.77 ms    0.0%     icmp
  Netflix               netflix.com               87.41 ms      2.30 ms    0.0%     tcp
  ByteDance 字节        bytedance.com             unreachable   -          100%     --

  Summary
  ------------------------------------------------------------------------------
  Targets 35     reachable 33     unreachable 2     (icmp 28 / tcp 5)
  Mean latency 118.4 ms
  Fastest Cloudflare DNS (2ms)  Google DNS (3ms)  Google (42ms)
  Slowest Bilibili 哔哩 (241ms)  Baidu 百度 (244ms)  Quora (301ms)
```

> 延迟数值按区间着色：绿色 `< 100ms`、黄色 `100–200ms`、红色 `> 200ms` 或不可达。

---

## ✨ 功能特性

| 特性 | 说明 |
|------|------|
| ⚡ **并发探测** | 默认自动并发（CPU×4，8–24），35 个目标从 ~3 分钟降到 ~15 秒 |
| 🔁 **ICMP + TCP 双探测** | ICMP 被墙的站点自动降级为 TCP 握手计时，结果标注 `tcp` |
| 📈 **完整统计** | min / avg / max / jitter / 丢包率，而非只有平均值 |
| 🧾 **多种输出** | `table` / `json` / `csv`，可直接喂给监控或表格 |
| 🎯 **分组与自定义** | `-g` 按组筛选，`-T` 加载自己的目标列表 |
| 🌏 **CJK 对齐** | 按显示宽度而非字节数对齐，中文目标名不再错位 |
| 🎨 **智能着色** | 自动识别管道/重定向/`NO_COLOR`，非 TTY 时输出纯文本 |
| 🧯 **可脚本化** | 明确的退出码、参数校验、Ctrl-C 清理、临时文件自动回收 |
| 🚀 **零第三方依赖** | 纯 Bash + ping + awk（curl 可选） |

---

## 🚀 快速开始

### 一键运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LYISTR2/VPS-world-ping/main/bootstrap.sh)
```

带参数：

```bash
bash <(curl -fsSL .../bootstrap.sh) -c 10 -j 16
```

只安装不运行（可自定义安装路径）：

```bash
INSTALL_DIR=~/bin NO_RUN=1 bash <(curl -fsSL .../bootstrap.sh)
```

> ⚠️ `curl | bash` 类安装方式意味着你信任该来源。建议先下载 `bootstrap.sh` 读一遍再执行。
> 安装脚本会校验下载内容确实是 bash 脚本、长度合理、且能通过 `bash -n` 语法检查后才写入磁盘。

### 手动使用

```bash
git clone https://github.com/LYISTR2/VPS-world-ping.git
cd VPS-world-ping
chmod +x vps-latency-test.sh
./vps-latency-test.sh
```

---

## 📖 使用方法

```text
USAGE
  vps-latency-test.sh [OPTIONS]

PROBING
  -c, --count N        每个目标发送的 ICMP 包数            (默认: 4)
  -t, --timeout SEC    单包等待超时（秒）                  (默认: 2)
  -j, --jobs N         并发探测数，1 表示串行              (默认: 自动)
  -4, --ipv4           强制 IPv4
  -6, --ipv6           强制 IPv6
      --no-fallback    ICMP 失败时不降级为 TCP 探测

SELECTION
  -g, --group LIST     只测试指定分组，逗号分隔
                       (core streaming social cn)
  -T, --targets FILE   追加自定义目标，每行 "group|Name|host"

OUTPUT
  -f, --format FMT     table | json | csv                 (默认: table)
  -o, --output FILE    输出到文件而非标准输出
  -s, --sort KEY       none | latency | name              (默认: none)
      --ip             显示解析到的 IP 列
      --color WHEN     auto | always | never              (默认: auto)
  -q, --quiet          不输出横幅、进度和图例
  -h, --help           帮助
  -V, --version        版本

EXIT CODES
  0  所有目标可达
  1  参数或依赖错误
  2  至少有一个目标不可达
```

### 示例

```bash
# 默认全量测试
./vps-latency-test.sh

# 精准模式：10 个包，16 并发
./vps-latency-test.sh -c 10 -j 16

# 只看国内 + 核心基础设施，并显示解析 IP
./vps-latency-test.sh -g cn,core --ip

# 按延迟排序（不可达的排最后）
./vps-latency-test.sh -s latency

# 存成 JSON 供监控采集
./vps-latency-test.sh -f json -o /var/log/latency-$(date +%F).json

# 存成纯文本（无需再 sed 去色，非 TTY 时自动关闭颜色）
./vps-latency-test.sh > result.txt

# 在 CI / 健康检查里使用退出码
./vps-latency-test.sh -q -g core || echo "有目标不可达"
```

### 自定义目标

新建 `my-targets.txt`：

```text
# group|显示名称|主机
mine|My Tokyo Node|tokyo.example.com
mine|My HK Node|hk.example.com
cn|微博 Weibo|weibo.com
```

```bash
./vps-latency-test.sh -T my-targets.txt -g mine
```

自定义分组会自动作为新的一节输出，无需改脚本。

---

## 📤 输出格式

### JSON

```json
{
  "version": "2.0.0",
  "timestamp": "2026-07-26T11:04:11Z",
  "hostname": "hk-node-01",
  "ping_count": 4,
  "ping_timeout": 2,
  "results": [
    {
      "group": "core", "name": "Google", "host": "google.com", "ip": "142.250.66.14",
      "reachable": true, "min_ms": 41.2, "avg_ms": 42.31, "max_ms": 44.9,
      "jitter_ms": 1.02, "loss_pct": 0.0, "method": "icmp"
    },
    {
      "group": "cn", "name": "ByteDance 字节", "host": "bytedance.com", "ip": "-",
      "reachable": false, "min_ms": null, "avg_ms": null, "max_ms": null,
      "jitter_ms": null, "loss_pct": 100, "method": "fail"
    }
  ]
}
```

### CSV

```csv
group,name,host,ip,min_ms,avg_ms,max_ms,jitter_ms,loss_pct,method
core,"Google",google.com,142.250.66.14,41.20,42.31,44.90,1.02,0.0,icmp
cn,"ByteDance 字节",bytedance.com,-,,,,,100,fail
```

`method` 取值：`icmp`（ICMP RTT）、`tcp`（TCP 握手耗时）、`fail`（不可达）。

> ⚠️ `tcp` 的数值是 TCP 三次握手时间，通常约等于 1 个 RTT，但与 ICMP RTT 并不严格可比，
> 也可能受中间 CDN / 负载均衡影响。混用时请注意。

---

## 🎯 测试目标

内置 35 个目标，分 4 组：

| 分组 key | 说明 | 数量 |
|----------|------|------|
| `core` | 核心基础设施 & 科技 | 8 |
| `streaming` | 流媒体 & 媒体 | 10 |
| `social` | 社交、论坛 & 社区 | 12 |
| `cn` | 中国大陆 | 5 |

<details>
<summary>展开完整列表</summary>

**core** — Google `google.com` · Cloudflare DNS `1.1.1.1` · Google DNS `8.8.8.8` · GitHub `github.com` · Amazon AWS `amazon.com` · Microsoft `microsoft.com` · Cloudflare CDN `cloudflare.com` · Fastly CDN `fastly.com`

**streaming** — YouTube `youtube.com` · Netflix `netflix.com` · Disney+ `disneyplus.com` · Hulu `hulu.com` · Twitch `twitch.tv` · Spotify `spotify.com` · Apple TV+ `tv.apple.com` · HBO Max `max.com` · Crunchyroll `crunchyroll.com` · SoundCloud `soundcloud.com`

**social** — Twitter/X `x.com` · Reddit `reddit.com` · Discord `discord.com` · Stack Overflow `stackoverflow.com` · Hacker News `news.ycombinator.com` · Wikipedia `wikipedia.org` · Telegram `telegram.org` · LinkedIn `linkedin.com` · Quora `quora.com` · Medium `medium.com` · Dev.to `dev.to` · Mastodon `mastodon.social`

**cn** — 百度 `baidu.com` · 腾讯 `qq.com` · 阿里云 `aliyun.com` · 字节跳动 `bytedance.com` · 哔哩哔哩 `bilibili.com`

</details>

---

## 🖥️ 系统要求

| 组件 | 要求 | 备注 |
|------|------|------|
| bash | **≥ 4.3** | 使用了 nameref（`local -n`）与 `wait -n` |
| ping | iputils-ping 或 BSD ping | 自动识别两种 `-W` 语义 |
| awk  | gawk / mawk / nawk | |
| curl | 可选 | 缺失时自动禁用 TCP 降级与公网 IP 查询 |

> **macOS 注意**：系统自带 bash 为 3.2，无法运行本脚本。请先 `brew install bash`，
> 然后用 `/opt/homebrew/bin/bash vps-latency-test.sh` 运行。

### 安装依赖

```bash
# Debian / Ubuntu
sudo apt-get install -y iputils-ping gawk curl

# CentOS / RHEL / Rocky / Fedora
sudo dnf install -y iputils gawk curl

# Alpine
apk add iputils gawk curl bash

# Arch
sudo pacman -S iputils gawk curl

# macOS
brew install bash gawk
```

---

## ❓ 常见问题

**Q：为什么有些目标显示 `tcp` 而不是 `icmp`？**
A：这些站点屏蔽了 ICMP。脚本自动降级为测量到 `443` 端口的 TCP 握手时间，这个值仍然能反映网络距离。用 `--no-fallback` 可以关闭该行为。

**Q：`unreachable` 是什么意思？**
A：ICMP 100% 丢包，且 TCP 握手也失败（或被 `--no-fallback` 禁用）。可能是域名解析失败、出口被封、或目标同时屏蔽了 ICMP 和你的 IP。

**Q：为什么国内站点从境外 VPS 延迟很高？**
A：跨境路由绕行、海底光缆物理距离和运营商 QoS 都会显著增加延迟，属正常现象。

**Q：并发会不会影响测量准确性？**
A：并发探测共享同一条上行链路，理论上高并发可能引入轻微排队。默认并发（8–24）对现代 VPS 影响可忽略；若追求极致准确，用 `-j 1` 串行测量。

**Q：怎么保存成纯文本？**
A：直接重定向即可，非 TTY 时颜色会自动关闭：
```bash
./vps-latency-test.sh > result-$(date +%Y%m%d-%H%M).txt
```

**Q：怎么定时采集？**
```bash
# crontab -e
*/30 * * * * /opt/vps-world-ping/vps-latency-test.sh -q -f json -o /var/log/latency.json
```

---

## 📁 项目结构

```text
VPS-world-ping/
├── vps-latency-test.sh          # 主脚本
├── bootstrap.sh                 # 一键安装/运行
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .github/workflows/lint.yml   # ShellCheck CI
```

---

## 📄 License

[MIT](LICENSE)

---

<div align="center">

如果这个项目对你有帮助，欢迎点一个 ⭐ Star！

</div>
