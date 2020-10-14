# Blockbridge PowerShell scripts

These PowerShell scripts are provided as a refence to illustate how to wrap Blockbridge API in PowerShell

  Common parameters:

  * `-s/-secret secretFile.txt`
    
       Secret file contains Authentication Token encrypted using Windows login credentials. The script must be run within the context of the same user that created the secret.
   If secret file is not used, the script must be edited and $AuthToken variable set.
 
 
  * `-h/-bb ControlPlaneHost`
  
     Specifies hostname of the Blockbridge API end-point. If not specified $BB_ControlPlane must be set in file.
  
  

## Snapshot management:

  1. Add snapshot to specified disk:
      
      * "-t/-tag" parameter to specify a tag. All disks with this tag will be snapshotted.
      
      To assign a tag to disk from CLI:`bb disk update -d [disk-label] --tag snapSchedule`
      
      * "-d/-disk" and "-v/-vss" can be provided to snapshot a specific disk.
      
  1. Delete all snapshots older than specified number of days:
  
      * "-d/-days" parameter which specifies how many days old should the checkpoint be to be deleted.
      

## Examples:

 Example 1: `powershell -command ./bb_add_snapshot.ps1 -h dogfood -s secretfile.txt -t snapSchedule`
 
 Example 2: `powershell -command ./bb_add_snapshot.ps1 -h dogfood -s secretfile.txt -d disk-1 -v service-1`
 
 Example 3: `powershell -command ./bb_add_snapshot.ps1 -t snapSchedule`
 
 Example 4: `powershell -command ./bb_remove_snapshot_older_than_days.ps1 -h dogfood -s secretfile.txt -d 30`
 
 Example 5: `powershell -command ./bb_remove_snapshot_older_than_days.ps1 -d 30`
 
## Quick Start

### Run from your Blockbridge Controlplane shell:
````
export BBUSER=account_with_storage
export SNAPUSER=snapmgmt
````

#### Create a new user in BBUSER account which is only allowed to manage snapshots and Authorization tokens
````
bb auth login --user $BBUSER
bb user create --name $SNAPUSER --grant vss.manage_snapshots
````

#### Create a persistent authorization token that inherits user rights (note the generated token, it cannot be re-displayed):
````
bb authorization create --user $SNAPUSER@$BBUSER --scope 'v:o=all v:r=manage_snapshots'
````

### Run on your Windows/Powershell Control host:

#### To store generated Authorization token in secretfile.txt execute the follow powershell command line: 
```
'AuthTokenString'|ConvertTo-SecureString -AsPlainText -Force|ConvertFrom-SecureString|Set-Content -Path secretfile.txt
```

## To avoid having to approve self-signed certificate, please follow this guide to install a properly signed SSL cert:
https://kb.blockbridge.com/guide/custom-certs/
