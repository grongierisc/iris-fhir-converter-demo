"""
FHIR HL7v2 Converter Production.

Orchestrates HL7v2 → FHIR conversion with the following flow:
  1. HL7v2 messages → FhirConverterProcess
  2. FhirConverterProcess → FhirConverterOperation (conversion)
  3. Converted FHIR → FhirHttpOperation (POST to FHIR server)
  4. FHIR requests → FhirMainProcess (with token validation & filtering)
  5. FhirMainProcess → FhirHttpOperation (forward to FHIR server)

The production also includes a RandomRestOperation for testing external API integration.
"""

import os

from iop import Production
from .bp import FhirConverterProcess
from .bo import (
    FhirConverterOperation,
    FhirFileDropOperation,
    FhirHttpOperation,
    RandomRestOperation,
)

# Define the production topology using IoP 4.0 API
prod = Production(
    name='EAIPKG.FoundationProduction',
    description='HL7v2 to FHIR conversion pipeline',
    testing_enabled=True,
    log_general_trace_events=False,
)

# Define operations
converter_op = prod.operation(FhirConverterOperation)

fhir_http_op = prod.operation(
    FhirHttpOperation,
    settings={
        'url': 'https://webgateway/fhir/r4',
        'credential': 'SuperUser',
    },
)

random_rest_op = prod.operation(RandomRestOperation)
file_drop_op = prod.operation(FhirFileDropOperation)

# Define processes
converter_proc = prod.process(FhirConverterProcess)

# Native ObjectScript HL7v2 inbound services
hl7_file_service = prod.service(
    'IRIS.HL7v2FileService',
    class_name='EnsLib.HL7.Service.FileService',
    settings={
        'MessageSchemaCategory': '2.8',
        'TargetConfigNames': converter_proc.name,
    },
    adapter_settings={
        'FilePath': f"{os.environ.get('APP_HOME', '/irisdev/app')}/misc/data/input/",
        'ArchivePath': f"{os.environ.get('APP_HOME', '/irisdev/app')}/misc/data/archive",
        'FileSpec': '*.hl7',
    },
)

hl7_tcp_service = prod.service(
    'IRIS.HL7v2TCPService',
    class_name='EnsLib.HL7.Service.TCPService',
    settings={
        'MessageSchemaCategory': '2.8',
        'TargetConfigNames': converter_proc.name,
    },
    adapter_settings={
        'Port': '62115',
    },
)

# Connect the conversion pipeline
prod.connect(converter_proc.converter_target, converter_op)
prod.connect(converter_proc.file_target, file_drop_op)
prod.connect(converter_proc.fhir_target, fhir_http_op)

