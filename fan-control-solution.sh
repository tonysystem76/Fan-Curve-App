#!/bin/bash

# Comprehensive Fan Control Solution
# This script addresses both permission issues and PWM persistence problems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Comprehensive Fan Control Solution

Usage: $0 <command>

Commands:
    diagnose         Diagnose current fan control issues
    fix-permissions  Fix PWM file permissions for user access
    test-direct      Test direct PWM control (requires sudo)
    test-dbus        Test DBus fan control via system76-power
    test-combined    Test both methods together
    run-app-sudo     Run fan curve app with sudo
    run-app-dbus     Run fan curve app using DBus method

Examples:
    $0 diagnose      # Check current state
    $0 test-direct   # Test direct PWM control
    $0 run-app-sudo  # Run app with sudo (bypasses permissions)

EOF
}

diagnose_issues() {
    print_status "=== Fan Control Diagnosis ==="
    echo ""
    
    # Check PWM file permissions
    print_status "1. PWM File Permissions:"
    PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"
    if [ -f "$PWM_FILE" ]; then
        echo "   File: $PWM_FILE"
        echo "   Permissions: $(ls -l "$PWM_FILE")"
        echo "   Current value: $(cat "$PWM_FILE")"
        
        if [ -w "$PWM_FILE" ]; then
            print_success "   File is writable by current user"
        else
            print_warning "   File is NOT writable by current user (needs sudo)"
        fi
    else
        print_error "   PWM file not found: $PWM_FILE"
    fi
    
    echo ""
    
    # Check system76-power daemon
    print_status "2. System76-Power Daemon:"
    if systemctl is-active --quiet com.system76.PowerDaemon.service; then
        print_success "   Daemon is RUNNING"
        echo "   PID: $(pgrep system76-power)"
        echo "   Version: $(system76-power --version)"
    else
        print_warning "   Daemon is STOPPED"
    fi
    
    echo ""
    
    # Check DBus fan interface
    print_status "3. DBus Fan Interface:"
    if busctl --system list | grep -q "com.system76.PowerDaemon"; then
        print_success "   DBus interface available"
        echo "   Methods: SetDuty, SetAuto, FullSpeed"
    else
        print_error "   DBus interface not available"
    fi
    
    echo ""
    
    # Test recent PWM changes
    print_status "4. Recent PWM Activity:"
    echo "   Current PWM: $(cat "$PWM_FILE")"
    echo "   Recent daemon logs:"
    journalctl -u com.system76.PowerDaemon.service --since "2 minutes ago" | grep -E "(set_duty|PWM)" | tail -3 || echo "   No recent PWM activity"
}

test_direct_pwm() {
    print_status "Testing direct PWM control (requires sudo)..."
    
    PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"
    ENABLE_FILE="/sys/class/hwmon/hwmon3/pwm1_enable"
    
    echo "Current PWM: $(cat "$PWM_FILE")"
    
    print_status "Setting PWM to 255 (100%)..."
    echo "255" | sudo tee "$PWM_FILE" > /dev/null
    
    if [ -f "$ENABLE_FILE" ]; then
        echo "1" | sudo tee "$ENABLE_FILE" > /dev/null
        print_status "Enabled manual PWM control"
    fi
    
    echo "PWM after setting: $(cat "$PWM_FILE")"
    
    print_status "Monitoring for 5 seconds..."
    for i in {1..5}; do
        pwm_val=$(cat "$PWM_FILE")
        echo "   [$i] PWM: $pwm_val"
        sleep 1
    done
    
    if [ "$(cat "$PWM_FILE")" = "255" ]; then
        print_success "Direct PWM control works!"
    else
        print_warning "PWM was overwritten - something else is controlling it"
    fi
}

test_dbus_pwm() {
    print_status "Testing DBus PWM control..."
    
    PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"
    
    echo "Current PWM: $(cat "$PWM_FILE")"
    
    print_status "Calling SetAuto to disable automatic control..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    
    print_status "Calling SetDuty(255) for 100% fan speed..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetDuty y 255
    
    echo "PWM after DBus call: $(cat "$PWM_FILE")"
    
    print_status "Monitoring for 5 seconds..."
    for i in {1..5}; do
        pwm_val=$(cat "$PWM_FILE")
        echo "   [$i] PWM: $pwm_val"
        sleep 1
    done
    
    if [ "$(cat "$PWM_FILE")" = "255" ]; then
        print_success "DBus PWM control works!"
    else
        print_warning "DBus PWM control not working - check daemon logs"
        print_status "Recent daemon logs:"
        journalctl -u com.system76.PowerDaemon.service --since "1 minute ago" | tail -5
    fi
}

test_combined() {
    print_status "Testing combined approach..."
    
    PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"
    
    echo "Initial PWM: $(cat "$PWM_FILE")"
    
    # Step 1: Use DBus to disable automatic control
    print_status "Step 1: Disabling automatic fan control via DBus..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    
    # Step 2: Use direct PWM control
    print_status "Step 2: Setting PWM directly..."
    echo "255" | sudo tee "$PWM_FILE" > /dev/null
    
    echo "PWM after combined approach: $(cat "$PWM_FILE")"
    
    # Step 3: Monitor
    print_status "Step 3: Monitoring for 10 seconds..."
    for i in {1..10}; do
        pwm_val=$(cat "$PWM_FILE")
        echo "   [$i] PWM: $pwm_val"
        sleep 1
    done
    
    if [ "$(cat "$PWM_FILE")" = "255" ]; then
        print_success "Combined approach works! PWM persisted at 255"
    else
        print_warning "Combined approach failed - PWM was overwritten"
    fi
}

run_app_sudo() {
    print_status "Running fan curve app with sudo (bypasses permission issues)..."
    print_warning "This will require your sudo password"
    echo ""
    
    sudo ./target/release/fan-curve-app --gui
}

run_app_dbus() {
    print_status "Running fan curve app using DBus method..."
    print_status "Make sure to disable automatic fan control first:"
    echo ""
    
    print_status "Disabling automatic fan control..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    
    print_status "Starting fan curve app..."
    ./target/release/fan-curve-app --gui
}

main() {
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    
    case "$1" in
        "diagnose")
            diagnose_issues
            ;;
        "test-direct")
            test_direct_pwm
            ;;
        "test-dbus")
            test_dbus_pwm
            ;;
        "test-combined")
            test_combined
            ;;
        "run-app-sudo")
            run_app_sudo
            ;;
        "run-app-dbus")
            run_app_dbus
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
