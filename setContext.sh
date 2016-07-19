#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

export CURRENT_DIR="$(pwd)"

# Generate the list of files constituting the aggregate solution
pushd ${CURRENT_DIR} >/dev/null
SOLUTION_LIST=
CONTAINERS_LIST=()

if [[ (-f "segment.json") || (-f "container.json") ]]; then
    # segment directory
    export LOCATION="${LOCATION:-segment}"
    export SEGMENT_DIR="$(pwd)"
    export SEGMENT="$(basename $(pwd))"

    if [[ -f "segment.json" ]]; then
        SOLUTION_LIST="${SEGMENT_DIR}/segment.json ${SOLUTION_LIST}"
    fi
    if [[ -f "container.json" ]]; then
        SOLUTION_LIST="${SEGMENT_DIR}/container.json ${SOLUTION_LIST}"
    fi
    if [[ -f "solution.json" ]]; then
        SOLUTION_LIST="${SEGMENT_DIR}/solution.json ${SOLUTION_LIST}"
    fi
    
    for CONTAINER in $(ls container_*.ftl 2> /dev/null); do
        CONTAINERS_LIST+=("${SEGMENT_DIR}/${CONTAINER}")
    done
    
    cd ..    

    # solutions directory
    export SOLUTIONS_DIR="$(pwd)"
    if [[ -f "solution.json" ]]; then
        SOLUTION_LIST="${SOLUTIONS_DIR}/solution.json ${SOLUTION_LIST}"
    fi
    
    for CONTAINER in $(ls container_*.ftl 2> /dev/null); do
        CONTAINERS_LIST+=("${SOLUTIONS_DIR}/${CONTAINER}")
    done

    cd ..
fi

if [[ -f "account.json" ]]; then
    # account directory
    # We check it before checking for a project as the account directory
    # also acts as a project directory for shared infrastructure
    # An account directory may also have no project information e.g.
    # in the case of production environments in dedicated accounts.
    export LOCATION="${LOCATION:-account}"
    export ROOT_DIR="$(cd ../..;pwd)"
fi

if [[ -f "project.json" ]]; then
    # project directory
    if [[ "${LOCATION}" == "account" ]]; then
        export LOCATION="${LOCATION:-account|project}"
    else
        export LOCATION="${LOCATION:-project}"
    fi
    export PROJECT_DIR="$(pwd)"
    export PID="$(basename $(pwd))"

    SOLUTION_LIST="${PROJECT_DIR}/project.json ${SOLUTION_LIST}"
    export ROOT_DIR="$(cd ../..;pwd)"
fi

if [[ (-d config) && (-d infrastructure) ]]; then
    export LOCATION="${LOCATION:-root}"
    export ROOT_DIR="$(pwd)"
fi

if [[ -z "${ROOT_DIR}" ]]; then
    echo "Can't locate the root of the directory tree. Are we in the right place?"
    usage
fi

# root directory
cd "${ROOT_DIR}"
export OAID="$(basename $(pwd))"
popd >/dev/null

export CONFIG_DIR="${ROOT_DIR}/config"
export INFRASTRUCTURE_DIR="${ROOT_DIR}/infrastructure"
export ORGANISATION_DIR="${CONFIG_DIR}/${OAID}"    
export ACCOUNT_DIR="${CONFIG_DIR}/${OAID}"    
export ACCOUNT_CREDENTIALS_DIR="${INFRASTRUCTURE_DIR}/${OAID}/credentials" 
export ACCOUNT_CREDENTIALS="${ACCOUNT_CREDENTIALS_DIR}/credentials.json"    
    
if [[ -f "${ACCOUNT_DIR}/account.json" ]]; then
    SOLUTION_LIST="${ACCOUNT_DIR}/account.json ${SOLUTION_LIST}"
fi

if [[ -f "${ORGANISATION_DIR}/organisation.json" ]]; then
    SOLUTION_LIST="${ORGANISATION_DIR}/organisation.json ${SOLUTION_LIST}"
fi

# Build the aggregate solution
export AGGREGATE_SOLUTION="${CONFIG_DIR}/aggregate_blueprint.json"
if [[ -n "${SOLUTION_LIST}" ]]; then
    ${BIN_DIR}/manageJSON.sh -o ${AGGREGATE_SOLUTION} ${SOLUTION_LIST}
else
    echo "{}" > ${AGGREGATE_SOLUTION}
fi
    
# Extract and default key region settings from the aggregate solution
export ACCOUNT_REGION=${ACCOUNT_REGION:-$(cat ${AGGREGATE_SOLUTION} | jq -r '.Account.Region | select(.!=null)')}
export PROJECT_REGION=${PROJECT_REGION:-$(cat ${AGGREGATE_SOLUTION} | jq -r '.Project.Region | select(.!=null)')}
export PROJECT_REGION="${PROJECT_REGION:-$ACCOUNT_REGION}"
export REGION="${REGION:-$PROJECT_REGION}"

if [[ -z "${REGION}" ]]; then
    echo -e "\nThe region must be defined in the Account or Project blueprint section. Nothing to do."
    usage
fi

# Build the aggregate containers list
export AGGREGATE_CONTAINERS="${CONFIG_DIR}/aggregate_containers.json"
for CONTAINER in $(find ${BIN_DIR}/templates/containers/container_*.ftl -maxdepth 1 2> /dev/null); do
    CONTAINERS_LIST+=("${CONTAINER}")
done

if [[ "${#CONTAINERS_LIST[@]}" -gt 0 ]]; then
    cat "${CONTAINERS_LIST[@]}" > ${AGGREGATE_CONTAINERS}
fi

