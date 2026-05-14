
# iris-fhir-converter-demo

> This is a demo project for using InterSystems IRIS for Health as a FHIR Server and FHIR Converter.

## Table of Contents

- [iris-fhir-converter-demo](#iris-fhir-converter-demo)
  - [Table of Contents](#table-of-contents)
  - [Useful Links](#useful-links)
  - [Running the project](#running-the-project)
  - [Environment variables principle and instructions](#environment-variables-principle-and-instructions)
    - [The three different mechanisms — easy to confuse](#the-three-different-mechanisms--easy-to-confuse)
    - [`env_file` vs `environment` precedence](#env_file-vs-environment-precedence)
    - [Why we don't use `env_file` in this project](#why-we-dont-use-env_file-in-this-project)
  - [The principle: validate at the boundary, trust within](#the-principle-validate-at-the-boundary-trust-within)
    - [What to do concretely](#what-to-do-concretely)
      - [Configuration: `.env` and `.env.example`](#configuration-env-and-envexample)
      - [docker-entrypoint.sh](#docker-entrypointsh)
      - [The exception: standalone scripts](#the-exception-standalone-scripts)
      - [Summary](#summary)
      - [APP\_HOME is special](#app_home-is-special)

## Useful Links

- [FHIR Dashboard](http://localhost:8081/csp/fhir-management/home)
- [EAI Production](http://localhost:8081/csp/healthshare/eai/EnsPortal.ProductionConfig.zen)

User name and password for both is `SuperUser` / `SYS`.

## Running the project

1. Make sure you have either [Docker Desktop](https://www.docker.com/products/docker-desktop/) or [Podman Desktop](https://podman-desktop.io/) installed and running.
2. Clone this repository.
3. Open a terminal and navigate to the root of the cloned repository.
4. Run the following command to build and start the Docker container:

    ```bash
    # Using Docker
    docker compose up --build
    # Or using Podman
    podman compose up --build
    ```

5. Wait for the container to start. This may take a few minutes as it needs to build the image and initialize the IRIS instance.
6. Once the container is running, you can access the FHIR Dashboard and EAI Production using the links provided above.
7. Copy HL7 v2 messages into the `input` folder. The EAI Production is configured to monitor this folder and will process any new files it finds, converting them to FHIR resources and storing them in the FHIR Server.

## Environment variables principle and instructions

### The three different mechanisms — easy to confuse

| Mechanism                 | What it does                                                         |
|---------------------------|----------------------------------------------------------------------|
| .env at compose level     | Provides values for `${VAR}` substitution in docker-compose.yml only |
| `environment:` in compose | Explicitly injects specific vars into the container                  |
| `env_file:` in compose    | Injects **all** vars from a file directly into the container         |

### `env_file` vs `environment` precedence

**`environment` wins over `env_file`**, always — regardless of order in the file.

```yaml
env_file:
  - .env              # sets FHIR_SERVER_ENABLE=1

environment:
  - FHIR_SERVER_ENABLE=0   # this wins → container sees 0
```

Full precedence chain (highest to lowest):

1. `environment:` in docker-compose.yml
2. `env_file:` in docker-compose.yml
3. `ENV` in the Dockerfile

### Why we don't use `env_file` in this project

`env_file:` injects **all** vars from a file directly into the container, which looks convenient:

```yaml
services:
  iris:
    env_file:
      - .env   # would inject APP_HOME, FHIR_SERVER_*, etc. all at once
```

However, this project doesn't use it because `.env` contains `APP_HOME=/irisdev/app`, and injecting it via `env_file` would override the `ENV APP_HOME=...` baked into the image at build time — potentially pointing scripts at a path that doesn't exist in the container. The explicit `environment:` listing gives precise control over exactly which vars enter the container.

## The principle: validate at the boundary, trust within

`docker-entrypoint.sh` **is** the boundary — it's the first process that runs, it owns the environment, and everything else is downstream. The right approach:

```text
.env
  └─► docker-compose reads it to substitute ${VAR} placeholders in docker-compose.yml. Only vars explicitly listed under `environment:` are passed to the container.
        └─► docker-entrypoint.sh  ← validate EVERYTHING here, once
              ├─► init_iris.sh    ← trust the env, no re-checks
              └─► iris.script     ← trust the env, no re-checks
```

### What to do concretely

#### Configuration: `.env` and `.env.example`

`.env` is gitignored to prevent accidental credential leaks. A committed `.env.example` serves as the reference for what variables are required:

```bash
cp .env.example .env
# then edit .env if needed
```

Never commit `.env`. Never leave `.env.example` out of date.

#### docker-entrypoint.sh

Do all pre-flight in this script, before calling anything:

- **`_preflight_check()`** — validates that all required env vars (`APP_HOME`, `FHIR_SERVER_*`) are set and non-empty, and that `APP_HOME` points to an existing directory. Fails fast with a clear `[ FAIL ]` message.
- **`docker_setup_env()`** — calls `file_env` for IRIS credentials only (`IRIS_USERNAME`, `IRIS_PASSWORD`, `IRIS_NAMESPACE`, `IRIS_URI`). These use `file_env` because they support Docker secrets (value can come from a `_FILE` var pointing to a mounted secret file).

Note: `file_env` is **not** used for `FHIR_SERVER_*` vars — those are simple required strings with no secrets use case, so plain presence validation in `_preflight_check` is sufficient.

#### The exception: standalone scripts

Use guards in the scripts themselves only if they are intended to be run standalone, outside of the entrypoint context.
In that case, they should have a lightweight guard to ensure the necessary environment is set up, but they can skip the full pre-flight logic since it's only relevant for the entrypoint.

Example: `init_iris.sh` has a comment saying it can run standalone inside the container.

#### Summary

| Script               | Guards needed?                                                    |
|----------------------|-------------------------------------------------------------------|
| docker-entrypoint.sh | Yes — full pre-flight, single source of truth                     |
| init_iris.sh         | Optional minimal guard only if it needs to support standalone use |
| iris.script          | No — always called transitively from entrypoint                   |

#### APP_HOME is special

`APP_HOME` is set once in the Dockerfile via `ENV APP_HOME=/irisdev/app`. It controls **both** where files are placed during the image build (`COPY ... "${APP_HOME}/"`) and where runtime scripts look for those files.

Because the filesystem layout is physically baked into the image at build time, `APP_HOME` **cannot be changed at runtime** (e.g. via docker-compose or a Kubernetes pod spec) without rebuilding the image — doing so would cause all scripts to look for files at a path that does not exist in the container.

The only supported way to use a different path is to rebuild the image with a build argument:

```bash
docker build --build-arg APP_HOME=/your/custom/path .
```

The entrypoint will refuse to start if `APP_HOME` is unset or points to a non-existent directory.

Having the `ARG/ENV` combo in the Dockerfile allows building a differently-rooted image variant via `--build-arg APP_HOME=/custom/path`.
This is useful when a corporate policy mandates a specific directory structure, or when building a derivative image on top of this one.
But once built, the value is frozen — it cannot be changed without a rebuild.

> **Note:** A pre-commit hook (`scripts/check-app-home.sh`) enforces that `ARG APP_HOME=` in the Dockerfile and `APP_HOME=` in `.env.example` always match. Any commit touching either file will fail if the values differ.

| Condition                             | Before      | After      |
|---------------------------------------|-------------|------------|
| Dockerfile missing                    | skip (warn) | `[ FAIL ]` |
| .env.example missing                  | skip (warn) | `[ FAIL ]` |
| `ARG APP_HOME=` missing in Dockerfile | skip (warn) | `[ FAIL ]` |
| `APP_HOME=` missing in .env.example   | skip (warn) | `[ FAIL ]` |
| Values differ                         | `[ FAIL ]`  | `[ FAIL ]` |
| All good                              | `[  OK  ]`  | `[  OK  ]` |
