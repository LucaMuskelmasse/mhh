# Code-Kontext – Repository `mhh`

Diese Datei fasst den wichtigen Kontext aller `.m`-Dateien zusammen, damit der
Konversationsverlauf gelöscht werden kann, ohne Verständnis über den Code zu
verlieren. Stand: 2026-06-26.

Das Repository enthält die **Bildauswertungs- / Tracking-Skripte**
(Auswertung der aufgenommenen Bilder bzw. Videos): `kruemung.m`,
`tip_track_matching_spline.m`, `cochlea_model_tracking.m`,
`create_trajectory.m`.

(Die Versuchssteuerungs-/Hardware-Skripte `bfrAufnahmeApp.m`, `listKameras.m`
und `testKameras.m` liegen in einem anderen Branch und sind hier bewusst nicht
enthalten.)

Kontext: Formgedächtnis-/Memory-CI-Forschung. Es geht um die Verbiegung von
Draht/Elektroden über Temperatur und um das Tracking der Spitze (Tip) einer
Cochlea-Elektrode beim Einführen ins Cochleamodell.

---

## Gemeinsame Konventionen (für die Auswertungs-Skripte)

- **Koordinaten:** Bildkoordinaten, `TipCoordinates(k,:) = [row, col]` = `[y, x]`.
  Referenzpunkte aus `ginput` werden dagegen als `[x, y] = [col, row]`
  gespeichert (z.B. `cochleaCenter`, `cochleaEntrance`). Achtung auf die
  Reihenfolge beim Rechnen!
- **Bildanzeige:** `axis ij` (y zeigt nach unten). Das ist relevant für die
  Vorzeichendefinition von Winkeln (siehe `cochlea_model_tracking.m`).
- **Binarisierungs-Konvention beim Tracking:** Elektrode/Draht = `0` (schwarz),
  Hintergrund = `1` (weiß). Das Tracking sucht im Komplement (`imcomplement`)
  nach der Elektrode.
- **`ImageData`-Struct-Array:** pro Frame ein Eintrag mit Feldern wie `name`,
  `path`, `gray`/`rgb`, `bw`, ggf. `skel`, `xs`, `ys`, `kappa`.
- **Persistenz:** Trajektorien werden als `.mat` neben den Daten gespeichert,
  beim nächsten Start per `questdlg` "Alte verwenden / Neu zuweisen".
- **Tracking-Pipeline (gemeinsam):** feste Workspace-Maske (Rechteck) + runde
  Tip-Suchmaske → größte zusammenhängende Komponente im Komplement →
  geodätische Distanztransformation (`bwdistgeodesic`) liefert den am weitesten
  entfernten Punkt = Tip. Plausibilitätsprüfungen (Krümmung, Konnektivität),
  bei Fehlschlag Vektorprädiktion + progressive Suche, sonst manuelles Klicken.

---

## `kruemung.m` — Krümmung eines biegenden Drahts über Temperatur (JPG)

**Zweck:** JPG-Bildfolge eines sich biegenden Drahts einlesen, den Draht
skelettieren, seine Krümmung entlang der Bogenlänge berechnen und als
Farbverlauf über dem Originalbild darstellen. Zusätzlich mittlere Krümmung über
Temperatur.

**Ablauf:**
1. Ordner mit `*.jpg` wählen (`uigetdir`, `imageDatastore`).
2. Pro Bild: Temperatur aus Dateinamen (`..._03-5` → `03.5 °C`), Graustufen +
   `medfilt2`, Binarisierung (`level = 0.6`), ROI-Beschränkung über ein
   Polygon (`xv`/`yv` mit `poly2mask`) — außerhalb wird auf weiß gesetzt.
3. Draht = Vordergrund (`~bwImg`), kleine Specks raus (`bwareaopen(...,300)`),
   Lücken schließen (`imclose`, `gapCloseRadius = 1`).
4. **Drahtauswahl:** die Komponente mit der **größten `MajorAxisLength`**
   (nicht größte Fläche!) wird als Draht gewählt — robust gegen runde
   Luftblasen, die mehr Fläche haben können.
