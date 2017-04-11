<# 
.Synopsis 
   Setup the test lab base configuration in Windows Azure to evaluate the single sign-on feature of Azure AD/Office 365 with AD FS in Windows Server 2012 R2. 
.DESCRIPTION 
   This script enables you to setup an Azure-based lab configuration in Windows Azure to evaluate the single sign-on feature of Azure AD/Office 365 with
   AD FS in Windows Server 2012 R2. It more particularly add a VM and script it to become a domain controller for a new forest, add an additional member server VM
   to the domain for AD FS, as well as another edge server VM for the Web Application Proxy by adding them to a cloud service on the same VNet. A new VNet is 
   created for the deployment, if a VNet site with the same name exists, the script does not continue.
   
   This script is just customized for the test lab base configuration.
.EXAMPLE 
    Using all of the required parameters 
 
   .\New-TestLabEnvironment.ps1 -ServiceName "identitypluslab" -Location "North Europe"
 
    Using all of the parameters including the optional VNet details and VM sizes 
 
    .\New-TestLabEnvironment.ps1 -ServiceName "identitypluslab" -Location "North Europe" ` 
		-DomainControllerName "ads01" -DCVMSize "Small" -FQDNDomainName "identityplus.ch" -NetBIOSDomainName "IDENTITYPLUS"  `
		-MemberServerName "idb01" -MemberVMSize "Small" -EdgeServerName "ura01" -EdgeVMSize "Small"  ` 
		-VNetAddressPrefix "10.0.0.0/8" -Subnet1AddressPrefix "10.0.1.0/24" -Subnet2AddressPrefix "10.0.2.0/24"
#> 
Param 
( 
    # Service name to deploy to 
    [Parameter(Mandatory=$true)] 
    [String] $ServiceName, 
 
    # Location of the service 
    [Parameter(Mandatory=$true)] 
    [String] $Location, 
	
    # Name of the DC 
    [Parameter(Mandatory=$false)] 
    [String] $DomainControllerName = "ads01",     
 
    # VM Size for the DC 
    [Parameter(Mandatory=$false)] 
    [ValidateSet("ExtraSmall","Small","Medium","Large","ExtraLarge","A6","A7")] 
    [String] $DCVMSize = "Small",     

    # FDQN Domain name for the forest 
    [Parameter(Mandatory=$false)] 
    [String] $FQDNDomainName = "identityplus.ch",
	
    # NetBIOS domain name for the forest 
    [Parameter(Mandatory=$false)] 
    [String] $NetBIOSDomainName = "IDENTITYPLUS", 
	
    # Name of the member server 
    [Parameter(Mandatory=$false)] 
    [String] $MemberServerName = "idb01", 
 
    # VM Size for the member server 
    [Parameter(Mandatory=$false)] 
    [ValidateSet("ExtraSmall","Small","Medium","Large","ExtraLarge","A6","A7")] 
    [String] $MemberVMSize = "Small",     
 
     # Name of the edge server 
    [Parameter(Mandatory=$false)] 
    [String] $EdgeServerName = "ura01", 
 
    # VM Size for the edge server 
    [Parameter(Mandatory=$false)] 
    [ValidateSet("ExtraSmall","Small","Medium","Large","ExtraLarge","A6","A7")] 
    [String] $EdgeVMSize = "Small",
	
	#VNet address prefix for the VNet 
    [Parameter(Mandatory=$false)] 
    [String] $VNetAddressPrefix = "10.0.0.0/8",  
	
	# Address space for the subnet #1 (aka edge subnet) to be used for the edge server
    [Parameter(Mandatory=$false)] 
    [String] $Subnet1AddressPrefix = "10.0.1.0/24", 

	# Address space for the subnet #2 (aka internal subnet) to be used for the DC and the member server 
    [Parameter(Mandatory=$false)] 
    [String] $Subnet2AddressPrefix = "10.0.2.0/24"  	
) 
 
# The script has been tested on Windows PowerShell 3.0 
Set-StrictMode -Version 3 
 
# Following modifies the Write-Verbose behavior to turn the messages on globally for this session 
$VerbosePreference = "Continue" 
 
# Check if Windows Azure PowerShell is available 
if ((Get-Module -ListAvailable Azure) -eq $null) 
{ 
    throw "Windows Azure PowerShell not found! Please install from http://www.windowsazure.com/en-us/downloads/#cmd-line-tools" 
} 
 
<# 
.SYNOPSIS 
    Adds a new affinity group if it does not exist. 
.DESCRIPTION 
   Looks up the current subscription's (as set by Set-AzureSubscription cmdlet) affinity groups and creates a new 
   affinity group if it does not exist. 
.EXAMPLE 
   New-AzureAffinityGroupIfNotExists -AffinityGroupName "identitypluslab" -Location "North Europe"  
#> 
function New-AzureAffinityGroupIfNotExists 
{ 
	param 
    ( 
        # Name of the affinity group 
        [String] $AffinityGroupName, 
         
        # Location where the affinity group will be pointing to 
        [String] $Location
	) 
     
    $affinityGroup = Get-AzureAffinityGroup -Name $AffinityGroupName -ErrorAction SilentlyContinue 
    if ($affinityGroup -eq $null) 
    { 
        New-AzureAffinityGroup -Name $AffinityGroupName -Location $Location -Label $AffinityGroupName `
			-ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null 
        if (!($?)) 
        { 
            throw "Cannot create the affinity group $AffinityGroupName on $Location" 
        } 
        Write-Verbose "Created affinity group $AffinityGroupName" 
    } 
    else 
    { 
        if ($affinityGroup.Location -ne $Location) 
        { 
            Write-Warning "Affinity group with name $AffinityGroupName already exists but in location $affinityGroup.Location, not in $Location" 
        } 
    } 
} 

