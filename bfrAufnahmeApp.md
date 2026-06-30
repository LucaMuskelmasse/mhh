# bfrAufnahmeApp — Dokumentation

Zentrale MATLAB-App zur Steuerung des **BFR-Versuchs**: Sie liest zyklisch die
Temperatur eines **Omega HH806AWE**-Thermometers (2 Kanäle) aus und nimmt mit
zwei **Dino-Lite**-Mikroskopkameras automatisch Bilder auf, sobald sich die
Temperatur einer Seite ändert. Damit wird der **Formgedächtniseffekt** eines
Materials (Inlay) beim Aufwärmen und Abkühlen Bild für Bild dokumentiert.

> Diese Datei ist die Referenz, falls der Gesprächskontext verloren geht.
> Sie beschreibt **Zweck, Architektur, alle Funktionen, das Datenformat und die
> nicht-offensichtlichen Designentscheidungen** (besonders die zwei großen
> Stolperfallen: das `preview()`-Speicherleck und die instabile USB-Enumeration).

---

## 1. Dateien im Repo

| Datei | Zweck |
|---|---|
| `bfrAufnahmeApp.m` | Die komplette App (eine `.m`-Datei, alles inklusive). |
| `listKameras.m` | Diagnose: listet winvideo-Geräte (ID + Name) und DNX64-Port-Pfade auf. Hilft, die Kamera-`CONFIG` zu kalibrieren. |
| `testKameras.m` | Diagnose: öffnet die Dino-Lites einzeln/gemeinsam **ohne** die App, um Geräte-/USB-Probleme vom App-Code zu trennen. |
| `bfrAufnahmeApp.md` | Diese Dokumentation. |
| `buildBfrAufnahmeApp.m` | Build-Skript: erstellt aus der App eine eigenständige Windows-`.exe` (§16). |
| `camAssign.mat` | **Zur Laufzeit** erzeugt (neben dem Skript): gespeicherte Kamera-Zuweisung des Einrichtungs-Wizards (USB-Port-Pfad je Kamera). Nicht im Repo, maschinenspezifisch. |

Die App ist **eigenständig**: Alle Hilfsfunktionen (`getHH806Temp`,
`captureSingleFrameSide`, `openDinoLiteCameras`, Dekodierung, Bildstempel …)
liegen als lokale Funktionen am Ende von `bfrAufnahmeApp.m`.

---

## 2. Voraussetzungen (Hard- & Software)

- **MATLAB** (entwickelt/getestet mit **R2025a**) mit:
  - **Image Acquisition Toolbox** (`videoinput`, `preview`, `getsnapshot`, `imaqhwinfo`, `imaqreset`) — Pflicht.
  - **Computer Vision Toolbox** (`insertText`) — *optional*; ohne sie greift ein eigener Bildstempel-Fallback (siehe §9).
  - `serialport` (Industrial-Comm/Instrument-Funktionalität, in MATLAB-Basis ab R2019b).
- **Dino-Lite-Treiber** + **`DNX64.dll`** und Header **`DNX64forMatlab.h`** müssen im MATLAB-Pfad liegen (für LED-Steuerung und Geräteerkennung).
- **Omega HH806AWE** über USB-Seriell-Kabel (Protokoll 19200 Baud, even parity, 8 Datenbits, 1 Stoppbit).
- Plattform: **Windows** (wegen `DNX64.dll`, winvideo, `setpref`).

**Start:** in MATLAB einfach `bfrAufnahmeApp` aufrufen (kein Argument).

---

## 3. Versuchsablauf (fachlich)

1. **Aufwärmvorgang** (Start-Zustand): Es wird ein Bild gemacht, sobald die
   Temperatur einer Seite **über** den letzten Auslösewert **steigt**.
2. **Abkühlvorgang**: Die Auslösung dreht sich um — Bild bei **fallender**
   Temperatur. Aktivierung entweder
   - **manuell** über den Umschaltknopf „Abkühlvorgang" **oder**
   - **automatisch**, sobald beide Kanäle die Schwelle **„Abkühlen ab"** (Default 80 °C) erreichen.
3. **Automatischer Stopp**:
   - Aufwärmen: beide Kanäle ≥ **Stopp Aufw.** (Default 90 °C) → Lauf endet.
   - Abkühlen: beide Kanäle ≤ **Stopp Abk.** (Default 37 °C) → Lauf endet.
4. **Deadband / Programmablaufplan** (siehe §6): legt temperaturabhängig fest,
   *wie groß* die Temperaturänderung sein muss, bevor ein neues Bild ausgelöst
   wird (feine Schritte im Formgedächtnisbereich, grobe außerhalb).

Typischer Default-Ablauf: Aufwärmen → bei 80 °C automatisch Abkühlen → bei 37 °C
Stopp. (Damit greift „Stopp Aufw." 90 °C im Default nur als Sicherheits-Obergrenze,
weil 80 < 90.)

---

## 4. GUI-Aufbau

