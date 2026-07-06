% Function (Schritt 5 - automatische Tip-Zuweisung über alle Frames, Ordnerlauf):
% 1. Einen ORDNER mit MP4-Videos auswählen. Verarbeitet werden nur die
%    *_Camera1.mp4 (V01, V02, ...); *_Camera2.mp4 werden ignoriert.
% 2. EINE Trajektorie-Datei (.mat mit TipCoordinates + cochleaCenter, erzeugt
%    von create_trajectory.m) auswählen - sie gilt für ALLE Videos im Ordner.
% 3. Jedes Video nacheinander mit demselben Algorithmus bearbeiten:
%    - Passende Messdaten-CSV laden (<...>_F1.csv, deutsches Format: ; und ,),
%      mit TimeStamp (Spalte U), Kraft in z-Richtung (Spalte C) und Frame-Nummer
%      (Spalte Y). Zu jedem Frame wird die ERSTE Zeile mit dieser Frame-Nummer
%      verwendet.
%    - Hintergrund-Referenz aus den ersten Frames bilden (Background Subtraction)
%    - Pro Trajektorienpunkt ein an Tangente/Normale ausgerichtetes Viereck,
%      dessen Breite/Höhe linear mit dem Abstand zum Mittelpunkt wachsen
%      (jede Ecke einzeln skaliert -> Trapeze). Statisch -> einmal vorberechnet.
%    - ALLE Frames chronologisch ab Frame 1 durchgehen. Pro Frame:
%        * Background Subtraction
%        * Trapeze als Suchflächen durchgehen: NICHT mehr immer ab dem
%          mittelpunktsnächsten Trajektorien-Ende, sondern ab dem Trapez,
%          das searchAhead Trapeze näher an M liegt als die Zuweisung des
%          VORHERIGEN Frames, von dort in derselben Richtung weiter bis zum
%          Eingang; im ersten Trapez mit schwarzen Pixeln (Elektrode) den
%          Schwerpunkt der GRÖSSTEN schwarzen Fläche als Tip (grünes Kreuz).
%        * Findet kein Trapez schwarze Pixel, wird der Tip auf das rote Kreuz des
%          Trajektorien-Eingangs gesetzt (= zuletzt durchsuchter Punkt).
%    - Tip-Trajektorie (grüne Kreuze), Winkel über TimeStamp und Winkel über
%      Kraft z anzeigen.
% 4. In jedem Figure-Titel steht zusätzlich, welches V0x bearbeitet wird. Die
%    Plots bleiben offen; die Videos laufen automatisch nacheinander durch.
% 5. Vor der Ordnerauswahl öffnet sich ein Fenster mit 4 Buttons (Ordner 1/2/3/4):
%    - Ordner 1: Verarbeitung wie oben beschrieben, unverändert.
%    - Ordner 2, 3 und 4: zusätzlich wird eine Ähnlichkeitstransformation
%      (Rotation, Skalierung, Translation; Parameter oben einstellbar, JEWEILS
%      EIGENE für Ordner 2, 3 und 4) auf die geladene Trajektorie und den
%      Mittelpunkt angewendet, bevor die Trapeze berechnet werden - die
%      Trapeze sind dadurch automatisch mit transformiert.
%    - Ordner 4: die Videos werden zusätzlich RÜCKWÄRTS abgespielt (letzter
%      echter Frame zuerst). Der Hintergrund kommt daher aus den letzten
%      echten Frames, die CSV-Daten (TimeStamp/Kraft) werden an die
%      Wiedergabe-Position gebunden -> die Zeitachse läuft vorwärts.
% 6. Danach ein weiteres Fenster mit 2 Buttons (Ein Video / Alle Videos):
%    - Ein Video: EIN bestimmtes Video aus dem Ordner auswählen und nur
%      dieses bearbeiten.
%    - Alle Videos: wie bisher werden alle *_Camera1.mp4 im Ordner nacheinander
%      bearbeitet.
% 7. GANZ ZU BEGINN (vor allen anderen Fenstern) ein Fenster mit 2 Buttons
%    (RGB Image / BW Maske) zum Testen der Background-Subtraction-Parameter:
%    legt fest, ob die Live-Vorschau (Abschnitt 5) das RGB-Bild oder die
%    binäre Vordergrundmaske zeigt. Ordner 2 und Ordner 4 verwenden dabei
%    eigene Background-Subtraction-Parameter (numBgFrames2.../numBgFrames4...),
%    Ordner 1 und 3 die ursprünglichen (numBgFrames/fgThreshold/minBlobSize).
%
% Es gibt KEINE Tip-Zuweisung per Suchradius und KEINE manuelle Korrektur mehr
% (gegenüber cochlea_model_tracking.m bewusst entfernt). Background Subtraction
% bleibt erhalten.

clear; clc; close all;

%% Parameter (oben einstellbar)
% --- Vierecke um jeden Trajektorienpunkt ---
% Breite = tangential (entlang Trajektorie), Höhe = normal (quer dazu).
% Grundmaße gelten bei Abstand 0 zum Mittelpunkt; pro Pixel Abstand wachsen
% Breite und Höhe linear (Steigung). Da jede Ecke EINZELN nach ihrem Abstand
% zum Mittelpunkt skaliert wird, werden die Boxen zu Trapezen / echten Vierecken.
rectWidth   = 4;     % Grundbreite (tangential) bei Abstand 0 [px]
rectHeight  = 10;    % Grundhöhe   (normal)     bei Abstand 0 [px]
widthSlope  = 0.05;  % Breitenzuwachs je px Abstand zum Mittelpunkt [px/px]
heightSlope = 0.4;   % Höhenzuwachs   je px Abstand zum Mittelpunkt [px/px]

