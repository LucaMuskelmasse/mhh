% Function:
% 1. Select a folder (with default path)
% 2. Read all JPG images using imageDatastore
% 3. Convert to grayscale on-the-fly
% 4. Store into a structure array (without storing RGB images)
% 5. Display the first image
% 6. Display elapsed time

clear; clc; close all;

%% Parameter: offizieller Messbereich der 3-Segment-Regression (laut Dokument)
% Die Regression (As/Af-Bestimmung) ist über diesen Bereich definiert, d.h.
% die festen Randwerte (f(measRangeMin)=0%, f(measRangeMax)=100%) werden dort
% verankert statt am tatsächlichen Minimum/Maximum der gemessenen Temperatur.
% Für Temperaturen AUSSERHALB der tatsächlich gemessenen Daten wird der
% Funktionswert am Rand der gemessenen Daten konstant fortgesetzt, nicht
% weiter der Randgerade folgend (siehe fitPlateauRampPlateau unten).
measRangeMin = -25;   % °C, Untergrenze des offiziellen Messbereichs
measRangeMax = 90;    % °C, Obergrenze des offiziellen Messbereichs

%% 1.Select folder with default path
defaultPath = 'M:\nascas2\Projects\MemoryCI 2.0\1 Dokumentation\AP01_Iterative Inlay-Entwicklung\AP 1.B BFR-Tests\Testergebnisse\2026-06-23-MV71-11-MV71-12';
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

% --- Temperaturen und Zeitstempel aus den Dateinamen lesen ---
% Dateiname-Format: yyyyMMdd_HHmmss_..._<Temperatur mit '-' statt '.'>.jpg
% So lässt sich der Aufwärmvorgang (Anfang bis höchste Temperatur) bestimmen.
T_all  = zeros(ImageNummax, 1);
ts_all = NaT(ImageNummax, 1);
for n = 1:ImageNummax
    [~, name, ~] = fileparts(imds.Files{n});
    parts     = strsplit(name, '_');
    T_all(n)  = str2double(strrep(parts{end}, '-', '.'));
    ts_all(n) = datetime([parts{1} '_' parts{2}], 'InputFormat', 'yyyyMMdd_HHmmss');
end

% --- Nur den Aufwärmvorgang behalten: von Anfang bis zur höchsten Temperatur ---
% Die Bilder NACH dem Temperaturmaximum (Abkühlvorgang) werden nicht benötigt
% und daher gar nicht erst eingelesen/ausgewertet.
[~, kMax] = max(T_all);
fprintf(['Aufwärmvorgang: Bilder 1 bis %d (max. Temperatur %.2f °C); ', ...
         '%d Abkühlbilder werden ignoriert.\n'], kMax, T_all(kMax), ImageNummax - kMax);

T         = T_all(1:kMax);    % Temperatur je Aufwärm-Bild
timestamp = ts_all(1:kMax);   % Zeitstempel je Aufwärm-Bild

% Initialize structure array (nur Aufwärmvorgang)
ImageData = struct('name', [], 'path', [], 'gray', [], 'bw', []);
ImageData(kMax).name = []; % Preallocate

% Read and process images one by one (no RGB storage), nur bis zum Maximum
reset(imds);
for n = 1:kMax
    img = read(imds);

    % Convert to grayscale if RGB
    if size(img,3) == 3
        grayImg = rgb2gray(img);
    else
        grayImg = img;
    end

    % Apply median filter (3x3 window)
    grayImgFiltered = medfilt2(grayImg, [3 3]);

    % Binarize image (threshold)
    level = 0.55; %[0,1]
    bwImg = imbinarize(grayImgFiltered, level);

    % Save into structure array
    [~, name, ext] = fileparts(imds.Files{n});
    ImageData(n).name = [name, ext];         % File name
    ImageData(n).gray = grayImgFiltered;     % Grayscale + median filtered image
    ImageData(n).bw = bwImg;                 % Binarized image
    ImageData(n).path = imds.Files{n};       % Full path
end


