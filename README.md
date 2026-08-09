# Docker NG (LoxBerry-Plugin)

Richtet **Docker** und **Portainer** auf [LoxBerry](https://www.loxberry.de) ein und meldet
den Zustand aller Container an Loxone.

Eigenständiger Neustart des ursprünglichen
[Docker-Plugins von Michael Miklis](https://github.com/michaelmiklis/loxberry-plugin-docker) -
kein Update davon, sondern ein neues Plugin mit eigener Kennung, das sich daneben installieren
lässt. Der ursprüngliche Entwickler betreibt selbst keinen LoxBerry mehr und hat keine
Kapazität für die Weiterpflege.

## Voraussetzungen

- LoxBerry 3.0.0 oder neuer.
- Raspberry Pi oder x86-System, **32-Bit und 64-Bit** - Docker Engine und Portainer bieten
  beide `armv7`-Abbilder an, im Gegensatz zu manchen anderen Docker-basierten Anwendungen.
- Internetzugang zum Herunterladen von Docker-Engine und Portainer-Abbild.

## Funktionen

- Docker-Engine und Portainer werden bei der Installation automatisch eingerichtet.
- **Automatisch erzeugtes Administratorkennwort** für Portainer, direkt in der Oberfläche
  einsehbar - kein manuelles Ablesen eines Setup-Tokens aus dem Containerprotokoll mehr, das
  ohnehin nach fünf Minuten verfällt.
- `--http-enabled` wird beim Einrichten automatisch gesetzt: ab Portainer CE 2.19 bleibt Port
  9000 sonst stumm (Weiterleitung auf `/timeout.html` statt der Anmeldeseite).
- Statuskacheln, Containertabelle, Schaltfläche "Portainer neu einrichten" für einen
  kontrollierten Neuaufbau.
- Containerzustand alle fünf Minuten per MQTT gemeldet (`docker/ok`, `docker/gesamt`,
  `docker/laeuft`, `docker/gestoppt`, `docker/portainer`, je ein `docker/container/<Name>`) -
  das Thema `docker/#` wird automatisch beim MQTT-Gateway registriert, kein manuelles
  Eintippen nötig.
- Konfiguration (inklusive Administratorkennwort) übersteht Plugin-Updates - LoxBerry löscht
  den Konfigurationsordner sonst bei jedem Update, bevor die Installation abgeschlossen ist.
- `LoxBerry::Log` korrekt eingebunden: der Loglevel-Wähler in der Pluginverwaltung wirkt
  tatsächlich.

## Dokumentation

- Wiki: https://wiki.loxberry.de/plugins/docker-ng/start
- LoxBerry-Forum: https://www.loxforum.com/forum/projektforen/loxberry/plugins/489589-docker-ng-nachfolgeplugin-zu-docker
- Aktuelle Releases: https://github.com/blacksun80/LoxBerry-Plugin-Docker-NG/releases

## Credits

Dieses Plugin ist ein abgeleitetes Werk des
[Docker-Plugins von Michael Miklis](https://github.com/michaelmiklis/loxberry-plugin-docker)
und steht deshalb weiterhin unter der Apache-Lizenz 2.0 - siehe [LICENSE.md](LICENSE.md) und
[NOTICE](NOTICE) für die im Einzelnen vorgenommenen Änderungen. Danke für die Vorarbeit, auf
der hier aufgebaut wird!

Weder mit Docker Inc. noch mit Portainer.io verbunden.
