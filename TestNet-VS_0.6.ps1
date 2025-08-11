<#
.Synopsis
This script check connection to/from machines 
.Description
This script has the ability to test network flows allowing us to make a correct report to our clients
.Example
Network_Checks 
#>

# Version - 0.6 [ 23.02.24 ]

#$global:scriptPath = ""
$global:tech = ""


# Functions #

function Get-ScriptDirectory {
    Split-Path -Parent $PSCommandPath
}

function writeLog( $type="info" , $module , $msg ){
    $datestring = (Get-Date).ToString("dd.MM.yyyy")
    $timestring = (Get-Date).ToString("hh:mm:ss")
    $prefix = $datestring + " " + $timestring + "`t" + $module + "`t" #date format

    if ( $type -eq "error" ){
        Write-Host -BackgroundColor red -ForegroundColor white $prefix $msg
    }
    elseif ( $type -eq "warning" ){
        Write-Warning $msg
    }
    elseif ( $type -eq "success" ){
        Write-Host -BackgroundColor DarkGreen -ForegroundColor white $prefix $msg
    }
}

function checkDatabaseConnectivity($tnsname){
    $tnsping = "C:\ORACLE12\Client64\bin\tnsping.exe"

    $result = & $tnsping $tnsname

    foreach($line in $result){
        if($line.Contains("OK")){
            writeLog -type "success" -msg "TNSPing $tnsname is OK" -module "checkDatabaseConnectivity"
            return $true
        }
    }
    writeLog -type "error" -msg "TNSPing $hst : $port is not reachable" -module "checkDatabaseConnectivity"
    return $false
}

function checkDNSv4($hst){
    try{
        $res = Resolve-DnsName -Name $hst -Type A -ErrorAction Stop
        $dns = New-Object PSObject -Property @{
            Name             = if ($res.Name) { $res.Name } else { "" }
            Type             = if ($res.Type) { $res.Type } else { "" }
            IPAddress        = if ($res.IPAddress) { $res.IPAddress } else { "" }
        }
        writeLog -type "success" -msg "$hst has a valid DNS A-Record" -module "DNSv4"
    }catch{
        writeLog -type "error" -msg "$hst has NO valid DNS A-Record" -module "DNSv4"
        $dns = New-Object PSObject -Property @{
            Name             = if ($_.Exception.Message) { $_.Exception.Message } else { "" }
            Type             = ""
            IPAddress        = "" 
        }
    }
    return $dns
}

function checkDNSv6($hst){
    try{
        $res = Resolve-DnsName -Name $hst -Type AAAA -ErrorAction Stop

        $dns = New-Object PSObject -Property @{
            Name             = if ($res.Name) { $res.Name } else { "" }
            Type             = if ($res.Type) { $res.Type } else { "" }
            IPAddress        = if ($res.IPAddress) { $res.IPAddress } else { "" }
        }
        writeLog -type "success" -msg "$hst has a valid DNS AAAA-Record" -module "DNSv6"
    }catch{
        writeLog -type "error" -msg "$hst has NO valid DNS AAAA-Record" -module "DNSv6"
        $dns = New-Object PSObject -Property @{
            Name             = if ($_.Exception.Message) { $_.Exception.Message } else { "" }
            Type             = ""
            IPAddress        = "" 
        }
    }
    return $dns
}

function checkPing($hst){
    try{
        $res = Test-Connection -ComputerName $hst -Count 1 -ErrorAction Stop
         $ping = New-Object PSObject -Property @{
            IPV4Address         = if ($res.IPV4Address) { $res.IPV4Address } else { "" }
            IPV6Address         = if ($res.IPV6Address) { $res.IPV6Address } else { "" }
            ResponseTime        = if ($res.ResponseTime) { $res.ResponseTime } else { "" }
        }
        writeLog -type "success" -msg "$hst is pingable" -module "Ping"
    }catch{
        $ping = New-Object PSObject -Property @{
            IPV4Address      = if ($_.Exception.Message) { $_.Exception.Message } else { "" }
            IPV6Address      = ""
            ResponseTime     = ""
        }
        writeLog -type "error" -msg "$hst is NOT pingable" -module "Ping"
    }
    return $ping
}

