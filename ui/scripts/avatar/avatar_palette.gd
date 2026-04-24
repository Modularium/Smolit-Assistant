extends RefCounted
## Avatar Render Polish Palette (PR 30) — kuratierte Konstanten für
## die zusätzlichen prozeduralen Polish-Layer der Phase-B-Identities.
##
## Zweck
## -----
## PR 30 bringt kleine, rein visuelle Feinarbeit in die bestehenden
## `_draw_*`-Pfade von [`avatar_identity_visual.gd`](./avatar_identity_visual.gd):
## ein Sekundär-Highlight am Orb-Kern, ein Specular-Dot pro Pupille
## beim Roboter, eine zweistufige Wangen-Betonung und Augenbrauen-
## Kurven beim Humanoid-Head. Um zu verhindern, dass diese Werte als
## Magic-Numbers in die `_draw_*`-Funktionen wandern, bündelt dieses
## Modul sie an einem Ort. Smoke-Tests lockens gegen stille Drift.
##
## Abgrenzung
## ----------
## * **Keine Duplikation bestehender Paletten.** Rim-Accent-Farben
##   (`avatar_rim_accent.gd`), Theme-Tints (`avatar_appearance.gd`)
##   und State-Modulates (`avatar_controller.gd`) bleiben dort, wo sie
##   sind. Dieses Modul trägt nur die **neuen** Polish-Konstanten.
## * **Keine Asset-Referenzen.** Keine PNG/SVG/GLB-Pfade, keine
##   Asset-Importe, keine Stage-C-Pipeline.
## * **Keine eigenen States / Capabilities.** Der Template-Capability-
##   Contract aus [`avatar_template_capabilities.gd`](./avatar_template_capabilities.gd)
##   bleibt bindend — `wiggle=NONE` / `theme_tint=NONE` respektieren
##   die bestehenden Clamp-Pfade; diese Palette liefert keine
##   zusätzliche Capability-Ausdrucks-Achse.
## * **Smolitux Design Contract — nicht implementiert.** ADR-0001
##   (PR 24) beschreibt Design Tokens als zukünftigen cross-runtime
##   Vertrag. Diese Palette ist der **Andockpunkt**: ein späterer,
##   reversibler Token-Import-Spike kann die hier definierten
##   Konstanten aus einer Token-Quelle speisen, ohne die `_draw_*`-
##   Pfade umzubauen. Heute werden **keine** Tokens konsumiert,
##   keine JSON-/YAML-/TOML-Dateien geladen, keine Generatoren
##   ausgeführt.
##
## Nutzung
## -------
## Als `class_name` importierbar — aber die Konstanten sind pure und
## werden in der Praxis direkt über den Script-Path referenziert:
##
## ```gdscript
## const _PaletteRef := preload("res://scripts/avatar/avatar_palette.gd")
## var c: Color = _PaletteRef.ROBOT_FACEPLATE_INNER_RIM_COLOR
## ```

class_name SmolitAvatarPalette

# --- Robot Head Polish --------------------------------------------------

## Face-Plate-Innenrim: ein sehr dezenter, 1-Pixel-äquivalenter
## Rim um die dunkle Augenband-Plate. Hebt die Plate visuell von der
## Kopfsilhouette ab, ohne sie zu umrahmen. Alpha klein genug, damit
## der Effekt unter Theme-Tints dezent bleibt.
const ROBOT_FACEPLATE_INNER_RIM_COLOR: Color = Color(0.85, 0.90, 1.00, 0.18)

## Specular-Dot in jeder Pupille. Macht den Blick einen Tick
## lebendiger, ohne den Roboter niedlich wirken zu lassen. Größe wird
## in `_draw_robot_face` relativ zum Pupillenradius berechnet.
const ROBOT_PUPIL_SPECULAR_COLOR: Color = Color(1.00, 1.00, 1.00, 0.80)

