#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nAdd the application settings for a segment"
    echo -e "\nUsage: $(basename $0) -u"
    echo -e "\nwhere\n"
    echo -e "    -h shows this text"
    echo -e "(o) -u if details should be updated"
    echo -e "\nDEFAULTS:\n"
    echo -e "\nNOTES:\n"
    echo -e "1. Any application settings are located via the solution"
    echo -e "   pattern"
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
            UPDATE_APPSETTINGS="true"
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

# Check whether the application settings already exist
SEGMENT_APPSETTINGS_DIR="${APPSETTINGS_DIR}/${SEGMENT}"
SLICES=$(find ${SEGMENT_APPSETTINGS_DIR}/* -type d 2> /dev/null)
if [[ -n ${SLICES} ]]; then
    if [[ "${UPDATE_APPSETTINGS}" != "true" ]]; then
        echo -e "\nSegment application settings already exist. Maybe try using update option?"
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
if [[ ! -d ${PATTERN_DIR}/appsettings ]]; then
    echo -e "\nNo application settings for the solution pattern. Nothing to do"
    RESULT=0
    exit
fi

# Copy across the application settings 
mkdir -p ${SEGMENT_APPSETTINGS_DIR}
cp -rp ${PATTERN_DIR}/appsettings/* ${SEGMENT_APPSETTINGS_DIR}

# All good
RESULT=0
