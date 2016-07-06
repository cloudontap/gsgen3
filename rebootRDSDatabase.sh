#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

trap 'find . -name STATUS.txt -exec rm {} \; ; exit $RESULT' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
TIER_DEFAULT="database"
function usage() {
  echo -e "\Reboot an RDS Database" 
  echo -e "\nUsage: $(basename $0) -t TIER -i COMPONENT -f -d DELAY\n"
  echo -e "\nwhere\n"
  echo -e "(o) -d DELAY is the interval between checking the progress of reboot"
  echo -e "(o) -f force reboot via failover"
  echo -e "    -h shows this text"
  echo -e "(m) -i COMPONENT is the name of the database component in the solution"
  echo -e "(o) -r (REBOOT ONLY) initiates but does not monitor the reboot process"
  echo -e "(o) -t TIER is the name of the database tier in the solution"
  echo -e "\nDEFAULTS:\n"
  echo -e "DELAY     = ${DELAY_DEFAULT} seconds"
  echo -e "TIER      = ${TIER_DEFAULT}"
  echo -e "\nNOTES:\n"
  echo -e ""
  exit 1
}

DELAY=${DELAY_DEFAULT}
TIER=${TIER_DEFAULT}
FORCE_FAILOVER=false
WAIT=true
# Parse options
while getopts ":d:fhi:rt:" opt; do
  case $opt in
    d)
      DELAY=$OPTARG
      ;;
    f)
      FORCE_FAILOVER=true
      ;;
    h)
      usage
      ;;
    i)
      COMPONENT=$OPTARG
      ;;
    r)
      WAIT=false
      ;;
    t)
      TIER=$OPTARG
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
if [[ "${COMPONENT}"  == "" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

CURRENT_DIR="$(pwd)"
PROJECT_DIR="$(cd ../../;pwd)"
ROOT_DIR="$(cd ../../../../;pwd)"

SEGMENT="$(basename ${CURRENT_DIR})"
PID="$(basename ${PROJECT_DIR})"
OAID="$(basename ${ROOT_DIR})"

CONFIG_DIR="${ROOT_DIR}/config"

ACCOUNT_DIR="${CONFIG_DIR}/${OAID}"

ACCOUNTFILE="${ACCOUNT_DIR}/account.json"
SEGMENTFILE="${CURRENT_DIR}/segment.json"
if [[ -f "${CURRENT_DIR}/container.json" ]]; then
    SEGMENTFILE="${CURRENT_DIR}/container.json"
fi

if [[ -f solution.json ]]; then
	SOLUTIONFILE="solution.json"
else
	SOLUTIONFILE="../solution.json"
fi

if [[ ! -f ${SEGMENTFILE} ]]; then
    echo -e "\nNo \"${SEGMENTFILE}\" file in current directory. Are we in a segment directory? Nothing to do."
    usage
fi 

REGION=$(grep '"Region"' ${SEGMENTFILE} | cut -d '"' -f 4)
if [[ -z "${REGION}" && -e ${SOLUTIONFILE} ]]; then
  REGION=$(grep '"Region"' ${SOLUTIONFILE} | cut -d '"' -f 4)
fi
if [[ -z "${REGION}" && -e ${ACCOUNTFILE} ]]; then
  REGION=$(grep '"Region"' ${ACCOUNTFILE} | cut -d '"' -f 4)
fi

if [[ "${REGION}" == "" ]]; then
    echo -e "\nThe region must be defined in the segment/solution/account configuration files (in this preference order). Nothing to do."
    usage
fi

# Set the profile if on PC to pick up the IAM credentials to use to access the credentials bucket. 
# For other platforms, assume the server has a service role providing access.
uname | grep -iE "MINGW64|Darwin|FreeBSD" > /dev/null 2>&1
if [[ "$?" -eq 0 ]]; then
    PROFILE="--profile ${OAID}"
fi

FAILOVER_OPTION="--no-force-failover"
if [[ "${FORCE_FAILOVER}" == "true" ]]; then
    FAILOVER_OPTION="--no-force-failover"
fi

DB_INSTANCE_IDENTIFIER="${PID}-${SEGMENT}-${TIER}-${COMPONENT}"

# Trigger the reboot
aws ${PROFILE} --region ${REGION} rds reboot-db-instance --db-instance-identifier ${DB_INSTANCE_IDENTIFIER}
RESULT=$?
if [ "$RESULT" -ne 0 ]; then exit; fi

if [[ "${WAIT}" == "true" ]]; then
  while true; do
	aws ${PROFILE} --region ${REGION} rds describe-db-instances --db-instance-identifier ${DB_INSTANCE_IDENTIFIER} 2>/dev/null | grep "DBInstanceStatus" > STATUS.txt
    cat STATUS.txt
    grep "available" STATUS.txt >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -eq 0 ]; then break; fi
    grep "rebooting" STATUS.txt  >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -ne 0 ]; then break; fi
    sleep $DELAY
  done
fi

