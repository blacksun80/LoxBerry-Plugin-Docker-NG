#!/usr/bin/perl

# Bedienoberfläche des Docker-Plugins: Statuskacheln, Containerliste mit
# Port-Links, Portainer-Kennwort, Portainer-Ports und
# Neuaufbau von Portainer sowie eine Übersicht der per MQTT
# veröffentlichten Themen.

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
    docker_config_write
    docker_bin
    docker_zustand
    docker_zaehlung
    docker_portainer_einrichten
    docker_portainer_hostports
    docker_portainer_passwort_pruefen
    docker_portainer_passwort_zuruecksetzen
    docker_port_frei
    docker_ports_vorschlagen
    docker_container_ports
    docker_port_schema
);

my $version = LoxBerry::System::pluginversion();

my $cgi = CGI->new;

# Rechnername für Links: wie die aktuelle LoxBerry-Adresse, ohne Port.
my $host = $ENV{HTTP_HOST} // 'localhost';
$host =~ s/:.*$//;

# ---------------- Port öffnen: Schema prüfen und weiterleiten ----------------
# Nur Ports, die ein laufender Container veröffentlicht; sonst zurück zur Übersicht.
my $oeffnen = $cgi->param('oeffnen') // '';
if ($oeffnen ne '') {
    my $ziel;
    if ($oeffnen =~ /^\d{1,5}$/) {
        foreach my $liste (values %{ docker_container_ports() }) {
            ($ziel) = grep { $_->{port} == $oeffnen } @$liste;
            last if ($ziel);
        }
    }
    if ($ziel) {
        my $schema = docker_port_schema($ziel->{ip}, $ziel->{port});
        print $cgi->redirect("$schema://$host:$ziel->{port}/");
    } else {
        print $cgi->redirect('index.cgi');
    }
    exit;
}

our $htmlhead = "<link rel='stylesheet' href='docker.css'></link>";

my $template = HTML::Template->new(
    filename => "$lbptemplatedir/index.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
    associate => $cgi,
);

my %L = LoxBerry::System::readlanguage($template, "language.ini");

my @fehler;
my $meldung = '';

# Übersetzte Fehlermeldung aus der Rückgabe von docker_portainer_einrichten.
sub einrichten_fehler {
    my ($text, $schluessel, @argumente) = @_;
    if ($schluessel && $L{"DOCKER.$schluessel"}) {
        return sprintf($L{"DOCKER.$schluessel"}, @argumente);
    }
    return sprintf($L{'DOCKER.FEHLER_NEUEINRICHTEN'}, $text);
}

my $aktion = $cgi->param('aktion') // '';

# Vorbelegung der Portfelder; wird durch Vorschlag oder abgelehnte Eingabe ersetzt.
my ($feld_http, $feld_https);

# ---------------- Aktion: Portainer neu einrichten ----------------
if ($aktion eq 'neu_einrichten') {
    my ($ok, $text, $schluessel, @argumente) = docker_portainer_einrichten(1);
    if ($ok) {
        $meldung = $L{'DOCKER.MELDUNG_NEUEINGERICHTET'};
    } else {
        push @fehler, einrichten_fehler($text, $schluessel, @argumente);
    }
}

# ---------------- Aktion: Administratorkennwort zurücksetzen ----------------
if ($aktion eq 'passwort_zuruecksetzen') {
    my ($ok, $text) = docker_portainer_passwort_zuruecksetzen();
    if ($ok) {
        $meldung = $L{'DOCKER.MELDUNG_PASSWORT_ZURUECKGESETZT'};
    } else {
        push @fehler, sprintf($L{'DOCKER.FEHLER_PASSWORT_ZURUECKSETZEN'}, $text);
    }
}

# ---------------- Aktion: Ports speichern ----------------
if ($aktion eq 'ports_speichern') {
    my $http  = $cgi->param('http_port')  // '';
    my $https = $cgi->param('https_port') // '';
    s/^\s+|\s+$//g for ($http, $https);

    my ($ok, $text, $schluessel, @argumente) =
        docker_portainer_einrichten(1, { http => $http, https => $https });
    if ($ok) {
        $meldung = $L{'DOCKER.MELDUNG_PORTS_GESPEICHERT'};
    } else {
        push @fehler, einrichten_fehler($text, $schluessel, @argumente);
        ($feld_http, $feld_https) = ($http, $https);
    }
}

