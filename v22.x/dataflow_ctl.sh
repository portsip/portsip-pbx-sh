#!/usr/bin/env bash
set -e

if [ -z $1 ]; then 
    echo "[error]: unknown command"
    exit -1
fi

# -p
data_path=/var/lib/portsip

# -a
local_pri_ip_address=

# -A
local_pub_ip_address=

# -x
pbx_ip_address=

# -i
dataflow_img=portsip/pbx:22

# -d
db_img="portsip/clickhouse:25.8"

production_version=

extend_svc_type=dataflow-server-only

compose_ini_file="docker-compose-portsip-dataflow-init.yml"
compose_file="docker-compose.yml"

datapath=
dbpath=

firewall_svc_name="portsip-dataflow"
firewall_predfined_ports="9000/tcp 8123/tcp"

deploy_config_file=".configure_dataflow"

#Defaults to Docker Hub if no server is specified
docker_hub_registry=
#Authenticate to a registry.
docker_hub_username=
docker_hub_token=

echo "[info]: Starting..."

export_production_version() {
    local null_str=null
    local labels=$(docker image inspect --format='{{json .Config.Labels}}' $dataflow_img)
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

is_production_version_less_than_22_3() {
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

    if [ $y -lt 3 ]; then
        echo 1
    else
        echo 0
    fi
}

parse_cmd_parameters() {
    echo "[info]: args $@"
    
    while getopts d:p:a:A:x:i:U:P:R: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            a)
                local_pri_ip_address=${OPTARG}
                ;;
            A)
                local_pub_ip_address=${OPTARG}
                ;;
            x)
                pbx_ip_address=${OPTARG}
                ;;
            i)
                dataflow_img=${OPTARG}
                ;;
            d)
                db_img=${OPTARG}
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
        exit -1
    fi

    if [ -z "$dataflow_img" ]; then
        echo "[error]: Option -i not specified"
        exit -1
    fi

    # extend service
    if [ -z "$pbx_ip_address" ]; then
        echo "[error]: Option -x not specified"
        exit -1
    fi

    if [ -z "$db_img" ]; then
        echo "[error]: Option -d not specified"
        exit -1
    fi
    
    # ret=$(docker compose ls -a -q | grep pbx | wc -l)
    # if [ $ret -ne 0 ]; then
    #     echo "[error]: already exist pbx on this host(containers)"
    #     exit -1
    # fi

    if [ -z "$local_pri_ip_address" ] && [ -z "$local_pub_ip_address" ]; then
        echo "[error]: Option -a and -A not specified"
        exit -1
    fi
    echo "[info]: run as STANDALONE mode"
}

set_firewall(){
    echo "[info]: configure firewalld"

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
    firewall-cmd -q --permanent --zone=trusted --add-source=${pbx_ip_address} > /dev/null || true
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
    echo "[info]: firewalld service ${firewall_svc_name}:"
    firewall-cmd --service=${firewall_svc_name}  --permanent --get-ports
}

config_sysctls() {

    cat << EOF > /etc/sysctl.d/ip_unprivileged_port_start.conf
net.ipv4.ip_unprivileged_port_start=0
EOF

    `sysctl -p > /dev/null 2>&1` || true
    `sysctl --system > /dev/null 2>&1` || true
}

export_configure_crt_or_up() {
    cat << FEOF > ${compose_ini_file}

volumes:
  df-db-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $dbpath/data
  df-db-log:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $dbpath/log
  df-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $datapath

services:
  database:
    image: ${db_img}
    network_mode: host
    user: root
    container_name: "portsip.clickhouse"
    volumes:
      - /etc/localtime:/etc/localtime
      - df-db-data:/var/lib/clickhouse
      - df-db-log:/var/log/clickhouse-server
    environment:
      - CLICKHOUSE_DB=default
      - CLICKHOUSE_USER=default
      - CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1
      - CLICKHOUSE_PASSWORD=${db_password}
    cap_add:
      - NET_ADMIN
      - SYS_NICE
      - IPC_LOCK
    ulimits:
      nofile:
        soft: 655360
        hard: 655360
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "clickhouse-client", "-q", "SELECT 1"]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

  initdt:
    image: ${dataflow_img}
    command: [ "sleep", "infinity" ]
    network_mode: host
    user: root
    container_name: "portsip.dataflow_initdt"
    volumes:
      - /etc/localtime:/etc/localtime
      - df-data:/var/lib/portsip/dataflow
    depends_on:
      database:
        condition: service_healthy
FEOF

    echo "[info] dumped ini configure file '${compose_ini_file}'"
}

