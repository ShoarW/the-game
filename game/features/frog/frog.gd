extends Node3D
## A small frog that idles in the room, hopping in place on a loop. Purely decorative:
## the hop is deterministic and runs locally on every peer, so it needs no server
## authority or MultiplayerSynchronizer.

const HOP_HEIGHT := 0.35  # meters, peak height of a hop
const HOP_PERIOD := 1.4  # seconds per hop cycle

var _base_y := 0.0
var _time := 0.0


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	_time = wrapf(_time + delta, 0.0, HOP_PERIOD)
	position.y = _base_y + hop_height(_time)


## Pure step, kept free of scene access so the arc math is unit-testable. The frog
## touches down at the start and end of every period and peaks at the midpoint.
static func hop_height(time: float) -> float:
	return HOP_HEIGHT * absf(sin(PI * time / HOP_PERIOD))
