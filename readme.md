About
==============
This script will generate/create a random user account and use Jailkit to chrooted it. There will be no access to a shell of anykind. This account is then to be used only for using SSHs socks proxy. 

This script has been tested on
Debian 6
CentOS release 6.4 

Uses
==============
* To give friends SSH access to your Linux server just to use as a socks proxy.
* For when you can't trust your own client. Think travel laptop for conferences, if it gets compromised then make it much harder for an attacker to then compromise your server.

The client might want to firewall off their host only to the server, a script is included for that.

The client will then probably run something like:

ssh -D8080 -f -C -q -N -o "VerifyHostKeyDNS no" -p 2222 -i /media/crypt/sshkey user@192.168.100.50 -v

Notes
==============
* The user will be subject to the iptables rules on the server so you might need to add outgoing rules for new user if you use restrictive rules.
* Don't use passwords for auth. This script assumes you are using public key authentication.

Logs:
* If "LogLevel DEBUG" is set in sshd_config then be aware that surfing history will be logged.
* If you use a Grsecurity patched Kernel and have enabled logging of execs within a chroot then execs will be logged (there should not be any!).

TO DO (maybe):
* account lifespan then auto rm of CELL_ramdom_username.
* SElinux policy for RH systems with it set as enforcing.
* Maybe add password support.
* Maybe alter sshd_config and add user to AllowUsers or AllowGroup.
* Maybe generate some iptables rules for the user.

Jailkit
==============
http://olivier.sessink.nl/jailkit/index.html

"Jailkit is a set of utilities to limit user accounts to specific files using chroot() and or specific commands. Setting up a chroot shell, a shell limited to some specific command, or a daemon inside a chroot jail is a lot easier and can be automated using these utilities."

Installation is usually as easy as downloading the code, checking the signature. Then a simple: 

./configure && make

sudo make install

