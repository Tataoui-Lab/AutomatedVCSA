﻿#
# Author: Dominic Chan (dominic.chan@tataoui.com)
# Date: 2020-11-11
# Last Update: 2021-01-25
#
# Description:
# VCSA unattended installation with post installation tasks.
# - tested on VCSA 6.7
# 
# Powershell environment prerequisites:
# 1. PowerShell version: 5.1.14393.3866
# 2. PowerCLI Version: 12.1.0.16997582
#    Install-Module VMware.PowerCLI
# 3. PowerNSX version: 3.0.1174
#    Install-Module -Name PowerNSX -Confirm:$false -AllowClobber -Force
#    or 
#    $Branch="master";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { $wc = new-object Net.WebClient;$scr = try { $wc.DownloadString($url)} catch { if ( $_.exception.innerexception -match "(407)") { $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"; $wc.DownloadString($url) } else { throw $_ }}; $scr | iex } catch { throw $_ }
# 4. ImportExcel7.1.0
#    Install-Module -Name ImportExcel -RequiredVersion 7.1.0
#

Set-PowerCLIConfiguration -defaultviservermode Single -Scope Session -ParticipateInCEIP $false -Confirm:$false
#Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | out-null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -WebOperationTimeoutSeconds 600 -Confirm:$false | out-null
#
$ScriptPath = Split-Path $MyInvocation.MyCommand.Path
$DataSourcePath = "G:\Transfer\VCSA-NSX-Configure.xlsx" # Absolute path to Excel Worksheet as the data sources
$NSXSettingsPath = "G:\Transfer\NSX-Configure.xlsx" # to be deleted
#$DataSourcePath = "$ScriptPath\VMware.xlsx" # Relative path to Excel Workbook as data sources
$hostfile = "$env:windir\System32\drivers\etc\hosts"

Function Release-Ref ($ref) {
    ([System.Runtime.InteropServices.Marshal]::ReleaseComObject([System.__ComObject]$ref) -gt 0)
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

if (!(Test-Path $DataSourcePath))
{
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
    InitialDirectory = [Environment]::GetFolderPath('Desktop') 
    Filter = 'SpreadSheet (*.xlsx)|*.xlsx'
    }
    $null = $FileBrowser.ShowDialog()
    $DataSourcePath = $FileBrowser.FileName
}

# Get-VM | Export-Excel -Path $Path -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -ClearSheet -WorksheetName 'Deploy VM'
#$MgmtVCSAParameters = Import-Excel -Path $DataSourcePath -WorksheetName 'Mgmt-VCSA'

$DataSource = Read-Host -Prompt 'Using static preset inputs or import from Excel? (S/E)'

