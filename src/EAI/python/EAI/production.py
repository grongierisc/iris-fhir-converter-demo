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

from iop import Production
from .bp import FhirConverterProcess
from .bo import FhirConverterOperation, FhirHttpOperation, RandomRestOperation

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

# Define processes
converter_proc = prod.process(FhirConverterProcess)

# Connect the conversion pipeline
prod.connect(converter_proc.converter_target, converter_op)
prod.connect(converter_proc.fhir_target, fhir_http_op)

