#!/usr/bin/env bash

# requires:

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
    echo -e "Logs are under [${LOGS_DIR}/${APP_NAME}.log]\n"
    return 0
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and host $2
function curl_health_endpoint() {
    local PORT=$1
    local PASSED_HOST="${2:-$HEALTH_HOST}"
    local READY_FOR_TESTS=1
    for i in $( seq 1 "${RETRIES}" ); do
        sleep "${WAIT_TIME}"
        curl -m 5 "${PASSED_HOST}:${PORT}}/health" && READY_FOR_TESTS=0 && break
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
    for i in {1..${NO_OF_REQUESTS}}; do
        curl -s "http://localhost:6666/test" >> target/${fileName}
        echo "\n" >> target/${fileName}
    done
}

function killApps() {
    pkill -9 -f 0.0.1-SLEUTH-SNAPSHOT
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
NO_OF_REQUESTS=100000

mkdir -p ${ROOT}/target

cat <<'EOF'

This Bash file will try to see check the memory usage of two apps. One without and one with Sleuth:

01) Build both apps
02) Run the non sleuth app
03) Curl X requests to the app and store the results in target/non_sleuth
04) Kill the non sleuth app
05) Run the sleuth app
06) Curl X requests to the app and store the results in target/sleuth
07) Kill the sleuth app

_______ _________ _______  _______ _________
(  ____ \\__   __/(  ___  )(  ____ )\__   __/
| (    \/   ) (   | (   ) || (    )|   ) (
| (_____    | |   | (___) || (____)|   | |
(_____  )   | |   |  ___  ||     __)   | |
      ) |   | |   | (   ) || (\ (      | |
/\____) |   | |   | )   ( || ) \ \__   | |
\_______)   )_(   |/     \||/   \__/   )_(
EOF

./mvnw clean install -T 2

echo -e "\n\nRunning the non sleuth application\n\n"
cd ${ROOT}/non-sleuth-application
java_jar "non-sleuth-application"
curl_local_health_endpoint 6666
send_test_request
killApps

echo -e "\n\nRunning the sleuth application\n\n"
cd ${ROOT}/sleuth-application
java_jar "sleuth-application"
curl_local_health_endpoint 6666
send_test_request
killApps

cd ${ROOT}