#!/usr/bin/env bash
set -e

firewall_svc_name="portsip-sbc"
firewall_predfined_ports="25000-34999/udp 5066/udp 5065/tcp 5067/tcp 5069/tcp 8882/tcp 8883/tcp 10443/tcp"

data_path=
sbc_img=
#Defaults to Docker Hub if no server is specified
docker_hub_registry=
#Authenticate to a registry.
docker_hub_username=
docker_hub_token=

if [ ! -d "./sbc" ]; then
    mkdir sbc
fi

deploy_config_file=".configure_sbc"

echo "[info]: starting..."

create_help() {
    echo  " command run options:"
    echo  "     -p <path>: required, sbc data path"
    echo  "     -i <docker image>: required, sbc docker image"
}

command_help() {
    echo  " use command:"
    echo  "     run"
    echo  "     status"
    echo  "     restart"
    echo  "     start"
    echo  "     stop"
    echo  "     rm"
}

if [ -z $1 ]; then 
    command_help
    exit 1
fi

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

create() {
    echo "[info]: try to create sbc service"

    cd sbc

    set_firewall

    config_sysctls

    # remove command firstly
    shift

    # parse parameters
    while getopts p:i:U:P:R: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            i)
                sbc_img=${OPTARG}
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

    # check parameters is exist
    if [ -z "$data_path" ]; then
        echo "[error]: data path(-p) not specified"
        create_help
        exit
    fi
    if [ -z "$sbc_img" ]; then
        echo "[error]: sbc docker image(-i) not specified"
        create_help
        exit
    fi

    if [ ! -z "$docker_hub_username" ] && [ ! -z "$docker_hub_token" ]; then
        echo "[info]: docker login -u $docker_hub_username $docker_hub_registry"
        docker login -u "$docker_hub_username" -p "$docker_hub_token" $docker_hub_registry
    fi

    echo  "[info]: use datapath $data_path, img $sbc_img"

    echo  "[info]: docker pull $sbc_img"
    docker pull $sbc_img > /dev/null

    # check datapath whether exist
    if [ ! -d "$data_path/sbc" ]; then
        echo  "[warn]: datapath $data_path/sbc not exist, try to reate it"
        mkdir -p $data_path/sbc
        echo  "[info]: $data_path created"
    fi

    # change directory mode
    chmod 755 $data_path

    # write configure file
    cat << EOF > .configure_sbc
SBC_DATA_PATH=$data_path
SBC_IMG=$sbc_img
HUB_USER=$docker_hub_username
HUB_SERVER=$docker_hub_registry
HUB_TOKEN=$docker_hub_token
EOF

    # run sbc service
    docker run -d \
        --name portsip.sbc \
        --restart=always \
        --cap-add=SYS_PTRACE \
        --network=host \
        -v $data_path/sbc:/var/lib/portsip/sbc \
        -v /etc/localtime:/etc/localtime:ro  \
        $sbc_img

    echo  "[info]: created"
}

status() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do 
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$service_name" ]; then
        echo "[info]: status all services"
        docker exec portsip.sbc supervisorctl status 
    else
        echo "[info]: status service $service_name"
        docker exec portsip.sbc supervisorctl status $service_name
    fi
}

restart() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do 
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$service_name" ]; then
        echo "[info]: restart all services"
        docker restart -t 300 portsip.sbc
        echo "[info]: all services restarted"
        exit
    fi

    echo "[info]: restart service $service_name"
    docker exec portsip.sbc supervisorctl restart $service_name
    echo "[info]: service $service_name restarted"
}

start() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do 
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$service_name" ]; then
        echo "[info]: start all services"
        docker start portsip.sbc
        echo "[info]: all services started"
    else
        echo "[info]: start service $service_name"
        docker exec portsip.sbc supervisorctl start $service_name
        echo "[info]: service $service_name started"
    fi
}

