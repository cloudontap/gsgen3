#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Ensure mandatory arguments have been provided
if [[ (-z "${TYPE}") || \
        ((-z "${SLICE}") && (! ("${TYPE}" ~= "account|project"))) ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

case $TYPE in
    account|project)
        if [[ ! ("${TYPE}" ~= "${LOCATION}") ]]; then
            echo "Current directory doesn't match requested type \"${TYPE}\". Are we in the right place?"
            usage
        fi
        ;;
    solution|segment|application)
        if [[ ! ("segment" ~= "${LOCATION}") ]]; then
            echo "Current directory doesn't match requested type \"${TYPE}\". Are we in the right place?"
            usage
        fi
        ;;
esac


# Determine the details of the template to be created
case $TYPE in
    account)
        REGION="${ACCOUNT_REGION}"
        CF_DIR="${INFRASTRUCTURE_DIR}/${OAID}/aws/cf"
        STACKNAME="${OAID}-${TYPE}"
        TEMPLATE="${TYPE}-${REGION}-template.json"
        STACK="${TYPE}-${REGION}-stack.json"
        ;;
    project)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/cf"
        STACKNAME="${PID}-${TYPE}"
        TEMPLATE="${TYPE}-${REGION}-template.json"
        STACK="${TYPE}-${REGION}-stack.json"
        ;;
    solution)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        STACKNAME="${PID}-${SEGMENT}-soln-${SLICE}"
        TEMPLATE="soln-${SLICE}-${REGION}-template.json"
        STACK="soln-${SLICE}-${REGION}-stack.json"
        ;;
    segment)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        PREFIX="seq"
        if [[ -f "${CF_DIR}/cont-${SLICE}-${REGION}-template.json" ]]; then
            # Stick with old prefix for existing stacks so they can be updated 
            PREFIX="cont"
        fi
        STACKNAME="${PID}-${SEGMENT}-${PREFIX}-${SLICE}"
        TEMPLATE="${PREFIX}-${SLICE}-${REGION}-template.json"
        STACK="${PREFIX}-${SLICE}-${REGION}-stack.json"
        ;;
    application)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        STACKNAME="${PID}-${SEGMENT}-app-${SLICE}"
        TEMPLATE="app-${SLICE}-${REGION}-template.json"
        STACK="app-${SLICE}-${REGION}-stack.json"
        ;;
    *)
        echo -e "\n\"$TYPE\" is not one of the known stack types (account, project, segment, solution, application). Nothing to do."
        usage
        ;;
esac

