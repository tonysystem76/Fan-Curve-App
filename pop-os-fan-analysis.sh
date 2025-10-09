#!/bin/bash

# Pop OS Version-Specific Fan Control Solution
# This script addresses differences between Pop OS 22.04 and 24.04

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

# Get system information
get_system_info() {
    print_status "=== System Information ==="
    echo "OS: $(lsb_release -d | cut -f2)"
    echo "Kernel: $(uname -r)"
    echo "System76 Power: $(system76-power --version)"
    echo "Architecture: $(uname -m)"
    echo ""
}

# Check for version-specific issues
check_version_issues() {
    print_status "=== Checking Version-Specific Issues ==="
    
    local os_version=$(lsb_release -r | cut -f2)
    echo "OS Version: $os_version"
    
    if [[ "$os_version" == "22.04" ]]; then
        print_warning "Running on Pop OS 22.04 - known PWM control issues"
        echo "  - PWM files may not be writable by userspace"
        echo "  - Thermal management may interfere with PWM control"
        echo "  - System76-power fork may not write to PWM files correctly"
    elif [[ "$os_version" == "24.04" ]]; then
        print_success "Running on Pop OS 24.04 - PWM control should work"
    else
        print_warning "Unknown OS version: $os_version"
    fi
    
    echo ""
}

# Check PWM file accessibility
check_pwm_access() {
    print_status "=== PWM File Accessibility ==="
    
    local pwm_file="/sys/class/hwmon/hwmon3/pwm1"
    local enable_file="/sys/class/hwmon/hwmon3/pwm1_enable"
    
    if [ -f "$pwm_file" ]; then
        echo "PWM file: $pwm_file"
        echo "Permissions: $(ls -l "$pwm_file")"
        echo "Current value: $(cat "$pwm_file")"
        
        if [ -w "$pwm_file" ]; then
            print_success "PWM file is writable by current user"
        else
            print_warning "PWM file is NOT writable by current user"
        fi
        
        if [ -f "$enable_file" ]; then
            echo "Enable file: $enable_file"
            echo "Enable permissions: $(ls -l "$enable_file")"
            echo "Enable value: $(cat "$enable_file")"
        else
            print_warning "Enable file not found: $enable_file"
        fi
    else
        print_error "PWM file not found: $pwm_file"
    fi
    
    echo ""
}

# Check thermal management
check_thermal_management() {
    print_status "=== Thermal Management ==="
    
    # Check for thermal daemon
    local thermal_processes=$(ps aux | grep -E "(thermald|thermal)" | grep -v grep)
    if [ -n "$thermal_processes" ]; then
        print_warning "Thermal management processes found:"
        echo "$thermal_processes" | sed 's/^/  /'
    else
        print_status "No thermal management processes found"
    fi
    
    # Check cooling devices
    local fan_cooling_devices=$(for i in /sys/class/thermal/cooling_device*; do echo "$(basename $i): $(cat $i/type)"; done | grep -i fan)
    if [ -n "$fan_cooling_devices" ]; then
        print_warning "Fan cooling devices found:"
        echo "$fan_cooling_devices" | sed 's/^/  /'
    else
        print_status "No fan cooling devices found"
    fi
    
    echo ""
}

# Test PWM control methods
test_pwm_methods() {
    print_status "=== Testing PWM Control Methods ==="
    
    local pwm_file="/sys/class/hwmon/hwmon3/pwm1"
    local initial_pwm=$(cat "$pwm_file")
    
    echo "Initial PWM: $initial_pwm"
    
    # Test 1: Direct file write (if writable)
    print_status "Test 1: Direct PWM file write"
    if [ -w "$pwm_file" ]; then
        echo "200" > "$pwm_file"
        sleep 1
        local pwm_after_direct=$(cat "$pwm_file")
        echo "PWM after direct write: $pwm_after_direct"
        
        if [ "$pwm_after_direct" = "200" ]; then
            print_success "✓ Direct PWM write works"
        else
            print_warning "✗ Direct PWM write failed (expected 200, got $pwm_after_direct)"
        fi
    else
        print_warning "✗ Direct PWM write not possible (file not writable)"
    fi
    
    # Test 2: DBus method
    print_status "Test 2: DBus PWM control"
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetDuty y 200
    
    sleep 1
    local pwm_after_dbus=$(cat "$pwm_file")
    echo "PWM after DBus call: $pwm_after_dbus"
    
    if [ "$pwm_after_dbus" = "200" ]; then
        print_success "✓ DBus PWM control works"
    else
        print_warning "✗ DBus PWM control failed (expected 200, got $pwm_after_dbus)"
    fi
    
    # Restore original value
    echo "$initial_pwm" > "$pwm_file" 2>/dev/null || true
    
    echo ""
}

# Provide solutions based on findings
provide_solutions() {
    print_status "=== Recommended Solutions ==="
    
    local os_version=$(lsb_release -r | cut -f2)
    
    if [[ "$os_version" == "22.04" ]]; then
        echo "For Pop OS 22.04:"
        echo ""
        echo "1. IMMEDIATE SOLUTION - Run fan curve app with sudo:"
        echo "   sudo ./target/release/fan-curve-app --gui"
        echo ""
        echo "2. LONG-TERM SOLUTION - Fix PWM permissions:"
        echo "   sudo chmod 666 /sys/class/hwmon/hwmon3/pwm*"
        echo "   sudo chmod 666 /sys/class/hwmon/hwmon3/pwm*_enable"
        echo ""
        echo "3. ALTERNATIVE - Use DBus method (if your fork works):"
        echo "   Modify your fan curve app to use DBus calls instead of direct file writes"
        echo ""
        echo "4. UPGRADE SOLUTION - Consider upgrading to Pop OS 24.04:"
        echo "   PWM control works better on newer versions"
        echo ""
    else
        echo "For Pop OS 24.04:"
        echo ""
        echo "1. Your fan curve app should work directly"
        echo "2. If not, check PWM file permissions"
        echo "3. Ensure no thermal management is interfering"
        echo ""
    fi
    
    echo "5. DEBUGGING - Check your system76-power fork:"
    echo "   - Verify it's actually writing to PWM files"
    echo "   - Check daemon logs for errors"
    echo "   - Test with different PWM values"
    echo ""
}

# Main function
main() {
    case "${1:-analyze}" in
        "analyze")
            get_system_info
            check_version_issues
            check_pwm_access
            check_thermal_management
            test_pwm_methods
            provide_solutions
            ;;
        "test")
            test_pwm_methods
            ;;
        "solutions")
            provide_solutions
            ;;
        "help"|"-h"|"--help")
            echo "Pop OS Version-Specific Fan Control Solution"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  analyze    - Full analysis of PWM control issues (default)"
            echo "  test       - Test PWM control methods"
            echo "  solutions  - Show recommended solutions"
            echo "  help       - Show this help"
            echo ""
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
