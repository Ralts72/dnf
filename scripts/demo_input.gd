extends RefCounted


static func ensure_bindings() -> void:
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"run": [KEY_SHIFT], "attack": [KEY_X], "skill_preview": [KEY_Q], "reset": [KEY_R],
		"jump": [KEY_SPACE], "ghost_slash": [KEY_Z], "upper_slash": [KEY_V], "hp_potion": [KEY_H], "guard": [KEY_C]
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: int in bindings[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key as Key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)
