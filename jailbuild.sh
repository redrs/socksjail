#!/bin/bash

# TO DO:
# * Account age limit with auto rm of CELL_ramdom_username
# * SElinux policy for RH systems set to enforcing

# eg will place each jail in /home/theslammer/CELL_ramdom_username
JAILDIR="/home/theslammer"

# Filename set in sshd_config for AuthorizedKeysFile
# tip: using a random filename could help avoid key injection attacks
AUTHKEYNAME="authorized_keys"

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

# distro?
if [ -f "/etc/redhat-release" ]; then
	DIST="RHEL"
fi
if [ -f "/etc/debian_version" ]; then
	DIST="DEBI"
fi

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

# password the account (otherwise passwordless accounts are locked)
genpass
usermod -p $(echo $ACPASSWD | openssl passwd -1 -stdin) $NEWNAME
#echo " account password is: $ACPASSWD"

echo -e "\n Created jail!\n"

# helpful hint
if [ `grep -i -e "AllowGroup" -e "AllowUsers" /etc/ssh/sshd_config | grep -v ^# | wc -c` -eq 0 ]; then
	echo " * tip: you should use the 'AllowUsers' or 'AllowGroup' setting in sshd_config!!!"
else
        echo " remember to add user to AllowUsers or AllowGroup in sshd_config and restart it."
fi

echo -e "\nAdd users public key to: $JAILDIR/CELL_$NEWNAME/home/$NEWNAME/.ssh/$AUTHKEYNAME"
echo -e "\n"
