# CLAUDE.md

## Arbeitsweise (wichtig)

- **Direkt auf `main` arbeiten.** Keine Feature-Branches, keine Pull Requests.
- Änderungen **ohne Rückfrage** umsetzen, committen und sofort pushen:
  `git push -u origin main`
- Commit-Nachrichten kurz und auf Deutsch, beschreiben *was* und *warum*.
- Kommunikation mit dem Nutzer auf Deutsch.

## Projekt

**Sammler** ist ein AutoHotkey-v2-Skript (Windows) für FiveM/GTA-RP. Es liest per
Texterkennung den Sammel-Fortschritt aus dem HUD (`Sammeln... (24 / 168) 14.76%`),
rechnet die Restzeit aus, zeigt optional Essen/Trinken an und kann nach dem
Fertigwerden eine Tasten-/Klick-Kette ins Spiel schicken
(Inventar öffnen → Rechtsklick auf Wegwerf-Punkt → Inventar zu → neu sammeln).
Dazu gibt es einen Tabak-Rechner (Blätter → Tabak → Geld, Rückwärtsrechnung auf eine Wunschsumme).

## Dateien

| Datei | Inhalt |
|---|---|
| `Sammler.ahk` | Das ganze Skript in einer Datei (inkl. PowerShell-OCR-Code in `PS_Quelltext()`). |
| `Sammler.ini` | Gemerkte Einstellungen (Lesefelder, Zeiten, Tasten, Tabak-Werte). |
| `Sammler.log` | Mitschrift des Ablaufs nach dem Sammeln (wird vom Skript geschrieben; ab 300 KB nach `Sammler.alt.log` verschoben). **Nicht im Repo** (`.gitignore`) – der Nutzer lädt sie bei Bedarf hoch. |

### Kodierung – nicht verändern!

- `Sammler.ahk`: **UTF-8 mit BOM, CRLF-Zeilenenden**.
- `Sammler.ini`: **UTF-16 LE mit BOM** (so schreibt `IniWrite` sie). Zum Lesen z. B.
  `iconv -f UTF-16LE -t UTF-8 Sammler.ini`; beim Schreiben wieder zurück nach UTF-16 LE.
- `Sammler.log`: UTF-8 mit BOM.
- `.gitattributes` setzt `-text`, damit Git nichts umwandelt. Beim Bearbeiten mit
  Edit-Tools darauf achten, dass CRLF und BOM erhalten bleiben.

## Aufbau von `Sammler.ahk`

- **Kopf (globale Konstanten):** Takt/Rate (`TAKT`, `PRO_TAKT`), Lese-Intervalle
  (`SCAN_MS`, `VORRAT_MS`), Schwellen (`STILL_S`, `WEG_MS`, `NAH_DRAN`, `KNAPP`),
  Tabak-Werte, Farben (dunkle Oberfläche), Ablauf-Kette (`TASTE_*`, `WURF_*`,
  `STOP_*`, `ZU_*`, `SAM_*`).
- **`class Lesefeld`:** Bildschirmausschnitt mit Fensterbezug (`FX/FY`) und Spiegel
  (`SpX/SpY`). Instanzen: `Zaehler`, `Vorrat`. INI-Abschnitt = `Name`.
- **GUI:** Hauptfenster `Ui`, Einstellungen `Ein` (Zahnrad). Hotkeys nur `F1`
  (einmal lesen) und `F2` (Dauerlesung) – bewusst keine weiteren Tastenkürzel,
  damit das Spiel keine Tasten verliert.
- **Einstellungen:** `LadeEinstellungen`, `WerteLaden`/`WerteSpeichern`,
  `FeldLaden`/`FeldSpeichern`, `WerteUebernehmen`.
- **OCR:** `StartOcr` schreibt `PS_Quelltext()` nach `%TEMP%\sammler_ocr.ps1` und
  startet einen PowerShell-Dienst; Kommunikation über `sammler_cmd.txt` /
  `sammler_ocr.txt` im Temp-Ordner (`Auftrag`, `WarteAufAntwort`, `FeldLesen`).
  Erst nach `READY` (`OcrBereit`) werden Aufträge angenommen; stirbt der Dienst,
  startet `OcrNeuStarten` ihn neu (höchstens alle 15 s).
- **Lesen/Auswerten:** `TimerTick`, `VorratTick`, `Lesen`, `Auswerten`,
  `VorratLesen`, `Fortschreiben`, `IstRate`, `Anzeigen`, `Dauer`.
  `Bestaetigt` lässt neue Gesamtwerte und Rücksprünge erst nach einer zweiten,
  passenden Lesung durch (gegen Verleser wie „40 / 40“).
- **Ablauf nach Fertig:** `Melde` → `AblaufStarten` → `AblaufSchritt`
  (`TasteJetzt`, `WurfJetzt`, `FensterNachVorn`); Einträge ins Log über `Protokoll`.
- **Fehler:** `Guard(fn)` und `HandleError` fangen ab und melden über `Note`.

## Konventionen

- Namen und Kommentare auf Deutsch, Umlaute in Kommentaren als ae/oe/ue/ss.
- AutoHotkey ist bei Namen nicht groß/klein-empfindlich – Variablen ausgeschrieben
  benennen, keine Namen, die sich nur in der Schreibung unterscheiden.
- Neue Einstellungen: globale Variable im Kopf + `WerteLaden` + `WerteSpeichern`
  (+ ggf. Feld in `WerteInsFenster`/`WerteUebernehmen`).
- Alles bleibt in einer Datei; keine zusätzlichen Hilfsdateien im Projektordner.

## Testen

Das Skript läuft nur unter Windows mit AutoHotkey v2 (hier in der Linux-Umgebung
nicht ausführbar). Änderungen sorgfältig lesen und auf Syntax prüfen. Bei Fehlern im
Ablauf den Nutzer bitten, seine `Sammler.log` hochzuladen – sie liegt nicht im Repo.
