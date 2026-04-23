extends RefCounted
## Avatar Identity Catalog — Phase B (erster kleiner, kuratierter Spike).
##
## Phase A hatte *eine* Identity: den Smolit-Salamander, hardcoded über
## die beiden Body-Texturen. Phase B öffnet diesen Punkt minimal und
## bewusst eng: 2–3 **kuratierte** zusätzliche Figuren, ausdrücklich
## keine User-Uploads, kein Template-Marktplatz, keine offene Plug-in-
## Pipeline.
##
## Was dieses Modul ist:
##
##   * Ein statischer Katalog der bekannten Figuren, mit einem kleinen
##     Render-Spec pro Eintrag (Render-Art, Grundform, Grundfarbe,
##     Capability-Flags).
##   * Ein robuster Parser (`identity_from_string`), der unbekannte
##     Werte **still auf Smolit zurückfallen lässt**. Damit können
##     Env-Variable, gespeicherte Preferences und künftige Quellen
##     nichts kaputt machen, was kein Avatar wäre.
##   * Capability-Lookups, damit der Avatar-Controller bei Bedarf
##     entscheiden kann, welche Ausdrucksdetails für eine Figur
##     darstellbar sind (z. B. „swap zwischen IDLE- und ACTIVE-Textur"
##     gilt nur für Smolit).
##
## Was dieses Modul **nicht** ist:
##
##   * Kein Asset-Loader. Smolit nutzt weiterhin die beiden
##     PNG-Texturen aus `assets/avatar/`. Die zusätzlichen Figuren
##     werden rein prozedural gezeichnet (siehe
##     `avatar_identity_visual.gd`) — keine neuen Binärassets, keine
##     Import-Pipeline.
##   * Kein Logik-Layer. Identity ≠ Behavior ≠ Personality ≠ Policy.
##     Ein Wechsel der Figur ändert nichts an Core-Entscheidungen,
##     Permissions, Approval-Flows oder ABrain-Prompts.
##   * Kein Plug-in-Framework. Jede Figur ist hart im Code hinterlegt.
##     Stage C (User-supplied Avatare) bleibt Ziel-Zustand und wird
##     erst später angegangen.
##
## Branding bleibt Smolit-first:
##
##   * `DEFAULT == SMOLIT_SALAMANDER`. Wer `identity` nicht aktiv
##     setzt (weder per Env noch per Preferences), bekommt Smolit.
##   * Jeder ungültige Eingabewert fällt auf Smolit zurück, nicht auf
##     eine der Alternativen.

class_name SmolitAvatarIdentity


## Kleiner, geschlossener Enum über alle in diesem PR kuratierten
## Figuren. Reihenfolge definiert die Reihenfolge im Dev-Panel-Picker
## (siehe `all_ids`).
enum Identity {
	SMOLIT_SALAMANDER,  # Default, Referenz-Avatar, PNG-basiert
	ROBOT_HEAD,         # kleine prozedurale Robot-Skizze (rounded rect)
	ORB,                # abstraktes Glow-Orb (Kreis mit Halo)
	HUMANOID_HEAD,      # ruhiges menschlich gelesenes Gesicht (Kreis + Augen + Mund)
}


## Render-Kategorie — bestimmt, welchen Visual-Pfad der Avatar-
## Controller nimmt:
##
##   * `TEXTURE` — der klassische Smolit-Pfad. Nutzt die beiden
##     `smolit_idle.png` / `smolit_active.png` und den Circle-Mask-
##     Shader aus `avatar_root.tscn`.
##   * `PROCEDURAL` — der Identity-Shape-Pfad. Versteckt die
##     Smolit-TextureRect und lässt stattdessen
##     `avatar_identity_visual.gd` zeichnen (Grundform aus
##     `Shape`-Enum, Grundfarbe aus `base_color`).
enum RenderKind {
	TEXTURE,
	PROCEDURAL,
}


## Grundform für prozedurale Figuren. `NONE` bedeutet „nichts
## zusätzlich zeichnen"; Smolit fällt auf diesen Wert zurück, weil
## dort das TextureRect die gesamte Darstellung übernimmt.
enum Shape {
	NONE,
	ROUNDED_RECT,  # z. B. Robot-Kopf
	CIRCLE,        # z. B. Orb (nur Halo + Körper + Highlight)
	HUMANOID,      # Kreis in Hauttönen + zwei Augen + kleiner Mund-Arc
}


