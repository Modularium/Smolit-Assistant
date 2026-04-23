extends RefCounted
## Template-Capability-Contract für kuratierte Avatar-Identities
## (Phase B, hardening). Diese Schicht beantwortet pro Template drei
## klar umrissene Fragen und liefert deterministische Fallbacks:
##
##   1. **Welche Avatar-States unterstützt die Figur voll?** Für
##      Zustände, die ein Template nicht tragen kann (z. B. „Talking
##      mouth" beim abstrakten `orb`), gibt ein optionaler
##      `state_fallback`-Map-Eintrag an, auf welchen *unterstützten*
##      State gerendert werden soll. Unbekannte States landen am
##      Ende bei `IDLE`.
##   2. **Wie stark werden Ausdrucksmittel mitgetragen?** Fünf
##      Ausdrucks-Achsen (`theme_tint`, `behavior_profile`,
##      `state_pulse`, `wiggle`, `error_startle`) werden als
##      `ExpressionLevel` (`NONE` / `REDUCED` / `FULL`) deklariert.
##      Der Controller leitet daraus einen Multiplikator ab (0.0 /
##      0.5 / 1.0), den er auf die jeweilige Intensität anwendet.
##   3. **Wo lebt die Entscheidung?** Capability-Lookups laufen
##      ausschließlich über diese Statics — der Controller hat keine
##      `if identity == ROBOT_HEAD: …`-Zweige mehr.
##
## Design-Prinzipien:
##
##   * **Ehrlich statt uniform.** Ein Template deklariert seine
##     tatsächlichen Ausdrucksmittel. `orb` hat keinen
##     „Mund" → `TALKING` wird sauber auf `ACTING` gemappt, statt
##     visuell nichts zu tun.
##   * **Klein statt offen.** Keine dynamische Contract-Sprache, kein
##     Plug-in-System. Die Liste der Ausdrucks-Achsen und die Liste
##     der Templates sind in dieser Datei hart kuratiert.
##   * **Smolit ist Referenz.** Default-Identity hat überall `FULL` +
##     keinen `state_fallback`. Alle anderen Templates leben relativ
##     zur Smolit-Referenzlinie.
##   * **Deterministisch.** Für jede gültige (identity, state)-
##     Kombination liefert `resolve_state` genau einen renderbaren
##     Ziel-State; für jede (identity, expression)-Kombination genau
##     einen `ExpressionLevel`.
##   * **Kein Crash-Pfad.** Unbekannte Identity-IDs fallen über
##     `avatar_identity.gd::is_known` auf Smolit zurück, bevor dieses
##     Modul überhaupt angefragt wird. Eine „vergessene" Expression-
##     Achse liefert `FULL` (konservativ, Default-Verhalten).

class_name SmolitAvatarTemplateCapabilities

const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const _StateRef := preload("res://scripts/avatar/avatar_state.gd")


## Ausdrucks-Stärke für eine einzelne Achse.
##
##   * `NONE` — Ausdruckspfad ist **aus**. Beispiel: `orb.wiggle = NONE`.
##     Der Controller zeichnet nichts, startet keinen Tween, verbrennt
##     keine Timer. Multiplikator ist 0.0.
##   * `REDUCED` — Ausdruckspfad ist **abgeschwächt**. Der Controller
##     fährt die Intensität halb; Tweens/Timer laufen, aber mit einer
##     weicheren Ausprägung. Multiplikator ist 0.5.
##   * `FULL` — Ausdruckspfad ist **vollständig** wie bei Smolit. Der
##     Controller rendert ohne Zusatzschritt. Multiplikator ist 1.0.
enum ExpressionLevel {
	NONE,
	REDUCED,
	FULL,
}


## Die fünf kuratierten Ausdrucks-Achsen. Die Namen sind Strings, damit
## die Spec-Tabelle lesbar bleibt; der Controller verwendet die Konstanten.
const EXPR_THEME_TINT: String = "theme_tint"
const EXPR_BEHAVIOR_PROFILE: String = "behavior_profile"
const EXPR_STATE_PULSE: String = "state_pulse"
const EXPR_WIGGLE: String = "wiggle"
const EXPR_ERROR_STARTLE: String = "error_startle"


