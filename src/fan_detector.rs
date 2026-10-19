//! CPU fan control for System76 hwmon devices the per-channel `IoBoard`
//! doesn't handle: finds the "CPU Fan" channel and drives its PWM.

use crate::errors::{FanCurveError, Result};
use log::{debug, info, warn};
use std::fs;
use std::path::PathBuf;

/// Fan sensor information
#[derive(Debug, Clone)]
pub struct FanSensor {
    pub fan_number: u8,
    pub hwmon_path: PathBuf,
    pub fan_label: String,
}

/// Fan detector for System76 Thelio IO
#[derive(Default)]
pub struct FanDetector {
    fans: Vec<FanSensor>,
}

impl FanDetector {
    pub fn new() -> Self {
        Self::default()
    }

    /// Find the CPU fan on the System76 hwmon device
    pub fn initialize(&mut self) -> Result<()> {
        let hwmon = fs::read_dir("/sys/class/hwmon")?
            .flatten()
            .map(|e| e.path())
            .find(|p| {
                let name = fs::read_to_string(p.join("name")).unwrap_or_default();
                matches!(
                    name.trim(),
                    "system76_thelio_io" | "system76_io" | "system76"
                )
            })
            .ok_or_else(|| FanCurveError::Config("System76 Thelio IO sensor not found".into()))?;

        // fanN_label / fanN_input pairs are numbered from 1 without gaps
        for fan_number in 1..=10 {
            let Ok(label) = fs::read_to_string(hwmon.join(format!("fan{}_label", fan_number)))
            else {
                break;
            };
            if !hwmon.join(format!("fan{}_input", fan_number)).exists() {
                break;
            }
            let fan_label = label.trim().to_string();
            if fan_label.to_lowercase().contains("cpu") {
                info!(
                    "Found CPU fan: fan{} '{}' at {}",
                    fan_number,
                    fan_label,
                    hwmon.display()
                );
                self.fans.push(FanSensor {
                    fan_number,
                    hwmon_path: hwmon,
                    fan_label,
                });
                return Ok(());
            }
        }

        Err(FanCurveError::Config(
            "CPU Fan not found in System76 Thelio IO".to_string(),
        ))
    }

    /// RPM of each detected fan, as (fan_number, rpm, label)
    pub fn read_all_fan_speeds(&self) -> Result<Vec<(u8, u16, String)>> {
        self.fans
            .iter()
            .map(|fan| {
                let path = fan.hwmon_path.join(format!("fan{}_input", fan.fan_number));
                let rpm = fs::read_to_string(path)?
                    .trim()
                    .parse()
                    .map_err(|_| FanCurveError::Config("Failed to parse fan speed".to_string()))?;
                Ok((fan.fan_number, rpm, fan.fan_label.clone()))
            })
            .collect()
    }

    pub fn get_fans(&self) -> &[FanSensor] {
        &self.fans
    }

    pub fn is_initialized(&self) -> bool {
        !self.fans.is_empty()
    }

    /// Set every fan to `duty` (PWM 0-255), or return them to automatic
    /// control (pwmN_enable = 2) when `duty` is None, like system76-power
    pub fn set_duty(&self, duty: Option<u8>) -> Result<()> {
        for fan in &self.fans {
            let pwm_path = fan.hwmon_path.join(format!("pwm{}", fan.fan_number));
            let enable_path = fan.hwmon_path.join(format!("pwm{}_enable", fan.fan_number));

            let Some(duty) = duty else {
                match fs::write(&enable_path, "2") {
                    Ok(()) => info!("Fan {} set to automatic mode", fan.fan_number),
                    Err(e) => warn!(
                        "Failed to enable automatic mode for fan {} at {}: {}",
                        fan.fan_number,
                        enable_path.display(),
                        e
                    ),
                }
                continue;
            };

            // Some boards have no enable file; the PWM write still takes effect.
            let _ = fs::write(&enable_path, "1");
            fs::write(&pwm_path, duty.to_string())?;
            debug!("Fan {} PWM set to {}", fan.fan_number, duty);
        }
        Ok(())
    }
}
