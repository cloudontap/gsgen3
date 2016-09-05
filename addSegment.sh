#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR=$( cd $( dirname "${BASH_SOURCE[0]}" ) && pwd )
trap '. ${BIN_DIR}/cleanupContext.sh; exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
    echo -e "\nAdd a new segment"
    echo -e "\nUsage: $(basename $0) -l TITLE -n NAME -d DESCRIPTION -s SID -e EID -o DOMAIN -r AWS_REGION -u"
    echo -e "\nwhere\n"
    echo -e "(o) -d DESCRIPTION is the segment description"
    echo -e "(o) -e EID is the ID of the environment of which this segment is part"
    echo -e "    -h shows this text"
    echo -e "(o) -l TITLE is the segment title"
    echo -e "(m) -n NAME is the human readable form (one word, lowercase and no spaces) of the segment id"
    echo -e "(o) -o DOMAIN is the default DNS domain to be used for the segment"
    echo -e "(o) -r AWS_REGION is the default AWS region for the segment"
    echo -e "(o) -s SID is the segment id"
    echo -e "(o) -u if details should be updated"
    echo -e "\nDEFAULTS:\n"
    echo -e "EID=SID"
    echo -e "TITLE,NAME and DESCRIPTION from environment master data for EID"
    echo -e "\nNOTES:\n"
    echo -e "1. Subdirectories are created in the config and infrastructure subtrees"
    echo -e "2. The segment information is saved in the segment profile"
    echo -e "3. To update the details, the update option must be explicitly set"
    echo -e "4. The environment must exist in the masterData"
    echo -e "5. EID or SID are required if creating a segment"
    echo -e ""
    exit
}

# Parse options
while getopts ":d:e:hl:n:o:r:s:u" opt; do
    case $opt in
        d)
            DESCRIPTION=$OPTARG
            ;;
        e)
            EID=$OPTARG
            ;;
        h)
            usage
            ;;
        l)
            TITLE=$OPTARG
            ;;
        n)
            NAME=$OPTARG
            ;;
        o)
            DOMAIN=$OPTARG
            ;;
        r)
            AWS_REGION=$OPTARG
            ;;
        s)
            SID=$OPTARG
            ;;
        u)
            UPDATE_SEGMENT="true"
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

EID=${EID:-$SID}

# Ensure mandatory arguments have been provided
if [[ (-z "${NAME}") ]]; then
    echo -e "\nInsufficient arguments"
    usage
fi

# Set up the context
. ${BIN_DIR}/setContext.sh

# Ensure we are in the root of the account tree
if [[ ! ("product" =~ "${LOCATION}") ]]; then
    echo -e "\nWe don't appear to be in the product directory. Are we in the right place?"
    usage
fi

# Create the directories for the segment
SEGMENT_SOLUTIONS_DIR="${SOLUTIONS_DIR}/${NAME}"
SEGMENT_DEPLOYMENTS_DIR="${DEPLOYMENTS_DIR}/${NAME}"
SEGMENT_CREDENTIALS_DIR="${CREDENTIALS_DIR}/${NAME}"
mkdir -p ${SEGMENT_SOLUTIONS_DIR}
if [[ ! -d ${SEGMENT_DEPLOYMENTS_DIR} ]]; then
    mkdir -p ${SEGMENT_DEPLOYMENTS_DIR}
    echo "{}" > ${SEGMENT_DEPLOYMENTS_DIR}/config.json
fi
mkdir -p ${SEGMENT_CREDENTIALS_DIR}

# Check whether the segment profile is already in place
if [[ -f ${SEGMENT_SOLUTIONS_DIR}/segment.json ]]; then
    if [[ "${UPDATE_SEGMENT}" != "true" ]]; then
        echo -e "\nSegment profile already exists. Maybe try using update option?"
        usage
    fi
    SEGMENT_PROFILE=${SEGMENT_SOLUTIONS_DIR}/segment.json
