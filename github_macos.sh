#!/usr/bin/env bash
# =============================================================================
#  setup-github-macos.sh — Automatic GitHub SSH setup for macOS (no admin)
#  Run with: bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/setup-github-macos.sh)
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
echo "  ║   GitHub SSH Auto-Setup  •  macOS        ║"
echo "  ║   (no admin / no Homebrew required)      ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── 0. Verify macOS ───────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || err "This script is for macOS only."
ok "macOS $(sw_vers -productVersion) • $(uname -m)"

# ── Local bin directory (no admin needed) ─────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# Persist PATH in shell rc (zsh is default on modern macOS)
for RC in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    if [[ -f "$RC" ]] || [[ "$RC" == "$HOME/.zprofile" ]]; then
        grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$RC" 2>/dev/null || \
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
        break
    fi
done

# ── 1. Check for existing SSH keys ────────────────────────────────────────────
step "Checking for existing SSH keys..."

EXISTING_KEYS=()

if [[ -d "$HOME/.ssh" ]]; then
    while IFS= read -r -d '' pubfile; do
        privfile="${pubfile%.pub}"
        # Only include if the private key also exists
        if [[ -f "$privfile" ]]; then
            EXISTING_KEYS+=("$privfile")
        fi
    done < <(find "$HOME/.ssh" -maxdepth 1 -name "*.pub" -print0 2>/dev/null)
fi

