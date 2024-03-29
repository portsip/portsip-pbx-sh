#!/bin/bash

data_drop_days=5

init(){
    # disable firewall
    systemctl stop firewalld.service || true
    #systemctl disable firewalld.service || true
    systemctl stop ufw || true
    #ufw disable || true
    #systemctl disable ufw || true
    echo "stopped firewall"

    # disable selinux
    #setenforce 0 || true

    #sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config || true
    #sed -i 's#SELINUX=permissive#SELINUX=disabled#g' /etc/selinux/config || true
    #echo "disabled selinux"
}

parse_cmd_parameters() {
    echo "args:$@"

    shift
    
    while getopts k: option
    do 
        case "${option}" in
            k)
                data_drop_days=${OPTARG}
                ;;
        esac
    done
}

generate_svc_config(){
cat >./docker-compose.yml <<EOL
# WARNING: DO NOT CHANGE THIS AUTOMATICALLY GENERATED FILE
# WARNING: DO NOT CHANGE THIS AUTOMATICALLY GENERATED FILE
# WARNING: DO NOT CHANGE THIS AUTOMATICALLY GENERATED FILE
version: '2.1'

volumes:
    prometheus_data: {}
    grafana_data: {}

services:
  trace-heplify-server:
    image: portsip/trace-server:heplify
    container_name: trace-heplify-server
    ports:
      - "9060:9060"
      - "9060:9060/udp"
      - "9061:9061/tcp"
    command:
      - './heplify-server'
    environment:
      - "HEPLIFYSERVER_HEPADDR=0.0.0.0:9060"
      - "HEPLIFYSERVER_HEPTCPADDR=0.0.0.0:9061"
      - "HEPLIFYSERVER_DBSHEMA=homer7"
      - "HEPLIFYSERVER_DBDRIVER=postgres"
      - "HEPLIFYSERVER_DBADDR=trace-db:5432"
      - "HEPLIFYSERVER_DBUSER=root"
      - "HEPLIFYSERVER_DBPASS=homerSeven"
      - "HEPLIFYSERVER_DBDATATABLE=homer_data"
      - "HEPLIFYSERVER_DBCONFTABLE=homer_config"
      - "HEPLIFYSERVER_DBROTATE=true"
      - "HEPLIFYSERVER_DBDROPDAYS=${data_drop_days}"
      - "HEPLIFYSERVER_LOGLVL=info"
      - "HEPLIFYSERVER_LOGSTD=true"
      - "HEPLIFYSERVER_DEDUP=false"
      - HEPLIFYSERVER_ALEGIDS=X-Session-Id
      - HEPLIFYSERVER_FORCEALEGID=false
      - HEPLIFYSERVER_CUSTOMHEADER=X-Session-Id,X-CID
      - HEPLIFYSERVER_SIPHEADER=callid,callid_aleg,method,ruri_user,ruri_domain,from_user,from_domain,from_tag,to_user,to_domain,to_tag,via,contact_user
    restart: unless-stopped
    depends_on:
      - trace-db
    expose:
      - 9090
      - 9096
    labels:
      org.label-schema.group: "monitoring"

  trace-webapp:
    container_name: trace-webapp
    image: portsip/trace-server:webapp
    environment:
      - "DB_HOST=trace-db"
      - "DB_USER=root"
      - "DB_PASS=homerSeven"
    restart: unless-stopped
    ports:
      - "9080:80"
    depends_on:
      trace-db:
        condition: service_healthy

  trace-db:
    container_name: trace-db
    image: portsip/trace-server:postgres11-alpine
    environment:
      POSTGRES_PASSWORD: homerSeven
      POSTGRES_USER: root
    expose:
      - 5432
    restart: unless-stopped
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "psql -h 'localhost' -U 'root' -c '\\\\l'"]
      interval: 1s
      timeout: 3s
      retries: 30
EOL
}

# install docker and docker compose plugin
install_docker_on_centos(){
    echo ""
    echo "====>Starting to install on centos"
    echo ""
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    yum install -y yum-utils device-mapper-persistent-data lvm2
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    yum makecache fast
    echo ""
    echo "====>Try to install docker"
    echo ""
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    #systemctl stop docker
    echo ""
    echo "====>Successfully to install the docker"
    echo ""
}

# install docker and docker compose plugin
install_docker_on_ubuntu(){
    echo ""
    echo "====>Starting to install on ubuntu"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove -y  docker docker-engine docker.io containerd runc || true
    apt update -y
    dpkg --configure -a || true
    DEBIAN_FRONTEND=noninteractive apt upgrade -y || true
    echo ""
    echo "====>System updated"
    echo ""
    DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg gnupg-agent software-properties-common lsb-release
    echo ""
    mkdir -p /etc/apt/keyrings
    rm -f /etc/apt/keyrings/docker.gpg || true
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    DEBIAN_FRONTEND=noninteractive apt-get update -y 
    echo ""
    echo "====>Try to install the docker"
    echo ""
    DEBIAN_FRONTEND=noninteractive apt-get install docker-ce docker-compose-plugin -y
    systemctl enable docker
    #systemctl stop docker
    echo ""
    echo "====Successfully to install the docker"
    echo ""
}

# install docker and docker compose plugin
install_docker_on_debian(){
    echo ""
    echo "====>Starting to install on debian"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove docker docker-engine docker.io containerd runc || true
    apt update -y 
    apt upgrade -y
    echo ""
    echo "====>System updated"

    echo ""
    apt-get install apt-transport-https ca-certificates curl gnupg lsb-release -y
    echo ""

    echo "====>Try to install docker"
    echo ""
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
    systemctl enable docker
    #systemctl stop docker
    echo ""
    echo "====>Successfully to install the docker"
    echo ""
}

install(){
    # disable firewall&selinux
    init
    echo "try to install docker"
    if [  -f "/etc/redhat-release" ];then
        install_docker_on_centos
    elif [ -f "/etc/lsb-release" ];then
        install_docker_on_ubuntu
    elif [ -f "/etc/debian_version" ];then
        install_docker_on_debian
    else
        echo "os not support"
        exit -1
    fi
    echo "succeed to install docker"

    systemctl restart docker
}

start(){
    # up trace server
    generate_svc_config
    echo "try to start trace server"
    systemctl start docker || exit -1
    echo ""
    docker compose up -d || exit -1
    echo ""
    echo "succeed to start trace server"
}

stop(){
    # stop trace server
    generate_svc_config
    echo "try to stop trace server"
    echo ""
    docker compose stop
    echo ""
    echo "succeed to stop trace server"
}

remove(){
    stop
    echo ""
    docker compose rm -f || true
    echo ""
    echo "succed to remove trace server containers"
    rm -rf ./postgres-data
    echo "succeed to remove trace server data"
}

case $1 in
    start)
        parse_cmd_parameters $@
        install
        start
        ;;
    stop)
        stop
        ;;
    remove)
        remove
        ;;
    rm)
        remove
        ;;
    *)
        echo "unknown action"
        exit -1
        ;;
esac
