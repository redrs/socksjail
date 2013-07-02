About
==============
This script will create a random user account on a Linux server and then use Jailkit to chrooted it. There will be no access to a shell of any kind, this account can only be used for SSHs socks proxy feature. 

Why?
* To give your friends a socks proxy on your server.
* When you just want an account to proxy pivot with (maybe on a firewall).
* For when you can't trust your own client. Think travel laptop for conferences (safely proxy your traffic over hostile Wi-Fi) and if it gets compromised in anyway (eg your private key is stolen) then make it much harder for an attacker to then compromise your server.

Using
==============
Install Jailkit and then run the script as root.

There is an option for generating SSH keys on the server (set in the script or run with ./jailbuild.sh genkey). This is not usually best practice but:
- These keys are temporary.
- These keys are *NOT* to be used for any other purpose.
- With SERVERDETAILS="y" set (default of the script) the private key and server details are piped straight to pgp. A longer password is generated and output to the TTY. 
	- Send the encrypted file to the recipient. It’s base 64 encoded so can be emailed safely or sent over IM etc.
	- Give the recipient the password to decrypt the file over a different (safe and ideally encrypted) communication channel.

This script has been tested on Debian 6 and CentOS. 

Server
==============
- Limit which users can SSH into your server. In sshd_config I use:
	- AllowUsers admin1 admin2
	- AllowGroups jailed
- The user will be subject to the iptables rules on the server so you might need to add outgoing rules for the new user if you have restrictive outgoing traffic rules.
	- Maybe make a rule for your group like: $IPTABLES -A OUTPUT --match owner --gid-owner jailed -j ACCEPT
- Don't use passwords for auth. This script assumes you are using public key authentication.

Logs:
- If "LogLevel DEBUG" is set in sshd_config then be aware that surfing history will be logged on the server, this might be undesirable. 
- If you use a Grsecurity patched Kernel and have enabled logging of execs within a chroot then execs will be logged (there should not be any!).

Clients
==============
The client might want to firewall off their host to only send/receive traffic from the server to stop leaks (a number of programs with socks proxy support will try to resolve DNS queries themselves, hence leaking). An iptables script is included for that.

The client will then probably run something like:

ssh -D8080 -f -C -q -N -o "VerifyHostKeyDNS no" -p 2222 -i /media/crypt/sshkey user@192.168.100.50 -v

TO DO list:
==============
* account lifespan then auto rm of CELL_ramdom_username.
* SElinux policy for systems with SElinux set as enforcing.
* Look into using the ChrootDirectory option in sshd_config too.
