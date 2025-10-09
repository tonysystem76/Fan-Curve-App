#!/bin/bash

# Fan Curve App - PWM Bypass Solution
# This script implements Option 1: PWM Bypass for system76-power 1.2.8 issues

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to show current status
show_status() {
    print_status "=== Current Status ==="
    echo "PWM value: $(cat /sys/class/hwmon/hwmon3/pwm1)"
    echo "Daemon status: $(systemctl is-active com.system76.PowerDaemon.service)"
    echo "PWM file permissions: $(ls -l /sys/class/hwmon/hwmon3/pwm1)"
    echo ""
}

# Function to implement PWM bypass
implement_pwm_bypass() {
    print_status "=== Implementing PWM Bypass ==="
    
    # Step 1: Stop system76-power daemon
    print_status "Step 1: Stopping system76-power daemon..."
    sudo systemctl stop com.system76.PowerDaemon.service
    print_success "✓ Daemon stopped"
    
    # Step 2: Enable manual PWM control
    print_status "Step 2: Enabling manual PWM control..."
    echo "1" | sudo tee /sys/class/hwmon/hwmon3/pwm1_enable > /dev/null
    print_success "✓ Manual PWM control enabled"
    
    # Step 3: Test PWM control
    print_status "Step 3: Testing PWM control..."
    local initial_pwm=$(cat /sys/class/hwmon/hwmon3/pwm1)
    echo "200" | sudo tee /sys/class/hwmon/hwmon3/pwm1 > /dev/null
    sleep 1
    local test_pwm=$(cat /sys/class/hwmon/hwmon3/pwm1)
    
    if [ "$test_pwm" = "200" ]; then
        print_success "✓ PWM control working! (set to 200)"
    else
        print_warning "✗ PWM control not working (expected 200, got $test_pwm)"
    fi
    
    # Restore original value
    echo "$initial_pwm" | sudo tee /sys/class/hwmon/hwmon3/pwm1 > /dev/null
    print_status "Restored PWM to original value: $initial_pwm"
    
    echo ""
}

# Function to run fan curve app
run_fan_curve_app() {
    print_status "=== Running Fan Curve App ==="
    print_status "Starting fan curve app with PWM bypass..."
    echo ""
    print_warning "The app should now work without permission errors!"
    echo "Press Ctrl+C to stop the app and restore system76-power"
    echo ""
    
    # Run the fan curve app
    ./target/release/fan-curve-app --gui
}

# Function to restore system76-power
restore_system76_power() {
    print_status "=== Restoring System76-Power ==="
    
    # Re-enable automatic control
    print_status "Re-enabling automatic fan control..."
    echo "2" | sudo tee /sys/class/hwmon/hwmon3/pwm1_enable > /dev/null
    print_success "✓ Automatic fan control re-enabled"
    
    # Restart daemon
    print_status "Restarting system76-power daemon..."
    sudo systemctl start com.system76.PowerDaemon.service
    print_success "✓ Daemon restarted"
    
    # Verify restoration
    sleep 2
    local daemon_status=$(systemctl is-active com.system76.PowerDaemon.service)
    if [ "$daemon_status" = "active" ]; then
        print_success "✓ System76-power fully restored"
    else
        print_warning "✗ Daemon not active (status: $daemon_status)"
    fi
    
    echo ""
}

# Function to run complete test
run_complete_test() {
    print_status "=== Complete PWM Bypass Test ==="
    
    show_status
    implement_pwm_bypass
    
    print_status "PWM bypass is ready! Your fan curve app should now work."
    echo ""
    echo "To test:"
    echo "1. Run: ./target/release/fan-curve-app --gui"
    echo "2. Set fan curve points (40°C, 50°C, 60°C at 100%)"
    echo "3. Watch PWM values change in real-time"
    echo "4. When done, run: $0 restore"
    echo ""
}

# Function to show help
show_help() {
    echo "Fan Curve App - PWM Bypass Solution"
    echo ""
    echo "This script solves the system76-power 1.2.8 PWM control issues"
    echo "by bypassing the daemon and enabling direct PWM control."
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  bypass     - Implement PWM bypass (default)"
    echo "  test       - Run complete test"
    echo "  run        - Run fan curve app with bypass"
    echo "  restore    - Restore system76-power"
    echo "  status     - Show current status"
    echo "  help       - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 bypass     # Implement bypass and test"
    echo "  $0 run        # Run fan curve app"
    echo "  $0 restore    # Restore system76-power"
    echo ""
    echo "Workflow:"
    echo "  1. $0 bypass  # Setup PWM bypass"
    echo "  2. $0 run     # Run your fan curve app"
    echo "  3. $0 restore # Restore when done"
    echo ""
}

# Main function
main() {
    case "${1:-bypass}" in
        "bypass")
            implement_pwm_bypass
            ;;
        "test")
            run_complete_test
            ;;
        "run")
            run_fan_curve_app
            ;;
        "restore")
            restore_system76_power
            ;;
        "status")
            show_status
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
