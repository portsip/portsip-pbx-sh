#!/usr/bin/env bash
set -e

if [ -z $1 ];
then 
    echo "=> need more parameters <="
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
im_img=portsip/pbx:22

# -d
db_img="portsip/postgresql:14.12"

# -t
im_token=

# -E -> 1 for extend
running_mode=0

production_version=

extend_svc_type=im-server-only

im_compose_ini_file="docker-compose-portsip-im-init.yml"
im_compose_file="docker-compose.yml"

im_datapath=
im_dbpath=

storage=

firewall_svc_name="portsip-im"
firewall_predfined_ports="8887/tcp"

export_production_version() {
    local null_str=null
    local labels=$(docker image inspect --format='{{json .Config.Labels}}' $im_img)
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

is_production_version_less_than_22_0() {
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
    else
        echo 0
    fi
}

parse_cmd_parameters() {
    echo "args:$@"
    
    while getopts f:d:p:a:A:x:i:t:E option
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
                im_img=${OPTARG}
                ;;
            t)
                im_token=${OPTARG}
                ;;
            E)
                running_mode=1
                ;;
            d)
                db_img=${OPTARG}
                ;;
            f)
                storage=${OPTARG}
                ;;
        esac
    done
}

verify_parameters() {
        # check parameters is exist
    if [ -z "$data_path" ]; then
        echo "\t Option -p not specified"
        exit -1
    fi

    if [ -z "$im_img" ]; then
        echo "\t Option -i not specified"
        exit -1
    fi

    if [ -z "$im_token" ]; then
        echo "\t Option -t not specified"
        exit -1
    fi

    if [ $running_mode -eq 0 ]; then
        pbx_ip_address=127.0.0.1
        local_pri_ip_address=127.0.0.1

        # make sure pbx already running on this host
        ret=$(docker compose ls -a | grep pbx | wc -l)
        if [ $ret -ne 1 ]; then
            echo "\t pbx not deployed on this host(containers)"
            exit -1
        fi
        if [ ! -d "$data_path/pbx" ]; then
            echo "\t pbx not deployed on this host(datapath)"
            exit -1
        fi
        if [ ! -d "$data_path/postgresql" ]; then
            echo "\t pbx not deployed on this host(db)"
            exit -1
        fi
        if [ ! -f "$data_path/pbx/system.ini" ]; then 
            echo "\t pbx not deployed on this host(configure)"
            exit -1
        fi
        mkdir -p $data_path/pbx/im/storage
        chmod 755 $data_path/pbx/im
        chown -R 888:888 $data_path/pbx/im
        echo ""
        echo "\t run as INTERNAL mode"
        echo ""
    else
        # extend service
        if [ -z "$pbx_ip_address" ]; then
            echo "\t Option -x not specified"
            exit -1
        fi

        if [ -z "$db_img" ]; then
            echo "\t Option -d not specified"
            exit -1
        fi
        
        ret=$(docker compose ls -a | grep pbx | wc -l)
        if [ $ret -ne 0 ]; then
            echo "\t already exist pbx on this host(containers)"
            exit -1
        fi

        if [ -z "$local_pri_ip_address" ] && [ -z "$local_pub_ip_address" ]; then
            echo "\t Option -a and -A not specified"
            exit -1
        fi
        echo ""
        echo "\t run as STANDALONE mode"
        echo ""
    fi
}

export_configure_internal() {
    local volume_name="$extend_svc_type"

    cat << VOLINITEOF > ${im_compose_file}
volumes:
  ${volume_name}:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${data_path}/pbx

VOLINITEOF

    if [ ! -z "$storage" ]; then 
      cat << FEOF >> ${im_compose_file}
  im-storage-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${storage}

FEOF
    fi

      cat << IMEOF >> ${im_compose_file}
services:
  instantmessage: 
    image: ${im_img}
    command: ["/usr/local/bin/im", "serve", "-D","/var/lib/portsip/pbx", "-t", "${im_token}"]
    network_mode: host
    user: portsip
    restart: unless-stopped
    container_name: "portsip.instantmessage"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
IMEOF

    if [ ! -z "$storage" ]; then 
      cat << FEOF >> ${im_compose_file}
      - im-storage-data:/var/lib/portsip/pbx/im/storage
FEOF
    fi
}

start_internal() {
    echo 
    echo "export internal configure file '${im_compose_file}'"

    export_configure_internal

    echo "done"
    echo ""
}

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

export_configure_crt_or_up() {
    echo 
    echo "[ini-cfg] export configure file '${im_compose_ini_file}'"

    cat << FEOF > ${im_compose_ini_file}

volumes:
  im-db:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $im_dbpath
  im-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $im_datapath

services:
  database:
    image: ${db_img}
    network_mode: host
    user: root
    container_name: "portsip.database"
    volumes:
      - /etc/localtime:/etc/localtime
      - im-db:/var/lib/postgresql/data
    environment:
      - PGDATA=/var/lib/postgresql/data
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${db_password}
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
    image: ${im_img}
    command: [ "sleep", "infinity" ]
    network_mode: host
    user: root
    container_name: "portsip.initdt"
    volumes:
      - /etc/localtime:/etc/localtime
      - im-data:/var/lib/portsip/pbx
    depends_on:
      database:
        condition: service_healthy

FEOF

    echo "[ini-cfg] done"
    echo ""
}

