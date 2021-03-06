#set parameter
param 
(
  [Parameter(Mandatory=$true,ParameterSetName='A',HelpMessage="Specify disk label to snapshot")]
  [alias("-d")]
  [ValidateNotNullOrEmpty()]
  [string]$disk,
  [Parameter(Mandatory=$true,ParameterSetName='B',HelpMessage="Specify tag assigned to disks that require snapshot")]
  [alias("-t")]
  [ValidateNotNullOrEmpty()]
  [string]$tag,
  [Parameter(Mandatory=$false,HelpMessage="Specify VSS where disk belongs")]
  [ValidateNotNullOrEmpty()]
  [alias("-v")]
  [string]$vss,
  [Parameter(Mandatory=$false,HelpMessage="Specify file where encrypted authentication is located")]
  [ValidateNotNullOrEmpty()]
  [alias("-s")]
  [string]$secret,
  [Parameter(Mandatory=$false,HelpMessage="Specify Blockbridge API end-point")]
  [ValidateNotNullOrEmpty()]
  [alias("-b","h","host")]
  [string]$bb
)

if ($PSVersionTable.PSVersion.Major -lt 7) {
  #This function sets up the Powershell environment to accept self-signed certificate
  function IgnoreCertificateValidity {
    if ("TrustAllCertsPolicy" -as [type]) {} else {
      Add-Type "using System.Net;using System.Security.Cryptography.X509Certificates;
      public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate, WebRequest request, int certificateProblem) {return true;}
      }"
      [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    }
  }
  $IgnoreCert=@{"TimeoutSec" = "30" }
  ignoreCertificateValidity
} else {
  #in PS7 we can just use an argument and its cross-platform compatible
  $IgnoreCert=@{SkipCertificateCheck = true }
}

#Authorization token was generated via steps in README.md. It can be supplied as encrypted string from -s secretfile.txt
#Secretfile.txt can be generated by running following powershell command:
#    'AuthTokenString' |  ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString |  Set-Content -Path secretfile.txt
if ( $secret -ne $null -and $secret -ne "" ) {
  $EncAuthToken = Get-Content  -Path $secret | ConvertTo-SecureString
  $AuthToken=[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((($EncAuthToken))))
}
else {
  #Manually set token and save it in the script
  $AuthToken="1/UlfS9+....."
}

#BB_ControlPlane should be set to https://[IP|Name|FQDN]/api where IP|NAME|FQDN is the ControlPlane of Blockbridge system
if ( $bb -ne $null -and $bb -ne "" ) {
  $BB_ControlPlane="https://$bb/api"
}
else {
  $BB_ControlPlane="https://dogfood/api"
}

#setup authentication header for REST request
$Header = @{"Authorization" = "Bearer $AuthToken" }

#Connectivity check
try {
  $my_result=Invoke-RestMethod @IgnoreCert -Method GET -Header $Header -ContentType "application/json" -uri $BB_ControlPlane"/status"
} catch {
  $_.Exception
  exit 1
}

#If tag is specified - find all disks that are tagged
if ( $tag -ne $null -and $tag -ne "" ) {
  #A tag was provided as a parameter. All disks containing this tag will be snapshotted serially
  $vdisk_to_snap=((Invoke-RestMethod @IgnoreCert -Method GET -Header $Header -ContentType "application/json" -uri "$BB_ControlPlane/vdisk?tags=$tag"))
  if ( $vdisk_to_snap.Count -lt 1 ) {
    write-host "No disks with Tag $tag found. Please verify -tag parameter" 
    exit 1
  }
} elseif ( $vss -ne $null -and $vss -ne "" ) {
  #Check that VSS label provided exists and retrive its ID
  $vss_list=Invoke-RestMethod @IgnoreCert -Method GET -Header $Header -ContentType "application/json" -uri "$BB_ControlPlane/vss?label=$vss"
  if ( $vss_list.Count -lt 1 ) {
    write-host "No vss with label $vss found. Please verify -vss parameter" 
    exit 1
  } else {
    $vss_id=$vss_list.id
    $vdisk_to_snap=((Invoke-RestMethod @IgnoreCert -Method GET -Header $Header -ContentType "application/json" -uri "$BB_ControlPlane/vdisk?vss_id=$vss_id&label=$disk"))  
    if ( $vdisk_to_snap.Count -lt 1 ) {
       write-host "No disk with label $disk found. Please verify -disk and -vss parameters" 
       exit 1
    }
  }
} else {
  #no vss was provided as parameter, we ensure that the disk label provided is unique and retrieve the ID of the disk.
  $vdisk_to_snap=Invoke-RestMethod @IgnoreCert -Method GET -Header $Header -ContentType "application/json" -uri "$BB_ControlPlane/vdisk?label=$disk"
  if ( $vdisk_to_snap.Count -gt 1 ) { 
    write-host "More than one disk with label $disk found. Please specify -vss" 
    write-host $vdisk_to_snap.serial
    exit 1
  } elseif ( $vdisk_to_snap.Count -lt 1 ) {
    write-host "No disk with label $disk found. Please verify -disk parameter" 
    exit 1
  }
}

#The snapshots will have a label assigned to them using "$prefix $oDate". Note this restricts the script to creating one snapshot a minute.
$prefix="Scheduled Snapshot"
$oDate = get-date -format "dd_MM_yyyy_HH_mm"
$label="$prefix $oDate"

$vdisk_to_snap|foreach {
  #setup body for api request using vdisk id and label, this will be passed via REST API to ControlPlane
  $Body = ( @{ vdisk_id=$_.serial ; label=$label } | ConvertTo-Json )
  $vdisk_label=$_.label
  $vss_id=$_.vss_id
  $vss_label=((Invoke-RestMethod @IgnoreCert -Method GET -Header $Header -ContentType "application/json" -uri $BB_ControlPlane"/vss/$vss_id").label )
  #snapshot create
  try {
      $snap_result=Invoke-RestMethod @IgnoreCert -Method POST -Header $Header -ContentType "application/json" -uri $BB_ControlPlane"/snapshot" -Body $Body
      Write-Host "Snapshot: ""$label"" for disk ""$vdisk_label"" on VSS ""$vss_label"" was created succesfully"
  } catch {
      # Dig into the exception to get the Response details.
      # Note that value__ is not a typo.
      Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
      Write-Host "StatusDescription:" $_.Exception.Response.StatusDescription
      Write-Host "ErrorDetails:" $_.ErrorDetails
      $my_error=1
  }
}
if ( $my_error -eq 1 ) { Write-Host "One or more snapshots failed to be created. Script did not complete successfully" ; exit 1}
