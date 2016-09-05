#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nAdd a solution pattern to a product"
    echo -e "\nUsage: $(basename $0) -s SOLUTION_NAME  -u"
    echo -e "\nwhere\n"
    echo -e "    -h shows this text"
    echo -e "(m) -s SOLUTION_NAME is the name of the solution pattern"
    echo -e "(o) -u if solution should be updated"
    echo -e "\nDEFAULTS:\n"
    echo -e "\nNOTES:\n"
    echo -e "1. Script will copy solution to product/segment depending on current location"
    echo -e ""
    exit
}

# Parse options
while getopts "hs:u" opt; do
    case $opt in
        h)
            usage
            ;;
        s)
            SOLUTION_NAME=$OPTARG
            ;;
        u)
            UPDATE_SOLUTION="true"
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
if [[ (-z "${SOLUTION_NAME}") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Ensure solution exists
PATTERN_DIR="${BIN_DIR}/patterns/solutions/${SOLUTION_NAME}"
if [[ ! -d "${PATTERN_DIR}" ]]; then
    echo -e "\nSolution pattern is not known"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

# Ensure we are in the product or segment directory
if [[ ("product" =~ "${LOCATION}") ]]; then
    TARGET_DIR="./solutions"
else
    if [[ ("segment" =~ "${LOCATION}") ]]; then
        TARGET_DIR="."
    else
        echo -e "\nWe don't appear to be in the product or segment directory. Are we in the right place?"
        usage
    fi
fi

# Check whether the solution profile is already in place
if [[ -f "${TARGET_DIR}/solution.json" ]]; then
    if [[ "${UPDATE_SOLUTION}" != "true" ]]; then
        echo -e "\nSolution profile already exists. Maybe try using update option?"
        usage
    fi
fi

# Copy across the solution pattern
cp -rp ${PATTERN_DIR}/* ${TARGET_DIR}

# Cleanup any placeholder
if [[ -e ${TARGET_DIR}/.placeholder ]] ; then
    ${FILE_RM} ${TARGET_DIR}/.placeholder
fi

# All good
RESULT=0

