#Requires AutoHotkey v2.0
#SingleInstance Force
CoordMode("Mouse", "Screen")
CoordMode("Pixel", "Screen")

; Sammler - liest den Sammel-Fortschritt aus dem HUD
; ("Sammeln... (24 / 168)  14.76%") und rechnet aus, wie lange der Rest dauert.
; Dazu auf Wunsch den Essen- und Trinken-Stand.
;
;   F1 = einmal lesen            F2 = Dauerlesung an/aus
;
; Alles zum Einrichten steht hinter dem Zahnrad - dafuer gibt es keine
; Tastenkuerzel, damit das Skript dem Spiel nicht die Tasten wegnimmt.
;
; Alles steckt in dieser einen Datei. Der Texterkenner braucht PowerShell;
; sein Code steht unten in PS_Quelltext() und wird beim Start in den
; Temp-Ordner geschrieben - im Projektordner bleibt nur diese Datei
; (plus Sammler.ini mit den gemerkten Einstellungen).
;
; Verdeckte Fenster: Der Fenstermanager kann einen Ausschnitt des
; Spielfensters in ein eigenes kleines Fenster zeichnen (Spiegel). Der
; funktioniert auch, wenn das Spiel hinter einem anderen Fenster liegt.
;
; Namen sind in AutoHotkey nicht gross/klein-empfindlich: QX und qx waeren
; dieselbe Variable. Deshalb sind die Namen hier ausgeschrieben.

global SCRIPT_DIR := A_ScriptDir
global INI     := SCRIPT_DIR . "\Sammler.ini"
global OCR_PS  := A_Temp . "\sammler_ocr.ps1"
global OCR_OUT := A_Temp . "\sammler_ocr.txt"
global OCR_CMD := A_Temp . "\sammler_cmd.txt"
global LOGDATEI     := SCRIPT_DIR . "\Sammler.log"   ; Mitschrift des Ablaufs nach dem Sammeln
global LOGALT       := SCRIPT_DIR . "\Sammler.alt.log"   ; die vorige Mitschrift, wenn die aktuelle voll war

global TAKT := 10.0      ; Sekunden pro Sammel-Zyklus
global PRO_TAKT := 2     ; Stueck pro Zyklus  ->  0,2 Stueck/s
global SOLL_RATE := PRO_TAKT / TAKT

; Der Zaehler laeuft schnell, damit die Anzeige nicht hinterherhinkt: eine
; Lesung dauert rund 0,2 s, 700 ms Takt heisst hoechstens etwa 1 s Rueckstand.
global SCAN_MS := 700    ; Abstand zwischen zwei Zaehler-Lesungen
global VORRAT_MS := 8000 ; Essen/Trinken aendern sich langsam - eigener Takt
global STILL_S := 25     ; ohne Fortschritt gilt das Sammeln als unterbrochen
global WEG_MS := 5000    ; so lange darf der Balken fehlen, bevor er als weg gilt
global NAH_DRAN := 4     ; Restmenge, ab der ein verschwundener Balken "fertig" heisst
global KNAPP := 25       ; ab hier gelten Essen/Trinken als knapp (Prozent)
global VORRAT_SPRUNG := 30   ; groessere Spruenge muss eine zweite Lesung bestaetigen

; Tabak: aus Blaettern wird verarbeitet Tabak, und der bringt Geld. Die drei
; Zahlen sind einstellbar - Server aendern Rezepte und Preise oefter.
global BLATT_PRO_TABAK := 20     ; Blaetter fuer ein Tabak
global MIN_PRO_TABAK := 1.0      ; Minuten Bearbeitung je Tabak
global PREIS_PRO_TABAK := 1256   ; Dollar je Tabak
global WUNSCH := 0               ; Zielsumme fuer die Rueckwaertsrechnung (0 = aus)

global SPIEGEL_RAND := 4 ; Rand zum Anfassen; das Spiegelbild deckt den Rest ab

; Dunkle Oberflaeche. Windows faerbt Knoepfe, Haken und Titelleiste selbst
; ein, sobald das Fenster auf den dunklen Modus gestellt ist - die Farben
; hier sind fuer alles, was AutoHotkey selbst malt.
global FARB_GRUND := "1B1B20"    ; Fensterhintergrund
global FARB_FELD  := "2B2B33"    ; Eingabefelder
global FARB_TEXT  := "E8E8EC"    ; normale Schrift
global FARB_GRAU  := "9AA0A8"    ; Nebensaetze
global FARB_LINIE := "3A3A44"    ; Trennlinien
global FARB_GUT   := "4CD07D"    ; fertig, genug Vorrat
global FARB_WARN  := "FF6B6B"    ; Essen/Trinken knapp

; Nach dem Sammeln: einmal eine frei waehlbare Taste ins Spiel schicken
; (z. B. das Inventar oeffnen). Ausgeloest wird das nur von der Fertig-Meldung,
; und die kommt pro Auftrag genau einmal - solange Fertig steht, kommt nichts mehr.
global ZIEL := 0             ; Stueck, ab denen der Auftrag als fertig gilt (0 = ganzer Auftrag)
global TASTE_AN := false     ; Taste ueberhaupt senden?
global TASTE := "i"          ; Taste in Hotkey-Schreibweise, z. B. "i", "F5", "^b"
global TASTE_MS := 800       ; Wartezeit zwischen Meldung und Tastendruck
global TASTE_AKT := true     ; Spielfenster vorher nach vorn holen

; Danach ein Gegenstand aus dem Inventar: ein Rechtsklick auf einen gemerkten
; Punkt. Gemerkt wird beides - der Bildschirmpunkt und seine Lage im
; Spielfenster. Verschiebt sich das Fenster, zaehlt die Lage im Fenster.
global WURF_AN := false      ; nach der Taste rechtsklicken?
global WURF_MS := 700        ; Wartezeit zwischen Taste und Klick
global WURF_X := -1          ; Bildschirmpunkt (-1 = nie gesetzt)
global WURF_Y := -1
global WURF_REL := false     ; gilt die Lage im Fenster?
global WURF_FX := 0          ; Lage des Punktes im Spielfenster
global WURF_FY := 0

; Zum Schluss zwei weitere Tasten: Inventar wieder zu, dann neu sammeln.
; Jede Stufe hat ihre eigene Wartezeit - gezaehlt ab dem Schritt davor.
; Bei einem eigenen Ziel laeuft das Sammeln noch, wenn der Sammler schon
; fertig meldet - dann muss es erst abgebrochen werden. Beim vollen Auftrag
; hat das Spiel von selbst aufgehoert, ein Druck wuerde neu starten.
global STOP_AN := false      ; Sammeln abbrechen?
global STOP_TASTE := "e"
global STOP_MS := 400

global ZU_AN := false        ; Inventar schliessen?
global ZU_TASTE := "Escape"
global ZU_MS := 600
global SAM_AN := false       ; Sammeln wieder starten?
global SAM_TASTE := "e"
global SAM_MS := 600

; ---------------------------------------------------------------- Lesefelder

; Ein Lesefeld ist ein Ausschnitt, der regelmaessig gelesen wird: wo er auf
; dem Bildschirm liegt, in welchem Fenster er steht und wo sein Spiegel haengt.
class Lesefeld {
    __New(name, titel) {
        this.Name := name          ; Abschnitt in der INI
        this.Titel := titel        ; Klartext fuer Meldungen
        this.X := 0, this.Y := 0, this.W := 0, this.H := 0
        this.Exe := "", this.Fenster := ""
        this.FX := 0, this.FY := 0         ; Lage innerhalb des Fensters
        this.SpX := 0, this.SpY := 0       ; Lage des Spiegels
        this.Gui := 0, this.Tn := 0, this.Quelle := 0
    }
    Kalibriert => this.W > 0 && this.H > 0
}

global Zaehler := Lesefeld("Zaehler", "Zählerstand")
global Vorrat  := Lesefeld("Vorrat", "Essen/Trinken")

; ---------------------------------------------------------------- Zustand

global OcrPid := 0
global AuftragNr := 0        ; jede Lesung bekommt eine Nummer
global Busy := false
global Aktuell := -1, Gesamt := -1
global KandidatA := -1, KandidatG := -1   ; verdaechtige Lesung, die noch eine Bestaetigung braucht
global OcrBereit := false         ; hat der Dienst READY gemeldet?
global OcrNeustartZeit := 0       ; wann zuletzt neu gestartet wurde (Bremse)
global KnappGemeldet := false     ; "knapp" schon in der Statuszeile gemeldet?
global StartZeit := 0, StartWert := -1
global LetzteAenderung := 0, LetzterWert := -1
global Verlauf := []              ; [Zeitstempel, Wert] fuer die gemessene Rate
global Fertig := false
global LetzteGuteLesung := 0      ; wann der Balken zuletzt lesbar war
global WegProtokolliert := false  ; "kein Abschluss" fuer diesen Aussetzer schon ins Log geschrieben?
global Essen := -1, Trinken := -1
global VorratZeit := 0            ; wann Essen/Trinken zuletzt gelesen wurden
global VorratKandidatE := -1, VorratKandidatT := -1
global Markiert := false
global Balken := []
global ZiehEingabe := ""
global TABAK_SICHTBAR := true   ; der Kasten wird sichtbar aufgebaut und danach zugeklappt
global TABAK_HOEHE := 0         ; wie viel Fensterhoehe der Kasten braucht
global TABAK_BLATT := 0         ; Blaetter, mit denen gerechnet wird
global TABAK_ENDE := 0          ; Tickzeit, zu der die Bearbeitung fertig ist (0 = laeuft nicht)
global Schritte := []        ; die Kette nach dem Fertigwerden
global SchrittNr := 0
global SchrittTest := false
global SchrittFaellig := 0   ; Tickzeit, zu der der naechste Schritt dran sein sollte
global SCHRITT_VERSPAETUNG := 5000   ; kommt ein Schritt spaeter, ist die Lage im Spiel nicht mehr sicher

OnError(HandleError)
DunkelAnmelden()

; ---------------------------------------------------------------- Hauptfenster
;
; Oben nur das, was beim Sammeln zaehlt. Alles zum Einstellen liegt hinter dem
; Zahnrad oben rechts, damit diese Seite ruhig bleibt.

global Ui := Gui("+AlwaysOnTop -MaximizeBox", "Sammler")
Ui.BackColor := FARB_GRUND
Ui.SetFont("s10 c" . FARB_TEXT, "Segoe UI")
Ui.MarginX := 16, Ui.MarginY := 14

Ui.SetFont("s16 Bold")
global TxtStand := Ui.Add("Text", "w330", "-  /  -")

Ui.SetFont("s14 Bold")
global TxtFertig := Ui.Add("Text", "xm y+10 w380 Center c" . FARB_GUT . " Hidden", "Fertig gesammelt")
Ui.SetFont("s10 Norm")

Ui.Add("Text", "xm y+8 w380 h1 Background" . FARB_LINIE)

Ui.SetFont("s10 Bold")
global TxtRest := Ui.Add("Text", "xm y+10 w380", "Rest: -")
Ui.SetFont("s10 Norm")
global TxtEtaSoll := Ui.Add("Text", "xm y+6 w380", "Restzeit (2 Stk / 10 s): -")
global TxtEtaIst  := Ui.Add("Text", "xm y+4 w380", "Restzeit (gemessen): -")
Ui.SetFont("s9 c" . FARB_GRAU)
global TxtRate := Ui.Add("Text", "xm y+6 w380", "Rate: -")
global TxtLauf := Ui.Add("Text", "xm y+3 w380", "Laufzeit: -")
Ui.SetFont("s10 Norm c" . FARB_TEXT)

Ui.Add("Text", "xm y+10 w380 h1 Background" . FARB_LINIE)

Ui.SetFont("s11 Bold")
global TxtVorrat := Ui.Add("Text", "xm y+10 w380 c" . FARB_GRAU, "Essen: -     Trinken: -")
Ui.SetFont("s10 Norm")

Ui.Add("Text", "xm y+10 w380 h1 Background" . FARB_LINIE)

global CbLoop := Ui.Add("CheckBox", "xm y+10 w180", "Dauerlesung (F2)")
CbLoop.OnEvent("Click", (*) => Guard(() => ToggleLoop(CbLoop.Value)))
Ui.Add("Button", "x+10 yp-4 w190", "Jetzt lesen (F1)").OnEvent("Click", (*) => Guard(() => Lesen(true)))

Ui.SetFont("s9 c" . FARB_GRAU)
global TxtHint := Ui.Add("Text", "xm y+12 w380", "Starte Texterkennung ...")
Ui.SetFont("s10 Norm c" . FARB_TEXT)

; Der Tabak-Rechner als zuschaltbarer Kasten. Er steht bewusst ganz unten:
; beim Ausblenden faellt nur das Fensterende weg, nichts darueber rutscht.
global CbTabak := Ui.Add("CheckBox", "xm y+12 w380", "Tabak-Rechner anzeigen")
CbTabak.OnEvent("Click", (*) => Guard(TabakHakenGeklickt))

; Erst die Flaeche, dann alles darauf: was spaeter angelegt wird, liegt
; obenauf. Mit BackgroundTrans scheint die Kastenfarbe durch die Schrift.
global TabakKasten := Ui.Add("Text", "xm y+8 w380 h252 Background" . FARB_FELD)

Ui.SetFont("s13 Bold c" . FARB_GUT)
global TxtKastenGeld := Ui.Add("Text", "xm+14 yp+12 w352 Background" . FARB_FELD, "-")
Ui.SetFont("s10 Norm c" . FARB_TEXT)
global TxtKastenMenge := Ui.Add("Text", "xm+14 y+8 w352 Background" . FARB_FELD, "-")
Ui.SetFont("s9 c" . FARB_GRAU)
global TxtKastenInfo := Ui.Add("Text", "xm+14 y+6 w352 Background" . FARB_FELD, "")
Ui.SetFont("s10 Norm c" . FARB_TEXT)

; Vorne stehen nur die zwei Zahlen, die sich staendig aendern. Das Rezept -
; Blaetter je Tabak und Bearbeitungsdauer - liegt im Zahnrad, das stellt man
; einmal ein und fasst es nicht wieder an.
Ui.SetFont("s9 c" . FARB_GRAU)
Ui.Add("Text", "xm+14 y+12 w54 BackgroundTrans", "Blätter")
Ui.SetFont("s10 Norm c" . FARB_TEXT)
global EdKastenBlatt := Ui.Add("Edit", "x+4 yp-4 w86 Number Center c" . FARB_TEXT . " Background" . FARB_GRUND, 0)
Ui.SetFont("s9 c" . FARB_GRAU)
Ui.Add("Text", "x+16 yp+4 w56 BackgroundTrans", "$/Tabak")
Ui.SetFont("s10 Norm c" . FARB_TEXT)
global EdKastenPreis := Ui.Add("Edit", "x+4 yp-4 w86 Number Center c" . FARB_TEXT . " Background" . FARB_GRUND, PREIS_PRO_TABAK)

for feld in [EdKastenBlatt, EdKastenPreis]
    feld.OnEvent("Change", (*) => Guard(KastenFeldGeaendert))

global TxtKastenZeit := Ui.Add("Text", "xm+14 y+12 w180 Background" . FARB_FELD, "-")
global BtnKastenStart := Ui.Add("Button", "x+8 yp-5 w80 h26", "Start")
BtnKastenStart.OnEvent("Click", (*) => Guard(BearbeitungUmschalten))
Ui.SetFont("s10 Bold c" . FARB_GUT)
global TxtKastenLauf := Ui.Add("Text", "x+10 yp+5 w76 Background" . FARB_FELD, "")
Ui.SetFont("s10 Norm c" . FARB_TEXT)

; Die Wunschsumme: wie viel Blaetter fuer diesen Betrag noetig sind, damit
; man beim Sammeln sieht, wie weit es noch ist.
global TabakStrich := Ui.Add("Text", "xm+14 y+12 w352 h1 Background" . FARB_LINIE)
Ui.SetFont("s9 c" . FARB_GRAU)
Ui.Add("Text", "xm+14 y+10 w62 BackgroundTrans", "Wunsch $")
Ui.SetFont("s10 Norm c" . FARB_TEXT)
global EdKastenWunsch := Ui.Add("Edit", "x+4 yp-4 w86 Number Center c" . FARB_TEXT . " Background" . FARB_GRUND, WUNSCH)
EdKastenWunsch.OnEvent("Change", (*) => Guard(() => WunschEingabe(EdKastenWunsch.Value)))
global TxtKastenWunsch := Ui.Add("Text", "xm+14 y+10 w352 Background" . FARB_FELD, "-")
Ui.SetFont("s9 c" . FARB_GRAU)
global TxtKastenWunschZeit := Ui.Add("Text", "xm+14 y+6 w352 Background" . FARB_FELD, "")
Ui.SetFont("s10 Norm c" . FARB_TEXT)

