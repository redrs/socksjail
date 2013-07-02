#!/bin/bash

# eg will place each jail in /home/theslammer/CELL_ramdom_username
JAILDIR="/home/theslammer"

# Filename set in sshd_config for AuthorizedKeysFile
# tip: using a random filename could help avoid key injection attacks
AUTHKEYNAME="authorized_keys"

# Generate ssh keys on this server? OR use ./jailbuild.sh genkey
SSHGENKEY="n"
# Place the generated private key and server details in a file
# that is encrypted with pgp. Passphrase to decrypt this will be 
# randomly generated and output to screen.
SERVERDETAILS="y"
# ssh details
SERVERIP="192.168.100.50"
SERVERPORT="22"

# group to put all the jailed uses in. Will create if does not exist
JAILGRP="jailed"

# usual place for dictionary (might need to install with package manager)
DICT="/usr/share/dict/words"

#########################################################################

fail () {
        echo -e "\n[X] Error: $@ \n" >&2;
        exit 1
}

genname () {
        shuf $DICT -n1 | tr '[:upper:]' '[:lower:]' | tr -dc '[a-z]\n'
}

newuser () {
        NEWNAME="`genname`_`genname`"
}

namecheck () {
        # dir exists already?
        if [ -d "$JAILDIR/$NEWNAME" ]; then
                newuser
                namecheck
        fi
        # not > 24 char
        if [ `echo $NEWNAME | wc -c` -gt "24" ]; then
                newuser
                namecheck
        fi
        # system account exists
        egrep -i "^$NEWNAME" /etc/passwd
        if [ $? -eq 0 ]; then
                newuser
                namecheck
        fi
}

genpass () {
	NUM1=`od -vAn -N4 -tu4 < /dev/urandom`
	NUM2=`od -vAn -N4 -tu4 < /dev/urandom`
	WORD1=`genname`
	WORD2=`genname`
	echo $NUM1 $WORD1 $NUM2 $WORD2;
}

# Checks
[ ! -f "$DICT" ] && fail "please run 'select-default-wordlist' command first!"
[ "$(id -u)" != "0" ] && fail "Need to run as this script as root"
JKINIT=`which jk_init`
JKJUSR=`which jk_jailuser`
[ ! -f "$JKINIT" ] && fail "please install jailkit!\nhttp://olivier.sessink.nl/jailkit/"

# make jailhouse
if [ ! -d "$JAILDIR" ]; then
        echo -e "\n $JAILDIR does not exist, creating. "
        mkdir $JAILDIR
        chmod 755 $JAILDIR
        echo;
fi
# group for jailed users exist?
if [ `egrep -i "^$JAILGRP" /etc/group | wc -c` -eq 0 ]; then
        echo -e " group $JAILGRP does not exist, creating. "
	groupadd $JAILGRP || fail "could not add group $JAILGRP"
fi

# make a random user name
newuser
# check random user name
namecheck

echo -e "\n [*] User account will be: $NEWNAME"
echo -e "     Building jail at: $JAILDIR/CELL_$NEWNAME"

# add user
mkdir $JAILDIR/CELL_$NEWNAME &> /dev/null || fail "could not create $JAILDIR/CELL_$NEWNAME"
useradd $NEWNAME -G $JAILGRP  &> /dev/null || fail "could not run useradd $NEWNAME"

# password the account
ACPASSWD=`genpass`
usermod -p $( echo $ACPASSWD | openssl passwd -1 -stdin) $NEWNAME || fail "could not set users system password, is /etc/passwd locked?"

# build jail for user
$JKINIT -j $JAILDIR/CELL_$NEWNAME/ netbasics  &> /dev/null || fail "jk_init failed"
mkdir $JAILDIR/CELL_$NEWNAME/bin 
cp /bin/false $JAILDIR/CELL_$NEWNAME/bin 
chown root:root $JAILDIR/CELL_$NEWNAME/bin
chmod 500 $JAILDIR/CELL_$NEWNAME/bin 
$JKJUSR -s /bin/false -m -j $JAILDIR/CELL_$NEWNAME/ $NEWNAME &> /dev/null || fail "jk_addjailuser failed"
mkdir $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/ -p 
chmod 755 $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/
chmod 755 $JAILDIR/CELL_$NEWNAME/ 
chmod 755 $JAILDIR/CELL_$NEWNAME/* 
chmod 444 $JAILDIR/CELL_$NEWNAME/etc/* 
# .ssh
chmod 744 $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh 
touch $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME 
chmod 400 $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME
chown $NEWNAME:$NEWNAME $JAILDIR/CELL_$NEWNAME/home/* -R

# are we generating the sshkey on the server too?
if [[ "$SSHGENKEY" = "y" || "$1" = "genkey" ]]; then
	SSHKEYPWPASS=`genpass`
        SSHKEYPW="-N $SSHKEYPWPASS"
        if [ "$SERVERDETAILS" != "y"  ]; then
		echo " [!] Password for "$NEWNAME"_id_rsa will be: $SSHKEYPWPASS"
	fi
        echo -e " [*] Generating ssh key"
	ssh-keygen -q -t rsa -b 4096 -f "$NEWNAME"_id_rsa -N "$SSHKEYPWPASS" -C "" || fail "could not create sshkey"
	cat "$NEWNAME"_id_rsa.pub > $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME
        rm "$NEWNAME"_id_rsa.pub -f
	if [ "$SERVERDETAILS" = "y" ]; then
		echo -e " [*] Encrypting ssh key"
		THEKEY=`cat "$NEWNAME"_id_rsa`	
		DETAILS="Name/Server/Port:\n$NEWNAME@$SERVERIP:$SERVERPORT\n"
                SERVERPRINTS="`ssh-keygen -l -f /etc/ssh/ssh_host_rsa_key.pub`\n`ssh-keygen -l -f /etc/ssh/ssh_host_dsa_key`"
                SERVERPRINT="Server fingerprints (PLEASE check!):\n$SERVERPRINTS"
		KEYPW="Private key password:\n$SSHKEYPWPASS\n"
		NOTECRYPT="`genpass``genpass`"
		exec 5<<<"$NOTECRYPT"	
		PGP=`which gpg` || fail "could not find gpg"
		# encrypt details
		echo -e "Here are your proxy server details:\n\n$DETAILS\n$SERVERPRINT\n\n$KEYPW\n\n$THEKEY" \
		| $PGP --batch --passphrase-fd 5 --symmetric --cipher-algo AES --armor --output "$NEWNAME"_details.gpg \
		|| fail "could not encrypt server details with pgp"
		rm "$NEWNAME"_id_rsa
		echo " [!] Password for details file is: $NOTECRYPT"
		echo " [!] Give the user the gpg file and communicate the password over another [secure] channel."
		echo
		exec 5<<<""		
	fi
	# set jail to READ ONLY as key has been installed
	chattr +i -R $JAILDIR/CELL_$NEWNAME/* &> /dev/null
else
	echo -e "\n [!] Add users public key to: $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME"
	echo " [*] then run: chattr +i -R $JAILDIR/CELL_$NEWNAME/*"
fi

# helpful hint
if [ `grep -i -e "AllowGroup" -e "AllowUsers" /etc/ssh/sshd_config | grep -v ^# | wc -c` -eq 0 ]; then
	echo -e " [*] tip: you should use the 'AllowUsers' and/or 'AllowGroup' settings in sshd_config!"
else
        echo -e "\n [!] remember to add user to AllowUsers or AllowGroup in sshd_config and restart it."
fi

echo -e "\n [*] Created jail!\n"
exit