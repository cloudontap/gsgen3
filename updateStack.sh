#!/bin/bash

if [[ -n "${GENERATION_DEBUG}" ]]; then set ${GENERATION_DEBUG}; fi
trap '. ${GENERATION_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
function usage() {
    echo -e "\nCreate/Update a CloudFormation stack"
    echo -e "\nUsage: $(basename $0) -t TYPE -s SLICE -u -m -d DELAY -r REGION\n"
    echo -e "\nwhere\n"
    echo -e "(o) -d DELAY is the interval between checking the progress of stack operation"
    echo -e "    -h shows this text"
    echo -e "(o) -i (INITIATE ONLY) initiates but does not monitor the stack operation"
    echo -e "(o) -m (MONITOR ONLY) monitors but does not initiate the stack operation"
    echo -e "(o) -r REGION is the AWS region identifier for the region in which the stack should be managed"
    echo -e "(o) -s SLICE is the slice of the solution to be included in the template"
    echo -e "(m) -t TYPE is the stack type - \"account\", \"product\", \"segment\", \"solution\" or \"application\""
    echo -e "\nDEFAULTS:\n"
    echo -e "DELAY = ${DELAY_DEFAULT} seconds"
    echo -e "\nNOTES:\n"
    echo -e "1. You must be in the correct directory corresponding to the requested stack type"
    echo -e "2. REGION is only relevant for the \"product\" type, where multiple product stacks are necessary"
    echo -e "   if the product uses resources in multiple regions"  
    echo -e "3. \"segment\" is now used in preference to \"container\" to avoid confusion with docker"
    echo -e "4. If stack isn't defined, create it otherwise update it"
    echo -e ""
    exit
}

DELAY=${DELAY_DEFAULT}
STACK_INITIATE=true
STACK_MONITOR=true

# Parse options
while getopts ":d:himr:s:t:" opt; do
    case $opt in
        d)
            DELAY=$OPTARG
            ;;
        h)
            usage
            ;;
        i)
            STACK_MONITOR=false
            ;;
        m)
            STACK_INITIATE=false
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
. ${GENERATION_DIR}/setStackContext.sh

pushd ${CF_DIR} > /dev/null 2>&1

if [[ ! -f "$TEMPLATE" ]]; then
    echo -e "\n\"${TEMPLATE}\" not found. Are we in the correct place in the directory tree? Nothing to do."
    usage
fi

if [[ "${STACK_INITIATE}" = "true" ]]; then
    # Compress the template to avoid aws cli size limitastions
    cat $TEMPLATE | jq -c '.' > stripped_${TEMPLATE}

    # Determine required operation
    STACK_OPERATION="CREATE"
    STACK_CLI_COMMAND="create-stack"
    aws --region ${REGION} cloudformation describe-stacks --stack-name $STACKNAME > $STACK 2>/dev/null
    RESULT=$?
    if [[ "$RESULT" -eq 0 ]]; then
        STACK_OPERATION="UPDATE"
        STACK_CLI_COMMAND="update-stack"
    fi
    
    # Initiate the required operation
    aws --region ${REGION} cloudformation ${STACK_CLI_COMMAND} --stack-name $STACKNAME --template-body file://stripped_${TEMPLATE} --capabilities CAPABILITY_IAM
    RESULT=$?
    if [[ "$RESULT" -ne 0 ]]; then exit; fi
fi

RESULT=1
if [[ "${STACK_MONITOR}" = "true" ]]; then
    while true; do
        aws --region ${REGION} cloudformation describe-stacks --stack-name $STACKNAME > $STACK
        grep "StackStatus" $STACK > STATUS.txt
        cat STATUS.txt
        grep "${STACK_OPERATION}_COMPLETE" STATUS.txt >/dev/null 2>&1
        RESULT=$?
        if [[ "$RESULT" -eq 0 ]]; then break;fi
        grep "${STACK_OPERATION}_IN_PROGRESS" STATUS.txt  >/dev/null 2>&1
        RESULT=$?
        if [[ "$RESULT" -ne 0 ]]; then break;fi
        sleep $DELAY
    done
fi

