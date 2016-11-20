#!/bin/bash

if [[ -n "${GENERATION_DEBUG}" ]]; then set ${GENERATION_DEBUG}; fi

# Context cleanup is only done from the script that set the context
if [[ -z "${GENERATION_CONTEXT_DEFINED_LOCAL}" ]]; then return 0; fi

if [[ (-z "${GENERATION_DEBUG}") && (-n "${BASE_DIR}") ]]; then
    find ${ROOT_DIR} -name "composite_*" -delete
    find ${ROOT_DIR} -name "STATUS.txt" -delete
    find ${ROOT_DIR} -name "stripped_*" -delete
    find ${ROOT_DIR} -name "temp_*" -delete
    find ${ROOT_DIR} -name "ciphertext*" -delete
fi

