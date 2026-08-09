<!--
Bereits veröffentlicht im LoxForum (Bereich Projektforen > LoxBerry > Plugins):
https://www.loxforum.com/forum/projektforen/loxberry/plugins/489589-docker-ng-nachfolgeplugin-zu-docker
Diese Datei ist die Ablage des Textes im Repo (siehe Wiki-Doku-Vorlage.md), keine
weitere Handlung nötig - nur bei größeren inhaltlichen Nachträgen synchron halten.
-->

# Docker NG - Nachfolgeplugin zu Docker

Hallo zusammen,

ich möchte euch mein neues Plugin **Docker NG** vorstellen.

Der ursprüngliche Entwickler des Docker-Plugins betreibt selbst keinen LoxBerry mehr und
pflegt es nicht weiter. Docker NG ist deshalb ein eigenständiger Neustart (mit KI-Unterstützung
entwickelt), zunächst für den eigenen Gebrauch auf LoxBerry 4 - lässt sich aber neben dem
ursprünglichen Plugin installieren, falls jemand lieber dabei bleiben möchte.

Neu gegenüber dem alten Docker-Plugin: das Administratorkennwort für Portainer wird bei der
Einrichtung automatisch erzeugt und in der Oberfläche angezeigt (kein Ablesen eines
Setup-Tokens aus dem Containerprotokoll mehr), der Containerzustand wird alle fünf Minuten per
MQTT gemeldet und dabei automatisch beim MQTT-Gateway registriert, und die Konfiguration
übersteht jetzt Plugin-Updates.

**Download & Doku:**
- GitHub: https://github.com/blacksun80/LoxBerry-Plugin-Docker-NG
- Wiki: https://wiki.loxberry.de/plugins/docker-ng/start
- Aktuelle Releases: https://github.com/blacksun80/LoxBerry-Plugin-Docker-NG/releases

Über Rückmeldungen und Tests freue ich mich!
