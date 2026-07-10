% Function:
% 1. Select a folder (with default path)
% 2. Read all JPG images using imageDatastore
% 3. Convert to grayscale on-the-fly
% 4. Store into a structure array (without storing RGB images)
% 5. Display the first image
% 6. Display elapsed time

clear; clc; close all;

%% 1.Select folder with default path
defaultPath = 'M:\nascas2\Projects\MemoryCI 2.0\1 Dokumentation\AP01_Iterative Inlay-Entwicklung\AP 1.B BFR-Tests\Testergebnisse\2026-06-22-MV71-09-FM-s-MV71-10-FM-s';
ImgPath = uigetdir(defaultPath, 'Select folder with images');
if ImgPath == 0
    error('No folder selected');
end

%% Start timing
% tic

%% 2.Create imageDatastore
imds = imageDatastore(fullfile(ImgPath, '*.jpg'));

% Get number of images
ImageNummax = numel(imds.Files);

% Initialize structure array
ImageData = struct('name', [], 'path', [], 'gray', [], 'bw', [], 'rgb', []);
ImageData(ImageNummax).name = []; % Preallocate

% Read and process images one by one (no RGB storage)
reset(imds);
for n = 1:ImageNummax
    img = read(imds);

    bwImg = createMask(img);

    % Save into structure array
    [~, name, ext] = fileparts(imds.Files{n});
    ImageData(n).name = [name, ext];         % File name
    ImageData(n).bw = bwImg;                 % Binarized image
    ImageData(n).path = imds.Files{n};       % Full path
    ImageData(n).rgb = img;
end

%% test
%% 4. Compute Tip coordinates for all images using fixed masks with curvature and connectivity check
numImages = numel(ImageData);
%numImages = 360;
TipCoordinates = zeros(numImages, 2); % [row, col]
timestamp = NaT(numImages, 1);
T_K = 0;
for k = 1:numImages

    stats = regionprops(ImageData(k).bw, 'Centroid', 'Area');
    [~, idx] = max([stats.Area]);
    c = stats(idx).Centroid;            % [x, y] = [Spalte, Zeile]
    TipCoordinates(k,:) = [c(2), c(1)]; % -> [Zeile, Spalte]

    [~, name, ~] = fileparts(imds.Files{k});
    parts        = strsplit(name, '_');
    T(k)         = str2double(strrep(parts{end}, '-', '.'));
    timestamp(k) = datetime([parts{1} '_' parts{2}], 'InputFormat', 'yyyyMMdd_HHmmss');

    if T(k) < T_K
        numImages = k;
        break;
    end

    T_K = T(k);


end

t_rel = seconds(timestamp - timestamp(1));     % Sekunden seit Start


%% Visualize Tip trajectory
% Extract valid Tip coordinates (non-zero and not NaN)
validIdx = all(TipCoordinates ~= 0, 2) & ~any(isnan(TipCoordinates), 2);
TipCoordsValid = TipCoordinates(validIdx, :);

if ~isempty(TipCoordsValid)
    figure(3);
    hold on;
    axis([1 1280 1 960]);
    axis ij; %Image Coordinate System (Row = Y Down)
    grid on;
    title('Tip Trajectory');
    xlabel('Column (x)');
    ylabel('Row (y)');

    plot(TipCoordsValid(:,2), TipCoordsValid(:,1), 'ro', 'MarkerSize', 6, 'MarkerFaceColor', 'r');

    plot(TipCoordsValid(:,2), TipCoordsValid(:,1), 'r-', 'LineWidth', 1.5);

    t = 1:size(TipCoordsValid,1);
    ts = linspace(1, size(TipCoordsValid,1), 200);
    xs = spline(t, TipCoordsValid(:,2), ts);
    ys = spline(t, TipCoordsValid(:,1), ts);
    plot(xs, ys, 'b-', 'LineWidth', 2);
end

%% Punkte mit konstantem euklidischem (Sehnen-)Abstand