<# 
.SYNOPSIS 
    Adds a new service if it does not exist. 
.DESCRIPTION 
   Looks up the current subscription's (as set by Set-AzureSubscription cmdlet) services and creates a new 
   storage account if it does not exist. 
.EXAMPLE 
   New-AzureServiceIfNotExists -ServiceName "identitypluslab" -AffinityGroup "identitypluslab"
#> 
function New-AzureServiceIfNotExists 
{ 
	param 
    ( 
        # Name of the cloud service
        [String] $ServiceName, 
         
        # Affinity group name to which the cloud service will be associated 
        [String] $AffinityGroupName
	) 
    
	$service = Get-AzureService -ServiceName $ServiceName -ErrorAction SilentlyContinue
	if ($service -eq $null) 
	{ 
		New-AzureService -ServiceName $ServiceName -AffinityGroup $AffinityGroupName  `
			-ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null 
        if (!($?)) 
        { 
            throw "Cannot create the service $ServiceName with $AffinityGroupName in $Location" 
        } 
        Write-Verbose "Created service $ServiceName" 
	}
	else
	{
        if ($service.AffinityGroup -ne $AffinityGroupName) 
        { 
            Write-Warning "Cloud service with name $ServiceName already exists but with the affinity group $service.AffinityGroup, not with $AffinityGroupName" 
        } 
	} 
}

<# 
.SYNOPSIS 
    Adds a new storage account if it does not exist. 
.DESCRIPTION 
   Looks up the current subscription's (as set by Set-AzureSubscription cmdlet) storage accounts and creates a new 
   storage account if it does not exist. 
.EXAMPLE 
   New-AzureStorageAccountIfNotExists -StorageAccountName "identitypluslab" -AffinityGroup "identitypluslab"
#> 
function New-AzureStorageAccountIfNotExists 
{ 
	param 
    ( 
        # Name of the storage account
        [String] $StorageAccountName, 
         
        # Affinity group name to which the storage account will be associated 
        [String] $AffinityGroupName
	) 
     
    $storageAccount = Get-AzureStorageAccount -StorageAccountName $StorageAccountName -ErrorAction SilentlyContinue 
    if ($storageAccount -eq $null) 
    { 
        New-AzureStorageAccount -StorageAccountName $StorageAccountName -AffinityGroup $AffinityGroupName  `
				-ErrorVariable lastError -ErrorAction SilentlyContinue | Out-Null 
        if (!($?)) 
        { 
            throw "Cannot create the storage account $StorageAccountName with $AffinityGroupName in $Location" 
        } 
        Write-Verbose "Created storage account $StorageAccountName" 
    } 
    else 
    { 
        if ($storageAccount.AffinityGroup -ne $AffinityGroupName) 
        { 
            Write-Warning "Storage account with name $StorageAccountName already exists but with the affinity group $storageAccountName.AffinityGroup, not with $AffinityGroupName" 
        } 
    } 
} 
  
<# 
.Synopsis 
   Create an empty VNet configuration file. 
.DESCRIPTION 
   Create an empty VNet configuration file. 
.EXAMPLE 
    Add-AzureVnetConfigurationFile -Path c:\temp\identitypluslabvnet.xml