%% Display the first grayscale image
% figure;
% imshow(ImageData(1).gray);
% title(['Image 1 of ', num2str(ImageNummax)]);

%% Display elapsed time
% elapsedTime = toc;
% fprintf('Total time to read and process %d images: %.2f seconds\n', ImageNummax, elapsedTime);

%% Trajektorie: vorhandene laden oder neu zuweisen?
% Pro Bildordner wird die zugewiesene Trajektorie als .mat gespeichert.
% Nur wenn eine solche Datei existiert, wird gefragt; sonst direkt neu.
trajFile = fullfile(ImgPath, 'tip_trajectory.mat');
useExisting = false;
if isfile(trajFile)
    choice = questdlg(['Für diesen Ordner existiert bereits eine gespeicherte ', ...
        'Trajektorie. Möchtest du die alte verwenden oder eine neue zuweisen?'], ...
        'Trajektorie laden', 'Alte verwenden', 'Neu zuweisen', 'Alte verwenden');
    useExisting = strcmp(choice, 'Alte verwenden');
end

if useExisting
    % --- Alte Trajektorie laden: ROI-Auswahl, Tracking und Kontrolle entfallen ---
    S = load(trajFile, 'TipCoordinates', 'T', 't_rel');
    TipCoordinates = S.TipCoordinates;
    T              = S.T;
    t_rel          = S.t_rel;
else
%% 3. Manually create fixed binary masks: workspace and tip
% Only applied to the first binarized image
firstBW = ImageData(1).bw;

figure;
imshow(firstBW); hold on;
title('Manual ROI creation: first draw workspace (red), then click Tip (green)');

% --- Interactive rectangle drawing for workspace ---
ROI_Workspace = drawrectangle('Color','r');
wait(ROI_Workspace); % wait for user to finish

% Generate workspace mask
rectPos = round(ROI_Workspace.Position); % [x, y, width, height]
Mask_workspace = zeros(size(firstBW));
wx1 = max(rectPos(1),1);
wy1 = max(rectPos(2),1);
wx2 = min(wx1 + rectPos(3), size(firstBW,2));
wy2 = min(wy1 + rectPos(4), size(firstBW,1));
Mask_workspace(wy1:wy2, wx1:wx2) = 1;

% --- Interactive single click for Tip ---
title('Single-click to define the ROI for Tip search (green)');

% Use ginput to get one point
[xTip, yTip] = ginput(1); % xTip = col, yTip = row
xTip = round(xTip);
yTip = round(yTip);

% Tip mask parameters
tipRadius = 25;
Mask_Tip = zeros(size(firstBW));

% Create circular mask
[cols, rows] = meshgrid(1:size(firstBW,2), 1:size(firstBW,1));
Mask_Tip(((rows - yTip).^2 + (cols - xTip).^2) <= tipRadius^2) = 1;

% Optional: visualize the Tip circle
viscircles([xTip, yTip], tipRadius, 'Color', 'g');



