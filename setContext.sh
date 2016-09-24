#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi                           
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# If the context has already been determined, there is nothing to do
if [[ -n "${GSGEN_CONTEXT_DEFINED}" ]]; then return 0; fi
export GSGEN_CONTEXT_DEFINED="true"
GSGEN_CONTEXT_DEFINED_LOCAL="true"

export CURRENT_DIR="$(pwd)"

# Generate the list of files constituting the blueprint
pushd ${CURRENT_DIR} >/dev/null
BLUEPRINT_LIST=
CONTAINERS_LIST=("${BIN_DIR}/templates/containers/switch_start.ftl")

if [[ (-f "segment.json") || (-f "container.json") ]]; then
    # segment directory
    export LOCATION="${LOCATION:-segment}"
    export SEGMENT_DIR="$(pwd)"
    export SEGMENT="$(basename $(pwd))"

    if [[ -f "segment.json" ]]; then
        BLUEPRINT_LIST="${SEGMENT_DIR}/segment.json ${BLUEPRINT_LIST}"
    fi
    if [[ -f "container.json" ]]; then
        BLUEPRINT_LIST="${SEGMENT_DIR}/container.json ${BLUEPRINT_LIST}"
    fi
    if [[ -f "solution.json" ]]; then
        BLUEPRINT_LIST="${SEGMENT_DIR}/solution.json ${BLUEPRINT_LIST}"
    fi
    
    for CONTAINER in $(ls container_*.ftl 2> /dev/null); do
        CONTAINERS_LIST+=("${SEGMENT_DIR}/${CONTAINER}")
    done
    
    cd ..    

    # solutions directory
    export SOLUTIONS_DIR="$(pwd)"
    if [[ -f "solution.json" ]]; then
        BLUEPRINT_LIST="${SOLUTIONS_DIR}/solution.json ${BLUEPRINT_LIST}"
    fi
    
    for CONTAINER in $(ls container_*.ftl 2> /dev/null); do
        CONTAINERS_LIST+=("${SOLUTIONS_DIR}/${CONTAINER}")
    done

    cd ..
fi

if [[ -f "account.json" ]]; then
    # account directory
    # We check it before checking for a product as the account directory
    # also acts as a product directory for shared infrastructure
    # An account directory may also have no product information e.g.
    # in the case of production environments in dedicated accounts.
    export LOCATION="${LOCATION:-account}"
    export ROOT_DIR="$(cd ../..;pwd)"
fi

if [[ -f "product.json" ]]; then
    # product directory
    if [[ "${LOCATION}" == "account" ]]; then
        export LOCATION="account|product"
    else
        export LOCATION="${LOCATION:-product}"
    fi
    export PRODUCT_DIR="$(pwd)"
    export PID="$(basename $(pwd))"

    BLUEPRINT_LIST="${PRODUCT_DIR}/product.json ${BLUEPRINT_LIST}"
    export ROOT_DIR="$(cd ../..;pwd)"
fi

if [[ -f "integrator.json" ]]; then
    export LOCATION="${LOCATION:-integrator}"
    export ROOT_DIR="$(pwd)"
    export IID="$(basename $(pwd))"
fi

if [[ (-d config) && (-d infrastructure) ]]; then
    export LOCATION="${LOCATION:-root}"
    export ROOT_DIR="$(pwd)"
fi

if [[ -z "${ROOT_DIR}" ]]; then
    echo "\nCan't locate the root of the directory tree. Are we in the right place?"
    usage
fi

# root directory
cd "${ROOT_DIR}"
export AID="$(basename $(pwd))"
popd >/dev/null

export CONFIG_DIR="${ROOT_DIR}/config"
export INFRASTRUCTURE_DIR="${ROOT_DIR}/infrastructure"
export TENANT_DIR="${CONFIG_DIR}/${AID}"    
export ACCOUNT_DIR="${CONFIG_DIR}/${AID}"    
export ACCOUNT_CREDENTIALS_DIR="${INFRASTRUCTURE_DIR}/${AID}/credentials" 
export ACCOUNT_APPSETTINGS_DIR="${ACCOUNT_DIR}/appsettings" 
export ACCOUNT_CREDENTIALS="${ACCOUNT_CREDENTIALS_DIR}/credentials.json"    
    
