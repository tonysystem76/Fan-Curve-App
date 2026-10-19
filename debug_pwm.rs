use fan_curve_app::fan_detector::FanDetector;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    println!("PWM Debug Tool - Testing 100% Fan Control");
    println!("=============================================\n");

    let mut fan_detector = FanDetector::new();
    if let Err(e) = fan_detector.initialize() {
        println!("Failed to initialize fan detector: {}", e);
        return Err(e.into());
    }
    println!("Fan detector initialized successfully");
    println!(" Found {} fans", fan_detector.get_fans().len());
    for fan in fan_detector.get_fans() {
        println!(
            "Fan {}: {} at {}",
            fan.fan_number,
            fan.fan_label,
            fan.hwmon_path.display()
        );
    }

    println!("\n Testing PWM Control at 100% (PWM value 255)");
    println!("===============================================");
    match fan_detector.set_duty(Some(255)) {
        Ok(()) => println!("Successfully set PWM to 255 (100%)"),
        Err(e) => println!("Failed to set PWM to 255: {}", e),
    }

    println!("\n Verifying PWM values...");
    for fan in fan_detector.get_fans() {
        let path = fan.hwmon_path.join(format!("pwm{}", fan.fan_number));
        match std::fs::read_to_string(&path) {
            Ok(value) => println!("Fan {} PWM value: {}", fan.fan_number, value.trim()),
            Err(e) => println!("Failed to read {}: {}", path.display(), e),
        }
    }

    println!("\n Debug test completed!");
    println!("\n If fans are not running at 100%, check:");
    println!(" 1. Are you running as root/sudo?");
    println!(" 2. Are the PWM files writable?");
    println!(" 3. Is the correct hwmon device detected?");
    println!(" 4. Are the fans physically connected?");

    Ok(())
}
