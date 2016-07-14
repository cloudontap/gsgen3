#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nCreate a CloudFormation (CF)  template" 
    echo -e "\nUsage: $(basename $0) -t TYPE -r REGION -s SLICE"
    echo -e "\nwhere\n"
    echo -e "(m) -c CONFIGURATION_REFERENCE is the id of the configuration (commit id, branch id, tag)"
    echo -e "    -h shows this text"
    echo -e "(o) -r REGION is the AWS region identifier"
    echo -e "(o) -s SLICE is the slice of the solution to be included in the template"
    echo -e "(m) -t TYPE is the template type - \"account\", \"project\", \"segment\", \"solution\" or \"application\""
    echo -e "\nNOTES:\n"
    echo -e "1. You must be in the directory specific to the type"
    echo -e "2. REGION is only relevant for the \"project\" type"
    echo -e "3. SLICE is mandatory for the \"segment\", \"solution\" or \"application\" type"
    echo -e "4. SLICE may be one of \"eip\", \"s3\", \"key\" or \"vpc\" for \"segment\" type "
    echo -e "3. CONFIGURATION is mandatory for the \"application\" type"
    echo -e ""
}

# Parse options
while getopts ":c:hr:s:t:" opt; do
    case $opt in
        c)
            CONFIGURATION_REFERENCE=$OPTARG
            ;;
        h)
            usage
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

# Ensure mandatory arguments have been provided
if [[ (-z "${TYPE}") ]]; then 
    echo -e "\nInsufficient arguments"
    usage
fi
if [[ (-z "${SLICE}") && 
      (! ("${TYPE}" ~= "account|project")) ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi
if [[ ( "${TYPE}" == "segment") && 
      (! ("${SLICE}" ~= "eip|s3|key|vpc")) ]]; then
    echo -e "\nUnknown slice ${SLICE} for the segment type"
    usage
fi
if [[ (-z "${CONFIGURATION_REFERENCE}") && 
      ("${TYPE}" == "application")) ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

# Ensure we are in the right place
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

# Set up the type specific template information
TEMPLATE_DIR="${BIN_DIR}/templates"
TEMPLATE="create${TYPE^}.ftl"
case $TYPE in
    account)
        CF_DIR="${INFRASTRUCTURE_DIR}/${OAID}/aws/cf"
        OUTPUT="${CF_DIR}/account-${REGION}-template.json"
        ;;
    project)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/cf"
        OUTPUT="${CF_DIR}/project-${REGION}-template.json"
        ;;
    solution)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        OUTPUT="${CF_DIR}/soln-${SLICE}-${REGION}-template.json"
        ;;
    segment)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        PREFIX="seq"
        if [[ -f "${CF_DIR}/cont-${SLICE}-${REGION}-template.json" ]]; then
            # Stick with old prefix for existing stacks so they can be updated 
            PREFIX="cont"
        fi
        OUTPUT="${CF_DIR}/${PREFIX}-${SLICE}-${REGION}-template.json"
        ;;
    application)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        OUTPUT="${CF_DIR}/app-${SLICE}-${REGION}-template.json"
        if [[ -f ${TEMPLATE} ]]; then
            TEMPLATE_DIR="./"
        else
            TEMPLATE_DIR="../"
        fi
        ;;
    *)
        echo -e "\n\"$TYPE\" is not one of the known stack types (account, project, segment, solution, application). Nothing to do."
        usage
        ;;
esac

# Ensure the aws tree for the templates exists
if [[ ! -d ${CF_DIR} ]]; then mkdir -p ${CF_DIR}; fi

ARGS=()
if [[ (-n "${SLICE}"                   ]]; then ARGS+=("-v" "slice=${SLICE}"); fi
if [[ (-n "${CONFIGURATION_REFERENCE}" ]]; then ARGS+=("-v" "configurationReference=${CONFIGURATION_REFERENCE}"); fi
if [[ (-n "${BUILD_REFERENCE}"         ]]; then ARGS+=("-v" "buildReference=${BUILD_REFERENCE}"); fi
ARGS+=("-v" "region=${REGION}")
ARGS+=("-v" "projectRegion=${PROJECT_REGION}")
ARGS+=("-v" "accountRegion=${ACCOUNT_REGION}")
ARGS+=("-v" "blueprint=${AGGREGATE_SOLUTION}")
ARGS+=("-v" "credentials=${AGGREGATE_CREDENTIALS}")
ARGS+=("-v" "configuration=${AGGREGATE_CONFIGURATION}")
ARGS+=("-v" "stackOutputs=${AGGREGATE_STACK_OUTPUTS}")
ARGS+=("-v" "masterData=${BIN_DIR}/data/masterData.json")

${BIN_DIR}/gsgen.sh -t $TEMPLATE -d $TEMPLATE_DIR -o $OUTPUT "${ARGS[@]}"
RESULT=$?
