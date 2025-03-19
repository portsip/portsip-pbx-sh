#!/usr/bin/env bash
set -e

if [ -z $1 ]; then 
    echo "[error]: unknown command"
    exit -1
fi

# -p
data_path=
# -a
local_ip_address=
# -x
pbx_ip_address=
# -i
pbx_img=
# -s
pbx_extend_svc_type=
# -n
pbx_extend_svc_name=

pbx_production_version=
pbx_extend_svc_datapath=

firewall_predfined_ports=
firewall_svc_name=

pbx_extend_svc_container_name=
pbx_exend_deploy_config_file=".configure_extend"

export_pbx_production_version() {
    local null_str=null
    local labels=$(docker image inspect --format='{{json .Config.Labels}}' $pbx_img)
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

is_pbx_production_version_less_than_22_0() {
    # x.y.z
    local v=$pbx_production_version

    set -f; IFS='.'
    set -- $v
    local x=$1; 
    local y=$2; 
    local z=$3
    set +f; unset IFS

    if [ $x -lt 22 ]; then
        echo 1
    else
        echo 0
    fi
}

# verify extend service type: queue-server-only,media-server-only,meeting-server-only,vr-server-only
verify_svc_type() {
    case "${pbx_extend_svc_type}" in
    queue-server-only)
        ;;
    media-server-only)
        ;;
    meeting-server-only)
        ;;
    vr-server-only)
        ;;
    *)
        echo "[error]: service type ${pbx_extend_svc_type} is not supported."
        echo "         only support queue-server-only,media-server-only,meeting-server-only,vr-server-only."
        exit -1
    esac
}

parse_cmd_parameters() {
    echo "[info]: args $@"
    
    while getopts p:a:x:i:s:n: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            a)
                local_ip_address=${OPTARG}
                ;;
            x)
                pbx_ip_address=${OPTARG}
                ;;
            i)
                pbx_img=${OPTARG}
                ;;
            s)
                pbx_extend_svc_type=${OPTARG}
                firewall_svc_name=${OPTARG}
                ;;
            n)
                pbx_extend_svc_name=${OPTARG}
                ;;
        esac
    done
}

verify_parameters() {
        # check parameters is exist
    if [ -z "$data_path" ]; then
        echo "[error]: option -p not specified"
        exit -1
    fi
    if [ -z "$local_ip_address" ]; then
        echo "[error]: option -a not specified"
        exit -1
    fi
    if [ -z "$pbx_ip_address" ]; then
        echo "[error]: option -x not specified"
        exit -1
    fi
    if [ -z "$pbx_img" ]; then
        echo "[error]: option -i not specified"
        exit -1
    fi
    if [ -z "$pbx_extend_svc_type" ]; then
        echo "[error]: option -s not specified"
        exit -1
    fi
    if [ -z "$pbx_extend_svc_name" ]; then
        echo "[error]: option -n not specified"
        exit -1
    fi

    verify_svc_type
}

export_configure() {
    local volume_name="$pbx_extend_svc_type"
    local extend_svc_name="$pbx_extend_svc_type"

    cat << VOLINITEOF > docker-compose.yml

volumes:
  ${volume_name}:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${pbx_extend_svc_datapath}

services:
VOLINITEOF

    case "${pbx_extend_svc_type}" in
    queue-server-only)
      cat << QUEUEEOF >> docker-compose.yml
  callqueue: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callqueue", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.callqueue"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
QUEUEEOF
        ;;

    media-server-only)
      cat << MEDIAEOF >> docker-compose.yml
  mediaserver:
    image: ${pbx_img}
    command: ["/usr/local/bin/mediaserver", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.mediaserver"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
MEDIAEOF
        ;;

    meeting-server-only)
      cat << MEETINGEOF >> docker-compose.yml
  conf: 
    image: ${pbx_img}
    command: ["/usr/local/bin/conf", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.conference"
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime     
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
MEETINGEOF
        ;;

    vr-server-only)
      cat << VREOF >> docker-compose.yml
  vr: 
    image: ${pbx_img}
    command: ["/usr/local/bin/vr", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.virtualreceptionist"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
VREOF
        ;;

    esac

    echo "[info]: dumped configure file 'docker-compose.yml'"
}

initdt() {
    mkdir -p $pbx_extend_svc_datapath/callqueue
    mkdir -p $pbx_extend_svc_datapath/dump
    mkdir -p $pbx_extend_svc_datapath/log
    mkdir -p $pbx_extend_svc_datapath/mcu/record

    chmod 755 $data_path
    chmod -R 755 $pbx_extend_svc_datapath
    chown -R 888:888 $pbx_extend_svc_datapath
}