% --- Lokale Trapez-Suche (pro Frame) ---
% Statt bei JEDEM Frame die komplette Trajektorie vom Mittelpunkt-Ende her zu
% durchsuchen, startet die Suche ab dem Trapez, das searchAhead Trapeze näher
% an M liegt als das zuletzt zugewiesene Trapez, und läuft von dort in der
% ursprünglichen Richtung bis zum Trajektorien-Eingang weiter. Das reduziert
% die Anzahl geprüfter Trapeze und verhindert Fehlzuweisungen an weit
% entfernten (unplausiblen) Trapezen nahe M.
searchAhead = 5;     % Trapeze "Vorsprung" Richtung M ab der letzten Zuweisung

% --- Background-Subtraction-Parameter (wie in cochlea_model_tracking.m) ---
% Gelten für Ordner 1 und Ordner 3 unverändert.
numBgFrames = 5;     % Anzahl früher (elektrodenfreier) Frames für den Hintergrund
fgThreshold = 0.15;  % Schwellwert (0..1) für die Differenz: größer = strenger
minBlobSize = 50;    % kleinste Vordergrund-Fläche (Pixel), kleinere werden entfernt

% --- Background-Subtraction-Parameter NUR für Ordner 2 (gesondert einstellbar) ---
numBgFrames2 = 5;     % Anzahl früher (elektrodenfreier) Frames für den Hintergrund
fgThreshold2 = 0.15;  % Schwellwert (0..1) für die Differenz: größer = strenger
minBlobSize2 = 50;    % kleinste Vordergrund-Fläche (Pixel), kleinere werden entfernt

% --- Background-Subtraction-Parameter NUR für Ordner 4 (gesondert einstellbar) ---
% Ordner-4-Videos werden RÜCKWÄRTS abgespielt -> die elektrodenfreien Frames
% (Hintergrund) sind am VideoENDE (= Anfang der Rückwärts-Wiedergabe).
numBgFrames4 = 5;     % Anzahl (in Wiedergaberichtung erster) elektrodenfreier Frames
fgThreshold4 = 0.15;  % Schwellwert (0..1) für die Differenz: größer = strenger
minBlobSize4 = 50;    % kleinste Vordergrund-Fläche (Pixel), kleinere werden entfernt

% --- Live-Vorschau während des Durchlaufs ---
showPreview = true;  % true = aktuellen Frame + Tip beim Durchlauf anzeigen

% --- Glättungsparameter für Winkel-über-TimeStamp-Plot ---
smoothSpan = 15;     % Breite des gleitenden Mittelwerts (Frames); ungerade empfohlen

% --- Insertionstiefe ---
% Trajektorienpunkte sind äquidistant (siehe create_trajectory.m) -> der
% Fortschritt entlang der Trajektorie (0 = Eingang, 1 = anderes Ende) ergibt
% sich direkt aus dem Punktindex. Multipliziert mit der tatsächlichen Tiefe
% am Trajektorienende ergibt sich die Insertionstiefe in mm.
insertionDepthMax = 28;   % tatsächliche Tiefe am Trajektorienende [mm]

% --- Standard-Startpfade für die 4 Ordner-Buttons (unten anpassen) ---
defaultPath1 = 'M:\nascas2\Students\Wöhlken\Tracking_Videos\Versuche_7';
defaultPath2 = 'M:\nascas2\Students\Wöhlken\Tracking_Videos\SlimStraigth_EA';
defaultPath3 = 'M:\nascas2\Students\Wöhlken\Tracking_Videos\vers_Lichter';
defaultPath4 = 'M:\nascas2\Students\Wöhlken\Tracking_Videos\eval';

% --- Ähnlichkeitstransformation der Trajektorie (bei Ordner 2 bzw. Ordner 3) ---
% Bildet Trajektorie + Mittelpunkt vom Koordinatensystem, in dem sie erstellt
% wurden, in das Koordinatensystem der Ordner-2- bzw. Ordner-3-Videos ab.
% Rotation und Skalierung erfolgen um den Mittelpunkt M (relativ zu M);
% anschließend wird zusätzlich um simTranslation verschoben:
%   [x'; y'] = simScale * R(simRotationDeg) * ([x;y] - M) + M + simTranslation'
% Ordner 2 und Ordner 3 haben JEWEILS EIGENE, unabhängige Parameter.
simRotationDeg2 = 0;             % Rotation um M [°] für Ordner 2, gegen den Uhrzeigersinn positiv
simScale2       = 1;             % Skalierungsfaktor (um M) für Ordner 2
simTranslation2 = [0, 0];        % [tx, ty] zusätzliche Verschiebung [px] für Ordner 2

simRotationDeg3 = 0;             % Rotation um M [°] für Ordner 3, gegen den Uhrzeigersinn positiv
simScale3       = 2;             % Skalierungsfaktor (um M) für Ordner 3
simTranslation3 = [230, 200];    % [tx, ty] zusätzliche Verschiebung [px] für Ordner 3

simRotationDeg4 = 0;             % Rotation um M [°] für Ordner 4, gegen den Uhrzeigersinn positiv
simScale4       = 1;             % Skalierungsfaktor (um M) für Ordner 4
simTranslation4 = [0, 0];        % [tx, ty] zusätzliche Verschiebung [px] für Ordner 4

%% -1. Vorschau-Anzeige auswählen (RGB Image / BW Maske) - zum Testen der
%      Background-Subtraction-Parameter (v.a. für Ordner 2)
previewMode = selectPreviewMode();
if isempty(previewMode)
    error('Kein Vorschau-Modus ausgewählt');
