# SAM-2-Segmentierung für kruemung_jinhan.m

Die HSV-Farbmaske funktioniert bei den Videos in `2026-07-06` nicht. Stattdessen
segmentiert das **Segment Anything Model 2 (SAM 2, Meta)** den Draht. Der Ablauf
ist zweistufig:

1. **Python**: `segment_wire_sam2.py` segmentiert das Video einmal komplett und
   speichert die Masken als PNGs neben dem Video.
2. **MATLAB**: `kruemung_jinhan.m` lädt diese Masken (statt `createMask`) und
   macht wie gewohnt Skelettierung + Krümmungsberechnung.

---

## Einmalige Einrichtung (Python)

Voraussetzung: **Python ≥ 3.10** (auf Windows: [python.org](https://www.python.org/downloads/),
beim Installieren "Add to PATH" anhaken) und **Git**.

In einer Eingabeaufforderung (cmd/PowerShell):

```bat
:: 1. Virtuelle Umgebung anlegen (einmalig), z.B. im Benutzerordner
python -m venv %USERPROFILE%\sam2env
%USERPROFILE%\sam2env\Scripts\activate

:: 2. PyTorch installieren
::    MIT NVIDIA-GPU (empfohlen, deutlich schneller) - CUDA-Variante:
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
::    ODER OHNE GPU (nur CPU):
::    pip install torch torchvision

:: 3. SAM 2 + Hilfspakete installieren
pip install git+https://github.com/facebookresearch/sam2.git
pip install opencv-python matplotlib numpy pillow
```

> **GPU oder nicht?** Das Skript erkennt das automatisch: mit CUDA-GPU nutzt es
> das Modell `base_plus`, ohne GPU das kleine `tiny`-Modell (funktioniert, ist
> aber pro Video deutlich langsamer). Die Modellgröße kann oben im Skript
> (`MODEL_SIZE`) fest vorgegeben werden.

> **Checkpoint-Download:** Beim ersten Start lädt das Skript die Modellgewichte
> automatisch von Metas offiziellen Servern in den Ordner `checkpoints/` neben
> dem Skript (tiny ≈ 150 MB, base_plus ≈ 320 MB, large ≈ 900 MB). Falls der
> Rechner keinen Internetzugang hat: Datei manuell von der im Skript
> hinterlegten URL laden und in `checkpoints/` legen.

---

## Nutzung (pro Video einmal)

```bat
%USERPROFILE%\sam2env\Scripts\activate
python segment_wire_sam2.py
```

1. Im Datei-Dialog das `.avi` auswählen (startet in
   `M:\nascas2\Students\Wöhlken\2026-07-06`).
2. Es öffnet sich der erste Frame:
   - **Linksklick** = Punkt liegt AUF dem Draht (grünes `+`)
   - **Rechtsklick** = Punkt gehört NICHT zum Draht (rotes `x`, z.B. um
     fälschlich mitsegmentierte Bereiche auszuschließen)
   - **Taste `u`** = letzten Klick rückgängig machen
   - Nach jedem Klick wird die aktuelle Maske blau überlagert angezeigt.
   - **Enter** = bestätigen, Propagation durch das ganze Video startet.
3. Warten, bis "Fertig" erscheint. Ergebnis: Ordner
   `<videoname>_sam2_masks\frame_00001.png, frame_00002.png, ...`
   neben dem Video (weiß = Draht, schwarz = Hintergrund).
4. In MATLAB `kruemung_jinhan.m` ausführen und dasselbe Video wählen.

**Tipp:** Ein paar PNGs aus der Mitte/dem Ende des Ordners kurz ansehen, um zu
prüfen, dass SAM 2 den Draht über das ganze Video sauber verfolgt hat. Falls
nicht: Skript erneut ausführen und zusätzliche positive/negative Klicks setzen.

---

## Fehlermeldungen

- **MATLAB: "Keine SAM-2-Masken gefunden"** → Schritt "Nutzung" oben für dieses
  Video ausführen.
- **MATLAB: "Maskenanzahl passt nicht zur Frameanzahl"** → Python-Skript für das
  Video erneut ausführen (alter/unvollständiger Maskenordner wird überschrieben).
- **Python: "Fehlendes Paket"** → Einrichtung oben durchführen bzw. venv
  aktivieren (`activate`).
