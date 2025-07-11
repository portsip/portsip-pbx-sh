#!/usr/bin/env bash
set -e

firewall_svc_name="portsip-pbx"
firewall_predfined_ports="8887-8889/tcp 8885/tcp 4222/tcp 80/tcp 443/tcp 5060/udp 5061/tcp 5063/tcp 45000-65000/udp"

if [ -z $1 ];
then 
    echo "[error]: unknown command"
    exit -1
fi

if [ ! -d "./pbx" ]; then
    mkdir pbx
fi

pbx_deploy_config_file=".configure_pbx"

#Defaults to Docker Hub if no server is specified
docker_hub_registry=
#Authenticate to a registry.
docker_hub_username=
docker_hub_token=

cd pbx

echo "[info]: Starting..."

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
        for pts in $ports
        do
            firewall-cmd -q --permanent --service=${firewall_svc_name} --add-port=$pts > /dev/null
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

export_pbx_production_version() {
    local pbx_img=$1
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
    local v=$1

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

svc_name() {
    case $1 in
    portsip.database)
        echo "database"
        ;;

    portsip.initdt)
        echo "initdt"
        ;;

    portsip.nats)
        echo "nats"
        ;;

    portsip.callmanager)
        echo "callmanager"
        ;;

    portsip.mediaserver)
        echo "mediaserver"
        ;;

    portsip.gateway)
        echo "gateway"
        ;;

    portsip.webserver)
        echo "websvc"
        ;;

    portsip.wsspublisher)
        echo "wsspublisher"
        ;;

    portsip.voicemail)
        echo "voicemail"
        ;;

    portsip.virtualreceptionist)
        echo "vr"
        ;;

    portsip.notificationcenter)
        echo "notifycenter"
        ;;

    portsip.provision)
        echo "prvserver"
        ;;

    portsip.conference)
        echo "conf"
        ;;

    portsip.callqueue)
        echo "callqueue"
        ;;

    portsip.callpark)
        echo "callpark"
        ;;

    portsip.announcement)
        echo "anncmnt"
        ;;

    portsip.loadbalancer)
        echo "loadbalancer"
        ;;

    portsip.databoard)
        echo "databoard"
        ;;

    *)
        echo $1
        ;;
    esac
}