end

%% 0. Ordner-Szenario auswählen (Ordner 1 / 2 / 3 / 4)
folderChoice = selectFolderScenario();
if isempty(folderChoice)
    error('Kein Ordner-Szenario ausgewählt');
end
reverseVideo = false;   % Standard: Frames in normaler Reihenfolge verarbeiten
switch folderChoice
    case 1
        defaultPath = defaultPath1;
    case 2
        defaultPath = defaultPath2;
        % Ordner 2: eigene Background-Subtraction-Parameter + eigene
        % Ähnlichkeitstransformation verwenden
        numBgFrames = numBgFrames2;
        fgThreshold = fgThreshold2;
        minBlobSize = minBlobSize2;
        simRotationDegActive = simRotationDeg2;
        simScaleActive       = simScale2;
        simTranslationActive = simTranslation2;
    case 3
        defaultPath = defaultPath3;
        % Ordner 3: eigene Ähnlichkeitstransformation verwenden
        simRotationDegActive = simRotationDeg3;
        simScaleActive       = simScale3;
        simTranslationActive = simTranslation3;
    case 4
        defaultPath = defaultPath4;
        % Ordner 4: eigene Background-Subtraction-Parameter + eigene
        % Ähnlichkeitstransformation; Videos werden RÜCKWÄRTS abgespielt.
        numBgFrames = numBgFrames4;
        fgThreshold = fgThreshold4;
        minBlobSize = minBlobSize4;
        simRotationDegActive = simRotationDeg4;
        simScaleActive       = simScale4;
        simTranslationActive = simTranslation4;
        reverseVideo = true;
end

%% 1. ORDNER mit MP4-Videos auswählen
vidDir = uigetdir(defaultPath, sprintf('Ordner mit MP4-Videos auswählen (Ordner %d)', folderChoice));
if isequal(vidDir, 0)
    error('Kein Ordner ausgewählt');
end

% Nur die Camera1-Videos, alphabetisch sortiert (-> V01, V02, ...).
% Camera2-Videos (*_Camera2.mp4) werden bewusst ignoriert.
listing = dir(fullfile(vidDir, '*_Camera1.mp4'));
if isempty(listing)
    error('Keine *_Camera1.mp4-Dateien im Ordner gefunden: %s', vidDir);
end
[~, ord] = sort({listing.name});
listing = listing(ord);

%% 1b. Ein Video oder alle Videos verarbeiten?
videoModeChoice = selectVideoMode();
if isempty(videoModeChoice)
    error('Kein Video-Modus ausgewählt');
end
if videoModeChoice == 1
    % Ein einzelnes Video aus dem Ordner auswählen
    [oneVidFile, ~] = uigetfile(fullfile(vidDir, '*_Camera1.mp4'), 'Video auswählen');
    if isequal(oneVidFile, 0)
        error('Kein Video ausgewählt');
    end
    idxSel = find(strcmp({listing.name}, oneVidFile), 1);
    if isempty(idxSel)
        error('Ausgewähltes Video nicht in der Liste gefunden: %s', oneVidFile);
    end
    listing = listing(idxSel);
end
numVideos = numel(listing);

%% 2. EINE Trajektorie (.mat) auswählen - gilt für alle Videos
% Die Trajektorie liegt für alle Videos (Ordner 1/2/3) in Ordner 1 -> als
% Startverzeichnis für den Dialog wird daher immer defaultPath1 verwendet.
[matFile, matDir] = uigetfile({'*.mat','MAT-Datei mit Trajektorie (*.mat)'; '*.*','Alle Dateien (*.*)'}, ...
    'Trajektorie (.mat) auswählen (gilt für alle Videos, liegt in Ordner 1)', defaultPath1);
if isequal(matFile, 0)
    error('Keine Trajektorie ausgewählt');
end
S = load(fullfile(matDir, matFile), 'TipCoordinates', 'cochleaCenter');
if ~isfield(S, 'TipCoordinates')
    error('Die .mat enthält keine Variable "TipCoordinates".');
end
if ~isfield(S, 'cochleaCenter')
    error('Die .mat enthält keine Variable "cochleaCenter". Bitte create_trajectory.m erneut ausführen.');
end
TipCoordinates = S.TipCoordinates;   % [row, col] = [y, x]  (für alle Videos)
M = S.cochleaCenter;                 % [x, y] = [col, row]   (für alle Videos)

