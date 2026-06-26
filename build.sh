#!/bin/bash
# build.sh - One-command build script for Glow for Facebook
# Usage: ./build.sh [deb|ipa|all|clean|check|help]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
PACKAGES_DIR="$SCRIPT_DIR/packages"
FB_IPA="$PARENT_DIR/glow/facebook.ipa"
OUTPUT_IPA="$PACKAGES_DIR/glow_v8.ipa"

# Get version from control file
VERSION=$(grep "^Version:" "$SCRIPT_DIR/control" | awk '{print $2}')
DEB_NAME="com.tommy.glowv3_${VERSION}_iphoneos-arm.deb"
DEB_FILE="$PACKAGES_DIR/$DEB_NAME"

# Functions
print_header() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_requirements() {
    print_header "Checking build environment"

    local all_ok=true

    # Check THEOS
    if [ -z "$THEOS" ]; then
        THEOS="/home/tommy/theos"
        export THEOS
    fi

    if [ -d "$THEOS" ]; then
        print_success "Theos: $THEOS"
    else
        print_error "Theos NOT found at $THEOS"
        echo "  Set THEOS env var or install Theos"
        all_ok=false
    fi

    # Check cyan
    if command -v cyan >/dev/null 2>&1; then
        print_success "cyan: $(which cyan)"
    else
        print_warning "cyan NOT found (needed for IPA injection)"
    fi

    # Check Facebook.ipa
    if [ -f "$FB_IPA" ]; then
        print_success "Facebook.ipa: $FB_IPA"
    else
        print_warning "Facebook.ipa NOT found at $FB_IPA"
        echo "  Place facebook.ipa in $PARENT_DIR/glow/"
    fi

    if [ "$all_ok" = true ]; then
        return 0
    else
        return 1
    fi
}

build_deb() {
    print_header "Building GlowV3 tweak v$VERSION"

    mkdir -p "$PACKAGES_DIR"

    # Clean previous build
    rm -rf "$SCRIPT_DIR/.theos/"

    # Build using Theos
    cd "$SCRIPT_DIR"
    if make package FINALPACKAGE=1; then
        # Move .deb to packages/ if it's not there
        if [ -f "$SCRIPT_DIR/packages/$DEB_NAME" ] && [ ! -f "$DEB_FILE" ]; then
            mv "$SCRIPT_DIR/packages/$DEB_NAME" "$DEB_FILE"
        fi

        if [ -f "$DEB_FILE" ]; then
            print_success ".deb built: $DEB_FILE"
            return 0
        else
            print_error ".deb not found after build"
            return 1
        fi
    else
        print_error "Build failed"
        return 1
    fi
}

build_ipa() {
    print_header "Injecting tweak into Facebook.ipa"

    # Check requirements
    if [ ! -f "$FB_IPA" ]; then
        print_error "Facebook.ipa not found at $FB_IPA"
        return 1
    fi

    if [ ! -f "$DEB_FILE" ]; then
        print_error "$DEB_FILE not found"
        echo "  Run 'build.sh deb' first"
        return 1
    fi

    if ! command -v cyan >/dev/null 2>&1; then
        print_error "cyan not found (install from https://github.com/aspect-build/cyan)"
        return 1
    fi

    # Inject
    cyan -i "$FB_IPA" -o "$OUTPUT_IPA" \
        -f "$DEB_FILE" --overwrite -s -d

    if [ -f "$OUTPUT_IPA" ]; then
        local size=$(ls -lh "$OUTPUT_IPA" | awk '{print $5}')
        print_success "IPA built: $OUTPUT_IPA ($size)"
        return 0
    else
        print_error "IPA build failed"
        return 1
    fi
}

clean_all() {
    print_header "Cleaning build artifacts"

    rm -rf "$SCRIPT_DIR/.theos/"
    rm -f "$PACKAGES_DIR"/*.deb

    print_success "Cleaned"
}

show_usage() {
    echo "Glow for Facebook - Build Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  deb       Build tweak (.deb only)"
    echo "  ipa       Build tweak + inject into Facebook.ipa"
    echo "  all       Build everything (deb + ipa) - DEFAULT"
    echo "  clean     Clean build artifacts"
    echo "  check     Check build environment"
    echo "  help      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0              # Build everything"
    echo "  $0 deb          # Just build .deb"
    echo "  $0 ipa          # Build + inject IPA"
    echo "  $0 clean        # Clean and rebuild"
}

# Main
case "${1:-all}" in
    deb)
        check_requirements && build_deb
        ;;
    ipa)
        check_requirements && build_deb && build_ipa
        ;;
    all)
        check_requirements && build_deb && build_ipa
        echo ""
        print_header "Build Complete!"
        echo ""
        echo "Output: $OUTPUT_IPA"
        echo "Size:   $(ls -lh "$OUTPUT_IPA" 2>/dev/null | awk '{print $5}')"
        echo ""
        echo "Install on device:"
        echo "  1. Copy $OUTPUT_IPA to device"
        echo "  2. Open with TrollStore"
        echo "  3. Launch Facebook"
        echo "  4. Check log: /var/mobile/Documents/glow.txt"
        ;;
    clean)
        clean_all
        ;;
    check)
        check_requirements
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac
