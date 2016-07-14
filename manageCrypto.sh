#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap '${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

OPERATION_DEFAULT="encrypt"
function usage() {
  echo -e "\nManage cryptographic operations using KMS" 
  echo -e "\nUsage: $(basename $0) -e -d -f FILE -t TEXT -a ALIAS -k KEYID -b\n"
  echo -e "\nwhere\n"
  echo -e "(o) -a ALIAS for the master key to be used"
  echo -e "(o) -b base64 decode the input before processing"
  echo -e "(o) -d decrypt operation"
  echo -e "(o) -e encrypt operation"
  echo -e "(o) -f FILE contains the plaintext or ciphertext to be processed"
  echo -e "    -h shows this text"
  echo -e "(o) -k KEYID for the master key to be used"
  echo -e "(o) -t TEXT is the plaintext or ciphertext to be processed"
  echo -e "\nDEFAULTS:\n"
  echo -e "OPERATION = ${OPERATION_DEFAULT}"
  echo -e "\nNOTES:\n"
  echo -e "1) Result is sent to stdout and is always base64 encoded"
  echo -e "2) Don't include \"alias/\" in any provided alias"
  echo -e "3) One of FILE or TEXT must be provided"
  echo -e "3) One of ALIAS or KEYID must be provided if encrypting"
  echo -e ""
}

ALIAS="${ALIAS_DEFAULT}"
OPERATION="${OPERATION_DEFAULT}"
# Parse options
while getopts ":a:bdef:hk:t:" opt; do
    case $opt in
        a)
            ALIAS=$OPTARG
            ;;
        b)
            CRYPTO_DECODE="true"
            ;;
        d)
            OPERATION="decrypt"
            ;;
        e)
            OPERATION="encrypt"
            ;;
        f)
            CRYPTO_FILE=$OPTARG
            ;;
        h)
            usage
            ;;
        k)
            KEYID=$OPTARG
            ;;
        t)
            CRYPTO_TEXT=$OPTARG
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
if [[ (-z "${CRYPTO_TEXT}") && (-z "${CRYPTO_FILE}") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi
if [[ ("${OPERATION}" == "encrypt") && (-z "${ALIAS}") && (-z "${KEYID}") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi
KEYID="${KEYID:-alias/$ALIAS}"

# Set up the context
. ${BIN_DIR}/setContext.sh

# Get the input 
if [[ -n "${CRYPTO_TEXT}" ]]; then
    echo -n "${CRYPTO_TEXT}" > ./ciphertext.src
else
    cp ${CRYPTO_FILE} ./ciphertext.src
fi

# base64 decode if necessary
if [[ -n "${CRYPTO_DECODE}" ]]; then
    dos2unix < ./ciphertext.src | base64 -d  > ./ciphertext.bin
else
    mv ./ciphertext.src ./ciphertext.bin
fi
        
# Perform the operation
case ${OPERATION} in
    encrypt)
        aws ${PROFILE} --region ${REGION} --output text kms ${OPERATION} \
            --key-id "${KEYID}" --query CiphertextBlob \
            --plaintext "fileb://ciphertext.bin" | dos2unix
        ;;
    decrypt)
        aws ${PROFILE} --region ${REGION} --output text kms ${OPERATION} \
            --query Plaintext \
            --ciphertext-blob "fileb://ciphertext.bin" | dos2unix
        ;;
esac
RESULT=$?
