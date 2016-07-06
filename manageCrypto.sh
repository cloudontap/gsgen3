#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

trap 'find . -name "ciphertext*" -delete' EXIT SIGHUP SIGINT SIGTERM

ALIAS_DEFAULT="$(basename $(cd ../../;pwd))"
OPERATION_DEFAULT="encrypt"
function usage() {
  echo -e "\nManage cryptographic operations using KMS" 
  echo -e "\nUsage: $(basename $0) -e -d -f FILE -t TEXT -a ALIAS -b\n"
  echo -e "\nwhere\n"
  echo -e "(o) -a ALIAS for the master key to be used"
  echo -e "(o) -b base64 decode the input before processing"
  echo -e "(o) -d decrypt operation"
  echo -e "(o) -e encrypt operation"
  echo -e "(o) -f FILE contains the plaintext or ciphertext to be processed"
  echo -e "    -h shows this text"
  echo -e "(o) -t TEXT is the plaintext or ciphertext to be processed"
  echo -e "\nDEFAULTS:\n"
  echo -e "ALIAS     = ${ALIAS_DEFAULT}"
  echo -e "OPERATION = ${OPERATION_DEFAULT}"
  echo -e "\nNOTES:\n"
  echo -e "1) Result is sent to stdout and is always base64 encoded"
  echo -e "2) Don't include \"alias/\" in any provided alias"
  echo -e "3) One of FILE or TEXT must be provided"
  echo -e ""
  exit 1
}

ALIAS="${ALIAS_DEFAULT}"
OPERATION="${OPERATION_DEFAULT}"
# Parse options
while getopts ":a:bdef:ht:" opt; do
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
if [[ -z "${CRYPTO_TEXT}" && -z "${CRYPTO_FILE}" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

CURRENT_DIR="$(pwd)"
PROJECT_DIR="$(cd ../../;pwd)"
ROOT_DIR="$(cd ../../../../;pwd)"

SEGMENT="$(basename ${CURRENT_DIR})"
PID="$(basename ${PROJECT_DIR})"
OAID="$(basename ${ROOT_DIR})"

CONFIG_DIR="${ROOT_DIR}/config"

ACCOUNT_DIR="${CONFIG_DIR}/${OAID}"

ACCOUNTFILE="${ACCOUNT_DIR}/account.json"
SEGMENTFILE="${CURRENT_DIR}/segment.json"
if [[ -f "${CURRENT_DIR}/container.json" ]]; then
    SEGMENTFILE="${CURRENT_DIR}/container.json"
fi

if [[ -f solution.json ]]; then
	SOLUTIONFILE="solution.json"
else
	SOLUTIONFILE="../solution.json"
fi

if [[ ! -f ${SEGMENTFILE} ]]; then
    echo -e "\nNo \"${SEGMENTFILE}\" file in current directory. Are we in a segment directory? Nothing to do."
    usage
fi 

REGION=$(grep '"Region"' ${SEGMENTFILE} | cut -d '"' -f 4)
if [[ -z "${REGION}" && -e ${SOLUTIONFILE} ]]; then
  REGION=$(grep '"Region"' ${SOLUTIONFILE} | cut -d '"' -f 4)
fi
if [[ -z "${REGION}" && -e ${ACCOUNTFILE} ]]; then
  REGION=$(grep '"Region"' ${ACCOUNTFILE} | cut -d '"' -f 4)
fi

if [[ "${REGION}" == "" ]]; then
    echo -e "\nThe region must be defined in the segment/solution/account configuration files (in this preference order). Nothing to do."
    usage
fi


# Set the profile if on PC to pick up the IAM credentials to use to access the credentials bucket. 
# For other platforms, assume the server has a service role providing access.
uname | grep -iE "MINGW64|Darwin|FreeBSD" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
    PROFILE="--profile ${OAID}"
fi

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
            --encryption-context "{\"gs:segment\":\"${SEGMENT}\"}" \
            --key-id "alias/${ALIAS}" --query CiphertextBlob \
            --plaintext "fileb://ciphertext.bin" | dos2unix
        ;;
    decrypt)
        aws ${PROFILE} --region ${REGION} --output text kms ${OPERATION} \
            --encryption-context "{\"gs:segment\":\"${SEGMENT}\"}" \
            --query Plaintext \
            --ciphertext-blob "fileb://ciphertext.bin" | dos2unix
        ;;
esac

