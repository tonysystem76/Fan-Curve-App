//! Local sensor readings, for the GUI when no daemon is running and for the
//! `fan-curve test` command.

use crate::cpu_temp::CpuTempDetector;
use crate::errors::{FanCurveError, Result};
use crate::fan::FanCurve;
use crate::fan_detector::FanDetector;
use chrono::{DateTime, Local};
use log::warn;
use std::fs;
use std::sync::Mutex;
use tokio::time::{sleep, Duration};

/// Fan data point for monitoring
#[derive(Debug, Clone)]
pub struct FanDataPoint {
    pub timestamp: DateTime<Local>,
    pub temperature: f32,
    pub fan_speeds: Vec<(u8, u16, String)>, // (fan_number, speed, label)
    /// Duty in ten-thousandths (0-10000)
    pub fan_duty: u16,
    pub cpu_usage: f32,
}

#[derive(Default)]
pub struct FanMonitor {
    fan_curve: Option<FanCurve>,
    cpu_temp_detector: CpuTempDetector,
    fan_detector: FanDetector,
    /// Previous /proc/stat CPU times (idle, total), so usage can be measured
    /// over the interval between readings rather than since boot
    prev_cpu_times: Mutex<Option<(u64, u64)>>,
}

impl FanMonitor {
    pub fn new() -> Self {
        Self::default()
    }

    /// Detect the CPU temperature sensor and fans; either may be missing
    pub fn initialize(&mut self) {
        if let Err(e) = self.cpu_temp_detector.initialize() {
            warn!("CPU temperature detection unavailable: {}", e);
        }
        if let Err(e) = self.fan_detector.initialize() {
            warn!("Fan detection unavailable: {}", e);
        }
    }

    /// Curve used to compute `FanDataPoint::fan_duty`
    pub fn set_fan_curve(&mut self, curve: FanCurve) {
        self.fan_curve = Some(curve);
    }

    pub fn cpu_temp_detector(&self) -> &CpuTempDetector {
        &self.cpu_temp_detector
    }

    /// Read the sensors and the duty the curve gives (does not write the fans)
    pub fn get_current_fan_data_sync(&self) -> Result<FanDataPoint> {
        let temperature = self.cpu_temp_detector.read_temperature()?;
        Ok(FanDataPoint {
            timestamp: Local::now(),
            temperature,
            fan_speeds: self.fan_detector.read_all_fan_speeds()?,
            fan_duty: self
                .fan_curve
                .as_ref()
                .map_or(0, |c| c.calculate_duty_for_temperature_celsius(temperature)),
            cpu_usage: self.read_cpu_usage()?,
        })
    }

    /// CPU usage in percent since the previous call (since boot on the first)
    pub fn read_cpu_usage(&self) -> Result<f32> {
        let current = parse_cpu_times(&fs::read_to_string("/proc/stat")?)?;
        let previous = self.prev_cpu_times.lock().unwrap().replace(current);
        Ok(cpu_usage_between(previous.unwrap_or((0, 0)), current))
    }
}

/// Run every fan at 100% for `duration_seconds`, printing live readings
pub async fn test_fan_curve(duration_seconds: u64) -> Result<()> {
    println!("Starting fan curve test for {} seconds", duration_seconds);
    println!("Real-time monitoring will begin in 3 seconds...\n");
    for i in (1..=3).rev() {
        println!("Starting in {}...", i);
        sleep(Duration::from_secs(1)).await;
    }
    println!("Test started! Press Ctrl+C to stop early.\n");

    let mut monitor = FanMonitor::new();
    monitor.initialize();
    let mut full_speed = FanCurve::new("Test 100%".to_string());
    full_speed.add_point(0, 10000);
    monitor.set_fan_curve(full_speed);

    for remaining in (1..=duration_seconds).rev() {
        match monitor.get_current_fan_data_sync() {
            Ok(data) => {
                let pwm = ((u32::from(data.fan_duty) * 255) / 10000) as u8;
                if let Err(e) = monitor.fan_detector.set_duty(Some(pwm)) {
                    warn!("Failed to apply fan curve: {}", e);
                }
                let fans = if data.fan_speeds.is_empty() {
                    "No fans".to_string()
                } else {
                    data.fan_speeds
                        .iter()
                        .map(|(_, speed, label)| format!("{}: {} RPM", label, speed))
                        .collect::<Vec<_>>()
                        .join(" | ")
                };
                println!(
                    " Temperature: {:.1}°C | Fans: {} | Fan Duty: {}% | CPU: {:.1}% | {}",
                    data.temperature,
                    fans,
                    data.fan_duty / 100,
                    data.cpu_usage,
                    data.timestamp.format("%H:%M:%S")
                );
            }
            Err(e) => warn!("Failed to read fan data: {}", e),
        }
        if remaining % 10 == 0 || remaining <= 10 {
            println!("Time remaining: {} seconds", remaining);
        }
        sleep(Duration::from_secs(1)).await;
    }

    println!("\n Fan curve test completed!");
    Ok(())
}

/// Aggregate CPU times from /proc/stat as (idle, total), in clock ticks.
fn parse_cpu_times(stat_content: &str) -> Result<(u64, u64)> {
    let invalid = || FanCurveError::Config("Invalid /proc/stat format".to_string());
    // cpu user nice system idle iowait irq softirq steal ...
    let fields: Vec<u64> = stat_content
        .lines()
        .next()
        .ok_or_else(invalid)?
        .split_whitespace()
        .skip(1)
        .take(8)
        .map(|f| f.parse().map_err(|_| invalid()))
        .collect::<Result<_>>()?;
    if fields.len() < 7 {
        return Err(invalid());
    }

    let idle = fields[3] + fields[4]; // idle + iowait
    let total = fields.iter().sum();
    Ok((idle, total))
}

/// Percent of time the CPU was busy between two (idle, total) samples.
fn cpu_usage_between(previous: (u64, u64), current: (u64, u64)) -> f32 {
    let idle = current.0.saturating_sub(previous.0);
    let total = current.1.saturating_sub(previous.1);
    if total == 0 {
        return 0.0;
    }
    ((total - idle.min(total)) as f32 / total as f32 * 100.0).clamp(0.0, 100.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_aggregate_cpu_line() {
        let stat = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 50 0 25 400 25 0 0 0 0 0\n";
        assert_eq!(parse_cpu_times(stat).unwrap(), (850, 1000));
    }

    #[test]
    fn usage_is_measured_between_samples() {
        // 1000 ticks pass, 250 of them idle -> 75% busy
        assert_eq!(cpu_usage_between((850, 1000), (1100, 2000)), 75.0);
        // No time passed
        assert_eq!(cpu_usage_between((850, 1000), (850, 1000)), 0.0);
    }
}