if [[ -f "${ACCOUNT_DIR}/account.json" ]]; then
    BLUEPRINT_LIST="${ACCOUNT_DIR}/account.json ${BLUEPRINT_LIST}"
fi

if [[ -f "${TENANT_DIR}/tenant.json" ]]; then
    BLUEPRINT_LIST="${TENANT_DIR}/tenant.json ${BLUEPRINT_LIST}"
fi

# Build the composite solution ( aka blueprint)
export COMPOSITE_BLUEPRINT="${CONFIG_DIR}/composite_blueprint.json"
if [[ -n "${BLUEPRINT_LIST}" ]]; then
    ${BIN_DIR}/manageJSON.sh -o ${COMPOSITE_BLUEPRINT} "${BIN_DIR}/data/masterData.json" ${BLUEPRINT_LIST}
else
    echo "{}" > ${COMPOSITE_BLUEPRINT}
fi
    
# Extract and default key region settings from the composite solution
export ACCOUNT_REGION=${ACCOUNT_REGION:-$(cat ${COMPOSITE_BLUEPRINT} | jq -r '.Account.Region | select(.!=null)')}
export PRODUCT_REGION=${PRODUCT_REGION:-$(cat ${COMPOSITE_BLUEPRINT} | jq -r '.Product.Region | select(.!=null)')}
export REGION="${REGION:-$PRODUCT_REGION}"

if [[ -z "${REGION}" ]]; then
    echo -e "\nThe region must be defined in the Account or Product blueprint section. Nothing to do."
    usage
fi

# Build the composite containers list
export COMPOSITE_CONTAINERS="${CONFIG_DIR}/composite_containers.json"
for CONTAINER in $(find ${BIN_DIR}/templates/containers/container_*.ftl -maxdepth 1 2> /dev/null); do
    CONTAINERS_LIST+=("${CONTAINER}")
done
CONTAINERS_LIST+=("${BIN_DIR}/templates/containers/switch_end.ftl")
cat "${CONTAINERS_LIST[@]}" > ${COMPOSITE_CONTAINERS}

# Product specific context if the product is known
APPSETTINGS_LIST=
CREDENTIALS_LIST=
if [[ -n "${PID}" ]]; then
    export SOLUTIONS_DIR="${CONFIG_DIR}/${PID}/solutions"
    export APPSETTINGS_DIR="${CONFIG_DIR}/${PID}/appsettings"
    export CREDENTIALS_DIR="${INFRASTRUCTURE_DIR}/${PID}/credentials"
    
    # slice level appsettings
    if [[ (-n "${SLICE}") ]]; then
    
        if [[ -f "${APPSETTINGS_DIR}/${SEGMENT}/${SLICE}/slice.ref" ]]; then
            SLICE=$(cat "${APPSETTINGS_DIR}/${SEGMENT}/${SLICE}/slice.ref")
        fi
        
        if [[ -f "${APPSETTINGS_DIR}/${SEGMENT}/${SLICE}/appsettings.json" ]]; then
            APPSETTINGS_LIST="${APPSETTINGS_DIR}/${SEGMENT}/${SLICE}/appsettings.json ${APPSETTINGS_LIST}"
        fi

        if [[ -f "${APPSETTINGS_DIR}/${SEGMENT}/${SLICE}/build.ref" ]]; then
            export BUILD_REFERENCE=$(cat "${APPSETTINGS_DIR}/${SEGMENT}/${SLICE}/build.ref")
        fi
    fi
    
    # segment level appsettings/credentials
    if [[ (-n "${SEGMENT}") ]]; then
        if [[ -f "${APPSETTINGS_DIR}/${SEGMENT}/appsettings.json" ]]; then
            APPSETTINGS_LIST="${APPSETTINGS_DIR}/${SEGMENT}/appsettings.json ${APPSETTINGS_LIST}"
        fi

        if [[ -f "${CREDENTIALS_DIR}/${SEGMENT}/credentials.json" ]]; then
            CREDENTIALS_LIST="${CREDENTIALS_DIR}/${SEGMENT}/credentials.json ${CREDENTIALS_LIST}"
        fi
    fi
    
    # product level appsettings
    if [[ -f "${APPSETTINGS_DIR}/appsettings.json" ]]; then
        APPSETTINGS_LIST="${APPSETTINGS_DIR}/appsettings.json ${APPSETTINGS_LIST}"
    fi

    # product level credentials
    if [[ -f "${CREDENTIALS_DIR}/credentials.json" ]]; then
        CREDENTIALS_LIST="${CREDENTIALS_DIR}/credentials.json ${CREDENTIALS_LIST}"
    fi

    # account level appsettings
    if [[ -f "${ACCOUNT_APPSETTINGS_DIR}/appsettings.json" ]]; then
        APPSETTINGS_LIST="${ACCOUNT_APPSETTINGS_DIR}/appsettings.json ${APPSETTINGS_LIST}"
    fi
