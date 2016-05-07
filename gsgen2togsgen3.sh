#!/bin/bash -x

function usage() {
  echo -e "\nConvert config tree used for gsgen2 to format required for gsgen3" 
  echo -e "\nUsage: $(basename $0) -a OAID -p PID"
  echo -e "\nwhere\n"
  echo -e "(m) -a OAID is the organisation account id e.g. \"env01\""
  echo -e "    -h shows this text"
  echo -e "(m) -p PID is the project id for the project e.g. \"eticket\""
  echo -e "\nNOTES:\n"
  echo -e "1) GSGEN3 expects project directories to be the immediate children of the config and infrastructure directories"
  echo -e "2) If the project directory is found as an immediate child of the OAID directory, nothing is done"
  echo -e "3) It is assumed we are in the config directory under the OAID directory when the script is run"
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

ROOT="$(basename $(cd ..;pwd))"

if [[ "${OAID}" != "${ROOT}" ]]; then
    echo -e "\nThe provided OAID (${OAID}) doesn't match the root directory (${ROOT}). Nothing to do."
    usage
fi

# if [[ -d ${PID} ]]; then
#    echo -e "\nLooks like the project directory tree already exists. Nothing to do."
#    usage
# fi

# If in a repo, save the results of the rearrangement
if [[ -d .git ]]; then
    MVCMD="git mv"
else
    MVCMD="mv"
fi

# Move each project to its own directory under config
for TREE in solutions deployments; do
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

# Move the ALM project and solution files into the alm directory
for FILE in $(ls ${OAID}/solutions/*.json  2>/dev/null); do
    ${MVCMD} ${FILE} ${OAID}/solutions/alm
done


# Commit the results if necessary 
if [[ -d .git ]]; then
    git commit -m "Convert directory structure to format required for gsgen3"
fi
