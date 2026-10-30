class_name BoardLayout
extends RefCounted
## Geometría del tablero en "unidades de tablero" compartida por las vistas 2D y 3D.
## Origen arriba-izquierda, X a la derecha, Y hacia abajo (en 3D, Y -> Z).
## La casilla 0 (Salida) está en la esquina inferior derecha y se avanza en sentido horario visual.

const CORNER := 1.6
const CELL := 1.0
const SIZE := CORNER * 2.0 + CELL * 9.0
const BAND := 0.32


static func rect(i: int) -> Rect2:
	var side := i / 10
	var k := i % 10
	var far := SIZE - CORNER
	if k == 0:
		match side:
			0: return Rect2(far, far, CORNER, CORNER)
			1: return Rect2(0, far, CORNER, CORNER)
			2: return Rect2(0, 0, CORNER, CORNER)
			_: return Rect2(far, 0, CORNER, CORNER)
	match side:
		0: return Rect2(far - k * CELL, far, CELL, CORNER)
		1: return Rect2(0, far - k * CELL, CORNER, CELL)
		2: return Rect2(CORNER + (k - 1) * CELL, 0, CELL, CORNER)
		_: return Rect2(far, CORNER + (k - 1) * CELL, CORNER, CELL)


static func side(i: int) -> int:
	return i / 10


static func is_corner(i: int) -> bool:
	return i % 10 == 0


## Dirección hacia el centro del tablero.
static func inward(i: int) -> Vector2:
	match side(i):
		0: return Vector2(0, -1)
		1: return Vector2(1, 0)
		2: return Vector2(0, 1)
	return Vector2(-1, 0)


## Rotación del texto para que se lea desde fuera del tablero.
static func text_angle(i: int) -> float:
	match side(i):
		0: return 0.0
		1: return PI / 2.0
		2: return PI
	return -PI / 2.0


## Franja de color (lado interior de la casilla).
static func band_rect(i: int) -> Rect2:
	var r := rect(i)
	match side(i):
		0: return Rect2(r.position, Vector2(r.size.x, BAND))
		1: return Rect2(Vector2(r.end.x - BAND, r.position.y), Vector2(BAND, r.size.y))
		2: return Rect2(Vector2(r.position.x, r.end.y - BAND), Vector2(r.size.x, BAND))
	return Rect2(r.position, Vector2(BAND, r.size.y))


## Posición de la ficha `slot` (0..5) dentro de la casilla.
static func token_point(i: int, slot: int, count: int) -> Vector2:
	var c := rect(i).get_center() - inward(i) * 0.12
	if count <= 1:
		return c
	var cols := 2 if count <= 4 else 3
	var col := slot % cols
	var row := slot / cols
	var spacing := 0.3
	var offset := Vector2((col - (cols - 1) / 2.0) * spacing, (row - 0.5) * spacing)
	return c + offset.rotated(text_angle(i))


static func space_at(p: Vector2) -> int:
	for i in 40:
		if rect(i).has_point(p):
			return i
	return -1
