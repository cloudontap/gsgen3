#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
function usage() {
    echo -e "\nDelete an existing CloudFormation stack" 
    echo -e "\nUsage: $(basename $0) -t TYPE -s SLICE -x -m -i -d DELAY -r REGION\n"
    echo -e "\nwhere\n"
    echo -e "(o) -d DELAY is the interval between checking the progress of stack deletion"
    echo -e "    -h shows this text"
    echo -e "(o) -i (IGNORE) if the stack deletion should be initiated even if there is no local copy of the stack"
    echo -e "(o) -m (MONITOR ONLY) monitors but does not initiate the stack deletion process"
    echo -e "(o) -r REGION is the AWS region identifier for the region in which the stack should be deleted"
    echo -e "(o) -s SLICE is the slice of the solution to be deleted"
    echo -e "(m) -t TYPE is the stack type - \"account\", \"product\", \"segment\", \"solution\" or \"application\""
    echo -e "(o) -x (DELETE ONLY) initiates but does not monitor the stack deletion process"
    echo -e "\nDEFAULTS:\n"
    echo -e "DELAY = ${DELAY_DEFAULT} seconds"
    echo -e "\nNOTES:\n"
    echo -e "1. You must be in the correct directory corresponding to the requested stack type"
    echo -e "2. REGION is only relevant for the \"product\" type, where multiple product stacks are necessary"
    echo -e "   if the product uses resources in multiple regions"  
    echo -e "3. \"segment\" is now used in preference to \"container\" to avoid confusion with docker"
    echo -e ""
    exit
}

DELAY=${DELAY_DEFAULT}
DELETE=true
WAIT=true
CHECK=true

# Parse options
while getopts ":d:himr:s:t:x" opt; do
    case $opt in
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
            DELETE=false
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
        x)
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

if [[ "${CHECK}" = "true" && ! -f "$STACK" ]]; then
    echo -e "\n\"${STACK}\" not found. Has the stack already been deleted? Nothing to do."
    usage
fi

if [[ "${DELETE}" = "true" ]]; then
    aws --region ${REGION} cloudformation delete-stack --stack-name $STACKNAME 2>/dev/null
fi

RESULT=1
if [[ "${WAIT}" = "true" ]]; then
    while true; do
        aws --region ${REGION} cloudformation describe-stacks --stack-name $STACKNAME > $STACK 2>/dev/null
        if [ "$RESULT" -eq 255 ]; then
            # Assume stack doesn't exist
            RESULT=0
            break
        fi
        grep "StackStatus" $STACK > STATUS.txt
        cat STATUS.txt
        grep "DELETE_COMPLETE" STATUS.txt >/dev/null 2>&1
        RESULT=$?
        if [ "$RESULT" -eq 0 ]; then break;fi
        grep "DELETE_IN_PROGRESS" STATUS.txt >/dev/null 2>&1
        RESULT=$?
        if [ "$RESULT" -ne 0 ]; then break;fi
        sleep $DELAY
    done
fi

rm -f $STACK

