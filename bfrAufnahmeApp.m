function bfrAufnahmeApp
% BFRAUFNAHMEAPP  Zentrale Bedienoberflaeche fuer den BFR-Versuch.
%
%   Liest zyklisch (timer-basiert, nicht blockierend) die Temperatur beider
%   Kanaele des Omega HH806AWE aus und nimmt pro Seite getrennt ein
%   Kamerabild auf, sobald die Temperatur der jeweiligen Seite ueber den
%   letzten Ausloesewert steigt (Geraeteaufloesung 0.1 °C -> ein Bild je
%   0.1-Grad-Schritt).
%
%   Mit dem Umschaltknopf "Abkühlvorgang" (waehrend des Laufs) wird die
%   Ausloesung umgedreht: Es wird ein Foto gemacht, sobald die Temperatur
%   unter den letzten Ausloesewert FAELLT.
%   Erneutes Druecken wechselt zurueck zum Aufwaermvorgang.
%
%   Ueber das Dropdown "Kameras" kann gewaehlt werden, ob nur die linke,
%   nur die rechte oder beide Kameras verwendet werden. Es werden nur die
%   gewaehlten Kameras geoeffnet, nur deren Unterordner angelegt und nur
%   fuer diese Seiten Bilder ausgeloest. Die Temperaturen beider Kanaele
%   werden weiterhin angezeigt und geplottet.
%
%   Aufruf:  bfrAufnahmeApp
%
%   Benoetigt im Pfad (bzw. unten angehaengt):
%     getHH806Temp, captureSingleFrameSide, openDinoLiteCameras

%% ================= Geteilter Zustand (nested-function Workspace) =================
s        = [];          % serialport-Objekt (waehrend eines Laufs offen)
cams     = [];          % struct mit Feldern .left / .right (videoinput)
tmr      = [];          % timer-Objekt fuer die Messschleife
t0       = NaT;         % Startzeitpunkt des Laufs
prevL    = -Inf;        % letzter Ausloesewert links
prevR    = -Inf;        % letzter Ausloesewert rechts
cntL     = 0;           % Bildzaehler links
cntR     = 0;           % Bildzaehler rechts
running  = false;       % Laufstatus
cooling  = false;       % false = Aufwaermen (Ausloesung bei Anstieg),
                        % true  = Abkuehlen (Ausloesung bei Abfall)

% Zur Laufzeit eingefrorene Parameter (beim Start aus den Feldern gelesen)
dirLrun   = "";
dirRrun   = "";
prefixRun = "";
inlay1Run = "";         % Inlay-Kennnummer links  (fuer den Bildstempel)
inlay2Run = "";         % Inlay-Kennnummer rechts (fuer den Bildstempel)
useL      = true;       % linke Kamera in diesem Lauf aktiv
useR      = true;       % rechte Kamera in diesem Lauf aktiv
stopTrun  = 70;         % Stopp-Temperatur Aufwaermen: Ende, wenn BEIDE Kanaele >= Wert
stopCrun  = 37;         % Stopp-Temperatur Abkuehlen:  Ende, wenn BEIDE Kanaele <= Wert

%% ================================ UI-Aufbau =====================================
fig = uifigure('Name','BFR-Versuch — Aufnahmesteuerung', ...
               'Position',[60 60 1280 780], ...
               'CloseRequestFcn',@onClose);

gMain = uigridlayout(fig, [2 2]);
gMain.RowHeight   = {'1x', 170};
gMain.ColumnWidth = {370, '1x'};

% ------------------------------ linke Spalte ------------------------------------
gLeft = uigridlayout(gMain, [3 1]);
gLeft.Layout.Row    = 1;
gLeft.Layout.Column = 1;
gLeft.RowHeight     = {'fit','fit','fit'};
gLeft.Padding       = [0 0 0 0];

% --- Parameter-Panel ---
pnlParam = uipanel(gLeft, 'Title','Parameter');
gP = uigridlayout(pnlParam, [12 3]);
gP.ColumnWidth = {120, '1x', 32};
gP.RowHeight   = repmat({'fit'}, 1, 12);

uilabel(gP, 'Text','COM-Port:');
edtCom = uieditfield(gP, 'text', 'Value','COM4');
edtCom.Layout.Column = [2 3];

uilabel(gP, 'Text','Intervall [s]:');
edtInt = uieditfield(gP, 'numeric', 'Value',1.0, ...
                     'Limits',[0.05 Inf], 'LowerLimitInclusive','on');
edtInt.Layout.Column = [2 3];

uilabel(gP, 'Text','Stopp Aufw. [°C]:');
edtStopT = uieditfield(gP, 'numeric', 'Value',70, ...
    'Tooltip',['Aufwaermvorgang: Lauf stoppt automatisch, wenn BEIDE ' ...
               'Kanaele >= diesem Wert sind.']);
edtStopT.Layout.Column = [2 3];

uilabel(gP, 'Text','Stopp Abk. [°C]:');
edtStopC = uieditfield(gP, 'numeric', 'Value',37, ...
    'Tooltip',['Abkuehlvorgang: Lauf stoppt automatisch, wenn BEIDE ' ...
               'Kanaele <= diesem Wert sind.']);
edtStopC.Layout.Column = [2 3];

uilabel(gP, 'Text','Kameras:');
ddCams = uidropdown(gP, ...
    'Items',         {'Beide','Nur links','Nur rechts'}, ...
    'ItemsData',     {'beide','links','rechts'}, ...
    'Value',         'beide', ...
    'Tooltip',       'Welche Kamera(s) sollen in diesem Lauf aufnehmen?', ...
    'ValueChangedFcn', @(~,~) syncInlayFields());
ddCams.Layout.Column = [2 3];

uilabel(gP, 'Text','Basisordner:');
edtBase = uieditfield(gP, 'text', 'Value','D:\MemoryCI 2.0\BFR-Versuch');
btnBrowseBase = uibutton(gP, 'Text','…', 'Tooltip','Basisordner waehlen', ...
                         'ButtonPushedFcn', @(~,~) onBrowse(edtBase));

uilabel(gP, 'Text','Datum:');
edtDatum = uieditfield(gP, 'text', ...
    'Value', char(datetime('today','Format','yyyy-MM-dd')), ...
    'Tooltip','Format YYYY-MM-DD');
edtDatum.Layout.Column = [2 3];

lblInlay1 = uilabel(gP, 'Text','Inlay 1 (links):');
edtInlay1 = uieditfield(gP, 'text', 'Placeholder','xx-xx');
edtInlay1.Layout.Column = [2 3];

lblInlay2 = uilabel(gP, 'Text','Inlay 2 (rechts):');
edtInlay2 = uieditfield(gP, 'text', 'Placeholder','xx-xx');
edtInlay2.Layout.Column = [2 3];

% Inlay-Felder passend zur Kameraauswahl ein-/ausblenden (Initialzustand)
syncInlayFields();

