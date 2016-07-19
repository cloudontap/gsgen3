#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
function usage() {
    echo -e "\nCreate a CloudFormation stack from an existing CloudFormation template" 
    echo -e "\nUsage: $(basename $0) -t TYPE -s SLICE -c -m -i -d DELAY -r REGION\n"
    echo -e "\nwhere\n"
    echo -e "(o) -c (CREATE ONLY) initiates but does not monitor the stack creation process"
    echo -e "(o) -d DELAY is the interval between checking the progress of stack creation"
    echo -e "    -h shows this text"
    echo -e "(o) -i (IGNORE) if the stack creation initiation should be skipped if the stack already exists"
    echo -e "(o) -m (MONITOR ONLY) monitors but does not initiate the stack creation process"
    echo -e "(o) -r REGION is the AWS region identifier for the region in which the stack should be created"
    echo -e "(o) -s SLICE is the slice of the solution to be included in the template"
    echo -e "(m) -t TYPE is the stack type - \"account\", \"project\", \"segment\", \"solution\" or \"application\""
    echo -e "\nDEFAULTS:\n"
    echo -e "DELAY = ${DELAY_DEFAULT} seconds"
    echo -e "\nNOTES:\n"
    echo -e "1. You must be in the correct directory corresponding to the requested stack type"
    echo -e "2. REGION is only relevant for the \"project\" type, where multiple project stacks are necessary if the project uses resources"
    echo -e "   in multiple regions"
    echo -e "3. Slice is mandatory for all types except \"account\" and \"project\""
    echo -e ""
    exit
}

DELAY=${DELAY_DEFAULT}
CREATE=true
WAIT=true
CHECK=true
# Parse options
while getopts ":cd:himr:s:t:" opt; do
    case $opt in
        c)
            WAIT=false
            ;;
        d)
            DELAY=$OPTARG
            ;;
        h)
            usage
            ;;
        i)
            CHECK=false
            ;;
        m)
            CREATE=false
            ;;
        r)
            REGION=$OPTARG
            ;;
        s)
            SLICE=$OPTARG
            ;;
        t)
            TYPE=$OPTARG
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

# Set up the context
. ${BIN_DIR}/setStackContext.sh

pushd ${CF_DIR} > /dev/null 2>&1

if [[ ! -f "${TEMPLATE}" ]]; then
    echo -e "\n\"${TEMPLATE}\" not found. Are we in the correct place in the directory tree? Nothing to do."
    usage
fi

if [[ "${CREATE}" == "true" ]]; then
    DOCREATE="true"
    if [[ "${CHECK}" == "false" ]]; then
        aws ${PROFILE} --region ${REGION} cloudformation describe-stacks --stack-name $STACKNAME > $STACK 2>/dev/null
        RESULT=$?
        if [ "$RESULT" -eq 0 ]; then DOCREATE="false"; fi
    fi
    if [[ "${DOCREATE}" == "true" ]]; then
        cat $TEMPLATE | jq -c '.' > stripped_${TEMPLATE}
        aws ${PROFILE} --region ${REGION} cloudformation create-stack --stack-name $STACKNAME --template-body file://stripped_${TEMPLATE} --capabilities CAPABILITY_IAM
        RESULT=$?
        if [ "$RESULT" -ne 0 ]; then exit; fi
    fi
fi

RESULT=1
if [[ "${WAIT}" == "true" ]]; then
  while true; do
    aws ${PROFILE} --region ${REGION} cloudformation describe-stacks --stack-name $STACKNAME > $STACK
    grep "StackStatus" $STACK > STATUS.txt
    cat STATUS.txt
    grep "CREATE_COMPLETE" STATUS.txt >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -eq 0 ]; then break; fi
    grep "CREATE_IN_PROGRESS" STATUS.txt  >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -ne 0 ]; then break; fi
    sleep $DELAY
  done
fi

