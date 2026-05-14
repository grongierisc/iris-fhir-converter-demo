#!/usr/bin/env bash
set -Eeo pipefail
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

INSTALLDIR=$ISC_PACKAGE_INSTALLDIR
if [ ! -z "$ISC_DATA_DIRECTORY" ]; then
	if [ -d $ISC_DATA_DIRECTORY ] || mkdir $ISC_DATA_DIRECTORY 2>/dev/null; then
		INSTALLDIR=$ISC_DATA_DIRECTORY		
	else
		printf >&2 '[ FAIL ] Durable folder: %s does not exist or cannot be created\n' "$ISC_DATA_DIRECTORY"
		exit 1
	fi
fi

# Validate them all once
_preflight_check() {
    local required=(
        APP_HOME
        FHIR_SERVER_ENABLE
        FHIR_SERVER_VERSION
        FHIR_SERVER_PATH
        FHIR_SERVER_STRATEGY
    )
    for var in "${required[@]}"; do
        if [ -z "${!var:-}" ]; then
            printf >&2 '[ FAIL ] %s is not set\n' "$var"
            exit 1
        fi
        printf '[  OK  ] %s=%s\n' "$var" "${!var}"
    done
    if [ ! -d "$APP_HOME" ]; then
        printf >&2 '[ FAIL ] APP_HOME="%s" does not point to an existing directory.\n' "$APP_HOME"
        exit 1
    fi
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
#
# Resolves the value of VAR from one of four sources (first match wins):
#   1. VAR itself            (e.g. IRIS_PASSWORD)
#   2. VAR without underscores (e.g. IRISPASSWORD)           — legacy/alternate naming
#   3. VAR_FILE              (e.g. IRIS_PASSWORD_FILE)       — path to a file holding the value
#   4. VAR_FILE without underscores (e.g. IRISPASSWORD_FILE) — same, alternate naming
#   5. DEFAULT argument, or "" if not provided
#
# The _FILE variants support Docker secrets: secrets are mounted as files under
# /run/secrets/, so callers can pass the file path instead of a plaintext value.
#
# After resolution, both VAR and its underscore-free form are exported with the
# resolved value, and the _FILE variants are unset so the file path is not leaked
# to child processes.
file_env() {
	local var="$1"
	local var2="${var//_/}"         # e.g. IRIS_PASSWORD -> IRISPASSWORD
	local fileVar="${var}_FILE"     # e.g. IRIS_PASSWORD_FILE
	local fileVar2="${var2}_FILE"   # e.g. IRISPASSWORD_FILE
	local def="${2:-}"              # optional default value, empty string if omitted

	# Guard: setting both a direct value and a file reference is ambiguous — reject it
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		printf >&2 '[ FAIL ] both %s and %s are set (but are exclusive)\n' "$var" "$fileVar"
		exit 1
	fi
	if [ "${!var2:-}" ] && [ "${!fileVar2:-}" ]; then
		printf >&2 '[ FAIL ] both %s and %s are set (but are exclusive)\n' "$var2" "$fileVar2"
		exit 1
	fi

	# Resolve value: direct env var takes precedence over file, default is the fallback
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!var2:-}" ]; then
		val="${!var2}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"    # read file contents into val
	elif [ "${!fileVar2:-}" ]; then
		val="$(< "${!fileVar2}")"
	fi

	# Export both forms so consumers using either naming convention get the value
	export "$var"="$val"
	export "$var2"="$val"

	# Unset the _FILE vars so the file path is not visible to child processes
	unset "$fileVar"
	unset "$fileVar2"
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# usage: docker_process_init_files [file [file [...]]]
#    ie: docker_process_init_files /always-initdb.d/*
# process initializer files, based on file extensions and permissions
docker_process_init_files() {
	printf '\n'
	local f
	for f; do
		case "$f" in
			*.sh)
				if [ -x "$f" ]; then
					printf '%s: running %s\n' "$0" "$f"
					"$f" > /proc/1/fd/1 2>&1 
				else
					printf '%s: sourcing %s\n' "$0" "$f"
					. "$f"
				fi
				;;
			*)         printf '%s: ignoring %s\n' "$0" "$f" ;;
		esac
		printf '\n'
	done
}

