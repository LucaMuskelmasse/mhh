% Function (Schritt 2 - automatische Tip-Zuweisung):
% 1. Eine .mat mit der zuvor festgelegten Trajektorie öffnen (TipCoordinates)
% 2. Ein MP4-Video öffnen
% 3. Hintergrund-Referenz aus den ersten Frames bilden (Background Subtraction)
% 4. Frame 300 per Background Subtraction segmentieren und anzeigen
% 5. Mittelpunkt per Klick wählen; Trajektorie als rote Kreuze einzeichnen;
%    um jedes Kreuz ein rotes, an Tangente/Normale ausgerichtetes Viereck,
%    dessen Breite und Höhe linear mit dem Abstand zum Mittelpunkt wachsen
%    (jede Ecke einzeln skaliert -> Trapeze / echte Vierecke).
% 6. Trapeze als Suchflächen: vom mittelpunktsnächsten Endpunkt der Trajektorie
%    Richtung Anfang durchgehen. Im ersten Trapez, in dem schwarze Pixel
%    (Vordergrund/Elektrode) auftauchen, den Schwerpunkt der GRÖSSTEN schwarzen
%    Fläche bestimmen und mit einem grünen Kreuz markieren.
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
rectWidth   = 7;     % Grundbreite (tangential) bei Abstand 0 [px]
rectHeight  = 0;     % Grundhöhe   (normal)     bei Abstand 0 [px]
widthSlope  = 0;     % Breitenzuwachs je px Abstand zum Mittelpunkt [px/px]
heightSlope = 0.5;   % Höhenzuwachs   je px Abstand zum Mittelpunkt [px/px]

% --- Background-Subtraction-Parameter (wie in cochlea_model_tracking.m) ---
numBgFrames = 5;     % Anzahl früher (elektrodenfreier) Frames für den Hintergrund
fgThreshold = 0.15;  % Schwellwert (0..1) für die Differenz: größer = strenger
minBlobSize = 50;    % kleinste Vordergrund-Fläche (Pixel), kleinere werden entfernt

% --- Anzuzeigender / auszuwertender Frame ---
trackFrame  = 300;   % Frame, der segmentiert und durchsucht wird

defaultPath = 'M:\nascas2\Students\Wöhlken\Tracking_Videos\Flex_EA';

%% 1. Trajektorie (.mat) öffnen
[matFile, matDir] = uigetfile({'*.mat','MAT-Datei mit Trajektorie (*.mat)'; '*.*','Alle Dateien (*.*)'}, ...
    'Trajektorie (.mat) auswählen', defaultPath);
if isequal(matFile, 0)
    error('Keine Trajektorie ausgewählt');
end
S = load(fullfile(matDir, matFile), 'TipCoordinates');
if ~isfield(S, 'TipCoordinates')
    error('Die .mat enthält keine Variable "TipCoordinates".');
end
TipCoordinates = S.TipCoordinates;   % [row, col] = [y, x]

%% 2. MP4-Video öffnen
[vidFile, vidDir] = uigetfile({'*.mp4','MP4 Video (*.mp4)'; '*.*','Alle Dateien (*.*)'}, ...
    'MP4 Video auswählen', defaultPath);
if isequal(vidFile, 0)
    error('Kein Video ausgewählt');
end
videoFullPath = fullfile(vidDir, vidFile);

%% 3. Hintergrund-Referenz aus den ersten Frames mitteln
v = VideoReader(videoFullPath);
totalFrames = v.NumFrames;

nbg = min(max(round(numBgFrames), 1), totalFrames);
bgAccum = zeros(v.Height, v.Width);
for b = 1:nbg
    f = read(v, b);
    if size(f,3) == 1
        f = repmat(f, [1 1 3]);
    end
    bgAccum = bgAccum + double(rgb2gray(f));
end
bgGray = medfilt2(bgAccum / nbg, [3 3]);   % statischer Hintergrund

%% 4. Frame 300 per Background Subtraction segmentieren
frameIdx = min(max(round(trackFrame), 1), totalFrames);  % Sicherung gegen kurze Videos
imgFrame = read(v, frameIdx);
if size(imgFrame,3) == 1
    imgFrame = repmat(imgFrame, [1 1 3]);