%% 2c. Bei Ordner 2, 3 oder 4: Ähnlichkeitstransformation auf Trajektorie + Mittelpunkt
% Rotation und Skalierung erfolgen um den Mittelpunkt M (relativ zu M) ->
% M selbst bewegt sich dabei nicht, wird aber anschließend wie die Trajektorie
% um simTranslationActive verschoben. Die Trapeze werden weiter unten aus
% dieser (dann bereits transformierten) Trajektorie berechnet und sind
% dadurch automatisch mit transformiert. Die Trapez-Grundmaße
% (rectWidth/rectHeight) werden mit simScaleActive skaliert, damit sie im
% neuen Maßstab weiterhin der tatsächlichen Elektrodengröße entsprechen.
if folderChoice == 2 || folderChoice == 3 || folderChoice == 4
    theta = deg2rad(simRotationDegActive);
    Rmat  = [cos(theta) -sin(theta); sin(theta) cos(theta)];

    xyTraj = [TipCoordinates(:,2), TipCoordinates(:,1)];        % [x, y]
    xyTraj = (simScaleActive * Rmat * (xyTraj - M).').' + M + simTranslationActive;
    TipCoordinates = [xyTraj(:,2), xyTraj(:,1)];                % zurück zu [row, col]

    M = M + simTranslationActive;   % M ist Rotations-/Skalierungszentrum -> nur Verschiebung

    rectWidth  = rectWidth  * simScaleActive;
    rectHeight = rectHeight * simScaleActive;

    fprintf(['Ähnlichkeitstransformation angewendet (Ordner %d): Rotation=%.2f°, ', ...
        'Skalierung=%.3f, Translation=[%.1f, %.1f]\n'], folderChoice, ...
        simRotationDegActive, simScaleActive, simTranslationActive(1), simTranslationActive(2));
end

%% Schleife über alle Videos im Ordner
for vi = 1:numVideos
    vidFile = listing(vi).name;
    videoFullPath = fullfile(vidDir, vidFile);
    [~, vidName, ~] = fileparts(vidFile);

    % V0x-Kennung aus dem Dateinamen herausziehen (z.B. '..._V01_...' -> 'V01')
    tok = regexp(vidName, 'V\d+', 'match', 'once');
    if isempty(tok)
        tok = vidName;   % Fallback, falls kein V0x im Namen
    end
    vLabel = tok;

    fprintf('\n=== Video %d/%d: %s (%s) ===\n', vi, numVideos, vidFile, vLabel);

    %% 2b. Passende Messdaten-CSV laden (TimeStamp Spalte U, Kraft z Spalte C, Frame Spalte Y)
    % Dateiname des Videos ohne "_Camera1" -> CSV-Name (z.B. ..._F1.csv).
    % Deutsches Format: ';' als Trennzeichen, ',' als Dezimalzeichen, 1 Kopfzeile.
    % Spalte Y (25) gibt die Frame-Nummer an; zu jedem Frame wird später die
    % ERSTE Zeile mit dieser Frame-Nummer verwendet.
    csvBase = regexprep(vidName, '_Camera1$', '');
    csvFile = fullfile(vidDir, [csvBase '.csv']);
    csvTime    = [];   % Spalte U
    csvForce   = [];   % Spalte C
    csvFrameNo = [];   % Spalte Y
    if isfile(csvFile)
        txt  = fileread(csvFile);
        txt  = strrep(txt, ',', '.');                    % Dezimalkomma -> Dezimalpunkt
        rows = regexp(txt, '\r\n|\r|\n', 'split');       % in Zeilen zerlegen
        rows = rows(~cellfun('isempty', rows));          % Leerzeilen entfernen
        if numel(rows) >= 2
            rows = rows(2:end);                          % Kopfzeile überspringen
            nCsv = numel(rows);
            csvTime    = nan(nCsv, 1);
            csvForce   = nan(nCsv, 1);
            csvFrameNo = nan(nCsv, 1);
            for r = 1:nCsv
                fld = strsplit(rows{r}, ';', 'CollapseDelimiters', false);
                if numel(fld) >= 21, csvTime(r)    = str2double(fld{21}); end  % Spalte U
                if numel(fld) >=  3, csvForce(r)   = str2double(fld{3});  end  % Spalte C
                if numel(fld) >= 25, csvFrameNo(r) = str2double(fld{25}); end  % Spalte Y
            end
        end
    else
        warning('[%s] Keine CSV gefunden: %s -> Winkel ersatzweise über Frame.', vLabel, csvFile);
    end

    %% 3. Hintergrund-Referenz aus den ersten (Wiedergabe-)Frames mitteln
    v = VideoReader(videoFullPath);
    totalFrames = v.NumFrames;

    % Wiedergabe-Reihenfolge der Frames: bei Ordner 4 rückwärts (letzter echter
    % Frame zuerst), sonst normal. frameOrder(p) = tatsächliche Video-Frame-Nr.
    % zur Wiedergabe-Position p. Der Hintergrund kommt aus den ersten nbg
    % Frames der WIEDERGABE (bei Rückwärts = die letzten echten Frames, dort
    % ist die Elektrode noch nicht/nicht mehr im Bild).
    if reverseVideo
        frameOrder = totalFrames:-1:1;
    else
        frameOrder = 1:totalFrames;
    end

    nbg = min(max(round(numBgFrames), 1), totalFrames);
    bgAccum = zeros(v.Height, v.Width);
    for b = 1:nbg
        f = read(v, frameOrder(b));
        if size(f,3) == 1
            f = repmat(f, [1 1 3]);
        end
        bgAccum = bgAccum + double(rgb2gray(f));
    end
    bgGray = medfilt2(bgAccum / nbg, [3 3]);   % statischer Hintergrund

    %% 4. Trapeze (statisch) als Suchmasken vorberechnen
    xs = TipCoordinates(:,2);   % x = Spalte
    ys = TipCoordinates(:,1);   % y = Zeile

    % Tangentenrichtung entlang der Trajektorie (gradient behandelt die Enden)
    tx = gradient(xs);
    ty = gradient(ys);
    tlen = hypot(tx, ty);
    tlen(tlen < eps) = 1;        % Schutz gegen Division durch 0 (doppelte Punkte)
    tx = tx ./ tlen;             % Einheits-Tangente
    ty = ty ./ tlen;
    % Normale = Tangente um 90° gedreht
    nx = -ty;
    ny =  tx;

    % Vorzeichen-Kombinationen der vier Ecken (entlang Tangente / Normale)
    signs = [ +1 +1;  +1 -1;  -1 -1;  -1 +1 ];

    H = v.Height;  W = v.Width;
    nP = numel(xs);
    allCorners = cell(nP, 1);   % je Punkt die 5x2-Eckpunkte (geschlossenes Polygon)
    allMasks   = cell(nP, 1);   % je Punkt die Trapez-Maske (logisch, HxW)
    for i = 1:nP
        P = [xs(i), ys(i)];
        T = [tx(i), ty(i)];   % Einheits-Tangente
        N = [nx(i), ny(i)];   % Einheits-Normale

        corners = zeros(5, 2);
        for c = 1:4
            sx = signs(c,1);   % Richtung entlang Tangente (Breite)
            sy = signs(c,2);   % Richtung entlang Normale (Höhe)

            % Basis-Ecke mit Grundmaßen -> Abstand DIESER Ecke zum Mittelpunkt
            baseCorner = P + sx*(rectWidth/2)*T + sy*(rectHeight/2)*N;
            d = hypot(baseCorner(1)-M(1), baseCorner(2)-M(2));

            % Maße wachsen linear mit dem Abstand der Ecke zum Mittelpunkt
            halfW = (rectWidth  + widthSlope  * d) / 2;
            halfH = (rectHeight + heightSlope * d) / 2;

            corners(c,:) = P + sx*halfW*T + sy*halfH*N;
        end
        corners(5,:) = corners(1,:);   % Polygon schließen
        allCorners{i} = corners;
        allMasks{i}   = poly2mask(corners(:,1), corners(:,2), H, W);
    end

    % Durchlaufreihenfolge der Suche: am Endpunkt der Trajektorie beginnen, der
    % dem Mittelpunkt M am nächsten liegt, und Richtung anderes Ende durchgehen.
    dFirst = hypot(xs(1)   - M(1), ys(1)   - M(2));
    dLast  = hypot(xs(end) - M(1), ys(end) - M(2));
    if dLast <= dFirst
        searchOrder = nP:-1:1;   % letzter Punkt ist näher an M -> von hinten nach vorne
        stepDir = -1;
    else
        searchOrder = 1:nP;      % erster Punkt ist näher an M -> von vorne nach hinten
        stepDir = 1;
    end
    idxLast = searchOrder(end);  % zuletzt durchsuchter Trajektorienpunkt (Fallback-Tip)

    %% 5. Alle Frames chronologisch durchgehen und Tip pro Frame bestimmen
    TipCoordinates2 = zeros(totalFrames, 2);   % [row, col] je Frame (grüne Kreuze)
    tipIdxFrame     = zeros(totalFrames, 1);   % Trajektorien-Index des Tips je Frame
    prevFoundIdx    = idxLast;   % Anker für die lokale Suche (Start: Eingang)

    % --- optionale Live-Vorschau: einmal anlegen, danach nur aktualisieren ---
    if showPreview
        hFig = figure('Name', ['Tip-Tracking ' vLabel], 'NumberTitle', 'off');
        hAx  = axes('Parent', hFig);
        if previewMode == 1
            hImg = imshow(zeros(H, W, 3, 'uint8'), 'Parent', hAx);   % RGB Image
        else
            hImg = imshow(false(H, W), 'Parent', hAx);               % BW Maske
        end
        hold(hAx, 'on');
        plot(hAx, M(1), M(2), 'cx', 'MarkerSize', 16, 'LineWidth', 2);  % Mittelpunkt
        plot(hAx, xs, ys, 'r+', 'MarkerSize', 8, 'LineWidth', 1.2);     % Trajektorie
        for i = 1:nP
            c = allCorners{i};
            plot(hAx, c(:,1), c(:,2), 'r-', 'LineWidth', 0.8);          % Trapeze
        end
        hBox   = plot(hAx, NaN, NaN, 'g-', 'LineWidth', 2);             % gefundenes Trapez
        hTip   = plot(hAx, NaN, NaN, 'gx', 'MarkerSize', 16, 'LineWidth', 2.5);
        hTitle = title(hAx, '');
        hold(hAx, 'off');
    end

    for fIdx = 1:totalFrames
        % fIdx = Wiedergabe-Position; frameOrder(fIdx) = tatsächliche Frame-Nr.
        % (bei Ordner 4 rückwärts). Alle Ergebnis-Arrays werden über die
        % Wiedergabe-Position indiziert -> chronologisch in Wiedergaberichtung.
        img = read(v, frameOrder(fIdx));
        if size(img,3) == 1
            img = repmat(img, [1 1 3]);
        end
        rgbFiltered = img;
        for ch = 1:3
            rgbFiltered(:,:,ch) = medfilt2(img(:,:,ch), [3 3]);
        end
        grayImg = double(rgb2gray(rgbFiltered));
        diffImg = abs(grayImg - bgGray) / 255;     % normierte Differenz 0..1
        fg = diffImg > fgThreshold;                % Vordergrund (Elektrode) = true
        fg = bwareaopen(fg, minBlobSize);          % kleine Störpixel entfernen
        bwFrame = ~fg;                             % Elektrode = 0 (schwarz), Hintergrund = 1

        % --- Lokale Suchreihenfolge: searchAhead Trapeze näher an M als die
        % letzte Zuweisung, dann in ursprünglicher Richtung bis zum Eingang ---
        startIdx = prevFoundIdx - searchAhead * stepDir;
        startIdx = min(max(startIdx, 1), nP);
        if stepDir == -1
            localSearchOrder = startIdx:-1:1;
        else
            localSearchOrder = startIdx:1:nP;
        end

        % --- Trapeze als Suchflächen durchgehen ---
        tipFound = false;
        foundIdx = idxLast;
        tipXY    = [NaN NaN];
        for i = localSearchOrder
            blackInside = fg & allMasks{i};        % schwarze Pixel im Trapez
            if any(blackInside(:))
                cc = bwconncomp(blackInside);
                rp = regionprops(cc, 'Area', 'Centroid');
                [~, k] = max([rp.Area]);           % größte zusammenhängende schwarze Fläche
                tipXY    = rp(k).Centroid;         % [x, y] = [col, row]
                foundIdx = i;
                tipFound = true;
                break;
            end
        end

        if ~tipFound
            % Kein Trapez mit schwarzen Pixeln -> Tip auf das rote Kreuz des
            % zuletzt durchsuchten Trajektorienpunkts setzen.
            tipXY = [xs(idxLast), ys(idxLast)];    % [x, y] = [col, row]
        end

        TipCoordinates2(fIdx, :) = [tipXY(2), tipXY(1)];   % [row, col]
        tipIdxFrame(fIdx) = foundIdx;                      % Trajektorien-Index des Tips
        prevFoundIdx = foundIdx;                            % Anker für den nächsten Frame

        % --- Live-Vorschau aktualisieren ---
        if showPreview && isvalid(hFig)
            if previewMode == 1
                set(hImg, 'CData', rgbFiltered);   % RGB Image
            else
                set(hImg, 'CData', fg);            % BW Maske (Vordergrund)
            end
            bc = allCorners{foundIdx};
            set(hBox, 'XData', bc(:,1), 'YData', bc(:,2));
            set(hTip, 'XData', tipXY(1), 'YData', tipXY(2));
            if tipFound
                set(hTitle, 'String', sprintf('%s | Frame %d / %d  -  Tip (x=%.1f, y=%.1f)', ...
                    vLabel, fIdx, totalFrames, tipXY(1), tipXY(2)));
            else
                set(hTitle, 'String', sprintf(['%s | Frame %d / %d  -  kein Trapez ', ...
                    'gefunden, Tip auf letztes Trajektorienkreuz'], vLabel, fIdx, totalFrames));
            end
            drawnow limitrate;
        end
    end

    % Live-Vorschau schließen (Trajektorie + Winkel bleiben offen)
    if showPreview && exist('hFig', 'var') && isvalid(hFig)
        delete(hFig);
    end

    %% 6. Tip-Trajektorie (grüne Kreuze) anzeigen (eigene Figure pro Video, bleibt offen)
    figure('Name', ['Tip Trajectory ' vLabel], 'NumberTitle', 'off');
    hold on;
    axis([1 W 1 H]);
    axis ij;                       % Bildkoordinaten (Zeile = y nach unten)
    grid on;
    title(sprintf('Automatische Tip-Trajektorie (%s, %d Frames)', vLabel, totalFrames));
    xlabel('Column (x)');
    ylabel('Row (y)');

    % grüne Kreuze (Tips pro Frame) + verbindende Linie
    plot(TipCoordinates2(:,2), TipCoordinates2(:,1), 'gx', 'MarkerSize', 8, 'LineWidth', 1.5);
    plot(TipCoordinates2(:,2), TipCoordinates2(:,1), 'g-', 'LineWidth', 1.0);

    % Mittelpunkt + Eingang (= entferntes Trajektorienende) + Referenzlinie
    cochleaEntrance = [xs(idxLast), ys(idxLast)];   % [x, y] = [col, row]
    plot(M(1), M(2), 'cx', 'MarkerSize', 15, 'LineWidth', 2);
    plot(cochleaEntrance(1), cochleaEntrance(2), 'm+', 'MarkerSize', 15, 'LineWidth', 2);
    plot([M(1) cochleaEntrance(1)], [M(2) cochleaEntrance(2)], 'm-', 'LineWidth', 1.5);
    legend({'Tip (grüne Kreuze)', 'Tip-Linie', 'Mittelpunkt', 'Eingang', 'Referenzlinie'}, ...
        'Location', 'best');
    hold off;

    %% 6b. Insertionstiefe je Frame (äquidistante Trajektorienpunkte -> linear)
    % Fortschritt entlang der Trajektorie: 0 am Eingang (idxLast), 1 am
    % anderen Ende (nächster Punkt zum Mittelpunkt). Da alle Trajektorien-
    % punkte den gleichen Abstand haben, ergibt sich der Fortschritt direkt
    % aus dem Punktindex des gefundenen Tips.
    insertionDepth = abs(tipIdxFrame - idxLast) / (nP - 1) * insertionDepthMax;

    %% 7. Winkel zwischen Referenzlinie (Mittelpunkt->Eingang) und Tip-Linie
    % Vorzeichen: gegen den Uhrzeigersinn = positiv (y-Achse zeigt im Bild nach
    % unten -> beim Kreuzprodukt berücksichtigt). Verlauf wird über die Frames
    % entfaltet (unwrap), kann also >180° / >360° werden (anguläre Insertionstiefe).
    % Null = Tip auf der Mittelpunkt->Eingang-Linie. Wie in cochlea_model_tracking.m.
    cx = M(1);   cy = M(2);                              % Mittelpunkt [x, y]
    ax = cochleaEntrance(1) - cx;                        % Referenzvektor (Eingang)
    ay = cochleaEntrance(2) - cy;

    nImg = size(TipCoordinates2, 1);
    angleDeg = nan(nImg, 1);
    for k = 1:nImg
        tc = TipCoordinates2(k, :);                      % [row, col]
        if all(tc ~= 0) && ~any(isnan(tc))
            bx = tc(2) - cx;                             % Tip-Vektor (col = x)
            by = tc(1) - cy;                             % (row = y)
            angleDeg(k) = atan2d(ay*bx - ax*by, ax*bx + ay*by);
        end
    end

    valid = ~isnan(angleDeg);
    if any(valid)
        angleUnwrapped = nan(nImg, 1);
        angleUnwrapped(valid) = rad2deg(unwrap(deg2rad(angleDeg(valid))));

        % Geglätteter Winkel (gleitender Mittelwert über die gültigen Werte)
        angleSmooth = nan(nImg, 1);
        angleSmooth(valid) = smooth(angleUnwrapped(valid), smoothSpan);

        % --- Pro Frame TimeStamp + Kraft z aus der CSV ---
        % Spalte Y enthält die Frame-Nummer. Für jeden Frame f wird die ERSTE
        % CSV-Zeile gesucht, deren Frame-Nummer == f ist, und von dort TimeStamp
        % (Spalte U) und Kraft z (Spalte C) übernommen.
        tsFrame = nan(nImg, 1);   % TimeStamp (Spalte U) je Frame
        fzFrame = nan(nImg, 1);   % Kraft z   (Spalte C) je Frame
        haveCSV = ~isempty(csvTime) && ~isempty(csvFrameNo);
        if haveCSV
            for f = 1:nImg
                idx = find(csvFrameNo == f, 1, 'first');   % erstes Auftreten von Frame f
                if ~isempty(idx)
                    tsFrame(f) = csvTime(idx);
                    fzFrame(f) = csvForce(idx);
                end
            end
            if all(isnan(tsFrame))
                warning(['[%s] Keine Frame-Nummer aus Spalte Y passte zu den Video-Frames ', ...
                    '(1..%d). Stimmt die Nummerierung (0- vs 1-basiert)?'], vLabel, nImg);
            end
        end

        % --- Zeitachse (TimeStamp, sonst Frame-Nummer als Fallback) ---
        if haveCSV
            vT = valid & ~isnan(tsFrame);
            xT = tsFrame(vT);     xlabT = 'TimeStamp (Spalte U)';
        else
            vT = valid;
            xT = find(vT);        xlabT = 'Frame (keine CSV)';
        end

        % --- Insertionstiefe glätten ---
        insertionDepthSmooth = nan(nImg, 1);
        insertionDepthSmooth(vT) = smooth(insertionDepth(vT), smoothSpan);

        % --- Kraft z je Frame (roh + geglättet) ---
        if haveCSV
            vF = valid & ~isnan(fzFrame);
            forceSmooth = nan(nImg, 1);
            forceSmooth(vF) = smooth(fzFrame(vF), smoothSpan);
        else
            vF = false(nImg, 1);
            forceSmooth = nan(nImg, 1);
        end

        % --- Übersicht: 3 Zeilen (Winkel/Zeit, Insertionstiefe/Zeit, Kraft/Winkel) ---
        %     x 2 Spalten (roh | geglättet)
        figure('Name', ['Übersicht ' vLabel], 'NumberTitle', 'off');

        subplot(3,2,1);
        plot(xT, angleUnwrapped(vT), 'b.-', 'LineWidth', 1.2, 'MarkerSize', 8);
        grid on; xlabel(xlabT); ylabel('Winkel [°]');
        title('Winkel über TimeStamp (roh)');

        subplot(3,2,2);
        hold on;
        plot(xT, angleUnwrapped(vT), 'Color', [0.7 0.7 0.7], 'LineStyle', '-', ...
            'Marker', '.', 'MarkerSize', 6, 'LineWidth', 0.6, 'DisplayName', 'Roh');
        plot(xT, angleSmooth(vT), 'b-', 'LineWidth', 1.8, ...
            'DisplayName', sprintf('Geglättet (span=%d)', smoothSpan));
        hold off;
        grid on; xlabel(xlabT); ylabel('Winkel [°]');
        title('Winkel über TimeStamp (geglättet)');
        legend('Location', 'best');

        subplot(3,2,3);
        plot(xT, insertionDepth(vT), 'b.-', 'LineWidth', 1.2, 'MarkerSize', 8);
        grid on; xlabel(xlabT); ylabel('Insertionstiefe [mm]');
        title('Insertionstiefe über TimeStamp (roh)');

        subplot(3,2,4);
        hold on;
        plot(xT, insertionDepth(vT), 'Color', [0.7 0.7 0.7], 'LineStyle', '-', ...
            'Marker', '.', 'MarkerSize', 6, 'LineWidth', 0.6, 'DisplayName', 'Roh');
        plot(xT, insertionDepthSmooth(vT), 'b-', 'LineWidth', 1.8, ...
            'DisplayName', sprintf('Geglättet (span=%d)', smoothSpan));
        hold off;
        grid on; xlabel(xlabT); ylabel('Insertionstiefe [mm]');
        title('Insertionstiefe über TimeStamp (geglättet)');
        legend('Location', 'best');

        subplot(3,2,5);
        plot(angleUnwrapped(vF), fzFrame(vF), 'b.-', 'LineWidth', 1.0, 'MarkerSize', 8);
        grid on; xlabel('Winkel [°]'); ylabel('Kraft z-Richtung (Spalte C)');
        title('Kraft z über Winkel (roh)');

        subplot(3,2,6);
        hold on;
        plot(angleUnwrapped(vF), fzFrame(vF), 'Color', [0.7 0.7 0.7], 'LineStyle', '-', ...
            'Marker', '.', 'MarkerSize', 6, 'LineWidth', 0.6, 'DisplayName', 'Roh');
        plot(angleUnwrapped(vF), forceSmooth(vF), 'r-', 'LineWidth', 1.8, ...
            'DisplayName', sprintf('Geglättet (span=%d)', smoothSpan));
        hold off;
        grid on; xlabel('Winkel [°]'); ylabel('Kraft z-Richtung (Spalte C)');
        title('Kraft z über Winkel (geglättet)');
        legend('Location', 'best');

        sgtitle(sprintf('Übersicht (%s)', vLabel));

        % --- Alle Ergebnisse in einem Struct sammeln ---
        results = struct( ...
            'video',         vidName, ...
            'label',         vLabel, ...
            'frame',         (1:nImg).', ...
            'timestamp',     tsFrame, ...
            'force',         fzFrame, ...
            'forceSmoothed', forceSmooth, ...
            'angle',         angleUnwrapped, ...
            'angleSmoothed', angleSmooth, ...
            'insertionDepth', insertionDepth, ...
            'insertionDepthSmoothed', insertionDepthSmooth);

        % Neben dem Video als <videoname>_results.mat speichern
        resFile = fullfile(vidDir, [vidName '_results.mat']);
        save(resFile, 'results');
        fprintf('[%s] Ergebnisse gespeichert: %s\n', vLabel, resFile);
    end

    % Plots bleiben offen; automatisch weiter zum nächsten Video
    if vi == numVideos
        fprintf('\nAlle %d Videos verarbeitet.\n', numVideos);
    end
end


%% Lokale Funktion: Ordner-Szenario per Button auswählen
function choice = selectFolderScenario()
%SELECTFOLDERSCENARIO  Modales Fenster mit 4 Buttons (Ordner 1/2/3/4).
%   Rückgabe: 1, 2, 3 oder 4 je nach gedrücktem Button; [] falls das Fenster
%   ohne Auswahl geschlossen wurde.

    choice = [];

    hFig = figure('Name', 'Ordner auswählen', 'NumberTitle', 'off', ...
        'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
        'Position', [500 500 440 140]);

    uicontrol('Parent', hFig, 'Style', 'text', 'String', 'Welcher Ordner?', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.9 0.25], ...
        'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Ordner 1', ...
        'Units', 'normalized', 'Position', [0.04 0.15 0.21 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(1));
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Ordner 2', ...
        'Units', 'normalized', 'Position', [0.28 0.15 0.21 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(2));
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Ordner 3', ...
        'Units', 'normalized', 'Position', [0.52 0.15 0.21 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(3));
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Ordner 4', ...
        'Units', 'normalized', 'Position', [0.76 0.15 0.21 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(4));

    set(hFig, 'CloseRequestFcn', @(s,e) closeFig());

    uiwait(hFig);   % blockiert, bis ein Button gedrückt / Fenster geschlossen wird

    % ---------- verschachtelte Funktionen ----------
    function setChoice(c)
        choice = c;
        closeFig();
    end

    function closeFig()
        if isvalid(hFig)
            uiresume(hFig);
            delete(hFig);
        end
    end
end


%% Lokale Funktion: Ein Video oder alle Videos verarbeiten?
function choice = selectVideoMode()
%SELECTVIDEOMODE  Modales Fenster mit 2 Buttons (Ein Video / Alle Videos).
%   Rückgabe: 1 = Ein Video, 2 = Alle Videos; [] falls das Fenster ohne
%   Auswahl geschlossen wurde.

    choice = [];

    hFig = figure('Name', 'Video-Modus auswählen', 'NumberTitle', 'off', ...
        'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
        'Position', [500 500 300 140]);

    uicontrol('Parent', hFig, 'Style', 'text', 'String', 'Ein Video oder alle Videos?', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.9 0.25], ...
        'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Ein Video', ...
        'Units', 'normalized', 'Position', [0.07 0.15 0.4 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(1));
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Alle Videos', ...
        'Units', 'normalized', 'Position', [0.53 0.15 0.4 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(2));

    set(hFig, 'CloseRequestFcn', @(s,e) closeFig());

    uiwait(hFig);   % blockiert, bis ein Button gedrückt / Fenster geschlossen wird

    % ---------- verschachtelte Funktionen ----------
    function setChoice(c)
        choice = c;
        closeFig();
    end

    function closeFig()
        if isvalid(hFig)
            uiresume(hFig);
            delete(hFig);
        end
    end
end


%% Lokale Funktion: Vorschau-Anzeige auswählen (RGB Image / BW Maske)
function choice = selectPreviewMode()
%SELECTPREVIEWMODE  Modales Fenster mit 2 Buttons (RGB Image / BW Maske).
%   Legt fest, was die Live-Vorschau während des Trackings zeigt - dient zum
%   Testen/Einstellen der Background-Subtraction-Parameter (v.a. Ordner 2).
%   Rückgabe: 1 = RGB Image, 2 = BW Maske; [] falls ohne Auswahl geschlossen.

    choice = [];

    hFig = figure('Name', 'Vorschau-Anzeige auswählen', 'NumberTitle', 'off', ...
        'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
        'Position', [500 500 300 140]);

    uicontrol('Parent', hFig, 'Style', 'text', 'String', 'Live-Vorschau: RGB oder BW?', ...
        'Units', 'normalized', 'Position', [0.05 0.65 0.9 0.25], ...
        'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'RGB Image', ...
        'Units', 'normalized', 'Position', [0.07 0.15 0.4 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(1));
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'BW Maske', ...
        'Units', 'normalized', 'Position', [0.53 0.15 0.4 0.4], ...
        'FontWeight', 'bold', 'Callback', @(s,e) setChoice(2));

    set(hFig, 'CloseRequestFcn', @(s,e) closeFig());

    uiwait(hFig);   % blockiert, bis ein Button gedrückt / Fenster geschlossen wird

    % ---------- verschachtelte Funktionen ----------
    function setChoice(c)
        choice = c;
        closeFig();
    end

    function closeFig()
        if isvalid(hFig)
            uiresume(hFig);
            delete(hFig);
        end
    end
end
