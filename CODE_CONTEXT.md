# Code-Kontext – Repository `mhh`

Diese Datei fasst den wichtigen Kontext aller `.m`-Dateien zusammen, damit der
Konversationsverlauf gelöscht werden kann, ohne Verständnis über den Code zu
verlieren. Stand: 2026-07-01.

Das Repository enthält die **Bildauswertungs- / Tracking-Skripte**
(Auswertung der aufgenommenen Bilder bzw. Videos): `kruemung.m`,
`tip_track_matching_spline.m`, `cochlea_model_tracking2.m`,
`create_trajectory.m`.

(`cochlea_model_tracking.m`, der Vorläufer von `cochlea_model_tracking2.m`
mit manueller Tip-Zuweisung per Suchradius/Klick-Korrektur, wurde gelöscht;
`cochlea_model_tracking2.m` ist die aktuelle, vollautomatische Video-Variante.)

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
  Vorzeichendefinition von Winkeln (siehe `cochlea_model_tracking2.m`).
- **Binarisierungs-Konvention beim Tracking:** Elektrode/Draht = `0` (schwarz),
  Hintergrund = `1` (weiß) bzw. Vordergrund `fg` = `true` bei der Background-
  Subtraction in `cochlea_model_tracking2.m`. Das Tracking sucht dort, wo die
  Elektrode als dunkler Bereich vom Hintergrund abweicht.
- **`ImageData`-Struct-Array (nur `kruemung.m`/`tip_track_matching_spline.m`):**
  pro Frame ein Eintrag mit Feldern wie `name`, `path`, `gray`/`rgb`, `bw`,
  ggf. `skel`, `xs`, `ys`, `kappa`.
- **Persistenz:** Trajektorien werden als `.mat` neben den Daten gespeichert.
  `tip_track_matching_spline.m` fragt beim nächsten Start per `questdlg`
  "Alte verwenden / Neu zuweisen"; `cochlea_model_tracking2.m` lädt IMMER eine
  vorher mit `create_trajectory.m` erzeugte `.mat` (keine eigene Neuzuweisung).
- **Tracking-Pipeline (nur `kruemung.m`/`tip_track_matching_spline.m`):** feste
  Workspace-Maske (Rechteck) + runde Tip-Suchmaske → größte zusammenhängende
  Komponente im Komplement → geodätische Distanztransformation
  (`bwdistgeodesic`) liefert den am weitesten entfernten Punkt = Tip.
  Plausibilitätsprüfungen (Krümmung, Konnektivität), bei Fehlschlag
  Vektorprädiktion + progressive Suche, sonst manuelles Klicken.
  `cochlea_model_tracking2.m` verwendet ein **anderes, trapezbasiertes**
  Verfahren ohne manuelle Korrektur (siehe eigener Abschnitt unten).

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
   manuelle Kontrolle (hier noch mit Slider; `cochlea_model_tracking2.m` hat
   dagegen KEINE manuelle Kontrolle mehr — vollautomatisch). Klick setzt Tip
   neu, "Bestätigen" beendet.
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

## `cochlea_model_tracking2.m` — Tip-Tracking aus MP4-Videos (Hauptskript, vollautomatisch)

**Zweck:** Ersetzt `cochlea_model_tracking.m` (gelöscht) vollständig. Verarbeitet
**einen ganzen Ordner mit mehreren MP4-Videos** (Dateinamen z.B.
`2026-06-23_TP07_V01_F1_Camera1.mp4`, dann `V02`, …; `*_Camera2.mp4` wird
ignoriert) nacheinander. Pro Video wird die Elektrodenspitze **komplett
automatisch** getrackt (KEINE manuelle Korrektur, KEIN Suchradius-Klick mehr —
bewusst gegenüber der Vorgängerversion entfernt) und Winkel, Insertionstiefe
und Kraft werden berechnet und geplottet.

**Bedienreihenfolge beim Start (3 modale Auswahlfenster, in dieser Reihenfolge):**
1. **`selectPreviewMode()`** — "RGB Image" / "BW Maske": legt fest, was die
   Live-Vorschau während des Trackings zeigt (RGB-Frame oder die binäre
   Vordergrundmaske `fg`). Dient zum visuellen Einstellen der
   Background-Subtraction-Parameter, v.a. für Ordner 2.
