#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Ensure mandatory arguments have been provided
if [[ (-z "${TYPE}") || \
        ((-z "${SLICE}") && (! ("${TYPE}" =~ account|project ))) ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

case $TYPE in
    account|project)
        if [[ ! ("${TYPE}" =~ ${LOCATION} ) ]]; then
            echo -e "\nCurrent directory doesn't match requested type \"${TYPE}\". Are we in the right place?"
            usage
        fi
        ;;
    solution|segment|application)
        if [[ ! ("segment" =~ ${LOCATION} ) ]]; then
            echo -e "\nCurrent directory doesn't match requested type \"${TYPE}\". Are we in the right place?"
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
        TYPE_PREFIX="seg-"
        TYPE_SUFFIX="seg"
        SLICE_PREFIX="${SLICE}-"
        SLICE_SUFFIX="-${SLICE}"
        REGION_PREFIX="${REGION}-"
        # LEGACY: Support old formats for existing stacks so they can be updated 
        if [[ !("${SLICE}" =~ key|dns ) ]]; then
            if [[ -f "${CF_DIR}/cont-${SLICE}-${REGION}-template.json" ]]; then
                TYPE_PREFIX="cont-"
                TYPE_SUFFIX="cont"
            fi
            if [[ -f "${CF_DIR}/container-${REGION}-template.json" ]]; then
                TYPE_PREFIX="container-"
                TYPE_SUFFIX="container"
                SLICE_PREFIX=""
                SLICE_SUFFIX=""
            fi
            if [[ -f "${CF_DIR}/${SEGMENT}-container-template.json" ]]; then
                TYPE_PREFIX="${SEGMENT}-container-"
                TYPE_SUFFIX="container"
                SLICE_PREFIX=""
                SLICE_SUFFIX=""
                REGION_PREFIX=""
            fi
        fi
        STACKNAME="${PID}-${SEGMENT}-${TYPE_SUFFIX}${SLICE_SUFFIX}"
        TEMPLATE="${TYPE_PREFIX}${SLICE_PREFIX}${REGION_PREFIX}template.json"
        STACK="${TYPE_PREFIX}${SLICE_PREFIX}${REGION_PREFIX}stack.json"
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

