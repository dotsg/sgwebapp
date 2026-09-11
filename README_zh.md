# sgwebapp 🚀

[English](README.md) | [简体中文](README_zh.md)

> **将 Omarchy 的 Web App 极致体验带到 macOS。**  
> 数秒内将任意网站转化为独立的、无干扰的 macOS 桌面原生应用 —— 默认真正无边框（0 顶栏、0 交通灯）、Retina 级高清 `.icns` 图标、深度集成 Spotlight 聚焦搜索、支持从 Chrome 导入登录态，以及与 macOS 系统原生对齐或 Hyprland 风格的动态窗口边框。

---

## 🌟 核心特性

- **🚫 真正的“0 顶栏 + 0 交通灯”模式（原生 Native 引擎，默认）**：基于轻量级 Cocoa / WebKit 原生编译运行时，打造 100% 真正无边框窗口，去除传统标题栏与红黄绿交通灯，呈现完全自适应的 macOS 系统级圆角和毛玻璃边框。
- **🍪 双引擎设计，直面核心权衡**：macOS 的交通灯按钮是由 AppKit 在浏览器进程内部绘制的，因此在系统底层“真正无顶栏”与“直接复用 Chrome 实时会话”不可兼得。您可以按需为每个应用单独选择引擎：
  - **原生引擎 (`--engine native` 或 `--engine safari`，默认)**：完全无标题栏与交通灯，基于 Safari 渲染核心（原生 WebKit）渲染，独立的 Dock 图标与进程名称，独立的持久化 Cookie 存储。新应用初始为未登录状态（支持一键从 Chrome 导入，详见下文）。
  - **Chrome 引擎 (`--engine chrome`)**：通过 Chromium `--app` 模式运行，直接复用 Google Chrome 本地的登录会话与 Cookie，但保留标准 macOS 标题栏。适合 Widevine DRM 受保护内容（如 Netflix/Spotify）、绑定 Chrome 资料库的 Passkey 或重度依赖 Chrome 扩展的站点。
- **🔑 原生引擎登录态方案**：提供 `sgwebapp import-cookies <应用名>` 命令，直接从 Chrome 读取并解密对应站点的 Cookie 注入应用；同时支持跨 sgwebapp 原生应用共享单点登录（SSO）Cookie（如 Google、GitHub 只需登录一次）。在 [docs/cookies.md](docs/cookies.md) 中详细解析了实现原理、边界限制与安全考量。
- **🎨 Retina 级 macOS 原生图标 (`.icns`)**：自动抓取目标网站的高清 `apple-touch-icon`，并通过 macOS 内置的 `sips` 与 `iconutil` 工具自动编译生成包含 10 种标准尺寸的 Apple 原生 `.icns` 图标包。
- **🔍 macOS 桌面深度集成**：安装至 `~/Applications/<应用名>.app`，完美支持 **Spotlight（聚焦搜索 `Cmd + Space`）**、**启动台（Launchpad）** 与 **Dock 栏**。
- **🪟 内置窗口边框守护进程 (`sgwebapp-border`)**：独立、零依赖的 Swift 编译程序，可为当前活动窗口实时绘制平滑圆角高亮边框（灵感源自 Omarchy / Hyprland 平铺窗口管理器）。
- **⚡ 极致轻量**：原生引擎体积仅约 100 KB！无 Electron 臃肿包袱，无 Node.js 运行时，极速冷启动，内存占用极低。
- **🧩 完备的原生浏览器行为**：支持 `target="_blank"` 和 `window.open()` 弹出独立窗口（OAuth 授权登录流程完美闭环），支持 `mailto:` / `tel:` / 第三方 App 协议跳转，支持 `<input type="file">` 唤起原生文件选择器，支持 JavaScript 原生弹窗，并在网络故障时提供可重试的优雅错误页而非空白窗口。

---

## 📦 安装与配置

克隆本仓库并将 `bin/` 目录添加到您的 `$PATH`：