# ---------------- Aktion: Freie Ports suchen ----------------
if ($aktion eq 'ports_suchen') {
    my ($http, $https) = docker_ports_vorschlagen();
    if (defined $http) {
        my $cfg_jetzt = docker_config_read();
        ($feld_http, $feld_https) = ($http, $https);
        $meldung = ($http == $cfg_jetzt->{portainer_port} && $https == $cfg_jetzt->{portainer_https_port})
            ? $L{'DOCKER.MELDUNG_PORTS_FREI'}
            : $L{'DOCKER.MELDUNG_PORTS_VORSCHLAG'};
    } else {
        push @fehler, $L{'DOCKER.FEHLER_PORT_PRUEFUNG'};
    }
}

# ---------------- Zustand ermitteln ----------------

my $docker_da = docker_bin();
my ($ok, undef, $zustand_meldung) = docker_zustand();
my $z = docker_zaehlung();
my $cfg = docker_config_read();
my $portainer_laeuft = (grep { $_->{name} eq $cfg->{portainer_name} && $_->{laeuft} } @{$z->{liste}}) ? 1 : 0;

$feld_http  //= $cfg->{portainer_port};
$feld_https //= $cfg->{portainer_https_port};

# Portainer-Links nur für Ports, die der laufende Container tatsächlich belegt.
my $eigen = $portainer_laeuft ? docker_portainer_hostports($cfg->{portainer_name}) : {};
my $http_aktiv  = $eigen->{$cfg->{portainer_port}} ? 1 : 0;
my $https_aktiv = $eigen->{$cfg->{portainer_https_port}} ? 1 : 0;

# Bei gestopptem Portainer: Ports melden, die inzwischen ein anderer Dienst belegt.
my @ports_belegt;
if ($ok && !$portainer_laeuft) {
    foreach my $p ($cfg->{portainer_port}, $cfg->{portainer_https_port}) {
        my $frei = docker_port_frei($p);
        push @ports_belegt, { TEXT => sprintf($L{'DOCKER.WARNUNG_PORT_BELEGT'}, $p) }
            if (defined $frei && !$frei);
    }
}

# Lehnt Portainer das gespeicherte Kennwort ab, wird es gelöscht und als "in Portainer geändert" vermerkt.
if ($cfg->{portainer_password} && $http_aktiv) {
    my $gueltig = docker_portainer_passwort_pruefen($cfg->{portainer_port}, $cfg->{portainer_password});
    if (defined $gueltig && !$gueltig) {
        docker_config_write({ portainer_password => '', portainer_password_geaendert => 1 });
        $cfg = docker_config_read();
    }
}

my $container_ports = $ok ? docker_container_ports() : {};

my @containerliste;
foreach my $c (@{$z->{liste}}) {
    push @containerliste, {
        NAME    => $c->{name},
        ABBILD  => $c->{image},
        ZUSTAND => $c->{status},
        LAEUFT  => $c->{laeuft},
        PORTS   => [ map { { PORT => $_->{port} } } @{ $container_ports->{$c->{name}} || [] } ],
    };
}

LoxBerry::Web::lbheader("Docker", "www.docker.com", "help.html");

