# sgwebapp 🚀

> **Bringing Omarchy's Web App experience to macOS.**  
> Convert any website into a standalone, distraction-free macOS desktop app in seconds — with 100% native Chrome cookie sharing, retina `.icns` icons, Spotlight integration, and optional Hyprland-style active window borders.

---

## 🌟 Features

- **🚫 True 0-Topbar & 0-Traffic-Light Mode (Native Engine, Default)**: A compiled native Cocoa/WebKit runner that creates 100% frameless windows with zero title bars and zero traffic lights, surrounded by a customizable Hyprland-style rounded accent border.
- **🍪 Dual Engine Support**:
  - **Native Engine (`--engine native`, Default)**: Completely frameless (0 titlebar, 0 traffic lights), native WebKit GPU acceleration, independent Dock icon and name, persistent cookie store.
  - **Chrome Engine (`--engine chrome`)**: Direct Chromium `--app` mode reusing Google Chrome's live active profile and cookies.
- **🎨 Retina macOS Icons (`.icns`)**: Automatically downloads high-resolution `apple-touch-icon` from target pages and builds native multi-size Apple `.icns` packages using macOS built-in `sips` and `iconutil`.
- **🔍 Full macOS Desktop Integration**: Installs to `~/Applications/<Name>.app`. Fully indexable and launchable via **Spotlight (`Cmd + Space`)**, **Launchpad**, and the **Dock**.
- **🪟 Built-in Native Border Daemon (`sgwebapp-border`)**: A standalone, zero-dependency Swift daemon that draws a customizable rounded border (inspired by Omarchy / Hyprland) around active windows.
- **⚡ Ultra Lightweight**: Native runner is only ~100 KB! No Electron bloat, no Node.js runtime, instantaneous startup.

---

## 📦 Installation & Setup

Clone the repository and add `bin/` to your `$PATH`:

```bash
git clone https://github.com/wuvist/sgwebapp.git ~/code/sgwebapp
cd ~/code/sgwebapp

# Compile the native runtime & border daemon, then run tests
make build
make test
```

### Add to your PATH
Add this line to your `~/.zshrc` or `~/.bashrc`:
```bash
export PATH="$HOME/code/sgwebapp/bin:$PATH"
```
Or install system-wide to `/usr/local/bin`:
```bash
sudo make install
```

---

## 🚀 Quick Start

### 1. Install a Web App (Frameless with 0 Top Bar & Border)
```bash
# Default: Native frameless engine (0 topbar, 0 traffic lights, beautiful border)
sgwebapp install "Solaree" "https://solaree.ai/index_cn.html"
sgwebapp install "Google Maps" "https://www.google.com/maps"

# Customize the accent border color and width:
sgwebapp install "GitHub" "https://github.com" --border-color "3b82f6" --border-width 3.0

# Optional: If you prefer Chrome's engine directly (retaining standard 28px traffic lights):
sgwebapp install "Solaree" "https://solaree.ai/index_cn.html" --engine chrome
```

Once installed:
- Press <kbd>Cmd</kbd> + <kbd>Space</kbd>, type `Solaree` or `Google Maps`, and press <kbd>Enter</kbd>.
- Or launch from the terminal: `sgwebapp launch "Solaree"`.

### 2. List Installed Web Apps
```bash
sgwebapp list
```
Output:
```
APP NAME                  URL                                           PATH
--------                  ---                                           ----
Solaree                   https://solaree.ai/index_cn.html              /Users/wuvist/Applications/Solaree.app
Google Maps               https://www.google.com/maps                   /Users/wuvist/Applications/Google Maps.app
```

### 3. Launch an App or URL
```bash
sgwebapp launch "Solaree"
# Or open any URL directly in app mode:
sgwebapp launch "https://news.ycombinator.com"
```

### 4. Remove a Web App
```bash
# Non-interactive:
sgwebapp remove "Solaree"

# Interactive (prompts with a list):
sgwebapp remove
```

---

## 🎨 macOS Tahoe Aesthetic & Configuration (`sgwebapp config`)

`sgwebapp` defaults to the **macOS Tahoe (macOS 26)** Liquid Glass design language:
- **Large concentric squircle corners**: `18.0 pt` corner radius.
- **Ultra-fine glass stroke**: `1.2 pt` border width.
- **Dynamic appearance**: Border color `"tahoe"` automatically shifts between a luminous translucent white outline (`alpha 0.22`) in Dark Mode and a refined subtle dark outline (`alpha 0.16`) in Light Mode.
- **Liquid Glass padding**: Optional content padding (`padding`, default `0.0 pt` for full-bleed apps like maps, or `8.0`–`12.0 pt` for a floating native Tahoe sidebar/window feel) revealing the frosted backdrop blur.

