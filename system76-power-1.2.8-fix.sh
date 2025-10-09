#!/bin/bash

# System76-Power 1.2.8 PWM Fix
# This script addresses the PWM control issues introduced in version 1.2.8

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

# Function to check if we can downgrade to 1.2.7
check_downgrade_possibility() {
    print_status "=== Checking Downgrade Possibility ==="
    
    # Check if we can find version 1.2.7
    echo "Current version: $(system76-power --version)"
    
    # Check if version 1.2.7 is available
    print_status "Checking for version 1.2.7 availability..."
    
    # Try to find 1.2.7 in repositories
    if apt-cache policy system76-power | grep -q "1.2.7"; then
        print_success "Version 1.2.7 is available in repositories"
        echo "Available versions:"
        apt-cache policy system76-power | grep -E "1\.2\.[67]" | sed 's/^/  /'
    else
        print_warning "Version 1.2.7 not available in repositories"
        echo "You may need to download it manually from GitHub releases"
    fi
    
    echo ""
}

# Function to create a PWM bypass solution
create_pwm_bypass() {
    print_status "=== Creating PWM Bypass Solution ==="
    
    # Create a script that bypasses system76-power and writes directly to PWM
    cat > pwm-bypass.sh << 'EOF'
#!/bin/bash

# PWM Bypass Script
# This script bypasses system76-power and controls PWM directly

set -e

PWM_FILE="/sys/class/hwmon/hwmon3/pwm1"
ENABLE_FILE="/sys/class/hwmon/hwmon3/pwm1_enable"

# Function to enable manual PWM control
enable_manual_control() {
    if [ -f "$ENABLE_FILE" ]; then
        echo "1" | sudo tee "$ENABLE_FILE" > /dev/null
        echo "Manual PWM control enabled"
    else
        echo "Warning: Enable file not found: $ENABLE_FILE"
    fi
}

# Function to set PWM duty
set_pwm_duty() {
    local duty=$1
    
    if [ -z "$duty" ] || [ "$duty" -lt 0 ] || [ "$duty" -gt 255 ]; then
        echo "Error: Invalid duty value: $duty (must be 0-255)"
        exit 1
    fi
    
    echo "$duty" | sudo tee "$PWM_FILE" > /dev/null
    echo "PWM set to $duty"
}

# Function to disable system76-power fan control
disable_system76_fan_control() {
    echo "Disabling system76-power fan control..."
    
    # Stop the daemon temporarily
    sudo systemctl stop com.system76.PowerDaemon.service
    
    # Enable manual PWM control
    enable_manual_control
    
    echo "System76-power fan control disabled"
}

# Function to re-enable system76-power fan control
enable_system76_fan_control() {
    echo "Re-enabling system76-power fan control..."
    
    # Re-enable automatic control
    if [ -f "$ENABLE_FILE" ]; then
        echo "2" | sudo tee "$ENABLE_FILE" > /dev/null
    fi
    
    # Restart the daemon
    sudo systemctl start com.system76.PowerDaemon.service
    
    echo "System76-power fan control re-enabled"
}

# Main function
main() {
    case "${1:-help}" in
        "disable")
            disable_system76_fan_control
            ;;
        "enable")
            enable_system76_fan_control
            ;;
        "set")
            set_pwm_duty "$2"
            ;;
        "manual")
            enable_manual_control
            ;;
        "help"|"-h"|"--help")
            echo "PWM Bypass Script"
            echo ""
            echo "Usage: $0 <command> [args]"
            echo ""
            echo "Commands:"
            echo "  disable     - Disable system76-power fan control"
            echo "  enable      - Re-enable system76-power fan control"
            echo "  set <duty>   - Set PWM duty (0-255)"
            echo "  manual      - Enable manual PWM control"
            echo "  help        - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 disable        # Disable system76-power control"
            echo "  $0 set 200         # Set PWM to 200 (78%)"
            echo "  $0 enable          # Re-enable system76-power control"
            echo ""
            ;;
        *)
            echo "Error: Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
EOF
    
    chmod +x pwm-bypass.sh
    print_success "Created pwm-bypass.sh"
}

