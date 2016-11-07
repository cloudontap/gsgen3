#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && cd .. && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
    
function usage() {
  echo -e "\nAdd a new account for a tenant"
  echo -e "\nUsage: $(basename $0) -l TITLE -n NAME -d DESCRIPTION -a TAID -t TID -o DOMAIN -r AWS_REGION -s AWS_SES_REGION -c AWS_ID -f -u"
  echo -e "\nwhere\n"
  echo -e "(m) -a TAID is the tenant account id"
  echo -e "(o) -c AWS_ID is the AWS account id"
  echo -e "(o) -d DESCRIPTION is the account description"
  echo -e "(o) -f if an existing shelf account should be used as the basis for the new account"
  echo -e "    -h shows this text"
  echo -e "(o) -l TITLE is the account title"
  echo -e "(o) -n NAME is the human readable form (one word, lowercase and no spaces) of the account id"
  echo -e "(o) -o DOMAIN is the default DNS domain to be used for account products"
  echo -e "(o) -r AWS_REGION is the AWS region identifier for the region in which the account will be created"
  echo -e "(o) -s AWS_SES_REGION is the default AWS region for use of the SES service"
  echo -e "(m) -t TID is the tenant id"
  echo -e "(o) -u if details should be updated"
  echo -e "\nDEFAULTS:\n"
  echo -e "\nNOTES:\n"
  echo -e "1) A sub-directory is created for the account under the tenant"
  echo -e "2) The account information is saved in the account profile"
  echo -e "3) To update the details, the update option must be explicitly set"
  echo -e ""
  exit
}

# Parse options
while getopts ":a:c:d:fhl:n:o:r:s:t:u" opt; do
  case $opt in
    a)
      TAID=$OPTARG
      ;;
    c)
      AWS_ID=$OPTARG
      ;;
    d)
      DESCRIPTION="$OPTARG"
      ;;
    f)
      USE_SHELF_ACCOUNT="true"
       ;;
    h)
      usage
      ;;
    l)
      TITLE="$OPTARG"
       ;;
    n)
      NAME=$OPTARG
       ;;
    o)
      DOMAIN="$OPTARG"
       ;;
    r)
      AWS_REGION=$OPTARG
       ;;
    s)
      AWS_SES_REGION=$OPTARG
       ;;
    t)
      TID=$OPTARG
      ;;
    u)
      UPDATE_ACCOUNT="true"
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

# Ensure the tenant already exists
TENANT_DIR="${ROOT_DIR}/tenants/${TID}"
if [[ ! -d "${TENANT_DIR}" ]]; then
    echo -e "\nThe tenant needs to be added before the account"
    usage
fi

# Create the directory for the account, potentially using a shelf account
ACCOUNTS_DIR="${TENANT_DIR}/accounts"
mkdir -p "${ACCOUNTS_DIR}"
ACCOUNT_DIR="${ACCOUNTS_DIR}/${TAID}"
if [[ ! -d "${ACCOUNT_DIR}" ]]; then
    if [[ "${USE_SHELF_ACCOUNT}" == "true" ]]; then
        # Find the highest numbered shelf account available
        for I in $(seq 1 9); do
            SHELF_ACCOUNT="${ROOT_DIR}/tenants/shelf/accounts/shelf0${I}"
            if [[ -d "${SHELF_ACCOUNT}" ]]; then
                LAST_SHELF_ACCOUNT="${SHELF_ACCOUNT}"
            fi
        done
        if [[ -n "${LAST_SHELF_ACCOUNT}" ]]; then
            ${FILE_MV} "${LAST_SHELF_ACCOUNT}" "${ACCOUNT_DIR}"
        fi
    fi
fi
if [[ ! -d "${ACCOUNT_DIR}" ]]; then
    mkdir -p ${ACCOUNT_DIR}
fi

# Check whether the account profile is already in place
if [[ -f ${ACCOUNT_DIR}/account.json ]]; then
    if [[ ("${UPDATE_ACCOUNT}" != "true") &&
          (-z "${LAST_SHELF_ACCOUNT}") ]]; then
        echo -e "\nAccount profile already exists. Maybe try using update option?"
        usage
    fi
    ACCOUNT_PROFILE=${ACCOUNT_DIR}/account.json
else
    ACCOUNT_PROFILE=${BIN_DIR}/templates/blueprint/account.json
fi

# Generate the filter
FILTER=". | .Account.Id=\$TAID"
if [[ -n "${NAME}" ]]; then FILTER="${FILTER} | .Account.Name=\$NAME"; fi
if [[ -n "${TITLE}" ]]; then FILTER="${FILTER} | .Account.Title=\$TITLE"; fi
if [[ -n "${DESCRIPTION}" ]]; then FILTER="${FILTER} | .Account.Description=\$DESCRIPTION"; fi
if [[ -n "${AWS_ID}" ]]; then FILTER="${FILTER} | .Account.AWSId=\$AWS_ID"; fi
if [[ -n "${AWS_REGION}" ]]; then FILTER="${FILTER} | .Account.Region=\$AWS_REGION"; fi
if [[ -n "${AWS_REGION}" ]]; then FILTER="${FILTER} | .Product.Region=\$AWS_REGION"; fi
if [[ -n "${AWS_SES_REGION}" ]]; then FILTER="${FILTER} | .Product.SES.Region=\$AWS_SES_REGION"; fi
if [[ -n "${DOMAIN}" ]]; then FILTER="${FILTER} | .Product.Domain.Stem=\$DOMAIN"; fi
if [[ -n "${DOMAIN}" ]]; then FILTER="${FILTER} | .Product.Domain.Certificate.Id=\$TAID"; fi

# Generate the account profile
cat ${ACCOUNT_PROFILE} | jq --indent 4 \
--arg TAID "${TAID}" \
--arg NAME "${NAME}" \
--arg TITLE "${TITLE}" \
--arg DESCRIPTION "${DESCRIPTION}" \
--arg AWS_ID "${AWS_ID}" \
--arg AWS_REGION "${AWS_REGION}" \
--arg DOMAIN "${DOMAIN}" \
"${FILTER}" > ${ACCOUNT_DIR}/temp_account.json
RESULT=$?

if [[ ${RESULT} -eq 0 ]]; then
    mv ${ACCOUNT_DIR}/temp_account.json ${ACCOUNT_DIR}/account.json
else
    echo -e "\nError creating account profile" 
    exit
fi

# Provide an empty credentials profile for the account
if [[ ! -f ${ACCOUNT_DIR}/credentials.json ]]; then
    echo "{\"Credentials\" : {}}" | jq --indent 4 '.' > ${ACCOUNT_DIR}/credentials.json
fi

# All good
RESULT=0
