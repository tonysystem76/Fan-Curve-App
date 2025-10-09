#!/bin/bash

# Simple PWM Overwrite Detection (No sudo required)
# This script monitors PWM changes and identifies the culprit

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

# PWM file to monitor
PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"

# Function to get current PWM value
get_pwm() {
    cat "$PWM_FILE" 2>/dev/null || echo "ERROR"
}

# Function to monitor PWM changes without sudo
monitor_pwm_changes() {
    print_status "Starting PWM monitoring (no sudo required)..."
    print_status "Monitoring: $PWM_FILE"
    print_status "Press Ctrl+C to stop"
    echo ""
    
    local last_value=$(get_pwm)
    local change_count=0
    local start_time=$(date +%s)
    
    echo "Time,Old_Value,New_Value,Change_Count,Elapsed_Seconds"
    
    while true; do
        local current_value=$(get_pwm)
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ "$current_value" != "$last_value" ]; then
            change_count=$((change_count + 1))
            local timestamp=$(date '+%H:%M:%S.%3N')
            echo "$timestamp,$last_value,$current_value,$change_count,$elapsed"
            
            print_warning "PWM changed from $last_value to $current_value (change #$change_count)"
            
            # Check what processes might be involved
            print_status "Checking for processes that might be controlling PWM..."
            
            # Check system76-power daemon logs
            local recent_logs=$(journalctl -u com.system76.PowerDaemon.service --since "30 seconds ago" 2>/dev/null | grep -E "(fan|pwm|PWM)" | tail -3)
            if [ -n "$recent_logs" ]; then
                print_status "Recent system76-power daemon activity:"
                echo "$recent_logs" | sed 's/^/  /'
            fi
            
            # Check for thermal events
            local thermal_logs=$(journalctl --since "30 seconds ago" 2>/dev/null | grep -i thermal | tail -2)
            if [ -n "$thermal_logs" ]; then
                print_status "Recent thermal events:"
                echo "$thermal_logs" | sed 's/^/  /'
            fi
            
            echo ""
            last_value="$current_value"
        fi
        
        sleep 0.2
    done
}

# Function to test with DBus calls
test_dbus_interaction() {
    print_status "Testing DBus interaction with PWM monitoring..."
    
    local initial_pwm=$(get_pwm)
    print_status "Initial PWM: $initial_pwm"
    
    # Disable automatic control
    print_status "Disabling automatic fan control..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    
    sleep 1
    local pwm_after_auto=$(get_pwm)
    print_status "PWM after SetAuto: $pwm_after_auto"
    
    # Set to 100%
    print_status "Setting fan to 100% (255)..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetDuty y 255
    
    sleep 1
    local pwm_after_duty=$(get_pwm)
    print_status "PWM after SetDuty(255): $pwm_after_duty"
    
    # Monitor for changes
    print_status "Monitoring for 10 seconds..."
    for i in {1..10}; do
        local current_pwm=$(get_pwm)
        echo "  [$i] PWM: $current_pwm"
        if [ "$current_pwm" != "$pwm_after_duty" ]; then
            print_warning "PWM changed from $pwm_after_duty to $current_pwm at second $i"
        fi
        sleep 1
    done
    
    local final_pwm=$(get_pwm)
    print_status "Final PWM: $final_pwm"
    
    if [ "$final_pwm" = "255" ]; then
        print_success "PWM remained at 255 - no overwriting detected!"
    else
        print_warning "PWM was overwritten - something else is controlling it"
    fi
}

# Function to check for thermal throttling
check_thermal_throttling() {
    print_status "Checking for thermal throttling..."
    
    # Check thermal zones
    if [ -d "/sys/class/thermal" ]; then
        print_status "Thermal zones:"
        for zone in /sys/class/thermal/thermal_zone*; do
            if [ -f "$zone/type" ] && [ -f "$zone/temp" ]; then
                local zone_type=$(cat "$zone/type")
                local zone_temp=$(cat "$zone/temp")
                local temp_c=$((zone_temp / 1000))
                echo "  $zone_type: ${temp_c}°C"
            fi
        done
    fi
    
    # Check for thermal events in logs
    print_status "Recent thermal events:"
    journalctl --since "5 minutes ago" 2>/dev/null | grep -i thermal | tail -5 || echo "  No recent thermal events"
}

# Main function
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_pwm_changes
            ;;
        "test")
            test_dbus_interaction
            ;;
        "thermal")
            check_thermal_throttling
            ;;
        "help"|"-h"|"--help")
            echo "PWM Overwrite Detection (No Sudo)"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  monitor   - Monitor PWM changes (default)"
            echo "  test      - Test DBus interaction with PWM monitoring"
            echo "  thermal   - Check thermal throttling"
            echo "  help      - Show this help"
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