export_configure_extension() {   
    if [ -z "$local_pri_ip_address" ]; then
        df_command="\"/usr/local/bin/dataflow\", \"serve\", \"-D\",\"/var/lib/portsip/dataflow\", \"-a\",\"$pbx_ip_address\", \"-z\", \"$local_pub_ip_address\""
    elif [ -z "$local_pub_ip_address" ]; then
        df_command="\"/usr/local/bin/dataflow\", \"serve\", \"-D\",\"/var/lib/portsip/dataflow\", \"-a\",\"$pbx_ip_address\", \"-x\", \"$local_pri_ip_address\""
    else
        df_command="\"/usr/local/bin/dataflow\", \"serve\", \"-D\",\"/var/lib/portsip/dataflow\", \"-a\",\"$pbx_ip_address\", \"-x\", \"$local_pri_ip_address\", \"-z\", \"$local_pub_ip_address\""
    fi

    cat << FEOF > ${compose_file}
volumes:
  df-db-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $dbpath/data
  df-db-log:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $dbpath/log
  df-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $datapath
FEOF

    cat << FEOF >> ${compose_file}
services:
  database:
    image: ${db_img}
    network_mode: host
    user: root
    container_name: "portsip.clickhouse"
    volumes:
      - /etc/localtime:/etc/localtime
      - df-db-data:/var/lib/clickhouse
      - df-db-log:/var/log/clickhouse-server
    environment:
      - CLICKHOUSE_DB=default
      - CLICKHOUSE_USER=default
      - CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1
      - CLICKHOUSE_PASSWORD=${db_password}
    cap_add:
      - NET_ADMIN
      - SYS_NICE
      - IPC_LOCK
    ulimits:
      nofile:
        soft: 655360
        hard: 655360
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "clickhouse-client", "-q", "SELECT 1"]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

  dataflow: 
    image: ${dataflow_img}
    command: [${df_command}]
    network_mode: host
    user: portsip
    restart: unless-stopped
    container_name: "portsip.dataflow"
    depends_on:
      database:
        condition: service_healthy
    volumes:
      - df-data:/var/lib/portsip/dataflow
      - /etc/localtime:/etc/localtime
FEOF

    echo "[info]: dumped configure file '${compose_file}'"
}