; Das Zahnrad sitzt fest oben rechts. Es wird als Letztes angelegt: es steht
; auf festen Koordinaten, und als Zwischenschritt haette es die Zeile danach
; an seinen unteren Rand gehaengt - die Fertig-Meldung lag dann auf der
; Prozentzeile.
Ui.SetFont("s13", "Segoe UI Symbol")
global BtnZahnrad := Ui.Add("Button", "x368 y14 w32 h30", Chr(0x2699))
BtnZahnrad.OnEvent("Click", (*) => Guard(EinstellungenZeigen))
Ui.SetFont("s10 Norm c" . FARB_TEXT, "Segoe UI")

Ui.OnEvent("Close", (*) => Beenden())
Ui.OnEvent("Escape", (*) => 1)

; ---------------------------------------------------------------- Einstellfenster
;
; Wird gleich mit aufgebaut, aber erst auf Klick gezeigt: so sind alle Felder
; vorhanden und der Rest des Skripts muss nirgends pruefen, ob es sie gibt.

global Ein := Gui("+AlwaysOnTop -MaximizeBox +Owner" . Ui.Hwnd, "Sammler - Einstellungen")
Ein.BackColor := FARB_GRUND
Ein.SetFont("s10 c" . FARB_TEXT, "Segoe UI")
Ein.MarginX := 16, Ein.MarginY := 14

; Drei Reiter statt einer langen Liste: einrichten, was nach dem Sammeln
; passiert, und die Rechenwerte. Die Hoehe ist fest, sonst springt das
; Fenster bei jedem Reiterwechsel.
global Reiter := Ein.Add("Tab3", "xm ym w400 h538", ["Bereiche", "Ablauf", "Werte"])

; ------------------------------------------------ Reiter 1: Bereiche
Reiter.UseTab(1)

Ein.SetFont("s9 c" . FARB_GRAU)
Ein.Add("Text", "xm+14 y+10 w372", "Hier wird festgelegt, wo der Sammler hinschaut.")
Ein.SetFont("s10 Norm c" . FARB_TEXT)

Ein.Add("Button", "xm+14 y+10 w181", "Zähler aufziehen").OnEvent("Click", (*) => Guard(() => Markieren(Zaehler)))
Ein.Add("Button", "x+10 yp w181", "Essen/Trinken aufziehen").OnEvent("Click", (*) => Guard(() => Markieren(Vorrat)))
Ein.Add("Button", "xm+14 y+8 w181", "Rahmen zeigen").OnEvent("Click", (*) => Guard(RahmenBlinken))
Ein.Add("Button", "x+10 yp w181", "Zählung zurücksetzen").OnEvent("Click", (*) => Guard(() => Reset()))

global CbSpiegel := Ein.Add("CheckBox", "xm+14 y+12 w372", "Spiegel benutzen (liest auch, wenn das Spiel verdeckt ist)")
CbSpiegel.OnEvent("Click", (*) => Guard(SpiegelUmschalten))

Ein.Add("Text", "xm+14 y+12 w372 h1 Background" . FARB_LINIE)

Ein.SetFont("s9 c" . FARB_GRAU)
global TxtQuelle  := Ein.Add("Text", "xm+14 y+10 w372", "")
global TxtBereich := Ein.Add("Text", "xm+14 y+6 w372 r2", "")
global TxtRoh     := Ein.Add("Text", "xm+14 y+6 w372 r2", "")
Ein.SetFont("s10 Norm c" . FARB_TEXT)

; ------------------------------------------------ Reiter 2: Ablauf
Reiter.UseTab(2)

Ein.Add("Text", "xm+14 y+10 w292", "Fertig ab Stück (0 = ganzer Auftrag)")
global EdZiel := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, ZIEL)

Ein.SetFont("s9 c" . FARB_GRAU)
Ein.Add("Text", "xm+14 y+10 w372 r2", "Was nach dem Fertigwerden passiert - von oben nach unten. Jede Wartezeit zählt ab dem Schritt davor.")
Ein.SetFont("s10 Norm c" . FARB_TEXT)

global CbStop := Ein.Add("CheckBox", "xm+14 y+8 w372", "1. Sammeln abbrechen (nur bei eigenem Ziel)")
Ein.Add("Text", "xm+14 y+6 w90", "      Taste")
global HkStop := Ein.Add("Hotkey", "x+4 yp-3 w100")
Ein.Add("Text", "x+12 yp+3 w90", "Wartezeit (ms)")
global EdStopMs := Ein.Add("Edit", "x+6 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, STOP_MS)

global CbTaste := Ein.Add("CheckBox", "xm+14 y+10 w372", "2. Inventar öffnen")
Ein.Add("Text", "xm+14 y+6 w90", "      Taste")
global HkTaste := Ein.Add("Hotkey", "x+4 yp-3 w100")
Ein.Add("Text", "x+12 yp+3 w90", "Wartezeit (ms)")
global EdTasteMs := Ein.Add("Edit", "x+6 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, TASTE_MS)

global CbWurf := Ein.Add("CheckBox", "xm+14 y+10 w372", "3. Gegenstand wegwerfen (Rechtsklick)")
Ein.Add("Text", "xm+14 y+6 w194", "      Punkt im Inventar")
Ein.Add("Text", "x+12 yp w90", "Wartezeit (ms)")
global EdWurfMs := Ein.Add("Edit", "x+6 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, WURF_MS)
Ein.Add("Button", "xm+14 y+6 w181", "Wegwerf-Punkt setzen").OnEvent("Click", (*) => Guard(WurfPunktSetzen))
Ein.Add("Button", "x+10 yp w181", "Punkt zeigen").OnEvent("Click", (*) => Guard(WurfPunktZeigen))
Ein.SetFont("s9 c" . FARB_GRAU)
global TxtWurf := Ein.Add("Text", "xm+14 y+6 w372 r2", "")
Ein.SetFont("s10 Norm c" . FARB_TEXT)

global CbZu := Ein.Add("CheckBox", "xm+14 y+10 w372", "4. Inventar schließen")
Ein.Add("Text", "xm+14 y+6 w90", "      Taste")
global HkZu := Ein.Add("Hotkey", "x+4 yp-3 w100")
Ein.Add("Text", "x+12 yp+3 w90", "Wartezeit (ms)")
global EdZuMs := Ein.Add("Edit", "x+6 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, ZU_MS)

global CbSam := Ein.Add("CheckBox", "xm+14 y+10 w372", "5. Sammeln starten")
Ein.Add("Text", "xm+14 y+6 w90", "      Taste")
global HkSam := Ein.Add("Hotkey", "x+4 yp-3 w100")
Ein.Add("Text", "x+12 yp+3 w90", "Wartezeit (ms)")
global EdSamMs := Ein.Add("Edit", "x+6 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, SAM_MS)

Ein.Add("Text", "xm+14 y+12 w372 h1 Background" . FARB_LINIE)

global CbTasteAkt := Ein.Add("CheckBox", "xm+14 y+10 w372", "Spielfenster vorher nach vorn holen")
Ein.Add("Button", "xm+14 y+8 w372", "Ablauf jetzt testen").OnEvent("Click", (*) => Guard(TasteTesten))

; ------------------------------------------------ Reiter 3: Werte
Reiter.UseTab(3)

Ein.SetFont("s9 c" . FARB_GRAU)
Ein.Add("Text", "xm+14 y+10 w372 r2", "Grundlage der Restzeit und der Lesetakte. Im Zweifel so lassen.")
Ein.SetFont("s10 Norm c" . FARB_TEXT)

Ein.Add("Text", "xm+14 y+10 w292", "Stück pro Sammel-Zyklus")
global EdProTakt := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, PRO_TAKT)
Ein.Add("Text", "xm+14 y+8 w292", "Sekunden pro Zyklus")
global EdTakt := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, Round(TAKT))
Ein.Add("Text", "xm+14 y+8 w292", "Zähler lesen alle (ms)")
global EdScan := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, SCAN_MS)
Ein.Add("Text", "xm+14 y+8 w292", "Essen/Trinken lesen alle (ms)")
global EdVorratMs := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, VORRAT_MS)
Ein.Add("Text", "xm+14 y+8 w292", "Essen/Trinken knapp ab (%)")
global EdKnapp := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, KNAPP)

Ein.Add("Text", "xm+14 y+12 w372 h1 Background" . FARB_LINIE)

Ein.SetFont("s10 Bold c" . FARB_TEXT)
Ein.Add("Text", "xm+14 y+10 w372", "Tabak-Rezept")
Ein.SetFont("s10 Norm c" . FARB_TEXT)
Ein.Add("Text", "xm+14 y+8 w292", "Blätter je Tabak")
global EdBlattProTabak := Ein.Add("Edit", "x+10 yp-3 w56 Number Center c" . FARB_TEXT . " Background" . FARB_FELD, BLATT_PRO_TABAK)
Ein.Add("Text", "xm+14 y+8 w292", "Minuten Bearbeitung je Tabak")
global EdMinProTabak := Ein.Add("Edit", "x+10 yp-3 w56 Center c" . FARB_TEXT . " Background" . FARB_FELD, MIN_PRO_TABAK)

; ------------------------------------------------ unter den Reitern
;
; Uebernehmen und Schliessen stehen ausserhalb der Reiter: sie gelten fuer
; alle Felder, egal welcher Reiter gerade offen ist.
Reiter.UseTab()

Ein.Add("Button", "xm y562 w195 Default", "Übernehmen").OnEvent("Click", (*) => Guard(WerteUebernehmen))
Ein.Add("Button", "x+10 yp w195", "Schließen").OnEvent("Click", (*) => Guard(EinstellungenVerstecken))

Ein.OnEvent("Close", (*) => (EinstellungenVerstecken(), 1))
Ein.OnEvent("Escape", (*) => (EinstellungenVerstecken(), 1))

LadeEinstellungen()
DunkelFenster(Ui)
DunkelFenster(Ein)
Ui.Show()

; Um wie viel das Fenster wachsen muss, wenn der Kasten dazukommt: der
; Abstand zwischen der Unterkante des Hakens und der Unterkante des Kastens.
; Erst nach dem Anzeigen messen - vorher stehen die Masse nicht fest.
ControlGetPos(, &hakenY, , &hakenH, CbTabak)
ControlGetPos(, &kastenY, , &kastenH, TabakKasten)
TABAK_HOEHE := (kastenY + kastenH) - (hakenY + hakenH)
TabakKastenUmschalten(CbTabak.Value)
StartOcr()
SetTimer(SpiegelPflegen, 1500)

; Maustaste auf einem Spiegel: Fenster verschieben, Ende merken.
OnMessage(0x201, SpiegelZiehen)      ; WM_LBUTTONDOWN
OnMessage(0x232, SpiegelAbgelegt)    ; WM_EXITSIZEMOVE

; ---------------------------------------------------------------- Hotkeys
;
; F1 und F2 gelten ueberall - ausser im Einstellfenster. Dort sollen sie in
; die Tastenfelder wandern koennen: ein globaler Hotkey faengt den Druck
; sonst ab, und F1 liesse sich nie als Sammel- oder Inventartaste eintragen.

#HotIf !EinstellungenVorn()
F1:: Guard(() => Lesen(true))
F2:: Guard(() => (CbLoop.Value := !CbLoop.Value, ToggleLoop(CbLoop.Value)))
#HotIf

EinstellungenVorn() {
    try return WinActive("ahk_id " . Ein.Hwnd) ? true : false
    return false
}

; ---------------------------------------------------------------- Fehlerabfang

; Fuehrt fn aus und faengt jeden Fehler ab, damit weder Timer noch Hotkey das Skript beenden.
Guard(fn) {
    try {
        fn()
    } catch as e {
        Note("Fehler abgefangen: " . e.Message)
    }
}

HandleError(err, mode) {
    Note("Fehler abgefangen: " . err.Message)
    return 1        ; Standarddialog unterdruecken, Skript laeuft weiter
}

Note(txt) {
    try TxtHint.Value := txt
}

; Schreibt eine Zeile in die Mitschrift. Hier landen der Ablauf nach dem
; Sammeln und Neustarts der Texterkennung - damit sich hinterher nachlesen
; laesst, warum eine Taste ausgeblieben ist. Wird die Datei zu gross, wandert
; sie nach Sammler.alt.log (die vorige alte faellt weg) und es geht neu los -
; so ist der letzte Verlauf nicht auf einen Schlag verloren.
Protokoll(txt) {
    try {
        if (FileExist(LOGDATEI) && FileGetSize(LOGDATEI) > 300000)
            FileMove(LOGDATEI, LOGALT, true)
        FileAppend(FormatTime(, "dd.MM. HH:mm:ss") . "  " . txt . "`n", LOGDATEI, "UTF-8")
    }
}

; ---------------------------------------------------------------- Dunkler Modus

; Windows selbst auf dunkel stellen. Die beiden Funktionen haben keinen
; Namen in der DLL, nur eine Nummer - deshalb erst die Adresse holen und
; dann darueber aufrufen. Ohne das blieben Knoepfe und Haken hellgrau.
DunkelAnmelden() {
    try {
        dll := DllCall("GetModuleHandle", "str", "uxtheme", "ptr")
        if (!dll)
            dll := DllCall("LoadLibrary", "str", "uxtheme.dll", "ptr")
        DllCall(DllCall("GetProcAddress", "ptr", dll, "ptr", 135, "ptr"), "int", 2)   ; immer dunkel
        DllCall(DllCall("GetProcAddress", "ptr", dll, "ptr", 136, "ptr"))             ; Themen neu laden
    }
}

; Titelleiste dunkel, und jedes Bedienfeld auf das dunkle Thema umstellen.
DunkelFenster(g) {
    an := 1
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "int", 20, "int*", an, "int", 4)
    try DllCall("uxtheme\SetWindowTheme", "ptr", g.Hwnd, "str", "DarkMode_Explorer", "ptr", 0)
    for hwnd, ctrl in g {
        ; Eingabefelder wollen ein anderes Thema als Knoepfe und Haken.
        thema := (ctrl.Type = "Edit" || ctrl.Type = "Hotkey" || ctrl.Type = "ComboBox" || ctrl.Type = "DDL")
            ? "DarkMode_CFD" : "DarkMode_Explorer"
        try DllCall("uxtheme\SetWindowTheme", "ptr", ctrl.Hwnd, "str", thema, "ptr", 0)
    }
}

; ---------------------------------------------------------------- Einstellungen

LadeEinstellungen() {
    ; Zaehler ist vorbelegt: am Screenshot gemessen, Text bei x 831..1088,
    ; y 982..996 auf 1920x1080. Wo Essen/Trinken steht, ist von Server und
    ; Aufloesung abhaengig - das muss jeder einmal selbst aufziehen.
    sx := A_ScreenWidth / 1920, sy := A_ScreenHeight / 1080
    FeldLaden(Zaehler, Round(820 * sx), Round(974 * sy), Round(280 * sx), Round(32 * sy))
    FeldLaden(Vorrat, 0, 0, 0, 0)

    CbSpiegel.Value := (IniRead(INI, "Allgemein", "Spiegel", "1") = "1")
    CbTabak.Value := (IniRead(INI, "Allgemein", "TabakKasten", "0") = "1")
    WerteLaden()
    ZeigeSollzeile(-1)
    ZeigeBereich()
    ZeigeQuelle()
    ZeigeVorrat()
    SpiegelAlle()
}

FeldLaden(f, vx, vy, vw, vh) {
    f.X := Integer(IniRead(INI, f.Name, "X", vx))
    f.Y := Integer(IniRead(INI, f.Name, "Y", vy))
    f.W := Integer(IniRead(INI, f.Name, "W", vw))
    f.H := Integer(IniRead(INI, f.Name, "H", vh))
    f.Exe     := IniRead(INI, f.Name, "Exe", "")
    f.Fenster := IniRead(INI, f.Name, "Fenster", "")
    f.FX := Integer(IniRead(INI, f.Name, "FX", 0))
    f.FY := Integer(IniRead(INI, f.Name, "FY", 0))
    f.SpX := Integer(IniRead(INI, f.Name, "SpX", f.X - SPIEGEL_RAND))
    f.SpY := Integer(IniRead(INI, f.Name, "SpY", f.Y - SPIEGEL_RAND))
}

FeldSpeichern(f) {
    IniWrite(f.X, INI, f.Name, "X")
    IniWrite(f.Y, INI, f.Name, "Y")
    IniWrite(f.W, INI, f.Name, "W")
    IniWrite(f.H, INI, f.Name, "H")
    IniWrite(f.Exe, INI, f.Name, "Exe")
    IniWrite(f.Fenster, INI, f.Name, "Fenster")
    IniWrite(f.FX, INI, f.Name, "FX")
    IniWrite(f.FY, INI, f.Name, "FY")
    IniWrite(f.SpX, INI, f.Name, "SpX")
    IniWrite(f.SpY, INI, f.Name, "SpY")
    IniWrite(CbSpiegel.Value ? 1 : 0, INI, "Allgemein", "Spiegel")
}

; ---------------------------------------------------------------- Einstellfenster

EinstellungenZeigen() {
    WerteInsFenster()
    ZeigeBereich()
    ZeigeQuelle()
    try WinGetPos(&x, &y, &b, , Ui)
    catch
        x := 0, y := 0, b := 0
    ; Neben das Hauptfenster legen, sonst verdeckt es die Anzeige.
    Ein.Show(Format("x{1} y{2} AutoSize", x + b + 8, y))
}