export_configure_extension() {
    echo 
    echo "[cfg] export configure file '${im_compose_file}'"

    webserver_command="\"/usr/local/bin/websrv\", \"serve\", \"-n\", \"websrv\", \"-D\",\"/var/lib/portsip/pbx\""

    
    if [ -z "$local_pri_ip_address" ]; then
        im_command="\"/usr/local/bin/im\", \"serve\", \"-E\", \"-D\",\"/var/lib/portsip/pbx\", \"-t\", \"${im_token}\",\"-a\",\"$pbx_ip_address\", \"-z\", \"$local_pub_ip_address\""
    elif [ -z "$local_pub_ip_address" ]; then
        im_command="\"/usr/local/bin/im\", \"serve\", \"-E\", \"-D\",\"/var/lib/portsip/pbx\", \"-t\", \"${im_token}\",\"-a\",\"$pbx_ip_address\", \"-x\", \"$local_pri_ip_address\""
    else
        im_command="\"/usr/local/bin/im\", \"serve\", \"-E\", \"-D\",\"/var/lib/portsip/pbx\", \"-t\", \"${im_token}\",\"-a\",\"$pbx_ip_address\", \"-x\", \"$local_pri_ip_address\", \"-z\", \"$local_pub_ip_address\""
    fi

    cat << FEOF > ${im_compose_file}
volumes:
  im-db:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${im_dbpath}
  im-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${im_datapath}

FEOF

    if [ ! -z "$storage" ]; then 
      cat << FEOF >> ${im_compose_file}
  im-storage-data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${storage}

FEOF
    fi

    cat << FEOF >> ${im_compose_file}
services:
  database:
    image: ${db_img}
    network_mode: host
    user: root
    container_name: "portsip.database"
    volumes:
      - /etc/localtime:/etc/localtime
      - im-db:/var/lib/postgresql/data
    environment:
      - PGDATA=/var/lib/postgresql/data
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${db_password}
      - POSTGRES_INITDB_ARGS=--encoding=UTF8 --auth=md5 --auth-host=md5 --data-checksums
      - POSTGRES_HOST_AUTH_METHOD=md5
    restart: unless-stopped
    healthcheck:
      test: [ "CMD", "pg_isready", "-h", "localhost", "-p", "5432", "-U", "postgres" ]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s

  websvc: 
    image: ${im_img}
    command: [${webserver_command}]
    network_mode: host
    #user: www-data
    container_name: "portsip.webserver"
    volumes:
      - im-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    restart: unless-stopped
    depends_on:
      database:
        condition: service_healthy
      instantmessage:
        condition: service_healthy

  instantmessage: 
    image: ${im_img}
    command: [${im_command}]
    network_mode: host
    user: portsip
    restart: unless-stopped
    container_name: "portsip.instantmessage"
    depends_on:
      database:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8902/svr_stats"]
      interval: 3s
      timeout: 1s
      retries: 10
      start_period: 3s
    volumes:
      - im-data:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
FEOF

    if [ ! -z "$storage" ]; then 
      cat << FEOF >> ${im_compose_file}
      - im-storage-data:/var/lib/portsip/pbx/im/storage
FEOF
    fi

    echo "[cfg] done"
    echo ""
}

