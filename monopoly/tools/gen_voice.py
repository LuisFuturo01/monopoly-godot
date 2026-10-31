# -*- coding: utf-8 -*-
"""Genera las frases del locutor con Kokoro (kokoro-onnx, pesos Apache-2.0), sin conexión.

Uso:
    python tools/gen_voice.py <dir_modelo> <dir_salida> [voz ...]
<dir_modelo> contiene kokoro-v1.0.onnx y voices-v1.0.bin (github.com/thewh1teagle/kokoro-onnx).
Voces en español: ef_dora (mujer), em_alex y em_santa (hombre). Por defecto: ef_dora em_alex.

Frases cortas para que la voz vaya al ritmo del juego. Se arman uniendo dos audios:
  n_<nombre>.ogg  el sujeto («Camilo,»): nombres comunes, los de la IA y las fichas
  a_<accion>.ogg  lo que hace («¡avanza siete!»)
y algunas frases sueltas (g_*.ogg), como «¡Dobles!» o «¡Empieza la subasta de El Prado!».
Si agregas un nombre a NAMES, el juego lo usa solo (busca n_<nombre_normalizado>.ogg).
"""
import json, os, re, sys, unicodedata
import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

model_dir, out_dir = sys.argv[1], sys.argv[2]
voices = sys.argv[3:] or ["ef_dora", "em_alex"]
here = os.path.dirname(os.path.abspath(__file__))
board = json.load(open(os.path.join(here, "..", "data", "board_lapaz.json"), encoding="utf-8"))

SPOKEN = {"Av. Camacho": "Avenida Camacho", "DELAPAZ": "De La Paz", "EPSAS": "Epsas"}
NUM = ["cero", "una", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "once", "doce",
       "trece", "catorce", "quince", "dieciséis", "diecisiete", "dieciocho", "diecinueve", "veinte"]
# Nombres comunes en Bolivia y Latinoamérica + los de la IA. El juego compara sin tildes ni mayúsculas.
NAMES = """Camilo Luis Lucho Luchito Juan Jose Carlos Jorge Miguel Pedro Pablo Diego Daniel David Mario Marco Marcos
Andres Fernando Ricardo Roberto Rodrigo Sergio Javier Alejandro Alex Gabriel Rafael Raul Oscar Eduardo Hugo Victor
Franz Freddy Grover Wilson Wilmer Edwin Erick Kevin Brayan Bryan Jhon Jhonny Cristian Christian Sebastian Mateo
Santiago Nicolas Martin Tomas Emilio Ivan Ruben Hector Alvaro Gonzalo Gustavo Fabricio Joel Abel Simon Samuel
Antonio Manuel Francisco Ramiro Rolando Reynaldo Remberto Fortunato Ariel Mauricio Alberto Gerardo Esteban
Maria Ana Lucia Sofia Valeria Camila Daniela Gabriela Fernanda Carla Paola Andrea Alejandra Patricia Rosa
Carmen Elena Laura Sandra Monica Veronica Silvia Claudia Jimena Ximena Natalia Paula Mariana Isabel Teresa
Beatriz Gloria Marcela Lorena Roxana Wendy Jhoselin Mayra Nayeli Fabiola Lourdes Remedios Pochi Rocio Cecilia
Julia Martha Noemi Ruth Sara Tatiana Vanessa Yesenia Zulema Karen Diana Adriana Brenda Karina Liliana Alicia
Abuela Abuelo Mama Papa Tia Tio Jugador""".split()
AI_NAMES = ["Doña Remedios", "Don Fortunato", "La Chola Rica", "El Ingeniero", "Tía Pochi", "Compadre Wilmer"]
TOKENS = {"llama": "La llama", "charango": "El charango", "cabina": "La cabina", "bombin": "El bombín",
          "ekeko": "El ekeko", "zampona": "La zampoña", "condor": "El cóndor", "trompo": "El trompo"}


