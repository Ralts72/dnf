extends RefCounted
## Retained source walk strips plus a short adapted approach to the visible gate.
## Coordinates are the shared source-ground pixels used by the comparison scene.

const DOOR_MIN:=Vector2(44,216)
const DOOR_MAX:=Vector2(112,245)

static func constrain(previous: Vector2, requested: Vector2) -> Vector2:
	var target := Vector2(clampf(requested.x,36.0,852.0),clampf(requested.y,DOOR_MIN.y,345.0))
	if target.y<DOOR_MAX.y and (target.x<DOOR_MIN.x or target.x>DOOR_MAX.x):
		# Stay on the corridor's side while approaching its mouth; crossing the
		# lower edge reopens the existing street without a vertical snap.
		if previous.y<DOOR_MAX.y:
			target.x=clampf(target.x,DOOR_MIN.x,DOOR_MAX.x)
		else:
			target.y=DOOR_MAX.y
	if target.x>378.0 and target.y<285.0:
		# Slide along the inside corner; do not snap the player down 40 pixels.
		if previous.y<285.0:
			target.x=378.0
		else:
			target.y=285.0
	return target
