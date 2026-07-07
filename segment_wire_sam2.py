# -*- coding: utf-8 -*-
"""
segment_wire_sam2.py
====================
Segmentiert einen Draht in einem .avi-Video ODER einer JPG-Bildsequenz mit dem
Segment Anything Model 2 (SAM 2, Meta) und speichert die Masken als PNG-Ordner
neben dem Video bzw. neben dem Bilderordner.

Workflow (Vorverarbeitung fuer kruemung_jinhan.m [Video] / kruemung.m [Ordner]):
  1. Auswahlfenster: "Video (.avi)" oder "Bilderordner (.jpg)", dann Datei-
     bzw. Ordner-Dialog (Start im DEFAULT_PATH).
  2. Alle Frames werden in einen temporaeren JPEG-Ordner extrahiert bzw.
     kopiert (das erwartet der SAM-2-Video-Predictor). Bei Bilderordnern
     werden die JPGs ALPHABETISCH sortiert - dieselbe Reihenfolge wie MATLABs
     imageDatastore in kruemung.m (frame_00001.png = 1. Bild der Sortierung).
  3. Der PROMPT_FRAME-te Frame wird angezeigt (Default: 10.; die ersten Frames
     sind oft verzerrt und ungeeignet): Draht anklicken.
       - Linksklick  = Punkt gehoert ZUM Draht (positiv, gruenes +)
       - Rechtsklick = Punkt gehoert NICHT zum Draht (negativ, rotes x)
       - Taste 'u'   = letzten Punkt entfernen
       - Enter       = bestaetigen und Propagation starten
     Nach jedem Klick wird die aktuelle SAM-2-Maske als Overlay angezeigt.
  4. SAM 2 propagiert die Maske automatisch in BEIDE Richtungen (vorwaerts und
     rueckwaerts ab dem Prompt-Frame) durch ALLE Frames.
  5. Masken werden gespeichert als:
         <videoname bzw. ordnername>_sam2_masks/frame_00001.png, ...
     (uint8, 0/255; 1-basiert -> frame_00001.png entspricht MATLAB read(v,1)
      bzw. dem ersten Bild des imageDatastore)
  6. Danach kruemung_jinhan.m (Video) bzw. kruemung.m (Bilderordner) in
     MATLAB ausfuehren (laedt diese PNGs).

Einrichtung: siehe README_SAM2.md.
"""

import os
import sys
import shutil
import tempfile
import urllib.request
import tkinter as tk
from tkinter import filedialog

import numpy as np
import cv2
import matplotlib.pyplot as plt

# ============================= Konfiguration =================================
DEFAULT_PATH = r"M:\nascas2\Students\Wöhlken\2026-07-06"   # Startordner Dialog

# Modellgroesse: "auto" | "tiny" | "small" | "base_plus" | "large"
# auto -> GPU (CUDA): base_plus, sonst CPU: tiny (CPU mit large ist sehr langsam)
MODEL_SIZE = "auto"

# 1-basiert: welcher Frame wird zum Anklicken gezeigt/geprompted. Die ersten
# Frames sind oft verzerrt und fuer den Prompt ungeeignet; SAM 2 propagiert
# die Maske von hier aus automatisch in BEIDE Richtungen durch das Video.
PROMPT_FRAME = 10

# Ordner fuer die Modellgewichte (wird bei Bedarf angelegt; Download automatisch)
CHECKPOINT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "checkpoints")

JPEG_QUALITY = 95   # Qualitaet der temporaeren Frame-JPEGs
# ==============================================================================

CHECKPOINT_URLS = {
    "tiny":      "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_tiny.pt",
    "small":     "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_small.pt",
    "base_plus": "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_base_plus.pt",
    "large":     "https://dl.fbaipublicfiles.com/segment_anything_2/092824/sam2.1_hiera_large.pt",
}
MODEL_CFGS = {
    "tiny":      "configs/sam2.1/sam2.1_hiera_t.yaml",
    "small":     "configs/sam2.1/sam2.1_hiera_s.yaml",
    "base_plus": "configs/sam2.1/sam2.1_hiera_b+.yaml",
    "large":     "configs/sam2.1/sam2.1_hiera_l.yaml",
}


