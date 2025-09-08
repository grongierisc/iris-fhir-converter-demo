from FhirInteraction import Interaction, Strategy, OperationHandler

import jwt

import iris

from deepdiff import DeepDiff

import json

class CustomStrategy(Strategy):
    
    def on_get_capability_statement(self, capability_statement):
        # Example : del resources Account
        capability_statement['rest'][0]['resource'] = [resource for resource in capability_statement['rest'][0]['resource'] if resource['type'] != 'Account']
        return capability_statement

class CustomInteraction(Interaction):

    def on_before_request(self, fhir_service, fhir_request, body, timeout):
        #Extract the user and roles for this request
        #so consent can be evaluated.
        self.requesting_user = fhir_request.Username
        self.requesting_roles = fhir_request.Roles
        self.scope_list = []
        self.security_list = []
        ## Uncomment the following code to extract the token from the request
        # token = fhir_request.AdditionalInfo.GetAt("USER:OAuthToken") or ""
        # if token:
        #     decoded_token = jwt.decode(token, options={"verify_signature": False})
        #     self.scope_list = decoded_token["scope"].split(" ")
        #     for scope in self.scope_list:
        #         self.security_list += self.get_security(scope)

    def get_security(self, scope):
        security = []
        try:
            permission = self.Interactions.Read("Permission", scope)._ToJSON()
            permission_dict = json.loads(permission)
            for rule in permission_dict["rule"]:
                for data in rule["data"]:
                    for sec in data["security"]:
                        security.append(sec["code"])
        except Exception as e:
            pass
        return security

    def on_after_request(self, fhir_service, fhir_request, fhir_response, body):
        #Clear the user and roles between requests.
        self.requesting_user = ""
        self.requesting_roles = ""
        self.scope_list = []
        self.security_list = []

    def post_process_read(self, fhir_object):
        #Evaluate consent based on the resource and user/roles.
        #Returning 0 indicates this resource shouldn't be displayed - a 404 Not Found
        #will be returned to the user.
        return 1
        ## Uncomment the following code to evaluate consent for the resource
        #return self.consent(fhir_object)

    def post_process_search(self, rs, resource_type):
        #Iterate through each resource in the search set and evaluate
        #consent based on the resource and user/roles.
        #Each row marked as deleted and saved will be excluded from the Bundle.
        pass
        ## Uncomment the following code to evaluate consent for the search result
        # rs._SetIterator(0)
        # while rs._Next():
        #     resource_dict = {}
        #     if resource_type == "Patient":
        #         json_str = self.Interactions.Read(resource_type, rs._Get("ResourceId"), rs._Get("VersionId"))._ToJSON()
        #         resource_dict = json.loads(json_str)
        #     if not self.consent(resource_dict):
        #         #Mark the row as deleted and save it.
        #         rs.MarkAsDeleted()
        #         rs._SaveRow()

    def consent(self,resource_dict):
        if "meta" in resource_dict:
            if "security" in resource_dict["meta"]:
                for security in resource_dict["meta"]["security"]:
                    if security["code"] in self.security_list:
                        return False
        return True

class CustomOperationHandler(OperationHandler):
    
        def add_supported_operations(self,map:dict) -> dict:
            """
            @API Enumerate the name and url of each Operation supported by this class
            @Output map : A map of operation names to their corresponding URL.
            Example:
            return map.put("restart","http://hl7.org/fhir/OperationDefinition/System-restart")
            """
            # verify the map has attribute resource 
            if not 'resource' in map:
                map['resource'] = {}
            # verify the map has attribute patient in the resource
            if not 'Patient' in map['resource']:
                map['resource']['Patient'] = []
            # add the operation to the map
            map['resource']['Patient'].append({"name": "diff" , "definition": "http://hl7.org/fhir/OperationDefinition/Patient-merge"})

            return map
    
        def process_operation(
            self,
            operation_name:str,
            operation_scope:str,
            body:dict,
            fhir_service:'iris.HS.FHIRServer.API.Service',
            fhir_request:'iris.HS.FHIRServer.API.Data.Request',
            fhir_response:'iris.HS.FHIRServer.API.Data.Response'
        ) -> 'iris.HS.FHIRServer.API.Data.Response':
            """
            @API Process an Operation request.
            @Input operation_name : The name of the Operation to process.
            @Input operation_scope : The scope of the Operation to process.
            @Input fhir_service : The FHIR Service object.
            @Input fhir_request : The FHIR Request object.
            @Input fhir_response : The FHIR Response object.
            @Output : The FHIR Response object.
            """
            if operation_name == "diff" and operation_scope == "Instance" and fhir_request.RequestMethod == "POST":
                # get the primary resource
                primary_resource = json.loads(fhir_service.interactions.Read(fhir_request.Type, fhir_request.Id)._ToJSON())
                # get the secondary resource
                secondary_resource = json.loads(fhir_request.Json._ToJSON())
                # retun the diff of the two resources
                # make use of deepdiff to get the difference between the two resources
                diff = DeepDiff(primary_resource, secondary_resource, ignore_order=True).to_json()

                # create a new %DynamicObject to store the result
                result = iris.cls('%DynamicObject')._FromJSON(diff)

                # set the result to the response
                fhir_response.Json = result
            
            return fhir_response

def set_capability_statement():
    from FhirInteraction import Utils
    utils = Utils()
    utils.update_capability_statement("/fhir/r4")