chkFM = uicheckbox(gP, 'Text','Funktionsmuster (-FM)');
chkFM.Layout.Column = [1 3];
chkSpiral = uicheckbox(gP, 'Text','Spiralform (-s)');
chkSpiral.Layout.Column = [1 3];

uilabel(gP, 'Text','Datums-Praefix:');
edtPrefix = uieditfield(gP, 'text', ...
    'Value', char(datetime('now','Format','yyyyMMdd')));
edtPrefix.Layout.Column = [2 3];

% Alle waehrend eines Laufs zu sperrenden Bedienelemente
lockables = [edtCom, edtInt, edtStopT, edtStopC, ddCams, edtBase, ...
             edtDatum, edtInlay1, edtInlay2, chkFM, chkSpiral, edtPrefix, ...
             btnBrowseBase];

% --- Steuerungs-Panel (Start/Stop/Status) ---
pnlCtrl = uipanel(gLeft, 'Title','Steuerung');
gC = uigridlayout(pnlCtrl, [1 6]);
gC.ColumnWidth = {'1x','1x','1x','fit',24,'fit'};

btnStart = uibutton(gC, 'Text','Start', 'FontWeight','bold', ...
                    'ButtonPushedFcn', @onStart);
btnStop  = uibutton(gC, 'Text','Stop', 'Enable','off', ...
                    'ButtonPushedFcn', @onStop);
btnCool  = uibutton(gC, 'state', 'Text','Abkühlvorgang', 'Enable','off', ...
                    'Tooltip',['Gedrueckt: Foto bei FALLENDER Temperatur ' ...
                               '(Abkuehlvorgang). Erneut druecken: zurueck ' ...
                               'zum Aufwaermvorgang.'], ...
                    'ValueChangedFcn', @onCool);
btnLed   = uibutton(gC, 'Text','LEDs aus', ...
                    'Tooltip','Dino-Lite-LEDs erneut ausschalten', ...
                    'ButtonPushedFcn', @(~,~) ledsOff(true));
lamp     = uilamp(gC, 'Color',[0.6 0.6 0.6]);
lblState = uilabel(gC, 'Text','gestoppt');

% --- Zaehler-Panel ---
pnlCnt = uipanel(gLeft, 'Title','Bildzaehler');
gZ = uigridlayout(pnlCnt, [2 2]);
gZ.ColumnWidth = {'1x','1x'};

uilabel(gZ, 'Text','Bilder links:');
lblCntL = uilabel(gZ, 'Text','0', 'FontWeight','bold');
uilabel(gZ, 'Text','Bilder rechts:');
lblCntR = uilabel(gZ, 'Text','0', 'FontWeight','bold');

% ------------------------------ rechte Spalte -----------------------------------
gRight = uigridlayout(gMain, [3 2]);
gRight.Layout.Row    = 1;
gRight.Layout.Column = 2;
gRight.RowHeight     = {80, '1x', 230};
gRight.Padding       = [0 0 0 0];

% --- grosse Live-Temperaturanzeigen ---
lblTL = uilabel(gRight, 'Text','— °C', 'FontSize',38, 'FontWeight','bold', ...
                'HorizontalAlignment','center');
lblTR = uilabel(gRight, 'Text','— °C', 'FontSize',38, 'FontWeight','bold', ...
                'HorizontalAlignment','center');

% --- Live-Kameravorschau links/rechts ---
axCamL = uiaxes(gRight); title(axCamL, 'Kamera LINKS');
axCamR = uiaxes(gRight); title(axCamR, 'Kamera RECHTS');
for ax = [axCamL axCamR]
    ax.XTick = []; ax.YTick = [];
end

% --- Live-Plot (Temperatur ueber Zeit, beide Kanaele) ---
axPlot = uiaxes(gRight);
axPlot.Layout.Row    = 3;
axPlot.Layout.Column = [1 2];
hold(axPlot, 'on'); grid(axPlot, 'on');
xlabel(axPlot, 't seit Start [s]'); ylabel(axPlot, 'Temperatur');
lineL = animatedline(axPlot, 'Color',[0.00 0.45 0.74], 'LineWidth',1.5, ...
                     'MaximumNumPoints',7200, 'DisplayName','links');
lineR = animatedline(axPlot, 'Color',[0.85 0.33 0.10], 'LineWidth',1.5, ...
                     'MaximumNumPoints',7200, 'DisplayName','rechts');
legend(axPlot, 'Location','northwest');

% ------------------------------ Status-Log --------------------------------------
txtLog = uitextarea(gMain, 'Editable','off', 'Value',{''});
txtLog.Layout.Row    = 2;
txtLog.Layout.Column = [1 2];

%% ============================ Dark-Mode-Styling =================================
% Zentrale Farbpalette — alle Farben der App an einer Stelle.
C = struct( ...
    'bg',      [0.11 0.11 0.13], ...   % Fensterhintergrund
    'panel',   [0.15 0.15 0.18], ...   % Panels / Karten
    'field',   [0.20 0.20 0.24], ...   % Eingabefelder / Buttons
    'border',  [0.32 0.32 0.38], ...   % Rahmen / Gitterlinien
    'text',    [0.91 0.91 0.93], ...   % Standardtext
    'subtle',  [0.62 0.62 0.68], ...   % Sekundaertext / Achsen
    'accentL', [0.38 0.69 1.00], ...   % Akzent links (blau)
    'accentR', [1.00 0.58 0.28], ...   % Akzent rechts (orange)
    'start',   [0.13 0.38 0.22], ...   % Start-Button (gruen)
    'stop',    [0.45 0.17 0.17]);      % Stop-Button (rot)

fig.Color = C.bg;

% Layout-Raster: Hintergruende + etwas Luft zwischen den Elementen
set([gMain gLeft gRight], 'BackgroundColor', C.bg);
set([gP gC gZ],           'BackgroundColor', C.panel);
gMain.Padding   = [10 10 10 10];
gMain.RowSpacing = 10;  gMain.ColumnSpacing = 10;
gLeft.RowSpacing = 10;
gRight.RowSpacing = 8;  gRight.ColumnSpacing = 8;

% Panels (Titelzeile hell auf dunkel)
set(findall(fig, 'Type','uipanel'), 'BackgroundColor', C.panel, ...
    'ForegroundColor', C.text, 'FontWeight', 'bold');

% Beschriftungen, Eingabefelder, Auswahl, Buttons
set(findall(fig, 'Type','uilabel'),            'FontColor', C.text);
set(findall(fig, 'Type','uieditfield'),        'BackgroundColor', C.field, 'FontColor', C.text);
set(findall(fig, 'Type','uinumericeditfield'), 'BackgroundColor', C.field, 'FontColor', C.text);
set(findall(fig, 'Type','uidropdown'),         'BackgroundColor', C.field, 'FontColor', C.text);
set(findall(fig, 'Type','uicheckbox'),         'FontColor', C.text);
set(findall(fig, 'Type','uibutton'),           'BackgroundColor', C.field, 'FontColor', C.text);
set(findall(fig, 'Type','uistatebutton'),      'BackgroundColor', C.field, 'FontColor', C.text);

