#!/bin/bash

set -euf

STOP_DSTAT="kill \$(ps -ef | grep dstat | grep -v grep | awk '{print \$2}') >/dev/null 2>&1 || true"
STOP_IPERF="killall iperf >/dev/null 2>&1 || true"

# load xperf config and workload
. workload.conf
. xperf.conf

ExecCommandOverSSH() {
    case $1 in
        "client")
            ssh -q -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${CLIENT_IP} $2
            return $?
            ;;
        "server")
            ssh -q -i ${SSH_PRIVATE_KEY} ${IPERF_USER}@${SERVER_IP} $2
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
            ExecCommandOverSSH $1 "echo \$(date +%Y%m%d_%H%M%S) | tee ${RESULT_DIR}/run$2-$3-$1.iperf && iperf -u -c ${SERVER_IP} -d -b $3 -t ${DURATION} -i ${INTERVAL} -B ${CLIENT_IP} -L ${CLIENT_PORT} -e -x CSV -p ${SERVER_PORT} -l ${UDP_PAYLOAD} | tee -a ${RESULT_DIR}/run$2-$3-$1.iperf";;
        "server")
            ExecCommandOverSSH $1 "nohup iperf -s -i ${INTERVAL} -u -e -p ${SERVER_PORT} -x CSV > ${RESULT_DIR}/run$2-$3-$1.iperf &";;
        *)
            echo -e "Sorry, I can not get what you want"
            return 1
            ;;
    esac
}

# clear result folder if exists
ExecCommandOverSSH "client" "rm -rf ${RESULT_DIR}"
ExecCommandOverSSH "server" "rm -rf ${RESULT_DIR}"

# creat result folder
ExecCommandOverSSH "client" "mkdir ${RESULT_DIR}"
ExecCommandOverSSH "server" "mkdir ${RESULT_DIR}"

# stop iperf and dstat on both sides
ExecCommandOverSSH "client" "$STOP_IPERF"
ExecCommandOverSSH "server" "$STOP_IPERF"
ExecCommandOverSSH "client" "$STOP_DSTAT"
ExecCommandOverSSH "server" "$STOP_DSTAT"

ExecCommandOverSSH "client" "[ ! -e /usr/local/bin/dstat ]" && scp $IPERF_FILE ${IPERF_USER}@${CLIENT_IP}:/usr/local/bin
ExecCommandOverSSH "server" "[ ! -e /usr/local/bin/dstat ]" && scp $IPERF_FILE ${IPERF_USER}@${SERVER_IP}:/usr/local/bin

ExecCommandOverSSH "client" "[ ! -e /usr/local/bin/dstat ]" && scp $DSTAT_FILE ${IPERF_USER}@${CLIENT_IP}:/usr/local/bin
ExecCommandOverSSH "server" "[ ! -e /usr/local/bin/dstat ]" && scp $DSTAT_FILE ${IPERF_USER}@${SERVER_IP}:/usr/local/bin

for ((i=1; i<=${ITERATIONS}; i++)); do
    # stop dstat on both sides
    ExecCommandOverSSH "client" "$STOP_DSTAT"
    ExecCommandOverSSH "server" "$STOP_DSTAT"
    sleep 1

    echo -e "Run${i}: start dstat on client and server.\n-----------------"
    RunDstatOverSSH "client" $i
    RunDstatOverSSH "server" $i
    
    for bandwidth in ${LOAD[*]}; do
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