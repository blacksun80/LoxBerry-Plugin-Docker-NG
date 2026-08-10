package DockerLib;

# Gemeinsame Funktionen fuer index.cgi, den MQTT-Cronjob und das
# Installationsskript: Konfiguration, Docker-Abfragen, Passwortverwaltung.
# Liegt in bin/, weil bin/ als einziger Ordner ausserhalb von webfrontend/
# von allen drei Aufrufern aus erreichbar ist, ohne dass sie denselben Code
# doppelt pflegen muessten.

use strict;
use warnings;
use Exporter 'import';
use LoxBerry::System;
use LoxBerry::JSON;
use LoxBerry::Log;
use File::Path qw(make_path);

our @EXPORT_OK = qw(
    docker_paths
    docker_config_read
    docker_config_write
    docker_password_neu
    docker_bin
    docker_version
    docker_zustand
    docker_container
    docker_zaehlung
    docker_portainer_laeuft
    docker_portainer_einrichten
    docker_log
);

our $PORTAINER_IMAGE = 'portainer/portainer-ce:latest';

# Eigener Containername und eigenes Datenverzeichnis - bewusst NICHT das
# schlichte "portainer" / "/opt/portainer".
#
# Das urspruengliche Docker-Plugin von Michael Miklis startet seinen Portainer
# unter genau diesen beiden Namen. Docker NG ist ausdruecklich so gebaut, dass
# es neben dem Original installiert sein kann - bei gleichen Namen griffen
# beide nach demselben Container und demselben Datenverzeichnis. Wer beide
# installiert hat und Docker NG wieder entfernt, verloere sonst den Portainer
# des anderen Plugins samt aller darin angelegten Benutzerkonten.
#
# Mit eigenen Namen ist der Besitz eindeutig: was "portainer-ng" heisst und in
# /opt/portainer-ng liegt, gehoert diesem Plugin und darf bei der
# Deinstallation restlos weg. Keine Ratespiele darueber, wem was gehoert.
our $PORTAINER_NAME_STD = 'portainer-ng';
our $PORTAINER_DATA     = '/opt/portainer-ng';

# FOLDER aus plugin.cfg - die eingefrorene Identitaet des Plugins, darf laut
# LoxBerry-Konvention hartkodiert werden (aendert sich im Normalbetrieb nie).
#
# NICHT auf $lbpconfigdir/$lbplogdir/$lbpbindir verlassen: LoxBerry::System
# leitet diese aus dem Pfad von $0 ab, und dessen Muster kennt nur
# webfrontend/, templates/, log/, data/, config/, bin/ und system/daemons/
# jeweils unter plugins/. Ein Cronjob unter system/cron/cron.05min/ passt in
# keins davon - dort blieben alle $lbp*-Variablen leer, und ein darauf
# aufbauendes LoxBerry::Log->new() wuerde sogar abbrechen ("Cannot determine
# plugin log directory"). $lbhomedir dagegen wird immer gesetzt, unabhaengig
# vom Aufrufpfad - darauf bauen alle Pfade hier auf, fuer CGI, Cronjob und
# Installationsskript gleichermassen.
our $PLUGINFOLDER = 'dockerng';

# Ein Log fuer alle Aufrufer (CGI, Cronjob, das Installationsskript). Nutzt
# den in plugin.cfg freigeschalteten CUSTOM_LOGLEVELS-Mechanismus tatsaechlich
# - vorher stand das Merkmal in der plugin.cfg, ohne dass irgendein Code
# LoxBerry::Log benutzt haette, und der Loglevel-Waehler in der
# Pluginverwaltung war wirkungslos.
my $_log;
sub docker_log {
    if (!$_log) {
        my $p = docker_paths();
        $_log = LoxBerry::Log->new(
            name    => 'docker',
            package => $PLUGINFOLDER,
            logdir  => $p->{logdir},
            addtime => 1,
            append  => 1,
        );
    }
    return $_log;
}

# ---------------- Pfade ----------------

sub docker_paths {
    my $configdir = "$lbhomedir/config/plugins/$PLUGINFOLDER";
    my $logdir    = "$lbhomedir/log/plugins/$PLUGINFOLDER";

    # config/ liefert nur mqtt_subscriptions.cfg mit - config/plugins/dockerng/
    # entsteht dadurch zwar normalerweise schon bei der Installation, aber
    # LoxBerry::JSON legt fuer die eigentliche Konfigurationsdatei nur die
    # Datei an, nicht den Ordner darueber. Dieses make_path ist das
    # Sicherheitsnetz, falls der Ordner aus irgendeinem Grund doch fehlt.
    make_path($configdir) if (!-d $configdir);
    make_path($logdir) if (!-d $logdir);

    return {
        config    => "$configdir/dockerng.json",
        configdir => $configdir,
        logdir    => $logdir,
    };
}