## Antennen-Kuppen-Highlight: ein Mini-Dot oben-links auf der
## orangenen Kappe, der den Metall-/Kunststoff-Eindruck subtil
## verstärkt. Alpha-moderate, damit es unter Acting- oder Error-
## Modulates nicht überproportional blitzt.
const ROBOT_ANTENNA_HIGHLIGHT_COLOR: Color = Color(1.00, 1.00, 0.88, 0.55)

# --- Orb Polish ---------------------------------------------------------

## Inner Core Glow — eine zusätzliche weiche Scheibe zwischen Haupt-
## körper und Primär-Highlight. Gibt dem Orb mehr Tiefe, ohne einen
## zweiten Highlight-Pfad aufzumachen. Alpha bewusst niedrig, damit
## der Effekt bei jeder Base-Color (heute: (0.82, 0.86, 1.00)) weich
## bleibt.
const ORB_CORE_GLOW_ALPHA: float = 0.22

## Radius-Ratio der Core-Glow-Scheibe relativ zum Orb-Außenradius.
## Sitzt zwischen Kernkreis (0.70) und Primär-Highlight (Offset+0.28)
## und erzeugt den sanften Übergang.
const ORB_CORE_GLOW_RADIUS_RATIO: float = 0.52

# --- Humanoid Head Polish -----------------------------------------------

## Äußere Wangen-Alpha — zarter Außenring des Blush. Gemeinsam mit
## `HUMANOID_CHEEK_INNER_ALPHA` entsteht ein weicher Zweischicht-
## Verlauf, der weniger kreisförmig wirkt als ein einzelner Kreis.
const HUMANOID_CHEEK_OUTER_ALPHA: float = 0.12

## Innere Wangen-Alpha — der dichtere Kern des Blush, leicht kleiner
## als der Außenkreis. Die Differenz zu `HUMANOID_CHEEK_OUTER_ALPHA`
## bleibt klein, damit die Wange nicht wie ein Malerei-Tupfen wirkt.
const HUMANOID_CHEEK_INNER_ALPHA: float = 0.20

## Augenbrauen-Farbe + Dicke-Ratio. Die Brauen sind statische, dezent
## nach außen geneigte Bögen über den Augen. Keine Animation, kein
## eigener State — sie prägen nur den Ruhe-Ausdruck des Humanoid-
## Heads.
const HUMANOID_EYEBROW_COLOR: Color = Color(0.25, 0.20, 0.18, 0.75)
const HUMANOID_EYEBROW_THICKNESS_RATIO: float = 0.045

# --- Palette Sanity ----------------------------------------------------

## Die erwartete Anzahl an Polish-Konstanten. Wird vom Smoke-Test
## genutzt, um versehentliches Dropping oder Dopplung zu erkennen,
## ohne sich an konkrete Werte zu klammern.
const POLISH_CONSTANT_NAMES: Array[String] = [
	"ROBOT_FACEPLATE_INNER_RIM_COLOR",
	"ROBOT_PUPIL_SPECULAR_COLOR",
	"ROBOT_ANTENNA_HIGHLIGHT_COLOR",
	"ORB_CORE_GLOW_ALPHA",
	"ORB_CORE_GLOW_RADIUS_RATIO",
	"HUMANOID_CHEEK_OUTER_ALPHA",
	"HUMANOID_CHEEK_INNER_ALPHA",
	"HUMANOID_EYEBROW_COLOR",
	"HUMANOID_EYEBROW_THICKNESS_RATIO",
]


## Validiert Alpha-/Ratio-Werte (Float-basierte Konstanten) auf das
## erlaubte Intervall [0.0, 1.0]. Pure, ohne Scene-Tree. Ermöglicht
## dem Smoke-Test ein einfaches „Palette-ist-in-Range"-Assertion,
## ohne dass der Test jeden Wert einzeln hart-kodiert (das würde
## Drift nur verschieben).
static func is_valid_ratio(value: float) -> bool:
	return value >= 0.0 and value <= 1.0
