#!/bin/bash

# Manual PWM Bypass Solution
# Run these commands manually to test the PWM bypass

echo "=== Manual PWM Bypass Solution ==="
echo ""
echo "Since the daemon is already stopped, let's test PWM control:"
echo ""
echo "1. Test PWM control (run this command):"
echo "   echo '200' | sudo tee /sys/class/hwmon/hwmon3/pwm1"
echo ""
echo "2. Check if PWM changed:"
echo "   cat /sys/class/hwmon/hwmon3/pwm1"
echo ""
echo "3. If PWM changed to 200, run your fan curve app:"
echo "   ./target/release/fan-curve-app --gui"
echo ""
echo "4. When done, restore system76-power:"
echo "   sudo systemctl start com.system76.PowerDaemon.service"
echo ""
echo "=== Current Status ==="
echo "PWM value: $(cat /sys/class/hwmon/hwmon3/pwm1)"
echo "Daemon status: $(systemctl is-active com.system76.PowerDaemon.service)"
echo ""
echo "If PWM control works (step 1-2), then your fan curve app should work!"
echo "If PWM control doesn't work, we need to fix the PWM file permissions."
