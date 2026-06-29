% Function:
% Krümmung eines SCHLAUCHS (statt eines Drahtes) aus einem .avi-Video bestimmen.
% 1. Ein .avi-Video auswählen (mit Default-Pfad)
% 2. Alle Frames nacheinander einlesen und in Graustufen wandeln
% 3. Schlauch per ROI/Maske + Binarisierung freistellen, skelettieren und die
%    Krümmung entlang der Mittellinie berechnen
% 4. Mittlere Krümmung über die Zeit plotten
% 5. Farbliche Krümmungsdarstellung über dem Originalbild (mit Slider)
%
% Hinweis: Gegenüber kruemung.m wird hier ein VIDEO (.avi) verarbeitet und die
% Maske/ROI ist auf einen Schlauch ausgelegt (siehe Abschnitt "Schlauch-ROI").
clear; clc; close all;

max_kappa = 0.0117;

%% 1. Video auswählen (mit Default-Pfad)
defaultPath = 'M:\nascas2\Students\Nguyen\1_Messversuch\26_06_15_Messung\pause_15ms\50ms';
[vidFile, vidDir] = uigetfile({'*.avi','AVI Video (*.avi)'; '*.*','Alle Dateien (*.*)'}, ...
    'Select AVI video', defaultPath);
if isequal(vidFile, 0)
    error('No video selected');
end
videoFullPath = fullfile(vidDir, vidFile);
[~, vidName, ~] = fileparts(vidFile);

%% 2. Video öffnen
v = VideoReader(videoFullPath);
ImageNummax = v.NumFrames;
frameRate   = v.FrameRate;                       % Bilder pro Sekunde
tVec        = (0:ImageNummax-1).' / frameRate;   % Zeit je Frame [s]

% Initialize structure array
ImageData = struct('name', [], 'path', [], 'rgb', [], 'bw', []);
ImageData(ImageNummax).name = [];

%% 3. Hauptschleife über alle Frames
for n = 1:ImageNummax
    img = read(v, n);

    % --- RGB sicherstellen ---
    if size(img,3) == 3
        rgbImg = img;
    else
        rgbImg = repmat(img, [1 1 3]);
    end

    % --- Farbbasierte Segmentierung (Color Thresholder) ---
    % Die Funktion wird vom Color Thresholder App erzeugt und gibt eine Binärmaske
    % zurück, in der true = Schlauchfarbe erkannt. Den Funktionsnamen hier anpassen.
    tubeFG = createMask(rgbImg);   % <-- Name der generierten Funktion anpassen

    % --- Nur die größte zusammenhängende Fläche behalten (weiß), Rest schwarz ---
    bwLargest = false(size(tubeFG));
    ccDisp = bwconncomp(tubeFG);
    if ccDisp.NumObjects >= 1
        areas = cellfun(@numel, ccDisp.PixelIdxList);
        [~, iBig] = max(areas);
        bwLargest(ccDisp.PixelIdxList{iBig}) = true;
    end
    tubeFG = bwLargest;

    figure(1)
    imshow(tubeFG);

    % --- Skelettierung mit Lückenschließung ---

    tubeFG = bwareaopen(tubeFG, 300);     % kleine Specks entfernen

    % Lücken schließen (Radius an größte Lücke anpassen, größer = mehr Brücken)
    gapCloseRadius = 1;
    tubeFG_closed = imclose(tubeFG, strel('disk', gapCloseRadius));

    N = 7;                               % gewünschte Punktzahl entlang des Schlauchs
    % Default-Werte, falls der Frame unbrauchbar ist (z.B. zerrissenes Skelett)
    xs    = nan(1, N);
    ys    = nan(1, N);
    kappa = nan(1, N);
    skel  = false(size(tubeFG_closed));

    % Die am stärksten langgestreckte Komponente als Schlauch wählen
    % -> größte Hauptachsenlänge (MajorAxisLength) statt größter Fläche.
    %    Robust gegen kompakte/runde Blasen, auch wenn diese dunkler sind
    %    oder mehr Fläche haben als ein kurzes Schlauchstück.
    cc = bwconncomp(tubeFG_closed);
    if cc.NumObjects >= 1
        stats = regionprops(cc, 'MajorAxisLength');
        [~, imax] = max([stats.MajorAxisLength]);
        tubeMain = false(size(tubeFG_closed));
        tubeMain(cc.PixelIdxList{imax}) = true;

        % Skelettieren
        skel = bwskel(tubeMain, 'MinBranchLength', 25);

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
    ImageData(n).name = sprintf('%s_frame%04d', vidName, n);
    ImageData(n).rgb  = rgbImg;
    ImageData(n).bw   = tubeFG;
    ImageData(n).skel = skel;
    ImageData(n).xs = xs;
    ImageData(n).ys = ys;
    ImageData(n).kappa = kappa;
    ImageData(n).mean_kappa = mean(kappa, 'omitnan');
    ImageData(n).path = videoFullPath;

end

%% 4. Mittlere Krümmung über die Zeit
mean_kappa_vec = [ImageData.mean_kappa].';
mean_kappa_vec = mean_kappa_vec / max_kappa;
figure(2)
plot(tVec, mean_kappa_vec, 'LineWidth', 2, 'Color', [0.8, 0.2, 0.6]);
xlabel('Zeit [s]');
ylabel('Mittlere Krümmung (normiert)');
title('Mittlere Krümmung über die Zeit');
fprintf('max_kappa normiert = %.4f\n', max(mean_kappa_vec));
fprintf('max_kappa nicht normiert = %.4f\n', max([ImageData.mean_kappa].'));
fprintf('end_kappa normiert = %.4f\n', mean_kappa_vec(end));


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

    imshow(ImageData(n).rgb, 'Parent', hAx);
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

function [BW,maskedRGBImage] = createMask(RGB)
%createMask  Threshold RGB image using auto-generated code from colorThresholder app.
%  [BW,MASKEDRGBIMAGE] = createMask(RGB) thresholds image RGB using
%  auto-generated code from the colorThresholder app. The colorspace and
%  range for each channel of the colorspace were set within the app. The
%  segmentation mask is returned in BW, and a composite of the mask and
%  original RGB images is returned in maskedRGBImage.

% Auto-generated by colorThresholder app on 29-Jun-2026
%------------------------------------------------------


% Convert RGB image to chosen color space
I = rgb2hsv(RGB);

% Define thresholds for channel 1 based on histogram settings
channel1Min = 0.751;
channel1Max = 0.198;

% Define thresholds for channel 2 based on histogram settings
channel2Min = 0.23;
channel2Max = 1.000;

% Define thresholds for channel 3 based on histogram settings
channel3Min = 0.000;
channel3Max = 0.750;

% Create mask based on chosen histogram thresholds
sliderBW = ( (I(:,:,1) >= channel1Min) | (I(:,:,1) <= channel1Max) ) & ...
    (I(:,:,2) >= channel2Min ) & (I(:,:,2) <= channel2Max) & ...
    (I(:,:,3) >= channel3Min ) & (I(:,:,3) <= channel3Max);
BW = sliderBW;

% Initialize output masked image based on input image.
maskedRGBImage = RGB;

% Set background pixels where BW is false to zero.
maskedRGBImage(repmat(~BW,[1 1 3])) = 0;

end
