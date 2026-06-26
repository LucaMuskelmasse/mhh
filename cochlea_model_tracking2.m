% Function (Schritt 1 - automatische Tip-Zuweisung, Aufbau):
% 1. Eine .mat mit der zuvor festgelegten Trajektorie öffnen (TipCoordinates)
% 2. Ein MP4-Video öffnen
% 3. Hintergrund-Referenz aus den ersten Frames bilden (Background Subtraction)
% 4. Den LETZTEN Frame per Background Subtraction segmentieren und anzeigen
% 5. Trajektorie als rote Kreuze einzeichnen; um jedes Kreuz ein rotes,
%    an Tangente/Normale der Trajektorie ausgerichtetes Rechteck.
%
% Es gibt KEINE Tip-Zuweisung per Suchradius und KEINE manuelle Korrektur mehr
% (gegenüber cochlea_model_tracking.m bewusst entfernt). Background Subtraction
% bleibt erhalten. Die weiteren Schritte folgen.

clear; clc; close all;

%% Parameter (oben einstellbar)
% --- Rechteck um jeden Trajektorienpunkt ---
rectWidth  = 40;   % Breite  = ENTLANG der Trajektorie (tangential) [px]
rectHeight = 20;   % Höhe    = QUER zur Trajektorie (normal)        [px]

% --- Background-Subtraction-Parameter (wie in cochlea_model_tracking.m) ---
numBgFrames = 5;     % Anzahl früher (elektrodenfreier) Frames für den Hintergrund
fgThreshold = 0.15;  % Schwellwert (0..1) für die Differenz: größer = strenger
minBlobSize = 50;    % kleinste Vordergrund-Fläche (Pixel), kleinere werden entfernt

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

%% 4. Letzten Frame per Background Subtraction segmentieren
imgLast = read(v, totalFrames);
if size(imgLast,3) == 1
    imgLast = repmat(imgLast, [1 1 3]);
end
rgbFiltered = imgLast;
for ch = 1:3
    rgbFiltered(:,:,ch) = medfilt2(imgLast(:,:,ch), [3 3]);
end

grayImg = double(rgb2gray(rgbFiltered));
diffImg = abs(grayImg - bgGray) / 255;     % normierte Differenz 0..1
fg = diffImg > fgThreshold;                % Vordergrund (Elektrode) = true
fg = bwareaopen(fg, minBlobSize);          % kleine Störpixel entfernen
bwLast = ~fg;                              % Elektrode = 0 (schwarz), Hintergrund = 1 (weiß)

%% 5. Anzeige: letzter Frame (BW) + Trajektorie + ausgerichtete Rechtecke
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

hw = rectWidth  / 2;   % halbe Breite (tangential)
hh = rectHeight / 2;   % halbe Höhe   (normal)

figure('Name', 'Trajektorie + Rechtecke (letzter Frame)', 'NumberTitle', 'off');
imshow(bwLast); hold on;

% rote Kreuze auf den Trajektorienpunkten
plot(xs, ys, 'r+', 'MarkerSize', 10, 'LineWidth', 1.5);

% rotiertes Rechteck um jeden Punkt (Outline)
for i = 1:numel(xs)
    cx = xs(i);  cy = ys(i);
    T = [tx(i), ty(i)];   % Einheits-Tangente
    N = [nx(i), ny(i)];   % Einheits-Normale

    % vier Ecken: Mittelpunkt ± hw*T ± hh*N
    c1 = [cx, cy] + hw*T + hh*N;
    c2 = [cx, cy] + hw*T - hh*N;
    c3 = [cx, cy] - hw*T - hh*N;
    c4 = [cx, cy] - hw*T + hh*N;
    corners = [c1; c2; c3; c4; c1];   % geschlossen

    plot(corners(:,1), corners(:,2), 'r-', 'LineWidth', 1.5);
end

title(sprintf('Letzter Frame (Background Subtraction) - %d Trajektorienpunkte', numel(xs)));
hold off;
