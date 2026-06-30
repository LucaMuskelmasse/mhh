function buildBfrAufnahmeApp(iconFile)
% BUILDBFRAUFNAHMEAPP  Erstellt eine eigenstaendige Windows-.exe aus
% bfrAufnahmeApp.m, die beim Doppelklick direkt die GUI oeffnet.
%
%   buildBfrAufnahmeApp                 % ohne eigenes Icon
%   buildBfrAufnahmeApp('mein_icon.png')% mit eigenem Icon (.png oder .ico)
%
% VORAUSSETZUNGEN
%   - MATLAB Compiler (Toolbox).  Pruefen:  license('test','Compiler')
%   - DNX64.dll UND DNX64forMatlab.h im selben Ordner wie dieses Skript
%     (werden fuer die Kamera-LED-Steuerung gebraucht).
%   - Ein konfigurierter C-Compiler fuer die einmalige Prototyp-Erzeugung
%     (pruefen/einrichten mit:  mex -setup  ). MATLABs mitgelieferter
%     MinGW reicht in der Regel.
%
% ERGEBNIS
%   <Skriptordner>\bfrAufnahmeApp_exe\bfrAufnahmeApp.exe
%   Der ZIEL-PC braucht zusaetzlich:
%     - die passende MATLAB Runtime (kostenlos; siehe Hinweis am Ende),
%     - installierte Dino-Lite-Treiber,
%     - DNX64.dll erreichbar (wird mit eingepackt).
%
% HINWEIS: Dieses Skript wurde nicht in einer Live-MATLAB-Umgebung getestet.
% Sollte der Build oder die .exe meckern, siehe die Fehlermeldungen unten und
% die Troubleshooting-Hinweise in bfrAufnahmeApp.md (Abschnitt zur .exe).

    if nargin < 1, iconFile = ''; end
    here    = fileparts(mfilename('fullpath'));
    appFile = fullfile(here, 'bfrAufnahmeApp.m');
    assert(isfile(appFile), 'bfrAufnahmeApp.m nicht gefunden in %s', here);

    %% 0) Compiler vorhanden? -------------------------------------------------
    if isempty(which('compiler.build.standaloneApplication'))
        error(['MATLAB Compiler nicht verfuegbar. Bitte die Toolbox ' ...
               '"MATLAB Compiler" installieren (Check:  ver  /  ' ...
               'license(''test'',''Compiler'') ).']);
    end

    dll    = fullfile(here, 'DNX64.dll');
    header = fullfile(here, 'DNX64forMatlab.h');
    extra  = {};

    %% 1) DNX64-Prototyp + Thunk erzeugen (fuer loadlibrary in der .exe) ------
    % loadlibrary kann in einer kompilierten App keinen C-Header parsen. Darum
    % hier EINMAL eine Prototyp-Datei (DNX64_proto.m) + Thunk-DLL erzeugen und
    % mit einpacken. bfrAufnahmeApp.m (loadDNX64) nutzt sie im deployten Modus.
    if isfile(dll) && isfile(header)
        fprintf('1) Erzeuge DNX64-Prototyp (DNX64_proto.m) ...\n');
        oldDir = cd(here);  cu = onCleanup(@() cd(oldDir));
        try
            if libisloaded('DNX64'), unloadlibrary('DNX64'); end
            loadlibrary(dll, header, 'mfilename', 'DNX64_proto', 'alias', 'DNX64');
            unloadlibrary('DNX64');
            fprintf('   Prototyp erzeugt.\n');
        catch ME
            warning(['Prototyp-Erzeugung fehlgeschlagen: %s\n' ...
                     '   -> Die .exe kann die DNX64-DLL evtl. nicht laden ' ...
                     '(Kamera-/LED-Funktionen). C-Compiler einrichten: mex -setup'], ...
                     ME.message);
        end
        clear cu;
        for f = {'DNX64_proto.m', 'DNX64_thunk_pcwin64.dll', 'DNX64.dll', 'DNX64forMatlab.h'}
            p = fullfile(here, f{1});
            if isfile(p), extra{end+1} = p; end %#ok<AGROW>
        end
    else
        warning(['DNX64.dll und/oder DNX64forMatlab.h fehlen in %s.\n' ...
                 '   -> Die .exe wird gebaut, aber das Oeffnen der Kameras ' ...
                 'schlaegt fehl. Beide Dateien hierher legen und neu bauen.'], here);
    end

    %% 2) Build-Optionen ------------------------------------------------------
    outDir = fullfile(here, 'bfrAufnahmeApp_exe');
    args = { appFile, ...
        'ExecutableName', 'bfrAufnahmeApp', ...
        'OutputDir',      outDir, ...
        'Verbose',        'on' };
    if ~isempty(extra)
        args = [args, {'AdditionalFiles', extra}];
    end
    if ~isempty(iconFile) && isfile(iconFile)
        % ExecutableIcon wird nicht von allen MATLAB-Versionen unterstuetzt;
        % bei Fehler diese Zeile entfernen und das Icon nachtraeglich setzen.
        args = [args, {'ExecutableIcon', iconFile}];
    end

    %% 3) Bauen ---------------------------------------------------------------
    fprintf('2) Starte Build - das dauert einige Minuten ...\n');
    results = compiler.build.standaloneApplication(args{:});

    fprintf('\n==================================================\n');
    fprintf('Fertig.\n');
    fprintf('EXE: %s\n', fullfile(outDir, 'bfrAufnahmeApp.exe'));
    fprintf('==================================================\n');
    fprintf(['Hinweis: Auf einem PC OHNE MATLAB muss die passende MATLAB ' ...
             'Runtime\ninstalliert sein. Eine einmalige Installer-Variante ' ...
             '(buendelt die\nRuntime) bekommst du mit:\n' ...
             '   compiler.package.installer(results)\n' ...
             'oder ueber die App "Application Compiler" (deploytool).\n']);
    disp(results);
end