; Beim Schliessen wird uebernommen und gespeichert - wer etwas eintippt und
; das Fenster zumacht, hat es sonst umsonst getippt.
;
; speichern := false ist fuer das kurze Wegblenden beim Aufziehen eines
; Bereichs: da geht das Fenster nur aus dem Weg und kommt gleich wieder.
EinstellungenVerstecken(speichern := true) {
    if (speichern)
        Guard(() => WerteUebernehmen(false))
    try Ein.Hide()
}

; Die Felder mit den aktuellen Werten fuellen.
WerteInsFenster() {
    EdProTakt.Value := PRO_TAKT
    EdTakt.Value := Round(TAKT)
    EdScan.Value := SCAN_MS
    EdVorratMs.Value := VORRAT_MS
    EdKnapp.Value := KNAPP
    FeldSetzen(EdBlattProTabak, BLATT_PRO_TABAK)
    FeldSetzen(EdMinProTabak, MIN_PRO_TABAK)
    EdZiel.Value := ZIEL
    CbStop.Value := STOP_AN ? 1 : 0
    HkStop.Value := STOP_TASTE
    EdStopMs.Value := STOP_MS
    CbTaste.Value := TASTE_AN ? 1 : 0
    HkTaste.Value := TASTE
    EdTasteMs.Value := TASTE_MS
    CbTasteAkt.Value := TASTE_AKT ? 1 : 0
    CbWurf.Value := WURF_AN ? 1 : 0
    EdWurfMs.Value := WURF_MS
    CbZu.Value := ZU_AN ? 1 : 0
    HkZu.Value := ZU_TASTE
    EdZuMs.Value := ZU_MS
    CbSam.Value := SAM_AN ? 1 : 0
    HkSam.Value := SAM_TASTE
    EdSamMs.Value := SAM_MS
    ZeigeWurf()
}

; Schreibt unter die Knoepfe, wo der Rechtsklick landet.
ZeigeWurf() {
    if (WURF_X < 0) {
        TxtWurf.Value := "Wegwerf-Punkt: noch nicht gesetzt"
        return
    }
    lage := WURF_REL ? Format("   im Fenster: x{1} y{2}", WURF_FX, WURF_FY) : "   (nur Bildschirm - Fenster darf sich nicht verschieben)"
    TxtWurf.Value := Format("Wegwerf-Punkt: x{1} y{2}{3}", WURF_X, WURF_Y, lage)
}

; Eingetragene Werte pruefen, uebernehmen und merken. Grenzen, damit sich
; niemand mit einer 0 den Takt oder die Rechnung zerschiesst.
; melden := false heisst: uebernehmen und speichern, aber ohne die lange
; Zeile in der Statuszeile. So kann auch das Schliessen des Fensters
; speichern, ohne dass es nach einer Meldung aussieht.
WerteUebernehmen(melden := true) {
    global PRO_TAKT, TAKT, SOLL_RATE, SCAN_MS, VORRAT_MS, KNAPP
    global ZIEL, TASTE_AN, TASTE, TASTE_MS, TASTE_AKT
    global WURF_AN, WURF_MS, ZU_AN, ZU_TASTE, ZU_MS, SAM_AN, SAM_TASTE, SAM_MS
    global STOP_AN, STOP_TASTE, STOP_MS
    global BLATT_PRO_TABAK, MIN_PRO_TABAK
    PRO_TAKT  := Grenze(EdProTakt.Value, 1, 100, PRO_TAKT)
    TAKT      := Grenze(EdTakt.Value, 1, 600, Round(TAKT)) + 0.0
    SCAN_MS   := Grenze(EdScan.Value, 300, 10000, SCAN_MS)
    VORRAT_MS := Grenze(EdVorratMs.Value, 2000, 120000, VORRAT_MS)
    KNAPP     := Grenze(EdKnapp.Value, 1, 99, KNAPP)
    BLATT_PRO_TABAK := Grenze(EdBlattProTabak.Value, 1, 10000, BLATT_PRO_TABAK)
    MIN_PRO_TABAK   := Kommazahl(EdMinProTabak.Value, 0.01, 600, MIN_PRO_TABAK)
    SOLL_RATE := PRO_TAKT / TAKT

    ZIEL      := Grenze(EdZiel.Value, 0, 100000, ZIEL)
    TASTE_AN  := CbTaste.Value ? true : false
    TASTE     := Trim(HkTaste.Value)
    TASTE_MS  := Grenze(EdTasteMs.Value, 0, 60000, TASTE_MS)
    TASTE_AKT := CbTasteAkt.Value ? true : false
    WURF_AN := CbWurf.Value ? true : false
    WURF_MS := Grenze(EdWurfMs.Value, 0, 60000, WURF_MS)
    if (WURF_AN && WURF_X < 0) {
        WURF_AN := false            ; ohne Punkt wuesste der Klick nicht wohin
        Note("Kein Wegwerf-Punkt gesetzt - erst im Zahnrad auf 'Wegwerf-Punkt setzen'.")
    }
    STOP_AN    := CbStop.Value ? true : false
    STOP_TASTE := Trim(HkStop.Value)
    STOP_MS    := Grenze(EdStopMs.Value, 0, 60000, STOP_MS)
    ZU_AN    := CbZu.Value ? true : false
    ZU_TASTE := Trim(HkZu.Value)
    ZU_MS    := Grenze(EdZuMs.Value, 0, 60000, ZU_MS)
    SAM_AN    := CbSam.Value ? true : false
    SAM_TASTE := Trim(HkSam.Value)
    SAM_MS    := Grenze(EdSamMs.Value, 0, 60000, SAM_MS)

    ; Ein Haken ohne Taste waere nur Deko - dann lieber ehrlich ausschalten.
    fehlt := ""
    if (STOP_AN && SendeSyntax(STOP_TASTE) = "")
        STOP_AN := false, fehlt .= " Sammeln abbrechen"
    if (TASTE_AN && SendeSyntax(TASTE) = "")
        TASTE_AN := false, fehlt .= " Inventar öffnen"
    if (ZU_AN && SendeSyntax(ZU_TASTE) = "")
        ZU_AN := false, fehlt .= " Inventar schließen"
    if (SAM_AN && SendeSyntax(SAM_TASTE) = "")
        SAM_AN := false, fehlt .= " Sammeln starten"
    if (fehlt != "")
        Note("Keine Taste gewählt bei:" . fehlt . " - Feld anklicken und Taste drücken.")

    WerteSpeichern()
    WerteInsFenster()            ; zeigt, was wirklich angekommen ist

    if (CbLoop.Value)            ; neuen Takt sofort wirksam machen
        ToggleLoop(true)

    if (Aktuell >= 0)
        Anzeigen()
    else
        ZeigeSollzeile(-1)      ; Beschriftung soll auch ohne Lesung stimmen
    ZeigeVorrat()
    TabakZeigen()
    TabakSpeichern()

    if (!melden) {
        Note("Einstellungen gespeichert um " . FormatTime(, "HH:mm:ss"))
        return
    }
    Note(Format("Übernommen: {1} Stück / {2} s, Zähler alle {3} ms, Vorrat alle {4} ms, knapp ab {5} Prozent, fertig ab {6}, Abbruch {7}, Inventar {8}, {9}, {10}, {11}"
        , PRO_TAKT, Round(TAKT), SCAN_MS, VORRAT_MS, KNAPP
        , ZIEL > 0 ? ZIEL . " Stück" : "ganzer Auftrag"
        , STOP_AN ? STOP_TASTE . " nach " . STOP_MS . " ms" : "aus"
        , TASTE_AN ? TASTE . " nach " . TASTE_MS . " ms" : "aus"
        , WURF_AN ? "Rechtsklick nach " . WURF_MS . " ms" : "kein Klick"
        , ZU_AN ? ZU_TASTE . " nach " . ZU_MS . " ms" : "kein Schließen"
        , SAM_AN ? SAM_TASTE . " nach " . SAM_MS . " ms" : "kein Neustart"))
}

; Wie Grenze, nur fuer Zahlen mit Komma - die Bearbeitungszeit darf auch
; eine halbe Minute sein.
Kommazahl(wert, min, max, ersatz) {
    wert := StrReplace(Trim(wert . ""), ",", ".")
    if !IsNumber(wert)
        return ersatz
    z := wert + 0.0
    return (z < min) ? min : (z > max) ? max : z
}

Grenze(wert, min, max, ersatz) {
    if !IsNumber(wert)
        return ersatz
    z := Integer(wert)
    if (z < min)
        return min
    if (z > max)
        return max
    return z
}

WerteLaden() {
    global PRO_TAKT, TAKT, SOLL_RATE, SCAN_MS, VORRAT_MS, KNAPP
    global ZIEL, TASTE_AN, TASTE, TASTE_MS, TASTE_AKT
    global WURF_AN, WURF_MS, WURF_X, WURF_Y, WURF_REL, WURF_FX, WURF_FY
    global ZU_AN, ZU_TASTE, ZU_MS, SAM_AN, SAM_TASTE, SAM_MS
    global STOP_AN, STOP_TASTE, STOP_MS
    global BLATT_PRO_TABAK, MIN_PRO_TABAK, PREIS_PRO_TABAK, WUNSCH
    PRO_TAKT  := Grenze(IniRead(INI, "Werte", "ProTakt", PRO_TAKT), 1, 100, PRO_TAKT)
    TAKT      := Grenze(IniRead(INI, "Werte", "Takt", Round(TAKT)), 1, 600, Round(TAKT)) + 0.0
    SCAN_MS   := Grenze(IniRead(INI, "Werte", "ScanMs", SCAN_MS), 300, 10000, SCAN_MS)
    VORRAT_MS := Grenze(IniRead(INI, "Werte", "VorratMs", VORRAT_MS), 2000, 120000, VORRAT_MS)
    KNAPP     := Grenze(IniRead(INI, "Werte", "Knapp", KNAPP), 1, 99, KNAPP)
    SOLL_RATE := PRO_TAKT / TAKT
    ZIEL      := Grenze(IniRead(INI, "Werte", "Ziel", ZIEL), 0, 100000, ZIEL)
    TASTE_AN  := (IniRead(INI, "Werte", "TasteAn", TASTE_AN ? "1" : "0") = "1")
    TASTE     := Trim(IniRead(INI, "Werte", "Taste", TASTE))
    TASTE_MS  := Grenze(IniRead(INI, "Werte", "TasteMs", TASTE_MS), 0, 60000, TASTE_MS)
    TASTE_AKT := (IniRead(INI, "Werte", "TasteAktivieren", TASTE_AKT ? "1" : "0") = "1")
    WURF_AN   := (IniRead(INI, "Werte", "WurfAn", WURF_AN ? "1" : "0") = "1")
    WURF_MS   := Grenze(IniRead(INI, "Werte", "WurfMs", WURF_MS), 0, 60000, WURF_MS)
    WURF_X    := Integer(IniRead(INI, "Werte", "WurfX", WURF_X))
    WURF_Y    := Integer(IniRead(INI, "Werte", "WurfY", WURF_Y))
    WURF_REL  := (IniRead(INI, "Werte", "WurfRel", "0") = "1")
    WURF_FX   := Integer(IniRead(INI, "Werte", "WurfFX", 0))
    WURF_FY   := Integer(IniRead(INI, "Werte", "WurfFY", 0))
    if (WURF_X < 0)
        WURF_AN := false
    WUNSCH          := Grenze(IniRead(INI, "Tabak", "Wunsch", WUNSCH), 0, 1000000000, WUNSCH)
    BLATT_PRO_TABAK := Grenze(IniRead(INI, "Tabak", "BlattProTabak", BLATT_PRO_TABAK), 1, 10000, BLATT_PRO_TABAK)
    MIN_PRO_TABAK   := Kommazahl(IniRead(INI, "Tabak", "MinProTabak", MIN_PRO_TABAK), 0.01, 600, MIN_PRO_TABAK)
    PREIS_PRO_TABAK := Grenze(IniRead(INI, "Tabak", "PreisProTabak", PREIS_PRO_TABAK), 0, 10000000, PREIS_PRO_TABAK)
    STOP_AN    := (IniRead(INI, "Werte", "StopAn", STOP_AN ? "1" : "0") = "1")
    STOP_TASTE := Trim(IniRead(INI, "Werte", "StopTaste", STOP_TASTE))
    STOP_MS    := Grenze(IniRead(INI, "Werte", "StopMs", STOP_MS), 0, 60000, STOP_MS)
    ZU_AN     := (IniRead(INI, "Werte", "ZuAn", ZU_AN ? "1" : "0") = "1")
    ZU_TASTE  := Trim(IniRead(INI, "Werte", "ZuTaste", ZU_TASTE))
    ZU_MS     := Grenze(IniRead(INI, "Werte", "ZuMs", ZU_MS), 0, 60000, ZU_MS)
    SAM_AN    := (IniRead(INI, "Werte", "SammelnAn", SAM_AN ? "1" : "0") = "1")
    SAM_TASTE := Trim(IniRead(INI, "Werte", "SammelnTaste", SAM_TASTE))
    SAM_MS    := Grenze(IniRead(INI, "Werte", "SammelnMs", SAM_MS), 0, 60000, SAM_MS)
    WerteInsFenster()
}

WerteSpeichern() {
    IniWrite(PRO_TAKT, INI, "Werte", "ProTakt")
    IniWrite(Round(TAKT), INI, "Werte", "Takt")
    IniWrite(SCAN_MS, INI, "Werte", "ScanMs")
    IniWrite(VORRAT_MS, INI, "Werte", "VorratMs")
    IniWrite(KNAPP, INI, "Werte", "Knapp")
    IniWrite(ZIEL, INI, "Werte", "Ziel")
    IniWrite(TASTE_AN ? 1 : 0, INI, "Werte", "TasteAn")
    IniWrite(TASTE, INI, "Werte", "Taste")
    IniWrite(TASTE_MS, INI, "Werte", "TasteMs")
    IniWrite(TASTE_AKT ? 1 : 0, INI, "Werte", "TasteAktivieren")
    IniWrite(WURF_AN ? 1 : 0, INI, "Werte", "WurfAn")
    IniWrite(WURF_MS, INI, "Werte", "WurfMs")
    IniWrite(WUNSCH, INI, "Tabak", "Wunsch")
    IniWrite(BLATT_PRO_TABAK, INI, "Tabak", "BlattProTabak")
    IniWrite(MIN_PRO_TABAK, INI, "Tabak", "MinProTabak")
    IniWrite(PREIS_PRO_TABAK, INI, "Tabak", "PreisProTabak")
    IniWrite(STOP_AN ? 1 : 0, INI, "Werte", "StopAn")
    IniWrite(STOP_TASTE, INI, "Werte", "StopTaste")
    IniWrite(STOP_MS, INI, "Werte", "StopMs")
    IniWrite(ZU_AN ? 1 : 0, INI, "Werte", "ZuAn")
    IniWrite(ZU_TASTE, INI, "Werte", "ZuTaste")
    IniWrite(ZU_MS, INI, "Werte", "ZuMs")
    IniWrite(SAM_AN ? 1 : 0, INI, "Werte", "SammelnAn")
    IniWrite(SAM_TASTE, INI, "Werte", "SammelnTaste")
    IniWrite(SAM_MS, INI, "Werte", "SammelnMs")
    WurfPunktSpeichern()
}

; Der Punkt wird sofort beim Setzen gemerkt, nicht erst beim Uebernehmen -
; sonst waere eine Kalibrierung weg, wenn das Fenster einfach zugeht.
WurfPunktSpeichern() {
    IniWrite(WURF_X, INI, "Werte", "WurfX")
    IniWrite(WURF_Y, INI, "Werte", "WurfY")
    IniWrite(WURF_REL ? 1 : 0, INI, "Werte", "WurfRel")
    IniWrite(WURF_FX, INI, "Werte", "WurfFX")
    IniWrite(WURF_FY, INI, "Werte", "WurfFY")
}

; ---------------------------------------------------------------- Tabak

; Kasten ein- oder ausblenden und das Fenster mitwachsen lassen. Nur ein
; echter Wechsel aendert die Hoehe - zweimal "an" hintereinander wuerde das
; Fenster sonst doppelt wachsen lassen.
TabakKastenUmschalten(an) {
    global TABAK_SICHTBAR

    an := an ? true : false
    if (an = TABAK_SICHTBAR)
        return

    for feld in KastenFelder()
        feld.Visible := an
    try {
        WinGetPos(, , , &hoehe, Ui)
        Ui.Move(, , , hoehe + (an ? TABAK_HOEHE : -TABAK_HOEHE))
    }
    TABAK_SICHTBAR := an

    if (an)
        TabakZeigen()
}

; Alles, was zum Kasten gehoert - die Flaeche, die Anzeigen und die
; Eingabefelder. Die drei kleinen Beschriftungen ("Blätter", "$/Tabak",
; "Wunsch $") haben keine eigene Variable und stehen nicht in der Liste:
; sie verschwinden, weil das Fenster beim Zuklappen um den Kasten kuerzer wird.
KastenFelder() {
    return [TabakKasten, TxtKastenGeld, TxtKastenMenge
        , EdKastenBlatt, EdKastenPreis
        , TxtKastenZeit, BtnKastenStart, TxtKastenLauf
        , TabakStrich, EdKastenWunsch, TxtKastenWunsch, TxtKastenWunschZeit
        , TxtKastenInfo]
}

