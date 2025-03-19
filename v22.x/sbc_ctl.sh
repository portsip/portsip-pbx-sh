#!/usr/bin/env bash
set -e

firewall_svc_name="portsip-sbc"
firewall_predfined_ports="25000-34999/udp 5066/udp 5065/tcp 5067/tcp 5069/tcp 8882/tcp 8883/tcp 10443/tcp"

create_help() {
    echo
    echo  " command run options:"
    echo  "     -p <path>: required, sbc data path"
    echo  "     -i <docker image>: required, sbc docker image"
    echo
}

command_help() {
    echo
    echo  " use command:"
    echo  "     run"
    echo  "     status"
    echo  "     restart"
    echo  "     start"
    echo  "     stop"
    echo  "     rm"
    echo 
}

if [ -z $1 ];
then 
    command_help
    exit
fi

set_firewall(){
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
    echo "[info]: try to create sbc service"
    echo ""

    set_firewall

    config_sysctls

    # remove command firstly
    shift

    data_path=
    sbc_img=
    # parse parameters
    while getopts p:i: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            i)
                sbc_img=${OPTARG}
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

    echo  "[info]: use datapath $data_path, img $sbc_img"
    echo ""

    docker pull $sbc_img

    # check datapath whether exist
    if [ ! -d "$data_path/sbc" ]; then
        echo  "[warn]: datapath $data_path/sbc not exist, try to reate it"
        mkdir -p $data_path/sbc
        echo  "[info]: $data_path created"
        echo ""
    fi

    # change directory mode
    chmod 755 $data_path

    # write configure file
    cat << EOF > .configure_sbc
SBC_DATA_PATH=$data_path
SBC_IMG=$sbc_img
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

    echo ""
    echo  "[info]: created"
    echo ""
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
        echo ""
        echo "[info]: status all services"
        echo ""
        docker exec portsip.sbc supervisorctl status 
    else
        echo ""
        echo "[info]: status service $service_name"
        echo ""
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
        echo ""
        echo "[info]: restart all services"
        echo ""
        docker restart -t 300 portsip.sbc
        exit
    fi

    echo ""
    echo "[info]: restart service $service_name"
    echo ""
    docker exec portsip.sbc supervisorctl restart $service_name
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
        echo ""
        echo "[info]: start all services"
        echo ""
        docker start portsip.sbc
    else
        echo ""
        echo "[info]: start service $service_name"
        echo ""
        docker exec portsip.sbc supervisorctl start $service_name
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
        echo ""
        echo "[info]: stop all services"
        echo ""
        docker stop -t 300 portsip.sbc
        exit
    fi
    echo ""
    echo "[info]: stop service $service_name"
    echo ""
    docker exec portsip.sbc supervisorctl stop $service_name
}

rm() {
    # remove command firstly
    shift

    echo ""
    echo "[info]: remove service sbc"
    echo ""

    #firewall-cmd -q --permanent --delete-service=${firewall_svc_name} || true
    #firewall-cmd --reload
    docker stop -t 300 portsip.sbc
    docker rm -f portsip.sbc
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

    # check the container exist
    docker inspect portsip.sbc > /dev/null
    # get docker image id
    used_sbc_img=$(docker ps -a --filter "name=^portsip.sbc$" --format "{{.Image}}")
    echo "[info]: used/$used_sbc_img new/$new_sbc_img"
    # get data path
    used_sbc_datapath=$(docker inspect -f '{{range .Mounts}}{{if gt (len .Source) 4}}{{if eq (slice .Source (slice .Source 3|len)) "sbc"}}{{slice .Source 0 (slice .Source 4|len)}} {{end}}{{end}}{{end}}' portsip.sbc)
    if [ -z "$used_sbc_datapath" ]; then
        echo ""
        echo "[error]: data path is empty"
        echo ""
        exit -1
    fi
    
    # remove container
    docker stop -t 60 portsip.sbc > /dev/null 2>&1 || true
    docker rm -f portsip.sbc > /dev/null 2>&1
    # remove docker image
    docker image rm -f $used_sbc_img > /dev/null 2>&1
    # re-create
    echo ""
    echo "[info]: start upgrade"
    echo ""
    sbc_img=$new_sbc_img
    if [ -z $sbc_img ]; then
        sbc_img=$used_sbc_img
    fi
    if [ -z $sbc_img ]; then
        echo "[error]: unknown the docker image of sbc"
        exit -1
    fi
    create run -i $sbc_img -p $used_sbc_datapath
    echo ""
    echo "[info]: upgraded"
    echo ""
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
    ;;

*)
    command_help
    ;;
esac
