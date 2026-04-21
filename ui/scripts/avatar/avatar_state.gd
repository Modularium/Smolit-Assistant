extends RefCounted
## Avatar state constants for the Phase 3.2 MVP.
##
## Plain integer enum; no behavior. The controller maps core events to
## these values and renders them. Kept separate so new states can be
## added later without touching transport or rendering code.

class_name AvatarState

enum State {
	IDLE,
	THINKING,
	TALKING,
	DISCONNECTED,
	ERROR,
}

const DEFAULT: int = State.IDLE


static func name_of(state: int) -> String:
	match state:
		State.IDLE: return "idle"
		State.THINKING: return "thinking"
		State.TALKING: return "talking"
		State.DISCONNECTED: return "disconnected"
		State.ERROR: return "error"
		_: return "unknown"