; Haken angeklickt: umschalten und die Wahl fuer das naechste Mal merken.
TabakHakenGeklickt() {
    TabakKastenUmschalten(CbTabak.Value)
    IniWrite(CbTabak.Value ? 1 : 0, INI, "Allgemein", "TabakKasten")
}

; ---- Eingaben ---------------------------------------------------------
;
; Blaetter und Preis werden im Kasten eingetragen, das Rezept (Blaetter je
; Tabak, Minuten je Tabak) im Zahnrad unter "Werte". TabakZeigen schreibt
; nach jeder Rechnung alle diese Felder neu. Jedes Setzen eines Feldes
; meldet Windows selbst wieder als Aenderung - deshalb prueft TabakEingabe
; zuerst, ob ueberhaupt etwas Neues drinsteht.

KastenFeldGeaendert() {
    TabakEingabe(EdKastenBlatt.Value, EdKastenPreis.Value)
}

; Nimmt entgegen, was in einem der Felder steht - egal von welcher Seite.
;
; Der Vergleich am Anfang ist die Bremse gegen die Endlosschleife: Windows
; meldet auch die Werte als Aenderung, die das Programm selbst gerade
; hineingeschrieben hat. Stimmt alles schon, war es die eigene Schreiberei
; und es gibt nichts zu tun.
TabakEingabe(blatt, preis) {
    global TABAK_BLATT, PREIS_PRO_TABAK

    neuBlatt := Grenze(blatt, 0, 10000000, TABAK_BLATT)
    neuPreis := Grenze(preis, 0, 10000000, PREIS_PRO_TABAK)
    if (neuBlatt = TABAK_BLATT && neuPreis = PREIS_PRO_TABAK)
        return

    TABAK_BLATT := neuBlatt
    PREIS_PRO_TABAK := neuPreis
    TabakZeigen()
    TabakSpeichern()
}

; ---- Anzeige ----------------------------------------------------------

; Rechnet aus den Blaettern das fertige Tabak, die Bearbeitungszeit und das
; Geld, und schreibt das Ergebnis in beide Ansichten. Angebrochene Buendel
; zaehlen nicht mit: aus 25 Blaettern wird bei 20 je Tabak ein Tabak, fuenf
; Blaetter bleiben liegen.
TabakZeigen() {
    tabak := TABAK_BLATT // BLATT_PRO_TABAK
    rest := Mod(TABAK_BLATT, BLATT_PRO_TABAK)
    geld := tabak * PREIS_PRO_TABAK
    sekunden := tabak * MIN_PRO_TABAK * 60

    geldText := Tausender(geld) . " $"
    mengeText := Format("{1} Tabak aus {2} Blättern{3}"
        , Tausender(tabak), Tausender(TABAK_BLATT)
        , rest ? Format("   ({1} übrig)", rest) : "")
    zeitText := "Bearbeitung: " . Dauer(sekunden)

    try {
        FeldSetzen(EdKastenBlatt, TABAK_BLATT)
        FeldSetzen(EdKastenPreis, PREIS_PRO_TABAK)
        FeldSetzen(EdBlattProTabak, BLATT_PRO_TABAK)
        FeldSetzen(EdMinProTabak, MIN_PRO_TABAK)
    }

    FeldSetzen(TxtKastenGeld, geldText)
    FeldSetzen(TxtKastenMenge, mengeText)
    if (!TABAK_ENDE)                ; laeuft eine Bearbeitung, gehoert die Zeile ihr
        FeldSetzen(TxtKastenZeit, zeitText)

    ; Wie lange die eingetragenen Blaetter zu sammeln sind - mit demselben
    ; Takt, aus dem oben im Fenster die Restzeit kommt.
    proBlatt := TABAK_BLATT ? geld / TABAK_BLATT : PREIS_PRO_TABAK / BLATT_PRO_TABAK
    FeldSetzen(TxtKastenInfo, Format("Sammeln {1}   -   je Blatt {2} $   -   je Stunde {3} $"
        , Dauer(TABAK_BLATT / SOLL_RATE), Zwei(proBlatt)
        , Tausender(Round(PREIS_PRO_TABAK * 60 / MIN_PRO_TABAK))))

    WunschRechnen()             ; haengt an denselben Zahlen, also gleich mit
}

; Schreibt nur, wenn sich der Inhalt wirklich aendert.
;
; Das ist kein Feinschliff, sondern Pflicht: Windows meldet jedes Setzen
; eines Feldes als Aenderung, die Gegenseite rechnet daraufhin neu und setzt
; zurueck - beide Seiten haetten sich endlos angestossen und das Fenster
; eingefroren. Bleibt der Inhalt gleich, entsteht gar kein Ereignis.
FeldSetzen(feld, wert) {
    if ((feld.Value . "") != (wert . ""))
        feld.Value := wert
}

; Die Wunschsumme aus dem Kasten. Wie bei den uebrigen Feldern zaehlt nur,
; was sich wirklich geaendert hat - WunschRechnen schreibt das Feld selbst
; wieder zurueck.
WunschEingabe(wert) {
    global WUNSCH

    neu := Grenze(wert, 0, 1000000000, WUNSCH)
    if (neu = WUNSCH)
        return
    WUNSCH := neu
    WunschRechnen()
    TabakSpeichern()
}

; Die Rechnung rueckwaerts: Wie viel muss zusammenkommen, damit die
; Wunschsumme herauskommt? Angebrochene Tabak zahlt niemand, deshalb wird
; auf das naechste volle Tabak aufgerundet - und damit auch auf volle
; Buendel Blaetter.
WunschRechnen() {
    FeldSetzen(EdKastenWunsch, WUNSCH)

    if (WUNSCH <= 0 || PREIS_PRO_TABAK <= 0) {
        FeldSetzen(TxtKastenWunsch, "Summe eintragen für die nötige Menge")
        FeldSetzen(TxtKastenWunschZeit, "")
        return
    }

    tabak := Ceil(WUNSCH / PREIS_PRO_TABAK)
    blatt := tabak * BLATT_PRO_TABAK
    bringt := tabak * PREIS_PRO_TABAK

    FeldSetzen(TxtKastenWunsch, Format("{1} Blätter = {2} Tabak   ({3} $)"
        , Tausender(blatt), Tausender(tabak), Tausender(bringt)))

    ; Was davon noch fehlt, und wie lange das dauert. Die Sammelzeit kommt
    ; aus demselben Takt, mit dem oben die Restzeit gerechnet wird.
    fehlt := blatt - TABAK_BLATT
    bearbeitung := tabak * MIN_PRO_TABAK * 60
    if (fehlt <= 0) {
        FeldSetzen(TxtKastenWunschZeit, "Blätter reichen - noch " . Dauer(bearbeitung) . " Bearbeitung")
        return
    }
    FeldSetzen(TxtKastenWunschZeit, Format("noch {1} Blätter - {2} sammeln + {3} Bearbeitung"
        , Tausender(fehlt), Dauer(fehlt / SOLL_RATE), Dauer(bearbeitung)))
}

; Rezept und Wunschsumme sofort merken. Kasten-Eingaben haben keinen
; Uebernehmen-Knopf, also darf das Speichern nicht daran haengen.
TabakSpeichern() {
    try {
        IniWrite(WUNSCH, INI, "Tabak", "Wunsch")
        IniWrite(BLATT_PRO_TABAK, INI, "Tabak", "BlattProTabak")
        IniWrite(MIN_PRO_TABAK, INI, "Tabak", "MinProTabak")
        IniWrite(PREIS_PRO_TABAK, INI, "Tabak", "PreisProTabak")
    }
}

; Nach jeder Lesung neu rechnen. Die Blattzahl bleibt dabei stehen: sie
; gehoert dem, der sie eingetragen hat - der Sammelstand ist etwas anderes
; als der Vorrat, den man verarbeiten will.
TabakKastenRechnen() {
    TabakZeigen()
}

; ---- Bearbeitungszeit -------------------------------------------------
;
; Die reine Zahl sagt nicht, wann man wiederkommen muss. Deshalb laeuft die
; Zeit auf Knopfdruck wirklich ab - jede halbe Sekunde neu geschrieben.

BearbeitungUmschalten() {
    global TABAK_ENDE

    if (TABAK_ENDE) {               ; laeuft gerade -> abbrechen
        BearbeitungStoppen()
        Note("Bearbeitung abgebrochen.")
        return
    }

    tabak := TABAK_BLATT // BLATT_PRO_TABAK
    if (tabak < 1) {
        Note("Zu wenig Blätter für ein Tabak.")
        return
    }

    TABAK_ENDE := A_TickCount + Round(tabak * MIN_PRO_TABAK * 60000)
    BtnKastenStart.Text := "Stopp"
    SetTimer(BearbeitungTicken, 1000)
    BearbeitungTicken()
    Note(Format("Bearbeitung gestartet: {1} Tabak, {2}", tabak, Dauer(tabak * MIN_PRO_TABAK * 60)))
}

BearbeitungTicken() {
    Guard(BearbeitungZeigen)
}

BearbeitungZeigen() {
    global TABAK_ENDE

    rest := (TABAK_ENDE - A_TickCount) / 1000
    if (rest > 0) {
        ; Nur schreiben, wenn sich der Text wirklich aendert: die Endzeit
        ; steht die ganze Zeit fest, jedes Neuschreiben waere ein Zucken
        ; ohne neuen Inhalt.
        FeldSetzen(TxtKastenZeit, "Läuft noch: " . Dauer(rest))
        FeldSetzen(TxtKastenLauf, "fertig " . FormatTime(DateAdd(A_Now, Round(rest), "Seconds"), "HH:mm"))
        return
    }

    BearbeitungStoppen()
    FeldSetzen(TxtKastenZeit, "Bearbeitung fertig")
    FeldSetzen(TxtKastenLauf, FormatTime(, "HH:mm:ss"))
    Note("Tabak fertig bearbeitet um " . FormatTime(, "HH:mm:ss"))
    Protokoll("Tabak-Bearbeitung fertig.")
}

BearbeitungStoppen() {
    global TABAK_ENDE
    TABAK_ENDE := 0
    SetTimer(BearbeitungTicken, 0)
    BtnKastenStart.Text := "Start"
    TxtKastenLauf.Value := ""
    TabakZeigen()
}

; 1256000 -> "1.256.000". Punkt als Tausenderzeichen, wie hierzulande ueblich.
Tausender(zahl) {
    txt := Format("{1:d}", Round(zahl))
    minus := (SubStr(txt, 1, 1) = "-") ? "-" : ""
    if (minus != "")
        txt := SubStr(txt, 2)
    aus := ""
    while (StrLen(txt) > 3) {
        aus := "." . SubStr(txt, -3) . aus
        txt := SubStr(txt, 1, StrLen(txt) - 3)
    }
    return minus . txt . aus
}

; Zwei Nachkommastellen mit Komma statt Punkt.
Zwei(zahl) {
    return StrReplace(Format("{1:.2f}", zahl), ".", ",")
}

ZeigeBereich() {
    v := Vorrat.Kalibriert ? Format("   Essen/Trinken: x{1} y{2} {3}x{4}", Vorrat.X, Vorrat.Y, Vorrat.W, Vorrat.H)
        : "   Essen/Trinken: nicht eingerichtet"
    TxtBereich.Value := Format("Zähler: x{1} y{2} {3}x{4}", Zaehler.X, Zaehler.Y, Zaehler.W, Zaehler.H) . v
}

ZeigeQuelle() {
    if (Zaehler.Exe = "" && Zaehler.Fenster = "") {
        TxtQuelle.Value := "Quelle: noch kein Fenster - Zähler im Zahnrad aufziehen"
        return
    }
    zustand := Zaehler.Tn ? "gespiegelt, Verdeckung egal"
        : (CbSpiegel.Value ? "Fenster nicht gefunden - liest vom Bildschirm" : "liest direkt vom Bildschirm")
    name := (Zaehler.Exe != "") ? Zaehler.Exe : Zaehler.Fenster
    TxtQuelle.Value := "Quelle: " . name . "  (" . zustand . ")"
}

; ---------------------------------------------------------------- Spiegel

; Sucht das gemerkte Spielfenster. Erst ueber die Programmdatei, dann ueber
; den Titel - der Titel eines Spiels aendert sich haeufiger als sein Name.
QuellFenster(f) {
    kandidaten := []
    if (f.Exe != "") {
        for h in WinGetList("ahk_exe " . f.Exe)
            kandidaten.Push(h)
    }
    if (f.Fenster != "") {
        for h in WinGetList(f.Fenster)
            if (!HatWert(kandidaten, h))
                kandidaten.Push(h)
    }

    passend := 0
    for h in kandidaten {
        if (h = Ui.Hwnd || FeldZuFenster(h))
            continue                     ; eigene Fenster kommen nicht in Frage

        ; Mehrere Fenster koennen dieselbe Programmdatei haben (zwei Spiele,
        ; zwei Skripte). Vorrang hat der gleiche Titel, danach ein Fenster,
        ; in das der gemerkte Bereich ueberhaupt hineinpasst.
        titelGleich := false
        try titelGleich := (f.Fenster != "" && WinGetTitle("ahk_id " . h) = f.Fenster)
        if (titelGleich)
            return h

        innen := Buffer(16, 0)
        DllCall("user32\GetClientRect", "ptr", h, "ptr", innen)
        cw := NumGet(innen, 8, "int"), ch := NumGet(innen, 12, "int")
        if (!passend && cw >= f.FX + f.W && ch >= f.FY + f.H)
            passend := h
    }
    return passend
}

HatWert(liste, wert) {
    for x in liste
        if (x = wert)
            return true
    return false
}

SpiegelAlle() {
    if (!CbSpiegel.Value)
        return
    for f in [Zaehler, Vorrat]
        if (f.Kalibriert)
            SpiegelAn(f)
}

SpiegelAn(f) {
    quelle := QuellFenster(f)
    if (!quelle || !f.Kalibriert) {
        SpiegelAus(f)
        ZeigeQuelle()
        return false
    }
    if (f.Tn && f.Quelle = quelle && WinExist("ahk_id " . f.Gui.Hwnd))
        return true                     ; laeuft schon

    SpiegelAus(f)

    if (!f.Gui) {
        ; NOACTIVATE: das Fenster darf dem Spiel nie den Fokus wegnehmen.
        f.Gui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "Spiegel-" . f.Name)
        f.Gui.BackColor := "3CC878"        ; gruener Rand zum Anfassen
    }
    f.Gui.Show(Format("x{1} y{2} w{3} h{4} NoActivate"
        , f.SpX, f.SpY, f.W + 2 * SPIEGEL_RAND, f.H + 2 * SPIEGEL_RAND))

    if (DllCall("dwmapi\DwmRegisterThumbnail", "ptr", f.Gui.Hwnd, "ptr", quelle, "ptr*", &tn := 0) != 0) {
        f.Gui.Hide()
        Note("Spiegel für " . f.Titel . " nicht möglich.")
        ZeigeQuelle()
        return false
    }

    ; Quellausschnitt auf die Fenstergroesse begrenzen, sonst weist der
    ; Fenstermanager die Einstellung ab.
    innen := Buffer(16, 0)
    DllCall("user32\GetClientRect", "ptr", quelle, "ptr", innen)
    cw := NumGet(innen, 8, "int"), ch := NumGet(innen, 12, "int")
    ql := Max(f.FX, 0), qo := Max(f.FY, 0)
    qr := Min(ql + f.W, cw), qu := Min(qo + f.H, ch)

    if (qr <= ql || qu <= qo) {
        DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", tn)
        f.Gui.Hide()
        Note(f.Titel . ": Bereich liegt außerhalb des Fensters - neu aufziehen.")
        ZeigeQuelle()
        return false
    }

    ; DWM_THUMBNAIL_PROPERTIES: Schalter, Ziel-Rechteck, Quell-Rechteck,
    ; Deckkraft, sichtbar, nur Fensterinhalt (ohne Rahmen).
    p := Buffer(48, 0)
    NumPut("uint", 0x01 | 0x02 | 0x04 | 0x08 | 0x10, p, 0)
    NumPut("int", SPIEGEL_RAND, p, 4)
    NumPut("int", SPIEGEL_RAND, p, 8)
    NumPut("int", SPIEGEL_RAND + f.W, p, 12)
    NumPut("int", SPIEGEL_RAND + f.H, p, 16)
    NumPut("int", ql, p, 20)
    NumPut("int", qo, p, 24)
    NumPut("int", qr, p, 28)
    NumPut("int", qu, p, 32)
    NumPut("uchar", 255, p, 36)
    NumPut("int", 1, p, 40)             ; sichtbar
    NumPut("int", 1, p, 44)             ; nur Fensterinhalt

    if (DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", tn, "ptr", p) != 0) {
        DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", tn)
        f.Gui.Hide()
        Note("Spiegel für " . f.Titel . " ließ sich nicht einstellen.")
        ZeigeQuelle()
        return false
    }

    f.Tn := tn, f.Quelle := quelle
    ZeigeQuelle()
    return true
}

