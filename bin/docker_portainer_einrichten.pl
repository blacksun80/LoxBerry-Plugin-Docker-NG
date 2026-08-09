#!/usr/bin/perl

# Wird von postroot.sh aufgerufen, um Portainer einzurichten.
#
# Eine echte Datei statt eines 'perl -e'-Einzeilers: LoxBerry::System leitet
# den Pluginordner aus dem Pfad von $0 ab (siehe LoxBerry/System.pm, Zeilen um
# lbpplugindir). Bei 'perl -e' ist $0 nur der Text '-e' - das Muster
# bin/plugins/<Ordner>/... passt dann nie, und $lbpconfigdir/$lbplogdir
# bleiben leer. Nachgestellt: mit 'perl -e' schlug das Schreiben der
# Konfiguration unbemerkt fehl.
#
# Aufruf: docker_portainer_einrichten.pl [--force]

use strict;
use warnings;
use LoxBerry::System;
use DockerLib qw(docker_portainer_einrichten);

my $force = (defined $ARGV[0] && $ARGV[0] eq '--force') ? 1 : 0;

my ($ok, $meldung) = docker_portainer_einrichten($force);
print(($ok ? '<OK> ' : '<FAIL> ') . $meldung . "\n");
exit($ok ? 0 : 1);
