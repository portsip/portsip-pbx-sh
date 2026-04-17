#!/bin/bash

set -e

workspace=/opt/portsip

url="https://raw.githubusercontent.com/portsip/portsip-pbx-sh/master/v22.x"
scriptInstallDockerUrl="$url/install_docker.sh"
scriptPbxCtlUrl="$url/pbx_ctl.sh"
scriptSbcCtlUrl="$url/sbc_ctl.sh"
scriptImCtlUrl="$url/im_ctl.sh"
scriptClusterCtlUrl="$url/cluster_ctl.sh"
scriptTraceCtlUrl="$url/trace_ctl.sh"
scriptDataflowCtlUrl="$url/dataflow_ctl.sh"
scriptCertCtlUrl="$url/certmanager_ctl.sh"

echo "[info]: Starting..."

if [ ! -d "$workspace" ]; then
    echo "[warn]: workspace $workspace does not exist."
    mkdir -p $workspace
fi

sudo apt-get install -y -qq curl >/dev/null  || true

chmod 755 $workspace

# remove all scripts
rm -rf $workspace/install_docker.sh || true
rm -rf $workspace/pbx_ctl.sh || true
rm -rf $workspace/sbc_ctl.sh || true
rm -rf $workspace/im_ctl.sh || true
rm -rf $workspace/cluster_ctl.sh || true
rm -rf $workspace/trace_ctl.sh || true
rm -rf $workspace/dataflow_ctl.sh || true
rm -rf $workspace/certmanager_ctl.sh || true

# cache scripts
echo "[info]: download $scriptInstallDockerUrl => $workspace/install_docker.sh"
curl $scriptInstallDockerUrl -o $workspace/install_docker.sh

echo "[info]: download $scriptPbxCtlUrl => $workspace/pbx_ctl.sh"
curl $scriptPbxCtlUrl -o $workspace/pbx_ctl.sh

echo "[info]: download $scriptSbcCtlUrl => $workspace/sbc_ctl.sh"
curl $scriptSbcCtlUrl -o $workspace/sbc_ctl.sh

echo "[info]: download $scriptImCtlUrl => $workspace/im_ctl.sh"
curl $scriptImCtlUrl -o $workspace/im_ctl.sh

echo "[info]: download $scriptClusterCtlUrl => $workspace/cluster_ctl.sh"
curl $scriptClusterCtlUrl -o $workspace/cluster_ctl.sh

echo "[info]: download $scriptTraceCtlUrl => $workspace/trace_ctl.sh"
curl $scriptTraceCtlUrl -o $workspace/trace_ctl.sh

echo "[info]: download $scriptDataflowCtlUrl => $workspace/dataflow_ctl.sh"
curl $scriptDataflowCtlUrl -o $workspace/dataflow_ctl.sh

echo "[info]: download $scriptCertCtlUrl => $workspace/certmanager_ctl.sh"
curl $scriptCertCtlUrl -o $workspace/certmanager_ctl.sh

echo ""
echo "[info]: All scripts are cached in directory $workspace."
echo "[info]: Successfully initialized. Please deploy the service according to the manual."
echo ""
