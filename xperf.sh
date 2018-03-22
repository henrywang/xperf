#!/bin/bash

set -euf

STOP_DSTAT="kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') >/dev/null 2>&1 || true"
STOP_IPERF="killall iperf >/dev/null 2>&1 || true"

# load xperf config and workload
. workload.conf
. xperf.conf

ExecCommandOnClient() {
    ssh -q -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${CLIENT_IP} $1
    return $?
}

ExecCommandOnServer() {
    ssh -q -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${SERVER_IP} $1
    return $?
}

# clear result folder if exists
ExecCommandOnClient "rm -rf ${RESULT_DIR}"
ExecCommandOnServer "rm -rf ${RESULT_DIR}"

# creat result folder
ExecCommandOnClient "mkdir ${RESULT_DIR}"
ExecCommandOnServer "mkdir ${RESULT_DIR}"

# stop iperf and dstat on both sides
ExecCommandOnClient "$STOP_IPERF"
ExecCommandOnServer "$STOP_IPERF"
ExecCommandOnClient "$STOP_DSTAT"
ExecCommandOnServer "$STOP_DSTAT"

ExecCommandOnClient "[ ! -e /usr/local/bin/dstat ]" && scp $IPERF_FILE ${IPERF_USER}@${CLIENT_IP}:/usr/local/bin
ExecCommandOnServer "[ ! -e /usr/local/bin/dstat ]" && scp $IPERF_FILE ${IPERF_USER}@${SERVER_IP}:/usr/local/bin

ExecCommandOnClient "[ ! -e /usr/local/bin/dstat ]" && scp $DSTAT_FILE ${IPERF_USER}@${CLIENT_IP}:/usr/local/bin
ExecCommandOnServer "[ ! -e /usr/local/bin/dstat ]" && scp $DSTAT_FILE ${IPERF_USER}@${SERVER_IP}:/usr/local/bin

for ((i=1; i<=${ITERATIONS}; i++)); do
    # stop dstat on both sides
    ExecCommandOnClient "$STOP_DSTAT"
    ExecCommandOnServer "$STOP_DSTAT"
    sleep 1

    DSTAT_CLIENT="export DSTAT_TIMEFMT='%Y/%m/%d %H:%M:%S'; nohup dstat -tv --output ${RESULT_DIR}/run${i}-client-dstat.csv 10 >/dev/null 2>&1 &"
    DSTAT_SERVER="export DSTAT_TIMEFMT='%Y/%m/%d %H:%M:%S'; nohup dstat -tv --output ${RESULT_DIR}/run${i}-server-dstat.csv 10 >/dev/null 2>&1 &"
    echo -e "Run${i}: start dstat on client and server.\n-----------------"
    ExecCommandOnClient "$DSTAT_CLIENT"
    ExecCommandOnServer "$DSTAT_SERVER"
    
    for bandwidth in ${LOAD[*]}; do
        echo -e "Run${i}: start iperf on ${LOAD[*]}\n-----------------"
        IPERF_CLIENT="echo \$(date +%Y%m%d_%H%M%S) | tee ${RESULT_DIR}/run${i}-${bandwidth}-client.iperf && iperf -u -c ${SERVER_IP} -d -b ${bandwidth} -t ${DURATION} -i ${INTERVAL} -B ${CLIENT_IP} -L 6001 -e -x CSV -p 5001 -l 104 | tee -a ${RESULT_DIR}/run${i}-${bandwidth}-client.iperf"
        IPERF_SERVER="nohup iperf -s -i 10 -u -e -p 5001 -x CSV > ${RESULT_DIR}/run${i}-${bandwidth}-server.iperf &"

        # stop iperf
        ExecCommandOnClient "$STOP_IPERF"
        ExecCommandOnServer "$STOP_IPERF"
        sleep 1

        echo -e "Run${i}: start iperf on server.\n-----------------"
        ExecCommandOnServer "$IPERF_SERVER"
        sleep 1

        echo -e "Run${i}: ${bandwidth} load.\n-----------------"
        ExecCommandOnClient "$IPERF_CLIENT"

        # stop iperf
        ExecCommandOnServer "$STOP_IPERF"
    done

    # stop dstat
    ExecCommandOnClient "$STOP_DSTAT"
    ExecCommandOnServer "$STOP_DSTAT"
done