extends RefCounted
## Presence-Mode-Konstanten für das Phase-3.3 Presence MVP.
##
## Orthogonal zum Avatar-State (siehe `avatar_state.gd`). Presence
## beschreibt, **wie viel UI** Smolit gerade zeigt — Docked (ruhig),
## Expanded (aktiv nutzbar), Action (laufende Aktion sichtbar),
## Disconnected (Core nicht erreichbar).

class_name PresenceState

enum Mode {
	DOCKED,
	EXPANDED,
	ACTION,
	DISCONNECTED,
}

const DEFAULT_BASE: int = Mode.DOCKED


static func name_of(mode: int) -> String:
	match mode:
		Mode.DOCKED: return "docked"
		Mode.EXPANDED: return "expanded"
		Mode.ACTION: return "action"
		Mode.DISCONNECTED: return "disconnected"
		_: return "unknown"


## Base modes are the ones a user can toggle between. Action and
## Disconnected are transient/system-driven and never become the base.
static func is_base_mode(mode: int) -> bool:
	return mode == Mode.DOCKED or mode == Mode.EXPANDED
