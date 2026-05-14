#!/usr/bin/env bash
# Checks that APP_HOME is in sync between Dockerfile (ARG default) and .env.example.
# Both files must exist, both must define APP_HOME, and the values must match.
# Run automatically as a pre-commit hook, or manually: bash scripts/check-app-home.sh

set -euo pipefail

DOCKERFILE="Dockerfile"
ENV_EXAMPLE=".env.example"

if [ ! -f "$DOCKERFILE" ]; then
    printf '[ FAIL ] %s not found.\n' "$DOCKERFILE" >&2
    exit 1
fi

if [ ! -f "$ENV_EXAMPLE" ]; then
    printf '[ FAIL ] %s not found.\n' "$ENV_EXAMPLE" >&2
    exit 1
fi

dockerfile_value=$(grep -E '^ARG APP_HOME=' "$DOCKERFILE" | cut -d= -f2)
env_value=$(grep -E '^APP_HOME=' "$ENV_EXAMPLE" | cut -d= -f2)

if [ -z "$dockerfile_value" ]; then
    printf '[ FAIL ] ARG APP_HOME= not found in %s.\n' "$DOCKERFILE" >&2
    exit 1
fi

if [ -z "$env_value" ]; then
    printf '[ FAIL ] APP_HOME= not found in %s.\n' "$ENV_EXAMPLE" >&2
    exit 1
fi

if [ "$dockerfile_value" != "$env_value" ]; then
    printf '[ FAIL ] APP_HOME mismatch:\n' >&2
    printf '           %-20s ARG APP_HOME=%s\n' "$DOCKERFILE" "$dockerfile_value" >&2
    printf '           %-20s APP_HOME=%s\n' "$ENV_EXAMPLE" "$env_value" >&2
    printf '\n' >&2
    printf '         If you changed APP_HOME, update both files to keep them in sync.\n' >&2
    printf '         Remember: APP_HOME cannot be changed at runtime without rebuilding the image.\n' >&2
    printf '         If you already built the image, double check what you did\n' >&2
    exit 1
fi

printf '[  OK  ] APP_HOME is in sync between %s and %s (%s)\n' "$DOCKERFILE" "$ENV_EXAMPLE" "$dockerfile_value"
exit 0
