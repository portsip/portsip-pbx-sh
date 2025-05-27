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

echo "[info]: Starting..."

if [ ! -d "$workspace" ]; then
    echo "[warn]: workspace $workspace does not exist."
    mkdir -p $workspace
fi

chmod 755 $workspace

# remove all scripts
rm -rf $workspace/install_docker.sh || true
rm -rf $workspace/pbx_ctl.sh || true
rm -rf $workspace/sbc_ctl.sh || true
rm -rf $workspace/im_ctl.sh || true
rm -rf $workspace/cluster_ctl.sh || true
rm -rf $workspace/trace_ctl.sh || true

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

echo ""
echo "[info]: All scripts are cached in directory $workspace."
echo ""
echo "Usage(pbx):"
echo "  cd $workspace && sudo /bin/sh pbx_ctl.sh run -p [data storage] -a [ip] -i [pbx image] -f [extend file storage]"
echo "Usage(sbc):"
echo "  cd $workspace && sudo /bin/sh sbc_ctl.sh run -p [data storage] -i [sbc image]"
echo "Usage(im):"
echo "  Integration: cd $workspace && sudo /bin/sh im_ctl.sh run -p [data storage] -i [pbx image] -t [im token] -f [extend file storage]"
echo "  Standalone: cd $workspace && sudo /bin/sh im_ctl.sh run -E -p [data storage] -i [pbx image] -a [private ip] -A [public ip] -x [pbx ip] -t [im token] -f [extend file storage]"
echo "Usage(cluster):"
echo "  cd $workspace && sudo /bin/sh cluster_ctl.sh run -p [data storage] -a [ip] -x [pbx ip] -i [pbx image] -s [queue-server-only|media-server-only|meeting-server-only|vr-server-only] -n [extend service name]"
echo "Usage(trace):"
echo "  cd $workspace && sudo /bin/sh trace_ctl.sh run -p [data storage] -k [rotation days] -l [http port] -z [capture port]"
echo ""
echo ""
echo "[info]: Successfully initialized. Please deploy the service according to the manual."
echo ""
