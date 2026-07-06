% This gives the inlay geometry for TB01Lv01
% Written by: N. Suzaly
% Created on: 2019-07-05
%
% Erweiterung: 7 gleichmäßig (nach Bogenlänge) verteilte Punkte werden auf
% die Geometrie gelegt und die Krümmung an jedem Punkt berechnet, gemittelt
% und ausgegeben. Die Krümmungsberechnung ist bewusst IDENTISCH zu
% kruemung_hai.m, damit die mittlere Krümmung direkt als Normierung
% (max_kappa) für kruemung_hai.m verwendet werden kann.

clear all;
close all;
clc;

% [x,y]-coordinates for specified points in the inlay geometry. Coordinates
% obtained from Inventor
p0 = [0,0];
p1 = [2.5,0];
p2 = [4.7,0.589];
p3 = [5.505,3.595];
p4 = [2.637, 4.363];
p5 = [2.014, 3.741];
p6 = [2.527, 1.829];
p7 = [3.827, 1.829];

p = [p0;p1;p2;p3;p4;p5;p6;p7];

r = [4.4, 2.2 , 2.1, 1.7, 1.4, 1.3]';  % specified radius for the six arcs

% [x,y]-coordinates of the center of the six arcs. Coordinates obtained
% from Inventor
C1 = [2.5, 4.4];
C2 = [3.6,2.495];
C3 = [3.687, 2.545];
C4 = [3.487, 2.891];
C5 = [3.227, 3.041];
C6 = [3.177, 2.955];

C = [C1;C2;C3;C4;C5;C6];

% specified angles [rad] for the six arcs
rad1 = pi/6;
rad2 = pi/2;
rad3 = pi/2;
rad4 = pi/6;
rad5 = pi/2;
rad6 = pi/3;

rad = [rad1;rad2;rad3;rad4;rad5;rad6];

pts = 100;
d = [];
c = [];
a = [];
b= [];
t = [];
lxc = nan(pts, length(r));
lyc = nan(pts, length(r));

% Draw arcs
for n = 2:length(p)-1

    d(:,n-1) = norm(p(n+1,:)'-p(n,:)');  % r has to be larger than d/2
    c(n-1,:) = (p(n+1,:)'+p(n,:)')/2 + sqrt(r(n-1)^2-d(n-1)^2/4)/d(n-1)*[0,-1;1,0]*(p(n+1,:)'-p(n,:)');
    a(:,n-1) = atan2(p(n,2)-c(n-1,2),p(n,1)-c(n-1,1));
    b(:,n-1) = atan2(p(n+1,2)-c(n-1,2),p(n+1,1)-c(n-1,1));
    b(:,n-1) = mod(b(n-1)-a(n-1),2*pi)+a(n-1);
    t(:,n-1) = linspace(a(n-1),b(n-1),pts);
    lxc(:,n-1) = c(n-1,1) + r(n-1)*cos(t(:,n-1));
    lyc(:,n-1) = c(n-1,2) + r(n-1)*sin(t(:,n-1));

end
lx1= linspace(0,2.5,pts)';  %initial line before first arc
ly1= linspace(0,0,pts)';

lx = [lx1;lxc(:,1);lxc(:,2);lxc(:,3);lxc(:,4);lxc(:,5);lxc(:,6)];
ly = [ly1;lyc(:,1);lyc(:,2);lyc(:,3);lyc(:,4);lyc(:,5);lyc(:,6)];

inlay = [lx,ly];

xlswrite('inlayGeometry100.xls',inlay);  %import x,y-coordinates of inlay geometry into excel file

figure;
plot(lx,ly,'.')


%% 7 gleichmäßig verteilte Punkte + mittlere Krümmung
% Die Krümmung wird EXAKT wie in kruemung_hai.m (Zeilen 115-129) berechnet,
% damit die hier ermittelte mittlere Krümmung direkt als Normierung (max_kappa)
% für kruemung_hai.m taugt: 7 äquidistante Punkte (lineares Resampling),
% Gauß-Glättung, gradient DIREKT auf den 7 Punkten, kappa = |x'y''-y'x''| /
% (x'^2+y'^2)^1.5, dann Mittelwert (omitnan).
N = 7;         % gleiche Punktzahl wie in kruemung_hai.m

% Pixel pro mm des Videos (aus Kalibrierung). 1 = keine Umrechnung.
% WICHTIG: echten Kalibrierwert eintragen, damit die Inlay-Krümmung im selben
% Pixel-Maßstab wie kruemung_hai (max_kappa) liegt. Krümmung ist 1/Länge, sie
% skaliert also mit dem Maßstab -> darf nicht weggelassen werden.
pxPerMm = 1;

% Geometrie in den Pixel-Maßstab des Videos bringen (mm -> px)
X = lx(:) * pxPerMm;
Y = ly(:) * pxPerMm;

% Bogenlänge als monotone Stützstelle (Analogon zur Geodät-Distanz d in
% kruemung_hai). Doppelte Punkte an Bogenübergängen -> unique entfernt sie.
d = [0; cumsum(hypot(diff(X), diff(Y)))];
[d, iu] = unique(d);          % strikt monoton -> für interp1
X = X(iu);  Y = Y(iu);

% --- exakt wie kruemung_hai.m ---
s  = linspace(0, d(end), N);  % 7 gleiche Abstände (Zeilenvektor)
xs = interp1(d, X, s);        % LINEAR (Default), wie kruemung_hai
ys = interp1(d, Y, s);

xs = smoothdata(xs, 'gaussian', 2);
ys = smoothdata(ys, 'gaussian', 2);

dx  = gradient(xs);
dy  = gradient(ys);
ddx = gradient(dx);
ddy = gradient(dy);

kappa = (dx.*ddy - dy.*ddx) ./ (dx.^2 + dy.^2).^(1.5);
kappa = abs(kappa);

meanKappa = mean(kappa, 'omitnan');   % = Wert für max_kappa in kruemung_hai.m

% --- Ausgabe ---
fprintf('\nKrümmung an %d Punkten (Methode wie kruemung_hai.m, Maßstab %.4f px/mm):\n', ...
    N, pxPerMm);
for k = 1:N
    fprintf('  Punkt %d:  kappa = %.4f 1/px\n', k, kappa(k));
end
fprintf('Mittlere Krümmung (= max_kappa für kruemung_hai.m): %.4f 1/px\n', meanKappa);

% --- 7 Punkte im Plot markieren (in mm-Koordinaten für die Anzeige) ---
hold on;
plot(xs/pxPerMm, ys/pxPerMm, 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
axis equal; grid on;
title(sprintf('Inlay: mittlere Krümmung = %.4f 1/px  (%.4f px/mm)', ...
    meanKappa, pxPerMm));
hold off;