if ($DataSource -eq 'S') {
    $VIServer = 'esx02'
    $VIServerIP ='192.168.10.21'
    $VIUsername = 'root'
    $VIPassword = 'VMware1!'
    $DeploymentTarget = 'ESXI'
    $VCSAInstallerPath = 'D:\VMware\VMware-VCSA-all-6.7.0-15132721'
    $NSX_Mgr_OVA =  'D:\VMware\ova\VMware-NSX-Manager-6.4.9-17267008.ova'
    #$NSXTManagerOVA = 'D:\VMware\ova\VMware NSX-T Data Center 2.5.2.2\nsx-unified-appliance-2.5.2.2.0.17003656.ova'
    #$NSXTControllerOVA = 
    #$NSXTEdgeOVA = 'D:\VMware\ova\VMware NSX-T Data Center 2.5.2.2\nsx-edge-2.5.2.2.0.17003662.ova'
    
    # Nested ESXi VMs to deploy
    $NestedESXiHostnameToIPs = @{
        "ESX02" = "192.168.10.21"
#        "ESX01" = "192.168.10.20"
#        "ESX03" = "192.168.10.22"
#        "ESX04" = "192.168.10.23"
    }

    $VDSPortgroupAndVLAN = @{
        "Management Network" = "0"
        "Trunk Network" = "0-4094"
        "VM Network" = "0"
    }

    # VCSA Deployment Configuration
    $VCSAIPAddress = '192.168.10.223'
    $VCSAHostname = 'VCSA100.tataoui.com' # Change to IP if you don't have valid DNS
    # $VCSAHostname = $VCSAIPAddress
    $VCSADeploymentSize = 'tiny'
    $VCSADisplayName = 'VCSA100'
    $VCSAIPAddress = '192.168.10.32'
    $VCSAPrefix = '24'
    $VCSASSODomainName = 'vsphere.local'
    $VCSASSOSiteName = "Tataoui"
    $VCSASSOPassword = 'VMware1!'
    $VCSARootPassword = 'VMware1!'
    $VCSASSHEnable = 'true'

    # General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
    $VirtualSwitchType = 'VSS' # VSS or VDS
    $VMNetwork = 'VM Network'
    $VMNetmask = '255.255.255.0'
    $VMGateway = '192.168.10.2'
    $VMDNS = '192.168.30.2'
    $VMNTP = 'pool.ntp.org'
    $VMPassword = "VMware1!" # Password to Add ESXi Host to vCenter Cluster
    $VMDomain = 'tataoui.com'
    # Not Used
    # VMSyslog = '192.168.1.200'
    $VMDatastore = 'SSD_VM'

    # Name of new vSphere Datacenter/Cluster when VCSA is deployed
    $NewVCDatacenterName = 'Datacenter-HQ'
    $NewVCVSANClusterName = 'vSphere-Host-Cluster'

    # VDS / VLAN Configurations
    $DeployVDS = 1
    $VDSName = 'VDS-6.7'
    $VLANMGMTPortgroup = 'Management Network'
    $VLANVMPortgroup = 'VM Network'
    $VLANTrunkPortgroup = 'Trunk Network'

    # NSX Manager Configuration
    $DeployNSX = 0
    $NSX_Mgr_vCPU = "2" # Reconfigure NSX vCPU
    $NSX_Mgr_vMem = "8" # Reconfigure NSX vMEM (GB)
    $NSX_Mgr_Name = "nsx64-1"
    $NSX_Mgr_Hostname = "nsx64-1.tataoui.com"
    $NSX_Mgr_IPAddress = "172.30.0.250"
    $NSX_Mgr_Netmask = "255.255.255.0"
    $NSX_Mgr_Gateway = "172.30.0.1"
    $NSX_Mgr_SSHEnable = "true"
    $NSX_Mgr_CEIPEnable = "false"
    $NSX_Mgr_UIPassword = "VMw@re123!"
    $NSX_Mgr_CLIPassword = "VMw@re123!"

    # VDS / VXLAN Configurations
    $PrivateVXLANVMNetwork = "dv-private-network" # Existing Portgroup
    $VDSName = "VDS-6.7"
    $VXLANDVPortgroup = "VXLAN"
    $VXLANSubnet = "172.16.66."
    $VXLANNetmask = "255.255.255.0"

    # Advanced Configurations
    # Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
    $addHostByDnsName = 1
    
    # Enable deployment options
    $preCheck = 1 # Validate VCSA installer location
    $confirmDeployment = 1 # Show and validate deployment settings
    $deployVCSA = 1 # Enable VCSA installation
    $setupNewVC = 1 # Enable VCSA post installation
    $addESXiHostsToVC = 1 # Enable adding ESXi hosts to vCenter during deployment
    $configurevMotion = 1 # Enable vMotion during deployment

    $setupVXLAN = 0 # Setup VXLAN
    $configureNSX = 0 # Configure NSX
    # Enable verbose output to a new PowerShell Console. Thanks to suggestion by Christian Mohn
    $enableVerboseLoggingToNewShell = 0

    $configureConLib = 1 # Enable creation of Content Library
    $ConLibName = 'Repo' # Content Library repository name
    $ConLibDSName = 'SSD_VM' # Datastore for Content Library
    $ISOPath = 'F:\ISO' # Path to ISO files to upload (note it will upload ALL isos found in this folder)

    $strO365Username = 'dominic.chan@tataoui.com' # Office 365 username
    $strO365Password = 'Mayflower#0322' # Office 365 Password ##########################
    $strSMTPServer = 'smtp.office365.com' # SMTP Server
    $intSMTPPort = 587 # SMTP Server Port
    $strSendTo = 'dwchan69@gmail.com' # Email Recipient

} else {

    # Import NSX_Info from Master Spreadsheet
    $Excel = New-Object -COM "Excel.Application"
    $Excel.Visible = $False
    $WorkBook = $Excel.Workbooks.Open($DataSourcePath)

    $WorkSheetname = "Software Depot"
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $VCSAInstallerPath = $WorkSheet.Cells.Item(3, 2).Value()
    $NSX_Mgr_OVA       = $WorkSheet.Cells.Item(4, 2).Value()
    #$NSXTManagerOVA = $MgmtVCSAParameters.NSXT_Manager_Source
    #$NSXTControllerOVA = 
    #$NSXTEdgeOVA = $MgmtVCSAParameters.NSXT_Edge_Source
    $release = Release-Ref($WorkSheet)

    $WorkSheetname = "Email"
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $strO365Username = $WorkSheet.Cells.Item(2, 1).Value() # Office 365 username
    $strO365Password = $WorkSheet.Cells.Item(2, 2).Value() # Office 365 Password ##########################
    $strSMTPServer   = $WorkSheet.Cells.Item(2, 3).Value() # SMTP Server
    $intSMTPPort     = $WorkSheet.Cells.Item(2, 4).Value() # SMTP Server Port
    $strSendTo       = $WorkSheet.Cells.Item(2, 5).Value() # Email Recipient
    $release = Release-Ref($WorkSheet)

    $WorkSheetname = "VCSA Information"
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $VIServer          = $WorkSheet.Cells.Item(3, 1).Value()
    $VIServerIP        = $WorkSheet.Cells.Item(3, 2).Value()
    $VIUsername        = $WorkSheet.Cells.Item(3, 3).Value()
    $VIPassword        = $WorkSheet.Cells.Item(3, 4).Value()
    $DeploymentTarget  = $WorkSheet.Cells.Item(3, 5).Value()

    # Nested ESXi VMs to deploy
    $NestedESXiHostnameToIPs = @{
    "ESX02" = "192.168.10.21"
    }
    
    # Read in MgmtESXHosts as an array
    # $NestedESXiHostnameToIPs = $MgmtVCSAParameters.MgmtESXHosts.split(',') | foreach {$K,$V=$_.split('='); @{$K.trim()=$V}}
    
    # Read in MgmtESXHosts as hash
    # $NestedESXiHostnameToIPs = @{}
    # $MgmtVCSAParameters.MgmtESXHosts.split(',') | % {
    # $key,$value = $_.split('=')
    # $NestedESXiHostnameToIPs[$key] = $value
    # }

    # Not used yet
    $VDSPortgroupAndVLAN = @{
    "Management Network" = $WorkSheet.Cells.Item(10, 2).Value()
    "Trunk Network" = $WorkSheet.Cells.Item(10, 3).Value()
    "VM Network" = $WorkSheet.Cells.Item(10, 4).Value()
    }

    # VCSA Deployment Configuration
    $VCSAIPAddress      = $WorkSheet.Cells.Item(7, 1).Value()
    $VCSAHostname       = $WorkSheet.Cells.Item(7, 2).Value() #Change to IP if you don't have valid DNS
    # $VCSAHostname = $VCSAIPAddress
    $VCSADeploymentSize = $WorkSheet.Cells.Item(7, 3).Value()
    $VCSADisplayName    = $WorkSheet.Cells.Item(7, 4).Value()
    $VCSAPrefix         = $WorkSheet.Cells.Item(7, 5).Value()
    $VCSASSODomainName  = $WorkSheet.Cells.Item(7, 6).Value()
    $VCSASSOSiteName    = $WorkSheet.Cells.Item(7, 7).Value()
    $VCSASSOPassword    = $WorkSheet.Cells.Item(7, 8).Value()
    $VCSARootPassword   = $WorkSheet.Cells.Item(7, 9).Value()
    $VCSASSHEnable      = $WorkSheet.Cells.Item(7, 10).Value()

    # General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
    $VirtualSwitchType = $WorkSheet.Cells.Item(13, 1).Value()
    $VMNetwork         = $WorkSheet.Cells.Item(13, 2).Value()
    $VMNetmask         = $WorkSheet.Cells.Item(13, 3).Value()
    $VMGateway         = $WorkSheet.Cells.Item(13, 4).Value()
    $VMDNS             = $WorkSheet.Cells.Item(13, 5).Value()
    $VMNTP             = $WorkSheet.Cells.Item(13, 6).Value()
    $VMPassword        = $WorkSheet.Cells.Item(13, 7).Value() # Password to Add ESXi Host to vCenter Cluster
    $VMDomain          = $WorkSheet.Cells.Item(13, 8).Value() # used by NSX
    # $VMSyslog          = $WorkSheet.Cells.Item(13, 9).Value() # Not used
    $VMDatastore       = $WorkSheet.Cells.Item(13, 10).Value()

    # Name of new vSphere Datacenter/Cluster when VCSA is deployed
    $NewVCDatacenterName  = $WorkSheet.Cells.Item(17, 1).Value()
    $NewVCVSANClusterName = $WorkSheet.Cells.Item(17, 2).Value()

    # VDS / VLAN Configurations
    $DeployVDS          = $WorkSheet.Cells.Item(21, 1).Value()
    $VDSName            = $WorkSheet.Cells.Item(21, 2).Value()
    $VLANMGMTPortgroup  = $WorkSheet.Cells.Item(21, 3).Value()
    $VLANVMPortgroup    = $WorkSheet.Cells.Item(21, 4).Value()
    $VLANTrunkPortgroup = $WorkSheet.Cells.Item(21, 5).Value()

    # NSX Manager Configuration
    $DeployNSX             = $WorkSheet.Cells.Item(21, 6).Value()
    # VDS / VXLAN Configurations (Not used)
    $PrivateVXLANVMNetwork = $WorkSheet.Cells.Item(21, 7).Value() # Not used
    $VXLANDVPortgroup      = $WorkSheet.Cells.Item(21, 8).Value() # Not used
    $VXLANSubnet           = $WorkSheet.Cells.Item(21, 9).Value() # Not used
    $VXLANNetmask          = $WorkSheet.Cells.Item(21, 10).Value() # Not used

    # Enable deployment options
    $preCheck          = $WorkSheet.Cells.Item(25, 1).Value() # Validate VCSA installer location
    $confirmDeployment = $WorkSheet.Cells.Item(25, 2).Value() # Show and validate deployment settings
    $deployVCSA        = $WorkSheet.Cells.Item(25, 3).Value() # Enable VCSA installation
    $setupNewVC        = $WorkSheet.Cells.Item(25, 4).Value() # Enable VCSA post installation
    # Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
    $addHostByDnsName  = $WorkSheet.Cells.Item(25, 5).Value()
    $addESXiHostsToVC  = $WorkSheet.Cells.Item(25, 6).Value() # Enable adding ESXi hosts to vCenter during deployment
    $configurevMotion  = $WorkSheet.Cells.Item(25, 7).Value() # Enable vMotion during deployment
    $setupVXLAN        = $WorkSheet.Cells.Item(25, 8).Value() # Setup VXLAN
    $DeployNSX         = $WorkSheet.Cells.Item(25, 9).Value()
    $configureNSX      = $WorkSheet.Cells.Item(25, 10).Value() # Configure NSX
    # Enable verbose output to a new PowerShell Console. Thanks to suggestion by Christian Mohn
    $enableVerboseLoggingToNewShell = $WorkSheet.Cells.Item(25, 11).Value()

    $configureConLib = $WorkSheet.Cells.Item(29, 1).Value() # Enable creation of Content Library
    $ConLibName      = $WorkSheet.Cells.Item(29, 2).Value() # Content Library repository name
    $ConLibDSName    = $WorkSheet.Cells.Item(29, 3).Value() # Datastore for Content Library
    $ISOPath         = $WorkSheet.Cells.Item(29, 4).Value() # Path to ISO files to upload (note it will upload ALL isos found in this folder)
    $release = Release-Ref($WorkSheet)

    $WorkSheetname = "NSX Information"
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $NSX_MGR_Name      = $WorkSheet.Cells.Item(3, 1).Value()
    $NSX_MGR_Hostname  = $WorkSheet.Cells.Item(3, 2).Value()
    $NSX_MGR_IP        = $WorkSheet.Cells.Item(3, 3).Value()
    $NSX_MGR_Netmask   = $WorkSheet.Cells.Item(3, 4).Value()
    $NSX_MGR_Gateway   = $WorkSheet.Cells.Item(3, 5).Value()
    $NSX_MGR_DNSServer = $WorkSheet.Cells.Item(3, 6).Value() # $VMDNS
    $NSX_MGR_DNSDomain = $WorkSheet.Cells.Item(3, 7).Value() # $VMDomain
    $NSX_MGR_NTPServer = $WorkSheet.Cells.Item(3, 8).Value() # $VMNTP

    $NSX_MGR_CLI_Pass   = $WorkSheet.Cells.Item(6, 1).Value()
    $NSX_MGR_UI_Pass    = $WorkSheet.Cells.Item(6, 2).Value()
    $NSX_Mgr_SSHEnable  = $WorkSheet.Cells.Item(6, 3).Value()
    $NSX_Mgr_CEIPEnable = $WorkSheet.Cells.Item(6, 4).Value()
    $NSX_Mgr_vCPU       = $WorkSheet.Cells.Item(6, 5).Value()
    $NSX_Mgr_vMem       = $WorkSheet.Cells.Item(6, 6).Value()

    $NSX_VC_IP        = $WorkSheet.Cells.Item(10, 1).Value()
    $NSX_VC_Username  = $WorkSheet.Cells.Item(10, 2).Value()
    $NSX_VC_Password  = $WorkSheet.Cells.Item(10, 3).Value()
    $NSX_VC_Cluster   = $WorkSheet.Cells.Item(10, 4).Value()
    $NSX_VC_Network   = $WorkSheet.Cells.Item(10, 5).Value()
    $NSX_VC_Datastore = $WorkSheet.Cells.Item(10, 6).Value()
    $NSX_VC_Folder    = $WorkSheet.Cells.Item(10, 7).Value()
    $NSX_License      = $WorkSheet.Cells.Item(10, 8).Value()
    $NSX_Mgr_Network  = $VLANMGMTPortgroup # or $NSX_VC_Network

    $NSX_Controllers_Cluster   = $WorkSheet.Cells.Item(14, 1).Value()
    $NSX_Controllers_Datastore = $WorkSheet.Cells.Item(14, 2).Value()
    $NSX_Controllers_PortGroup = $WorkSheet.Cells.Item(14, 3).Value()
    $NSX_Controllers_Password  = $WorkSheet.Cells.Item(14, 4).Value()
    $NSX_Controllers_Amount    = [int]$WorkSheet.Cells.Item(14, 5).Value()

    $NSX_VXLAN_Cluster               = $WorkSheet.Cells.Item(18, 1).Value()
    $NSX_VXLAN_DSwitch               = $WorkSheet.Cells.Item(18, 2).Value()
    $NSX_VXLAN_VLANID                = $WorkSheet.Cells.Item(18, 3).Value()
    $NSX_VXLAN_VTEP_Count            = $WorkSheet.Cells.Item(18, 4).Value()
    $NSX_VXLAN_Segment_ID_Begin      = [int]$WorkSheet.Cells.Item(18, 5).Value()
    $NSX_VXLAN_Segment_ID_End        = [int]$WorkSheet.Cells.Item(18, 6).Value()
    $NSX_VXLAN_Multicast_Range_Begin = $WorkSheet.Cells.Item(18, 7).Value()
    $NSX_VXLAN_Multicast_Range_End   = $WorkSheet.Cells.Item(18, 8).Value()

    $NSX_VXLAN_Failover_Mode = $WorkSheet.Cells.Item(21, 1).Value()
    $NSX_VXLAN_MTU_Size      = $WorkSheet.Cells.Item(21, 2).Value()

    $NSX_VXLAN_TZ_Name = $WorkSheet.Cells.Item(25, 1).Value()
    $NSX_VXLAN_TZ_Mode = $WorkSheet.Cells.Item(25, 2).Value()
    $release = Release-Ref($WorkSheet)

    $WorkSheetname = "IP Pools"
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $NSX_Controllers_IP_Pool_Name      = $WorkSheet.Cells.Item(2, 2).Value()
    $NSX_Controllers_IP_Pool_Gateway   = $WorkSheet.Cells.Item(2, 3).Value()
    $NSX_Controllers_IP_Pool_Prefix    = $WorkSheet.Cells.Item(2, 4).Value()
    $NSX_Controllers_IP_Pool_DNS1      = $WorkSheet.Cells.Item(2, 5).Value()
    $NSX_Controllers_IP_Pool_DNS2      = $WorkSheet.Cells.Item(2, 6).Value()
    $NSX_Controllers_IP_Pool_DNSSuffix = $WorkSheet.Cells.Item(2, 7).Value()
    $NSX_Controllers_IP_Pool_Start     = $WorkSheet.Cells.Item(2, 8).Value()
    $NSX_Controllers_IP_Pool_End       = $WorkSheet.Cells.Item(2, 9).Value()

    $NSX_VXLAN_IP_Pool_Name      = $WorkSheet.Cells.Item(3, 2).Value()
    $NSX_VXLAN_IP_Pool_Gateway   = $WorkSheet.Cells.Item(3, 3).Value()
    $NSX_VXLAN_IP_Pool_Prefix    = $WorkSheet.Cells.Item(3, 4).Value()
    $NSX_VXLAN_IP_Pool_DNS1      = $WorkSheet.Cells.Item(3, 5).Value()
    $NSX_VXLAN_IP_Pool_DNS2      = $WorkSheet.Cells.Item(3, 6).Value()
    $NSX_VXLAN_IP_Pool_DNSSuffix = $WorkSheet.Cells.Item(3, 7).Value()
    $NSX_VXLAN_IP_Pool_Start     = $WorkSheet.Cells.Item(3, 8).Value()
    $NSX_VXLAN_IP_Pool_End       = $WorkSheet.Cells.Item(3, 9).Value()
    $release = Release-Ref($WorkSheet)
}

#### DO NOT EDIT BEYOND HERE ####
#$VIServerShort = $VIServer.Substring(0,$VIServer.IndexOf("."))
$verboseLogFile = "vsphere67-Physical-Manage-VCSA-Deployment.log"
$vSphereVersion = "6.7"
# Not used - $deploymentType
$deploymentType = "Standard"
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$depotServer = "https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml"