# ---------------- Konfiguration ----------------
#
# LoxBerry::JSON uebernimmt Anlegen, Sperren (flock) und Schreiben der Datei -
# dafuer ist die Bibliothek da, ein eigenes file_get_contents/file_put_contents
# waere nur eine schlechtere Kopie davon.

sub docker_config_read {
    my $p = docker_paths();
    my $json = LoxBerry::JSON->new();
    my $cfg = $json->open(filename => $p->{config}, readonly => 1, locktimeout => 3);
    $cfg = {} if (!defined $cfg || ref($cfg) ne 'HASH');

    $cfg->{portainer_port} = 9000 if (!$cfg->{portainer_port} || $cfg->{portainer_port} !~ /^\d+$/);
    $cfg->{portainer_name} = $PORTAINER_NAME_STD
        if (!defined $cfg->{portainer_name} || $cfg->{portainer_name} !~ /^[A-Za-z0-9_.-]{1,64}$/);
    $cfg->{portainer_password} = '' if (!defined $cfg->{portainer_password});
    return $cfg;
}

sub docker_config_write {
    my ($neu) = @_;
    my $p = docker_paths();
    my $json = LoxBerry::JSON->new();
    my $cfg = $json->open(filename => $p->{config}, lockexclusive => 1, locktimeout => 3);
    return 0 if (!defined $json->{jsonobj});

    $cfg->{$_} = $neu->{$_} for (keys %$neu);
    $json->{jsonobj} = $cfg;
    $json->write();

    # Nur fuer loxberry lesbar - dort steht das Portainer-Passwort im Klartext.
    chmod 0600, $p->{config};

    # Der Rueckgabewert von LoxBerry::JSON->write() taugt NICHT als
    # Erfolgspruefung: die Methode steigt mit einem leeren 'return' aus, wenn
    # der neue Inhalt mit dem bestehenden identisch ist ("JSON are equal -
    # nothing to do", JSON.pm um Zeile 181). Das ist Erfolg, sah hier aber wie
    # ein Fehlschlag aus - beim Neuaufbau von Portainer ohne Aenderung
    # (gleiches Passwort, gleicher Port, gleicher Name) meldete das Plugin
    # daraufhin "das Passwort liess sich NICHT speichern, es ist verloren",
    # obwohl es unveraendert und korrekt in der Datei stand.
    #
    # Geprueft wird deshalb das Ergebnis statt des Rueckgabewerts: steht
    # hinterher in der Datei, was hineingeschrieben werden sollte?
    #
    # Das Schreibobjekt muss dafuer zuerst weg: es haelt wegen lockexclusive
    # eine exklusive Sperre auf der Datei, an der die Kontrolle sonst
    # scheitert ("Could not get lock after 3 seconds"). undef gibt das
    # Dateihandle und damit die Sperre frei.
    undef $json;

    my $kontrolle = LoxBerry::JSON->new();
    my $geschrieben = $kontrolle->open(filename => $p->{config}, readonly => 1, locktimeout => 3);
    return 0 if (!defined $geschrieben || ref($geschrieben) ne 'HASH');

    foreach my $schluessel (keys %$neu) {
        my $soll = defined $neu->{$schluessel} ? $neu->{$schluessel} : '';
        my $ist  = defined $geschrieben->{$schluessel} ? $geschrieben->{$schluessel} : '';
        return 0 if ($soll ne $ist);
    }
    return 1;
}

# Zeichen ohne 0/O/1/l/I - beim Ablesen vom Bildschirm sonst verwechselbar,
# und dieses Passwort wird per Hand in Portainer eingetippt, nicht kopiert.
sub docker_password_neu {
    my ($laenge) = @_;
    $laenge ||= 20;
    my @zeichen = split //, 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    my $aus = '';
    $aus .= $zeichen[int(rand(scalar @zeichen))] for (1 .. $laenge);
    return $aus;
}

