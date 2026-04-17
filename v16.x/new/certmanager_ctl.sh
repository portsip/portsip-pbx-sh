#!/usr/bin/env bash
set -e

firewall_svc_name="portsip-certmanager"
data_path=
certmanager_img=
version=

if [ -z $1 ];
then
    echo ""
    echo "[command] need more parameters."
    echo ""
    exit -1
fi

if [ ! -d "./certmanager" ]; then
    mkdir certmanager
fi

cd certmanager

set_firewall(){
    echo ""
    echo "[firewall] configure firewall rules:"
    systemctl stop ufw || true
    systemctl disable ufw  || true
    systemctl enable firewalld
    systemctl start firewalld
    local pre_svc_exist=false
    local ports="$(firewall-cmd --permanent --service=${firewall_svc_name} --get-ports)"
    if [ $? -eq 0 ]; then
        pre_svc_exist=true
    fi
    firewall-cmd -q --zone=trusted --remove-interface=docker0 --permanent

    firewall-cmd -q --permanent --delete-service=${firewall_svc_name} || true
    firewall-cmd --reload
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --new-service=${firewall_svc_name} || true
    firewall-cmd --permanent --service=${firewall_svc_name} --add-port=443/tcp
    if [ "$pre_svc_exist" = true ] ; then
        for port_rule in $ports
        do
            firewall-cmd --permanent --service=${firewall_svc_name} --add-port=$port_rule
        done
    fi
    firewall-cmd --permanent --add-service=${firewall_svc_name}
    firewall-cmd --reload
    systemctl restart firewalld
    echo "[firewall] done"
}

export_certmanager_production_version() {
    local null_str=null
    local labels=$(docker image inspect --format='{{json .Config.Labels}}' $certmanager_img)
    if [ -z "$labels" ]; then
        return
    elif [ "$labels" = $null_str ]; then
        return
    fi
    cat << LEOF > labels.json
$labels
LEOF

    grep -o '"version":"[^"]*' labels.json | grep -o '[^"]*$'
}

is_certmanager_production_version_less_than_16_1() {
    # x.y.z

    set -f; IFS='.'
    set -- $version
    local x=$1; 
    local y=$2; 
    local z=$3
    set +f; unset IFS

    if [ $x -lt 16 ]; then
        echo 1
    elif [ $x -gt 16 ]; then
        echo 0
    elif [ $y -lt 1 ]; then
        echo 1
    else
        echo 0
    fi
}

# $1: data_path
# $2: certmanager_img
export_configure() {
    echo 
    echo "[configure] export configure file 'docker-compose-portsip-certmanager.yml'"

    # certmanager >= 16.1
    local ret=$(is_certmanager_production_version_less_than_16_1)
    # ret: 1 for success and 0 for failure
    if [ $ret -ne 0 ]; then
        echo "[configure] not support version $version"
        exit -1
    fi

    cat << FEOF > docker-compose-portsip-certmanager.yml
version: "3.9"

volumes:
  certmanager-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${data_path}/certmanager

services:
  # PortSIP Cert Manager
  certmanager:
    image: ${certmanager_img}
    command: ["/usr/local/bin/certmanager", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "portsip.certmanager"
    volumes:
      - certmanager-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: unless-stopped
FEOF

    echo "[configure] done"
    echo ""
}

initdt() {
    mkdir -p "$data_path"/certmanager/log

    chmod 755 "$data_path"/certmanager
    chmod 755 "$data_path"/certmanager/log
    chown 888:888 "$data_path"/certmanager
    chown 888:888 "$data_path"/certmanager/log
}

create() {
    echo ""
    echo "[run] try to create certmanager service"
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    set_firewall

    # remove command firstly
    shift

    while getopts p:i: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            i)
                certmanager_img=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$data_path" ]; then
        echo "[run] option -p not specified"
        exit -1
    fi
    if [ -z "$certmanager_img" ]; then
        echo "[run] option -i not specified"
        exit -1
    fi

    echo ""
    echo "[run] datapath       : $data_path"
    echo "[run] certmanager img: $certmanager_img"
    echo ""

    # write configure file
    cat << EOF > .configure_certmanager
CERTMANAGER_DATA_PATH=$data_path
CERTMANAGER_IMG=$certmanager_img
EOF

    # get product version
    docker image pull $certmanager_img
    version=$(export_certmanager_production_version)
    if [ -z "$version" ]; then
        echo "[run] not found label 'version' in certmanager docker image"
        exit -1
    fi
    echo "[run] certmanager version: $version"

    export_configure
    initdt

    # run certmanager service
    docker compose -f docker-compose-portsip-certmanager.yml up -d

    echo ""
    echo "[run] done"
    echo ""
}


status() {
    echo ""
    echo "[status] status service certmanager"
    echo ""
    docker compose -f docker-compose-portsip-certmanager.yml ls -a
    docker compose -f docker-compose-portsip-certmanager.yml ps -a
}

restart() {
    echo ""
    echo "[restart] restart service certmanager"
    echo ""
    docker compose -f docker-compose-portsip-certmanager.yml stop -t 300
    sleep 5
    docker compose -f docker-compose-portsip-certmanager.yml start
    exit 0
}

start() {
    echo ""
    echo "[start] start service certmanager"
    echo ""
    docker compose -f docker-compose-portsip-certmanager.yml start
}

stop() {
    echo ""
    echo "[stop] stop service certmanager"
    echo ""
    docker compose -f docker-compose-portsip-certmanager.yml stop -t 120
    exit 0
}

rm() {
    echo ""
    echo "[remove] remove service certmanager"
    echo ""

    docker compose -f docker-compose-portsip-certmanager.yml down

    docker volume rm `docker volume ls  -q | grep certmanager-data` || true
}

case $1 in
run)
    create $@
    ;;

restart)
    restart $@
    ;;

status)
    status $@
    ;;

stop)
    stop $@
    ;;

start)
    start $@
    ;;

rm)
    rm $@
    ;;

*)
    echo "[command] error command"
    ;;
esac
