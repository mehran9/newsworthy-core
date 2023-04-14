#!/usr/bin/env bash

export LC_ALL="en_US.UTF-8"
locale-gen en_US.UTF-8
echo >> /etc/environment <<- EOM
LC_ALL="en_US.UTF-8"
LANG="en_US.UTF-8"
EOM
echo > /etc/default/locale <<- EOM
LC_ALL="en_US.UTF-8"
LANG="en_US.UTF-8"
EOM
