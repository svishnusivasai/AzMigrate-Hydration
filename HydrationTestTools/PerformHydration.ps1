<#+--------------------------------------------------------------------------------------------------+
File         :   PerformHydration.ps1

Description  :  This script is independently capable of raising a hydration virtual machine,
                attaching customer disks to it, performing customizations and recreating a VM through
                the changed disks. The user is required to give all the necessary inputs as parameters
                when running in the beginning itself. Refer to the HelpMessages of the parameters
                wherever necessary.
+---------------------------------------------------------------------------------------------------+#>
[CmdletBinding(DefaultParametersetName='Default')] 
param
(
    [parameter(mandatory=$true, HelpMessage="Enter Your Resource Group Name...")]
    [string]$ResourceGroupName,

    [parameter(mandatory=$true, HelpMessage="Enter Your Location... Eg: centraluseuap")]
    [string]$Location,

    [parameter(mandatory=$true, HelpMessage="Enter Your Subscription Id...")]
    [string]$SubscriptionId,

    [parameter(mandatory=$true, HelpMessage="Mention the type of Operating System: Enter 0 for Windows and 1 for Linux. (Linux is set as default)")]
    [int]$OSType,

    [parameter(mandatory=$true, HelpMessage="Enter the name of the Source OS Disk")]
    [string]$OSDiskName,

    [parameter(ParameterSetName="DataDisk", mandatory=$false)]
    [switch]$AttachDataDisks,

    [parameter(ParameterSetName="DataDisk", mandatory=$false, HelpMessage="Enter the number of source data disks")]
    [int]$NoOfDataDisks=0,
    
    [parameter(ParameterSetName="DataDisk", mandatory=$false, HelpMessage="Enter the name of all the Source Data Disks")]
    [string[]]$DataDisksName,

    [parameter(mandatory=$true, HelpMessage="Enter the value of release tag")]
    [string]$Tag,

    [parameter(ParameterSetName="CustomConfigSettings", mandatory=$false)]
    [switch]$AddCustomConfigSettings,

    [parameter(ParameterSetName="CustomConfigSettings", mandatory=$false, HelpMessage="Enter 1 for Yes and 0 for No")]
    [int]$EnableDHCP,
    
    [parameter(ParameterSetName="CustomConfigSettings", mandatory=$false, HelpMessage="Enter 1 for Yes and 0 for No")]
    [int]$EnableGA,

    [parameter(mandatory=$true, HelpMessage="Enter the name of the network interface for the target Virtual Machine")]
    [string]$TargetVM_NICName,

    [parameter(mandatory=$true, HelpMessage="Enter the name of the target Virtual Machine")]
    [string]$TargetVM_VirtualMachineName,
    
    [parameter(mandatory=$true, HelpMessage="Enter the size of the target Virtual Machine")]
    [string]$TargetVM_VirtualMachineSize
)

#Random String Generation
[String]$RandomString = -join ( (48..57)  | Get-Random -Count 5 | % {[char]$_}) 

[string]$OSDiskCopy   = $OSDiskName + $RandomString

#Variables/Constants used in Creation of Virtual Network 
[string]$HydVM_AddressPrefix      = "10.255.248.0/22"
[string]$HydVM_VirtualNetworkName = "HydVM-VN" + $RandomString
[String]$HydVM_SubnetName         = "HydVM-Subnet"

#Variable used in Creation of NIC
[string]$HydVM_NICName = "HydVM-NIC" + $RandomString

#Variable used in Creation of NSG
[string]$HydVM_NSGName = "HydVM-NSG" + $RandomString

#Variables used in the Creation of Hydration Virtual Machine
[string]$HydVM_Name       = "HydVM" + $RandomString
[string]$HydVM_OSDiskName = "HydOsDisk" + $RandomString

#Variables/Constants used in Creation of Hydration Virtual Machine- Windows
[string]$HydVM_PublisherNameWindows      = "MicrosoftWindowsServer"
[string]$HydVM_OfferWindows              = "WindowsServer"
[string]$HydVM_SkusWindows               = "2016-Datacenter-smalldisk"
[string]$HydVM_VersionWindows            = "latest"
[string]$HydVM_StorageAccountTypeWindows = "Standard_LRS"

#Variables/Constants used in Creation of Hydration Virtual Machine- Linux
[string]$HydVM_PublisherNameLinux      = "Canonical"
[string]$HydVM_OfferLinux              = "ubuntu-24_04-lts"
[string]$HydVM_SkusLinux               = "server"
[string]$HydVM_VersionLinux            = "latest"
[string]$HydVM_StorageAccountTypeLinux = "Standard_LRS"

#Variables/constants used to fetch files from a github release
$HydVM_CustomScriptExtensionName = "HydrationCustomScriptExtension"
$BaseUriApi                      = "https://api.github.com/repos/svishnusivasai/AzMigrate-Hydration/releases/tags/" + $Tag
$PrefixFileUri                   = "https://github.com/svishnusivasai/AzMigrate-Hydration/releases/download/" + $Tag + "/"
$script:FileUris                 =  @();

#Variable used for the creation of RecoveryInfoFile
$script:RecoveryInfoFileContent  = "PreRecoveryExecutionBlobSasUri=abc#"
$script:RecoveryInfoFileContent += "TestFailover=True#"
$script:RecoveryInfoFileContent += "HostId=d8303bf4-d5f6-4449-81d8-218f1314eb23#"
$script:RecoveryInfoFileContent += "EnableRDP=False#"
$script:RecoveryInfoFileContent += "IsUEFI=False#"
$script:RecoveryInfoFileContent += "ActivePartitionStartingOffset=0#"
$script:RecoveryInfoFileContent += "DiskSignature=0#"

#Variables used to validate the status of operations for/on Hydration VM
[bool]$script:LoginSuccessStatus                        = $false
[bool]$script:SubscriptionSuccessStatus                 = $false
[bool]$script:HydVM_VirtualNetworkSuccessStatus         = $false
[bool]$script:HydVM_NICSuccessStatus                    = $false
[bool]$script:HydVM_NSGSuccessStatus                    = $false
[bool]$script:HydVM_VirtualMachineSuccessStatus         = $false
[bool]$script:HydVM_CopyOSDiskStatus                    = $false
[bool]$script:HydVM_AttachOSDiskSuccessStatus           = $false
[bool]$script:HydVM_AttachDataDisksSuccessStatus        = $true
[bool]$script:HydVM_FetchHydCompFromGithubSuccessStatus = $false
[bool]$script:HydVM_AttachCSESuccessStatus              = $false
[bool]$script:HydVM_VMDeletionSuccessStatus             = $false

#Variables used to validate the status of operations for/on Target VM
[bool]$script:TargetVM_VirtualMachineSuccessStatus = $false