# $1: pbx_data_path
# $2: pbx_ip_address
# $3: pbx_img
# $4: pbx_db_img
# $5: pbx_db_password
export_configure() {
    local pbx_data_path=$1
    local pbx_ip_address=$2
    local pbx_img=$3
    local pbx_db_img=$4
    local pbx_db_password=$5
    local pbx_product_version=$6

    local webserver_command="\"/usr/sbin/nginx\", \"-c\", \"/etc/nginx/nginx.conf\""

    # pbx >= 22.0
    local ret=$(is_pbx_production_version_less_than_22_0 $pbx_product_version)
    # ret: 1 for success and 0 for failure
    if [ $ret -eq 0 ]; then
        webserver_command="\"/usr/local/bin/websrv\", \"serve\", \"-n\", \"websrv\", \"-D\",\"/var/lib/portsip/pbx\""
    fi

    cat << FEOF > docker-compose-portsip-pbx.yml
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

    if [ ! -z "$storage" ]; then 
      cat << FEOF >> docker-compose-portsip-pbx.yml
  pbx-storage-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${storage}

FEOF
    fi

    cat << FEOF >> docker-compose-portsip-pbx.yml
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
    restart: unless-stopped
    healthcheck:
      test: [ "CMD", "pg_isready", "-h", "localhost", "-p", "5432", "-U", "postgres" ]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

  nats: 
    image: ${pbx_img}
    command: ["/usr/local/bin/nats-server", "--log", "/var/lib/portsip/pbx/log/nats.log", "--http_port", "8222"]
    network_mode: host
    user: portsip
    container_name: "portsip.nats"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8222"]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

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
      - LD_PRELOAD=/usr/local/lib/libmimalloc.so.2
      - MIMALLOC_PAGE_RESET=1
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  websvc: 
    image: ${pbx_img}
    command: [${webserver_command}]
    network_mode: host
    #user: www-data
    container_name: "portsip.webserver"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: unless-stopped
    depends_on:
      nats:
        condition: service_healthy
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
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
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
      - LD_PRELOAD=/usr/local/lib/libmimalloc.so
      - MIMALLOC_PAGE_RESET=1
      - MIMALLOC_SHOW_STATS=1
      - MIMALLOC_VERBOSE=1
      - MIMALLOC_SHOW_ERRORS=1
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
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
    restart: unless-stopped
    depends_on:
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  # PortSIP loadbalancer
  loadbalancer: 
    image: ${pbx_img}
    command: ["/usr/local/bin/loadbalancer", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "portsip.loadbalancer"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
    depends_on:
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Data Board
  databoard: 
    image: ${pbx_img}
    command: ["node", "server.js", "/var/lib/portsip/pbx"]
    network_mode: host
    environment:
      - PORT=8890
      - HOSTNAME=0.0.0.0
    user: portsip
    container_name: "portsip.databoard"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    working_dir: /usr/share/nginx/html/databoard
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
    depends_on:
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
      callmanager:
        condition: service_started

  gateway: 
    image: ${pbx_img}
    command:  ["/usr/local/bin/apigate", "serve", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "portsip.gateway"
    restart: unless-stopped
    depends_on:
      nats:
        condition: service_healthy
      database:
        condition: service_healthy
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
FEOF

    if [ ! -z "$storage" ]; then 
      cat << FEOF >> docker-compose-portsip-pbx.yml
      - pbx-storage-data:/var/lib/portsip/pbx/storage
FEOF
    fi

    echo "[info]: dumped configure file 'docker-compose-portsip-pbx.yml'"
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
        docker compose -f docker-compose-portsip-pbx.yml ls -a
        docker compose -f docker-compose-portsip-pbx.yml ps -a
    else
        service_name=$(svc_name $service_name)
        echo "[info]: status service $service_name"
        docker compose -f docker-compose-portsip-pbx.yml ps $service_name
    fi
}

restart() {
    # remove command firstly
    shift

    local service_name=

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
        docker compose -f docker-compose-portsip-pbx.yml stop -t 300
        sleep 10
        docker compose -f docker-compose-portsip-pbx.yml start
        exit 0
    fi

    service_name=$(svc_name $service_name)
    echo "[info]: restart service $service_name"
    case $service_name in
    database)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 300
        sleep 10
        docker compose -f docker-compose-portsip-pbx.yml start
        ;;

    nats)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 300
        sleep 10
        docker compose -f docker-compose-portsip-pbx.yml start
        ;;

    *)
        docker compose -f docker-compose-portsip-pbx.yml stop -t 300 $service_name
        sleep 1
        docker compose -f docker-compose-portsip-pbx.yml start $service_name
        ;;
    esac
}

start() {
    # remove command firstly
    shift

    local service_name=

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
        docker compose -f docker-compose-portsip-pbx.yml start
    else
        service_name=$(svc_name $service_name)
        echo "[info]: start service $service_name"
        docker compose -f docker-compose-portsip-pbx.yml start $service_name
    fi
}

stop() {
    # remove command firstly
    shift

    local service_name=

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
        docker compose -f docker-compose-portsip-pbx.yml stop
        exit 0
    fi
    service_name=$(svc_name $service_name)
    echo "[info]: stop service $service_name"
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
    # shift

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

    #firewall-cmd -q --permanent --delete-service=${firewall_svc_name} || true
    #firewall-cmd --reload
    echo "[info]: remove pbx service"
    docker compose -f docker-compose-portsip-pbx.yml down  -v
    echo "[info]: removed"

    #docker volume rm `docker volume ls  -q | grep pbx-data` || true
    #docker volume rm `docker volume ls  -q | grep pbx-db` || true
}