### View & Update Global Defaults
You can configure global defaults stored in `~/.config/sgwebapp/config.json`:

```bash
# View current configuration
sgwebapp config

# Set default border to a colorful accent (e.g. Catppuccin Blue, Emerald, or Rose)
sgwebapp config set border_color 89b4fa
sgwebapp config set border_width 2.0
sgwebapp config set border_radius 18.0
sgwebapp config set padding 10.0

# Reset anytime back to macOS Tahoe defaults
sgwebapp config reset
```

### Per-App Customization
You can also override the style when installing an individual app:
```bash
# Tahoe full-bleed style (default, padding: 0)
sgwebapp install "Google Maps" "https://www.google.com/maps"

# Tahoe frosted inset style (padding: 10pt)
sgwebapp install "Solaree" "https://solaree.ai/index_cn.html" --padding 10.0

# Custom accent style for a specific app
sgwebapp install "GitHub" "https://github.com" --border-color "3b82f6" --border-width 2.0 --border-radius 16.0 --padding 8.0
```

---

## 🪟 Active Window Border Daemon (`sgwebapp border`)

Want the signature **Omarchy / Hyprland** active window border on macOS? `sgwebapp` includes a compiled Swift daemon that tracks active Chrome web app windows and renders a floating rounded border over them.

### Start the Border
```bash
# Start with default accent color (#89b4fa, Catppuccin Blue, 2.5px width)
sgwebapp border start

# Or customize color, width, and corner radius:
sgwebapp border start --color 3b82f6 --width 3.0 --radius 12.0
```

### Check Status & Stop
```bash
sgwebapp border status
sgwebapp border stop
```

### CLI Options for `sgwebapp-border`
```text
Options:
  --color <hex>     Border color in hex (e.g. 89b4fa, #3b82f6, ff5555)
  --width <float>   Border stroke width in points (default: 2.5)
  --radius <float>  Window corner radius (default: 10.0)
  --all-apps        Render border for all active apps, not just web apps
  --app <name>      Add specific application name to track
```

---

## 🛠️ Architecture & Under the Hood

### How Web Apps are Structured
Each app created by `sgwebapp` is a standard macOS application bundle located in `~/Applications/<AppName>.app`:

```
~/Applications/Solaree.app/
├── Contents/
│   ├── Info.plist                     # App metadata & bundle identifier
│   ├── MacOS/
│   │   └── launcher                   # Executable script invoking Chrome --app
│   └── Resources/
│       ├── AppIcon.icns               # 10-tier high-res Apple icon
│       └── sgwebapp.json              # App URL, creation timestamp, browser
```

### Browser Engine Resolution
`sgwebapp` detects and supports the following Chromium-family browsers in order of preference:
1. `$SGWEBAPP_BROWSER` environment variable (if specified)
2. Google Chrome (`/Applications/Google Chrome.app`)
3. Brave Browser (`/Applications/Brave Browser.app`)
4. Microsoft Edge (`/Applications/Microsoft Edge.app`)
5. Arc (`/Applications/Arc.app`)
6. Chromium (`/Applications/Chromium.app`)

### Icon Fetching Pipeline
1. Parses site HTML for `<link rel="apple-touch-icon">` or `<link rel="icon">`.
2. Fallback to `<origin>/apple-touch-icon.png`.
3. Fallback to Google Favicon 256px resolution API.
4. Uses macOS native `sips` to generate 10 standard icon resolutions (16x16 up to 1024x1024).
5. Compiles `.iconset` into a native `.icns` file using `iconutil`.

---

## 📊 Comparison Matrix

| Feature | `sgwebapp` | Chrome PWA | Safari Web App (Sonoma) | Electron / Pake |
| :--- | :---: | :---: | :---: | :---: |
| **Chrome Cookie Reuse** | **100% (Instant)** | 100% | ❌ Isolated sandbox | ❌ Requires re-login |
| **Install Any Arbitrary URL** | **Yes** | Only if site has PWA manifest | Yes | Yes (requires build) |
| **CLI Automation** | **Yes (`sgwebapp install`)** | ❌ Manual UI clicks | ❌ Manual UI clicks | Requires packaging |
| **Distraction-Free Window** | **Yes** | Yes | Yes | Yes |
| **Active Window Border** | **Yes (Built-in Swift daemon)** | ❌ No | ❌ No | ❌ Custom CSS only |
| **Disk & RAM Footprint** | **~1 MB (Shared Chrome engine)** | ~1 MB | ~1 MB | 100 MB - 300 MB |

---

## 🧪 Testing

Run the included automated regression test suite:

```bash
make test
```

This verifies:
- CLI command validation and help outputs
- Swift daemon compilation
- `.app` bundle structure and metadata creation
- Listing and filtering
- Daemon lifecycle (`start`, `status`, `stop`)
- Clean application removal and deregistration

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