%% 4. Compute Tip coordinates for all images using fixed masks with curvature check
% numImages = numel(ImageData);
% TipCoordinates = zeros(numImages, 2); % [row, col]
% TipCurvature = zeros(numImages, 1);  % store tip curvature
% curvatureThreshold = 0.06;          % example threshold, adjust as needed
%
% for k = 1:numImages
%     bwImg = ImageData(k).bw;
%     sz = size(bwImg);
%
%     % Apply workspace & tip masks
%     I_Mask_Tip = ones(sz);
%     I_Mask_Tip(Mask_workspace & Mask_Tip) = bwImg(Mask_workspace & Mask_Tip);
%
%     % Get boundary of Tip mask
%     B = bwboundaries(Mask_Tip);
%     if isempty(B)
%         warning(['Image ', num2str(k), ': Tip mask has no boundary, skipping']);
%         continue;
%     end
%     B_coords = B{1};
%
%     % Find largest connected component in complement
%     CC = bwconncomp(imcomplement(I_Mask_Tip));
%
%     % Adaptive ROI: vector prediction + progressive search
%     found = true;
%     if isempty(CC.PixelIdxList)
%         if k > 2 && all(TipCoordinates(k-1,:)) && all(TipCoordinates(k-2,:))
%             warning(['Image ', num2str(k), ': No component found, using vector prediction']);
%
%             delta = TipCoordinates(k-1,:) - TipCoordinates(k-2,:);
%             predTip = TipCoordinates(k-1,:) + delta;
%
%             % Parameters for progressive search
%             maxSteps = 5;
%             radiusStep = 15;
%             found = false;
%
%             for step = 0:maxSteps
%                 moveTip = predTip + (step * delta / norm(delta))';
%
%                 Mask_Tip(:) = 0;
%                 [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
%                 Mask_Tip(((rows - moveTip(1)).^2 + (cols - moveTip(2)).^2) <= (tipRadius + radiusStep)^2) = 1;
%
%                 I_Mask_Tip = ones(sz);
%                 I_Mask_Tip(Mask_workspace & Mask_Tip) = bwImg(Mask_workspace & Mask_Tip);
%                 CC = bwconncomp(imcomplement(I_Mask_Tip));
%
%                 if ~isempty(CC.PixelIdxList)
%                     found = true;
%                     break;
%                 end
%             end
%         else
%             found = false;
%         end
%     end
%
%     % If progressive search fails, pop up manual marking window
%     if ~found
%         warning(['Image ', num2str(k), ': prediction + progressive search failed, please mark Tip manually']);
%
%         figure(1); clf;
%         imshow(bwImg); hold on;
%         title(['Image ', num2str(k), ': Single-click to define the ROI for Tip search']);
%
%         [colTip, rowTip] = ginput(1);
%         rowTip = round(rowTip);
%         colTip = round(colTip);
%
%         Mask_Tip(:) = 0;
%         [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
%         Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;
%
%         viscircles([colTip, rowTip], tipRadius, 'Color', 'g');
%
%         TipCoordinates(k,:) = [rowTip, colTip];
%         TipCurvature(k) = NaN; % cannot compute curvature manually
%
%         continue;
%     end
%
%     % Determine largest connected component
%     numPixels = cellfun(@numel, CC.PixelIdxList);
%     [~, idx] = max(numPixels);
%
%     B_ind = sub2ind(sz, B_coords(:,1), B_coords(:,2));
%     Intersection = intersect(B_ind, CC.PixelIdxList{idx});
%     if isempty(Intersection)
%         warning(['Image ', num2str(k), ': No intersection found, skipping']);
%         continue;
%     end
%
%     [rowPts, colPts] = ind2sub(sz, Intersection);
%     rowCentroid = round(mean(rowPts));
%     colCentroid = round(mean(colPts));
%
%     % Geodesic distance transform to get Tip
%     I_Mask_Tip2 = im2bw(imcomplement(I_Mask_Tip));
%     D = bwdistgeodesic(I_Mask_Tip2, colCentroid, rowCentroid);
%     D(isinf(D)) = 0;
%
%     [~, maxIdx] = max(D(:));
%     [rowTip, colTip] = ind2sub(sz, maxIdx);
%
%     % Compute curvature using three points: two farthest points in Intersection + Tip
%     [rowPts, colPts] = ind2sub(sz, Intersection);
%     numPts = numel(rowPts);
%
%     % Find the pair of points with the maximum distance
%     maxDist = 0;
%     for i = 1:numPts-1
%         for j = i+1:numPts
%             dist = norm([colPts(i)-colPts(j), rowPts(i)-rowPts(j)]);
%             if dist > maxDist
%                 maxDist = dist;
%                 P1 = [colPts(i), rowPts(i)];
%                 P2 = [colPts(j), rowPts(j)];
%             end
%         end
%     end
%
%     % Tip point
%     P3 = [colTip, rowTip];
%
%     % Compute curvature using three points
%     A = [P1(2)-P2(2), P1(1)-P2(1)];
%     Bvec = [P3(2)-P2(2), P3(1)-P2(1)];
%     area = 0.5 * abs(A(1)*Bvec(2) - A(2)*Bvec(1));
%     a = norm(P1-P2); b = norm(P2-P3); c = norm(P3-P1);
%     kappa = 4*area / (a*b*c);   % curvature
%
%     % Compare with previous curvature
%     if k > 1 && ~isnan(TipCurvature(k-1))
%         if abs(kappa - TipCurvature(k-1)) > curvatureThreshold
%             warning(['Image ', num2str(k), ': curvature difference too large, please mark Tip manually']);
%
%             figure(1); clf;
%             imshow(bwImg); hold on;
%             title(['Image ', num2str(k), ': Single-click to redefine Tip']);
%
%             [colTip, rowTip] = ginput(1);
%             rowTip = round(rowTip);
%             colTip = round(colTip);
%
%             Mask_Tip(:) = 0;
%             [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
%             Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;
%
%             viscircles([colTip, rowTip], tipRadius, 'Color', 'g');
%
%             kappa = NaN; % cannot compute reliable curvature manually
%         end
%     end
%
%     TipCoordinates(k,:) = [rowTip, colTip];
%     TipCurvature(k) = kappa;
%
%     % Optional visualization
%     figure(1); clf;
%     imshow(bwImg); hold on;
%     plot(colTip, rowTip, 'r+', 'MarkerSize', 15, 'LineWidth', 2);
%     title(['Image ', num2str(k), ' Tip position']);
%     drawnow;
%
%     % Update Mask_Tip for next iteration
%     Mask_Tip(:) = 0;
%     [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
%     Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;
% end

%% test
%% 4. Compute Tip coordinates for all images using fixed masks with curvature and connectivity check
% Nur die Aufwärm-Bilder (1..kMax) werden hier verarbeitet, da ImageData
% bereits auf den Aufwärmvorgang beschränkt ist.
numImages = numel(ImageData);
TipCoordinates = zeros(numImages, 2); % [row, col]
TipCurvature = zeros(numImages, 1);  % store tip curvature
curvatureThreshold = 0.06;           % example threshold, adjust as needed

for k = 1:numImages

    bwImg = ImageData(k).bw;
    sz = size(bwImg);

    % Apply workspace & tip masks
    I_Mask_Tip = ones(sz);
    I_Mask_Tip(Mask_workspace & Mask_Tip) = bwImg(Mask_workspace & Mask_Tip);

    % Get boundary of Tip mask
    B = bwboundaries(Mask_Tip);
    if isempty(B)
        warning(['Image ', num2str(k), ': Tip mask has no boundary, skipping']);
        continue;
    end
    B_coords = B{1};

    % Find largest connected component in complement
    CC = bwconncomp(imcomplement(I_Mask_Tip));

    % Adaptive ROI: vector prediction + progressive search
    found = true;
    if isempty(CC.PixelIdxList)
        if k > 2 && all(TipCoordinates(k-1,:)) && all(TipCoordinates(k-2,:))
            warning(['Image ', num2str(k), ': No component found, using vector prediction']);

            delta = TipCoordinates(k-1,:) - TipCoordinates(k-2,:);
            predTip = TipCoordinates(k-1,:) + delta;

            % Parameters for progressive search
            maxSteps = 5;
            radiusStep = 15;
            found = false;

            for step = 0:maxSteps
                moveTip = predTip + (step * delta / norm(delta))';

                Mask_Tip(:) = 0;
                [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
                Mask_Tip(((rows - moveTip(1)).^2 + (cols - moveTip(2)).^2) <= (tipRadius + radiusStep)^2) = 1;

                I_Mask_Tip = ones(sz);
                I_Mask_Tip(Mask_workspace & Mask_Tip) = bwImg(Mask_workspace & Mask_Tip);
                CC = bwconncomp(imcomplement(I_Mask_Tip));

                if ~isempty(CC.PixelIdxList)
                    found = true;
                    break;
                end
            end
        else
            found = false;
        end
    end

    % If progressive search fails, pop up manual marking window
    if ~found
        warning(['Image ', num2str(k), ': prediction + progressive search failed, please mark Tip manually']);

        figure(1); clf;
        imshow(bwImg); hold on;
        title(['Image ', num2str(k), ': Single-click to define the ROI for Tip search']);

        [colTip, rowTip] = ginput(1);
        rowTip = round(rowTip);
        colTip = round(colTip);

        Mask_Tip(:) = 0;
        [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
        Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;

        viscircles([colTip, rowTip], tipRadius, 'Color', 'g');

        TipCoordinates(k,:) = [rowTip, colTip];
        TipCurvature(k) = NaN; % cannot compute curvature manually

        continue;
    end

    % Determine largest connected component
    numPixels = cellfun(@numel, CC.PixelIdxList);
    [~, idx] = max(numPixels);

    B_ind = sub2ind(sz, B_coords(:,1), B_coords(:,2));
    Intersection = intersect(B_ind, CC.PixelIdxList{idx});
    if isempty(Intersection)
        warning(['Image ', num2str(k), ': No intersection found, skipping']);
        continue;
    end

    [rowPts, colPts] = ind2sub(sz, Intersection);
    rowCentroid = round(mean(rowPts));
    colCentroid = round(mean(colPts));

    % Geodesic distance transform to get Tip
    I_Mask_Tip2 = im2bw(imcomplement(I_Mask_Tip));
    D = bwdistgeodesic(I_Mask_Tip2, colCentroid, rowCentroid);
    D(isinf(D)) = 0;

    [~, maxIdx] = max(D(:));
    [rowTip, colTip] = ind2sub(sz, maxIdx);

    % Compute curvature using three points: two farthest points in Intersection + Tip
    numPts = numel(rowPts);
    maxDist = 0;
    for i = 1:numPts-1
        for j = i+1:numPts
            dist = norm([colPts(i)-colPts(j), rowPts(i)-rowPts(j)]);
            if dist > maxDist
                maxDist = dist;
                P1 = [colPts(i), rowPts(i)];
                P2 = [colPts(j), rowPts(j)];
            end
        end
    end
    P3 = [colTip, rowTip];

    A = [P1(2)-P2(2), P1(1)-P2(1)];
    Bvec = [P3(2)-P2(2), P3(1)-P2(1)];
    area = 0.5 * abs(A(1)*Bvec(2) - A(2)*Bvec(1));
    a = norm(P1-P2); b = norm(P2-P3); c = norm(P3-P1);
    kappa = 4*area / (a*b*c);

    % Curvature check
    if k > 1 && ~isnan(TipCurvature(k-1))
        if abs(kappa - TipCurvature(k-1)) > curvatureThreshold
            warning(['Image ', num2str(k), ': curvature difference too large, please mark Tip manually']);

            figure(1); clf;
            imshow(bwImg); hold on;
            title(['Image ', num2str(k), ': Single-click to redefine Tip']);

            [colTip, rowTip] = ginput(1);
            rowTip = round(rowTip);
            colTip = round(colTip);

            Mask_Tip(:) = 0;
            [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
            Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;

            viscircles([colTip, rowTip], tipRadius, 'Color', 'g');
            kappa = NaN;
        end
    end

    % Connectivity check: ensure ROI is a single white region
    MaskedRegion = I_Mask_Tip & (Mask_workspace & Mask_Tip);
    CC_masked = bwconncomp(MaskedRegion);
    if CC_masked.NumObjects > 1
        warning(['Image ', num2str(k), ': masked ROI contains multiple disconnected white regions, please adjust manually']);

        % %TEST%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % figure;
        % imshow(MaskedRegion);
        % title(['Check ROI - Image ', num2str(k)]);
        %
        % return;
        % %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        figure(1); clf;
        imshow(bwImg); hold on;
        title(['Image ', num2str(k), ': Single-click to redefine Tip due to disconnected ROI']);

        [colTip, rowTip] = ginput(1);
        rowTip = round(rowTip);
        colTip = round(colTip);

        Mask_Tip(:) = 0;
        [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
        Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;

        viscircles([colTip, rowTip], tipRadius, 'Color', 'g');

        kappa = NaN; % curvature not reliable after manual adjustment
    end

    % Update Mask_Tip for subsequent iterations
    Mask_Tip(:) = 0;
    [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
    Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;

    TipCoordinates(k,:) = [rowTip, colTip];
    TipCurvature(k) = kappa;

    % Optional visualization
    figure(1); clf;
    imshow(bwImg); hold on;
    plot(colTip, rowTip, 'r+', 'MarkerSize', 15, 'LineWidth', 2);
    title(['Image ', num2str(k), ' Tip position']);
    drawnow;

    % Update Mask_Tip for next iteration
    Mask_Tip(:) = 0;
    [cols, rows] = meshgrid(1:sz(2), 1:sz(1));
    Mask_Tip(((rows - rowTip).^2 + (cols - colTip).^2) <= tipRadius^2) = 1;
end
t_rel = seconds(timestamp - timestamp(1));     % Sekunden seit Start


%% 4b. Manuelle Kontrolle/Korrektur der Tip-Zuweisung
% Öffnet ein Fenster durch die Bildfolge mit dem zugewiesenen roten Kreuz.
% Per Klick ins Bild kann der Tip für den aktuellen Frame neu gesetzt werden.
% Erst nach Klick auf "Fertig" läuft das Programm weiter.
TipCoordinates = reviewTips(ImageData, TipCoordinates);

    % --- Neu zugewiesene Trajektorie speichern (für nächsten Programmstart) ---
    save(trajFile, 'TipCoordinates', 'T', 't_rel');
    fprintf('Trajektorie gespeichert: %s\n', trajFile);
end


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

figure(5);
plot(measTemp(1:end-1), prog(1:end-1)*100, 'LineWidth', 2, 'Color', [0.8 0.2 0.6]);
xlabel('Temperatur [°C]');
ylabel('Zurückgelegter Anteil der Trajektorie [%]');
title('Fortschritt des Tips entlang der Trajektorie über die Temperatur');
ylim([0 100]); grid on;


%% Stückweise-lineare 3-Segment-Regression (Start 0, Ende 100, alle Segmente mit Steigung)
% Randbedingungen (0%/100%) sind am offiziellen Messbereich verankert
% (measRangeMin/measRangeMax), gefittet wird aber nur mit den tatsächlich
% gemessenen Daten. Außerhalb dieser Daten wird der Funktionswert am Rand
% konstant fortgesetzt (siehe fitPlateauRampPlateau).
[params, predictFcn] = fitPlateauRampPlateau(measTemp(1:end-1), prog(1:end-1)*100, ...
    [], [], measRangeMin, measRangeMax);

% Fit über den vollen offiziellen Messbereich auswerten, damit die konstante
% Fortsetzung außerhalb der gemessenen Daten im Plot sichtbar ist.
xPlot = linspace(measRangeMin, measRangeMax, 500);
y_fit = predictFcn(xPlot);

figure(6);
plot(measTemp(1:end-1), prog(1:end-1)*100, 'LineWidth', 2, 'Color', [0.8 0.2 0.6], 'LineStyle','--');
xlabel('Temperatur [°C]');
ylabel('Zurückgelegter Anteil der Trajektorie [%]');
title('Fortschritt des Tips entlang der Trajektorie über die Temperatur');
xlim([measRangeMin measRangeMax]); ylim([0 100]); grid on;
hold on;
plot(xPlot, y_fit, 'LineWidth', 2, 'Color', [0.2 0.8 0.6]);
hold off;
legend({'Gemessene Daten', 'Regression (3-Segment)'}, 'Location', 'best');

fprintf('As = %.4f\n', params.x1);
fprintf('Af = %.4f\n', params.x2);


%% Lokale Funktion: manuelle Kontrolle/Korrektur der Tip-Zuweisung
function TipCoordinates = reviewTips(ImageData, TipCoordinates)
% Chronologische Tip-Kontrolle ohne Latenz: Fenster, Bild und Marker werden
% EINMAL angelegt und danach nur noch aktualisiert (kein imshow/ginput pro
% Frame -> kein Flackern). Bedienung:
%   - Pfeil rechts / links : nächstes / vorheriges Bild
%   - Linksklick ins Bild  : Tip des aktuellen Frames auf die Klickstelle setzen
%   - "Fertig" / Escape / Fenster schließen : Kontrolle beenden
% Rückgabe: (ggf.) korrigiertes TipCoordinates.

    nImg = numel(ImageData);
    cur  = 1;

    hFig = figure('Name', 'Tip-Kontrolle', 'NumberTitle', 'off');
    hAx  = axes('Parent', hFig);

    % Bild + Marker EINMAL anlegen, danach nur noch Daten aktualisieren
    hImg = imshow(ImageData(cur).gray, 'Parent', hAx);
    hold(hAx, 'on');
    hCross = plot(hAx, NaN, NaN, 'r+', 'MarkerSize', 15, 'LineWidth', 2, ...
        'PickableParts', 'none');     % Klicks gehen durch den Marker aufs Bild
    hold(hAx, 'off');
    hTitle = title(hAx, '');

    % Event-Callbacks
    set(hImg, 'ButtonDownFcn', @onClick);        % Klick aufs Bild
    set(hFig, 'WindowKeyPressFcn', @onKey);      % Pfeiltasten
    set(hFig, 'CloseRequestFcn', @(s,e) onClose());

    % "Fertig"-Button
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Fertig', ...
        'Units', 'normalized', 'Position', [0.85 0.01 0.14 0.06], ...
        'FontWeight', 'bold', 'Callback', @(s,e) onClose());

    redraw();
    uiwait(hFig);   % blockiert, bis das Fenster geschlossen / "Fertig" gedrückt wird

    % ---------- verschachtelte Funktionen ----------
    function redraw()
        set(hImg, 'CData', ImageData(cur).gray);
        tc = TipCoordinates(cur, :);
        if all(tc ~= 0) && ~any(isnan(tc))
            set(hCross, 'XData', tc(2), 'YData', tc(1));
            statusStr = sprintf('Tip = (%d, %d)', tc(2), tc(1));
        else
            set(hCross, 'XData', NaN, 'YData', NaN);
            statusStr = 'kein Tip zugewiesen';
        end
        set(hTitle, 'String', sprintf(['Frame %d / %d   |   %s\n', ...
            'Pfeil rechts/links = vor/zurück    Linksklick = Tip setzen    Fertig = beenden'], ...
            cur, nImg, statusStr));
    end

    function gotoFrame(idx)
        cur = min(max(idx, 1), nImg);
        redraw();
    end

    function onKey(~, evt)
        switch evt.Key
            case 'rightarrow'
                gotoFrame(cur + 1);
            case 'leftarrow'
                gotoFrame(cur - 1);
            case 'escape'
                onClose();
        end
    end

    function onClick(~, ~)
        cp = get(hAx, 'CurrentPoint');
        TipCoordinates(cur, :) = [round(cp(1,2)), round(cp(1,1))];   % [row, col]
        redraw();          % Marker sofort an die neue Stelle
    end

    function onClose()
        if isvalid(hFig)
            uiresume(hFig);
            delete(hFig);
        end
    end
end


%% Lokale Funktion: stueckweise-lineare 3-Segment-Regression
function [params, predictFcn] = fitPlateauRampPlateau(x, y, c1, c2, xLo, xHi)
%FITPLATEAURAMPPLATEAU  Stueckweise-lineare 3-Segment-Regression mit festen Randwerten.
%   Fittet eine STETIGE, stueckweise lineare Funktion mit DREI linearen
%   Segmenten an die Daten (x,y). Alle drei Segmente duerfen eine Steigung
%   haben; festgehalten werden nur die Randwerte: f(xLo) = c1 und
%   f(xHi) = c2 (Default: c1 = 0, c2 = 100). xLo/xHi sind der OFFIZIELLE
%   Messbereich (Default -25/90), NICHT das Minimum/Maximum von x - die
%   Randbedingungen werden also unabhaengig von den tatsaechlich gemessenen
%   Daten am offiziellen Messbereich verankert.
%
%   Das Modell verlaeuft linear durch die Stuetzpunkte
%       (xLo, c1) - (x1, y1) - (x2, y2) - (xHi, c2)
%   mit den Knickstellen x1 < x2 und den freien Knickwerten y1, y2.
%   Bei festen Knickstellen sind y1, y2 per linearer Ausgleichsrechnung
%   exakt loesbar; optimiert werden daher nur die Knickstellen x1 < x2 (per
%   Grid-Suche im vollen [xLo, xHi] + lokaler Verfeinerung), bewertet nur
%   anhand der tatsaechlichen Datenpunkte (x,y).
%
%   Da (x,y) typischerweise NICHT den vollen Bereich [xLo, xHi] abdecken,
%   wuerde eine Auswertung ausserhalb der gemessenen Daten der (eher
%   willkuerlichen) Randgeraden zum Anker (xLo,c1) bzw. (xHi,c2) folgen.
%   Stattdessen wird predictFcn ausserhalb von [min(x), max(x)] KONSTANT mit
%   dem jeweiligen Randwert der gemessenen Daten fortgesetzt (kein weiteres
%   Extrapolieren) - siehe modelEvalClamped.
%
%   [params, predictFcn] = fitPlateauRampPlateau(x, y)                  % c1=0, c2=100, xLo=-25, xHi=90
%   [params, predictFcn] = fitPlateauRampPlateau(x, y, c1, c2)
%   [params, predictFcn] = fitPlateauRampPlateau(x, y, c1, c2, xLo, xHi)
%     params     : struct mit c1, c2, xLo, xHi, dataXmin, dataXmax, x1, x2,
%                  y1, y2, m1, m2, m3, sse, r2
%     predictFcn : Function-Handle, predictFcn(xq) -> Modellwerte (ausserhalb
%                  der gemessenen Daten konstant fortgesetzt)

    if nargin < 3 || isempty(c1),  c1  = 0;   end
    if nargin < 4 || isempty(c2),  c2  = 100; end
    if nargin < 5 || isempty(xLo), xLo = -25; end
    if nargin < 6 || isempty(xHi), xHi = 90;  end

    x = x(:);  y = y(:);
    xmin = xLo;  xmax = xHi;                    % offizieller Messbereich (Randanker)
    dataXmin = min(x);  dataXmax = max(x);      % tatsaechlich gemessener Bereich

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

    params = struct('c1',c1, 'c2',c2, 'xLo',xLo, 'xHi',xHi, ...
                    'dataXmin',dataXmin, 'dataXmax',dataXmax, ...
                    'x1',x1, 'x2',x2, 'y1',y1, 'y2',y2, ...
                    'm1',m1, 'm2',m2, 'm3',m3, 'sse',sse, 'r2',r2);

    predictFcn = @(xq) modelEvalClamped(xq, dataXmin, dataXmax, ...
        xmin, xmax, x1, x2, c1, c2, y1, y2);
end

% ----------------------------------------------------------------------
function yhat = modelEval(x, xmin, xmax, x1, x2, c1, c2, y1, y2)
% Modellauswertung: lineare Interpolation durch die vier Stuetzpunkte.
    x  = x(:);
    xk = [xmin, x1, x2, xmax];
    yk = [c1,   y1, y2, c2  ];
    yhat = interp1(xk, yk, x, 'linear', 'extrap');
end

function yhat = modelEvalClamped(x, dataXmin, dataXmax, xmin, xmax, x1, x2, c1, c2, y1, y2)
% Wie modelEval, aber ausserhalb der TATSAECHLICH gemessenen Daten
% [dataXmin, dataXmax] wird die Anfrage auf den naechsten Rand geklemmt ->
% der Funktionswert bleibt dort konstant (= Wert am Rand der Messdaten),
% statt der Randgerade zum offiziellen Messbereich [xmin,xmax] zu folgen.
    x = x(:);
    xClamped = min(max(x, dataXmin), dataXmax);
    yhat = modelEval(xClamped, xmin, xmax, x1, x2, c1, c2, y1, y2);
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
