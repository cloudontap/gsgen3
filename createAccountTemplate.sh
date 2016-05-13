#!/bin/bash

function usage() {
  echo -e "\nCreate the account specific CloudFormation template" 
  echo -e "\nUsage: $(basename $0) -h"
  echo -e "\nwhere\n"
  echo -e "(m) -a OAID is the organisation account id e.g. \"env01\""
  echo -e "    -h shows this text"
  echo -e "\nNOTES:\n"
  echo -e "1) You must be in the OAID directory when running this script"
  echo -e ""
  exit 1
}

# Parse options
while getopts ":a:h" opt; do
  case $opt in
    a)
      OAID=$OPTARG
      ;;
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

# Ensure mandatory arguments have been provided
if [[ "${OAID}" == "" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ROOT_DIR="$(pwd)"
ROOT="$(basename ${ROOT_DIR})"

ACCOUNT_DIR="${ROOT_DIR}/config/${OAID}"

CF_DIR="${ROOT_DIR}/infrastructure/${OAID}/aws/${CONTAINER}/cf"

if [[ "${OAID}" != "${ROOT}" ]]; then
    echo -e "\nThe provided OAID (${OAID}) doesn't match the root directory (${ROOT}). Nothing to do."
    usage
fi

cd ${ACCOUNT_DIR}
if [[ ! -f account.json ]]; then
    echo -e "\nNo \"account.json\" file in the config/${OAID} directory. Nothing to do."
    usage
fi 

REGION=$(grep '"Region"' account.json | cut -d '"' -f 4)

if [[ "${REGION}" == "" ]]; then
    echo -e "\nThe region must be defined in the account configuration file. Are we in the correct directory? Nothing to do."
    usage
fi

if [[ ! -d ${CF_DIR} ]]; then mkdir -p ${CF_DIR}; fi

TEMPLATE="createAccount.ftl"
TEMPLATEDIR="${BIN}/templates"
OUTPUT="${CF_DIR}/account-${REGION}-template.json"

ARGS="-v organisation=organisation.json"
ARGS="${ARGS} -v account=account.json"
ARGS="${ARGS} -v masterData=$BIN/data/masterData.json"

CMD="${BIN}/gsgen.sh -t $TEMPLATE -d $TEMPLATEDIR -o $OUTPUT $ARGS"
eval $CMD

exit $?
