function bildFolgeZusammenfuehren()
%BILDFOLGEZUSAMMENFUEHREN  Fuehrt mehrere (durch Abstuerze entstandene) Bild-
%   ordner einer Aufnahme zu EINEM Ordner zusammen und benennt die Bilder um.
%
%   Hintergrund:
%   Die Bilder der ALTEN Aufnahme-Version heissen
%       <yyyyMMdd>_<Sekunden seit Start, 6-stellig>_<Temp z.B. 03-5>.jpg
%   z.B. 20260615_000123_03-5.jpg  (= 123 s seit Start, 3.5 Grad)
%
%   Da das Aufnahmeprogramm mehrfach abgestuerzt ist, liegen die Bilder in
%   mehreren Ordnern; bei jedem Neustart wurde der Sekundenzaehler wieder auf
%   0 gesetzt. Dieses Skript stellt die durchgehende echte Uhrzeit wieder her
%   und schreibt alle Bilder im NEUEN Schema in einen Zielordner:
%       <yyyyMMdd>_<HHmmss>_<Temp>.jpg
%
%   Vorgehen / Annahmen:
%   * Die Ordner werden NACHEINANDER ausgewaehlt (1. = frueheste Aufnahme).
%     Auswahl beenden: im Ordnerdialog auf "Abbrechen" klicken.
%   * Startuhrzeit des allerersten Bildes = Dateidatum (Aenderungszeit) des
%     ersten Bildes im ersten Ordner.
%   * Innerhalb eines Ordners: echte Zeit = Basiszeit + Sekunden-seit-Start.
%   * Zwischen zwei Ordnern werden +30 s fuer den Neustart addiert
%     (erstes Bild des naechsten Ordners = letztes Bild davor + 30 s).
%   * Die Bilder werden KOPIERT; die Originalordner bleiben unveraendert.
%
%   Aufruf:  bildFolgeZusammenfuehren   (oeffnet die Dialoge)

    NEUSTART_LUECKE_S = 30;   % Sekunden, die ein Neustart gedauert hat

    % --- 1) Ordner nacheinander auswaehlen --------------------------------
    ordnerListe = {};
    startPfad   = pwd;
    while true
        nr  = numel(ordnerListe) + 1;
        sel = uigetdir(startPfad, sprintf('Ordner %d auswaehlen (Abbrechen = fertig)', nr));
        if isequal(sel, 0)
            break;                       % Abbrechen -> Auswahl beenden
        end
        ordnerListe{end+1} = sel;        %#ok<AGROW>
        startPfad = fileparts(sel);      % naechster Dialog startet daneben
        fprintf('Ordner %d: %s\n', nr, sel);
    end

    if isempty(ordnerListe)
        fprintf('Keine Ordner ausgewaehlt. Abbruch.\n');
        return;
    end

    % --- 2) Zielordner waehlen --------------------------------------------
    zielOrdner = uigetdir(startPfad, 'Zielordner fuer ALLE Bilder auswaehlen');
    if isequal(zielOrdner, 0)
        fprintf('Kein Zielordner ausgewaehlt. Abbruch.\n');
        return;
    end
    if ~exist(zielOrdner, 'dir'); mkdir(zielOrdner); end

    % --- 3) Ordner der Reihe nach verarbeiten -----------------------------
    basisZeit   = datetime.empty;   % Basiszeit des aktuellen Ordners
    letzteZeit  = datetime.empty;   % echte Zeit des letzten Bildes im Vorordner
    gesamtKopie = 0;
    gesamtWarn  = 0;

    for k = 1:numel(ordnerListe)
        ordner = ordnerListe{k};
        d = dir(fullfile(ordner, '*.jpg'));
        if isempty(d)
            fprintf('  [Warnung] Ordner %d enthaelt keine .jpg-Dateien: %s\n', k, ordner);
            continue;
        end

        % --- Dateinamen parsen: date / elapsed / temp ---
        n        = numel(d);
        datumStr = strings(n,1);
        elapsed  = nan(n,1);
        tempStr  = strings(n,1);
        gueltig  = false(n,1);
        for i = 1:n
            [~, name] = fileparts(d(i).name);
            teile = strsplit(name, '_');
            if numel(teile) >= 3 && numel(teile{1}) == 8
                e = str2double(teile{2});
                if ~isnan(e)
                    datumStr(i) = teile{1};
                    elapsed(i)  = e;
                    tempStr(i)  = strjoin(teile(3:end), '_');  % Rest = Temperatur
                    gueltig(i)  = true;
                end
            end
            if ~gueltig(i)
                fprintf('  [Warnung] Unerwarteter Dateiname uebersprungen: %s\n', d(i).name);
                gesamtWarn = gesamtWarn + 1;
            end
        end

        idx = find(gueltig);
        if isempty(idx)
            fprintf('  [Warnung] Ordner %d: keine gueltigen Dateinamen.\n', k);
            continue;
        end

        % --- nach Sekunden-seit-Start sortieren (zeitliche Reihenfolge) ---
        [elapsedSort, ord] = sort(elapsed(idx));
        idx     = idx(ord);
        tempS   = tempStr(idx);

        % --- Basiszeit dieses Ordners bestimmen ---
        if k == 1
            % Startzeit = Dateidatum des ersten (zeitlich fruehesten) Bildes
            startDt   = datetime(d(idx(1)).datenum, 'ConvertFrom', 'datenum');
            basisZeit = startDt - seconds(elapsedSort(1));
            fprintf('  Startzeit (Dateidatum 1. Bild): %s\n', ...
                    char(datetime(startDt,'Format','yyyy-MM-dd HH:mm:ss')));
        else
            % erstes Bild dieses Ordners = letztes Bild davor + Neustartluecke
            basisZeit = letzteZeit + seconds(NEUSTART_LUECKE_S) - seconds(elapsedSort(1));
        end

        % --- Bilder kopieren und umbenennen ---
        for j = 1:numel(idx)
            absZeit = basisZeit + seconds(elapsedSort(j));
            dStr    = char(datetime(absZeit, 'Format', 'yyyyMMdd'));
            tStr    = char(datetime(absZeit, 'Format', 'HHmmss'));
            neuName = sprintf('%s_%s_%s.jpg', dStr, tStr, tempS(j));

            zielPfad = fullfile(zielOrdner, neuName);
            % Namenskollision (gleiche Sekunde) vermeiden: Suffix -b, -c, ...
            suffix = 'b';
            while exist(zielPfad, 'file')
                neuName  = sprintf('%s_%s_%s-%s.jpg', dStr, tStr, tempS(j), suffix);
                zielPfad = fullfile(zielOrdner, neuName);
                suffix   = char(suffix + 1);
                gesamtWarn = gesamtWarn + 1;
            end

            copyfile(fullfile(ordner, d(idx(j)).name), zielPfad);
            gesamtKopie = gesamtKopie + 1;
        end

        letzteZeit = basisZeit + seconds(elapsedSort(end));
        fprintf('  Ordner %d: %d Bilder, %s ... %s\n', k, numel(idx), ...
                char(datetime(basisZeit + seconds(elapsedSort(1)),'Format','HH:mm:ss')), ...
                char(datetime(letzteZeit,'Format','HH:mm:ss')));
    end

    % --- 4) Zusammenfassung ----------------------------------------------
    fprintf('\nFertig. %d Bilder nach %s kopiert', gesamtKopie, zielOrdner);
    if gesamtWarn > 0
        fprintf(' (%d Warnungen/Umbenennungen, siehe oben)', gesamtWarn);
    end
    fprintf('.\n');
end
