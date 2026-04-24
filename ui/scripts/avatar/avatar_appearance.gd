extends RefCounted
## Avatar Appearance — Phase A (MVP-Spike, Smolit Salamander only)
##
## Kleine, rein visuelle Darstellungsschicht für den bestehenden
## Smolit-Salamander-Avatar. Diese Datei implementiert Phase A aus der
## Doku-Linie „Avatar Appearance & Personalization"
## ([`docs/ui_architecture.md` §8b](../../docs/ui_architecture.md),
## [`ROADMAP.md` Phase 4b](../../ROADMAP.md)):
##
##   * **Identity** bleibt implizit `smolit_salamander` — keine
##     alternativen Figuren in dieser Phase. Kein Template-Marktplatz,
##     keine User-Uploads, kein Rigging-System.
##   * **Theme** (`default` / `soft` / `tech` / `minimal`) — kleine,
##     markentreue visuelle Varianten des Salamanders. Themes
##     verändern nur Tönungen, keine Figur.
##   * **Behavior Profile (UI)** (`calm` / `lively` / `reserved`) —
##     rein visuelle Modulation von Mikroanimation (Amplitude, Tempo,
##     Wiggle-Frequenz). Keine Logikänderung, keine Assistenten-
##     personality.
##   * **Appearance Overrides** — `primary_tint` (multiplikativer
##     Farb-Overlay), `intensity` (Skalierung der Animationsstärke)
##     und `scale` (Skalierung des Root-Nodes). Alles rein visuell.
##
## Bindende Abgrenzungen (aus `docs/ui_architecture.md` §8b und
## `ROADMAP.md` Phase 4b):
##
##   * Appearance ≠ Behavior ≠ Personality ≠ Policy.
##   * Avatar-Auswahl verändert **nicht**: Action-Execution,
##     Permissions, ABrain-Entscheidungen, Sicherheitsmodelle,
##     Action-Event-Handling.
##   * Personalisierung ist additiv, nicht ersetzend — der Default
##     Smolit Salamander ist der Referenz-Avatar. DEFAULT-Theme +
##     CALM-Profile + Unity-Overrides *muss* dasselbe Rendering
##     liefern wie vor dieser Phase (Identitätsgarantie, unten im
##     `avatar_appearance_smoke`-Stil überprüft).
##
## Das Modul hat absichtlich **keinen Zustand**: es liefert
## Factory-Dicts und pure static Resolve-Funktionen. Der Avatar-
## Controller hält die aktuelle Appearance-Konfiguration und ruft die
## Helfer bei jedem State-Wechsel auf.

class_name SmolitAvatarAppearance


## Eingebaute, markentreue Smolit-Themes. Alle ändern nur Tönungen
## auf dem Basis-Modulate des Avatars — keine Texturwechsel, keine
## neue Figur.
##
## Der Enum heißt `ThemePreset` (statt `Theme`), weil `Theme` in
## Godot 4 ein nativer Resource-Typ ist — ein Enum mit diesem Namen
## würde die native Klasse beschatten und ist daher nicht erlaubt.
enum ThemePreset {
	DEFAULT,
	SOFT,
	TECH,
	MINIMAL,
}


## UI-only Behavior Profiles. Sie steuern ausschließlich die
## Intensität und das Tempo der Mikroanimation (Idle-Breath,
## Thinking-Breath, Acting-/Talking-Pulse, Wiggle-Frequenz). Sie
## sind **kein** Assistant-Personality-System und haben keinen
## Einfluss auf Core, ABrain, Policy, Presence-State-Maschine oder
## Event-Handling.
enum BehaviorProfile {
	CALM,
	LIVELY,
	RESERVED,
}


const DEFAULT_THEME: int = ThemePreset.DEFAULT
const DEFAULT_PROFILE: int = BehaviorProfile.CALM

## Intensitäts-Override wird weich geklammert, damit niemand durch
## eine Env-Variable den Avatar unsichtbar oder hysterisch macht.
const INTENSITY_MIN: float = 0.5
const INTENSITY_MAX: float = 1.5
const SCALE_MIN: float = 0.75
const SCALE_MAX: float = 1.5


## Theme-Presets. Jedes Preset liefert nur einen `tint_multiplier`
## (additionales Multiplier-Color auf die Basis-Modulate des
## Avatars). Das ist bewusst minimal — Phase A soll keine
## Designexplosion auslösen.
const _THEME_PRESETS: Dictionary = {
	ThemePreset.DEFAULT: {
		"tint_multiplier": Color(1.00, 1.00, 1.00, 1.00),
	},
	# Soft: minimal warme Abweichung. Wirkt freundlicher, bleibt als
	# Smolit klar erkennbar.
	ThemePreset.SOFT: {
		"tint_multiplier": Color(1.05, 1.02, 0.98, 1.00),
	},
	# Tech: leichter Blauton, nüchterner Look.
	ThemePreset.TECH: {
		"tint_multiplier": Color(0.92, 0.98, 1.08, 1.00),
	},
	# Minimal: entsättigt, weniger Kontrast.
	ThemePreset.MINIMAL: {
		"tint_multiplier": Color(0.92, 0.92, 0.92, 0.95),
	},
}