def norm(s):
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def place(i):
    sp = board["spaces"][i]
    name = SPOKEN.get(sp["name"], sp["name"])
    return {"go": "la Salida", "free": "el Mirador", "jail": "el Retén"}.get(sp["type"], name)


PH = {}
for n in NAMES + AI_NAMES:
    PH["n_" + norm(n)] = n + ","
for k, n in TOKENS.items():
    PH["n_ficha_" + k] = n + ","
for n in range(1, 21):
    PH["a_adv_%d" % n] = "¡avanza %s!" % NUM[n]
for n in range(1, 6):
    PH["a_back_%d" % n] = "¡retrocede %s!" % ("uno" if n == 1 else NUM[n])
PH.update({
    "a_tax": "paga impuestos.",
    "a_rent": "paga alquiler.",
    "a_jail": "¡al Retén!",
    "a_jail_free": "¡sale libre!",
    "a_win_auction": "¡gana la subasta!",
    "a_bankrupt": "¡quebró!",
    "a_wins": "¡gana la partida!",
    "a_pot": "¡se lleva el bote!",
    "a_destino": "saca Destino.",
    "a_cabildo": "saca Cabildo.",
    "a_debt": "¡no le alcanza!",
    "g_doubles": "¡Dobles!",
    "g_three_doubles": "¡Tres dobles, al Retén!",
    "g_no_buyer": "Sin comprador.",
    "g_trade_offer": "¡Propuesta de trato!",
    "g_trade_ok": "¡Trato hecho!",
    "g_trade_no": "Trato rechazado.",
    "g_your_turn": "¡Te toca!",
    "g_last_round": "¡Última ronda!",
})
for i, sp in enumerate(board["spaces"]):
    if sp["type"] in ("street", "transit", "utility", "go", "free"):
        PH["a_goto_%d" % i] = "¡a %s!" % place(i)
    if sp["type"] not in ("street", "transit", "utility"):
        continue
    p = place(i)
    PH["a_buy_%d" % i] = "¡compra %s!" % p
    PH["a_mort_%d" % i] = "hipoteca %s." % p
    PH["a_unmort_%d" % i] = "recupera %s." % p
    PH["g_auction_%d" % i] = "¡Subasta de %s!" % p
    if sp["type"] == "street":
        PH["a_house_%d" % i] = "¡casa en %s!" % p
        PH["a_hotel_%d" % i] = "¡hotel en %s!" % p
        PH["a_sell_%d" % i] = "vende casa en %s." % p


def polish(x, sr):
    """Voz más presente: recorta silencios, realza agudos (menos «apagada»),
    comprime un poco y normaliza a -1 dBFS."""
    loud = np.where(np.abs(x) > 0.01)[0]
    if loud.size:
        pad = int(sr * 0.03)
        x = x[max(0, loud[0] - pad):min(len(x), loud[-1] + pad)]
    lp = np.convolve(x, np.ones(5) / 5.0, mode="same")
    x = x + 0.45 * (x - lp)                       # realce de presencia
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak
    x = np.sign(x) * np.power(np.abs(x), 0.8)     # compresión suave
    return (x / (np.max(np.abs(x)) or 1.0) * 0.89).astype(np.float32)


k = Kokoro(os.path.join(model_dir, "kokoro-v1.0.onnx"), os.path.join(model_dir, "voices-v1.0.bin"))
for voice in voices:
    dest = os.path.join(out_dir, voice)
    os.makedirs(dest, exist_ok=True)
    for f in os.listdir(dest):
        if f.endswith(".ogg") or f.endswith(".ogg.import"):
            os.remove(os.path.join(dest, f))
    for key, text in PH.items():
        speed = 1.2 if "!" in text else 1.12
        samples, sr = k.create(text, voice=voice, speed=speed, lang="es")
        sf.write(os.path.join(dest, key + ".ogg"), polish(samples, sr), sr, format="OGG", subtype="VORBIS")
    print(voice, len(PH), "frases", flush=True)
