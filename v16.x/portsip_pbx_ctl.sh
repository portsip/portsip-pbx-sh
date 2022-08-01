#!/usr/bin/env bash
set -e

if [ -z $1 ];
then 
    echo -e "\t => need parameters <="
    exit -1
fi


# $1: pbx_data_path
# $2: pbx_ip_address
# $3: pbx_img
# $4: pbx_db_img
# $5: pbx_db_password
export_configure() {
    echo ""
    echo -e "\t => export configure file 'docker-compose.yml' <="
    echo ""

    pbx_data_path=$1
    pbx_ip_address=$2
    pbx_img=$3
    pbx_db_img=$4
    pbx_db_password=$5

    cat << FEOF > docker-compose.yml
version: "3.9"
services:
  database:
    image: ${pbx_db_img}
    network_mode: host
    user: root
    container_name: "PortSIP.Database"
    volumes:
      - /etc/localtime:/etc/localtime
      - pbx-db:/var/lib/postgresql/data
    environment:
      - PGDATA=/var/lib/postgresql/data
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${pbx_db_password}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --auth=md5 --auth-host=md5 --data-checksums
      - POSTGRES_HOST_AUTH_METHOD=md5
    restart: always
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
    container_name: "PortSIP.Initdt"
    volumes:
      - /etc/localtime:/etc/localtime
      - pbx-data:/var/lib/portsip/pbx
    depends_on:
      database:
        condition: service_healthy

  wdfs: 
    image: ${pbx_img}
    command: ["/usr/local/bin/weed", "-logdir=/var/lib/portsip/pbx/log", "-v=0", "server", "-ip=127.0.0.1", "-master.port=9333", "-master.volumeSizeLimitMB=30000", "-volume.max=1750", "-volume.port=8882", "-filer.port=8889", "-dir=/var/lib/portsip/pbx/filedata", "-volume.publicUrl=${pbx_ip_address}:8882"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.Weed"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully

  nats: 
    image: ${pbx_img}
    command: ["/usr/local/bin/nats-server", "--log", "/var/lib/portsip/pbx/log/nats.log", "--http_port", "8222"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.NATS"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: always
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
    container_name: "PortSIP.CallManager"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
      - IP_ADDRESS=${pbx_ip_address}
      - LD_PRELOAD=/usr/local/lib/libmimalloc.so
    cap_add:
      - SYS_PTRACE
    restart: always
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
    container_name: "PortSIP.MediaServer"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
      - IP_ADDRESS=${pbx_ip_address}
    cap_add:
      - SYS_PTRACE
    restart: always
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
    container_name: "PortSIP.Gateway"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: always
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
    container_name: "PortSIP.WebServer"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully

  wsspublisher: 
    image: ${pbx_img}
    command: ["/usr/local/bin/wsspublisher", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.WSSPublisher"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  voicemail: 
    image: ${pbx_img}
    command: ["/usr/local/bin/voicemail", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.Voicemail"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  vr: 
    image: ${pbx_img}
    command: ["/usr/local/bin/vr", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.VirtualReceptionist"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Push Server
  pushserver: 
    image: ${pbx_img}
    command: ["/usr/local/bin/pushserver", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.PushServer"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Provision Sever
  prvserver: 
    image: ${pbx_img}
    command: ["/usr/local/bin/prvserver", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.Provision"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Mail Gateway
  mailgateway: 
    image: ${pbx_img}
    command: ["/usr/local/bin/mailgateway", "-D","/var/lib/portsip/pbx"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.MailGateway"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Logging Server
  # logging: 
  #   image: ${pbx_img}
  #   command: ["bundle", "exec", "thin", "-p", "3000"]
  #   network_mode: host
  #   volumes:
  #     - pbx-data:/var/lib/portsip/pbx
  #   depends_on:
  #     initdt:
  #       condition: service_completed_successfully

  # PortSIP Conference Server
  conf: 
    image: ${pbx_img}
    command: ["/usr/local/bin/conf", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.Conference"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Call Queue Server
  callqueue: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callqueue", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.CallQueue"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Call Park Server
  callpark: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callpark", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.CallPark"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

  # PortSIP Announcement Server
  anncmnt: 
    image: ${pbx_img}
    command: ["/usr/local/bin/anncmnt", "-D","/var/lib/portsip/pbx", "start"]
    network_mode: host
    user: portsip
    container_name: "PortSIP.Announcement"
    volumes:
      - pbx-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: always
    depends_on:
      initdt:
        condition: service_completed_successfully
      nats:
        condition: service_healthy
      database:
        condition: service_healthy

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
    cat << EOF > .configure
PBX_DATA_PATH=$data_path
IP_ADDRESS=$ip_address
PBX_IMG=$pbx_img
PBX_DB_IMG=$db_img
DB_PASSWORD=$db_password
EOF

    export_configure $data_path $ip_address $pbx_img $db_img $db_password
    # run pbx service
    docker compose up -d

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
        docker compose ls -a
        docker compose ps -a
    else
        echo ""
        echo "status service $service_name"
        echo ""
        docker compose ps $service_name
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
        docker compose restart
        exit 0
    fi

    echo ""
    echo "restart service $service_name"
    echo ""
    case $service_name in
    database)
        docker compose stop -t 100
        docker compose start
        ;;

    nats)
        docker compose stop -t 100
        docker compose start
        ;;

    wdfs)
        docker compose stop -t 100
        docker compose start
        ;;

    *)
        docker compose stop -t 100 $service_name
        docker compose start $service_name
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
        docker compose start
    else
        echo ""
        echo "start service $service_name"
        echo ""
        docker compose start $service_name
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
        docker compose stop
        exit 0
    fi
    echo ""
    echo "stop service $service_name"
    echo ""
    case $service_name in
    database)
        docker compose stop -t 100
        ;;

    nats)
        docker compose stop -t 100
        ;;

    wdfs)
        docker compose stop -t 100
        ;;

    *)
        docker compose stop -t 100 $service_name
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

    docker compose down

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