Hauptfenster `fig` (uifigure, 1280×780). Layout `gMain` [2×2], Spalten {370, '1x'},
Zeilen {'1x', 170}:

- **Linke Spalte** (`gLeft`, scrollbar, volle Höhe) enthält 4 Panels untereinander:
  1. **Parameter** (`pnlParam`/`gP`, 16 Zeilen): COM-Port, Intervall, Stopp-Temperaturen, „Abkühlen ab", Kameras, Basisordner, Datum, Inlay 1/2 mit Muster/Form.
  2. **Programmablaufplan (Deadband)** (`pnlDb`/`gD`): Checkbox „Deadband aktiv" + zwei editierbare Tabellen (Aufwärmen/Abkühlen) je mit „+ Zeile"/„− Zeile".
  3. **Steuerung** (`pnlCtrl`/`gC`): Start, Stop, Umschaltknopf „Abkühlvorgang", „LEDs aus", Statuslampe + Statustext.
  4. **Bildzähler** (`pnlCnt`/`gZ`): „Bilder Kamera 1 (links)" / „Kamera 2 (rechts)".
- **Rechte Spalte** (`gRight`, Zeilen {80, '1x', 230}):
  - Große Live-Temperaturanzeigen (`lblTL`/`lblTR`, „1: …" blau / „2: …" orange).
  - Live-Kameravorschau (`axCamL`/`axCamR`) — **stark gedrosselt, siehe §8**.
  - Live-Plot (`axPlot`, beide Temperaturkanäle über Zeit, `animatedline` max. 7200 Punkte).
- **Status-Log** (`txtLog`): rechts unten (Zeile 2, Spalte 2), zeitgestempelte Meldungen, max. 500 Zeilen, dunkle „Konsole" (Consolas).

**Dark-Mode-Styling**: zentrale Farbpalette `C` (struct) direkt nach dem
UI-Aufbau; alle Komponenten werden per `findall(fig,'Type',…)` eingefärbt.
`uiconfirm`-Dialoge (Ordnerbestätigung, Scharfstellung) bleiben im Standard-Look
(von MATLAB gerendert, nicht einfärbbar).

### Parameter und Defaults

| Feld / Bedienelement | Variable (UI) | Default | Bedeutung |
|---|---|---|---|
| COM-Port | `ddCom` (editierbares Dropdown) | gemerkter Port / `COM4` | Serieller Port des Thermometers. ⟳ = Liste aktualisieren, „Messgerät suchen" = Auto-Erkennung (Handshake). |
| Intervall [s] | `edtInt` | **0.4** | Abtastintervall. Minimum 0.4 s = Geräte-Latenz des HH806AWE (2,5 Messungen/s). |
| Stopp Aufw. [°C] | `edtStopT` | **90** | Aufwärmen stoppt, wenn beide Kanäle ≥ Wert. |
| Stopp Abk. [°C] | `edtStopC` | **37** | Abkühlen stoppt, wenn beide Kanäle ≤ Wert. |
| Abkühlen ab [°C] | `edtCoolAct` | **80** | Abkühlvorgang aktiviert sich automatisch, wenn beide Kanäle ≥ Wert. |
| Kameras | `ddCams` | „Beide" | ItemsData `beide`/`links`/`rechts`. |
| Kameras zuweisen … | `btnFindCams` | – | Startet den **Kamera-Einrichtungs-Wizard** (§10). |
| Zuweisung testen | `btnTestCams` | (aus) | Öffnet beide zugewiesenen Kameras zur Sichtkontrolle (nur wenn beide zugewiesen). |
| (Statuszeile) | `lblCamAssign` | – | Zeigt, ob/welche Kameras zugewiesen sind. |
| Basisordner | `edtBase` (+ `btnBrowseBase`) | `D:\MemoryCI 2.0\BFR-Versuch` | Wurzel für Versuchsordner. |
| Datum | `edtDatum` | heute (`YYYY-MM-DD`) | Bestandteil des Ordnernamens; daraus wird der Datums-Präfix `YYYYMMDD` abgeleitet. |
| Inlay 1 / 2 | `edtInlay1`/`edtInlay2` | leer | Kennnummer je Kamera (führendes „MV"/„mv" wird automatisch entfernt). Pflicht für aktive Seite(n). |
| Muster 1 / 2 | `ddMuster1`/`ddMuster2` | „(keins)" | ItemsData `''`/`-FM`/`-LM` (Funktions-/Labormuster). |
| Form 1 / 2 | `ddForm1`/`ddForm2` | „(keine)" | ItemsData `''`/`-s`/`-g` (Spiral-/gerade Form). |
| Deadband aktiv | `chkDb` | **an** | Schaltet beide Programmablaufpläne scharf. Aus → überall jeder 0,1-Grad-Schritt. |

Inlay-, Muster- und Form-Felder werden über `syncInlayFields` passend zur
Kameraauswahl aktiviert/ausgegraut (nur Felder aktiver Kameras nutzbar; inaktive
werden geleert). Die Deadband-Tabellen werden über `syncDbFields` passend zum
Häkchen aktiviert/gesperrt. Während eines Laufs sind alle Eingaben gesperrt
(`lockables`-Array, `set(lockables,'Enable','off')`).

