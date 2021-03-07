# http://michaelstoica.com/how-to-configure-iscsi-targets-on-esxi-hosts-with-powercli/
# Author: Dominic Chan (dominic.chan@tataoui.com)
# Date: 2020-11-11
# Last Update: 2021-03-04
#
# Description:
# VCSA unattended installation with post installation tasks and NSX-V integration.
# - tested on VCSA 6.7
# - tested on NSX-V 6.4.9
# 
# Powershell environment prerequisites:
# 1. PowerShell version: 5.1.14393.3866
# 2. PowerCLI Version: 12.1.0.16997582
#    Install-Module VMware.PowerCLI
# 3. PowerNSX version: 3.0.1174
#    Install-Module -Name PowerNSX -Confirm:$false -AllowClobber -Force
#    or 
#    $Branch="master";$url="https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSXInstaller.ps1"; try { $wc = new-object Net.WebClient;$scr = try { $wc.DownloadString($url)} catch { if ( $_.exception.innerexception -match "(407)") { $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"; $wc.DownloadString($url) } else { throw $_ }}; $scr | iex } catch { throw $_ }
# 4. Excel locally installed on desktop / laptop
# 5. ImportExcel7.1.0 (removed)
#    Install-Module -Name ImportExcel -RequiredVersion 7.1.0
#
#
Set-PowerCLIConfiguration -defaultviservermode Single -Scope Session -ParticipateInCEIP $false -Confirm:$false
# Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | out-null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -WebOperationTimeoutSeconds 600 -Confirm:$false | out-null
#
$ScriptPath = Split-Path $MyInvocation.MyCommand.Path
$DataSourcePath = "G:\Transfer\VCSA-NSX-Configure.xlsx" # Absolute path to Excel Worksheet as the data sources
#$DataSourcePath = "$ScriptPath\VMware.xlsx" # Relative path to Excel Workbook as data sources
$hostfile = "$env:windir\System32\drivers\etc\hosts"

