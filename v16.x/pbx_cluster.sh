#!/usr/bin/env bash
set -e

if [ -z $1 ];
then 
    echo "=> need more parameters <="
    exit -1
fi

# -p
data_path=
# -a
local_ip_address=
# -x
pbx_ip_address=
# -i
pbx_img=
# -s
pbx_extend_svc_type=
# -n
pbx_extend_svc_name=

pbx_production_version=
pbx_extend_svc_datapath=

export_pbx_production_version() {
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

is_pbx_production_version_less_than_16_1() {
    # x.y.z
    local v=$pbx_production_version

    set -f; IFS='.'
    set -- $v
    local x=$1; 
    local y=$2; 
    local z=$3
    set +f; unset IFS

    if [ $x -lt 16 ]; then
        echo 1
    elif [ $x -gt 16 ]; then
        echo 0
    elif [ $y -lt 1 ]; then
        echo 1
    else
        echo 0
    fi
}

# verify extend service type: queue-server-only,media-server-only,meeting-server-only,vr-server-only
verify_svc_type() {
    case "${pbx_extend_svc_type}" in
    queue-server-only)
        ;;
    media-server-only)
        ;;
    meeting-server-only)
        ;;
    vr-server-only)
        ;;
    *)
        echo "service type ${pbx_extend_svc_type} is not supported."
        echo " NOTE: please use one of queue-server-only,media-server-only,meeting-server-only,vr-server-only."
        exit -1
    esac
}

parse_cmd_parameters() {
    echo "args:$@"
    
    while getopts p:a:x:i:s:n: option
    do 
        case "${option}" in
            p)
                data_path=${OPTARG}
                ;;
            a)
                local_ip_address=${OPTARG}
                ;;
            x)
                pbx_ip_address=${OPTARG}
                ;;
            i)
                pbx_img=${OPTARG}
                ;;
            s)
                pbx_extend_svc_type=${OPTARG}
                ;;
            n)
                pbx_extend_svc_name=${OPTARG}
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
    if [ -z "$local_ip_address" ]; then
        echo "\t Option -a not specified"
        exit -1
    fi
    if [ -z "$pbx_ip_address" ]; then
        echo "\t Option -x not specified"
        exit -1
    fi
    if [ -z "$pbx_img" ]; then
        echo "\t Option -i not specified"
        exit -1
    fi
    if [ -z "$pbx_extend_svc_type" ]; then
        echo "\t Option -s not specified"
        exit -1
    fi
    if [ -z "$pbx_extend_svc_name" ]; then
        echo "\t Option -n not specified"
        exit -1
    fi

    verify_svc_type
}

export_configure() {
    echo 
    echo "export configure file 'docker-compose.yml'"

    local volume_name="pbx-data-$pbx_extend_svc_type"
    local extend_svc_name="$pbx_extend_svc_type"

    cat << VOLINITEOF > docker-compose.yml
version: "3.9"

volumes:
  ${volume_name}:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${pbx_extend_svc_datapath}

services:
VOLINITEOF

    case "${pbx_extend_svc_type}" in
    queue-server-only)
      cat << QUEUEEOF >> docker-compose.yml
  callqueue: 
    image: ${pbx_img}
    command: ["/usr/local/bin/callqueue", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.callqueue"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
QUEUEEOF
        ;;

    media-server-only)
      cat << MEDIAEOF >> docker-compose.yml
  mediaserver:
    image: ${pbx_img}
    command: ["/usr/local/bin/mediaserver", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.mediaserver"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
MEDIAEOF
        ;;

    meeting-server-only)
      cat << MEETINGEOF >> docker-compose.yml
  conf: 
    image: ${pbx_img}
    command: ["/usr/local/bin/conf", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.conference"
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime     
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
MEETINGEOF
        ;;

    vr-server-only)
      cat << VREOF >> docker-compose.yml
  vr: 
    image: ${pbx_img}
    command: ["/usr/local/bin/vr", "-D","/var/lib/portsip/pbx","-E","-a","${pbx_ip_address}","-x", "${local_ip_address}","-n","${pbx_extend_svc_name}", "start"]
    network_mode: host
    user: portsip
    container_name: "portsip.virtualreceptionist"
    volumes:
      - ${volume_name}:/var/lib/portsip/pbx
      - /etc/localtime:/etc/localtime
    environment:
      - LD_LIBRARY_PATH=/usr/local/lib
    cap_add:
      - SYS_PTRACE
    restart: unless-stopped
VREOF
        ;;

    esac

    echo "done"
    echo ""
}

initdt() {
    mkdir -p $pbx_extend_svc_datapath/callqueue
    mkdir -p $pbx_extend_svc_datapath/dump
    mkdir -p $pbx_extend_svc_datapath/log
    mkdir -p $pbx_extend_svc_datapath/mcu/record

    chmod 755 $data_path
    chmod -R 755 $pbx_extend_svc_datapath
    chown -R 888:888 $pbx_extend_svc_datapath
}