2. **`selectFolderScenario()`** — "Ordner 1" / "Ordner 2" / "Ordner 3": legt
   fest, welcher Standardpfad (`defaultPath1/2/3`) für den anschließenden
   `uigetdir`-Ordnerdialog vorgeschlagen wird, UND welcher Parametersatz
   aktiv ist (siehe unten).
3. **`selectVideoMode()`** — "Ein Video" / "Alle Videos": bei "Ein Video" wird
   zusätzlich per `uigetfile` genau ein `*_Camera1.mp4` aus dem gewählten
   Ordner ausgewählt und NUR dieses verarbeitet; bei "Alle Videos" wie bisher
   alle `*_Camera1.mp4` im Ordner nacheinander (alphabetisch, `V01, V02, …`).

Alle drei Funktionen sind lokale Funktionen am Dateiende, gleiches Muster:
`uicontrol`-Pushbuttons + `uiwait/uiresume`, Rückgabe `[]` falls das Fenster
ohne Auswahl geschlossen wurde (führt zu `error(...)`).

**Ordner-spezifische Parameter (jeweils eigene Sätze, oben im Code):**
- **Ordner 1:** keine Sonderbehandlung — Original-Parameter
  (`numBgFrames`/`fgThreshold`/`minBlobSize`), keine Trajektorie-Transformation.
- **Ordner 2:** eigene Background-Subtraction-Parameter
  (`numBgFrames2`/`fgThreshold2`/`minBlobSize2`) UND eigene
  Ähnlichkeitstransformation (`simRotationDeg2`/`simScale2`/`simTranslation2`).
- **Ordner 3:** eigene Ähnlichkeitstransformation
  (`simRotationDeg3`/`simScale3`/`simTranslation3`), Background-Subtraction
  wie Ordner 1.
- Die Trajektorie-`.mat` (aus `create_trajectory.m`) liegt für ALLE Ordner
  in **Ordner 1** — der Auswahldialog dafür startet daher immer in
  `defaultPath1`, unabhängig vom gewählten Ordner-Szenario.

**Ähnlichkeitstransformation (Ordner 2/3):** bildet die in Ordner 1 erstellte
Trajektorie + Mittelpunkt `M` in das Koordinatensystem des jeweiligen Ordners
ab. Rotation und Skalierung erfolgen **um `M`** (relativ zu `M`, `M` bewegt
sich dabei nicht), danach zusätzliche Verschiebung um `simTranslation`:
`[x';y'] = simScale * R(simRotationDeg) * ([x;y] - M) + M + simTranslation`.
Wird VOR der Trapez-Berechnung angewendet → Trapeze sind automatisch mit
transformiert. `rectWidth`/`rectHeight` werden zusätzlich mit `simScale`
skaliert, damit die Trapezgröße im neuen Maßstab weiterhin der tatsächlichen
Elektrodengröße entspricht (`widthSlope`/`heightSlope` bleiben unverändert, da
sie bereits relativ zum – ebenfalls transformierten – Abstand zu `M` skalieren).

**Trapezbasierte Tip-Suche (Kernalgorithmus, pro Video):**
1. Pro Trajektorienpunkt wird ein an Tangente/Normale ausgerichtetes Viereck
   berechnet (Tangente via `gradient(xs,ys)`, Normale = 90°-Rotation der
   Tangente). **Jede der 4 Ecken wird einzeln** nach ihrem Abstand zu `M`
   skaliert (`rectWidth/rectHeight` als Grundmaß bei Abstand 0,
   `widthSlope/heightSlope` als Zuwachs pro Pixel Abstand) → aus Rechtecken
   werden dadurch Trapeze. Statisch, einmal pro Video vorberechnet
   (`allCorners`, `allMasks` via `poly2mask`).
2. **Background Subtraction:** Hintergrund = Mittel der ersten `numBgFrames`
   Frames (statisch, elektrodenfrei). Pro Frame
   `diffImg = |gray − bgGray|/255`, `fg = diffImg > fgThreshold`,
   `bwareaopen(fg, minBlobSize)` (Elektrode = `fg`, `true`/schwarz).
3. **Suchreihenfolge:** global wird einmal festgelegt, ob Trajektorienindex 1
   oder `nP` näher an `M` liegt (`dFirst`/`dLast`) → `searchOrder` +
   `stepDir` (±1). `idxLast` = das vom-`M`-Ende aus zuletzt durchsuchte
   Trajektorienende = der **Eingang** (Fallback-Position).