# ---------------- Docker ----------------
#
# Ein Befehl wird NIE mit '2>/dev/null' abgesetzt: nach einer frischen
# Installation steht loxberry zwar in der Gruppe docker, der bereits laufende
# Webserver hat diese Gruppe aber noch nicht - Linux zieht Gruppen fuer
# laufende Prozesse nicht nach. 'docker ps' scheitert dann mit
# 'permission denied' und Rueckgabewert 1. Mit '2>/dev/null' waere davon
# nichts angekommen: leere Ausgabe, leere Liste, und das Plugin haette
# faelschlich '0 Container' gemeldet, waehrend tatsaechlich alles laeuft.
sub _ausfuehren {
    my ($befehl) = @_;
    my $fehlerdatei = "/tmp/dockerplugin_stderr.$$";
    my @ausgabe = `$befehl 2>$fehlerdatei`;
    my $code = $? >> 8;
    my $fehler = '';
    if (open(my $fh, '<', $fehlerdatei)) {
        local $/;
        $fehler = <$fh> // '';
        close($fh);
    }
    unlink($fehlerdatei);
    chomp(@ausgabe);
    return (\@ausgabe, $fehler, $code);
}

sub docker_bin {
    my (undef, undef, $code) = _ausfuehren('command -v docker');
    return $code == 0 ? 1 : 0;
}

sub docker_version {
    return '' if (!docker_bin());
    my ($ausgabe, $fehler, $code) = _ausfuehren('docker --version');
    return $code == 0 ? $ausgabe->[0] : $fehler;
}

# Warum klappt der Zugriff auf Docker nicht? Rueckgabe: (ok, grund, meldung).
sub docker_zustand {
    if (!docker_bin()) {
        return (0, 'KEIN_DOCKER', 'Das Programm docker ist nicht vorhanden.');
    }
    my (undef, $fehler, $code) = _ausfuehren('docker ps --format "{{.Names}}"');
    return (1, '', '') if ($code == 0);

    my $t = lc($fehler);
    if ($t =~ /permission denied/) {
        return (0, 'KEINE_RECHTE',
            'Der Webserver darf noch nicht auf den Docker-Socket zugreifen. Das ist nach '
            . 'einer frischen Installation der Regelfall: der Benutzer loxberry wurde der '
            . 'Gruppe docker hinzugefuegt, aber Linux zieht neue Gruppen fuer bereits '
            . 'laufende Prozesse nicht nach. Ein Neustart des LoxBerry oder von Apache '
            . '(sudo systemctl restart apache2) behebt es.');
    }
    if ($t =~ /cannot connect to the docker daemon|is the docker daemon running/) {
        return (0, 'DIENST_AUS',
            'Der Docker-Dienst laeuft nicht. Pruefen mit: systemctl status docker');
    }
    return (0, 'FEHLER', $fehler ne '' ? $fehler : "docker endete mit Rueckgabewert $code ohne Meldung.");
}