def imwrite_unicode(path, img, params=None):
    """Wie cv2.imwrite, aber sicher fuer Windows-Pfade mit Sonderzeichen
    (z.B. Umlauten) und/oder Vorwaerts-Slashes.

    cv2.imwrite() nutzt unter Windows intern eine aeltere fopen()-Route, die
    bei solchen Pfaden bei manchen OpenCV-Builds STILL fehlschlaegt (gibt nur
    False zurueck, wirft KEINE Exception) - Dateien fehlen dann kommentarlos.
    Hier wird stattdessen mit cv2.imencode() ein Byte-Array erzeugt und ueber
    Pythons eingebautes open() geschrieben (Windows-Wide-Char-API, robust).

    Wirft RuntimeError, wenn Encodierung oder Schreiben fehlschlaegt.
    """
    ext = os.path.splitext(path)[1]
    ok, buf = cv2.imencode(ext, img, params or [])
    if not ok:
        raise RuntimeError(f"cv2.imencode fehlgeschlagen fuer: {path}")
    with open(path, "wb") as f:
        f.write(buf.tobytes())
    if not os.path.isfile(path):
        raise RuntimeError(f"Datei wurde nicht geschrieben: {path}")


def select_input_type():
    """Kleines Auswahlfenster mit 2 Buttons (wie die MATLAB-Auswahlfenster):
    'Video (.avi)' oder 'Bilderordner (.jpg)'. Rueckgabe: 'video' | 'folder'.
    """
    choice = {"value": None}

    root = tk.Tk()
    root.title("Eingabe waehlen")
    root.geometry("380x110")
    root.resizable(False, False)
    tk.Label(root, text="Was soll segmentiert werden?",
             font=("Segoe UI", 11, "bold")).pack(pady=8)
    row = tk.Frame(root)
    row.pack()

    def pick(value):
        choice["value"] = value
        root.destroy()

    tk.Button(row, text="Video (.avi)", width=17,
              command=lambda: pick("video")).pack(side="left", padx=8)
    tk.Button(row, text="Bilderordner (.jpg)", width=17,
              command=lambda: pick("folder")).pack(side="left", padx=8)
    root.mainloop()

    if choice["value"] is None:
        sys.exit("Keine Auswahl getroffen - Abbruch.")
    return choice["value"]


def select_video():
    """Datei-Dialog wie uigetfile in MATLAB."""
    root = tk.Tk()
    root.withdraw()
    initial = DEFAULT_PATH if os.path.isdir(DEFAULT_PATH) else os.path.expanduser("~")
    path = filedialog.askopenfilename(
        title="AVI-Video auswaehlen (SAM-2-Segmentierung)",
        initialdir=initial,
        filetypes=[("AVI Video", "*.avi"), ("Alle Dateien", "*.*")],
    )
    root.destroy()
    if not path:
        sys.exit("Kein Video ausgewaehlt - Abbruch.")
    return path


def select_folder():
    """Ordner-Dialog wie uigetdir in MATLAB."""
    root = tk.Tk()
    root.withdraw()
    initial = DEFAULT_PATH if os.path.isdir(DEFAULT_PATH) else os.path.expanduser("~")
    path = filedialog.askdirectory(
        title="Bilderordner (.jpg) auswaehlen (SAM-2-Segmentierung)",
        initialdir=initial,
    )
    root.destroy()
    if not path:
        sys.exit("Kein Ordner ausgewaehlt - Abbruch.")
    return path


def extract_frames(video_path, frames_dir):
    """Alle Frames als JPEGs (00000.jpg, ...) extrahieren; SAM 2 erwartet das."""
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        sys.exit(f"Video konnte nicht geoeffnet werden: {video_path}")
    idx = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        imwrite_unicode(
            os.path.join(frames_dir, f"{idx:05d}.jpg"),
            frame,
            [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY],
        )
        idx += 1
        if idx % 200 == 0:
            print(f"  Frames extrahiert: {idx} ...")
    cap.release()
    if idx == 0:
        sys.exit("Keine Frames im Video gefunden - Abbruch.")
    print(f"  Frames insgesamt: {idx}")
    return idx


