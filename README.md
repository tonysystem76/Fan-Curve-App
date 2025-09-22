# Fan Curve Control App

A modern GUI application for controlling CPU fan curves on System76 systems, built with Rust and egui.

## Features

- 🎛️ **Interactive Fan Curve Editor** - Create custom fan curves with an intuitive GUI
- 🌡️ **Real-time Temperature Monitoring** - Monitor CPU temperatures and fan speeds
- 📊 **Multiple Curve Profiles** - Save and switch between different fan curve configurations
- 🔧 **System76 Integration** - Native integration with `system76-power` via DBus
- 🧰 **Manual Override** - Force a fan duty (0–100%) on demand
- 🧩 **Optional Thelio IO Integration** - Experimental hook to the Thelio IO daemon
- 🚀 **High Performance** - Built with Rust for optimal performance and reliability

## Quick Installation

### One-Command Install

```bash
curl -sSL https://raw.githubusercontent.com/tonysystem76/Fan-Curve-App/main/install.sh | bash
```

### Manual Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/tonysystem76/Fan-Curve-App.git
   cd Fan-Curve-App
   ```

2. **Run the installation script:**
   ```bash
   ./install.sh
   ```

3. **Launch the application:**
   ```bash
   fan-curve --gui
   ```

## Requirements

- **Operating System:** Linux (tested on Pop!_OS and Ubuntu)
- **Hardware:** System76 desktop/laptop (Thelio IO supported for CPU fan via `pwm1`)
- **Dependencies:** Rust 1.75+, build tools, X11 libraries

The installation script will automatically install all required dependencies.

## Usage

### Command Line Interface

```bash
# Launch GUI
fan-curve --gui

# List available fan curves
fan-curve list

# Apply a specific curve
fan-curve apply "Performance"

# Show help
fan-curve --help
```

### GUI Application

1. Launch the application from your applications menu or run `fan-curve --gui`.
2. Select a fan curve from the dropdown and click "Apply fan curve".
3. The curve is applied in real-time; duty is set via `system76-power` DBus.
4. Use "Manual Fan Control" to temporarily override duty with a slider.
5. Use "Max Fans" to force full speed (PWM 255). Use "Auto Fans" to return control to the curve/daemon.

Notes:
- 100% duty maps to PWM 255, driving the CPU fan to full speed.
- Currently the app controls the CPU fan channel (`pwm1`). Additional channels may be added later.

## Configuration
### system76-power Integration

This app integrates with a fork of `system76-power` that exposes a `com.system76.PowerDaemon.Fan` DBus interface with `SetDuty(u8)`, `SetAuto()`, and `FullSpeed()` methods. When available, the app uses this interface to set duty persistently. If unavailable, it falls back to direct sysfs writes.

Switch your system to use your fork (recommended) with:

```bash
sudo /home/system76/Fan-Curve-App/install-system76-power-fork.sh
```

This will:
- Build your fork at `/home/system76/system76-power`
- Install the binary to `/usr/local/bin/system76-power`
- Add a systemd override so the daemon runs your forked binary
- Restart the daemon and hold the distro package to prevent overwrite

To revert:

```bash
sudo rm /etc/systemd/system/com.system76.PowerDaemon.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart com.system76.PowerDaemon.service
```
### Thelio IO (Experimental)

Set an environment variable to enable Thelio IO integration. When enabled, the app will attempt to detect the Thelio IO DBus service and, if present, use it as a backend for chassis fan telemetry/control in future updates.

```bash
export FAN_APP_ENABLE_THELIO_IO=1
# Optional: override service name if needed
export FAN_APP_THELIO_IO_SERVICE="com.system76.ThelioIo"
```

Notes:
- If the service is not present, the application continues to function normally (no-op backend).
- Current implementation focuses on CPU fan (`pwm1`); additional channels may be added later.


Configuration files are stored in `~/.fan_curve_app/config.json`. You can edit this file directly or use the GUI to modify settings.

### Default Curves

- **Standard** - Balanced performance and noise
- **Quiet** - Lower fan speeds for quieter operation
- **Performance** - Higher fan speeds for maximum cooling

## Building from Source

If you prefer to build from source:

```bash
# Install Rust (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Clone and build
git clone https://github.com/tonysystem76/Fan-Curve-App.git
cd Fan-Curve-App
cargo build --release

# Run
./target/release/fan-curve-app --gui
```

## Uninstallation

To uninstall the application:

```bash
# Run the uninstall script
~/uninstall-fan-curve-app.sh

# Or manually remove:
sudo rm /usr/local/bin/fan-curve-app /usr/local/bin/fan-curve
rm -rf ~/.fan_curve_app
rm ~/.local/share/applications/fan-curve-app.desktop
rm ~/.local/share/icons/fan-curve-app.svg
```

## Troubleshooting

### DBus Access Denied
If DBus calls to `com.system76.PowerDaemon.Fan` fail with `AccessDenied`, ensure a polkit policy allows your user to call `SetDuty`, `SetAuto`, and `FullSpeed`, or run the included installer to switch to the fork that includes the fan DBus interface.

### Fans do not reach full speed at 100%
- Ensure your system is using the forked `system76-power` via the installer script.
- Some hardware requires a direct raw write of PWM 255; the fork handles this for `pwm1` when duty is 100%.

### Desktop Entry Not Appearing
After installation, you may need to log out and back in for the desktop entry to appear in your applications menu.

### Build Issues
If you encounter build issues, make sure all dependencies are installed:
```bash
# Ubuntu/Debian
sudo apt-get install build-essential pkg-config libssl-dev libx11-dev libxcb1-dev

# Arch Linux
sudo pacman -S base-devel openssl pkgconf libx11 libxcb
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For issues and questions, please open an issue on the [GitHub repository](https://github.com/tonysystem76/Fan-Curve-App/issues).