function New-NsxMulticastRange
{

  <#
  .SYNOPSIS
  Adds a new multicast IP address range for use in the VXLAN network
  .DESCRIPTION
  Specifying a multicast address range helps in spreading traffic across your
  network to avoid overloading a single multicast address.A virtualized
  network‐ready host is assigned an IP address from this range.
  This cmdlet adds a multicast range
  .EXAMPLE
  PowerCLI C:\> New-NsxMulticastRange -Name Multicast01 -Begin 239.0.1.1 -End 239.0.1.255
  #>

  param (
    [Parameter (Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [Parameter (Mandatory=$False)]
    [ValidateNotNullOrEmpty()]
    [string]$Description="",
    [Parameter (Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [ipaddress]$Begin,
    [Parameter (Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [ipaddress]$End,
    [Parameter (Mandatory=$false)]
    [switch]$Universal=$false,
    [Parameter (Mandatory=$False)]
    #PowerNSX Connection object.
    [ValidateNotNullOrEmpty()]
    [PSCustomObject]$Connection=$defaultNSXConnection
  )

  begin {}
  process
  {
    # Build URL
    $URI = "/api/2.0/vdn/config/multicasts?isUniversal=$($Universal.ToString().ToLower())"

    #Construct the XML
    [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
    [System.XML.XMLElement]$xmlRange = $XMLDoc.CreateElement("multicastRange")
    $xmlDoc.Appendchild($xmlRange) | out-null

    #Mandatory and default params
    Add-XmlElement -xmlRoot $xmlRange -xmlElementName "name" -xmlElementText $Name
    Add-XmlElement -xmlRoot $xmlRange -xmlElementName "desc" -xmlElementText $Description
    Add-XmlElement -xmlRoot $xmlRange -xmlElementName "begin" -xmlElementText $Begin
    Add-XmlElement -xmlRoot $xmlRange -xmlElementName "end" -xmlElementText $End

    # #Do the post
    $body = $xmlRange.OuterXml

    try {
        $response = invoke-nsxrestmethod -method "POST" -uri $URI -connection $connection -body $body
    }
    catch {
        Throw "Unable to add multicast range. $_"
    }
  }

  end {}
}