#> 
function Add-AzureVnetConfigurationFile 
{ 
    param ([String] $Path) 
     
    $configFileContent = [Xml] "<?xml version=""1.0"" encoding=""utf-8""?> 
    <NetworkConfiguration xmlns:xsd=""http://www.w3.org/2001/XMLSchema"" xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance"" xmlns=""http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration""> 
              <VirtualNetworkConfiguration> 
                <Dns /> 
                <VirtualNetworkSites/> 
              </VirtualNetworkConfiguration> 
            </NetworkConfiguration>" 
     
    $configFileContent.Save($Path) 
} 
 
<# 
.SYNOPSIS 
   Sets the provided values in the VNet file of a subscription's VNet file  
.DESCRIPTION 
   It sets the VNetName and AffinityGroup of a given subscription's VNEt configuration file. 
.EXAMPLE 
    Set-VNetFileValues -FilePath c:\temp\identitypluslabvnet.xml -AffinityGroupName "identitypluslab" ` 
		-VNetName "identitypluslab" -VNetAddressPrefix "10.0.0.0/8"  ` 
		-Subnet1Name "identitypluslab-subnet1" -Subnet1AddressPrefix "10.0.1.0/24"  `
		-Subnet2Name "identitypluslab-subnet2" -Subnet2AddressPrefix "10.0.2.0/24"
#> 
function Set-VNetFileValues 
{ 
    param ( 
         
        # The path to the exported VNet file 
        [String] $FilePath,  
         
        # The affinity group the new VNet site will be associated with 
        [String] $AffinityGroupName,  

        # Name of the new VNet site 
        [String] $VNet,  
                  
        # Address prefix for the VNet 
        [String] $VNetAddressPrefix,  
		
		# The name of the  subnet #2 (aka internal subnet) to be added to the VNet 
        [String] $Subnet2Name,  
         
        # Address space for the subnet #2 (aka internal subnet)
        [String] $Subnet2AddressPrefix,
         
        # The name of the  subnet #1 (aka edge subnet) to be added to the VNet 
        [String] $Subnet1Name,  
         
        # Address space for the subnet #1 (aka edge subnet)
        [String] $Subnet1AddressPrefix
	) 
     
    [Xml]$xml = New-Object XML 
    $xml.Load($FilePath) 
			
    $vnetSiteNodes = $xml.GetElementsByTagName("VirtualNetworkSite") 
     
    $foundVirtualNetworkSite = $null 
    if ($vnetSiteNodes -ne $null) 
    { 
        $foundVirtualNetworkSite = $vnetSiteNodes | Where-Object { $_.name -eq $VNet } 
    } 
 
    if ($foundVirtualNetworkSite -ne $null) 
    { 
        $foundVirtualNetworkSite.AffinityGroup = $AffinityGroupName 
    } 
    else 
    { 
        $virtualNetworkSites = $xml.NetworkConfiguration.VirtualNetworkConfiguration.GetElementsByTagName("VirtualNetworkSites") 
        if ($null -ne $virtualNetworkSites) 
        { 	
            $virtualNetworkElement = $xml.CreateElement("VirtualNetworkSite", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
             
            $vNetSiteNameAttribute = $xml.CreateAttribute("name") 
            $vNetSiteNameAttribute.InnerText = $VNet 
            $virtualNetworkElement.Attributes.Append($vNetSiteNameAttribute) | Out-Null 
             
            $affinityGroupAttribute = $xml.CreateAttribute("AffinityGroup") 
            $affinityGroupAttribute.InnerText = $AffinityGroupName 
            $virtualNetworkElement.Attributes.Append($affinityGroupAttribute) | Out-Null 
             
            $addressSpaceElement = $xml.CreateElement("AddressSpace", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")             
            $addressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
            $addressPrefixElement.InnerText = $VNetAddressPrefix 
            $addressSpaceElement.AppendChild($addressPrefixElement) | Out-Null 
            $virtualNetworkElement.AppendChild($addressSpaceElement) | Out-Null 
             
            $subnetsElement = $xml.CreateElement("Subnets", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
                        
            $subnet1Element = $xml.CreateElement("Subnet", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
            $subnet1NameAttribute = $xml.CreateAttribute("name") 
            $subnet1NameAttribute.InnerText = $Subnet1Name 
            $subnet1Element.Attributes.Append($subnet1NameAttribute) | Out-Null 
            $subnet1AddressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
            $subnet1AddressPrefixElement.InnerText = $Subnet1AddressPrefix
            $subnet1Element.AppendChild($subnet1AddressPrefixElement) | Out-Null 
            $subnetsElement.AppendChild($subnet1Element) | Out-Null 
            
            $subnet2Element = $xml.CreateElement("Subnet", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
            $subnet2NameAttribute = $xml.CreateAttribute("name") 
            $subnet2NameAttribute.InnerText = $Subnet2Name 
            $subnet2Element.Attributes.Append($subnet2NameAttribute) | Out-Null 
            $subnet2AddressPrefixElement = $xml.CreateElement("AddressPrefix", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
            $subnet2AddressPrefixElement.InnerText = $Subnet2AddressPrefix
            $subnet2Element.AppendChild($subnet2AddressPrefixElement) | Out-Null 
            $subnetsElement.AppendChild($subnet2Element) | Out-Null 
			
			$virtualNetworkElement.AppendChild($subnetsElement) | Out-Null 
			
            $virtualNetworkSites.AppendChild($virtualNetworkElement) | Out-Null 
        } 
        else 
        { 
            throw "Can't find 'VirtualNetworkSite' tag" 
        } 
    } 
     
    $xml.Save($filePath) 
} 
 
<# 
.SYNOPSIS 
   Creates a Virtual Network Site if it does not exist and sets the subnet details for the test lab environment. 
.DESCRIPTION 
   Creates the VNet site if it does not exist. It leverages the network configuration provided for the test lab environment. 
.EXAMPLE 
   New-VNetSite -VNetName "identitypluslab" -AffinityGroupName "identitypluslab" -VNetAddressPrefix "10.0.0.0/8" ` 
		-Subnet1Name "identitypluslab-subnet1" -Subnet1AddressPrefix "10.0.1.0/24" `
		-Subnet2Name "identitypluslab-subnet2" -Subnet2AddressPrefix "10.0.2.0/24"
#> 
function New-VNetSite 
{ 
    param 
    ( 
        # Name of the VNet site 
        [String] $VNetName, 
         
         # The affinity group the vNet will be associated with 
        [Parameter(Mandatory = $true)] 
        [String] $AffinityGroupName, 

		# Address prefix for the VNet	
        [String] $VNetAddressPrefix, 
		
		# The name of the  subnet #2 (aka internal subnet) to be added to the VNet 
        [String] $Subnet2Name,  
         
        # Address space for the subnet #2 (aka internal subnet)
        [String] $Subnet2AddressPrefix,

        # The name of the  subnet #1 (aka edge subnet) to be added to the VNet 
        [String] $Subnet1Name,  
         
        # Address space for the subnet #1 (aka edge subnet)
        [String] $Subnet1AddressPrefix
	)
	
    $vNetFilePath = "$env:temp\$ServiceName" + "identitypluslabvnet.xml" 
    Get-AzureVNetConfig -ExportToFile $vNetFilePath  -ErrorAction SilentlyContinue | Out-Null 
    if (!(Test-Path $vNetFilePath)) 
    { 
        Add-AzureVnetConfigurationFile -Path $vNetFilePath 
    } 
    
    Set-VNetFileValues -FilePath $vNetFilePath -VNet $VNetName -VNetAddressPrefix $VNetAddressPrefix -AffinityGroup $AffinityGroupName `
	       -Subnet1Name $Subnet1Name -Subnet1AddressPrefix $Subnet1AddressPrefix -Subnet2Name $Subnet2Name -Subnet2AddressPrefix $Subnet2AddressPrefix
    Set-AzureVNetConfig -ConfigurationPath $vNetFilePath -ErrorAction SilentlyContinue -ErrorVariable errorVariable | Out-Null 
    if (!($?)) 
    { 
        throw "Cannot set the vNet configuration for the subscription, please see the file $vNetFilePath. Error detail is: $errorVariable" 
    } 
    Write-Verbose "Modified and saved the VNet Configuration for the subscription" 
     
    Remove-Item $vNetFilePath 
} 
 
