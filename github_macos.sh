#!/usr/bin/env bash
# =============================================================================
#  setup-github-macos.sh — GitHub SSH-konfiguration för macOS utan admin
#  Kör med: bash <(curl -fsSL https://raw.githubusercontent.com/DITT_REPO/main/setup-github-macos.sh)
# =============================================================================

set -euo pipefail

# ── Färger ────────────────────────────────────────────────────────────────────
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
echo "  ║   (utan admin / utan Homebrew)           ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── 0. Kontrollera macOS ──────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || err "Det här skriptet är enbart för macOS."
ok "macOS $(sw_vers -productVersion) • $(uname -m)"

# ── Lokal bin-mapp (ingen admin krävs) ───────────────────────────────────────
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# Lägg till i shell-rc om det saknas (zsh är default på moderna macOS)
for RC in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    if [[ -f "$RC" ]] || [[ "$RC" == "$HOME/.zprofile" ]]; then
        grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$RC" 2>/dev/null || \
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC"
        break
    fi
done

# ── 1. Kontrollera git ────────────────────────────────────────────────────────
step "Kontrollerar git..."
GIT_OK=false
for GIT_PATH in /usr/bin/git /usr/local/bin/git "$LOCAL_BIN/git"; do
    if [[ -x "$GIT_PATH" ]] && "$GIT_PATH" --version &>/dev/null 2>&1; then
        GIT_OK=true
        ok "Git hittad: $("$GIT_PATH" --version)"
        break
    fi
done

if ! $GIT_OK; then
    warn "Git hittades inte som körbar fil."
    info "SSH-nyckeln och GitHub-kopplingen fungerar ändå utan git."
    info "Be IT installera git, eller kör: xcode-select --install (kräver admin)."
fi

# ── 2. GitHub CLI utan Homebrew / admin ───────────────────────────────────────
step "Kontrollerar GitHub CLI (gh)..."