SpiegelAus(f) {
    if (f.Tn) {
        DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", f.Tn)
        f.Tn := 0
    }
    f.Quelle := 0
    try f.Gui.Hide()
}

SpiegelAlleAus() {
    for f in [Zaehler, Vorrat]
        SpiegelAus(f)
}

SpiegelUmschalten() {
    if (CbSpiegel.Value) {
        if (Zaehler.Exe = "" && Zaehler.Fenster = "")
            Note("Erst im Zahnrad den Zähler im Spielfenster aufziehen.")
        else {
            SpiegelAlle()
            Note("Spiegel an - das Spiel darf jetzt verdeckt sein.")
        }
    } else {
        SpiegelAlleAus()
        ZeigeQuelle()
        Note("Spiegel aus - liest direkt vom Bildschirm.")
    }
    FeldSpeichern(Zaehler)
}

; Haelt die Spiegel am Leben: Spiel neu gestartet, Fenster geschlossen usw.
SpiegelPflegen() {
    if (Markiert || !CbSpiegel.Value)
        return
    for f in [Zaehler, Vorrat] {
        if (!f.Kalibriert)
            continue
        if (f.Tn && f.Quelle && WinExist("ahk_id " . f.Quelle))
            continue
        Guard(SpiegelAn.Bind(f))
    }
}

; Zu welchem Feld gehoert dieses Fenster?
FeldZuFenster(hwnd) {
    for f in [Zaehler, Vorrat]
        if (f.Gui && hwnd = f.Gui.Hwnd)
            return f
    return 0
}

; Ein Spiegel laesst sich mit der Maus an eine freie Stelle schieben.
SpiegelZiehen(wParam, lParam, msg, hwnd) {
    if (!FeldZuFenster(hwnd))
        return
    PostMessage(0xA1, 2, 0, , "ahk_id " . hwnd)     ; WM_NCLBUTTONDOWN / HTCAPTION
    return 0
}

SpiegelAbgelegt(wParam, lParam, msg, hwnd) {
    f := FeldZuFenster(hwnd)
    if (!f)
        return
    try {
        WinGetPos(&x, &y, , , f.Gui)
        f.SpX := x, f.SpY := y
        FeldSpeichern(f)
        Note(Format("Spiegel {1} liegt jetzt bei x{2} y{3}", f.Titel, x, y))
    }
}

; Welches Rechteck wird fotografiert? Mit Spiegel dessen Inhalt, sonst der
; kalibrierte Fleck auf dem Bildschirm.
LeseRechteck(f, &x, &y, &w, &h) {
    w := f.W, h := f.H
    if (f.Tn) {
        try {
            WinGetPos(&sx, &sy, , , f.Gui)
            x := sx + SPIEGEL_RAND, y := sy + SPIEGEL_RAND
            return
        }
    }
    x := f.X, y := f.Y
}

; ---------------------------------------------------------------- Bereich aufziehen

; Rechteck ueber den gesuchten Text ziehen. Ein halbdurchsichtiger Schleier ueber
; dem ganzen Bildschirm faengt die Maus ab, damit der Zug nicht im Spiel landet.
Markieren(f) {
    ; ZiehEingabe muss hier stehen, sonst legt die Zuweisung unten eine lokale
    ; Variable an und Abgebrochen() sieht den Abbruch nie.
    global Markiert, ZiehEingabe

    if (Markiert)
        return
    Markiert := true
    probe := false          ; Probelesung erst NACH dem Markieren, siehe unten
    einWar := WinExist("ahk_id " . Ein.Hwnd) ? true : false
    if (einWar)
        EinstellungenVerstecken(false)   ; darf den Bereich nicht verdecken
    SpiegelAlleAus()        ; sonst zieht man ueber ein Spiegelbild statt ueber das Spiel
    ZiehEingabe := InputHook("B L0")        ; B = Tasten nicht schlucken
    ZiehEingabe.KeyOpt("{Escape}", "E")     ; Esc beendet die Aufzeichnung
    ZiehEingabe.Start()
    try {
        hinweis := (f.Name = "Vorrat")
            ? "ein Rechteck um die Anzeige für Essen und Trinken ziehen`n`nalso um  Essen 54%   Trinken 39%"
            : "ein Rechteck um den Zählerstand ziehen`n`nalso um  Sammeln... (24 / 168)  14.76%"

        schleier := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "Auswahl-Schleier")
        schleier.BackColor := "101018"
        schleier.SetFont("s13 Bold", "Segoe UI")
        schleier.MarginX := 0, schleier.MarginY := 0
        schleier.Add("Text", Format("x0 y{1} w{2} Center cWhite BackgroundTrans", A_ScreenHeight // 5, A_ScreenWidth)
            , "Mit gedrückter linker Maustaste " . hinweis . "`n`nEsc bricht ab")
        schleier.Show(Format("x0 y0 w{1} h{2} NoActivate", A_ScreenWidth, A_ScreenHeight))
        WinSetTransparent(150, schleier)

        if !ZiehRechteck(&x1, &y1, &x2, &y2) {
            RahmenAus()
            schleier.Destroy()
            SpiegelAlle()
            return Note("Abgebrochen - Bereich unverändert.")
        }

        nx := Min(x1, x2), ny := Min(y1, y2)
        nw := Abs(x2 - x1), nh := Abs(y2 - y1)
        schleier.Destroy()
        Sleep(250)          ; Schleier muss weg sein, bevor gemessen wird

        if (nw < 20 || nh < 8) {
            RahmenAus()
            SpiegelAlle()
            return Note("Bereich zu klein - noch einmal ziehen.")
        }

        f.X := nx, f.Y := ny, f.W := nw, f.H := nh
        f.SpX := nx - SPIEGEL_RAND, f.SpY := ny - SPIEGEL_RAND
        gefunden := QuelleErmitteln(f)
        FeldSpeichern(f)
        ZeigeBereich()
        ZeigeQuelle()
        RahmenAus()

        if (!gefunden)
            Note("Kein Fenster erkannt - liest vom Bildschirm, also nur unverdeckt.")

        SpiegelAlle()

        if Verdeckt(f)
            Note("Achtung: das Sammler-Fenster liegt über dem Bereich - verschieben.")
        else
            probe := true
    } finally {
        try ZiehEingabe.Stop()
        try schleier.Destroy()          ; darf auf keinen Fall stehen bleiben
        Markiert := false
        if (einWar)
            EinstellungenZeigen()
    }

    ; Erst hier lesen: solange Markiert gesetzt ist, weist FeldLesen() jeden
    ; Auftrag ab - die Probe lief sonst ins Leere.
    if (probe) {
        if (f.Name = "Vorrat")
            VorratLesen()
        else
            Lesen()
    }
}

; Merkt sich das Fenster unter dem Bereich und den Bereich innerhalb davon.
QuelleErmitteln(f) {
    cx := f.X + f.W // 2, cy := f.Y + f.H // 2
    ; POINT wird als Ganzes uebergeben - zwei einzelne Zahlen zerschiessen
    ; den Aufruf auf 64 Bit.
    punkt := (cy << 32) | (cx & 0xFFFFFFFF)
    h := DllCall("user32\WindowFromPoint", "int64", punkt, "ptr")
    if (!h)
        return false
    h := DllCall("user32\GetAncestor", "ptr", h, "uint", 2, "ptr")   ; GA_ROOT
    if (!h)
        return false
    if (h = Ui.Hwnd || FeldZuFenster(h))
        return false                     ; das eigene Fenster spiegelt man nicht

    ecke := Buffer(8, 0)
    if (!DllCall("user32\ClientToScreen", "ptr", h, "ptr", ecke))
        return false
    f.FX := f.X - NumGet(ecke, 0, "int")
    f.FY := f.Y - NumGet(ecke, 4, "int")

    try {
        f.Exe := WinGetProcessName("ahk_id " . h)
        f.Fenster := WinGetTitle("ahk_id " . h)
    } catch {
        return false
    }
    return true
}

; Wartet auf einen Mauszug und zeichnet ihn live nach. false = abgebrochen.
ZiehRechteck(&x1, &y1, &x2, &y2) {
    x1 := 0, y1 := 0, x2 := 0, y2 := 0

    ende := A_TickCount + 60000
    while !GetKeyState("LButton", "P") {         ; auf den Beginn des Zugs warten
        if (Abgebrochen() || A_TickCount > ende)
            return false
        Sleep(15)
    }

    MouseGetPos(&x1, &y1)
    while GetKeyState("LButton", "P") {
        if Abgebrochen()
            return false
        MouseGetPos(&x2, &y2)
        RahmenZeigen(Min(x1, x2), Min(y1, y2), Abs(x2 - x1), Abs(y2 - y1))
        Note(Format("Größe: {1} x {2}", Abs(x2 - x1), Abs(y2 - y1)))
        Sleep(15)
    }
    ; x2/y2 bleiben auf dem letzten Wert waehrend des Zugs - nach dem Loslassen
    ; steht die Maus oft schon woanders, das Rechteck waere dann groesser als gezeigt.
    return true
}

; true, sobald Esc gedrueckt wurde.
Abgebrochen() {
    try return !ZiehEingabe.InProgress
    return false
}

; Rahmen aus vier duennen Balken - die stoeren die Bildaufnahme nicht,
; weil sie beim Lesen ausgeblendet sind.
RahmenZeigen(x, y, w, h) {
    global Balken
    if !Balken.Length {
        loop 4 {
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000020", "Rahmen-Balken")   ; E0x20 = mausdurchlaessig
            g.BackColor := "00D000"
            Balken.Push(g)
        }
    }
    d := 2
    Balken[1].Show(Format("x{1} y{2} w{3} h{4} NoActivate", x, y, w, d))
    Balken[2].Show(Format("x{1} y{2} w{3} h{4} NoActivate", x, y + h - d, w, d))
    Balken[3].Show(Format("x{1} y{2} w{3} h{4} NoActivate", x, y, d, h))
    Balken[4].Show(Format("x{1} y{2} w{3} h{4} NoActivate", x + w - d, y, d, h))
}

RahmenAus() {
    global Balken
    for g in Balken
        try g.Hide()
}

; Zeigt die gerade gelesenen Bereiche kurz an - zum Nachschauen, ob sie sitzen.
RahmenBlinken() {
    LeseRechteck(Zaehler, &x, &y, &w, &h)
    RahmenZeigen(x, y, w, h)
    text := Format("Zähler: x{1} y{2} {3}x{4}", x, y, w, h)
    if (Vorrat.Kalibriert) {
        LeseRechteck(Vorrat, &vx, &vy, &vw, &vh)
        text .= Format("   Essen/Trinken: x{1} y{2} {3}x{4}", vx, vy, vw, vh)
    }
    Note(text)
    SetTimer(RahmenAus, -1500)
}

; Liegt das eigene Fenster ueber dem Lesebereich? Dann wird es mitfotografiert.
Verdeckt(f) {
    LeseRechteck(f, &x, &y, &w, &h)
    try WinGetPos(&wx, &wy, &ww, &wh, Ui)
    catch
        return false
    return (wx < x + w) && (wx + ww > x) && (wy < y + h) && (wy + wh > y)
}

; ---------------------------------------------------------------- Texterkennung

StartOcr() {
    global OcrPid, OcrBereit

    ; Bis READY kommt, nimmt FeldLesen keine Auftraege an: sonst loescht eine
    ; Lesung die READY-Antwort, bevor WarteAufDienst sie sieht.
    OcrBereit := false

    ; Den PowerShell-Teil bei jedem Start frisch hinlegen, damit er zur
    ; Fassung dieser Datei passt.
    try FileDelete(OCR_PS)
    FileAppend(PS_Quelltext(), OCR_PS, "UTF-8")

    cmd := Format('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" -Server -Cmd "{2}" -Out "{3}" -Watch {4}'
        , OCR_PS, OCR_CMD, OCR_OUT, DllCall("GetCurrentProcessId"))
    try FileDelete(OCR_OUT)
    try FileDelete(OCR_CMD)
    ; Der Dienst beendet sich selbst, sobald dieses Skript nicht mehr laeuft (-Watch).
    ; "Hide" statt WScript.Shell.Exec: Exec haengt dem Prozess ein
    ; Konsolenfenster an, das kurz aufblitzt.
    Run(cmd, , "Hide", &OcrPid)
    SetTimer(WarteAufDienst, -300)
}

WarteAufDienst() {
    global OcrBereit
    if (WarteAufAntwort(0, 20000) = "READY") {
        OcrBereit := true
        Note("Bereit. F1 = einmal lesen, F2 = Dauerlesung.")
        return
    }
    Note("Texterkennung antwortet nicht - Windows-OCR-Sprache installiert?")
}

; Der Dienst ist weg (abgestuerzt, Standby, von Hand beendet): neu starten.
; Hoechstens alle 15 s, damit ein Dienst, der sofort wieder stirbt, nicht
; in einer Schleife PowerShell nach PowerShell startet.
OcrNeuStarten() {
    global OcrNeustartZeit
    if (OcrNeustartZeit && A_TickCount - OcrNeustartZeit < 15000)
        return
    OcrNeustartZeit := A_TickCount
    Protokoll("Texterkennung war beendet - wird neu gestartet.")
    Note("Texterkennung war beendet - starte neu ...")
    StartOcr()
}

; Wartet, bis der Dienst die Ergebnisdatei geschrieben hat.
; Wartet auf die Antwort MIT DER PASSENDEN NUMMER. Ohne diese Zuordnung
; schnappt sich die naechste Lesung die verspaetete Antwort der vorigen -
; dann standen die Zahlen des Zaehlers bei Essen und Trinken.
WarteAufAntwort(nr, timeout) {
    ende := A_TickCount + timeout
    while (A_TickCount < ende) {
        if FileExist(OCR_OUT) {
            txt := ""
            try txt := Trim(FileRead(OCR_OUT, "UTF-8"), " `t`r`n")   ; Datei kann kurz gesperrt sein
            if (txt != "") {
                try FileDelete(OCR_OUT)
                if RegExMatch(txt, "^(\d+) ?(.*)$", &m) {
                    if (Integer(m[1]) = nr)
                        return m[2]
                    continue          ; alte Antwort - wegwerfen und weiterwarten
                }
                return txt            ; ohne Nummer (sollte nicht vorkommen)
            }
        }
        Sleep(15)
    }
    return ""
}

Beenden() {
    ; Was in den Feldern steht, gilt: beim Zumachen wird es uebernommen und
    ; gespeichert, nicht verworfen.
    Guard(() => WerteUebernehmen(false))
    Guard(TabakSpeichern)
    try Auftrag("QUIT")
    SpiegelAlleAus()
    ExitApp()
}

; Legt dem Dienst einen Auftrag hin (erst Nebendatei, dann umbenennen,
; damit er nie eine halb geschriebene Zeile liest).
Auftrag(text) {
    tmp := OCR_CMD . ".tmp"
    try FileDelete(tmp)
    FileAppend(text, tmp, "UTF-8")
    FileMove(tmp, OCR_CMD, true)
}

; Liest ein Feld und gibt den erkannten Text zurueck ("" = nichts bekommen).
; modus 1 setzt die Zeilen des Ausschnitts nebeneinander - noetig fuer
; Anzeigen wie "Essen 54%", siehe VorratLesen().
FeldLesen(f, modus := 0, sc := 3, rd := 0) {
    global Busy
    if (Busy || Markiert)
        return "BUSY"                ; laeuft schon etwas - nicht dazwischenfunken
    if (!f.Kalibriert)
        return ""
    if (!OcrPid || !ProcessExist(OcrPid)) {
        OcrNeuStarten()
        return "BUSY"                ; gleich wieder da - bis dahin still aussetzen
    }
    if (!OcrBereit)
        return "BUSY"                ; Dienst startet noch

    LeseRechteck(f, &x, &y, &w, &h)
    global AuftragNr
    AuftragNr++
    nr := AuftragNr
    Busy := true
    antwort := ""
    try {
        try FileDelete(OCR_OUT)        ; eine liegengebliebene Antwort ist wertlos
        Auftrag(Format("{1} {2} {3} {4} {5} {6} {7} {8}", nr, x, y, w, h, sc, rd, modus))
        ; Kurzes Zeitlimit: eine Lesung dauert ueblich 0,1 bis 0,6 s. Laenger
        ; warten wuerde nur den schnellen Zaehlertakt blockieren.
        antwort := WarteAufAntwort(nr, 2500)
    } finally {
        Busy := false
    }
    return antwort
}

; ---------------------------------------------------------------- Ablauf

ToggleLoop(on) {
    if (on) {
        SetTimer(TimerTick, SCAN_MS)
        SetTimer(VorratTick, Vorrat.Kalibriert ? VORRAT_MS : 0)
        Note("Dauerlesung läuft.")
    } else {
        SetTimer(TimerTick, 0)
        SetTimer(VorratTick, 0)
        Note("Dauerlesung gestoppt.")
    }
}

TimerTick() {
    Guard(Lesen)
}