def copy_jpg_frames(src_dir, frames_dir):
    """JPGs eines Bilderordners ALPHABETISCH sortiert als 00000.jpg, ... in den
    Temp-Ordner kopieren (SAM 2 braucht rein numerische Dateinamen).

    Die alphabetische Sortierung entspricht der Reihenfolge von MATLABs
    imageDatastore in kruemung.m -> frame_00001.png passt zum 1. Bild dort.
    """
    jpgs = sorted(f for f in os.listdir(src_dir)
                  if f.lower().endswith((".jpg", ".jpeg")))
    if not jpgs:
        sys.exit(f"Keine .jpg-Dateien gefunden in: {src_dir}")
    for idx, name in enumerate(jpgs):
        shutil.copy(os.path.join(src_dir, name),
                    os.path.join(frames_dir, f"{idx:05d}.jpg"))
        if (idx + 1) % 200 == 0:
            print(f"  Bilder kopiert: {idx + 1} ...")
    print(f"  Bilder insgesamt: {len(jpgs)}")
    return len(jpgs)


def download_checkpoint(model_size):
    """Checkpoint bei Bedarf von Metas offiziellen URLs herunterladen."""
    url = CHECKPOINT_URLS[model_size]
    os.makedirs(CHECKPOINT_DIR, exist_ok=True)
    ckpt_path = os.path.join(CHECKPOINT_DIR, os.path.basename(url))
    if os.path.isfile(ckpt_path):
        return ckpt_path
    print(f"Lade SAM-2-Checkpoint ({model_size}) herunter:\n  {url}")

    def progress(blocks, block_size, total):
        done = blocks * block_size
        if total > 0:
            pct = min(100.0, done * 100.0 / total)
            print(f"\r  {pct:5.1f} %  ({done/1e6:.0f}/{total/1e6:.0f} MB)", end="")

    tmp_path = ckpt_path + ".part"
    try:
        urllib.request.urlretrieve(url, tmp_path, reporthook=progress)
    except Exception as exc:
        if os.path.isfile(tmp_path):
            os.remove(tmp_path)
        sys.exit(f"\nDownload fehlgeschlagen: {exc}\n"
                 f"Alternativ manuell herunterladen und ablegen als:\n  {ckpt_path}")
    os.replace(tmp_path, ckpt_path)
    print("\n  Download abgeschlossen.")
    return ckpt_path