install_gh() {
    info "Hämtar senaste gh-versionen från GitHub Releases..."

    GH_VERSION=$(curl -fsSL "https://api.github.com/repos/cli/cli/releases/latest" \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    [[ -z "$GH_VERSION" ]] && err "Kunde inte hämta gh-version från GitHub API."
    info "Senaste gh: v${GH_VERSION}"

    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        GH_ARCH="macOS_arm64"
    else
        GH_ARCH="macOS_amd64"
    fi

    GH_ZIP="gh_${GH_VERSION}_${GH_ARCH}.zip"
    GH_URL="https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_ZIP}"
    GH_TMP=$(mktemp -d)

    info "Laddar ner: $GH_ZIP"
    curl -fsSL "$GH_URL" -o "${GH_TMP}/${GH_ZIP}"
    unzip -q "${GH_TMP}/${GH_ZIP}" -d "${GH_TMP}/extracted"

    GH_BIN=$(find "${GH_TMP}/extracted" -name "gh" -type f | head -1)
    [[ -z "$GH_BIN" ]] && err "Kunde inte hitta gh-binären i zip-filen."
    cp "$GH_BIN" "$LOCAL_BIN/gh"
    chmod +x "$LOCAL_BIN/gh"
    rm -rf "$GH_TMP"

    ok "gh v${GH_VERSION} installerat → $LOCAL_BIN/gh"
}

if command -v gh &>/dev/null; then
    ok "gh redan tillgänglig: $(gh --version | head -1)"
else
    install_gh
fi

# ── 3. Samla in användaruppgifter ─────────────────────────────────────────────
echo ""
step "Samlar in uppgifter..."

read -rp "  GitHub-användarnamn : " GH_USER
[[ -z "$GH_USER" ]] && err "Användarnamn krävs."

read -rp "  GitHub-e-post        : " GH_EMAIL
[[ -z "$GH_EMAIL" ]] && err "E-post krävs."

echo -n "  SSH-nyckelns lösenord (lämna tomt för inget): "
read -rs SSH_PASS; echo
echo -n "  Bekräfta lösenord                           : "
read -rs SSH_PASS2; echo
[[ "$SSH_PASS" != "$SSH_PASS2" ]] && err "Lösenorden matchar inte."

KEY_LABEL="${GH_USER}-$(hostname -s | tr '[:upper:]' '[:lower:]')-$(date +%Y%m%d)"
KEY_PATH="$HOME/.ssh/${KEY_LABEL}"

# ── 4. SSH-katalog ────────────────────────────────────────────────────────────
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# ── 5. Generera SSH-nyckel ────────────────────────────────────────────────────
step "Genererar SSH-nyckel (ed25519)..."
if [[ -f "$KEY_PATH" ]]; then
    warn "Nyckel finns redan: $KEY_PATH"
    read -rp "  Skriv över? (j/N): " OW
    if [[ "$OW" =~ ^[jJ]$ ]]; then
        rm -f "$KEY_PATH" "${KEY_PATH}.pub"
        ssh-keygen -t ed25519 -C "$GH_EMAIL" -f "$KEY_PATH" -N "$SSH_PASS"
        ok "Nyckel genererad (skriven över)."
    else
        ok "Behåller befintlig nyckel."
    fi
else
    ssh-keygen -t ed25519 -C "$GH_EMAIL" -f "$KEY_PATH" -N "$SSH_PASS"
    ok "Nyckel genererad: $KEY_PATH"
fi
chmod 600 "$KEY_PATH"
PUB_KEY=$(cat "${KEY_PATH}.pub")

# ── 6. ssh-agent + macOS Keychain ────────────────────────────────────────────
step "Lägger till nyckel i ssh-agent och macOS Keychain..."
eval "$(ssh-agent -s)" > /dev/null 2>&1

# --apple-use-keychain (macOS 12+), faller tillbaka på -K (äldre macOS)
if ssh-add --apple-use-keychain "$KEY_PATH" 2>/dev/null; then
    ok "Nyckel tillagd med Keychain (--apple-use-keychain)."
elif ssh-add -K "$KEY_PATH" 2>/dev/null; then
    ok "Nyckel tillagd med Keychain (-K)."
else
    ssh-add "$KEY_PATH"
    ok "Nyckel tillagd i ssh-agent."
fi

# ── 7. ~/.ssh/config ──────────────────────────────────────────────────────────
step "Uppdaterar ~/.ssh/config..."
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
    ok "SSH-config uppdaterad."
else
    ok "SSH-config innehåller redan denna nyckel."
fi

# ── 8. Autentisera och lägg till nyckel på GitHub ────────────────────────────
step "Kopplar upp mot GitHub via gh..."

if ! gh auth status &>/dev/null; then
    info "Webbläsaren öppnas – logga in och godkänn åtkomst."
    gh auth login --hostname github.com --git-protocol ssh --web
else
    ok "Redan inloggad i gh."
fi

if gh ssh-key list 2>/dev/null | grep -q "$KEY_LABEL"; then
    ok "SSH-nyckel '${KEY_LABEL}' finns redan på GitHub."
else
    gh ssh-key add "${KEY_PATH}.pub" --title "$KEY_LABEL"
    ok "SSH-nyckel tillagd på GitHub!"
fi

# ── 9. Git-konfiguration ──────────────────────────────────────────────────────
step "Konfigurerar git..."
if $GIT_OK; then
    git config --global user.name  "$GH_USER"
    git config --global user.email "$GH_EMAIL"
    ok "Git: $GH_USER <$GH_EMAIL>"
else
    warn "Git ej tillgängligt – hoppar över git config."
    info "Kör detta manuellt när git är installerat:"
    info "  git config --global user.name  \"$GH_USER\""
    info "  git config --global user.email \"$GH_EMAIL\""
fi

# ── 10. Testa anslutning ──────────────────────────────────────────────────────
step "Testar SSH-anslutning till GitHub..."
sleep 1
SSH_TEST=$(ssh -T git@github.com -i "$KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes 2>&1 || true)

if echo "$SSH_TEST" | grep -q "successfully authenticated"; then
    ok "Anslutning till GitHub fungerar!"
else
    warn "Kunde inte bekräfta anslutning automatiskt."
    info "Testa manuellt: ssh -T git@github.com"
    info "Svar: $SSH_TEST"
fi

# ── Klar ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════╗"
echo -e "║           ✓  Installation klar!              ║"
echo -e "╚════════════════════════════════════════════════╝${NC}"
echo ""
info "Privat nyckel  : $KEY_PATH"
info "Publik nyckel  : ${KEY_PATH}.pub"
info "gh binär       : $LOCAL_BIN/gh"
echo ""
echo -e "${YELLOW}OBS:${NC} Inget admin-lösenord användes under installationen."
echo -e "     Allt ligger i din hemkatalog: ~/."
echo -e "     Kör skriptet på nästa Mac för att sätta upp den också."
echo ""
