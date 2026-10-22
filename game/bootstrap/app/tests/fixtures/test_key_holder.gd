extends Node3D

# Stand-in for the player and for doors: carries the emergency-key fields the mission layout reads.
var holding := false
var requires_emergency_key := false
var permanently_locked := false


func has_emergency_key() -> bool:
	return holding
