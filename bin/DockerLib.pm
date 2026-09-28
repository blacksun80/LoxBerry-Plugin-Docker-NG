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
use JSON ();

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
    docker_portainer_hostports
    docker_portainer_passwort_pruefen
    docker_portainer_passwort_zuruecksetzen
    docker_port_gueltig
    docker_port_frei
    docker_ports_vorschlagen
    docker_container_ports
    docker_port_schema
    docker_log
);

our $PORTAINER_IMAGE = 'portainer/portainer-ce:latest';

# Standardports für Neuinstallationen (Host-Seite).
our $PORT_HTTP_STD  = 9990;
our $PORT_HTTPS_STD = 9443;

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

    # Gespeicherte Ports bleiben erhalten, fehlende oder ungültige erhalten den Standardwert.
    $cfg->{portainer_port} = $PORT_HTTP_STD if (!docker_port_gueltig($cfg->{portainer_port}));
    $cfg->{portainer_https_port} = $PORT_HTTPS_STD if (!docker_port_gueltig($cfg->{portainer_https_port}));
    $cfg->{portainer_name} = $PORTAINER_NAME_STD
        if (!defined $cfg->{portainer_name} || $cfg->{portainer_name} !~ /^[A-Za-z0-9_.-]{1,64}$/);
    $cfg->{portainer_password} = '' if (!defined $cfg->{portainer_password});
    $cfg->{portainer_password_geaendert} = $cfg->{portainer_password_geaendert} ? 1 : 0;
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

# Prüft, ob $port eine Zahl von 1024 bis 65535 ist.
sub docker_port_gueltig {
    my ($port) = @_;
    return (defined $port && $port =~ /^\d{1,5}$/ && $port >= 1024 && $port <= 65535) ? 1 : 0;
}

# Prüft per ss, ob auf $port ein TCP-Dienst lauscht.
# Rückgabe: 1 = frei, 0 = belegt, undef = ss nicht ausführbar.
sub docker_port_frei {
    my ($port) = @_;
    return 0 if (!docker_port_gueltig($port));
    my ($belegt, $fehler, $code) = _ausfuehren("ss -Htln sport = :$port");
    if ($code != 0) {
        docker_log()->ERR("Portbelegung ließ sich nicht prüfen (ss, Rückgabewert $code): $fehler");
        return undef;
    }
    return (scalar(grep { $_ ne '' } @$belegt) == 0) ? 1 : 0;
}

# Sucht ab $start bis 65535, danach ab 1024 bis $start den ersten freien
# Port, der nicht in @ausser steht. Rückgabe: Port oder undef.
sub _freien_port_finden {
    my ($start, @ausser) = @_;
    my %ausser = map { $_ => 1 } grep { defined } @ausser;
    for my $kandidat ($start .. 65535, 1024 .. $start - 1) {
        next if ($ausser{$kandidat});
        my $frei = docker_port_frei($kandidat);
        return undef if (!defined $frei);
        return $kandidat if ($frei);
    }
    return undef;
}

# Liefert die Hostports des laufenden Containers $name als Hash,
# z.B. { 9990 => 1, 9443 => 1 }. Leer, wenn der Container nicht läuft.
sub docker_portainer_hostports {
    my ($name) = @_;
    my %ports;
    my ($ausgabe, undef, $code) = _ausfuehren('docker port ' . quotemeta($name));
    return \%ports if ($code != 0);
    foreach my $zeile (@$ausgabe) {
        # 9000/tcp -> 0.0.0.0:9990   bzw.   9000/tcp -> [::]:9990
        $ports{$1} = 1 if ($zeile =~ /->\s*\S*:(\d+)\s*$/);
    }
    return \%ports;
}

# Port ist frei oder von Portainer selbst belegt ($eigen aus
# docker_portainer_hostports). Rückgabe wie docker_port_frei.
sub _port_verwendbar {
    my ($port, $eigen) = @_;
    return 1 if ($eigen->{$port});
    return docker_port_frei($port);
}

