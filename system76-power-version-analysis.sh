#!/bin/bash

# System76-Power Version Analysis and Fix
# This script helps investigate differences between 1.2.7 and 1.2.8

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

# Function to check current system76-power version
check_current_version() {
    print_status "=== Current System76-Power Version ==="
    local current_version=$(system76-power --version)
    echo "Current version: $current_version"
    
    if [[ "$current_version" == *"1.2.8"* ]]; then
        print_warning "Running version 1.2.8 - this may have PWM control issues"
    elif [[ "$current_version" == *"1.2.7"* ]]; then
        print_success "Running version 1.2.7 - this should work correctly"
    else
        print_warning "Unknown version: $current_version"
    fi
    
    echo ""
}

# Function to check available versions
check_available_versions() {
    print_status "=== Available System76-Power Versions ==="
    
    echo "Installed packages:"
    dpkg -l | grep system76-power | sed 's/^/  /'
    
    echo ""
    echo "Available versions in repositories:"
    apt list --upgradable 2>/dev/null | grep system76-power || echo "  No upgrades available"
    
    echo ""
}

# Function to check for version-specific configuration differences
check_config_differences() {
    print_status "=== Configuration Differences ==="
    
    # Check for configuration files
    local config_files=(
        "/etc/system76-power.conf"
        "/etc/systemd/system/com.system76.PowerDaemon.service"
        "/lib/systemd/system/com.system76.PowerDaemon.service"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            print_status "Found config file: $file"
            echo "Permissions: $(ls -l "$file")"
            echo "Size: $(wc -l < "$file") lines"
        fi
    done
    
    echo ""
}

# Function to check daemon behavior
check_daemon_behavior() {
    print_status "=== Daemon Behavior Analysis ==="
    
    # Check if daemon is running
    if systemctl is-active --quiet com.system76.PowerDaemon.service; then
        print_success "Power daemon is running"
        
        # Check daemon logs for recent activity
        print_status "Recent daemon activity:"
        journalctl -u com.system76.PowerDaemon.service --since "10 minutes ago" | tail -10 || echo "  No recent activity"
        
        # Check DBus interface
        print_status "DBus interface status:"
        busctl --system list | grep system76.PowerDaemon || echo "  DBus interface not found"
        
    else
        print_warning "Power daemon is not running"
    fi
    
    echo ""
}

# Function to test PWM control with current version
test_pwm_control() {
    print_status "=== PWM Control Test ==="
    
    local pwm_file="/sys/class/hwmon/hwmon3/pwm1"
    local initial_pwm=$(cat "$pwm_file")
    
    echo "Initial PWM: $initial_pwm"
    
    # Test DBus control
    print_status "Testing DBus PWM control..."
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetDuty y 200
    
    sleep 2
    local pwm_after=$(cat "$pwm_file")
    echo "PWM after DBus call: $pwm_after"
    
    if [ "$pwm_after" = "200" ]; then
        print_success "✓ PWM control working correctly"
    else
        print_warning "✗ PWM control not working (expected 200, got $pwm_after)"
        
        # Check daemon logs for errors
        print_status "Checking daemon logs for errors..."
        journalctl -u com.system76.PowerDaemon.service --since "2 minutes ago" | grep -E "(error|Error|ERROR|fail|Fail|FAIL)" || echo "  No errors found in logs"
    fi
    
    echo ""
}

# Function to provide downgrade instructions
provide_downgrade_instructions() {
    print_status "=== Downgrade Instructions ==="
    
    echo "To downgrade to system76-power 1.2.7:"
    echo ""
    echo "1. Stop the current daemon:"
    echo "   sudo systemctl stop com.system76.PowerDaemon.service"
    echo ""
    echo "2. Download version 1.2.7:"
    echo "   wget https://github.com/pop-os/system76-power/releases/download/1.2.7/system76-power_1.2.7_amd64.deb"
    echo ""
    echo "3. Install version 1.2.7:"
    echo "   sudo dpkg -i system76-power_1.2.7_amd64.deb"
    echo ""
    echo "4. Hold the package to prevent upgrades:"
    echo "   sudo apt-mark hold system76-power"
    echo ""
    echo "5. Start the daemon:"
    echo "   sudo systemctl start com.system76.PowerDaemon.service"
    echo ""
    echo "6. Test your fan curve app"
    echo ""
}

# Function to provide fork update instructions
provide_fork_update_instructions() {
    print_status "=== Fork Update Instructions ==="
    
    echo "To update your fork with 1.2.8 changes:"
    echo ""
    echo "1. Check what changed between 1.2.7 and 1.2.8:"
    echo "   git log --oneline 1.2.7..1.2.8"
    echo ""
    echo "2. Look for fan/PWM related changes:"
    echo "   git log --oneline 1.2.7..1.2.8 --grep='fan\\|pwm\\|thermal'"
    echo ""
    echo "3. Check specific files that might affect PWM:"
    echo "   git diff 1.2.7..1.2.8 -- src/fan.rs src/thermal.rs"
    echo ""
    echo "4. Merge relevant changes into your fork"
    echo ""
}

# Function to create a version comparison script
create_version_comparison() {
    print_status "Creating version comparison script..."
    
    cat > compare-versions.sh << 'EOF'
#!/bin/bash

# System76-Power Version Comparison Script
# This script helps compare behavior between versions

echo "=== System76-Power Version Comparison ==="
echo ""

# Function to test PWM control
test_pwm() {
    local version=$1
    echo "Testing PWM control with version $version..."
    
    # Test DBus control
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetAuto
    busctl --system call com.system76.PowerDaemon /com/system76/PowerDaemon/Fan com.system76.PowerDaemon.Fan SetDuty y 200
    
    sleep 2
    local pwm=$(cat /sys/class/hwmon/hwmon3/pwm1)
    echo "PWM after SetDuty(200): $pwm"
    
    if [ "$pwm" = "200" ]; then
        echo "✓ PWM control working with $version"
    else
        echo "✗ PWM control NOT working with $version"
    fi
    echo ""
}

# Test current version
current_version=$(system76-power --version)
echo "Current version: $current_version"
test_pwm "$current_version"

echo "To test with version 1.2.7:"
echo "1. Downgrade to 1.2.7"
echo "2. Run this script again"
echo "3. Compare results"
EOF
    
    chmod +x compare-versions.sh
    print_success "Created compare-versions.sh"
}

# Main function
main() {
    case "${1:-analyze}" in
        "analyze")
            check_current_version
            check_available_versions
            check_config_differences
            check_daemon_behavior
            test_pwm_control
            ;;
        "downgrade")
            provide_downgrade_instructions
            ;;
        "update-fork")
            provide_fork_update_instructions
            ;;
        "compare")
            create_version_comparison
            ;;
        "test")
            test_pwm_control
            ;;
        "help"|"-h"|"--help")
            echo "System76-Power Version Analysis and Fix"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  analyze      - Full analysis of current version (default)"
            echo "  downgrade    - Show downgrade instructions"
            echo "  update-fork  - Show fork update instructions"
            echo "  compare      - Create version comparison script"
            echo "  test         - Test PWM control"
            echo "  help         - Show this help"
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
