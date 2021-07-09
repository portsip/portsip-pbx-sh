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
    sudo systemctl stop ufw
    sudo systemctl disable ufw
    sudo systemctl enable firewalld
    sudo systemctl start firewalld
    sudo firewall-cmd --zone=trusted --remove-interface=docker0 --permanent
    sudo firewall-cmd --reload
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --permanent --new-service=portsip-pbx
    sudo firewall-cmd --permanent --service=portsip-pbx --add-port=5060/udp --add-port=45000-64999/udp --add-port=25000-34999/udp --add-port=5065/tcp --add-port=8899-8900/tcp --add-port=8881-8888/tcp --set-description="PortSIP PBX"
    sudo firewall-cmd --permanent --add-service=portsip-pbx
    sudo firewall-cmd --reload
}

Install_docker_on_centos(){
    sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2 firewalld
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum makecache fast
    sudo yum install -y docker-ce-20.10.7 docker-ce-cli-20.10.7 containerd.io
    sudo systemctl enable docker
    sudo systemctl start docker

    set_firewall
}

Install_docker_on_ubuntu(){
    sudo apt-get remove -y  docker docker-engine docker.io containerd runc
    sudo apt update -y
    sudo apt upgrade -y 
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common firewalld
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt-get update -y 
    sudo apt-get install docker-ce -y
    sudo systemctl enable docker
    sudo systemctl start docker

    set_firewall
}

Install_docker_on_debian(){
    sudo apt-get remove docker docker-engine docker.io containerd runc
    sudo apt update -y 
    sudo apt upgrade -y 
    sudo apt-get install apt-transport-https ca-certificates curl gnupg lsb-release firewalld
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -y
    sudo apt-get install docker-ce docker-ce-cli containerd.io -y
    sudo systemctl enable docker
    sudo systemctl start docker

    set_firewall
}

system_check