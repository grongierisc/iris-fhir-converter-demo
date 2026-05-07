# iris-fhir-converter-demo

This is a demo project for using InterSystems IRIS for Health as a FHIR Server and FHIR Converter.

## Useful Links

- [FHIR Dashboard](http://localhost:8081/csp/fhir-management/home)
- [EAI Production](http://localhost:8081/csp/healthshare/eai/EnsPortal.ProductionConfig.zen)

User name and password for both is `SuperUser` / `SYS`.

## The APP_HOME environment variable

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