start_extension(){
    datapath=$data_path/dataflow
    dbpath=$data_path/clickhouse
    # check datapath whether exist
    if [ ! -d "$datapath" ]; then
        echo "[warn]: the current data path $datapath does not exist, try to create it"
        mkdir -p "$datapath"
        echo "[info]: $datapath created"
    fi

    # check db datapath whether exist
    if [ ! -d "$dbpath/data" ]; then
        echo "[warn]: db data path $dbpath/data not exist, try to create it"
        mkdir -p $dbpath/data
        echo "[info]: $dbpath/data created"
    fi
    if [ ! -d "$dbpath/log" ]; then
        echo "[warn]: db log path $dbpath/log not exist, try to create it"
        mkdir -p $dbpath/log
        echo "[info]: $dbpath/log created"
    fi

    chown 888:888 $datapath
    chmod 755 $datapath

    cfgpath=$datapath/system.ini
    db_password=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20`
    if [ -f $cfgpath ]; then
        db_password=`sed -nr "/^\[dataflow\]/ { :l /^password[ ]*=/ { s/[^=]*=[ ]*//; p; q;}; n; b l;}" $cfgpath`
        echo "[info]: use existed old password $db_password"
    fi

    # get product version
    echo "[info]: docker pull $dataflow_img"
    docker image pull $dataflow_img > /dev/null

    new_version=$(export_production_version)
    echo "[info]: try to init dataflow $new_version"

    # init or upgrade data
    export_configure_crt_or_up
    set +e
    docker compose -f ${compose_ini_file} down -v || true
    docker compose -f ${compose_ini_file} up -d --wait
    local crtOrUpRetEnv=$?
    if [ $crtOrUpRetEnv -ne 0 ]; then
        docker compose -f ${compose_ini_file} down -v
        echo "[error]: init or upgrade env"
        exit -1
    fi
    echo "[info]: initdt start "
    docker compose -f ${compose_ini_file} exec -u root initdt /usr/local/bin/initdt_dataflow.sh initdt -D /var/lib/portsip/dataflow  --password ${db_password}
    local crtOrUpRet=$?
    echo "[info]: initdt done"
    docker compose -f ${compose_ini_file} down -v
    if [ $crtOrUpRet -ne 0 ]; then
        echo "[error]: init or upgrade"
        exit -1
    fi

    set -e

    echo "[info]: succeed init data"

    chmod 755 $dbpath
    chmod 755 $datapath
    
    # configure
    export_configure_extension
}

create() {
    echo "[info]: try to create dataflow service"
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    parse_cmd_parameters $@
    verify_parameters

    config_sysctls

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
    echo "ip(pri)       : $local_pri_ip_address"
    echo "ip(pub)       : $local_pub_ip_address"
    echo "ip(pbx)       : $pbx_ip_address"
    echo "dataflow img  : $dataflow_img"
    echo "db img        : $db_img"
    echo "hub user      : $docker_hub_username"
    echo "hub server    : $docker_hub_registry"

    # get product version
    docker image pull $dataflow_img
    production_version=$(export_production_version)
    if [ -z "$production_version" ]; then
        echo "[error]: no 'version' information found in the docker image"
        exit -1
    fi
    echo "[info]: current version $production_version"

    local ret=$(is_production_version_less_than_22_3)
    # ret: 1 for success and 0 for failure
    if [ $ret -eq 1 ]; then
      echo "[error]: version $production_version < 22.3.0"
      exit -1
    fi

    # write configure file
    cat << EOF > ${deploy_config_file}
DATA_PATH=$data_path
PRI_IP_ADDRESS=$local_pri_ip_address
PUB_IP_ADDRESS=$local_pub_ip_address
PBX_IP_ADDRESS=$pbx_ip_address
DATAFLOW_IMG=$dataflow_img
DB_IMG=$db_img
EXTEND_SVC_TYPE=$extend_svc_type
HUB_USER=$docker_hub_username
HUB_SERVER=$docker_hub_registry
EOF

    #set_firewall
    start_extension

    # run extend service
    docker compose -f ${compose_file} up -d

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
        echo "[error]: option -s not specified"
        exit -1
    fi
    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        echo "[error]: no service configuration found, not exist directory ${extend_svc_type}"
        exit -1
    fi
    cd $extend_svc_type

    echo "[info]: ${operator} service $extend_svc_type"
  
    case $operator in
    restart)
        docker compose -f ${compose_file} stop -t 300
        sleep 3
        docker compose -f ${compose_file} start
        ;;

    status)
        docker compose -f ${compose_file} ls -a
        docker compose -f ${compose_file} ps -a
        ;;

    stop)
        docker compose -f ${compose_file} stop -t 300
        ;;

    start)
        docker compose -f ${compose_file} start
        ;;

    rm)
        docker compose -f ${compose_file} down -v
        ;;
    
    *)
        echo "[error]: unknown command $operator"
        exit -1
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
    docker inspect portsip.dataflow > /dev/null
    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        echo "[error]: the resources that the dataflow service depends on are lost."
        exit -1
    fi
    cd $extend_svc_type

    if [ ! -f "$deploy_config_file" ]; then 
        echo "[error]: the configures that the dataflow service depends on are lost."
        exit -1
    fi

    # read configures from .configure_dataflow
    data_path=$(sed -n '/^DATA_PATH/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    local_pri_ip_address=$(sed -n '/^PRI_IP_ADDRESS/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    local_pub_ip_address=$(sed -n '/^PUB_IP_ADDRESS/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    pbx_ip_address=$(sed -n '/^PBX_IP_ADDRESS/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    dataflow_img=$(sed -n '/^DATAFLOW_IMG/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    db_img=$(sed -n '/^DB_IMG/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')
    #extend_svc_type=$(sed -n '/^EXTEND_SVC_TYPE/p' ${deploy_config_file} | awk 'BEGIN{FS="="}{print $2}')

    echo "[info]: variables"
    echo "datapath        : $data_path"
    echo "ip(pri)         : $local_pri_ip_address"
    echo "ip(pub)         : $local_pub_ip_address"
    echo "ip(pbx)         : $pbx_ip_address"
    echo "dataflow img    : $dataflow_img new/$new_img"
    echo "db img          : $db_img"

    # remove container
    echo "[info]: start upgrade"
    docker compose -f ${compose_file} down -v
    # remove docker image
    # docker image rm -f $dataflow_img > /dev/null 2>&1
    echo "[info]: the old service has been deleted"
    # re-create
    paras="-p ${data_path}"
    if [ ! -z "$new_img" ]; then
        dataflow_img="$new_img"
    fi
    if [ -z $dataflow_img ]; then
        echo "[error]: unknown the docker image of dataflow"
        exit -1
    fi
    paras="$paras -i $dataflow_img"
    paras="$paras -d $db_img"
    if [ ! -z $local_pri_ip_address ]; then
        paras="$paras -a $local_pri_ip_address"
    fi
    if [ ! -z $local_pub_ip_address ]; then
        paras="$paras -A $local_pub_ip_address"
    fi
    if [ ! -z $pbx_ip_address ]; then
        paras="$paras -x $pbx_ip_address"
    fi

    command="create run $paras"
    $command

    echo "[info]: upgraded"
}

remove_unused_imgs(){
    docker image prune -a --filter "label=product=PBX" -f  > /dev/null 2>&1 || true
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
    ;;
esac