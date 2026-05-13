#!/usr/bin/env bash
# =============================================================================
#  vscode_macos.sh — Install VSCode on macOS without admin
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
echo "  ║   VSCode Installer  •  macOS             ║"
echo "  ║   (no admin required)                    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── 0. Verify macOS ───────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || err "This script is for macOS only."
ok "macOS $(sw_vers -productVersion) • $(uname -m)"

# ── Local bin directory ───────────────────────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

for RC in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    if [[ -f "$RC" ]] || [[ "$RC" == "$HOME/.zprofile" ]]; then
        grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$RC" 2>/dev/null || \
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
        break
    fi
done

APP_DIR="$HOME/Applications"
APP_PATH="$APP_DIR/Visual Studio Code.app"
VSCODE_CLI="$APP_PATH/Contents/Resources/app/bin/code"
CODE_WRAPPER="$LOCAL_BIN/code"

# ── 1. Check if already installed ────────────────────────────────────────────
step "Checking for existing VSCode installation..."

# Check if 'code' already works in the terminal
if command -v code &>/dev/null; then
    ok "'code' is already available in the terminal: $(command -v code)"
    info "Run 'code .' to open a folder, or 'code --version' to confirm."
    echo ""
    exit 0
fi

# Check if the .app exists but isn't wired up to the terminal
if [[ -d "$APP_PATH" ]]; then
    warn "VSCode.app found at: $APP_PATH"
    warn "But 'code' is not available in the terminal yet — fixing that now."
    SKIP_DOWNLOAD=true
else
    ok "No existing VSCode installation found — downloading."
    SKIP_DOWNLOAD=false
fi

# ── 2. Download VSCode ────────────────────────────────────────────────────────
if ! $SKIP_DOWNLOAD; then
    step "Downloading VSCode..."

    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        DOWNLOAD_URL="https://update.code.visualstudio.com/latest/darwin-arm64/stable"
        info "Architecture: Apple Silicon (arm64)"
    else
        DOWNLOAD_URL="https://update.code.visualstudio.com/latest/darwin/stable"
        info "Architecture: Intel (x86_64)"
    fi

    mkdir -p "$APP_DIR"
    TMP_DIR=$(mktemp -d)
    TMP_ZIP="$TMP_DIR/vscode.zip"

    info "This may take a moment (~100MB)..."
    curl -fsSL -o "$TMP_ZIP" "$DOWNLOAD_URL"
    ok "Download complete."

    # ── 3. Extract ────────────────────────────────────────────────────────────
    step "Extracting VSCode..."
    unzip -q "$TMP_ZIP" -d "$TMP_DIR"

    # The zip contains "Visual Studio Code.app" — move it to ~/Applications/
    if [[ -d "$TMP_DIR/Visual Studio Code.app" ]]; then
        mv "$TMP_DIR/Visual Studio Code.app" "$APP_DIR/"
    else
        # Some releases nest it differently — find it
        FOUND_APP=$(find "$TMP_DIR" -name "Visual Studio Code.app" -maxdepth 2 | head -1)
        [[ -z "$FOUND_APP" ]] && err "Could not find Visual Studio Code.app in the downloaded zip."
        mv "$FOUND_APP" "$APP_DIR/"
    fi

    rm -rf "$TMP_DIR"
    ok "VSCode installed to: $APP_PATH"
fi

# ── 4. Wire up 'code' in the terminal ────────────────────────────────────────
step "Setting up 'code' command in terminal..."

[[ -f "$VSCODE_CLI" ]] || err "Could not find the code CLI inside the app bundle at: $VSCODE_CLI"

# Create a small wrapper script that calls the real CLI inside the .app
cat > "$CODE_WRAPPER" <<EOF
#!/usr/bin/env bash
exec "$VSCODE_CLI" "\$@"
EOF
chmod +x "$CODE_WRAPPER"
ok "'code' command created at: $CODE_WRAPPER"

# ── 5. Verify ─────────────────────────────────────────────────────────────────
step "Verifying installation..."
VSCODE_VERSION=$("$CODE_WRAPPER" --version 2>/dev/null | head -1 || echo "unknown")
ok "VSCode version: $VSCODE_VERSION"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════╗"
echo -e "║              ✓  Setup complete!              ║"
echo -e "╚════════════════════════════════════════════════╝${NC}"
echo ""
info "App location  : $APP_PATH"
info "CLI wrapper   : $CODE_WRAPPER"
echo ""
echo -e "${YELLOW}Note:${NC} Open a new terminal tab, then run:"
echo -e "        code .        → open current folder"
echo -e "        code file.txt → open a specific file"
echo ""
