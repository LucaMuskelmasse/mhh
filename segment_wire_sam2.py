# -*- coding: utf-8 -*-
"""
segment_wire_sam2.py
====================
Segmentiert einen Draht in einem .avi-Video mit dem Segment Anything Model 2
(SAM 2, Meta) und speichert die Masken als PNG-Ordner neben dem Video.

Workflow (Vorverarbeitung fuer kruemung_jinhan.m):
  1. Video per Datei-Dialog auswaehlen (Start im DEFAULT_PATH).
  2. Alle Frames werden in einen temporaeren JPEG-Ordner extrahiert
     (das erwartet der SAM-2-Video-Predictor).
  3. Erster Frame wird angezeigt: Draht anklicken.
       - Linksklick  = Punkt gehoert ZUM Draht (positiv, gruenes +)
       - Rechtsklick = Punkt gehoert NICHT zum Draht (negativ, rotes x)
       - Taste 'u'   = letzten Punkt entfernen
       - Enter       = bestaetigen und Propagation starten
     Nach jedem Klick wird die aktuelle SAM-2-Maske als Overlay angezeigt.
  4. SAM 2 propagiert die Maske automatisch durch ALLE Frames.
  5. Masken werden gespeichert als:
         <videoname>_sam2_masks/frame_00001.png, frame_00002.png, ...
     (uint8, 0/255; 1-basiert -> frame_00001.png entspricht MATLAB read(v,1))
  6. Danach kruemung_jinhan.m in MATLAB ausfuehren (laedt diese PNGs).

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
        cv2.imwrite(
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


def collect_prompts_interactive(predictor, state, first_frame_rgb):
    """Erster Frame anzeigen, Klick-Prompts sammeln, Maske live anzeigen.

    Rueckgabe: (points Nx2 float32, labels N int32) - mindestens 1 positiver Punkt.
    """
    points = []   # [x, y]
    labels = []   # 1 = positiv (Draht), 0 = negativ (Hintergrund)

    fig, ax = plt.subplots(figsize=(12, 8))
    fig.canvas.manager.set_window_title("SAM 2 - Draht anklicken")
    ax.imshow(first_frame_rgb)
    ax.set_title("Linksklick = Draht | Rechtsklick = Hintergrund | "
                 "'u' = rueckgaengig | Enter = fertig")
    ax.set_axis_off()

    h, w = first_frame_rgb.shape[:2]
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
            frame_idx=0,
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

    video_path = select_video()
    vid_dir = os.path.dirname(video_path)
    vid_name = os.path.splitext(os.path.basename(video_path))[0]
    out_dir = os.path.join(vid_dir, f"{vid_name}_sam2_masks")

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
        print("Extrahiere Frames ...")
        num_frames = extract_frames(video_path, frames_dir)

        print("Lade SAM-2-Modell ...")
        predictor = build_sam2_video_predictor(MODEL_CFGS[model_size], ckpt_path, device=device)
        state = predictor.init_state(video_path=frames_dir)

        # Erster Frame fuer die Klick-Ansicht (BGR -> RGB)
        first_bgr = cv2.imread(os.path.join(frames_dir, "00000.jpg"))
        first_rgb = cv2.cvtColor(first_bgr, cv2.COLOR_BGR2RGB)

        print("Bitte Draht im Fenster anklicken (Enter = fertig) ...")
        points, point_labels = collect_prompts_interactive(predictor, state, first_rgb)

        # Prompts final setzen (Zustand nach interaktiver Phase ist bereits korrekt,
        # zur Sicherheit einmal sauber neu setzen)
        predictor.reset_state(state)
        predictor.add_new_points_or_box(
            inference_state=state, frame_idx=0, obj_id=1,
            points=points, labels=point_labels,
        )

        # --- Propagation durch das ganze Video + Masken speichern ---
        os.makedirs(out_dir, exist_ok=True)
        print(f"Propagiere Maske durch {num_frames} Frames ...")
        n_saved = 0
        for frame_idx, obj_ids, mask_logits in predictor.propagate_in_video(state):
            mask = (mask_logits[0] > 0.0).squeeze().cpu().numpy().astype(np.uint8) * 255
            # 1-basiert speichern: frame_00001.png = MATLAB read(v, 1)
            cv2.imwrite(os.path.join(out_dir, f"frame_{frame_idx + 1:05d}.png"), mask)
            n_saved += 1
            if n_saved % 100 == 0:
                print(f"  {n_saved}/{num_frames} Masken gespeichert ...")

        print(f"\nFertig: {n_saved} Masken gespeichert in\n  {out_dir}")
        if n_saved != num_frames:
            print(f"WARNUNG: {num_frames} Frames, aber {n_saved} Masken!")
        print("Jetzt kruemung_jinhan.m in MATLAB ausfuehren und dieses Video waehlen.")
    finally:
        shutil.rmtree(frames_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
