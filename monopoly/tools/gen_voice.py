# -*- coding: utf-8 -*-
"""Genera las frases del locutor con Kokoro (kokoro-onnx, pesos Apache-2.0), sin conexión.

Uso:
    python tools/gen_voice.py <dir_modelo> <dir_salida> [voz ...]
<dir_modelo> contiene kokoro-v1.0.onnx y voices-v1.0.bin (github.com/thewh1teagle/kokoro-onnx).
Voces en español: ef_dora (mujer), em_alex y em_santa (hombre). Por defecto: ef_dora em_alex.
Crea <dir_salida>/<voz>/<clave>.ogg. Los textos van sin «¡» ni «¿»: la voz los leía como un
ruido al inicio de cada frase.
"""
import json, os, sys
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

model_dir, out_dir = sys.argv[1], sys.argv[2]
voices = sys.argv[3:] or ["ef_dora", "em_alex"]
here = os.path.dirname(os.path.abspath(__file__))
board = json.load(open(os.path.join(here, "..", "data", "board_lapaz.json"), encoding="utf-8"))

# Cómo se pronuncia cada nombre (abreviaturas y siglas).
SPOKEN = {"Av. Camacho": "Avenida Camacho", "DELAPAZ": "De La Paz", "EPSAS": "Epsas"}
NUM = ["", "", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce"]

PHRASES = {"dice_%d" % n: "Dado %s." % NUM[n] for n in range(2, 13)}
PHRASES.update({
    "doubles": "Dobles. Tira otra vez.",
    "three_doubles": "Tres dobles. Directo al Retén.",
    "auction_sold": "Vendido.",
    "no_buyer": "Nadie lo compró.",
    "tax": "Toca pagar impuesto.",
    "salary": "Cobras tu sueldo.",
    "destino": "Carta de Destino.",
    "cabildo": "Carta de Cabildo.",
    "jail": "Al Retén.",
    "jail_free": "Sales del Retén.",
    "trade_offer": "Tienes una propuesta.",
    "trade_ok": "Trato aceptado.",
    "trade_no": "Trato rechazado.",
    "bankrupt": "Quiebra.",
    "win": "Tenemos un ganador.",
    "your_turn": "Tu turno.",
    "last_round": "Última ronda.",
    "pot": "Te llevas el bote.",
    "debt": "Te falta dinero. Hipoteca o vende.",
})
# Frases con el nombre de cada terreno
for i, sp in enumerate(board["spaces"]):
    if sp["type"] not in ("street", "transit", "utility"):
        continue
    name = SPOKEN.get(sp["name"], sp["name"])
    PHRASES["bought_%d" % i] = "%s, comprado." % name
    PHRASES["auction_%d" % i] = "Inicia la subasta de %s." % name
    PHRASES["mortgaged_%d" % i] = "%s, hipotecado." % name
    PHRASES["unmortgaged_%d" % i] = "%s, hipoteca levantada." % name
    PHRASES["rent_%d" % i] = "Alquiler en %s." % name
    if sp["type"] == "street":
        PHRASES["house_%d" % i] = "Casa nueva en %s." % name
        PHRASES["hotel_%d" % i] = "Hotel en %s." % name
        PHRASES["sold_%d" % i] = "Casa vendida en %s." % name


def trim(samples, sr):
    """Quita silencios al inicio y al final para que la voz llegue a tiempo."""
    loud = np.where(np.abs(samples) > 0.01)[0]
    if loud.size == 0:
        return samples
    pad = int(sr * 0.05)
    return samples[max(0, loud[0] - pad):min(len(samples), loud[-1] + pad)]


k = Kokoro(os.path.join(model_dir, "kokoro-v1.0.onnx"), os.path.join(model_dir, "voices-v1.0.bin"))
for voice in voices:
    dest = os.path.join(out_dir, voice)
    os.makedirs(dest, exist_ok=True)
    for key, text in PHRASES.items():
        samples, sr = k.create(text, voice=voice, speed=1.05, lang="es")
        sf.write(os.path.join(dest, key + ".ogg"), trim(samples, sr), sr, format="OGG", subtype="VORBIS")
    print(voice, len(PHRASES), "frases")
