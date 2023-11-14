#!/usr/bin/env bash
set -e

# example(use default): sh trace_server_ctl.sh run
#          datapath: /var/lib/portsip
#          drop days: 5
#          capture port: 9061
#          http port: 9080

# example(custom): sh trace_server_ctl.sh run -p /var/lib/trace_server -k 10 -l 12345 -z 23456
#          datapath: /var/lib/trace_server
#          drop days: 10
#          capture port: 23456
#          http port: 12345

data_path="/var/lib/portsip"
heplify_img="portsip/trace-server:heplify-16"
webapp_img="portsip/trace-server:webapp-16"
db_img="portsip/trace-server:postgres11-alpine"
db_password="homerSeven"
db_user="root"
db_port=5432
db_host="127.0.0.1"
db_svc_name="database"
data_drop_days=5
http_port=9080
capture_port_1=9060
capture_port_2=9061

firewall_svc_name="portsip-trace-svc"

if [ -z $1 ];
then 
    echo "[op] need parameters"
    exit -1
fi

if [ ! -d "./trace_server" ]; then
    mkdir trace_server
fi

cd trace_server

set_firewall(){
    echo ""
    echo "[firewall] Configure firewall rules:"
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
    firewall-cmd --permanent --service=${firewall_svc_name} --add-port=${capture_port_1}/tcp --add-port=${capture_port_2}/tcp --add-port=${http_port}/tcp
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

export_configure() {
    echo 
    echo "[config] export configure file 'docker-compose.yml'"

    cat << FEOF > docker-compose.yml
version: "3.9"

volumes:
  trace-data-db:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${data_path}/trace_server_postgresql

services:
  ${db_svc_name}:
    container_name: "trace.db"
    image: ${db_img}
    environment:
      - PGDATA=/var/lib/postgresql/data
      - POSTGRES_USER=${db_user}
      - POSTGRES_PASSWORD=${db_password}
    network_mode: host
    restart: unless-stopped
    volumes:
      - /etc/localtime:/etc/localtime
      - trace-data-db:/var/lib/postgresql/data
    healthcheck:
      test: [ "CMD-SHELL", "psql -h 'localhost' -U 'root' -c '\\\\l'" ]
      interval: 1s
      timeout: 3s
      retries: 30

  heplify:
    image: ${heplify_img}
    container_name: "trace.heplify"
    network_mode: host
    command:
      - './heplify-server'
    environment:
      - HEPLIFYSERVER_HEPADDR=0.0.0.0:${capture_port_1}
      - HEPLIFYSERVER_HEPTCPADDR=0.0.0.0:${capture_port_2}
      - HEPLIFYSERVER_DBSHEMA=homer7
      - HEPLIFYSERVER_DBDRIVER=postgres
      - HEPLIFYSERVER_DBADDR=${db_host}:${db_port}
      - HEPLIFYSERVER_DBUSER=${db_user}
      - HEPLIFYSERVER_DBPASS=${db_password}
      - HEPLIFYSERVER_DBDATATABLE=homer_data
      - HEPLIFYSERVER_DBCONFTABLE=homer_config
      - HEPLIFYSERVER_DBROTATE=true
      - HEPLIFYSERVER_DBDROPDAYS=${data_drop_days}
      - HEPLIFYSERVER_LOGLVL=info
      - HEPLIFYSERVER_LOGSTD=true
      - HEPLIFYSERVER_DEDUP=false
      - HEPLIFYSERVER_ALEGIDS=X-Session-Id
      - HEPLIFYSERVER_FORCEALEGID=false
      - HEPLIFYSERVER_CUSTOMHEADER=X-Session-Id,X-CID
      - HEPLIFYSERVER_SIPHEADER=callid,callid_aleg,method,ruri_user,ruri_domain,from_user,from_domain,from_tag,to_user,to_domain,to_tag,via,contact_user
    restart: unless-stopped
    depends_on:
      ${db_svc_name}:
        condition: service_healthy
    labels:
      org.label-schema.group: "monitoring"

  trace-webapp:
    container_name: "trace.webapp"
    image: ${webapp_img}
    environment:
      - DB_HOST=${db_host}
      - DB_USER=${db_user}
      - DB_PASS=${db_password}
      - HTTP_PORT=${http_port}
    restart: unless-stopped
    network_mode: host
    depends_on:
      ${db_svc_name}:
        condition: service_healthy
FEOF

    echo "[config] done"
    echo ""
}

create() {
    echo ""
    echo "[run] try to create trace server"
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    #  generate db password
    db_password=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8`

    # parse parameters
    while getopts p:k:d:w:c:l:y:z: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            k)
                data_drop_days=${OPTARG}
                ;;
            d)
                db_img=${OPTARG}
                ;;
            w)
                webapp_img=${OPTARG}
                ;;
            c)
                heplify_img=${OPTARG}
                ;;
            l)
                http_port=${OPTARG}
                ;;
            y)
                capture_port_1=${OPTARG}
                ;;
            z)
                capture_port_2=${OPTARG}
                ;;
        esac
    done

    if [ -z "$db_password" ]; then
        echo "[run] Password is empty"
        exit -1
    fi

    # check parameters is exist
    if [ -z "$data_path" ]; then
        echo "[run] data path is empty(used default /var/lib/portsip)"
        data_path=/var/lib/portsip
    fi

    if [ -z "$data_drop_days" ]; then
        echo "[run] data drop days is empty(used default 5)"
        data_drop_days=5
    fi

    if [ -z "$db_img" ]; then
        echo "[run] db image is empty(used default portsip/trace-server:postgres11-alpine)"
        db_img=portsip/trace-server:postgres11-alpine
    fi

    if [ -z "$webapp_img" ]; then
        echo "[run] webapp image is empty(used default portsip/trace-server:webapp-16)"
        webapp_img=portsip/trace-server:webapp-16
    fi

    if [ -z "$heplify_img" ]; then
        echo "[run] heplify server image is empty(used default portsip/trace-server:heplify-16)"
        heplify_img=portsip/trace-server:heplify-16
    fi

    if [ -z "$http_port" ]; then
        echo "[run] http listen port is empty(used default 9080)"
        http_port=9080
    fi

    if [ -z "$capture_port_1" ]; then
        echo "[run] HEPLIFYSERVER_HEPADDR is empty(used default 9060)"
        capture_port_1=9060
    fi

    if [ -z "$capture_port_2" ]; then
        echo "[run] HEPLIFYSERVER_HEPTCPADDR is empty(used default 9061)"
        capture_port_2=9061
    fi

    set_firewall

    echo "[run] parameters :"
    echo "    datapath    : $data_path"
    echo "    drop(day)   : $data_drop_days"
    echo "    db img      : $db_img"
    echo "    webapp img  : $webapp_img"
    echo "    heplify img : $heplify_img"
    echo "    http port   : $http_port"
    echo "    capture port: $capture_port_2"
    echo ""

    cat << EOF > .configure
data_path       $data_path
data_drop_days  $data_drop_days
db_img          $db_img
webapp_img      $webapp_img
heplify_img     $heplify_img
http_port       $http_port
capture_port_2  $capture_port_2
EOF

    # check datapath whether exist
    if [ ! -d "$data_path/trace_server_postgresql" ]; then
        echo "[run] datapath $data_path/trace_server_postgresql not exist, try to create it"
        mkdir -p $data_path/trace_server_postgresql
        echo "[run] created"
        echo ""
    fi

    # change directory mode
    chmod 755 $data_path

    export_configure
    # run service
    docker compose up -d

    echo ""
    echo "[run] done"
    echo ""
}


status() {
    echo ""
    echo "[op] status all services"
    echo ""
    docker compose ls -a
    docker compose ps -a
}

restart() {
    echo ""
    echo "[op] restart all services"
    echo ""
    docker compose stop -t 300
    sleep 10
    docker compose start
}

start() {
    echo ""
    echo "[op] start all services"
    echo ""
    docker compose start
}

stop() {
    echo ""
    echo "[op] stop all services"
    echo ""
    docker compose stop
}

rm() {
    echo ""
    echo "[op] stop all services"
    echo ""
    docker compose down
    docker volume rm `docker volume ls  -q | grep trace-data-db` || true
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
    echo "[op] error command"
    ;;
esac