% Akzente: Start gruen, Stop rot, Temperaturen in den Plot-Farben
btnStart.BackgroundColor = C.start;
btnStop.BackgroundColor  = C.stop;
lblTL.FontColor = C.accentL;
lblTR.FontColor = C.accentR;
lblState.FontColor = C.subtle;

% Achsen (Kameravorschau + Live-Plot)
for ax = [axCamL axCamR axPlot]
    ax.Color       = C.panel;
    ax.XColor      = C.subtle;
    ax.YColor      = C.subtle;
    ax.GridColor   = C.border;
    ax.Title.Color = C.text;
end
axPlot.XLabel.Color = C.subtle;
axPlot.YLabel.Color = C.subtle;
lineL.Color = C.accentL;
lineR.Color = C.accentR;
lgd = legend(axPlot);
lgd.TextColor = C.text;
lgd.Color     = C.panel;
lgd.EdgeColor = C.border;

% Status-Log als dunkle "Konsole" mit Monospace-Schrift
txtLog.BackgroundColor = [0.08 0.08 0.10];
txtLog.FontColor       = [0.78 0.84 0.78];
txtLog.FontName        = 'Consolas';

logMsg("Bereit. Parameter pruefen und 'Start' druecken.");

%% ================================ Callbacks =====================================

    % ----------------------------------------------------------------- Browse ---
    function onBrowse(edt)
        % Zielordner per Dialog waehlen und ins Feld uebernehmen
        d = uigetdir(edt.Value, 'Zielordner waehlen');
        figure(fig);                       % App-Fenster wieder in den Vordergrund
        if ~isequal(d, 0)
            edt.Value = d;
        end
    end

    % ------------------------------------------------------------------ Start ---
    function onStart(~,~)
        if running, return; end
        try
            % --- Parameter aus den Feldern lesen und validieren ---
            port      = strtrim(string(edtCom.Value));
            intervall = edtInt.Value;
            stopTrun  = edtStopT.Value;
            stopCrun  = edtStopC.Value;
            baseDir   = strtrim(string(edtBase.Value));
            datum     = strtrim(string(edtDatum.Value));
            inlay1    = regexprep(strtrim(string(edtInlay1.Value)), '^(MV|mv)', '');
            inlay2    = regexprep(strtrim(string(edtInlay2.Value)), '^(MV|mv)', '');
            prefixRun = strtrim(string(edtPrefix.Value));

            % --- Kameraauswahl fuer diesen Lauf einfrieren ---
            camSel = string(ddCams.Value);          % "beide" | "links" | "rechts"
            useL   = camSel ~= "rechts";
            useR   = camSel ~= "links";

            % Inlay-Nummern fuer den Bildstempel einfrieren
            inlay1Run = inlay1;
            inlay2Run = inlay2;

            assert(strlength(port)    > 0, "COM-Port darf nicht leer sein.");
            assert(intervall          > 0, "Intervall muss > 0 sein.");
            assert(strlength(baseDir) > 0, "Basisordner darf nicht leer sein.");
            assert(~isempty(regexp(datum, '^\d{4}-\d{2}-\d{2}$', 'once')), ...
                   "Datum bitte im Format YYYY-MM-DD angeben.");
            % Nur die Inlays der aktiven Seite(n) sind Pflicht
            if useL
                assert(strlength(inlay1) > 0, "Kennnummer Inlay 1 (links) darf nicht leer sein.");
            end
            if useR
                assert(strlength(inlay2) > 0, "Kennnummer Inlay 2 (rechts) darf nicht leer sein.");
            end
            assert(strlength(prefixRun) > 0, "Datums-Praefix darf nicht leer sein.");

            % --- Versuchsordner nach festem Namensschema zusammensetzen ---
            % beide : <Datum>-MV<Inlay1>-MV<Inlay2>[-FM][-s]
            % links : <Datum>-MV<Inlay1>[-FM][-s]
            % rechts: <Datum>-MV<Inlay2>[-FM][-s]
            name = datum;
            if useL, name = name + "-MV" + inlay1; end
            if useR, name = name + "-MV" + inlay2; end
            if chkFM.Value,     name = name + "-FM"; end
            if chkSpiral.Value, name = name + "-s";  end
            ordner = string(fullfile(baseDir, name));

            % --- Bestaetigung wie im alten Skript ---
            sel = uiconfirm(fig, ...
                "Geplanter Versuchsordner:" + newline + newline + ordner + ...
                newline + newline + "Kameras: " + camLabel(), ...
                "Ordner anlegen?", ...
                'Options',{'Anlegen','Abbrechen'}, ...
                'DefaultOption',1, 'CancelOption',2);
            if ~strcmp(sel, 'Anlegen')
                logMsg("Start abgebrochen — es wurde kein Ordner erstellt.");
                return;
            end

            % --- Versuchsordner + Unterordner nur fuer aktive Seiten anlegen ---
            if exist(ordner, 'dir')
                logMsg("Ordner existiert bereits — wird weiterverwendet: " + ordner);
            else
                [okMk, msgMk] = mkdir(ordner);
                assert(okMk, "Versuchsordner konnte nicht erstellt werden: " + string(msgMk));
                logMsg("Versuchsordner erstellt: " + ordner);
            end
            dirLrun = string(fullfile(ordner, "links"));
            dirRrun = string(fullfile(ordner, "rechts"));
            if useL && ~exist(dirLrun, 'dir'), mkdir(dirLrun); end
            if useR && ~exist(dirRrun, 'dir'), mkdir(dirRrun); end

            % UI sperren
            set(lockables, 'Enable', 'off');
            btnStart.Enable = 'off';
            drawnow;

            % --- serialport EINMALIG oeffnen (offen halten, nicht pro Tick) ---
            % Evtl. verwaiste serialport-Objekte auf diesem Port freigeben
            try
                if exist('serialportfind','file')          % ab R2024a
                    delete(serialportfind('Port', port));
                end
            catch
            end
            logMsg("Oeffne " + port + " …");
            s = serialport(port, 19200, "Parity","even", "DataBits",8, "StopBits",1);
            s.Timeout = 1;

            % --- Nur die gewaehlten Kameras oeffnen (feste Zuordnung, LEDs aus) ---
            sides = strings(1,0);
            if useL, sides(end+1) = "LINKS";  end
            if useR, sides(end+1) = "RECHTS"; end
            logMsg("Oeffne Dino-Lite-Kamera(s): " + camLabel() + " …");
            cams = openDinoLiteCameras("DNX64.dll", sides);

            % Externe Vorschaufenster schliessen und Streams in die App umleiten
            attachPreviews();

            % --- Laufzustand initialisieren ---
            t0    = datetime('now');
            prevL = -Inf;  prevR = -Inf;
            cntL  = 0;     cntR  = 0;
            if useL, lblCntL.Text = '0'; else, lblCntL.Text = '— (inaktiv)'; end
            if useR, lblCntR.Text = '0'; else, lblCntR.Text = '— (inaktiv)'; end
            clearpoints(lineL);  clearpoints(lineR);

            % --- Timer (fixedRate) starten — UI bleibt bedienbar ---
            tmr = timer('ExecutionMode','fixedRate', ...
                        'Period', intervall, ...
                        'BusyMode','drop', ...
                        'TimerFcn', @onTick, ...
                        'ErrorFcn', @(~,e) logMsg("Timer-Fehler: " + e.Data.message));
            start(tmr);

            running        = true;
            cooling        = false;                 % jeder Lauf beginnt als Aufwaermvorgang
            btnCool.Value  = false;
            btnCool.Enable = 'on';
            btnStop.Enable = 'on';
            lamp.Color     = [0 0.8 0];
            lblState.Text  = 'läuft (Aufwärmen)';
            logMsg(sprintf(['Lauf gestartet (Intervall %.2f s, ' ...
                            'Stopp Aufw. %.1f °C, Stopp Abk. %.1f °C, Kameras: %s).'], ...
                           intervall, stopTrun, stopCrun, camLabel()));
        catch ME
            logMsg("Start fehlgeschlagen: " + string(ME.message));
            cleanupResources();
            set(lockables, 'Enable', 'on');
            syncInlayFields();          % Inlay-Sichtbarkeit wiederherstellen
            btnStart.Enable = 'on';
            btnStop.Enable  = 'off';
            btnCool.Enable  = 'off';
            btnCool.Value   = false;
            lamp.Color      = [0.6 0.6 0.6];
            lblState.Text   = 'gestoppt';
        end
    end

    % --------------------------------------------------- Abkuehl-/Aufwaerm-Modus ---
    function onCool(~,~)
        % Schaltet waehrend des Laufs zwischen Aufwaerm- und Abkuehlvorgang um.
        % Beim Umschalten wird der Referenzwert so gesetzt, dass die naechste
        % Messung ein Basisbild ausloest.
        if ~running
            btnCool.Value = false;
            return;
        end
        cooling = logical(btnCool.Value);
        if cooling
            prevL = +Inf;  prevR = +Inf;
            lblState.Text = 'läuft (Abkühlen)';
            logMsg("Abkühlvorgang aktiviert — Foto bei fallender Temperatur.");
        else
            prevL = -Inf;  prevR = -Inf;
            lblState.Text = 'läuft (Aufwärmen)';
            logMsg("Aufwärmvorgang aktiviert — Foto bei steigender Temperatur.");
        end
    end

    % ------------------------------------------------------------- Timer-Tick ---
    function onTick(~,~)
        % Ein Messzyklus: Temperatur lesen, Anzeige aktualisieren, ggf. ausloesen.
        % Fehler in einem Tick duerfen den Lauf nicht abbrechen.
        try
            [vals, units, ok] = getHH806Temp(s);   % offenes Objekt uebergeben!
            if ~ok || numel(vals) < 2
                logMsg("Lesefehler am Thermometer (Antwort nicht dekodierbar).");
                return;
            end

            uL = "°C"; uR = "°C";
            if numel(units) >= 2, uL = units(1); uR = units(2); end

            % --- Live-Anzeige + Plot aktualisieren (beide Kanaele, unabhaengig
            %     von der Kameraauswahl) ---
            lblTL.Text = sprintf('L: %.1f %s', vals(1), uL);
            lblTR.Text = sprintf('R: %.1f %s', vals(2), uR);

            tsec = seconds(datetime('now') - t0);
            if ~isnan(vals(1)), addpoints(lineL, tsec, vals(1)); end
            if ~isnan(vals(2)), addpoints(lineR, tsec, vals(2)); end

            % --- Automatischer Stopp, je nach Modus ---
            % Aufwaermen: BEIDE Kanaele >= Stopp Aufw.  |  Abkuehlen: BEIDE <= Stopp Abk.
            if ~cooling && vals(1) >= stopTrun && vals(2) >= stopTrun
                drawnow limitrate;
                logMsg(sprintf(['Stopp-Temperatur Aufwaermen erreicht (L: %.1f %s, ' ...
                    'R: %.1f %s >= %.1f °C) — Lauf wird automatisch gestoppt.'], ...
                    vals(1), uL, vals(2), uR, stopTrun));
                onStop();
                return;
            end
            if cooling && vals(1) <= stopCrun && vals(2) <= stopCrun
                drawnow limitrate;
                logMsg(sprintf(['Stopp-Temperatur Abkuehlen erreicht (L: %.1f %s, ' ...
                    'R: %.1f %s <= %.1f °C) — Lauf wird automatisch gestoppt.'], ...
                    vals(1), uL, vals(2), uR, stopCrun));
                onStop();
                return;
            end

            % --- Ausloeselogik: Aufwaermen -> jeder Anstieg ueber den letzten
            %     Ausloesewert, Abkuehlen -> jeder Abfall darunter. Bei der
            %     Geraeteaufloesung von 0.1 °C ergibt das ein Bild je
            %     0.1-Grad-Schritt (jeweils nur aktive Seiten). ---
            if cooling
                trigL = vals(1) < prevL;
                trigR = vals(2) < prevR;
            else
                trigL = vals(1) > prevL;
                trigR = vals(2) > prevR;
            end

            if useL && trigL
                captureSingleFrameSide(cams.left, dirLrun, t0, prefixRun, vals(1), "L", ...
                                       "MV" + inlay1Run);
                cntL = cntL + 1;
                lblCntL.Text = num2str(cntL);
                logMsg(sprintf("Aufnahme LINKS  bei %.1f %s (Bild %d).", vals(1), uL, cntL));
                prevL = vals(1);            % nur bei Ausloesung aktualisieren
            end

            if useR && trigR
                captureSingleFrameSide(cams.right, dirRrun, t0, prefixRun, vals(2), "R", ...
                                       "MV" + inlay2Run);
                cntR = cntR + 1;
                lblCntR.Text = num2str(cntR);
                logMsg(sprintf("Aufnahme RECHTS bei %.1f %s (Bild %d).", vals(2), uR, cntR));
                prevR = vals(2);            % nur bei Ausloesung aktualisieren
            end

            drawnow limitrate;
        catch ME
            logMsg("Fehler im Messzyklus: " + string(ME.message));
        end
    end

    % ------------------------------------------------------------------- Stop ---
    function onStop(~,~)
        if ~running, return; end
        logMsg("Stoppe Lauf …");
        cleanupResources();
        running         = false;
        cooling         = false;
        set(lockables, 'Enable', 'on');
        syncInlayFields();          % Inlay-Sichtbarkeit wiederherstellen
        btnStart.Enable = 'on';
        btnStop.Enable  = 'off';
        btnCool.Enable  = 'off';
        btnCool.Value   = false;
        lamp.Color      = [0.6 0.6 0.6];
        lblState.Text   = 'gestoppt';
        logMsg(sprintf("Lauf beendet. Bilder links: %d, rechts: %d.", cntL, cntR));
    end

    % ---------------------------------------------------------- Fenster zu -----
    function onClose(~,~)
        % Beim Schliessen des Fensters alle Ressourcen aufraeumen
        try
            cleanupResources();
        catch
        end
        delete(fig);
    end

