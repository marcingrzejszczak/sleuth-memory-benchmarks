#!/usr/bin/env bash

set -e

# FUNCTIONS

# Runs the `java -jar` for given application $1 jars $2 and env vars $3
function java_jar() {
    local APP_NAME=$1
    local JAR="${ROOT}/${APP_NAME}/target/*.jar"
    local EXPRESSION="nohup ${JAVA_PATH_TO_BIN}java -jar ${JAR} >${LOGS_DIR}/${APP_NAME}.log &"
    echo -e "\nTrying to run [$EXPRESSION]"
    eval ${EXPRESSION}
    pid=$!
    echo ${pid} > ${LOGS_DIR}/${APP_NAME}.pid
    echo -e "[${APP_NAME}] process pid is [${pid}]"
    echo -e "Logs are under [${LOGS_DIR}${APP_NAME}.log]\n"
    return 0
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and host $2
function curl_health_endpoint() {
    local PORT=$1
    local PASSED_HOST="${2:-$HEALTH_HOST}"
    local READY_FOR_TESTS=1
    for i in $( seq 1 "${RETRIES}" ); do
        sleep "${WAIT_TIME}"
        curl -m 5 "${PASSED_HOST}:${PORT}/health" && READY_FOR_TESTS=0 && break
        echo "Fail #$i/${RETRIES}... will try again in [${WAIT_TIME}] seconds"
    done
    return ${READY_FOR_TESTS}
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and localhost
function curl_local_health_endpoint() {
    curl_health_endpoint $1 "127.0.0.1"
}

function send_test_request() {
    local fileName=${1}
    local path="${LOGS_DIR}/${fileName}"
    for i in $( seq 1 "${NO_OF_REQUESTS}" ); do
        if (( ${i} % 100 == 0 )) ; then
            echo "Sent ${i}/${NO_OF_REQUESTS} requests"
        fi
        curl -s "http://localhost:6666/test" > /dev/null
        pid=`jps | grep ${fileName} | awk '{print $1}'`
        jstatResult=`${JAVA_PATH_TO_BIN}jstat -gc ${pid} | tail -1`
        echo "${jstatResult}" >> "${path}.jstat"
        OU=`echo ${jstatResult} | tail -1 | awk '{ print $8 }'`
        EU=`echo ${jstatResult} | tail -1 | awk '{ print $6 }'`
        S0U=`echo ${jstatResult} | tail -1 | awk '{ print $3 }'`
        S1U=`echo ${jstatResult} | tail -1 | awk '{ print $4 }'`
        totalMemory=$(echo "scale=2; ${OU}+${EU}+${S0U}+${S1U}" | bc)
        echo "${totalMemory}" >> ${path}
    done
}

function store_heap_dump() {
    local fileName=${1}
    local path="${LOGS_DIR}/${fileName}"
    echo -e "\nStoring heapdump of [${fileName}]"
    pid=`jps | grep ${fileName} | awk '{print $1}'`
    ${JAVA_PATH_TO_BIN}jmap -dump:format=b,file="${path}.hprof" "${pid}"
}

function calculate_99th_percentile() {
    local fileName=${1}
    local path="${LOGS_DIR}/${fileName}"
    sort -n ${path} | awk '{all[NR] = $0} END{print all[int(NR*0.99 - 0.01)]}' > "${path}_99th"
}

function print_gc_usage() {
    local fileName=${1}
    local path="${LOGS_DIR}/${fileName}.jstat"
    tail -1 ${path} | awk '{ print $17 }'
}

function press_any_key_to_continue() {
    if [[ "${AUTO}" != "yes" ]] ; then
      echo -e "\nPress any key to continue or 'q' to quit"
      read key
      if [[ ${key} = "q" ]]
      then
          exit 1
      fi
    else
      echo -e "\nAuto switch was turned on - continuing..."
    fi
}
function killApps() {
    ${ROOT}/scripts/kill.sh
}

# VARIABLES
JAVA_PATH_TO_BIN="${JAVA_HOME}/bin/"
if [[ -z "${JAVA_HOME}" ]] ; then
    JAVA_PATH_TO_BIN=""
fi
ROOT=`pwd`
LOGS_DIR="${ROOT}/target/"
HEALTH_HOST="127.0.0.1"
RETRIES=10
WAIT_TIME=5
NO_OF_REQUESTS=${NO_OF_REQUESTS:-500}
ALLOWED_DIFFERENCE_IN_PERCENTS=30
NON_SLEUTH="non-sleuth-application"
SLEUTH="sleuth-application"
AUTO="${AUTO:-yes}"

cat <<'EOF'

This Bash file will try to see check the memory usage of two apps. One without and one with Sleuth:

01) Build both apps
02) Run the non sleuth app
03) Curl X requests to the app and store the results in target/non_sleuth
04) Kill the non sleuth app
05) Run the sleuth app
06) Curl X requests to the app and store the results in target/sleuth
07) Kill the sleuth app
08) Calculate the 99 percentile of each of the metrics
09) Calculate the difference between memory usage of Sleuth vs Non-Sleuth app

