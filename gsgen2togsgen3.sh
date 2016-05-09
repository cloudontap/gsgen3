#!/bin/bash

function usage() {
  echo -e "\nConvert config/infrastructure trees used for gsgen2 to the format required for gsgen3" 
  echo -e "\nUsage: $(basename $0) -a OAID -p PID"
  echo -e "\nwhere\n"
  echo -e "(m) -a OAID is the organisation account id e.g. \"env01\""
  echo -e "    -h shows this text"
  echo -e "(m) -p PID is the project id for the project e.g. \"eticket\""
  echo -e "\nNOTES:\n"
  echo -e "1) GSGEN3 expects project directories to be the immediate children of the config and infrastructure directories"
  echo -e "2) It is assumed we are in the config or infrastructure directory under the OAID directory when the script is run"
  echo -e ""
  exit 1
}

# Parse options
while getopts ":a:hl:p:r:s:t:" opt; do
  case $opt in
    a)
      OAID=$OPTARG
      ;;
    h)
      usage
      ;;
    p)
      PID=$OPTARG
      ;;
    \?)
      echo -e "\nInvalid option: -${OPTARG}" 
      usage
      ;;
    :)
      echo -e "\nOption -${OPTARG} requires an argument" 
      usage
      ;;
   esac
done

# Ensure mandatory arguments have been provided
if [[ "${OAID}" == "" ||
      "${PID}"  == "" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

OAID_DIR="$(basename $(cd ..;pwd))"
CURRENT_DIR="$(basename $(pwd))"

if [[ "${OAID}" != "${OAID_DIR}" ]]; then
    echo -e "\nThe provided OAID (${OAID}) doesn't match the root directory (${ROOT}). Nothing to do."
    usage
fi

# If in a repo, save the results of the rearrangement
if [[ -d .git ]]; then
    MVCMD="git mv"
else
    MVCMD="mv"
fi

# Deal with the aws/startup and aws/cf directories
# They shouldn't be treated as a project
# We also combine the account and project level cf directories for OAID
if [[ -d aws ]]; then
    mkdir -p ${OAID}/aws/
    pushd aws
    for DIRECTORY in startup cf ; do
        if [[ -d ${DIRECTORY} ]]; then
            ${MVCMD} ${DIRECTORY} ../${OAID}/aws
        fi
    done
    if [[ -d ${OAID}/cf ]]; then
        ${MVCMD} ${OAID}/cf/* ../${OAID}/aws/cf
        rm -rf ${OAID}/cf
    fi
    popd
fi

# Move each project to its own directory
# This will pick up the alm as a "project" as well
for TREE in solutions deployments credentials aws; do
    if [[ -d ${TREE} ]]; then
        pushd ${TREE}
        for PROJECT in $(ls -d */ 2>/dev/null); do
            mkdir -p ../${PROJECT}/${TREE}
            ${MVCMD} ${PROJECT}/* ../${PROJECT}/${TREE}
            rm -rf ${PROJECT}
        done
        popd
    fi
done

# Move the organisation.json and account.json files to the OAID directory
for FILE in $(ls solutions/*.json  2>/dev/null); do
    ${MVCMD} ${FILE} ${OAID}
done

# Move the project.json files to their respective project directories
for PROJECT in $(ls -d */ 2>/dev/null); do
    if [[ -f ${PROJECT}/solutions/project.json ]]; then
    ${MVCMD} ${PROJECT}/solutions/project.json ${PROJECT}/${TREE}
    fi
done

# Move the ALM solution file into the alm directory
if [[ -f ${OAID}/solutions/solution.json ]]; then
    ${MVCMD} ${OAID}/solutions/solution.json ${OAID}/solutions/alm
fi

# Final cleanup
for TREE in solutions deployments credentials aws; do
    if [[ -d ${TREE} ]]; then
        rm -rf ${TREE}
    fi
done

# Commit the results if necessary 
if [[ -d .git ]]; then
    git commit -m "Convert directory structure to format required for gsgen3"
fi
