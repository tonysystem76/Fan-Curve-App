# System76 Power Fan DBus Integration Plan

## Goal
Add a Fan DBus API to your fork of system76-power and update Fan-Curve-App to use it so fan duty persists and isn’t overridden by system76-power.

## Why
- system76-power already sets PWM by writing `pwm1_enable` and `pwm1..pwm4` (see upstream fan.rs) [Upstream reference](https://github.com/pop-os/system76-power/blob/master/src/fan.rs).
- The current DBus API on `com.system76.PowerDaemon` does not expose fan methods (introspection shows no fan endpoints).
- By adding a Fan DBus interface to system76-power and calling it from Fan-Curve-App, system76-power remains the authority and prevents races/overrides.

## Repository to modify
- Fork: https://github.com/tonysystem76/system76-power
- Target branch for PR: `master` (or a feature branch, e.g. `feature/fan-dbus`)

## DBus API to add (in system76-power)
- Object path: `/com/system76/PowerDaemon/Fan`
- Interface: `com.system76.PowerDaemon.Fan`
- Methods:
  - `SetDuty(y duty)`
    - Puts fans in manual (enable) mode and writes the same PWM value (0–255) to `pwm1`, `pwm2`, `pwm3`, `pwm4`.
    - Equivalent to existing internal `set_duty(Some(duty))` logic.
  - `SetAuto()`
    - Returns to automatic mode; sets `pwm1_enable = "2"` (and any other required resets).
- Optional (later):
  - `GetDuty() -> (b manual, y duty)` (if you cache the last set or read back current)
  - `GetRpm() -> a(uy)` or similar to enumerate fan RPMs.

## Implementation steps (system76-power)
1. Reuse fan logic
   - The existing `fan.rs` includes the write paths (`pwm1_enable`, `pwm1..pwm4`). Keep a handle to this fan/platform manager.
2. Create DBus adapter
   - New module: `src/fan_dbus.rs`
   - Define a struct (e.g., `FanDbus`) that has access to the fan manager.
   - Implement DBus with `#[dbus_interface(name = "com.system76.PowerDaemon.Fan")]` and methods `SetDuty` and `SetAuto`.
3. Register the object on the system bus
   - In the daemon setup (where `com.system76.PowerDaemon` service is registered), also `serve_at("/com/system76/PowerDaemon/Fan", fan_dbus_instance)`.
4. Build and deploy
   - `cargo build --release`
   - Ensure the systemd service `com.system76.PowerDaemon.service` starts your updated binary.
5. Verify DBus surface
   - `busctl --system introspect com.system76.PowerDaemon /com/system76/PowerDaemon/Fan | cat`
   - You should see `SetDuty` and `SetAuto` methods.
6. Manual DBus tests
   - Set full duty: `busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetDuty y 255`
   - Set auto: `busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto`

## Fan-Curve-App updates (already prepared here)
- New client methods in `src/system76_power_client.rs`:
  - `set_fan_duty_via_power(duty_pwm: u8)`
  - `set_fan_auto_via_power()`
- Flow change in `FanMonitor::apply_fan_curve`:
  - Convert duty% → PWM by `(duty_percent * 255) / 100`.
  - Attempt DBus `SetDuty` first; on error (method not present/service down), fall back to direct sysfs write once.
- Build & test:
  - `cargo build`
  - `sudo ./target/debug/fan-curve-app fan-curve test 10`
  - Expect DBus path to be used once your daemon exposes `/Fan`; otherwise direct sysfs fallback is used.

## Validation checklist
- DBus introspection of `/com/system76/PowerDaemon/Fan` shows `SetDuty` and `SetAuto`.
- Calling `SetDuty 255` drives RPM near max (~2200 RPM on your system) and stays there.
- Fan-Curve-App logs show: `Set fan duty via system76-power Fan DBus: 255` and no repeated fallback warnings.
- GUI and CLI reflect stable high RPM at 100% duty without reversion by system76-power.

## References
- Upstream fan logic (writes to pwm*): https://github.com/pop-os/system76-power/blob/master/src/fan.rs
- Fork used for PR and testing: https://github.com/tonysystem76/system76-power

---

### (Optional) Example DBus adapter skeleton (system76-power)
```rust
use zbus::{dbus_interface, SignalContext};

pub struct FanDbus {
    fan: FanManager, // your existing handler for writes
}

impl FanDbus {
    pub fn new(fan: FanManager) -> Self { Self { fan } }
}

#[dbus_interface(name = "com.system76.PowerDaemon.Fan")]
impl FanDbus {
    /// Set the current duty cycle, from 0 to 255
    fn SetDuty(&self, duty: u8) -> zbus::fdo::Result<()> {
        self.fan.set_duty(Some(duty));
        Ok(())
    }

    /// Return to automatic fan control
    fn SetAuto(&self) -> zbus::fdo::Result<()> {
        self.fan.set_duty(None);
        Ok(())
    }
}
```

### Daemon wiring (system bus)
```rust
use zbus::ConnectionBuilder;

let fan_dbus = FanDbus::new(fan_manager.clone());
let _conn = ConnectionBuilder::system()?
    .name("com.system76.PowerDaemon")?
    .serve_at("/com/system76/PowerDaemon/Fan", fan_dbus)?
    .build()
    .await?;
```

> Note: adapt the ownership/cloning to your daemon architecture; ensure the service stays alive.
