#!/bin/bash
set -euo pipefail
# This script is used to initialize the InterSystems IRIS database with the necessary configuration files and data.

# APP_HOME is inherited from the environment (set in the Dockerfile, validated by docker-entrypoint.sh).
# The guard below also allows this script to be run standalone inside the container.
if [ -z "${APP_HOME:-}" ]; then
    printf '[ INFO ] APP_HOME is defaulted to /irisdev/app, but it is not set in the environment.\n'
fi

# First, merge the main configuration file
if [ ! -f "${APP_HOME:-/irisdev/app}/initdb.d/merge.cpf" ]; then
    printf >&2 '[ FAIL ] Configuration file %s/initdb.d/merge.cpf not found.\n' "${APP_HOME:-/irisdev/app}"
    exit 1
fi
printf '[  OK  ] Merging configuration file %s/initdb.d/merge.cpf into IRIS database...\n' "${APP_HOME:-/irisdev/app}"
iris merge iris "${APP_HOME:-/irisdev/app}/initdb.d/merge.cpf"
if [ $? -ne 0 ]; then
    printf >&2 '[ FAIL ] Error during merge of %s/initdb.d/merge.cpf\n' "${APP_HOME:-/irisdev/app}"
    exit 1
fi

# Init also the iris fhir python strategy settings if the file exists
python3 -m iris_fhir_python_strategy --namespace FHIRSERVER

# Now, run the initialization script
if [ -f "${APP_HOME:-/irisdev/app}/initdb.d/iris.script" ]; then
    printf '[  OK  ] Running initialization script %s/initdb.d/iris.script...\n' "${APP_HOME:-/irisdev/app}"
    iris session iris < "${APP_HOME:-/irisdev/app}/initdb.d/iris.script"
    if [ $? -ne 0 ]; then
        printf >&2 '[ FAIL ] Error during initialization script %s/initdb.d/iris.script\n' "${APP_HOME:-/irisdev/app}"
        exit 1
    fi
fi

# Check if iop module is available and run it if it is
if command -v iop &> /dev/null; then
    IOP_CMD="iop"
elif python3 -m iop --help &> /dev/null; then
    printf '[ WARN ] iop command not found in PATH. PATH may not be set correctly. Falling back to "python3 -m iop".\n'
    IOP_CMD="python3 -m iop"
else
    IOP_CMD=""
fi

if [ -n "$IOP_CMD" ]; then
    printf '[  OK  ] Running iop command to import additional configuration...\n'
    $IOP_CMD --init --namespace EAI
    $IOP_CMD --migrate "${APP_HOME:-/irisdev/app}/src/EAI/python/settings.py"
fi
