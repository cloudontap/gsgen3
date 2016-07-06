#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

trap 'find . -name STATUS.txt -exec rm {} \; ; exit $RESULT' EXIT SIGHUP SIGINT SIGTERM

DELAY_DEFAULT=30
TIER_DEFAULT="database"
function usage() {
  echo -e "\nSnapshot an RDS Database" 
  echo -e "\nUsage: $(basename $0) -t TIER -i COMPONENT -s SUFFIX -c -m -d DELAY -r RETAIN -a AGE\n"
  echo -e "\nwhere\n"
  echo -e "(o) -a AGE is the maximum age in days of snapshots to retain"
  echo -e "(o) -c (CREATE ONLY) initiates but does not monitor the snapshot creation process"
  echo -e "(o) -d DELAY is the interval between checking the progress of snapshot creation"
  echo -e "    -h shows this text"
  echo -e "(m) -i COMPONENT is the name of the database component in the solution"
  echo -e "(o) -m (MONITOR ONLY) monitors but does not initiate the snapshot creation process"
  echo -e "(o) -r RETAIN is the count of snapshots to retain"
  echo -e "(o) -s SUFFIX is appended to the snapshot identifier"
  echo -e "(o) -t TIER is the name of the database tier in the solution"
  echo -e "\nDEFAULTS:\n"
  echo -e "DELAY     = ${DELAY_DEFAULT} seconds"
  echo -e "TIER      = ${TIER_DEFAULT}"
  echo -e "\nNOTES:\n"
  echo -e "1. Snapshot identifer takes the form {project}-{environment}-{tier}-{component}-datetime-{suffix}"
  echo -e "2. RETAIN and AGE may be used together. If both are present, RETAIN is applied first"
  echo -e ""
  exit 1
}

DELAY=${DELAY_DEFAULT}
TIER=${TIER_DEFAULT}
CREATE=true
WAIT=true
# Parse options
while getopts ":a:cd:hi:mr:s:t:" opt; do
  case $opt in
    a)
      AGE=$OPTARG
      ;;
    c)
      WAIT=false
      ;;
    d)
      DELAY=$OPTARG
      ;;
    h)
      usage
      ;;
    i)
      COMPONENT=$OPTARG
      ;;
    m)
      CREATE=false
      ;;
    r)
      RETAIN=$OPTARG
      ;;
    s)
      SUFFIX=$OPTARG
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

DB_INSTANCE_IDENTIFIER="${PID}-${SEGMENT}-${TIER}-${COMPONENT}"
DB_SNAPSHOT_IDENTIFIER="${DB_INSTANCE_IDENTIFIER}-$(date -u +%Y-%m-%d-%H-%M-%S)"
if [[ "${SUFFIX}" != "" ]]; then
    DB_SNAPSHOT_IDENTIFIER="${DB_SNAPSHOT_IDENTIFIER}-${SUFFIX}"
fi


if [[ "${CREATE}" == "true" ]]; then
	aws ${PROFILE} --region ${REGION} rds create-db-snapshot --db-snapshot-identifier ${DB_SNAPSHOT_IDENTIFIER} --db-instance-identifier ${DB_INSTANCE_IDENTIFIER}
	RESULT=$?
	if [ "$RESULT" -ne 0 ]; then exit; fi
fi

if [[ ("${RETAIN}" != "") || ("${AGE}" != "") ]]; then
    if [[ "${RETAIN}" != "" ]]; then
        LIST=$(aws ${PROFILE} --region ${REGION} rds describe-db-snapshots --snapshot-type manual | grep DBSnapshotIdentifier | grep ${DB_INSTANCE_IDENTIFIER} | cut -d'"' -f 4 | sort | head -n -${RETAIN})
    else
        LIST=$(aws ${PROFILE} --region ${REGION} rds describe-db-snapshots --snapshot-type manual | grep DBSnapshotIdentifier | grep ${DB_INSTANCE_IDENTIFIER} | cut -d'"' -f 4 | sort)
    fi
    if [[ "${AGE}" != "" ]]; then
        BASELIST=${LIST}
        LIST=""
        LASTDATE=$(date --utc +%Y%m%d%H%M%S -d "$AGE days ago")
        for SNAPSHOT in $(echo $BASELIST); do
            DATEPLUSSUFFIX=${SNAPSHOT#"$DB_INSTANCE_IDENTIFIER-"}
            SUFFIX=${DATEPLUSSUFFIX#????-??-??-??-??-??}
            SNAPSHOTDATE=$(echo ${DATEPLUSSUFFIX%"$SUFFIX"} | tr -d "-")
#            echo LASTDATE=$LASTDATE, SNAPSHOT=$SNAPSHOTDATE
            if [[ $LASTDATE > $SNAPSHOTDATE ]]; then
                LIST="${LIST} ${SNAPSHOT}"
            fi
        done        
    fi
    if [[ "${LIST}" != "" ]]; then
        for SNAPSHOT in $(echo $LIST); do
            aws ${PROFILE} --region ${REGION} rds delete-db-snapshot --db-snapshot-identifier $SNAPSHOT
        done
    fi
fi

RESULT=1
if [[ "${WAIT}" == "true" ]]; then
  while true; do
	aws ${PROFILE} --region ${REGION} rds describe-db-snapshots --db-snapshot-identifier ${DB_SNAPSHOT_IDENTIFIER} 2>/dev/null | grep "Status" > STATUS.txt
    cat STATUS.txt
    grep "available" STATUS.txt >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -eq 0 ]; then break; fi
    grep "creating" STATUS.txt  >/dev/null 2>&1
    RESULT=$?
    if [ "$RESULT" -ne 0 ]; then break; fi
    sleep $DELAY
  done
fi

