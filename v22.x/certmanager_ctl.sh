#!/usr/bin/env bash
set -e

if [ -z $1 ]; then 
    echo "[error]: unknown command"
    exit 1
fi

# -p
data_path=/var/lib/portsip

# -i
img=portsip/certmanager:22

firewall_svc_name="portsip-certmanager"
firewall_predfined_ports="443/tcp"
compose_file="docker-compose.yml"
extend_svc_type=certmanager-server-only

deploy_config_file=".configure_certmanager"

#Defaults to Docker Hub if no server is specified
docker_hub_registry=
#Authenticate to a registry.
docker_hub_username=
docker_hub_token=

export_production_version() {
    local null_str=null
    local labels=$(docker image inspect --format='{{json .Config.Labels}}' $img)
    if [ -z "$labels" ]; then
        return
    elif [ $labels = $null_str ]; then
        return
    fi
    cat << LEOF > labels.json
$labels
LEOF

    grep -o '"version":"[^"]*' labels.json | grep -o '[^"]*$'
}

is_production_version_less_than_22_4() {
    # x.y.z
    local v=$production_version

    set -f; IFS='.'
    set -- $v
    local x=$1; 
    local y=$2; 
    local z=$3
    set +f; unset IFS

    if [ $x -lt 22 ]; then
        echo 1
    fi

    if [ $x -gt 22 ]; then
        echo 0
    fi

    if [ $y -lt 4 ]; then
        echo 1
    else
        echo 0
    fi
}

parse_cmd_parameters() {
    echo "[info]: args $@"
    
    while getopts p:i:U:P:R: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            i)
                img=${OPTARG}
                ;;
            U)
                docker_hub_username=${OPTARG}
                ;;
            P)
                docker_hub_token=${OPTARG}
                ;;
            R)
                docker_hub_registry=${OPTARG}
                ;;
        esac
    done
}

verify_parameters() {
    # check parameters is exist
    if [ -z "$data_path" ]; then
        echo "[error]: Option -p not specified"
        exit 1
    fi

    if [ -z "$img" ]; then
        echo "[error]: Option -i not specified"
        exit 1
    fi

    echo "[info]: run as STANDALONE mode"
}

set_firewall(){
    echo "[info]: configure firewall"

    `systemctl stop ufw > /dev/null 2>&1` || true
    `systemctl disable ufw > /dev/null 2>&1` || true
    systemctl enable firewalld
    systemctl start firewalld
    echo "[info]: enabled firewalld"

    ports=
    pre_svc_exist=$(firewall-cmd --get-services | grep ${firewall_svc_name} | wc -l)
    if [ $pre_svc_exist -eq 1 ]; then
        ports="$(firewall-cmd --permanent --service=${firewall_svc_name} --get-ports)"
        firewall-cmd --reload > /dev/null
    fi
    firewall-cmd -q --permanent --zone=trusted --remove-interface=docker0 > /dev/null || true
    firewall-cmd -q --permanent --delete-service=${firewall_svc_name} > /dev/null || true

    firewall-cmd -q --permanent --add-service=ssh > /dev/null || true
    firewall-cmd -q --permanent --new-service=${firewall_svc_name} > /dev/null
    for fpp in $firewall_predfined_ports
    do
        firewall-cmd -q --permanent --service=${firewall_svc_name} --add-port=$fpp > /dev/null
    done
    if [ $pre_svc_exist -eq 1 ] ; then
        for port_rule in $ports
        do
            firewall-cmd -q --permanent --service=${firewall_svc_name} --add-port=$port_rule > /dev/null
        done
    fi
    firewall-cmd -q --permanent --add-service=${firewall_svc_name} > /dev/null
    firewall-cmd --reload > /dev/null
    systemctl restart firewalld
    echo "[info]: info firewalld service ${firewall_svc_name}:"
    firewall-cmd --service=${firewall_svc_name} --permanent --get-ports
}

config_sysctls() {
    cat << EOF > /etc/sysctl.d/ip_unprivileged_port_start.conf
net.ipv4.ip_unprivileged_port_start=0
EOF

    `sysctl -p > /dev/null 2>&1` || true
    `sysctl --system > /dev/null 2>&1` || true
}

