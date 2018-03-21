#!/bin/bash

set -euf

. workload.conf
. xperf.conf

echo "INFO: Clear result folder if exists."
ssh ${IPERF_USER}@${CLIENT_IP} "rm -rf ${RESULT_DIR}"
ssh ${IPERF_USER}@${SERVER_IP} "rm -rf ${RESULT_DIR}"

echo "INFO: Creating result folder."
ssh ${IPERF_USER}@${CLIENT_IP} "mkdir ${RESULT_DIR}"
ssh ${IPERF_USER}@${SERVER_IP} "mkdir ${RESULT_DIR}"

echo "INFO: Clear iperf and dstat on both sides."
ssh ${IPERF_USER}@${CLIENT_IP} "killall iperf || true"
ssh ${IPERF_USER}@${SERVER_IP} "killall iperf || true"
ssh ${IPERF_USER}@${CLIENT_IP} "kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') || true"
ssh ${IPERF_USER}@${SERVER_IP} "kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') || true"

echo "INFO: Copy iperf to client and server."
if [ ! -f /usr/local/bin/iperf ]; then scp $IPERF_FILE ${IPERF_USER}@${CLIENT_IP}:/usr/local/bin; fi
if [ ! -f /usr/local/bin/iperf ]; then scp $IPERF_FILE ${IPERF_USER}@${SERVER_IP}:/usr/local/bin; fi

echo "INFO: Copy dstat to client and server."
if [ ! -f /usr/local/bin/dstat ]; then scp $DSTAT_FILE ${IPERF_USER}@${CLIENT_IP}:/usr/local/bin; fi
if [ ! -f /usr/local/bin/dstat ]; then scp $DSTAT_FILE ${IPERF_USER}@${SERVER_IP}:/usr/local/bin; fi

for ((i=1; i<=${ITERATIONS}; i++)); do
    echo "INFO: Clear dstat on both sides."
    ssh ${IPERF_USER}@${CLIENT_IP} "kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') || true"
    ssh ${IPERF_USER}@${SERVER_IP} "kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') || true"
    sleep 1

    DSTAT_CLIENT="export DSTAT_TIMEFMT='%Y/%m/%d %H:%M:%S'; nohup dstat -tv --output ${RESULT_DIR}/run${i}-client-dstat.csv 10 >/dev/null 2>&1 &"
    DSTAT_SERVER="export DSTAT_TIMEFMT='%Y/%m/%d %H:%M:%S'; nohup dstat -tv --output ${RESULT_DIR}/run${i}-server-dstat.csv 10 >/dev/null 2>&1 &"
    echo "INFO: Running dstat on client and server."
    ssh -n ${IPERF_USER}@${CLIENT_IP} $DSTAT_CLIENT
    ssh -n ${IPERF_USER}@${SERVER_IP} $DSTAT_SERVER
    
    for bandwidth in ${LOAD[*]}; do
        echo "INFO: Run iperf on ${LOAD[*]}"
        IPERF_CLIENT="echo \$(date +%Y%m%d_%H%M%S) | tee ${RESULT_DIR}/run${i}-${bandwidth}-client.iperf && iperf -u -c ${SERVER_IP} -d -b ${bandwidth} -t ${DURATION} -i ${INTERVAL} -B ${CLIENT_IP} -L 6001 -e -x CSV -p 5001 -l 104 | tee -a ${RESULT_DIR}/run${i}-${bandwidth}-client.iperf"
        IPERF_SERVER="nohup iperf -s -i 10 -u -e -p 5001 -x CSV > ${RESULT_DIR}/run${i}-${bandwidth}-server.iperf &"

        echo "INFO: Clear iperf on both sides."
        ssh ${IPERF_USER}@${CLIENT_IP} "killall iperf || true"
        ssh ${IPERF_USER}@${SERVER_IP} "killall iperf || true"
        sleep 2

        echo "INFO: Running iperf on server."
        ssh ${IPERF_USER}@${SERVER_IP} $IPERF_SERVER
        sleep 2

        echo "INFO: Running iperf on client."
        echo "INFO: ${bandwidth} load is running."
        ssh ${IPERF_USER}@${CLIENT_IP} $IPERF_CLIENT

        echo "INFO: Stop iperf on server side."
        ssh ${IPERF_USER}@${SERVER_IP} "killall iperf || true"
    done

    echo "INFO: stop dstat on both sides."
    ssh ${IPERF_USER}@${CLIENT_IP} "kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') || true"
    ssh ${IPERF_USER}@${SERVER_IP} "kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') || true"
done