# ---------------------------------------------------
# Sprachphrasen an die Vorlage uebergeben
# ---------------------------------------------------
$template->param(
    lblKDocker               => $L{'DOCKER.K_DOCKER'},
    lblKGesamt               => $L{'DOCKER.K_GESAMT'},
    lblKLaeuft               => $L{'DOCKER.K_LAEUFT'},
    lblKGestoppt             => $L{'DOCKER.K_GESTOPPT'},
    lblKPortainer            => $L{'DOCKER.K_PORTAINER'},
    lblJa                    => $L{'DOCKER.JA'},
    lblNein                  => $L{'DOCKER.NEIN'},
    lblStatusLaeuft          => $L{'DOCKER.STATUS_LAEUFT'},
    lblStatusGestoppt        => $L{'DOCKER.STATUS_GESTOPPT'},
    lblNichtAnsprechbarTitel => $L{'DOCKER.NICHT_ANSPRECHBAR_TITEL'},
    lblPortainerTitel        => $L{'DOCKER.PORTAINER_TITEL'},
    lblPortainerText         => $L{'DOCKER.PORTAINER_TEXT'},
    lblBOeffnen              => $L{'DOCKER.B_OEFFNEN'},
    lblBOeffnenHttps         => $L{'DOCKER.B_OEFFNEN_HTTPS'},
    lblPasswortTitel         => $L{'DOCKER.PASSWORT_TITEL'},
    lblPasswortText          => $L{'DOCKER.PASSWORT_TEXT'},
    lblPasswortAnzeigen      => $L{'DOCKER.PASSWORT_ANZEIGEN'},
    lblPasswortUnbekannt     => $L{'DOCKER.PASSWORT_UNBEKANNT'},
    lblPasswortGeaendert     => $L{'DOCKER.PASSWORT_GEAENDERT'},
    lblBPasswortZuruecksetzen => $L{'DOCKER.B_PASSWORT_ZURUECKSETZEN'},
    lblPasswortZuruecksetzenText  => $L{'DOCKER.PASSWORT_ZURUECKSETZEN_TEXT'},
    lblPasswortZuruecksetzenFrage => $L{'DOCKER.PASSWORT_ZURUECKSETZEN_FRAGE'},
    lblPortsTitel            => $L{'DOCKER.PORTS_TITEL'},
    lblPortsText             => $L{'DOCKER.PORTS_TEXT'},
    lblPortHttp              => $L{'DOCKER.PORT_HTTP'},
    lblPortHttps             => $L{'DOCKER.PORT_HTTPS'},
    lblBPortsSpeichern       => $L{'DOCKER.B_PORTS_SPEICHERN'},
    lblBPortsSuchen          => $L{'DOCKER.B_PORTS_SUCHEN'},
    lblBNeueinrichten        => $L{'DOCKER.B_NEUEINRICHTEN'},
    lblNeueinrichtenText     => $L{'DOCKER.NEUEINRICHTEN_TEXT'},
    lblContainerTitel        => $L{'DOCKER.CONTAINER_TITEL'},
    lblTName                 => $L{'DOCKER.T_NAME'},
    lblTPorts                => $L{'DOCKER.T_PORTS'},
    lblPortOeffnen           => $L{'DOCKER.PORT_OEFFNEN'},
    lblTAbbild               => $L{'DOCKER.T_ABBILD'},
    lblTZustand              => $L{'DOCKER.T_ZUSTAND'},
    lblKeineContainer        => $L{'DOCKER.KEINE_CONTAINER'},
    lblMqttTitel             => $L{'DOCKER.MQTT_TITEL'},
    lblMqttText              => $L{'DOCKER.MQTT_TEXT'},
);

# ---------------------------------------------------
# Zustand an die Vorlage uebergeben
# ---------------------------------------------------
$template->param(
    DOCKER_JA          => $docker_da,
    DOCKER_OK          => $ok,
    ZustandMeldung     => $zustand_meldung,
    GESAMT             => $z->{gesamt},
    LAEUFT             => $z->{laeuft},
    GESTOPPT           => $z->{gestoppt},
    PORTAINER_LAEUFT   => $portainer_laeuft,
    HTTP_AKTIV         => $http_aktiv,
    HTTPS_AKTIV        => $https_aktiv,
    PORTAINER_URL      => "http://$host:$cfg->{portainer_port}",
    PORTAINER_URL_HTTPS => "https://$host:$cfg->{portainer_https_port}",
    PORTAINER_PORT     => $cfg->{portainer_port},
    PORTAINER_HTTPS_PORT => $cfg->{portainer_https_port},
    FELD_HTTP          => $feld_http,
    FELD_HTTPS         => $feld_https,
    PORTS_BELEGT       => \@ports_belegt,
    PASSWORT           => $cfg->{portainer_password},
    PASSWORT_GEAENDERT => $cfg->{portainer_password_geaendert},
    CONTAINERLISTE     => \@containerliste,
    MELDUNG            => $meldung,
    FEHLER             => [ map { { TEXT => $_ } } @fehler ],
);

print $template->output();

LoxBerry::Web::lbfooter();