%% ============================== Hilfsfunktionen ==================================

    function syncInlayFields()
        % Blendet die Inlay-Eingabefelder passend zur Kameraauswahl ein/aus.
        % Nur links  -> nur Inlay 1; nur rechts -> nur Inlay 2; beide -> beide.
        camSel = string(ddCams.Value);     % "beide" | "links" | "rechts"
        wantL  = camSel ~= "rechts";
        wantR  = camSel ~= "links";
        setInlay(lblInlay1, edtInlay1, wantL);
        setInlay(lblInlay2, edtInlay2, wantR);
    end

    function setInlay(lbl, edt, on)
        % Ein einzelnes Inlay-Feld samt Label aktivieren/deaktivieren.
        if on
            lbl.Enable = 'on';  edt.Enable = 'on';
        else
            edt.Value  = '';            % deaktiviertes Feld leeren
            lbl.Enable = 'off'; edt.Enable = 'off';
        end
    end

    function lbl = camLabel()
        % Lesbare Beschreibung der aktuellen Kameraauswahl fuers Log / Dialoge
        if useL && useR
            lbl = "beide";
        elseif useL
            lbl = "nur links";
        else
            lbl = "nur rechts";
        end
    end

    function vv = activeCams()
        % Liefert die videoinput-Objekte der in diesem Lauf aktiven Seiten
        vv = [];
        if isempty(cams), return; end
        if useL && ~isempty(cams.left),  vv = [vv cams.left];  end
        if useR && ~isempty(cams.right), vv = [vv cams.right]; end
    end

    function attachPreviews()
        % Leitet die Live-Vorschau der aktiven Kameras in die App-Achsen um,
        % schliesst die von openDinoLiteCameras erzeugten externen Fenster und
        % markiert die Achsen inaktiver Seiten.
        stoppreview(activeCams());
        for nm = ["LINKS","RECHTS"]
            fOld = findall(0, 'Type','figure', 'Name',char(nm));
            delete(fOld);
        end
        if useL
            hImL = makePreviewImage(axCamL, cams.left);
            preview(cams.left, hImL);      % fluessiger Stream, getrennt vom
        else                               % getsnapshot beim Speichern
            showInactive(axCamL);
        end
        if useR
            hImR = makePreviewImage(axCamR, cams.right);
            preview(cams.right, hImR);
        else
            showInactive(axCamR);
        end

        % WICHTIG: Der Neustart der Vorschau schaltet die Dino-Lite-LEDs
        % automatisch wieder ein -> nach kurzem Anlaufen erneut ausschalten.
        pause(0.5); drawnow;
        ledsOff(false);
    end

    function ledsOff(verbose)
        % Schaltet die LEDs aller angeschlossenen Dino-Lite-Kameras aus.
        % verbose = true -> Erfolg/Misserfolg ins Log schreiben (Button).
        if nargin < 1, verbose = false; end
        try
            if ~libisloaded('DNX64')
                if verbose, logMsg("DNX64 nicht geladen — LEDs koennen nur bei laufendem Lauf geschaltet werden."); end
                return;
            end
            n = calllib('DNX64','GetVideoDeviceCount');
            for idx = 0:n-1
                calllib('DNX64','SetVideoDeviceIndex', idx); pause(0.1);
                calllib('DNX64','SetLEDState', idx, 0);      pause(0.1);   % 0 = aus
            end
            if verbose, logMsg("LEDs ausgeschaltet."); end
        catch ME2
            logMsg("LEDs ausschalten fehlgeschlagen: " + string(ME2.message));
        end
    end

    function hIm = makePreviewImage(ax, vid)
        % Erzeugt ein passend dimensioniertes image-Objekt fuer preview()
        cla(ax);
        res = vid.VideoResolution;     % [Breite Hoehe]
        nb  = vid.NumberOfBands;
        hIm = image(zeros(res(2), res(1), nb, 'uint8'), 'Parent', ax);
        axis(ax, 'image');
        ax.XTick = []; ax.YTick = [];
    end

    function showInactive(ax)
        % Markiert die Vorschau-Achse einer nicht verwendeten Kameraseite
        cla(ax);
        ax.XLim = [0 1]; ax.YLim = [0 1];
        text(ax, 0.5, 0.5, 'inaktiv', 'HorizontalAlignment','center', ...
             'FontSize',18, 'Color',[0.55 0.55 0.55]);
        ax.XTick = []; ax.YTick = [];
    end

    function cleanupResources()
        % Timer, Kameras, DNX64-Bibliothek und serialport sauber freigeben.
        % Jede Stufe einzeln abgesichert, damit Teilfehler den Rest nicht blockieren.
        try
            if ~isempty(tmr) && isvalid(tmr)
                stop(tmr); delete(tmr);
            end
        catch, end
        tmr = [];

        try
            if ~isempty(cams)
                vv = [cams.left cams.right];   % leere Seiten fallen hier raus
                vv = vv(arrayfun(@isvalid, vv));
                if ~isempty(vv)
                    stoppreview(vv);
                    delete(vv);
                end
            end
        catch, end
        cams = [];

        try
            if libisloaded('DNX64'), unloadlibrary('DNX64'); end
        catch, end

        try
            s = [];                    % serialport schliesst beim Loeschen
        catch, end
    end

    function logMsg(msg)
        % Zeitgestempelte Zeile ans Status-Log anhaengen (max. 500 Zeilen)
        line = sprintf('[%s] %s', char(datetime('now','Format','HH:mm:ss')), char(msg));
        v = txtLog.Value;
        if ~iscell(v), v = cellstr(v); end
        if numel(v) == 1 && isempty(strtrim(v{1}))
            v = {};
        end
        v{end+1} = line; %#ok<AGROW>
        if numel(v) > 500
            v = v(end-499:end);
        end
        txtLog.Value = v;
        try
            scroll(txtLog, 'bottom');
        catch
        end
        drawnow limitrate;
    end

