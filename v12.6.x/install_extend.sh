#!/bin/bash

set -ex

pbx_addr=
pbx_private_addr=
pbx_public_addr=
db_passwd=
volumn=
img=
service=
cfg_path=
#only for conference ip
myself_private_addr= 

help() {
echo "
\n
    install_ext_media.sh [options]
\n
\noptions:
\n    -a  (required when PBX public IP empty) : PBX private IP address
\n    -p  (required when PBX private IP empty) : PBX public IP address
\n    -d  (required) : PBX DB password
\n    -i  (required) : PBX docker image
\n    -s [media | conference] (required) : PBX extend service
\n    -v  (optional) : volumn (default: /var/lib/portsip/{media|conference})
\n    -m  (required when service is conference) : host private IP address (only for conference)
"
    exit -1;
}

set_firewall(){

    echo ""
    echo "====>Stop the ufw" 
    echo ""
    systemctl stop ufw || true
    systemctl disable ufw || true
    echo ""
    echo "====>Enable the firewalld"
    echo ""
    systemctl enable firewalld || true
    systemctl start firewalld || true
    echo ""
    echo "====>Configure PBX's default firewall rules"
    echo ""
    firewall-cmd --permanent --new-service=portsip-pbx || true
    firewall-cmd --permanent --service=portsip-pbx --add-port=45000-65000/udp --add-port=8896/tcp --set-description="PortSIP PBX" || true
    firewall-cmd --permanent --add-service=portsip-pbx || true
    firewall-cmd --reload  || true
    systemctl restart firewalld  || true
    echo ""
    echo "====>Firewalld configure done"
    echo ""
}

export_supervisor_cfg() {

    mkdir -p ${cfg_path} || true

    if [ "${service}" = "media" ]
    then
        echo " export media configure file"
cat <<END > ${cfg_path}/media.conf
[program:mediaserver]
command=/usr/local/bin/mediaserver -D %(ENV_PORTSIP_DATADIR)s start
;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
numprocs=1                    ; number of processes copies to start (def 1)
;directory=/var/lib/portsip                ; directory to cwd to before exec (def no cwd)
;umask=022                     ; umask for process (default None)
priority=20                  ; the relative start priority (default 999)
autostart=true                ; start at supervisord start (default: true)
;autorestart=unexpected        ; whether/when to restart (default: unexpected)
startsecs=1                   ; number of secs prog must stay running (def. 1)
startretries=3                ; max # of serial start failures (default 3)
;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
;stopsignal=QUIT               ; signal used to kill process (default TERM)
stopwaitsecs=30               ; max num secs to wait b4 SIGKILL (default 10)
;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
;killasgroup=false             ; SIGKILL the UNIX process group (def false)
user=portsip                   ; setuid to this UNIX account to run the program
;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
;stdout_logfile=/a/path        ; stdout log path, NONE for none; default AUTO
;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
;stdout_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
;stdout_events_enabled=false   ; emit events on stdout writes (default false)
;stderr_logfile=/a/path        ; stderr log path, NONE for none; default AUTO
;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
;stderr_logfile_backups=10     ; # of stderr logfile backups (default 10)
;stderr_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
;stderr_events_enabled=false   ; emit events on stderr writes (default false)
;serverurl=AUTO                ; override serverurl computation (childutils)
END
    else
        echo " export conference configure file"
cat <<END > ${cfg_path}/conf.conf
[program:conf]
command=/usr/local/bin/conf -D %(ENV_PORTSIP_DATADIR)s start
;process_name=%(program_name)s ; process_name expr (default %(program_name)s)
numprocs=1                    ; number of processes copies to start (def 1)
;directory=/var/lib/portsip                ; directory to cwd to before exec (def no cwd)
;umask=022                     ; umask for process (default None)
priority=20                  ; the relative start priority (default 999)
autostart=true                ; start at supervisord start (default: true)
;autorestart=unexpected        ; whether/when to restart (default: unexpected)
startsecs=1                   ; number of secs prog must stay running (def. 1)
startretries=3                ; max # of serial start failures (default 3)
;exitcodes=0,2                 ; 'expected' exit codes for process (default 0,2)
;stopsignal=QUIT               ; signal used to kill process (default TERM)
stopwaitsecs=30               ; max num secs to wait b4 SIGKILL (default 10)
;stopasgroup=false             ; send stop signal to the UNIX process group (default false)
;killasgroup=false             ; SIGKILL the UNIX process group (def false)
user=portsip                   ; setuid to this UNIX account to run the program
;redirect_stderr=true          ; redirect proc stderr to stdout (default false)
;stdout_logfile=/a/path        ; stdout log path, NONE for none; default AUTO
;stdout_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
;stdout_logfile_backups=10     ; # of stdout logfile backups (default 10)
;stdout_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
;stdout_events_enabled=false   ; emit events on stdout writes (default false)
;stderr_logfile=/a/path        ; stderr log path, NONE for none; default AUTO
;stderr_logfile_maxbytes=1MB   ; max # logfile bytes b4 rotation (default 50MB)
;stderr_logfile_backups=10     ; # of stderr logfile backups (default 10)
;stderr_capture_maxbytes=1MB   ; number of bytes in 'capturemode' (default 0)
;stderr_events_enabled=false   ; emit events on stderr writes (default false)
;serverurl=AUTO                ; override serverurl computation (childutils)
END

    fi
}

