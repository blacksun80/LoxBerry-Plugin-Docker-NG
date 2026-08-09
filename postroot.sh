#!/bin/bash

# Shell script which is executed by bash *AFTER* complete installation is done
# (*AFTER* postinstall and *AFTER* postupdate). Use with caution and remember,
# that all systems may be different!
#
# Exit code must be 0 if executed successfull. 
# Exit code 1 gives a warning but continues installation.
# Exit code 2 cancels installation.
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# Will be executed as user "root".
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# You can use all vars from /etc/environment in this script.
#
# We add 5 additional arguments when executing this script:
# command <TEMPFOLDER> <NAME> <FOLDER> <VERSION> <BASEFOLDER>
#
# For logging, print to STDOUT. You can use the following tags for showing
# different colorized information during plugin installation:
#
# <OK> This was ok!"
# <INFO> This is just for your information."
# <WARNING> This is a warning!"
# <ERROR> This is an error!"
# <FAIL> This is a fail!"

# To use important variables from command line use the following code:
COMMAND=$0    # Zero argument is shell command
PTEMPDIR=$1   # First argument is temp folder during install
PSHNAME=$2    # Second argument is Plugin-Name for scipts etc.
PDIR=$3       # Third argument is Plugin installation folder
PVERSION=$4   # Forth argument is Plugin version
#LBHOMEDIR=$5 # Comes from /etc/environment now. Fifth argument is
              # Base folder of LoxBerry
PTEMPPATH=$6  # Sixth argument is full temp path during install (see also $1)

# Combine them with /etc/environment
PCGI=$LBPCGI/$PDIR
PHTML=$LBPHTML/$PDIR
PTEMPL=$LBPTEMPL/$PDIR
PDATA=$LBPDATA/$PDIR
PLOG=$LBPLOG/$PDIR # Note! This is stored on a Ramdisk now!
PCONFIG=$LBPCONFIG/$PDIR
PSBIN=$LBPSBIN/$PDIR
PBIN=$LBPBIN/$PDIR

echo -n "<INFO> Current working folder is: "
pwd
echo "<INFO> Command is: $COMMAND"
echo "<INFO> Temporary folder is: $PTEMPDIR"
echo "<INFO> (Short) Name is: $PSHNAME"
echo "<INFO> Installation folder is: $PDIR"
echo "<INFO> Plugin version is: $PVERSION"
echo "<INFO> Plugin CGI folder is: $PCGI"
echo "<INFO> Plugin HTML folder is: $PHTML"
echo "<INFO> Plugin Template folder is: $PTEMPL"
echo "<INFO> Plugin Data folder is: $PDATA"
echo "<INFO> Plugin Log folder (on RAMDISK!) is: $PLOG"
echo "<INFO> Plugin CONFIG folder is: $PCONFIG"

# ---------------------------------------------------------------------------
# Gesicherte Konfiguration zurueckholen
#
# Gegenstueck zu preroot.sh. Dort wurde die dockerng.json weggeschrieben, bevor
# LoxBerry die alte Installation samt Konfigurationsordner geloescht hat.
# ---------------------------------------------------------------------------

SICHERUNG="/tmp/dockerplugin_config_sicherung.json"

if [ -f "$SICHERUNG" ]
then
	mkdir -p "$PCONFIG"
	if cp -p "$SICHERUNG" "$PCONFIG/dockerng.json"
	then
		chown loxberry:loxberry "$PCONFIG/dockerng.json"
		chmod 600 "$PCONFIG/dockerng.json"
		rm -f "$SICHERUNG"
		echo "<OK> Konfiguration wiederhergestellt - das Portainer-Passwort ist unveraendert."
	else
		echo "<WARNING> Die gesicherte Konfiguration liess sich nicht zurueckholen."
		echo "<WARNING> Sie liegt weiterhin unter $SICHERUNG."
	fi
fi

# check if docker is already installed, otherwise install
if  [ ! -f "/usr/bin/docker" ]
then
	# install docker
	curl -fsSL https://get.docker.com -o get-docker.sh
	sh get-docker.sh
	usermod -aG docker loxberry
fi

# ---------------------------------------------------------------------------
# Portainer einrichten
#
# Die eigentliche Logik (Version pruefen, Passwort erzeugen oder
# wiederverwenden, --http-enabled, Zeit zum Anwenden des Bootstrap-Passworts
# abwarten) steht EINMAL in DockerLib.pm - dieselbe Funktion bedient auch die
# Schaltflaeche "Portainer neu einrichten" in der Oberflaeche. Zwei getrennte
# Kopien derselben sicherheitsrelevanten Logik liefen hier frueher schnell
# auseinander.
# ---------------------------------------------------------------------------

perl -I"$PBIN" "$PBIN/docker_portainer_einrichten.pl"
PERLCODE=$?

# Verify that Docker and the Portainer container are actually up.
# If not, abort with exit code 2 so LoxBerry reports a real failure
# instead of marking the plugin as successfully installed.
if [ ! -x "/usr/bin/docker" ]
then
	echo "<FAIL> Docker binary /usr/bin/docker not found - installation failed."
	exit 2
fi

if [ "$PERLCODE" -ne 0 ] || [ -z "$(docker ps --quiet --filter name=portainer)" ]
then
	echo "<FAIL> Portainer container is not running - installation failed."
	exit 2
fi

echo "<OK> Docker and Portainer container are up and running."

# Exit with Status 0
exit 0