# Function to create a fan curve app wrapper
create_fan_curve_wrapper() {
    print_status "=== Creating Fan Curve App Wrapper ==="
    
    cat > fan-curve-wrapper.sh << 'EOF'
#!/bin/bash

# Fan Curve App Wrapper
# This script runs your fan curve app with proper PWM control

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

# Function to setup PWM control
setup_pwm_control() {
    print_status "Setting up PWM control..."
    
    # Disable system76-power fan control
    ./pwm-bypass.sh disable
    
    # Wait a moment for changes to take effect
    sleep 2
    
    print_success "PWM control setup complete"
}

# Function to cleanup PWM control
cleanup_pwm_control() {
    print_status "Cleaning up PWM control..."
    
    # Re-enable system76-power fan control
    ./pwm-bypass.sh enable
    
    print_success "PWM control cleanup complete"
}

# Function to run fan curve app
run_fan_curve_app() {
    print_status "Starting fan curve app..."
    
    # Setup PWM control
    setup_pwm_control
    
    # Run the fan curve app
    print_status "Running: ./target/release/fan-curve-app --gui"
    ./target/release/fan-curve-app --gui
    
    # Cleanup when app exits
    cleanup_pwm_control
}

# Function to run with sudo
run_with_sudo() {
    print_status "Running fan curve app with sudo..."
    print_warning "This will require your sudo password"
    
    sudo ./target/release/fan-curve-app --gui
}

# Main function
main() {
    case "${1:-normal}" in
        "normal")
            run_fan_curve_app
            ;;
        "sudo")
            run_with_sudo
            ;;
        "setup")
            setup_pwm_control
            ;;
        "cleanup")
            cleanup_pwm_control
            ;;
        "help"|"-h"|"--help")
            echo "Fan Curve App Wrapper"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  normal      - Run with PWM bypass (default)"
            echo "  sudo        - Run with sudo (bypasses permissions)"
            echo "  setup       - Setup PWM control only"
            echo "  cleanup     - Cleanup PWM control only"
            echo "  help        - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 normal   # Run with PWM bypass"
            echo "  $0 sudo     # Run with sudo"
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
EOF
    
    chmod +x fan-curve-wrapper.sh
    print_success "Created fan-curve-wrapper.sh"
}

# Function to provide comprehensive solution
provide_comprehensive_solution() {
    print_status "=== Comprehensive Solution ==="
    
    echo "Based on the analysis, here are your options:"
    echo ""
    
    echo "1. IMMEDIATE SOLUTION - Use PWM Bypass:"
    echo "   ./fan-curve-wrapper.sh normal"
    echo "   This disables system76-power fan control and runs your app"
    echo ""
    
    echo "2. SIMPLE SOLUTION - Run with sudo:"
    echo "   ./fan-curve-wrapper.sh sudo"
    echo "   This bypasses permission issues"
    echo ""
    
    echo "3. LONG-TERM SOLUTION - Downgrade to 1.2.7:"
    echo "   ./system76-power-version-analysis.sh downgrade"
    echo "   This shows instructions to downgrade to the working version"
    echo ""
    
    echo "4. DEVELOPER SOLUTION - Fix your fork:"
    echo "   - Investigate what changed between 1.2.7 and 1.2.8"
    echo "   - Update your fork to handle the new PWM control method"
    echo "   - Test with the official 1.2.8 changes"
    echo ""
    
    echo "5. HYBRID SOLUTION - Use both methods:"
    echo "   - Use PWM bypass for immediate functionality"
    echo "   - Work on fixing your fork for long-term solution"
    echo ""
}

# Main function
main() {
    case "${1:-solution}" in
        "solution")
            provide_comprehensive_solution
            ;;
        "bypass")
            create_pwm_bypass
            ;;
        "wrapper")
            create_fan_curve_wrapper
            ;;
        "all")
            create_pwm_bypass
            create_fan_curve_wrapper
            provide_comprehensive_solution
            ;;
        "help"|"-h"|"--help")
            echo "System76-Power 1.2.8 PWM Fix"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  solution    - Show comprehensive solution (default)"
            echo "  bypass      - Create PWM bypass script"
            echo "  wrapper     - Create fan curve app wrapper"
            echo "  all         - Create all scripts and show solution"
            echo "  help        - Show this help"
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