configFirewallPorts(){
    case "${pbx_extend_svc_type}" in
    queue-server-only)
        firewall_predfined_ports="8916-8921/udp 8916-8921/tcp"
        ;;
    media-server-only)
        firewall_predfined_ports="35000-65000/udp 8840-8845/udp 8840-8845/tcp"
        ;;
    meeting-server-only)
        firewall_predfined_ports="8928-8933/udp 8928-8933/tcp"
        ;;
    vr-server-only)
        firewall_predfined_ports="8922-8927/udp 8922-8927/tcp"
        ;;
    esac
}

set_firewall(){
    configFirewallPorts
    echo ""
    echo "[info]: configure firewall"

    `systemctl stop ufw &> /dev/null` || true
    `systemctl disable ufw &> /dev/null` || true
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
    echo ""
    firewall-cmd --info-service=${firewall_svc_name}
}

config_sysctls() {

    cat << EOF > /etc/sysctl.d/ip_unprivileged_port_start.conf
net.ipv4.ip_unprivileged_port_start=0
EOF
    sysctl -p
    sysctl --system
}

create() {
    echo ""
    echo "[info]: try to create extend service"
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    parse_cmd_parameters $@
    verify_parameters

    set_firewall

    config_sysctls

    # change work directory
    if [ ! -d "./$pbx_extend_svc_type" ]; then
        mkdir $pbx_extend_svc_type
    fi
    cd $pbx_extend_svc_type

    echo "[info]: variables"
    echo ""
    echo "  datapath       : $data_path"
    echo "  ip(local)      : $local_ip_address"
    echo "  ip(pbx)        : $pbx_ip_address"
    echo "  pbx img        : $pbx_img"
    echo "  extend service : $pbx_extend_svc_type"
    echo "  extend name    : $pbx_extend_svc_name"
    echo ""

    # check if the data path exists
    pbx_extend_svc_datapath="$data_path/$pbx_extend_svc_type"
    if [ ! -d "$pbx_extend_svc_datapath" ]; then
        echo "[warn]: the current data path $pbx_extend_svc_datapath does not exist, try to create it"
        mkdir -p "$pbx_extend_svc_datapath"
        echo "[info]: $pbx_extend_svc_datapath created"
        echo ""
    fi

    # write configure file
    cat << EOF > .configure_extend
PBX_DATA_PATH=$data_path
IP_ADDRESS=$local_ip_address
PBX_IP_ADDRESS=$pbx_ip_address
PBX_IMG=$pbx_img
EXTEND_SVC_TYPE=$pbx_extend_svc_type
EXTEND_SVC_NAME=$pbx_extend_svc_name
EXTEND_SVC_DATAPATH=$pbx_extend_svc_datapath
EOF

    # get product version
    docker image pull $pbx_img
    pbx_production_version=$(export_pbx_production_version)
    if [ -z "$pbx_production_version" ]; then
        echo "[error]: no 'version' information found in the docker image"
        exit -1
    fi
    echo "[info]: current pbx version $pbx_production_version"
    # pbx >= 16.1
    local ret=$(is_pbx_production_version_less_than_22_0)
    # ret: 1 for success and 0 for failure
    if [ $ret -eq 1 ]; then
      echo "[error]: pbx version < 22.0.0"
      exit -1
    fi

    export_configure
    initdt

    # run pbx extend service
    docker compose -f docker-compose.yml up -d

    echo ""
    echo "[info]: created"
    echo ""
}

op() {
    #echo "$@"
    local operator=$1
    shift

    # parse parameters
    parse_cmd_parameters $@

    # check parameters is exist
    if [ -z "$pbx_extend_svc_type" ]; then
        echo "[error]: option -s not specified"
        exit -1
    fi
    # change work directory
    if [ ! -d "./$pbx_extend_svc_type" ]; then
        echo "[error]: no service configuration found"
        exit -1
    fi
    cd $pbx_extend_svc_type

    echo ""
    echo "[info]: ${operator} service $pbx_extend_svc_type"
    echo ""
  
    case $operator in
    restart)
        docker compose -f docker-compose.yml stop -t 300
        sleep 3
        docker compose -f docker-compose.yml start
        ;;

    status)
        docker compose -f docker-compose.yml ls -a
        docker compose -f docker-compose.yml ps -a
        ;;

    stop)
        docker compose -f docker-compose.yml stop -t 300
        ;;

    start)
        docker compose -f docker-compose.yml start
        ;;

    rm)
        firewall-cmd -q --permanent --delete-service=${pbx_extend_svc_type} || true
        firewall-cmd --reload
        #local volume_name="$pbx_extend_svc_type"
        docker compose -f docker-compose.yml down -v
        #docker volume rm `docker volume ls  -q | grep ${volume_name}` || true
        ;;
    *)
        echo "[error]: unknown command $operator"
        exit -1
    esac
}