end % ================================ Ende App =====================================


%% ###############################################################################
%  Ab hier: vorhandene Funktionen (uebernommen), damit die Datei komplett
%  eigenstaendig lauffaehig ist. Liegen sie bereits im Pfad, koennen diese
%  lokalen Kopien auch entfernt werden.
%  ###############################################################################

function cams = openDinoLiteCameras(dllPath, sides)
% OPENDINOLITECAMERAS  Oeffnet die gewuenschten Dino-Lite-Kameras mit fester
% Links/Rechts-Zuordnung ueber den USB-Portpfad, beschriftet die Vorschau-
% fenster mit LINKS / RECHTS und schaltet die LEDs aus. Die Funktion kehrt
% erst zurueck, nachdem die Scharfstellung im OK-Fenster bestaetigt wurde
% (die Vorschauen laufen waehrend des Wartens weiter).
%
%   cams = openDinoLiteCameras()                          % beide Kameras
%   cams = openDinoLiteCameras("DNX64.dll")               % beide Kameras
%   cams = openDinoLiteCameras("DNX64.dll", "LINKS")      % nur links
%   cams = openDinoLiteCameras("DNX64.dll", ["LINKS","RECHTS"])
%
% Eingaben:
%   dllPath - Pfad zur DNX64.dll (Default "DNX64.dll")
%   sides   - string-Array mit den zu oeffnenden Seiten, Teilmenge von
%             ["LINKS","RECHTS"] (Default: beide)
%
% Rueckgabe: cams.left, cams.right (videoinput-Objekt oder [] wenn die
%            Seite nicht angefordert wurde).
%
% Schliessen:  vv=[cams.left cams.right]; stoppreview(vv); delete(vv);
%              clear cams; unloadlibrary('DNX64')
%
% ============================ KONFIGURATION ============================
    CONFIG(1).side = "LINKS";   CONFIG(1).winvideo = 2;  CONFIG(1).idaKey = "6&189ed0a2&8&0000";
    CONFIG(2).side = "RECHTS";  CONFIG(2).winvideo = 1;  CONFIG(2).idaKey = "6&d82dd4a&0&0000";