5. Skelettieren (`bwskel`, `MinBranchLength=25`), Endpunkt finden,
   `bwdistgeodesic` für die Bogenlänge, `unique(d)` für streng monotone
   Stützstellen (sonst `interp1`-Fehler), `interp1` auf `N=20` gleichverteilte
   Punkte, glätten, Krümmung `kappa = |x'y'' − y'x''| / (x'²+y'²)^1.5`.
6. NaN-Guards: Frames mit < 2 Skelettpunkten / ohne Komponente werden mit NaN
   gefüllt (kein Absturz).
7. `figure(2)`: mittlere Krümmung über eindeutige Temperaturen (normiert,
   NaN-sicher via `accumarray`).
8. `figure` mit **Slider** (`uicontrol` + `addlistener` auf `Value`/`PostSet`):
   farbige Krümmungsdarstellung (jet-Colormap) über dem Graustufenbild, lokale
   Funktion `drawFrame`.

**Wichtige Parameter:** `level=0.6`, `gapCloseRadius=1`, `N=20`, ROI-Polygon
`xv`/`yv`, ROI-Rechteck `bwImg(1:end-70, 400:end-170)`.

**Gelöste Probleme:** `interp1`-Fehler (→ `unique(d)` + NaN-Guards);
Draht/Blasen-Unterscheidung (→ `MajorAxisLength`). Ein Kantenfilter und
morphologisches Opening zur Dicken-Trennung wurden getestet und wieder
**verworfen** (kein Mehrwert, Blasen sind ohnehin separate Komponenten).

---

## `tip_track_matching_spline.m` — Tip-Tracking aus JPG + Temperaturanalyse

**Zweck:** Vorläufer von `cochlea_model_tracking.m`, arbeitet auf **JPG-Bildern**
statt Video. Trackt die Elektrodenspitze über die Bildfolge und analysiert den
Fortschritt entlang der Trajektorie **über die Temperatur** (Formgedächtnis-
Aktivierung).

**Ablauf:**
1. JPG-Ordner wählen, Graustufen + `medfilt2`, Binarisierung (`level=0.55`).
2. Trajektorie laden oder neu (`tip_trajectory.mat` enthält
   `TipCoordinates`, `T`, `t_rel`).
3. Manuelle Maskenerzeugung: Workspace-Rechteck (`drawrectangle`) + Tip-Klick
   (`ginput`), `tipRadius=25`.
4. Tracking-Schleife (siehe gemeinsame Pipeline). Zusätzlich werden pro Frame
   **Temperatur** `T(k)` und **Zeitstempel** aus dem Dateinamen geparst
   (`yyyyMMdd_HHmmss`), `t_rel` = Sekunden seit Start.
   - Es gibt einen großen **auskommentierten** ersten Versuch der Tracking-
     Schleife (Zeilen ~129–300); aktiv ist die Variante ab "`%% test`".
5. `reviewTips(ImageData, TipCoordinates, tipRadius)`: **Slider**-basierte
   manuelle Kontrolle (hier noch mit Slider, anders als in
   `cochlea_model_tracking.m`!). Klick setzt Tip neu, "Bestätigen" beendet.
6. `figure(3)`: Trajektorie (Punkte, Linie, Spline). Achsen fest `1280×960`.
7. **Äquidistante Punkte** (`figure(4)`): Kurve dicht splinen und Punkte mit
   konstantem euklidischem Sehnenabstand `d=5 px` per Kreis-Segment-Schnitt
   erzeugen (`TipCoordsEqui`).
8. **Fortschritt über Temperatur** (`figure(5)`): jeder Messpunkt wird dem
   nächstgelegenen Referenzpunkt zugeordnet → Anteil `0..100 %` der Trajektorie
   über `T`.
9. **3-Segment-Regression** (`figure(6)`): stückweise lineare Anpassung
   `fitPlateauRampPlateau` mit festen Randwerten (Start 0, Ende 100). Liefert
   Aktivierungstemperaturen `As = x1`, `Af = x2`.

**Lokale Funktionen:**
- `reviewTips(...)` — Slider-Variante der Tip-Kontrolle.
- `fitPlateauRampPlateau(x, y, c1=0, c2=100)` — stetige stückweise-lineare
  3-Segment-Regression. Knickstellen `x1<x2` per Grid-Suche + `fminsearch`
  optimiert; Knickwerte `y1,y2` exakt per linearer Ausgleichsrechnung
  (`sseFixed`). Rückgabe: `params` (inkl. `m1,m2,m3,r2`) + `predictFcn`.