export_configure() {
    cat << FEOF > ${compose_file}
volumes:
  cert-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${data_path}/${extend_svc_type}

services:
  # PortSIP Cert Manager
  certmanager:
    image: ${img}
    command: ["/usr/local/bin/certmanager", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "portsip.certmanager"
    volumes:
      - cert-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: unless-stopped
FEOF

    echo "[info]: dumped configure file '${compose_file}'"
}

initdt() {
    mkdir -p "$data_path"/${extend_svc_type}/log

    chmod 755 "$data_path"/${extend_svc_type}
    chmod 755 "$data_path"/${extend_svc_type}/log
    chown 888:888 "$data_path"/${extend_svc_type}
    chown 888:888 "$data_path"/${extend_svc_type}/log
}

create() {
    echo "[info]: try to create certmanager service"
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    set_firewall

    config_sysctls

    shift

    parse_cmd_parameters $@
    verify_parameters

    if [ ! -z "$docker_hub_username" ] && [ ! -z "$docker_hub_token" ]; then
        echo "[info]: docker login -u $docker_hub_username $docker_hub_registry"
        docker login -u "$docker_hub_username" -p "$docker_hub_token" $docker_hub_registry
    fi

    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        mkdir $extend_svc_type
    fi
    cd $extend_svc_type

    echo "[info]: variables"
    echo "datapath      : $data_path"
    echo "img           : $img"
    echo "hub user      : $docker_hub_username"
    echo "hub server    : $docker_hub_registry"

    # get product version
    docker image pull $img
    production_version=$(export_production_version)
    if [ -z "$production_version" ]; then
        echo "[error]: no 'version' information found in the docker image"
        exit 1
    fi
    echo "[info]: current version $production_version"

    local ret=$(is_production_version_less_than_22_4)
    # ret: 1 for success and 0 for failure
    if [ $ret -eq 1 ]; then
      echo "[error]: version $production_version < 22.4.0"
      exit 1
    fi

    # write configure file
    cat << EOF > ${deploy_config_file}
DATA_PATH=$data_path
IMG=$img
EXTEND_SVC_TYPE=$extend_svc_type
HUB_USER=$docker_hub_username
HUB_SERVER=$docker_hub_registry
HUB_TOKEN=$docker_hub_token
EOF

    initdt
    export_configure

    # run extend service
    docker compose -f ${compose_file} up -d > /dev/null

    echo "[info]: created"
}

op() {
    #echo "$@"
    local operator=$1
    shift

    # parse parameters
    parse_cmd_parameters $@

    # check parameters is exist
    if [ -z "$extend_svc_type" ]; then
        echo "[error]: certmanager not exist"
        exit 1
    fi
    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        echo "[error]: no service configuration found, not exist directory ${extend_svc_type}"
        exit 1
    fi
    cd $extend_svc_type

    echo "[info]: ${operator} service $extend_svc_type"
  
    case $operator in
    restart)
        docker compose -f ${compose_file} stop -t 300 > /dev/null
        sleep 3
        docker compose -f ${compose_file} start > /dev/null
        echo "[info]: service restarted"
        ;;

    status)
        docker compose -f ${compose_file} ls -a
        docker compose -f ${compose_file} ps -a
        ;;

    stop)
        docker compose -f ${compose_file} stop -t 300 > /dev/null
        echo "[info]: service stopped"
        ;;

    start)
        docker compose -f ${compose_file} start > /dev/null
        echo "[info]: service started"
        ;;

    rm)
        dpath=$(sed -n '/^DATA_PATH/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
        docker compose -f ${compose_file} down -v > /dev/null
        echo "[info]: host bind-mount data preserved at $dpath after the teardown."
        echo "[info]: service removed"
        ;;
    
    *)
        echo "[error]: unknown command $operator"
        exit 1
        ;;
    esac
}