% =======================================================================

    if nargin < 1 || strlength(string(dllPath)) == 0, dllPath = "DNX64.dll"; end
    dllPath = string(dllPath);
    if nargin < 2 || isempty(sides), sides = ["LINKS","RECHTS"]; end
    sides = upper(string(sides));

    % Nur die angeforderten Seiten aus der Konfiguration verwenden
    CONFIG = CONFIG(ismember([CONFIG.side], sides));
    assert(~isempty(CONFIG), ...
           "Keine gueltige Kameraseite angefordert (erlaubt: LINKS, RECHTS).");

    %% 1) DNX64-SDK laden ------------------------------------------------
    if ~libisloaded('DNX64')
        loadlibrary(char(dllPath), 'DNX64forMatlab.h', 'alias', 'DNX64');
    end

    %% 2) Portpfade aller angeschlossenen DNX64-Geraete auslesen ---------
    calllib('DNX64','SetVideoDeviceIndex',0); pause(0.1);
    nDnx = calllib('DNX64','GetVideoDeviceCount');
    keys = strings(1, nDnx);
    for idx = 0:nDnx-1
        calllib('DNX64','SetVideoDeviceIndex', idx); pause(0.1);
        ida = string(calllib('DNX64','GetDeviceIDA', idx));
        keys(idx+1) = extractPortKey(ida);
    end
    fprintf("Angeschlossene Port-Kennungen: %s\n", strjoin(keys, ", "));

    %% 3) Fail-safe: sind alle benoetigten Ports vorhanden? --------------
    % Es muessen mindestens die Ports der angeforderten Seiten gefunden
    % werden — sonst Abbruch, damit LINKS/RECHTS nicht vertauscht werden.
    cfgKeys = [CONFIG.idaKey];
    missing = setdiff(cfgKeys, keys);
    if ~isempty(missing)
        error(['Die angeschlossenen USB-Ports passen nicht zur Konfiguration ' ...
               'der angeforderten Seite(n).\nBenoetigt: %s\nGefunden : %s\n' ...
               'Vermutlich wurden die Ports geaendert. Bitte CONFIG neu ' ...
               'kalibrieren - es wird abgebrochen, damit LINKS/RECHTS nicht ' ...
               'vertauscht werden.'], strjoin(cfgKeys,", "), strjoin(keys,", "));
    end

    %% 4) Kameras oeffnen, Fenster beschriften + platzieren --------------
    % Vorab die Bildaufnahme zuruecksetzen: gibt evtl. verwaiste videoinput-
    % Objekte aus frueheren (abgebrochenen) Laeufen frei, die das Geraet sonst
    % blockieren -> sonst zeigt die Vorschau nur ein rotes Kreuz ("Geraet belegt").
    try, imaqreset; pause(0.5); catch, end

    scr = get(0,'ScreenSize');
    wW  = scr(3)*0.46;  wH = wW*0.72;  yP = scr(4)*0.28;
    posBySide = struct('LINKS',  [scr(3)*0.02, yP, wW, wH], ...
                       'RECHTS', [scr(3)*0.52, yP, wW, wH]);

    % Bei einem Fehler waehrend des Oeffnens alle bereits erzeugten Objekte
    % wieder freigeben, damit nichts verwaist zurueckbleibt.
    cams    = struct('left', [], 'right', []);
    opened  = [];
    figs    = [];
    try
        for c = 1:numel(CONFIG)
            vid = videoinput('winvideo', CONFIG(c).winvideo);
            opened = [opened vid]; %#ok<AGROW>
            vid.FramesPerTrigger = 1;
            triggerconfig(vid, 'manual');

            hFig = figure('Name', char(CONFIG(c).side), 'NumberTitle', 'off', ...
                          'MenuBar', 'none', 'Position', posBySide.(CONFIG(c).side), ...
                          'Color', [0.11 0.11 0.13]);
            figs = [figs hFig]; %#ok<AGROW>
            res = vid.VideoResolution;  nb = vid.NumberOfBands;
            hAx = axes('Parent', hFig);
            hIm = image(zeros(res(2), res(1), nb), 'Parent', hAx);
            axis(hAx, 'image'); axis(hAx, 'off');
            title(hAx, CONFIG(c).side, 'FontSize', 16, 'FontWeight', 'bold', ...
                  'Color', [0.91 0.91 0.93]);
            preview(vid, hIm);

            if CONFIG(c).side == "LINKS", cams.left = vid; else, cams.right = vid; end
            fprintf("%-6s -> winvideo-ID %d (Port %s)\n", ...
                    CONFIG(c).side, CONFIG(c).winvideo, CONFIG(c).idaKey);
        end
    catch ME
        % Aufraeumen, damit keine belegten Geraete zurueckbleiben
        try, stoppreview(opened); catch, end
        try, delete(opened);      catch, end
        try, delete(figs(ishghandle(figs))); catch, end
        rethrow(ME);
    end

    %% 5) LEDs ausschalten (nach dem Stream-Start) ----------------------
    for idx = 0:nDnx-1
        calllib('DNX64','SetVideoDeviceIndex', idx); pause(0.1);
        calllib('DNX64','SetLEDState', idx, 0);      pause(0.1);   % 0 = aus
    end
    fprintf("LEDs aus. Bitte in den Fenstern pruefen, ob die Zuordnung stimmt.\n");

    %% 6) Auf Scharfstellung warten - haelt die Vorschauen aktiv --------
    pause(0.5); drawnow;
    fprintf("\nWarte auf Bestaetigung der Scharfstellung...\n");
    if numel(CONFIG) == 1
        frage = sprintf('Ist die Kamera %s scharf gestellt?', CONFIG(1).side);
    else
        frage = 'Sind beide Kameras scharf gestellt?';
    end
    bestaetigt = false;
    hWait = figure('Name','Scharfstellung', 'NumberTitle','off', ...
                   'MenuBar','none', 'Resize','off', ...
                   'Position',[scr(3)*0.40, scr(4)*0.46, 280, 130]);
    uicontrol('Parent',hWait, 'Style','text', 'FontSize',11, ...
              'Units','normalized', 'Position',[0.08 0.5 0.84 0.35], ...
              'String',frage);
    uicontrol('Parent',hWait, 'Style','pushbutton', 'FontSize',11, ...
              'Units','normalized', 'Position',[0.30 0.12 0.40 0.28], ...
              'String','OK - weiter', 'Callback',@onOK);

    while ~bestaetigt && ishghandle(hWait)
        drawnow limitrate;     % haelt die Live-Vorschauen am Laufen
        pause(0.03);
    end
    if ishghandle(hWait), delete(hWait); end
    fprintf("Weiter geht's.\n");

    % --- verschachtelte Funktion: OK-Knopf ---
    function onOK(~,~)
        bestaetigt = true;
    end
