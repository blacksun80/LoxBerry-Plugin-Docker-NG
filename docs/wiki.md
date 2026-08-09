====== Docker NG ======

===== Funktion des Plugins =====

Richtet **Docker** und **Portainer** auf dem LoxBerry ein und meldet den Zustand aller
Container an Loxone. Eigenständiges Plugin, kein Update des älteren
[[https://github.com/michaelmiklis/loxberry-plugin-docker|Docker-Plugins von M. Miklis]] -
beide lassen sich nebeneinander installieren.

Funktionen:
  * Docker-Engine und Portainer werden bei der Installation automatisch eingerichtet
  * Administratorkennwort für Portainer wird automatisch erzeugt und in der Oberfläche
    angezeigt - kein manuelles Ablesen eines Setup-Tokens aus dem Containerprotokoll mehr
  * Statuskacheln (Docker vorhanden, Container gesamt/laufen/gestoppt, Portainer-Status)
  * Containertabelle mit Name, Abbild und Zustand
  * "Portainer neu einrichten" für einen kontrollierten Neuaufbau
  * Containerzustand alle fünf Minuten per MQTT gemeldet, mit automatischer Registrierung
    beim MQTT-Gateway - kein manuelles Eintippen des Themas nötig
  * Konfiguration (inkl. Administratorkennwort) übersteht Plugin-Updates
  * Läuft sowohl auf LoxBerry 3 als auch LoxBerry 4

===== Download =====

  * [[https://github.com/blacksun80/LoxBerry-Plugin-Docker-NG/releases/latest|Neueste Version auf GitHub]]

Die ZIP-Adresse des Releases lässt sich direkt in der LoxBerry-Pluginverwaltung eingeben.

===== Installation =====

  - Pluginverwaltung öffnen
  - "Plugin installieren" wählen
  - Adresse der ZIP-Datei aus dem GitHub-Release eintragen
  - Installation abwarten - Docker und Portainer werden dabei automatisch eingerichtet

**Voraussetzungen:**
  * LoxBerry 3.0.0 oder neuer
  * Raspberry Pi oder x86-System (32-Bit UND 64-Bit werden unterstützt)
  * Internetzugang zum Herunterladen von Docker-Engine und Portainer-Abbild

===== Konfigurationsoptionen =====

==== Plugin-Seite öffnen ====

Pluginverwaltung -> Docker NG. Die Seite gliedert sich in mehrere Karten:

^ Karte | Zweck |
| Statuskacheln | Docker vorhanden, Container gesamt/laufen/gestoppt, Portainer-Status |
| Portainer | Öffnet Portainer in einem eigenen Fenster, zeigt das automatisch erzeugte \\ Administratorkennwort, Schaltfläche "Portainer neu einrichten" |
| Container | Tabelle aller Container mit Name, Abbild und Zustand |
| MQTT | Hinweis auf die automatische Registrierung des Themas beim MQTT-Gateway |

==== Administratorkennwort ====

Wird bei der Ersteinrichtung automatisch erzeugt. Unter "Kennwort anzeigen" abrufbar,
Benutzername ist immer **admin**. Bleibt über Plugin-Updates hinweg gültig.

===== Einbindung in Loxone Config =====

Der Zustand wird alle fünf Minuten per MQTT veröffentlicht (retained). Das Thema
**docker/#** wird automatisch beim LoxBerry-MQTT-Gateway registriert - unter
**System -> MQTT-Gateway** lässt sich von dort aus die Weiterleitung an einen Miniserver
einrichten, ohne das Thema von Hand eintippen zu müssen.

^ Thema | Bedeutung |
| docker/ok | 1 = Docker ist vorhanden und ansprechbar |
| docker/gesamt | Anzahl Container |
| docker/laeuft | davon in Betrieb |
| docker/gestoppt | davon gestoppt |
| docker/portainer | 1 = Portainer läuft |
| docker/container/<name> | 1 = dieser Container läuft (ein Thema je Container) |

===== Fragen stellen und Fehler melden =====

  * GitHub Issues: [[https://github.com/blacksun80/LoxBerry-Plugin-Docker-NG/issues]]
  * LoxBerry-Forum: [[https://www.loxforum.com/forum/projektforen/loxberry/plugins/489589-docker-ng-nachfolgeplugin-zu-docker]]