```bash
git clone https://github.com/wuvist/sgwebapp.git ~/code/sgwebapp
cd ~/code/sgwebapp

# 编译原生运行时与边框守护进程，并运行测试验证
make build
make test
```

### 添加到 PATH 环境变量
将以下内容添加到您的 `~/.zshrc` 或 `~/.bashrc`：
```bash
export PATH="$HOME/code/sgwebapp/bin:$PATH"
```
或者将其安装到系统的 `/usr/local/bin`（供全局使用）：
```bash
sudo make install
```

---

## 🚀 快速上手

### 1. 安装 Web App（默认无顶栏沉浸模式与边框）
```bash
# 默认模式：原生无边框引擎（0 顶栏、0 交通灯、macOS 原生毛玻璃质感）
sgwebapp install "WhatsApp Web" "https://web.whatsapp.com"
sgwebapp install "Google Maps" "https://www.google.com/maps"

# 自定义强调边框颜色与宽度：
sgwebapp install "GitHub" "https://github.com" --border-color "3b82f6" --border-width 3.0

# 可选：直接使用 Chrome 引擎（保留标准 28px 标题栏与实时共享 Chrome 会话）：
sgwebapp install "WhatsApp Web" "https://web.whatsapp.com" --engine chrome
```

安装完成后：
- 按下 <kbd>Cmd</kbd> + <kbd>Space</kbd> 打开 Spotlight，输入 `WhatsApp Web` 或 `Google Maps` 即可启动。
- 或在终端中直接运行：`sgwebapp launch "WhatsApp Web"`。

### 2. 查看已安装的 Web App 列表
```bash
sgwebapp list
```
输出示例：
```
APP NAME                  URL                                           PATH
--------                  ---                                           ----
WhatsApp Web              https://web.whatsapp.com                      /Users/wuvist/Applications/WhatsApp Web.app
Google Maps               https://www.google.com/maps                   /Users/wuvist/Applications/Google Maps.app
```

### 3. 运行 Web App 或临时打开网页
```bash
sgwebapp launch "WhatsApp Web"
# 也可以直接以应用模式打开任意 URL：
sgwebapp launch "https://news.ycombinator.com"
```

### 4. 卸载 Web App
```bash
# 命令行非交互式直接移除：
sgwebapp remove "WhatsApp Web"

# 交互式菜单选择移除：
sgwebapp remove
```

---

## 🎨 macOS 原生系统窗口美学与全局配置 (`sgwebapp config`)

`sgwebapp` 默认遵循 macOS 原生系统窗口设计规范（与 Finder、系统设置、备忘录等系统原生 App 100% 保持一致）：
- **macOS 连续超椭圆圆角**：外层窗口圆角统一为 `26.0 pt`，采用与苹果硬件及系统一致的 G2 连续曲率（`.continuous` Squircle）。
- **极细微光描边**：`0.5 pt` 发丝级边框宽度（在 Retina 视网膜屏上精确对齐 1 个物理像素）。
- **自适应动态外观 (`tahoe`)**：边框颜色默认自适应系统明暗模式：
  - **浅色模式 (Light Mode)**：边框自然融入 macOS WindowServer 窗口合成器的原生投影，呈现干净纯粹的原生边缘（彻底消除标准屏幕及 Retina 屏上的人造粗重黑线）；
  - **深色模式 (Dark Mode)**：自动呈现精致的半透明微光描边（`alpha 0.18`），确保在深色暗底壁纸下窗口边缘清晰分明。
- **原生卡片内边距 (Padding)**：`8.0 pt` 内容内边距，透出四周精致的磨砂毛玻璃背景（与 macOS 侧边栏和悬浮卡片间距一致）。

### 查看与修改全局默认样式
全局配置保存在 `~/.config/sgwebapp/config.json` 中：

