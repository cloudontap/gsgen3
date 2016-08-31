#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

ACL_DEFAULT="private"
PREFIX_DEFAULT="/"
function usage() {
    echo -e "\nUpdate the ACL associated with all objects in a bucket" 
    echo -e "\nUsage: $(basename $0) -b BUCKET -p PREFIX -a ACL -d\n"
    echo -e "\nwhere\n"
    echo -e "(o) -a ACL is the canned ACL to apply to all objects in the bucket"
    echo -e "(m) -b BUCKET is the bucket to be updated"
    echo -e "    -d displays the ACLs but does not update them"
    echo -e "    -h shows this text"
    echo -e "(o) -p PREFIX is the key prefix for objects to be updated"
    echo -e "\nDEFAULTS:\n"
    echo -e "ACL    = \"${ACL_DEFAULT}\""
    echo -e "PREFIX = \"${PREFIX_DEFAULT}\""
    echo -e "\nNOTES:\n"
    echo -e "1. PREFIX must start and end with a /"
    echo -e ""
    exit
}

ACL="${ACL_DEFAULT}"
PREFIX="${PREFIX_DEFAULT}"
DISPLAY_ACLS="false"
# Parse options
while getopts ":a:b:dhp:" opt; do
    case $opt in
        a)
            ACL=$OPTARG
            ;;
        b)
            BUCKET=$OPTARG
            ;;
        d)
            DISPLAY_ACLS="true"
            ;;
        h)
            usage
            ;;
        p)
            PREFIX=$OPTARG
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
if [[ "${BUCKET}"  == "" ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

# Get the list of ECS clusters  
for KEY in $(aws ${PROFILE} --region ${REGION} s3 ls s3://${BUCKET}${PREFIX} --recursive  | tr -s " " | tr -d "\r" | cut -d " " -f4); do
    if [[ "${DISPLAY_ACLS}" == "true" ]]; then
        # Show current ACL
        echo "Key=${KEY}"
        aws ${PROFILE} --region ${REGION} s3api get-object-acl --bucket "${BUCKET}" --key "${KEY}"
    else
        # Update the ACL
        aws ${PROFILE} --region ${REGION} s3api put-object-acl --bucket "${BUCKET}" --key "${KEY}" --acl "${ACL}"
    fi
done

# All good
RESULT=0

