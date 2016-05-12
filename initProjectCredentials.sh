#!/bin/bash

function usage() {
  echo -e "\nCreate project credentials and install them in an AWS region" 
  echo -e "\nUsage: $(basename $0) -a OAID -p PID -c CONTAINER -r REGION"
  echo -e "\nwhere\n"
  echo -e "(m) -a OAID is the organisation account id e.g. \"env01\""
  echo -e "(o) -c CONTAINER is the container to be updated"
  echo -e "    -h shows this text"
  echo -e "(m) -p PID is the project id e.g. \"eticket\""
  echo -e "(o) -r REGION is the AWS region identifier for the region to be updated"
  echo -e "\nNOTES:\n"
  echo -e "1) The project credentials directory tree will be created if not present"
  echo -e "2) The script assumes we are in the OAID directory"
  echo -e "3) If ssh keys already exist, they are not recreated"
  echo -e "4) If a region is not provided, the organisation account/solution region will be used"
  echo -e "5) If a container is not provided, all containers are updated"
  echo -e ""
  exit 1
}

# Parse options
while getopts ":a:c:hp:r:" opt; do
  case $opt in
    a)
      OAID=$OPTARG
      ;;
    c)
      CONTAINER=$OPTARG
      ;;
    h)
      usage
      ;;
    p)
      PID=$OPTARG
      ;;
    r)
      REGION=$OPTARG
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

BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ROOT_DIR="$(pwd)"
ROOT="$(basename ${ROOT_DIR})"

CREDS_DIR="${ROOT_DIR}/infrastructure/${PID}/credentials"

SOLUTIONS_DIR="${ROOT_DIR}/config/${PID}/solutions"
ACCOUNT_DIR="${ROOT_DIR}/config/${OAID}"

# Region defaults to that configured in the account/solution files
if [[ "${REGION}" == "" && -e ${SOLUTIONS_DIR}/solution.json ]]; then
  REGION=$(grep '"Region"' ${SOLUTIONS_DIR}/solution.json | cut -d '"' -f 4)
fi

if [[ "${REGION}" == "" && -e ${ACCOUNT_DIR}/account.json ]]; then
  REGION=$(grep '"Region"' ${ACCOUNT_DIR}/account.json | cut -d '"' -f 4)
fi