N      = size(TipCoordsValid, 1);
tIdx   = 1:N;
tDense = linspace(1, N, 2000);                        % dichte Stützstellen
xDense = spline(tIdx, TipCoordsValid(:,2), tDense);   % x = Spalte
yDense = spline(tIdx, TipCoordsValid(:,1), tDense);   % y = Zeile


% Voraussetzung: dichte, glatte Kurve xDense/yDense (am besten mit pchip, kein Overshoot)
X = xDense(:);  Y = yDense(:);

d = 5;                 % gewünschter euklidischer Abstand in Pixel

px = X(1);  py = Y(1);    % erster Punkt = Kurvenanfang
ptsX = px;  ptsY = py;
i = 1;                    % aktuelles Segment auf der dichten Kurve

while i < numel(X)
    % vorwärts laufen, bis ein dichter Stützpunkt weiter als d vom Anker liegt
    while i < numel(X) && hypot(X(i+1)-px, Y(i+1)-py) < d
        i = i + 1;
    end
    if i >= numel(X), break; end   % Kurvenende: kein Punkt mehr im Abstand d

    % auf Segment [i, i+1] den Punkt mit exakt Abstand d (Kreis-Segment-Schnitt)
    ex = X(i)-px;   ey = Y(i)-py;
    fx = X(i+1)-X(i); fy = Y(i+1)-Y(i);
    a = fx^2 + fy^2;
    b = 2*(ex*fx + ey*fy);
    c = ex^2 + ey^2 - d^2;
    t = (-b + sqrt(b^2 - 4*a*c)) / (2*a);   % größere Wurzel = Kreisaustritt (vorwärts)

    px = X(i) + t*fx;
    py = Y(i) + t*fy;
    ptsX(end+1,1) = px;
    ptsY(end+1,1) = py;
end

TipCoordsEqui = [ptsY, ptsX];   % [row, col]

% --- Verifikation: alle Sehnenabstände sollten ~d sein ---
dChord = hypot(diff(ptsX), diff(ptsY));
fprintf('Sehne: min %.2f  max %.2f  std %.4f  (d = %.2f)\n', ...
        min(dChord), max(dChord), std(dChord), d);

% --- Plot ---
figure(4); hold on; axis ij; axis([1 1280 1 960]); grid on;
plot(xDense, yDense, 'b-', 'LineWidth', 1);
plot(ptsX, ptsY, 'ko', 'MarkerSize', 6, 'MarkerFaceColor', 'g');
xlabel('Column (x)'); ylabel('Row (y)');
title(sprintf('Konstanter euklidischer Abstand d = %.1f px (%d Punkte)', d, numel(ptsX)));


%% Fortschritt der Trajektorie über die Temperatur

% --- Referenzkurve (gleiche Abstände) -> 0..1-Parameter ---
refX = ptsX(:);  refY = ptsY(:);
sRef = [0; cumsum(hypot(diff(refX), diff(refY)))];
pRef = sRef / sRef(end);

% --- Messpunkte + Temperatur (+ Zeit), alle in Frame-Reihenfolge, gleich indiziert ---
validIdx = all(TipCoordinates ~= 0, 2) & ~any(isnan(TipCoordinates), 2);
measX    = TipCoordinates(validIdx, 2);
measY    = TipCoordinates(validIdx, 1);
measTemp = T(validIdx);   measTemp = measTemp(:);   % Temperatur aus Dateiname
measT    = t_rel(validIdx);


% --- Fortschritt je Messpunkt (nächster Referenzpunkt) ---
prog = zeros(numel(measX), 1);
for k = 1:numel(measX)
    [~, j]  = min((refX - measX(k)).^2 + (refY - measY(k)).^2);
    prog(k) = pRef(j);
end

[Temp_u, ia] = unique(measTemp);   % aufsteigend sortiert + jede Temperatur nur einmal
prog_u = prog(ia);

figure(5);
plot(measTemp(1:end-1), prog(1:end-1)*100, 'LineWidth', 2, 'Color', [0.8 0.2 0.6]);
xlabel('Temperatur [°C]');
ylabel('Zurückgelegter Anteil der Trajektorie [%]');
title('Fortschritt des Tips entlang der Trajektorie über die Temperatur');
ylim([0 100]); grid on;