_______ _________ _______  _______ _________
(  ____ \\__   __/(  ___  )(  ____ )\__   __/
| (    \/   ) (   | (   ) || (    )|   ) (
| (_____    | |   | (___) || (____)|   | |
(_____  )   | |   |  ___  ||     __)   | |
      ) |   | |   | (   ) || (\ (      | |
/\____) |   | |   | )   ( || ) \ \__   | |
\_______)   )_(   |/     \||/   \__/   )_(
EOF

./mvnw clean install -T 2 -DskipTests

mkdir -p "${LOGS_DIR}"
echo -e "\n\nRunning the non sleuth application\n\n"
cd "${ROOT}/${NON_SLEUTH}"
java_jar "${NON_SLEUTH}"
curl_local_health_endpoint 6666
press_any_key_to_continue
echo -e "\n\nSending ${NO_OF_REQUESTS} requests to the app\n\n"
send_test_request "${NON_SLEUTH}"
store_heap_dump "${NON_SLEUTH}"
press_any_key_to_continue
killApps

echo -e "\n\nRunning the sleuth application\n\n"
cd "${ROOT}/${SLEUTH}"
java_jar "${SLEUTH}"
curl_local_health_endpoint 6666
press_any_key_to_continue
echo -e "\n\nSending ${NO_OF_REQUESTS} requests to the app\n\n"
send_test_request "${SLEUTH}"
store_heap_dump "${SLEUTH}"
press_any_key_to_continue
killApps

calculate_99th_percentile "${NON_SLEUTH}"
calculate_99th_percentile "${SLEUTH}"

NON_SLEUTH_PERCENTILE=`cat ${LOGS_DIR}/${NON_SLEUTH}_99th`
SLEUTH_PERCENTILE=`cat ${LOGS_DIR}/${SLEUTH}_99th`

echo "99th percentile of memory usage for a non sleuth app is [${NON_SLEUTH_PERCENTILE}]"
echo "99th percentile of memory usage for a sleuth app is [${SLEUTH_PERCENTILE}]"

DIFFERENCE_IN_MEMORY=$( echo "scale=2; ${SLEUTH_PERCENTILE}-${NON_SLEUTH_PERCENTILE}" | bc)
INCREASE_IN_PERCENTS=$( echo "scale=2; ${DIFFERENCE_IN_MEMORY}/${NON_SLEUTH_PERCENTILE}*100" | bc)

echo "The Sleuth app is using [${DIFFERENCE_IN_MEMORY}] more memory which means a increase by [${INCREASE_IN_PERCENTS}%]"

NON_SLEUTH_GC=`print_gc_usage ${NON_SLEUTH}`
SLEUTH_GC=`print_gc_usage ${SLEUTH}`
echo "GC time for non sleuth app [${NON_SLEUTH_GC}]"
echo "GC time for sleuth app [${SLEUTH_GC}]"

DIFFERENCE_IN_GC=$( echo "scale=3; ${SLEUTH_GC}-${NON_SLEUTH_GC}" | bc)
GC_INCREASE_IN_PERCENTS=$( echo "scale=3; ${DIFFERENCE_IN_GC}/${NON_SLEUTH_GC}*100" | bc)

echo "The Sleuth app needs [${DIFFERENCE_IN_GC}] more time (in seconds) which means a increase by [${GC_INCREASE_IN_PERCENTS}%]"

cd ${ROOT}