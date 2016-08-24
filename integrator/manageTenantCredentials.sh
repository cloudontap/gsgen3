#!/bin/bash
                                                                                        
if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && cd .. && pwd )
trap '${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

CRYPTO_OPERATION_DEFAULT="decrypt"
function usage() {
  echo -e "\nManage account credentials"
  echo -e "\nUsage: $(basename $0) -e -d -t TID -a TAID -k ACCESS_KEY -s SECREY_KEY -u AWS_USERNAME -p AWS_PASSWORD\n"
  echo -e "\nwhere\n"
  echo -e "(m) -a TAID is the tenant account id"
  echo -e "(o) -d decrypt operation"
  echo -e "(o) -e encrypt operation"
  echo -e "    -h shows this text"
  echo -e "(o) -k ACCESS_KEY specifies the API access key value"
  echo -e "(o) -p AWS_PASSWORD specifies the AWS account password"
  echo -e "(o) -s SECRET_KEY specifies the API secret key value"
  echo -e "(m) -t TID is the organisation id"
  echo -e "(o) -u AWS_USERNAME specifies the AWS account username"
  echo -e "\nDEFAULTS:\n"
  echo -e "OPERATION = ${CRYPTO_OPERATION_DEFAULT}"
  echo -e "\nNOTES:\n"
  echo -e "1. decrypt shows the current values for all four fields"
  echo -e "2. encrypt updates whichever fields are provided on the command line"
  echo -e ""
  exit
}

# Parse options
while getopts ":a:dehk:p:s:t:u:" opt; do
    case $opt in
        a)
            TAID="${OPTARG}"
            ;;
        d)
            CRYPTO_OPERATION="decrypt"
            ;;
        e)
            CRYPTO_OPERATION="encrypt"
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

# Set up the context
. ${BIN_DIR}/setContext.sh

# Ensure we are in the integrator tree
if [[ "${LOCATION}" != "integrator" ]]; then
    echo -e "\nWe don't appear to be in the integrator tree. Are we in the right place?"
    usage
fi

CRYPTO_OPERATION="${CRYPTO_OPERATION:-$CRYPTO_OPERATION_DEFAULT}"
CRYPTO_FILE_PATH="tenants/${TID}/${TAID}"
CRYPTO_FILE="${CRYPTO_FILE_PATH}/credentials.json"


# Ensure the tenant/account already exists
if [[ ! -f "${CRYPTO_FILE}" ]]; then
    echo -e "\nThe tenant/account needs to be added before managing credentials"
    usage
fi

PATH_LOGIN_USER='.Credentials["root+aws"].Login.Username'
PATH_LOGIN_PASSWORD='.Credentials["root+aws"].Login.Password'
PATH_API_ACCESS_KEY='.Credentials["gosource-root"].API.AccessKey'
PATH_API_SECRET_KEY='.Credentials["gosource-root"].API.SecretKey'

case "${CRYPTO_OPERATION}" in
    encrypt)
        OPTIONS="-e -u"
        if [[ -n "${AWS_USERNAME}" ]]; then
            echo -e "\nUSERNAME=$($BIN_DIR/manageCrypto.sh    -f ${CRYPTO_FILE_PATH} -p ${PATH_LOGIN_USER} -t ${AWS_USERNAME} ${OPTIONS})"
        fi
        if [[ -n "${AWS_PASSWORD}" ]]; then
            echo -e "\nPASSWORD=$($BIN_DIR/manageCrypto.sh   -f ${CRYPTO_FILE_PATH} -p ${PATH_LOGIN_PASSWORD} -t ${AWS_PASSWORD} ${OPTIONS})"
        fi
        if [[ -n "${ACCESS_KEY}" ]]; then
            echo -e "\nACCESS_KEY=$($BIN_DIR/manageCrypto.sh -f ${CRYPTO_FILE_PATH} -p ${PATH_API_ACCESS_KEY} -t ${ACCESS_KEY} ${OPTIONS})"
        fi
        if [[ -n "${SECRET_KEY}" ]]; then
            echo -e "\nSECRET_KEY=$($BIN_DIR/manageCrypto.sh -f ${CRYPTO_FILE_PATH} -p ${PATH_API_SECRET_KEY} -t ${SECRET_KEY} ${OPTIONS})"
        fi
        ;;
    *)
        OPTIONS="-d -b -v"
        echo -e "USERNAME=$($BIN_DIR/manageCrypto.sh   -f ${CRYPTO_FILE_PATH} -p ${PATH_LOGIN_USER}     ${OPTIONS})"
        echo -e "PASSWORD=$($BIN_DIR/manageCrypto.sh   -f ${CRYPTO_FILE_PATH} -p ${PATH_LOGIN_PASSWORD} ${OPTIONS})"
        echo -e "ACCESS_KEY=$($BIN_DIR/manageCrypto.sh -f ${CRYPTO_FILE_PATH} -p ${PATH_API_ACCESS_KEY} ${OPTIONS})"  
        echo -e "SECRET_KEY=$($BIN_DIR/manageCrypto.sh -f ${CRYPTO_FILE_PATH} -p ${PATH_API_SECRET_KEY} ${OPTIONS})"  
        ;;
esac

# All good
RESULT=0