- Hilfsfunktionen `modelEval`, `sseFixed`, `objective`.

---

## `cochlea_model_tracking.m` — Tip-Tracking aus MP4-Videos (Hauptskript)

**Zweck:** Aus `tip_track_matching_spline.m` abgeleitete **Video-Variante**.
Verarbeitet **einen ganzen Ordner mit mehreren MP4-Videos** (Dateinamen z.B.
`2026-06-23_TP07_V01_F1_Camera1`, dann `V02`, …) nacheinander. Pro Video wird
die Elektrodenspitze getrackt und der **Einführwinkel** ins Cochleamodell
berechnet.

**Ablauf (äußere Schleife über alle Videos im Ordner):**
1. **Ordner** wählen (`uigetdir`); alle `*.mp4` alphabetisch sortiert
   (→ `V01, V02, …`). Gemeinsame Parameter für alle Videos:
   `startFrame=40`, `numBgFrames=5`, `fgThreshold=0.15`, `minBlobSize=50`,
   `tipRadius=20`, `curvatureThreshold=0.06`.
2. Pro Video: `vLabel` = `V0x` per `regexp(vidName,'V\d+')` (Fallback:
   Dateiname). **`vLabel` steht im Titel JEDER Figure.**
3. **Frames lesen** ab `startFrame` (Elektrode ist am Videoanfang noch nicht im
   Bild). RGB + `medfilt2` pro Kanal.
4. **Background Subtraction:** Hintergrund = Mittel der ersten `numBgFrames`
   Frames (statisch, elektrodenfrei). Pro Frame
   `diffImg = |gray − bgGray|/255`, `fg = diffImg > fgThreshold`,
   `bwareaopen`, dann `bwImg = ~fg` (Elektrode=0, Hintergrund=1).
   **Es gibt KEINE Farb-Maske (`createMask`) mehr** — wurde durch Background
   Subtraction ersetzt.
5. Trajektorie laden oder neu (`<videoname>_tip_trajectory.mat`). Gespeichert
   werden **`TipCoordinates`, `cochleaCenter`, `cochleaEntrance`**.
6. **Bei Neuzuweisung zuerst zwei Referenzpunkte per Klick** (auf dem RGB-Bild,
   damit die Anatomie sichtbar ist):
   - 1. Klick = **Mittelpunkt** des Cochleamodells (`cochleaCenter`, cyan).
   - 2. Klick = **Eingang** der Elektrode ins Modell (`cochleaEntrance`, magenta).
   Beim Laden einer **alten** `.mat` ohne diese Punkte werden sie einmalig
   nachgeklickt und per `save(...,'-append')` ergänzt.
7. Danach Workspace-Rechteck + Tip-Klick, dann Tracking-Schleife (gemeinsame
   Pipeline; Live-Ansicht in `figure(1)`, wird pro Video wiederverwendet).
8. `reviewTips(ImageData, TipCoordinates, vLabel)` — **event-gesteuerte,
   flackerfreie** Tip-Kontrolle (NICHT die Slider-Variante!). Details unten.
9. **Trajektorie-Plot** (eigene, benannte Figure `Tip Trajectory V0x`): Punkte,
   Linie, Spline + Mittelpunkt/Eingang/Referenzlinie + Legende.
10. **Winkel-Plot** (eigene Figure `Winkel V0x`): siehe unten.
11. **Übergang:** nach den Plots wartet eine modale `msgbox` auf OK, bevor das
    nächste Video startet. **Alle Ergebnis-Plots bleiben offen** (deshalb je
    Video eigene, eindeutig benannte Figures statt fester Nummern `figure(3/4)`).

**Winkelberechnung (wichtig, mit dem Nutzer abgestimmt):**
- Winkel zwischen Referenzlinie (Mittelpunkt→Eingang) und Tip-Linie
  (Mittelpunkt→Tip) **pro Frame**.