stop() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do 
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$service_name" ]; then
        echo "[info]: stop all services"
        docker stop -t 300 portsip.sbc
        echo "[info]: all services stopped"
        exit
    fi
    echo "[info]: stop service $service_name"
    docker exec portsip.sbc supervisorctl stop $service_name
    echo "[info]: service $service_name stopped"
}

rm() {
    # remove command firstly
    shift

    echo "[info]: remove service sbc"

    #firewall-cmd -q --permanent --delete-service=${firewall_svc_name} || true
    #firewall-cmd --reload
    docker stop -t 300 portsip.sbc
    docker rm -f portsip.sbc

    deploy_file=
    if [ -f "$deploy_config_file" ]; then 
        deploy_file=$deploy_config_file
    fi
    if [ -f "sbc/$deploy_config_file" ]; then 
        deploy_file="sbc/$deploy_config_file"
    fi

    if [ ! -f "$deploy_file" ]; then 
        echo "[info]: service removed"
        exit
    fi

    used_sbc_datapath=$(sed -n '/^SBC_DATA_PATH/p' ${deploy_file} | awk 'BEGIN{FS="="}{print $2}')
    echo "[info]: host bind-mount data preserved at $used_sbc_datapath after the teardown."
    echo "[info]: service removed"
}

upgrade(){
    shift

    new_sbc_img=

    # parse parameters
    while getopts i: option
    do 
        case "${option}" in
            i)
                new_sbc_img=${OPTARG}
                ;;
        esac
    done

    deploy_file=
    if [ -f "$deploy_config_file" ]; then 
        deploy_file=$deploy_config_file
    fi
    if [ -f "sbc/$deploy_config_file" ]; then 
        deploy_file="sbc/$deploy_config_file"
    fi

    if [ ! -f "$deploy_file" ]; then 
        echo "[error]: the configures that the sbc service depends on are lost."
        exit 1
    fi

    used_sbc_datapath=$(sed -n '/^SBC_DATA_PATH/p' ${deploy_file} | awk 'BEGIN{FS="="}{print $2}')
    used_sbc_img=$(sed -n '/^SBC_IMG/p' ${deploy_file} | awk 'BEGIN{FS="="}{print $2}')
    docker_hub_username=$(sed -n '/^HUB_USER/p' ${deploy_file} | awk 'BEGIN{FS="="}{print $2}')
    docker_hub_registry=$(sed -n '/^HUB_SERVER/p' ${deploy_file} | awk 'BEGIN{FS="="}{print $2}')
    docker_hub_token=$(sed -n '/^HUB_TOKEN/p' ${deploy_file} | awk 'BEGIN{FS="="}{print $2}')

    echo "[info]: sbc img : $used_sbc_img new/$new_sbc_img"
    echo "[info]: datapath: $used_sbc_datapath"

    if [ -z "$used_sbc_datapath" ]; then
        echo "[error]: data path not setup"
        exit 1
    fi

    sbc_img=$new_sbc_img
    if [ -z $sbc_img ]; then
        sbc_img=$used_sbc_img
    fi
    if [ -z $sbc_img ]; then
        echo "[error]: unknown sbc image"
        exit 1
    fi
    
    echo "[info]: start upgrade"
    if docker ps -a --format '{{.Names}}' | grep -qw 'portsip.sbc'; then
        # remove container
        rm none
    else
        echo "[info]: not found service"
    fi

    paras="-i $sbc_img -p $used_sbc_datapath"
    if [ ! -z $docker_hub_username ]; then
        paras="$paras -U $docker_hub_username"
    fi
    if [ ! -z $docker_hub_token ]; then
        paras="$paras -P $docker_hub_token"
    fi
    if [ ! -z $docker_hub_registry ]; then
        paras="$paras -R $docker_hub_registry"
    fi

    command="create run $paras"
    $command

    echo "[info]: upgraded"
}

remove_unused_imgs(){
    docker image prune -a --filter "label=product=SBC" -f  > /dev/null 2>&1 || true
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

upgrade)
    upgrade $@
    remove_unused_imgs
    ;;

*)
    command_help
    exit 1
    ;;
esac
