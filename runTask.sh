#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
RID_DEFAULT="web"
CID_DEFAULT="www"
function usage() {
    echo -e "\nRun an ECS task" 
    echo -e "\nUsage: $(basename $0) -t RID -i CID -w KID -e ENV -v VALUE -d DELAY\n"
    echo -e "\nwhere\n"
    echo -e "(o) -d DELAY is the interval between checking the progress of the task"
    echo -e "(o) -e ENV is the name of an environment variable to define for the task"
    echo -e "    -h shows this text"
    echo -e "(o) -i CID is the id of the component in the solution where the task is defined"
    echo -e "(o) -t RID is the id of the tier in the solution where the task is defined"
    echo -e "(o) -v VALUE is the value for the last environment value defined (via -e) for the task"
    echo -e "(m) -w KID is the id of the task to be run"
    echo -e "\nDEFAULTS:\n"
    echo -e "DELAY = ${DELAY_DEFAULT} seconds"
    echo -e "RID   = ${RID_DEFAULT}"
    echo -e "CID   = ${CID_DEFAULT}"
    echo -e "\nNOTES:\n"
    echo -e "1. The ECS cluster is found using the provided tier and component combined with the product and segment"
    echo -e "2. ENV and VALUE should always appear in pairs"
    echo -e ""
    exit
}

ENV_STRUCTURE="\"environment\":["
ENV_NAME=

# Parse options
while getopts ":d:e:hi:t:v:w:" opt; do
    case $opt in
        d)
            DELAY=$OPTARG
            ;;
        e)
            # Separate environment variable definitions
            if [[ -n "${ENV_NAME}" ]]; then 
              ENV_STRUCTURE="${ENV_STRUCTURE},"
            fi
            ENV_NAME=$OPTARG
            ;;
        h)
            usage
            ;;
        i)
            CID=$OPTARG
            ;;
        t)
            RID=$OPTARG
            ;;
        v)
            ENV_STRUCTURE="${ENV_STRUCTURE}{\"name\":\"${ENV_NAME}\", \"value\":\"${OPTARG}\"}"
            ;;
        w)
            KID=$OPTARG
            ;;
        \?)
            echo -e "\nInvalid option: -$OPTARG" 
            usage
            ;;
        :)
            echo -e "\nOption -$OPTARG requires an argument" 
            usage
            ;;
    esac
done

DELAY="${DELAY:-${DELAY_DEFAULT}}"
RID="${RID:-${RID_DEFAULT}}"
CID="${CID:-${CID_DEFAULT}}"
ENV_STRUCTURE="${ENV_STRUCTURE}]"

# Ensure mandatory arguments have been provided
if [[ "${TASK}"  == "" ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

# Ensure we are in the right place
if [[ "${LOCATION}" != "segment" ]]; then
    echo -e "\nWe don't appear to be in the right directory. Nothing to do"
    usage
fi

# Find the cluster
CLUSTER_ARN=$(aws --region ${REGION} ecs list-clusters | jq -r ".clusterArns[] | capture(\"(?<arn>.*${PRODUCT}-${SEGMENT}.*ecsX${RID}X${CID}.*)\").arn")
if [[ -z "${CLUSTER_ARN}" ]]; then
    echo -e "\nUnable to locate ECS cluster"
    usage
fi

# Find the task definition
TASK_DEFINITION_ARN=$(aws --region ${REGION} ecs list-task-definitions | jq -r ".taskDefinitionArns[] | capture(\"(?<arn>.*${PRODUCT}-${SEGMENT}.*ecsTaskX${RID}X${CID}X${KID}.*)\").arn")
if [[ -z "${TASK_DEFINITION_ARN}" ]]; then
    echo -e "\nUnable to locate task definition"
    usage
fi

aws --region ${REGION} ecs run-task --cluster "${CLUSTER_ARN}" --task-definition "${TASK_DEFINITION_ARN}" --count 1 --overrides "{\"containerOverrides\":[{\"name\":\"${RID}-${CID}-${KID}\",${ENV_STRUCTURE}}]}" > STATUS.txt
RESULT=$?
if [ "$RESULT" -ne 0 ]; then exit; fi
cat STATUS.txt
TASK_ARN=$(cat STATUS.txt | jq -r ".tasks[0].taskArn")

while true; do
    aws --region ${REGION} ecs describe-tasks --cluster ${CLUSTER_ARN} --tasks ${TASK_ARN} 2>/dev/null | jq ".tasks[] | select(.taskArn == \"${TASK_ARN}\") | {lastStatus: .lastStatus}" > STATUS.txt
    cat STATUS.txt
    grep "STOPPED" STATUS.txt >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -eq 0 ]; then break; fi
    grep "PENDING\|RUNNING" STATUS.txt  >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -ne 0 ]; then break; fi
    sleep $DELAY
done

# Show the exit codes and return an error if they are not 0
aws --region ${REGION} ecs describe-tasks --cluster ${CLUSTER_ARN} --tasks ${TASK_ARN} 2>/dev/null | jq ".tasks[].containers[] | {name: .name, exitCode: .exitCode}" > STATUS.txt
cat STATUS.txt
RESULT=$(cat STATUS.txt | jq ".exitCode" | grep -m 1 -v "^0$" | tr -d '"')
RESULT=${RESULT:-0}


