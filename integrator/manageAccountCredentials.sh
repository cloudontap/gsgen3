#!/bin/bash
                                                                                        
if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && cd .. && pwd )
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
  echo -e "\nManage account credentials"
  echo -e "\nUsage: $(basename $0) -t TID -a TAID -k ACCESS_KEY -s SECREY_KEY -u AWS_USERNAME -p AWS_PASSWORD\n"
  echo -e "\nwhere\n"
  echo -e "(m) -a TAID is the tenant account id"
  echo -e "    -h shows this text"
  echo -e "(o) -k ACCESS_KEY specifies the API access key value"
  echo -e "(o) -p AWS_PASSWORD specifies the AWS account password"
  echo -e "(o) -s SECRET_KEY specifies the API secret key value"
  echo -e "(m) -t TID is the organisation id"
  echo -e "(o) -u AWS_USERNAME specifies the AWS account username"
  echo -e "\nDEFAULTS:\n"
  echo -e "\nNOTES:\n"
  echo -e "1. Provided values (if any) are updated"
  echo -e "2. Current values are displayed"
  echo -e ""
  exit
}

# Parse options
while getopts ":a:hk:p:s:t:u:" opt; do
    case $opt in
        a)
            TAID="${OPTARG}"
            ;;
        h)
            usage
            ;;
        k)
            ACCESS_KEY="${OPTARG}"
            ;;
        p)
            AWS_PASSWORD="${OPTARG}"
            ;;
        s)
            SECRET_KEY="${OPTARG}"
            ;;
        t)
            TID="${OPTARG}"
            ;;
        u)
            AWS_USERNAME="${OPTARG}"
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
if [[ (-z "${TID}") || (-z "${TAID}") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

CRYPTO_FILE_PATH="tenants/${TID}/${TAID}"

# Login credentials
OPTIONS="-v"
if [[ -n "${AWS_USERNAME}" ]]; then OPTIONS="${OPTIONS} -i ${AWS_USERNAME}"; fi
if [[ -n "${AWS_PASSWORD}" ]]; then OPTIONS="${OPTIONS} -s ${AWS_PASSWORD}"; fi
${BIN_DIR}/manageCredential.sh -f "${CRYPTO_FILE_PATH}" -n "root+aws" -t "Login" ${OPTIONS}
RESULT=$?
if [[ "${RESULT}" -ne 0 ]]; then exit; fi

# API credentials
OPTIONS="-v"
if [[ -n "${ACCESS_KEY}" ]]; then OPTIONS="${OPTIONS} -i ${ACCESS_KEY}"; fi
if [[ -n "${SECRET_KEY}" ]]; then OPTIONS="${OPTIONS} -s ${SECRET_KEY}"; fi
${BIN_DIR}/manageCredential.sh -f "${CRYPTO_FILE_PATH}" -n "gosource-root" -t "API" ${OPTIONS}
RESULT=$?
