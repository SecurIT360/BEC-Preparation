<#
    .SYNOPSIS
        A PowerShell script that connects to your Microsoft and Azure tenants
        and pulls out information related to:
            - Unified Audit Log
            - Mailbox Audit Logging
            - Microsoft & Azure Subscription and Service Plan Information
        for the purposes of preparing for Business Email Compromise investigations.
        
        This script was created to go along with a series of emails related to preparing for, preventing and responding to Business Email Compromise.
        https://www.securit360.com/insights/business-email-compromise-prevention-and-mitigation/
    
    .NOTES     
        Name: BEC-Preparation.ps1
        Author: Spencer Alessi @SecurIT360
        Modified: 08/27/2021
#>

### Transcript Setup
$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"

$currUser = $env:UserName
if (Test-Path "C:\users\$currUser\Desktop\BEC_Preparation_Output.txt"){
    Remove-Item "C:\users\$currUser\Desktop\BEC_Preparation_Output.txt"
}
Start-Transcript -path "C:\users\$currUser\Desktop\BEC_Preparation_Output.txt" -append


### Installing Required Modules
if (Get-InstalledModule -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue) {
    # "[+] Prerequisite satisfied: 'ExchangeOnlineManagement' module already installed"
} else {
    Write-Host "[!] Prerequisite not satisifed, installing now.." -ForegroundColor yellow
    Install-Module ExchangeOnlineManagement
}

if (Get-InstalledModule -Name AzureAD -ErrorAction SilentlyContinue) {
    # "[+] Prerequisite satisfied: 'AzureAD' module already installed"
} else {
    Write-Host "[!] Prerequisite not satisifed, installing now.." -ForegroundColor yellow
    Install-Module AzureAD
}


### Importing modules and connecting to EXO & AzureAD
Import-Module ExchangeOnlineManagement
Import-Module AzureAD
Connect-ExchangeOnline


### Unified Audit Log
Write-Host "`nChecking to see if the Unified Audit Log is enabled...`n" -ForegroundColor Yellow
$UAL = Get-AdminAuditLogConfig | Select-Object UnifiedAuditLogIngestionEnabled

if ($UAL.UnifiedAuditLogIngestionEnabled -eq $true) {
    Write-Host "[+] UnifiedAuditLogIngestionEnabled : $($UAL.UnifiedAuditLogIngestionEnabled) - The Unified Audit Log is enabled for your organization.`n" -ForegroundColor Green
} elseif ($UAL.UnifiedAuditLogIngestionEnabled -eq $false)  {
    Write-Host "[!] UnifiedAuditLogIngestionEnabled : $($UAL.UnifiedAuditLogIngestionEnabled) - The Unified Audit Log IS NOT enabled for your organization!`n" -ForegroundColor Red
    Write-Host "Run the following command to enable the Unified Audit Log: Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled `$true" -ForegroundColor White
} else {
    Write-Host "[!] Unnable to determine 'Mailbox auditing on by default' status for your organization!`n" -ForegroundColor Red
}


### Mailbox Audit Logging
Write-Host "`nChecking to see if Mailbox Audit Logging is enabled...`n" -ForegroundColor Yellow
$MAL = Get-OrganizationConfig | Select-Object AuditDisabled

if ($MAL.AuditDisabled -eq $false) {
    Write-Host "[+] AuditDisabled : $($MAL.AuditDisabled) - 'Mailbox auditing on by default' is enabled for your organization.`n" -ForegroundColor Green
} elseif ($MAL.AuditDisabled -eq $true){
    Write-Host "[!] AuditDisabled : $($MAL.AuditDisabled) - 'Mailbox auditing on by default' IS NOT enabled for your organization!`n" -ForegroundColor Red
    Write-Host "Run the following command to enable 'Mailbox auditing on by default': Set-OrganizationConfig -AuditDisabled `$false" -ForegroundColor Magenta
} else {
    Write-Host "[!] Unnable to determine 'Mailbox auditing on by default' status for your organization!`n" -ForegroundColor Red
}


### Per User Mailbox Audit Logging
Write-Host "`nChecking users for mailbox auditing enabled...`n" -ForegroundColor Yellow
$userMAL = Get-EXOMailbox -ResultSize Unlimited -Filter "RecipientTypeDetails -eq 'UserMailbox'" -Properties AuditEnabled | Select-Object DisplayName,AuditEnabled

