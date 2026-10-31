# Voz del locutor

Frases generadas sin conexión con [Kokoro](https://huggingface.co/hexgrad/Kokoro-82M)
(pesos con licencia Apache-2.0) mediante [kokoro-onnx](https://github.com/thewh1teagle/kokoro-onnx).

- `ef_dora/`: voz femenina «Dora».
- `em_alex/`: voz masculina «Alex».

Se elige en Opciones › «Voz de Dora / Voz de Alex». Para regenerarlas, cambiar textos o
pronunciaciones (por ejemplo «Av. Camacho» → «Avenida Camacho»), edita `tools/gen_voice.py`:

    python tools/gen_voice.py <carpeta con kokoro-v1.0.onnx y voices-v1.0.bin> audio/voice