## Pro Template ein Eintrag:
##
##   * `states_supported`: Array über `AvatarState.State`-Werte, die das
##     Template direkt (ohne Fallback) rendern kann.
##   * `state_fallback`: Dictionary `{ unsupported_state: replacement_state }`.
##     Wird nur konsultiert, wenn `states_supported` den Ursprungs-State
##     nicht enthält. Der Replacement-State muss in `states_supported`
##     sein; andernfalls greift der End-Fallback auf `IDLE`.
##   * `expression`: Dictionary über `EXPR_*`-Keys auf `ExpressionLevel`-
##     Werte. Fehlende Keys werden als `FULL` interpretiert (konservatives
##     Default-Verhalten).
const _CAPS: Dictionary = {
	# Smolit Salamander — Referenzlinie. Alle States voll unterstützt,
	# keine Fallbacks nötig, alle Ausdrucks-Achsen FULL. Das Template
	# definiert, was „vollständig" bedeutet; alle anderen Templates
	# werden dagegen gemessen.
	_IdentityRef.Identity.SMOLIT_SALAMANDER: {
		"states_supported": [
			_StateRef.State.IDLE,
			_StateRef.State.THINKING,
			_StateRef.State.TALKING,
			_StateRef.State.ACTING,
			_StateRef.State.DISCONNECTED,
			_StateRef.State.ERROR,
		],
		"state_fallback": {},
		"expression": {
			EXPR_THEME_TINT: ExpressionLevel.FULL,
			EXPR_BEHAVIOR_PROFILE: ExpressionLevel.FULL,
			EXPR_STATE_PULSE: ExpressionLevel.FULL,
			EXPR_WIGGLE: ExpressionLevel.FULL,
			EXPR_ERROR_STARTLE: ExpressionLevel.FULL,
		},
	},
	# Robot-Head — mechanisch gelesene Figur. Alle States werden
	# akzeptiert, aber der Idle-„Wiggle" (kleiner Kopf-Nick-Cue) wirkt
	# auf einem Rounded-Rect mechanisch zuviel; deshalb `REDUCED`. Der
	# Rest bleibt voll.
	_IdentityRef.Identity.ROBOT_HEAD: {
		"states_supported": [
			_StateRef.State.IDLE,
			_StateRef.State.THINKING,
			_StateRef.State.TALKING,
			_StateRef.State.ACTING,
			_StateRef.State.DISCONNECTED,
			_StateRef.State.ERROR,
		],
		"state_fallback": {},
		"expression": {
			EXPR_THEME_TINT: ExpressionLevel.FULL,
			EXPR_BEHAVIOR_PROFILE: ExpressionLevel.FULL,
			EXPR_STATE_PULSE: ExpressionLevel.FULL,
			EXPR_WIGGLE: ExpressionLevel.REDUCED,
			EXPR_ERROR_STARTLE: ExpressionLevel.FULL,
		},
	},
	# Orb — abstraktes Glow-Bouquet ohne Gesicht. Hat keinen „Talking
	# mouth", deshalb wird `TALKING` auf `ACTING` gemappt (vorhandener
	# Acting-Pulse trägt den Ausdruck). Wiggle entfällt komplett, weil
	# ein abstrakter Kreis keinen Kopf-Nick-Cue sinnvoll trägt.
	_IdentityRef.Identity.ORB: {
		"states_supported": [
			_StateRef.State.IDLE,
			_StateRef.State.THINKING,
			_StateRef.State.ACTING,
			_StateRef.State.DISCONNECTED,
			_StateRef.State.ERROR,
		],
		"state_fallback": {
			_StateRef.State.TALKING: _StateRef.State.ACTING,
		},
		"expression": {
			EXPR_THEME_TINT: ExpressionLevel.FULL,
			EXPR_BEHAVIOR_PROFILE: ExpressionLevel.FULL,
			EXPR_STATE_PULSE: ExpressionLevel.FULL,
			EXPR_WIGGLE: ExpressionLevel.NONE,
			EXPR_ERROR_STARTLE: ExpressionLevel.FULL,
		},
	},
	# Humanoid-Head — ruhige Figur. Alle States werden getragen, aber
	# Wiggle wirkt hier zu „spielerisch" für einen menschlich gelesenen
	# Kopf — deshalb `REDUCED`. Kein State-Fallback nötig.
	_IdentityRef.Identity.HUMANOID_HEAD: {
		"states_supported": [
			_StateRef.State.IDLE,
			_StateRef.State.THINKING,
			_StateRef.State.TALKING,
			_StateRef.State.ACTING,
			_StateRef.State.DISCONNECTED,
			_StateRef.State.ERROR,
		],
		"state_fallback": {},
		"expression": {
			EXPR_THEME_TINT: ExpressionLevel.FULL,
			EXPR_BEHAVIOR_PROFILE: ExpressionLevel.FULL,
			EXPR_STATE_PULSE: ExpressionLevel.FULL,
			EXPR_WIGGLE: ExpressionLevel.REDUCED,
			EXPR_ERROR_STARTLE: ExpressionLevel.FULL,
		},
	},
}


