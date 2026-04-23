extends RefCounted
## Behavioral Expression Layer v1 (PR 15).
##
## Der Expression-Layer liegt **oberhalb** der bestehenden Avatar-State-
## Maschine (`avatar_state.gd`). States sind weiterhin die Wahrheit für
## „was gerade läuft" (idle / thinking / talking / acting / error /
## disconnected). Expressions modulieren diesen Ausdruck nur subtil:
## sie skalieren Puls-Amplitude, Wiggle-Stärke und Tint-Ton — mehr
## nicht. Keine eigene State-Maschine, keine eigenen Wartungskanäle,
## keine Ersatz-Events.
##
## Design-Prinzipien:
##
##   * **Additiv, nicht ersetzend.** Jede Expression ist ein kleiner
##     Multiplikator-/Tint-Patch auf der bestehenden State-Darstellung.
##     Ohne den Layer (oder bei `neutral`) ist das Rendering byte-
##     identisch zum vor-PR-Verhalten.
##   * **Kurz oder klebend.** `hold_seconds > 0` markiert transiente
##     Expressions (z. B. `pleased`, `curious`), die der Controller
##     nach Ablauf wieder auf den State-Default zurückrollt. `0.0`
##     heißt „bleibt, bis eine neue Expression gesetzt wird".
##   * **Template-Respekt.** Der Controller multipliziert die
##     Expression-Faktoren **zusätzlich** zum bestehenden Template-
##     Capability-Multiplier (`avatar_template_capabilities.gd`); eine
##     Figur mit `wiggle = NONE` bleibt auch in `curious` still.
##   * **Kein neues Protokoll.** Die Schicht existiert rein UI-seitig.
##     Kein `emotion`-Feld, kein neues IPC-Event, kein neuer
##     Core-Hook. Die Projektion reagiert auf bestehende EventBus-
##     Signale (`thinking_received`, `response_received`,
##     `heard_received`, `speaking_*_received`, `ipc_*connected`).
##
## Explizit **nicht** Teil dieses Layers:
##
##   * Kein Phonem-/Lip-Sync, kein Audio-Stream, keine Audio-Timeline.
##   * Kein neuer Asset-Import, keine neuen Binärdateien.
##   * Keine Personality-Engine, keine Policy-Kopplung. Der Layer weiß
##     nichts über Approval, Interaction, Provider oder Settings.
##   * Kein Emotion-Input-Kanal (Core sendet keine Emotion und nimmt
##     keine Expressions entgegen).

class_name AvatarExpression

const _StateRef := preload("res://scripts/avatar/avatar_state.gd")


## Ausdrucksmodi. Reihenfolge ist Teil des Kontrakts (Smoketests und
## optionale Dev-Controls lesen `all_kinds()` deterministisch).
enum Kind {
	NEUTRAL,
	FOCUSED,
	CURIOUS,
	SPEAKING,
	PLEASED,
	ERROR_SOFT,
}

const DEFAULT: int = Kind.NEUTRAL


const _NAMES: Dictionary = {
	Kind.NEUTRAL: "neutral",
	Kind.FOCUSED: "focused",
	Kind.CURIOUS: "curious",
	Kind.SPEAKING: "speaking",
	Kind.PLEASED: "pleased",
	Kind.ERROR_SOFT: "error_soft",
}


## Transient-Hold in Sekunden. `0.0` heißt „klebend, bis eine neue
## Expression gesetzt wird". Werte bewusst klein: der Layer ist ein
## Mikro-Cue, keine Animation mit eigenem Tempo.
const _HOLD_SECONDS: Dictionary = {
	Kind.NEUTRAL: 0.0,
	Kind.FOCUSED: 0.0,
	Kind.CURIOUS: 0.9,
	Kind.SPEAKING: 0.0,
	Kind.PLEASED: 0.6,
	Kind.ERROR_SOFT: 0.9,
}