# init or upgrade
# $1: pbx_data_path
# $2: pbx_ip_address
# $3: pbx_img
# $4: pbx_db_img
# $5: pbx_db_password
export_configure_crt_or_up() {
    local pbx_data_path=$1
    local pbx_ip_address=$2
    local pbx_img=$3
    local pbx_db_img=$4
    local pbx_db_password=$5
    local pbx_product_version=$6

    cat << FEOF > docker-compose-portsip-pbx-init.yml

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
    restart: unless-stopped
    healthcheck:
      test: [ "CMD", "pg_isready", "-h", "localhost", "-p", "5432", "-U", "postgres" ]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

  initdt:
    image: ${pbx_img}
    command: [ "sleep", "infinity" ]
    network_mode: host
    user: root
    container_name: "portsip.initdt"
    volumes:
      - /etc/localtime:/etc/localtime
      - pbx-data:/var/lib/portsip/pbx
    depends_on:
      database:
        condition: service_healthy

FEOF

    echo "[info]: dumped init configure file 'docker-compose-portsip-pbx-init.yml'"
}

create() {
    #remove old
    #echo "[run] stop and remove old pbx"
    #rm

    # init or upgrade pbx
    echo "[info]: try to deploy pbx service"
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    set_firewall

    config_sysctls

    # remove command firstly
    shift

    local storage=
    local data_path=
    local ip_address=
    local pbx_img=
    local db_listen_address=0.0.0.0
    local db_img="portsip/postgresql:14.12"
    #  generate db password
    local db_password=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20`
    local pbx_pre_version=
    local pbx_new_version=
    # parse parameters
    while getopts p:a:i:d:f:U:P:R: option
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
            f)
                storage=${OPTARG}
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
        echo "[error]: option -p not specified"
        exit -1
    fi
    if [ -z "$ip_address" ]; then
        echo "[error]: option -a not specified"
        exit -1
    fi
    if [ -z "$pbx_img" ]; then
        echo "[error]: option -i not specified"
        exit -1
    fi

    if [ -z "$db_img" ]; then
        echo "[error]: option -d not specified"
        exit -1
    fi

    if [ ! -z "$docker_hub_username" ] && [ ! -z "$docker_hub_token" ]; then
        echo "[info]: docker login -u $docker_hub_username $docker_hub_registry"
        docker login -u "$docker_hub_username" -p "$docker_hub_token" $docker_hub_registry
    fi

    # check datapath whether exist
    if [ ! -d "$data_path/pbx" ]; then
        echo "[warn]: datapath $data_path/pbx not exist, try to create it"
        mkdir -p $data_path/pbx
        echo "[info]: $data_path created"
    fi

    # check db datapath whether exist
    if [ ! -d "$data_path/postgresql" ]; then
        echo "[warn]: db datapath $data_path/postgresql not exist, try to create it"
        mkdir -p $data_path/postgresql
        echo "[info]: $data_path created"
    fi

    # check storage datapath whether exist
    if [ ! -z "$storage" ]; then
      if [ ! -d "$storage" ]; then
          echo "[error]: storage datapath $storage not exist, exit"
          exit -1
      else
          chmod 755 "$storage"
          chown 888:888 "$storage"
      fi
    fi

    # read database password if exist
    if [ -f $data_path/pbx/system.ini ] 
    then
        db_password=`sed -nr "/^\[database\]/ { :l /^superuser_password[ ]*=/ { s/[^=]*=[ ]*//; p; q;}; n; b l;}" $data_path/pbx/system.ini`
    fi

    if [ -z "$db_password" ]; then
        echo "[error]: empty database password"
        exit -1
    fi

    if [ -f $data_path/pbx/VERSION ]; then
        pbx_pre_version=`head -n 1 $data_path/pbx/VERSION`
    fi

    echo "[info]: variables"
    echo "    datapath: $data_path"
    echo "    ip      : $ip_address"
    echo "    pbx  img: $pbx_img"
    echo "    db   img: $db_img"
    echo "     storage: $storage"
    echo "    hub user: $docker_hub_username"
    echo "  hub server: $docker_hub_registry"

    # change directory mode
    chmod 755 $data_path

    # write configure file
    cat << EOF > .configure_pbx
PBX_DATA_PATH=$data_path
IP_ADDRESS=$ip_address
PBX_IMG=$pbx_img
PBX_DB_IMG=$db_img
DB_PASSWORD=$db_password
STORAGE=$storage
HUB_USER=$docker_hub_username
HUB_SERVER=$docker_hub_registry
EOF

    # get product version
    echo "[info]: docker pull $pbx_img"
    docker image pull $pbx_img > /dev/null
    pbx_new_version=$(export_pbx_production_version $pbx_img)
    if [ -z "$pbx_new_version" ]; then
        echo "[error]: not found label 'version' in the pbx image"
        exit -1
    fi

    if [ -z "$pbx_pre_version" ]; then
        echo "[info]: try to create pbx"
    else
        echo "[info]: upgrade from $pbx_pre_version to $pbx_new_version"
    fi

    # init or upgrade data
    export_configure_crt_or_up $data_path $ip_address $pbx_img $db_img $db_password $pbx_new_version
    set +e
    docker compose -f docker-compose-portsip-pbx-init.yml down -v || true
    docker compose -f docker-compose-portsip-pbx-init.yml up -d --wait
    local crtOrUpRetEnv=$?
    if [ $crtOrUpRetEnv -ne 0 ]; then
        docker compose -f docker-compose-portsip-pbx-init.yml down -v
        echo "[error]: init or upgrade env"
        exit -1
    fi
    echo "[info]: initdt start "
    docker compose -f docker-compose-portsip-pbx-init.yml exec initdt /usr/local/bin/initdt.sh -D /var/lib/portsip/pbx --pg-superuser-name postgres --pg-superuser-password ${db_password}
    local crtOrUpRet=$?
    echo "[info]: initdt done"
    docker compose -f docker-compose-portsip-pbx-init.yml down -v
    if [ $crtOrUpRet -ne 0 ]; then
        echo "[error]: init or upgrade"
        exit -1
    fi

    set -e

    # succeed init or upgrade data
    if [ -z "$pbx_pre_version" ]; then
        echo "[info]: succeed init data"
    else
        echo "[info]: succeed upgrade data"
    fi

    # 2. run
    export_configure $data_path $ip_address $pbx_img $db_img $db_password $pbx_new_version
    echo "[info]: start pbx service"
    docker compose -f docker-compose-portsip-pbx.yml up -d

    echo "[info]: created"
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

upgrade(){
    echo "[info]: try to upgrade the pbx service"

    shift

    new_pbx_img=

    # parse parameters
    while getopts i: option
    do 
        case "${option}" in
            i)
                new_pbx_img=${OPTARG}
                ;;
        esac
    done

    # check the container exist
    docker inspect portsip.callmanager > /dev/null

    if [ ! -f "$pbx_deploy_config_file" ]; then 
        echo "[error]: the configures that the pbx service depends on are lost."
        exit -1
    fi

    # read configures from .configure_im
    data_path=$(sed -n '/^PBX_DATA_PATH/p' ${pbx_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    ip_address=$(sed -n '/^IP_ADDRESS/p' ${pbx_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    pbx_img=$(sed -n '/^PBX_IMG/p' ${pbx_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    db_img=$(sed -n '/^PBX_DB_IMG/p' ${pbx_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    db_password=$(sed -n '/^DB_PASSWORD/p' ${pbx_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    storage=$(sed -n '/^STORAGE/p' ${pbx_deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')

    echo "[info]: variables"
    echo "    datapath: $data_path"
    echo "    ip      : $ip_address"
    echo "    pbx  img: used/$pbx_img new/$new_pbx_img"
    echo "    db   img: $db_img"
    echo "     storage: $storage"

    # remove container
    echo "[info]: start upgrade"
    rm
    echo "[info]: the old service has been deleted"
    # re-create
    paras="-p ${data_path} -a $ip_address -d $db_img"
    if [ ! -z "$new_pbx_img" ]; then
        pbx_img="$new_pbx_img"
    fi
    if [ -z $pbx_img ]; then
        echo "[error]: unknown the docker image of pbx"
        exit -1
    fi
    paras="$paras -i $pbx_img"
    if [ ! -z $storage ]; then
        paras="$paras -f $storage"
    fi

    command="create run $paras"
    echo "$command"
    $command

    echo "[info]: upgraded"
}

remove_unused_imgs(){
    docker image prune -a --filter "label=product=PBX" -f  > /dev/null 2>&1 || true
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

up)
    rm $@
    create $@
    ;;

upgrade)
    upgrade $@
    remove_unused_imgs
    ;;

*)
    echo "[error]: unknown command $1"
    ;;

esac