imageSliderViewer(ImageData)


%% Stückweise-lineare 3-Segment-Regression (Start 0, Ende 100, alle Segmente mit Steigung)
[params, predictFcn] = fitPlateauRampPlateau(measTemp(1:end-1), prog(1:end-1)*100);
y_fit = predictFcn(measTemp(1:end-1));

figure(6);
plot(measTemp(1:end-1), prog(1:end-1)*100, 'LineWidth', 2, 'Color', [0.8 0.2 0.6], 'LineStyle','--');
xlabel('Temperatur [°C]');
ylabel('Zurückgelegter Anteil der Trajektorie [%]');
title('Fortschritt des Tips entlang der Trajektorie über die Temperatur');
ylim([0 100]); grid on;
hold on;
plot(measTemp(1:end-1), y_fit, 'LineWidth', 2, 'Color', [0.2 0.8 0.6]);
hold off;

fprintf('As = %.4f\n', params.x1);
fprintf('Af = %.4f\n', params.x2);

function [BW,maskedRGBImage] = createMask(RGB)
%createMask  Threshold RGB image using auto-generated code from colorThresholder app.
%  [BW,MASKEDRGBIMAGE] = createMask(RGB) thresholds image RGB using
%  auto-generated code from the colorThresholder app. The colorspace and
%  range for each channel of the colorspace were set within the app. The
%  segmentation mask is returned in BW, and a composite of the mask and
%  original RGB images is returned in maskedRGBImage.

% Auto-generated by colorThresholder app on 05-Jun-2026
%------------------------------------------------------


% Convert RGB image to chosen color space
I = rgb2hsv(RGB);

% Define thresholds for channel 1 based on histogram settings
channel1Min = 0.000;
channel1Max = 0.109;

% Define thresholds for channel 2 based on histogram settings
channel2Min = 0.665;
channel2Max = 1.000;

% Define thresholds for channel 3 based on histogram settings
channel3Min = 0.535;
channel3Max = 0.887;

% Create mask based on chosen histogram thresholds
sliderBW = (I(:,:,1) >= channel1Min ) & (I(:,:,1) <= channel1Max) & ...
    (I(:,:,2) >= channel2Min ) & (I(:,:,2) <= channel2Max) & ...
    (I(:,:,3) >= channel3Min ) & (I(:,:,3) <= channel3Max);
BW = sliderBW;


% Initialize output masked image based on input image.
maskedRGBImage = RGB;

% Set background pixels where BW is false to zero.
maskedRGBImage(repmat(~BW,[1 1 3])) = 0;

end