const DEFAULT: int = Identity.SMOLIT_SALAMANDER


## Spec-Tabelle. Jede Zeile ist absichtlich klein gehalten — nur die
## Felder, die der Controller oder die Preview tatsächlich liest.
const _SPECS: Dictionary = {
	Identity.SMOLIT_SALAMANDER: {
		"name": "smolit_salamander",
		"label": "Smolit Salamander",
		"render_kind": RenderKind.TEXTURE,
		"shape": Shape.NONE,
		"base_color": Color(1, 1, 1, 1),
		# Smolit hat zwei Texturen (idle / active), die der Controller
		# beim State-Wechsel tauscht. Kuratierte Alternativen nutzen
		# diesen Pfad nicht; sie bekommen ihren Zustands-Ausdruck
		# komplett über Modulate / Scale / Rotation.
		"supports_texture_swap": true,
	},
	Identity.ROBOT_HEAD: {
		"name": "robot_head",
		"label": "Robot Head",
		"render_kind": RenderKind.PROCEDURAL,
		"shape": Shape.ROUNDED_RECT,
		"base_color": Color(0.55, 0.72, 0.95, 1.0),
		"supports_texture_swap": false,
	},
	Identity.ORB: {
		"name": "orb",
		"label": "Orb",
		"render_kind": RenderKind.PROCEDURAL,
		"shape": Shape.CIRCLE,
		"base_color": Color(0.82, 0.86, 1.00, 1.0),
		"supports_texture_swap": false,
	},
	Identity.HUMANOID_HEAD: {
		"name": "humanoid_head",
		"label": "Humanoid Head",
		"render_kind": RenderKind.PROCEDURAL,
		"shape": Shape.HUMANOID,
		# Warmer, neutraler Hautton. Theme-Tints multiplizieren auf
		# diese Basis (z. B. "tech" schiebt leicht ins Bläuliche).
		"base_color": Color(0.95, 0.82, 0.72, 1.0),
		"supports_texture_swap": false,
	},
}


# --- Basic lookups -------------------------------------------------------


static func is_known(ident: int) -> bool:
	return _SPECS.has(ident)


static func all_ids() -> Array:
	# Reihenfolge ist Doku-relevant: Smolit bleibt erste Option in
	# Pickern und Listen, damit der Default nicht "untergeht".
	return [
		Identity.SMOLIT_SALAMANDER,
		Identity.ROBOT_HEAD,
		Identity.HUMANOID_HEAD,
		Identity.ORB,
	]


static func spec(ident: int) -> Dictionary:
	# Tiefe Kopie, damit Caller das Dict nicht versehentlich mutieren.
	var key: int = ident if _SPECS.has(ident) else DEFAULT
	return (_SPECS[key] as Dictionary).duplicate(true)


static func identity_name(ident: int) -> String:
	return String(spec(ident).get("name", "smolit_salamander"))


static func identity_label(ident: int) -> String:
	return String(spec(ident).get("label", "Smolit Salamander"))


## Robuster Parser. Akzeptiert mehrere Schreibweisen pro Figur (die
## Aliasse machen Env-Konfiguration und gespeicherte Preferences
## vergebender); unbekannte Eingaben fallen **still auf Smolit**
## zurück — kein Crash, kein Log-Spam, Default bleibt brand-safe.
static func identity_from_string(value: String) -> int:
	match value.strip_edges().to_lower():
		"smolit_salamander", "smolit", "salamander":
			return Identity.SMOLIT_SALAMANDER
		"robot_head", "robot":
			return Identity.ROBOT_HEAD
		"orb", "mist", "abstract":
			return Identity.ORB
		"humanoid_head", "humanoid", "human":
			return Identity.HUMANOID_HEAD
		_:
			return DEFAULT


# --- Capability lookups --------------------------------------------------


static func render_kind(ident: int) -> int:
	return int(spec(ident)["render_kind"])


static func shape(ident: int) -> int:
	return int(spec(ident)["shape"])


static func base_color(ident: int) -> Color:
	var value: Variant = spec(ident).get("base_color", Color(1, 1, 1, 1))
	if typeof(value) == TYPE_COLOR:
		return value
	return Color(1, 1, 1, 1)


static func supports_texture_swap(ident: int) -> bool:
	return bool(spec(ident).get("supports_texture_swap", false))


static func is_smolit(ident: int) -> bool:
	return ident == Identity.SMOLIT_SALAMANDER