$userMAL | ForEach-Object {
    if ($_.AuditEnabled -eq $false) {
        Write-Host "[!] AuditEnabled : $($_.AuditEnabled) - $($_.DisplayName) does not have mailbox audit logging enabled.`n" -ForegroundColor Red
        Write-Host "Run the following command to enable mailbox audit logging for $($_.DisplayName) : Set-Mailbox -Identity `"<user name>`" -AuditEnabled `$true" -ForegroundColor Magenta
    } elseif ($userMAL.AuditEnabled -eq $true) {
        Write-Host "[+] AuditEnabled : $($_.AuditEnabled) - $($_.DisplayName) has mailbox audit logging is enabled.`n" -ForegroundColor Green
    } else {
        Write-Host "[!] Unnable to determine mailbox auditing status for $($_.Name)`n" -ForegroundColor Red
    } 
}

### MailboxLogin operation
Write-Host "`nChecking to see if the operation 'MailboxLogin' is enabled for all users...`n" -ForegroundColor Yellow
$usersWithMailbox = Get-EXOMailbox -ResultSize Unlimited -Filter "RecipientTypeDetails -eq 'UserMailbox'" | Select-Object DisplayName

$usersWithMailbox | ForEach-Object { 
    $usersMALOperations = Get-Mailbox -Identity $_.DisplayName | Select-Object -ExpandProperty AuditOwner

    if ($usersMALOperations -contains "MailboxLogin"){
        Write-Host "[+] MailboxLogin : enabled - $($_.DisplayName)" -ForegroundColor Green
    } else {
        Write-Host "[!] MailboxLogin : not enabled - $($_.DisplayName)" -ForegroundColor Red
    }
}

Write-Host "`n`Run the following commands to enable the 'MailboxLogin' operation for all users:`n" -ForegroundColor Magenta
Write-Host "`$usersWithMailbox = Get-EXOMailbox -ResultSize Unlimited -Filter `"RecipientTypeDetails -eq 'UserMailbox'`" | Select-Object DisplayName" -ForegroundColor Magenta
Write-Host "`$usersWithMailbox | ForEach-Object { Set-Mailbox -Identity $_.DisplayName -AuditOwner @{Add=`"MailboxLogin`"}}" -ForegroundColor Magenta

### Connect to AzureAD
Write-Host "`nConnecting to Azure AD...`n" -ForegroundColor Yellow
Connect-AzureAD

### Microsoft 365/Office 365/Azure Subscription Information
Write-Host "`nChecking Microsoft Subscription Information...`n" -ForegroundColor Yellow
Get-AzureADSubscribedSku | Select-Object -Property Sku*,ConsumedUnits -ExpandProperty PrepaidUnits | Format-Table

$SKUs = Get-AzureADSubscribedSku | Select-Object -Property Sku*,ConsumedUnits -ExpandProperty PrepaidUnits
$SKUs | ForEach-Object {
    if ($_.SkuPartNumber -match ".+E5") {
        Write-Host "[+] $($Matches.Values) - Possible Microsoft 365 E5 Subscription detected. Check if 'Advanced Audit' is available." -ForegroundColor Green 
    }
}


### Microsoft Service Plans 
Write-Host "`nChecking Microsoft Service Plans...`n" -ForegroundColor Yellow
Get-AzureADSubscribedSku | ForEach-Object {$_.ServicePlans} 

$aadPremium = $false
$servicePlans = Get-AzureADSubscribedSku | ForEach-Object {$_.ServicePlans} | Select-Object ServicePlanName
$servicePlans | ForEach-Object {
    if ($_.ServicePlanName -match "AAD_PREMIUM") {
        $aadPremium = $true
    }
}

if ($aadPremium -eq $true) {
    Write-Host "[+] Possible AzureAD Premium P1 and/or P2 detected - Log Retention : 30 Days" -ForegroundColor Green
} else {
    Write-Host "[!] AzureAD Premium NOT detected - Log Retention : 7 Days" -ForegroundColor Red
}

Write-Host "`nRemember to forward your logs to a collector or SIEM!`n" -ForegroundColor Yellow

Stop-Transcript