# --- State support -------------------------------------------------------


## Liefert `true`, wenn das Template den Ziel-State direkt rendert.
## Unbekannte Identity-IDs werden auf Smolit geklemmt, damit der
## Aufrufer nie in einen undefinierten Kapabilitätszustand gerät.
static func supports_state(identity: int, state: int) -> bool:
	var key: int = _safe_identity(identity)
	var states: Array = _CAPS[key]["states_supported"]
	return states.has(state)


## Mappt einen angefragten Avatar-State auf den tatsächlich zu
## rendernden State:
##
##   * Wird `state` unterstützt → gibt `state` zurück.
##   * Gibt es einen `state_fallback`-Eintrag → gibt den dortigen
##     Replacement-State zurück (auch wenn dieser selbst in
##     `states_supported` fehlt; Templates deklarieren den Fallback
##     bewusst, und der End-Fallback `IDLE` fängt den Rest).
##   * Sonst → `AvatarState.State.IDLE`. Das garantiert, dass jede
##     Anfrage mit einem renderbaren State beantwortet wird.
static func resolve_state(identity: int, state: int) -> int:
	var key: int = _safe_identity(identity)
	var states: Array = _CAPS[key]["states_supported"]
	if states.has(state):
		return state
	var fallback: Dictionary = _CAPS[key]["state_fallback"]
	if fallback.has(state):
		return int(fallback[state])
	return _StateRef.State.IDLE


# --- Expression levels ---------------------------------------------------


## Liefert den deklarierten `ExpressionLevel` für eine Achse. Ein
## fehlender Key wird konservativ als `FULL` interpretiert — das hält
## die Tabelle kurz und erzwingt keine redundanten Einträge für
## Referenz-Templates.
static func expression_level(identity: int, expression_key: String) -> int:
	var key: int = _safe_identity(identity)
	var expr_map: Dictionary = _CAPS[key].get("expression", {})
	if not expr_map.has(expression_key):
		return ExpressionLevel.FULL
	return int(expr_map[expression_key])


## Kleiner Helper für den Controller: liefert den numerischen
## Multiplikator, der auf Amplitude / Winkel / Tint-Delta angewendet
## werden kann. `FULL` = 1.0, `REDUCED` = 0.5, `NONE` = 0.0.
static func multiplier(identity: int, expression_key: String) -> float:
	match expression_level(identity, expression_key):
		ExpressionLevel.NONE:
			return 0.0
		ExpressionLevel.REDUCED:
			return 0.5
		_:
			return 1.0


# --- Introspection / debugging ------------------------------------------


## Für Smokes und Diagnose: liefert das (tief kopierte) Capability-Dict
## eines Templates. Nicht dafür gedacht, den Zustand zu mutieren — die
## Caller-seitige Mutation wäre ein Bug.
static func capabilities_for(identity: int) -> Dictionary:
	var key: int = _safe_identity(identity)
	return (_CAPS[key] as Dictionary).duplicate(true)


# --- Internals -----------------------------------------------------------


## Unbekannte Identity-IDs werden still auf Smolit geklemmt — genau
## wie an allen anderen Grenzen der Appearance-Linie. Das vermeidet,
## dass eine fremde ID den Controller in einen nicht-deklarierten
## Zustand rutschen lässt.
static func _safe_identity(identity: int) -> int:
	if _CAPS.has(identity):
		return identity
	return _IdentityRef.DEFAULT
