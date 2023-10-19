# # Input bindings are passed in via param block.
# param($Timer)

# # Get the current universal time in the default string format.
# $currentUTCtime = (Get-Date).ToUniversalTime()

# # The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
# if ($Timer.IsPastDue) {
#     Write-Host "PowerShell timer is running late!"
# }

# # Write an information log with the current time.
# Write-Host "PowerShell timer trigger function ran! TIME: $currentUTCtime"

param($Timer)

$InstrumentationKey = $ENV:AvailabilityResults_InstrumentationKey
$webtests = $ENV:webtests -split ","
$GEOLOCATION = $ENV:geolocation
$FunctionAppName = $ENV:FunctionAppName
function convert-rawHTTPResponseToObject {
    param(
        [string] $rawHTTPResponse
    )
    
    if ("$rawHTTPResponse" -match '(\d\d\d) \(((\w+|\s)+)\)') {
       
        $props = @{
            StatusCode    = $Matches[1]
            StatusMessage = $Matches[2]
        
        }
        return new-object psobject -Property $props 
    }
    else {
        write-error "Could not extract data from input"
    }  
}
$OriginalErrorActionPreference = "Stop";
foreach ($webtest in $webtests) {
    
    $webtest -match 'https?://([a-zA-Z_0-9.]+)'
    $TestName = $Matches[1]
    $Uri = $webtest 
    $Expected = 200

    $EndpointAddress = "https://dc.services.visualstudio.com/v2/track";
    $Channel = [Microsoft.ApplicationInsights.Channel.InMemoryChannel]::new();
    $Channel.EndpointAddress = $EndpointAddress;
    $TelemetryConfiguration = [Microsoft.ApplicationInsights.Extensibility.TelemetryConfiguration]::new(
        $InstrumentationKey,  
        $Channel
    );
    $TelemetryClient = [Microsoft.ApplicationInsights.TelemetryClient]::new($TelemetryConfiguration);


    $TestLocation = "$GEOLOCATION ($FunctionAppName)"; # you can use any string for this
    $OperationId = (New-Guid).ToString("N");

    $Availability = [Microsoft.ApplicationInsights.DataContracts.AvailabilityTelemetry]::new();
    $Availability.Id = $OperationId;
    $Availability.Name = $TestName;
    $Availability.RunLocation = $TestLocation;
    $Availability.Success = $False;

    $Stopwatch = [System.Diagnostics.Stopwatch]::New()
    $Stopwatch.Start();

    Try {
        # Run test
        $Response = Invoke-WebRequest -Uri $Uri  -SkipCertificateCheck;
        
    }
    Catch {
        $s = [string]$_.Exception.Message
        $Response = convert-rawHTTPResponseToObject -rawHTTPResponse  "$s"
        
    }
    Finally {
        $Success = $Response.StatusCode -eq $Expected;
        if ($Success) {
            Write-host "Testing $TestName on $Uri (Successful: The server retuned the expected statuscode $Expected)"
        }
        else {
            Write-host "Testing $TestName on $Uri (Failed: expected $Expected. Got: "  $Response.StatusCode  ")"
        }
        $Availability.Success = $Success;
        
        $ExceptionTelemetry = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new($_.Exception);
        $ExceptionTelemetry.Context.Operation.Id = $OperationId;
        $ExceptionTelemetry.Properties["TestName"] = $TestName;
        $ExceptionTelemetry.Properties["TestLocation"] = $TestLocation;
        $TelemetryClient.TrackException($ExceptionTelemetry);

        $Stopwatch.Stop();
        $Availability.Duration = $Stopwatch.Elapsed;
        $Availability.Timestamp = [DateTimeOffset]::UtcNow;
        
        # Submit Availability details to Application Insights
        $TelemetryClient.TrackAvailability($Availability);
        # call flush to ensure telemetry is sent
        $TelemetryClient.Flush();
    }

}