; Essen und Trinken haben einen eigenen, langsamen Takt. Sonst wartet der
; Zaehler bei jeder Runde auf zwei zusaetzliche Lesungen und hinkt hinterher.
VorratTick() {
    Guard(VorratLesen)
}

Lesen(auchVorrat := false) {
    roh := FeldLesen(Zaehler)
    if (roh = "BUSY")
        return                       ; es laeuft schon eine Lesung, kein Fehler
    if (roh = "")
        return Note("Keine Antwort von der Texterkennung.")
    if (SubStr(roh, 1, 4) = "ERR ")
        return Note(roh)

    TxtRoh.Value := "OCR: " . roh
    Auswerten(roh)

    if (auchVorrat && Vorrat.Kalibriert)
        VorratLesen()
}

; Buegelt haeufige Lesefehler der Erkennung aus.
; WICHTIG: StrReplace unterscheidet von sich aus NICHT zwischen gross und
; klein. Ohne das vierte Argument wurde aus "Trinke" ein "Tr1nke" - und die
; eingeschleuste 1 landete als Trinken-Wert in der Anzeige.
Normal(txt) {
    n := StrReplace(txt, "O", "0", true)        ; grosses O
    n := StrReplace(n, "l", "1", true)          ; kleines L
    n := StrReplace(n, "I", "1", true)          ; grosses i
    n := StrReplace(n, ",", ".")
    ; Das Prozentzeichen kommt haeufig als "0/0" zurueck ("98.81%" -> "98.810/0").
    return RegExReplace(n, "(\d)0/0(?!\d)", "$1%")
}

; Holt "24 / 168" und die Prozentzahl aus dem erkannten Text.
Auswerten(txt) {
    global Aktuell, Gesamt

    norm := Normal(txt)

    ; Das Trennzeichen wird mal als / mal als | oder \ erkannt.
    if !RegExMatch(norm, "(\d+)\s*[/|\\]\s*(\d+)", &m) {
        OhneAnzeige()
        return
    }
    a := Integer(m[1]), g := Integer(m[2])
    if (g <= 0 || a > g) {
        Note("Unplausibel gelesen: " . m[1] . "/" . m[2])
        return
    }

    p := -1.0
    if RegExMatch(norm, "(\d+(?:\.\d+)?)\s*%", &mp)
        p := mp[1] + 0.0

    ; Gegenprobe: passt der Anteil zur Prozentzahl? Sonst war es ein Lesefehler.
    if (p >= 0) {
        soll := a / g * 100
        if (Abs(soll - p) > 3.0) {
            Note(Format("Verworfen: {1}/{2} passt nicht zu {3} Prozent", a, g, p))
            return
        }
    }

    ; Ein anderer Gesamtwert oder ein Ruecksprung heisst entweder "neuer
    ; Auftrag" oder "verlesen". Beides sieht in einer einzelnen Lesung gleich
    ; aus - im Log standen Abschluesse wie "40 / 40" nach einem vollen
    ; 168er-Auftrag, und "40 / 40" passt sogar zu "100 %". Deshalb gilt so
    ; eine Lesung erst, wenn die naechste sie bestaetigt: gleicher Gesamtwert,
    ; Stand hoechstens ein paar Stueck weiter.
    if (!Bestaetigt(a, g))
        return

    global LetzteGuteLesung, WegProtokolliert
    LetzteGuteLesung := A_TickCount
    WegProtokolliert := false       ; ein neuer Aussetzer darf wieder einmal ins Log
    Aktuell := a, Gesamt := g
    Fortschreiben()
    Anzeigen()
    Note("Gelesen um " . FormatTime(, "HH:mm:ss"))
}

; true = die Lesung darf uebernommen werden. Unauffaellige Lesungen (gleicher
; Gesamtwert, Stand nicht kleiner) gehen sofort durch, alles andere erst,
; wenn es zweimal hintereinander so gelesen wurde.
Bestaetigt(a, g) {
    global KandidatA, KandidatG

    if (Gesamt <= 0 || (g = Gesamt && a >= Aktuell)) {
        KandidatA := -1, KandidatG := -1
        return true
    }
    if (g = KandidatG && a >= KandidatA && a - KandidatA <= 5) {
        KandidatA := -1, KandidatG := -1
        return true
    }
    KandidatA := a, KandidatG := g
    Note(Format("Unsicher gelesen: {1}/{2} (bisher {3}/{4}) - warte auf Bestätigung", a, g, Aktuell, Gesamt))
    return false
}

; ---------------------------------------------------------------- Essen und Trinken

VorratLesen() {
    ; Modus 1 zuerst: Die deutsche Windows-OCR gibt alleinstehende kurze
    ; Zahlen nicht zurueck ("54%" allein ergibt nichts). Der Umbau stellt die
    ; Zeilen nebeneinander, dann steht jede Zahl neben einem Wort und wird
    ; gelesen. Gemessen: ohne Umbau kam nur "Essen Trinken", mit Umbau
    ; "Esse 54 Trinke 39".
    ;
    ; Beim Laufen wechselt der Hintergrund hinter der Anzeige staendig, mal
    ; hell, mal dunkel. Deshalb mehrere Anlaeufe mit unterschiedlicher
    ; Vergroesserung, bevor aufgegeben wird.
    e := -1, t := -1, roh := ""
    for versuch in [[1, 3, 0], [1, 5, 20], [0, 4, 20]] {
        antwort := FeldLesen(Vorrat, versuch[1], versuch[2], versuch[3])
        if (antwort = "BUSY")
            return                      ; spaeter noch einmal, nichts anzeigen
        if (antwort = "" || SubStr(antwort, 1, 4) = "ERR ")
            continue
        roh := antwort
        VorratZahlen(Normal(antwort), &e2, &t2)
        if (e < 0)
            e := e2
        if (t < 0)
            t := t2
        if (e >= 0 && t >= 0)
            break
    }

    if (roh != "")
        TxtRoh.Value := "OCR Vorrat: " . roh

    ; Woerter erkannt, aber keine Zahlen: dann ist der Ausschnitt zu eng
    ; geraten - die Prozentzahlen stehen ausserhalb.
    if (e < 0 && t < 0 && RegExMatch(roh, "i)Ess|Trink"))
        Note("Bereich zu eng - die Zahlen fehlen im Ausschnitt. Im Zahnrad größer ziehen.")

    VorratUebernehmen(e, t)
}

; Uebernimmt neue Werte, faengt aber Ausreisser ab.
VorratUebernehmen(e, t) {
    ; Die Kandidaten muessen hier stehen: ohne Deklaration waeren sie lokal,
    ; und die gemerkte Bestaetigung ginge bei jedem Aufruf verloren.
    global Essen, Trinken, VorratZeit, VorratKandidatE, VorratKandidatT

    e := VorratWert(e, Essen, &VorratKandidatE)
    t := VorratWert(t, Trinken, &VorratKandidatT)

    if (e >= 0)
        Essen := e
    if (t >= 0)
        Trinken := t
    if (e >= 0 || t >= 0)
        VorratZeit := A_TickCount

    ZeigeVorrat()      ; zeigt sonst den letzten Stand mit Altersangabe
}

; Ein Wert wird sofort genommen, wenn er zum bisherigen passt. Ein grosser
; Sprung muss erst von einer zweiten Lesung bestaetigt werden - Essen und
; Trinken fallen langsam, ein Satz von 54 auf 7 ist also ein Lesefehler.
VorratWert(neu, alt, &kandidat) {
    if (neu < 0 || neu > 100)
        return -1
    if (alt < 0 || Abs(neu - alt) <= VORRAT_SPRUNG) {
        kandidat := -1
        return neu
    }
    if (kandidat >= 0 && Abs(neu - kandidat) <= 5) {
        kandidat := -1
        return neu                  ; zweimal hintereinander aehnlich - stimmt wohl
    }
    kandidat := neu
    return -1
}

; Sucht die beiden Werte im erkannten Text. Der Umbau schneidet das
; Prozentzeichen ab und dabei auch den letzten Buchstaben des Wortes -
; deshalb wird nur auf "Esse" und "Trink" geprueft.
VorratZahlen(norm, &e, &t) {
    e := -1, t := -1

    ; Sicherheitsnetz: Steht dort "34 / 166", ist das die Zeile des Zaehlers
    ; und nicht die Vorratsanzeige. Solche Zahlen duerfen nie hier landen.
    if RegExMatch(norm, "\d+\s*[/|\\]\s*\d+")
        return
    if RegExMatch(norm, "i)Esse\w*\D{0,6}(\d{1,3})", &m)
        e := Integer(m[1])
    if RegExMatch(norm, "i)Tr[i1]nk\w*\D{0,6}(\d{1,3})", &m)
        t := Integer(m[1])
    if (e >= 0 && t >= 0)
        return

    ; Notnagel: die Zahlen der Reihe nach - erst Essen, dann Trinken.
    zahlen := []
    pos := 1
    while RegExMatch(norm, "\b(\d{1,3})\b", &m, pos) {
        wert := Integer(m[1])
        if (wert <= 100)
            zahlen.Push(wert)
        pos := m.Pos + m.Len
    }
    if (zahlen.Length < 2)
        return                  ; eine einzelne Zahl ist zu wenig, um zu raten
    if (e < 0)
        e := zahlen[1]
    if (t < 0)
        t := zahlen[2]
}

ZeigeVorrat() {
    if (!Vorrat.Kalibriert) {
        TxtVorrat.Value := "Essen/Trinken: nicht eingerichtet - im Zahnrad aufziehen"
        Farbe(TxtVorrat, FARB_GRAU)
        return
    }
    if (Essen < 0 && Trinken < 0) {
        TxtVorrat.Value := "Essen: -     Trinken: -"
        Farbe(TxtVorrat, FARB_GRAU)
        return
    }

    ; Beim Laufen ist die Anzeige oft kurz nicht lesbar. Dann bleibt der letzte
    ; Stand stehen - mit Altersangabe, damit klar ist, dass er nicht frisch ist.
    alter := VorratZeit ? (A_TickCount - VorratZeit) // 1000 : 0
    zusatz := (alter > 25) ? Format("   (vor {1} s)", alter) : ""

    TxtVorrat.Value := Format("Essen: {1}     Trinken: {2}{3}"
        , Essen < 0 ? "-" : Essen . " %", Trinken < 0 ? "-" : Trinken . " %", zusatz)

    ; Name darf NICHT knapp heissen: KNAPP ist die Konstante, und AutoHotkey
    ; unterscheidet nicht zwischen gross und klein - die Zuweisung haette die
    ; Konstante beim Lesen verdeckt.
    zuWenig := (Essen >= 0 && Essen <= KNAPP) || (Trinken >= 0 && Trinken <= KNAPP)
    if (alter > 25)
        Farbe(TxtVorrat, FARB_GRAU)
    else
        Farbe(TxtVorrat, zuWenig ? FARB_WARN : FARB_GUT)

    ; Nur einmal beim Unterschreiten melden: die rote Zeile zeigt es ohnehin,
    ; und alle 8 s neu geschrieben verdraengte die Meldung alles andere aus
    ; der Statuszeile (etwa "Ablauf abgebrochen").
    global KnappGemeldet
    if (!zuWenig)
        KnappGemeldet := false
    else if (alter <= 25 && !KnappGemeldet) {
        KnappGemeldet := true
        Note("Essen oder Trinken unter " . KNAPP . " Prozent.")
    }
}

; Textfarbe umstellen. Ohne Redraw bleibt die alte Farbe stehen.
Farbe(feld, hex) {
    try {
        feld.Opt("c" . hex)
        feld.Redraw()
    }
}

; ---------------------------------------------------------------- Fortschritt

; Kein Balken im Bild. Am Ende eines Auftrags blendet das HUD ihn aus, deshalb
; kommt die letzte Zahl oft nie an - dann entscheidet der zuletzt gelesene Stand.
OhneAnzeige() {
    global Fertig, WegProtokolliert

    if (Aktuell < 0) {
        Note("Zahlen nicht erkannt - im Zahnrad den Zähler neu aufziehen.")
        return
    }
    ; Nach Zeit, nicht nach Anzahl der Versuche: der Takt ist jetzt schnell,
    ; drei Fehlversuche waeren schon nach zwei Sekunden erreicht.
    fehlt := A_TickCount - LetzteGuteLesung
    rest := Fertigwert() - Aktuell

    ; Wie lange muss der Balken weg sein, bevor das als Schluss zaehlt? Die
    ; Grundkarenz allein reicht nicht: stand zuletzt 162/166, braucht das
    ; Spiel fuer die letzten vier Stueck noch rund zwanzig Sekunden. Ein
    ; Aussetzer der Erkennung sah frueher genauso aus wie ein Abschluss -
    ; deshalb wird die Zeit fuer den Rest dazugerechnet.
    noetig := WEG_MS + (rest > 0 ? Round(rest / SOLL_RATE * 1000) : 0)
    if (fehlt < noetig) {
        Note(Format("Balken nicht lesbar seit {1} s - letzter Stand {2}/{3}, warte noch {4} s"
            , Round(fehlt / 1000), Aktuell, Gesamt, Round((noetig - fehlt) / 1000)))
        return
    }
    if (Fertig)
        return                      ; schon gemeldet

    if (rest <= 0) {
        Melde("FERTIG - " . Aktuell . " / " . Gesamt . Zielzusatz())
    } else if (rest <= NAH_DRAN) {
        ; Balken weg und die Zeit fuer den Rest ist auch herum: die letzten
        ; Stueck hat das HUD nicht mehr gezeigt.
        Protokoll(Format("Balken seit {1} s weg, letzter Stand {2}/{3} (Rest {4}) - gilt als fertig."
            , Round(fehlt / 1000), Aktuell, Gesamt, rest))
        Melde(Format("FERTIG (Balken weg bei {1}/{2}, Rest {3}){4}", Aktuell, Gesamt, rest, Zielzusatz()))
    } else {
        ; Nur einmal je Aussetzer ins Log: diese Stelle laeuft bei jedem Takt,
        ; frueher stand dieselbe Zeile mehrmals pro Sekunde in der Mitschrift.
        if (!WegProtokolliert) {
            WegProtokolliert := true
            Protokoll(Format("Balken seit {1} s weg, letzter Stand {2}/{3} (Rest {4}) - kein Abschluss."
                , Round(fehlt / 1000), Aktuell, Gesamt, rest))
        }
        Note(Format("Kein Balken mehr bei {1}/{2} - Sammeln abgebrochen oder Bereich verdeckt.", Aktuell, Gesamt))
    }
}

; Meldet den Abschluss genau einmal: gruene Zeile in der Oberflaeche, kein Ton.
Melde(txt) {
    global Fertig
    Fertig := true
    TxtFertig.Value := Vorzeitig() ? Format("Ziel {1} erreicht", Fertigwert()) : "Fertig gesammelt"
    TxtFertig.Visible := true
    Note(txt . "   um " . FormatTime(, "HH:mm:ss"))
    Protokoll(Format("--- {1}  (Stand {2}/{3}, Ziel {4}, {5})"
        , txt, Aktuell, Gesamt, Fertigwert(), Vorzeitig() ? "vorzeitig" : "Auftrag durch"))

    ; Jetzt die Kette: Inventar auf, wegwerfen, zu, weiter sammeln. Jeder
    ; Schritt wartet erst seine Zeit ab - das Spiel raeumt nach dem letzten
    ; Stueck noch auf, ein Druck mitten in die Animation geht oft verloren.
    AblaufStarten(false)
}

; Schickt die eingestellte Taste einmal ins Spiel. Laeuft als Einmal-Timer,
; damit die Anzeige nicht so lange haengt wie die Wartezeit.
; Nach dem Sammeln laeuft eine feste Kette ab: Inventar auf, Gegenstand weg,
; Inventar zu, wieder sammeln. Jeder Schritt kann einzeln abgeschaltet werden
; und bringt seine eigene Wartezeit mit - gezaehlt ab dem Schritt davor.
;
; Die Kette haengt an Einmal-Timern statt an Sleep: ein Sleep in diesem Thread
; wuerde den Zaehler-Takt so lange anhalten, wie die Wartezeiten zusammen dauern.
AblaufStarten(test) {
    global Schritte, SchrittNr, SchrittTest

    Schritte := []
    ; Abbrechen nur, wenn das Spiel ueberhaupt noch sammelt. Beim vollen
    ; Auftrag ist es von selbst fertig - der Druck wuerde dort neu starten.
    ; Beim Testen kommt der Schritt mit, sonst laesst er sich nie pruefen.
    if (STOP_AN && (test || Vorzeitig()))
        Schritte.Push({ms: STOP_MS, art: "taste", taste: STOP_TASTE, name: "Sammeln abbrechen"})
    if (TASTE_AN)
        Schritte.Push({ms: TASTE_MS, art: "taste", taste: TASTE, name: "Inventar öffnen"})
    if (WURF_AN)
        Schritte.Push({ms: WURF_MS, art: "klick", taste: "", name: "Gegenstand wegwerfen"})
    if (ZU_AN)
        Schritte.Push({ms: ZU_MS, art: "taste", taste: ZU_TASTE, name: "Inventar schließen"})
    if (SAM_AN)
        Schritte.Push({ms: SAM_MS, art: "taste", taste: SAM_TASTE, name: "Sammeln starten"})

    if (!Schritte.Length) {
        Protokoll("Abbruch: kein Schritt eingeschaltet.")
        if (test)
            Note("Kein Schritt eingeschaltet - im Zahnrad einen Haken setzen.")
        return
    }

    namen := ""
    for sch in Schritte
        namen .= (namen = "" ? "" : ", ") . sch.name . " nach " . sch.ms . " ms"
    Protokoll("Ablauf" . (test ? " (Test)" : "") . " mit " . Schritte.Length . " Schritten: " . namen)

    ; Ohne aktives Spielfenster landet alles irgendwo - im Zweifel im Sammler
    ; selbst. Einmal vorn, gilt fuer die ganze Kette.
    if (TASTE_AKT && !FensterNachVorn()) {
        Schritte := []
        return
    }
    if (!TASTE_AKT)
        Protokoll("Fenster nicht geholt (Haken aus) - vorn ist: " . VornTitel())

    SchrittTest := test, SchrittNr := 0
    SchrittPlanen(Schritte[1].ms)
}