def collect_prompts_interactive(predictor, state, prompt_idx, prompt_frame_rgb):
    """Prompt-Frame anzeigen, Klick-Prompts sammeln, Maske live anzeigen.

    Rueckgabe: (points Nx2 float32, labels N int32) - mindestens 1 positiver Punkt.
    """
    points = []   # [x, y]
    labels = []   # 1 = positiv (Draht), 0 = negativ (Hintergrund)

    fig, ax = plt.subplots(figsize=(12, 8))
    fig.canvas.manager.set_window_title(f"SAM 2 - Draht anklicken (Frame {prompt_idx + 1})")
    ax.imshow(prompt_frame_rgb)
    ax.set_title(f"Frame {prompt_idx + 1} | Linksklick = Draht | Rechtsklick = Hintergrund | "
                 "'u' = rueckgaengig | Enter = fertig")
    ax.set_axis_off()

    h, w = prompt_frame_rgb.shape[:2]
    overlay = ax.imshow(np.zeros((h, w, 4), dtype=np.float32))  # Masken-Overlay
    pos_plot, = ax.plot([], [], 'g+', markersize=14, markeredgewidth=2)
    neg_plot, = ax.plot([], [], 'rx', markersize=12, markeredgewidth=2)

    def update_mask():
        """SAM 2 mit allen bisherigen Punkten aufrufen und Overlay aktualisieren."""
        if not any(l == 1 for l in labels):
            overlay.set_data(np.zeros((h, w, 4), dtype=np.float32))
            fig.canvas.draw_idle()
            return
        predictor.reset_state(state)
        _, _, mask_logits = predictor.add_new_points_or_box(
            inference_state=state,
            frame_idx=prompt_idx,
            obj_id=1,
            points=np.array(points, dtype=np.float32),
            labels=np.array(labels, dtype=np.int32),
        )
        mask = (mask_logits[0] > 0.0).squeeze().cpu().numpy()
        rgba = np.zeros((h, w, 4), dtype=np.float32)
        rgba[mask] = [0.0, 0.6, 1.0, 0.5]   # halbtransparentes Blau
        overlay.set_data(rgba)
        fig.canvas.draw_idle()

    def redraw_points():
        px = [p[0] for p, l in zip(points, labels) if l == 1]
        py = [p[1] for p, l in zip(points, labels) if l == 1]
        nx = [p[0] for p, l in zip(points, labels) if l == 0]
        ny = [p[1] for p, l in zip(points, labels) if l == 0]
        pos_plot.set_data(px, py)
        neg_plot.set_data(nx, ny)

    def on_click(event):
        if event.inaxes != ax or event.xdata is None:
            return
        if event.button == 1:
            labels.append(1)
        elif event.button == 3:
            labels.append(0)
        else:
            return
        points.append([float(event.xdata), float(event.ydata)])
        redraw_points()
        update_mask()

    def on_key(event):
        if event.key == 'enter':
            plt.close(fig)
        elif event.key == 'u' and points:
            points.pop()
            labels.pop()
            redraw_points()
            update_mask()

    fig.canvas.mpl_connect('button_press_event', on_click)
    fig.canvas.mpl_connect('key_press_event', on_key)
    plt.show()   # blockiert bis Enter / Fenster geschlossen

    if not any(l == 1 for l in labels):
        sys.exit("Kein positiver Klick auf den Draht gesetzt - Abbruch.")
    return np.array(points, dtype=np.float32), np.array(labels, dtype=np.int32)


