#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nAdd SSH certificate to product/segment"
    echo -e "\nUsage: $(basename $0) "
    echo -e "\nwhere\n"
    echo -e "    -h shows this text"
    echo -e "\nDEFAULTS:\n"
    echo -e "\nNOTES:\n"
    echo -e "1. Current directory must be for product or segment"
    echo -e ""
    exit
}

# Parse options
while getopts ":hn:" opt; do
    case $opt in
        h)
            usage
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

# Process the relevant directory
INFRASTRUCTURE_DIR="${ROOT_DIR}/infrastructure/${PRODUCT}"
CREDENTIALS_DIR="${INFRASTRUCTURE_DIR}/credentials"
if [[ "product" =~ ${LOCATION} ]]; then
    SSH_ID="${PRODUCT}"
elif [[ "segment" =~ ${LOCATION} ]]; then
    CREDENTIALS_DIR="${CREDENTIALS_DIR}/${SEGMENT}"
    SSH_ID="${PRODUCT}-${SEGMENT}"
else
    echo -e "\nWe don't appear to be in the product or segment directory. Are we in the right place?"
    usage
fi
    
# Create an SSH certificate at the product level
. ${BIN_DIR}/createSSHCertificate.sh ${CREDENTIALS_DIR}

# Check that the SSH certificate has been defined in AWS
${BIN_DIR}/manageSSHCertificate.sh -i ${SSH_ID} -p ${CREDENTIALS_DIR}/aws-ssh-crt.pem -r ${REGION}
RESULT=$?