end

% ----------------------------------------------------------------------
function key = extractPortKey(ida)
% "...mi_00#6&d82dd4a&0&0000#{guid}..." -> "6&d82dd4a&0&0000"
    tok = regexp(lower(ida), 'mi_\d+#(.*?)#\{', 'tokens', 'once');
    if isempty(tok), key = lower(ida); else, key = string(tok{1}); end
end

function [vals, units, ok, raw] = getHH806Temp(portOrObj, closeAfter)
% GETHH806TEMP  Liest EINMAL die Temperatur eines Omega HH806AWE aus.
%
%   [vals, units, ok] = getHH806Temp(s)          % s = offenes serialport-Objekt
%   [vals, units, ok] = getHH806Temp("COM4")     % Port wird geoeffnet & geschlossen
%   [vals, units, ok] = getHH806Temp("COM4", false) % Port nach Lesen offen lassen
%
% Eingaben:
%   portOrObj  - ENTWEDER ein bereits offenes serialport-Objekt (schnell, fuer
%                getaktete Loops) ODER ein Portname als string/char (z.B. "COM4").
%   closeAfter - optional (logical), nur relevant bei Portname-Eingabe.
%                Default true: Port wird nach dem Lesen wieder geschlossen.
%
% Ausgaben:
%   vals   - 1xN double, Messwerte (NaN bei +OL/-OL Ueberlauf)
%   units  - 1xN string, zugehoerige Einheiten
%   ok     - logical, true wenn Antwort dekodierbar war
%   raw    - rohe Antwort-Bytes (uint8) zur Diagnose
%
% Protokoll (Omega 8xx): 19200,E,8,1 | Kommando ASCII (Grossbuchstaben) + CR LF.

    if nargin < 2, closeAfter = true; end

    ID = "00";   % Geraete-ID (2 Hex)
    CH = "00";   % Kanal      (2 Hex)

    % --- Port beschaffen ---------------------------------------------------
    % Portname (char/string) -> selbst oeffnen. Sonst: offenes Objekt nutzen.
    openedHere = false;
    if ischar(portOrObj) || isstring(portOrObj)
        s = serialport(portOrObj, 19200, "Parity","even", ...
                       "DataBits",8, "StopBits",1);
        s.Timeout = 1;          % max 1 s auf Antwort warten
        openedHere = true;
    else
        s = portOrObj;          % bereits offenes serialport-Objekt
    end

    % --- Kommando senden ---------------------------------------------------
    cmd = buildCmd("#0A" + ID + CH + "N");
    flush(s);                   % Altlasten im Puffer verwerfen
    write(s, cmd, "uint8");

    % --- Antwort blockierend lesen (identisch zu readHH806) ----------------
    raw = [];
    b1 = read(s, 1, "uint8");                 % 1. auf Startbyte '>' (62) warten
    if ~isempty(b1) && b1 == 62
        b2 = read(s, 1, "uint8");             % 2. LL = Frame-Gesamtlaenge
        if ~isempty(b2)
            LL = double(b2);
            if LL > 2
                rest = read(s, LL - 2, "uint8");  % 3. Rest in einem Rutsch
                raw  = [b1, b2, rest];
            end
        end
    end

    % --- Port ggf. wieder schliessen ---------------------------------------
    % serialport schliesst beim Loeschen der Variable automatisch.
    if openedHere && closeAfter
        clear s;
    end

    % --- Dekodieren --------------------------------------------------------
    [vals, units, ok] = decodeMeasurement(raw);
end

% ======================= lokale Hilfsfunktionen =======================
function b = buildCmd(payload)
    p  = double(char(payload));
    cs = mod(sum(p), 256);
    b  = [p, double(upper(dec2hex(cs,2))), 13, 10];   % + CR LF
end

function [vals, units, ok] = decodeMeasurement(raw)
% Dekodiert die rohe Binaerantwort des '#...N'-Kommandos.
    vals = []; units = strings(1,0); ok = false;

    if numel(raw) < 6 || raw(1) ~= 62, return; end    % 62 = '>'

    LL  = double(raw(2));
    nCh = floor((LL - 5) / 5);                         % Header(4) + n*5 + Checksum(1)

    if nCh < 1 || numel(raw) < 4 + nCh*5 + 1, return; end

    vals  = zeros(1, nCh);
    units = strings(1, nCh);

    for k = 1:nCh
        off = 4 + (k-1)*5;
        AAA = double(raw(off+1))*65536 + double(raw(off+2))*256 + double(raw(off+3)); % 24-Bit big-endian
        C   = double(raw(off+5));                      % Einheitencode
        dp  = bitand(bitshift(AAA, -20), 7);           % Dezimalpunkt
        val = bitand(AAA, 1048575);                    % untere 20 Bit

        if val >= 524288, val = val - 1048576; end     % 2er-Komplement

        if val == 524287 || val == -524288             % +OL / -OL
            vals(k) = NaN;
        else
            vals(k) = val / 10^double(dp);
        end
        units(k) = unitName(C);
    end
    ok = true;
end

function u = unitName(c)
    deg = char(176);                  % Gradzeichen
    switch c
        case 1, u = string([deg 'C']);
        case 2, u = string([deg 'F']);
        case 3, u = string([deg 'K']);
        otherwise, u = sprintf("[Einheit %d]", c);
    end
end