def main():
    # --- Torch/SAM2 erst hier importieren (schnellere Fehlermeldung ohne Env) ---
    try:
        import torch
        from sam2.build_sam import build_sam2_video_predictor
    except ImportError as exc:
        sys.exit(f"Fehlendes Paket: {exc}\nBitte Einrichtung laut README_SAM2.md durchfuehren.")

    # --- Eingabe waehlen: Video (.avi) oder Bilderordner (.jpg) ---
    input_type = select_input_type()
    if input_type == "video":
        video_path = os.path.normpath(select_video())
        base_dir = os.path.dirname(video_path)
        src_name = os.path.splitext(os.path.basename(video_path))[0]
    else:
        img_dir = os.path.normpath(select_folder())
        base_dir = os.path.dirname(img_dir)
        src_name = os.path.basename(img_dir)
    # Masken landen im Nebenordner <name>_sam2_masks (neben Video bzw. Ordner)
    out_dir = os.path.normpath(os.path.join(base_dir, f"{src_name}_sam2_masks"))

    # --- Device + Modellgroesse ---
    if torch.cuda.is_available():
        device = "cuda"
        model_size = MODEL_SIZE if MODEL_SIZE != "auto" else "base_plus"
        # wie im offiziellen SAM-2-Beispiel: bfloat16-Autocast + TF32 (Ampere+)
        torch.autocast("cuda", dtype=torch.bfloat16).__enter__()
        if torch.cuda.get_device_properties(0).major >= 8:
            torch.backends.cuda.matmul.allow_tf32 = True
            torch.backends.cudnn.allow_tf32 = True
    else:
        device = "cpu"
        model_size = MODEL_SIZE if MODEL_SIZE != "auto" else "tiny"
        print("Hinweis: keine CUDA-GPU gefunden -> CPU-Modus (langsamer).")
    print(f"Device: {device} | Modell: sam2.1_hiera_{model_size}")

    ckpt_path = download_checkpoint(model_size)

    frames_dir = tempfile.mkdtemp(prefix="sam2_frames_")
    try:
        if input_type == "video":
            print("Extrahiere Frames ...")
            num_frames = extract_frames(video_path, frames_dir)
        else:
            print("Kopiere Bilder ...")
            num_frames = copy_jpg_frames(img_dir, frames_dir)
        if num_frames < PROMPT_FRAME:
            sys.exit(f"Video hat nur {num_frames} Frames, PROMPT_FRAME={PROMPT_FRAME} "
                     f"ist nicht erreichbar. PROMPT_FRAME oben im Skript anpassen.")
        prompt_idx = PROMPT_FRAME - 1   # 0-basiert fuer SAM-2-API/Dateinamen

        print("Lade SAM-2-Modell ...")
        predictor = build_sam2_video_predictor(MODEL_CFGS[model_size], ckpt_path, device=device)
        state = predictor.init_state(video_path=frames_dir)

        # Prompt-Frame fuer die Klick-Ansicht (BGR -> RGB)
        prompt_bgr = cv2.imread(os.path.join(frames_dir, f"{prompt_idx:05d}.jpg"))
        prompt_rgb = cv2.cvtColor(prompt_bgr, cv2.COLOR_BGR2RGB)

        print(f"Bitte Draht im Fenster anklicken (Frame {PROMPT_FRAME}, Enter = fertig) ...")
        points, point_labels = collect_prompts_interactive(predictor, state, prompt_idx, prompt_rgb)

        # Prompts final setzen (Zustand nach interaktiver Phase ist bereits korrekt,
        # zur Sicherheit einmal sauber neu setzen)
        predictor.reset_state(state)
        predictor.add_new_points_or_box(
            inference_state=state, frame_idx=prompt_idx, obj_id=1,
            points=points, labels=point_labels,
        )

        # --- Propagation in BEIDE Richtungen ab dem Prompt-Frame + Masken speichern ---
        os.makedirs(out_dir, exist_ok=True)
        print(f"Propagiere Maske durch {num_frames} Frames ...")
        seen = set()
        n_saved = 0

        def save_mask(frame_idx, mask_logits):
            nonlocal n_saved
            if frame_idx in seen:
                return
            seen.add(frame_idx)
            mask = (mask_logits[0] > 0.0).squeeze().cpu().numpy().astype(np.uint8) * 255
            # 1-basiert speichern: frame_00001.png = MATLAB read(v, 1)
            imwrite_unicode(os.path.join(out_dir, f"frame_{frame_idx + 1:05d}.png"), mask)
            n_saved += 1
            if n_saved % 100 == 0:
                print(f"  {n_saved}/{num_frames} Masken gespeichert ...")

        print(f"  vorwaerts ab Frame {PROMPT_FRAME} ...")
        for frame_idx, obj_ids, mask_logits in predictor.propagate_in_video(state):
            save_mask(frame_idx, mask_logits)

        if prompt_idx > 0:
            print(f"  rueckwaerts bis Frame 1 ...")
            for frame_idx, obj_ids, mask_logits in predictor.propagate_in_video(state, reverse=True):
                save_mask(frame_idx, mask_logits)

        # Doppelte Kontrolle: tatsaechlich vorhandene Dateien zaehlen, damit ein
        # zukuenftiges stilles Fehlschlagen nicht erneut unbemerkt bliebe.
        n_on_disk = len([f for f in os.listdir(out_dir) if f.lower().endswith(".png")])
        if n_on_disk != n_saved:
            sys.exit(f"FEHLER: {n_saved} Masken sollten geschrieben sein, "
                      f"aber nur {n_on_disk} PNG-Dateien liegen in\n  {out_dir}")

        print(f"\nFertig: {n_saved} Masken gespeichert in\n  {out_dir}")
        if n_saved != num_frames:
            print(f"WARNUNG: {num_frames} Frames, aber {n_saved} Masken!")
        if input_type == "video":
            print("Jetzt kruemung_jinhan.m in MATLAB ausfuehren und dieses Video waehlen.")
        else:
            print("Jetzt kruemung.m in MATLAB ausfuehren und diesen Bilderordner waehlen.")
    finally:
        shutil.rmtree(frames_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