---

## 5. Ausgabe: Ordner, Dateinamen, Bildstempel, CSV

### Ordnerstruktur

```
<Basisordner>\<Datum>-<Inlay1-Bez>-<Inlay2-Bez>\
├── <Inlay1-Bez>\                         (nur wenn Kamera 1 aktiv)
│   ├── <YYYYMMDD>-<Inlay1-Bez>.csv       (Mess-/Parametertabelle)
│   ├── <YYYYMMDD>_<HHmmss>_<temp>.jpg    (gestempelte Bilder)
│   └── …
└── <Inlay2-Bez>\                         (nur wenn Kamera 2 aktiv)
    └── …
```

- **Inlay-Bezeichner** je Seite: `MV<Nr><Muster><Form>` — z. B. `MV71-07-FM-s`.
  Wird in Versuchsordnername, Unterordnername, CSV-Dateiname **und** Bildstempel verwendet.
- **Bild-Dateiname:** `<YYYYMMDD>_<HHmmss>_<temp>.jpg`
  - `HHmmss` = **aktuelle Uhrzeit der Aufnahme** (nicht Sekunden seit Start!).
  - `<temp>` = Temperatur 4-stellig, Punkt durch `-` ersetzt, z. B. `25-3` (= 25,3 °C).
  - Beispiel: `20260617_144623_25-3.jpg`.

### Bildstempel (in das JPEG eingebrannt)

- **unten links:** `<yyyy/MM/dd> @ <HH:mm:ss> <Inlay-Bez>` (mit Doppelpunkten, aktuelle Zeit).
- **unten rechts:** `Temperature: <x,x> Deg-C` (Komma als Dezimaltrenner).
- Weiße Schrift auf schwarzem Kasten, Größe an Bildhöhe gekoppelt.

### CSV (eine Datei je aktiver Kamera)

Aufbau: zuerst ein **Parameterblock** (alle gewählten Einstellungen, je Zeile
`Name;Wert`), dann eine Leerzeile, dann die Tabelle:

```
Parameter;Wert
COM-Port;COM4
Intervall [s];0,40
Stopp Aufwaermen [Grad C];90,0
Stopp Abkuehlen [Grad C];37,0
Abkuehlen ab [Grad C];80,0
Deadband aktiv;ja
Deadband Aufwaermen Abschnitt 1;-inf .. 25 -> 1
Deadband Aufwaermen Abschnitt 2;25 .. 70 -> 0,1
Deadband Aufwaermen Abschnitt 3;70 .. inf -> 1
Deadband Abkuehlen Abschnitt 1;-inf .. inf -> 1
Kameras;beide
Datum;2026-06-17
Inlay 1 (Kamera 1);MV71-07
Muster (Kamera 1);Funktionsmuster (-FM)
Form (Kamera 1);Spiralform (-s)
Inlay 2 (Kamera 2);MV71-08
Muster (Kamera 2);Labormuster (-LM)
Form (Kamera 2);Gerade Form (-g)
Basisordner;D:\MemoryCI 2.0\BFR-Versuch
Versuchsordner;…
Datums-Praefix;20260617

Uhrzeit;Temperatur
144623;25,3
144630;25,4
…
```

- **Trennzeichen `;`**, **Dezimaltrenner `,`**, Einheit als `Grad C` statt `°C`
  → öffnet encoding-sicher in deutschem Excel.
- Eine **Datenzeile je gespeichertem Bild**: `Uhrzeit;Temperatur`, Uhrzeit als `HHmmss`.
- Wird ein bestehender Versuchsordner weiterverwendet, wird die CSV **fortgeführt**
  (Kopf nicht erneut geschrieben).

---

## 6. Programmablaufplan / Deadband (Kernkonzept)

Das „Deadband" legt **temperaturabhängig** fest, um wie viel Grad sich die
Temperatur seit dem letzten Bild ändern muss, bevor ein neues Bild ausgelöst wird.
Es gibt **zwei Tabellen**: eine für **Aufwärmen**, eine für **Abkühlen** (zur Laufzeit
wird je nach `cooling`-Zustand die passende gewählt).

Jede Tabelle hat Spalten **Start | Ende | Deadband** (alle in °C):
- **Start** der ersten Zeile ist fest `-Inf`, **Ende** der letzten Zeile fest `Inf`
  (nicht editierbar bzw. wird beim Editieren zurückgesetzt).
- **Ende** und **Deadband** sind editierbar; **Start** folgt automatisch dem Ende der Zeile darüber.
- Deadband-Spalte ist eine **Text-Spalte** (`char`) mit genau **1 Nachkommastelle**
  (z. B. `1.0`, `0.1`) — eine numerische uitable-Spalte erlaubt kein eigenes Format.
