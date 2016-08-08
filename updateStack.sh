#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
function usage() {
    echo -e "Update an existing CloudFormation stack" 
    echo -e "\nUsage: $(basename $0) -t TYPE -s SLICE -u -m -d DELAY -r REGION\n"
    echo -e "\nwhere\n"
    echo -e "(o) -d DELAY is the interval between checking the progress of stack update"
    echo -e "    -h shows this text"
    echo -e "(o) -m (MONITOR ONLY) monitors but does not initiate the stack update process"
    echo -e "(o) -r REGION is the AWS region identifier for the region in which the stack should be updated"
    echo -e "(o) -s SLICE is the slice of the solution to be included in the template"
    echo -e "(m) -t TYPE is the stack type - \"account\", \"product\", \"segment\", \"solution\" or \"application\""
    echo -e "(o) -u (UPDATE ONLY) initiates but does not monitor the stack update process"
    echo -e "\nDEFAULTS:\n"
    echo -e "DELAY = ${DELAY_DEFAULT} seconds"
    echo -e "\nNOTES:\n"
    echo -e "1. You must be in the correct directory corresponding to the requested stack type"
    echo -e "2. REGION is only relevant for the \"product\" type, where multiple product stacks are necessary"
    echo -e "   if the product uses resources in multiple regions"  
    echo -e "3. \"segment\" is now used in preference to \"container\" to avoid confusion with docker, but"
    echo -e "   \"container\" is still accepted to support legacy configurations"
    echo -e ""
    exit
}

DELAY=${DELAY_DEFAULT}
UPDATE=true
WAIT=true

# Parse options
while getopts ":d:hmr:s:t:u" opt; do
    case $opt in
        d)
            DELAY=$OPTARG
            ;;
        h)
            usage
            ;;
        m)
            UPDATE=false
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
        u)
            WAIT=false
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

if [[ ! -f "$TEMPLATE" ]]; then
    echo -e "\n\"${TEMPLATE}\" not found. Are we in the correct place in the directory tree? Nothing to do."
    usage
fi

if [[ "${UPDATE}" = "true" ]]; then
    cat $TEMPLATE | jq -c '.' > stripped_${TEMPLATE}
    aws ${PROFILE} --region ${REGION} cloudformation update-stack --stack-name $STACKNAME --template-body file://stripped_${TEMPLATE} --capabilities CAPABILITY_IAM
    RESULT=$?
    if [ "$RESULT" -ne 0 ]; then exit; fi
fi

RESULT=1
if [[ "${WAIT}" = "true" ]]; then
    while true; do
        aws ${PROFILE} --region ${REGION} cloudformation describe-stacks --stack-name $STACKNAME > $STACK
        grep "StackStatus" $STACK > STATUS.txt
        cat STATUS.txt
        grep "UPDATE_COMPLETE" STATUS.txt >/dev/null 2>&1
        RESULT=$?
        if [ "$RESULT" -eq 0 ]; then break;fi
        grep "UPDATE_IN_PROGRESS" STATUS.txt  >/dev/null 2>&1
        RESULT=$?
        if [ "$RESULT" -ne 0 ]; then break;fi
        sleep $DELAY
    done
fi