fi

# Build the composite appsettings
export COMPOSITE_APPSETTINGS="${CONFIG_DIR}/composite_appsettings.json"
if [[ -n "${APPSETTINGS_LIST}" ]]; then
    ${BIN_DIR}/manageJSON.sh -o ${COMPOSITE_APPSETTINGS} -c ${APPSETTINGS_LIST}
else
    echo "{}" > ${COMPOSITE_APPSETTINGS}
fi    

# Check for account level credentials
if [[ -f "${ACCOUNT_CREDENTIALS_DIR}/credentials.json" ]]; then
    CREDENTIALS_LIST="${ACCOUNT_CREDENTIALS_DIR}/credentials.json ${CREDENTIALS_LIST}"
fi

# Build the composite credentials
export COMPOSITE_CREDENTIALS="${INFRASTRUCTURE_DIR}/composite_credentials.json"
if [[ -n "${CREDENTIALS_LIST}" ]]; then
    ${BIN_DIR}/manageJSON.sh -o ${COMPOSITE_CREDENTIALS} ${CREDENTIALS_LIST}
else
    echo "{}" > ${COMPOSITE_CREDENTIALS}
fi    

# Create the composite stack outputs
STACK_LIST=()
if [[ (-n "${AID}") && (-d "${INFRASTRUCTURE_DIR}/${AID}/aws/cf") ]]; then
    STACK_LIST+=($(find "${INFRASTRUCTURE_DIR}/${AID}/aws/cf" -name account-*-stack.json))
fi
if [[ (-n "${PID}") && (-n "${REGION}") && (-d "${INFRASTRUCTURE_DIR}/${PID}/aws/cf") ]]; then
    STACK_LIST+=($(find "${INFRASTRUCTURE_DIR}/${PID}/aws/cf" -name product-${REGION}-stack.json))
fi
if [[ (-n "${SEGMENT}") && (-n "${REGION}") && (-d "${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf") ]]; then
    STACK_LIST+=($(find "${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf" -name *-${REGION}-stack.json))
fi

export COMPOSITE_STACK_OUTPUTS="${INFRASTRUCTURE_DIR}/composite_stack_outputs.json"
if [[ "${#STACK_LIST[@]}" -gt 0 ]]; then
    ${BIN_DIR}/manageJSON.sh -f "[.[].Stacks[].Outputs[]]" -o ${COMPOSITE_STACK_OUTPUTS} "${STACK_LIST[@]}"
else
    echo "[]" > ${COMPOSITE_STACK_OUTPUTS}
fi

# Set AWS credentials if available (hook from Jenkins framework)
CHECK_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${!AID_AWS_ACCESS_KEY_ID_VAR}}"
if [[ -n "${CHECK_AWS_ACCESS_KEY_ID}" ]]; then export AWS_ACCESS_KEY_ID="${CHECK_AWS_ACCESS_KEY_ID}"; fi
CHECK_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${!AID_AWS_SECRET_ACCESS_KEY_VAR}}"
if [[ -n "${CHECK_AWS_SECRET_ACCESS_KEY}" ]]; then export AWS_SECRET_ACCESS_KEY="${CHECK_AWS_SECRET_ACCESS_KEY}"; fi
    
# Set the profile for IAM access if AWS credentials not in the environment
if [[ ((-z "${AWS_ACCESS_KEY_ID}") || (-z "${AWS_SECRET_ACCESS_KEY}")) && (-n "${AID}") ]]; then
    export AWS_DEFAULT_PROFILE="${AID}"
fi

# Handle some MINGW peculiarities
uname | grep -i "MINGW64" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
    export MINGW64="true"
fi

# Detect if within a git repo
git status >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
    export WITHIN_GIT_REPO="true"
    export FILE_MV="git mv"
    export FILE_RM="git rm"
else
    export FILE_MV="mv"
    export FILE_RM="rm"
fi

