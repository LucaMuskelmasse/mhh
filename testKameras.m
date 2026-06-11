function testKameras
% TESTKAMERAS  Minimaltest OHNE die App.
%
%   Prueft, ob die beiden Dino-Lites EINZELN und GEMEINSAM ein Live-Bild
%   liefern. Damit laesst sich klaeren, ob das "rote Kreuz" am Programm-
%   code liegt (dann nicht reproduzierbar) oder am Geraet/USB/Treiber bzw.
%   an der USB-Bandbreite (zwei Kameras am selben Controller).
%
%   Vorgehen:
%     1) App (bfrAufnahmeApp) und ggf. DinoCapture o.ae. komplett schliessen.
%     2) In MATLAB:  testKameras
%     3) Nacheinander beobachten: Live-Bild oder rotes Kreuz?
%
%   Beobachtung bitte zurueckmelden:
%     - LINKS allein:   Bild / rotes Kreuz?
%     - RECHTS allein:  Bild / rotes Kreuz?
%     - BEIDE zusammen: beide Bild / eine rotes Kreuz / beide rotes Kreuz?

    imaqreset; pause(0.5);

    % --- LINKS allein -------------------------------------------------
    fprintf('Oeffne LINKS (winvideo 1) ...\n');
    vL = videoinput('winvideo', 1);
    fL = figure('Name','TEST LINKS','NumberTitle','off');
    preview(vL, image(zeros(vL.VideoResolution(2), vL.VideoResolution(1), ...
                            vL.NumberOfBands, 'uint8')));
    uiwait(msgbox('LINKS allein: Live-Bild oder rotes Kreuz? -> OK','TEST LINKS','modal'));

    % --- RECHTS zusaetzlich (beide gleichzeitig) ----------------------
    fprintf('Oeffne RECHTS (winvideo 2) zusaetzlich ...\n');
    vR = videoinput('winvideo', 2);
    fR = figure('Name','TEST RECHTS','NumberTitle','off');
    preview(vR, image(zeros(vR.VideoResolution(2), vR.VideoResolution(1), ...
                            vR.NumberOfBands, 'uint8')));
    uiwait(msgbox(['BEIDE gleichzeitig: streamen beide, oder zeigt eine ' ...
                   'das rote Kreuz? -> OK'],'TEST BEIDE','modal'));

    % --- aufraeumen ---------------------------------------------------
    try, stoppreview([vL vR]); catch, end
    try, delete([vL vR]);      catch, end
    try, delete([fL fR]);      catch, end
    imaqreset;
    fprintf('Test beendet.\n');
end
