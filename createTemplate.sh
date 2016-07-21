#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nCreate a CloudFormation (CF) template" 
    echo -e "\nUsage: $(basename $0) -t TYPE -r REGION -s SLICE"
    echo -e "\nwhere\n"
    echo -e "(o) -c CONFIGURATION_REFERENCE is the id of the configuration (commit id, branch id, tag)"
    echo -e "    -h shows this text"
    echo -e "(o) -r REGION is the AWS region identifier"
    echo -e "(o) -s SLICE is the slice of the solution to be included in the template"
    echo -e "(m) -t TYPE is the template type - \"account\", \"project\", \"segment\", \"solution\" or \"application\""
    echo -e "\nNOTES:\n"
    echo -e "1. You must be in the directory specific to the type"
    echo -e "2. REGION is only relevant for the \"project\" type"
    echo -e "3. SLICE is mandatory for the \"segment\", \"solution\" or \"application\" type"
    echo -e "4. SLICE may be one of \"eip\", \"s3\", \"key\", \"vpc\" or \"dns\" for \"segment\" type "
    echo -e "5. Stack for SLICE of \"vpc\" must be created before stack for \"dns\" for \"segment\" type "
    echo -e "6. CONFIGURATION_REFERENCE is mandatory for the \"application\" type"
    echo -e "7. To support legacy configurations, the SLICE combinations \"eipvpc\" and"
    echo -e "   \"eips3vpc\" are also supported but for new projects, individual "
    echo -e "   templates for each slice should be created"
    echo -e ""
    exit
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
      (!("${TYPE}" =~ account|project)) ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi
if [[ ("${TYPE}" == "segment") && 
      (!("${SLICE}" =~ eip|s3|key|vpc|dns|eipvpc|eips3vpc)) ]]; then
    echo -e "\nUnknown slice ${SLICE} for the segment type"
    usage
fi
if [[ (-z "${CONFIGURATION_REFERENCE}") && 
      ("${TYPE}" == "application") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

# Ensure we are in the right place
case $TYPE in
    account|project)
        if [[ ! ("${TYPE}" =~ ${LOCATION}) ]]; then
            echo "Current directory doesn't match requested type \"${TYPE}\". Are we in the right place?"
            usage
        fi
        ;;
    solution|segment|application)
        if [[ ! ("segment" =~ ${LOCATION}) ]]; then
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
        OUTPUT="${CF_DIR}/${TYPE}-${REGION}-template.json"
        TEMP_OUTPUT="${CF_DIR}/temp_${TYPE}-${REGION}-template.json"
        ;;
    project)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/cf"
        OUTPUT="${CF_DIR}/${TYPE}-${REGION}-template.json"
        TEMP_OUTPUT="${CF_DIR}/temp_${TYPE}-${REGION}-template.json"
        ;;
    solution)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        OUTPUT="${CF_DIR}/soln-${SLICE}-${REGION}-template.json"
        TEMP_OUTPUT="${CF_DIR}/temp_soln-${SLICE}-${REGION}-template.json"
        ;;
    segment)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        TYPE_PREFIX="seg-"
        SLICE_PREFIX="${SLICE}-"
        REGION_PREFIX="${REGION}-"
        # LEGACY: Support old formats for existing stacks so they can be updated 
        if [[ !("${SLICE}" =~ key|dns ) ]]; then
            if [[ -f "${CF_DIR}/cont-${SLICE}-${REGION}-template.json" ]]; then
                TYPE_PREFIX="cont-"
            fi
            if [[ -f "${CF_DIR}/container-${REGION}-template.json" ]]; then
                TYPE_PREFIX="container-"
                SLICE_PREFIX=""
            fi
            if [[ -f "${CF_DIR}/${SEGMENT}-container-template.json" ]]; then
                TYPE_PREFIX="${SEGMENT}-container-"
                SLICE_PREFIX=""
                REGION_PREFIX=""
            fi
        fi
        OUTPUT="${CF_DIR}/${TYPE_PREFIX}${SLICE_PREFIX}${REGION_PREFIX}template.json"
        TEMP_OUTPUT="${CF_DIR}/temp_${TYPE_PREFIX}${SLICE_PREFIX}${REGION_PREFIX}template.json"
        ;;
    application)
        CF_DIR="${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf"
        OUTPUT="${CF_DIR}/app-${SLICE}-${REGION}-template.json"
        TEMP_OUTPUT="${CF_DIR}/temp_app-${SLICE}-${REGION}-template.json"
        ;;
    *)
        echo -e "\n\"$TYPE\" is not one of the known stack types (account, project, segment, solution, application). Nothing to do."
        usage
        ;;
esac

# Ensure the aws tree for the templates exists
if [[ ! -d ${CF_DIR} ]]; then mkdir -p ${CF_DIR}; fi

ARGS=()
if [[ -n "${SLICE}"                   ]]; then ARGS+=("-v" "slice=${SLICE}"); fi
if [[ -n "${CONFIGURATION_REFERENCE}" ]]; then ARGS+=("-v" "configurationReference=${CONFIGURATION_REFERENCE}"); fi
if [[ -n "${BUILD_REFERENCE}"         ]]; then ARGS+=("-v" "buildReference=${BUILD_REFERENCE}"); fi
# Removal of /c/ is specifically for MINGW. It shouldn't affect other platforms as it won't be found
if [[ "${TYPE}" == "segment"          ]]; then ARGS+=("-r" "containerList=${COMPOSITE_CONTAINERS#/c/}"); fi
ARGS+=("-v" "region=${REGION}")
ARGS+=("-v" "projectRegion=${PROJECT_REGION}")
ARGS+=("-v" "accountRegion=${ACCOUNT_REGION}")
ARGS+=("-v" "blueprint=${COMPOSITE_SOLUTION}")
ARGS+=("-v" "credentials=${COMPOSITE_CREDENTIALS}")
ARGS+=("-v" "configuration=${COMPOSITE_CONFIGURATION}")
ARGS+=("-v" "stackOutputs=${COMPOSITE_STACK_OUTPUTS}")

${BIN_DIR}/gsgen.sh -t $TEMPLATE -d $TEMPLATE_DIR -o $TEMP_OUTPUT "${ARGS[@]}"
RESULT=$?
if [[ "${RESULT}" -eq 0 ]]; then
    # Tidy up the result
    cat $TEMP_OUTPUT | jq --indent 4 '.' > $OUTPUT
fi
