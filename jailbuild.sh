#!/bin/bash

# eg will place each jail in /home/theslammer/CELL_ramdom_username
JAILDIR="/home/theslammer"

# Filename set in sshd_config for AuthorizedKeysFile
# tip: using a random filename could help avoid key injection attacks
AUTHKEYNAME="authorized_keys"

# Generate a ssh key for the user?
SSHGENKEY="y"
# generate/set a Password for the key?
SSHKEYPW="y"

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
	ACPASSWD=`echo $NUM1 $WORD1 $NUM2 $WORD2 | tr -d ' '`
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

echo -e " User account will be: $NEWNAME"
echo -e " Will build jail at: $JAILDIR/CELL_$NEWNAME \n"

# add user
mkdir $JAILDIR/CELL_$NEWNAME || fail "could not create $JAILDIR/CELL_$NEWNAME"
useradd $NEWNAME -G $JAILGRP || fail "could not adduser"
$JKINIT -j $JAILDIR/CELL_$NEWNAME/ netbasics || fail "jk_init failed"

# /bin/false just needs to exist, jailkit fails without
mkdir $JAILDIR/CELL_$NEWNAME/bin
cp /bin/false $JAILDIR/CELL_$NEWNAME/bin
chown root:root $JAILDIR/CELL_$NEWNAME/bin
chmod 500 $JAILDIR/CELL_$NEWNAME/bin
$JKJUSR -s /bin/false -m -j $JAILDIR/CELL_$NEWNAME/ $NEWNAME

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
echo 

# are we generating the sshkey on the server too?
if [ "$SSHGENKEY" = "y" ]; then
        if [ "$SSHKEYPW" = "y"  ]; then
                SSHKEYPWPASS=`genpass`
                SSHKEYPW="-N $SSHKEYPWPASS"
                echo " [!] Password for "$NEWNAME"_id_rsa will be: $SSHKEYPWPASS"
        else
                SSHKEYPW=""
        fi
        echo -e " [*] Generating ssh key"
        ssh-keygen -q -t rsa -b 4096 -f "$NEWNAME"_id_rsa -N "$SSHKEYPWPASS" || fail "could not create sshkey"
        cat "$NEWNAME"_id_rsa.pub > $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME
        rm "$NEWNAME"_id_rsa.pub -f
fi

# password the account (otherwise passwordless accounts are locked)
ACPASSWD=`genpass`
usermod -p $( echo $ACPASSWD | openssl passwd -1 -stdin) $NEWNAME || fail "could no change users password"
#echo " [!] account password is: $ACPASSWD"

# helpful hint
if [ `grep -i -e "AllowGroup" -e "AllowUsers" /etc/ssh/sshd_config | grep -v ^# | wc -c` -eq 0 ]; then
        echo " [*] tip: you should use the 'AllowUsers' or 'AllowGroup' setting in sshd_config!!!"
else
        echo " [!] remember to add user to AllowUsers or AllowGroup in sshd_config and restart it."
fi

if [ "$SSHGENKEY" != "y" ]; then
        echo -e "\n [!] Add users public key to: $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME"
fi

echo -e "\n [*] Created jail!\n"
exit