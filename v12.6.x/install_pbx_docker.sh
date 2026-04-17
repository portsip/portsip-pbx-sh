#!/bin/bash

system_check(){
    if [  -f "/etc/redhat-release" ];then
        Install_docker_on_centos
    elif [ -f "/etc/lsb-release" ];then
        Install_docker_on_ubuntu
    elif [ -f "/etc/debian_version" ];then
        Install_docker_on_debian
    else
        echo "Unknown operating system"
        exit
    fi
}

set_firewall(){
    echo ""
    echo "====>Stop the ufw"
    echo ""
    systemctl stop ufw
    systemctl disable ufw
    echo ""
    echo "====>Enable the firewalld"
    echo ""
    systemctl enable firewalld
    systemctl start firewalld
    echo ""
    echo "====>Configure PBX's default firewall rules"
    echo ""
    firewall-cmd --zone=trusted --remove-interface=docker0 --permanent
    firewall-cmd --reload
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --new-service=portsip-pbx
    firewall-cmd --permanent --service=portsip-pbx --add-port=5060/udp --add-port=45000-64999/udp --add-port=25000-34999/udp --add-port=5065/tcp --add-port=8899-8900/tcp --add-port=8881-8888/tcp --set-description="PortSIP PBX"
    firewall-cmd --permanent --add-service=portsip-pbx
    firewall-cmd --reload
    systemctl restart firewalld
    echo ""
    echo "====>Firewalld configure done"
    echo ""
}

Install_docker_on_centos(){
    echo ""
    echo "====>Starting to install on centos"
    echo ""
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    yum install -y yum-utils device-mapper-persistent-data lvm2 firewalld
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache fast
    echo ""
    echo "====>Try to install the docker"
    echo ""
    yum install -y docker-ce-20.10.7 docker-ce-cli-20.10.7 containerd.io
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====>Successfully installed the docker"
    echo ""

    set_firewall

    systemctl start docker
}

Install_docker_on_ubuntu(){
    echo ""
    echo "====>Starting to install on ubuntu"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove -y  docker docker-engine docker.io containerd runc
    apt update -y
    apt upgrade -y
    echo ""
    echo "====>System updated"
    echo ""
    echo "====>Try to install firewalld"
    echo ""
    apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common firewalld
    if [ $? -ne 0 ];then
        echo "Failed to install dependencies"
        exit 1
    fi
    echo ""
    echo "====>Firewalld installed"
    echo ""
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg |  apt-key add -
    if [ $? -ne 0 ];then
        echo "Failed to install gpg"
        exit 1
    fi
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    if [ $? -ne 0 ];then
        echo "Failed to add docker repo"
        exit 1
    fi
    apt-get update -y 
    if [ $? -ne 0 ];then
        echo "Failed to update software packages"
        exit 1
    fi
    echo ""
    echo "====>Try to install the docker"
    echo ""
    apt-get install docker-ce -y
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====>Successfully installed the docker"
    echo ""

    set_firewall

    systemctl start docker
}

Install_docker_on_debian(){
    echo ""
    echo "====>Starting to install on debian"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove docker docker-engine docker.io containerd runc
    apt update -y 
    apt upgrade -y
    echo ""
    echo "====>System updated"

    echo ""
    echo "====>Try to install the firewalld"
    echo ""
    apt-get install apt-transport-https ca-certificates curl gnupg lsb-release firewalld -y
    systemctl stop firewalld
    echo ""
    echo "====>Firewalld installed"
    echo ""

    echo "====>Try to install the docker"
    echo ""
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install docker-ce docker-ce-cli containerd.io -y
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====>Successfully installed the docker"
    echo ""

    sed -i 's#IndividualCalls=no#IndividualCalls=yes#g' /etc/firewalld/firewalld.conf

    set_firewall

    systemctl start docker
}

system_check