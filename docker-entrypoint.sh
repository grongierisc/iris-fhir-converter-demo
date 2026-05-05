#!/usr/bin/env bash
set -Eeo pipefail
# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# APP_HOME must be set and must point to an existing directory.
# It is defined as ENV in the Dockerfile and is baked into the image filesystem at build time.
# Overriding it at runtime (e.g. via docker-compose or a k8s pod spec) without rebuilding
# the image will break all path lookups — see README for details.
if [ -z "${APP_HOME:-}" ]; then
	printf >&2 'error: APP_HOME is not set. This variable is required and must match the path used at image build time.\n'
	exit 1
fi
if [ ! -d "$APP_HOME" ]; then
	printf >&2 'error: APP_HOME="%s" does not point to an existing directory.\n' "$APP_HOME"
	exit 1
fi

INSTALLDIR=$ISC_PACKAGE_INSTALLDIR
if [ ! -z "$ISC_DATA_DIRECTORY" ]; then
	if [ -d $ISC_DATA_DIRECTORY ] || mkdir $ISC_DATA_DIRECTORY 2>/dev/null; then
		INSTALLDIR=$ISC_DATA_DIRECTORY		
	else
		printf >&2 'Durable folder: %s does not exists, or cannot be created' "$ISC_DATA_DIRECTORY"
		exit 1
	fi
fi

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local var2="${var//_/}"
	local fileVar="${var}_FILE"
	local fileVar2="${var2}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		printf >&2 'error: both %s and %s are set (but are exclusive)\n' "$var" "$fileVar"
		exit 1
	fi
	if [ "${!var2:-}" ] && [ "${!fileVar2:-}" ]; then
		printf >&2 'error: both %s and %s are set (but are exclusive)\n' "$var2" "$fileVar2"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!var2:-}" ]; then
		val="${!var2}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	elif [ "${!fileVar2:-}" ]; then
		val="$(< "${!fileVar2}")"
	fi
	export "$var"="$val"
	export "$var2"="$val"
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
			echo "Already initialized, initdb.d files will not be processed again"
			# run init_iris.sh if it exists
			if [ -f "$APP_HOME/init_iris.sh" ]; then
				echo "Running $APP_HOME/init_iris.sh"
				"$APP_HOME/init_iris.sh"
			else
				echo "No $APP_HOME/init_iris.sh found, skipping"
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