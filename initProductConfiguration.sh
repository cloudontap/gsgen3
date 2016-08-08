#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

function usage() {
  echo -e "\nCreate the configuration directory structure for a product" 
  echo -e "\nUsage: $(basename $0) -a AID -t TITLE -p PID -r REGION -s SOLUTION -l ALPHASOLUTION"
  echo -e "\nwhere\n"
  echo -e "(m) -a AID is the tenant account id e.g. \"env01\""
  echo -e "    -h shows this text"
  echo -e "(o) -l ALPHASOLUTION is the solution template used for prototyping"
  echo -e "(m) -p PID is the product id for the product e.g. \"eticket\""
  echo -e "(o) -r REGION is the AWS region identifier where product resources will be created"
  echo -e "(o) -s SOLUTION is the target solution template for the product"
  echo -e "(m) -t TITLE is the title for the product e.g. \"Parks E-Ticketing\""
  echo -e "\nNOTES:\n"
  echo -e "1) The product directory tree will be created and populated"
  echo -e "2) If the product directory already exists, no action is performed"
  echo -e "3) The AID is only used to ensure we are in the correct directory tree"
  echo -e "4) If a region is not provided, the tenant account region will be used"
  echo -e "5) The ALPHASOLUTION template overrides the SOLUTION template in the alpha environment"
  echo -e "6) If ALPHASOLUTION is not provided, a default alpha solution is provided, which"
  echo -e "   provides a basic VPC with a publically accessible subnet" 
  echo -e ""
  exit 1
}

# Parse options
while getopts ":a:hl:p:r:s:t:" opt; do
  case $opt in
    a)
      AID=$OPTARG
      ;;
    h)
      usage
      ;;
    l)
      ALPHASOLUTION=$OPTARG
      ;;
    p)
      PID=$OPTARG
      ;;
    r)
      REGION=$OPTARG
      ;;
    s)
      SOLUTION=$OPTARG
      ;;
    t)
      PRD=$OPTARG
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
if [[ "${AID}" == "" ||
      "${PRD}"  == "" ||
      "${PID}"  == "" ]]; then
  echo -e "\nInsufficient arguments"
  usage
fi

BIN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

ROOT_DIR="$(../..;pwd)"
ROOT="$(basename ${ROOT_DIR})"
SOLUTIONS_DIR="${ROOT_DIR}/config/solutions"
PRODUCT_DIR="${SOLUTIONS_DIR}/${PID}"
ALPHA_DIR="${PRODUCT_DIR}/alpha"

if [[ "${AID}" != "${ROOT}" ]]; then
    echo -e "\nThe provided AID (${AID}) doesn't match the root directory (${ROOT}). Nothing to do."
    usage
fi

if [[ -d ${PRODUCT_DIR} ]]; then
    echo -e "\nLooks like the product directory tree already exists. Nothing to do."
    usage
fi

# Create the product
if [[ ! -e ${PRODUCT_DIR} ]]; then
    mkdir ${PRODUCT_DIR}
fi

cp -rp ${BIN}/patterns/configuration/product/* ${PRODUCT_DIR} 

# Generate the product profile
TEMPLATE="product.ftl"
TEMPLATEDIR="${BIN}/templates"
OUTPUT="${PRODUCT_DIR}/product.json"

ARGS="-v \"product=${PRD}\""
ARGS="${ARGS} -v id=${PID}"
ARGS="${ARGS} -v name=${PID}"

CMD="${BIN}/gsgen.sh -t $TEMPLATE -d $TEMPLATEDIR -o $OUTPUT $ARGS"
eval $CMD

if [[ "${REGION}" != "" ]]; then
  ARGS="-v region=${REGION}"
fi

# Generate the target solution template
SOLUTIONDIR="${BIN}/patterns/solutions/${SOLUTION}"

if [[ ("${SOLUTION}" != "") && (-d "${SOLUTIONDIR}") ]]; then

    for f in ${SOLUTIONDIR}/*; do
        NAME=$(basename $f)
        case $NAME in 
            solution.ftl)
                TEMPLATEDIR="${SOLUTIONDIR}/"
                TEMPLATE="$NAME"
                OUTPUT="${PRODUCT_DIR}/solution.json"
                
                CMD="${BIN}/gsgen.sh -t $TEMPLATE -d $TEMPLATEDIR -o $OUTPUT $ARGS"
                eval $CMD
                ;;            
            *)
                cp -p $f .
                ;;
        esac
    done
fi

# Generate the alpha solution template
SOLUTIONDIR="${BIN}/patterns/solutions/${ALPHASOLUTION}"

if [[ ("${ALPHASOLUTION}" == "") || (! -d "${SOLUTIONDIR}") ]]; then
  SOLUTIONDIR="${BIN}/patterns/solutions/alpha"
fi

for f in ${SOLUTIONDIR}/*; do
    NAME=$(basename $f)
    case $NAME in 
        solution.ftl)
            TEMPLATEDIR="${SOLUTIONDIR}/"
            TEMPLATE="$NAME"
            OUTPUT="${ALPHA_DIR}/solution.json"
            
            CMD="${BIN}/gsgen.sh -t $TEMPLATE -d $TEMPLATEDIR -o $OUTPUT $ARGS"
            eval $CMD
            ;;        
        *)
            cp -p $f ${ALPHA_DIR}
            ;;
    esac
done

# Commit the results
cd ${PRODUCT_DIR}
git add *
git commit -m "Configure product ${PID} solution"