4. **Lokale Suche pro Frame (WICHTIG, letzte Änderung):** statt jeden Frame
   die komplette Trajektorie ab `M`-Ende zu durchsuchen, startet die Suche ab
   dem Trapez, das `searchAhead` (Default 5) Trapeze näher an `M` liegt als
   das im VORHERIGEN Frame gefundene Trapez (`prevFoundIdx`), und läuft von
   dort in derselben Richtung weiter bis zum Eingang (`localSearchOrder`).
   Grund: Verhindert Fehlzuweisungen an weit entfernten, physikalisch
   unplausiblen Trapezen nahe `M` und reduziert die Anzahl geprüfter Trapeze.
   Deckt Vorwärtssprünge bis `searchAhead` Trapeze UND beliebige
   Rückwärtsbewegung ab (Suche läuft immer bis zum Eingang durch).
5. Im **ersten** Trapez der lokalen Suchreihenfolge mit schwarzen Pixeln wird
   der Schwerpunkt der **größten zusammenhängenden schwarzen Fläche**
   (`bwconncomp` + `regionprops('Area','Centroid')`) als Tip übernommen.
   Findet sich in KEINEM der lokal durchsuchten Trapeze ein schwarzer Pixel,
   wird der Tip auf den **Eingang** (`idxLast`) zurückgesetzt.
6. **Live-Vorschau** (`figure 'Tip-Tracking V0x'`, optional via `showPreview`):
   Bild (RGB oder BW je nach `previewMode`), Trajektorie, alle Trapeze (rot),
   gefundenes Trapez (grün) + Tip-Kreuz werden EINMAL angelegt und nur per
   `set(...,'CData'/'XData'/'YData',...)` aktualisiert (flackerfrei). Wird
   nach jedem Video geschlossen; Ergebnis-Plots bleiben offen.

**Berechnete Größen pro Video (nach der Frame-Schleife):**
- **Insertionstiefe:** da die Trajektorienpunkte äquidistant sind (siehe
  `create_trajectory.m`), ergibt sich der Fortschritt entlang der Trajektorie
  (0 = Eingang, 1 = anderes Ende) direkt aus dem Punktindex des gefundenen
  Tips: `insertionDepth = |tipIdxFrame - idxLast| / (nP-1) * insertionDepthMax`
  (`insertionDepthMax` = tatsächliche Tiefe am Trajektorienende in mm).
- **Winkel:** zwischen Referenzlinie (`M`→Eingang) und Tip-Linie (`M`→Tip),
  **gegen den Uhrzeigersinn = positiv** (`atan2d(ay*bx-ax*by, ax*bx+ay*by)`,
  y zeigt im Bild nach unten). Über die gültigen Frames **entfaltet**
  (`unwrap`), kann >180°/360° werden. Null = Tip auf der Referenzlinie.
- **CSV-Messdaten:** passende `<...>_F1.csv` (Videoname ohne `_Camera1`),
  deutsches Format (`;`-getrennt, `,`-Dezimalzeichen, 1 Kopfzeile). Spalte U
  = TimeStamp, Spalte C = Kraft z, Spalte Y = Frame-Nummer. Pro Video-Frame
  wird die ERSTE CSV-Zeile mit passender Frame-Nummer verwendet
  (`find(csvFrameNo==f,1,'first')`).
- **Glättung:** Winkel, Insertionstiefe und Kraft z werden zusätzlich mit
  `smooth(..., smoothSpan)` geglättet (gleitender Mittelwert).

**Plots pro Video:**
- `Tip Trajectory V0x`: grüne Kreuze (Tip je Frame) + Linie, `M` (cyan),
  Eingang (magenta), Referenzlinie, `axis ij`.
- `Übersicht V0x`: EIN Figure mit `subplot(3,2,...)` — 3 Zeilen (Winkel über
  TimeStamp / Insertionstiefe über TimeStamp / Kraft z über Winkel) × 2
  Spalten (roh | geglättet, geglättet mit grauer Roh-Linie + farbiger
  geglätteter Linie + Legende).

**Ergebnis-Struct (pro Video als `<videoname>_results.mat` gespeichert):**
`results` mit Feldern `video`, `label`, `frame`, `timestamp`, `force`,
`forceSmoothed`, `angle`, `angleSmoothed`, `insertionDepth`,
`insertionDepthSmoothed`.

