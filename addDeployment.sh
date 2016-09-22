#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nAdd the deployment configuration for a segment"
    echo -e "\nUsage: $(basename $0) -u"
    echo -e "\nwhere\n"
    echo -e "    -h shows this text"
    echo -e "(o) -u if details should be updated"
    echo -e "\nDEFAULTS:\n"
    echo -e "\nNOTES:\n"
    echo -e "1. Any deployment configuration is located via the solution"
    echo -e "   pattern matching the solution name"
    echo -e "2. Nothing is done if no solution pattern can be found"
    echo -e "3. The script must be run in the segment directory"
    echo -e ""
    exit
}

# Parse options
while getopts ":hu" opt; do
    case $opt in
        h)
            usage
            ;;
        u)
            UPDATE_DEPLOYMENT="true"
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
. ${BIN_DIR}/setContext.sh

# Ensure we are in the segment directory
if [[ ! ("segment" =~ "${LOCATION}") ]]; then
    echo -e "\nWe don't appear to be in the segment directory. Are we in the right place?"
    usage
fi

# Check whether the deployment already exists
SEGMENT_DEPLOYMENT_DIR="${DEPLOYMENTS_DIR}/${SEGMENT}"
SLICES=$(find ${SEGMENT_DEPLOYMENT_DIR}/* -type d 2> /dev/null)
if [[ -n ${SLICES} ]]; then
    if [[ "${UPDATE_DEPLOYMENT}" != "true" ]]; then
        echo -e "\nSegment deployment configuration already exists. Maybe try using update option?"
        usage
    fi
fi

# Find the solution name
SOLUTION_NAME=$(cat ${COMPOSITE_BLUEPRINT} | jq -r ".Solution.Pattern | select(.!=null)")

if [[ -z "${SOLUTION_NAME}" ]]; then
    echo -e "\nNo solution pattern configured yet. Maybe try adding the solution first?"
    usage
fi

# Check if a corresponding solution pattern exists
PATTERN_DIR="${BIN_DIR}/patterns/solutions/${SOLUTION_NAME}"
if [[ ! -d ${PATTERN_DIR} ]]; then
    echo -e "\nNo pattern found matching the solution name \"${SOLUTION_NAME}\". Nothing to do"
    RESULT=0
    exit
fi
if [[ ! -d ${PATTERN_DIR}/deployment ]]; then
    echo -e "\nNo deployment configuration for the solution pattern. Nothing to do"
    RESULT=0
    exit
fi

# Copy across the deployment 
mkdir -p ${SEGMENT_DEPLOYMENT_DIR}
cp -rp ${PATTERN_DIR}/deployment/* ${SEGMENT_DEPLOYMENT_DIR}

# All good
RESULT=0
