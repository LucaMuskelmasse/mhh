function listKameras(dllPath)
% LISTKAMERAS  Diagnose-Hilfe: listet alle erkannten Videoquellen auf.
%
%   Zeigt nebeneinander
%     (a) die winvideo-Geraete der Image Acquisition Toolbox (ID + Name)
%     (b) die vom DNX64-SDK erkannten Dino-Lite-Geraete (Index + Port-Pfad)
%
%   Damit laesst sich feststellen, welcher winvideo-Index und welcher
%   USB-Port-Pfad (idaKey) aktuell zu LINKS bzw. RECHTS gehoeren — und ob
%   eine Kamera (z.B. die Laptop-Webcam) faelschlich mitzaehlt.
%
%   Aufruf:  listKameras            % nutzt "DNX64.dll"
%            listKameras("DNX64.dll")
%
%   Die Ausgabe einfach kopieren und zur Konfiguration von bfrAufnahmeApp
%   (CONFIG in openDinoLiteCameras) verwenden.

    if nargin < 1 || strlength(string(dllPath)) == 0, dllPath = "DNX64.dll"; end
    dllPath = string(dllPath);

    %% (a) winvideo-Geraete (Image Acquisition Toolbox) ------------------
    fprintf('\n=== winvideo-Geraete (videoinput) ===\n');
    try
        info = imaqhwinfo('winvideo');
        ids  = info.DeviceIDs;
        if isempty(ids)
            fprintf('  (keine winvideo-Geraete gefunden)\n');
        else
            for k = 1:numel(ids)
                di = info.DeviceInfo(k);
                fprintf('  winvideo-ID %d : %s\n', di.DeviceID, di.DeviceName);
            end
        end
    catch ME
        fprintf('  Fehler beim Abfragen der winvideo-Geraete: %s\n', ME.message);
    end

    %% (b) DNX64-SDK-Geraete ---------------------------------------------
    fprintf('\n=== DNX64-SDK-Geraete (Port-Pfade) ===\n');
    loadedHere = false;
    try
        if ~libisloaded('DNX64')
            loadlibrary(char(dllPath), 'DNX64forMatlab.h', 'alias', 'DNX64');
            loadedHere = true;
        end
        calllib('DNX64','SetVideoDeviceIndex',0); pause(0.1);
        nDnx = calllib('DNX64','GetVideoDeviceCount');
        fprintf('  GetVideoDeviceCount = %d\n', nDnx);
        for idx = 0:nDnx-1
            calllib('DNX64','SetVideoDeviceIndex', idx); pause(0.1);
            ida = string(calllib('DNX64','GetDeviceIDA', idx));
            key = extractPortKey(ida);
            fprintf('  DNX64-Index %d : Port %-20s (IDA roh: %s)\n', idx, key, ida);
        end
    catch ME
        fprintf('  Fehler beim Abfragen der DNX64-Geraete: %s\n', ME.message);
    end
    if loadedHere
        try, unloadlibrary('DNX64'); catch, end
    end

    fprintf(['\nHinweis: Die Dino-Lite-Geraete heissen bei winvideo meist ' ...
             '"Dino-Lite" o.ae.,\n         die Laptop-Webcam traegt einen ' ...
             'anderen Namen. Vergleiche Anzahl und\n         Reihenfolge mit ' ...
             'den DNX64-Port-Pfaden, um LINKS/RECHTS korrekt zuzuordnen.\n\n']);
end

% ----------------------------------------------------------------------
function key = extractPortKey(ida)
% "...mi_00#6&d82dd4a&0&0000#{guid}..." -> "6&d82dd4a&0&0000"
    tok = regexp(lower(ida), 'mi_\d+#(.*?)#\{', 'tokens', 'once');
    if isempty(tok), key = lower(ida); else, key = string(tok{1}); end
end