**Lokale Funktionen:** `selectFolderScenario()`, `selectVideoMode()`,
`selectPreviewMode()` — alle nach demselben Muster (Pushbuttons +
`uiwait/uiresume`, siehe oben).

**Historie der Designentscheidungen für dieses Skript (chronologisch):**
1. Aus `cochlea_model_tracking.m` entstanden: Umstellung von
   Suchradius-Zuweisung + manueller Klick-Korrektur auf **vollautomatische**
   trapezbasierte Suche (kein `reviewTips` mehr).
2. Trapez-Suche vom `M`-nahen Ende zum Eingang, Fallback auf Eingang bei
   Nichtfund; Frame-für-Frame chronologisch statt ab `startFrame`.
3. Mittelpunkt wird in `create_trajectory.m` geklickt und in der `.mat`
   mitgespeichert (`cochleaCenter`), nicht mehr pro Video neu geklickt.
4. Ordner-Stapelverarbeitung (`*_Camera1.mp4`, `V01,V02,…`), EINE Trajektorie
   gilt für alle Videos, RGB-Live-Vorschau, automatischer Videowechsel ohne
   Bestätigungsdialog.
5. Winkel-Plot über TimeStamp/Kraft aus CSV (statt Frame-Nummer), CSV-Frame-
   Zuordnung über Spalte Y.
6. Insertionstiefe (aus Trajektorienindex), Glättung (Winkel/Insertionstiefe/
   Kraft), Zusammenfassung aller Plots in einer `Übersicht`-Subplot-Figure,
   Ergebnis-Struct + `.mat`.
7. Ordner-1/2/3-Auswahl mit je eigenen Background-Subtraction- und
   Ähnlichkeitstransformations-Parametern (Ordner 2/3); Ein-Video/Alle-Videos-
   Auswahl; RGB/BW-Vorschau-Umschalter zum Parameter-Tuning.
8. **Lokale Trapez-Suche** (`searchAhead`, ankert an der Zuweisung des
   Vorframes) statt globaler Suche ab dem `M`-Ende bei jedem Frame — behebt
   Fehlzuweisungen an weit entfernten Trapezen.

---

## `create_trajectory.m` — Referenztrajektorie per Klick erzeugen (MP4)

**Zweck:** Manuell eine Soll-/Referenztrajektorie auf dem ersten Videoframe
festlegen, sie auf gleiche Abstände umrechnen und als `.mat` speichern.

**Ablauf:**
1. MP4 wählen (`uigetfile`), nur den **ersten Frame** lesen (`read(v,1)`, auf
   RGB gebracht).
2. **Mittelpunkt anklicken** (1 Linksklick, `ginput(1)`) → `cochleaCenter`
   (`[x,y]=[col,row]`, cyan markiert). Wird von `cochlea_model_tracking2.m`
   als `M` verwendet.
3. `collectTrajectory(firstFrame)` (lokale Funktion): zeigt den Frame, per
   **Linksklick** wird ein rotes Kreuz gesetzt (beliebig oft), die Punkte
   werden mit einer Linie verbunden. **"Bestätigen"** (oder Fenster schließen)
   beendet die Eingabe. Event-gesteuert/flackerfrei (Bild + Marker einmal
   anlegen, nur `set(XData/YData)`). Rückgabe `pts = [x,y]` in Klick-Reihenfolge.
4. **Gleiche Abstände, gleiche Punktanzahl:** dichte Spline-Kurve durch die
   Klicks (`spline`, 2000 Punkte), Bogenlänge `s` (streng monoton via `unique`),
   dann `nPts` (= Anzahl Klicks) gleichmäßig über `s` verteilte Punkte
   (`interp1`). Methode angelehnt an die äquidistante Resampling-Logik in
   `tip_track_matching_spline.m`, aber mit **fester Punktanzahl** statt festem
   Abstand `d`.
5. Ergebnis-Plot über dem ersten Frame (Mittelpunkt, rohe Klicks, Spline +
   äquidistante Punkte).
6. Speichern neben dem Video als `<videoname>_trajectory.mat` mit
   `TipCoordinates` (äquidistant, `[row,col]`), `clickedPoints`
   (rohe Klicks, `[x,y]`) und `cochleaCenter` (`[x,y]`).

---

## Git / Workflow

- Entwicklungsbranch: **`claude/magical-noether-e66dy1`** (Repo
  `LucaMuskelmasse/mhh`). Commits/Pushes gehen dorthin; keine PRs ohne
  ausdrückliche Aufforderung.
