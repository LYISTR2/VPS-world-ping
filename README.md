# 🌐 VPS Latency Test

<div align="center">

![Version](https://img.shields.io/badge/version-1.3.0-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![Shell](https://img.shields.io/badge/shell-bash-orange?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey?style=flat-square)

**一个轻量、美观、开箱即用的 VPS 全球网络延迟测试工具**

[快速开始](#-快速开始) · [功能特性](#-功能特性) · [使用方法](#-使用方法) · [测试目标](#-测试目标) · [常见问题](#-常见问题)

</div>

---

## 📸 效果预览

```text
 ╦ ╦╔═╗╔═╗ ╦ ╔═╗╔╦╗╔═╗╔╗╔╔═╗╦ ╦ ╔╦╗╔═╗╔═╗╔╦╗
 ╚╗╔╝╠═╝╚═╗ ║ ╠═╣ ║ ║╣ ║║║║ ╚╦╝ ║ ║╣ ╚═╗ ║
 ╚╝ ╩ ╚═╝ ╩═╝╩ ╩ ╩ ╚═╝╝╚╝╚═╝ ╩ ╩ ╚═╝╚═╝ ╩

 VPS Global & China Latency Benchmark • v1.3.0
```

> 📌 实际运行时延迟数值以彩色显示：绿色（< 100ms）、黄色（100–200ms）、红色（> 200ms / 超时）

---

## ✨ 功能特性

| 特性 | 说明 |
|------|------|
| 🎯 **35 个测试目标** | 4 大分类：基础设施、流媒体、社区论坛、中国大陆 |
| 🎨 **彩色输出** | 按延迟高低自动着色，一目了然 |
| 📊 **整齐表格** | 名称、主机、平均延迟、丢包率四列对齐 |
| 🔍 **环境自检** | 启动前自动检测 `ping`、`awk` 等依赖 |
| ⚙️ **参数可调** | 支持自定义 ping 次数和超时时间 |
| 🖥️ **跨平台** | 同时支持 GNU/Linux 和 BSD/macOS ping |
| 🚀 **零依赖** | 纯 Bash 编写，无需安装额外软件包 |

---

## 🚀 快速开始

### 一键运行（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LYISTR2/VPS-world-ping/main/vps-latency-test.sh)
```

### 带参数运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LYISTR2/VPS-world-ping/main/vps-latency-test.sh) -c 3 -t 2
```

### 手动下载运行

```bash
git clone https://github.com/LYISTR2/VPS-world-ping.git
cd VPS-world-ping
chmod +x vps-latency-test.sh
./vps-latency-test.sh
```

---

## 📖 使用方法

```text
Usage: vps-latency-test.sh [OPTIONS]

 -c COUNT    每个目标 ping 的次数 (默认: 5)
 -t TIMEOUT  ping 超时时间（秒） (默认: 3)
 -h          显示帮助信息
```

### 示例

```bash
# 默认运行（每目标 ping 5 次）
./vps-latency-test.sh

# 快速模式（ping 3 次，适合快速概览）
./vps-latency-test.sh -c 3

# 精准模式（ping 10 次，结果更稳定）
./vps-latency-test.sh -c 10

# 调整超时（适合高延迟线路）
./vps-latency-test.sh -c 5 -t 5

# 保存结果到文件（去除 ANSI 颜色码）
./vps-latency-test.sh | sed 's/\x1b\[[0-9;]*m//g' > result.txt
```

---

## 🎯 测试目标

### 🌐 核心基础设施 & 科技（8 个）

| # | 名称 | 主机 |
|---|------|------|
| 1 | Google | `google.com` |
| 2 | Cloudflare DNS | `1.1.1.1` |
| 3 | Google DNS | `8.8.8.8` |
| 4 | GitHub | `github.com` |
| 5 | Amazon AWS | `amazon.com` |
| 6 | Microsoft | `microsoft.com` |
| 7 | Cloudflare CDN | `cloudflare.com` |
| 8 | Fastly CDN | `fastly.com` |

### 📺 流媒体 & 媒体（10 个）

| # | 名称 | 主机 |
|---|------|------|
| 1 | YouTube | `youtube.com` |
| 2 | Netflix | `netflix.com` |
| 3 | Disney+ | `disneyplus.com` |
| 4 | Hulu | `hulu.com` |
| 5 | Twitch | `twitch.tv` |
| 6 | Spotify | `spotify.com` |
| 7 | Apple TV+ | `tv.apple.com` |
| 8 | HBO Max | `max.com` |
| 9 | Crunchyroll | `crunchyroll.com` |
| 10 | SoundCloud | `soundcloud.com` |

### 💬 社交、论坛 & 社区（12 个）

| # | 名称 | 主机 |
|---|------|------|
| 1 | Twitter / X | `x.com` |
| 2 | Reddit | `reddit.com` |
| 3 | Discord | `discord.com` |
| 4 | Stack Overflow | `stackoverflow.com` |
| 5 | Hacker News | `news.ycombinator.com` |
| 6 | Wikipedia | `wikipedia.org` |
| 7 | Telegram | `telegram.org` |
| 8 | LinkedIn | `linkedin.com` |
| 9 | Quora | `quora.com` |
| 10 | Medium | `medium.com` |
| 11 | Dev.to | `dev.to` |
| 12 | Mastodon | `mastodon.social` |

### 🇨🇳 中国大陆（5 个）

| # | 名称 | 主机 |
|---|------|------|
| 1 | 百度 Baidu | `baidu.com` |
| 2 | 腾讯 Tencent | `qq.com` |
| 3 | 阿里云 Aliyun | `aliyun.com` |
| 4 | 字节跳动 ByteDance | `bytedance.com` |
| 5 | 哔哩哔哩 Bilibili | `bilibili.com` |

---

## 🖥️ 系统要求

| 组件 | 要求 |
|------|------|
| Shell | Bash 4.0+ |
| ping | iputils-ping（Linux）或系统内置（macOS） |
| awk | gawk / mawk / nawk（任一） |
| curl | 用于获取公网 IP（可选，不影响主功能） |

### 安装依赖（如缺失）

```bash
# Debian / Ubuntu
sudo apt-get install -y iputils-ping gawk curl bash

# CentOS / RHEL / Rocky
sudo yum install -y iputils gawk curl bash

# Alpine Linux
apk add iputils gawk curl bash

# macOS (通过 Homebrew)
brew install gawk
```

---

## 🎨 延迟颜色说明

| 颜色 | 延迟范围 | 说明 |
|------|----------|------|
| 🟢 **绿色** | < 100 ms | 优秀，适合大多数应用 |
| 🟡 **黄色** | 100 – 200 ms | 良好，日常使用可接受 |
| 🔴 **红色** | > 200 ms | 较高，可能影响体验 |
| 🔴 **红色粗体** | 超时 / 失败 | 目标不可达或 100% 丢包 |

---

## ❓ 常见问题

**Q：为什么国内网站从境外 VPS 延迟很高？**  
A：这是正常现象。跨国路由、海底电缆物理距离以及 QoS 策略都会带来较高延迟。

**Q：Timeout / Fail 是什么意思？**  
A：目标主机可能屏蔽了 ICMP ping，或者从当前 VPS 出口不可达。

**Q：如何将结果保存为纯文本？**  
```bash
./vps-latency-test.sh | sed 's/\x1b\[[0-9;]*m//g' | tee result-$(date +%Y%m%d-%H%M).txt
```

**Q：如何添加自定义测试目标？**  
A：编辑脚本中的 `TARGETS_CORE`、`TARGETS_STREAMING`、`TARGETS_SOCIAL`、`CN_TARGETS` 数组即可。

---

## 📁 项目结构

```text
VPS-world-ping/
├── vps-latency-test.sh   # 主脚本
├── README.md             # 本文档
└── LICENSE               # MIT 许可证
```

---

## 📄 License

本项目基于 [MIT License](LICENSE) 开源。

---

<div align="center">

如果这个项目对你有帮助，欢迎点一个 ⭐ Star！

Made with ❤️ for the VPS community

</div>
