% Function:
% Krümmung eines DRAHTS aus einer JPG-Bildsequenz bestimmen (SAM-2-Masken).
% 1. Ordner mit JPG-Bildern auswählen (mit Default-Pfad)
% 2. Pro Bild die vorberechnete SAM-2-Maske laden, skelettieren und die
%    Krümmung entlang der Mittellinie berechnen
% 3. Mittlere Krümmung über die Temperatur (aus Dateinamen) plotten
% 4. Farbliche Krümmungsdarstellung über dem Originalbild (mit Slider)
%
% WICHTIG - zweistufiger Workflow (Segmentierung mit Segment Anything Model 2,
% ersetzt die frühere Binarisierung + ROI/Polygon-Maske):
%   Schritt 1 (einmal pro Bilderordner, Python):
%       python segment_wire_sam2.py
%     -> Button "Bilderordner (.jpg)" waehlen, den Ordner auswaehlen; die
%        Masken werden als <ordnername>_sam2_masks\frame_00001.png, ...
%        NEBEN dem Bilderordner gespeichert (frame_00001.png = 1. Bild in
%        alphabetischer Reihenfolge = Reihenfolge des imageDatastore).
%        Einrichtung/Details: siehe README_SAM2.md
%   Schritt 2: dieses Skript ausführen (lädt die PNGs statt zu binarisieren).
clear; clc; close all;

%% 1. Select folder with default path
defaultPath = 'M:\nascas2\Projects\MemoryCI 2.0\1 Dokumentation\AP01_Iterative Inlay-Entwicklung\AP 1.B BFR-Tests\Testergebnisse\2026-06-23-MV71-11-MV71-12';
ImgPath = uigetdir(defaultPath, 'Select folder with images');
if ImgPath == 0
    error('No folder selected');
end

%% 1b. SAM-2-Masken prüfen (müssen vorab mit segment_wire_sam2.py erzeugt sein)
[parentDir, imgFolderName] = fileparts(ImgPath);
maskDir = fullfile(parentDir, [imgFolderName '_sam2_masks']);
if ~isfolder(maskDir)
    error(['Keine SAM-2-Masken gefunden: %s\n' ...
           'Bitte zuerst das Python-Skript ausführen:\n' ...
           '    python segment_wire_sam2.py\n' ...
           'dort "Bilderordner (.jpg)" wählen und diesen Ordner auswählen ' ...
           '(siehe README_SAM2.md).'], maskDir);
end

%% 2. Create imageDatastore
imds = imageDatastore(fullfile(ImgPath, '*.jpg'));
ImageNummax = numel(imds.Files);

% Maskenanzahl muss exakt zur Bildanzahl passen (sonst falsche Zuordnung)
maskListing = dir(fullfile(maskDir, 'frame_*.png'));
if numel(maskListing) ~= ImageNummax
    error(['Maskenanzahl (%d) passt nicht zur Bildanzahl (%d) in %s.\n' ...
           'Bitte segment_wire_sam2.py für diesen Ordner erneut ausführen.'], ...
        numel(maskListing), ImageNummax, maskDir);
end

% Initialize structure array
ImageData = struct('name', [], 'path', [], 'gray', [], 'bw', []);
ImageData(ImageNummax).name = [];

%% 3. Initialisierung
T = zeros(ImageNummax, 1);
reset(imds);