- Start/Ende sind **numerische** Spalten (rechtsbündig, zeigen `-Inf`/`Inf`).
- **„+ Zeile"** hängt einen Abschnitt an (neuer Schnittpunkt = letzte untere Grenze + 10),
  **„− Zeile"** entfernt die letzte Zeile (mindestens 1 Zeile bleibt).

**Initialwerte:**
- Aufwärmen: 3 Zeilen — `-Inf..25 → 1.0`, `25..70 → 0.1`, `70..Inf → 1.0`.
- Abkühlen: 1 Zeile — `-Inf..Inf → 1.0`.

**Auslöselogik** (`onTick`): Für jeden Kanal wird per `deadbandFor(T)` der
Deadband-Wert des Abschnitts bestimmt, in den die aktuelle Temperatur fällt
(Segment `i` gilt für `edges(i) <= T < edges(i+1)`). Ein Bild löst aus, wenn
sich die Temperatur in Auslöserichtung (Aufwärmen: Anstieg, Abkühlen: Abfall) um
**mindestens** diesen Wert vom letzten Auslösewert entfernt hat. Bei `Deadband
aktiv = aus` ist der Schritt überall 0 → jeder 0,1-Grad-Schritt löst aus.

Beim Start werden beide Tabellen über `dbFreeze` in numerische Arrays
(`dbWarmEdges`/`dbWarmVals`, `dbCoolEdges`/`dbCoolVals`) eingefroren und über
`dbValidate` geprüft (Grenzen streng aufsteigend, Deadbands > 0).

---

## 7. Architektur

