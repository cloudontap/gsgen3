#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

function usage() {
  echo -e "\nCreate a solution specific CloudFormation template" 
  echo -e "\nUsage: $(basename $0) -s SLICE"
  echo -e "\nwhere\n"
  echo -e "    -h shows this text"
  echo -e "(o) -s SLICE is the slice of the solution to be included in the template"
  echo -e "\nNOTES:\n"
  echo -e "1) You must be in the segment specific directory when running this script"
  echo -e ""
  exit 1
}

# Parse options
while getopts ":hs:" opt; do
  case $opt in
    h)
      usage
      ;;
    s)
      SLICE=$OPTARG
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

CURRENT_DIR="$(pwd)"
PROJECT_DIR="$(cd ../../;pwd)"
ROOT_DIR="$(cd ../../../../;pwd)"

SEGMENT="$(basename ${CURRENT_DIR})"
PID="$(basename ${PROJECT_DIR})"
OAID="$(basename ${ROOT_DIR})"

CONFIG_DIR="${ROOT_DIR}/config"
INFRA_DIR="${ROOT_DIR}/infrastructure"

ACCOUNT_DIR="${CONFIG_DIR}/${OAID}"

CF_DIR="${INFRA_DIR}/${PID}/aws/${SEGMENT}/cf"

CREDS_DIR="${INFRA_DIR}/${PID}/credentials/${SEGMENT}"

ORGANISATIONFILE="${ACCOUNT_DIR}/organisation.json"
ACCOUNTFILE="${ACCOUNT_DIR}/account.json"
PROJECTFILE="${PROJECT_DIR}/project.json"
SEGMENTFILE="${CURRENT_DIR}/segment.json"
if [[ -f "${CURRENT_DIR}/container.json" ]]; then
    SEGMENTFILE="${CURRENT_DIR}/container.json"
fi
CREDENTIALSFILE="${CREDS_DIR}/credentials.json"

if [[ -f solution.json ]]; then
	SOLUTIONFILE="solution.json"
else
	SOLUTIONFILE="../solution.json"
fi

if [[ ! -f ${SEGMENTFILE} ]]; then
    echo -e "\nNo \"${SEGMENTFILE}\" file in current directory. Are we in a segment directory? Nothing to do."
    usage
fi 

if [[ -e ${ACCOUNTFILE} ]]; then
  ACCOUNTREGION=$(grep '"Region"' ${ACCOUNTFILE} | cut -d '"' -f 4)
fi

if [[ "${ACCOUNTREGION}" == "" ]]; then
    echo -e "\nThe account region must be defined in the account configuration file."
    echo -e "Are we in the correct directory? Nothing to do."
    usage
fi

REGION=$(grep '"Region"' ${SEGMENTFILE} | cut -d '"' -f 4)
if [[ "${REGION}" == "" && -e ${SOLUTIONFILE} ]]; then
  REGION=$(grep '"Region"' ${SOLUTIONFILE} | cut -d '"' -f 4)
fi
if [[ "${REGION}" == "" && -e ${ACCOUNTFILE} ]]; then
  REGION=$(grep '"Region"' ${ACCOUNTFILE} | cut -d '"' -f 4)
fi

if [[ "${REGION}" == "" ]]; then
    echo -e "\nThe region must be defined in the segment/solution/account configuration files (in this preference order)."
    echo -e "Are we in the correct directory? Nothing to do."
    usage
fi

if [[ ! -d ${CF_DIR} ]]; then mkdir -p ${CF_DIR}; fi

TEMPLATE="createSolution.ftl"
TEMPLATEDIR="${BIN}/templates"

if [[ "${SLICE}" != "" ]]; then
	ARGS="-v slice=${SLICE}"
	OUTPUT="${CF_DIR}/soln-${SLICE}-${REGION}-template.json"
else
	ARGS=""
	OUTPUT="${CF_DIR}/solution-${REGION}-template.json"
fi

ARGS="${ARGS} -v organisation=${ORGANISATIONFILE}"
ARGS="${ARGS} -v account=${ACCOUNTFILE}"
ARGS="${ARGS} -v project=${PROJECTFILE}"
ARGS="${ARGS} -v solution=${SOLUTIONFILE}"
ARGS="${ARGS} -v segment=${SEGMENTFILE}"
ARGS="${ARGS} -v credentials=${CREDENTIALSFILE}"
ARGS="${ARGS} -v masterData=$BIN/data/masterData.json"

pushd ${CF_DIR}  > /dev/null 2>&1
STACKCOUNT=0
for f in $( ls cont*-${REGION}-stack.json seg*-${REGION}-stack.json sol*-${REGION}-stack.json 2> /dev/null); do
	PREFIX=$(echo $f | awk -F "-${REGION}-stack.json" '{print $1}' | sed 's/-//g')
	ARGS="${ARGS} -v ${PREFIX}Stack=${CF_DIR}/${f}"
	if [[ ${STACKCOUNT} > 0 ]]; then
		STACKS="${STACKS},"
	fi
	STACKS="${STACKS}\\\\\\\"${PREFIX}Stack\\\\\\\""
	STACKCOUNT=${STACKCOUNT}+1
done
popd  > /dev/null 2>&1
ARGS="${ARGS} -v stacks=[${STACKS}]"

CMD="${BIN}/gsgen.sh -t $TEMPLATE -d $TEMPLATEDIR -o $OUTPUT $ARGS"
eval $CMD
EXITSTATUS=$?

exit ${EXITSTATUS}