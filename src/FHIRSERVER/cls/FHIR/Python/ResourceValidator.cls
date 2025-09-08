Class FHIR.Python.ResourceValidator Extends HS.FHIRServer.Util.ResourceValidator
{

Parameter SkipIfNoProfileKEY = 1;

Parameter PatientProfileKEY = "http://hl7.org/fhir/StructureDefinition/Patient|4.0.0";

Method Validate(theResource As %DynamicObject)
{
	#dim skipIfNoProfile As %String = ..#SkipIfNoProfileKEY

	#dim errorStatus As %Status = $$$OK

	#dim noProfile As %Boolean = ('theResource.%IsDefined("meta") || 'theResource.meta.%IsDefined("profile") || (theResource.meta.profile.%Size() = 0))
	
	// skipIfNoProfile: only validate if profile is specified
	if +skipIfNoProfile && noProfile
	{
		quit
	}

	#dim patientProfile As %String = ..#PatientProfileKEY

	#dim profileToValidateAgainst As %List = ""
	if noProfile 
			&& (theResource.resourceType = "Patient") 
			&& (patientProfile '= "")
	{
		set profileToValidateAgainst = $lb(patientProfile)
	}
	else
	{
		set profileToValidateAgainst = $lb(theResource.meta.profile.%Get(0))
	}

	try
	{
		set json = ..ValidateAgainstProfile(theResource, profileToValidateAgainst)
	}
	catch ex
	{
		set sc = ex.AsStatus()
		$$$FHIRAddError(errorStatus, sc)
	}

	$$$ThrowOnError(errorStatus)

	if '$IsObject($get(json))
	{
		quit
	}

	// assemble error status in case of any severity=error issues
	#dim operationOutcome As %DynamicObject = json

	#dim iter As %Iterator.Object = operationOutcome.issue.%GetIterator()
	#dim issue As %DynamicObject
	while iter.%GetNext(.key, .issue) 
	{
		if (issue.severity = "error")
		{
			#dim oneError As %Status = $$$ERROR($$$GeneralError, issue.details.text, $$$OutcomeWithPath(400, "error", issue.code, ""))

			$$$FHIRAddError(errorStatus, oneError)
		}
	}
	
	$$$ThrowOnError(errorStatus)
}

/// @API
/// ValidateResource validates a FHIR Resource.  If a validation error is found, a
/// compound %Status is thrown in a StatusException.  The compound %Status starts with a
/// $$$ValidationFailure code, followed by additional %Status objects for each detected
/// validation error.
/// Inputs:
/// <li>pJsonResource           : (required) %DynamicObject representation of the FHIR resource.
/// <li>Throws					: A StatusException containing a compound %Status representing all
///                             : validation errors.
Method ValidateResource(
	pResourceObject As %DynamicObject,
	pIsInTransaction As %Boolean = 0)
{
	do ##super(pResourceObject, pIsInTransaction)
	
	// it's FHIRBundleValidator that takes care of validating Bundle entries
	//   so here we skip validation if this is the case
	
	if ($get(%inTransactionFlag, $$$NO) '= $$$YES) && (pResourceObject.resourceType '= "CapabilityStatement")
	{
		do ##class(FHIR.Python.Validation).Validate(pResourceObject)
	}
}

}
