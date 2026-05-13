#!/usr/bin/env bash
# =============================================================================
#  install-vscode-ubuntu.sh — Install VSCode on Ubuntu without admin
#  Uses VSCode's official portable mode (no apt, no sudo)
#  Run with: bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/install-vscode-ubuntu.sh)
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

step() { echo -e "\n${BLUE}${BOLD}[→]${NC} $*"; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
info() { echo -e "${CYAN}    $*${NC}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   VSCode Installer  •  Ubuntu            ║"
echo "  ║   (portable mode, no admin required)     ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── 0. Verify Linux ───────────────────────────────────────────────────────────
[[ "$(uname)" == "Linux" ]] || err "This script is for Linux/Ubuntu only."
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    ok "Detected: ${PRETTY_NAME:-Linux} • $(uname -m)"
else
    ok "Linux • $(uname -m)"
fi

# ── Local directories ─────────────────────────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
VSCODE_DIR="$HOME/.local/vscode"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# Persist PATH in shell rc
SHELL_RC="$HOME/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && SHELL_RC="$HOME/.zshrc"
grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$SHELL_RC" 2>/dev/null || \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"

# ── 1. Check if already installed ────────────────────────────────────────────
step "Checking for existing VSCode installation..."

# Check if 'code' already works in the terminal
if command -v code &>/dev/null; then
    ok "'code' is already available in the terminal: $(command -v code)"
    info "Run 'code .' to open a folder, or 'code --version' to confirm."
    echo ""
    exit 0
fi

# Check if the portable install exists but isn't linked
if [[ -d "$VSCODE_DIR" ]] && [[ -f "$VSCODE_DIR/code" ]]; then
    warn "VSCode portable found at: $VSCODE_DIR"
    warn "But 'code' is not linked to the terminal yet — fixing that now."
    SKIP_DOWNLOAD=true
else
    ok "No existing VSCode installation found — downloading."
    SKIP_DOWNLOAD=false
fi

# ── 2. Determine architecture ─────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  OS_TYPE="linux-x64"   ;;
    aarch64) OS_TYPE="linux-arm64" ;;
    armv6l)  OS_TYPE="linux-armhf" ;;
    *)       err "Unsupported architecture: $ARCH" ;;
esac

# ── 3. Download VSCode portable ───────────────────────────────────────────────
if ! $SKIP_DOWNLOAD; then
    step "Downloading VSCode portable ($OS_TYPE)..."
    info "This may take a moment (~100MB)..."

    DOWNLOAD_URL="https://code.visualstudio.com/sha/download?build=stable&os=$OS_TYPE"
    TMP_DIR=$(mktemp -d)
    TMP_TAR="$TMP_DIR/vscode.tar.gz"

    curl -fsSL -o "$TMP_TAR" "$DOWNLOAD_URL"
    ok "Download complete."

    # ── 4. Extract into ~/.local/vscode ──────────────────────────────────────
    step "Extracting VSCode..."
    mkdir -p "$VSCODE_DIR"
    tar -xzf "$TMP_TAR" -C "$VSCODE_DIR" --strip-components=1
    # --strip-components=1 removes the top-level folder inside the archive
    # so the contents land directly in $VSCODE_DIR instead of a subfolder

    rm -rf "$TMP_DIR"
    ok "VSCode extracted to: $VSCODE_DIR"

    # ── 5. Create portable mode data directory ────────────────────────────────
    # VSCode looks for a 'data' folder next to the binary to activate portable mode
    # This keeps all extensions and settings inside ~/.local/vscode/data
    # instead of scattering them across the home directory
    mkdir -p "$VSCODE_DIR/data"
    ok "Portable mode enabled — settings stored in: $VSCODE_DIR/data"
fi

# ── 6. Symlink 'code' into ~/.local/bin ───────────────────────────────────────
step "Linking 'code' command to terminal..."

CODE_BIN="$VSCODE_DIR/code"
[[ -f "$CODE_BIN" ]] || err "Could not find the code binary at: $CODE_BIN"

# Remove old symlink if it exists but points somewhere wrong
if [[ -L "$LOCAL_BIN/code" ]]; then
    rm "$LOCAL_BIN/code"
fi

ln -s "$CODE_BIN" "$LOCAL_BIN/code"
ok "'code' symlinked: $LOCAL_BIN/code → $CODE_BIN"

# ── 7. Verify ─────────────────────────────────────────────────────────────────
step "Verifying installation..."
VSCODE_VERSION=$("$LOCAL_BIN/code" --version 2>/dev/null | head -1 || echo "unknown")
ok "VSCode version: $VSCODE_VERSION"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════╗"
echo -e "║              ✓  Setup complete!              ║"
echo -e "╚════════════════════════════════════════════════╝${NC}"
echo ""
info "Install location : $VSCODE_DIR"
info "Settings & exts  : $VSCODE_DIR/data"
info "CLI command      : $LOCAL_BIN/code"
echo ""
echo -e "${YELLOW}Note:${NC} Open a new terminal tab, then run:"
echo -e "        code .        → open current folder"
echo -e "        code file.txt → open a specific file"
echo ""
echo -e "${YELLOW}Note:${NC} No sudo was used — VSCode is fully contained in ~/.local/"
echo ""
