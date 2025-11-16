#!/bin/bash
# Local test script for ESPHome configuration validation (Linux/macOS)
# Run this before committing changes or creating releases

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}ESPHome Local Test Suite${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

test_step() {
    local name="$1"
    local command="$2"
    
    echo -e "${YELLOW}[$name]${NC} ${GRAY}Running...${NC}"
    
    if eval "$command"; then
        echo -e "  ${GREEN}✓ PASSED${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "  ${RED}✗ FAILED${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Test 1: Check Python
test_step "Python Installation" "python3 --version > /dev/null 2>&1 && echo '    Found: '$(python3 --version)"

# Test 2: Check ESPHome
if ! command -v esphome &> /dev/null; then
    echo -e "    ${YELLOW}ESPHome not found, installing...${NC}"
    pip3 install esphome
fi
test_step "ESPHome Installation" "esphome version > /dev/null 2>&1 && echo '    Found: '$(esphome version 2>&1 | head -n1)"

# Test 3: Check yamllint
if ! command -v yamllint &> /dev/null; then
    echo -e "    ${YELLOW}yamllint not found, installing...${NC}"
    pip3 install yamllint
fi
test_step "yamllint Installation" "yamllint --version > /dev/null 2>&1 && echo '    Found: '$(yamllint --version)"

# Test 4: Create test secrets
test_step "Test Secrets Setup" "
    cd '$PROJECT_ROOT'
    if [ ! -f secrets.yaml ]; then
        cat > secrets.yaml << 'EOF'
# Test secrets file (auto-generated)
wifi_ssid: \"TestNetwork\"
wifi_password: \"TestPassword123\"
EOF
        echo '    Created test secrets.yaml'
    else
        echo '    Using existing secrets.yaml'
    fi
"

# Test 5: YAML linting
test_step "YAML Linting" "
    cd '$PROJECT_ROOT'
    yamllint -d relaxed waterlevel-sensor.yaml
    echo '    No YAML syntax errors found'
"

# Test 6: ESPHome config validation
test_step "ESPHome Config Validation" "
    cd '$PROJECT_ROOT'
    echo '    Validating configuration...'
    esphome config waterlevel-sensor.yaml > /dev/null
    echo '    Configuration is valid'
"

# Test 7: ESPHome compilation
test_step "ESPHome Compilation Test" "
    cd '$PROJECT_ROOT'
    echo '    Compiling firmware (this may take a few minutes)...'
    esphome compile waterlevel-sensor.yaml > /dev/null
    echo '    Compilation successful'
"

# Test 8: README check
test_step "README Validation" "
    cd '$PROJECT_ROOT'
    if [ -f README.md ] && [ \$(wc -c < README.md) -gt 100 ]; then
        echo '    README.md looks good'
        exit 0
    else
        echo '    README.md missing or incomplete'
        exit 1
    fi
"

# Test 9: LICENSE check
if [ -f "$PROJECT_ROOT/LICENSE" ]; then
    echo -e "${YELLOW}[License File Check]${NC} ${GRAY}Running...${NC}"
    echo -e "  ${GREEN}✓ PASSED${NC}"
    echo "    LICENSE file present"
    ((TESTS_PASSED++))
else
    echo -e "${YELLOW}[License File Check]${NC} ${GRAY}Running...${NC}"
    echo -e "  ${YELLOW}✓ PASSED (warning)${NC}"
    echo "    WARNING: LICENSE file not found"
    ((TESTS_PASSED++))
fi

# Test 10: Git status
test_step "Git Status Check" "
    cd '$PROJECT_ROOT'
    if [ -n \"\$(git status --porcelain 2>/dev/null)\" ]; then
        echo '    WARNING: Uncommitted changes detected:'
        git status --short
    else
        echo '    Working directory clean'
    fi
"

# Summary
echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}Test Summary${NC}"
echo -e "${CYAN}=====================================${NC}"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}Failed: $TESTS_FAILED${NC}"
else
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
fi
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed! Ready to commit/release.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed. Please fix issues before committing.${NC}"
    exit 1
fi
