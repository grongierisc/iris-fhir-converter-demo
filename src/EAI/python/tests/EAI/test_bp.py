from unittest.mock import MagicMock

from bp import FhirMainProcess,FilterProcess,PermissionProcess
from msg import FilterResource,GetPermissionRequest,PermissionResponse
from obj import PermissionObj

import fixtures as fixtures

import json

class TestFhirMainProcess:

    def test_build_request_query_string_empty(self):
        # initialize the business process
        bp = FhirMainProcess()
        # create a mock request
        request = MagicMock()
        # expect request._ConstructClone(1)
        request._ConstructClone.return_value = request
        request.Request.QueryString = ""
        request.Request.RequestPath = "Patient"

        permission_obj = PermissionObj(json_path=None, query=None, resource_type=None, security=["VIP"])
        permission_obj2 = PermissionObj(json_path=None, query="_elements=name,maritalStatus", resource_type="Patient", security=[])
        permissions = [permission_obj, permission_obj2]

        # call the build_request_query_string method
        result = bp.build_request(request, permissions)
        assert result.Request.QueryString == "_security:not=VIP&_elements=name,maritalStatus"

    def test_build_request_query_string_one_element(self):
        # initialize the business process
        bp = FhirMainProcess()
        # create a mock request
        request = MagicMock()
        # expect request._ConstructClone(1)
        request._ConstructClone.return_value = request
        request.Request.QueryString = "_elements=toto"
        request.Request.RequestPath = "Patient"

        permission_obj = PermissionObj(json_path=None, query=None, resource_type=None, security=["VIP"])
        permission_obj2 = PermissionObj(json_path=None, query="_elements=name,maritalStatus", resource_type="Patient", security=[])
        permissions = [permission_obj, permission_obj2]

        # call the build_request_query_string method
        result = bp.build_request(request, permissions)
        assert result.Request.QueryString == "_security:not=VIP&_elements=name,maritalStatus"

    def test_build_request_query_string_two_elements(self):
        # initialize the business process
        bp = FhirMainProcess()
        # create a mock request
        request = MagicMock()
        # expect request._ConstructClone(1)
        request._ConstructClone.return_value = request
        request.Request.QueryString = "_elements=toto&else=toto"
        request.Request.RequestPath = "Patient"

        permission_obj = PermissionObj(json_path=None, query=None, resource_type=None, security=["VIP"])
        permission_obj2 = PermissionObj(json_path=None, query="_elements=name,maritalStatus", resource_type="Patient", security=[])
        permissions = [permission_obj, permission_obj2]

        # call the build_request_query_string method
        result = bp.build_request(request, permissions)
        assert result.Request.QueryString == "else=toto&_security:not=VIP&_elements=name,maritalStatus"

    def test_on_init(self):
        bp = FhirMainProcess()
        bp.on_init()
        assert bp.target == 'FHIR_MAIN_HTTP'

    def test_on_fhir_request(self):
        # initialize the business process
        bp = FhirMainProcess()
        bp.on_init()
        # create a mock request
        request = MagicMock()
        # mock all the methods that are called on the request
        request.Request.AdditionalInfo.GetAt.return_value = fixtures.VALIDE_TOKEN
        # create the expected response
        expected_rsp = MagicMock()
        # mock the send_request_sync method
        bp.send_request_sync = MagicMock(return_value=expected_rsp)
        # call the on_fhir_request method
        rsp = bp.on_fhir_request(request)
        assert rsp is not None

    def test_quick_stream_to_string(self):
        bp = FhirMainProcess()
        quick_stream_id = '12345'
        result = bp.quick_stream_to_string(quick_stream_id)
        assert isinstance(result, str)

    def test_string_to_quick_stream(self):
        bp = FhirMainProcess()
        json_string = '{"name": "John Doe"}'
        result = bp.string_to_quick_stream(json_string)
        assert result is not None

    def test_set_x_forwarded_headers(self):
        # initialize the business process
        bp = FhirMainProcess()
        # create a mock request
        request = MagicMock()
        request.Request.LocalBaseURL = "http://example.com:8080/api"
        request.Request.BaseURL = "http://example.com:8080/api"

        # call the set_x_forwarded_headers method
        bp.set_x_forwarded_headers(request)

        # expect request.Request.AdditionalInfo.SetAt to be called
        request.Request.AdditionalInfo.SetAt.assert_called()