function captureSingleFrameSide(cam, outDir, t0, datePrefix, temp, sideLabel, inlayLabel)
% CAPTURESINGLEFRAMESIDE  Speichert genau EIN Bild EINER Kamera (links ODER rechts).
%
% Dateiname:  <datePrefix>_<elapsed>_<temp>.jpg
% Beispiel:   20250924_123621_03-5.jpg   (Temperatur 3.5, '.' ersetzt durch '-')
%
% Vor dem Speichern werden Stempel ins Bild gebrannt:
%   unten links:  <yyyy/MM/dd> @ <HH:mm:ss> <inlayLabel>
%   unten rechts: Temperature: <x,x> Deg-C
%
%   captureSingleFrameSide(cams.left,  dirL, t0, datePrefix, vals(1), "L", "MV71-07")
%   captureSingleFrameSide(cams.right, dirR, t0, datePrefix, vals(2), "R", "MV71-08")
%
% Eingaben:
%   cam        - Kamera-Objekt der gewuenschten Seite (z.B. cams.left)
%   outDir     - Zielordner fuer diese Seite (z.B. dirL bzw. dirR)
%   t0         - Startzeitpunkt (datetime) zur Berechnung von elapsed
%   datePrefix - Dateinamen-Praefix (Datum zuerst)
%   temp       - aktuelle Temperatur dieser Seite (double, z.B. 3.5)
%   sideLabel  - optionales Label nur fuer die Konsolenausgabe ("L"/"R")
%   inlayLabel - optionale Inlay-Kennung fuer den Stempel (z.B. "MV71-07")

    if nargin < 6, sideLabel  = ""; end
    if nargin < 7, inlayLabel = ""; end

    % Vergangene Sekunden seit Start -> identisches Namensschema wie zuvor
    elapsed = round(seconds(datetime('now') - t0));

    % Temperatur als "03-5" formatieren: 2-stelliger Ganzzahlteil, '.' -> '-'
    tempStr = strrep(sprintf('%04.1f', temp), '.', '-');

    fname = sprintf('%s_%06d_%s.jpg', datePrefix, elapsed, tempStr);

    try
        % Bild aus dem Videostream holen, stempeln und speichern
        img = getsnapshot(cam);

        nowDt   = datetime('now');
        stampBL = strtrim(sprintf('%s @ %s %s', ...
            char(datetime(nowDt,'Format','yyyy/MM/dd')), ...
            char(datetime(nowDt,'Format','HH:mm:ss')), char(inlayLabel)));
        stampBR = ['Temperature: ' strrep(sprintf('%.1f', temp), '.', ',') ' Deg-C'];
        img = stampImage(img, stampBL, stampBR);

        imwrite(img, fullfile(outDir, fname));
        fprintf("[%s] %s gespeichert: %s\n", ...
                datestr(now,'HH:MM:SS'), sideLabel, fname);
    catch ME
        warning("Aufnahme (%s) bei t=%ds fehlgeschlagen: %s", ...
                sideLabel, elapsed, ME.message);
    end
end

function img = stampImage(img, txtBL, txtBR)
% STAMPIMAGE  Brennt die Stempeltexte unten links/rechts ins Bild ein
% (weisse Schrift auf schwarzem Kasten).
%
% Bevorzugt insertText (Computer Vision Toolbox); ist die Toolbox nicht
% installiert, rendert ein Fallback den Text ueber eine unsichtbare Figure.
% Schlaegt auch das fehl, wird das Bild UNGESTEMPELT zurueckgegeben — der
% Stempel darf das Speichern der Aufnahme nie verhindern.
    try
        H    = size(img,1);  W = size(img,2);
        fs   = max(14, round(H/42));        % Schriftgroesse an Bildhoehe koppeln
        marg = max(8,  round(H/60));        % Randabstand

        if exist('insertText','file')
            img = insertText(img, [marg,   H-marg], txtBL, 'FontSize',fs, ...
                'TextColor','white', 'BoxColor','black', 'BoxOpacity',1, ...
                'AnchorPoint','LeftBottom');
            img = insertText(img, [W-marg, H-marg], txtBR, 'FontSize',fs, ...
                'TextColor','white', 'BoxColor','black', 'BoxOpacity',1, ...
                'AnchorPoint','RightBottom');
        else
            img = blitLabel(img, renderTextStrip(txtBL, fs), 'sw', marg);
            img = blitLabel(img, renderTextStrip(txtBR, fs), 'se', marg);
        end
    catch ME
        warning('Bildstempel fehlgeschlagen (%s) — Bild wird ungestempelt gespeichert.', ...
                ME.message);
    end
end

function strip = renderTextStrip(txt, fontPx)
% Rendert weissen Text auf schwarzem Grund als RGB-Streifen (uint8).
% Nutzt eine persistente unsichtbare Figure, damit pro Bild nur der Text
% aktualisiert und gerendert werden muss.
    persistent hFig hTxt
    if isempty(hFig) || ~ishghandle(hFig)
        hFig = figure('Visible','off', 'Units','pixels', ...
                      'Position',[50 50 1200 120], 'Color','k', ...
                      'MenuBar','none', 'ToolBar','none', ...
                      'IntegerHandle','off', 'HandleVisibility','off');
        hAx  = axes('Parent',hFig, 'Units','normalized', 'Position',[0 0 1 1], ...
                    'Visible','off', 'XLim',[0 1200], 'YLim',[0 120]);
        hTxt = text(hAx, 10, 60, '', 'Color','w', 'FontUnits','pixels', ...
                    'FontName','Consolas', 'Interpreter','none', ...
                    'VerticalAlignment','middle');
    end
    hTxt.FontSize = fontPx;
    hTxt.String   = txt;

    fr   = getframe(hFig);
    A    = fr.cdata;
    mask = any(A > 40, 3);                  % Pixel mit Textanteil
    rows = find(any(mask,2));  cols = find(any(mask,1));
    if isempty(rows)                        % nichts gerendert -> leerer Kasten
        strip = zeros(2*fontPx, 4*fontPx, 3, 'uint8');
        return;
    end
    pad = round(0.4*fontPx);                % schwarzer Rand um den Text
    r1 = max(1, rows(1)-pad);  r2 = min(size(A,1), rows(end)+pad);
    c1 = max(1, cols(1)-pad);  c2 = min(size(A,2), cols(end)+pad);
    strip = A(r1:r2, c1:c2, :);
end

function img = blitLabel(img, strip, corner, marg)
% Kopiert einen Textstreifen deckend in die linke ('sw') oder rechte ('se')
% untere Bildecke. Klassen-/Graustufen-sicher.
    if ndims(img) == 2                              % Graustufenbild
        strip = uint8(mean(double(strip), 3));
    end
    if isfloat(img)
        strip = cast(strip, 'like', img) / 255;     % double/single: 0..1
    elseif ~isa(img, 'uint8')
        strip = cast(double(strip) / 255 * double(intmax(class(img))), class(img));
    end

    [sh, sw, ~] = size(strip);
    [H,  W,  ~] = size(img);
    sh = min(sh, H);  sw = min(sw, W);
    strip = strip(1:sh, 1:sw, :);

    r2 = min(H, H - marg);  r1 = max(1, r2 - sh + 1);
    switch corner
        case 'sw',  c1 = min(W, 1 + marg);  c2 = min(W, c1 + sw - 1);
        otherwise,  c2 = max(1, W - marg);  c1 = max(1, c2 - sw + 1);
    end
    img(r1:r2, c1:c2, :) = strip(1:(r2-r1+1), 1:(c2-c1+1), :);
end