function imageSliderViewer(ImageData)
%IMAGESLIDERVIEWER Zeigt eine Bildfolge mit Slider und plottet das
%   Center of Mass (größte Region) zur Validierung auf das bw-Bild.

    numFrames = numel(ImageData);
    if numFrames < 1
        error('ImageData enthält keine Bilder.');
    end

    % --- Figure und Achse anlegen ---
    hFig = figure('Name', 'Bildfolge', 'NumberTitle', 'off');
    hAx  = axes('Parent', hFig, 'Units', 'normalized', ...
                'Position', [0.05 0.15 0.9 0.80]);

    % --- Erstes Bild anzeigen ---
    hImg   = imshow(ImageData(1).bw, 'Parent', hAx);
    hold(hAx, 'on');

    % --- Marker für Center of Mass (wird in updateFrame aktualisiert) ---
    hMarker = plot(hAx, NaN, NaN, 'r+', 'MarkerSize', 16, 'LineWidth', 2);
    hCircle = plot(hAx, NaN, NaN, 'ro', 'MarkerSize', 16, 'LineWidth', 1.5);
    hold(hAx, 'off');

    hTitle = title(hAx, sprintf('Frame 1 / %d', numFrames));

    % aktueller Frame-Index, von Slider und Tastatur gemeinsam genutzt
    currentIdx = 1;

    % --- Slider-Schrittweite (Sonderfall: nur ein Bild) ---
    if numFrames > 1
        singleStep = 1 / (numFrames - 1);
        step = [singleStep, max(10 * singleStep, singleStep)];
    else
        step = [1 1];
    end

    % --- Slider anlegen ---
    hSlider = uicontrol('Parent', hFig, 'Style', 'slider', ...
        'Units', 'normalized', 'Position', [0.05 0.03 0.9 0.06], ...
        'Min', 1, 'Max', numFrames, 'Value', 1, ...
        'SliderStep', step, ...
        'Callback', @(src, ~) updateFrame(round(get(src, 'Value'))));

    % --- Pfeiltasten-Navigation ---
    set(hFig, 'KeyPressFcn', @onKeyPress);

    % --- Initiale Anzeige inkl. Marker setzen ---
    updateFrame(1);

    % ----------------------------------------------------------------
    %  Geschachtelte Funktionen
    % ----------------------------------------------------------------
    function updateFrame(idx)
        idx = max(1, min(numFrames, idx));     % auf gültigen Bereich begrenzen
        currentIdx = idx;

        bw = ImageData(idx).bw;
        set(hImg, 'CData', bw);

        % Center of Mass identisch zur Tip-Berechnung: größte Region
        stats = regionprops(bw, 'Centroid', 'Area');
        if ~isempty(stats)
            [~, iMax] = max([stats.Area]);
            c = stats(iMax).Centroid;          % [x, y] = [Spalte, Zeile]
            set(hMarker, 'XData', c(1), 'YData', c(2));
            set(hCircle, 'XData', c(1), 'YData', c(2));
        else
            set(hMarker, 'XData', NaN, 'YData', NaN);
            set(hCircle, 'XData', NaN, 'YData', NaN);
        end

        set(hTitle,  'String', sprintf('Frame %d / %d', idx, numFrames));
        set(hSlider, 'Value',  idx);           % Slider synchron halten
    end

    function onKeyPress(~, event)
        switch event.Key
            case 'rightarrow'
                updateFrame(currentIdx + 1);
            case 'leftarrow'
                updateFrame(currentIdx - 1);
        end
    end
end




%Optimierungsfunktionen