## Profile-Presets. Multiplikatoren auf die bestehenden Avatar-
## Constants. CALM ist die Referenzlinie (1.0 für alles), damit die
## aktuelle Avatar-Mikroanimation 1:1 erhalten bleibt.
const _PROFILE_PRESETS: Dictionary = {
	BehaviorProfile.CALM: {
		"amplitude_multiplier": 1.00,
		"tempo_multiplier":     1.00,   # >1 = langsamer (half_seconds × x)
		"wiggle_interval_multiplier": 1.00,
	},
	BehaviorProfile.LIVELY: {
		"amplitude_multiplier": 1.20,
		"tempo_multiplier":     0.90,   # leicht flotter
		"wiggle_interval_multiplier": 0.70,  # wiggle häufiger
	},
	BehaviorProfile.RESERVED: {
		"amplitude_multiplier": 0.70,
		"tempo_multiplier":     1.15,   # bewusst ruhiger
		"wiggle_interval_multiplier": 1.50,  # wiggle selten
	},
}


# --- Helpers: Namen / Parsing -------------------------------------------


static func theme_name(theme: int) -> String:
	match theme:
		ThemePreset.DEFAULT: return "default"
		ThemePreset.SOFT:    return "soft"
		ThemePreset.TECH:    return "tech"
		ThemePreset.MINIMAL: return "minimal"
		_:             return "default"


static func profile_name(profile: int) -> String:
	match profile:
		BehaviorProfile.CALM:     return "calm"
		BehaviorProfile.LIVELY:   return "lively"
		BehaviorProfile.RESERVED: return "reserved"
		_:                        return "calm"


## Robuste Parser: leere / unbekannte Strings fallen auf den Default
## zurück, damit eine fehlerhafte Env-Konfiguration den Avatar nicht
## bricht. Case-insensitiv.
static func theme_from_string(value: String) -> int:
	match value.strip_edges().to_lower():
		"default": return ThemePreset.DEFAULT
		"soft":    return ThemePreset.SOFT
		"tech":    return ThemePreset.TECH
		"minimal": return ThemePreset.MINIMAL
		_:         return DEFAULT_THEME


static func profile_from_string(value: String) -> int:
	match value.strip_edges().to_lower():
		"calm":     return BehaviorProfile.CALM
		"lively":   return BehaviorProfile.LIVELY
		"reserved": return BehaviorProfile.RESERVED
		_:          return DEFAULT_PROFILE


# --- Appearance-Dict-Factory --------------------------------------------


## Frisches Appearance-Dict mit Identitätsdefaults. Unity-Overrides +
## DEFAULT-Theme + CALM-Profile müssen das alte Verhalten exakt
## reproduzieren — diese Garantie wird im Smoke-Test geprüft.
static func new_appearance() -> Dictionary:
	return {
		"identity": "smolit_salamander",
		"theme": DEFAULT_THEME,
		"profile": DEFAULT_PROFILE,
		"overrides": {
			"primary_tint": Color(1.0, 1.0, 1.0, 1.0),
			"intensity": 1.0,
			"scale": 1.0,
		},
	}


## Convenience: baut ein Appearance-Dict aus expliziten Werten und
## sanitisiert jeden Eintrag via der Parser-/Clamping-Logik oben.
## Signatur bewusst ohne Default-Argumente — GDScripts statischer
## Parser reagiert in preload-Referenzen gelegentlich empfindlich auf
## Default-Ausdrücke, und der Controller ruft die Funktion ohnehin
## mit explizitem Argument-Set auf.
static func make_appearance(
	theme: int,
	profile: int,
	primary_tint: Color,
	intensity: float,
	scale: float,
) -> Dictionary:
	var appearance := new_appearance()
	appearance["theme"] = _sanitize_theme(theme)
	appearance["profile"] = _sanitize_profile(profile)
	var overrides: Dictionary = appearance["overrides"]
	overrides["primary_tint"] = primary_tint
	overrides["intensity"] = clampf(intensity, INTENSITY_MIN, INTENSITY_MAX)
	overrides["scale"] = clampf(scale, SCALE_MIN, SCALE_MAX)
	appearance["overrides"] = overrides
	return appearance


# --- Resolve: reine Funktionen ------------------------------------------


## Multipliziert Theme-Tint × Override-primary_tint auf eine
## zustandsabhängige Basisfarbe (z. B. `NORMAL_MODULATE` oder
## `THINKING_MODULATE`). Liefert garantiert eine gültige Color.
static func resolved_tint(appearance: Dictionary, base_color: Color) -> Color:
	var theme_tint := _theme_tint_multiplier(appearance)
	var override_tint := _override_primary_tint(appearance)
	return _multiply_color(_multiply_color(base_color, theme_tint), override_tint)