disable_upgrade(){
    # disable unattended-upgrades
    systemctl stop unattended-upgrades  > /dev/null 2>&1 || true
    systemctl disable unattended-upgrades  > /dev/null 2>&1 || true
    systemctl mask unattended-upgrades  > /dev/null 2>&1 || true
    apt remove -y unattended-upgrades  > /dev/null 2>&1 || true

    #echo "removed unattended-upgrades"

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

    #echo "disabled apt-daily-upgrade apt-daily"
}

service_container_name(){
    case "${pbx_extend_svc_type}" in
    queue-server-only)
        pbx_extend_svc_container_name="portsip.callqueue"
        ;;
    media-server-only)
        pbx_extend_svc_container_name="portsip.mediaserver"
        ;;
    meeting-server-only)
        pbx_extend_svc_container_name="portsip.conference"
        ;;
    vr-server-only)
        pbx_extend_svc_container_name="portsip.virtualreceptionist"
        ;;
    *)
        echo "[error]: service type ${pbx_extend_svc_type} is not supported."
        exit -1
    esac
}

upgrade(){
    shift

    parse_cmd_parameters $@
    # check parameters is exist
    if [ -z "$pbx_extend_svc_type" ]; then
        echo "[error]: option -s not specified"
        exit -1
    fi
    verify_svc_type
    service_container_name
    
    # check the container exist
    docker inspect ${pbx_extend_svc_container_name} > /dev/null
    # change work directory
    if [ ! -d "./$pbx_extend_svc_type" ]; then
        echo ""
        echo "[error]: the resources that the $pbx_extend_svc_type service depends on are lost."
        echo ""
        exit -1
    fi
    cd $pbx_extend_svc_type

    if [ ! -f "$pbx_exend_deploy_config_file" ]; then 
        echo ""
        echo "[error]: the configures that the $pbx_extend_svc_type service depends on are lost."
        echo ""
        exit -1
    fi

    # read configures from .configure_im
    data_path=$(sed -n '/^PBX_DATA_PATH/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    local_ip_address=$(sed -n '/^IP_ADDRESS/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    pbx_ip_address=$(sed -n '/^PBX_IP_ADDRESS/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    used_pbx_img=$(sed -n '/^PBX_IMG/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    pbx_extend_svc_type=$(sed -n '/^EXTEND_SVC_TYPE/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    pbx_extend_svc_name=$(sed -n '/^EXTEND_SVC_NAME/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    pbx_extend_svc_datapath=$(sed -n '/^EXTEND_SVC_DATAPATH/p' ${pbx_exend_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')


    echo "[info]: variables"
    echo ""
    echo "  datapath       : $data_path"
    echo "  ip(local)      : $local_ip_address"
    echo "  ip(pbx)        : $pbx_ip_address"
    echo "  pbx img        : used/$used_pbx_img new/$pbx_img"
    echo "  extend service : $pbx_extend_svc_type"
    echo "  extend name    : $pbx_extend_svc_name"
    echo ""

    # remove container
    echo "[info]: start upgrade"
    docker compose -f docker-compose.yml down -v
    # remove docker image
    docker image rm -f $used_pbx_img > /dev/null 2>&1
    echo "[info]: the old service has been deleted"
    # re-create
    paras="-p ${data_path} -a $local_ip_address -x $pbx_ip_address -s $pbx_extend_svc_type -n $pbx_extend_svc_name"
    if [ -z $pbx_img ]; then
        pbx_img="$used_pbx_img"
    fi
    if [ -z $pbx_img ]; then
        echo "[error]: unknown the docker image of pbx"
        exit -1
    fi

    paras="$paras -i $pbx_img"
    command="create run $paras"
    $command

    echo ""
    echo "[info]: upgraded"
    echo ""
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
    ;;

*)
    echo "[error]: unknown command $1"
    ;;
esac