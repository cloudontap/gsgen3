#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

BASE64_REGEX="^[A-Za-z0-9+/=\n]\+$"

CREDENTIAL_TYPE_VALUES=("Login" "API")
function usage() {
  echo -e "\nManage crypto for credential storage"
  echo -e "\nUsage: $(basename $0) -f CRYPTO_FILE -n CREDENTIAL_NAME -t CREDENTIAL_TYPE -i CREDENTIAL_ID -s CREDENTIAL_SECRET -e CREDENTIAL_EMAIL -v\n"
  echo -e "\nwhere\n"
  echo -e "(o) -e CREDENTIAL_EMAIL is the email associated with the credential (not encrypted)"
  echo -e "(o) -f CRYPTO_FILE is the path to the credentials file to be used"
  echo -e "    -h shows this text"
  echo -e "(o) -i CREDENTIAL_ID of credential (i.e. Username/Client Key/Access Key value) - not encrypted"
  echo -e "(m) -n CREDENTIAL_NAME for the set of values (id, secret, email)"
  echo -e "(o) -s CREDENTIAL_SECRET of credential (i.e. Password/Secret Key value) - encrypted"
  echo -e "(m) -t CREDENTIAL_TYPE of credential"
  echo -e "(o) -v if CREDENTIAL_SECRET should be decrypted (visible)"
  echo -e "\nDEFAULTS:\n"
  echo -e "CREDENTIAL_TYPE = ${CREDENTIAL_TYPE_VALUES[0]}"
  echo -e "\nNOTES:\n"
  echo -e "1. CREDENTIAL_TYPE is one of" "${CREDENTIAL_TYPE_VALUES[@]}"
  echo -e ""
  exit
}

# Parse options
while getopts ":e:f:hi:n:s:t:v" opt; do
    case $opt in
        e)
            CREDENTIAL_EMAIL="${OPTARG}"
            ;;
        f)
            export CRYPTO_FILE="${OPTARG}"
            ;;
        h)
            usage
            ;;
        i)
            CREDENTIAL_ID="${OPTARG}"
            ;;
        n)
            CREDENTIAL_NAME="${OPTARG}"
            ;;
        s)
            CREDENTIAL_SECRET="${OPTARG}"
            ;;
        t)
            CREDENTIAL_TYPE="${OPTARG}"
            ;;
        v)
            CRYPTO_VISIBLE="true"
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

CREDENTIAL_TYPE="${CREDENTIAL_TYPE:-${CREDENTIAL_TYPE_VALUES[0]}}"

# Ensure mandatory arguments have been provided
if [[ (-z "${CREDENTIAL_NAME}") || (-z "${CREDENTIAL_TYPE}") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Define JSON paths
PATH_BASE="Credentials[\"${CREDENTIAL_NAME}\"].${CREDENTIAL_TYPE}"
case ${CREDENTIAL_TYPE} in
    Login)
        ATTRIBUTE_ID="Username"
        ATTRIBUTE_SECRET="Password"
        ;;
    API)
        ATTRIBUTE_ID="AccessKey"
        ATTRIBUTE_SECRET="SecretKey"
        ;;
    *)
        echo -e "\nUnknown credential type \"${CREDENTIAL_TYPE}\""
        usage
        ;;
esac
ATTRIBUTE_EMAIL="Email"

PATH_ID=".${PATH_BASE}.${ATTRIBUTE_ID}"
PATH_SECRET=".${PATH_BASE}.${ATTRIBUTE_SECRET}"
PATH_EMAIL=".${PATH_BASE}.Email"

# Define which attributes to encrypt
ENCRYPT_ID="-n"
ENCRYPT_SECRET="-e"
ENCRYPT_EMAIL="-n"

# Perform updates if required
for ATTRIBUTE in ID SECRET EMAIL; do
    VAR_NAME="CREDENTIAL_${ATTRIBUTE}"
    VAR_PATH="PATH_${ATTRIBUTE}"
    VAR_ENCRYPT="ENCRYPT_${ATTRIBUTE}"
    if [[ -n "${!VAR_NAME}" ]]; then
        ${BIN_DIR}/manageCrypto.sh ${!VAR_ENCRYPT} -t "${!VAR_NAME}" -p "${!VAR_PATH}" -u -q
        RESULT=$?
        if [[ "${RESULT}" -ne 0 ]]; then
            echo -e "\nFailed to update credential ${ATTRIBUTE}"
            exit
        fi
    fi
done

# Display current values
echo -e "\n${PATH_BASE}"
for ATTRIBUTE in ID SECRET EMAIL; do
    VAR_PATH="PATH_${ATTRIBUTE}"
    VAR_ATTRIBUTE="ATTRIBUTE_${ATTRIBUTE}"
    VALUE=$(${BIN_DIR}/manageCrypto.sh -n -p "${!VAR_PATH}")
    RESULT=$?
    if [[ "${RESULT}" -eq 0 ]]; then
        ENCRYPTED=$(echo "${VALUE}" | grep -q "${BASE64_REGEX}")
        if [[ ($? -eq 0) && (-n "${CRYPTO_VISIBLE}" ) ]]; then
            VALUE=$(${BIN_DIR}/manageCrypto.sh -d -b -v -p "${!VAR_PATH}")
            RESULT=$?
            if [[ "${RESULT}" -eq 0 ]]; then
                echo -e "${!VAR_ATTRIBUTE}=${VALUE}"
            fi
        else
            echo -e "${!VAR_ATTRIBUTE}=${VALUE}"
        fi
    fi
done

# All good
RESULT=0