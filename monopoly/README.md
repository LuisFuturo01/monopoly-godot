# Magnates — juego de propiedades (Godot 4.7)

Juego de mesa de compra-venta de propiedades con temática de La Paz / El Alto:
tablero, cartas (Destino / Cabildo), fichas (llama, charango, cabina, bombín,
ekeko, zampoña, cóndor, trompo) y nombres propios. PC y móvil, 2D y 3D,
contra la IA, pasar y jugar, y red local Wi-Fi / Bluetooth sin servidores.

## Decisión de arquitectura

La versión anterior (ahora en `legacy/`, ignorada por Godot) mezclaba en un solo
`GameManager.gd` de 1460 líneas la cámara, la UI, las animaciones y las reglas, y
los datos de casilla guardaban referencias a nodos visuales. Eso impide red
autoritativa, IA y una segunda vista, así que se rehízo desde cero. Solo se
reutiliza el asset `ciudad/city.glb` (ciudad en miniatura del centro 3D).

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

### Fases de la FSM

`pre_roll → (resolving) → await_buy | auction | debt → post_roll → pre_roll (siguiente)`
y `game_over`. Los intercambios quedan pendientes en `pre_roll`/`post_roll` y bloquean
tirar/terminar hasta que el destinatario responde.

## Reglas implementadas

- Dobles con tirada extra; tres dobles → Retén sin cobrar sueldo.
- Retén: pagar multa, salvoconducto o intentar dobles; al tercer fallo paga y mueve.
- 8 grupos de color, 4 teleféricos, 2 servicios (Luz y Agua). Alquiler doble con
  grupo completo sin edificar.
- Rechazar una compra abre una subasta por turnos entre todos los jugadores activos.
- Intercambio de dinero, propiedades y salvoconductos antes o después de tirar.
- Construcción pareja, suministro limitado (32 casas / 12 hoteles), hotel = 4 casas
  (3 en modo rápido), venta pareja a mitad de precio.
- Hipoteca al 50 %, levantar al 55 %. Patrimonio neto y valor de liquidación.
- Deudas encadenadas: si no alcanza el efectivo, fase `debt` para hipotecar/vender;
  quiebra transfiere todo al acreedor o devuelve las propiedades al banco.
- Mazos barajados con: dinero, movimientos, teleférico/servicio más cercano,
  reparaciones por casa/hotel, pagar/cobrar a cada jugador, salvoconducto.
- Modo rápido: fin en la primera quiebra (gana el mayor patrimonio), hotel con 3 casas,
  dado turbo. Límite de rondas opcional.
- Dado turbo (diseño propio): caras 1, 2, 3 suman; » salta a la siguiente propiedad
  libre tras resolver la caída; $ da un bono de $50.
- Reglas de la casa: bote en el Mirador, $400 al caer justo en la Salida, sin alquiler
  desde el Retén.

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
`--page=profile|setup|wifi`, `--hud-test=manager|trade|auction|space`, `--speed=<x>`.

## Limitaciones conocidas

- Bluetooth: el plugin Kotlin no se ha compilado ni probado en un dispositivo. iOS no
  expone RFCOMM a apps sin MFi, así que allí solo hay Wi-Fi.
- Descubrimiento solo por broadcast UDP (sin mDNS). Si el anfitrión sale, la partida
  termina (no hay migración de anfitrión).
- En quiebra contra el banco las propiedades vuelven libres (no se subastan) y las
  propiedades hipotecadas se transfieren sin el 10 % de interés.
- Las vistas aún no tienen modelos importados para fichas ni edificios: todo es
  procedural (primitivas 3D y glifos 2D).
