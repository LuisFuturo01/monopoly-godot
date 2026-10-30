# Luchopolis — juego de propiedades (Godot 4.7)

Juego de mesa de compra-venta de propiedades con temática de La Paz / El Alto:
tablero, cartas (Destino / Cabildo), fichas (llama, charango, cabina, bombín,
ekeko, zampoña, cóndor, trompo) y nombres propios. PC y móvil, 2D y 3D,
contra la IA, pasar y jugar, y red local Wi-Fi / Bluetooth sin servidores.

## Decisión de arquitectura

La versión anterior (ahora en `legacy/`, ignorada por Godot) mezclaba en un solo
`GameManager.gd` de 1460 líneas la cámara, la UI, las animaciones y las reglas, y
los datos de casilla guardaban referencias a nodos visuales. Eso impide red
autoritativa, IA y una segunda vista, así que se rehízo desde cero. La ciudad del
centro es procedural (avenidas con aceras y pasos de cebra, torres de vidrio, casas,
parque con fuente, faroles, nevados, teleférico y autos animados); no se usan modelos
descargados. Cada casilla tiene un cartel que gira hacia la cámara con una foto real
del lugar (Wikimedia Commons, licencias libres; créditos en `data/places/CREDITS.md`).
La moneda del juego es el boliviano (Bs).

```
core/       Reglas puras (RefCounted, sin nodos). Testeables en headless.
  board.gd          Tablero cargado desde data/board_lapaz.json
  rules_config.gd   Clásico, rápido, dado turbo, reglas de la casa
  game_engine.gd    FSM: apply(cmd) -> {ok, error, events}; estado = Dictionary serializable
  ai_brain.gd       IA fácil / media / difícil
data/       Tablero, precios, alquileres y mazos (JSON editable)
game/       GameController (enruta comandos: local, IA o red), EventPlayer (línea
            de tiempo de animaciones), GameAudio, Profile (autoload)
net/        NetworkAdapter (abstracción de transporte), EnetAdapter (Wi-Fi),
            BluetoothAdapter + BluetoothMultiplayerPeer, LanDiscovery (UDP), NetSession (autoload "Net")
views/      BoardView2D y BoardView3D (solo leen estado y eventos), BoardLayout, TokenArt
ui/         MainMenu, Hud, UiKit (tema)
audio/      Sfx (autoload): efectos sintetizados + música lo-fi con AudioStreamGenerator
native/     Plugin Android Bluetooth RFCOMM (Kotlin)
addons/     Plugin de exportación que empaqueta el .aar Bluetooth
tests/      Pruebas del núcleo
```

Flujo: la UI/IA/red producen **comandos** → `GameEngine.apply()` valida y muta el
estado → devuelve **eventos** → `EventPlayer` los reproduce en secuencia → vistas
2D/3D, HUD y audio reaccionan. El motor nunca conoce la presentación.

El motor aplica cada comando al instante, pero la pantalla no debe adelantarse:
`EventPlayer.shown_pos` / `shown_cash` avanzan con cada evento reproducido, y las
vistas y el HUD dibujan esos valores. Así la ficha recorre las casillas desde su origen
y el dinero cambia cuando la animación llega, no antes.

### Fases de la FSM

`pre_roll → (resolving) → await_buy | auction | debt → post_roll → pre_roll (siguiente)`
y `game_over`. Los intercambios quedan pendientes en `pre_roll`/`post_roll` y bloquean
tirar/terminar hasta que el destinatario responde.

## Reglas implementadas

- Dobles con tirada extra; tres dobles en el mismo turno → Retén sin cobrar sueldo.
- Retén: "Pagar Bs 50 y tirar", "Usar salvoconducto y tirar" o "Intentar dobles"; si no
  salen dobles pierdes el turno, y al tercer intento fallido pagas la multa y mueves.
- La partida solo termina por quiebra (o por el límite de rondas si se elige).
- 8 grupos de color, 4 teleféricos, 2 servicios (Luz y Agua). Alquiler doble con
  grupo completo sin edificar.
- Rechazar una compra abre una subasta por turnos entre todos los jugadores activos.
- Intercambio de cualquier combinación de dinero, propiedades y salvoconductos antes o
  después de tirar. La IA ofrece dinero o canjes de terreno por terreno (+ diferencia en
  dinero) cuando a ambos les completa un grupo.
- Construcción pareja, suministro limitado (32 casas / 12 hoteles), hotel = 4 casas
  (3 en modo rápido), venta pareja a mitad de precio.
- Hipoteca al 50 %, levantar al 55 %. Quien recibe una propiedad hipotecada (por
  intercambio o quiebra) paga al banco el 10 % de interés. Patrimonio neto y valor
  de liquidación.