set_firewall() {
    echo ""
    echo "stop the ufw"
    echo ""
    systemctl stop ufw || true
    systemctl disable ufw || true
    echo ""
    echo "enable the firewalld"
    echo ""
    systemctl enable firewalld
    systemctl start firewalld
    echo ""
    echo "configure firewall rules for ${pbx_extend_svc_type} ${pbx_extend_svc_name}"
    echo ""
    firewall-cmd -q --zone=trusted --remove-interface=docker0 --permanent || true
    firewall-cmd -q --permanent --delete-service=${pbx_extend_svc_type} || true
    firewall-cmd --reload
    firewall-cmd --permanent --new-service=${pbx_extend_svc_type} || true

    case "${pbx_extend_svc_type}" in
    queue-server-only)
        #firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=50000-65000/udp --add-port=8916-8921/udp --add-port=8916-8921/tcp --set-description="PortSIP Call Queue Server"
        firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=8916-8921/udp --add-port=8916-8921/tcp --set-description="PortSIP Call Queue Server"
        ;;
    media-server-only)
        firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=35000-65000/udp --add-port=8840-8845/udp --add-port=8840-8845/tcp --set-description="PortSIP Media Server"
        ;;
    meeting-server-only)
        #firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=50000-65000/udp --add-port=8928-8933/udp --add-port=8928-8933/tcp --set-description="PortSIP Meeting Server"
        firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=8928-8933/udp --add-port=8928-8933/tcp --set-description="PortSIP Meeting Server"
        ;;
    vr-server-only)
        #firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=50000-65000/udp  --add-port=8922-8927/udp --add-port=8922-8927/tcp --set-description="PortSIP VR Server"
        firewall-cmd --permanent --service=${pbx_extend_svc_type} --add-port=8922-8927/udp --add-port=8922-8927/tcp --set-description="PortSIP VR Server"
        ;;
    esac

    firewall-cmd --permanent --add-service=${pbx_extend_svc_type}
    firewall-cmd --reload
    systemctl restart firewalld
    firewall-cmd --permanent --info-service=${pbx_extend_svc_type}
    echo ""
    echo "====>Firewalld configure done"
    echo ""
}

create() {
    echo ""
    echo "==> try to create extend service <=="
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    parse_cmd_parameters $@
    verify_parameters

    set_firewall

    # change work directory
    if [ ! -d "./$pbx_extend_svc_type" ]; then
        mkdir $pbx_extend_svc_type
    fi
    cd $pbx_extend_svc_type

    echo ""
    echo "datapath       : $data_path"
    echo "ip(local)      : $local_ip_address"
    echo "ip(pbx)        : $pbx_ip_address"
    echo "pbx img        : $pbx_img"
    echo "extend service : $pbx_extend_svc_type"
    echo "extend name    : $pbx_extend_svc_name"
    echo ""

    # check if the data path exists
    pbx_extend_svc_datapath="$data_path/$pbx_extend_svc_type"
    if [ ! -d "$pbx_extend_svc_datapath" ]; then
        echo "the current data path $pbx_extend_svc_datapath does not exist, try to create it"
        mkdir -p $pbx_extend_svc_datapath
        echo "created"
        echo ""
    fi

    # write configure file
    cat << EOF > .configure_extend
PBX_DATA_PATH=$data_path
IP_ADDRESS=$local_ip_address
PBX_IP_ADDRESS=$pbx_ip_address
PBX_IMG=$pbx_img
EXTEND_SVC_TYPE=$pbx_extend_svc_type
EXTEND_SVC_NAME=$pbx_extend_svc_name
EXTEND_SVC_DATAPATH=$pbx_extend_svc_datapath
EOF

    # get product version
    docker image pull $pbx_img
    pbx_production_version=$(export_pbx_production_version)
    if [ -z "$pbx_production_version" ]; then
        echo "no 'version' information found in the docker image, just use '16.0'"
        pbx_production_version="16.0.1"
    fi
    echo "current pbx version $pbx_production_version"
    # pbx >= 16.1
    local ret=$(is_pbx_production_version_less_than_16_1)
    # ret: 1 for success and 0 for failure
    if [ $ret -eq 1 ]; then
      echo "when the pbx version is less than 16.1.0, the extended service is not supported."
      exit -1
    fi

    export_configure
    initdt

    # run pbx extend service
    docker compose -f docker-compose.yml up -d

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
    if [ -z "$pbx_extend_svc_type" ]; then
        echo "Option -s not specified"
        exit -1
    fi
    # change work directory
    if [ ! -d "./$pbx_extend_svc_type" ]; then
        echo "no service configuration found"
        exit -1
    fi
    cd $pbx_extend_svc_type

    echo ""
    echo "${operator} service $pbx_extend_svc_type"
    echo ""
  
    case $operator in
    restart)
        docker compose -f docker-compose.yml stop -t 300
        sleep 3
        docker compose -f docker-compose.yml start
        ;;

    status)
        docker compose -f docker-compose.yml ls -a
        docker compose -f docker-compose.yml ps -a
        ;;

    stop)
        docker compose -f docker-compose.yml stop -t 300
        ;;

    start)
        docker compose -f docker-compose.yml start
        ;;

    rm)
        firewall-cmd -q --permanent --delete-service=${pbx_extend_svc_type} || true
        firewall-cmd --reload
        local volume_name="pbx-data-$pbx_extend_svc_type"
        docker compose -f docker-compose.yml down
        docker volume rm `docker volume ls  -q | grep ${volume_name}` || true
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