class TestFilterProcess:

    def test_main_full(self):
        permission_obj = PermissionObj(json_path=None, query=None, resource_type=None, security=["VIP"])
        permission_obj2 = PermissionObj(json_path=None, query="_elements=name,maritalStatus", resource_type="Patient", security=[])
        permissions = [permission_obj, permission_obj2]
        resource_str = """{"resourceType":"Bundle","id":"05cdbeda-f658-11ee-8095-0242ac120005","type":"searchset","timestamp":"2024-04-09T10:00:40Z","total":9,"link":[{"relation":"self","url":"https://webgatewayfhir/fhir/r5/Patient?_elements=name%2CmaritalStatus"}],"entry":[{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/1","resource":{"resourceType":"Patient","name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]},"meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/2","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/3","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/4","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/5","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/6","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/7","resource":{"resourceType":"Patient","name":[{"given":["Janette"],"family":"Smith"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]},"meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/10","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["VIP"],"family":"VIP"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}},{"fullUrl":"https://webgatewayfhir/fhir/r5/Patient/11","resource":{"resourceType":"Patient","meta":{"tag":[{"system":"http://terminology.hl7.org/CodeSystem/v3-ObservationValue","code":"SUBSETTED","display":"Resource content reduced because _elements search parameter"}]},"name":[{"given":["VIP"],"family":"VIP"}],"maritalStatus":{"coding":[{"code":"M","system":"http://terminology.hl7.org/CodeSystem/v3-MaritalStatus","display":"Married"}]}},"search":{"mode":"match"}}]}"""
        request = FilterResource(permissions=permissions, resource_str=resource_str)
        filter_process = FilterProcess()
        filter_process.on_init()
        result = filter_process.main(request)


    def test_main(self):
        # initialize the filter process
        filter_process = FilterProcess()
        filter_process.on_init()
        # create a mock request
        request = MagicMock()
        request.scopes = ['user/Patient.read']
        request.resource_str = fixtures.FHIR_BUNDLE_PERMISSION
        # mock the send_request_sync method
        rsp = MagicMock()
        rsp.permissions = fixtures.PERMISSIONS
        filter_process.send_request_sync = MagicMock(return_value=rsp)
        # call the main method
        result = filter_process.main(request)
        assert isinstance(result, FilterResource)
        assert isinstance(result.resource_str, str)

    def test_apply_filter_bundle(self):
        # initialize the filter process
        filter_process = FilterProcess()
        filter_process.on_init()
        filter_process.multithread = True
        # create a mock resource string
        resource_str = fixtures.FHIR_N_BUNDLE
        # create a mock permissions list
        permissions = fixtures.PERMISSIONS
        # call the apply_filter method
        result = filter_process.apply_filter(resource_str, permissions)
        assert isinstance(result, str)
        assert 'name' not in result


    def test_apply_filter_resource(self):
        # initialize the filter process
        filter_process = FilterProcess()
        # create a mock resource string
        resource_str = fixtures.FHIR_PATIENT
        # create a mock permissions list
        permissions = fixtures.PERMISSIONS
        # call the apply_filter method
        result = json.loads(filter_process.apply_filter(resource_str, permissions))
        assert 'name' not in result

    def test_filter_resource(self):
        # initialize the filter process
        filter_process = FilterProcess()
        # create a mock resource
        resource = json.loads(fixtures.FHIR_PATIENT)
        # create a mock permissions list
        permissions = fixtures.PERMISSIONS
        # call the filter_resource method
        result = filter_process.filter_resource(resource, permissions)
        assert isinstance(result, dict)
        assert 'name' not in result

    def test_remove_fields(self):
        # initialize the filter process
        filter_process = FilterProcess()
        # create a mock resource string
        resource_str = json.loads(fixtures.FHIR_PATIENT)
        # create a mock JSON path
        json_path = "$.name"
        # call the remove_fields method
        result = filter_process.remove_fields(resource_str, json_path)
        assert isinstance(result, dict)
        assert 'name' not in result

class TestPermissionProcess:

    def test_on_init(self):
        permission_process = PermissionProcess()
        permission_process.on_init()
        assert permission_process.target == 'FHIR_PYTHON_HTTP'

    def test_get_all_permissions(self):
        # initialize the permission process
        permission_process = PermissionProcess()
        permission_process.on_init()
        # create a mock request
        request = GetPermissionRequest(['user/Patient.read', 'BOT'])
        # create a mock fhir response
        fhir_response = MagicMock()
        fhir_response.content = fixtures.FHIR_BUNDLE_PERMISSION
        fhir_response.status_code = 200
        # mock the send_request_sync method
        permission_process.send_request_sync = MagicMock(return_value=fhir_response)
        # call the get_all_permissions method
        result = permission_process.get_all_permissions(request)
        assert isinstance(result, PermissionResponse)
        assert len(result.permissions) == 3


    def test_permission_to_list_permission_obj(self):
        # initialize the permission process
        permission_process = PermissionProcess()
        # create a mock permission dictionary
        permission = json.loads(fixtures.FHIR_PERMISSION)
        # call the permission_to_list_permission_obj method
        result = permission_process.permission_to_list_permission_obj(permission)
        assert isinstance(result, list)
        assert len(result) == 1