# Loads various settings that are used elsewhere in the script
# This should be called before any other functions
docker_setup_env() {

	# All vars the entire pipeline depends on
	file_env 'APP_HOME'
	file_env 'FHIR_SERVER_ENABLE'
	file_env 'FHIR_SERVER_VERSION'
	file_env 'FHIR_SERVER_PATH'
	file_env 'FHIR_SERVER_STRATEGY'

	file_env 'IRIS_USERNAME' '_SYSTEM'
	file_env 'IRIS_PASSWORD'
	file_env 'IRIS_NAMESPACE' ${IRIS_DATABASE} 'USER'
	
	file_env 'IRIS_URI' "iris+emb:///$IRIS_NAMESPACE"
	
	declare -g IRIS_INIT
	if [ -f "$INSTALLDIR/iris.init" ]; then
		IRIS_INIT='true'
	else
		IRIS_INIT='false'
	fi
}

docker_enable_callin() {

iris session $ISC_PACKAGE_INSTANCENAME -U%SYS <<-'EOSESS' > /dev/null
set prop("Enabled")=1 
Do ##class(Security.Services).Modify("%Service_CallIn",.prop) 
halt
EOSESS

}

docker_setup_username() {

	if [ -z "$IRIS_PASSWORD" ]; then 
		return
	fi

iris session $ISC_PACKAGE_INSTANCENAME -U%SYS <<-EOSESS > /dev/null
check(sc)	if 'sc { do ##class(%SYSTEM.OBJ).DisplayError(sc) do ##class(%SYSTEM.Process).Terminate(, 1) }
set exists = ##class(Security.Users).Exists("$IRIS_USERNAME", .user)
if 'exists { set sc = ##class(Security.Users).Create("$IRIS_USERNAME", "%All", "$IRIS_PASSWORD") }
if exists,\$isobject(user) { set user.PasswordExternal = "$IRIS_PASSWORD", sc = user.%Save() }
do check(sc)
halt
EOSESS

}

_main() {
	# if first arg looks like a flag, assume we want to run IRIS
	if [[ $# -eq 0 ]] || [ "${1:0:1}" = '-' ]; then
		set -- iris "$@"
	fi

	if [ "$1" = 'iris' ]; then
        shift;

        ARGS=()
		# May accept multiple --after parameters, we'll execute all of them
        AFTER=()
		# Community Edition does not need ISCAgent
        ISCAgent="false"
        while [[ $# -gt 0 ]]; do
            case $1 in
                -a|--after)
                AFTER+=("$2")
                shift;shift;
                ;;
                --ISCAgent)
                ISCAgent="$2"
                shift;shift;
                ;;
                *)
                ARGS+=("$1")
                shift
                ;;
            esac
        done
        ARGS+=("--ISCAgent")
        ARGS+=("$ISCAgent")
        ARGS+=("-a")
        ARGS+=("$0 iris-after-start ${AFTER[@]@Q}")
        set -- "${ARGS[@]}"

		# to solve issues with iris-main.log, switch to the home
		pushd ~
		touch iris-main.log
        /iris-main "$@" &
		PID=$!
		popd
		trap "while kill -s SIGTERM $PID > /dev/null 2>&1;do wait $PID; done" TERM
		trap "while kill -s SIGINT $PID > /dev/null 2>&1;do wait $PID; done" INT
		wait $PID
    elif [ "$1" = 'iris-after-start' ]; then
		shift
		while [[ $# -gt 0 ]]; do
			eval "$1"
			shift
		done
		
		docker_setup_env
		
		ls "$APP_HOME/initdb.d/" > /dev/null
		
		if [ "$IRIS_INIT" != "true" ]; then

			date > "$INSTALLDIR/iris.init"

			docker_enable_callin

			docker_setup_username

			docker_process_init_files "$APP_HOME"/initdb.d/*
		else
			printf '[ INFO ] Already initialized, initdb.d files will not be processed again\n'
			# run init_iris.sh if it exists
			if [ -f "$APP_HOME/init_iris.sh" ]; then
				printf '[ INFO ] Running %s\n' "$APP_HOME/init_iris.sh"
				"$APP_HOME/init_iris.sh"
			else
				printf '[ INFO ] No %s found, skipping\n' "$APP_HOME/init_iris.sh"
			fi
		fi
	else 
	    exec "$@"
    fi

}

if ! _is_sourced; then
	_main "$@"
# else 
	# docker_setup_env
fi