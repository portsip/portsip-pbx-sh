#!/usr/bin/env bash
set -e

if [ -z $1 ];
then 
    echo -e "\t => need parameters <="
    exit -1
fi

if [ ! -d "./pbx" ]; then
    mkdir pbx
fi

cd pbx

# $1: pbx_data_path
# $2: pbx_ip_address
# $3: pbx_img
# $4: pbx_db_img
# $5: pbx_db_password
export_configure() {
    echo ""
    echo -e "\t => export configure file 'docker-compose-portsip-pbx.yml' <="
    echo ""

    pbx_data_path=$1
    pbx_ip_address=$2
    pbx_img=$3
    pbx_db_img=$4
    pbx_db_password=$5

    cat << FEOF > docker-compose-portsip-pbx.yml
version: "3.9"
services:
  database:
    image: ${pbx_db_img}
    network_mode: host
    user: root
    container_name: "portsip.database"
    volumes:
      - /etc/localtime:/etc/localtime
      - pbx-db:/var/lib/postgresql/data
    environment:
      - PGDATA=/var/lib/postgresql/data
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${pbx_db_password}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --auth=md5 --auth-host=md5 --data-checksums
      - POSTGRES_HOST_AUTH_METHOD=md5
    restart: on-failure:3
    healthcheck:
      test: [ "CMD", "pg_isready", "-h", "localhost", "-p", "5432", "-U", "postgres" ]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

  initdt:
    image: ${pbx_img}
    command: [ "/usr/local/bin/initdt.sh", "-D", "/var/lib/portsip/pbx", "--pg-superuser-name", "postgres",  "--pg-superuser-password", "${pbx_db_password}" ]
    network_mode: host
    user: root
    container_name: "portsip.initdt"
    volumes:
      - /etc/localtime:/etc/localtime
      - pbx-data:/var/lib/portsip/pbx
    depends_on:
      database:
        condition: service_healthy

  nats: 
    image: ${pbx_img}
    command: ["/usr/local/bin/nats-server", "--log", "/var/lib/portsip/pbx/log/nats.log", "--http_port", "8222"]
    network_mode: host
    user: portsip
    container_name: "portsip.nats"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: on-failure:3
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8222"]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s
    depends_on:
      initdt:
        condition: service_completed_successfully

  callmanager: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callmanager", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.callmanager"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
      - IP_ADDRESS=${pbx_ip_address}
      - LD_PRELOAD=/usr/local/lib/libmimalloc.so
      - MIMALLOC_PAGE_RESET=1
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  mediaserver: 
    image: ${pbx_img}
    command: ["/usr/local/bin/mediaserver", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.mediaserver"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
      - IP_ADDRESS=${pbx_ip_address}
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  gateway: 
    image: ${pbx_img}
    command:  ["/usr/local/bin/apigate", "serve", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "portsip.gateway"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  websvc: 
    image: ${pbx_img}
    command: ["/usr/sbin/nginx", "-c", "/etc/nginx/nginx.conf"]
    network_mode: host
    #user: www-data
    container_name: "portsip.webserver"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      gateway:
        condition: service_started

  wsspublisher: 
    image: ${pbx_img}
    command: ["/usr/local/bin/wsspublisher", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.wsspublisher"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  voicemail: 
    image: ${pbx_img}
    command: ["/usr/local/bin/voicemail", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.voicemail"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  vr: 
    image: ${pbx_img}
    command: ["/usr/local/bin/vr", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.virtualreceptionist"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP Notification Center
  notifycenter: 
    image: ${pbx_img}
    command: ["/usr/local/bin/notifycenter", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "portsip.notificationcenter"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP Provision Sever
  prvserver: 
    image: ${pbx_img}
    command: ["/usr/local/bin/prvserver", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.provision"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP Conference Server
  conf: 
    image: ${pbx_img}
    command: ["/usr/local/bin/conf", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.conference"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP Call Queue Server
  callqueue: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callqueue", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.callqueue"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP Call Park Server
  callpark: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callpark", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.callpark"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP Announcement Server
  anncmnt: 
    image: ${pbx_img}
    command: ["/usr/local/bin/anncmnt", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.announcement"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: on-failure:3
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

volumes:
  pbx-db:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${pbx_data_path}/postgresql
  pbx-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${pbx_data_path}/pbx
FEOF
    echo ""
    echo -e "\t => configure file done <="
    echo ""
    echo ""
}

create() {
    echo ""
    echo "==> try to create pbx service <=="
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    data_path=
    ip_address=
    pbx_img=
    db_listen_address=0.0.0.0
    db_img="portsip/postgresql:14"
    #  generate db password
    db_password=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20`
    # parse parameters
    while getopts p:a:i:d: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            a)
                ip_address=${OPTARG}
                ;;
            i)
                pbx_img=${OPTARG}
                ;;
            d)
                db_img=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$data_path" ]; then
        echo -e "\t Option -p not specified"
        exit -1
    fi
    if [ -z "$ip_address" ]; then
        echo -e "\t Option -a not specified"
        exit -1
    fi
    if [ -z "$pbx_img" ]; then
        echo -e "\t Option -i not specified"
        exit -1
    fi

    if [ -z "$db_img" ]; then
        echo -e "\t Option -d not specified"
        exit -1
    fi

    if [ -f $data_path/pbx/system.ini ] 
    then
        db_password=`sed -nr "/^\[database\]/ { :l /^superuser_password[ ]*=/ { s/[^=]*=[ ]*//; p; q;}; n; b l;}" $data_path/pbx/system.ini`
    fi
    if [ -z "$db_password" ]; then
        echo -e "\t Password is empty"
        exit -1
    fi

    echo -e "\t use datapath $data_path, ip $ip_address, img $pbx_img, db img $db_img"
    echo ""

    # check datapath whether exist
    if [ ! -d "$data_path/pbx" ]; then
        echo -e "\t datapath $data_path/pbx not exist, try to reate it"
        mkdir -p $data_path/pbx
        echo -e "\t created"
        echo ""
    fi

    # check db datapath whether exist
    if [ ! -d "$data_path/postgresql" ]; then
        echo ""
        echo -e "\t db datapath $data_path/postgresql not exist, try to reate it"
        mkdir -p $data_path/postgresql
        echo -e "\t created"
        echo ""
    fi

    # change directory mode
    chmod 755 $data_path

    # write configure file
    cat << EOF > .configure_pbx
PBX_DATA_PATH=$data_path
IP_ADDRESS=$ip_address
PBX_IMG=$pbx_img
PBX_DB_IMG=$db_img
DB_PASSWORD=$db_password
EOF

    export_configure $data_path $ip_address $pbx_img $db_img $db_password
    # run pbx service
    docker compose -f docker-compose-portsip-pbx.yml up -d

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
        docker compose -f docker-compose-portsip-pbx.yml ls -a
        docker compose -f docker-compose-portsip-pbx.yml ps -a
    else
        echo ""
        echo "status service $service_name"
        echo ""
        docker compose -f docker-compose-portsip-pbx.yml ps $service_name
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
        docker compose -f docker-compose-portsip-pbx.yml restart
        exit 0
    fi

    echo ""
    echo "restart service $service_name"
    echo ""
    case $service_name in
    database)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 100
        docker compose -f docker-compose-portsip-pbx.yml start
        ;;

    nats)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 100
        docker compose -f docker-compose-portsip-pbx.yml start
        ;;

    *)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 100 $service_name
        docker compose -f docker-compose-portsip-pbx.yml start $service_name
        ;;
    esac
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
        docker compose -f docker-compose-portsip-pbx.yml start
    else
        echo ""
        echo "start service $service_name"
        echo ""
        docker compose -f docker-compose-portsip-pbx.yml start $service_name
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
        docker compose -f docker-compose-portsip-pbx.yml stop
        exit 0
    fi
    echo ""
    echo "stop service $service_name"
    echo ""
    case $service_name in
    database)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 100
        ;;

    nats)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 100
        ;;

    *)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 100 $service_name
        ;;
    esac
}

rm() {
    # remove command firstly
    shift

    # remove_data=false

    # # parse parameters
    # while getopts f option
    # do 
    #     case "${option}" in
    #         f)
    #             remove_data=true
    #             ;;
    #     esac
    # done

    docker compose -f docker-compose-portsip-pbx.yml down

    docker volume rm `docker volume ls  -q | grep pbx-data` || true
    docker volume rm `docker volume ls  -q | grep pbx-db` || true
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