- **Eine `function bfrAufnahmeApp` mit verschachtelten (nested) Funktionen.**
  Alle Callbacks (`onStart`, `onTick`, …) und Helfer teilen sich den Workspace
  der Hauptfunktion → **geteilter Zustand** sind die Variablen am Dateianfang
  (§ „Geteilter Zustand", Zeilen ~33–62).
- **Eigenständige (nicht verschachtelte) Funktionen** am Dateiende: `openDinoLiteCameras`,
  `getHH806Temp`, `decodeMeasurement`, `buildCmd`, `unitName`, `extractPortKey`,
  `captureSingleFrameSide`, `stampImage`, `renderTextStrip`, `glyphAtlas`,
  `blitLabel`, `throttledPreviewUpdate`. Diese bekommen alles per Argument.
- **Messschleife:** ein `timer` (`ExecutionMode='fixedRate'`, `BusyMode='drop'`),
  Periode = Intervall, ruft `onTick` auf. Nicht blockierend → GUI bleibt bedienbar.
- **Persistenz:** der zuletzt funktionierende COM-Port wird per
  `setpref('bfrAufnahmeApp','comPort',…)` gemerkt und beim Start vorausgewählt.

### Wichtige Zustandsvariablen (geteilt)

| Variable | Bedeutung |
|---|---|
| `s` | offenes `serialport`-Objekt während eines Laufs |
| `cams` | struct `.left`/`.right` mit `videoinput`-Objekten |
| `tmr` | Timer der Messschleife |
| `t0` | Startzeitpunkt (für die Plot-Achse „t seit Start") |
| `prevL`/`prevR` | letzter Auslösewert je Kanal (`-Inf` Aufwärmen-Start, `+Inf` Abkühlen-Start) |
| `cntL`/`cntR` | Bildzähler je Seite |
| `running` | Lauf aktiv? |
| `cooling` | false = Aufwärmen, true = Abkühlen |
| `dirLrun`/`dirRrun`, `csvLrun`/`csvRrun` | eingefrorene Ziel-Unterordner/CSV-Pfade |
| `prefixRun` | `YYYYMMDD` (aus Datum) |
| `id1Run`/`id2Run` | voller Inlay-Bezeichner je Seite (Stempel/Namen) |
| `useL`/`useR` | aktive Kameras |
| `stopTrun`/`stopCrun`/`coolActRun` | eingefrorene Stopp-/Aktivierungs-Temperaturen |
| `dbOnRun` | Deadband aktiv? |
| `dbWarmEdges`/`dbWarmVals`, `dbCoolEdges`/`dbCoolVals` | eingefrorene Programmablaufpläne |

---

## 8. ⚠️ Speicherleck in `preview()` — NICHT „reparieren"!

**Symptom:** Bei laufender Live-Vorschau wuchs der RAM stetig (mehrfach
beobachtet bis >16 GB) und MATLAB stürzte nach annähernd konstanter Laufzeit ab.

**Diagnose (mühsam erarbeitet):**
- Es ist **kein** klassisches MATLAB-Array-Leck — `memory`/`MemUsedMATLAB` blieb flach.
- Der Speicher wuchs im **GUI-Renderer-Prozess** `matlabwindowhelper.exe` (uifigure ist Chromium/JS-basiert).
- Verschieben in ein **klassisches `figure`-Fenster** half nicht — dann wuchs `MATLAB.exe` genauso. Das Leck hängt also an **`preview()` selbst** und ist von MATLAB aus **nicht freigebbar** (auch periodisches Neustart/`cla` der Vorschau gibt den Speicher nicht zurück).

**Lösung (die einzige, die wirkt): die ANZEIGE-Bildrate drosseln.**
- `attachPreviews` setzt je Kameraachse `UpdatePreviewWindowFcn = @throttledPreviewUpdate` **vor** `preview(...)`.
- `throttledPreviewUpdate` aktualisiert das angezeigte Bild **zeitbasiert höchstens 1×/Sekunde** (Konstante `INTERVALL_S = 1.0` in der Funktion).
- Die **Kamera streamt weiter mit voller Rate** → Auto-Belichtung bleibt korrekt; die **gespeicherten Bilder** (`getsnapshot` in `captureSingleFrameSide`) sind **unverändert in voller Qualität/Aktualität**. Nur die Live-Anzeige ist gedrosselt.
- Leckrate so ≈ 30× kleiner → grob ~0,8 GB/Stunde; über mehrere Stunden unkritisch (Laptop hat 32 GB).

**Konsequenzen für künftige Änderungen:**
- Die 1-fps-Drosselung **nicht** auf höhere FPS stellen, ohne den RAM zu beobachten.
- **Kein** `getsnapshot` als Ersatz für `preview` zur Anzeige — ohne Dauerstream schwingt die Auto-Belichtung nicht ein → überbelichtete Bilder (haben wir durch).
- Wenn künftig der Plot (`axPlot`) langsam Speicher zieht: das wäre der nächste Kandidat (winzige Datenmengen, aber dieselbe Renderer-Mechanik) — dann ggf. Plot-Updates throttlen.

---

## 9. Bildstempel ohne `getframe` (Glyphen-Atlas)

Frühe Versionen stempelten Text per `figure`+`getframe`/`print` **pro Bild** —
das ist eine bekannte MATLAB-Leckquelle und ließ den RAM in der Schleife wachsen.

Aktuelle Lösung (`stampImage`):
1. **Bevorzugt `insertText`** (Computer Vision Toolbox) — leckfrei, sauberes Schriftbild.
2. **Fallback ohne Toolbox:** `glyphAtlas(fontPx)` rendert **jedes Zeichen genau einmal**
   offscreen (begrenzte, einmalige Anzahl `print`-Aufrufe) und cached die Bitmaps
   persistent. `renderTextStrip` setzt die Stempel danach **nur per Matrix-Operationen**
   aus den gecachten Glyphen zusammen → **kein figure/print/getframe pro Bild**.
   `blitLabel` kopiert den Streifen in die Bildecke (klassen-/graustufensicher).
   Der Atlas wird in `onStart` einmalig vorgebaut (nur wenn `insertText` fehlt),
   damit die erste Aufnahme nicht verzögert wird.
- Schlägt das Stempeln fehl, wird das Bild **ungestempelt** gespeichert — eine
  Aufnahme geht nie verloren.

---

## 10. ⚠️ Instabile USB-Enumeration — Kamera-Zuordnung

**Symptom:** Auf dem Versuchslaptop ändern sich **ohne Umstecken**
(a) der **USB-Port-Pfad** (`idaKey`) einer Dino-Lite und (b) der **`winvideo`-Index**
(eine HD-Webcam verschiebt sich in der Aufzählung). Folge: mal „Ports passen nicht",
mal „links zeigt die Webcam", mal „Kameras vertauscht".

**Robuste Lösung in `openDinoLiteCameras`:**
- `CONFIG(c).idaKey` darf **mehrere** bekannte Port-Pfade je Seite enthalten;
  der Fail-safe verlangt nur, dass **mindestens einer** vorhanden ist.
  - Aktuell: **LINKS** = `6&d82dd4a&0&0000` (stabil); **RECHTS** = `6&189ed0a2&8&0000` **oder** `6&2b588147&5&0000` (wechselt).
- `CONFIG(c).winvideo` ist nur noch **Rückfallebene**. Der echte Index wird zur
  Laufzeit **dynamisch** bestimmt: alle winvideo-Geräte mit „Dino" im Namen
  filtern (Webcam fällt weg), sortieren und über die **DNX64-Reihenfolge** der
  Seite zuordnen.
- Vor dem Öffnen `imaqreset`, um verwaiste `videoinput`-Objekte freizugeben
  (sonst „Gerät belegt" → rotes Kreuz in der Vorschau).
- Externe Vorschaufenster (klassische `figure`, Tag `bfrPreview`) dienen zum
  **Scharfstellen**; die Funktion kehrt erst nach Klick auf „OK – weiter" zurück.
  Danach werden sie geschlossen und die Vorschau in die App-Achsen umgeleitet.

**Wenn es wieder klemmt:** `listKameras` ausführen, Ausgabe prüfen, neuen
Port-Pfad bei der passenden Seite in `CONFIG.idaKey` ergänzen. Die Scharfstell-
Fenster sind die finale **Sichtkontrolle** (LINKS/RECHTS richtig?).

### Kamera-Einrichtungs-Wizard (laptop-unabhängig, ohne Code-Edit)

Statt die `CONFIG`-Ports von Hand zu pflegen, gibt es im Parameter-Panel den
Button **„Kameras zuweisen …"** (`findCameras`):
- Öffnet **nacheinander jede** winvideo-Kamera mit Live-Vorschau; pro Kamera ein
  Dialog mit **Kamera 1 (links) / Kamera 2 (rechts) / Ignorieren** (`assignOneCamera`).
- Endet, wenn **beide** zugewiesen sind oder **alle** Kameras durch sind.
- Gespeichert wird je Kamera der **USB-Port-Pfad** (`idaKey`), nicht der
  instabile winvideo-Index — ermittelt über `dinoWinvideoMap` (Dino-Lites per
  Name filtern, DNX64-Ports per Reihenfolge zuordnen). Webcam (kein Port) kann
  nicht zugewiesen werden.
- Persistenz: **Datei `camAssign.mat`** neben dem Skript (`saveCamAssign` /
  Laden beim Start). Beim nächsten Start ist die Zuweisung **vorausgewählt**;
  Status zeigt `lblCamAssign`.
- Diese Zuweisung hat in `openDinoLiteCameras` **Vorrang** vor den fest
  hinterlegten `CONFIG.idaKey` (Argument `assignPorts`). Ist nichts gespeichert,
  gilt der `CONFIG`-Default. Der **winvideo-Index** wird weiterhin dynamisch
  ermittelt (robust gegen Webcam-Umsortierung).
- **„Zuweisung testen"** (`testCameras`, nur aktiv wenn beide zugewiesen): öffnet
  beide Kameras in LINKS/RECHTS-Fenstern + Bestätigungsdialog — **ohne** Lauf,
  reine Sichtkontrolle.
- **Grenze:** Der gespeicherte Port ist **EIN** Pfad. Oszilliert er (wie bei einer
  Kamera auf dem aktuellen Laptop), schlägt die Erkennung fehl → einfach Wizard
  erneut laufen lassen (re-assign). Die fest hinterlegte Multi-Key-`CONFIG` deckt
  beide bekannten Werte ab und dient als Default ohne gespeicherte Zuweisung.

---

## 11. Thermometer (Omega HH806AWE)

- Protokoll: 19200 Baud, **even** parity, 8 Datenbits, 1 Stoppbit. Kommando-Frame
  per `buildCmd` (ASCII-Großbuchstaben + 2-Hex-Checksumme + CR LF). Antwort wird
  in `decodeMeasurement` dekodiert (24-Bit-Big-Endian je Kanal, Dezimalpunkt-Bits,
  2er-Komplement, `+OL`/`-OL` → `NaN`, Einheitencode → `unitName`).
- `getHH806Temp(portOrObj[, closeAfter])`: nimmt **entweder** ein offenes
  `serialport`-Objekt (schnell, für die getaktete Schleife) **oder** einen
  Portnamen (öffnet/schließt selbst). Liefert `[vals, units, ok, raw]`.
- **Auto-Erkennung** („Messgerät suchen" → `findThermo`): probiert jeden Port aus
  `serialportlist`, sendet den Omega-Befehl und wählt den Port, der eine **gültige
  Antwort** liefert (2 Kanäle, plausible Werte −100…500 °C). Erkennung über das
  **Protokoll**, nicht über den Portnamen — funktioniert laptop-/kabelunabhängig.
- COM-Feld ist ein **editierbares Dropdown** aus `serialportlist`; ⟳ =
  `refreshPorts`. Zuletzt erfolgreicher Port wird per `getpref`/`setpref` gemerkt.

---

## 12. Funktionsreferenz

### Nested (teilen den App-Zustand)

| Funktion | Aufgabe |
|---|---|
| `onBrowse(edt)` | Ordnerdialog für den Basisordner. |
| `refreshPorts()` | COM-Port-Liste aus `serialportlist` aktualisieren (aktuelle Auswahl bleibt erhalten). |
| `findThermo()` | Thermometer per Handshake suchen und Port auswählen. |
| `findCameras()` | Kamera-Wizard: jede Kamera nacheinander zeigen + zuweisen, speichern (§10). |
| `assignOneCamera(wid,nm,k,total)` | Eine Kamera live zeigen + Seite abfragen (1/2/0). |
| `assignDone(h,v)` | Dialog-Knopf-Callback (Wahl merken, `uiresume`). |
| `testCameras()` | Beide zugewiesenen Kameras zur Sichtkontrolle öffnen (kein Lauf). |
| `saveCamAssign()` / `updateCamAssignUI()` | Zuweisung in `camAssign.mat` speichern / Statuszeile + Test-Button-Freigabe. |
| `onStart(~,~)` | Parameter lesen/validieren/einfrieren, Ordner+CSV anlegen, serialport + Kameras öffnen, Vorschau anhängen, Bildstempel-Atlas vorbauen, Timer starten. |
| `onCool(~,~)` | Zwischen Aufwärm-/Abkühlmodus umschalten (setzt `cooling`, `prevL/prevR`, Statustext); auch programmgesteuert für die Auto-Aktivierung aufgerufen. |
| `onTick(~,~)` | Ein Messzyklus: Temperatur lesen, Anzeige/Plot, Auto-Stopp, Auto-Abkühl-Aktivierung, Auslöselogik (`deadbandFor`) + Aufnahme je Seite. Fehler in einem Tick brechen den Lauf nicht ab. |
| `onStop(~,~)` | Lauf beenden, Ressourcen freigeben, UI entsperren, Zustand zurücksetzen. |
| `onClose(~,~)` | Beim Fensterschließen aufräumen und `fig` löschen. |
| `syncInlayFields()` | Inlay-/Muster-/Form-Felder passend zur Kameraauswahl aktivieren/leeren. |
| `setInlay(lbl,edt,on)` | Ein Label+Feld aktivieren/deaktivieren (deaktiviert → leeren). |
| `initCsv(p,paramLines)` | CSV anlegen: Parameterblock + Leerzeile + Tabellenkopf (nur wenn Datei neu). |
| `jaNein(b)` | logisch → „ja"/„nein" für CSV. |
| `syncDbFields()` | Beide Deadband-Tabellen + ihre +/−-Buttons passend zum Häkchen sperren/freigeben. |
| `onDbEdit(src,ev)` | Zellbearbeitung: Deadband auf 1 Nachkommastelle/`>0` normieren, letztes Ende = `Inf`, Start-Spalte neu ableiten. |
| `dbNormalize(d)` | Cell-Tabelle normieren: Start(1)=−Inf, Ende(letzte)=Inf, Start(i)=Ende(i−1). |
| `dbAddRow(tbl,gridRow)` / `dbDelRow(tbl,gridRow)` | Abschnitt anhängen / letzten entfernen + Höhe anpassen. |
| `dbFitHeight(tbl,gridRow)` | Panel-Grid-Zeilenhöhe an Zeilenzahl koppeln (`32 + 26*n`) — gegen Scrollbalken/helle Leerfläche. |
| `dbFreeze(tbl)` | Tabelle → numerische `edges`/`vals`. |
| `dbValidate(edges,vals,which)` | Grenzen streng aufsteigend & Deadbands > 0 prüfen. |
| `deadbandFor(T)` | Deadband-Wert für Temperatur `T` (wählt warm/kalt anhand `cooling`). |
| `edgeStr(x)` / `dbSegLines(label,edges,vals)` | Formatierung der Pläne für CSV. |
| `camLabel()` | „beide"/„nur Kamera 1 (links)"/„nur Kamera 2 (rechts)". |
| `activeCams()` | `videoinput`-Objekte der aktiven Seiten. |
| `attachPreviews()` | Externe Fokusfenster schließen, **gedrosselte** Live-Vorschau in die App-Achsen starten (`UpdatePreviewWindowFcn`), LEDs aus. |
| `ledsOff(verbose)` | Dino-Lite-LEDs über DNX64 ausschalten. |
| `makePreviewImage(ax,vid)` | Bild-Objekt passender Größe für `preview`. |
| `showInactive(ax)` | „inaktiv" in einer ungenutzten Kameraachse. |
| `cleanupResources()` | Timer/Kameras/externe Fenster/DNX64/serialport sicher freigeben. |
| `logMsg(msg)` | Zeitgestempelte Zeile ins Status-Log (max. 500). |

### Eigenständig (alles per Argument)

| Funktion | Aufgabe |
|---|---|
| `throttledPreviewUpdate(~,event,himage)` | Vorschau ≤ 1×/s aktualisieren (Speicher, §8). |
| `openDinoLiteCameras(dllPath,sides)` | Dino-Lites öffnen mit dynamischer winvideo-Zuordnung + Multi-Key-Fail-safe + Scharfstell-Dialog (§10). |
| `extractPortKey(ida)` | USB-Port-Kennung aus dem DNX64-IDA-String extrahieren. |
| `dinoWinvideoMap(dllPath)` | Alle winvideo-Kameras + Dino-Lite-Port-Zuordnung (für den Wizard). |
| `getHH806Temp(portOrObj,closeAfter)` | Eine Temperaturmessung lesen (§11). |
| `buildCmd(payload)` / `decodeMeasurement(raw)` / `unitName(c)` | Omega-Protokoll: Befehl bauen / Antwort dekodieren / Einheit. |
| `captureSingleFrameSide(cam,outDir,datePrefix,temp,sideLabel,inlayLabel,csvPath)` | Ein Bild holen, **stempeln**, speichern, CSV-Zeile anhängen. |
| `stampImage(img,txtBL,txtBR)` | Stempel einbrennen (insertText oder Glyphen-Atlas, §9). |
| `renderTextStrip(txt,fontPx)` / `glyphAtlas(fontPx)` / `blitLabel(img,strip,corner,marg)` | Fallback-Bildstempel ohne getframe (§9). |

---

## 13. Konfigurations-/Tuning-Punkte (wo schrauben)

| Was | Wo |
|---|---|
| Kamera-Port-Pfade & Seiten | `CONFIG` in `openDinoLiteCameras` (Multi-Key je Seite). |
| Vorschau-Bildrate (Speicher!) | `INTERVALL_S` in `throttledPreviewUpdate` (Default 1.0 s). |
| Tabellen-Zeilenhöhe (Scrollbar/Lücke) | `dbFitHeight` (Formel `32 + 26*n`). |
| Default-Parameter | UI-Erstellung in `bfrAufnahmeApp` (Feld-`'Value'`) **und** der „geteilte Zustand"-Block. |
| Dezimal-/Trennzeichen der CSV | `initCsv` + `n1`/`gv`-Formatter in `onStart`. |
| Plot-Punktelimit | `animatedline(... 'MaximumNumPoints',7200 ...)`. |
| Farbschema (Dark Mode) | struct `C` im Styling-Block. |

---

## 14. Bekannte Eigenheiten / Stolperfallen

- **Webcam vorhanden:** wird per Namensfilter aus der Kamera-Zuordnung
  herausgehalten; taucht sie trotzdem als „Kamera" auf → `CONFIG`/Namensfilter prüfen.
- **`uiconfirm`-Dialoge** sind nicht dark-mode-fähig (MATLAB-Standard).
- **Auto-Abkühlung (80 °C) < Stopp Aufw. (90 °C):** im Default greift „Stopp Aufw."
  nicht, weil vorher auf Abkühlen umgeschaltet wird. Beabsichtigt; bei Bedarf
  Schwellen anpassen.
- **Gleiche Sekunde, gleiche Temperatur:** zwei Aufnahmen mit identischem
  `HHmmss` **und** identischem Temp-Suffix würden sich überschreiben — wegen der
  Deadband-Auslösung (Temperatur muss sich geändert haben) praktisch
  ausgeschlossen.
- **MATLAB-Version:** Ein neueres MATLAB behebt das `preview`-Leck **nicht**
  (architektonische Einschränkung der uifigure-/JS-Render-Pipeline).
- **Modell-/Identitätshinweise** gehören nicht in dieses Repo — nur Code/Funktion dokumentieren.

---

## 15. Eigenständige `.exe` bauen (`buildBfrAufnahmeApp.m`)

Erstellt eine Windows-`.exe`, die beim Doppelklick direkt die GUI öffnet
(läuft ohne MATLAB, nur mit der MATLAB Runtime).

**Bauen (in MATLAB, mit Quellcode):**
```matlab
buildBfrAufnahmeApp            % ohne Icon
buildBfrAufnahmeApp('icon.png')% mit eigenem Icon
```
Ergebnis: `bfrAufnahmeApp_exe\bfrAufnahmeApp.exe`.

**Voraussetzungen:** MATLAB Compiler (Toolbox), `DNX64.dll` + `DNX64forMatlab.h`
im Skriptordner, ein C-Compiler (`mex -setup`) für die einmalige Prototyp-Erzeugung.
Ziel-PC: passende MATLAB Runtime + Dino-Lite-Treiber.

**Drei deploy-spezifische Anpassungen im App-Code** (alle über `isdeployed`
gekapselt, ändern das Verhalten in MATLAB selbst nicht):
1. **`loadDNX64(dllPath)`** statt direktem `loadlibrary(...,'DNX64forMatlab.h',...)`:
   `loadlibrary` kann in einer `.exe` keinen C-Header parsen → im deployten Modus
   wird die vom Build erzeugte **Prototyp-Datei `DNX64_proto.m`** (+ Thunk-DLL)
   genutzt. Die DLL wird über `ctfroot`/`which` gesucht.
2. **`camAssign.mat`** liegt im deployten Modus unter `%APPDATA%\bfrAufnahmeApp\`
   (der Skript-/Paketordner ist dort schreibgeschützt).
3. **`uiwait(fig)`** am Ende der Hauptfunktion (nur deployed) hält die App offen —
   sonst kehrt die Funktion sofort zurück und die `.exe` beendet sich.

Das Build-Skript erzeugt den Prototyp automatisch, packt DLL/Header/Prototyp/Thunk
per `AdditionalFiles` ein und ruft `compiler.build.standaloneApplication`. Für eine
Installer-Variante, die die Runtime mitbringt: `compiler.package.installer(results)`
oder die App „Application Compiler" (`deploytool`).

**Nicht getestet** (keine Live-MATLAB-Umgebung beim Erstellen): Deployment von
`loadlibrary`+Custom-DLL ist erfahrungsgemäß fummelig; ggf. sind auf der
Zielmaschine ein bis zwei Iterationen nötig (siehe Build-Warnungen).

---

## 16. Git / Branch

Entwicklung läuft auf Branch **`claude/lucid-brown-2rxlsq`**. Änderungen werden
committet und gepusht; PR nur auf ausdrückliche Anfrage.