# Project specific context if the project is known
DEPLOYMENT_LIST=
CREDENTIALS_LIST=
if [[ -n "${PID}" ]]; then
    export SOLUTIONS_DIR="${CONFIG_DIR}/${PID}/solutions"
    export DEPLOYMENTS_DIR="${CONFIG_DIR}/${PID}/deployments"
    export CREDENTIALS_DIR="${INFRASTRUCTURE_DIR}/${PID}/credentials"
    
    # slice level configuration
    if [[ (-n "${SLICE}") ]]; then
    
        if [[ -f "${DEPLOYMENTS_DIR}/${SEGMENT}/${SLICE}/slice.ref" ]]; then
            SLICE=$(cat "${DEPLOYMENTS_DIR}/${SEGMENT}/${SLICE}/slice.ref")
        fi
        
        if [[ -f "${DEPLOYMENTS_DIR}/${SEGMENT}/${SLICE}/config.json" ]]; then
            DEPLOYMENT_LIST="${DEPLOYMENTS_DIR}/${SEGMENT}/${SLICE}/config.json ${DEPLOYMENT_LIST}"
        fi

        if [[ -f "${DEPLOYMENTS_DIR}/${SEGMENT}/${SLICE}/build.ref" ]]; then
            export BUILD_REFERENCE=$(cat "${DEPLOYMENTS_DIR}/${SEGMENT}/${SLICE}/build.ref")
        fi
    fi
    
    # segment level configuration/credentials
    if [[ (-n "${SEGMENT}") ]]; then
        if [[ -f "${DEPLOYMENTS_DIR}/${SEGMENT}/config.json" ]]; then
            DEPLOYMENT_LIST="${DEPLOYMENTS_DIR}/${SEGMENT}/config.json ${DEPLOYMENT_LIST}"
        fi

        if [[ -f "${CREDENTIALS_DIR}/${SEGMENT}/credentials.json" ]]; then
            CREDENTIALS_LIST="${CREDENTIALS_DIR}/${SEGMENT}/credentials.json ${CREDENTIALS_LIST}"
        fi
    fi
    
    # project level configuration
    if [[ -f "${DEPLOYMENTS_DIR}/config.json" ]]; then
        DEPLOYMENT_LIST="${DEPLOYMENTS_DIR}/config.json ${DEPLOYMENT_LIST}"
    fi

    # project level credentials
    if [[ -f "${CREDENTIALS_DIR}/credentials.json" ]]; then
        CREDENTIALS_LIST="${CREDENTIALS_DIR}/credentials.json ${CREDENTIALS_LIST}"
    fi
fi

# Build the aggregate configuration
export AGGREGATE_CONFIGURATION="${CONFIG_DIR}/aggregate_configuration.json"
if [[ -n "${DEPLOYMENT_LIST}" ]]; then
    ${BIN_DIR}/manageJSON.sh -o ${AGGREGATE_CONFIGURATION} ${DEPLOYMENT_LIST}
else
    echo "{}" > ${AGGREGATE_CONFIGURATION}
fi    

# Check for account level credentials
if [[ -f "${ACCOUNT_CREDENTIALS_DIR}/credentials.json" ]]; then
    CREDENTIALS_LIST="${ACCOUNT_CREDENTIALS_DIR}/credentials.json ${CREDENTIALS_LIST}"
fi

# Build the aggregate credentials
export AGGREGATE_CREDENTIALS="${INFRASTRUCTURE_DIR}/aggregate_credentials.json"
if [[ -n "${CREDENTIALS_LIST}" ]]; then
    ${BIN_DIR}/manageJSON.sh -o ${AGGREGATE_CREDENTIALS} ${CREDENTIALS_LIST}
else
    echo "{}" > ${AGGREGATE_CREDENTIALS}
fi    

# Create the aggregate stack outputs
STACK_LIST=()
if [[ (-n "{OAID}") && (-d "${INFRASTRUCTURE_DIR}/${OAID}/aws/cf") ]]; then
    STACK_LIST+=($(find "${INFRASTRUCTURE_DIR}/${OAID}/aws/cf" -name account-*-stack.json))
fi
if [[ (-n "{PID}") && (-n "${REGION}") && (-d "${INFRASTRUCTURE_DIR}/${PID}/aws/cf") ]]; then
    STACK_LIST+=($(find "${INFRASTRUCTURE_DIR}/${PID}/aws/cf" -name *-${REGION}-stack.json))
fi
if [[ (-n "{SEGMENT}") && (-n "${REGION}") && (-d "${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf") ]]; then
    STACK_LIST+=($(find "${INFRASTRUCTURE_DIR}/${PID}/aws/${SEGMENT}/cf" -name *-${REGION}-stack.json))
fi

export AGGREGATE_STACK_OUTPUTS="${INFRASTRUCTURE_DIR}/aggregate_stack_outputs.json"
if [[ "${#STACK_LIST[@]}" -gt 0 ]]; then
    ${BIN_DIR}/manageJSON.sh -f "[.[].Stacks[].Outputs[]]" -o ${AGGREGATE_STACK_OUTPUTS} "${STACK_LIST[@]}"
else
    echo "[]" > ${AGGREGATE_STACK_OUTPUTS}
fi

# Set AWS credentials if available (hook from Jenkins framework)
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-${!OAID_AWS_ACCESS_KEY_ID_VAR}}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-${!OAID_AWS_SECRET_ACCESS_KEY_VAR}}"
    
# Set the profile for IAM access if AWS credentials not in the environment
if [[ ((-z "${AWS_ACCESS_KEY_ID}") || (-z "${AWS_SECRET_ACCESS_KEY}")) && (-n "${OAID}") ]]; then
    export PROFILE="--profile ${OAID}"
fi

# Handle some MINGW peculiarities
uname | grep -i "MINGW64" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
    MINGW64="true"
fi




