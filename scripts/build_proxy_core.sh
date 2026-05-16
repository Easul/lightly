#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$PROJECT_ROOT/rust/proxy-core"
JNILIBS_DIR="$PROJECT_ROOT/android/app/src/main/jniLibs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_cargo_ndk() {
    if ! command -v cargo-ndk &> /dev/null; then
        log_error "cargo-ndk is not installed. Install with: cargo install cargo-ndk"
        exit 1
    fi
}

install_targets() {
    log_info "Installing Rust targets..."
    rustup target add aarch64-linux-android armv7-linux-androideabi || {
        log_error "Failed to install Rust targets"
        exit 1
    }
}

build_target() {
    local target=$1
    local arch=$2
    
    log_info "Building proxy-core for $target..."
    cd "$RUST_DIR"
    cargo ndk -t $target -P 21 build --release
    
    if [ $? -ne 0 ]; then
        log_error "Build failed for $target"
        exit 1
    fi
    
    local src_file="$RUST_DIR/target/$arch/release/libproxy_core.so"
    local dest_dir="$JNILIBS_DIR/$target"
    local dest_file="$dest_dir/libproxy_core.so"
    
    mkdir -p "$dest_dir"
    cp "$src_file" "$dest_file"
    
    local file_size=$(ls -lh "$dest_file" | awk '{ print $5 }')
    log_info "Built for $target: libproxy_core.so ($file_size)"
}

clean_build() {
    log_info "Cleaning build artifacts..."
    cd "$RUST_DIR"
    cargo clean
    rm -f "$JNILIBS_DIR"/*/libproxy_core.so
    log_info "Clean complete"
}

show_help() {
    echo "Usage: $0 [OPTIONS] [TARGETS]"
    echo ""
    echo "OPTIONS:"
    echo "  -h, --help      Show this help message"
    echo "  -c, --clean     Clean build artifacts"
    echo "  -a, --all       Build for all targets"
    echo ""
    echo "TARGETS:"
    echo "  arm64           Build for arm64-v8a (64-bit)"
    echo "  arm32           Build for armeabi-v7a (32-bit)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 --all        Build for all targets"
    echo "  $0 arm64        Build only for arm64"
    echo "  $0 --clean      Clean build artifacts"
}

main() {
    local clean=false
    local build_all=false
    local targets=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                clean=true
                shift
                ;;
            -a|--all)
                build_all=true
                shift
                ;;
            arm64)
                targets+=("arm64-v8a")
                shift
                ;;
            arm32)
                targets+=("armeabi-v7a")
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [ "$clean" = true ]; then
        clean_build
    fi
    
    if [ "$build_all" = true ]; then
        targets=("arm64-v8a" "armeabi-v7a")
    fi
    
    if [ ${#targets[@]} -eq 0 ]; then
        targets=("arm64-v8a" "armeabi-v7a")
    fi
    
    check_cargo_ndk
    install_targets
    
    log_info "Starting proxy-core build..."
    log_info "Project root: $PROJECT_ROOT"
    
    for target in "${targets[@]}"; do
        case $target in
            arm64-v8a)
                build_target "arm64-v8a" "aarch64-linux-android"
                ;;
            armeabi-v7a)
                build_target "armeabi-v7a" "armv7-linux-androideabi"
                ;;
        esac
    done
    
    log_info "Build complete! Native libraries:"
    ls -lh "$JNILIBS_DIR"/*/libproxy_core.so 2>/dev/null || true
}

main "$@"