- Deudas encadenadas: si no alcanza el efectivo, fase `debt` para hipotecar/vender;
  quiebra transfiere todo al acreedor; si el acreedor es el banco, éste subasta una
  a una las propiedades del jugador quebrado.
- Mazos barajados con: dinero, movimientos, teleférico/servicio más cercano,
  reparaciones por casa/hotel, pagar/cobrar a cada jugador, salvoconducto.
- Modo rápido: fin en la primera quiebra (gana el mayor patrimonio), hotel con 3 casas,
  dado turbo. Límite de rondas opcional.
- Dado turbo (diseño propio): caras 1, 2, 3 suman; » salta a la siguiente propiedad
  libre tras resolver la caída; $ da un bono de $50.
- Reglas de la casa: bote en el Mirador, $400 al caer justo en la Salida, sin alquiler
  desde el Retén.

### Comparación con el reglamento clásico

Revisado contra el reglamento clásico (alquiler doble con grupo completo, hotel solo con
4 casas en todo el grupo, venta pareja a mitad de precio, hipoteca + 10 %, quiebra y
subasta del banco, Mirador sin premio, sueldo al pasar o caer en la Salida, alquiler
cobrable desde el Retén). Ajustes para cumplirlo:

- La primera puja de una subasta puede ser de cualquier monto (desde Bs 1); las
  siguientes suben de a Bs 10 para que las subastas no se eternicen.
- Quien recibe una propiedad hipotecada paga el 10 % de interés; si la levanta en ese
  mismo turno solo paga el valor de hipoteca (total: valor + 10 %). Si espera, levantarla
  vuelve a costar valor + 10 %.

Diferencias que quedan, propias de la versión digital:

- El alquiler se cobra automáticamente (no hay que "pedirlo" antes de la siguiente tirada).
- Solo se construye en el propio turno (el reglamento también permite entre turnos ajenos).
- Si el banco se queda sin casas u hoteles, simplemente no se puede construir; no se
  subastan los edificios escasos.

## Perfil sin autenticación

Cada dispositivo genera un UUID local (`user://profile.cfg`) con nombre, apodo, ficha
y color. En red, el UUID identifica el asiento: al reconectar se recupera.

## Red local

- **Wi-Fi**: ENet cliente-servidor autoritativo. El anfitrión ejecuta el motor y tira
  los dados; los clientes envían comandos (`_rpc_command`) y reciben estado + eventos
  (`_rpc_sync`, `@rpc("authority", "call_remote", "reliable")`). Descubrimiento por
  broadcast UDP en el puerto 47011 (juego en 47010).
- **Desconexión**: el asiento pasa a la IA (nivel medio) hasta que el jugador vuelve
  con el mismo UUID y recibe el estado completo.
- **Bluetooth**: `BluetoothMultiplayerPeer` implementa `MultiplayerPeerExtension`
  sobre sockets RFCOMM del plugin nativo, así que las mismas RPC funcionan sin cambios.
  Para compilarlo: crear un módulo Android con `native/android_bluetooth`, ejecutar
  `assembleRelease` y copiar el `.aar` a
  `addons/magnates_bluetooth/bin/magnates-bluetooth-release.aar`; exportar con
  Gradle build activado.

## Ejecutar y probar

```bash
GODOT=/ruta/a/Godot_v4.7.2-stable_win64_console.exe
$GODOT --headless --path . --script res://tests/run_tests.gd   # 81 comprobaciones + 60 partidas IA
$GODOT --path . -- --demo --view=3d                             # partida de 4 IA
$GODOT --headless --path . -- --net-host --time=20 &            # prueba de red: anfitrión
$GODOT --headless --path . -- --net-join=127.0.0.1 --drop=8     # cliente que se cae a los 8 s
```

Otros argumentos de depuración: `--shot=<png> --time=<s>` (captura y salir),
`--page=profile|setup|rules|modes|wifi`, `--hud-test=manager|trade|auction|space|buy|build|victory`,
`--speed=<x>`, `--think=<s>` (pausa de la IA) y `--log` (registra Retén, deudas y quiebras).

Opciones (menú y partida): volumen de música y efectos, vista 2D/3D, velocidad de
animación, cámara que sigue a la ficha y registro de jugadas.

## Limitaciones conocidas

- Bluetooth: el plugin Kotlin no se ha compilado ni probado en un dispositivo. iOS no
  expone RFCOMM a apps sin MFi, así que allí solo hay Wi-Fi.
- Descubrimiento solo por broadcast UDP (sin mDNS). Si el anfitrión sale, la partida
  termina (no hay migración de anfitrión).
- Las vistas aún no tienen modelos importados para fichas ni edificios: todo es
  procedural (primitivas 3D y glifos 2D).