#Variables to display the error
$script:HydErrorData    = ""
$script:HydErrorMessage = ""


<#----------------------------------------------------------------------------------------------------------------------------
Function Name                   : Login
Global Variables/Constants used : $SubsciptionId
Description                     : Requests the user to login to their Azure account and sets subscription to subscriptionId
                                  given by the user
------------------------------------------------------------------------------------------------------------------------------#>
function Login 
{
    Write-Host "Logging in..."
    $AccountDetails = Get-AzContext
    if($?)
    {
        Write-Host "Successful Login to Account: $($AccountDetails.Account)" -ForegroundColor Green     
        $script:LoginSuccessStatus = $true
    }
    else 
    {
        Write-Host "Login to your azure account in the pop-up below"
        Connect-AzAccount
       
        if($?)
        {
            Write-Host "Successful Login!" -ForegroundColor Green     
            $script:LoginSuccessStatus = $true
        }
        else 
        {
            Write-Error "Unsuccessful Login!"
        }
    }

    Set-AzContext -Subscription $SubscriptionId

    if($?)
    {
        $script:SubscriptionSuccessStatus = $true
    }
    else 
    {
        Write-Error "Invalid SubscriptionId: $SubscriptionId"
    }
}

<#----------------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_CreateVirtualNetwork
Global Variables/Constants used : $HydVM_SubnetName, $HydVM_AddressPrefix, $HydVM_VirtualNetworkName, $ResourceGroupName, $Location,
                                  $script:HydVM_VirtualNetworkSuccessStatus
Description                     : Creates the Sub Network and Virtual Network for the Hydration VM and sets the value of 
                                  $HydVM_VirtualNetworkSuccessStatus to true if the creation is successful