sub docker_container {
    return [] if (!docker_bin());
    my ($ok) = docker_zustand();
    return [] if (!$ok);

    my ($ausgabe, undef, $code) = _ausfuehren(q{docker ps -a --format '{{.Names}}}."\t".q{{{.Image}}}."\t".q{{{.Status}}}."'");
    return [] if ($code != 0);

    my @liste;
    foreach my $zeile (@$ausgabe) {
        next if ($zeile eq '');
        my @t = split(/\t/, $zeile);
        next if (scalar(@t) < 3);
        push @liste, {
            name    => $t[0],
            image   => $t[1],
            status  => $t[2],
            laeuft  => (index($t[2], 'Up') == 0) ? 1 : 0,
        };
    }
    return \@liste;
}

sub docker_zaehlung {
    my $alle = docker_container();
    my $laeuft = 0;
    $laeuft += $_->{laeuft} for (@$alle);
    return {
        gesamt   => scalar(@$alle),
        laeuft   => $laeuft,
        gestoppt => scalar(@$alle) - $laeuft,
        liste    => $alle,
    };
}

sub docker_portainer_laeuft {
    my ($name) = @_;
    foreach my $c (@{docker_container()}) {
        return 1 if ($c->{name} eq $name && $c->{laeuft} == 1);
    }
    return 0;
}

# ---------------- Portbelegung ----------------
#
# Portainers Standardport 9000 ist nicht exklusiv - z.B. AudioServer4Home
# (sonn-core, network_mode: host) hoert selbst auf 9000. 'docker run -p 9000:9000'
# scheitert dann mit 'address already in use', und bislang brach die gesamte
# Portainer-Einrichtung darueber ab (bestaetigt im LoxBerry-Forum: die
# Installation schlaegt genau dann fehl, wenn AudioServer4Home bereits laeuft -
# ohne es installiert sich Docker NG sauber). Ein Portkonflikt ist kein Grund,
# die Einrichtung abzubrechen - ein freier Port tut es genauso.
sub _port_frei {
    my ($port) = @_;
    my ($belegt) = _ausfuehren("ss -Htln sport = :$port");
    return (scalar(@$belegt) == 0) ? 1 : 0;
}

# Sucht ab $start aufwaerts den ersten freien Port (max. 50 Versuche - mehr
# deutet auf ein grundsaetzliches Problem hin, das ein Ausweichen nicht loest).
sub _freien_port_finden {
    my ($start) = @_;
    for my $kandidat ($start .. $start + 49) {
        return $kandidat if (_port_frei($kandidat));
    }
    return $start;
}

# ---------------- Portainer einrichten ----------------
#
# Eine einzige Funktion fuer zwei Aufrufer: postroot.sh bei der Installation
# und die Schaltflaeche "Portainer neu einrichten" in der Oberflaeche. Zwei
# getrennte Implementierungen derselben sicherheitsrelevanten Logik laufen
# ueber die Zeit auseinander - genau das ist hier zu vermeiden.
#
# Das Administrator-Passwort setzt Portainer nur beim ALLERERSTEN Start einer
# Instanz ohne bestehendes Konto - --admin-password-file wird bei jedem
# spaeteren Start stillschweigend ignoriert. Ein bestehender Container wird
# deshalb nur bei $force entfernt (das Datenverzeichnis bleibt
# davon unberuehrt, das Konto darin ueberlebt die Neuerstellung des
# Containers und der neue Aufruf hat dann ohnehin keine Wirkung mehr).
#
# Ohne '--http-enabled' antwortet Portainer ab 2.19 auf Port 9000 nicht mit
# der Anmeldeseite, sondern mit einer Weiterleitung auf /timeout.html - der
# Port wirkt dann offen, ist es aber nicht. Deshalb zusaetzlich Port 9443
# freigeben.
#
# Rueckgabe: (erfolg, meldung).
sub docker_portainer_einrichten {
    my ($force) = @_;
    my $cfg  = docker_config_read();
    my $name = $cfg->{portainer_name};
    my $port = $cfg->{portainer_port};
    my $qname = quotemeta($name);

    my ($korrekt) = _ausfuehren(
        "docker ps --filter ancestor=$PORTAINER_IMAGE --filter name=$qname -q");
    my $laeuft_korrekt = (scalar(@$korrekt) > 0) ? 1 : 0;

    if ($laeuft_korrekt && !$force) {
        docker_log()->INF('Portainer laeuft bereits in der erwarteten Version - nichts zu tun.');
        return (1, 'Portainer laeuft bereits in der erwarteten Version - nichts zu tun.');
    }

    docker_log()->INF("Richte Portainer ein (force=$force, name=$name, port=$port).");

    # Vorhandenen Container entfernen, egal in welchem Zustand (laeuft,
    # gestoppt, falsche Version). Das Datenverzeichnis bleibt unberuehrt - das ist
    # ein Bind-Mount auf ein Host-Verzeichnis, kein vom Container verwaltetes
    # Volume, und geht beim Entfernen des Containers nicht verloren.
    my ($vorhanden) = _ausfuehren("docker ps -a --filter name=$qname -q");
    if (@$vorhanden) {
        my (undef, $fehler, $code) = _ausfuehren('docker rm --force ' . $qname);
        if ($code != 0) {
            docker_log()->ERR("Vorhandener Container liess sich nicht entfernen: $fehler");
            return (0, "Vorhandener Container liess sich nicht entfernen: $fehler");
        }
        docker_log()->INF('Vorhandener Container entfernt.');
    }

    # Portpruefung ERST NACH dem Entfernen des alten Containers: hielt
    # Portainer selbst den Port (Normalfall bei einem Neuaufbau), ist er jetzt
    # frei und wuerde sonst faelschlich als 'belegt' gelten.
    if (!_port_frei($port)) {
        my $ausweich = _freien_port_finden($port + 1);
        docker_log()->WARN("Port $port ist belegt (vermutlich ein anderer Dienst mit "
            . "eigenem Netzwerk, z.B. AudioServer4Home) - weiche auf Port $ausweich aus.");
        $port = $ausweich;
        $cfg->{portainer_port} = $port;
    }

    # Der HTTPS-Zusatzport ist ein Bonus, kein Muss - '--http-enabled' macht
    # Portainer bereits ueber $port vollstaendig erreichbar. Ist 9443 belegt,
    # wird die Zuordnung einfach weggelassen statt die ganze Einrichtung
    # daran scheitern zu lassen.
    my $https_zuordnung = ' -p=9443:9443';
    if (!_port_frei(9443)) {
        docker_log()->WARN('Port 9443 ist belegt - Portainer bleibt ohne den optionalen '
            . 'HTTPS-Zusatzport erreichbar, der normale Zugang ueber Port '
            . $port . ' funktioniert davon unabhaengig.');
        $https_zuordnung = '';
    }

    my (undef, $pullfehler, $pullcode) = _ausfuehren("docker pull $PORTAINER_IMAGE");
    if ($pullcode != 0) {
        docker_log()->ERR("Abbild liess sich nicht laden: $pullfehler");
        return (0, "Abbild liess sich nicht laden: $pullfehler");
    }

    # Passwort wiederverwenden, falls schon eins gesetzt wurde (z.B. bei
    # einem Update, wo der Container aus anderem Grund neu aufgesetzt wird) -
    # sonst neu erzeugen. So bleibt ein bereits bekanntes Anmeldepasswort
    # gueltig, statt bei jedem Neuaufbau ein neues zu wuerfeln.
    my $passwort = $cfg->{portainer_password};
    if (!$passwort) {
        $passwort = docker_password_neu();
    }

    # Das Passwort landet NUR fluechtig auf der Platte, fuer den einen
    # Moment, in dem der Docker-Daemon (als root) die Bind-Mount-Quelle liest.
    # /tmp traegt sowohl von root (postroot.sh) als auch von loxberry (CGI)
    # aus - der Daemon selbst liest als root ohnehin unabhaengig von den
    # Dateirechten des Erstellers.
    my $pwdatei = "/tmp/portainer_admin_password.$$";
    if (!open(my $fh, '>', $pwdatei)) {
        docker_log()->ERR("Temporaere Passwortdatei liess sich nicht anlegen: $!");
        return (0, "Temporaere Passwortdatei liess sich nicht anlegen: $!");
    } else {
        chmod 0600, $pwdatei;
        print {$fh} $passwort;
        close($fh);
    }

    my $run = 'docker run'
        . ' --volume=/var/run/docker.sock:/var/run/docker.sock'
        . " --volume=$PORTAINER_DATA:/data"
        . " --volume=$pwdatei:/run/portainer_admin_password:ro"
        . " -p=$port:9000$https_zuordnung"
        . " --name=$qname --restart=unless-stopped --detach=true"
        . " $PORTAINER_IMAGE --http-enabled --admin-password-file=/run/portainer_admin_password";
    my (undef, $runfehler, $runcode) = _ausfuehren($run);

    # Das Bootstrap-Passwort wird nur beim allerersten Start OHNE bestehendes
    # Konto ausgewertet. Kurz warten, bis Portainer antwortet, dann erst die
    # Datei entfernen - sonst besteht ein winziges Zeitfenster, in dem der
    # Container zwar schon laeuft, das Passwort aber noch nicht gelesen hat.
    if ($runcode == 0) {
        for (1 .. 10) {
            my (undef, undef, $code) = _ausfuehren("curl -s -o /dev/null -m 2 http://127.0.0.1:$port/");
            last if ($code == 0);
            sleep(1);
        }
    }
    unlink($pwdatei);

    if ($runcode != 0) {
        docker_log()->ERR("Portainer liess sich nicht starten: $runfehler");
        return (0, "Portainer liess sich nicht starten: $runfehler");
    }

    # Der Container laeuft ab hier auf jeden Fall - ein Fehlschlag ab hier
    # bedeutet nicht "nicht eingerichtet", sondern "eingerichtet, aber das
    # Passwort ist verloren". Beides zu vermelden waere falsch: (1,...) taeuscht
    # Erfolg vor, obwohl niemand mehr weiss, mit welchem Passwort man hineinkommt.
    $cfg->{portainer_password} = $passwort;
    if (!docker_config_write($cfg)) {
        docker_log()->ERR('Portainer laeuft, aber das Passwort liess sich nicht speichern.');
        return (0, 'Portainer laeuft, aber das Passwort liess sich NICHT speichern. '
                 . 'Es ist damit verloren. Bitte ueber "Portainer neu einrichten" '
                 . 'einen neuen Versuch starten.');
    }

    docker_log()->OK('Portainer wurde eingerichtet.');
    return (1, 'Portainer wurde eingerichtet.');
}

1;
