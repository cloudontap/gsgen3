#!/bin/bash

if [[ -n "${GSGEN_DEBUG}" ]]; then set ${GSGEN_DEBUG}; fi

if [[ (-z "${GSGEN_DEBUG}") && (-n "${ROOT_DIR}") ]]; then
    find ${ROOT_DIR} -name "aggregate_*.json" -delete
    find ${ROOT_DIR} -name "STATUS.txt" -delete
    find ${ROOT_DIR} -name "stripped_*.json" -delete
    find ${ROOT_DIR} -name "temp_*.json" -delete
    find ${ROOT_DIR} -name "ciphertext*" -delete
fi

