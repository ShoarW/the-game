extends GutTest
## Pure hop math for the frog (features/frog/frog.gd).

const Frog := preload("res://features/frog/frog.gd")


func test_hop_starts_and_ends_at_ground() -> void:
	assert_almost_eq(Frog.hop_height(0.0), 0.0, 0.0001)
	assert_almost_eq(Frog.hop_height(Frog.HOP_PERIOD), 0.0, 0.0001)


func test_hop_peaks_at_midpoint() -> void:
	var mid: float = Frog.HOP_PERIOD / 2.0
	assert_almost_eq(Frog.hop_height(mid), Frog.HOP_HEIGHT, 0.0001)


func test_hop_never_goes_negative_or_above_peak() -> void:
	for i: int in 100:
		var t: float = Frog.HOP_PERIOD * i / 100.0
		assert_between(Frog.hop_height(t), 0.0, Frog.HOP_HEIGHT)