- **Gegen den Uhrzeigersinn = positiv, visuell im angezeigten Bild** (y zeigt
  nach unten). Umgesetzt mit `atan2d(ay*bx − ax*by, ax*bx + ay*by)` — das
  negierte Kreuzprodukt dreht das y-nach-unten-Bild auf "visuell CCW positiv".
- Verlauf wird über die gültigen Frames **entfaltet** (`unwrap`), kann also
  >180°/360° werden (anguläre Insertionstiefe). **Null = Tip auf der
  Mittelpunkt→Eingang-Linie** (Eingangslinie ist die Nullreferenz, kein
  Abziehen des ersten Frames).
- `cochleaCenter`/`cochleaEntrance` sind `[x,y]=[col,row]`; `TipCoordinates`
  ist `[row,col]` → beim Vektoraufbau `bx=col−cx`, `by=row−cy`.

**`reviewTips` (in dieser Datei, event-gesteuert/flackerfrei):**
- Fenster, Bild (`imshow`) und Marker (`plot 'r+'`) werden **einmal** angelegt,
  danach nur per `set(hImg,'CData',...)` / `set(hCross,'XData/YData',...)`
  aktualisiert (kein `imshow`/`ginput` pro Frame → keine Latenz/Flackern).
- Steuerung: Pfeil **rechts/links** = vor/zurück, **Linksklick** ins Bild setzt
  Tip des aktuellen Frames, **"Fertig"/Escape/Schließen** beendet (`uiresume`
  + `delete(hFig)`). Marker hat `PickableParts='none'`, damit Klicks aufs Bild
  durchgehen. Titel enthält `vLabel`.

**Historie der Designentscheidungen für dieses Skript:**
- Erst Slider in `reviewTips`, dann auf chronologische Anzeige mit Pfeiltasten
  umgestellt, dann flackerfrei (Event-CData) gemacht.
- Farb-Maske (`createMask`) → durch Background Subtraction ersetzt.
- Äquidistante Punkte / Temperatur-Fortschritt / 3-Segment-Fit aus
  `tip_track_matching_spline.m` wurden hier **entfernt** (Video hat keine
  Temperatur im Dateinamen).
- Zuletzt: Ordner-Stapelverarbeitung mehrerer Videos + Referenzpunkte +
  Winkel-Plot ergänzt.

---

## `create_trajectory.m` — Referenztrajektorie per Klick erzeugen (MP4)

**Zweck:** Manuell eine Soll-/Referenztrajektorie auf dem ersten Videoframe
festlegen, sie auf gleiche Abstände umrechnen und als `.mat` speichern.

**Ablauf:**
1. MP4 wählen (`uigetfile`), nur den **ersten Frame** lesen (`read(v,1)`, auf
   RGB gebracht).
2. `collectTrajectory(firstFrame)` (lokale Funktion): zeigt den Frame, per
   **Linksklick** wird ein rotes Kreuz gesetzt (beliebig oft), die Punkte
   werden mit einer Linie verbunden. **"Bestätigen"** (oder Fenster schließen)
   beendet die Eingabe. Event-gesteuert/flackerfrei (Bild + Marker einmal
   anlegen, nur `set(XData/YData)`). Rückgabe `pts = [x,y]` in Klick-Reihenfolge.
3. **Gleiche Abstände, gleiche Punktanzahl:** dichte Spline-Kurve durch die
   Klicks (`spline`, 2000 Punkte), Bogenlänge `s` (streng monoton via `unique`),
   dann `nPts` (= Anzahl Klicks) gleichmäßig über `s` verteilte Punkte
   (`interp1`). Methode angelehnt an die äquidistante Resampling-Logik in
   `tip_track_matching_spline.m`, aber mit **fester Punktanzahl** statt festem
   Abstand `d`.
4. Ergebnis-Plot über dem ersten Frame (Spline + äquidistante Punkte).
5. Speichern neben dem Video als `<videoname>_trajectory.mat` mit
   `TipCoordinates` (äquidistant, `[row,col]`) und `clickedPoints`
   (rohe Klicks, `[x,y]`).

---

## Git / Workflow

- Entwicklungsbranch: **`claude/magical-noether-e66dy1`** (Repo
  `LucaMuskelmasse/mhh`). Commits/Pushes gehen dorthin; keine PRs ohne
  ausdrückliche Aufforderung.