else
    SEGMENT_PROFILE=${BIN_DIR}/templates/blueprint/segment.json
    ENVIRONMENT_TITLE=$(cat ${COMPOSITE_BLUEPRINT} | jq -r ".Environments[\"${EID}\"].Title | select(.!=null)")
    if [[ -z "${ENVIRONMENT_TITLE}" ]]; then 
        echo -e "\nEnvironment not defined in masterData.json. Was SID or EID provided?"
        usage
    fi
    TITLE=${TITLE:-$ENVIRONMENT_TITLE}
    NAME=${NAME:-$(cat ${COMPOSITE_BLUEPRINT} | jq -r ".Environments[\"${EID}\"].Name | select(.!=null)")}
    DESCRIPTION=${DESCRIPTION:-$(cat ${COMPOSITE_BLUEPRINT} | jq -r ".Environments[\"${EID}\"].Description | select(.!=null)")}
fi

# Generate the filter
FILTER="."
if [[ -n "${SID}" ]]; then FILTER="${FILTER} | .Segment.Id=\$SID"; fi
if [[ -n "${NAME}" ]]; then FILTER="${FILTER} | .Segment.Name=\$NAME"; fi
if [[ -n "${TITLE}" ]]; then FILTER="${FILTER} | .Segment.Title=\$TITLE"; fi
if [[ -n "${DESCRIPTION}" ]]; then FILTER="${FILTER} | .Segment.Description=\$DESCRIPTION"; fi
if [[ -n "${EID}" ]]; then FILTER="${FILTER} | .Segment.Environment=\$EID"; fi
if [[ -n "${AWS_REGION}" ]]; then FILTER="${FILTER} | .Product.Region=\$AWS_REGION"; fi
if [[ -n "${DOMAIN}" ]]; then FILTER="${FILTER} | .Product.Domain.Stem=\$DOMAIN"; fi
if [[ -n "${DOMAIN}" ]]; then FILTER="${FILTER} | .Product.Domain.Certificate.Id=\$PID-\$NAME"; fi

# Generate the segment profile
cat ${SEGMENT_PROFILE} | jq --indent 4 \
--arg PID "${PID}" \
--arg SID "${SID}" \
--arg NAME "${NAME}" \
--arg TITLE "${TITLE}" \
--arg DESCRIPTION "${DESCRIPTION}" \
--arg EID "${EID}" \
--arg AWS_REGION "${AWS_REGION}" \
--arg DOMAIN "${DOMAIN}" \
"${FILTER}" > ${SEGMENT_SOLUTIONS_DIR}/temp_segment.json
RESULT=$?

if [[ ${RESULT} -eq 0 ]]; then
    mv ${SEGMENT_SOLUTIONS_DIR}/temp_segment.json ${SEGMENT_SOLUTIONS_DIR}/segment.json
else
    echo -e "\nError creating segment profile" 
    exit
fi

# Cleanup any placeholder
if [[ -e "${SOLUTIONS_DIR}/.placeholder" ]]; then
    ${FILE_RM} "${SOLUTIONS_DIR}/.placeholder"
fi

# Provide an empty credentials profile for the segment
if [[ ! -f ${SEGMENT_CREDENTIALS_DIR}/credentials.json ]]; then
    echo "{}" > ${SEGMENT_CREDENTIALS_DIR}/credentials.json
fi

# Create an SSH certificate at the segment level
. ${BIN_DIR}/createSSHCertificate.sh ${SEGMENT_CREDENTIALS_DIR}

# Check that the SSH certificate has been defined in AWS
REGION=$(cat ${SEGMENT_SOLUTIONS_DIR}/segment.json | jq -r '.Product.Region | select(.!=null)')
REGION=${REGION:-$PRODUCT_REGION}
${BIN_DIR}/manageSSHCertificate.sh -i ${PID}-${NAME} -p ${SEGMENT_CREDENTIALS_DIR}/aws-ssh-crt.pem -r ${REGION}
RESULT=$?