# Vorschlag für "Freie Ports suchen": verwendbare Ports bleiben, belegte
# werden durch den nächsten freien ersetzt. Rückgabe: (http, https) oder ().
sub docker_ports_vorschlagen {
    my $cfg   = docker_config_read();
    my $eigen = docker_portainer_hostports($cfg->{portainer_name});
    my $http  = $cfg->{portainer_port};
    my $https = $cfg->{portainer_https_port};

    my $ok = _port_verwendbar($http, $eigen);
    return () if (!defined $ok);
    if (!$ok) {
        $http = _freien_port_finden($http + 1, $https);
        return () if (!defined $http);
    }

    $ok = ($https != $http) ? _port_verwendbar($https, $eigen) : 0;
    return () if (!defined $ok);
    if (!$ok) {
        $https = _freien_port_finden($https + 1, $http);
        return () if (!defined $https);
    }
    return ($http, $https);
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
# Portainer lauscht im Container auf 9000 (HTTP, mit --http-enabled) und
# 9443 (HTTPS). Die Hostports stammen aus der Konfiguration oder aus $wunsch
# ({ http => ..., https => ... }); ein belegter Konfigurationsport wird durch
# den nächsten freien ersetzt, ein belegter Wunschport führt zum Abbruch.
#
# Rückgabe: (erfolg, meldung, schlüssel, argumente...). Der Schlüssel benennt
# den Fehler für die Übersetzung in der Oberfläche (language_*.ini).
sub docker_portainer_einrichten {
    my ($force, $wunsch) = @_;
    my $cfg  = docker_config_read();
    my $name = $cfg->{portainer_name};
    my $qname = quotemeta($name);

    # Wunschports prüfen, solange der bestehende Container noch unangetastet ist.
    if ($wunsch) {
        my ($http, $https) = ($wunsch->{http}, $wunsch->{https});
        if (!docker_port_gueltig($http) || !docker_port_gueltig($https)) {
            return (0, 'Die Ports müssen Zahlen von 1024 bis 65535 sein.', 'FEHLER_PORT_UNGUELTIG');
        }
        if ($http == $https) {
            return (0, 'HTTP- und HTTPS-Port dürfen nicht gleich sein.', 'FEHLER_PORT_GLEICH');
        }
        my $eigen = docker_portainer_hostports($name);
        foreach my $p ($http, $https) {
            my $ok = _port_verwendbar($p, $eigen);
            return (0, 'Die Portbelegung ließ sich nicht prüfen (ss).', 'FEHLER_PORT_PRUEFUNG') if (!defined $ok);
            return (0, "Port $p wird bereits von einem anderen Dienst verwendet.", 'FEHLER_PORT_BELEGT', $p) if (!$ok);
        }
        $cfg->{portainer_port}       = $http + 0;
        $cfg->{portainer_https_port} = $https + 0;
        $force = 1;
    }

    my $port       = $cfg->{portainer_port};
    my $https_port = $cfg->{portainer_https_port};

    my ($korrekt) = _ausfuehren(
        "docker ps --filter ancestor=$PORTAINER_IMAGE --filter name=$qname -q");
    my $laeuft_korrekt = (scalar(@$korrekt) > 0) ? 1 : 0;

    if ($laeuft_korrekt && !$force) {
        # Container mit Passwortdatei unter /tmp (Version 1.0) wird neu aufgebaut.
        my ($quellen) = _ausfuehren("docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}' $qname");
        if (join(' ', @$quellen) !~ m{^/tmp/|\s/tmp/}) {
            docker_log()->INF('Portainer laeuft bereits in der erwarteten Version - nichts zu tun.');
            return (1, 'Portainer laeuft bereits in der erwarteten Version - nichts zu tun.');
        }
        docker_log()->INF('Portainer nutzt noch eine Passwortdatei unter /tmp - wird neu aufgebaut.');
    }

    docker_log()->INF("Richte Portainer ein (force=$force, name=$name, http=$port, https=$https_port).");

    # Abbild und Passwortdatei vorbereiten, solange der bestehende Container noch läuft.
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
    my $passwort_unbekannt = 0;
    if (!$passwort) {
        $passwort = docker_password_neu();
        # Bestehende Portainer-Datenbank: Das Kennwort aus der Datei wird nicht
        # übernommen, deshalb bleibt es unbekannt und wird nicht gespeichert.
        if (-e "$PORTAINER_DATA/portainer.db") {
            $passwort_unbekannt = 1;
            docker_log()->WARN('Portainer hat bereits ein Administratorkonto, dessen Kennwort nicht gespeichert ist.');
        }
    }

    # Die Passwortdatei liegt DAUERHAFT im Datenverzeichnis - nicht in /tmp,
    # und sie wird nach dem Start auch nicht mehr geloescht.
    #
    # Frueher lag sie unter /tmp/portainer_admin_password.<PID> und wurde
    # gleich nach dem Start entfernt. Das war ein schwerer Fehler: die Datei
    # ist Quelle eines Bind-Mounts, und der gehoert dauerhaft zur
    # Container-Definition. Solange der Container durchlief, fiel es nicht
    # auf - sobald er aber neu starten musste (Neustart des Docker-Dienstes,
    # etwa weil ein anderes Plugin Docker-Pakete installiert, oder schlicht
    # ein Reboot), wollte Docker den Mount wiederherstellen, fand die Quelle
    # nicht und legte an ihrer Stelle ein VERZEICHNIS an. Portainer bekam
    # damit ein Verzeichnis statt einer Datei und brach mit Rueckgabewert 127
    # ab: der Container blieb tot zurueck.
    #
    # Nachgestellt: nach der Installation von AudioServer4Home stand
    # portainer-ng auf "Exited (127)", waehrend Port 9000 voellig frei war -
    # es war also nie ein Portkonflikt, sondern immer diese fehlende Datei.
    #
    # Sicherheitlich ist das unbedenklich: dasselbe Passwort steht ohnehin in
    # dockerng.json. Die Datei bekommt 0600 und liegt in einem Verzeichnis,
    # das bei der Deinstallation mitentfernt wird.
    make_path($PORTAINER_DATA) if (!-d $PORTAINER_DATA);

    # Eigentuemer auf loxberry setzen, solange wir root sind (Installation).
    # Sonst gehoert das Verzeichnis root, und die Oberflaeche - die als
    # loxberry laeuft - koennte die Passwortdatei bei "Portainer neu
    # einrichten" nicht schreiben ("Inappropriate ioctl for device", genau so
    # aufgetreten). Portainer selbst laeuft im Container als root und schreibt
    # unabhaengig davon weiter in /data.
    if ($> == 0) {
        my (undef, undef, $uid, $gid) = getpwnam('loxberry');
        chown($uid, $gid, $PORTAINER_DATA) if (defined $uid);
    }

    my $pwdatei = "$PORTAINER_DATA/.admin_password";

    # Nur schreiben, wenn noetig. Steht das richtige Passwort schon drin,
    # bleibt die Datei unangetastet - das vermeidet einen Schreibversuch in
    # Faellen, in denen die Rechte nicht passen, obwohl gar nichts zu tun ist.
    my $pw_vorhanden = '';
    if (open(my $lesen, '<', $pwdatei)) {
        local $/;
        $pw_vorhanden = <$lesen> // '';
        close($lesen);
    }

    if ($pw_vorhanden ne $passwort) {
        # Nicht beschreibbare Datei (z.B. von root angelegt) im eigenen Verzeichnis ersetzen.
        unlink($pwdatei) if (-e $pwdatei && !-w $pwdatei);
        if (!open(my $fh, '>', $pwdatei)) {
            docker_log()->ERR("Passwortdatei liess sich nicht anlegen: $!");
            return (0, "Passwortdatei liess sich nicht anlegen: $!");
        } else {
            print {$fh} $passwort;
            close($fh);
        }
    }
    chmod 0600, $pwdatei;
    if ($> == 0) {
        my (undef, undef, $uid, $gid) = getpwnam('loxberry');
        chown($uid, $gid, $pwdatei) if (defined $uid);
    }

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

    # Portprüfung nach dem Entfernen des alten Containers, dessen Ports jetzt frei sind.
    foreach my $art ('http', 'https') {
        my $schluessel = ($art eq 'http') ? 'portainer_port' : 'portainer_https_port';
        my $anderer    = ($art eq 'http') ? $cfg->{portainer_https_port} : $cfg->{portainer_port};
        my $p = $cfg->{$schluessel};

        my $frei = docker_port_frei($p);
        if (!defined $frei) {
            return (0, 'Die Portbelegung ließ sich nicht prüfen (ss).', 'FEHLER_PORT_PRUEFUNG');
        }
        next if ($frei);

        if ($wunsch) {
            docker_log()->ERR("Port $p wurde zwischenzeitlich von einem anderen Dienst belegt.");
            return (0, "Port $p wird bereits von einem anderen Dienst verwendet.", 'FEHLER_PORT_BELEGT', $p);
        }

        my $ausweich = _freien_port_finden($p + 1, $anderer);
        if (!defined $ausweich) {
            docker_log()->ERR("Für $art ist kein freier Port zu finden.");
            return (0, "Für $art ist kein freier Port zu finden.", 'FEHLER_KEIN_PORT');
        }
        docker_log()->WARN("Port $p ($art) ist belegt - weiche auf Port $ausweich aus.");
        $cfg->{$schluessel} = $ausweich;
    }
    $port       = $cfg->{portainer_port};
    $https_port = $cfg->{portainer_https_port};

    my $run = 'docker run'
        . ' --volume=/var/run/docker.sock:/var/run/docker.sock'
        . " --volume=$PORTAINER_DATA:/data"
        . " --volume=$pwdatei:/run/portainer_admin_password:ro"
        . " -p=$port:9000 -p=$https_port:9443"
        . " --name=$qname --restart=unless-stopped --detach=true"
        . " $PORTAINER_IMAGE --http-enabled --admin-password-file=/run/portainer_admin_password";
    my (undef, $runfehler, $runcode) = _ausfuehren($run);

    # Warten, bis Portainer antwortet - das Bootstrap-Passwort wird nur beim
    # allerersten Start ohne bestehendes Konto ausgewertet, und der Aufrufer
    # soll erst zurueckkehren, wenn der Dienst wirklich erreichbar ist.
    #
    # Die Passwortdatei wird hier NICHT geloescht: sie ist Quelle eines
    # Bind-Mounts und muss existieren, solange der Container existiert (siehe
    # ausfuehrliche Begruendung weiter oben).
    if ($runcode == 0) {
        for (1 .. 10) {
            my (undef, undef, $code) = _ausfuehren("curl -s -o /dev/null -m 2 http://127.0.0.1:$port/");
            last if ($code == 0);
            sleep(1);
        }
    }

    if ($runcode != 0) {
        docker_log()->ERR("Portainer liess sich nicht starten: $runfehler");
        return (0, "Portainer liess sich nicht starten: $runfehler");
    }

    # Der Container laeuft ab hier auf jeden Fall - ein Fehlschlag ab hier
    # bedeutet nicht "nicht eingerichtet", sondern "eingerichtet, aber das
    # Passwort ist verloren". Beides zu vermelden waere falsch: (1,...) taeuscht
    # Erfolg vor, obwohl niemand mehr weiss, mit welchem Passwort man hineinkommt.
    if (!$passwort_unbekannt) {
        $cfg->{portainer_password} = $passwort;
        $cfg->{portainer_password_geaendert} = 0;
    }
    if (!docker_config_write($cfg)) {
        docker_log()->ERR('Portainer laeuft, aber das Passwort liess sich nicht speichern.');
        return (0, 'Portainer laeuft, aber das Passwort liess sich NICHT speichern. '
                 . 'Es ist damit verloren. Bitte ueber "Portainer neu einrichten" '
                 . 'einen neuen Versuch starten.');
    }

    docker_log()->OK('Portainer wurde eingerichtet.');
    return (1, 'Portainer wurde eingerichtet.');
}

# Meldet sich mit Benutzer "admin" und $passwort testweise an Portainer an.
# Rückgabe: 1 = Kennwort gültig, 0 = abgelehnt (422 "Invalid credentials"), undef = nicht prüfbar.
sub docker_portainer_passwort_pruefen {
    my ($port, $passwort) = @_;
    return undef if (!docker_port_gueltig($port) || !$passwort);

    # Anmeldedaten als Datei an curl, damit das Kennwort nicht in der Prozessliste steht.
    my $datei = "/tmp/dockerplugin_auth.$$";
    my $fh;
    return undef if (!open($fh, '>', $datei));
    chmod 0600, $datei;
    print {$fh} JSON::to_json({ Username => 'admin', Password => $passwort });
    close($fh);

    my ($ausgabe, undef, undef) = _ausfuehren(
        "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 --max-time 3"
        . " -H 'Content-Type: application/json' --data-binary \@$datei"
        . " http://127.0.0.1:$port/api/auth");
    unlink($datei);

    my $status = (@$ausgabe) ? $ausgabe->[0] : '';
    return 1 if ($status eq '200');
    return 0 if ($status eq '422');
    return undef;
}

# Setzt das Kennwort des ersten Portainer-Administrators mit dem Hilfsabbild
# portainer/helper-reset-password zurück: Abbild laden, Portainer stoppen,
# zurücksetzen, Portainer wieder starten, neues Kennwort speichern.
# Rückgabe: (erfolg, meldung).
sub docker_portainer_passwort_zuruecksetzen {
    my $cfg   = docker_config_read();
    my $qname = quotemeta($cfg->{portainer_name});
    my $hilfe = 'portainer/helper-reset-password';

    if (!-e "$PORTAINER_DATA/portainer.db") {
        return (0, 'Portainer hat noch kein Administratorkonto.');
    }

    my (undef, $pullfehler, $pullcode) = _ausfuehren("docker pull $hilfe");
    if ($pullcode != 0) {
        docker_log()->ERR("Hilfsabbild liess sich nicht laden: $pullfehler");
        return (0, "Hilfsabbild liess sich nicht laden: $pullfehler");
    }

    docker_log()->INF('Setze das Kennwort des Portainer-Administrators zurück.');
    _ausfuehren("docker stop $qname");
    my ($ausgabe, $fehler, $code) = _ausfuehren("docker run --rm --volume=$PORTAINER_DATA:/data $hilfe");
    my (undef, $startfehler, $startcode) = _ausfuehren("docker start $qname");

    my ($benutzer, $passwort);
    foreach my $zeile (@$ausgabe, split(/\n/, $fehler)) {
        $benutzer = $1 if ($zeile =~ /Password successfully updated for user: (\S+)\s*$/);
        $passwort = $1 if ($zeile =~ /Use the following password to login: (\S+)\s*$/);
    }
    if ($code != 0 || !defined $passwort) {
        docker_log()->ERR("Zurücksetzen fehlgeschlagen (Rückgabewert $code): $fehler");
        return (0, "Zurücksetzen fehlgeschlagen: $fehler");
    }
    if ($startcode != 0) {
        docker_log()->ERR("Portainer liess sich nach dem Zurücksetzen nicht starten: $startfehler");
    }
    docker_log()->OK("Kennwort für Benutzer " . ($benutzer // '?') . " zurückgesetzt.");

    # Passwortdatei auf das neue Kennwort bringen (bei bestehendem Konto von Portainer ignoriert).
    my $pwdatei = "$PORTAINER_DATA/.admin_password";
    unlink($pwdatei) if (-e $pwdatei && !-w $pwdatei);
    if (open(my $fh, '>', $pwdatei)) {
        chmod 0600, $pwdatei;
        print {$fh} $passwort;
        close($fh);
    }

    if (!docker_config_write({ portainer_password => $passwort, portainer_password_geaendert => 0 })) {
        docker_log()->ERR('Das neue Kennwort liess sich nicht speichern.');
        return (0, "Das Kennwort wurde zurückgesetzt, liess sich aber nicht speichern. Neues Kennwort: $passwort");
    }
    return (1, 'Das Kennwort wurde zurückgesetzt.');
}

# ---------------- Ports der Container ----------------

# Liefert für alle laufenden Container die veröffentlichten TCP-Hostports:
# { name => [ { port => ..., ip => ... }, ... ] }, nach Port sortiert. ip ist die
# Adresse, an die der Port gebunden ist (127.0.0.1 bei 0.0.0.0/::). Bei
# network_mode host die im Abbild freigegebenen Ports. An 127.0.0.1/::1
# gebundene Ports fehlen, da sie vom Browser aus nicht erreichbar sind.
sub docker_container_ports {
    my %ergebnis;
    my ($ids, undef, $code) = _ausfuehren('docker ps -q');
    return \%ergebnis if ($code != 0);
    my @ids = grep { /^[0-9a-f]+$/ } @$ids;
    return \%ergebnis if (!@ids);

    my $format = q({{.Name}}|{{.HostConfig.NetworkMode}}|)
        . q({{range $p, $b := .NetworkSettings.Ports}}{{range $b}}{{$p}}={{.HostIp}}={{.HostPort}} {{end}}{{end}}|)
        . q({{range $p, $v := .Config.ExposedPorts}}{{$p}} {{end}});
    my ($zeilen, undef, $icode) = _ausfuehren("docker inspect --format '$format' " . join(' ', @ids));
    return \%ergebnis if ($icode != 0);

    foreach my $zeile (@$zeilen) {
        my ($name, $netz, $veroeffentlicht, $freigegeben) = split(/\|/, $zeile, 4);
        next if (!defined $name || $name eq '');
        $name =~ s{^/}{};

        my %ports;
        foreach my $eintrag (split(/\s+/, $veroeffentlicht // '')) {
            my ($intern, $ip, $hostport) = split(/=/, $eintrag, 3);
            next if (!defined $hostport || $hostport !~ /^\d+$/ || $intern !~ m{/tcp$});
            next if ($ip eq '127.0.0.1' || $ip eq '::1');
            $ports{$hostport} //= ($ip eq '' || $ip eq '0.0.0.0' || $ip eq '::') ? '127.0.0.1' : $ip;
        }
        if (($netz // '') eq 'host') {
            foreach my $p (split(/\s+/, $freigegeben // '')) {
                $ports{$1} //= '127.0.0.1' if ($p =~ m{^(\d+)/tcp$});
            }
        }
        $ergebnis{$name} = [ map { { port => $_, ip => $ports{$_} } } sort { $a <=> $b } keys %ports ];
    }
    return \%ergebnis;
}

# Prüft, ob $ip:$port HTTPS spricht (TLS-Verbindung mit beliebiger HTTP-Antwort).
# Rückgabe: 'https' oder 'http'.
sub docker_port_schema {
    my ($ip, $port) = @_;
    return 'http' if (!docker_port_gueltig($port) || ($ip // '') !~ /^[0-9A-Fa-f.:]+$/);
    my $adresse = ($ip =~ /:/) ? "[$ip]" : $ip;
    my (undef, undef, $code) = _ausfuehren("curl -s -k -o /dev/null --max-time 3 https://$adresse:$port/");
    return ($code == 0) ? 'https' : 'http';
}

1;