upgrade(){
    shift

    new_img=

    # parse parameters
    while getopts i: option
    do 
        case "${option}" in
            i)
                new_img=${OPTARG}
                ;;
        esac
    done

    # check the container exist
    # docker inspect portsip.certmanager > /dev/null
    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        echo "[error]: required configuration directory(${extend_svc_type}) are missing."
        exit 1
    fi
    cd $extend_svc_type

    if [ ! -f "$deploy_config_file" ]; then 
        echo "[error]: required configuration file(${deploy_config_file}) are missing."
        exit 1
    fi

    # read configures from configure file
    data_path=$(sed -n '/^DATA_PATH/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    img=$(sed -n '/^IMG/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    docker_hub_username=$(sed -n '/^HUB_USER/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    docker_hub_registry=$(sed -n '/^HUB_SERVER/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    docker_hub_token=$(sed -n '/^HUB_TOKEN/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')

    echo "[info]: variables"
    echo "datapath        : $data_path"
    echo "img             : $img new/$new_img"

    echo "[info]: start upgrade"
    if docker ps -a --format '{{.Names}}' | grep -qw 'portsip.certmanager'; then
        # remove container
        docker compose -f ${compose_file} down -v > /dev/null
    else
        echo "[info]: not found service $extend_svc_type"
    fi
    # remove docker image
    # docker image rm -f $img > /dev/null 2>&1
    echo "[info]: the old service has been deleted"
    # re-create
    paras="-p ${data_path}"
    if [ ! -z "$new_img" ]; then
        img="$new_img"
    fi
    if [ -z $img ]; then
        echo "[error]: unknown the service image"
        exit 1
    fi
    paras="$paras -i $img"
    if [ ! -z $docker_hub_username ]; then
        paras="$paras -U $docker_hub_username"
    fi
    if [ ! -z $docker_hub_token ]; then
        paras="$paras -P $docker_hub_token"
    fi
    if [ ! -z $docker_hub_registry ]; then
        paras="$paras -R $docker_hub_registry"
    fi

    cd ../
    command="create run $paras"
    $command

    echo "[info]: upgraded"
}

remove_unused_imgs(){
    docker image prune -a --filter "label=product=CERT" -f  > /dev/null 2>&1 || true
}

disable_upgrade(){
    # disable unattended-upgrades
    systemctl stop unattended-upgrades  > /dev/null 2>&1 || true
    systemctl disable unattended-upgrades  > /dev/null 2>&1 || true
    systemctl mask unattended-upgrades  > /dev/null 2>&1 || true
    apt remove -y unattended-upgrades  > /dev/null 2>&1 || true

    #echo "[info]: removed unattended-upgrades"

    # disable  apt daily
    systemctl stop apt-daily.timer  > /dev/null 2>&1 || true
    systemctl stop apt-daily.service  > /dev/null 2>&1 || true
    systemctl disable apt-daily.timer  > /dev/null 2>&1 || true
    systemctl disable apt-daily.service  > /dev/null 2>&1 || true
    systemctl mask apt-daily.service  > /dev/null 2>&1 || true

    # disable  apt upgrade
    systemctl stop apt-daily-upgrade.timer  > /dev/null 2>&1 || true
    systemctl stop apt-daily-upgrade.service  > /dev/null 2>&1 || true
    systemctl disable apt-daily-upgrade.timer  > /dev/null 2>&1 || true
    systemctl disable apt-daily-upgrade.service  > /dev/null 2>&1 || true
    systemctl mask apt-daily-upgrade.service  > /dev/null 2>&1 || true

    #echo "[info]: disabled apt-daily-upgrade apt-daily"
}

if grep -q "Ubuntu" /etc/os-release; then
    disable_upgrade
elif grep -q "Debian" /etc/os-release; then
    disable_upgrade
fi

echo "[warn]: disabled system auto update"

case $1 in
run)
    create $@
    ;;

restart)
    op $@
    ;;

status)
    op $@
    ;;

stop)
    op $@
    ;;

start)
    op $@
    ;;

rm)
    op $@
    ;;

upgrade)
    upgrade $@
    remove_unused_imgs
    ;;

*)
    echo "[error]: unknown command $1"
    exit 1
    ;;
esac
