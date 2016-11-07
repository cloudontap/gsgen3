#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && cd .. && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
    
function usage() {
  echo -e "\nPopulate the account tree for an account"
  echo -e "\nUsage: $(basename $0) -t TID -a TAID -c INIT_CONFIG_DIR -i INIT_INFRASTRUCTURE_DIR -u"
  echo -e "\nwhere\n"
  echo -e "(m) -a TAID is the tenant account id"
  echo -e "(m) -c INIT_CONFIG_DIR is the directory to hold the the config repo"
  echo -e "    -h shows this text"
  echo -e "(m) -i INIT_INFRASTRUCTURE_DIR is the directory to hold the infrastructure repo"
  echo -e "(m) -t TID is the tenant id"
  echo -e "(o) -u if details should be updated"
  echo -e "\nDEFAULTS:\n"
  echo -e "\nNOTES:\n"
  echo -e "1) The directory tree expected by gsgen3 is created under the "
  echo -e "   provided directories, which are created if they don't exist"
  echo -e "2) To update the details, the update option must be explicitly set"
  echo -e ""
  exit
}

# Parse options
while getopts ":a:c:hi:t:u" opt; do
  case $opt in
    a)
      TAID=$OPTARG
      ;;
    c)
      INIT_CONFIG_DIR=$OPTARG
      ;;
    h)
      usage
      ;;
    i)
      INIT_INFRASTRUCTURE_DIR=$OPTARG
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
      (-z "${TAID}") ||
      (-z "${INIT_CONFIG_DIR}") ||
      (-z "${INIT_INFRASTRUCTURE_DIR}") ]]; then
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
if [[ (-e "${INIT_CONFIG_DIR}/account.json") ]]; then
    if [[ ("${UPDATE_TREE}" != "true") ]]; then
        echo -e "\nAccount tree already exists. Maybe try using the update option?"
        usage
    fi
fi

# Populate the config tree
mkdir -p ${INIT_CONFIG_DIR}
cd ${INIT_CONFIG_DIR}

# Copy across key files
cp -p ${TENANT_DIR}/tenant.json .
cp -p ${ACCOUNT_DIR}/account.json .

# Extract account information
AWS_ID=$(jq -r '.[0] * .[1] | .Account.AWSId | select(.!=null)' -s tenant.json account.json)
AWS_REGION=$(jq -r '.[0] * .[1] | .Account.Region | select(.!=null)' -s tenant.json account.json)

# Provide the docker registry endpoint by default
APPSETTINGS_DIR=${INIT_CONFIG_DIR}/appsettings
mkdir -p ${APPSETTINGS_DIR}
cd ${APPSETTINGS_DIR}

if [[ -f appsettings.json ]]; then
    ACCOUNT_APPSETTINGS=appsettings.json
else
    ACCOUNT_APPSETTINGS=${BIN_DIR}/templates/blueprint/accountAppSettings.json
fi

# Generate the filter
FILTER=". | .Docker.Registry=\"${AWS_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com\""

# Generate the account appsettings
cat ${ACCOUNT_APPSETTINGS} | jq --indent 4 \
"${FILTER}" > temp_appsettings.json
RESULT=$?

if [[ ${RESULT} -eq 0 ]]; then
    mv temp_appsettings.json appsettings.json
else
    echo -e "\nError creating account appsettings" 
    exit
fi

# Populate the infrastructure tree
mkdir -p ${INIT_INFRASTRUCTURE_DIR}
cd ${INIT_INFRASTRUCTURE_DIR}

# Generate default credentials 
CREDENTIALS_DIR=${INIT_INFRASTRUCTURE_DIR}/credentials
mkdir -p ${CREDENTIALS_DIR}
cd ${CREDENTIALS_DIR}

if [[ ! -f credentials.json ]]; then
    echo "{\"Credentials\" : {}}" | jq --indent 4 '.' > credentials.json
fi

# All good
RESULT=0