## Skaliert eine Basis-Breath-/Pulse-Amplitude (Vector2) anhand des
## Profils und des Intensity-Overrides. Die Amplitude wird um `1.0`
## herum skaliert — `Vector2.ONE` bedeutet „keine Pulsbewegung", und
## nur der *Abstand* zur Identität wird gestreckt/geschrumpft.
static func resolved_amplitude(appearance: Dictionary, base: Vector2) -> Vector2:
	var multiplier := _profile_amplitude_multiplier(appearance) * _override_intensity(appearance)
	var delta: Vector2 = (base - Vector2.ONE) * multiplier
	return Vector2.ONE + delta


## Skaliert eine Basis-Halbperiode (half_seconds) anhand des
## Profil-Tempos. `>1` heißt langsamer, `<1` schneller. Minimal 0.05
## sichern, damit niemand das Tempo gegen 0 treibt.
static func resolved_half_seconds(appearance: Dictionary, base_half: float) -> float:
	var multiplier := _profile_tempo_multiplier(appearance)
	return maxf(0.05, base_half * multiplier)


## Skaliert eine Basis-Root-Scale (BASE_SCALE, HOVER_SCALE) anhand des
## Override-scale-Werts. Wird für Root-Scale/Hover-Scale verwendet —
## NICHT für Body-Scale-Animationen, die laufen durch `resolved_amplitude`.
static func resolved_scale(appearance: Dictionary, base: Vector2) -> Vector2:
	var factor := _override_scale(appearance)
	return base * factor


## Skaliert einen Wiggle-Intervallwert anhand des Profils. `>1` heißt
## seltener, `<1` heißt häufiger. Minimal 1.0 Sekunde, damit auch
## extreme LIVELY+INTENSITY-Konfigurationen nicht hysterisch werden.
static func resolved_wiggle_interval(appearance: Dictionary, base_seconds: float) -> float:
	var multiplier := _profile_wiggle_multiplier(appearance)
	return maxf(1.0, base_seconds * multiplier)


# --- Internals -----------------------------------------------------------


static func _sanitize_theme(theme: int) -> int:
	if _THEME_PRESETS.has(theme):
		return theme
	return DEFAULT_THEME


static func _sanitize_profile(profile: int) -> int:
	if _PROFILE_PRESETS.has(profile):
		return profile
	return DEFAULT_PROFILE


static func _theme_tint_multiplier(appearance: Dictionary) -> Color:
	var theme := _sanitize_theme(int(appearance.get("theme", DEFAULT_THEME)))
	var preset: Dictionary = _THEME_PRESETS[theme]
	var value: Variant = preset.get("tint_multiplier", Color(1, 1, 1, 1))
	if typeof(value) == TYPE_COLOR:
		return value
	return Color(1, 1, 1, 1)


static func _override_primary_tint(appearance: Dictionary) -> Color:
	var overrides: Dictionary = appearance.get("overrides", {})
	var value: Variant = overrides.get("primary_tint", Color(1, 1, 1, 1))
	if typeof(value) == TYPE_COLOR:
		return value
	return Color(1, 1, 1, 1)


static func _override_intensity(appearance: Dictionary) -> float:
	var overrides: Dictionary = appearance.get("overrides", {})
	var value: Variant = overrides.get("intensity", 1.0)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return clampf(float(value), INTENSITY_MIN, INTENSITY_MAX)
	return 1.0


static func _override_scale(appearance: Dictionary) -> float:
	var overrides: Dictionary = appearance.get("overrides", {})
	var value: Variant = overrides.get("scale", 1.0)
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return clampf(float(value), SCALE_MIN, SCALE_MAX)
	return 1.0


static func _profile_amplitude_multiplier(appearance: Dictionary) -> float:
	var profile := _sanitize_profile(int(appearance.get("profile", DEFAULT_PROFILE)))
	var preset: Dictionary = _PROFILE_PRESETS[profile]
	return float(preset.get("amplitude_multiplier", 1.0))


static func _profile_tempo_multiplier(appearance: Dictionary) -> float:
	var profile := _sanitize_profile(int(appearance.get("profile", DEFAULT_PROFILE)))
	var preset: Dictionary = _PROFILE_PRESETS[profile]
	return float(preset.get("tempo_multiplier", 1.0))


static func _profile_wiggle_multiplier(appearance: Dictionary) -> float:
	var profile := _sanitize_profile(int(appearance.get("profile", DEFAULT_PROFILE)))
	var preset: Dictionary = _PROFILE_PRESETS[profile]
	return float(preset.get("wiggle_interval_multiplier", 1.0))


## Komponentenweise Farbmultiplikation. Godot liefert `Color * Color`
## nicht als öffentliche Operator-Überladung, daher diese kleine
## Helper-Funktion.
static func _multiply_color(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)