```bash
# 查看当前默认配置
sgwebapp config

# 将全局默认边框修改为您喜欢的色彩（例如 Catppuccin Blue、Emerald 绿或玫瑰色）
sgwebapp config set border_color 89b4fa
sgwebapp config set border_width 0.5
sgwebapp config set border_radius 26.0
sgwebapp config set padding 8.0

# 随时一键重置回系统推荐默认值
sgwebapp config reset
```

### 单个应用独立配置
安装单个应用时也可以直接覆盖样式参数：
```bash
# 原生系统标准风格（默认：圆角 26pt，边距 8pt，边框 0.5pt）
sgwebapp install "Google Maps" "https://www.google.com/maps"

# 全通铺满无白边风格（padding 为 0）
sgwebapp install "WhatsApp Web" "https://web.whatsapp.com" --padding 0.0

# 为特定工具定制鲜明边框主题
sgwebapp install "GitHub" "https://github.com" --border-color "3b82f6" --border-width 2.0 --border-radius 26.0 --padding 8.0

# 自定义 User-Agent（Native 原生引擎默认已自动配置完整现代 Safari 桌面 UA，亦可手动指定）
sgwebapp install "SpecialApp" "https://example.com" --user-agent "CustomUserAgent/1.0"
```

---

## 🪟 活动窗口高亮边框守护程序 (`sgwebapp border`)

喜欢 **Omarchy / Hyprland** 经典的活动窗口聚焦高亮边框效果？`sgwebapp` 内置了一个用 Swift 编写的高性能后台守护程序，能够自动追踪当前获得焦点的 Chrome 窗口，并在其周围绘制浮动圆角边框。

### 启动边框
```bash
# 以默认配色启动（#89b4fa，Catppuccin Blue，2.5px 宽度）
sgwebapp border start

# 或自定义边框颜色、粗细与圆角大小：
sgwebapp border start --color 3b82f6 --width 3.0 --radius 12.0
```

### 查看状态与停止
```bash
sgwebapp border status
sgwebapp border stop
```

### `sgwebapp-border` 选项说明
```text
选项：
  --color <hex>     十六进制边框颜色（例如 89b4fa, #3b82f6, ff5555）
  --width <float>   描边宽度（pt，默认: 2.5）
  --radius <float>  窗口圆角半径（默认: 10.0）
  --all-apps        为所有活动应用窗口绘制边框，不局限于 Web App
  --app <name>      添加需要追踪的指定应用名称
```

---

## 🛠️ 底层架构与实现原理

### Web App 的组织结构
`sgwebapp` 创建的每一个应用都是位于 `~/Applications/<应用名>.app` 的标准 macOS Application Bundle：

```
~/Applications/WhatsApp Web.app/
├── Contents/
│   ├── Info.plist                     # 应用元数据、Bundle ID、边框与登录同步配置
│   ├── MacOS/
│   │   └── WhatsApp Web               # 原生引擎：编译后的 sgwebapp-runtime 二进制副本
│   │                                  # Chrome 引擎：执行 chrome --app 的启动脚本
│   └── Resources/
│       ├── AppIcon.icns               # 10 种分辨率级别的 Apple 高清图标包
│       └── sgwebapp.json              # 记录 URL、引擎、边框参数及安装时间戳
```

原生引擎应用的网页数据独立保存在 `~/Library/WebKit/<bundle-id>/` 目录下。该路径由 macOS 系统根据 bundle identifier 严格隔离，不同应用之间无法直接共享底层数据目录。因此，我们通过 Cookie 同步机制来解决登录态问题 —— 详细介绍请参阅 [docs/cookies.md](docs/cookies.md)。

### 浏览器路径解析顺序
只有 Chrome 引擎和 `import-cookies` 命令需要在本地磁盘上存在 Chromium 内核浏览器；对于默认的原生引擎，即便系统中完全没有安装任何 Chrome 也可以正常使用。在需要时，`sgwebapp` 会按如下优先顺序自动查找浏览器：
1. `$SGWEBAPP_BROWSER` 环境变量（若已设置）
2. Google Chrome (`/Applications/Google Chrome.app`)
3. Brave Browser (`/Applications/Brave Browser.app`)
4. Microsoft Edge (`/Applications/Microsoft Edge.app`)
5. Arc (`/Applications/Arc.app`)
6. Chromium (`/Applications/Chromium.app`)

