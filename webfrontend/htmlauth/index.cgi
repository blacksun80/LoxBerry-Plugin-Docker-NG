#!/usr/bin/perl

# Bedienoberflaeche des Docker-Plugins: Statuskacheln, Containerliste,
# automatisch erzeugtes Portainer-Administratorkennwort, Neuaufbau von
# Portainer sowie eine Uebersicht der per MQTT veroeffentlichten Themen.

use strict;
use warnings;
use CGI;
use HTML::Template;
use LoxBerry::System;
use LoxBerry::Web;

# DockerLib.pm liegt in bin/, nicht in webfrontend/htmlauth/ - $lbpbindir
# steht erst nach 'use LoxBerry::System' fest und muss deshalb VOR 'use
# DockerLib' in @INC aufgenommen werden. Ohne diesen Schritt findet Perl das
# Modul nur bei manuellem 'perl -I...', nicht aber beim Aufruf durch Apache
# ueber das Shebang - genau das fiel beim ersten Testaufruf als HTTP 500 auf.
BEGIN { push @INC, $LoxBerry::System::lbpbindir if $LoxBerry::System::lbpbindir; }

use DockerLib qw(
    docker_config_read
    docker_bin
    docker_zustand
    docker_zaehlung
    docker_portainer_laeuft
    docker_portainer_einrichten
);

my $version = LoxBerry::System::pluginversion();

my $cgi = CGI->new;
$cgi->import_names('R');

our $htmlhead = "<link rel='stylesheet' href='docker.css'></link>";

my @fehler;
my $meldung = '';

# ---------------- Aktion: Portainer neu einrichten ----------------
#
# Dieselbe Funktion, die auch postroot.sh bei der Installation aufruft -
# siehe DockerLib::docker_portainer_einrichten(). Erzwungen (force=1), weil
# ein Klick auf diese Schaltflaeche ausdruecklich einen Neuaufbau verlangt.
if ($R::aktion && $R::aktion eq 'neu_einrichten') {
    my ($ok, $text) = docker_portainer_einrichten(1);
    if ($ok) {
        $meldung = 'Portainer wurde neu eingerichtet.';
    } else {
        push @fehler, "Portainer liess sich nicht neu einrichten: $text";
    }
}

# ---------------- Zustand ermitteln ----------------

my $docker_da = docker_bin();
my ($ok, undef, $zustand_meldung) = docker_zustand();
my $z = docker_zaehlung();
my $cfg = docker_config_read();
my $portainer_laeuft = docker_portainer_laeuft($cfg->{portainer_name});

my @containerliste;
foreach my $c (@{$z->{liste}}) {
    push @containerliste, {
        NAME    => $c->{name},
        ABBILD  => $c->{image},
        ZUSTAND => $c->{status},
        LAEUFT  => $c->{laeuft},
    };
}

LoxBerry::Web::lbheader("Docker", "www.docker.com", "help.html");

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/index.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    associate => $cgi,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

# ---------------------------------------------------
# Sprachphrasen an die Vorlage uebergeben
# ---------------------------------------------------
$template->param(
    lblKDocker              => $L{'DOCKER.K_DOCKER'},
    lblKGesamt              => $L{'DOCKER.K_GESAMT'},
    lblKLaeuft              => $L{'DOCKER.K_LAEUFT'},
    lblKGestoppt            => $L{'DOCKER.K_GESTOPPT'},
    lblKPortainer           => $L{'DOCKER.K_PORTAINER'},
    lblJa                   => $L{'DOCKER.JA'},
    lblNein                 => $L{'DOCKER.NEIN'},
    lblStatusLaeuft         => $L{'DOCKER.STATUS_LAEUFT'},
    lblStatusGestoppt       => $L{'DOCKER.STATUS_GESTOPPT'},
    lblNichtAnsprechbarTitel => $L{'DOCKER.NICHT_ANSPRECHBAR_TITEL'},
    lblPortainerTitel       => $L{'DOCKER.PORTAINER_TITEL'},
    lblPortainerText        => $L{'DOCKER.PORTAINER_TEXT'},
    lblBOeffnen             => $L{'DOCKER.B_OEFFNEN'},
    lblPasswortTitel        => $L{'DOCKER.PASSWORT_TITEL'},
    lblPasswortText         => $L{'DOCKER.PASSWORT_TEXT'},
    lblPasswortAnzeigen     => $L{'DOCKER.PASSWORT_ANZEIGEN'},
    lblPasswortUnbekannt    => $L{'DOCKER.PASSWORT_UNBEKANNT'},
    lblBNeueinrichten       => $L{'DOCKER.B_NEUEINRICHTEN'},
    lblNeueinrichtenText    => $L{'DOCKER.NEUEINRICHTEN_TEXT'},
    lblContainerTitel       => $L{'DOCKER.CONTAINER_TITEL'},
    lblTName                => $L{'DOCKER.T_NAME'},
    lblTAbbild              => $L{'DOCKER.T_ABBILD'},
    lblTZustand             => $L{'DOCKER.T_ZUSTAND'},
    lblKeineContainer       => $L{'DOCKER.KEINE_CONTAINER'},
    lblMqttTitel            => $L{'DOCKER.MQTT_TITEL'},
    lblMqttText             => $L{'DOCKER.MQTT_TEXT'},
);

# ---------------------------------------------------
# Zustand an die Vorlage uebergeben
# ---------------------------------------------------
$template->param(
    DOCKER_JA        => $docker_da,
    DOCKER_OK        => $ok,
    ZustandMeldung   => $zustand_meldung,
    GESAMT           => $z->{gesamt},
    LAEUFT           => $z->{laeuft},
    GESTOPPT         => $z->{gestoppt},
    PORTAINER_LAEUFT => $portainer_laeuft,
    PASSWORT         => $cfg->{portainer_password},
    CONTAINERLISTE   => \@containerliste,
    MELDUNG          => $meldung,
    FEHLER           => [ map { { TEXT => $_ } } @fehler ],
);

print $template->output();

LoxBerry::Web::lbfooter();
