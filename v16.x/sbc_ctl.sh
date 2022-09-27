#!/usr/bin/env bash
set -e

if [ -z $1 ];
then 
    echo -e "\t => need parameters <="
    exit -1
fi

if [ ! -d "./sbc" ]; then
    mkdir sbc
fi

cd sbc

# $1: sbc_data_path
# $2: sbc_img
export_configure() {
    echo ""
    echo -e "\t => export configure file 'docker-compose-portsip-sbc.yml' <="
    echo ""

    sbc_data_path=$1
    sbc_img=$2

    cat << FEOF > docker-compose-portsip-sbc.yml
version: "3.9"
services:  
  initdt:
    image: ${sbc_img}
    command: [ "/usr/local/bin/initdt.sh"]
    network_mode: host
    user: root
    container_name: "PortSIP.SBC.Initdt"
    volumes:
      - /etc/localtime:/etc/localtime
      - sbc-data:/var/lib/portsip/sbc

  sbc: 
    image: ${sbc_img}
    command: ["/usr/local/bin/portsbc", "-D","/var/lib/portsip/sbc", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.SBC"
    volumes:
      - sbc-data:/var/lib/portsip/sbc
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
      - LD_PRELOAD=/usr/local/lib/libmimalloc.so
      - MIMALLOC_PAGE_RESET=1
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully

  websvc: 
    image: ${sbc_img}
    command: ["/usr/sbin/nginx", "-c", "/etc/nginx/nginx.conf"]
    network_mode: host
    #user: www-data
    container_name: "PortSIP.SBC.Admin"
    volumes:
      - sbc-data:/var/lib/portsip/sbc
      - /etc/localtime:/etc/localtime
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully

volumes:
  sbc-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${sbc_data_path}/sbc
FEOF
    echo ""
    echo -e "\t => configure file done <="
    echo ""
    echo ""
}

create() {
    echo ""
    echo "==> try to create sbc service <=="
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

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
        echo -e "\t Option data path(-p) not specified"
        exit -1
    fi
    if [ -z "$sbc_img" ]; then
        echo -e "\t Option sbc docker image(-i) not specified"
        exit -1
    fi

    echo -e "\t use datapath $data_path, ip $ip_address, img $sbc_img"
    echo ""

    # check datapath whether exist
    if [ ! -d "$data_path/sbc" ]; then
        echo -e "\t datapath $data_path/sbc not exist, try to reate it"
        mkdir -p $data_path/sbc
        echo -e "\t created"
        echo ""
    fi

    # change directory mode
    chmod 755 $data_path

    # write configure file
    cat << EOF > .configure_sbc
SBC_DATA_PATH=$data_path
SBC_IMG=$sbc_img
EOF

    export_configure $data_path $sbc_img

    # run sbc service
    docker compose -f docker-compose-portsip-sbc.yml up -d

    echo ""
    echo -e "\t done"
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
        docker compose -f docker-compose-portsip-sbc.yml ls -a
        docker compose -f docker-compose-portsip-sbc.yml ps -a
    else
        echo ""
        echo "status service $service_name"
        echo ""
        docker compose -f docker-compose-portsip-sbc.yml ps $service_name
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
        docker compose -f docker-compose-portsip-sbc.yml restart
        exit 0
    fi

    echo ""
    echo "restart service $service_name"
    echo ""
    docker compose -f docker-compose-portsip-sbc.yml stop -t 100 $service_name
    docker compose -f docker-compose-portsip-sbc.yml start $service_name
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
        docker compose -f docker-compose-portsip-sbc.yml start
    else
        echo ""
        echo "start service $service_name"
        echo ""
        docker compose -f docker-compose-portsip-sbc.yml start $service_name
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
        docker compose -f docker-compose-portsip-sbc.yml stop
        exit 0
    fi
    echo ""
    echo "stop service $service_name"
    echo ""
    docker compose -f docker-compose-portsip-sbc.yml stop -t 100 $service_name
}

rm() {
    # remove command firstly
    shift

    docker compose -f docker-compose-portsip-sbc.yml down

    docker volume rm `docker volume ls  -q | grep sbc-data` || true
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
    echo -e "\t error command"
    ;;
esac

