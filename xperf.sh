#!/bin/bash

set -euf

STOP_DSTAT="kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') >/dev/null 2>&1 || true"
STOP_IPERF="pkill iperf >/dev/null 2>&1 || true"

if [ $# -eq 0 ]; then
    WORKLOAD="workload.conf"
    XPERF="xperf.conf"
elif [ $# -eq 2 ]; then
    WORKLOAD=$1
    XPERF=$2
else
    echo "$0: usage: xperf <workload config> <xperf config>"
    exit 1
fi

# load xperf config and workload
. $WORKLOAD
. $XPERF

ExecCommandOverSSH() {
    case $1 in
        "client")
            ssh -q -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${CLIENT_IP_MGT} $2
            return $?
            ;;
        "server")
            ssh -q -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${SERVER_IP_MGT} $2
            return $?
            ;;
        *)
            echo -e "Sorry, I can not get what you want"
            return 1
            ;;
    esac
}

RunDstatOverSSH() {
    ExecCommandOverSSH $1 "export DSTAT_TIMEFMT='%Y/%m/%d %H:%M:%S'; nohup dstat -tv --output ${RESULT_DIR}/run$2-$1-dstat.csv 10 >/dev/null 2>&1 &"
}

# e.g. RunIperfOverSSH "client" 1 "140M"
RunIperfOverSSH() {
    case $1 in
        "client")
            ExecCommandOverSSH $1 "echo \$(date +%Y%m%d_%H%M%S) > ${RESULT_DIR}/run$2-$3-$11.iperf; nohup iperf -u -c ${SERVER_IP_IPERF} -d -b $3 -t ${DURATION} -i ${INTERVAL} -B ${CLIENT_IP_IPERF} -L ${CLIENT_PORT} -e -x CSV -p ${SERVER_PORT} -l ${UDP_PAYLOAD} >> ${RESULT_DIR}/run$2-$3-$11.iperf &"
            ExecCommandOverSSH $1 "echo \$(date +%Y%m%d_%H%M%S) | tee ${RESULT_DIR}/run$2-$3-$12.iperf; iperf -u -c ${SERVER_IP_IPERF} -d -b $3 -t ${DURATION} -i ${INTERVAL} -B ${CLIENT_IP_IPERF} -L ${CLIENT_PORT_SEC} -e -x CSV -p ${SERVER_PORT_SEC} -l ${UDP_PAYLOAD} | tee -a ${RESULT_DIR}/run$2-$3-$12.iperf"
            ;;
        "server")
            ExecCommandOverSSH $1 "nohup iperf -s -i ${INTERVAL} -u -e -p ${SERVER_PORT} -x CSV > ${RESULT_DIR}/run$2-$3-$11.iperf &"
            ExecCommandOverSSH $1 "nohup iperf -s -i ${INTERVAL} -u -e -p ${SERVER_PORT_SEC} -x CSV > ${RESULT_DIR}/run$2-$3-$12.iperf &"
            ;;
        *)
            echo -e "Sorry, I can not get what you want"
            return 1
            ;;
    esac
}

# reboot client and server, wait ssh ready
ResetOverSSH() {
    rpm -qa | grep nmap || yum -y install nmap
    ExecCommandOverSSH "client" "reboot" || true
    ExecCommandOverSSH "server" "reboot" || true
    sleep 1
    while : ;
    do
        nmap -p22 ${CLIENT_IP_MGT} -oG - | grep -q 22/open && nmap -p22 ${SERVER_IP_MGT} -oG - | grep -q 22/open && break
    done
}

# collect result file
CollectResult() {
    LOCAL_DIR="${TEST_NAME}-${RESULT_DIR}"
    [[ -d $LOCAL_DIR ]] || mkdir -p $LOCAL_DIR
    scp -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${CLIENT_IP_MGT}:\$HOME/${RESULT_DIR}/* $LOCAL_DIR
    scp -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${SERVER_IP_MGT}:\$HOME/${RESULT_DIR}/* $LOCAL_DIR
}

# system settings
SetSystem() {
    ExecCommandOverSSH "client" "sysctl -w net.core.rmem_default=$RMEM_DEFAULT && sysctl -w net.core.rmem_max=$RMEM_MAX"
    ExecCommandOverSSH "server" "sysctl -w net.core.rmem_default=$RMEM_DEFAULT && sysctl -w net.core.rmem_max=$RMEM_MAX"
}

# clear result folder if exists
ExecCommandOverSSH "client" "rm -rf ${RESULT_DIR}"
ExecCommandOverSSH "server" "rm -rf ${RESULT_DIR}"

# creat result folder
ExecCommandOverSSH "client" "mkdir -p ${RESULT_DIR}"
ExecCommandOverSSH "server" "mkdir -p ${RESULT_DIR}"

# stop iperf and dstat on both sides
ExecCommandOverSSH "client" "$STOP_IPERF"
ExecCommandOverSSH "server" "$STOP_IPERF"
ExecCommandOverSSH "client" "$STOP_DSTAT"
ExecCommandOverSSH "server" "$STOP_DSTAT"

ExecCommandOverSSH "client" "[[ -e /usr/local/bin/dstat ]]" || scp -i ${SSH_PRIVATE_KEY} $IPERF_FILE ${IPERF_USER}@${CLIENT_IP_MGT}:/usr/local/bin
ExecCommandOverSSH "server" "[[ -e /usr/local/bin/dstat ]]" || scp -i ${SSH_PRIVATE_KEY} $IPERF_FILE ${IPERF_USER}@${SERVER_IP_MGT}:/usr/local/bin

ExecCommandOverSSH "client" "[[ -e /usr/local/bin/dstat ]]" || scp -i ${SSH_PRIVATE_KEY} $DSTAT_FILE ${IPERF_USER}@${CLIENT_IP_MGT}:/usr/local/bin
ExecCommandOverSSH "server" "[[ -e /usr/local/bin/dstat ]]" || scp -i ${SSH_PRIVATE_KEY} $DSTAT_FILE ${IPERF_USER}@${SERVER_IP_MGT}:/usr/local/bin

for ((i=1; i<=${ITERATIONS}; i++));
do
    # reboot client and server
    ResetOverSSH

    # system setting
    SetSystem
    
    # stop dstat on both sides
    ExecCommandOverSSH "client" "$STOP_DSTAT"
    ExecCommandOverSSH "server" "$STOP_DSTAT"
    sleep 1

    echo -e "Run${i}: start dstat on client and server.\n-----------------"
    RunDstatOverSSH "client" $i
    RunDstatOverSSH "server" $i
    
    for bandwidth in ${LOAD[*]};
    do
        echo -e "Run${i}: start iperf on ${LOAD[*]}\n-----------------"
        # stop iperf
        ExecCommandOverSSH "client" "$STOP_IPERF"
        ExecCommandOverSSH "server" "$STOP_IPERF"
        sleep 1

        echo -e "Run${i}: start iperf on server.\n-----------------"
        RunIperfOverSSH "server" $i $bandwidth
        sleep 1

        echo -e "Run${i}: ${bandwidth} load.\n-----------------"
        RunIperfOverSSH "client" $i $bandwidth

        # stop iperf
        ExecCommandOverSSH "server" "$STOP_IPERF"
    done

    # stop dstat
    ExecCommandOverSSH "client" "$STOP_DSTAT"
    ExecCommandOverSSH "server" "$STOP_DSTAT"
done

CollectResult