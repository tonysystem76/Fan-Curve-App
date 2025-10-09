#!/bin/bash

# PWM Overwrite Detective
# This script monitors PWM files and identifies what process is overwriting them

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
ENABLE_FILE="/sys/class/hwmon/hwmon3/pwm1_enable"

# Function to get current PWM value
get_pwm() {
    cat "$PWM_FILE" 2>/dev/null || echo "ERROR"
}

# Function to get process info for a PID
get_process_info() {
    local pid=$1
    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        ps -p "$pid" -o pid,ppid,cmd --no-headers 2>/dev/null || echo "Process not found"
    else
        echo "Unknown process"
    fi
}

# Function to monitor PWM changes
monitor_pwm_changes() {
    print_status "Starting PWM monitoring..."
    print_status "Monitoring: $PWM_FILE"
    print_status "Press Ctrl+C to stop"
    echo ""
    
    local last_value=$(get_pwm)
    local change_count=0
    
    echo "Time,Old_Value,New_Value,Change_Count"
    
    while true; do
        local current_value=$(get_pwm)
        
        if [ "$current_value" != "$last_value" ]; then
            change_count=$((change_count + 1))
            local timestamp=$(date '+%H:%M:%S.%3N')
            echo "$timestamp,$last_value,$current_value,$change_count"
            
            # Try to identify what changed it
            print_warning "PWM changed from $last_value to $current_value"
            
            # Check if it's a file write
            if command -v lsof >/dev/null 2>&1; then
                local pids=$(lsof "$PWM_FILE" 2>/dev/null | awk 'NR>1 {print $2}' | sort -u)
                if [ -n "$pids" ]; then
                    print_status "Processes with PWM file open:"
                    for pid in $pids; do
                        echo "  PID $pid: $(get_process_info "$pid")"
                    done
                fi
            fi
            
            # Check recent system calls
            if command -v strace >/dev/null 2>&1; then
                print_status "Recent system calls to PWM file:"
                # This is a simplified check - in practice you'd need to trace specific processes
                echo "  (Use 'sudo strace -p <PID> -e write' to trace a specific process)"
            fi
            
            echo ""
            last_value="$current_value"
        fi
        
        sleep 0.1
    done
}

# Function to test PWM overwriting
test_pwm_overwrite() {
    print_status "Testing PWM overwrite behavior..."
    
    # Set PWM to a known value
    local test_value=200
    print_status "Setting PWM to $test_value..."
    echo "$test_value" | sudo tee "$PWM_FILE" > /dev/null
    
    # Enable manual control
    if [ -f "$ENABLE_FILE" ]; then
        echo "1" | sudo tee "$ENABLE_FILE" > /dev/null
        print_status "Enabled manual PWM control"
    fi
    
    local initial_value=$(get_pwm)
    print_status "Initial PWM value: $initial_value"
    
    # Monitor for changes
    print_status "Monitoring for 10 seconds..."
    local start_time=$(date +%s)
    local last_value="$initial_value"
    local changes=0
    
    while [ $(($(date +%s) - start_time)) -lt 10 ]; do
        local current_value=$(get_pwm)
        if [ "$current_value" != "$last_value" ]; then
            changes=$((changes + 1))
            local timestamp=$(date '+%H:%M:%S')
            print_warning "[$timestamp] PWM changed from $last_value to $current_value"
            last_value="$current_value"
        fi
        sleep 0.5
    done
    
    local final_value=$(get_pwm)
    print_status "Final PWM value: $final_value"
    print_status "Total changes detected: $changes"
    
    if [ "$changes" -gt 0 ]; then
        print_warning "PWM is being overwritten! Something is actively changing it."
    else
        print_success "PWM remained stable - no overwriting detected."
    fi
}

# Function to identify potential overwriters
identify_potential_overwriters() {
    print_status "Identifying potential PWM overwriters..."
    echo ""
    
    # Check running processes that might control fans
    print_status "1. Fan-related processes:"
    ps aux | grep -E "(fan|pwm|thermal|system76)" | grep -v grep || echo "  No obvious fan processes found"
    echo ""
    
    # Check systemd services
    print_status "2. Systemd services that might control fans:"
    systemctl list-units --type=service | grep -E "(fan|pwm|thermal|system76|power)" || echo "  No obvious fan services found"
    echo ""
    
    # Check for thermal management
    print_status "3. Thermal management processes:"
    ps aux | grep -E "(thermald|thermal)" | grep -v grep || echo "  No thermal management processes found"
    echo ""
    
    # Check for hardware monitoring
    print_status "4. Hardware monitoring processes:"
    ps aux | grep -E "(lm-sensors|sensors|hwmon)" | grep -v grep || echo "  No hardware monitoring processes found"
    echo ""
    
    # Check for kernel modules
    print_status "5. Relevant kernel modules:"
    lsmod | grep -E "(thermal|fan|pwm)" || echo "  No obvious fan-related kernel modules"
    echo ""
}

# Function to create a PWM protection script
create_pwm_protection() {
    print_status "Creating PWM protection script..."
    
    cat > pwm_protector.sh << 'EOF'
#!/bin/bash

# PWM Protector - Prevents other processes from overwriting PWM values
# Run this script to continuously restore your desired PWM value

PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"
ENABLE_FILE="/sys/class/hwmon/hwmon3/pwm1_enable"
DESIRED_VALUE=${1:-255}  # Default to 255 (100%) if no argument provided

echo "PWM Protector started - maintaining PWM at $DESIRED_VALUE"
echo "Press Ctrl+C to stop"

# Enable manual control
if [ -f "$ENABLE_FILE" ]; then
    echo "1" | sudo tee "$ENABLE_FILE" > /dev/null
fi

while true; do
    current_value=$(cat "$PWM_FILE")
    if [ "$current_value" != "$DESIRED_VALUE" ]; then
        echo "$DESIRED_VALUE" | sudo tee "$PWM_FILE" > /dev/null
        echo "$(date '+%H:%M:%S'): Restored PWM from $current_value to $DESIRED_VALUE"
    fi
    sleep 0.5
done
EOF
    
    chmod +x pwm_protector.sh
    print_success "Created pwm_protector.sh - run with: ./pwm_protector.sh [desired_value]"
}

# Main function
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_pwm_changes
            ;;
        "test")
            test_pwm_overwrite
            ;;
        "identify")
            identify_potential_overwriters
            ;;
        "protect")
            create_pwm_protection
            ;;
        "help"|"-h"|"--help")
            echo "PWM Overwrite Detective"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  monitor   - Continuously monitor PWM changes (default)"
            echo "  test      - Test PWM overwrite behavior"
            echo "  identify  - Identify potential overwriters"
            echo "  protect   - Create PWM protection script"
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
