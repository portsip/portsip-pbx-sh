#!/bin/sh

set -e

# ============================================================
# install_docker.sh
# Install Docker (with Compose & plugins) + firewalld
# Supports: Ubuntu / Debian (amd64 only)
# Usage:    sudo /bin/sh install_docker.sh
# ============================================================

log_info()  { echo "[info]: $*"; }
log_warn()  { echo "[warn]: $*"; }
log_error() { echo "[error]: $*"; }

# ---------- preflight checks ----------

if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root."
    echo "        sudo /bin/sh install_docker.sh"
    exit 1
fi

if [ ! -f /etc/os-release ]; then
    log_error "Cannot detect operating system (/etc/os-release not found)."
    exit 1
fi

. /etc/os-release

case "$ID" in
    ubuntu|debian) ;;
    *)
        log_error "Unsupported OS: $ID"
        log_error "This script only supports Ubuntu and Debian (amd64)."
        exit 1
        ;;
esac

ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
case "$ARCH" in
    amd64|x86_64) ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        log_error "This script only supports amd64."
        exit 1
        ;;
esac

CODENAME="${VERSION_CODENAME:-}"
if [ -z "$CODENAME" ]; then
    log_error "Cannot determine distribution codename (VERSION_CODENAME is empty)."
    exit 1
fi

log_info "Detected: $NAME ($CODENAME) on $ARCH"
log_info "Starting Docker + firewalld installation..."

# ---------- network check ----------

log_info "Checking network connectivity..."
if ! curl -s --connect-timeout 5 https://download.docker.com > /dev/null 2>&1; then
    log_warn "Cannot reach download.docker.com — will try to proceed anyway."
fi

# ---------- clean up conflicting packages ----------

log_info "Removing conflicting packages (if any)..."
apt-get remove -y ufw 2>/dev/null || true
for pkg in docker docker-engine docker.io containerd runc; do
    apt-get remove -y "$pkg" 2>/dev/null || true
done

# ---------- update system ----------

log_info "Updating package index..."
if ! apt-get update -y; then
    log_warn "apt-get update failed; attempting dpkg reconfigure..."
    dpkg --configure -a
    apt-get update -y
fi

log_info "Upgrading existing packages..."
if ! DEBIAN_FRONTEND=noninteractive apt-get upgrade -y; then
    log_warn "apt-get upgrade failed; attempting dpkg reconfigure..."
    dpkg --configure -a
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
fi

# ---------- install prerequisites + firewalld ----------

log_info "Installing prerequisites and firewalld..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    firewalld

log_info "Enabling and starting firewalld..."
systemctl enable firewalld
systemctl start firewalld || log_warn "firewalld could not be started (possibly already running)."

# ensure IndividualCalls is enabled in firewalld
if [ -f /etc/firewalld/firewalld.conf ]; then
    log_info "Configuring firewalld IndividualCalls..."
    sed -i 's#IndividualCalls=no#IndividualCalls=yes#g' /etc/firewalld/firewalld.conf
fi

# ---------- add Docker repository ----------

log_info "Adding Docker GPG key..."
mkdir -p /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
    -o /tmp/docker-gpg-key.tmp
gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg < /tmp/docker-gpg-key.tmp
rm -f /tmp/docker-gpg-key.tmp
chmod a+r /etc/apt/keyrings/docker.gpg

log_info "Adding Docker APT repository..."
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${CODENAME} stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

# ---------- install Docker ----------

log_info "Installing Docker Engine, CLI, containerd, and Compose..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-compose-plugin

log_info "Enabling and starting Docker..."
systemctl enable docker
systemctl restart firewalld || log_warn "Failed to restart firewalld after config change."
systemctl restart docker

# ---------- verify ----------

log_info "Verifying installation..."
echo

docker --version || log_error "Docker CLI not found."
docker compose version || log_error "Docker Compose plugin not found."

echo
if systemctl is-active --quiet firewalld; then
    log_info "firewalld is running."
else
    log_warn "firewalld is not running. Start it with: systemctl start firewalld"
fi

if systemctl is-active --quiet docker; then
    log_info "Docker daemon is running."
else
    log_warn "Docker daemon is not running. Start it with: systemctl start docker"
fi

echo
log_info "============================================"
log_info " Installation complete!"
log_info " Docker:         $(docker --version 2>/dev/null || echo 'N/A')"
log_info " Docker Compose: $(docker compose version 2>/dev/null || echo 'N/A')"
log_info "============================================"
