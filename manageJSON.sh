#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi
BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM

function usage() {
  echo -e "\nManage JSON files" 
  echo -e "\nUsage: $(basename $0) -f JSON_FILTER -o JSON_OUTPUT JSON_LIST\n"
  echo -e "\nwhere\n"
  echo -e "(o) -f JSON_FILTER is the filter to use"
  echo -e "(m) -o JSON_OUTPUT is the desired output file"
  echo -e "\nDEFAULTS:\n"
  echo -e "JSON_FILTER = merge files"
  echo -e "\nNOTES:\n"
  echo -e "1. parameters can be provided in an environment variables of the same name"
  echo -e "2. Any positional arguments will be appended to the existing value"
  echo -e "   (if any) of JSON_LIST"
  echo -e ""
}

# Parse options
while getopts ":f:ho:" opt; do
  case $opt in
    f)
      JSON_FILTER=$OPTARG
      ;;
    h)
      usage
      ;;
    o)
      JSON_OUTPUT=$OPTARG
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

# Determine the file list
shift $((OPTIND-1))
JSON_ARRAY=(${JSON_LIST})
JSON_ARRAY+=("$@")

# Ensure mandatory arguments have been provided
if [[ (-z "${JSON_OUTPUT}") || ("${#JSON_ARRAY[@]}" -eq 0) ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

# Merge the files
if [[ -z "${JSON_FILTER}" ]]; then
    FILTER_INDEX=0
    JSON_FILTER=".[${FILTER_INDEX}]"
    for F in "${JSON_ARRAY[@]}"; do
        if [[ "${FILTER_INDEX}" > 0 ]]; then
            JSON_FILTER="${JSON_FILTER} * .[$FILTER_INDEX]"
        fi
        FILTER_INDEX=$(( $FILTER_INDEX + 1 ))
    done
fi
jq --indent 4 -s "${JSON_FILTER}" "${JSON_ARRAY[@]}" > ${JSON_OUTPUT} 
RESULT=$?
