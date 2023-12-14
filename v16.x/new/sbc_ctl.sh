#!/usr/bin/env bash
set -e

firewall_svc_name="portsip-sbc"
firewall_predfined_ports="25000-35000/udp 5066/udp 5065/tcp 5067/tcp 5069/tcp 8882/tcp 8883/tcp 10443/tcp"

create_help() {
    echo
    echo  "\t command run options:"
    echo  "\t     -p <path>: required, sbc data path"
    echo  "\t     -i <docker image>: required, sbc docker image"
    echo
}

command_help() {
    echo
    echo  "\t use command:"
    echo  "\t     run"
    echo  "\t     status"
    echo  "\t     restart"
    echo  "\t     start"
    echo  "\t     stop"
    echo  "\t     rm"
    echo 
}

if [ -z $1 ];
then 
    command_help
    exit
fi

set_firewall(){
    echo ""
    echo "[firewall] Configure firewall"

    `systemctl stop ufw &> /dev/null` || true
    `systemctl disable ufw &> /dev/null` || true
    systemctl enable firewalld
    systemctl start firewalld
    echo "[firewall] enabled firewalld"

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
    echo "[firewall] info service ${firewall_svc_name}:"
    echo ""
    firewall-cmd --info-service=${firewall_svc_name}
    echo ""
    echo "[firewall] done"
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
    echo "==> try to create sbc service <=="
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
        echo  "\t data path(-p) not specified"
        create_help
        exit
    fi
    if [ -z "$sbc_img" ]; then
        echo  "\t sbc docker image(-i) not specified"
        create_help
        exit
    fi

    echo  "\t use datapath $data_path, img $sbc_img"
    echo ""

    docker pull $sbc_img

    # check datapath whether exist
    if [ ! -d "$data_path/sbc" ]; then
        echo  "\t datapath $data_path/sbc not exist, try to reate it"
        mkdir -p $data_path/sbc
        echo  "\t created"
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
    echo  "\t done"
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
        echo "status all services"
        echo ""
        docker exec portsip.sbc supervisorctl status 
    else
        echo ""
        echo "status service $service_name"
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
        echo "restart all services"
        echo ""
        docker restart -t 300 portsip.sbc
        exit
    fi

    echo ""
    echo "restart service $service_name"
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
        echo "start all services"
        echo ""
        docker start portsip.sbc
    else
        echo ""
        echo "start service $service_name"
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
        echo "stop all services"
        echo ""
        docker stop -t 300 portsip.sbc
        exit
    fi
    echo ""
    echo "stop service $service_name"
    echo ""
    docker exec portsip.sbc supervisorctl stop $service_name
}

rm() {
    # remove command firstly
    shift

    #firewall-cmd -q --permanent --delete-service=${firewall_svc_name} || true
    #firewall-cmd --reload
    docker stop -t 300 portsip.sbc
    docker rm -f portsip.sbc
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
    command_help
    ;;
esac