end
rgbFiltered = imgFrame;
for ch = 1:3
    rgbFiltered(:,:,ch) = medfilt2(imgFrame(:,:,ch), [3 3]);
end

grayImg = double(rgb2gray(rgbFiltered));
diffImg = abs(grayImg - bgGray) / 255;     % normierte Differenz 0..1
fg = diffImg > fgThreshold;                % Vordergrund (Elektrode) = true
fg = bwareaopen(fg, minBlobSize);          % kleine Störpixel entfernen
bwFrame = ~fg;                             % Elektrode = 0 (schwarz), Hintergrund = 1 (weiß)

%% 5. Mittelpunkt wählen, dann Trajektorie + abstandsabhängige Vierecke anzeigen
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

% --- Frame zeigen und Mittelpunkt anklicken (vor der Trajektorie) ---
figure('Name', sprintf('Vierecke (Frame %d)', frameIdx), 'NumberTitle', 'off');
imshow(bwFrame); hold on;
title('Mittelpunkt anklicken (Viereckgröße wächst mit Abstand dazu)');
[xM, yM] = ginput(1);
M = [xM, yM];
plot(xM, yM, 'cx', 'MarkerSize', 16, 'LineWidth', 2);   % Mittelpunkt (cyan)

% --- Trajektorie als rote Kreuze ---
plot(xs, ys, 'r+', 'MarkerSize', 10, 'LineWidth', 1.5);

% --- Pro Punkt ein Viereck; jede Ecke einzeln nach Abstand zum Mittelpunkt skaliert ---
% Vorzeichen-Kombinationen der vier Ecken (entlang Tangente / Normale)
signs = [ +1 +1;  +1 -1;  -1 -1;  -1 +1 ];

nP = numel(xs);
allCorners = cell(nP, 1);   % je Punkt die 5x2-Eckpunkte (geschlossenes Polygon)
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

    plot(corners(:,1), corners(:,2), 'r-', 'LineWidth', 1.5);
end

%% 6. Trapeze als Suchflächen: Tip automatisch finden
% Durchlaufreihenfolge: an dem Endpunkt der Trajektorie beginnen, der dem
% Mittelpunkt M am nächsten liegt, und Richtung anderes Ende durchgehen.
dFirst = hypot(xs(1)   - M(1), ys(1)   - M(2));
dLast  = hypot(xs(end) - M(1), ys(end) - M(2));
if dLast <= dFirst
    order = nP:-1:1;   % letzter Punkt ist näher an M -> von hinten nach vorne
else
    order = 1:nP;      % erster Punkt ist näher an M -> von vorne nach hinten
end

% Schwarze Pixel im Bild = Vordergrund (Elektrode) = fg == true
tipFound = false;
tipXY    = [NaN NaN];
for i = order
    poly = allCorners{i};
    mask = poly2mask(poly(:,1), poly(:,2), v.Height, v.Width);  % Trapez als Maske
    blackInside = fg & mask;                 % schwarze Pixel innerhalb des Trapezes
    if any(blackInside(:))
        cc = bwconncomp(blackInside);
        rp = regionprops(cc, 'Area', 'Centroid');
        [~, k] = max([rp.Area]);             % größte zusammenhängende schwarze Fläche
        tipXY = rp(k).Centroid;              % [x, y] = [col, row]
        % gefundenes Trapez hervorheben + Schwerpunkt als grünes Kreuz
        plot(poly(:,1), poly(:,2), 'g-', 'LineWidth', 2);
        plot(tipXY(1), tipXY(2), 'gx', 'MarkerSize', 16, 'LineWidth', 2.5);
        tipFound = true;
        break;
    end
end

if tipFound
    title(sprintf(['Frame %d - Tip gefunden bei (x=%.1f, y=%.1f)  ', ...
        '(Schwerpunkt der größten schwarzen Fläche)'], frameIdx, tipXY(1), tipXY(2)));
else
    title(sprintf('Frame %d - kein Trapez mit schwarzen Pixeln gefunden', frameIdx));
    warning('In keinem Trapez wurden schwarze Pixel gefunden.');
end
hold off;