start() {

    container_name=portsip-pbx-extend-${service}

    docker rm -f ${container_name} || true

    if [ -d "${volumn}" ];
    then
        rm -rf ${volumn} || true
    fi

    mkdir -p ${volumn} || true
    docker container run -d --name ${container_name} \
            --cap-add=SYS_PTRACE \
            --network=host \
            -v ${volumn}:/var/lib/portsip \
            -v /etc/localtime:/etc/localtime:ro \
            -v ${cfg_path}:/etc/supervisor/conf.d \
            -e POSTGRES_PASSWORD=${db_passwd} \
            -e POSTGRES_LISTEN_ADDRESSES=* \
            -e IP_ADDRESS=${pbx_addr} \
            -e PRIVATE_IP_ADDRESS=${pbx_addr} ${img}
    sleep 120;

    docker stop -t 120 ${container_name} || true

# export system.ini
cat <<END > ${volumn}/system.ini
[global]
private_ipaddr_v4 = ${pbx_private_addr}
public_ipaddr_v4 = ${pbx_public_addr}
private_ipaddr_v6 = 
public_ipaddr_v6 = 
event_url = https://www.portsip.com/news/portsip_news.json

[database]
host = ${pbx_addr}
port = 5432
username = portsip
password = ${db_passwd}
dbname = pucs
dcid = 1
wid = 1

[filegate]
backend = wdfs
host = ${pbx_addr}
port = 8903

[wdfs]
master_ipaddr = ${pbx_addr}
master_port = 9333
volume_port = 8882
filer_port = 8889
volume_size_limit = 30000

[s3]
endpoint = 
cred_id = 
cred_secret = 
region = 
bucket = 

[log]
rpc_port = 8874

[pbx]
rpc_port = 8898
enable_call_recovery = true

[gateway]
rest_http_port = 8899
rest_https_port = 8900
session_key = 

[voicemail]
rpc_port = 8894

[conf]
name = ${myself_private_addr}
rpc_port = 8886

[ivr]
rpc_port = 8890

[callqueue]
rpc_port = 8892

[mediaserver]
rpc_port = 8896
rtp_port_begin = 45000
rtp_port_end = 65000
session_life_time = 300
recorder_file_format = 1
recorder_video_framerate = 15
recorder_video_bitratekbps = 500
recorder_video_layout = 1

[moh]
rpc_port = 8902

[scheduler]
rpc_port = 6460
file_port = 6461
file_download_timeout_ms = 60000
file_upload_timeout_ms = 60000
file_delete_timeout_ms = 10000
reap_system_interval = 60000
scheduled_backup_interval = 60000

[wssp]
rpc_port = 8904
wss_port = 8885
END

    docker start ${container_name} || true

}

# parse parameters
while getopts a:p:d:v:i:s:m: option
do 
    case "${option}" in
        a)
            pbx_private_addr=${OPTARG}
            ;;
        p)
            pbx_public_addr=${OPTARG}
            ;;
        d)
            db_passwd=${OPTARG}
            ;;
        v)
            volumn=${OPTARG}
            ;;
        i)
            img=${OPTARG}
            ;;
        s)
            service=${OPTARG}
            ;;
        m)
            myself_private_addr=${OPTARG}
            ;;
    esac
done

if [ -z "${pbx_private_addr}" ] && [ -z "${pbx_public_addr}" ]; then
    echo ""
    echo "\t empty pbx address"
    help
fi

if [ -n "${pbx_public_addr}" ]; then
    pbx_addr=${pbx_public_addr}
fi

if [ -n "${pbx_private_addr}" ]; then
    pbx_addr=${pbx_private_addr}
fi

if [ -z "${db_passwd}" ]; then
    echo ""
    echo "\t empty db password"
    help
fi

if [ -z "${img}" ]; then
    echo ""
    echo "\t empty docker image"
    help
fi

if [ -z "${service}" ]; then
    echo ""
    echo "\t need set to media or conference"
    help
fi

if [ ${service} != media ] && [ ${service} != conference ]; then
    echo ""
    echo "\t need set to media or conference"
    help
fi

if [ -z "${volumn}" ]; then
    echo "\t empty volumn host path, use default path(/var/lib/portsip/{service})"
    volumn=/var/lib/portsip/${service}
fi

if [ ${service} != media ]; then 
    if [ -z "${myself_private_addr}" ]; then
        echo ""
        echo "\t service conference, MUST setup -m"
        help
    fi
fi

cfg_path=/etc/portsip/extend/conf.d/${service}

#set_firewall

export_supervisor_cfg

start