function checkPort($hst, $port){
    $res = Test-NetConnection $hst -Port $port -InformationLevel "Quiet" -ErrorAction Stop
    if($res -eq $True){
        writeLog -type "success" -msg "Socket $hst : $port is OPEN"
        return $True
    }elseif ($res -eq $False){
        writeLog -type "error" -msg "Socket $hst : $port is NOT OPEN"
        return $False
    }
}

function openFileDialog(){
    Add-Type -AssemblyName System.Windows.Forms
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog
    $FileBrowser.InitialDirectory =  Get-ScriptDirectory
    $FileBrowser.filter = "CSV (*.csv) | *.csv"
    $null = $FileBrowser.ShowDialog()
    return $FileBrowser.FileName
}


### ---MAIN CODE--- ###

$csvPath = if ($null -eq $args[0]) { openFileDialog } else {$args[0]} #if no file was passed into the script command, open a dialog box
Write-Warning "Please make sure that the first Column is called SERVERID!!"
$csvDelim = Read-Host "Please enter the delimiter [;] "
if ( $csvDelim -eq "" ) { $csvDelim = ";" } #default value for the delimeter (regarding the csv file)

$tech = Read-Host "Please specify the technology between the following => | WN | UX | WEB | DB |  . . . [UX]"

if ( $tech -eq "" ) { $tech = "UX" } #default option
$global:tech = $tech

$csvContent = Import-Csv $csvPath -Delimiter $csvDelim
$datestring = (Get-Date).ToString("yyyy-MM-dd")
$timestring = (Get-Date).ToString("hh.mm.ss")
$outputFile = (Split-Path -Path $csvPath) + "\"+ $datestring +"_"+ $timestring + "_" + $global:tech + "_" + $env:COMPUTERNAME + ".csv"

$cntAll = $csvContent.Count #count all the lines of the csv file
$ipLines = $cntAll
$current = 0 # csvContent[0] is the SERVERID row