<# 
.SYNOPSIS 
   Modifies the virtual network configuration xml file to include a DNS service reference. 
.DESCRIPTION 
   This a small utility that programmatically modifies the vNet configuration file to add a DNS server 
   then adds the DNS server's reference to the specified VNet site. 
.EXAMPLE 
    Add-AzureDnsServerConfiguration -Name "ads01" -IpAddress "10.0.2.4" -VNetName "identitypluslab" 
#> 
function Add-AzureDnsServerConfiguration 
{ 
   param 
    ( 
        [String] $Name, 
 
        [String] $IpAddress, 
 
        [String] $VNetName 
    ) 
 
    $vNet = Get-AzureVNetSite -VNetName $VNetName -ErrorAction SilentlyContinue 
    if ($vNet -eq $null) 
    { 
        throw "VNetSite $VNetName does not exist. Cannot add DNS server reference." 
    } 
 
    $vnetFilePath = "$env:temp\$ServiceName" + "identitypluslab.xml" 
    Get-AzureVNetConfig -ExportToFile $vnetFilePath | Out-Null 
    if (!(Test-Path $vNetFilePath)) 
    { 
        throw "Cannot retrieve the vNet configuration file." 
    } 
 
    [Xml]$xml = New-Object XML 
    $xml.Load($vnetFilePath) 
 
    $dns = $xml.NetworkConfiguration.VirtualNetworkConfiguration.Dns 
    if ($dns -eq $null) 
    { 
        $dns = $xml.CreateElement("Dns", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
        $xml.NetworkConfiguration.VirtualNetworkConfiguration.AppendChild($dns) | Out-Null 
    } 
 
    # Dns node is returned as an empy element, and in Windows PowerShell 3.0 the empty elements are returned as a string with dot notation 
    # use Select-Xml instead to bring it in. 
    # When using the default namespace in Select-Xml cmdlet, an arbitrary namespace name is used (because there is no name 
    # after xmlns:) 
    $namespace = @{network="http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration"} 
    $dnsNode = select-xml -xml $xml -XPath "//network:Dns" -Namespace $namespace 
    $dnsElement = $null 
 
    # In case the returning node is empty, let's create it 
    if ($dnsNode -eq $null) 
    { 
        $dnsElement = $xml.CreateElement("Dns", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
        $xml.NetworkConfiguration.VirtualNetworkConfiguration.AppendChild($dnsElement) 
    } 
    else 
    { 
        $dnsElement = $dnsNode.Node 
    } 
 
    $dnsServersNode = select-xml -xml $xml -XPath "//network:DnsServers" -Namespace $namespace 
    $dnsServersElement = $null 
 
    if ($dnsServersNode -eq $null) 
    { 
        $dnsServersElement = $xml.CreateElement("DnsServers", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
        $dnsElement.AppendChild($dnsServersElement) | Out-Null 
    } 
    else 
    { 
        $dnsServersElement = $dnsServersNode.Node 
    } 
 
    $dnsServersElements = $xml.GetElementsByTagName("DnsServer") 
    $dnsServerElement = $dnsServersElements | Where-Object {$_.name -eq $Name} 
    if ($dnsServerElement -ne $null) 
    { 
        $dnsServerElement.IpAddress = $IpAddress 
    } 
    else 
    { 
        $dnsServerElement = $xml.CreateElement("DnsServer", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
        $nameAttribute = $xml.CreateAttribute("name") 
        $nameAttribute.InnerText = $Name 
        $dnsServerElement.Attributes.Append($nameAttribute) | Out-Null 
        $ipAddressAttribute = $xml.CreateAttribute("IPAddress") 
        $ipAddressAttribute.InnerText = $IpAddress 
        $dnsServerElement.Attributes.Append($ipAddressAttribute) | Out-Null 
        $dnsServersElement.AppendChild($dnsServerElement) | Out-Null 
    } 
 
    # Now set the DnsReference for the network site 
    $xpathQuery = "//network:VirtualNetworkSite[@name = '" + $VNetName + "']" 
    $foundVirtualNetworkSite = select-xml -xml $xml -XPath $xpathQuery -Namespace $namespace  
 
    if ($foundVirtualNetworkSite -eq $null) 
    { 
        throw "Cannot find the VNet $VNetName" 
    } 
 
    $dnsServersRefElementNode = $foundVirtualNetworkSite.Node.GetElementsByTagName("DnsServersRef") 
 
    $dnsServersRefElement = $null 
    if ($dnsServersRefElementNode.Count -eq 0) 
    { 
        $dnsServersRefElement = $xml.CreateElement("DnsServersRef", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration") 
        $foundVirtualNetworkSite.Node.AppendChild($dnsServersRefElement) | Out-Null 
    } 
    else 
    { 
        $dnsServersRefElement = $foundVirtualNetworkSite.DnsServersRef 
    } 
     
    $xpathQuery = "/DnsServerRef[@name = '" + $Name + "']" 
    $dnsServerRef = $dnsServersRefElement.SelectNodes($xpathQuery) 
    $dnsServerRefElement = $null 
 
    if($dnsServerRef.Count -eq 0) 
    { 
        $dnsServerRefElement = $xml.CreateElement("DnsServerRef", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")         
        $dnsServerRefNameAttribute = $xml.CreateAttribute("name") 
        $dnsServerRefElement.Attributes.Append($dnsServerRefNameAttribute) | Out-Null 
        $dnsServersRefElement.AppendChild($dnsServerRefElement) | Out-Null 
    } 
 
    if ($dnsServerRefElement -eq $null) 
    { 
        throw "No DnsServerRef element is found" 
    }     
 
    $dnsServerRefElement.name = $name 
 
    $xml.Save($vnetFilePath) 
	
	Set-AzureVNetConfig -ConfigurationPath $vNetFilePath -ErrorAction SilentlyContinue -ErrorVariable errorVariable | Out-Null 
    if (!($?)) 
    { 
        throw "Cannot set the vNet configuration for the subscription, please see the file $vNetFilePath. Error detail is: $errorVariable" 
    } 
    Write-Verbose "Modified and saved the VNet Configuration for the subscription" 
     
    Remove-Item $vNetFilePath 
}
  
<# 
.SYNOPSIS 
  Returns the latest image for a given image family name filter. 
.DESCRIPTION 
  Will return the latest image based on a filter match on the ImageFamilyName and 
  PublisedDate of the image.  The more specific the filter, the more control you have 
  over the object returned. 
.EXAMPLE 
  The following example will return the latest Windows Server 2012 R2 image. This function will 
  also only select the image from images published by Microsoft:
    Get-LatestImage -ImageFamilyNameFilter "*Windows Server 2012 R2*" -OnlyMicrosoftImages 
#> 
function Get-LatestImage 
{ 
    param 
    ( 
        # A filter for selecting the image family. 
        # For example, "Windows Server 2012 R2*", "*2012 R2 Datacenter*" 
        [String] $ImageFamilyNameFilter, 
 
        # A switch to indicate whether or not to select the latest image where the publisher is Microsoft. 
        # If this switch is not specified, then images from all possible publishers are considered. 
        [switch] $OnlyMicrosoftImages 
    ) 
     
    # Get a list of all available images. 
    $imageList = Get-AzureVMImage 
     
    if ($OnlyMicrosoftImages.IsPresent)
    { 
        $imageList = $imageList | 
                         Where-Object { ` 
                             ($_.PublisherName -ilike "Microsoft*" -and ` 
                              $_.ImageFamily -ilike $ImageFamilyNameFilter ) } 
    } 
    else 
    { 
        $imageList = $imageList | 
                         Where-Object { ` 
                             ($_.ImageFamily -ilike $ImageFamilyNameFilter ) }  
    } 
 
    $imageList = $imageList |  
                     Sort-Object -Unique -Descending -Property ImageFamily | 
                     Sort-Object -Descending -Property PublishedDate 
 
    $imageList | Select-Object -First(1)
} 

$serviceNameCore = $ServiceName.ToLower() 

# Create the affinity group
$affinityGroupName = ($serviceNameCore + "aff").ToLower() 
New-AzureAffinityGroupIfNotExists -AffinityGroupName $affinityGroupName -Location $Location 
 
# Create the service name
$ServiceName= ($serviceNameCore  + "svc").ToLower()
New-AzureServiceIfNotExists -ServiceName $ServiceName -AffinityGroup $affinityGroupName

# Check the VNet site, and add it to the configuration if it does not exist. 
$VNetName = ($serviceNameCore  + "vnet").ToLower()
$vNet = Get-AzureVNetSite -VNetName $VNetName  -ErrorAction Ignore  | Out-Null
if ($vNet -ne $null) 
{ 

    throw "VNet site name $VNetName is taken. Please provide a different name." 
} 
 
$subnet1Name = ($VNetName + "-subnet1").ToLower()
$subnet2Name = ($VNetName + "-subnet2").ToLower() 

New-VNetSite -VNetName $VNetName -AffinityGroupName $affinityGroupName -VNetAddressPrefix $VNetAddressPrefix `
	-Subnet1Name $subnet1Name -Subnet1AddressPrefix $Subnet1AddressPrefix `
	-Subnet2Name $subnet2Name -Subnet2AddressPrefix $Subnet2AddressPrefix
 
# Create the storage account
$storageAccountName = ($serviceNameCore + "stor").ToLower() 
New-AzureStorageAccountIfNotExists -StorageAccountName $storageAccountName.ToLower() -AffinityGroup $affinityGroupName

$subscription = Get-AzureSubscription -Current 
Set-AzureSubscription -SubscriptionName $subscription.SubscriptionName -CurrentStorageAccount $storageAccountName -ErrorAction SilentlyContinue | Out-Null 
 
# Test if there are already VMs deployed with those names 
$existingVm = Get-AzureVM  -ServiceName $ServiceName -Name $DomainControllerName -ErrorAction SilentlyContinue | Out-Null 
if ($existingVm -ne $null) 
{ 
    throw "A VM with name $DomainControllerName exists on $ServiceName" 
} 
 
$existingVm = Get-AzureVM  -ServiceName $ServiceName -Name $MemberServerName -ErrorAction SilentlyContinue | Out-Null 
if ($existingVm -ne $null) 
{ 
    throw "A VM with name $MemberServerName exists on $ServiceName" 
} 

$existingVm = Get-AzureVM -ServiceName $ServiceName -Name $EdgeServerName -ErrorAction SilentlyContinue | Out-Null 
if ($existingVm -ne $null) 
{ 
    throw "A VM with name $EdgeServerName exists on $ServiceName" 
} 
	
$imageFamilyNameFilter = "Windows Server 2012 R2 Datacenter" 
 
$image = Get-LatestImage -ImageFamilyNameFilter $imageFamilyNameFilter -OnlyMicrosoftImages 
if ($image -eq $null) 
{ 
    throw "Unable to find an image for $imageFamilyNameFilter to provision Virtual Machine." 
} 
 
Write-Verbose "Prompt user for administrator credentials to use when provisioning the virtual machine(s)." 
$credential = Get-Credential -Message "Please provide the administrator credentials for the virtual machines" 
$username = $credential.GetNetworkCredential().username
$password = $credential.GetNetworkCredential().password

$domainControllerVM = New-AzureVMConfig -Name $DomainControllerName -InstanceSize $DCVMSize -ImageName $image.ImageName |  
                        Add-AzureProvisioningConfig -Windows -AdminUsername $username -Password $password |  
                        Set-AzureSubnet -SubnetNames $subnet2Name | 
                        Add-AzureDataDisk -CreateNew -DiskSizeInGB 20 -DiskLabel 'DITDrive' -LUN 0 
New-AzureVM -ServiceName $ServiceName -VMs $domainControllerVM -VNetName $VNetName -WaitForBoot | Out-Null 
 
# Set the WinRmHTTPs communication information
$domainControllerWinRMUri= Get-AzureWinRMUri -ServiceName $ServiceName -Name $DomainControllerName
 
$option = New-PSSessionOption -SkipCACheck   
 
$domainInstallScript = { 
        param ([String] $FQDNDomainName, [string] $NetBIOSDomainName, [System.Security.SecureString] $safeModePassword) 
        initialize-disk 2 -PartitionStyle MBR  
        New-Partition -DiskNumber 2 -UseMaximumSize -IsActive -DriveLetter F | Format-Volume -FileSystem NTFS -NewFileSystemLabel "AD DS Data" -Force:$true -confirm:$false 
 
        Import-Module ServerManager 
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools 
        Install-WindowsFeature RSAT-AD-Tools 
        Import-Module ADDSDeployment
		Install-ADDSForest `
			-CreateDNSDelegation:$false `
			-DatabasePath "F:\NTDS" `
			-DomainMode "Win2012R2" `
			-DomainName $FQDNDomainName `
			-DomainNetBiosName $NetBIOSDomainName `
			-ForestMode "Win2012R2" `
			-InstallDns:$true `
			-LogPath "F:\NTDS" `
			-NoRebootOnCompletion:$false `
			-SysvolPath "F:\SYSVOL" `
			-SafeModeAdministratorPassword $safeModePassword  `
			-Force:$true   
} 

$safeModePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
Invoke-Command -ConnectionUri $domainControllerWinRMUri.ToString() -Credential $credential -SessionOption $option -ScriptBlock $domainInstallScript -ArgumentList @($FQDNDomainName, $NetBIOSDomainName, $safeModePassword) 
 
do 
{ 
    Start-Sleep -Seconds 30 
    $vm = Get-AzureVM -ServiceName $ServiceName -Name $DomainControllerName     
} 
until ($vm.InstanceStatus -eq "ReadyRole") 
 
Add-AzureDnsServerConfiguration -Name $DomainControllerName -IpAddress $vm.IpAddress -VNetName $VNetName 
 
if ($vm -eq $null) 
{ 
    throw "Cannot get the details of the DC VM" 
} 
 
$memberServerVM = New-AzureVMConfig -Name $MemberServerName -InstanceSize $MemberVMSize -ImageName $image.ImageName |  
                    Add-AzureProvisioningConfig -WindowsDomain -Password $password -AdminUsername $username  `
						-JoinDomain $FQDNDomainName -Domain $NetBIOSDomainName -DomainUserName $username -DomainPassword $password  | 
                    Set-AzureSubnet -SubnetNames $subnet2Name  
New-AzureVM -ServiceName $ServiceName -VMs $memberServerVM -VNetName $VNetName -WaitForBoot  | Out-Null 
							
# Set WinRmHTTPs communication information
$memberServerWinRMUri = Get-AzureWinRMUri -ServiceName $serviceName -Name $MemberServerName 
$option = New-PSSessionOption -SkipCACheck    

Invoke-Command -ConnectionUri $memberServerWinRMUri.ToString() -Credential $credential `
    -SessionOption $option -ScriptBlock {
	Import-Module ServerManager
	# See Installing IIS 8.5 on Windows Server 2012 R2 (http://www.iis.net/learn/install/installing-iis-85/installing-iis-85-on-windows-server-2012-r2)
	Install-WindowsFeature NET-Framework-Core, AS-HTTP-Activation, NET-Framework-45-Features, Web-Mgmt-Console, Web-Asp-Net, Web-Asp-Net45, Web-Basic-Auth,  `
		Web-Client-Auth, Web-Digest-Auth, Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, Web-Http-Logging, Web-Http-Redirect,  `
		Web-Http-Tracing, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Lgcy-Mgmt-Console, Web-Metabase, Web-Mgmt-Console, Web-Mgmt-Service,  `
		Web-Net-Ext, Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, Web-Static-Content, Web-Windows-Auth, Web-WMI,  `
		Windows-Identity-Foundation
		
	Configure-SMRemoting.exe -enable
    Restart-Computer -Force
}
							
$edgeServerVM = New-AzureVMConfig -Name $EdgeServerName -InstanceSize $EdgeVMSize -ImageName $image.ImageName |  
                    Add-AzureProvisioningConfig -WindowsDomain -Password $password -AdminUsername $username  `
						-JoinDomain $FQDNDomainName -Domain $NetBIOSDomainName -DomainUserName $username -DomainPassword $password  | 
					Set-AzureSubnet -SubnetNames $subnet1Name   
New-AzureVM -ServiceName $ServiceName -VMs $edgeServerVM -VNetName $VNetName  -WaitForBoot | Out-Null
Get-AzureVM -ServiceName $ServiceName -Name $EdgeServerName |
	Add-AzureEndpoint -Name "HttpsIn" -Protocol "tcp" -PublicPort 443 -LocalPort 443 -LBSetName "IdentityPlusWebFarm" -ProbePort 80 -ProbeProtocol "http" -ProbePath "/" | 
	Update-AzureVM | Out-Null
					
# Set WinRmHTTPs communication information
$edgeServerWinRMUri = Get-AzureWinRMUri -ServiceName $serviceName -Name $EdgeServerName 
$option = New-PSSessionOption -SkipCACheck    

Invoke-Command -ConnectionUri $edgeServerWinRMUri.ToString() -Credential $credential `
    -SessionOption $option -ScriptBlock {
    #Get-WindowsFeature Web-* | Add-WindowsFeature
	Import-Module ServerManager
	# See Installing IIS 8.5 on Windows Server 2012 R2 (http://www.iis.net/learn/install/installing-iis-85/installing-iis-85-on-windows-server-2012-r2)
	Install-WindowsFeature NET-Framework-Core, AS-HTTP-Activation, NET-Framework-45-Features, Web-Mgmt-Console, Web-Asp-Net, Web-Asp-Net45, Web-Basic-Auth,  `
		Web-Client-Auth, Web-Digest-Auth, Web-Dir-Browsing, Web-Dyn-Compression, Web-Http-Errors, Web-Http-Logging, Web-Http-Redirect,  `
		Web-Http-Tracing, Web-ISAPI-Ext, Web-ISAPI-Filter, Web-Lgcy-Mgmt-Console, Web-Metabase, Web-Mgmt-Console, Web-Mgmt-Service,  `
		Web-Net-Ext, Web-Net-Ext45, Web-Request-Monitor, Web-Server, Web-Stat-Compression, Web-Static-Content, Web-Windows-Auth, Web-WMI,  `
		Windows-Identity-Foundation
			
    Configure-SMRemoting.exe -enable
    Restart-Computer -Force
}

Write-Verbose "Test lab setup completed." 