----------------------------------------------------------------------------------------------------------------------------------#>
function HydVM_CreateVirtualNetwork
{
    Write-Host "Creating the Virtual Network for Hydration Virtual Machine..."

    $CreatedSubnet = New-AzVirtualNetworkSubnetConfig -Name $HydVM_SubnetName -AddressPrefix $HydVM_AddressPrefix
    New-AzVirtualNetwork -Name $HydVM_VirtualNetworkName -ResourceGroupName $ResourceGroupName `
    -Location $Location -AddressPrefix $HydVM_AddressPrefix -Subnet $CreatedSubnet

    if($?)
    {
        Write-Host "Creation of Virtual Network: $HydVM_VirtualNetworkName for Hydration Virtual Machine Successful!" -ForegroundColor Green      
        $script:HydVM_VirtualNetworkSuccessStatus = $true
    }
    else 
    {
        Write-Error "Creation of Virtual Network: $HydVM_VirtualNetworkName for Hydration Virtual Machine Unsuccessful!"
    }   
}

<#---------------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_CreateNIC
Global Variables/Constants used : $HydVM_SubnetName, $HydVM_VirtualNetworkName, $ResourceGroupName, $Location, $HydVM_NICName
                                  $script:HydVM_NICSuccessStatus, 
Description                     : Creates Network Interface for the Hydration VM and sets the value of 
                                  $script:HydVM_NICSuccessStatus to true if the creation is successful
---------------------------------------------------------------------------------------------------------------------------------#>
function HydVM_CreateNIC
{
    Write-Host "Creating the Network Interface for Hydration Virtual Machine..."

    $CreatedVirtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HydVM_VirtualNetworkName
    $CreatedSubnet = Get-AzVirtualNetworkSubnetConfig -Name $HydVM_SubnetName -VirtualNetwork $CreatedVirtualNetwork
    New-AzNetworkInterface -Name $HydVM_NICName -ResourceGroupName $ResourceGroupName `
    -Location $Location -Subnet $CreatedSubnet
    if($?)
    {
        Write-Host "Creation of Network Interface: $HydVM_NICName for Hydration Virtual Machine Successful!" -ForegroundColor Green      
        $script:HydVM_NICSuccessStatus = $true
    }
    else 
    {
        Write-Error "Creation of Network Interface: $HydVM_NICName Unsuccessful!"
    }
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_CreateNSG
Global Variables/Constants used : $HydVM_SubnetName, $HydVM_VirtualNetworkName, $ResourceGroupName, $Location,$HydVM_AddressPrefix,
                                  $HydVM_NSGName, $script:HydVM_NSGSuccessStatus
Description                     : Creates Network Security Group for the Hydration VM and sets the value of 
                                  $script:HydVM_NSGSuccessStatus to true if the creation is successful
---------------------------------------------------------------------------------------------------------------------------#>
function HydVM_CreateNSG
{
    Write-Host "Creating Network Security Group for Hydration Virtual Machine..."

    $CreatedNSG = New-AzNetworkSecurityGroup -Name $HydVM_NSGName -ResourceGroupName $ResourceGroupName -Location $Location
    if($?)
    {
        $CreatedVirtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $HydVM_VirtualNetworkName
        Set-AzVirtualNetworkSubnetConfig -Name $HydVM_SubnetName -VirtualNetwork $CreatedVirtualNetwork -AddressPrefix $HydVM_AddressPrefix `
        -NetworkSecurityGroup $CreatedNSG
        Set-AzVirtualNetwork -VirtualNetwork $CreatedVirtualNetwork
        Write-Host "Creation of Network Security Group: $HydVM_NSGName for Hydration Virtual Machine Successful!" -ForegroundColor Green      
        $script:HydVM_NSGSuccessStatus = $true
    }
    else 
    {
        Write-Error "Creation of Network Security Group: $HydVM_NSGName for Hydration Virtual Machine Unsuccessful!"  
    }  
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_CreateVirtualMachineWindows
Global Variables/Constants used : $HydVM_Name, $NoOfDataDisks, $HydVM_OSDiskName, $HydVM_StorageAccountTypeWindows, 
                                  $HydVM_PublisherNameWindows, $HydVM_OfferWindows, $HydVM_SkusWindows, $HydVM_VersionWindows,
                                  $HydVM_NICName, $ResourceGroupName, $Location, $script:HydVM_VirtualMachineSuccessStatus
Description                     : Sets the OS profile, Hardware profile, Storage profile and Network profile of the 
                                  configurable virtual machine object and creates Windows Hydration Virtual Machine using it.
                                  It sets the value of $script:HydVM_VirtualMachineSuccessStatus to true if the creation of
                                  Windows Hydration VM is successful
---------------------------------------------------------------------------------------------------------------------------#>
function HydVM_CreateVirtualMachineWindows 
{
    #$Credentials=Get-Credential -Message "Enter a username and password for the virtual machine."

    #OSProfile->Prerequisites
    #These commands are used for random generation of username and password adhering to the password rules
    $Username = $HydVM_Name
    $Password = -join ( (33..126)  | Get-Random -Count 10 | % {[char]$_}) 
    $Password = "HydVM@"+$Password | ConvertTo-SecureString -Force -AsPlainText
    $Credentials = New-Object -TypeName PSCredential -ArgumentList ($Username, $Password)
    
    #HardwareProfile
    $NoOfSourceDisks = $NoOfDataDisks + 1 # +1 for source OS Disk
    $VMSize = Get-AzVMSize -Location $Location | Where {($_.NumberOfCores -gt '2') -and ($_.MemoryInMB -gt '2048') -and `
    ($_.MaxDataDiskCount -gt $NoOfSourceDisks) -and ($_.ResourceDiskSizeInMB -ne 0)}
    $VirtualMachine = New-AzVMConfig -VMName $HydVM_Name -VMSize $VMSize[0].Name

    #StorageProfile
    Set-AzVMOSDisk -Name $HydVM_OSDiskName -VM $VirtualMachine -CreateOption FromImage `
    -StorageAccountType $HydVM_StorageAccountTypeWindows -Caching ReadWrite
    
    #OSProfile->Setting the values
    Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $HydVM_Name -Credential $Credentials
    Set-AzVMSourceImage -VM $VirtualMachine -PublisherName $HydVM_PublisherNameWindows -Offer $HydVM_OfferWindows `
    -Skus $HydVM_SkusWindows -Version $HydVM_VersionWindows
    
    #Network Profile
    $NICObject = Get-AzNetworkInterface -Name $HydVM_NICName -ResourceGroupName $ResourceGroupName
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NICObject.Id
    
    Write-Host "Creating the Hydration Virtual Machine..."

    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine

    if($?)
    {
        #GetStatusofVM
        Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HydVM_Name -Status
        Write-Host "Creation of Hydration Virtual Machine: $HydVM_Name Successful!" -ForegroundColor Green      
        $script:HydVM_VirtualMachineSuccessStatus = $true
    }
    else 
    {
        Write-Error "Creation of Hydration Virtual Machine: $HydVM_Name Unsuccessful!"
    }
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_CreateVirtualMachineLinux
Global Variables/Constants used : $HydVM_Name, $NoOfDataDisks, $HydVM_OSDiskName, $HydVM_StorageAccountTypeLinux, 
                                  $HydVM_PublisherNameLinux, $HydVM_OfferLinux, $HydVM_SkusLinux, $HydVM_VersionLinux,
                                  $HydVM_NICName, $ResourceGroupName, $Location, $script:HydVM_VirtualMachineSuccessStatus
Description                     : Sets the OS profile, Hardware profile, Storage profile and Network profile of the 
                                  configurable virtual machine object and creates Linux Hydration Virtual Machine using it.
                                  It sets the value of $script:HydVM_VirtualMachineSuccessStatus to true if the creation of
                                  Linux Hydration VM is successful
---------------------------------------------------------------------------------------------------------------------------#>
function HydVM_CreateVirtualMachineLinux
{
    #$Credentials=Get-Credential -Message "Enter a username and password for the virtual machine."

    #OSProfile->Prerequisites
    #These commands are used for random generation of username and password adhering to the password rules
    $Username = $HydVM_Name
    $Password = -join ( (33..126)  | Get-Random -Count 20 | % {[char]$_}) 
    $Password = $Password+ "HydVM@" | ConvertTo-SecureString -Force -AsPlainText
    $Credentials = New-Object -TypeName PSCredential -ArgumentList ($Username, $Password)

    #HardwareProfile 
    $NoOfSourceDisks = $NoOfDataDisks + 1 # 1 for source OS Disk
    $VMSize = Get-AzVMSize -Location $Location | Where {($_.NumberOfCores -gt '2') -and ($_.MemoryInMB -gt '2048') -and `
    ($_.MaxDataDiskCount -gt $NoOfSourceDisks) -and ($_.ResourceDiskSizeInMB -ne 0)}
    $VirtualMachine = New-AzVMConfig -VMName $HydVM_Name -VMSize $TargetVM_VirtualMachineSize

    #StorageProfile
    Set-AzVMOSDisk -Name $HydVM_OSDiskName -VM $VirtualMachine -CreateOption FromImage `
    -StorageAccountType $HydVM_StorageAccountTypeLinux -Caching ReadWrite
    
    #OSProfile->Setting the values
    Set-AzVMOperatingSystem -VM $VirtualMachine -Linux -ComputerName $HydVM_Name -Credential $Credentials 
    Set-AzVMSourceImage -VM $VirtualMachine -PublisherName $HydVM_PublisherNameLinux -Offer $HydVM_OfferLinux `
    -Skus $HydVM_SkusLinux -Version $HydVM_VersionLinux

    #NetworkProfile
    $NICObject = Get-AzNetworkInterface -Name $HydVM_NICName -ResourceGroupName $ResourceGroupName
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NICObject.Id
    
    Write-Host "Creating the Hydration Virtual Machine..."
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine

    if($?)
    {
        #GetStatusofVM
        Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HydVM_Name -Status
        Write-Host "Creation of Hydration Virtual Machine: $HydVM_Name Successful!" -ForegroundColor Green
        $script:HydVM_VirtualMachineSuccessStatus = $true
    }
    else 
    {
        Write-Error "Creation of Hydration Virtual Machine: $HydVM_Name Unsuccessful!"
    }   
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_AttachSourceDisks
Global Variables/Constants used : $script:RecoveryInfoFileContent, $ResourceGroupName, $OSDiskCopy, $HydVM_Name, 
                                  $script:HydVM_AttachOSDiskSuccessStatus, $script:AttachDataDiskSuccessStatus
Description                     : Attaches source OS Disk and Data Disks to the Hydration VM and appends the DiskMap in
                                  $script:RecoveryInfoFileContent string. It sets the value of
                                  $script:HydVM_AttachOSDiskSuccessStatus to true on success attachment of OS disk to Hyd VM
                                  and $script:AttachDataDiskSuccessStatus to false if any data disk fails to get attached.
---------------------------------------------------------------------------------------------------------------------------#>
Function HydVM_CopySourceOSDisk
{
	Write-Host "Copy source OS Disk to $OSDiskCopy"
	
	$sourceDisk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskName
	$newDiskConfig = New-AzDiskConfig -SourceResourceId $sourceDisk.Id -Location $sourceDisk.Location -CreateOption Copy
	New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskCopy -Disk $newDiskConfig
    If($?)
    {
		Write-Host "Successfully copied source OS disk to $OSDiskCopy"
		$script:HydVM_CopyOSDiskStatus = $true
	}
	else
	{
		Write-Error "Couldn't copy source OS disk to $OSDiskCopy"
	}
	
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_AttachSourceDisks
Global Variables/Constants used : $script:RecoveryInfoFileContent, $ResourceGroupName, $OSDiskCopy, $HydVM_Name, 
                                  $script:HydVM_AttachOSDiskSuccessStatus, $script:AttachDataDiskSuccessStatus
Description                     : Attaches source OS Disk and Data Disks to the Hydration VM and appends the DiskMap in
                                  $script:RecoveryInfoFileContent string. It sets the value of
                                  $script:HydVM_AttachOSDiskSuccessStatus to true on success attachment of OS disk to Hyd VM
                                  and $script:AttachDataDiskSuccessStatus to false if any data disk fails to get attached.
---------------------------------------------------------------------------------------------------------------------------#>
Function HydVM_AttachSourceDisks
{
    Write-Host "Attaching Source OS Disk to the Hydration Virtual Machine..."
    
    $script:RecoveryInfoFileContent+="[DiskMap]#"
    $Disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskCopy
    $VirtualMachine = Get-AzVM -Name $HydVM_Name -ResourceGroupName $ResourceGroupName
    $VirtualMachine = Add-AzVMDataDisk -CreateOption Attach -Lun 0 -VM $VirtualMachine -ManagedDiskId $Disk.Id
    If($?)
    {
        Update-AzVM -VM $VirtualMachine -ResourceGroupName $ResourceGroupName
        if($?)
        {
            Write-Host "Attachment of Source OS disk: $OSDiskCopy to Hydration Virtual Machine Successful!" -ForegroundColor Green
            $script:RecoveryInfoFileContent+=$Disk.UniqueId+"=0#"
            $script:HydVM_AttachOSDiskSuccessStatus = $true
        }
        else 
        {
            Write-Error "Attachment of Source OS disk: $OSDiskCopy to Hydration Virtual Machine Unsuccessful!"
        }
        
    }
    else 
    {
        Write-Error "Attachment of Source OS disk: $OSDiskCopy to Hydration Virtual Machine Unsuccessful!"
    }
    If($OSType -ne 0 -and $AttachDataDisks.IsPresent)
    {
        Write-Host "Attaching Source Data Disks to the Hydration Virtual Machine..."
        for($i = 0; $i -lt $NoOfDataDisks; $i++)
        {
            $Disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DataDisksName[$i]
            $VirtualMachine = Get-AzVM -Name $HydVM_Name -ResourceGroupName $ResourceGroupName
            $VirtualMachine = Add-AzVMDataDisk -CreateOption Attach -Lun ($i+1) -VM $VirtualMachine -ManagedDiskId $Disk.Id
            If(!$?)
            {
                Write-Error "Attachment of Source Data disk:$DataDisksName[$i] to Hydration Virtual Machine Unsuccessful!"
                $script:AttachDataDiskSuccessStatus = $false
            }
            Update-AzVM -VM $VirtualMachine -ResourceGroupName $ResourceGroupName
            If(!$?)
            {
                Write-Error "Attachment of Source Data disk:$DataDisksName[$i] to Hydration Virtual Machine Unsuccessful!"
                $script:AttachDataDiskSuccessStatus = $false
            }
            $script:RecoveryInfoFileContent+=$Disk.UniqueId+"="+($i+1)+"#"
            #$DiskMap.Add($Disk.Id, ($i+1))   
        } 
    } 
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_FetchHydComponentsFromGithub
Global Variables/Constants used : $Tag, $BaseUriApi, $AllMandatoryFilesPresent_Windows, $AllMandatoryFilesPresent_Linux,
                                  $script:FileUris, $script:HydVM_FetchHydCompFromGithubSuccessStatus
Description                     : Fetches all the files from the Github Branch provided by user and validates the presence of 
                                  mandatory files: AzureRecoveryTools.zip, StartupScript.ps1 and StartupScript.sh for Windows 
                                  Hydration VM and Linux Hydration VM respectively (The config file gets created in the 
                                  StartupScript). It adds File Uris in $script:FileUri array to be used by 
                                  HydVM_AttachCustomScriptExtensionWindows and HydVM_AttachCustomScriptExtensionLinux.
---------------------------------------------------------------------------------------------------------------------------#>
function HydVM_FetchHydComponentsFromGithub
{
    Write-Host "Fetching Hydration Components from Github Release with tag:$Tag..."
    #Fetching
    $Information = Invoke-WebRequest -Uri $BaseUriApi -UseBasicParsing
    if($null -eq $Information)
    {
        Write-Error "Invalid Github release Tag!"
    }
    else
    {   
		$Objects = $Information.Content | ConvertFrom-Json

		# Extract the asset URLs and create the FileUris
		$Assets = $Objects.assets
		[string[]]$FileNames = $Assets.name

		<#Validation
		$CheckMandatoryFiles
		Index 0 : AzureRecoveryTools.zip
		Index 1 : StartupScript.ps1 (Windows)
		Index 2 : StartupScript.sh (Linux)
		Index 3 : azurerecovery-70b5c7c0-ad71-4cc6-afbe-1bab5226da25.conf#>
		$CheckMandatoryFiles = @($false, $false, $false, $false)

		for ($i = 0; $i -lt $FileNames.Length; $i++) {
			if ($FileNames[$i] -eq "AzureRecoveryTools.zip") {
				$CheckMandatoryFiles[$i] = $true
			}
			if ($FileNames[$i] -eq "StartupScript.ps1") {
				$CheckMandatoryFiles[$i] = $true
			}
			if ($FileNames[$i] -eq "StartupScript.sh") {
				$CheckMandatoryFiles[$i] = $true
			}
			if ($FileNames[$i] -eq "azurerecovery-70b5c7c0-ad71-4cc6-afbe-1bab5226da25.conf") {
				$CheckMandatoryFiles[$i] = $true
			}
		}

        $AllMandatoryFilesPresent_Windows = $true
        $AllMandatoryFilesPresent_Linux = $true
        if(-not $CheckMandatoryFiles[0])
        {
            Write-Error "Mandatory component: AzureRecoveryTools.zip missing from Github Release with the tag:'$Tag'."
            $AllMandatoryFilesPresent_Windows=$false
            $AllMandatoryFilesPresent_Linux=$false
        }
        if(-not $CheckMandatoryFiles[1] -and $OSType -eq 0)
        {
            Write-Error "Mandatory component: StartupScript.ps1 missing from Github Release with the tag:'$Tag'."
            $AllMandatoryFilesPresent_Windows=$false
        }
        if(-not $CheckMandatoryFiles[2] -and $OSType -ne 0)
        {
            Write-Error "Mandatory component: StartupScript.sh missing from Github Release with the tag:'$Tag'."
            $AllMandatoryFilesPresent_Linux=$false
        }
        
        <#Adding File Uris in $script:FileUri array to be used by HydVM_AttachCustomScriptExtensionWindows 
        and HydVM_AttachCustomScriptExtensionLinux#>
        if($OSType -eq 0 -and $AllMandatoryFilesPresent_Windows)
        { 
            for($i=0;$i -lt $FileNames.Length;$i++)
            {
                $FileUri=$PrefixFileUri+$FileNames[$i]
                $script:FileUris+=$FileUri            
            }
            Write-Host "Fetching Hydration Components from Github Release with the tag:'$Tag' Successful! " -ForegroundColor Green
            $script:HydVM_FetchHydCompFromGithubSuccessStatus = $true
        }
        elseif ($OSType -ne 0 -and $AllMandatoryFilesPresent_Linux) 
        {
            for($i=0;$i -lt $FileNames.Length;$i++)
            {
                $FileUri=$PrefixFileUri+$FileNames[$i]
                $script:FileUris+=$FileUri
            }
            Write-Host "Fetching Hydration Components from Github Release with the tag:'$Tag' Successful! " -ForegroundColor Green
            $script:HydVM_FetchHydCompFromGithubSuccessStatus = $true  
        }
        else 
        {
            Write-Error "Fetching Files from Github Release with the tag:'$Tag' Unsuccessful!"
        }
    }    
}

<#------------------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_AttachCustomScriptExtensionWindows
Global Variables/Constants used : $ResourceGroupName, $HydVM_Name, $Location, $script:FileUris, $script:HydVM_AttachCSESuccessStatus,
                                  $HydVM_CustomScriptExtensionName, $AddCustomConfigSettings, $EnableDHCP, $EnableGA
Description                     : Attaches Custom Script Extension to the Windows Hydration Virtual Machine
--------------------------------------------------------------------------------------------------------------------------------------#>
function HydVM_AttachCustomScriptExtensionWindows
{
    Write-Host "Attaching custom Script Extension to the Hydration Virtual Machine..."
    
    if(-not $AddCustomConfigSettings)
    {
        Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -VMName $HydVM_Name -Location $Location -FileUri $script:FileUris `
        -Run "StartupScript.ps1 70b5c7c0-ad71-4cc6-afbe-1bab5226da25 migration -HydrationConfigSettings EnableWindowsGAInstallation:true -RecoveryInfofileContent $script:RecoveryInfoFileContent" `
        -Name $HydVM_CustomScriptExtensionName  
        if($?)
        {
            Write-Host "Attachment of custom Script Extension Successful!" -ForegroundColor Green
            $HydErrCodeDetails = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $HydVM_Name -CommandId "RunPowerShellScript"  -ScriptPath ".\GetErrorCode.ps1" | Out-String -Stream

            $HydErrCode = $HydErrCodeDetails[7]
            $script:HydErrorData = $HydErrCodeDetails[8]
            $script:HydErrorMessage = $HydErrCodeDetails[9]
            
            Write-Host $script:HydErrorData
            Write-Host $script:HydErrorMessage

            [xml]$ErrorCodesXml = Get-Content -Path ".\ErrorCodes.xml"
            foreach($ErrCode in $ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode.Number)
            { 
                if($ErrCode -eq $HydErrCode)
                {
                    Write-Host "Description: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Description)"
                    Write-Host "Category: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Category)"
                    Write-Host "Possible Cause: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].PossibleCause)"
                    Write-Host "Recommended Action: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].RecommendedAction)"
                }
            }
            #SoftErrors
            if($HydErrCode -ne 5 -and $HydErrCode -ne 16 -and $HydErrCode -ne 21 -and $HydErrCode -ne 22 -and $HydErrCode -ne 23 -and $HydErrCode -ne 24 -and $HydErrCode -ne 27) 
            {
                $script:HydVM_AttachCSESuccessStatus = $true
            }
            #HardErrors
            else 
            {
                Write-Error "Terminating the process due to Hard Errors"
            }  
        }
        else 
        {
            Write-Error "Attachment of custom Script Extension Unsuccessful! Suggestion: Use main branch and re-run the script"
        }
    }
    else 
    {
        $CustomConfigSettings="";
        if($EnableDHCP -eq 1)
        {
            $CustomConfigSettings+="EnableDHCP:true,"
        }
        else 
        {
            $CustomConfigSettings+="EnableDHCP:false,"
        }
        if($EnableGA -eq 1)
        {
            $CustomConfigSettings+="EnableGA:true"
        }
        else 
        {
            $CustomConfigSettings+="EnableGA:false"
        }

        Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -VMName $HydVM_Name -Location $Location -FileUri $script:FileUris `
        -Run "StartupScript.ps1 70b5c7c0-ad71-4cc6-afbe-1bab5226da25 migration -HydrationConfigSettings EnableWindowsGAInstallation:true -RecoveryInfofileContent $script:RecoveryInfoFileContent -CustomConfigSettings $CustomConfigSettings" `
        -Name $HydVM_CustomScriptExtensionName  

        if($?)
        {
            Write-Host "Attachment of custom Script Extension Successful!" -ForegroundColor Green
            $HydErrCodeDetails = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $HydVM_Name -CommandId "RunPowerShellScript"  -ScriptPath ".\GetErrorCode.ps1" | Out-String -Stream

            $HydErrCode = $HydErrCodeDetails[7]
            $script:HydErrorData = $HydErrCodeDetails[8]
            $script:HydErrorMessage = $HydErrCodeDetails[9]
            
            Write-Host $script:HydErrorData
            Write-Host $script:HydErrorMessage

            [xml]$ErrorCodesXml = Get-Content -Path ".\ErrorCodes.xml"
            foreach($ErrCode in $ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode.Number)
            { 
                if($ErrCode -eq $HydErrCode)
                {
                    Write-Host "Description: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Description)"
                    Write-Host "Category: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Category)"
                    Write-Host "Possible Cause: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].PossibleCause)"
                    Write-Host "Recommended Action: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].RecommendedAction)"
                }
            }
            #SoftErrors
            if($HydErrCode -ne 5 -and $HydErrCode -ne 16 -and $HydErrCode -ne 21 -and $HydErrCode -ne 22 -and $HydErrCode -ne 23 -and $HydErrCode -ne 24 -and $HydErrCode -ne 27) 
            {
                $script:HydVM_AttachCSESuccessStatus = $true
            }
            #HardErrors
            else 
            {
                Write-Error "Terminating the process due to Hard Errors"
            }
        }
        else 
        {
            Write-Error "Attachment of custom Script Extension Unsuccessful!"
        }
    }   
}

<#------------------------------------------------------------------------------------------------------------------------------------
Function Name                   : HydVM_AttachCustomScriptExtensionLinux
Global Variables/Constants used : $ResourceGroupName, $HydVM_Name, $Location, $script:FileUris, $script:HydVM_AttachCSESuccessStatus,
                                  $HydVM_CustomScriptExtensionName, $AddCustomConfigSettings, $EnableDHCP, $EnableGA
Description                     : Attaches Custom Script Extension to the Linux Hydration Virtual Machine
--------------------------------------------------------------------------------------------------------------------------------------#>
function HydVM_AttachCustomScriptExtensionLinux
{
    Write-Host "Attaching Custom Script Extension to the Hydration Virtual Machine..." 

    if(-not $AddCustomConfigSettings)
    {
		$Settings = @{"fileUris" = $script:FileUris; "commandToExecute" = "bash StartupScript.sh migrationtest 70b5c7c0-ad71-4cc6-afbe-1bab5226da25 'UseGithubHydrationUtils:false;IsInlineGAInstallationEnabled:true;IsCentosInlineGAInstallationEnabled:true;IsConfidentialVmMigration:false'"};        
		Set-AzVMExtension -ResourceGroupName $ResourceGroupName -Location $Location -VMName $HydVM_Name -Name $HydVM_CustomScriptExtensionName `
        -Type "CustomScript" -Settings $Settings -TypeHandlerVersion "2.1" -Publisher "Microsoft.Azure.Extensions"
       
        if($?)
        {
            Write-Host "Attachment of custom Script Extension Successful!" -ForegroundColor Green
			#$HydErrCodeDetails = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $HydVM_Name -CommandId "RunShellScript"  -ScriptPath ".\GetErrorCode.sh" | Out-String -Stream
           
            #$HydErrCode = $HydErrCodeDetails[8]
            #$script:HydErrorData = $HydErrCodeDetails[9]
            #$script:HydErrorMessage = $HydErrCodeDetails[10]
            
            #Write-Host $script:HydErrorData
            #Write-Host $script:HydErrorMessage

            #[xml]$ErrorCodesXml = Get-Content -Path ".\ErrorCodes.xml"
            #foreach($ErrCode in $ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode.Number)
            #{ 
            #    if($ErrCode -eq $HydErrCode)
            #    {
            #        Write-Host "Description: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Description)"
            #        Write-Host "Category: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Category)"
            #        Write-Host "Possible Cause: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].PossibleCause)"
            #        Write-Host "Recommended Action: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].RecommendedAction)"
            #    }
            #}
            #SoftErrors
            #if($HydErrCode -ne 5 -and $HydErrCode -ne 16 -and $HydErrCode -ne 21 -and $HydErrCode -ne 22 -and $HydErrCode -ne 23 -and $HydErrCode -ne 24 -and $HydErrCode -ne 27) 
            #{
            #    $script:HydVM_AttachCSESuccessStatus = $true
            #}
            #HardErrors
            #else 
            #{
            #    Write-Error "Terminating the process due to Hard Errors"
            #}   
        }
        else 
        {
            Write-Error "Attachment of Custom Script Extension Unsuccessful!"
        }
    }
    else 
    {
        $CustomConfigSettings="";
        if($EnableDHCP -eq 1)
        {
            $CustomConfigSettings+="EnableDHCP:true,"
        }
        else 
        {
            $CustomConfigSettings+="EnableDHCP:false,"
        }
        if($EnableGA -eq 1)
        {
            $CustomConfigSettings+="EnableGA:true"
        }
        else 
        {
            $CustomConfigSettings+="EnableGA:false"
        } 
    
		$Settings = @{"fileUris" = $script:FileUris; "commandToExecute" = "bash StartupScript.sh migrationtest 70b5c7c0-ad71-4cc6-afbe-1bab5226da25 'UseGithubHydrationUtils:false;IsInlineGAInstallationEnabled:true;IsCentosInlineGAInstallationEnabled:true;IsConfidentialVmMigration:false'"};
        Set-AzVMExtension -ResourceGroupName $ResourceGroupName -Location $Location -VMName $HydVM_Name -Name $HydVM_CustomScriptExtensionName `
        -Type "CustomScript" -Settings $Settings -TypeHandlerVersion "2.1" -Publisher "Microsoft.Azure.Extensions"
        
        if($?)
        {
            Write-Host "Attachment of custom Script Extension Successful!" -ForegroundColor Green
			#$HydErrCodeDetails = Invoke-AzVMRunCommand -ResourceGroupName $ResourceGroupName -VMName $HydVM_Name -CommandId "RunShellScript"  -ScriptPath ".\GetErrorCode.sh" | Out-String -Stream
           
            #$HydErrCode = $HydErrCodeDetails[8]
            #$script:HydErrorData = $HydErrCodeDetails[9]
            #$script:HydErrorMessage = $HydErrCodeDetails[10]
            
            #Write-Host $script:HydErrorData
            #Write-Host $script:HydErrorMessage

            #[xml]$ErrorCodesXml = Get-Content -Path ".\ErrorCodes.xml"
            #foreach($ErrCode in $ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode.Number)
            #{ 
            #    if($ErrCode -eq $HydErrCode)
            #    {
            #        Write-Host "Description: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Description)"
            #        Write-Host "Category: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].Category)"
            #        Write-Host "Possible Cause: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].PossibleCause)"
            #        Write-Host "Recommended Action: $($ErrorCodesXml.ErrorCodeDetailMapping.ErrorCode[$ErrCode].RecommendedAction)"
            #    }
            #}
            #SoftErrors
            #if($HydErrCode -ne 5 -and $HydErrCode -ne 16 -and $HydErrCode -ne 21 -and $HydErrCode -ne 22 -and $HydErrCode -ne 23 -and $HydErrCode -ne 24 -and $HydErrCode -ne 27) 
            #{
            #    $script:HydVM_AttachCSESuccessStatus = $true
            #}
            #HardErrors
            #else 
            #{
            #    Write-Error "Terminating the process due to Hard Errors"
            #}
        }
        else 
        {
            Write-Error "Attachment of Custom Script Extension Unsuccessful!"
        }
    }    
}

<#------------------------------------------------------------------------------------
Function Name                   : HydVM_DeleteVirtualMachine
Global Variables/Constants used : $ResourceGroupName, $HydVM_Name
Description                     : Deletion of Hydration Virtual Machine
--------------------------------------------------------------------------------------#>
function HydVM_DeleteVirtualMachine
{
    Write-Host "Deleting the Hydration Virtual Machine..." 
    Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $HydVM_Name -Force
    if($?)
    {
        Write-Host "Deletion of $HydVM_Name Successful!" -ForegroundColor Green
        $script:HydVM_VMDeletionSuccessStatus = $true
    }
    else 
    {
        Write-Error "Deletion of $HydVM_Name Unsuccessful. Kindly delete the resource manually"
    }
}

<#------------------------------------------------------------------------------------
Function Name                   : HydVM_DeleteOSDisk
Global Variables/Constants used : $ResourceGroupName, $HydVM_Name
Description                     : Deletion of Hydration VM's OS Disk
--------------------------------------------------------------------------------------#>
function HydVM_DeleteOSDisk
{
    Write-Host "Deleting the Hydration VM's OS Disk..."
    Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $HydVM_OSDiskName -Force
    if($?)
    {
        Write-Host "Deletion of $HydVM_OSDiskName Successful!" -ForegroundColor Green
    }
    else 
    {
        Write-Error "Deletion of $HydVM_OSDiskName Unsuccessful. Kindly delete the resource manually"
    }
}

<#------------------------------------------------------------------------------------
Function Name                   : HydVM_DeleteNIC
Global Variables/Constants used : $ResourceGroupName, $HydVM_NICName
Description                     : Deletion of Hydration VM's Network Interface
--------------------------------------------------------------------------------------#>
function HydVM_DeleteNIC
{
    Write-Host "Deleting the Hydration VM's Network Interface..."
    Remove-AzNetworkInterface -Name $HydVM_NICName -ResourceGroup $ResourceGroupName -Force
    if($?)
    {
        Write-Host "Deletion of $HydVM_NICName Successful!" -ForegroundColor Green
    }
    else 
    {
        Write-Error "Deletion of $HydVM_NICName Unsuccessful. Kindly delete the resource manually"
    } 
}

<#------------------------------------------------------------------------------------
Function Name                   : HydVM_DeleteVirtualNetwork
Global Variables/Constants used : $ResourceGroupName, $HydVM_VirtualNetworkName
Description                     : Deletion of Hydration VM's Network Interface
--------------------------------------------------------------------------------------#>
function HydVM_DeleteVirtualNetwork 
{
    Write-Host "Deleting the Hydration VM's Virtual Network..."
    Remove-AzVirtualNetwork -Name $HydVM_VirtualNetworkName -ResourceGroupName $ResourceGroupName -Force
    if($?)
    {
        Write-Host "Deletion of $HydVM_VirtualNetworkName Successful!" -ForegroundColor Green
    }
    else 
    {
        Write-Error "Deletion of $HydVM_VirtualNetworkName Unsuccessful. Kindly delete the resource manually"
    }
}

<#------------------------------------------------------------------------------------
Function Name                   : HydVM_DeleteNSG
Global Variables/Constants used : $ResourceGroupName, $HydVM_NSGName
Description                     : Deletion of Hydration VM's Network Interface
--------------------------------------------------------------------------------------#>
function HydVM_DeleteNSG
{
    Write-Host "Deleting the Hydration VM's Network Security Group..."
    Remove-AzNetworkSecurityGroup -Name $HydVM_NSGName -ResourceGroupName $ResourceGroupName -Force
    if($?)
    {
        Write-Host "Deletion of $HydVM_NSGName Successful!" -ForegroundColor Green
    }
    else 
    {
        Write-Error "Deletion of $HydVM_NSGName Unsuccessful. Kindly delete the resource manually"
    }
}

<#------------------------------------------------------------------------------------
Function Name                   : TargetVM_DeleteVirtualMachine
Global Variables/Constants used : $ResourceGroupName, $TargetVM_Name
Description                     : Deletion of Target Virtual Machine
--------------------------------------------------------------------------------------#>
function TargetVM_DeleteVirtualMachine
{
    Write-Host "Deleting the Target Virtual Machine..." 
    Remove-AzVM -ResourceGroupName $ResourceGroupName -Name $TargetVM_VirtualMachineName -Force
    if($?)
    {
        Write-Host "Deletion of $TargetVM_Name Successful!" -ForegroundColor Green
    }
    else 
    {
        Write-Error "Deletion of $TargetVM_VirtualMachineName Unsuccessful. Kindly delete the resource manually"
    }
}

<#------------------------------------------------------------------------------------
Function Name                   : TargetVM_DeleteOSDisk
Global Variables/Constants used : $ResourceGroupName, $TargetVM_Name
Description                     : Deletion of Target VM's OS Disk
--------------------------------------------------------------------------------------#>
function TargetVM_DeleteOSDisk
{
    Write-Host "Deleting the Target VM's OS Disk..."
    Remove-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskCopy -Force
    if($?)
    {
        Write-Host "Deletion of $OSDiskCopy Successful!" -ForegroundColor Green
    }
    else 
    {
        Write-Error "Deletion of $OSDiskCopy Unsuccessful. Kindly delete the resource manually"
    }
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : TargetVM_CreateVirtualMachineWindows
Global Variables/Constants used : $TargetVM_VirtualMachineName, $TargetVM_VirtualMachineSize, $OSDiskCopy, $TargetVM_NICName, 
                                  $ResourceGroupName, $Location, $script:TargetVM_VirtualMachineSuccessStatus
Description                     : Sets the OS profile, Hardware profile, Storage profile and Network profile of the 
                                  configurable virtual machine object and creates Windows Target Virtual Machine using it.
                                  It sets the value of $script:TargetVM_VirtualMachineSuccessStatus to true if the creation of
                                  Windows Target VM is successful
---------------------------------------------------------------------------------------------------------------------------#>
function TargetVM_CreateVirtualMachineWindows
{
    #HardwareProfile
    $VirtualMachine = New-AzVMConfig -VMName $TargetVM_VirtualMachineName -VMSize $TargetVM_VirtualMachineSize

    #StorageProfile and #OSProfile
    $Disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskCopy
    Set-AzVMOSDisk -VM $VirtualMachine -ManagedDiskId $Disk.Id -Name $OSDiskCopy -CreateOption "Attach" -Windows

    #NetworkProfile
    $NICObject = Get-AzNetworkInterface -Name $TargetVM_NICName -ResourceGroupName $ResourceGroupName
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NICObject.Id
    
    Write-Host "Creating the Target Virtual Machine..."
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine

    if($?)
    {
        #GetStatusofVM
        Get-AzVM -ResourceGroupName $ResourceGroupName -Name $TargetVM_VirtualMachineName -Status
        Write-Host "Creation of Target Virtual Machine:  $TargetVM_VirtualMachineName Successful!" -ForegroundColor Green
        $script:TargetVM_VirtualMachineSuccessStatus = $true
		
        # Wait for 5 minutes
        Start-Sleep -Seconds 300

        # Check Guest Agent Status
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $TargetVM_VirtualMachineName -Status
		$guestAgentStatus = $vm.VMAgent.Statuses | Where-Object { $_.DisplayStatus -eq 'Ready' }
		if ($guestAgentStatus)
		{
			Write-Host "Guest Agent is up and running!" -ForegroundColor Green
		}
		else
		{
            Write-Error "Guest Agent is not up and running!"
            exit
		}
    }
    else 
    {
        Write-Error "Creation of Target Virtual Machine: $TargetVM_VirtualMachineName Unsuccessful!"
    }   
    
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : TargetVM_CreateVirtualMachineLinux
Global Variables/Constants used : $TargetVM_VirtualMachineName, $TargetVM_VirtualMachineSize, $OSDiskCopy, $TargetVM_NICName, 
                                  $ResourceGroupName, $Location, $script:TargetVM_VirtualMachineSuccessStatus
Description                     : Sets the OS profile, Hardware profile, Storage profile and Network profile of the 
                                  configurable virtual machine object and creates Linux Target Virtual Machine using it.
                                  It sets the value of $script:TargetVM_VirtualMachineSuccessStatus to true if the creation of
                                  Linux Target VM is successful
---------------------------------------------------------------------------------------------------------------------------#>
function TargetVM_CreateVirtualMachineLinux
{
    #HardwareProfile
    $VirtualMachine = New-AzVMConfig -VMName $TargetVM_VirtualMachineName -VMSize $TargetVM_VirtualMachineSize

    #StorageProfile and #OSProfile
    $Disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskCopy
    Set-AzVMOSDisk -VM $VirtualMachine -ManagedDiskId $Disk.Id -Name $OSDiskCopy -CreateOption "Attach" -Linux

    #NetworkProfile
    $NICObject = Get-AzNetworkInterface -Name $TargetVM_NICName -ResourceGroupName $ResourceGroupName
    $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NICObject.Id
    
    Write-Host "Creating the Target Virtual Machine..."
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine

    if($?)
    {
        #GetStatusofVM
        Get-AzVM -ResourceGroupName $ResourceGroupName -Name $TargetVM_VirtualMachineName -Status
        Write-Host "Creation of Target Virtual Machine:  $TargetVM_VirtualMachineName Successful!" -ForegroundColor Green
        $script:TargetVM_VirtualMachineSuccessStatus = $true
		
        # Wait for 5 minutes
        Start-Sleep -Seconds 300

        # Check Guest Agent Status
        $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $TargetVM_VirtualMachineName -Status
		$guestAgentStatus = $vm.VMAgent.Statuses | Where-Object { $_.DisplayStatus -eq 'Ready' }
		if ($guestAgentStatus)
		{
			Write-Host "Guest Agent is up and running!" -ForegroundColor Green
		}
		else
		{
            Write-Error "Guest Agent is not up and running!"
            exit
		}
    }
    else 
    {
        Write-Error "Creation of Target Virtual Machine: $TargetVM_VirtualMachineName Unsuccessful!"
    }   
    
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name                   : TargetVM_AttachDataDisks
Global Variables/Constants used : $NoOfDataDisks, $DataDisksName, $ResourceGroupName, $TargetVM_VirtualMachineName
Description                     : Attaches the data disks to the Target Virtual Machine
---------------------------------------------------------------------------------------------------------------------------#>
function TargetVM_AttachDataDisks
{
    Write-Host "Attaching Source Data Disks to the Target Virtual Machine..."
    for($i = 0; $i -lt $NoOfDataDisks; $i++)
    {
        $Disk = Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $DataDisksName[$i]
        $VirtualMachine = Get-AzVM -Name $TargetVM_VirtualMachineName -ResourceGroupName $ResourceGroupName
        $VirtualMachine = Add-AzVMDataDisk -CreateOption Attach -Lun $i -VM $VirtualMachine -ManagedDiskId $Disk.Id
        $DataDiskCheckStatus = Update-AzVM -VM $VirtualMachine -ResourceGroupName $ResourceGroupName
        If([string]::IsNullOrEmpty($DataDiskCheckStatus))
        {
            Write-Error "Attachment of Source Data disk:$DataDisksName[$i] to Target Virtual Machine Unsuccessful!"
        }  
    } 
}

<#---------------------------------------------------------------------------------------------------------------------------
Function Name : Main
Description   : Calls the respective functions if the success status of previous function is true and deletes 
                the temporary resources in case of any failure or when their job is done
---------------------------------------------------------------------------------------------------------------------------#>
function Main
{
    Start-Transcript
    Login

    if($script:LoginSuccessStatus -and $script:SubscriptionSuccessStatus)
    {
        HydVM_CreateVirtualNetwork
    }
    
    if($script:HydVM_VirtualNetworkSuccessStatus)
    {
        HydVM_CreateNIC
    }

    if($script:HydVM_NICSuccessStatus)
    {
        HydVM_CreateNSG
    }

    if($script:HydVM_NSGSuccessStatus)
    {
        if($OSType -eq 0)
        {
            HydVM_CreateVirtualMachineWindows
        }
        else 
        {
            HydVM_CreateVirtualMachineLinux
        }
    }

    if($script:HydVM_VirtualMachineSuccessStatus)
    {
		HydVM_CopySourceDisk
    }	
	
    if($script:HydVM_CopyOSDiskStatus)
    {
		HydVM_AttachSourceDisks
    }
    
    if($script:HydVM_AttachOSDiskSuccessStatus -and $script:HydVM_AttachDataDisksSuccessStatus)
    {
        HydVM_FetchHydComponentsFromGithub
        if($script:HydVM_FetchHydCompFromGithubSuccessStatus)
        {
            if($OSType -eq 0)
            {
                HydVM_AttachCustomScriptExtensionWindows
            }
            else 
            {
                HydVM_AttachCustomScriptExtensionLinux 
            }
        }
        
    }

    if($script:HydVM_VirtualMachineSuccessStatus)
    {
        HydVM_DeleteVirtualMachine
        HydVM_DeleteOSDisk
    }

    if($script:HydVM_NICSuccessStatus)
    {
        HydVM_DeleteNIC
    }

    if($script:HydVM_VirtualNetworkSuccessStatus)
    {
        HydVM_DeleteVirtualNetwork
    }

    if($script:HydVM_NSGSuccessStatus)
    {
        HydVM_DeleteNSG
    }

    if($script:HydVM_VMDeletionSuccessStatus)
    {
        if($OSType -eq 0)
        {
            TargetVM_CreateVirtualMachineWindows
        }
        else 
        {
            TargetVM_CreateVirtualMachineLinux
        }
         
        if($AttachDataDisks.IsPresent -and $script:TargetVM_VirtualMachineSuccessStatus)
        {
            TargetVM_AttachDataDisks
        }  
    }
	
	TargetVM_DeleteVirtualMachine
	TargetVM_DeleteOSDisk
	
    Stop-Transcript  
    Write-Host $script:HydErrorData
    Write-Host $script:HydErrorMessage
}

#Entry-Point
Main