# Ensure mandatory arguments have been provided
if [[ "${OAID}" == "" || 
      "${REGION}" == "" || 
      "${PID}"  == "" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

if [[ "${OAID}" != "${ROOT}" ]]; then
    echo -e "\nThe provided OAID (${OAID}) doesn't match the root directory (${ROOT}). Nothing to do."
    usage
fi

if [[ ! -d ${SOLUTIONS_DIR} ]]; then
    echo -e "\nProject needs to be configured before credentials are created. Nothing to do."
    usage
fi

# Set the profile if on PC to pick up the IAM credentials to use to access the credentials bucket. 
# For other platforms, assume the server has a service role providing access.
uname | grep -iE "MINGW64|Darwin|FreeBSD" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
    PROFILE="--profile ${OAID}"
fi

# Handle some MINGW peculiarities
uname | grep -i "MINGW64" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
	MINGW64="true"
fi

if [[ ! -d "${CREDS_DIR}" ]]; then
  mkdir -p ${CREDS_DIR}
  for CONTAINER in $(ls ${SOLUTIONS_DIR}); do
  	CONTAINER_NAME="$(basename ${CONTAINER})"
  	CONTAINER_DIR="${CREDS_DIR}/${CONTAINER_NAME}"
    if [[ (-d ${SOLUTIONS_DIR}/${CONTAINER_NAME}) && (! -d ${CONTAINER_DIR}) ]]; then
      mkdir ${CONTAINER_DIR}
      
      # Flag if a specific keypair is required for the container
      if [[ -f ${SOLUTIONS_DIR}/${CONTAINER_NAME}/.sshpair ]]; then
          touch ${CONTAINER_DIR}/.sshpair
      fi

      # Generate the credentials for the container 
      PASSWORD="$(curl -s 'https://www.random.org/passwords/?num=1&len=20&format=plain&rnd=new')"
      TEMPLATE="containerCredentials.ftl"
      TEMPLATEDIR="${BIN}/templates"
      OUTPUT="${CONTAINER_DIR}/credentials.json"

      ARGS="-v password=${PASSWORD}"

      CMD="${BIN}/gsgen.sh -t $TEMPLATE -d $TEMPLATEDIR -o $OUTPUT $ARGS"
      eval $CMD
    fi  
  done
fi

# Assumes KEYNAME contains the desired name for the ssh key
function check_ssh_key () { 
    if [[ (! -e aws-ssh-crt.pem) && (! -e aws-ssh-prv.pem) ]]; then
        openssl genrsa -out aws-ssh-prv.pem 2048
        openssl rsa -in aws-ssh-prv.pem -pubout > aws-ssh-crt.pem
    fi

    # Upload the keypair
    if [[ -e aws-ssh-crt.pem ]]; then
        aws ${PROFILE} --region ${REGION} ec2 describe-key-pairs --key-name ${KEYNAME} > /dev/null 2>&1
        if [[ "$?" -ne 0 ]]; then 
            CRT=$(cat aws-ssh-crt.pem | dos2unix | awk 'BEGIN {RS="\n"} /^[^-]/ {printf $1}')
            aws ${PROFILE} --region ${REGION} ec2 import-key-pair --key-name ${KEYNAME} --public-key-material $CRT
        fi
    fi
}

# Assumes CERTNAME contains the desired name for the SSL certificate
function check_certificate () {
    # Upload any SSL certificate if present for ELB/CloudFront
    for CERTIFICATE in $(ls *crt.pem 2> /dev/null | grep -v "^aws-ssh"); do
        PREFIX=$(echo $CERTIFICATE | awk -F "crt.pem" '{print $1}')
        aws ${PROFILE} --region ${REGION} iam get-server-certificate --server-certificate-name ${CERTNAME}-ssl > /dev/null 2>&1
        if [[ "$?" -ne 0 ]]; then
            if [[ "${MINGW64}" == "true" ]]; then
                MSYS_NO_PATHCONV=1 aws ${PROFILE} --region ${REGION} iam upload-server-certificate --server-certificate-name ${CERTNAME}-ssl --path "/ssl/${CERTNAME}/" --certificate-body file://${PREFIX}crt.pem --private-key file://${PREFIX}prv.pem --certificate-chain file://${PREFIX}chain.pem
            else
                aws ${PROFILE} --region ${REGION} iam upload-server-certificate --server-certificate-name ${CERTNAME}-ssl --path "/ssl/${CERTNAME}/" --certificate-body file://${PREFIX}crt.pem --private-key file://${PREFIX}prv.pem --certificate-chain file://${PREFIX}chain.pem
            fi
        fi
    
        aws ${PROFILE} --region ${REGION} iam get-server-certificate --server-certificate-name ${CERTNAME}-cloudfront > /dev/null 2>&1
        if [[ "$?" -ne 0 ]]; then
            if [[ "${MINGW64}" == "true" ]]; then
                MSYS_NO_PATHCONV=1  aws ${PROFILE} --region ${REGION} iam upload-server-certificate --server-certificate-name ${CERTNAME}-cloudfront --path "/cloudfront/${CERTNAME}/" --certificate-body file://${PREFIX}crt.pem --private-key file://${PREFIX}prv.pem --certificate-chain file://${PREFIX}chain.pem
            else
                aws ${PROFILE} --region ${REGION} iam upload-server-certificate --server-certificate-name ${CERTNAME}-cloudfront --path "/cloudfront/${CERTNAME}/" --certificate-body file://${PREFIX}crt.pem --private-key file://${PREFIX}prv.pem --certificate-chain file://${PREFIX}chain.pem
            fi
        fi
    done
}

pushd ${CREDS_DIR} > /dev/null 2>&1
if [[ "${CONTAINER}" == "" || (! -f "${CONTAINER}/.sshpair") ]]; then
    KEYNAME=${PID} check_ssh_key
    CERTNAME=${PID} check_certificate
fi

if [[ "${CONTAINER}" == ""]]; then
    CONTAINER_LIST="$(ls -d */)"
else
    CONTAINER_LIST="${CONTAINER}"
fi

# Check if container specific keypair/certificate
for CONTAINER in ${CONTAINER_LIST}; do
  	CONTAINER_NAME="$(basename ${CONTAINER})"
    pushd $CONTAINER_NAME > /dev/null 2>&1
    if [[ -f .sshpair ]]; then 
        KEYNAME=${PID}-${CONTAINER_NAME} check_ssh_key
    fi
    CERTNAME=${PID}-${CONTAINER_NAME} check_certificate
    
    popd > /dev/null 2>&1
done

