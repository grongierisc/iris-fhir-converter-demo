# iris-fhir-converter-demo

This is a demo project for using InterSystems IRIS for Health as a FHIR Server and FHIR Converter.

## Useful Links

- [FHIR Dashboard](http://localhost:8081/csp/fhir-management/index.html#/home)
- [EAI Production](http://localhost:8081/csp/healthshare/eai/EnsPortal.ProductionConfig.zen)

User name and password for both is `SuperUser` / `SYS`.

## Running the project

1. Make sure you have [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
2. Clone this repository.
3. Open a terminal and navigate to the root of the cloned repository.
4. Run the following command to build and start the Docker container:
    ```bash
    docker compose up --build
    ```

5. Wait for the container to start. This may take a few minutes as it needs to build the image and initialize the IRIS instance.
6. Once the container is running, you can access the FHIR Dashboard and EAI Production using the links provided above.
7. Copy HL7 v2 messages into the `input` folder. The EAI Production is configured to monitor this folder and will process any new files it finds, converting them to FHIR resources and storing them in the FHIR Server.