start_extension(){
    db_listen_address=0.0.0.0
    #  generate db password
    db_password=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20`

    pre_version=
    new_version=
    im_datapath=$data_path/im-data
    im_dbpath=$data_path/im-postgresql
    im_cfgpath=$im_datapath/system.ini
    im_pbxver=$im_datapath/VERSION

    # check datapath whether exist
    if [ ! -d "$im_datapath" ]; then
        echo "the current data path $im_datapath does not exist, try to create it"
        mkdir -p "$im_datapath"
        echo "created"
        echo ""
    fi

    # check db datapath whether exist
    if [ ! -d "$im_dbpath" ]; then
        echo ""
        echo "[run] db datapath $im_dbpath not exist, try to create it"
        mkdir -p $im_dbpath
        echo "[run] created"
        echo ""
    fi

    # read database password if exist
    if [ -f $im_cfgpath ]; then
        db_password=`sed -nr "/^\[database\]/ { :l /^superuser_password[ ]*=/ { s/[^=]*=[ ]*//; p; q;}; n; b l;}" $im_cfgpath`
    fi

    if [ -f $im_pbxver ]; then
        pre_version=`head -n 1 $im_pbxver`
    fi

    # get product version
    docker image pull $im_img
    new_version=$(export_production_version)
    if [ -z "$new_version" ]; then
        echo "[run] FAILED: not found label 'version' in the im image"
        exit -1
    fi
    if [ -z "$pre_version" ]; then
        echo "[run] try to create im"
    else
        echo "[run] upgrade from $pre_version to $new_version"
    fi

    # init or upgrade data
    export_configure_crt_or_up
    set +e
    docker compose -f ${im_compose_ini_file} down -v || true
    docker compose -f ${im_compose_ini_file} up -d --wait
    local crtOrUpRetEnv=$?
    if [ $crtOrUpRetEnv -ne 0 ]; then
        docker compose -f ${im_compose_ini_file} down -v
        echo "[run] FAILED: init or upgrade env"
        exit -1
    fi
    echo ""
    echo "[run] ===> initdt start "
    docker compose -f ${im_compose_ini_file} exec initdt /usr/local/bin/initdt.sh -D /var/lib/portsip/pbx --pg-superuser-name postgres --pg-superuser-password ${db_password}
    local crtOrUpRet=$?
    echo "[run] ===> initdt done"
    echo ""
    docker compose -f ${im_compose_ini_file} down -v
    if [ $crtOrUpRet -ne 0 ]; then
        echo "[run] FAILED: init or upgrade"
        exit -1
    fi

    set -e

    # succeed init or upgrade data
    if [ -z "$pre_version" ]; then
        echo "[run] succeed init data"
    else
        echo "[run] succeed upgrade data"
    fi

    chmod 755 $im_dbpath
    chmod 755 $im_datapath
    mkdir -p $im_datapath/im
    chmod 755 $im_datapath/im
    chown 888:888 $im_datapath/im
    
    # configure
    export_configure_extension
}

create() {
    echo ""
    echo "==> try to create im service <=="
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    parse_cmd_parameters $@
    verify_parameters

    config_sysctls

    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        mkdir $extend_svc_type
    fi
    cd $extend_svc_type

    echo ""
    echo "datapath  : $data_path"
    echo "ip(pri)   : $local_pri_ip_address"
    echo "ip(pub)   : $local_pub_ip_address"
    echo "ip(pbx)   : $pbx_ip_address"
    echo "im img    : $im_img"
    echo "db img    : $db_img"
    echo "token     : $im_token"
    echo "storage   : $storage"
    echo ""

    # get product version
    docker image pull $im_img
    production_version=$(export_production_version)
    if [ -z "$production_version" ]; then
        echo "no 'version' information found in the docker image"
        exit -1
    fi
    echo "current version $production_version"

    local ret=$(is_production_version_less_than_22_0)
    # ret: 1 for success and 0 for failure
    if [ $ret -eq 1 ]; then
      echo "[error] version < 22.0.0"
      exit -1
    fi

    # write configure file
    cat << EOF > .configure_im
DATA_PATH=$data_path
PRI_IP_ADDRESS=$local_pri_ip_address
PUB_IP_ADDRESS=$local_pub_ip_address
PBX_IP_ADDRESS=$pbx_ip_address
IM_IMG=$im_img
DB_IMG=$db_img
EXTEND_SVC_TYPE=$extend_svc_type
RUNNING_MODE=$running_mode
STORAGE=$storage
EOF

    # check storage datapath whether exist
    if [ ! -z "$storage" ]; then
        if [ ! -d "$storage" ]; then
            echo ""
            echo "[run] storage datapath $storage not exist, exit"
            echo ""
            exit -1
        else
            chmod 755 "$storage"
            chown 888:888 "$storage"
        fi
    fi

    if [ $running_mode -eq 0 ]; then
        start_internal
    else
        set_firewall
        start_extension
    fi

    # run extend service
    docker compose -f ${im_compose_file} up -d

    echo ""
    echo "done"
    echo ""
}

op() {
    #echo "$@"
    local operator=$1
    shift

    # parse parameters
    parse_cmd_parameters $@

    # check parameters is exist
    if [ -z "$extend_svc_type" ]; then
        echo "Option -s not specified"
        exit -1
    fi
    # change work directory
    if [ ! -d "./$extend_svc_type" ]; then
        echo "no service configuration found"
        exit -1
    fi
    cd $extend_svc_type

    echo ""
    echo "${operator} service $extend_svc_type"
    echo ""
  
    case $operator in
    restart)
        docker compose -f ${im_compose_file} stop -t 300
        sleep 3
        docker compose -f ${im_compose_file} start
        ;;

    status)
        docker compose -f ${im_compose_file} ls -a
        docker compose -f ${im_compose_file} ps -a
        ;;

    stop)
        docker compose -f ${im_compose_file} stop -t 300
        ;;

    start)
        docker compose -f ${im_compose_file} start
        ;;

    rm)
        docker compose -f ${im_compose_file} down -v
        ;;

    esac
}

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

*)
    echo "command error"
    ;;
esac