## Modulation pro Ausdruck:
##
##   * `pulse`:   Faktor auf das Delta des State-Pulses zu `Vector2.ONE`.
##                1.0 = unverändert, <1.0 = ruhiger, >1.0 = deutlicher.
##   * `wiggle`:  Faktor auf den Wiggle-Winkel (0.0 = Wiggle stumm).
##   * `tint`:    `Color`, die multiplikativ auf den State-Tint wirkt.
##                `Color(1,1,1,1)` = neutral (kein Effekt).
const _MODULATION: Dictionary = {
	Kind.NEUTRAL: {
		"pulse": 1.0,
		"wiggle": 1.0,
		"tint": Color(1.0, 1.0, 1.0, 1.0),
	},
	Kind.FOCUSED: {
		"pulse": 0.85,
		"wiggle": 0.3,
		"tint": Color(0.95, 0.97, 1.0, 1.0),
	},
	Kind.CURIOUS: {
		"pulse": 1.1,
		"wiggle": 1.7,
		"tint": Color(1.0, 1.02, 0.98, 1.0),
	},
	Kind.SPEAKING: {
		"pulse": 1.2,
		"wiggle": 0.5,
		"tint": Color(1.02, 1.0, 0.98, 1.0),
	},
	Kind.PLEASED: {
		"pulse": 1.05,
		"wiggle": 0.8,
		"tint": Color(1.02, 1.02, 0.96, 1.0),
	},
	Kind.ERROR_SOFT: {
		"pulse": 0.9,
		"wiggle": 0.0,
		"tint": Color(1.0, 0.92, 0.92, 1.0),
	},
}


# --- Enum / Names -------------------------------------------------------


static func name_of(kind: int) -> String:
	if _NAMES.has(kind):
		return String(_NAMES[kind])
	return String(_NAMES[DEFAULT])


static func from_string(s: String) -> int:
	var key: String = s.strip_edges().to_lower()
	if key.is_empty():
		return DEFAULT
	for k in _NAMES:
		if String(_NAMES[k]) == key:
			return int(k)
	return DEFAULT


static func is_known(kind: int) -> bool:
	return _NAMES.has(kind)


## Gesamte Ausdrucksliste in stabiler Reihenfolge (Smoke-Kontrakt und
## kuratierte Dev-Controls). Nur RefCounted-freundliche Typen.
static func all_kinds() -> Array:
	var out: Array = []
	for k in _NAMES:
		out.append(int(k))
	out.sort()
	return out


# --- Modulation --------------------------------------------------------


static func hold_seconds(kind: int) -> float:
	if _HOLD_SECONDS.has(kind):
		return float(_HOLD_SECONDS[kind])
	return 0.0


static func is_transient(kind: int) -> bool:
	return hold_seconds(kind) > 0.0


static func pulse_multiplier(kind: int) -> float:
	return _field_for(kind, "pulse", 1.0)


static func wiggle_multiplier(kind: int) -> float:
	return _field_for(kind, "wiggle", 1.0)


static func tint_shift(kind: int) -> Color:
	var m: Dictionary = _MODULATION.get(kind, _MODULATION[DEFAULT])
	var c: Variant = m.get("tint", Color(1.0, 1.0, 1.0, 1.0))
	if c is Color:
		return c
	return Color(1.0, 1.0, 1.0, 1.0)


# --- State → default expression ---------------------------------------


## Liefert den Default-Ausdruck für einen gegebenen Avatar-State. Wird
## vom Controller aufgerufen, wenn keine transiente Expression aktiv
## ist — sorgt dafür, dass jede State-Änderung mit einem passenden
## Ausdruck startet, ohne dass der Controller separate
## `if state == …`-Verzweigungen braucht.
##
## `connected` bildet den Transport-Zustand ab: wer offline ist, bleibt
## im stillen `NEUTRAL` — der Sleeping-Tint kommt weiterhin aus der
## State-Visualisierung (`DISCONNECTED_MODULATE`).
static func default_for_state(avatar_state: int, connected: bool) -> int:
	if not connected:
		return Kind.NEUTRAL
	if avatar_state == _StateRef.State.THINKING:
		return Kind.FOCUSED
	if avatar_state == _StateRef.State.TALKING:
		return Kind.SPEAKING
	if avatar_state == _StateRef.State.ERROR:
		return Kind.ERROR_SOFT
	return Kind.NEUTRAL


# --- Internals ---------------------------------------------------------


static func _field_for(kind: int, field: String, default_value: float) -> float:
	var m: Dictionary = _MODULATION.get(kind, _MODULATION[DEFAULT])
	return float(m.get(field, default_value))
