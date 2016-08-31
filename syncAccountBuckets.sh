#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nSynchronise the contents of the code and credentials buckets to the local values" 
    echo -e "\nUsage: $(basename $0) -a CHECK_AID -d DOMAIN -x -y"
    echo -e "\nwhere\n"
    echo -e "(m) -a CHECK_AID is the tenant account id e.g. \"env01\""
    echo -e "(o) -d DOMAIN is the domain of the buckets to be synchronised"
    echo -e "    -h shows this text"
    echo -e "(o) -x for no delete - by default files in the buckets that are absent locally are deleted"
    echo -e "(o) -y for a dryrun - show what will happen without actually transferring any files"
    echo -e "\nDEFAULTS:\n"
    echo -e "DOMAIN = {AID}.gosource.com.au"
    echo -e "\nNOTES:\n"
    echo -e "1. The CHECK_AID is only used to ensure we are in the AID directory"
    echo -e ""
    exit
}

DRYRUN=
DELETE="--delete"

# Parse options
while getopts ":a:d:hy" opt; do
    case $opt in
        a)
            CHECK_AID=$OPTARG
            ;;
        d)
            DOMAIN=$OPTARG
            ;;
        h)
            usage
            ;;
        x)
            DELETE=
            ;;
        y)
            DRYRUN="--dryrun"
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

if [[ "${CHECK_AID}" != "${AID}" ]]; then
echo -e "\nThe provided AID (${CHECK_AID}) doesn't match the root directory (${AID}). Nothing to do."
    usage
fi

pushd ${ACCOUNT_DIR}  > /dev/null 2>&1

if [[ -z "${DOMAIN}" ]]; then DOMAIN=${AID}.gosource.com.au; fi

# Confirm access to the code bucket
aws ${PROFILE} --region ${REGION} s3 ls s3://code.${DOMAIN}/ > /dev/null 2>&1
RESULT=$?
if [[ "$RESULT" -ne 0 ]]; then
      echo -e "\nCan't access the code bucket. Does the service role for the server include access to the \"${AID}\" configuration bucket? If windows, is a profile matching the account been set up? Nothing to do."
      usage
fi

cd ${INFRASTRUCTURE_DIR}/startup
aws ${PROFILE} --region ${REGION} s3 sync ${DRYRUN} ${DELETE} --exclude=".git*" bootstrap/ s3://code.${DOMAIN}/bootstrap/

# Confirm access to the credentials bucket
aws ${PROFILE} --region ${REGION} s3 ls s3://credentials.${DOMAIN}/ > /dev/null 2>&1
RESULT=$?
if [[ "$RESULT" -ne 0 ]]; then
      echo -e "\nCan't access the credentials bucket. Does the service role for the server include access to the \"${AID}\" configuration bucket? If windows, is a profile matching the account been set up? Nothing to do."
      usage
fi

cd ${ACCOUNT_CREDENTIALS_DIR}/alm/docker
aws ${PROFILE} --region ${REGION} s3 sync ${DRYRUN} ${DELETE} . s3://credentials.${DOMAIN}/${AID}/alm/docker/
RESULT=$?