$vcsaSize2MemoryStorageMap = @{
"tiny"=@{"cpu"="2";"mem"="10";"disk"="250"};
"small"=@{"cpu"="4";"mem"="16";"disk"="290"};
"medium"=@{"cpu"="8";"mem"="24";"disk"="425"};
"large"=@{"cpu"="16";"mem"="32";"disk"="640"};
"xlarge"=@{"cpu"="24";"mem"="48";"disk"="980"}
}

$nsxStorageMap = @{
"manager"="160";
"controller"="120";
"edge"="120"
}

$esxiTotalCPU = 0
$vcsaTotalCPU = 0
$nsxTotalCPU = 0
$esxiTotalMemory = 0
$vcsaTotalMemory = 0
$nsxTotalMemory = 0
$esxiTotStorage = 0
$vcsaTotalStorage = 0
$nsxTotalStorage = 0

$strO365Password = ConvertTo-SecureString -string $strO365Password -AsPlainText -Force
$oOffice365credential = New-Object System.Management.Automation.PSCredential -argumentlist $strO365Username, $strO365Password
$strEmailSubject = "VMware Physical Manage VCSA (vCenter Server Appliance) Deployment Log - $VCSAHostname"

$StartTime = Get-Date
# Load in external MAC Learn function
. $ScriptPath'MacLearn.ps1'

Function Get-SSLThumbprint256 {
    param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]
    [Alias('FullName')]
    [String]$URL
    )

add-type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
            public class IDontCarePolicy : ICertificatePolicy {
            public IDontCarePolicy() {}
            public bool CheckValidationResult(
                ServicePoint sPoint, X509Certificate cert,
                WebRequest wRequest, int certProb) {
                return true;
            }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = new-object IDontCarePolicy

    # Need to connect using simple GET operation for this to work
    Invoke-RestMethod -Uri $URL -Method Get | Out-Null

    $ENDPOINT_REQUEST = [System.Net.Webrequest]::Create("$URL")
    $CERT = $ENDPOINT_REQUEST.ServicePoint.Certificate
    # https://stackoverflow.com/a/22251597
    $BYTES = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    Set-content -value $BYTES -encoding byte -path $ENV:TMP\cert-temp
    $SSL_THUMBPRINT = (Get-FileHash -Path $ENV:TMP\cert-temp -Algorithm SHA256).Hash
    return $SSL_THUMBPRINT -replace '(..(?!$))','$1:'
}