Function Clear-Ref ($ref) {
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

$DataSource = Read-Host -Prompt 'Using static preset inputs or import from Excel? (S/E)'

if ($DataSource -eq 'S') {
    $Workload = 'Manager' # Worker / Manager
    $NestedESXiApplianceOVA = 'D:\VMware\ova\Nested_ESXi6.7u3_Appliance_Template_v1.ova'
    $NestedESXiApplianceOVF = 'D:\VMware\ova\Nested_ESXi6.7u3_Appliance_Template_v1\Nested_ESXi6.7u3_Appliance_Template_v1.ovf'
    $VCSAInstallerPath = 'D:\VMware\VMware-VCSA-all-6.7.0-15132721'
    $NSX_Mgr_OVA =  'D:\VMware\ova\VMware-NSX-Manager-6.4.9-17267008.ova'
    #$NSXTManagerOVA = 'D:\VMware\ova\VMware NSX-T Data Center 2.5.2.2\nsx-unified-appliance-2.5.2.2.0.17003656.ova'
    #$NSXTControllerOVA = 
    #$NSXTEdgeOVA = 'D:\VMware\ova\VMware NSX-T Data Center 2.5.2.2\nsx-edge-2.5.2.2.0.17003662.ova'

    $strSMTPServer = 'smtp.office365.com' # SMTP Server
    $intSMTPPort = 587 # SMTP Server Port
    $strO365Username = 'user@office365.com' # Office 365 username
    $strO365Password = 'Pa55w0rd' # Office 365 Password
    $strSendTo = 'admin@test.com' # Email Recipient

    $VIServer = 'esx02.tataoui.com'
    $VIServerIP ='192.168.10.21'
    $VIUsername = 'root'
    $VIPassword = 'VMware1!'
    $DeploymentTarget = 'ESXI'
    
    # Nested ESXi VMs or Manage ESX hosts to deploy
    $NestedESXiHostnameToIPs = @{
        "ESX01" = "192.168.10.20"
        "ESX02" = "192.168.10.21"
        "ESX03" = "192.168.10.22"
        "ESX04" = "192.168.10.23"
    }

    $VDSPortgroupAndVLAN = @{
        "Management Network" = "0"
        "Trunk Network" = "0-4094"
        "VM Network" = "0"
    }

    # VCSA Deployment Configuration
    $VCSAHostname = 'VCSA100.tataoui.com' # Change to IP if you don't have valid DNS
    # $VCSAHostname = $VCSAIPAddress
    $VCSAIPAddress = '192.168.10.223'
    $VCSADeploymentSize = 'tiny'
    $VCSADisplayName = 'VCSA100'
    $VCSAIPAddress = '192.168.10.32'
    $VCSAPrefix = '24'
    $VCSASSODomainName = 'vsphere.local'
    $VCSASSOSiteName = 'Site HQ'
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
    $VMPassword = 'VMware1!' # Password to Add ESXi Host to vCenter Cluster
    $VMDomain = 'tataoui.com'
    # VMSyslog = '192.168.1.200' # Not Used
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

    # VDS / VXLAN Configurations (Not used)
    $PrivateVXLANVMNetwork = 'dv-private-network' # Existing Portgroup
    $VXLANDVPortgroup = 'VXLAN'
    $VXLANSubnet = '172.16.66.'
    $VXLANNetmask = '255.255.255.0'

    # Enable deployment options
    $preCheck = 'true' # Validate VCSA installer location
    $confirmDeployment = 'true' # Show and validate deployment settings
    $deployVCSA = 'true' # Enable VCSA installation
    $setupNewVC = 'true' # Enable VCSA post installation
    $addHostByDnsName  = 'true' # Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
    $addESXiHostsToVC = 'true' # Enable adding ESXi hosts to vCenter during deployment
    $configurevMotion = 'true' # Enable vMotion during deployment
    $setupVXLAN = 'true' # Setup VXLAN
    $DeployNSX = 'true'
    $configureNSX = 'true' # Configure NSX
    # Enable verbose output to a new PowerShell Console. Thanks to suggestion by Christian Mohn
    $enableVerboseLoggingToNewShell = 'false'

    $configureConLib = 1 # Enable creation of Content Library
    $ConLibName = 'Repo' # Content Library repository name
    $ConLibDSName = 'SSD_VM' # Datastore for Content Library
    $ISOPath = 'F:\ISO' # Path to ISO files to upload (note it will upload ALL isos found in this folder)

     # NSX Manager Configuration
    $NSX_Mgr_Name = 'nsx64-1'
    $NSX_Mgr_Hostname = 'nsx64-1.tataoui.com'
    $NSX_Mgr_IPAddress = '172.30.0.250'
    $NSX_Mgr_Netmask = '255.255.255.0'
    $NSX_Mgr_Gateway = '172.30.0.1'
    $NSX_MGR_DNSServer = $VMDNS
    $NSX_MGR_DNSDomain = $VMDomain
    $NSX_MGR_NTPServer = $VMNTP
    $NSX_Mgr_UIPassword = 'VMware1!VMware1!'
    $NSX_Mgr_CLIPassword = 'VMware1!VMware1!'
    $NSX_Mgr_SSHEnable = 'true'
    $NSX_Mgr_CEIPEnable = 'false'
    $NSX_Mgr_vCPU = '2' # Reconfigure NSX vCPU
    $NSX_Mgr_vMem = '8' # Reconfigure NSX vMEM (GB)
    $NSX_License  = '--'

} else {
    # Import VCSA and NSX Info from Excel
    $Excel = New-Object -COM "Excel.Application"
    $Excel.Visible = $False
    $WorkBook = $Excel.Workbooks.Open($DataSourcePath)

    $WorkSheetname = 'Build'
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $PhysicalHost = $WorkSheet.Cells.Item(2, 1).Value() # Targeted physical host
    $Workload     = $WorkSheet.Cells.Item(2, 2).Value() # Workload type - Management or workload (Nested ESX)
    $release = Clear-Ref($WorkSheet)
   
    if ($Workload -eq 'Worker') {
        $NestedESXParameters = Import-Excel -Path $DataSourcePath -WorksheetName $PhysicalHost
        $NestedCount         = $NestedESXParameters.Count
        $Nested_Hostname     = $NestedESXParameters.Nested_Hostname
        $Nested_CPU          = $NestedESXParameters.Nested_CPU
        $Nested_Mem          = $NestedESXParameters.Nested_Mem
        $Nested_CacheDisk    = $NestedESXParameters.Nested_CacheDisk
        $Nested_CapacityDisk = $NestedESXParameters.Nested_CapacityDisk
        $Nested_IP           = $NestedESXParameters.Nested_IP
        $Nested_Subnet       = $NestedESXParameters.Nested_Subnet
        $Nested_GW           = $NestedESXParameters.Nested_GW
        $Nested_MgmtVLAN     = $NestedESXParameters.Nested_MgmtVLAN
        $Nested_vMotion_IP   = $NestedESXParameters.Nested_vMotion_IP
        $Nested_vMotion_Mask = $NestedESXParameters.Nested_Subnet # $NestedESXParameters.Nested_vMotion_Mask
        $Nested_vMotionVLAN  = $NestedESXParameters.Nested_vMotionVLAN
        $Nested_vSANVLAN     = $NestedESXParameters.Nested_vSANVLAN
        $Nested_DNS1         = $NestedESXParameters.Nested_DNS1
        $Nested_DNS2         = $NestedESXParameters.Nested_DNS2
        $Nested_PW           = $NestedESXParameters.Nested_PW
        $Nested_Domain       = $NestedESXParameters.Nested_Domain
        #$Nested_VCS_IP       = $NestedESXParameters.Nested_VCS_IP
    }

    $WorkSheetname = 'Software Depot'
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $NestedESXiApplianceOVA = $WorkSheet.Cells.Item(36, 2).Value() # OVA for VMware ESX OVA 
    $NestedESXiApplianceOVF = $WorkSheet.Cells.Item(37, 2).Value() # OVA for VMware ESX OVA Appliance
    $VCSAInstallerPath      = $WorkSheet.Cells.Item(38, 2).Value() # OVA for VMware vCenter Server Appliance
    $NSX_Mgr_OVA            = $WorkSheet.Cells.Item(39, 2).Value() # OVA for VMware NSX-V Manager Appliance
    $NSXTManagerOVA         = $WorkSheet.Cells.Item(40, 2).Value() # OVA for VMware NSX-T Manager/Ctrl Appliance
    #$NSXTControllerOVA = 
    $NSXTEdgeOVA            = $WorkSheet.Cells.Item(41, 2).Value() # OVA for VMware NSX-T Edge Appliance
    $release = Clear-Ref($WorkSheet)

    $WorkSheetname = 'Email'
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $strSMTPServer   = $WorkSheet.Cells.Item(2, 1).Value() # SMTP Server
    $intSMTPPort     = $WorkSheet.Cells.Item(2, 2).Value() # SMTP Server Port
    $strO365Username = $WorkSheet.Cells.Item(2, 3).Value() # Office 365 username
    $strO365Password = $WorkSheet.Cells.Item(2, 4).Value() # Office 365 Password
    $strSendTo       = $WorkSheet.Cells.Item(2, 5).Value() # Email Recipient
    $release = Clear-Ref($WorkSheet)

    $WorkSheetname = 'VCSA Information'
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $VIServer          = $WorkSheet.Cells.Item(3, 1).Value()
    $VIServerIP        = $WorkSheet.Cells.Item(3, 2).Value()
    $VIUsername        = $WorkSheet.Cells.Item(3, 3).Value()
    $VIPassword        = $WorkSheet.Cells.Item(3, 4).Value()
    $DeploymentTarget  = $WorkSheet.Cells.Item(3, 5).Value()
    $iSCSIEnable       = $WorkSheet.Cells.Item(3, 6).Value() # iSCSI Enable on ESX host
    $VCSAManager       = $WorkSheet.Cells.Item(3, 7).Value() # VCSA to Physical Infrastructure
    # VCSA Deployment Configuration
    $VCSAHostname       = $WorkSheet.Cells.Item(7, 1).Value() #Change to IP if you don't have valid DNS
    # $VCSAHostname = $VCSAIPAddress
    $VCSAIPAddress      = $WorkSheet.Cells.Item(7, 2).Value()
    $VCSADeploymentSize = $WorkSheet.Cells.Item(7, 3).Value()
    $VCSADisplayName    = $WorkSheet.Cells.Item(7, 4).Value()
    $VCSAPrefix         = [string]$WorkSheet.Cells.Item(7, 5).Value() # [int]$WorkSheet.Cells.Item(7, 5).Value()
    $VCSASSODomainName  = $WorkSheet.Cells.Item(7, 6).Value()
    $VCSASSOSiteName    = $WorkSheet.Cells.Item(7, 7).Value()
    $VCSASSOPassword    = $WorkSheet.Cells.Item(7, 8).Value()
    $VCSARootPassword   = $WorkSheet.Cells.Item(7, 9).Value()
    $VCSASSHEnable      = $WorkSheet.Cells.Item(7, 10).Value()

    # General Deployment Configuration for Nested ESXi, VCSA & NSX VMs
    $VirtualSwitchType = $WorkSheet.Cells.Item(10, 1).Value()
    $VMNetwork         = $WorkSheet.Cells.Item(10, 2).Value()
    $VMNetmask         = $WorkSheet.Cells.Item(10, 3).Value()
    $VMGateway         = $WorkSheet.Cells.Item(10, 4).Value()
    $VMDNS             = $WorkSheet.Cells.Item(10, 5).Value()
    $VMNTP             = $WorkSheet.Cells.Item(10, 6).Value()
    $VMPassword        = $WorkSheet.Cells.Item(10, 7).Value() # Password to Add ESXi Host to vCenter Cluster
    $VMDomain          = $WorkSheet.Cells.Item(10, 8).Value() # used by NSX
    $VMSyslog          = $WorkSheet.Cells.Item(10, 9).Value() # Used by VCSA
    $VMDatastore       = $WorkSheet.Cells.Item(10, 10).Value()

    # Name of new vSphere Datacenter/Cluster when VCSA is deployed
    $NewVCDatacenterName  = $WorkSheet.Cells.Item(13, 1).Value()
    $NewVCVSANClusterName = $WorkSheet.Cells.Item(13, 2).Value()

    $MgmtESXHosts = $WorkSheet.Cells.Item(16, 1).Value()
    # Read in MgmtESXHosts as hash
    $NestedESXiHostnameToIPs = @{}
    $MgmtESXHosts.split(',') | % {
        $key,$value = $_.split('=')
        $NestedESXiHostnameToIPs[$key] = $value
    }
    # Read in MgmtESXHosts as an array
    # $NestedESXiHostnameToIPs = $MgmtVCSAParameters.MgmtESXHosts.split(',') | foreach {$K,$V=$_.split('='); @{$K.trim()=$V}}
    $MgmtvMotionIP = $WorkSheet.Cells.Item(16, 2).Value()
    $MgmtvSANIP    = $WorkSheet.Cells.Item(16, 3).Value()
    $MgmtiSCSIIP   = $WorkSheet.Cells.Item(16, 4).Value()

    # VDS / VLAN Configurations
    $DeployVDS            = $WorkSheet.Cells.Item(20, 1).Value()
    $VDSName              = $WorkSheet.Cells.Item(20, 2).Value()

    # VDS / VLAN Portgroup Configurations
    $VLANMGMTPortgroup     = $WorkSheet.Cells.Item(23, 1).Value()
    $VLANvMotionPortgroup  = $WorkSheet.Cells.Item(23, 2).Value()
    $VLANvSANPortgroup     = $WorkSheet.Cells.Item(23, 3).Value()
    $VLANVMPortgroup       = $WorkSheet.Cells.Item(23, 4).Value()
    $VLANiSCSIPortgroup    = $WorkSheet.Cells.Item(23, 5).Value()
    $VLANTrunkPortgroup    = $WorkSheet.Cells.Item(23, 6).Value()
    $VLANTrunk1Portgroup   = $WorkSheet.Cells.Item(23, 7).Value()
    $VLANTrunk2Portgroup   = $WorkSheet.Cells.Item(23, 8).Value()

        # Not used yet
    # $VDSPortgroupAndVLAN = @{
    #    "Management Network" = $WorkSheet.Cells.Item(10, 2).Value()
    #    "Trunk Network" = $WorkSheet.Cells.Item(10, 3).Value()
    #    "VM Network" = $WorkSheet.Cells.Item(10, 4).Value()
    # }
    $VLANMGMTID     = $WorkSheet.Cells.Item(26, 1).Value()
    $VLANvMotionID  = $WorkSheet.Cells.Item(26, 2).Value()
    $VLANvSANID     = $WorkSheet.Cells.Item(26, 3).Value()
    $VLANVMID       = $WorkSheet.Cells.Item(26, 4).Value()
    $VLANiSCSIID    = $WorkSheet.Cells.Item(26, 5).Value()
    $VLANTrunkID    = $WorkSheet.Cells.Item(26, 6).Value()
    $VLANTrunk1ID   = $WorkSheet.Cells.Item(26, 7).Value()
    $VLANTrunk2ID   = $WorkSheet.Cells.Item(26, 8).Value()
    #

    # NSX Manager Configuration
    $DeployNSX             = $WorkSheet.Cells.Item(29, 1).Value()
    # VDS / VXLAN Configurations (Not used)
    $PrivateVXLANVMNetwork = $WorkSheet.Cells.Item(29, 2).Value() # Not used
    $VXLANDVPortgroup      = $WorkSheet.Cells.Item(29, 3).Value() # Not used
    $VXLANSubnet           = $WorkSheet.Cells.Item(29, 4).Value() # Not used
    $VXLANNetmask          = $WorkSheet.Cells.Item(29, 5).Value() # Not used

    # Enable deployment options
    $preCheck          = $WorkSheet.Cells.Item(33, 1).Value() # Validate VCSA installer location
    $confirmDeployment = $WorkSheet.Cells.Item(33, 2).Value() # Show and validate deployment settings
    $deployVCSA        = $WorkSheet.Cells.Item(33, 3).Value() # Enable VCSA installation
    $setupNewVC        = $WorkSheet.Cells.Item(33, 4).Value() # Enable VCSA post installation
    # Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
    $addHostByDnsName  = $WorkSheet.Cells.Item(33, 5).Value()
    $addESXiHostsToVC  = $WorkSheet.Cells.Item(33, 6).Value() # Enable adding ESXi hosts to vCenter during deployment
    $configurevMotion  = $WorkSheet.Cells.Item(33, 7).Value() # Enable vMotion during deployment
    $configureVSAN = $WorkSheet.Cells.Item(33, 8).Value()
    $setupVXLAN        = $WorkSheet.Cells.Item(33, 9).Value() # Setup VXLAN
    $DeployNSX         = $WorkSheet.Cells.Item(33, 10).Value()
    $configureNSX      = $WorkSheet.Cells.Item(33, 11).Value() # Configure NSX
    # Enable verbose output to a new PowerShell Console. Thanks to suggestion by Christian Mohn
    $enableVerboseLoggingToNewShell = $WorkSheet.Cells.Item(33, 12).Value()

    # vApp Options
    $moveVMsIntovApp   = $WorkSheet.Cells.Item(36, 1).Value() # Enable creation of vApp
    $vAppName          = $WorkSheet.Cells.Item(36, 2).Value() # vApp name
    $VMFolder          = $WorkSheet.Cells.Item(36, 3).Value() # Create folder within VCSA

    # Content Library Creation
    $configureConLib = $WorkSheet.Cells.Item(40, 1).Value() # Enable creation of Content Library
    $ConLibName      = $WorkSheet.Cells.Item(40, 2).Value() # Content Library repository name
    $ConLibDSName    = $WorkSheet.Cells.Item(40, 3).Value() # Datastore for Content Library
    $ISOPath         = $WorkSheet.Cells.Item(40, 4).Value() # Path to ISO files to upload (note it will upload ALL isos found in this folder)
    $release = Clear-Ref($WorkSheet)

    if ($iSCSIEnable -eq 'true') {
        $WorkSheetname = 'Global Settings'
        $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
        $iSCSITarget     = $WorkSheet.Cells.Item(5, 1).Value()
        $iSCSITargetName = $WorkSheet.Cells.Item(5, 2).Value()
        $iSCSIChap       = $WorkSheet.Cells.Item(5, 3).Value()
        $iSCSIMutualChap = $WorkSheet.Cells.Item(5, 4).Value()
        $release = Clear-Ref($WorkSheet)
    }

    $WorkSheetname = 'NSX Information'
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

    $NumDLR = $WorkSheet.Cells.Item(29, 1).Value()
    $NumESG = $WorkSheet.Cells.Item(29, 2).Value()
    $release = Clear-Ref($WorkSheet)

    $WorkSheetname = 'IP Pools'
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
    $release = Clear-Ref($WorkSheet)
    #
    #
    #
    
    $WorkSheetname = 'NSX-T Information'
    $WorkSheet = $WorkBook.Sheets.Item($WorkSheetname)
    $NSXT_MGR_DisplayName  = $WorkSheet.Cells.Item(3, 1).Value() # $NSXTMgrDisplayName
    $NSXT_MGR_Hostname     = $WorkSheet.Cells.Item(3, 2).Value() # $NSXTMgrHostname
    $NSXT_MGR_IP           = $WorkSheet.Cells.Item(3, 3).Value() # $NSXTMgrIPAddress
    $NSXT_MGR_Netmask      = $WorkSheet.Cells.Item(3, 4).Value()
    $NSXT_MGR_Gateway      = $WorkSheet.Cells.Item(3, 5).Value()
    $NSXT_MGR_DNSServer    = $WorkSheet.Cells.Item(3, 6).Value() # $VMDNS
    $NSXT_MGR_DNSDomain    = $WorkSheet.Cells.Item(3, 7).Value() # $VMDomain
    $NSXT_MGR_NTPServer    = $WorkSheet.Cells.Item(3, 8).Value() # $VMNTP

    $NSXT_MGR_RootEnable      = $WorkSheet.Cells.Item(6, 1).Value()
    $NSXT_MGR_Root_Password   = $WorkSheet.Cells.Item(6, 2).Value()
    $NSXT_MGR_Admin_Username  = $WorkSheet.Cells.Item(6, 3).Value()
    $NSXT_MGR_Admin_Password  = $WorkSheet.Cells.Item(6, 4).Value()
    $NSXT_MGR_Audit_Username  = $WorkSheet.Cells.Item(6, 5).Value()
    $NSXT_MGR_Admin_Password  = $WorkSheet.Cells.Item(6, 6).Value()
    $NSXT_Mgr_SSHEnable       = $WorkSheet.Cells.Item(6, 7).Value()
    $NSXT_Mgr_CEIPEnable      = $WorkSheet.Cells.Item(6, 8).Value()
    $NSXT_MGR_RoleName        = $WorkSheet.Cells.Item(9, 1).Value()
    $NSXT_Mgr_Size            = $WorkSheet.Cells.Item(9, 2).Value()
    $NSXT_Mgr_vCPU            = $WorkSheet.Cells.Item(9, 3).Value()
    $NSXT_Mgr_vMem            = $WorkSheet.Cells.Item(9, 4).Value()

    $NSXT_VC_IP        = $WorkSheet.Cells.Item(10, 1).Value()
    $NSXT_VC_Username  = $WorkSheet.Cells.Item(10, 2).Value()
    $NSXT_VC_Password  = $WorkSheet.Cells.Item(10, 3).Value()
    $NSXT_VC_Cluster   = $WorkSheet.Cells.Item(10, 4).Value()
    $NSXT_VC_Network   = $WorkSheet.Cells.Item(10, 5).Value()
    $NSXT_VC_Datastore = $WorkSheet.Cells.Item(10, 6).Value()
    $NSXT_VC_Folder    = $WorkSheet.Cells.Item(10, 7).Value()
    $NSXT_License_Key  = $WorkSheet.Cells.Item(13, 8).Value()
    $release = Clear-Ref($WorkSheet)
}

#### DO NOT EDIT BEYOND HERE ####
#$VIServerShort = $VIServer.Substring(0,$VIServer.IndexOf("."))
$verboseLogFile = 'vsphere67-Physical-Manage-VCSA-Deployment.log'
$vSphereVersion = '6.7'
# Not used - $deploymentType - Placeholder
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

# Import RestAPI functions for NSX
. $ScriptPath'Install-NSX-Functions.ps1'

if($preCheck -eq 'True') {
    if(!(Test-Path $VCSAInstallerPath)) {
        Write-Host -ForegroundColor Red "`nUnable to find $VCSAInstallerPath ...`nexiting"
        exit
    }
}

if($DeployNSX -eq 'True') {
    if(!(Test-Path $NSX_Mgr_OVA)) {
        Write-Host -ForegroundColor Red "`nUnable to find $NSX_Mgr_OVA ...`nexiting"
        exit
    }

    if(-not (Get-Module -Name "PowerNSX")) {
        Write-Host -ForegroundColor Red "`nPowerNSX Module is not loaded, please install and load PowerNSX before running script ...`nexiting"
        # exit
    }
}

if($confirmDeployment -eq 'True') {
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

    if($DeployNSX -eq 'True') {
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

    if($DeployNSX -eq 'True' -and $setupVXLAN -eq 'True') {
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

    if($Workload -eq "Worker") {
        Write-Host -ForegroundColor Yellow "`n-------------------- Nested ESX Configuration -------------------"
        Write-Host -NoNewline -ForegroundColor Green "Number of Nested ESX host to deploy: "
        Write-Host -ForegroundColor White $NestedCount
        Write-Host -NoNewline -ForegroundColor Green "vCPU per Nested host: "
        Write-Host -NoNewline -ForegroundColor White $Nested_CPU[0]
        Write-Host -NoNewline -ForegroundColor Green "           vMem per Nested host: "
        Write-Host -ForegroundColor White $Nested_Mem[0]
        Write-Host -NoNewline -ForegroundColor Green "Cache per Nested host: "
        Write-Host -NoNewline -ForegroundColor White $Nested_CacheDisk[0]
        Write-Host -NoNewline -ForegroundColor Green "        Capacity per Nested host: "
        Write-Host -ForegroundColor White $Nested_CapacityDisk[0]
    }

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

    if($DeployVDS -eq 'True') {
        Write-Host -ForegroundColor Yellow "`n----------------------- VDS Configuration -----------------------"
        Write-Host -NoNewline -ForegroundColor Green "VDS Name: "
        Write-Host -ForegroundColor White $VDSName
        Write-Host -NoNewline -ForegroundColor Green "Management Portgroup: "
        Write-Host -ForegroundColor White $VLANMGMTID
        Write-Host -NoNewline -ForegroundColor Green "vMotion Portgroup: "
        Write-Host -ForegroundColor White $VLANvMotionID
        Write-Host -NoNewline -ForegroundColor Green "vSAN Portgroup: "
        Write-Host -ForegroundColor White $VLANvSANID
        Write-Host -NoNewline -ForegroundColor Green "Virtual Machine Portgroup: "
        Write-Host -ForegroundColor White $VLANVMID
        Write-Host -NoNewline -ForegroundColor Green "iSCSI Portgroup: "
        Write-Host -ForegroundColor White $VLANiSCSIID
        Write-Host -NoNewline -ForegroundColor Green "VLAN Back Trunk Portgroup: "
        Write-Host -ForegroundColor White $VLANTrunkID
        Write-Host -NoNewline -ForegroundColor Green "NSX Trunk1 Portgroup: "
        Write-Host -ForegroundColor White $VLANTrunk2ID
        Write-Host -NoNewline -ForegroundColor Green "NSX Trunk2 Portgroup: "
        Write-Host -ForegroundColor White $VLANTrunk2ID
    }

    if($DeployNSX -eq 'True' -and $setupVXLAN -eq 'True') {
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

    if($configureConLib -eq 'True') {
        Write-Host -ForegroundColor Yellow "`n---------------- Content Library Configuration ------------------"
        Write-Host -NoNewline -ForegroundColor Green "Repository Name: "
        Write-Host -ForegroundColor White $ConLibName
        Write-Host -NoNewline -ForegroundColor Green "Content Library Datastore: "
        Write-Host -ForegroundColor White $ConLibDSName
        Write-Host -NoNewline -ForegroundColor Green "Path to upload ISO: "
        Write-Host -ForegroundColor White $ISOPath
    }

    if($moveVMsIntovApp -eq 'True') {
        Write-Host -ForegroundColor Yellow "`n--------------------- vApp Configuration ------------------------"
        Write-Host -NoNewline -ForegroundColor Green "vApp Name: "
        Write-Host -ForegroundColor White $vAppName
        Write-Host -NoNewline -ForegroundColor Green "VM Folder Name: "
        Write-Host -ForegroundColor White $VMFolder
    }

    if($DeployNSX -eq 'True') {
        Write-Host -ForegroundColor Yellow "`n------------------- NSX Manager Configuration -------------------"
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

    if($ConfigureNSX -eq 'True') {
        Write-Host -ForegroundColor Yellow "`n----------------------- NSX Configuration -----------------------"
        Write-Host -NoNewline -ForegroundColor Green "Number of NSX controller to deploy: "
        Write-Host -ForegroundColor White $NSX_Controllers_Amount
        Write-Host -NoNewline -ForegroundColor Green "VLAN ID for VXLAN: "
        Write-Host -NoNewline -ForegroundColor White $NSX_VXLAN_VLANID
        Write-Host -NoNewline -ForegroundColor Green "             VTEP per ESX host: "
        Write-Host -ForegroundColor White $NSX_VXLAN_VTEP_Count 
        Write-Host -NoNewline -ForegroundColor Green "Segment ID (VNI) range: "
        Write-Host -NoNewline -ForegroundColor White $NSX_VXLAN_Segment_ID_Begin
        Write-Host -NoNewline -ForegroundColor Green " to "
        Write-Host -ForegroundColor White $NSX_VXLAN_Segment_ID_End
        Write-Host -NoNewline -ForegroundColor Green "Transport Zone Name: "
        Write-Host -NoNewline -ForegroundColor White $NSX_VXLAN_TZ_Name
        Write-Host -NoNewline -ForegroundColor Green "   Transport Zone Mode: "
        Write-Host -ForegroundColor White $NSX_VXLAN_TZ_Mode
        Write-Host -NoNewline -ForegroundColor Green "DLR to Deploy: "
        Write-Host -NoNewline -ForegroundColor White $NumDLR
        Write-Host -NoNewline -ForegroundColor Green "                  ESG to Deploy: "
        Write-Host -ForegroundColor White $NumESG
    }

    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
    $ESXHost = Get-VMHost -Name $VIServer
    $esxiTotalCPU = $ESXHost.NumCpu
    $esxiTotalMemory = [math]::Round($ESXHost.MemoryTotalGB,0)
    $esxiTotalStorage = [math]::Round((Get-Datastore -Name $VMDatastore).FreeSpaceGB,0)

    $NestedesxiTotalCPU = $NestedCount * [int]$Nested_CPU[0]
    $NestedesxiTotalMemory = $NestedCount * [int]$Nested_Mem[0]
    $NestedesxiTotalStorage = ($NestedCount * [int]$Nested_CacheDisk[0]) + ($NestedCount * [int]$Nested_CapacityDisk[0])
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
    if($DeployNSX -eq 'True') {
        Write-Host -NoNewline -ForegroundColor Green "NSX VM CPU: "
        Write-Host -NoNewline -ForegroundColor White $nsxTotalCPU
        Write-Host -NoNewline -ForegroundColor Green "      NSX Memory: "
        Write-Host -NoNewline -ForegroundColor White $nsxTotalMemory "GB "
        Write-Host -NoNewline -ForegroundColor Green "         NSX VM Storage: "
        Write-Host -ForegroundColor White $nsxTotalStorage "GB"
    }
    if($Workload -eq "Worker") {
        Write-Host -NoNewline -ForegroundColor Green "Nested ESX CPU: "
        Write-Host -NoNewline -ForegroundColor White $NestedesxiTotalCPU
        Write-Host -NoNewline -ForegroundColor Green " Nested ESX Memory: "
        Write-Host -NoNewline -ForegroundColor White $NestedesxiTotalMemory "GB "
        Write-Host -NoNewline -ForegroundColor Green " Nested ESx Storage: "
        Write-Host -ForegroundColor White $NestedesxiTotalStorage "GB"
    }
        Write-Host -ForegroundColor Yellow "---------------------------------------------------------------------------"
        Write-Host -NoNewline -ForegroundColor Green "Total CPU: "
        Write-Host -NoNewline  -ForegroundColor White ([int]$vcsaTotalCPU + [int]$nsxTotalCPU + [int]$NestedesxiTotalCPU)
        Write-Host -NoNewline -ForegroundColor Green "      Total Memory: "
        Write-Host -NoNewline  -ForegroundColor White ([int]$vcsaTotalMemory + [int]$nsxTotalMemory + [int]$NestedesxiTotalMemory) "GB"
        Write-Host -NoNewline -ForegroundColor Green "      Total Storage: "
        Write-Host -ForegroundColor White ([int]$vcsaTotalStorage + [int]$nsxTotalStorage + [int]$NestedesxiTotalStorage) "GB"

    Write-Host -ForegroundColor Red "`nWould you like to proceed with this deployment?`n"
    $answer = Read-Host -Prompt "Do you accept (Y or N)"
    if($answer -ne "Y" -or $answer -ne "y") {
        exit
    }
    Clear-Host
    # Set temporary host record on deployment laptop/desktop to mitigate if ESX host not added to DNS
    # "$VIServerIP  $VIServer" | Add-Content -PassThru $hostfile
}

My-Logger "Connecting to $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
# $VCSAIPAddress = '192.168.10.32'
# $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

$ESXHost = Get-VMHost -Name $VIServer
$ESXState = $ESXHost.ConnectionState
if($ESXState -eq "Maintenance") {
    My-Logger "Host '$VIServer' is in Maintenance Mode ..."
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
    $network = Get-VDPortgroup -Server $vc -Name $VLANTrunkPortgroup
}

$VMVMFS = $false
if($Workload -eq "Worker") {
    if($DeploymentTarget -eq "ESXI") {
        for ($NestedIndex=0; $NestedIndex -lt $NestedCount; $NestedIndex++ ) {

            $Nested_Hostname     = $NestedESXParameters[$NestedIndex].Nested_Hostname
            $Nested_CPU          = $NestedESXParameters[$NestedIndex].Nested_CPU
            $Nested_Mem          = $NestedESXParameters[$NestedIndex].Nested_Mem
            $Nested_CacheDisk    = $NestedESXParameters[$NestedIndex].Nested_CacheDisk
            $Nested_CapacityDisk = $NestedESXParameters[$NestedIndex].Nested_CapacityDisk
            $Nested_IP           = $NestedESXParameters[$NestedIndex].Nested_IP
            $Nested_Subnet       = $NestedESXParameters[$NestedIndex].Nested_Subnet
            $Nested_GW           = $NestedESXParameters[$NestedIndex].Nested_GW
            $Nested_MgmtVLAN     = $NestedESXParameters[$NestedIndex].Mgmt_VLAN
            $Nested_vMotionIP    = $NestedESXParameters[$NestedIndex].vMotion_IP
            $Nested_vMotionMask  = $Nested_Subnet
            $Nested_vMotionVLAN  = $NestedESXParameters[$NestedIndex].vMotion_VLAN
            $Nested_vSANIP       = $NestedESXParameters[$NestedIndex].vSAN_IP
            $Nested_vSANVLAN     = $NestedESXParameters[$NestedIndex].vSAN_VLAN
            $Nested_vSANMask     = $Nested_Subnet
            $Nested_VMVLAN       = $NestedESXParameters[$NestedIndex].VM_VLAN
            $Nested_iSCSIVLAN    = $NestedESXParameters[$NestedIndex].iSCSI_VLAN
            $Nested_DNS1         = $NestedESXParameters[$NestedIndex].Nested_DNS1
            $Nested_DNS2         = $NestedESXParameters[$NestedIndex].Nested_DNS2
            $Nested_PW           = $NestedESXParameters[$NestedIndex].Nested_PW
            $Nested_Domain       = $NestedESXParameters[$NestedIndex].Nested_Domain

            My-Logger "Deploying Nested ESXi VM $Nested_Hostname ..."
            $vm = Import-VApp -Server $viConnection -Source $NestedESXiApplianceOVF -Name $Nested_Hostname `
            -VMHost $VIServer -Datastore $VMDatastore -DiskStorageFormat thin
            
            My-Logger "Updating VM Network ..." 
            $vm | Get-NetworkAdapter -Name "Network Adapter 1" | Set-NetworkAdapter -Portgroup $network -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            $vm | Get-NetworkAdapter -Name "Network Adapter 2" | Set-NetworkAdapter -Portgroup $network -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            
            if($DeployNSX -eq $false) {
                $vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $privateNetwork -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            } else {
                $vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $VLANTrunkPortgroup -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            }

            My-Logger "Updating vCPU Count to $Nested_CPU & vMEM to $Nested_Mem GB ..."
            Set-VM -Server $viConnection -VM $Nested_Hostname -NumCpu $Nested_CPU -MemoryGB $Nested_Mem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Caching VMDK size to $Nested_CacheDisk GB ..."
            Get-HardDisk -Server $viConnection -VM $Nested_Hostname -Name "Hard disk 2" | Remove-HardDisk -DeletePermanently -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            New-HardDisk -Server $viConnection -VM $Nested_Hostname -Datastore "SSD_VSAN" -CapacityGB $Nested_CacheDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            #Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Capacity VMDK size to $Nested_CapacityDisk GB ..."
            Get-HardDisk -Server $viConnection -VM $Nested_Hostname -Name "Hard disk 2" | Remove-HardDisk -DeletePermanently -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            New-HardDisk -Server $viConnection -VM $Nested_Hostname -Datastore "HDD_VSAN" -CapacityGB $Nested_CapacityDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            #Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating with 2 additional NIC - (vmnic2 and vmnic3) ..."
            New-NetworkAdapter -Server $viConnection -VM $Nested_Hostname -NetworkName $network -StartConnected -Type Vmxnet3 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            New-NetworkAdapter -Server $viConnection -VM $Nested_Hostname -NetworkName $network -StartConnected -Type Vmxnet3 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            $orignalExtraConfig = $vm.ExtensionData.Config.ExtraConfig
            $a = New-Object VMware.Vim.OptionValue
            $a.key = "guestinfo.hostname"
            $a.value = $Nested_Hostname
            $b = New-Object VMware.Vim.OptionValue
            $b.key = "guestinfo.ipaddress"
            $b.value = $Nested_IP
            $c = New-Object VMware.Vim.OptionValue
            $c.key = "guestinfo.netmask"
            $c.value = $Nested_Subnet
            $d = New-Object VMware.Vim.OptionValue
            $d.key = "guestinfo.gateway"
            $d.value = $Nested_GW
            $e = New-Object VMware.Vim.OptionValue
            $e.key = "guestinfo.dns"
            $e.value = $Nested_DNS1 # $VMDNS
            $f = New-Object VMware.Vim.OptionValue
            $f.key = "guestinfo.domain"
            $f.value = $Nested_Domain # $VMDomain
            $g = New-Object VMware.Vim.OptionValue
            $g.key = "guestinfo.ntp"
            $g.value = $VMNTP
            $h = New-Object VMware.Vim.OptionValue
            $h.key = "guestinfo.syslog"
            $h.value = $VMSyslog
            $i = New-Object VMware.Vim.OptionValue
            $i.key = "guestinfo.password"
            $i.value = $Nested_PW # $VMPassword
            $j = New-Object VMware.Vim.OptionValue
            $j.key = "guestinfo.ssh"
            $j.value = "$VCSASSHEnable" # $VMSSH
            $k = New-Object VMware.Vim.OptionValue
            $k.key = "guestinfo.vlan"
            $k.value = "$Nested_MgmtVLAN"
            $l = New-Object VMware.Vim.OptionValue
            $l.key = "guestinfo.createvmfs"
            $l.value = "$VMVMFS"
            $m = New-Object VMware.Vim.OptionValue
            $m.key = "ethernet1.filter4.name"
            $m.value = "dvfilter-maclearn"
            $n = New-Object VMware.Vim.OptionValue
            $n.key = "ethernet1.filter4.onFailure"
            $n.value = "failOpen"
            $o = New-Object VMware.Vim.OptionValue
            $o.key = "ethernet2.filter4.name"
            $o.value = "dvfilter-maclearn"
            $p = New-Object VMware.Vim.OptionValue
            $p.key = "ethernet2.filter4.onFailure"
            $p.value = "failOpen"
            $q = New-Object VMware.Vim.OptionValue
            $q.key = "ethernet3.filter4.name"
            $q.value = "dvfilter-maclearn"
            $r = New-Object VMware.Vim.OptionValue
            $r.key = "ethernet3.filter4.onFailure"
            $r.value = "failOpen"

            $orignalExtraConfig+=$a
            $orignalExtraConfig+=$b
            $orignalExtraConfig+=$c
            $orignalExtraConfig+=$d
            $orignalExtraConfig+=$e
            $orignalExtraConfig+=$f
            $orignalExtraConfig+=$g
            $orignalExtraConfig+=$h
            $orignalExtraConfig+=$i
            $orignalExtraConfig+=$j
            $orignalExtraConfig+=$k
            $orignalExtraConfig+=$l
            $orignalExtraConfig+=$m
            $orignalExtraConfig+=$n
            $orignalExtraConfig+=$o
            $orignalExtraConfig+=$p
            $orignalExtraConfig+=$q

            $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
            $spec.ExtraConfig = $orignalExtraConfig

            My-Logger "Adding guestinfo customization properties to $Nested_Hostname ..."
            $task = $vm.ExtensionData.ReconfigVM_Task($spec)
            $task1 = Get-Task -Server $viConnection -Id ("Task-$($task.value)")
            $task1 | Wait-Task | Out-Null

            My-Logger "Powering On $Nested_Hostname ..."
            Start-VM -Server $viConnection -VM $vm -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    } else {
        for ($NestedIndex=0; $NestedIndex -lt $NestedCount; $NestedIndex++ ) { 
            
            $Nested_Hostname     = $NestedESXParameters[$NestedIndex].Nested_Hostname
            $Nested_CPU          = $NestedESXParameters[$NestedIndex].Nested_CPU
            $Nested_Mem          = $NestedESXParameters[$NestedIndex].Nested_Mem
            $Nested_CacheDisk    = $NestedESXParameters[$NestedIndex].Nested_CacheDisk
            $Nested_CapacityDisk = $NestedESXParameters[$NestedIndex].Nested_CapacityDisk
            $Nested_IP           = $NestedESXParameters[$NestedIndex].Nested_IP
            $Nested_Subnet       = $NestedESXParameters[$NestedIndex].Nested_Subnet
            $Nested_GW           = $NestedESXParameters[$NestedIndex].Nested_GW
            $Nested_MgmtVLAN     = $NestedESXParameters[$NestedIndex].Mgmt_VLAN
            $Nested_vMotionIP    = $NestedESXParameters[$NestedIndex].vMotion_IP
            $Nested_vMotionMask  = $Nested_Subnet
            $Nested_vMotionVLAN  = $NestedESXParameters[$NestedIndex].vMotion_VLAN
            $Nested_vSANIP       = $NestedESXParameters[$NestedIndex].vSAN_IP
            $Nested_vSANVLAN     = $NestedESXParameters[$NestedIndex].vSAN_VLAN
            $Nested_vSANMask     = $Nested_Subnet
            $Nested_VMVLAN       = $NestedESXParameters[$NestedIndex].VM_VLAN
            $Nested_iSCSIVLAN    = $NestedESXParameters[$NestedIndex].iSCSI_VLAN
            $Nested_DNS1         = $NestedESXParameters[$NestedIndex].Nested_DNS1
            $Nested_DNS2         = $NestedESXParameters[$NestedIndex].Nested_DNS2
            $Nested_PW           = $NestedESXParameters[$NestedIndex].Nested_PW
            $Nested_Domain       = $NestedESXParameters[$NestedIndex].Nested_Domain

            $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
            $networkMapLabel = ($ovfconfig.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
            $ovfconfig.NetworkMapping.$networkMapLabel.value = $VLANTrunkPortgroup

            $ovfconfig.common.guestinfo.hostname.value = $Nested_Hostname
            $ovfconfig.common.guestinfo.ipaddress.value = $Nested_IP
            $ovfconfig.common.guestinfo.netmask.value = $Nested_Subnet
            $ovfconfig.common.guestinfo.gateway.value = $Nested_GW
            $ovfconfig.common.guestinfo.dns.value = $Nested_DNS1 # $VMDNS
            $ovfconfig.common.guestinfo.domain.value = $Nested_Domain
            $ovfconfig.common.guestinfo.ntp.value = $VMNTP
            $ovfconfig.common.guestinfo.syslog.value = $VMSyslog
            $ovfconfig.common.guestinfo.password.value = $Nested_PW
            $ovfconfig.common.guestinfo.vlan.value = $Nested_MgmtVLAN
            if($VMSSH -eq "true") {
                $VMSSHVar = $true
            } else {
                $VMSSHVar = $false
            }
            $ovfconfig.common.guestinfo.ssh.value = $VCSASSHEnable
            #
            # these are not set for OVA
            #
            # $k = New-Object VMware.Vim.OptionValue
            # $k.key = "guestinfo.createvmfs"
            # $k.value = $VMVMFS
            # $l = New-Object VMware.Vim.OptionValue
            # $l.key = "ethernet1.filter4.name"
            # $l.value = "dvfilter-maclearn"
            # $m = New-Object VMware.Vim.OptionValue
            # $m.key = "ethernet1.filter4.onFailure"
            # $m.value = "failOpen"
            
            My-Logger "Deploying Nested ESXi VM - $Nested_Hostname ..."
            if($DeploymentTarget -eq "VMC") {
                $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $Nested_Hostname -Location $resourcePool -VMHost $VIServer -Datastore $VMDatastore -DiskStorageFormat thin -InventoryLocation $folder
            } else {
                $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $Nested_Hostname -Location $NewVCVSANClusterName -VMHost $VIServer -Datastore $VMDatastore -DiskStorageFormat thin
            }

            if($DeployNSX -eq 1) {
                My-Logger "Connecting Eth1 to $privateNetwork ..."
                $vm | Get-NetworkAdapter -Name "Network adapter 2" | Set-NetworkAdapter -Portgroup $privateNetwork -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            }

            My-Logger "Updating vCPU count to $Nested_CPU & vMEM to $Nested_Mem GB ..."
            Set-VM -Server $vc -VM $Nested_Hostname -NumCpu $Nested_CPU -MemoryGB $Nested_Mem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            # Get-HardDisk -Server $vc -VM $Nested_Hostname -Name "Hard disk 1" | Set-HardDisk -CapacityGB 10
            My-Logger "Updating vSAN Caching VMDK size to $Nested_CacheDisk GB ..."
            Get-HardDisk -Server $vc -VM $Nested_Hostname -Name "Hard disk 2" | Remove-HardDisk -DeletePermanently -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            New-HardDisk -Server $vc -VM $Nested_Hostname -Datastore "SSD_VSAN" -CapacityGB $Nested_CacheDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating vSAN Capacity VMDK size to $Nested_CapacityDisk GB ..."
            Get-HardDisk -Server $vc -VM $Nested_Hostname -Name "Hard disk 2" | Remove-HardDisk -DeletePermanently -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            New-HardDisk -Server $vc -VM $Nested_Hostname -Datastore "HDD_VSAN" -CapacityGB $Nested_CapacityDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            My-Logger "Updating with 2 additional NIC - (vmnic2 and vmnic3) ..."
            New-NetworkAdapter -Server $vc -VM $Nested_Hostname -NetworkName $network -StartConnected -Type Vmxnet3 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            New-NetworkAdapter -Server $vc -VM $Nested_Hostname -NetworkName $network -StartConnected -Type Vmxnet3 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            # New-NetworkAdapter -Server $vc -VM $Nested_Hostname -Portgroup $VMNetwork -StartConnected -Type Vmxnet3 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

            $orignalExtraConfig = $vm.ExtensionData.Config.ExtraConfig
            $a = New-Object VMware.Vim.OptionValue
            $a.key = "ethernet2.filter4.name"
            $a.value = "dvfilter-maclearn"
            $b = New-Object VMware.Vim.OptionValue
            $b.key = "ethernet2.filter4.onFailure"
            $b.value = "failOpen"
            $c = New-Object VMware.Vim.OptionValue
            $c.key = "ethernet3.filter4.name"
            $c.value = "dvfilter-maclearn"
            $d = New-Object VMware.Vim.OptionValue
            $d.key = "ethernet3.filter4.onFailure"
            $d.value = "failOpen"
            $orignalExtraConfig+=$a
            $orignalExtraConfig+=$b
            $orignalExtraConfig+=$c
            $orignalExtraConfig+=$d

            $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
            $spec.ExtraConfig = $orignalExtraConfig

            My-Logger "Adding guestinfo customization properties to '$Nested_Hostname' ..."
            $task = $vm.ExtensionData.ReconfigVM_Task($spec)
            $task1 = Get-Task -Id ("Task-$($task.value)")
            $task1 | Wait-Task | Out-Null

            My-Logger "Powering On Nested VM - $Nested_Hostname ..."
            $vm | Start-Vm -RunAsync | Out-Null
        }
    }
}

if($deployVCSA -eq 'True') {
    if ($Workload -eq 'Worker') {
        $vc = Connect-VIServer $VCSAManager -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue
        $vds = GEt-VDSwitch -Server $vc -Name $VDSName
        $VLANMGMTPortgroup = "VCSA-"+$Nested_MgmtVLAN
        My-Logger "Creating new DVPortgroup '$VLANMGMTPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANMGMTPortgroup -Vds $vds -NumPorts 8 -VlanId $Nested_MgmtVLAN -PortBinding Ephemeral
    }
    if($DeploymentTarget -eq 'ESXI') {
        # Deploy using the VCSA CLI Installer
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_ESXi.json") | convertfrom-json
        $config.new_vcsa.esxi.hostname = $VIServer
        $config.new_vcsa.esxi.username = $VIUsername
        $config.new_vcsa.esxi.password = $VIPassword
        $config.new_vcsa.esxi.deployment_network = $VMNetwork
        $config.new_vcsa.esxi.datastore = $VMDatastore
        $config.new_vcsa.appliance.thin_disk_mode = $true
        $config.new_vcsa.appliance.deployment_option = $VCSADeploymentSize
        $config.new_vcsa.appliance.name = $VCSADisplayName
        $config.new_vcsa.network.ip_family = 'ipv4'
        $config.new_vcsa.network.mode = 'static'
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
        $config.ceip.settings.ceip_enabled = $false

        My-Logger "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

        if($enableVerboseLoggingToNewShell -eq 'true') {
            My-Logger "Spawning new PowerShell Console for detailed verbose output ..."
            Start-process powershell.exe -argument "-nologo -noprofile -executionpolicy bypass -command Get-Content $verboseLogFile -Tail 2 -Wait"
        }

        My-Logger "Deploying VCSA - $VCSAHostname ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile

    } else {
    # https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vcenter.install.doc/GUID-457EAE1F-B08A-4E64-8506-8A3FA84A0446.html
    # https://www.jeffreykusters.nl/2020/05/06/detailed-write-up-on-my-vmware-vsphere-7-nested-homelab-networking-setup/
        # Deploy using the VCSA CLI Installer
        $config = (Get-Content -Raw "$($VCSAInstallerPath)\vcsa-cli-installer\templates\install\embedded_vCSA_on_VC.json") | convertfrom-json
        $config.new_vcsa.vc.hostname = $VCSAManager # need update $VIServer = '192.168.10.32'
        $config.new_vcsa.vc.username = "administrator@$VCSASSODomainName" # need update $VIUsername = 'administrator@vsphere.local'
        $config.new_vcsa.vc.password = $VCSASSOPassword # $VIPassword 
        $config.new_vcsa.vc.deployment_network = $VLANMGMTPortgroup # $VMNetwork # need update $VMNetwork = 'VCSA'
        $config.new_vcsa.vc.datastore = $VMDatastore
        $config.new_vcsa.vc.datacenter = $NewVCDatacenterName # $datacenter.name
        $config.new_vcsa.vc.target = $NewVCVSANClusterName # $cluster
        $config.new_vcsa.appliance.thin_disk_mode = $true
        $config.new_vcsa.appliance.deployment_option = $VCSADeploymentSize
        $config.new_vcsa.appliance.name = $VCSADisplayName
        $config.new_vcsa.network.ip_family = 'ipv4'
        $config.new_vcsa.network.mode = 'static'
        $config.new_vcsa.network.ip = $VCSAIPAddress # $VCSAIPAddress = '172.16.10.20'
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
        # $config.new_vcsa.os.time_tools_sync = $true # set this to ignore VMNTP, vSphere 7  
        $config.new_vcsa.os.ssh_enable = $VCSASSHEnableVar
        $config.new_vcsa.sso.password = $VCSASSOPassword
        $config.new_vcsa.sso.domain_name = $VCSASSODomainName
        $config.ceip.settings.ceip_enabled = $false

        My-Logger "Creating VCSA JSON Configuration file for deployment ..."
        $config | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\jsontemplate.json"

        if($enableVerboseLoggingToNewShell -eq 'True') {
            My-Logger "Spawning new PowerShell Console for detailed verbose output ..."
            Start-process powershell.exe -argument "-nologo -noprofile -executionpolicy bypass -command Get-Content $verboseLogFile -Tail 2 -Wait"
        }

        My-Logger "Deploying VCSA - $VCSAHostname ..."
        Invoke-Expression "$($VCSAInstallerPath)\vcsa-cli-installer\win32\vcsa-deploy.exe install --no-ssl-certificate-verification --accept-eula --acknowledge-ceip $($ENV:Temp)\jsontemplate.json"| Out-File -Append -LiteralPath $verboseLogFile
    }
}

My-Logger "Disconnecting from $VIServer ..."
Disconnect-VIServer $viConnection -Confirm:$false
Disconnect-VIServer $vc -Confirm:$false

# Remove earlier temporary host record on deployment laptop/desktop
# (Get-Content $hostfile) -notmatch $VIServer | Set-Content $hostfile

if($setupNewVC -eq 'True') {
    My-Logger "Connecting to the new VCSA - $VCSADisplayName ..."
    $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

    My-Logger "Creating Datacenter - '$NewVCDatacenterName' ..."
    New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile
    
    My-Logger "Creating Cluster - '$NewVCVSANClusterName' ..."
    New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled | Out-File -Append -LiteralPath $verboseLogFile

    if($addESXiHostsToVC -eq 'True') {
        $i = 0
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $VMName = $_.Key
            $VMIPAddress = $_.Value
            #$VMName = $NestedESXiHostnameToIPs[$i].Keys
            #$VMIPAddress = $NestedESXiHostnameToIPs[$i].Values
            $targetVMHost = $VMIPAddress
            if($addHostByDnsName -eq 'true') {
                $targetVMHost = $VMName 
            }
            My-Logger "Adding ESXi host '$targetVMHost' to Cluster - $NewVCVSANClusterName ..."
            Add-VMHost -Server $vc -Name $targetVMHost -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Force | Out-File -Append -LiteralPath $verboseLogFile
        $i++
        }
    }
    
    if($DeployVDS -eq 'True') {
        # Create VDS switch
        My-Logger "Creating VDS - $VDSName ..."
        $vds = New-VDSwitch -Server $vc -Name $VDSName -Location (Get-Datacenter -Name $NewVCDatacenterName) -LinkDiscoveryProtocol LLDP -LinkDiscoveryProtocolOperation Listen -MaxPorts 128 -Version 6.6.0 -MTU 9000 -NumUplinkPorts 4
        My-Logger "Enable Network IO Control on VDS - $VDSName ..."
        (Get-VDSwitch $VDSName | Get-View).EnableNetworkResourceManagement($true)
        # Create DVPortgroup
        My-Logger "Creating new DVPortgroup '$VLANMGMTPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANMGMTPortgroup -Vds $vds -NumPorts 24 -VlanId $VLANMGMTID -PortBinding Ephemeral
        My-Logger "Creating new DVPortgroup '$VLANvMotionPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANvMotionPortgroup -Vds $vds -NumPorts 24 -VlanId $VLANvMotionID -PortBinding Static
        if($Workload -eq 'Worker') {
            My-Logger "Creating new DVPortgroup '$VLANvSANPortgroup' ..."
            New-VDPortgroup -Server $vc -Name $VLANvSANPortgroup -Vds $vds -NumPorts 24 -VlanTrunkRange $VLANvSANID -PortBinding Static
        }
        My-Logger "Creating new DVPortgroup '$VLANVMPortgroup' ..."
        New-VDPortgroup -Server $vc -Name $VLANVMPortgroup -Vds $vds -NumPorts 24 -VlanTrunkRange $VLANVMID -PortBinding Static
        if ($iSCSIEnable -eq 'True') {
            My-Logger "Creating new DVPortgroup '$VLANiSCSIPortgroup' ..."
            New-VDPortgroup -Server $vc -Name $VLANiSCSIPortgroup -Vds $vds -NumPorts 24 -VlanId $VLANiSCSIID -PortBinding Static
        }
        if($Workload -ne 'Worker') {
            My-Logger "Creating new DVPortgroup '$VLANTrunkPortgroup' ..."
            New-VDPortgroup -Server $vc -Name $VLANTrunkPortgroup -Vds $vds -NumPorts 24 -VlanTrunkRange $VLANTrunkID -PortBinding Static
        }
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
            
            # Set VDS uplinks from 2 (default) to 4
            # Set-VDSwitch -Vds $vds -NumUplinkPorts 4

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
            #### backup $config.proxySwitch[0].spec.backing.pnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
            $config.proxySwitch[0].spec.backing.pnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (4)
            $config.proxySwitch[0].spec.backing.pnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
            $config.proxySwitch[0].spec.backing.pnicSpec[0].pnicDevice = "vmnic1"
            $config.proxySwitch[0].spec.backing.pnicSpec[0].uplinkPortKey = ($uplinks | where {$_.Name -eq "dvUplink2"}).key

            $config.proxySwitch[0].spec.backing.pnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec # new
            $config.proxySwitch[0].spec.backing.pnicSpec[1].pnicDevice = "vmnic2"
            $config.proxySwitch[0].spec.backing.pnicSpec[1].uplinkPortKey = ($uplinks | where {$_.Name -eq "dvUplink3"}).key

            $config.proxySwitch[0].spec.backing.pnicSpec[2] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec # new
            $config.proxySwitch[0].spec.backing.pnicSpec[2].pnicDevice = "vmnic3"
            $config.proxySwitch[0].spec.backing.pnicSpec[2].uplinkPortKey = ($uplinks | where {$_.Name -eq "dvUplink4"}).key

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
            $vmk = Get-VMHostNetworkAdapter -Name vmk0 -VMHost $vmhost
            My-Logger "Migrate '$vmhostname' VMkernel interface - $vmk to VDS '$VDSName' ..."
            Set-VMHostNetworkAdapter -PortGroup $VLANMGMTPortgroup -VirtualNic $vmk -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            
            # Migrating Virtual Machines from vSwitch to VDS if Virtual Machines exist on Host
            My-Logger "Migrate Virtual Machine from VSS to 'VDS '$VDSName' if VMs exist ..."
            My-Logger "Check to see if VMs exist on host '$vmhostname' ..."
            $VMonHost = (Get-VM).count
            if($VMonHost -gt 0) { 
                My-Logger "$VMonHost Virtual Machines on host '$vmhostname' will be migrate to DVS ..."
                $vdPortgroup = Get-VDPortGroup -VDSwitch (Get-VDSwitch -Name $VDSName) -Name $VLANVMPortgroup
                Get-VM -Location $vmhostname | Get-NetworkAdapter | where { $_.NetworkName -eq $VMNetwork } | Set-NetworkAdapter -Portgroup $vdPortgroup -confirm:$false #did not work as it detect 2 entries
            }

            My-Logger "Removing legacy Standard Switch - vSwitch0 on $vmhostname ..."
            # code for removing portgroup on vSwitch0 if needed below
            #
            # $vSS_pg1 = Get-VirtualPortGroup -Name "VM Network" -VirtualSwitch vSwitch0
            # Remove-VirtualPortGroup -VirtualPortGroup $vSS_pg1 -confirm:$false
            Remove-VirtualSwitch -VirtualSwitch vSwitch0 -Confirm:$false
            
            # Reclaim vmnic0 on host and add to VDS
            My-Logger "Reclaim vmnic0 on host '$vmhostname' and add to VDS '$VDSName' ..."
            $pNIC_vSS = $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic0
            # Get-VMHostNetworkAdapter -Physical -Name vmnic2 | Remove-VDSwitchPhysicalNetworkAdapter
            Add-VDSwitchPhysicalNetworkAdapter -Server $vc -DistributedSwitch $vds -VMHostPhysicalNic $pNIC_vSS -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    if($configurevMotion -eq 'True') {
        My-Logger "Enabling vMotion on ESXi hosts ..."
        $index = 0
        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            ## old $vmhost | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
            My-Logger "Add VMkernel vMotion Adapter on '$vmhost' ..."
            $vmhost | New-VMHostNetworkAdapter -PortGroup "vMotion" -VirtualSwitch $vds -IP $MgmtvSANIP.split(',')[$index] -SubnetMask 255.255.255.0 -VMotionEnabled $true | Out-File -Append -LiteralPath $verboseLogFile
        $index++
        }
    }
    
    if($configureVSAN -eq 'True') {
        My-Logger "Enabling vSAN on ESXi hosts ..."
        $index = 0
        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            My-Logger "Add VMkernel vSAN Adapter on '$vmhost' ..."
            $vmhost | New-VMHostNetworkAdapter -PortGroup $VLANvSANPortgroup -VirtualSwitch $vds -IP $MgmtvSANIP.split(',')[$index] -SubnetMask 255.255.255.0 -VsanTrafficEnabled $true | Out-File -Append -LiteralPath $verboseLogFile
        $index++
        }

        My-Logger "Enabling VSAN & disabling VSAN Health Check ..."
        Get-VsanClusterConfiguration -Server $vc -Cluster $NewVCVSANClusterName | Set-VsanClusterConfiguration -HealthCheckIntervalMinutes 0 | Out-File -Append -LiteralPath $verboseLogFile

        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            $luns = $vmhost | Get-ScsiLun | select CanonicalName, CapacityGB

            My-Logger "Querying ESXi host disks to create VSAN Diskgroups ..."
            foreach ($lun in $luns) {
                if(([int]($lun.CapacityGB)).toString() -eq "$Nested_CacheDisk") {
                    $vsanCacheDisk = $lun.CanonicalName
                }
                if(([int]($lun.CapacityGB)).toString() -eq "$Nested_CapacityDisk") {
                    $vsanCapacityDisk = $lun.CanonicalName
                }
            }
            My-Logger "Creating VSAN DiskGroup for $vmhost ..."
            New-VsanDiskGroup -Server $vc -VMHost $vmhost -SsdCanonicalName $vsanCacheDisk -DataDiskCanonicalName $vsanCapacityDisk | Out-File -Append -LiteralPath $verboseLogFile
        }
    } else {
        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            $localDS = ($vmhost | Get-Datastore) | where {$_.type -eq "VMFS"}
            $localDS | Set-Datastore -Server $vc -Name "not-supported-datastore" | Out-File -Append -LiteralPath $verboseLogFile
        }
    }

    # $iSCSITarget = '192.168.200.10'
    if($iSCSIEnable -eq 'True') {
        My-Logger "Enabling iSCSI on ESXi hosts ..."
        $index = 0
        foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
            My-Logger "Enabling Software iSCSI Adapter on '$vmhost' ..."
            Get-VMHostStorage -VMHost $vmhost | Set-VMHostStorage -SoftwareIScsiEnabled $True | Out-File -Append -LiteralPath $verboseLogFile
            #
            My-Logger "Add VMkernel iSCSI Adapter on '$vmhost' ..."
            $vmhost | New-VMHostNetworkAdapter -PortGroup $VLANiSCSIPortgroup -VirtualSwitch $vds -IP $MgmtiSCSIIP.split(',')[$index] -SubnetMask 255.255.255.0 | Out-File -Append -LiteralPath $verboseLogFile
            #
            $hba = Get-VMHostHba -Type iScsi | Where {$_.Model -eq "iSCSI Software Adapter"}
            $vmkSCSI = $vmhost | Get-VMHostNetworkAdapter -VMKernel | where {$_.PortGroupName -cmatch 'iSCSI Network'} | select Devicename
            My-Logger "Bind VMkernel port '$($vmkSCSI.DeviceName)' on '$vmhost' to host HBA '$hba' ..."
            $esxcli = Get-EsxCli -V2 -VMHost $vmhost
            $esxcli.iscsi.networkportal.add.CreateArgs()
            $bind = @{
                adapter = $hba.Device
                force = $true
                nic = $vmkSCSI.DeviceName
            }
            $esxcli.iscsi.networkportal.add.Invoke($bind)
            #
            My-Logger "Attach new iSCSI target '$iSCSITarget' and Rescan on '$vmhost' ..."
            New-IScsiHbaTarget -IScsiHba $hba -Address $iSCSITarget
            $vmhost | Get-VMHostStorage -RescanAllHba -RescanVmfs
            #
            My-Logger "Attach new iSCSI LUN to '$vmhost' Datastore ..."        
            $LUN_1 = Get-SCSILun -VMhost $vmhost -LunType Disk | Where-Object {$_.CanonicalName -cmatch "naa"} | Select CanonicalName
            # New-Datastore -VMHost $vmhost -Name ‘iSCSI_DS_1’ -Path $LUN_1.CanonicalName -vmfs
        $index++
        }
    } 

    # Define Teaming and Failover policies on portgroups
    My-Logger "Setting DVS Uplink policy on DVSwitch - $VDSName..."
    Get-VDSwitch $vds | Get-VDPortgroup $VLANMGMTPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1', 'dvUplink3' -StandbyUplinkPort 'dvUplink2', 'dvUplink4'
    Get-VDSwitch $vds | Get-VDPortgroup $VLANvMotionPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1', 'dvUplink3' -StandbyUplinkPort 'dvUplink2', 'dvUplink4'
    Get-VDSwitch $vds | Get-VDPortgroup $VLANVMPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1', 'dvUplink3' -StandbyUplinkPort 'dvUplink2', 'dvUplink4'
    if ($iSCSIEnable -eq 'True') {
        Get-VDSwitch $vds | Get-VDPortgroup $VLANiSCSIPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1', 'dvUplink3' -StandbyUplinkPort 'dvUplink2', 'dvUplink4'
    }
    if ($Workload -ne 'Worker') {
        Get-VDSwitch $vds | Get-VDPortgroup $VLANTrunkPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1', 'dvUplink3' -StandbyUplinkPort 'dvUplink2', 'dvUplink4'
    }
    # VXLAN portgroups
    if($DeployNSX -eq 'True') {
        Get-VDSwitch $vds | Get-VDPortgroup $VXLANDVPortgroup | Get-VDUplinkTeamingPolicy | Set-VDUplinkTeamingPolicy -ActiveUplinkPort 'dvUplink1' -StandbyUplinkPort 'dvUplink2'
    }
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

    if($DeployNSX -eq 'True') {
        $ovfconfig = Get-OvfConfiguration $NSX_Mgr_OVA
        #$ovfconfig.NetworkMapping.VSMgmt.value = $VMNetwork
        #$ovfconfig.NetworkMapping.Management_Network.value = $VMNetwork
        # $ovfconfig.VSMgmt
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
        
        $vmhost = Get-VMHost -Server $vc -Name $VIServer
        $datastore = Get-Datastore -Server $vc -Name $VMDatastore
        $vm = Import-VApp -Source $NSX_Mgr_OVA -OvfConfiguration $ovfconfig -Name $NSX_Mgr_Name -Location $NewVCVSANClusterName -Server $vc -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin
        # Alternative option, but without setting CEIP, DiskStorageFormat, and Host to use
        #New-NSXManager -NsxManagerOVF $NSXManagerOVF -Name $NSX_Mgr_Name -ClusterName $NSX_VC_Cluster -ManagementPortGroupName $NSX_VC_Network -DatastoreName $NSX_VC_Datastore -FolderName $NSX_VC_Folder -CliPassword $NSX_MGR_CLI_Pass -CliEnablePassword $NSX_MGR_CLI_Pass -Hostname $NSX_MGR_Hostname -IpAddress $NSX_MGR_IP -Netmask $NSX_MGR_Netmask -Gateway $NSX_MGR_Gateway -DnsServer $NSX_MGR_DNSServer -DnsDomain $NSX_MGR_DNSDomain -NtpServer $NSX_MGR_NTPServer -EnableSsh -StartVm)

        My-Logger "Updating NSX VM vCPU Count to '$NSX_Mgr_vCPU' & vMEM to '$NSX_Mgr_vMem GB' ..."
        Set-VM -Server $vc -VM $vm -NumCpu $NSX_Mgr_vCPU -MemoryGB $NSX_Mgr_vMem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

        My-Logger "Powering On NSX - $NSX_Mgr_Name ..."
        $oVMName = VMware.VimAutomation.Core\Get-VM -Name $vm
        Start-VM -VM $vm -Confirm:$false
        # $vm | Start-Vm -RunAsync | Out-Null
        while (-not $oVMName.ExtensionData.Guest.GuestOperationsReady)
        {
            Start-Sleep 2
            $oVMName.ExtensionData.UpdateViewData('Guest')
        }
        My-Logger "Wait for NSX Manager to finish boot up before continuing ..."
        Start-Sleep 90
    }

    if($DeployNSX -eq 'true' -and $configureNSX -eq 'true' -and $setupVXLAN -eq 'true') {
        My-Logger "Validate NSX Manager access ..."
        if(!(Connect-NSXServer -Server $NSX_Mgr_Hostname -Username admin -Password $NSX_Mgr_UI_Pass -DisableVIAutoConnect -WarningAction SilentlyContinue)) {
            Write-Host -ForegroundColor Red "Unable to connect to NSX Manager, please check the deployment"
            exit
        } else {
            My-Logger "Successfully logged into NSX Manager - $NSX_Mgr_Hostname ..."
        }
        [System.Windows.Forms.MessageBox]::Show("NSX Manager`nJoin NSX Manager")
        break
        $ssoUsername = "administrator@$VCSASSODomainName"
        My-Logger "Registering NSX Manager '$NSX_Mgr_Hostname' with vCenter Server '$VCSAHostname' ..."
        #Connect-NSXServer -Server $NSX_Mgr_Hostname -Username admin -Password $NSX_Mgr_UI_Pass -DisableVIAutoConnect -WarningAction SilentlyContinue
        $vcConfig = Set-NsxManager -vCenterServer $VCSAHostname -vCenterUserName $ssoUsername -vCenterPassword $VCSASSOPassword -AcceptAnyThumbprint
       
        My-Logger "Registering NSX Manager with vCenter SSO $VCSAHostname - Lookup Service ..."
        #Connect-NSXServer -Server $NSX_Mgr_Hostname -Username admin -Password $NSX_Mgr_UI_Pass -DisableVIAutoConnect -WarningAction SilentlyContinue
        $ssoConfig = Set-NsxManager -SsoServer $VCSAHostname -SsoUserName $ssoUsername -SsoPassword $VCSASSOPassword -AcceptAnyThumbprint

try {
$vcConfig = Set-NSXManager -vCenterServer $VCSAHostname -vCenterUserName $ssoUsername -vCenterPassword $VCSASSOPassword
} catch {
$ErrorMessage = $_.Exception.Message
}
#$thumbprintMatch = '[<"]details[>"]:*"*(([A-F0-9]{2}:)+[A-F0-9]{2})'
$ErrorMessage -match 'details[>"]:*"*(([A-F0-9]{2}:))'
echo $ErrorMessage
$ErrorMessage -match 'details":"(?.*)","'
$sslThumbprint=$matches['key']
$sslThumbPrint = "15:99:A2:78:DC:DC:7A:5D:D6:42:CD:C8:3A:97:DA:4E:92:1F:06:12:14:FD:32:4B:A9:4E:AF:10:44:6A:20:EC"
$vcConfig = Set-NSXManager -vCenterServer $VCSAHostname -vCenterUserName $ssoUsername -vCenterPassword $VCSASSOPassword -SslThumbprint $sslThumbPrint


        My-Logger "Assigning NSX license to vCenter ..."
        Connect-NSXServer -Server $NSX_Mgr_Hostname -Username admin -Password $NSX_Mgr_UI_Pass -DisableVIAutoConnect -WarningAction SilentlyContinue
        $ServiceInstance = Get-View ServiceInstance
        $LicenseManager = Get-View $ServiceInstance.Content.licenseManager
        $LicenseAssignmentManager = Get-View $LicenseManager.licenseAssignmentManager
        $LicenseAssignmentManager.UpdateAssignedLicense("nsx-netsec", $NSX_License, $NULL) > $Null

        My-Logger "Check if NSX has been properly set ..."
        $CheckLicense = $LicenseAssignmentManager.QueryAssignedLicenses("nsx-netsec")
        if($CheckLicense.AssignedLicense.LicenseKey -ne $NSX_License) {
            My-Logger "Setting the NSX License failed! Error: $CheckLicense ..."
            Exit
        } else {
            My-Logger "Configured NSX License on vCenter ..."
        }
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

    My-Logger "Create NSX Controllers ..."
    # can take up to 8 minutes each
    $cluster = Get-Cluster -Name $NSX_Controllers_Cluster
    $datastore = Get-Datastore -Name $NSX_Controllers_Datastore
    $portgroup = Get-VirtualPortGroup -Name $NSX_Controllers_PortGroup
    $i = 1
    While ($i -le $NSX_Controllers_Amount) {
        My-Logger "Deloying NSX Controller $i ..."
        $controller = New-NsxController -Confirm:$False -IpPool $CTRLIPPool -Cluster $cluster -Datastore $datastore -PortGroup $portgroup -Password $NSX_Controllers_Password -Wait
        $i += 1
    }
    My-Logger "$NSX_Controllers_Amount NSX Controllers deployed ..."

    My-Logger "Preparing ESX Hosts on Cluster - $NSX_VXLAN_Cluster (installing VIBs) ..." # flag with some license issue
    $cluster = Get-Cluster -Name $NSX_VXLAN_Cluster
    $HostPrep = Install-NsxCluster -Cluster $cluster -VxlanPrepTimeout 300
    My-Logger "VXLAN enabled on Cluster - $NSX_VXLAN_Cluster ..."

    My-Logger "Creating VXLAN Segment ID, Range from $NSX_VXLAN_Segment_ID_Begin to $NSX_VXLAN_Segment_ID_End ..."
    $SegmentID = New-NsxSegmentIdRange -Name "Segment-1" -Begin $NSX_VXLAN_Segment_ID_Begin -End $NSX_VXLAN_Segment_ID_End
    # Command for Segment removal
    # $SegmentID = Get-NsxSegmentIdRange
    # Remove-NsxSegmentIdRange $SegmentID 

    My-Logger  "Creating VXLAN Multicast IP range ..."
    #. "D:\New-NsxMulticastRange.ps1"
    . $ScriptPath'New-NsxMulticastRange.ps1'
    # $MultiCast = New-NsxMulticastRange -Name "Multicast1" -Begin $NSX_VXLAN_Multicast_Range_Begin -End $NSX_VXLAN_Multicast_Range_End

    My-Logger "Check if VXLAN (VTEP) IP Pool already exists .."
    $VTEPIPPool = Get-NsxIpPool -Name $NSX_VXLAN_IP_Pool_Name -ErrorAction SilentlyContinue
    if($VTEPIPPool -eq $null) {
        $VTEPIPPool = New-NsxIpPool -Name $NSX_VXLAN_IP_Pool_Name -Gateway $NSX_VXLAN_IP_Pool_Gateway -SubnetPrefixLength $NSX_VXLAN_IP_Pool_Prefix -DnsServer1 $NSX_VXLAN_IP_Pool_DNS1 -DnsServer2 $NSX_VXLAN_IP_Pool_DNS2 -DnsSuffix $NSX_VXLAN_IP_Pool_DNSSuffix -StartAddress $NSX_VXLAN_IP_Pool_Start -EndAddress $NSX_VXLAN_IP_Pool_End
        My-Logger "Create VXLAN (VTEP) IP Pool - $NSX_VXLAN_IP_Pool_Name ..."
    }

    My-Logger "Configuring '$NSX_VXLAN_VTEP_Count' VXLAN VTEPs on cluster - $NSX_VXLAN_Cluster ..." # flag with some license issue
    $vds = Get-VDSwitch -Name $NSX_VXLAN_DSwitch
    New-NsxVdsContext -VirtualDistributedSwitch $vds -Teaming $NSX_VXLAN_Failover_Mode -Mtu $NSX_VXLAN_MTU_Size
    New-NsxClusterVxlanConfig -Cluster $cluster -VirtualDistributedSwitch $vds -IpPool $VTEPIPPool -VlanId $NSX_VXLAN_VLANID -VtepCount $NSX_VXLAN_VTEP_Count

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
    $release = Clear-Ref($WorkSheet_Exclusions)
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
    $release = Clear-Ref($WorkSheet_LS)
    My-Logger "Added $LogicalSwitchCount new Logical Switches to Transport Zone - $NSX_VXLAN_TZ_Name ..."

    My-Logger "Creating NSX Distributed Logical Routers (DLR) ..."
    for ($intDLR=1; $intDLR -le $NumDLR; $intDLR++ ) {
        $WorkSheetname = "Distributed Logical Routers - " + $intDLR
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
            # Now for the management port
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
            #$intRow++
        #My-Logger "Added $DLRCount Distributed Logical Routers ..."

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
        My-Logger "$lifCount internal LIF were added to $DLR_Name ..."

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
    }
    $release = Clear-Ref($WorkSheet_DLR)
    My-Logger "Added $DLRCount Distributed Logical Routers ..."
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
    $intRow = 20 # move cursor to row 20
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

    My-Logger "Configure newly created Edge Services Gateway '$ESG_Name' ..."
    $intRow = 12 # Move cursor to row 12
    
        $ESG_RouteID           = $WorkSheet_ESG.Cells.Item($intRow, 1).Value()
        $ESG_BGP_IPAddr        = $WorkSheet_ESG.Cells.Item($intRow, 2).Value()
        $ESG_BGP_LocalAS       = $WorkSheet_ESG.Cells.Item($intRow, 3).Value()
        $ESG_BGP_RemoteAS      = $WorkSheet_ESG.Cells.Item($intRow, 4).Value()
        $ESG_BGP_KeepAlive     = $WorkSheet_ESG.Cells.Item($intRow, 5).Value()
        $ESG_BGP_HoldDown      = $WorkSheet_ESG.Cells.Item($intRow, 6).Value()
    $intRow = 16 # Move cursor to row 16
        $ESG_DefaultGW_vNic      = $WorkSheet_ESG.Cells.Item($intRow, 1).Value()
        $ESG_DefaultGW_IP        = $WorkSheet_ESG.Cells.Item($intRow, 2).Value()
        $ESG_DefaultGW_AdminDist = $WorkSheet_ESG.Cells.Item($intRow, 3).Value()

    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgp -LocalAS $ESG_BGP_LocalAS -RouterId $ESG_RouteID -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeBgp -GracefulRestart:$false -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution -confirm:$false
    #$ESG = Get-NsxEdge -Name $ESG_Name
    ##$ESG | Get-NsxEdgeRouting | Set-NsxEdgeBgp -FromConnected -Learner bgp -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -Confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESGvNic = $ESG | Get-NsxEdgeInterface -Name $ESG_DefaultGW_vNic
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayVnic $ESGvNic.Index -DefaultGatewayAddress $ESG_DefaultGW_IP `
    -DefaultGatewayAdminDistance $ESG_DefaultGW_AdminDist -Confirm:$false
    #$ESG = Get-NsxEdge -Name $ESG_Name
    #$ESG | Get-NsxEdgeRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule -confirm:$false
    $ESG = Get-NsxEdge -Name $ESG_Name
    $ESG | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour -IpAddress $ESG_BGP_IPAddr -RemoteAS $ESG_BGP_RemoteAS -Weight 60 `
-KeepAliveTimer $ESG_BGP_KeepAlive -HoldDownTimer $ESG_BGP_HoldDown -confirm:$false

    $release = Clear-Ref($WorkSheet_ESG)
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
    Get-MacLearn -DVPortgroupName @($VLANTrunkPortgroup)
    Set-MacLearn -DVPortgroupName @($VLANTrunkPortgroup) -EnableMacLearn $true -EnablePromiscuous $false -EnableForgedTransmit $true -EnableMacChange $false

    My-Logger "Disconnecting from new VCSA ..."
    Disconnect-VIServer $vc -Confirm:$false
}

if($deployNSXTManager -eq 'True') {
    # Deploy NSX Manager
    $nsxMgrOvfConfig = Get-OvfConfiguration $NSXTManagerOVA
    $nsxMgrOvfConfig.DeploymentOption.Value = $NSXT_Mgr_Size
    $nsxMgrOvfConfig.NetworkMapping.Network_1.value = 'Management' #$VMNetwork
    $nsxMgrOvfConfig.IpAssignment.IpProtocol.Value = "IPv4" #
    $nsxMgrOvfConfig.Common.nsx_role.Value = $NSXT_MGR_RoleName
    $nsxMgrOvfConfig.Common.nsx_hostname.Value = $NSXT_MGR_Hostname
    $nsxMgrOvfConfig.Common.nsx_ip_0.Value = $NSXT_MGR_IP 
    $nsxMgrOvfConfig.Common.nsx_netmask_0.Value = $NSXT_MGR_Netmask
    $nsxMgrOvfConfig.Common.nsx_gateway_0.Value = $NSXT_MGR_Gateway
    $nsxMgrOvfConfig.Common.nsx_dns1_0.Value = $NSXT_MGR_DNSServer
    $nsxMgrOvfConfig.Common.nsx_domain_0.Value = $NSXT_MGR_DNSDomain
    $nsxMgrOvfConfig.Common.nsx_ntp_0.Value = $NSXT_MGR_NTPServer
    if($NSXT_Mgr_SSHEnable -eq "True") {
        $NSXTSSHEnableVar = $true
    } else {
        $NSXTSSHEnableVar = $false
    }
    $nsxMgrOvfConfig.Common.nsx_isSSHEnabled.Value = $NSXTSSHEnableVar
    if($NSXT_MGR_RootEnable -eq "true") {
        $NSXTRootPasswordVar = $true
    } else {
        $NSXTRootPasswordVar = $false
    }
    $nsxMgrOvfConfig.Common.nsx_allowSSHRootLogin.Value = $NSXTRootPasswordVar
    $nsxMgrOvfConfig.Common.nsx_passwd_0.Value = $NSXT_MGR_Root_Password
    $nsxMgrOvfConfig.Common.nsx_cli_username.Value = $NSXT_MGR_Admin_Username
    $nsxMgrOvfConfig.Common.nsx_cli_passwd_0.Value = $NSXT_MGR_Admin_Password
    $nsxMgrOvfConfig.Common.nsx_cli_audit_username.Value = $NSXT_MGR_Audit_Username
    $nsxMgrOvfConfig.Common.nsx_cli_audit_passwd_0.Value = $NSXT_MGR_Audit_Password

    $datastore = Get-Datastore -Name "SSD_VM"
    $vmhost = Get-VMHost -Name $VIServer
    $nsxMgrOvfConfig | ConvertTo-Json | Set-Content -Path "$($ENV:Temp)\NSXjsontemplate.json"

    My-Logger "Deploying NSX-T Manager OVA - $NSXT_MGR_DisplayName ..."
    $nsxmgr_vm = Import-VApp -Source $NSXTManagerOVA -OvfConfiguration $nsxMgrOvfConfig -Name $NSXT_MGR_DisplayName -Location $NewVCVSANClusterName -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

    My-Logger "Updating vCPU Count to '$NSXT_Mgr_vCPU' & vMEM to '$NSXT_Mgr_vMem' GB ..."
    Set-VM -Server $vc -VM $nsxmgr_vm -NumCpu $NSXT_Mgr_vCPU -MemoryGB $NSXT_Mgr_vMem -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Disabling vCPU Reservation ..."
    Get-VM -Server $vc -Name $nsxmgr_vm | Get-VMResourceConfiguration | Set-VMResourceConfiguration -CpuReservationMhz 0 | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Powering On NSX Manager - $NSXT_MGR_RoleName ..."
    $nsxmgr_vm | Start-Vm -RunAsync | Out-Null
}




if ($moveVMsIntovApp -eq 'True') {
    My-Logger "Creating vApp - $vAppName ..."
    $vApp = New-VApp -Name $vAppName -Server $vc -Location $NewVCVSANClusterName

    if(-Not (Get-Folder $VMFolder -ErrorAction Ignore)) {
        My-Logger "Creating VM Folder - $VMFolder ..."
        $folder = New-Folder -Name $VMFolder -Server $vc -Location (Get-Datacenter $NewVCDatacenterName | Get-Folder vm)
    }
    if($deployNestedESXiVMs -eq 1) {
        My-Logger "Moving Nested ESXi VMs into '$vAppName' vApp ..."
        $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $vm = Get-VM -Name $_.Key -Server $vc
            Move-VM -VM $vm -Server $vc -Destination $vApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }
    if($deployVCSA -eq 1) {
        $vcsaVM = Get-VM -Name $VCSADisplayName -Server $vc
        My-Logger "Moving VCSA '$VCSADisplayName' into '$vAppName' vApp ..."
        Move-VM -VM $vcsaVM -Server $vc -Destination $vApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
    if($deployNSXManager -eq 1) {
        $nsxMgrVM = Get-VM -Name $NSXT_MGR_RoleName -Server $vc
        My-Logger "Moving NST-T Manager '$NSXT_MGR_RoleName' into '$vAppName' vApp ..."
        Move-VM -VM $nsxMgrVM -Server $vc -Destination $vApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    }
    if($deployNSXEdge -eq 1) {
        My-Logger "Moving NSX-T Edge VMs into '$vAppName' vApp ..."
        $NSXTEdgeHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
            $nsxEdgeVM = Get-VM -Name $_.Key -Server $vc
            Move-VM -VM $nsxEdgeVM -Server $vc -Destination $vApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
        }
    }
    My-Logger "Moving '$vAppName' to VM Folder '$VMFolder' ..."
    Move-VApp -Server $vc $vAppName -Destination (Get-Folder -Server $vc $VMFolder) | Out-File -Append -LiteralPath $verboseLogFile
}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "vSphere $vSphereVersion Lab Deployment for VCSA Complete!"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"

# Forward Deployment summary and log to receipent...
$verboseLogFilePath = Get-ChildItem Env:Userprofile
#$strVMGuestIP = (Get-VM $strVMName).Guest.IPAddress
#$strVMFreeSpace = [math]::Round((Get-VM $strVMName).Guest.Disks.FreeSpaceGB[0],2)
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
    <th>VCSA Name</th>
    <th>VCSA Size</th> 
    <th>VCSA IP address</th>
  </tr>
  <tr>
    <td style='text-align:center'>$VCSAHostname</td>
    <td style='text-align:center'>$VCSADeploymentSize</td> 
    <td style='text-align:center'>$VCSAIPAddress</td>
  </tr>
  <tr>
    <th>VDS Mgmt Portgroup</th>
    <th>VDS VM Portgroup</th> 
    <th>VDS Trunk Portgroup</th>
  </tr>
  <tr>
    <td style='text-align:center'>$VLANMGMTPortgroup</td>
    <td style='text-align:center'>$VLANVMPortgroup</td> 
    <td style='text-align:center'>$VLANTrunkPortgroup</td>
  </tr>
  <tr>
    <th>Repository Name</th>
    <th>Content Library Datastore</th> 
    <th>Path to upload ISO</th>
  </tr>
  <tr>
    <td style='text-align:center'>$ConLibName</td>
    <td style='text-align:center'>$ConLibDSName</td> 
    <td style='text-align:center'>$ISOPath</td>
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