; Naechsten Schritt stellen und merken, wann er dran sein sollte.
SchrittPlanen(ms) {
    global SchrittFaellig
    ms := Max(ms, 1)
    SchrittFaellig := A_TickCount + ms
    SetTimer(AblaufWeiter, -ms)
}

; Kette anhalten - der Rest wuerde sonst in irgendein Fenster tippen.
AblaufAbbrechen(grund) {
    global Schritte
    Protokoll(Format("Abbruch bei Schritt {1}/{2}: {3}", SchrittNr, Schritte.Length, grund))
    Note("Ablauf abgebrochen: " . grund)
    SetTimer(AblaufWeiter, 0)
    Schritte := []
}

; Steht das Spiel noch vorn? Zwischen zwei Schritten kann sich viel tun -
; ein Klick daneben, das Startmenue, die Windows-Suche. Einmal geht es
; nochmal nach vorn zu holen; klappt das nicht, ist Schluss.
SpielNochVorn() {
    h := Spielfenster()
    if (!h)
        return !EigenesFenster(WinExist("A"))   ; ohne gemerktes Fenster: nur nicht in den Sammler
    if (SpielIstVorn(h))
        return true
    if (!TASTE_AKT)
        return !EigenesFenster(WinExist("A"))   ; holen abgeschaltet: wie bisher, nur nicht in den Sammler
    loop 2 {
        try {
            WinActivate("ahk_id " . h)
            WinWaitActive("ahk_id " . h, , 0.5)
        }
        if (SpielIstVorn(h)) {
            Protokoll("Spielfenster war weg und ist wieder vorn.")
            return true
        }
        Sleep(100)
    }
    return false
}

; Ist das Spiel vorn? Vollbild meldet sich nicht immer sauber als aktiv -
; deshalb reicht auch ein vorderes Fenster derselben Programmdatei.
SpielIstVorn(h) {
    if (WinActive("ahk_id " . h))
        return true
    try return (WinGetProcessName("A") = WinGetProcessName("ahk_id " . h))
    return false
}

AblaufWeiter() {
    Guard(AblaufSchritt)
}

AblaufSchritt() {
    global SchrittNr

    SchrittNr++
    if (SchrittNr > Schritte.Length)
        return
    sch := Schritte[SchrittNr]

    ; Kommt ein Schritt viel zu spaet (Skript haengte, Rechner beschaeftigt),
    ; passt der Zustand im Spiel nicht mehr zur Kette - frueher kam Schritt 2
    ; einmal 83 s nach Schritt 1 und landete in der Windows-Suche.
    spaet := A_TickCount - SchrittFaellig
    if (spaet > SCHRITT_VERSPAETUNG)
        return AblaufAbbrechen(Format("{1} kam {2} s zu spät", sch.name, Round(spaet / 1000)))

    if (!SpielNochVorn())
        return AblaufAbbrechen(sch.name . " - Spielfenster nicht vorn, vorn ist: " . VornTitel())

    if (sch.art = "klick")
        WurfJetzt(sch.name)
    else
        TasteJetzt(sch.taste, sch.name)

    if (SchrittNr < Schritte.Length)
        SchrittPlanen(Schritte[SchrittNr + 1].ms)
}

; Von Hand ausgeloest: dieselbe Kette, nur mit Hinweis in der Statuszeile.
TasteTesten() {
    AblaufStarten(true)
}

; Das Spielfenster, so gut es zu finden ist: erst ueber den Zaehler, dann
; ueber Essen/Trinken. Wer nur einen der beiden Bereiche ueber dem Spiel
; aufgezogen hat, hat trotzdem ein gemerktes Fenster.
Spielfenster() {
    h := QuellFenster(Zaehler)
    if (!h)
        h := QuellFenster(Vorrat)
    return h
}

; Holt das Spiel nach vorn. Ist kein Fenster gemerkt, gehen die Tasten an
; das, was gerade vorn ist - nur nicht an den Sammler selbst, denn dort
; waere der Tastendruck sicher verkehrt.
FensterNachVorn() {
    h := Spielfenster()
    if (!h) {
        if (EigenesFenster(WinExist("A"))) {
            Protokoll("Abbruch: kein Spielfenster gemerkt, und vorn steht der Sammler selbst.")
            Note("Kein Spielfenster gemerkt und der Sammler ist vorn - Ablauf abgebrochen."
                . " Im Zahnrad den Zähler über dem Spiel aufziehen.")
            return false
        }
        Protokoll("Kein Spielfenster gemerkt - Tasten gehen an: " . VornTitel())
        Note("Kein Spielfenster gemerkt - Tasten gehen an das Fenster, das gerade vorn ist.")
        return true
    }

    ; Vollbild-Spiele brauchen manchmal zwei Anlaeufe: Windows laesst einen
    ; Wechsel nicht immer beim ersten Mal zu. Deshalb bis zu drei Versuche
    ; statt einem - ein einzelner Fehlschlag hat frueher die ganze Kette
    ; verschluckt, und genau das sah nach "manchmal tippt er nicht" aus.
    loop 3 {
        try {
            WinActivate("ahk_id " . h)
            WinWaitActive("ahk_id " . h, , 0.7)
        }
        if (WinActive("ahk_id " . h)) {
            if (A_Index > 1)
                Protokoll("Spielfenster erst im " . A_Index . ". Anlauf vorn.")
            return true
        }
        Sleep(150)
    }

    ; Es kam nicht nach vorn. Steht trotzdem nicht der Sammler vorn, ist das
    ; vorderste Fenster hoechstwahrscheinlich das Spiel selbst (Vollbild
    ; meldet sich nicht immer sauber als aktiv) - dann lieber tippen als
    ; nichts tun.
    if (!EigenesFenster(WinExist("A"))) {
        Protokoll("Spielfenster kam nicht nach vorn - tippe trotzdem, vorn ist: " . VornTitel())
        Note("Spielfenster kam nicht nach vorn - Tasten gehen an: " . VornTitel())
        return true
    }

    Protokoll("Abbruch: Spielfenster kam nicht nach vorn, vorn ist der Sammler.")
    Note("Spielfenster kam nicht nach vorn - Ablauf abgebrochen.")
    return false
}

; Titel des Fensters, das gerade vorn ist - fuer Meldung und Mitschrift.
VornTitel() {
    try {
        t := WinGetTitle("A")
        return (t = "") ? "(ohne Titel)" : SubStr(t, 1, 60)
    }
    return "(unbekannt)"
}

; Gehoert das Fenster zum Sammler selbst (Hauptfenster, Einstellungen,
; Spiegel, Rahmen)? Dann ist es kein Ziel fuer Tastendruecke.
EigenesFenster(h) {
    if (!h)
        return false
    if (h = Ui.Hwnd || h = Ein.Hwnd)
        return true
    return FeldZuFenster(h) ? true : false
}

; Ein Tastendruck ins Spiel. SendEvent statt SendInput, und die Taste rund
; 60 ms halten: Spiele ueberspringen einen zu kurzen Druck haeufig.
TasteJetzt(taste, name) {
    text := SendeSyntax(taste)
    if (text = "") {
        Protokoll("Schritt " . SchrittNr . " uebersprungen: " . name . " hat keine Taste.")
        Note(name . ": keine Taste eingestellt - im Zahnrad eine waehlen.")
        return
    }
    SetKeyDelay(30, 60)
    SendEvent(text)
    Ablaufmeldung(name . ": Taste " . taste)
    Protokoll(Format("Schritt {1}/{2}: {3} - Taste {4} an {5}"
        , SchrittNr, Schritte.Length, name, taste, VornTitel()))
}

; Ein Rechtsklick auf den gemerkten Punkt - damit wirft das Spiel den
; Gegenstand weg, der dort im Inventar liegt.
WurfJetzt(name := "Gegenstand wegwerfen") {
    if (!WurfPunkt(&x, &y)) {
        Protokoll("Schritt " . SchrittNr . " uebersprungen: kein Wegwerf-Punkt gesetzt.")
        Note("Kein Wegwerf-Punkt gesetzt - im Zahnrad auf 'Wegwerf-Punkt setzen'.")
        return
    }

    MouseGetPos(&altX, &altY)
    SendMode("Event")                ; Spiele verschlucken zu schnelle Klicks
    SetMouseDelay(40)

    ; Geschwindigkeit 0 heisst: ohne Zwischenschritte, der Zeiger steht sofort
    ; auf dem Punkt. Jede Zwischenbewegung wuerde im Spiel nur wackeln.
    MouseMove(x, y, 0)
    Sleep(120)                       ; das Spiel muss den Gegenstand erst anleuchten
    Click("Right")                   ; ohne Koordinaten: die Maus steht schon da
    Sleep(60)
    MouseMove(altX, altY, 0)         ; und zurueck, wo sie vorher stand
    Ablaufmeldung(Format("{1}: Rechtsklick auf x{2} y{3}", name, x, y))
    Protokoll(Format("Schritt {1}/{2}: {3} - Rechtsklick x{4} y{5} an {6}"
        , SchrittNr, Schritte.Length, name, x, y, VornTitel()))
}

; Eine Zeile pro Schritt in die Statuszeile: welcher von wie vielen, was er
; getan hat, und wann.
Ablaufmeldung(txt) {
    Note(Format("{1}Schritt {2}/{3} - {4}   um {5}"
        , SchrittTest ? "Test: " : "", SchrittNr, Schritte.Length, txt, FormatTime(, "HH:mm:ss")))
}

; Wo der Klick hin soll. Ist das Spielfenster da, zaehlt die gemerkte Lage
; im Fenster - dann stimmt der Punkt auch nach dem Verschieben. Sonst bleibt
; der Bildschirmpunkt von damals. false = nie kalibriert.
WurfPunkt(&x, &y) {
    x := WURF_X, y := WURF_Y
    if (WURF_X < 0)
        return false
    if (WURF_REL) {
        h := Spielfenster()
        if (h) {
            ecke := Buffer(8, 0)
            if (DllCall("user32\ClientToScreen", "ptr", h, "ptr", ecke)) {
                x := NumGet(ecke, 0, "int") + WURF_FX
                y := NumGet(ecke, 4, "int") + WURF_FY
            }
        }
    }
    return true
}

; Zeigt den Punkt kurz als kleines Quadrat - zum Nachschauen, ob er sitzt.
WurfPunktZeigen() {
    if (!WurfPunkt(&x, &y)) {
        Note("Kein Wegwerf-Punkt gesetzt - erst im Zahnrad setzen.")
        return
    }
    RahmenZeigen(x - 12, y - 12, 24, 24)
    Note(Format("Wegwerf-Punkt liegt bei x{1} y{2}", x, y))
    SetTimer(RahmenAus, -1500)
}

; Kalibrierung: das Inventar muss im Spiel offen sein, dann faengt ein
; halbdurchsichtiger Schleier den naechsten Klick ab, statt ihn ins Spiel
; zu lassen - sonst wuerde beim Einstellen schon etwas weggeworfen.
WurfPunktSetzen() {
    global Markiert, ZiehEingabe, WURF_X, WURF_Y, WURF_REL, WURF_FX, WURF_FY

    if (Markiert)
        return
    Markiert := true
    einWar := WinExist("ahk_id " . Ein.Hwnd) ? true : false
    if (einWar)
        EinstellungenVerstecken(false)
    ZiehEingabe := InputHook("B L0")
    ZiehEingabe.KeyOpt("{Escape}", "E")
    ZiehEingabe.Start()
    schleier := 0
    try {
        schleier := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "Auswahl-Schleier")
        schleier.BackColor := "101018"
        schleier.SetFont("s13 Bold", "Segoe UI")
        schleier.MarginX := 0, schleier.MarginY := 0
        schleier.Add("Text", Format("x0 y{1} w{2} Center cWhite BackgroundTrans", A_ScreenHeight // 5, A_ScreenWidth)
            , "Das Inventar muss im Spiel offen sein."
            . "`n`nJetzt auf den Gegenstand klicken, der weggeworfen werden soll."
            . "`n`nEsc bricht ab")
        schleier.Show(Format("x0 y0 w{1} h{2} NoActivate", A_ScreenWidth, A_ScreenHeight))
        WinSetTransparent(150, schleier)

        if !PunktHolen(&px, &py) {
            try schleier.Destroy()
            return Note("Abgebrochen - Wegwerf-Punkt unverändert.")
        }
        try schleier.Destroy()

        WURF_X := px, WURF_Y := py
        WURF_REL := false, WURF_FX := 0, WURF_FY := 0

        ; Lage im Spielfenster merken, damit ein verschobenes Fenster den
        ; Punkt nicht entwertet. Ohne bekanntes Fenster bleibt der Bildschirmpunkt.
        h := Spielfenster()
        if (h) {
            ecke := Buffer(8, 0)
            if (DllCall("user32\ClientToScreen", "ptr", h, "ptr", ecke)) {
                WURF_FX := px - NumGet(ecke, 0, "int")
                WURF_FY := py - NumGet(ecke, 4, "int")
                WURF_REL := true
            }
        }
        WurfPunktSpeichern()
        ZeigeWurf()
        RahmenZeigen(px - 12, py - 12, 24, 24)
        SetTimer(RahmenAus, -1500)
        Note(Format("Wegwerf-Punkt gesetzt: x{1} y{2}{3}", px, py
            , WURF_REL ? " (Lage im Spielfenster gemerkt)" : " (nur Bildschirm - kein Spielfenster erkannt)"))
    } finally {
        try ZiehEingabe.Stop()
        try schleier.Destroy()
        Markiert := false
        if (einWar)
            EinstellungenZeigen()
    }
}

; Wartet auf einen einzelnen Klick. false = Esc oder nach einer Minute nichts.
PunktHolen(&px, &py) {
    px := 0, py := 0
    ende := A_TickCount + 60000
    while !GetKeyState("LButton", "P") {
        if (Abgebrochen() || A_TickCount > ende)
            return false
        Sleep(15)
    }
    MouseGetPos(&px, &py)
    while GetKeyState("LButton", "P")    ; Loslassen abwarten, sonst zieht der Klick weiter
        Sleep(15)
    return true
}

; Rechnet die Schreibweise des Hotkey-Feldes ("^i", "F5", "Numpad0") in das um,
; was Send versteht ("^i", "{F5}", "{Numpad0}"). "" = nichts Brauchbares drin.
SendeSyntax(hk) {
    hk := Trim(hk)
    if (hk = "")
        return ""
    mods := "", i := 1
    while (i < StrLen(hk) && InStr("^!+#", SubStr(hk, i, 1))) {
        mods .= SubStr(hk, i, 1)
        i++
    }
    taste := SubStr(hk, i)
    if (taste = "")
        return ""
    if (StrLen(taste) > 1 || InStr("^!+#{}", taste))
        taste := "{" . taste . "}"
    return mods . taste
}

; Blendet die Fertig-Meldung wieder aus, sobald ein neuer Auftrag laeuft.
Fertigmeldung_Aus() {
    global Fertig
    Fertig := false
    TxtFertig.Visible := false
}

; Ab diesem Stand gilt der Auftrag als fertig. ZIEL = 0 heisst: der ganze
; Auftrag. Ein Ziel groesser als Gesamt waere nie zu erreichen und wird
; deshalb auf Gesamt gestutzt - so bleibt ein zu hoch eingetragener Wert
; harmlos, statt die Fertig-Meldung ganz zu verhindern.
Fertigwert() {
    if (Gesamt <= 0)
        return Gesamt
    return (ZIEL > 0 && ZIEL < Gesamt) ? ZIEL : Gesamt
}

; true, solange das Spiel beim Fertigmelden noch weitersammelt - also wenn
; ein eigenes Ziel vor dem Ende des Auftrags greift.
Vorzeitig() {
    return (Gesamt > 0 && Fertigwert() < Gesamt)
}

; Haengt " (Ziel 158)" an, aber nur wenn wirklich vorzeitig abgebrochen wird.
Zielzusatz() {
    z := Fertigwert()
    return (Gesamt > 0 && z < Gesamt) ? Format(" (Ziel {1})", z) : ""
}