if [[ ${#EXISTING_KEYS[@]} -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠  Existing SSH keys found on this machine:${NC}"
    echo ""
    for key in "${EXISTING_KEYS[@]}"; do
        # Check if the key is already linked to github.com in ~/.ssh/config
        GITHUB_TAG=""
        if grep -A5 "github.com" "$HOME/.ssh/config" 2>/dev/null | grep -q "$(basename "$key")"; then
            GITHUB_TAG=" ${CYAN}← linked to github.com${NC}"
        fi
        echo -e "    ${YELLOW}•${NC} $(basename "$key")${GITHUB_TAG}"
    done
    echo ""
    echo -e "  ${YELLOW}If you continue, a new key will be created and added to GitHub."
    echo -e "  Existing keys will not be touched, but make sure you actually"
    echo -e "  need a new one — old keys should be removed from GitHub when"
    echo -e "  they are no longer in use.${NC}"
    echo ""
    read -rp "  Are you sure you want to continue? (y/N): " CONTINUE_CONFIRM
    echo ""
    if [[ ! "$CONTINUE_CONFIRM" =~ ^[yY]$ ]]; then
        echo -e "  ${CYAN}Aborted. No changes were made.${NC}"
        echo ""
        echo -e "  Your existing public keys:"
        for key in "${EXISTING_KEYS[@]}"; do
            echo -e "    $(cat "${key}.pub")"
        done
        echo ""
        exit 0
    fi
else
    ok "No existing SSH keys found — continuing."
fi

# ── 2. Check for git ──────────────────────────────────────────────────────────
step "Checking for git..."
GIT_OK=false

for GIT_PATH in /usr/bin/git /usr/local/bin/git "$LOCAL_BIN/git"; do
    if [[ -x "$GIT_PATH" ]] && "$GIT_PATH" --version &>/dev/null 2>&1; then
        GIT_OK=true
        ok "Git found: $("$GIT_PATH" --version)"
        break
    fi
done

if ! $GIT_OK; then
    warn "Git not found."
    info "The SSH key and GitHub connection will still work without git."
    info "Ask IT to install git, or run: xcode-select --install (requires admin)."
fi

# ── 3. GitHub CLI — no Homebrew / no admin ────────────────────────────────────
step "Checking for GitHub CLI (gh)..."

install_gh() {
    info "Fetching latest gh release from GitHub..."

    GH_VERSION=$(curl -fsSL "https://api.github.com/repos/cli/cli/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    [[ -z "$GH_VERSION" ]] && err "Could not fetch gh version from GitHub API."
    info "Latest gh: v${GH_VERSION}"

    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        GH_ARCH="macOS_arm64"
    else
        GH_ARCH="macOS_amd64"
    fi

    GH_ZIP="gh_${GH_VERSION}_${GH_ARCH}.zip"
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_ZIP}"
    GH_TMP=$(mktemp -d)

    info "Downloading: $GH_ZIP"
    curl -fsSL "$GH_URL" -o "${GH_TMP}/${GH_ZIP}"
    unzip -q "${GH_TMP}/${GH_ZIP}" -d "${GH_TMP}/extracted"

    GH_BIN=$(find "${GH_TMP}/extracted" -name "gh" -type f | head -1)
    [[ -z "$GH_BIN" ]] && err "Could not find gh binary inside zip."
    cp "$GH_BIN" "$LOCAL_BIN/gh"
    chmod +x "$LOCAL_BIN/gh"
    rm -rf "$GH_TMP"

    ok "gh v${GH_VERSION} installed → $LOCAL_BIN/gh"
}

if command -v gh &>/dev/null; then
    ok "gh already available: $(gh --version | head -1)"
else
    install_gh
fi

# ── 4. Collect user details ───────────────────────────────────────────────────
echo ""
step "Collecting details..."

read -rp "  GitHub username      : " GH_USER
[[ -z "$GH_USER" ]] && err "Username is required."

read -rp "  GitHub email         : " GH_EMAIL
[[ -z "$GH_EMAIL" ]] && err "Email is required."

echo -n "  SSH key passphrase (leave empty for none): "
read -rs SSH_PASS; echo
echo -n "  Confirm passphrase                       : "
read -rs SSH_PASS2; echo
[[ "$SSH_PASS" != "$SSH_PASS2" ]] && err "Passphrases do not match."

KEY_LABEL="${GH_USER}-$(hostname -s | tr '[:upper:]' '[:lower:]')-$(date +%Y%m%d)"
KEY_PATH="$HOME/.ssh/${KEY_LABEL}"

# ── 5. Ensure SSH directory exists ────────────────────────────────────────────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# ── 6. Generate SSH key ───────────────────────────────────────────────────────
step "Generating SSH key (ed25519)..."
if [[ -f "$KEY_PATH" ]]; then
    warn "Key already exists at: $KEY_PATH"
    read -rp "  Overwrite? (y/N): " OW
    if [[ "$OW" =~ ^[yY]$ ]]; then
        rm -f "$KEY_PATH" "${KEY_PATH}.pub"
        ssh-keygen -t ed25519 -C "$GH_EMAIL" -f "$KEY_PATH" -N "$SSH_PASS"
        ok "Key generated (overwritten)."
    else
        ok "Keeping existing key."
    fi
else
    ssh-keygen -t ed25519 -C "$GH_EMAIL" -f "$KEY_PATH" -N "$SSH_PASS"
    ok "Key generated: $KEY_PATH"
fi
chmod 600 "$KEY_PATH"
PUB_KEY=$(cat "${KEY_PATH}.pub")

# ── 7. ssh-agent + macOS Keychain ────────────────────────────────────────────
step "Adding key to ssh-agent and macOS Keychain..."
eval "$(ssh-agent -s)" > /dev/null 2>&1

# --apple-use-keychain (macOS 12+), falls back to -K (older macOS)
if ssh-add --apple-use-keychain "$KEY_PATH" 2>/dev/null; then
    ok "Key added with Keychain (--apple-use-keychain)."
elif ssh-add -K "$KEY_PATH" 2>/dev/null; then
    ok "Key added with Keychain (-K)."
else
    ssh-add "$KEY_PATH"
    ok "Key added to ssh-agent."
fi

# ── 8. Update ~/.ssh/config ───────────────────────────────────────────────────
step "Updating ~/.ssh/config..."
SSH_CONFIG="$HOME/.ssh/config"
MARKER="# github-${KEY_LABEL}"

if ! grep -q "$MARKER" "$SSH_CONFIG" 2>/dev/null; then
    cat >> "$SSH_CONFIG" <<EOF

$MARKER
Host github.com
    HostName github.com
    User git
    IdentityFile $KEY_PATH
    AddKeysToAgent yes
    UseKeychain yes
    IdentitiesOnly yes
EOF
    chmod 600 "$SSH_CONFIG"
    ok "SSH config updated."
else
    ok "SSH config already contains this key."
fi

# ── 9. Authenticate and add key to GitHub ─────────────────────────────────────
step "Connecting to GitHub via gh..."

if ! gh auth status &>/dev/null; then
    info "Your browser will open — log in and approve access."
    gh auth login --hostname github.com --git-protocol ssh --web
else
    ok "Already logged in to gh."
fi

if gh ssh-key list 2>/dev/null | grep -q "$KEY_LABEL"; then
    ok "SSH key '${KEY_LABEL}' already exists on GitHub."
else
    gh ssh-key add "${KEY_PATH}.pub" --title "$KEY_LABEL"
    ok "SSH key added to GitHub!"
fi

# ── 10. Configure git identity ────────────────────────────────────────────────
step "Configuring git..."
if $GIT_OK; then
    git config --global user.name  "$GH_USER"
    git config --global user.email "$GH_EMAIL"
    ok "Git identity set: $GH_USER <$GH_EMAIL>"
else
    warn "Git not available — skipping git config."
    info "Run these manually once git is installed:"
    info "  git config --global user.name  \"$GH_USER\""
    info "  git config --global user.email \"$GH_EMAIL\""
fi

# ── 11. Test connection ───────────────────────────────────────────────────────
step "Testing SSH connection to GitHub..."
sleep 1
SSH_TEST=$(ssh -T git@github.com -i "$KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes 2>&1 || true)

if echo "$SSH_TEST" | grep -q "successfully authenticated"; then
    ok "GitHub connection is working!"
else
    warn "Could not confirm connection automatically."
    info "Test manually with: ssh -T git@github.com"
    info "Response received: $SSH_TEST"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════╗"
echo -e "║              ✓  Setup complete!              ║"
echo -e "╚════════════════════════════════════════════════╝${NC}"
echo ""
info "Private key  : $KEY_PATH"
info "Public key   : ${KEY_PATH}.pub"
info "gh binary    : $LOCAL_BIN/gh"
echo ""
echo -e "${YELLOW}Note:${NC} No admin password was used during setup."
echo -e "      Everything is stored in your home directory: ~/."
echo -e "      Run this script on your next Mac to set that up too."
echo ""
