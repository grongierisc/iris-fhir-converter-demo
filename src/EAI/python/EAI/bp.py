"""Business Processes for HL7v2 → FHIR conversion pipeline."""

import os

from iop import BusinessProcess, target
import iris

from .msg import FhirRequest, FhirConverterMessage, FhirConverterResponse


class FhirConverterProcess(BusinessProcess):
    """Routes HL7v2 messages through FHIR conversion and submission."""

    converter_target = target()
    file_target = target()
    fhir_target = target()

    def on_enslib_message(self, request: 'iris.EnsLib.HL7.Message') -> None:
        """
        Handle native IRIS HL7 message.
        
        Args:
            request: Native IRIS HL7 message
        """
        try:
            fcm = FhirConverterMessage(
                input_filename=os.path.basename(request.Source),
                input_data=request.RawContent,
                input_data_type='Hl7v2',
                root_template=request.Name
            )
            self.submit_fhir_converter_message(fcm)
        except Exception as e:
            self.log_error(f'Failed to process HL7 message: {str(e)}')
            raise

    def submit_fhir_converter_message(self, request: FhirConverterMessage) -> None:
        """
        Submit message to converter, then post result to FHIR server.
        
        Args:
            request: FhirConverterMessage with HL7 data
        """
        # Normalize template names (force custom template for ADT_Z99)
        request.root_template = (
            'ADT_CUSTOM' if request.root_template == 'ADT_Z99'
            else request.root_template
        )

        # Convert HL7v2 to FHIR
        response: FhirConverterResponse = self.send_request_sync(
            self.converter_target,
            request
        )
        response.output_filename = request.input_filename.replace('.hl7', '.json')
        self.log_info(f'Converted {request.input_filename} → {response.output_filename}')

        # Drop converted payload to misc/data/fhir via dedicated operation.
        self.send_request_sync(self.file_target, response)

        # Post result to FHIR server
        fhir_request = FhirRequest(
            url='https://webgateway',
            resource='fhir/r4/',
            method='POST',
            data=response.output_data,
            headers={
                'Accept': 'application/json',
                'Content-Type': 'application/json+fhir'
            }
        )
        self.send_request_sync(self.fhir_target, fhir_request)

