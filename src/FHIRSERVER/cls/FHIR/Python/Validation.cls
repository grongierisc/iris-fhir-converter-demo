Include HS.FHIRServer

Class FHIR.Python.Validation [ Abstract ]
{

Parameter SkipIfNoProfileKEY = 0;

Parameter TerminologyServerKEY;

Parameter PatientProfileKEY = "http://hl7.org/fhir/StructureDefinition/Patient";

ClassMethod GetAllPackageSources() As %String
{
	New $NAMESPACE
	Set directoryList = ""
	Set $Namespace = "HSLIB"
	Set rs = ##class(%SQL.Statement).%ExecDirect(,"SELECT ID as namespace FROM HS_Util_Installer.ConfigItem")
	$$$ThrowSQLIfError(rs.%SQLCODE,rs.%Message)
	While (rs.%Next()) {
		Set namespace = rs.namespace
		If ##class(%SYS.Namespace).Exists(namespace){
			Set $NAMESPACE = namespace
			If $DATA(^HS.FHIRServer) {
				Set allPackages = ##class(HS.FHIRMeta.Storage.Package).GetCustomPackagesJSON("hl7.fhir.r4.core@4.0.1")
				Set iter = allPackages.%GetIterator()
				While iter.%GetNext(.key,.val) {
					Set dir = val."loaded_from"
					Continue:((val."core_version" '= "4.0.1") || (directoryList [ val."loaded_from"))
					If directoryList '= "" {
						Set directoryList = directoryList_","_dir
					}
					Else {
						Set directoryList = dir
					}
				}
			}
		}		
	}
	Quit directoryList
}

ClassMethod Validate(theResource As %DynamicObject)
{

	#dim skipIfNoProfile As %String = ..#SkipIfNoProfileKEY

	#dim errorStatus As %Status = $$$OK

	#dim noProfile As %Boolean = ('theResource.%IsDefined("meta") || 'theResource.meta.%IsDefined("profile") || (theResource.meta.profile.%Size() = 0))
	
	// skipIfNoProfile: only validate if profile is specified
	if +skipIfNoProfile && noProfile
	{
		quit
	}

	#dim igList As %String = ##class(FHIR.Python.Validation).GetAllPackageSources()
	#dim terminologyServer As %String = ..#TerminologyServerKEY
	#dim patientProfile As %String = ..#PatientProfileKEY
	#dim profileToValidateAgainst As %String = ""
	
	if noProfile 
			&& (theResource.resourceType = "Patient") 
			&& (patientProfile '= "")
	{
		set profileToValidateAgainst = patientProfile
	}	
	
	set tGatewayName = "%Java Server FHIR"
	set gw = $system.external.getGateway(tGatewayName)

	// create temporary file with the resource
	#dim file As %Stream.FileCharacter = ##class(%Stream.FileCharacter).%New()
	set file.TranslateTable = "UTF8"
	do theResource.%ToJSON(file)
	do file.Flush()

	// run FHIR validator against the file
	#dim json As %String = ""
	try
	{
		Do ##class(%Library.Device).ReDirectIO(0)
		$$$FSLog("About to call Java validator...")

		set validator = gw.new("Iris.JavaValidatorFacade")

		set json = validator.validate( igList, file.Filename, terminologyServer, profileToValidateAgainst)
	}
	catch ex
	{
		set sc = ex.AsStatus()
		$$$FHIRAddError(errorStatus, sc)
	}

	Do ##class(%Library.Device).ReDirectIO(1)
	kill file  // the file gets deleted here as we've never %Save()d it!

	$$$ThrowOnError(errorStatus)

	// assemble error status in case of any severity=error issues
	#dim operationOutcome As %DynamicObject = {}.%FromJSON(json)

	#dim iter As %Iterator.Object = operationOutcome.issue.%GetIterator()
	#dim issue As %DynamicObject
	while iter.%GetNext(.key, .issue) 
	{
		if (issue.severity = "error")
		{
			#dim oneError As %Status = $$$ERROR($$$GeneralError, issue.details.text, $$$OutcomeWithPath(400, "error", issue.code, issue.expression.%Get(0)))
			$$$FHIRAddError(errorStatus, oneError)
		}
	}

	$$$ThrowOnError(errorStatus)
}

}
