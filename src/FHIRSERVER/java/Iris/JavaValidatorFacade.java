package Iris;

import java.util.*;
import java.io.*;
import org.hl7.fhir.validation.*;
import org.hl7.fhir.validation.instance.advisor.BasePolicyAdvisorForFullValidation;
import org.hl7.fhir.r5.model.*;
import org.hl7.fhir.r5.utils.validation.constants.ReferenceValidationPolicy;
import org.hl7.fhir.r5.elementmodel.Manager;
import org.hl7.fhir.r5.formats.JsonParser;
import org.hl7.fhir.utilities.FhirPublication;

public class JavaValidatorFacade
{
    private static ValidationEngine validator;
    private static String IG;
    private static String terminologyServer;
    
    public static void init(String igList, String txServer) throws Throwable
    {
        validator = null;
        IG = null;
        terminologyServer = null;
        try 
        {
            if ((txServer != null) && (txServer.trim().length() == 0)) txServer = null;
            boolean canRunWithoutTerminologyServer = (txServer == null);

            ValidationEngine.ValidationEngineBuilder builder = new ValidationEngine.ValidationEngineBuilder().withVersion("4.0.1").withCanRunWithoutTerminologyServer(canRunWithoutTerminologyServer);
            validator = builder.fromSource("hl7.fhir.r4.core#4.0.1");

            validator.setPolicyAdvisor(new BasePolicyAdvisorForFullValidation(ReferenceValidationPolicy.IGNORE));

            if (validator == null)
            {
                throw new Exception("Unable to create validation engine");
            }
            if (txServer != null) {
                validator.setTerminologyServer(txServer, null, FhirPublication.R4, false);
            }
            

            validator.setLevel(org.hl7.fhir.validation.service.utils.ValidationLevel.ERRORS);

            if (igList != null && igList.length() > 0)
            {
                IgLoader igLoader = validator.getIgLoader();

                String[] igs = igList.split(",");
                for (int i = 0; i < igs.length; i++)
                {
                    igLoader.loadIg(validator.getIgs(), validator.getBinaries(), igs[i], true);
                }
            }
            validator.prepare();

            IG = igList;
            terminologyServer = txServer;
        }
        catch (Throwable e) 
        {
            validator = null;
            IG = null;
            terminologyServer = null;
            throw e;
        }
    }

    public static String validate(String igList, String resourceFilePath, String txServer, String profileList) throws Throwable
    {
        if ((validator == null)
            || !igList.equals(IG) 
            || (terminologyServer == null && txServer != null)
            || (terminologyServer != null && txServer == null)
            || (terminologyServer != null && !terminologyServer.equals(txServer)))
        {
            init(igList, txServer);
        }

        String[] profiles = (profileList == null || profileList.length() == 0 ? new String[] {} : profileList.split(","));

        Resource r = validator.validate(Manager.FhirFormat.JSON, new FileInputStream(resourceFilePath), Arrays.asList(profiles));

        return serialize(r);
    }

    private static String serialize(Resource r) throws Throwable
    {
        ByteArrayOutputStream os = new ByteArrayOutputStream();
        new JsonParser().setOutputStyle(org.hl7.fhir.r5.formats.IParser.OutputStyle.PRETTY).compose(os, r);
        os.close();
        return os.toString();
    }

    public static void main(String[] args) throws Throwable
    {
        String igList = args[0];
        String source = args[1];

        String txServer = null;
        if (args.length > 2) txServer = args[2];

        String profileList = null;
        if (args.length > 3) profileList = args[3];

        init(igList, txServer);

        String[] profiles = (profileList == null || profileList.length() == 0 ? new String[] {} : profileList.split(","));

        Resource r = validator.validate(Manager.FhirFormat.JSON, new FileInputStream(source), Arrays.asList(profiles));

        System.out.println();
        displayValidationResult(r);
        System.out.println();
        System.out.println(serialize(r));
        System.out.println();
    }

    private static void displayValidationResult(Resource r) throws Throwable
    {
        if (r instanceof Bundle)
        {
            System.out.println("Bundle outcome from validator.validate()");
            //for (Bundle.BundleEntryComponent e : ((Bundle) r).getEntry())
            //    ec = ec + displayOperationOutcome((OperationOutcome) e.getResource(), ((Bundle) r).getEntry().size() > 1) + ec;
        }
        else if (r == null)
        {
            System.out.println("No output from validation - nothing to validate");
        }
        else 
        {
            OperationOutcome oo = (OperationOutcome) r;
            int error = 0;
            int warn = 0;
            int info = 0;

            for (OperationOutcome.OperationOutcomeIssueComponent issue : oo.getIssue()) 
            {
                if (issue.getSeverity() == OperationOutcome.IssueSeverity.FATAL || issue.getSeverity() == OperationOutcome.IssueSeverity.ERROR)
                    error++;
                else if (issue.getSeverity() == OperationOutcome.IssueSeverity.WARNING)
                    warn++;
                else
                    info++;
            }
            System.out.println((error == 0 ? "Success" : "*FAILURE*") + ": " + Integer.toString(error) + " errors, " + Integer.toString(warn) + " warnings, " + Integer.toString(info) + " notes");
        }
    }

}