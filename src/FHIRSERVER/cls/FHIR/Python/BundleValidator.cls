Class FHIR.Python.BundleValidator Extends HS.FHIRServer.Util.BundleValidator
{

ClassMethod ValidateBundle(
	pResourceObject As %DynamicObject,
	pFHIRVersion As %String)
{
	do ##super(pResourceObject, pFHIRVersion)

	do ##class(FHIR.Python.Validation).Validate(pResourceObject)
}

}
