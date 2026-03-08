# 🌐 VPS World Ping

<div align="center">

![Version](https://img.shields.io/badge/version-1.2.0-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![Shell](https://img.shields.io/badge/shell-bash-orange?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey?style=flat-square)

**一个轻量、美观、开箱即用的 VPS 全球网络延迟测试工具**

[快速开始](#-快速开始) · [功能特性](#-功能特性) · [使用方法](#-使用方法) · [测试目标](#-测试目标) · [常见问题](#-常见问题)

</div>

---

## 📸 效果预览

```text
  ╦  ╦╔═╗╔═╗  ╦  ╔═╗╔╦╗╔═╗╔╗╔╔═╗╦ ╦  ╔╦╗╔═╗╔═╗╔╦╗
  ╚╗╔╝╠═╝╚═╗  ║  ╠═╣ ║ ║╣ ║║║║  ╚╦╝   ║ ║╣ ╚═╗ ║
   ╚╝ ╩  ╚═╝  ╩═╝╩ ╩ ╩ ╚═╝╝╚╝╚═╝ ╩    ╩ ╚═╝╚═╝ ╩

  VPS Global & China Latency Benchmark  •  v1.2.0

  Ping Count : 5 packets per host
  Timeout    : 3s per packet
  Timestamp  : 2025-07-10 12:34:56 UTC
  Hostname   : vps-node-001
  Public IP  : 203.0.113.42

┌──────────────────────────────────────────────────────────────────────────────┐
│  🌐  Global Websites                                                         │
└──────────────────────────────────────────────────────────────────────────────┘

  Target                  Host / IP                     Avg Latency         Pkt Loss
  ──────────────────────  ────────────────────────────  ──────────────────  ──────────
  Google                  google.com                    3.42 ms             0%
  Cloudflare DNS          1.1.1.1                       1.89 ms             0%
  GitHub                  github.com                    98.6 ms             0%
  YouTube                 youtube.com                   145.2 ms            0%
  Amazon AWS              amazon.com                    187.4 ms            0%
  Cloudflare CDN          cloudflare.com                2.14 ms             0%
  Twitter / X             x.com                         210.5 ms            0%
  Microsoft               microsoft.com                 Timeout / Fail      100%
```

> 实际运行时延迟值为彩色输出：绿色（<100ms）、黄色（100–200ms）、红色（>200ms / 超时）。

---

## ✨ 功能特性

- 16 个默认测试目标，覆盖国际与中国大陆常见网站
- 彩色延迟输出，快速看线路表现
- 表格化展示名称、目标主机、平均延迟、丢包率
- 自动检测 Linux / macOS 的 `ping` 参数差异
- 支持自定义 ping 次数与超时时间
- 纯 Bash 实现，零运行时依赖
- 支持一键安装并立即执行

---

## 🚀 快速开始

### 一键运行（推荐）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LYISTR2/VPS-world-ping/main/bootstrap.sh)
```

也可以直接指定参数：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LYISTR2/VPS-world-ping/main/bootstrap.sh) -c 3 -t 2
```

### 直接执行主脚本

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LYISTR2/VPS-world-ping/main/vps-latency-test.sh)
```

### 手动下载运行

```bash
git clone https://github.com/LYISTR2/VPS-world-ping.git
cd VPS-world-ping
chmod +x vps-latency-test.sh bootstrap.sh
./vps-latency-test.sh
```

---

## 📖 使用方法

```text
Usage: vps-latency-test.sh [OPTIONS]

  -c COUNT    每个目标 ping 的次数（默认: 5）
  -t TIMEOUT  ping 超时时间（秒）（默认: 3）
  -h          显示帮助信息
```

### 示例

```bash
# 默认测试
./vps-latency-test.sh

# 快速模式
./vps-latency-test.sh -c 3

# 更稳定的采样
./vps-latency-test.sh -c 10

# 更长超时
./vps-latency-test.sh -c 5 -t 5

# 保存纯文本结果
./vps-latency-test.sh | sed 's/\x1b\[[0-9;]*m//g' > result.txt
```

---

## 🎯 测试目标

### 🌐 国际网站

- Google → `google.com`
- Cloudflare DNS → `1.1.1.1`
- GitHub → `github.com`
- YouTube → `youtube.com`
- Amazon AWS → `amazon.com`
- Cloudflare CDN → `cloudflare.com`
- Twitter / X → `x.com`
- Microsoft → `microsoft.com`

### 🇨🇳 国内网站

- 百度 Baidu → `baidu.com`
- 腾讯 Tencent → `qq.com`
- 淘宝 Taobao → `taobao.com`
- 字节跳动 ByteDance → `bytedance.com`
- 阿里云 Aliyun → `aliyun.com`
- 网易 NetEase → `163.com`
- 京东 JD.com → `jd.com`
- 哔哩哔哩 Bilibili → `bilibili.com`

---

## 🖥️ 系统要求

- Bash 4.0+
- `ping`
- `awk`（或兼容实现）
- `curl`（仅用于获取公网 IP，可选）

### 依赖安装示例

```bash
# Debian / Ubuntu
sudo apt-get install -y iputils-ping gawk curl bash

# CentOS / RHEL / Rocky
sudo yum install -y iputils gawk curl bash

# Alpine Linux
apk add iputils gawk curl bash

# macOS
brew install gawk
```

---

## 🎨 延迟颜色说明

- 🟢 绿色：`< 100 ms`
- 🟡 黄色：`100 – 200 ms`
- 🔴 红色：`> 200 ms`
- 🔴 红色粗体：超时 / 不可达 / 100% 丢包

---

## ❓ 常见问题

**Q：为什么境外 VPS 到国内网站延迟高？**  
A：这是正常现象，受物理距离、跨境路由、运营商 QoS 和线路类型影响很大。

**Q：Timeout / Fail 是什么意思？**  
A：通常表示目标屏蔽了 ICMP，或者从当前 VPS 出口不可达。

**Q：怎么保存成纯文本？**  
```bash
./vps-latency-test.sh | sed 's/\x1b\[[0-9;]*m//g' | tee result-$(date +%Y%m%d-%H%M).txt
```

**Q：如何自定义测试目标？**  
A：编辑脚本里的 `GLOBAL_TARGETS` 和 `CN_TARGETS` 数组即可。

---

## 📁 项目结构

```text
VPS-world-ping/
├── vps-latency-test.sh   # 主测试脚本
├── bootstrap.sh          # 一键安装/运行脚本
├── README.md             # 说明文档
└── LICENSE               # MIT 许可证
```

---

## 📄 License

MIT

---

<div align="center">

如果这个项目对你有帮助，欢迎点个 ⭐ Star。

</div>