foreach ( $line in $csvContent )
{

    $current = $current + 1 
    $checked = $current - 1 
    $progress = $checked / $cntAll
    $progress = [math]::round($progress, 2) #round the float value of the progress status
    $progress = $progress * 100

    if ( $current -eq 1 ) { Write-Host -ForegroundColor Gray "... Starting the network checks ..." }
    elseif ( $current -gt 1 ) {
        Write-Host -ForegroundColor Gray "... processing "$progress" % "
        Write-Host "Number of Ip checked :: [ "$checked" of "$ipLines" ]"
    }



    ## WN : [Windows] ##
    if($tech -eq "WN"){

        $epmapCheck = ""
        $netbiosCheck = ""
        $smbCheck = ""
        $rdpCheck = ""
        $ldapCheck = ""
        $ldapsCheck = ""
        
        if ( $current -eq 1 ) {

            Write-Warning "The following ports will be checked:`n
            -1 [EPMAP] : 135 `n
            -2 [NetBios] : 139 `n
            -3 [Smb] : 445 `n
            -4 [Rdp] : 3389"

            Write-Host `n
            $condWN = Read-Host "Do you need to check all those ports? [ y/[n] ] "

            if ( $condWN -eq "n" -or $condWN -eq "" ) { 
                $portToCheck = Read-Host "Please insert the numbers of the ports that you DO need to check (ex. 2,4,5 )  "
                $portToCheck = $portToCheck.Split(',')

                $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
                $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
                $pingCheck = checkPing -hst $line.SERVERID

                Write-Host `n
                
                #pre-setting all variable to "Not Controlled" 
                $epmapCheck = "Not Controlled"
                $netbiosCheck = "Not Controlled"
                $smbCheck = "Not Controlled"
                $rdpCheck = "Not Controlled"

                foreach ($singlePort in $portToCheck) {

                    switch($singlePort) {

                        "1" {$epmapCheck   = checkPort -hst $line.SERVERID -port 135}
                        "2" {$netbiosCheck = checkPort -hst $line.SERVERID -port 139}
                        "3" {$smbCheck     = checkPort -hst $line.SERVERID -port 445}
                        "4" {$rdpCheck     = checkPort -hst $line.SERVERID -port 3389}

                    }

                }

            }
            elseif ( $condWN -eq 'y' ) { 
                Write-Host `n

                $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
                $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
                $pingCheck = checkPing -hst $line.SERVERID

                Write-Host `n

                $epmapCheck = checkPort -hst $line.SERVERID -port 135
                $netbiosCheck = checkPort -hst $line.SERVERID -port 139
                $smbCheck = checkPort -hst $line.SERVERID -port 445
                $rdpCheck = checkPort -hst $line.SERVERID -port 3389
            }
            else { # -> if the user typed a value that was neither y or n
                Write-Error "I think you didn't type correctly . . ."  -Category InvalidData
                exit
            }
        }
        else { # if we are on the second and next line of the CSV file

            Write-Host `n

            $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
            $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
            $pingCheck = checkPing -hst $line.SERVERID

            Write-Host `n

            if ( $condWN -eq "n" -or $condWN -eq "" ) { # -> Not every port will be checked

                #pre-setting all variable to "Not Controlled" 
                $epmapCheck = "Not Controlled"
                $netbiosCheck = "Not Controlled"
                $smbCheck = "Not Controlled"
                $rdpCheck = "Not Controlled"

                foreach ($singlePort in $portToCheck) {

                    switch($singlePort) {

                        "1" {$epmapCheck   = checkPort -hst $line.SERVERID -port 135}
                        "2" {$netbiosCheck = checkPort -hst $line.SERVERID -port 139}
                        "3" {$smbCheck     = checkPort -hst $line.SERVERID -port 445}
                        "4" {$rdpCheck     = checkPort -hst $line.SERVERID -port 3389}

                    }

                }

            }
            elseif ( $condWN -eq "y" ) { # -> All the ports will be checked

                $epmapCheck = checkPort -hst $line.SERVERID -port 135
                $netbiosCheck = checkPort -hst $line.SERVERID -port 139
                $smbCheck = checkPort -hst $line.SERVERID -port 445
                $rdpCheck = checkPort -hst $line.SERVERID -port 3389    
                $ldapCheck = checkPort -hst $line.SERVERID -port 389
                $ldapsCheck = checkPort -hst $line.SERVERID -port 686

            }
        }
        
        #formatting the row that has to be inserted into the final csv export file
        $props = [ordered]@{
            ServerID             = $line.SERVERID.ToLower()
            SOCK_135_EPMA        = $epmapCheck.ToString()
            SOCK_139_NETB        = $netbiosCheck.ToString()
            SOCK_445_SMB         = $smbCheck.ToString()
            SOCK_3389_RDP        = $rdpCheck.ToString()
            SOCK_389_LDAP        = $ldapCheck.ToString()
            SOCK_686_LDAPS       = $ldapsCheck.ToString()
            DNS_Name             = $dnsCheckv4.Name.ToString()
            DNS_Type             = $dnsCheckv4.Type.ToString()
            DNS_IPAddress        = $dnsCheckv4.IPAddress.ToString()
            DNS_Namev6           = $dnsCheckv6.Name.ToString()
            DNS_Typev6           = $dnsCheckv6.Type.ToString()
            DNS_IPAddressv6      = $dnsCheckv6.IPAddress.ToString()
            PING_IPV4Address     = $pingCheck.IPV4Address.ToString()
            PING_IPV6Address     = $pingCheck.IPV6Address.ToString()
            PING_ResponseTime    = $pingCheck.ResponseTime.ToString()
        }      

    } ## <end Windows Check> ##
    elseif ( $tech -eq "UX" ){

        Write-Host `n

        $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
        $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
        $pingCheck = checkPing -hst $line.SERVERID

        Write-Host `n

        $sshCheck = checkPort -hst $line.SERVERID -port 22 # I'm assuming that there will be no need to check other port than the 22 (SSH)

        $props = [ordered]@{
            ServerID             = $line.SERVERID.ToLower()
            SOCK_SSH             = $sshCheck.ToString()
            DNS_Name             = $dnsCheckv4.Name.ToString()
            DNS_Type             = $dnsCheckv4.Type.ToString()
            DNS_IPAddress        = $dnsCheckv4.IPAddress.ToString()
            DNS_Namev6           = $dnsCheckv6.Name.ToString()
            DNS_Typev6           = $dnsCheckv6.Type.ToString()
            DNS_IPAddressv6      = $dnsCheckv6.IPAddress.ToString()
            PING_IPV4Address     = $pingCheck.IPV4Address.ToString()
            PING_IPV6Address     = $pingCheck.IPV6Address.ToString()
            PING_ResponseTime    = $pingCheck.ResponseTime.ToString()
        }

    } ## <end Unix Check> ##
    elseif ( $tech -eq "WEB" ){
        
        if ($current -eq 1) {

            Write-Warning "The following ports will be checked:`n
            -1 [HTTPS] : 443 `n
            -2 [HTTP] : 80 `n
            -3 [HTTP] : 8080"
            
            Write-Host `n
            $condWeb = Read-Host "Do you need to check all of those ports? [ y/[n] ] "

            if ( $condWeb -eq "n" -or $condWeb -eq "" ) { # -> Not every port will be checked
                Write-Host " . . . "
                $portToCheck = Read-Host "Please insert the numbers of the ports that you DO need to check (ex. 1,3 )  "
                $portToCheck = $portToCheck.Split(',')

                Write-Host `n

                $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
                $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
                $pingCheck = checkPing -hst $line.SERVERID

                #pre-settins all the variable to "Not Controlled"
                $HttpsCheck = "Not Controlled"
                $HttpCheck = "Not Controlled"
                $HttpCheck2 = "Not Controlled"

                foreach ($singlePort in $portToCheck) {
                    switch($singlePort) {
                        "1" { $HttpsCheck = checkPort -hst $line.SERVERID -port 443  }
                        "2" { $HttpCheck   = checkPort -hst $line.SERVERID -port 80 }
                        "3" { $HttpCheck2  = checkPort -hst $line.SERVERID -port 8080 }
                    }
                }
            }
            elseif ( $condWeb -eq "y" ){ # -> Every port will be checked
                Write-Host `n

                $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
                $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
                $pingCheck = checkPing -hst $line.SERVERID

                $HttpsCheck = checkPort -hst $line.SERVERID -port 443
                $HttpCheck  = checkPort -hst $line.SERVERID -port 80
                $HttpCheck2 = checkPort -hst $line.SERVERID -port 8080
            }
            else { # -> if the user typed a value that was neither y or n
                Write-Error "I think you didn't type correctly . . ." -Category InvalidData
                exit
            }
        }
        else {

            Write-Host `n

            $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
            $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
            $pingCheck = checkPing -hst $line.SERVERID

            Write-Host `n

            #pre-settins all the variable to "Not Controlled"
            $HttpsCheck = "Not Controlled"
            $HttpCheck = "Not Controlled"
            $HttpCheck2 = "Not Controlled"

            #for each -- switch
            if ( $condWeb -eq "n" -or $condWeb -eq "" ) {
                foreach ($singlePort in $portToCheck) {
                    switch($singlePort) {
                        "1" { $HttpsCheck = checkPort -hst $line.SERVERID -port 443  }
                        "2" { $HttpCheck   = checkPort -hst $line.SERVERID -port 80 }
                        "3" { $HttpCheck2  = checkPort -hst $line.SERVERID -port 8080 }
                    }
                }
            }
            elseif ( $condWeb -eq "y" ){ # -> Every port will be checked
                $HttpsCheck = checkPort -hst $line.SERVERID -port 443
                $HttpCheck = checkPort -hst $line.SERVERID -port 80
                $HttpCheck2 = checkPort -hst $line.SERVERID -port 8080
            }
        }

        $props = [ordered]@{
            ServerID             = $line.SERVERID.ToLower()
            SOCK_443_HTTPS       = $HttpsCheck.ToString()
            SOCK_80_HTTP         = $HttpCheck.ToString()
            SOCK_8080_HTTP       = $HttpCheck2.ToString()
            DNS_Name             = $dnsCheckv4.Name.ToString()
            DNS_Type             = $dnsCheckv4.Type.ToString()
            DNS_IPAddress        = $dnsCheckv4.IPAddress.ToString()
            DNS_Namev6           = $dnsCheckv6.Name.ToString()
            DNS_Typev6           = $dnsCheckv6.Type.ToString()
            DNS_IPAddressv6      = $dnsCheckv6.IPAddress.ToString()
            PING_IPV4Address     = $pingCheck.IPV4Address.ToString()
            PING_IPV6Address     = $pingCheck.IPV6Address.ToString()
            PING_ResponseTime    = $pingCheck.ResponseTime.ToString()
        }

    } ## <end Web Check> ##
    elseif ( $tech -eq "DB" ){
        
        if ( $current -eq 1 ) {

            Write-Warning "The following ports will be checked:`n
            -1 [MySQL] : 3306 `n
            -2 [OracleDB-1] : 1521 `n
            -3 [OracleDB-2] : 1830 `n
            -4 [PostgreSQL] : 5432 `n
            -5 [SQL Server - MSSQL] : 1433 `n
            -6 [SQL Server - MSSQL 2] : 1434"
            
            Write-Host `n
            $condDB = Read-Host "Do you need to check all of these ports? [ y/[n] ] "

            
            if ( $condDB -eq "n" -or $condDB -eq "" ) { # -> Not every port will be checked

                Write-Host " . . . "
                $portToCheck = Read-Host "Please insert the numbers of the ports that you DO need to check (ex. 2,4,5 )  "
                $portToCheck = $portToCheck.split(',')
                
                Write-Host `n
                Write-Host `n

                $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
                $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
                $pingCheck = checkPing -hst $line.SERVERID

                Write-Host `n

                #pre-setting to "Not Controlled"
                $mysql_Check      = "Not Controlled"
                $oracleDB1_Check  = "Not Controlled"
                $oracleDB2_Check  = "Not Controlled"
                $postgreSQL_Check = "Not Controlled"
                $mssql1_Check     = "Not Controlled"
                $mssql2_Check     = "Not Controlled"

                foreach ($singlePort in $portToCheck) {

                    switch ($singlePort) {
                        "1" { $mysqlCheck       = checkPort -hst $line.SERVERID -port 3306 } 
                        "2" { $oracleDB1_Check  = checkPort -hst $line.SERVERID -port 1521 } 
                        "3" { $oracleDB2_Check  = checkPort -hst $line.SERVERID -port 1830 } 
                        "4" { $postgreSQL_Check = checkPort -hst $line.SERVERID -port 5432 } 
                        "5" { $mssql1_Check     = checkPort -hst $line.SERVERID -port 1433 } 
                        "6" { $mssql2_Check     = checkPort -hst $line.SERVERID -port 1434 } 
                    } #end of the switch iteration

                }

            }
            elseif ($condDB -eq "y") { #if we have to check every single port

                Write-Host `n
                Write-Host `n

                $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
                $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
                $pingCheck = checkPing -hst $line.SERVERID

                $mysqlCheck       = checkPort -hst $line.SERVERID -port 3306
                $oracleDB1_Check  = checkPort -hst $line.SERVERID -port 1521
                $oracleDB2_Check  = checkPort -hst $line.SERVERID -port 1830
                $postgreSQL_Check = checkPort -hst $line.SERVERID -port 5432
                $mssql1_Check     = checkPort -hst $line.SERVERID -port 1433
                $mssql2_Check     = checkPort -hst $line.SERVERID -port 1434

            }
            else { #if the user typed a value that was neither y or n
                Write-Error "I think you didn't type correctly . . ." -Category InvalidData
                exit
            }

        } #end of the first iteration
        else { #if we are on the second or next lines of the csv file

            Write-Host `n

            $dnsCheckv4 = checkDNSv4 -hst $line.SERVERID
            $dnsCheckv6 = checkDNSv6 -hst $line.SERVERID
            $pingCheck = checkPing -hst $line.SERVERID

            Write-Host `n

            if ( $condDB -eq "n" -or $condDB -eq "" ) { # -> Not every port will be checked

                Write-Host " . . . "
               
                #pre-setting all the variable to "Not Controlled"
                $mysql_Check      = "Not Controlled"
                $oracleDB1_Check  = "Not Controlled"
                $oracleDB2_Check  = "Not Controlled"
                $postgreSQL_Check = "Not Controlled"
                $mssql1_Check     = "Not Controlled"
                $mssql2_Check     = "Not Controlled"

                foreach ($singlePort in $portToCheck) {
                    switch ($singlePort) {
                        "1" { $mysqlCheck       = checkPort -hst $line.SERVERID -port 3306 } 
                        "2" { $oracleDB1_Check  = checkPort -hst $line.SERVERID -port 1521 } 
                        "3" { $oracleDB2_Check  = checkPort -hst $line.SERVERID -port 1830 } 
                        "4" { $postgreSQL_Check = checkPort -hst $line.SERVERID -port 5432 } 
                        "5" { $mssql1_Check     = checkPort -hst $line.SERVERID -port 1433 } 
                        "6" { $mssql2_Check     = checkPort -hst $line.SERVERID -port 1434 } 
                    } #end of the switch iteration
                }
                
            }
            elseif ($condDB -eq "y") { #if we have to check every single port

                $mysqlCheck       = checkPort -hst $line.SERVERID -port 3306
                $oracleDB1_Check  = checkPort -hst $line.SERVERID -port 1521
                $oracleDB2_Check  = checkPort -hst $line.SERVERID -port 1830
                $postgreSQL_Check = checkPort -hst $line.SERVERID -port 5432
                $mssql1_Check     = checkPort -hst $line.SERVERID -port 1433
                $mssql2_Check     = checkPort -hst $line.SERVERID -port 1434

            }
            
        }
        
        $props = [ordered]@{
            ServerID             = $line.SERVERID.ToLower() 
            MYSQL_CHECK          = $mysqlCheck.toString()
            ORACLEDB_1           = $oracleDB1_Check.toString()
            ORACLEDB_2           = $oracleDB2_Check.toString()
            PostgreSQL           = $postgreSQL_Check.toString()
            MSSQL_1              = $mssql1_Check.toString()
            MSSQL_2              = $mssql2_Check.toString()
            DNS_Name             = $dnsCheckv4.Name.ToString()
            DNS_Type             = $dnsCheckv4.Type.ToString()
            DNS_IPAddress        = $dnsCheckv4.IPAddress.ToString()
            DNS_Namev6           = $dnsCheckv6.Name.ToString()
            DNS_Typev6           = $dnsCheckv6.Type.ToString()
            DNS_IPAddressv6      = $dnsCheckv6.IPAddress.ToString()
            PING_IPV4Address     = $pingCheck.IPV4Address.ToString()
            PING_IPV6Address     = $pingCheck.IPV6Address.ToString()
            PING_ResponseTime    = $pingCheck.ResponseTime.ToString()
        }
        
    }  #end of the DB condition
    
    Write-Host `n
    $row = New-Object -Type PSObject -Property $props
    $row | Export-Csv -Path $outputFile -Append -noType -Force
    Write-Host "`n"

} #end foreach [ the foreach allow the script to get every line of the file consequentially ]

Write-Host -ForegroundColor Gray "... processing 100% "
Write-Host "Number of Ip checked :: [ "$ipLines" of "$ipLines" ]"
Write-Host `n
Read-Host -Prompt "[!] Finished [!]"