%% 4. Hauptschleife
for n = 1:ImageNummax
    img = read(imds);

    [~, name, ~] = fileparts(imds.Files{n});   % z.B. '20250917_122541_03-5'
    parts   = strsplit(name, '_');
    tempStr = strrep(parts{end}, '-', '.');    % '03-5' -> '03.5'
    T(n)    = str2double(tempStr);

    % --- Grauwertbild + Filter ---
    if size(img,3) == 3
        grayImg = rgb2gray(img);
    else
        grayImg = img;
    end
    grayImgFiltered = medfilt2(grayImg, [3 3]);

    % --- SAM-2-Segmentierung laden (vorberechnet mit segment_wire_sam2.py) ---
    % PNG-Maske des Bildes: weiß (255) = Draht, schwarz (0) = Hintergrund.
    % Zuordnung über die Position n: imds.Files ist alphabetisch sortiert -
    % identisch zur Sortierung im Python-Skript -> frame_%05d.png passt.
    maskFile = fullfile(maskDir, sprintf('frame_%05d.png', n));
    wireFG   = imread(maskFile) > 0;   % Vordergrund-Konvention: Draht = 1

    figure(1)
    imshow(wireFG);

    % --- Skelettierung mit Lückenschließung ---
    wireFG = bwareaopen(wireFG, 300);     % kleine Specks entfernen

    % Lücken schließen (Radius an größte Lücke anpassen, größer = mehr Brücken)
    gapCloseRadius = 1;
    wireFG_closed = imclose(wireFG, strel('disk', gapCloseRadius));

    N = 20;                               % gewünschte Punktzahl entlang des Drahtes
    % Default-Werte, falls der Frame unbrauchbar ist (z.B. zerrissenes Skelett)
    xs    = nan(1, N);
    ys    = nan(1, N);
    kappa = nan(1, N);
    skel  = false(size(wireFG_closed));

    % Die am stärksten langgestreckte Komponente als Draht wählen
    % -> größte Hauptachsenlänge (MajorAxisLength) statt größter Fläche.
    %    Robust gegen kompakte/runde Blasen, auch wenn diese dunkler sind
    %    oder mehr Fläche haben als ein kurzes Drahtstück.
    cc = bwconncomp(wireFG_closed);
    if cc.NumObjects >= 1
        stats = regionprops(cc, 'MajorAxisLength');
        [~, imax] = max([stats.MajorAxisLength]);
        wireMain = false(size(wireFG_closed));
        wireMain(cc.PixelIdxList{imax}) = true;

        % Skelettieren
        skel = bwskel(wireMain, 'MinBranchLength', 25);

        endpts   = bwmorph(skel, 'endpoints');
        [ey, ex] = find(endpts);
        [yy, xx] = find(skel);

        if ~isempty(ex) && numel(yy) >= 2
            x0 = ex(1); y0 = ey(1);

            D = bwdistgeodesic(skel, x0, y0, 'quasi-euclidean');
            d = D(sub2ind(size(skel), yy, xx));

            valid = isfinite(d);          % unerreichbare Pixel rausfiltern
            d  = d(valid);
            xx = xx(valid);
            yy = yy(valid);

            % unique sortiert aufsteigend UND entfernt doppelte Distanzen
            % (interp1 braucht streng monotone Stützstellen)
            [d, iu] = unique(d);
            xx = xx(iu);
            yy = yy(iu);

            if numel(d) >= 2
                s = linspace(0, d(end), N);    % gleiche Abstände
                xs = interp1(d, xx, s);
                ys = interp1(d, yy, s);

                xs = smoothdata(xs, 'gaussian', 2);
                ys = smoothdata(ys, 'gaussian', 2);

                dx  = gradient(xs);
                dy  = gradient(ys);
                ddx = gradient(dx);
                ddy = gradient(dy);

                kappa = (dx.*ddy - dy.*ddx) ./ (dx.^2 + dy.^2).^(1.5);
                kappa = abs(kappa);
            else
                warning('Frame %d: zu wenige Skelettpunkte (<2) - wird mit NaN gefüllt.', n);
            end
        else
            warning('Frame %d: kein verwertbares Skelett - wird mit NaN gefüllt.', n);
        end
    else
        warning('Frame %d: kein Vordergrund gefunden - wird mit NaN gefüllt.', n);
    end


    % --- In Struktur speichern ---
    [~, name, ext] = fileparts(imds.Files{n});
    ImageData(n).name = [name, ext];
    ImageData(n).gray = grayImgFiltered;
    ImageData(n).bw   = wireFG;   % SAM-2-Maske (nach bwareaopen)
    ImageData(n).skel = skel;     % <-- neu
    ImageData(n).xs = xs;
    ImageData(n).ys = ys;
    ImageData(n).kappa = kappa;
    ImageData(n).mean_kappa = mean(kappa, 'omitnan');
    ImageData(n).path = imds.Files{n};

end

[Tu, ~, ic] = unique(T(1:end-10));                          % Tu: eindeutige Temperaturen (sortiert)
mean_kappa_vec = [ImageData.mean_kappa].';
mean_kappa_vec = mean_kappa_vec/max(mean_kappa_vec, [], 'omitnan');
kappaMean   = accumarray(ic, mean_kappa_vec(1:end-10), [], @(x) mean(x, 'omitnan'));
figure(2)
plot(Tu, kappaMean,'LineWidth',2,'Color',[0.8, 0.2, 0.6]);
xlabel('Temperatur [°C]');
ylabel('Mittlere Krümmung');
title('Mittlere Krümmung abhängig von Temperatur');

%% 5. Farbliche Krümmungsdarstellung über dem Originalbild (mit Slider)
cmap = jet(256);
allKappa = [ImageData.kappa];
kMin = min(allKappa);            % min/max ignorieren NaN automatisch
kMax = max(allKappa);

hFig = figure('Name', 'Krümmungsdarstellung', 'NumberTitle', 'off');
hAx  = axes('Parent', hFig, 'Position', [0.05 0.15 0.9 0.80]);

% Slider zum Vor- und Zurückspulen durch die Frames
if ImageNummax > 1
    smallStep = 1/(ImageNummax-1);
    sliderStep = [smallStep, max(smallStep, 10/(ImageNummax-1))];
else
    sliderStep = [1 1];
end
hSlider = uicontrol('Parent', hFig, 'Style', 'slider', ...
    'Units', 'normalized', 'Position', [0.15 0.03 0.7 0.05], ...
    'Min', 1, 'Max', max(ImageNummax,2), 'Value', 1, ...
    'SliderStep', sliderStep);

% Live-Aktualisierung beim Ziehen des Sliders
addlistener(hSlider, 'Value', 'PostSet', ...
    @(src, evt) drawFrame(hAx, ImageData, round(hSlider.Value), cmap, kMin, kMax));

% Erstes Bild anzeigen
drawFrame(hAx, ImageData, 1, cmap, kMin, kMax);


%% Lokale Funktion: ein Frame mit farbiger Krümmung zeichnen
function drawFrame(hAx, ImageData, n, cmap, kMin, kMax)
    n = min(max(round(n), 1), numel(ImageData));

    imshow(ImageData(n).gray, 'Parent', hAx);
    hold(hAx, 'on');

    kValues = ImageData(n).kappa;
    xs = ImageData(n).xs;
    ys = ImageData(n).ys;

    for i = 1:length(xs)-1
        normVal = (kValues(i) - kMin) / (kMax - kMin);
        normVal = min(max(normVal, 0), 1);

        colorIdx = max(1, round(normVal * 255) + 1);
        lineColor = cmap(colorIdx,:);

        plot(hAx, xs(i:i+1), ys(i:i+1), ...
            '-', 'LineWidth', 3, 'Color', lineColor);
    end

    title(hAx, sprintf('Skelett über Originalbild (Frame %d / %d)', n, numel(ImageData)));
    hold(hAx, 'off');
end
