% Function:
% 1. Select a folder (with default path)
% 2. Read all JPG images using imageDatastore
% 3. Convert to grayscale on-the-fly
% 4. Store into a structure array (without storing RGB images)
% 5. Display the first image
% 6. Display elapsed time
clear; clc; close all;

%% 1. Select folder with default path
defaultPath = 'M:\nascas2\Projects\MemoryCI 2.0\1 Dokumentation\AP01_Iterative Inlay-Entwicklung\AP 1.B BFR-Tests\Testergebnisse\2026-06-23-MV71-11-MV71-12';
ImgPath = uigetdir(defaultPath, 'Select folder with images');
if ImgPath == 0
    error('No folder selected');
end

%% 2. Create imageDatastore
imds = imageDatastore(fullfile(ImgPath, '*.jpg'));
ImageNummax = numel(imds.Files);

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

    % --- Binarisierung ---
    level = 0.58;
    bwImg = imbinarize(grayImgFiltered, level);

    % ROI: außerhalb des interessanten Bereichs auf weiß setzen
    bwImg_size = size(bwImg);
    whiteImg = ones(bwImg_size);
    whiteImg(1:end-70, 400:end-170) = bwImg(1:end-70, 400:end-170);
    bwImg = whiteImg;


    [H, W] = size(bwImg);

    xv = [0.3563 0.4332 0.9173 1.1393 1.1933 1.1768 0.9188 0.6053 0.5183]*1000;
    yv = [0.0005 0.9313 0.9253 0.7618 0.4918 0.2037 0.0822 0.0792 0.0005]*1000;


    mask = poly2mask(xv, yv, H, W);
    mask = ~mask;
    bwImg(mask) = 1;

    figure(1)
    imshow(bwImg);


    % --- Skelettierung mit Lückenschließung ---
    % Vordergrund-Konvention: Draht = 1
    wireFG = ~bwImg;

    wireFG = bwareaopen(wireFG, 300);     % kleine Specks entfernen

    % Lücken schließen (Radius an größte Lücke anpassen, größer = mehr Brücken)
    gapCloseRadius = 12;
    wireFG_closed = imclose(wireFG, strel('disk', gapCloseRadius));

    N = 20;                               % gewünschte Punktzahl entlang des Drahtes
    % Default-Werte, falls der Frame unbrauchbar ist (z.B. zerrissenes Skelett)
    xs    = nan(1, N);
    ys    = nan(1, N);
    kappa = nan(1, N);
    skel  = false(size(wireFG_closed));

    % Nur die größte zusammenhängende Komponente behalten
    % -> entfernt isolierte Blasen und kleine Drahtfragmente
    cc = bwconncomp(wireFG_closed);
    if cc.NumObjects >= 1
        [~, imax] = max(cellfun(@numel, cc.PixelIdxList));
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
    ImageData(n).bw   = bwImg;
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

%% 5. Farbliche Krümmungsdarstellung über dem Originalbild
figure;
cmap = jet(256);
allKappa = [ImageData.kappa];
kMin = min(allKappa);            % min/max ignorieren NaN automatisch
kMax = max(allKappa);

for n = 1:ImageNummax
    imshow(ImageData(n).gray); hold on;

    kValues = ImageData(n).kappa;

    for i = 1:length(ImageData(n).xs)-1

        normVal = (kValues(i) - kMin) / (kMax - kMin);
        normVal = min(max(normVal, 0), 1);

        colorIdx = max(1, round(normVal * 255) + 1);
        lineColor = cmap(colorIdx,:);

        plot(ImageData(n).xs(i:i+1), ImageData(n).ys(i:i+1), ...
            '-', 'LineWidth', 3, 'Color', lineColor);
    end

    title(sprintf('Skelett über Originalbild (Frame %d)', n));
    drawnow;
    hold off;
    pause(0.1);
end
