% Function:
% 1. Select an MP4 video file (with default path)
% 2. Read all frames using VideoReader
% 3. Convert to grayscale on-the-fly
% 4. Store into a structure array (without storing RGB images)
% 5. Track the tip across all frames -> TipCoordinates
% 6. Manual review/correction, then plot the tip trajectory

clear; clc; close all;

%% 1. Select MP4 video file with default path
defaultPath = 'M:\nascas2\Projects\MemoryCI 2.0\1 Dokumentation\AP01_Iterative Inlay-Entwicklung\AP 1.B BFR-Tests\Testergebnisse\2026-06-23-MV71-11-MV71-12';
[vidFile, vidDir] = uigetfile({'*.mp4','MP4 Video (*.mp4)'; '*.*','Alle Dateien (*.*)'}, ...
    'Select MP4 video', defaultPath);
if isequal(vidFile, 0)
    error('No video selected');
end
videoFullPath = fullfile(vidDir, vidFile);

%% 2. Read video frames with VideoReader
v = VideoReader(videoFullPath);
ImageNummax = v.NumFrames;

% Initialize structure array
ImageData = struct('name', [], 'path', [], 'gray', [], 'bw', []);
ImageData(ImageNummax).name = []; % Preallocate

% Read and process frames one by one (no RGB storage)
for n = 1:ImageNummax
    img = read(v, n);

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
    ImageData(n).name = sprintf('frame_%05d', n);  % Frame index as name
    ImageData(n).gray = grayImgFiltered;           % Grayscale + median filtered image
    ImageData(n).bw   = bwImg;                      % Binarized image
    ImageData(n).path = videoFullPath;             % Source video
end


%% Trajektorie: vorhandene laden oder neu zuweisen?
% Pro Video wird die zugewiesene Trajektorie als .mat neben dem Video gespeichert.
% Nur wenn eine solche Datei existiert, wird gefragt; sonst direkt neu.
[~, vidName, ~] = fileparts(vidFile);
trajFile = fullfile(vidDir, [vidName '_tip_trajectory.mat']);
useExisting = false;
if isfile(trajFile)
    choice = questdlg(['Für dieses Video existiert bereits eine gespeicherte ', ...
        'Trajektorie. Möchtest du die alte verwenden oder eine neue zuweisen?'], ...
        'Trajektorie laden', 'Alte verwenden', 'Neu zuweisen', 'Alte verwenden');
    useExisting = strcmp(choice, 'Alte verwenden');
end

if useExisting
    % --- Alte Trajektorie laden: ROI-Auswahl, Tracking und Kontrolle entfallen ---
    S = load(trajFile, 'TipCoordinates');
    TipCoordinates = S.TipCoordinates;
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


%% 4. Compute Tip coordinates for all frames using fixed masks with curvature and connectivity check
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


%% 4b. Manuelle Kontrolle/Korrektur der Tip-Zuweisung
% Öffnet ein Fenster mit Slider durch die Bildfolge und dem zugewiesenen
% roten Kreuz. Per Klick ins Bild kann der Tip für den aktuellen Frame neu
% gesetzt werden. Erst nach Klick auf "Bestätigen" läuft das Programm weiter.
TipCoordinates = reviewTips(ImageData, TipCoordinates, tipRadius);

    % --- Neu zugewiesene Trajektorie speichern (für nächsten Programmstart) ---
    save(trajFile, 'TipCoordinates');
    fprintf('Trajektorie gespeichert: %s\n', trajFile);
end


%% Visualize Tip trajectory
% Extract valid Tip coordinates (non-zero and not NaN)
validIdx = all(TipCoordinates ~= 0, 2) & ~any(isnan(TipCoordinates), 2);
TipCoordsValid = TipCoordinates(validIdx, :);

if ~isempty(TipCoordsValid)
    [H, W] = size(ImageData(1).bw);   % Bildgröße für die Achsen
    figure(3);
    hold on;
    axis([1 W 1 H]);
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


%% Lokale Funktion: manuelle Kontrolle/Korrektur der Tip-Zuweisung
function TipCoordinates = reviewTips(ImageData, TipCoordinates, tipRadius)
% Slider zum Durchblättern der Bildfolge, Klick ins Bild setzt den Tip des
% aktuellen Frames neu. Mit "Bestätigen" wird die Kontrolle beendet und das
% (ggf. korrigierte) TipCoordinates zurückgegeben.

    nImg = numel(ImageData);
    cur  = 1;

    hFig = figure('Name', 'Tip-Kontrolle', 'NumberTitle', 'off');
    hAx  = axes('Parent', hFig, 'Position', [0.05 0.20 0.9 0.74]);

    % Slider zum Vor-/Zurückspulen durch die Frames
    if nImg > 1
        smallStep  = 1/(nImg-1);
        sliderStep = [smallStep, max(smallStep, 10/(nImg-1))];
    else
        sliderStep = [1 1];
    end
    hSlider = uicontrol('Parent', hFig, 'Style', 'slider', ...
        'Units', 'normalized', 'Position', [0.10 0.08 0.60 0.05], ...
        'Min', 1, 'Max', max(nImg,2), 'Value', 1, ...
        'SliderStep', sliderStep, 'Callback', @onSlide);
    addlistener(hSlider, 'Value', 'PostSet', @(s,e) onSlide());

    % Hinweistext
    uicontrol('Parent', hFig, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.10 0.135 0.60 0.035], ...
        'String', 'Slider: Frame wählen   |   Klick ins Bild: Tip neu zuweisen');

    % Bestätigen-Button
    uicontrol('Parent', hFig, 'Style', 'pushbutton', 'String', 'Bestätigen', ...
        'Units', 'normalized', 'Position', [0.74 0.08 0.18 0.06], ...
        'FontWeight', 'bold', 'Callback', @onConfirm);

    drawFrame();
    uiwait(hFig);   % blockiert das Skript, bis "Bestätigen" gedrückt wird

    % ---------- verschachtelte Callback-Funktionen ----------
    function onSlide(~, ~)
        cur = min(max(round(hSlider.Value), 1), nImg);
        drawFrame();
    end

    function onClick(~, ~)
        cp = get(hAx, 'CurrentPoint');
        xClick = round(cp(1,1));
        yClick = round(cp(1,2));
        TipCoordinates(cur, :) = [yClick, xClick];   % [row, col]
        drawFrame();
    end

    function onConfirm(~, ~)
        if isvalid(hFig)
            uiresume(hFig);
            close(hFig);
        end
    end

    function drawFrame()
        hImg = imshow(ImageData(cur).gray, 'Parent', hAx);
        set(hImg, 'ButtonDownFcn', @onClick);   % Klick aufs Bild -> Tip neu setzen
        hold(hAx, 'on');

        tc = TipCoordinates(cur, :);
        if all(tc ~= 0) && ~any(isnan(tc))
            % rotes Kreuz auf zugewiesener Tip-Position
            plot(hAx, tc(2), tc(1), 'r+', 'MarkerSize', 15, 'LineWidth', 2, ...
                'HitTest', 'off');
            statusStr = sprintf('Tip = (%d, %d)', tc(2), tc(1));
        else
            statusStr = 'kein Tip zugewiesen - bitte ins Bild klicken';
        end

        title(hAx, sprintf('Frame %d / %d   |   %s', cur, nImg, statusStr));
        hold(hAx, 'off');
    end
end
