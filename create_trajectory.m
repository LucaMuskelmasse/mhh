% Function:
% 1. Select an MP4 video file (with default path)
% 2. Show only the FIRST frame of the video
% 3. Place a red cross per left-click; repeat as often as wanted
% 4. Press the confirmation button to close the window
% 5. Resample the clicked trajectory to EQUAL spacing (same dense-spline
%    approach as in tip_track_matching_spline.m), keeping the same NUMBER of
%    points as clicks
% 6. Save the trajectory into a .mat file next to the video

clear; clc; close all;

%% 1. Select MP4 video file with default path
defaultPath = 'M:\nascas2\Students\Wöhlken\Tracking_Videos\Flex_EA';
[vidFile, vidDir] = uigetfile({'*.mp4','MP4 Video (*.mp4)'; '*.*','Alle Dateien (*.*)'}, ...
    'Select MP4 video', defaultPath);
if isequal(vidFile, 0)
    error('No video selected');
end
videoFullPath = fullfile(vidDir, vidFile);
[~, vidName, ~] = fileparts(vidFile);

%% 2. Read only the first frame
v = VideoReader(videoFullPath);
firstFrame = read(v, v.NumFrames);
if size(firstFrame, 3) == 1
    firstFrame = repmat(firstFrame, [1 1 3]);   % auf RGB bringen
end

%% 3. Punkte per Linksklick setzen (rote Kreuze), Bestätigen schließt das Fenster
clickedPoints = collectTrajectory(firstFrame);   % [x, y] = [col, row], in Klick-Reihenfolge

nPts = size(clickedPoints, 1);
if nPts < 2
    error('Mindestens zwei Punkte nötig, um eine Trajektorie zu erzeugen.');
end

%% 4. Trajektorie auf gleiche Abstände umrechnen (gleiche Punktanzahl wie Klicks)
% Vorgehen wie in tip_track_matching_spline.m: dichte Spline-Kurve durch die
% Klickpunkte, danach entlang der Bogenlänge gleichmäßig abtasten. Die Anzahl
% der Stützstellen wird aus der Anzahl der gesetzten Punkte übernommen.
xC = clickedPoints(:, 1);   % x = Spalte
yC = clickedPoints(:, 2);   % y = Zeile

tIdx   = 1:nPts;
tDense = linspace(1, nPts, 2000);                 % dichte Stützstellen
xDense = spline(tIdx, xC, tDense);
yDense = spline(tIdx, yC, tDense);

X = xDense(:);  Y = yDense(:);

% Bogenlänge entlang der dichten Kurve (streng monoton -> für interp1)
s = [0; cumsum(hypot(diff(X), diff(Y)))];
[s, iu] = unique(s, 'stable');
X = X(iu);  Y = Y(iu);

% nPts gleichmäßig über die Bogenlänge verteilte Punkte (gleiche Abstände)
sTarget = linspace(0, s(end), nPts);
xEqui = interp1(s, X, sTarget).';
yEqui = interp1(s, Y, sTarget).';

% [row, col] - konsistent zu den anderen Tracking-Skripten
TipCoordinates = [yEqui, xEqui];

% --- Verifikation: alle Sehnenabstände sollten ~gleich sein ---
dChord = hypot(diff(xEqui), diff(yEqui));
fprintf('Punkte: %d   Sehne: min %.2f  max %.2f  std %.4f  (soll = %.2f)\n', ...
        nPts, min(dChord), max(dChord), std(dChord), s(end)/(nPts-1));

%% 5. Ergebnis anzeigen
figure('Name', 'Erzeugte Trajektorie', 'NumberTitle', 'off');
imshow(firstFrame); hold on;
% Rohe Klickpunkte (grau, zum Vergleich)
plot(xC, yC, 'w+', 'MarkerSize', 10, 'LineWidth', 1.5);
% Äquidistante Trajektorie: Linie + Kreuze
plot(xEqui, yEqui, 'r-',  'LineWidth', 2);
plot(xEqui, yEqui, 'r+', 'MarkerSize', 8, 'LineWidth', 1.5);
legend({'Klickpunkte (roh)', 'Trajektorie (gleiche Abstände)', ''}, ...
    'Location', 'best', 'TextColor', 'w', 'Color', [0.2 0.2 0.2]);
title(sprintf('Trajektorie mit gleichen Abständen (%d Punkte)', nPts));
hold off;

%% 6. Trajektorie speichern (neben dem Video)
matFile = fullfile(vidDir, [vidName '_trajectory.mat']);
save(matFile, 'TipCoordinates', 'clickedPoints');
fprintf('Trajektorie gespeichert: %s\n', matFile);


%% Lokale Funktion: Punkte per Linksklick sammeln
function pts = collectTrajectory(frame)
% Zeigt das übergebene Bild und sammelt per Linksklick gesetzte Punkte
% (rote Kreuze, durch eine Linie verbunden). Beliebig viele Punkte möglich.
% "Bestätigen" (oder Fenster schließen) beendet die Eingabe.
% Rückgabe: pts = [x, y] (col, row) in Klick-Reihenfolge.

    pts = zeros(0, 2);

    hFig = figure('Name', 'Trajektorie erstellen', 'NumberTitle', 'off');
    hAx  = axes('Parent', hFig);

    hImg = imshow(frame, 'Parent', hAx);
    hold(hAx, 'on');
    hLine = plot(hAx, NaN, NaN, 'r-', 'LineWidth', 1.5, 'PickableParts', 'none');
    hPts  = plot(hAx, NaN, NaN, 'r+', 'MarkerSize', 12, 'LineWidth', 2, ...
        'PickableParts', 'none');   % Klicks gehen durch die Marker aufs Bild
    hold(hAx, 'off');
    title(hAx, 'Linksklick: Punkt setzen    |    Bestätigen: fertig');

    set(hImg, 'ButtonDownFcn', @onClick);          % Klick aufs Bild
    set(hFig, 'CloseRequestFcn', @(s,e) onConfirm());

    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Bestätigen', ...
        'Units', 'normalized', 'Position', [0.80 0.01 0.18 0.06], ...
        'FontWeight', 'bold', 'Callback', @(s,e) onConfirm());

    uiwait(hFig);   % blockiert, bis "Bestätigen" gedrückt / Fenster geschlossen wird

    % ---------- verschachtelte Funktionen ----------
    function onClick(~, ~)
        cp = get(hAx, 'CurrentPoint');
        pts(end+1, :) = [cp(1,1), cp(1,2)];   % [x, y] = [col, row]
        redraw();
    end

    function redraw()
        set(hPts,  'XData', pts(:,1), 'YData', pts(:,2));
        set(hLine, 'XData', pts(:,1), 'YData', pts(:,2));
    end

    function onConfirm()
        if isvalid(hFig)
            uiresume(hFig);
            delete(hFig);
        end
    end
end
