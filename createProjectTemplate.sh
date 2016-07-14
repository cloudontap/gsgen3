#!/bin/bash

BIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

trap 'exit ${RESULT:-1}' EXIT SIGHUP SIGINT SIGTERM
${BIN_DIR}/createTemplate.sh -t project "$@"
RESULT=$?