Function Set-VMKeystrokes {
    <#
        Please see http://www.virtuallyghetto.com/2017/09/automating-vm-keystrokes-using-the-vsphere-api-powercli.html for more details
    #>
    param(
        [Parameter(Mandatory=$true)][String]$VMName,
        [Parameter(Mandatory=$true)][String]$StringInput,
        [Parameter(Mandatory=$false)][Boolean]$ReturnCarriage,
        [Parameter(Mandatory=$false)][Boolean]$DebugOn
    )

    # Map subset of USB HID keyboard scancodes
    # https://gist.github.com/MightyPork/6da26e382a7ad91b5496ee55fdc73db2
    $hidCharacterMap = @{
        "a"="0x04";
        "b"="0x05";
        "c"="0x06";
        "d"="0x07";
        "e"="0x08";
        "f"="0x09";
        "g"="0x0a";
        "h"="0x0b";
        "i"="0x0c";
        "j"="0x0d";
        "k"="0x0e";
        "l"="0x0f";
        "m"="0x10";
        "n"="0x11";
        "o"="0x12";
        "p"="0x13";
        "q"="0x14";
        "r"="0x15";
        "s"="0x16";
        "t"="0x17";
        "u"="0x18";
        "v"="0x19";
        "w"="0x1a";
        "x"="0x1b";
        "y"="0x1c";
        "z"="0x1d";
        "1"="0x1e";
        "2"="0x1f";
        "3"="0x20";
        "4"="0x21";
        "5"="0x22";
        "6"="0x23";
        "7"="0x24";
        "8"="0x25";
        "9"="0x26";
        "0"="0x27";
        "!"="0x1e";
        "@"="0x1f";
        "#"="0x20";
        "$"="0x21";
        "%"="0x22";
        "^"="0x23";
        "&"="0x24";
        "*"="0x25";
        "("="0x26";
        ")"="0x27";
        "_"="0x2d";
        "+"="0x2e";
        "{"="0x2f";
        "}"="0x30";
        "|"="0x31";
        ":"="0x33";
        "`""="0x34";
        "~"="0x35";
        "<"="0x36";
        ">"="0x37";
        "?"="0x38";
        "-"="0x2d";
        "="="0x2e";
        "["="0x2f";
        "]"="0x30";
        "\"="0x31";
        "`;"="0x33";
        "`'"="0x34";
        ","="0x36";
        "."="0x37";
        "/"="0x38";
        " "="0x2c";
    }

    $vm = Get-View -ViewType VirtualMachine -Filter @{"Name"=$VMName}

    # Verify we have a VM or fail
    if(!$vm) {
        Write-host "Unable to find VM $VMName"
        return
    }

    $hidCodesEvents = @()
    foreach($character in $StringInput.ToCharArray()) {
        # Check to see if we've mapped the character to HID code
        if($hidCharacterMap.ContainsKey([string]$character)) {
            $hidCode = $hidCharacterMap[[string]$character]

            $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent

            # Add leftShift modifer for capital letters and/or special characters
            if( ($character -cmatch "[A-Z]") -or ($character -match "[!|@|#|$|%|^|&|(|)|_|+|{|}|||:|~|<|>|?]") ) {
                $modifer = New-Object Vmware.Vim.UsbScanCodeSpecModifierType
                $modifer.LeftShift = $true
                $tmp.Modifiers = $modifer
            }

            # Convert to expected HID code format
            $hidCodeHexToInt = [Convert]::ToInt64($hidCode,"16")
            $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007

            $tmp.UsbHidCode = $hidCodeValue
            $hidCodesEvents+=$tmp
            } else {
                My-Logger Write-Host "The following character `"$character`" has not been mapped, you will need to manually process this character"
                break
            }
        }

        # Add return carriage to the end of the string input (useful for logins or executing commands)
        if($ReturnCarriage) {
            # Convert return carriage to HID code format
            $hidCodeHexToInt = [Convert]::ToInt64("0x28","16")
            $hidCodeValue = ($hidCodeHexToInt -shl 16) + 7

            $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent
            $tmp.UsbHidCode = $hidCodeValue
            $hidCodesEvents+=$tmp
        }

        # Call API to send keystrokes to VM
        $spec = New-Object Vmware.Vim.UsbScanCodeSpec
        $spec.KeyEvents = $hidCodesEvents
        $results = $vm.PutUsbScanCodes($spec)
}

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )
    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"
    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

Function URL-Check([string] $url) {
    $isWorking = $true
    try {
        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.UseDefaultCredentials = $true

        $response = $request.GetResponse()
        $httpStatus = $response.StatusCode

        $isWorking = ($httpStatus -eq "OK")
    }
    catch {
        $isWorking = $false
    }
    return $isWorking
}

# Confirm and load PowerCLI
if (!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
    if (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI' ) {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI'
    } else {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware vSphere PowerCLI'
    }
    .(join-path -path (Get-ItemProperty  $Regkey).InstallPath -childpath 'Scripts\Initialize-PowerCLIEnvironment.ps1')
}
if (!(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue)) {
    Write-Host "VMware modules not loaded/unable to load ..." -ForegroundColor Red
    Exit
}

# Load PowerNSX
Import-Module -Name '.\PowerNSX.psm1' -ErrorAction SilentlyContinue -DisableNameChecking

# Check if the excel exists
if(!(Test-Path $NSXSettingsPath)) {
  Write-Host "Settings Excel file '$NSXSettingsPath' not found!" -ForegroundColor "red"
  Exit
}

# Import RestAPI functions for NSX
. $ScriptPath'Install-NSX-Functions.ps1'

if($preCheck -eq 'true') {
    if(!(Test-Path $VCSAInstallerPath)) {
        Write-Host -ForegroundColor Red "`nUnable to find $VCSAInstallerPath ...`nexiting"
        exit
    }
}

if($DeployNSX -eq 'true') {
    if(!(Test-Path $NSX_Mgr_OVA)) {
        Write-Host -ForegroundColor Red "`nUnable to find $NSX_Mgr_OVA ...`nexiting"
        exit
    }

    if(-not (Get-Module -Name "PowerNSX")) {
        Write-Host -ForegroundColor Red "`nPowerNSX Module is not loaded, please install and load PowerNSX before running script ...`nexiting"
        #exit
    }
}

if($confirmDeployment -eq 'true') {
    Write-Host -ForegroundColor Red "`nPlease confirm the following configuration will be deploy:`n"

    Write-Host -ForegroundColor Yellow "---- Physical Manage VCSA Automated Deployment Configuration ----"
    Write-Host -ForegroundColor Yellow "---------------- Physical vCenter Server (VCSA) -----------------"
    Write-Host -NoNewline -ForegroundColor Green "Destination Target (ESXi / VCSA): "
    Write-Host -ForegroundColor White $DeploymentTarget
    Write-Host -NoNewline -ForegroundColor Green "Deployment Type: "
    Write-Host -ForegroundColor White $deploymentType
    Write-Host -NoNewline -ForegroundColor Green "vSphere Version: "
    Write-Host -ForegroundColor White  "vSphere $vSphereVersion"
    Write-Host -NoNewline -ForegroundColor Green "VCSA Image Path: "
    Write-Host -ForegroundColor White $VCSAInstallerPath

    if($DeployNSX -eq 'true') {
        Write-Host -NoNewline -ForegroundColor Green "NSX Image Path: "
        Write-Host -ForegroundColor White $NSX_Mgr_OVA
    }

    if($DeploymentTarget -eq "ESXI") {
        Write-Host -ForegroundColor Yellow "`n--------- Physical ESXi Deployment Target Configuration ---------"
        Write-Host -NoNewline -ForegroundColor Green "ESXi Host: "
    } else {
        Write-Host -ForegroundColor Yellow "`n--------- vCenter Server Deployment Target Configuration --------"
        Write-Host -NoNewline -ForegroundColor Green "vCenter Server Address: "
    }

    Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "ESXi Username: "
    Write-Host -ForegroundColor White $VIUsername
    Write-Host -NoNewline -ForegroundColor Green "VCSA VM Network: "
    Write-Host -ForegroundColor White $VMNetwork

    if($DeployNSX -eq 'true' -and $setupVXLAN -eq 'true') {
        Write-Host -NoNewline -ForegroundColor Green "Private VXLAN VM Network: "
        Write-Host -ForegroundColor White $PrivateVXLANVMNetwork
    }

    Write-Host -NoNewline -ForegroundColor Green "VCSA Datastore: "
    Write-Host -ForegroundColor White $VMDatastore

    if($DeploymentTarget -eq "VCENTER") {
        Write-Host -NoNewline -ForegroundColor Green "VM Cluster: "
        Write-Host -ForegroundColor White $VMCluster
    }

    Write-Host -NoNewline -ForegroundColor Green "DNS use by VCSA: "
    Write-Host -ForegroundColor White $VMDNS
    Write-Host -NoNewline -ForegroundColor Green "NTP use by VCSA: "
    Write-Host -ForegroundColor White $VMNTP
    Write-Host -NoNewline -ForegroundColor Green "Syslog use by VCSA: "
    Write-Host -ForegroundColor White $VMSyslog

    Write-Host -ForegroundColor Yellow "`n------------------ Manage VCSA Configuration --------------------"
    Write-Host -NoNewline -ForegroundColor Green "VCSA Deployment Size: "
    Write-Host -ForegroundColor White $VCSADeploymentSize
    Write-Host -NoNewline -ForegroundColor Green "VCSA SSO Domain: "
    Write-Host -ForegroundColor White $VCSASSODomainName
    Write-Host -NoNewline -ForegroundColor Green "VCSA SSO Password: "
    Write-Host -ForegroundColor White $VCSASSOPassword
    Write-Host -NoNewline -ForegroundColor Green "VCSA Root Password: "
    Write-Host -ForegroundColor White $VCSARootPassword
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH on VCSA: "
    Write-Host -ForegroundColor White $VCSASSHEnable
    Write-Host -NoNewline -ForegroundColor Green "VCSA Hostname: "
    Write-Host -ForegroundColor White $VCSAHostname
    Write-Host -NoNewline -ForegroundColor Green "VCSA IP: "
    Write-Host -ForegroundColor White $VCSAIPAddress
    Write-Host -NoNewline -ForegroundColor Green "VCSA Netmask "
    Write-Host -ForegroundColor White $VMNetmask
    Write-Host -NoNewline -ForegroundColor Green "VCSA Gateway: "
    Write-Host -ForegroundColor White $VMGateway
    Write-Host -NoNewline -ForegroundColor Green "VCSA Datacenter Name: "
    Write-Host -ForegroundColor White $NewVCDatacenterName
    Write-Host -NoNewline -ForegroundColor Green "VCSA Cluster Name: "
    Write-Host -ForegroundColor White $NewVCVSANClusterName

    if($DeployVDS -eq 'true') {
        Write-Host -ForegroundColor Yellow "`n----------------------- VDS Configuration -----------------------"
        Write-Host -NoNewline -ForegroundColor Green "VDS Name: "
        Write-Host -ForegroundColor White $VDSName
        Write-Host -NoNewline -ForegroundColor Green "Management Portgroup: "
        Write-Host -ForegroundColor White $VLANMGMTPortgroup
        Write-Host -NoNewline -ForegroundColor Green "Virtual Machine Portgroup: "
        Write-Host -ForegroundColor White $VLANVMPortgroup
        Write-Host -NoNewline -ForegroundColor Green "Trunk Portgroup: "
        Write-Host -ForegroundColor White $VLANTrunkPortgroup
    }

    if($DeployNSX -eq 'true' -and $setupVXLAN -eq 'true') {
        Write-Host -ForegroundColor Yellow "`n------------------- VDS VXLAN Configuration ---------------------"
        Write-Host -NoNewline -ForegroundColor Green "VDS Name: "
        Write-Host -ForegroundColor White $VDSName
        Write-Host -NoNewline -ForegroundColor Green "VXLAN Portgroup Name: "
        Write-Host -ForegroundColor White $VXLANDVPortgroup
        Write-Host -NoNewline -ForegroundColor Green "VXLAN Subnet: "
        Write-Host -ForegroundColor White $VXLANSubnet
        Write-Host -NoNewline -ForegroundColor Green "VXLAN Netmask: "
        Write-Host -ForegroundColor White $VXLANNetmask
    }

    if($configureConLib -eq 'true') {
        Write-Host -ForegroundColor Yellow "`n---------------- Content Library Configuration ------------------"
        Write-Host -NoNewline -ForegroundColor Green "Repository Name: "
        Write-Host -ForegroundColor White $ConLibName
        Write-Host -NoNewline -ForegroundColor Green "Content Library Datastore: "
        Write-Host -ForegroundColor White $ConLibDSName
        Write-Host -NoNewline -ForegroundColor Green "Path to upload ISO: "
        Write-Host -ForegroundColor White $ISOPath
    }

    if($DeployNSX -eq 'true') {
        Write-Host -ForegroundColor Yellow "`n----------------------- NSX Configuration -----------------------"
        Write-Host -NoNewline -ForegroundColor Green "NSX number of vCPU: "
        Write-Host -ForegroundColor White $NSX_Mgr_vCPU
        Write-Host -NoNewline -ForegroundColor Green "NSX Memory (GB): "
        Write-Host -ForegroundColor White $NSX_Mgr_vMem
        Write-Host -NoNewline -ForegroundColor Green "NSX Hostname: "
        Write-Host -ForegroundColor White $NSX_Mgr_Hostname
        Write-Host -NoNewline -ForegroundColor Green "NSX IP Address: "
        Write-Host -ForegroundColor White $NSX_Mgr_IP
        Write-Host -NoNewline -ForegroundColor Green "NSX Netmask: "
        Write-Host -ForegroundColor White $NSX_Mgr_Netmask
        Write-Host -NoNewline -ForegroundColor Green "NSX Gateway: "
        Write-Host -ForegroundColor White $NSX_Mgr_Gateway
        Write-Host -NoNewline -ForegroundColor Green "NSX Enable SSH: "
        Write-Host -ForegroundColor White $NSX_Mgr_SSHEnable
        Write-Host -NoNewline -ForegroundColor Green "NSX Enable CEIP: "
        Write-Host -ForegroundColor White $NSX_Mgr_CEIPEnable
        Write-Host -NoNewline -ForegroundColor Green "NSX UI Password: "
        Write-Host -ForegroundColor White $NSX_Mgr_UI_Pass
        Write-Host -NoNewline -ForegroundColor Green "NSX CLI Password: "
        Write-Host -ForegroundColor White $NSX_Mgr_CLI_Pass
    }

    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
    $ESXHost = Get-VMHost -Name $VIServer
    $esxiTotalCPU = $ESXHost.NumCpu
    $esxiTotalMemory = [math]::Round($ESXHost.MemoryTotalGB,0)
    $esxiTotalStorage = [math]::Round((Get-Datastore -Name $VMDatastore).FreeSpaceGB,0)

    #$esxiTotalCPU = $NestedESXiHostnameToIPs.count * [int]$NestedESXivCPU
    #$esxiTotalMemory = $NestedESXiHostnameToIPs.count * [int]$NestedESXivMEM
    #$esxiTotalStorage = ($NestedESXiHostnameToIPs.count * [int]$NestedESXiCachingvDisk) + ($NestedESXiHostnameToIPs.count * [int]$NestedESXiCapacityvDisk)
    $vcsaTotalCPU = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.cpu
    $vcsaTotalMemory = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.mem
    $vcsaTotalStorage = $vcsaSize2MemoryStorageMap.$VCSADeploymentSize.disk
    $nsxTotalCPU = [int]$NSX_Mgr_vCPU
    $nsxTotalMemory = [int]$NSX_Mgr_vMem
    $nsxTotalStorage = 60

    Write-Host -ForegroundColor Yellow "`n--------------------------- Available Resource ----------------------------"
    Write-Host -NoNewline -ForegroundColor Green "ESXi Total CPU: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " ESXi Total Memory: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "ESXi Assigned Storage: "
    Write-Host -ForegroundColor White $esxiTotalStorage "GB"
    Write-Host -ForegroundColor Yellow "`n-------------------------- Resource Requirements --------------------------"
    Write-Host -NoNewline -ForegroundColor Green "VCSA VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalCPU
    Write-Host -NoNewline -ForegroundColor Green "     VCSA VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "    VCSA VM Storage: "
    Write-Host -ForegroundColor White $vcsaTotalStorage "GB"
    if($DeployNSX -eq 'true') {
        Write-Host -NoNewline -ForegroundColor Green "NSX VM CPU: "
        Write-Host -NoNewline -ForegroundColor White $nsxTotalCPU
        Write-Host -NoNewline -ForegroundColor Green "      NSX Memory: "
        Write-Host -NoNewline -ForegroundColor White $nsxTotalMemory "GB "
        Write-Host -NoNewline -ForegroundColor Green "         NSX VM Storage: "
        Write-Host -ForegroundColor White $nsxTotalStorage "GB"
    }
    #Write-Host -ForegroundColor Yellow "-----------------------------------------------------------------"
    #Write-Host -NoNewline -ForegroundColor Green "Total CPU: "
    #Write-Host -ForegroundColor White ($esxiTotalCPU + $vcsaTotalCPU + $nsxTotalCPU)
    #Write-Host -NoNewline -ForegroundColor Green "Total Memory: "
    #Write-Host -ForegroundColor White ($esxiTotalMemory + $vcsaTotalMemory + $nsxTotalMemory) "GB"
    #Write-Host -NoNewline -ForegroundColor Green "Total Storage: "
    #Write-Host -ForegroundColor White ($esxiTotalStorage + $vcsaTotalStorage + $nsxTotalStorage) "GB"

    Write-Host -ForegroundColor Red "`nWould you like to proceed with this deployment?`n"
    $answer = Read-Host -Prompt "Do you accept (Y or N)"
    if($answer -ne "Y" -or $answer -ne "y") {
        exit
    }
    Clear-Host
    # Set temporary host record on deployment laptop/desktop
    "$VIServerIP  $VIServer" | Add-Content -PassThru $hostfile
}

My-Logger "Connecting to $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

$ESXHost = Get-VMHost -Name $VIServer
$ESXState = $ESXHost.ConnectionState
if($ESXState -eq "Maintenance") {
    My-Logger "Host '$VIServer' is in Maintenance Mode."
    $maintenace = Read-Host -Prompt "Remove host '$VIServer' out of maintenace mode? (Y or N)"
    if($maintenace -eq "Y" -or $maintenace -eq "y") {
        Get-VMHost -Name $VIServer | Set-VMHost -State Connected
    } else {
        break
    }
}

if($VirtualSwitchType -eq "VSS") {
    $network = Get-VirtualPortGroup -Server $viConnection -Name $VMNetwork
} else {
    $network = Get-VDPortgroup -Server $viConnection -Name $VMNetwork
}

    Write-Host "Vritual Switch type set to -" $VirtualSwitchType
    write-host "Deploying to the following portgroup -" $network
    write-host "Datastore set to -" $VMDatastore
    write-host "DeployDVS is set to"$DeployVDS

if($deployVCSA -eq 'true') {
    if($DeploymentTarget -eq "ESXI") {
        # Deploy using the VCSA CLI Installer
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_ESXi.json") | convertfrom-json
        $config.new_vcsa.esxi.hostname = $VIServer
        $config.new_vcsa.esxi.username = $VIUsername
        $config.new_vcsa.esxi.password = $VIPassword
        $config.new_vcsa.esxi.deployment_network = $VMNetwork
        $config.new_vcsa.esxi.datastore = $datastore
        $config.new_vcsa.appliance.thin_disk_mode = $true
        $config.new_vcsa.appliance.deployment_option = $VCSADeploymentSize
        $config.new_vcsa.appliance.name = $VCSADisplayName
        $config.new_vcsa.network.ip_family = "ipv4"
        $config.new_vcsa.network.mode = "static"
        $config.new_vcsa.network.ip = $VCSAIPAddress
        $config.new_vcsa.network.dns_servers[0] = $VMDNS
        $config.new_vcsa.network.prefix = $VCSAPrefix
        $config.new_vcsa.network.gateway = $VMGateway
        $config.new_vcsa.network.system_name = $VCSAHostname
        $config.new_vcsa.os.password = $VCSARootPassword
        if($VCSASSHEnable -eq 'true') {
            $VCSASSHEnableVar = $true
        } else {
            $VCSASSHEnableVar = $false
        }
        $config.new_vcsa.os.ntp_servers = $VMNTP
        $config.new_vcsa.os.ssh_enable = $VCSASSHEnableVar
        $config.new_vcsa.sso.password = $VCSASSOPassword
        $config.new_vcsa.sso.domain_name = $VCSASSODomainName

        My-Logger "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

        if($enableVerboseLoggingToNewShell -eq 'true') {
            My-Logger "Spawning new PowerShell Console for detailed verbose output ..."
            Start-process powershell.exe -argument "-nologo -noprofile -executionpolicy bypass -command Get-Content $verboseLogFile -Tail 2 -Wait"
        }

        My-Logger "Deploying VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile

    } else {
        # Deploy using the VCSA CLI Installer
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_VC.json") | convertfrom-json
        $config.new_vcsa.vc.hostname = $VIServer
        $config.new_vcsa.vc.username = $VIUsername
        $config.new_vcsa.vc.password = $VIPassword
        $config.new_vcsa.vc.deployment_network = $VMNetwork
        $config.new_vcsa.vc.datastore = $datastore
        $config.new_vcsa.vc.datacenter = $datacenter.name

        $config.new_vcsa.appliance.thin_disk_mode = $true
        $config.new_vcsa.appliance.deployment_option = $VCSADeploymentSize
        $config.new_vcsa.appliance.name = $VCSADisplayName
        $config.new_vcsa.network.ip_family = "ipv4"
        $config.new_vcsa.network.mode = "static"
        $config.new_vcsa.network.ip = $VCSAIPAddress
        $config.new_vcsa.network.dns_servers[0] = $VMDNS
        $config.new_vcsa.network.prefix = $VCSAPrefix
        $config.new_vcsa.network.gateway = $VMGateway
        $config.new_vcsa.network.system_name = $VCSAHostname
        $config.new_vcsa.os.password = $VCSARootPassword
        if($VCSASSHEnable -eq "true") {
            $VCSASSHEnableVar = $true
        } else {
            $VCSASSHEnableVar = $false
        }
        $config.new_vcsa.os.ntp_servers = $VMNTP
        $config.new_vcsa.os.ssh_enable = $VCSASSHEnableVar
        $config.new_vcsa.sso.password = $VCSASSOPassword
        $config.new_vcsa.sso.domain_name = $VCSASSODomainName

        My-Logger "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

        if($enableVerboseLoggingToNewShell -eq 1) {
            My-Logger "Spawning new PowerShell Console for detailed verbose output ..."
            Start-process powershell.exe -argument "-nologo -noprofile -executionpolicy bypass -command Get-Content $verboseLogFile -Tail 2 -Wait"
        }

        My-Logger "Deploying the VCSA ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile
    }
}

My-Logger "Disconnecting from $VIServer ..."
Disconnect-VIServer $viConnection -Confirm:$false

# Remove earlier temporary host record on deployment laptop/desktop
(Get-Content $hostfile) -notmatch $VIServer | Set-Content $hostfile

if($setupNewVC -eq 'true') {
    My-Logger "Connecting to the new VCSA - $VCSADisplayName ..."
    Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false
    $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

    My-Logger "Creating Datacenter - '$NewVCDatacenterName' ..."
    New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile
    
    My-Logger "Creating Cluster - '$NewVCVSANClusterName' ..."
    New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled | Out-File -Append -LiteralPath $verboseLogFile

    if($addESXiHostsToVC -eq 'true') {
        $i = 0
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value
            #$VMName = $NestedESXiHostnameToIPs[$i].Keys
            #$VMIPAddress = $NestedESXiHostnameToIPs[$i].Values
            $targetVMHost = $VMIPAddress
            if($addHostByDnsName -eq 'true') {
                $targetVMHost = $VMName
                $targetVMHost = 'esx02.tataoui.com' # this worked with DNS set to 192.168.30.2   
            }
            My-Logger "Adding ESXi host '$targetVMHost' to Cluster - $NewVCVSANClusterName ..."
            Add-VMHost -Server $vc -Name $targetVMHost -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Force | Out-File -Append -LiteralPath $verboseLogFile
        $i++
        }
    }
    
    if($DeployVDS -eq 'true') {
        # Create VDS switch
        My-Logger "Creating VDS - $VDSName ..."
        $vds = New-VDSwitch -Server $vc -Name $VDSName -Location (Get-Datacenter -Name $NewVCDatacenterName) -LinkDiscoveryProtocol LLDP -LinkDiscoveryProtocolOperation Listen -MaxPorts 128 -Version 6.6.0 -MTU 9000 -NumUplinkPorts 2
        My-Logger "Enable Network IO Control on VDS - $VDSName ..."
        (Get-VDSwitch $VDSName | Get-View).EnableNetworkResourceManagement($true)
        # Create DVPortgroup
        My-Logger "Creating new DVPortgroup '$VLANMGMTPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANMGMTPortgroup -Vds $vds -NumPorts 24 -PortBinding Ephemeral
        My-Logger "Creating new DVPortgroup '$VLANVMPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANVMPortgroup -Vds $vds -NumPorts 24 -PortBinding Static
        My-Logger "Creating new DVPortgroup '$VLANTrunkPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANTrunkPortgroup -Vds $vds -NumPorts 24 -VlanTrunkRange 0-4094 -PortBinding Static

        if($DeployNSX -eq 'true') {
            My-Logger "Creating new VXLAN DVPortgroup - $VXLANDVPortgroup ..."
            New-VDPortgroup -Server $vc -Name $VXLANDVPortgroup -Vds $vds -NumPorts 24 -VlanId 11 -PortBinding Static
        }

        # Add ESXi host to VDS
        $vmhosts = Get-Cluster -Server $vc -Name $NewVCVSANClusterName | Get-VMHost
        foreach ($vmhost in $vmhosts) {
            $vmhostname = $vmhost.name
            
            # Add ESXi host to VDS
            My-Logger "Adding $vmhostname to VDS $VDSName..."
            Add-VDSwitchVMHost -Server $vc -VDSwitch $vds -VMHost $vmhost | Out-File -Append -LiteralPath $verboseLogFile
            
            # Adding Physical NIC (vmnic1) to VDS
            My-Logger "Adding vmnic1 to VDS $VDSName..."
            # https://vbombarded.wordpress.com/2015/01/29/migrate-esxi-host-physical-adapters-to-specific-dvuplink-port/
            $uplinks = $vmhost | Get-VDSwitch | Get-VDPort -Uplink | where {$_.ProxyHost -like $vmhost.Name}
            $config = New-Object VMware.Vim.HostNetworkConfig
            $config.proxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
            $config.proxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
            $config.proxySwitch[0].changeOperation = "edit"
            $config.proxySwitch[0].uuid = $vds.Key
            $config.proxySwitch[0].spec = New-Object VMware.Vim.HostProxySwitchSpec
            $config.proxySwitch[0].spec.backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
            $config.proxySwitch[0].spec.backing.pnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
            $config.proxySwitch[0].spec.backing.pnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
            $config.proxySwitch[0].spec.backing.pnicSpec[0].pnicDevice = "vmnic1"
            $config.proxySwitch[0].spec.backing.pnicSpec[0].uplinkPortKey = ($uplinks | where {$_.Name -eq "dvUplink2"}).key
            $_this = Get-View (Get-View $vmhost).ConfigManager.NetworkSystem
            $_this.UpdateNetworkConfig($config, "modify")
            #
            # reserved and did work $pNIC = $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
            # $pNIC= $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1, vmnic2
            # reserved and did work Add-VDSwitchPhysicalNetworkAdapter -Server $vc -DistributedSwitch $vds -VMHostPhysicalNic $pNIC -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            # Not used - Adding new VMKernel to VDS
            # My-Logger "Adding VMKernel $VLANvmk0IP to VDS $VDSName..."
            # 
            # $vmk0 = Get-VMHostNetworkAdapter -Server $vc -Name vmk0 -VMHost $vmhost
            # $lastNetworkOcet = $vmk0.ip.Split('.')[-1]
            # $vxlanVmkIP = $VXLANSubnet + $lastNetworkOcet
            # New-VMHostNetworkAdapter -VMHost $vmhost -PortGroup $VLANMGMTPortgroup -VirtualSwitch $VDSName -IP $VLANvmk0IP -SubnetMask 255.255.255.0 -Mtu 1600 | Out-File -Append -LiteralPath $verboseLogFile

            # Migrating VMkernel port (vmk0) on vSwitch to VDS
            My-Logger "Migrate $vmhostname VMkernel interfaces to VDS $VDSName..."
            $vmk = Get-VMHostNetworkAdapter -Name vmk0 -VMHost $vmhost
            Set-VMHostNetworkAdapter -PortGroup $VLANMGMTPortgroup -VirtualNic $vmk -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            
            # Migrating Virtual Machines from vSwitch to VDS if Virtual Machines exist on Host
            My-Logger "Migrate Virtual Machine from VSS to VDS $VDSName if VM exist..."
            My-Logger "Check to see if VM exist on host $vmhostname..."
            $VMonHost = (Get-VM).count
            if($VMonHost -gt 0) {
                My-Logger "$VMonHost Virtual Machine on host $vmhostname will be migrated to DVS..."
                $vdPortgroup = Get-VDPortGroup -VDSwitch (Get-VDSwitch -Name $VDSName) -Name $VLANVMPortgroup
                Get-VM -Location $vmhostname | Get-NetworkAdapter | where { $_.NetworkName -eq $VMNetwork } | Set-NetworkAdapter -Portgroup $vdPortgroup -confirm:$false #did not work as it detect 2 entries
            }

            My-Logger "Removing legacy Standard Switch - vSwitch0 on $vmhostnam..."
            # code for removing portgroup on vSwitch0 if needed below
            #
            # $vSS_pg1 = Get-VirtualPortGroup -Name "VM Network" -VirtualSwitch vSwitch0
            # Remove-VirtualPortGroup -VirtualPortGroup $vSS_pg1 -confirm:$false
            Remove-VirtualSwitch -VirtualSwitch vSwitch0 -Confirm:$false
            
            # Reclaim vmnic0 on host and add to VDS
            My-Logger "Reclaim vmnic0 on host and add to VDS $VDSName..."
            $pNIC_vSS = $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic0
            # Get-VMHostNetworkAdapter -Physical -Name vmnic2 | Remove-VDSwitchPhysicalNetworkAdapter
            Add-VDSwitchPhysicalNetworkAdapter -Server $vc -DistributedSwitch $vds -VMHostPhysicalNic $pNIC_vSS -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if($configurevMotion -eq 'true') {
        My-Logger "Enabling vMotion on ESXi hosts ..."
        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            $vmhost | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }    

    # Define Teaming and Failover policies on portgroups
    My-Logger "Setting DVS Uplink policy on DVSwitch - $VDSName..."
    Get-VDSwitch $vds | Get-VDPortgroup $VLANMGMTPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1' -StandbyUplinkPort 'dvUplink2'
    Get-VDSwitch $vds | Get-VDPortgroup $VLANVMPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1' -StandbyUplinkPort 'dvUplink2'
    Get-VDSwitch $vds | Get-VDPortgroup $VLANTrunkPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1' -StandbyUplinkPort 'dvUplink2'

    Get-VDSwitch $vds | Get-VDPortgroup $VXLANDVPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1' -StandbyUplinkPort 'dvUplink2'


    # Define Portgroup Secuirty Policy
    # Get-VDSwitch $vds | Get-VDPortgroup $VLANVMPortgroup | Get-VDSecurityPolicy | Set-VDSecurityPolicy -AllowPromiscuous $false -ForgedTransmits $false -MacChanges $true 

    # Define Portgroup Traffic Shaping
    # Get-VDSwitch $vds | Get-VDPortgroup $VLANVMPortgroup | Get-VDTrafficShapingPolicy -Direction In/Out | Set-VDTrafficShapingPolicy -Enabled $true -AverageBandwidth 100000 -BurstSize -PeakBandwidth

    # Define Portgroup Load Balancing Policy
    # For LB options, set -LoadBalancingPolicy to
    #   'Set Route based on IP hash' - LoadBalanceIP
    #   'Set Route based on source MAC hash' - LoadBalanceSrcMac
    #   'Set Route based on originating virtual port' - LoadBalanceSrcId
    #   'Set Use explicit failover order' - ExplicitFailover 
    #   'Set Route based on physcial NIC load' - LoadBalanceLoadBased
    #
    # Use Get-VDPortgroup alone to set for all Portgroup on the same VDS
    # Get-VDswitch $vds | Get-VDPortgroup $VLANVMPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -LoadBalancingPolicy LoadBalanceIP

    # Define Portgroup Others Policy
    # Get-VDSwitch $vds | Get-VDPortgroup $VLANVMPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -FailoverDetectionPolicy LinkStatus/BeaconProbing -NotifySwitches $true -EnableFailback $true  

    # Exit maintanence mode in case patching was done earlier
    foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
        if($vmhost.ConnectionState -eq "Maintenance") {
            Set-VMHost -VMhost $vmhost -State Connected -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if($DeployNSX -eq 'true') {
        $ovfconfig = Get-OvfConfiguration $NSX_Mgr_OVA
        #$ovfconfig.NetworkMapping.VSMgmt.value = $VMNetwork
        #$ovfconfig.NetworkMapping.Management_Network.value = $VMNetwork
        $ovfconfig.NetworkMapping.Management_Network.value = $NSX_Mgr_Network
        $ovfconfig.common.vsm_hostname.value = $NSX_Mgr_Hostname
        $ovfconfig.common.vsm_ip_0.value = $NSX_Mgr_IP
        $ovfconfig.common.vsm_netmask_0.value = $NSX_Mgr_Netmask
        $ovfconfig.common.vsm_gateway_0.value = $NSX_Mgr_Gateway
        $ovfconfig.common.vsm_dns1_0.value = $VMDNS
        $ovfconfig.common.vsm_domain_0.value = $VMDomain
        $ovfconfig.common.vsm_ntp_0.value = $VMNTP
        if($NSX_Mgr_SSHEnable -eq "true") {
            $NSX_Mgr_SSHEnableVar = $true
        } else {
            $NSX_Mgr_SSHEnableVar = $false
        }
        $ovfconfig.common.vsm_isSSHEnabled.value = $NSX_Mgr_SSHEnableVar
        if($NSX_Mgr_CEIPEnable -eq "true") {
            $NSX_Mgr_CEIPEnableVar = $true
        } else {
            $NSX_Mgr_CEIPEnableVar = $false
        }
        $ovfconfig.common.vsm_isCEIPEnabled.value = $NSX_Mgr_CEIPEnableVar
        $ovfconfig.common.vsm_cli_passwd_0.value = $NSX_Mgr_UI_Pass
        $ovfconfig.common.vsm_cli_en_passwd_0.value = $NSX_Mgr_CLI_Pass

        My-Logger "Deploying NSX Manager VM - $NSX_Mgr_Name ..."
        #$vmhost = Get-VMHost -Name $VIServer
        #$datastore = Get-Datastore -Name $VMDatastore
        #$vm = Import-VApp -Source $NSX_Mgr_OVA -OvfConfiguration $ovfconfig -Name $NSX_Mgr_Name -Location $NewVCVSANClusterName -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin
        
        # One option - without setting CEIP, DiskStorageFormat, Host to use
        #New-NSXManager -NsxManagerOVF $NSXManagerOVF -Name $NSX_Mgr_Name -ClusterName $NSX_VC_Cluster -ManagementPortGroupName $NSX_VC_Network -DatastoreName $NSX_VC_Datastore -FolderName $NSX_VC_Folder -CliPassword $NSX_MGR_CLI_Pass -CliEnablePassword $NSX_MGR_CLI_Pass -Hostname $NSX_MGR_Hostname -IpAddress $NSX_MGR_IP -Netmask $NSX_MGR_Netmask -Gateway $NSX_MGR_Gateway -DnsServer $NSX_MGR_DNSServer -DnsDomain $NSX_MGR_DNSDomain -NtpServer $NSX_MGR_NTPServer -EnableSsh -StartVm)

        $vmhost = Get-VMHost -Server $vc -Name $VIServer
        $datastore = Get-Datastore -Server $vc -Name $VMDatastore
        $vm = Import-VApp -Source $NSX_Mgr_OVA -OvfConfiguration $ovfconfig -Name $NSX_Mgr_Name -Location $NewVCVSANClusterName -Server $vc -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin
        
        My-Logger "Updating NSX VM vCPU Count to '$NSX_Mgr_vCPU' & vMEM to '$NSX_Mgr_vMem GB' ..."
        #Set-VM -Server $viConnection -VM $vm -NumCpu $NSX_Mgr_vCPU -MemoryGB $NSX_Mgr_vMem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        Set-VM -Server $vc -VM $vm -NumCpu $NSX_Mgr_vCPU -MemoryGB $NSX_Mgr_vMem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "Powering On NSX - $NSX_Mgr_Name ..."
        $vm | Start-Vm -RunAsync | Out-Null
    }

    My-Logger "Creating new VXLAN DVPortgroup - $VXLANDVPortgroup ..."
    #$vds = Get-VDSwitch $VDSName
    #New-VDPortgroup -Server $vc -Name $VXLANDVPortgroup -Vds $vds -NumPorts 24 #-PortBinding Ephemeral/Static

    if($DeployNSX -eq 'true' -and $configureNSX -eq 'true' -and $setupVXLAN -eq 'true') {
        My-Logger "Validate NSX Manager access ..."
        if(!(Connect-NSXServer -Server $NSX_Mgr_Hostname -Username admin -Password $NSX_Mgr_UI_Pass -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
            Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
            exit
        } else {
            My-Logger "Successfully logged into NSX Manager - $NSX_Mgr_Hostname ..."
        }

        $ssoUsername = "administrator@$VCSASSODomainName"
        My-Logger "Registering NSX Manager '$NSX_Mgr_Hostname' with vCenter Server '$VCSAHostname' ..."
        $vcConfig = Set-NsxManager -vCenterServer $VCSAHostname -vCenterUserName $ssoUsername -vCenterPassword $VCSASSOPassword

        My-Logger "Registering NSX Manager with vCenter SSO $VCSAHostname ..."
        $ssoConfig = Set-NsxManager -SsoServer $VCSAHostname -SsoUserName $ssoUsername -SsoPassword $VCSASSOPassword -AcceptAnyThumbprint

        My-Logger "Disconnecting from NSX Manager ..."
        Disconnect-NsxServer
    }

    My-Logger "Check if NSX Controllers IP Pool already exists .."
    $CTRLIPPool = Get-NsxIpPool -Name $NSX_Controllers_IP_Pool_Name -ErrorAction SilentlyContinue
    if($CTRLIPPool -eq $null) {
        $CTRLIPPool = New-NsxIpPool -Name $NSX_Controllers_IP_Pool_Name -Gateway $NSX_Controllers_IP_Pool_Gateway -SubnetPrefixLength $NSX_Controllers_IP_Pool_Prefix -DnsServer1 $NSX_Controllers_IP_Pool_DNS1 -DnsServer2 $NSX_Controllers_IP_Pool_DNS2 -DnsSuffix $NSX_Controllers_IP_Pool_DNSSuffix -StartAddress $NSX_Controllers_IP_Pool_Start -EndAddress $NSX_Controllers_IP_Pool_End
        My-Logger "Create NSX Controllers IP Pool - $NSX_Controllers_IP_Pool_Name ..."
    }
    # Command for IP Pool removal
    # $IP_Pool = Get-NsxIpPool -Name $NSX_Controllers_IP_Pool_Name
    # Remove-NsxIpPool -IPPool $IP_Pool -Confirm:$false

    My-Logger "Create NSX Controllers .."
    $cluster = Get-Cluster -Name $NSX_Controllers_Cluster
    $datastore = Get-Datastore -Name $NSX_Controllers_Datastore
    $portgroup = Get-VirtualPortGroup -Name $NSX_Controllers_PortGroup
    $i = 1
    While ($i -le $NSX_Controllers_Amount) {
        My-Logger "Deloying NSX Controller $i ..."
        $controller = New-NsxController -Confirm:$False -IpPool $IPPool -Cluster $cluster -Datastore $datastore -PortGroup $portgroup -Password $NSX_Controllers_Password -Wait
        $i += 1
    }
    My-Logger "$NSX_Controllers_Amount NSX Controllers deployed ..."

    My-Logger "Preparing ESX Hosts on Cluster - $NSX_VXLAN_Cluster (installing VIBs) ..."
    $cluster = Get-Cluster -Name $NSX_VXLAN_Cluster
    $HostPrep = Install-NsxCluster -Cluster $cluster -VxlanPrepTimeout 300
    My-Logger "VXLAN enabled on Cluster - $NSX_VXLAN_Cluster ..."

    My-Logger "Creating VXLAN Segment ID, Range from $NSX_VXLAN_Segment_ID_Begin to $NSX_VXLAN_Segment_ID_End ..."
    $SegmentID = New-NsxSegmentIdRange -Name "Segment-1" -Begin $NSX_VXLAN_Segment_ID_Begin -End $NSX_VXLAN_Segment_ID_End
    # Command for Segment removal
    # $SegmentID = Get-NsxSegmentIdRange
    # Remove-NsxSegmentIdRange $SegmentID 

    My-Logger  "Creating VXLAN Multicast IP range ..."
    . "D:\New-NsxMulticastRange.ps1"
    $MultiCast = New-NsxMulticastRange -Name "Multicast1" -Begin $NSX_VXLAN_Multicast_Range_Begin -End $NSX_VXLAN_Multicast_Range_End

    My-Logger "Check if VXLAN (VTEP) IP Pool already exists .."
    $VTEPIPPool = Get-NsxIpPool -Name $NSX_VXLAN_IP_Pool_Name -ErrorAction SilentlyContinue
    if($VTEPIPPool -eq $null) {
        $VTEPIPPool = New-NsxIpPool -Name $NSX_VXLAN_IP_Pool_Name -Gateway $NSX_VXLAN_IP_Pool_Gateway -SubnetPrefixLength $NSX_VXLAN_IP_Pool_Prefix -DnsServer1 $NSX_VXLAN_IP_Pool_DNS1 -DnsServer2 $NSX_VXLAN_IP_Pool_DNS2 -DnsSuffix $NSX_VXLAN_IP_Pool_DNSSuffix -StartAddress $NSX_VXLAN_IP_Pool_Start -EndAddress $NSX_VXLAN_IP_Pool_End
        My-Logger "Create VXLAN (VTEP) IP Pool - $NSX_VXLAN_IP_Pool_Name ..."
    }

    My-Logger "Configuring '$NSX_VXLAN_VTEP_Count' VXLAN VTEPs on cluster - $NSX_VXLAN_Cluster ..."
    $vds = Get-VDSwitch -Name $NSX_VXLAN_DSwitch
    New-NsxVdsContext -VirtualDistributedSwitch $vds -Teaming $NSX_VXLAN_Failover_Mode -Mtu $NSX_VXLAN_MTU_Size
    New-NsxClusterVxlanConfig -Cluster $cluster -VirtualDistributedSwitch $vds -IpPool $IPPool -VlanId $NSX_VXLAN_VLANID -VtepCount $NSX_VXLAN_VTEP_Count

    My-Logger "Adding Transport Zone - $NSX_VXLAN_TZ_Name ..." 
    New-NsxTransportZone -Cluster $cluster -Name $NSX_VXLAN_TZ_Name -ControlPlaneMode $NSX_VXLAN_TZ_Mode
    # Remove Transport Zone
    # $a = Get-NsxTransportZone -name $NSX_VXLAN_TZ_Name
    # Remove-NsxTransportZone $a -Confirm:$false
    My-Logger "NSX Cluster Preparation Completed ..."
   
    My-Logger "Adding VM exclusions to NSX Distributed Firewall ..."
    $WorkSheetname = "Exclusion List"
    $WorkSheet_Exclusions = $WorkBook.Sheets.Item($WorkSheetname)
    $intRow = 3 # Start at row 3 (minus headers) and loop through them while the cells are not empty
    $ExcludedVMCount = 0
    While ($WorkSheet_Exclusions.Cells.Item($intRow, 1).Value() -ne $null){
        $Exclusion_VM_Name = $WorkSheet_Exclusions.Cells.Item($intRow, 1).Value()
        if(($(Get-NsxFirewallExclusionListMember).name -eq $Exclusion_VM_Name)) {
            My-Logger "$Exclusion_VM_Name already added to Firewall Exlcuded VM(s) ..."
        } else {
            Add-NsxFirewallExclusionListMember -VirtualMachine (Get-VM -Name $Exclusion_VM_Name)
            # Remove-NsxFirewallExclusionListMember -VirtualMachine (Get-VM -Name $Exclusion_VM_Name)
            $ExcludedVMCount++
        }
        $intRow++
    }
    $release = Release-Ref($WorkSheet_Exclusions)
    My-Logger "Added $ExcludedVMCount VM(s) to NSX Distributed Firewall exclusion list ..."

    My-Logger "Creating NSX Logical Switches ..."
    $ScopeId = Get-NsxTransportZone -Name $NSX_VXLAN_TZ_Name
    if($ScopeId -eq $null) {
        My-Logger "Expected NSX Transport Zone - '$NSX_VXLAN_TZ_Name' not found, cluster was not properly configure"
        Exit
    }
    $WorkSheetname = "Logical Switches"
    $WorkSheet_LS = $WorkBook.Sheets.Item($WorkSheetname)
    # Start at row 2 (minus header) and loop through them while the cells are not empty
    $intRow = 2
    $LogicalSwitchCount = 0
    While ($WorkSheet_LS.Cells.Item($intRow, 1).Value() -ne $null)
    {
        # Get the Logical Switch name from worksheet and add it to NSX
        $LS_Name = $WorkSheet_LS.Cells.Item($intRow, 1).Value()
        $LS_Desc = $WorkSheet_LS.Cells.Item($intRow, 2).Value()

        if(!(New-NsxLogicalSwitch -Name $LS_Name -Description $LS_Desc -vdnScope $scopeId)) {
            My-Logger "Unable to create Logical Switch - $LS_Name $_"
        } else {
            $LogicalSwitchCount++
        }
        $intRow++
    }
    $release = Release-Ref($WorkSheet_LS)
    My-Logger "Added $LogicalSwitchCount new Logical Switches to Transport Zone - $NSX_VXLAN_TZ_Name ..."

    My-Logger "Creating NSX Distributed Logical Routers (DLR) ..."
    $WorkSheetname = "Distributed Logical Routers"
    $WorkSheet_DLR = $WorkBook.Sheets.Item($WorkSheetname)
    # Start at row 2 (minus header)
    $intRow = 2
    $DLRCount = 0

        $DLR_Name               = $WorkSheet_DLR.Cells.Item($intRow, 1).Value()
        $DLR_Tenant             = $WorkSheet_DLR.Cells.Item($intRow, 2).Value()
        $DLR_Cluster            = $WorkSheet_DLR.Cells.Item($intRow, 3).Value()
        $DLR_Datastore          = $WorkSheet_DLR.Cells.Item($intRow, 4).Value()
        $DLR_Password           = $WorkSheet_DLR.Cells.Item($intRow, 5).Value()
        $DLR_HA                 = $WorkSheet_DLR.Cells.Item($intRow, 6).Value()
        $DLR_VNIC0_Name         = $WorkSheet_DLR.Cells.Item($intRow, 7).Value()
        $DLR_VNIC0_IP           = $WorkSheet_DLR.Cells.Item($intRow, 8).Value()
        $DLR_VNIC0_Prefixlength = $WorkSheet_DLR.Cells.Item($intRow, 9).Value()
        $DLR_VNIC0_PortGroup    = $WorkSheet_DLR.Cells.Item($intRow, 10).Value()
        $DLR_MGMT_PortGroup     = $WorkSheet_DLR.Cells.Item($intRow, 11).Value()

        $enableHA = $false
        if($DLR_HA -eq "Yes") {
            $enableHA = $true
        }

        # figure out the connected portgroup. First, assume it's a logical switch and if it's not, move on to a PortGroup
        $connectedTo = (Get-NsxTransportZone -Name $NSX_VXLAN_TZ_Name | Get-NsxLogicalSwitch $DLR_VNIC0_PortGroup)
        if($connectedTo -eq $null) {
            $connectedTo = (Get-VDPortgroup $DLR_VNIC0_PortGroup)
        }
        # Same for the management port
        $mgtNic = (Get-NsxTransportZone -Name $NSX_VXLAN_TZ_Name | Get-NsxLogicalSwitch $DLR_MGMT_PortGroup)
        if($mgtNic -eq $null) {
            $mgtNic = (Get-VDPortgroup $DLR_MGMT_PortGroup)
        }

        $vnic0 = New-NsxLogicalRouterInterfaceSpec -Name $DLR_VNIC0_Name -Type Uplink -ConnectedTo $connectedTo -PrimaryAddress $DLR_VNIC0_IP -SubnetPrefixLength $DLR_VNIC0_Prefixlength
        $DLR = New-NsxLogicalRouter -Name $DLR_Name -Tenant $DLR_Tenant -Cluster (Get-Cluster -Name $DLR_Cluster) -Datastore (Get-Datastore -Name $DLR_Datastore) -EnableHa:$enableHA -Interface $vnic0 -ManagementPortGroup $mgtNic

        if(!($DLR)) {
            My-Logger "Unable to create Distributed Logical Routers - $DLR_Name ..."
        } else {
            $DLRCount++
        }
        $intRow++
    My-Logger "Added $DLRCount Distributed Logical Routers ..."

    My-Logger "Configure Logical Interface (LIF) to newly created Distributed Logical Routers - $DLR_Name ..."
    $intRow = 10 # move cursor to row 10
    $lifCount = 0
    While ($WorkSheet_DLR.Cells.Item($intRow, 1).Value() -ne $null)
    {
        # Get the Logical Switch name from worksheet and add it to DLR
        $LIF_Name      = $WorkSheet_DLR.Cells.Item($intRow, 1).Value()
        $LIF_Address   = $WorkSheet_DLR.Cells.Item($intRow, 2).Value()
        $LIF_SPrefix   = $WorkSheet_DLR.Cells.Item($intRow, 3).Value()
        $LIF_LogSwitch = $WorkSheet_DLR.Cells.Item($intRow, 4).Value()
        $DLR = Get-NsxLogicalRouter -Name $DLR_Name

        My-Logger "Adding '$LIF_Name' LIF to DLR '$DLR_Name'"
        $LS = Get-NsxLogicalSwitch -Name $LIF_LogSwitch
        $DLR | New-NsxLogicalRouterInterface -Type Internal -name $LIF_Name -ConnectedTo $LS -PrimaryAddress $LIF_Address -SubnetPrefixLength $LIF_SPrefix | out-null
        $lifCount++
        $intRow++
    }
    My-Logger "$lifCount LIF were added to $DLR_Name ..."

    My-Logger "Configure newly created Distributed Logical Routers '$DLR_Name' ..."
    $intRow = 6 # Move cursor to row 6
    
        $DLR_RouteID           = $WorkSheet_DLR.Cells.Item($intRow, 1).Value()
        $DLR_BGP_Protocol_Addr = $WorkSheet_DLR.Cells.Item($intRow, 2).Value()
        $DLR_BGP_Foward_Addr   = $WorkSheet_DLR.Cells.Item($intRow, 3).Value()
        $DLR_BGP_IPAddr        = $WorkSheet_DLR.Cells.Item($intRow, 4).Value()
        $DLR_BGP_LocalAS       = $WorkSheet_DLR.Cells.Item($intRow, 5).Value()
        $DLR_BGP_RemoteAS      = $WorkSheet_DLR.Cells.Item($intRow, 6).Value()
        $DLR_BGP_KeepAlive     = $WorkSheet_DLR.Cells.Item($intRow, 7).Value()
        $DLR_BGP_HoldDown      = $WorkSheet_DLR.Cells.Item($intRow, 8).Value()

    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgp -LocalAS $DLR_BGP_LocalAS -RouterId $DLR_RouteID -confirm:$false
    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterBgp -GracefulRestart:$false -confirm:$false
    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution -confirm:$false
    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -FromConnected -Learner bgp -confirm:$false
    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution:$false -Confirm:$false
    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -confirm:$false
    $dlr = Get-NsxLogicalRouter -Name $DLR_Name
    $dlr | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $DLR_BGP_IPAddr -RemoteAS $DLR_BGP_RemoteAS `
-ForwardingAddress $DLR_BGP_Foward_Addr -ProtocolAddress $DLR_BGP_Protocol_Addr -KeepAliveTimer $DLR_BGP_KeepAlive -HoldDownTimer $DLR_BGP_HoldDown -confirm:$false

    $release = Release-Ref($WorkSheet_DLR)
    My-Logger "Distributed Logical Routers deployment completed ..."

    My-Logger "Creating Edge Services Gateways (ESG) ..."
    $WorkSheetname = "Edge Services Gateways"
    $WorkSheet_ESG = $WorkBook.Sheets.Item($WorkSheetname)
    $ESGCount = 0
    #While ($WorkSheet_ESG.Cells.Item($intRow, 1).Value() -ne $null) {}
    
    $ESG_Name               = $WorkSheet_ESG.Cells.Item(2, 1).Value()
    $ESG_Tenant             = $WorkSheet_ESG.Cells.Item(2, 2).Value()
    $ESG_Cluster            = $WorkSheet_ESG.Cells.Item(2, 3).Value()
    $ESG_Datastore          = $WorkSheet_ESG.Cells.Item(2, 4).Value()
    $ESG_Password           = $WorkSheet_ESG.Cells.Item(2, 5).Value()
    $ESG_FormFactor         = $WorkSheet_ESG.Cells.Item(2, 6).Value()
    $ESG_HA                 = $WorkSheet_ESG.Cells.Item(2, 7).Value()
    $ESG_HADeadTime         = $WorkSheet_ESG.Cells.Item(2, 8).Value()
    $ESG_SSH                = $WorkSheet_ESG.Cells.Item(2, 9).Value()
    $ESG_Hostname           = $WorkSheet_ESG.Cells.Item(2, 10).Value()
    $ESG_VNIC0_Name         = $WorkSheet_ESG.Cells.Item(2, 11).Value()

    $ESG_VNIC0_IP           = $WorkSheet_ESG.Cells.Item(5, 1).Value()
    $ESG_VNIC0_Prefixlength = $WorkSheet_ESG.Cells.Item(5, 2).Value()
    $ESG_VNIC0_IP2          = $WorkSheet_ESG.Cells.Item(5, 3).Value()
    $ESG_VNIC0_MTU          = $WorkSheet_ESG.Cells.Item(5, 4).Value()
    $ESG_VNIC0_PortGroup    = $WorkSheet_ESG.Cells.Item(5, 5).Value()
    $ESG_Firewall           = $WorkSheet_ESG.Cells.Item(5, 6).Value()
    $ESG_Firewall_Log       = $WorkSheet_ESG.Cells.Item(5, 7).Value()
    $ESG_FW_DefaultPolicy   = $WorkSheet_ESG.Cells.Item(5, 8).Value()
    $ESG_FW_AutoRules       = $WorkSheet_ESG.Cells.Item(5, 9).Value()
    $ESG_Syslog             = $WorkSheet_ESG.Cells.Item(8, 1).Value()
    $ESG_Syslog_Server      = $WorkSheet_ESG.Cells.Item(8, 2).Value()
    $ESG_Syslog_Protocol    = $WorkSheet_ESG.Cells.Item(8, 3).Value()

    $enableHA = $false
    if($ESG_HA -eq "Yes") {
        $enableHA = $true
    }
    $enableSSH = $false
    if($ESG_SSH -eq "Yes") {
        $enableSSH = $true
    }
    $enableFW = $false
    if($ESG_Firewall -eq "Yes") {
        $enableFW = $true
    }
    $enableFWLog = $false
    if($ESG_Firewall_Log -eq "Yes") {
        $enableFWLog = $true
    }
    $enableFWDP = $false
    if($ESG_FW_DefaultPolicy -eq "Yes") {
        $enableFWDP = $true
    }
    $enableFWAR = $false
    if($ESG_FW_AutoRules -eq "Yes") {
        $enableFWAR = $true
    }
    $enableSyslog = $false
    if($ESG_Syslog -eq "Yes") {
        $enableSyslog = $true
    }

    # figure out the connected portgroup. First, assume it's a logical switch and if it's not, move on to a PortGroup
    $connectedTo = (Get-NsxTransportZone -Name $NSX_VXLAN_TZ_Name | Get-NsxLogicalSwitch $ESG_VNIC0_PortGroup)
    if($connectedTo -eq $null) {
        $connectedTo = (Get-VDPortgroup $ESG_VNIC0_PortGroup)
    }

    # Uplink - vnic0
    $vnic0 = New-NsxEdgeInterfaceSpec -Index 0 -Name $ESG_VNIC0_Name -Type Uplink -ConnectedTo $connectedTo -PrimaryAddress $ESG_VNIC0_IP `
    -SecondaryAddresses $ESG_VNIC0_IP2 -MTU $ESG_VNIC0_MTU -SubnetPrefixLength $ESG_VNIC0_Prefixlength
    $ESG = New-NsxEdge -Name $ESG_Name -Cluster (Get-Cluster -Name $ESG_Cluster) -Datastore (Get-Datastore -Name $ESG_Datastore) -FormFactor $ESG_FormFactor `
    -Password $ESG_Password -Hostname $ESG_Hostname -EnableHa:$enableHA -HaDeadTime $ESG_HADeadTime -EnableSSH:$enableSSH -FwEnabled:$enableFW `
    -FwLoggingEnabled:$enableFWLog -FwDefaultPolicyAllow:$enableFWDP -AutoGenerateRules:$enableFWAR -EnableSyslog:$enableSyslog -SyslogServer $ESG_Syslog_Server `
    -SyslogProtocol $ESG_Syslog_Protocol -Interface $vnic0

    if(!($ESG)) {
        My-Logger "Unable to create Edge $Edge_Name ..."
    }
    else {
      $ESGCount++
    }
    
    My-Logger "Added $ESGCount Edge Services Gateways ..."

    My-Logger "Adding interfaces to newly created Edge Service Gateway - $ESG_Name ..."
    $intRow = 16 # move cursor to row 16
    $ESGIFIndex = 1
    $ESGIFCount = 0
    While ($WorkSheet_ESG.Cells.Item($intRow, 1).Value() -ne $null)
    {
        # Get the Logical Switch name from worksheet and add it to DLR
        $ESG_IF_Name      = $WorkSheet_ESG.Cells.Item($intRow, 1).Value()
        $ESG_IF_Address   = $WorkSheet_ESG.Cells.Item($intRow, 2).Value()
        $ESG_IF_SPrefix   = $WorkSheet_ESG.Cells.Item($intRow, 3).Value()
        $ESG_IF_LogSwitch = $WorkSheet_ESG.Cells.Item($intRow, 4).Value()
        $ESG = Get-NsxEdge -Name $ESG_Name

        My-Logger "Adding '$ESG_IF_Name' interface to ESG '$ESG_Name'"
        $LS = Get-NsxLogicalSwitch -Name $ESG_IF_LogSwitch
        $ESG | Get-NsxEdgeInterface –Index $ESGIFIndex | Set-NsxEdgeInterface -Type Internal -name $ESG_IF_Name -ConnectedTo $LS -PrimaryAddress $ESG_IF_Address -SubnetPrefixLength $ESG_IF_SPrefix | out-null
        $ESGIFCount++
        $ESGIFIndex++
    }
    My-Logger "$ESGIFCount interfaces were added to ESG - $ESG_Name ..."

    My-Logger "Configure newly created Distributed Logical Routers '$DLR_Name' ..."
    $intRow = 12 # Move cursor to row 12
    
        $ESG_RouteID           = $WorkSheet_ESG.Cells.Item($intRow, 1).Value()
        $ESG_BGP_Protocol_Addr = $WorkSheet_ESG.Cells.Item($intRow, 2).Value()
        $ESG_BGP_Foward_Addr   = $WorkSheet_ESG.Cells.Item($intRow, 3).Value()
        $ESG_BGP_IPAddr        = $WorkSheet_ESG.Cells.Item($intRow, 4).Value()
        $ESG_BGP_LocalAS       = $WorkSheet_ESG.Cells.Item($intRow, 5).Value()
        $ESG_BGP_RemoteAS      = $WorkSheet_ESG.Cells.Item($intRow, 6).Value()
        $ESG_BGP_KeepAlive     = $WorkSheet_ESG.Cells.Item($intRow, 7).Value()
        $ESG_BGP_HoldDown      = $WorkSheet_ESG.Cells.Item($intRow, 8).Value()

    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgp -LocalAS $ESG_BGP_LocalAS -RouterId $ESG_RouteID -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeBgp -GracefulRestart:$false -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    ##$ESG | Get-NsxEdgeRouting | Set-NsxEdgeBgp -FromConnected -Learner bgp -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -Confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayVnic 0 -DefaultGatewayAddress 192.168.10.2 -DefaultGatewayAdminDistance 1 -Confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress $DLR_BGP_IPAddr -RemoteAS $DLR_BGP_RemoteAS `
-ForwardingAddress $DLR_BGP_Foward_Addr -ProtocolAddress $DLR_BGP_Protocol_Addr -KeepAliveTimer $DLR_BGP_KeepAlive -HoldDownTimer $DLR_BGP_HoldDown -confirm:$false

    $release = Release-Ref($WorkSheet_ESG)
    My-Logger "Edge Services Gateway deployment completed ..."

    # Cleanup Excel object
    $Excel.Quit()

    if($configureConLib -eq 'true') {

        # Setup Content Library for ISO
        My-Logger "Setup Content Library on VCSA ..."
        $ConLibDatastore = Get-Datastore -Name $ConLibDSName

        New-ContentLibrary -Datastore $ConLibDatastore -Name $ConLibName

        # Get the list of ISO files from the path that was specified
        $ListOfISO = ls $($ISOPath)*.iso | Get-ChildItem -rec | ForEach-Object -Process {$_.BaseName}

        # For each ISO file in the list check to see if it is already in the repo, if not upload it
        foreach( $iso in $ListOfISO){
            $FullPath = "$($ISOPath)\$($iso).iso"
            $ExistingItem = Get-ContentLibraryItem -Name "$iso.iso" -ContentLibrary $ConLibName
            if (!$ExistingItem) {
                Write-Host "Uploading $($iso)"
                New-ContentLibraryItem -ContentLibrary $ConLibName -Name "$iso.iso" -Files $FullPath
            } else {
                Write-Host "$($iso) Already Exists In Repo"
            }
        }
    }
    
    # Set MAC-Learn on DVS Portgroup
    My-Logger "Set MAC-Learning on DVS Portgroup ..."
    Get-MacLearn -DVPortgroupName @("Trunk Network")
    Set-MacLearn -DVPortgroupName @("Trunk Network") -EnableMacLearn $true -EnablePromiscuous $false -EnableForgedTransmit $true -EnableMacChange $false

    My-Logger "Disconnecting from new VCSA ..."
    Disconnect-VIServer $vc -Confirm:$false
}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "vSphere $vSphereVersion Lab Deployment for VCSA Complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"

# Forward Deployment summary and log to receipent...
$verboseLogFilePath = Get-ChildItem Env:Userprofile
$strVMGuestIP = (Get-VM $strVMName).Guest.IPAddress
$strVMFreeSpace = [math]::Round((Get-VM $strVMName).Guest.Disks.FreeSpaceGB[0],2)
$AttachmentsPath = $verboseLogFilePath.Value+'\'+$verboseLogFile
$strEmailBody = @"
<h1><span style="color: #0000ff;">VMware Manage VCSA Deployment Log attached</span></h1>
<hr />
<table style="width:100%">
  <tr>
    <th>Start Time</th>
    <th>End Time</th> 
    <th>Duration</th>
  </tr>
  <tr>
    <td style='text-align:center'>$StartTime</td>
    <td style='text-align:center'>$EndTime</td> 
    <td style='text-align:center'>$duration minutes</td>
  </tr>
  <tr>
    <th>Operation System</th>
    <th>Role</th> 
    <th>Virtual Machine Name</th>
  </tr>
  <tr>
    <td style='text-align:center'>$strVMTemplate</td>
    <td style='text-align:center'>$strVMRole</td> 
    <td style='text-align:center'>$strVMName</td>
  </tr>
  <tr>
    <th>IP address</th>
    <th>FreeSpace (GB)</th> 
    <th>Domain</th>
  </tr>
  <tr>
    <td style='text-align:center'>$strVMGuestIP</td>
    <td style='text-align:center'>$strVMFreeSpace</td> 
    <td style='text-align:center'>$JoinDomain</td>
  </tr>
</table>
"@
$sendMailParams = @{
    From = $strO365Username
    To = $strSendTo
    #Cc =
    #Bcc =
    Subject = $strEmailSubject
    Body = $strEmailBody
    BodyAsHtml = $true
    Attachments = $AttachmentsPath
    Priority = 'High'
    DeliveryNotificationOption = 'None' # 'OnSuccess, OnFailure'
    SMTPServer = $strSMTPServer
    Port = $intSMTPPort
    UseSsl = $true
    Credential = $oOffice365credential
}
Send-MailMessage @sendMailParams