; Pflegt Startpunkt, Verlauf und Stillstandserkennung.
Fortschreiben() {
    global StartZeit, StartWert, LetzterWert, LetzteAenderung, Verlauf, Fertig
    jetzt := A_TickCount

    if (StartWert < 0 || Aktuell < LetzterWert) {   ; erster Wert oder neuer Auftrag
        Reset(false)
        StartZeit := jetzt, StartWert := Aktuell
    }

    if (Aktuell != LetzterWert) {
        LetzterWert := Aktuell
        LetzteAenderung := jetzt
        Verlauf.Push([jetzt, Aktuell])
        if (Verlauf.Length > 30)
            Verlauf.RemoveAt(1)
    }

    if (Aktuell >= Fertigwert() && !Fertig)
        Melde("FERTIG - " . Aktuell . " / " . Gesamt . Zielzusatz())
    else if (Aktuell < Fertigwert() && Fertig)
        Fertigmeldung_Aus()
}

Reset(melden := true) {
    global StartZeit, StartWert, LetzterWert, LetzteAenderung, Verlauf
    StartZeit := A_TickCount, StartWert := Aktuell
    LetzterWert := Aktuell, LetzteAenderung := A_TickCount
    Verlauf := []
    Fertigmeldung_Aus()
    if (melden)
        Note("Zählung zurückgesetzt.")
}

; Gemessene Rate in Stueck pro Sekunde, sonst -1.
IstRate() {
    if (Verlauf.Length < 2)
        return -1
    erst := Verlauf[1], letzt := Verlauf[Verlauf.Length]
    dt := (letzt[1] - erst[1]) / 1000
    ds := letzt[2] - erst[2]
    return (dt > 5 && ds > 0) ? ds / dt : -1
}

Anzeigen() {
    ziel := Fertigwert()
    rest := ziel - Aktuell

    TxtStand.Value := Format("{1}  /  {2}", Aktuell, Gesamt)
    TxtRest.Value := "Rest: " . rest . " Stück" . (ziel < Gesamt ? Format("  (bis {1})", ziel) : "")

    ZeigeSollzeile(rest)

    r := IstRate()
    if (r > 0) {
        TxtEtaIst.Value := "Restzeit (gemessen): " . Dauer(rest / r)
        TxtRate.Value := Format("Rate: {1:0.2f} Stk/s  ({2:0.1f} Stk/min)", r, r * 60)
    } else {
        TxtEtaIst.Value := "Restzeit (gemessen): sammle noch Messwerte"
        TxtRate.Value := "Rate: -"
    }

    lauf := (A_TickCount - StartZeit) / 1000
    gemacht := Aktuell - StartWert
    TxtLauf.Value := Format("Laufzeit: {1}   davon gesammelt: {2}", Dauer(lauf), gemacht)

    TabakKastenRechnen()

    still := (A_TickCount - LetzteAenderung) / 1000
    if (Aktuell < ziel && still > STILL_S)
        Note(Format("Kein Fortschritt seit {1} s - Sammeln unterbrochen?", Round(still)))
}

; Beschriftung und Wert der vorgegebenen Restzeit. rest < 0 heisst: noch
; nichts gelesen - dann steht nur die Rechengrundlage da.
ZeigeSollzeile(rest) {
    TxtEtaSoll.Value := Format("Restzeit ({1} Stk / {2} s): {3}"
        , PRO_TAKT, Round(TAKT), rest < 0 ? "-" : Dauer(rest / SOLL_RATE))
}

Dauer(sek) {
    if (sek < 0)
        return "-"
    sek := Round(sek)
    if (sek < 60)
        return sek . " s"
    m := sek // 60, s := Mod(sek, 60)
    if (m < 60)
        return Format("{1} min {2:02} s", m, s)
    return Format("{1} h {2:02} min", m // 60, Mod(m, 60))
}

; ---------------------------------------------------------------- PowerShell-Teil
;
; Wird beim Start nach %TEMP%\sammler_ocr.ps1 geschrieben und dort gestartet.
; Er nimmt den Bildausschnitt auf und laesst die Windows-Texterkennung darauf los.
; Aenderungen also hier machen, nicht an der Datei im Temp-Ordner.

PS_Quelltext() {
    return "
(`
<#
    OCR-Dienst fuer Sammler.ahk

    Zwei Betriebsarten:
      1) Einzellesung  ->  powershell -File ocr.ps1 -X 830 -Y 975 -W 400 -H 40
      2) Dauerdienst   ->  powershell -File ocr.ps1 -Server -Out <datei>
         Liest Zeilen "X Y W H" von StdIn und schreibt den erkannten Text
         nach <datei>. Spart die ~1,5 s Startzeit pro Lesung.

    Ein vorhandenes Bild statt Bildschirm:  -Image <pfad>   (zum Testen)
#>
param(
    [int]$X = 0, [int]$Y = 0, [int]$W = 0, [int]$H = 0,
    [string]$Image = "",
    [string]$Out = "",
    [string]$Cmd = "",
    [int]$Scale = 3,
    [int]$Rand = 0,
    [int]$Modus = 0,
    [int]$Watch = 0,
    [switch]$Server,
    [switch]$KeepShot)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Runtime.WindowsRuntime

# Schwellwert-Filter als kompilierter Code: eine PowerShell-Schleife ueber
# ~1 Mio. Pixel dauert Sekunden, das hier braucht Millisekunden.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class SammlerImg {
    // Schrift ist weiss, Hintergruende sind dunkel ODER kraeftig farbig
    // (orange/blaue Kacheln). Deshalb zaehlt der KLEINSTE Farbkanal: bei Weiss
    // sind alle drei hoch, bei jeder Farbe ist mindestens einer niedrig.
    // Reine Helligkeit wuerde die orange Kachel (Helligkeit 147) fast wie
    // Schrift behandeln und die Buchstaben verschmieren.
    public static void Threshold(Bitmap bmp, int cut) {
        Rectangle r = new Rectangle(0, 0, bmp.Width, bmp.Height);
        BitmapData d = bmp.LockBits(r, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int n = Math.Abs(d.Stride) * bmp.Height;
        byte[] buf = new byte[n];
        Marshal.Copy(d.Scan0, buf, 0, n);
        for (int i = 0; i < n; i += 4) {
            int min = buf[i];
            if (buf[i+1] < min) min = buf[i+1];
            if (buf[i+2] < min) min = buf[i+2];
            byte v = min > cut ? (byte)0 : (byte)255;
            buf[i] = v; buf[i+1] = v; buf[i+2] = v; buf[i+3] = 255;
        }
        Marshal.Copy(buf, 0, d.Scan0, n);
        bmp.UnlockBits(d);
    }

    // Die deutsche Windows-OCR wirft alleinstehende kurze Zahlen weg:
    // "54%" allein ergibt nichts, "Essen 54" wird gelesen. Deshalb werden
    // hier alle Textzeilen des Ausschnitts NEBENEINANDER gesetzt und von
    // jeder Zeile die letzte Zeichengruppe (das Prozentzeichen) entfernt.
    // Aus zwei Kacheln wird so eine Zeile "Esse 54 Trinke 39" - gemessen:
    // ohne diesen Umbau kam nur "Essen Trinken" zurueck.
    public static Bitmap EineZeile(Bitmap src, int luecke) {
        int w = src.Width, h = src.Height;
        Rectangle r = new Rectangle(0, 0, w, h);
        BitmapData d = src.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = Math.Abs(d.Stride);
        byte[] buf = new byte[stride * h];
        Marshal.Copy(d.Scan0, buf, 0, buf.Length);
        src.UnlockBits(d);

        // Zeilenbaender: Bildzeilen, in denen ueberhaupt Schrift steht
        List<int[]> baender = new List<int[]>();
        int start = -1;
        for (int y = 0; y < h; y++) {
            bool tinte = false;
            for (int x = 0; x < w; x++) {
                if (buf[y * stride + x * 4] < 128) { tinte = true; break; }
            }
            if (tinte && start < 0) start = y;
            else if (!tinte && start >= 0) {
                if (y - start >= 6) baender.Add(new int[] { start, y });
                start = -1;
            }
        }
        if (start >= 0 && h - start >= 6) baender.Add(new int[] { start, h });
        if (baender.Count < 2) return null;      // eine Zeile braucht keinen Umbau

        // je Band: linker Rand, rechter Rand, Beginn der letzten Luecke
        List<int[]> teile = new List<int[]>();
        int hoehe = 0;
        for (int i = 0; i < baender.Count; i++) {
            int o = baender[i][0], u = baender[i][1];
            int links = -1, rechts = -1, letzte = -1, letzteLuecke = -1;
            for (int x = 0; x < w; x++) {
                bool tinte = false;
                for (int y = o; y < u; y++) {
                    if (buf[y * stride + x * 4] < 128) { tinte = true; break; }
                }
                if (tinte) {
                    if (links < 0) links = x;
                    rechts = x;
                    if (letzte >= 0 && x - letzte > 3) letzteLuecke = letzte + 1;
                    letzte = x;
                }
            }
            if (links < 0) continue;

            // Das Prozentzeichen abschneiden. Steht es frei, faellt die letzte
            // Zeichengruppe weg. Klebt es am Nachbarn - in der Spielschrift
            // haengen "8" und "%" zusammen -, wuerde das die Ziffer
            // mitnehmen (aus "98%" wurde "9"). Dann wird stattdessen fest
            // etwa eine Zeichenbreite abgeschnitten.
            int zh = u - o;                       // Hoehe dieser Zeile
            int letzteBreite = rechts + 1 - letzteLuecke;
            int ende;
            if (letzteLuecke > links && letzteBreite <= zh * 13 / 10)
                ende = letzteLuecke;
            else
                ende = rechts + 1 - zh * 12 / 10;

            // Was jetzt noch ganz rechts steht und sehr schmal ist, ist ein
            // Rest des Prozentzeichens - der stoert die Erkennung ("98'").
            while (ende > links + 2) {
                bool leer = true;
                for (int y = o; y < u && leer; y++)
                    if (buf[y * stride + (ende - 1) * 4] < 128) leer = false;
                if (leer) break;
                int blockBreite = 0;
                for (int x = ende - 1; x >= links; x--) {
                    bool tinte = false;
                    for (int y = o; y < u && !tinte; y++)
                        if (buf[y * stride + x * 4] < 128) tinte = true;
                    if (!tinte) break;
                    blockBreite++;
                }
                if (blockBreite >= zh * 35 / 100) break;   // breit genug = Ziffer
                ende -= blockBreite;
                while (ende > links + 2) {                 // Luecke davor ueberspringen
                    bool tinte = false;
                    for (int y = o; y < u && !tinte; y++)
                        if (buf[y * stride + (ende - 1) * 4] < 128) tinte = true;
                    if (tinte) break;
                    ende--;
                }
            }
            if (ende <= links + 2) ende = rechts + 1;
            teile.Add(new int[] { links, ende, o, u });
            if (u - o > hoehe) hoehe = u - o;
        }
        if (teile.Count < 2) return null;

        int breite = luecke;
        for (int i = 0; i < teile.Count; i++) breite += (teile[i][1] - teile[i][0]) + luecke;

        Bitmap ziel = new Bitmap(breite, hoehe + 2 * luecke);
        using (Graphics g = Graphics.FromImage(ziel)) {
            g.Clear(Color.White);
            int x2 = luecke;
            for (int i = 0; i < teile.Count; i++) {
                int bb = teile[i][1] - teile[i][0];
                int hh = teile[i][3] - teile[i][2];
                Rectangle quelle = new Rectangle(teile[i][0], teile[i][2], bb, hh);
                Rectangle ablage = new Rectangle(x2, luecke, bb, hh);
                g.DrawImage(src, ablage, quelle, GraphicsUnit.Pixel);
                x2 += bb + luecke;
            }
        }
        return ziel;
    }
}
'@ -ReferencedAssemblies System.Drawing

# --- WinRT-Await-Helfer (Windows PowerShell 5.1 kann IAsyncOperation nicht direkt) ---
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($op, $type) {
    $task = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $task.Wait(-1) | Out-Null
    $task.Result
}

[Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (-not $engine) { throw "Keine OCR-Sprache installiert (Einstellungen > Zeit und Sprache)." }

$shotPath = Join-Path $env:TEMP "sammler_shot.png"

function Get-Shot([int]$x, [int]$y, [int]$w, [int]$h, [int]$sc = 3, [int]$rd = 0, [int]$modus = 0) {
    # sc: kleine HUD-Schrift vergroessern, sonst erkennt die OCR wenig.
    # rd: Rand rundherum. Die Windows-OCR laesst kurze Zahlen am Bildrand
    #     gern aus; mit Luft drumherum kommen sie haeufiger durch.
    if ($sc -lt 1) { $sc = 3 }
    $raw = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($raw)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()

    $big = New-Object System.Drawing.Bitmap(($w * $sc + 2 * $rd), ($h * $sc + 2 * $rd))
    $g2 = [System.Drawing.Graphics]::FromImage($big)
    $g2.Clear([System.Drawing.Color]::Black)      # wird vom Schwellwert zu Weiss
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.DrawImage($raw, $rd, $rd, ($w * $sc), ($h * $sc))
    $g2.Dispose()
    $raw.Dispose()

    [SammlerImg]::Threshold($big, 150)

    # Modus 1: Zeilen nebeneinander setzen (fuer Anzeigen wie "Essen 54%")
    if ($modus -eq 1) {
        $eine = [SammlerImg]::EineZeile($big, 40)
        if ($eine) { $big.Dispose(); $big = $eine }
    }

    $big.Save($shotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $big.Dispose()
    return $shotPath
}

function Read-Text([string]$path) {
    $file    = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($path)) ([Windows.Storage.StorageFile])
    $stream  = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
    $bitmap  = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
    $res     = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
    $stream.Dispose()
    return (($res.Lines | ForEach-Object { $_.Text }) -join " ")
}

function Write-Result([string]$text) {
    if (-not $Out) { Write-Output $text; return }
    # Erst in eine Nebendatei schreiben, dann umbenennen: sonst liest das
    # Skript die Datei mitten im Schreibvorgang und bekommt einen Fehler.
    $tmp = $Out + ".tmp"
    Set-Content -Path $tmp -Value $text -Encoding UTF8 -Force
    Move-Item -Path $tmp -Destination $Out -Force
}

if ($Server) {
    if (-not $Cmd) { throw "-Cmd <Auftragsdatei> fehlt." }

    # Auftraege kommen als Datei, nicht ueber StdIn: eine Pipe von AutoHotkey
    # nach PowerShell wird nicht zuverlaessig durchgereicht.
    Write-Result "0 READY"
    # Die Lebendpruefung kostet spuerbar Zeit, deshalb hoechstens alle zwei
    # Sekunden. Nach Auftraegen wird dafuer alle 10 ms geschaut - das spart
    # bei jeder Lesung ein paar Dutzend Millisekunden.
    $naechstePruefung = [DateTime]::UtcNow
    while ($true) {
        if ($Watch -gt 0 -and [DateTime]::UtcNow -ge $naechstePruefung) {
            $naechstePruefung = [DateTime]::UtcNow.AddSeconds(2)
            if (-not (Get-Process -Id $Watch -ErrorAction SilentlyContinue)) {
                break                              # AutoHotkey ist weg -> mitgehen
            }
        }
        if (-not (Test-Path $Cmd)) { Start-Sleep -Milliseconds 10; continue }

        $line = ""
        try { $line = (Get-Content $Cmd -Raw -ErrorAction Stop).Trim() } catch { Start-Sleep -Milliseconds 20; continue }
        Remove-Item $Cmd -Force -ErrorAction SilentlyContinue

        if ($line -eq "") { continue }
        if ($line -eq "QUIT") { break }
        # Aufbau: Nummer x y b h Vergroesserung Rand Modus
        # Die Nummer kommt in die Antwort zurueck, damit das Skript eine
        # verspaetete Antwort nicht der naechsten Lesung zuordnet.
        $p = $line -split '\s+'
        if ($p.Count -lt 5) { continue }
        $nr = $p[0]
        $sc = 3; $rd = 0
        if ($p.Count -ge 6) { $sc = [int]$p[5] }
        if ($p.Count -ge 7) { $rd = [int]$p[6] }
        $modus = 0
        if ($p.Count -ge 8) { $modus = [int]$p[7] }
        try {
            $t = Read-Text (Get-Shot ([int]$p[1]) ([int]$p[2]) ([int]$p[3]) ([int]$p[4]) $sc $rd $modus)
            # Nie leer antworten - das Skript wartet sonst bis zum Zeitlimit.
            if ($t.Trim() -eq "") { $t = "LEER" }
            Write-Result ($nr + " " + $t)
        } catch {
            Write-Result ($nr + " ERR " + $_.Exception.Message)
        }
    }
    exit
}

# Einzellesung
if ($Image) { Write-Result (Read-Text $Image); exit }
if ($W -le 0 -or $H -le 0) { throw "Breite/Hoehe fehlen." }
Write-Result (Read-Text (Get-Shot $X $Y $W $H $Scale $Rand $Modus))
if (-not $KeepShot) { Remove-Item $shotPath -ErrorAction SilentlyContinue }
)"
}