### 高清图标抓取生成流程
1. 解析网页 HTML，提取 `<link rel="apple-touch-icon">` 或 `<link rel="icon">`；
2. 若未提供，则尝试回退抓取 `<域名>/apple-touch-icon.png`；
3. 再次回退至 Google Favicon 256px 高分辨率 API；
4. 调用 macOS 原生图像处理工具 `sips` 自动缩放生成 10 种标准尺寸（从 16x16 到 1024x1024）；
5. 使用系统内置的 `iconutil` 将 `.iconset` 编译封装为原生 Apple `.icns` 格式。

---

## 📊 横向对比矩阵

| 功能特性 | `sgwebapp` 原生引擎 | `sgwebapp` Chrome 引擎 | Chrome 原生 PWA | Safari 添加到程序坞 | Electron / Pake |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **真正无顶栏 / 消除交通灯** | **支持 (0 顶栏)** | ❌ 不支持 | ❌ 不支持 | ❌ 不支持 | 需手动深度定制 |
| **复用 Chrome 登录 Cookie** | 支持一键导入 | **实时无缝** | 实时无缝 | ❌ 互相隔离 | ❌ 需重新登录 |
| **支持任意网站 URL** | **支持** | **支持** | 仅限含 Manifest 的 PWA | 支持 | 支持（需重新打包） |
| **命令行快捷自动化** | **支持** | **支持** | ❌ 需浏览器手动点击 | ❌ 需手动分享添加 | 需编译打包环境 |
| **活动窗口圆角边框** | **内置原生支持** | 支持后台守护 | ❌ 无 | ❌ 无 | 仅限网页内部 CSS |
| **Widevine DRM（流媒体）** | ❌ WebKit 限制 | **支持** | 支持 | 支持 | 视配置而定 |
| **磁盘与内存资源占用** | **~1 MB** | ~1 MB | ~1 MB | ~1 MB | 100–300 MB |

---

## 🧪 自动化测试

运行自动化回归测试套件。测试全程在独立的临时沙盒中进行，绝对不会篡改您真实的 `~/.config/sgwebapp` 配置或 `~/Applications` 目录：

```bash
make test        # 验证 CLI 命令、边界安全逻辑及单元测试
make test-e2e    # 启动真实 .app 窗口测试端到端流程（需要在图形桌面会话下运行）
make lint        # 检查 Shell 脚本规范（若安装了 shellcheck）
```

`make test` 涵盖：
- CLI 命令行参数解析与 help 文本校验；
- 原生 Swift 运行时与边框守护进程的编译检测；
- `.app` Bundle 组织结构、合规的 `Info.plist` 与元数据 JSON 验证；
- 包含 `&`、引号等特殊字符以及非 ASCII 中文名称的安全转义与独立 Bundle ID 分配；
- 安全防护：拒绝覆盖或删除非本工具创建的外部 `.app`、防止应用名称路径穿越攻击、防止非法配置键注入代码；
- 守护进程生命周期（`start`, `status`, `stop`）与全局配置的读取/写入/重置；
- Chrome Cookie 解密算法（AES-CBC、PKCS7 填充、Chrome 118+ 哈希前缀、域名筛选机制）在合成测试数据库上的正确性。

`make test-e2e` 则进一步在真实桌面环境中启动应用，检验预存 Cookie 是否在首个请求发起前成功注入、`window.open` 弹窗是否能正常加载、以及导出的 Cookie 文件是否被赋予严密的 `0600` 文件权限。

---

## 📄 开源许可证

本项目基于 MIT 许可证开源。详情请参阅 [LICENSE](LICENSE) 文件。
