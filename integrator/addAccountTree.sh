#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && cd .. && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
    
function usage() {
  echo -e "\nPopulate the account tree for an account"
  echo -e "\nUsage: $(basename $0) -a TAID -t TID -u"
  echo -e "\nwhere\n"
  echo -e "(m) -a TAID is the tenant account id"
  echo -e "    -h shows this text"
  echo -e "(m) -t TID is the tenant id"
  echo -e "(o) -u if details should be updated"
  echo -e "\nDEFAULTS:\n"
  echo -e "\nNOTES:\n"
  echo -e "1) The directory tree expected by gsgen3 is created under a TAID sub-directory"
  echo -e "   of the account directory"
  echo -e "2) To update the details, the update option must be explicitly set"
  echo -e ""
  exit
}

# Parse options
while getopts ":a:ht:u" opt; do
  case $opt in
    a)
      TAID=$OPTARG
      ;;
    h)
      usage
      ;;
    t)
      TID=$OPTARG
      ;;
    u)
      UPDATE_TREE="true"
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
if [[ (-z "${TID}") ||
      (-z "${TAID}") ]]; then
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

# Ensure the tenant/account already exists
TENANT_DIR="${ROOT_DIR}/tenants/${TID}"
ACCOUNT_DIR="${TENANT_DIR}/accounts/${TAID}"
if [[ ! -d "${ACCOUNT_DIR}" ]]; then
    echo -e "\nThe tenant/account doesn't appear to exist. Nothing to do."
    usage
fi

# Check whether the tree is already in place
ACCOUNT_TREE_DIR="${ACCOUNT_DIR}/${TAID}"
ACCOUNT_CONFIG_DIR=${ACCOUNT_TREE_DIR}/config/${TAID}
ACCOUNT_INFRASTRUCTURE_DIR=${ACCOUNT_TREE_DIR}/infrastructure/${TAID}
if [[ -d ${ACCOUNT_TREE_DIR} ]]; then
    if [[ ("${UPDATE_TREE}" != "true") ]]; then
        echo -e "\nAccount tree already exists. Maybe try using the update option?"
        usage
    fi
fi

# Create the config tree
mkdir -p ${ACCOUNT_CONFIG_DIR}
cd ${ACCOUNT_CONFIG_DIR}

# Copy across key files
cp -p ${TENANT_DIR}/tenant.json .
cp -p ${ACCOUNT_DIR}/account.json .

# Extract account information
AWS_ID=$(jq -r '.[0] * .[1] | .Account.AWSId | select(.!=null)' -s tenant.json account.json)
AWS_REGION=$(jq -r '.[0] * .[1] | .Account.Region | select(.!=null)' -s tenant.json account.json)

# Provide the docker registry endpoint by default
ACCOUNT_APPSETTINGS_DIR=${ACCOUNT_CONFIG_DIR}/appsettings
mkdir -p ${ACCOUNT_APPSETTINGS_DIR}
cd ${ACCOUNT_APPSETTINGS_DIR}

if [[ -f appsettings.json ]]; then
    ACCOUNT_APPSETTINGS=appsettings.json
else
    ACCOUNT_APPSETTINGS=${BIN_DIR}/templates/blueprint/accountAppSettings.json
fi

# Generate the filter
FILTER=". | .Docker.Registry=\"${AWS_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""

# Generate the account appsettings
cat ${ACCOUNT_APPSETTINGS} | jq --indent 4 \
"${FILTER}" > ${ACCOUNT_APPSETTINGS_DIR}/temp_appsettings.json
RESULT=$?

if [[ ${RESULT} -eq 0 ]]; then
    mv ${ACCOUNT_APPSETTINGS_DIR}/temp_appsettings.json ${ACCOUNT_APPSETTINGS_DIR}/appsettings.json
else
    echo -e "\nError creating account appsettings" 
    exit
fi

# Create the infrastructure tree
ACCOUNT_CREDENTIALS_DIR=${ACCOUNT_INFRASTRUCTURE_DIR}/credentials
mkdir -p ${ACCOUNT_CREDENTIALS_DIR}

if [[ ! -f ${ACCOUNT_CREDENTIALS_DIR}/credentials.json ]]; then
    echo "{\"Credentials\" : {}}" | jq --indent 4 '.' > ${ACCOUNT_CREDENTIALS_DIR}/credentials.json
fi

# All good
RESULT=0
