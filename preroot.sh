#!/bin/bash

# Shell script which is executed by bash *BEFORE* installation is done. Use
# with caution and remember, that all systems may be different!
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

COMMAND=$0
PTEMPDIR=$1
PSHNAME=$2
PDIR=$3
PVERSION=$4
PTEMPPATH=$6

PCONFIG=$LBPCONFIG/$PDIR

echo "<INFO> Installation folder is: $PDIR"
echo "<INFO> Plugin version is: $PVERSION"
echo "<INFO> Plugin CONFIG folder is: $PCONFIG"

# ---------------------------------------------------------------------------
# Konfiguration ueber ein Update hinwegretten
#
# LoxBerry loescht bei einem Update die alte Installation samt Konfigurations-
# ordner - und zwar BEVOR postinstall.sh und postroot.sh laufen. preroot.sh
# ist dafuer die einzige Stelle: es laeuft als root und garantiert als erstes.
#
# In der dockerng.json steht das Portainer-Administratorpasswort. Ginge es
# verloren, wuerde bei einer spaeteren Neuerstellung des Containers ein neues
# Passwort gewuerfelt - der Anwender kaeme mit dem bisher bekannten Passwort
# nicht mehr hinein, ohne dass irgendetwas im Log darauf hindeutet.
# ---------------------------------------------------------------------------

SICHERUNG="/tmp/dockerplugin_config_sicherung.json"

if [ -f "$PCONFIG/dockerng.json" ]
then
	if cp -p "$PCONFIG/dockerng.json" "$SICHERUNG"
	then
		chmod 600 "$SICHERUNG"
		echo "<OK> Konfiguration gesichert - das Portainer-Passwort bleibt erhalten."
	else
		echo "<WARNING> Die Konfiguration liess sich nicht sichern."
		echo "<WARNING> Nach dem Update wird beim naechsten Neuaufbau von Portainer ein"
		echo "<WARNING> neues Passwort erzeugt."
		exit 1
	fi
else
	echo "<INFO> Keine vorhandene Konfiguration gefunden - das ist bei einer"
	echo "<INFO> Erstinstallation der Normalfall."
fi

exit 0
