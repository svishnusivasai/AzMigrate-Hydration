$Inputs = cat .\Input.json | convertfrom-json

#Connect-AzAccount -Tenant 70a036f6-8e4d-4615-bad6-149c02e7720d
#Select-AzSubscription -SubscriptionId $SubscriptionId

$OSType = 1
if(($Inputs.OSType -eq "Windows") -or ($Inputs.OSType -eq "windows"))
{
    $OSType = 0
}

if($Inputs.AddCustomConfigSettings)
{
    $EnableDHCP = 1
    $EnableGA = 1

    if(!$Inputs.EnableDHCP)
    {
        $EnableDHCP = 0
    }
    if(!$Inputs.EnableGA)
    {
        $EnableGA = 0
    }
    if(!$Inputs.AttachDataDisk)
    {
        .\PerformHydration.ps1 -ResourceGroupName $Inputs.ResourceGroupName -Location  $Inputs.Location -SubscriptionId $Inputs.SubscriptionId `
        -OSType $OSType ` -OSDiskName $Inputs.OSDiskName -TargetVM_NICName $Inputs.TargetVM_NICName `
        -TargetVM_VirtualMachineName $Inputs.TargetVM_VirtualMachineName -TargetVM_VirtualMachineSize $Inputs.TargetVM_VirtualMachineSize `
        -AddCustomConfigSettings -EnableDHCP $EnableDHCP -EnableGA $EnableGA -GithubBranch $Inputs.GithubBranch
    }
    else 
    {
        .\PerformHydration.ps1 -ResourceGroupName $Inputs.ResourceGroupName -Location  $Inputs.Location -SubscriptionId $Inputs.SubscriptionId `
        -OSType $OSType ` -OSDiskName $Inputs.OSDiskName -TargetVM_NICName $Inputs.TargetVM_NICName `
        -TargetVM_VirtualMachineName $Inputs.TargetVM_VirtualMachineName -TargetVM_VirtualMachineSize $Inputs.TargetVM_VirtualMachineSize `
        -AddCustomConfigSettings -EnableDHCP $EnableDHCP -EnableGA $EnableGA -AttachDataDisks -NoOfDataDisks $Inputs.NoOfDataDisks `
        -DataDisksName $Inputs.DataDisksName -GithubBranch $Inputs.GithubBranch
    }
}
else 
{
    if(!$Inputs.AttachDataDisk)
    {
        .\PerformHydration.ps1 -ResourceGroupName $Inputs.ResourceGroupName -Location  $Inputs.Location -SubscriptionId $Inputs.SubscriptionId `
        -OSType $OSType ` -OSDiskName $Inputs.OSDiskName -TargetVM_NICName $Inputs.TargetVM_NICName `
        -TargetVM_VirtualMachineName $Inputs.TargetVM_VirtualMachineName -TargetVM_VirtualMachineSize $Inputs.TargetVM_VirtualMachineSize `
        -GithubBranch $Inputs.GithubBranch
    }
    else 
    {
        .\PerformHydration.ps1 -ResourceGroupName $Inputs.ResourceGroupName -Location  $Inputs.Location -SubscriptionId $Inputs.SubscriptionId `
        -OSType $OSType ` -OSDiskName $Inputs.OSDiskName -TargetVM_NICName $Inputs.TargetVM_NICName `
        -TargetVM_VirtualMachineName $Inputs.TargetVM_VirtualMachineName -TargetVM_VirtualMachineSize $Inputs.TargetVM_VirtualMachineSize `
        -AttachDataDisks -NoOfDataDisks $Inputs.NoOfDataDisks -DataDisksName $Inputs.DataDisksName -GithubBranch $Inputs.GithubBranch
    } 
}