%% Lokale Funktion: stueckweise-lineare 3-Segment-Regression
function [params, predictFcn] = fitPlateauRampPlateau(x, y, c1, c2)
%FITPLATEAURAMPPLATEAU  Stueckweise-lineare 3-Segment-Regression mit festen Randwerten.
%   Fittet eine STETIGE, stueckweise lineare Funktion mit DREI linearen
%   Segmenten an die Daten (x,y). Alle drei Segmente duerfen eine Steigung
%   haben; festgehalten werden nur die Randwerte: f(xmin) = c1 und
%   f(xmax) = c2 (Default: c1 = 0, c2 = 100).
%
%   Das Modell verlaeuft linear durch die Stuetzpunkte
%       (xmin, c1) - (x1, y1) - (x2, y2) - (xmax, c2)
%   mit den Knickstellen x1 < x2 und den freien Knickwerten y1, y2.
%   Bei festen Knickstellen sind y1, y2 per linearer Ausgleichsrechnung
%   exakt loesbar; optimiert werden daher nur die Knickstellen x1 < x2.
%
%   [params, predictFcn] = fitPlateauRampPlateau(x, y)        % c1=0, c2=100
%   [params, predictFcn] = fitPlateauRampPlateau(x, y, c1, c2)
%     params     : struct mit c1, c2, x1, x2, y1, y2, m1, m2, m3, sse, r2
%     predictFcn : Function-Handle, predictFcn(xq) -> Modellwerte

    if nargin < 3 || isempty(c1), c1 = 0;   end
    if nargin < 4 || isempty(c2), c2 = 100; end

    x = x(:);  y = y(:);
    xmin = min(x);  xmax = max(x);

    % --- 1) Grobe globale Suche ueber die Knickstellen (Grid) -----------
    % Fuer feste (x1,x2) werden die optimalen Knickwerte (y1,y2) intern per
    % linearer Ausgleichsrechnung bestimmt -> SSE direkt minimal bewertet.
    ng   = 80;
    cand = linspace(xmin, xmax, ng);
    bestSSE = inf;  bx1 = cand(2);  bx2 = cand(end-1);
    for i = 2:ng-1
        for j = i+1:ng-1                      % erzwingt xmin < x1 < x2 < xmax
            sse = sseFixed(x, y, cand(i), cand(j), xmin, xmax, c1, c2);
            if sse < bestSSE
                bestSSE = sse;  bx1 = cand(i);  bx2 = cand(j);
            end
        end
    end

    % --- 2) Lokale Verfeinerung (Reparam. x1, w = x2-x1 > 0) ------------
    obj  = @(p) objective(p, x, y, xmin, xmax, c1, c2);
    p0   = [bx1, bx2 - bx1];
    opts = optimset('TolX',1e-9, 'TolFun',1e-11, ...
                    'MaxFunEvals',4000, 'MaxIter',4000);
    popt = fminsearch(obj, p0, opts);
    x1 = popt(1);  x2 = popt(1) + popt(2);

    % --- 3) Optimale Knickwerte und abgeleitete Groessen ---------------
    [sse, y1, y2] = sseFixed(x, y, x1, x2, xmin, xmax, c1, c2);
    m1  = (y1 - c1) / (x1 - xmin);   % Steigung Segment 1
    m2  = (y2 - y1) / (x2 - x1);     % Steigung Segment 2 (Rampe)
    m3  = (c2 - y2) / (xmax - x2);   % Steigung Segment 3
    sst = sum((y - mean(y)).^2);
    r2  = 1 - sse/sst;

    params = struct('c1',c1, 'c2',c2, 'x1',x1, 'x2',x2, ...
                    'y1',y1, 'y2',y2, 'm1',m1, 'm2',m2, 'm3',m3, ...
                    'sse',sse, 'r2',r2);

    predictFcn = @(xq) modelEval(xq, xmin, xmax, x1, x2, c1, c2, y1, y2);
end

% ----------------------------------------------------------------------
function yhat = modelEval(x, xmin, xmax, x1, x2, c1, c2, y1, y2)
% Modellauswertung: lineare Interpolation durch die vier Stuetzpunkte.
    x  = x(:);
    xk = [xmin, x1, x2, xmax];
    yk = [c1,   y1, y2, c2  ];
    yhat = interp1(xk, yk, x, 'linear', 'extrap');
end

function [sse, y1, y2] = sseFixed(x, y, x1, x2, xmin, xmax, c1, c2)
% Optimale Knickwerte y1,y2 (lineare Ausgleichsrechnung) bei festen
% Knickstellen und festen Randwerten c1,c2 sowie zugehoeriger SSE.
    xk   = [xmin, x1, x2, xmax];
    b    = interp1(xk, [0 1 0 0], x, 'linear', 'extrap');   % Basisfkt. fuer y1
    d    = interp1(xk, [0 0 1 0], x, 'linear', 'extrap');   % Basisfkt. fuer y2
    base = interp1(xk, [c1 0 0 c2], x, 'linear', 'extrap'); % fester Randanteil
    A    = [b, d];
    yk   = A \ (y - base);            % LS-Loesung [y1; y2]
    y1   = yk(1);  y2 = yk(2);
    resid = y - (base + A*yk);
    sse   = resid.' * resid;
end

function val = objective(p, x, y, xmin, xmax, c1, c2)
% Zielfunktion fuer fminsearch: SSE ueber (x1, w), mit Penalty ausserhalb.
    x1 = p(1);  w = p(2);
    x2 = x1 + w;
    eps0 = 1e-6 * (xmax - xmin);
    if w <= eps0 || x1 <= xmin + eps0 || x2 >= xmax - eps0
        val = 1e12;  return;          % ungueltiger Bereich
    end
    val = sseFixed(x, y, x1, x2, xmin, xmax, c1, c2);
end
