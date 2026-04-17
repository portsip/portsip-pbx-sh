#!/bin/sh

set -eu

workspace="/opt/portsip"
url="https://raw.githubusercontent.com/portsip/portsip-pbx-sh/master/v22.x"

scripts="
install_docker_cn.sh
pbx_ctl.sh
sbc_ctl.sh
im_ctl.sh
cluster_ctl.sh
trace_ctl.sh
dataflow_ctl.sh
certmanager_ctl.sh
"

echo "[info]: Starting..."

# Create workspace if it doesn't exist
if [ ! -d "$workspace" ]; then
    echo "[warn]: workspace $workspace does not exist."
    mkdir -p "$workspace"
fi

# Install curl if not installed
sudo apt-get install -y -qq curl >/dev/null  || true

chmod 755 "$workspace"

# Remove any existing scripts in the workspace
echo "[info]: removing existing scripts from $workspace..."
for script in $scripts; do
    rm -f "$workspace/$script" || true
done

# download scripts
for script in $scripts; do
    src="$url/$script"
    dst="$workspace/$script"
    echo "[info]: downloading $src -> $dst"

    curl -fsS "$src" -o "$dst"

    chmod 755 "$dst"
done

mv "$workspace/install_docker_cn.sh" "$workspace/install_docker.sh" 

echo ""
echo "[info]: All scripts have been cached in directory $workspace."
echo "[info]: Initialization complete. Please deploy the service according to the manual."
echo ""
