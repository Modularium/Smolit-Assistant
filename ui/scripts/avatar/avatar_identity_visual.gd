extends Control
## Prozedurale Darstellung kuratierter Avatar-Identities (Phase B).
##
## Wird als Sibling-Node zur Smolit-`Body: TextureRect` verwendet
## (siehe `avatar_root.tscn`). Für die Default-Identity (Smolit
## Salamander) bleibt dieser Node versteckt und macht gar nichts —
## Smolit rendert weiterhin 1:1 wie in Phase A. Erst wenn eine
## kuratierte Alternative aktiv ist, wird dieser Node sichtbar und
## zeichnet eine kleine prozedurale Grundform (Rounded Rect oder
## Kreis).
##
## Design-Prinzipien:
##
##   * Keine Binärassets, keine Import-Pipeline. Jede Form ist mit
##     ein paar `draw_rect` / `draw_circle`-Aufrufen umgesetzt.
##   * Keine eigene Animation. Zustands-Ausdruck (Breath, Pulse,
##     Startle, Wiggle, Tint) kommt vom Avatar-Controller über
##     `self.modulate` / `self.scale` / `self.rotation` — diese Werte
##     werden vom Controller pro Frame gespiegelt, damit alle
##     bestehenden Tweens weiter auf `_body` laufen können, ohne dass
##     die Tween-Logik verzweigen muss (siehe
##     `avatar_controller.gd::_mirror_visual_transform`).
##   * Keine Logik. Die Ziel-Identity wird von außen gesetzt
##     (`set_identity`), dieses Skript entscheidet nichts über
##     Zustände, Actions, Permissions oder Persistence.

class_name SmolitAvatarIdentityVisual

const _IdentityRef := preload("res://scripts/avatar/avatar_identity.gd")
const _PaletteRef := preload("res://scripts/avatar/avatar_palette.gd")


var _identity: int = _IdentityRef.DEFAULT


func _ready() -> void:
	# Kein Input-Steal — der Avatar-Controller (`AvatarRoot`) behält
	# den Klick- und Drag-Flow. Wir sind rein visuell.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


## Setzt die gewünschte Identity und triggert ein Re-Draw. Unbekannte
## IDs fallen in `avatar_identity.gd::spec` still auf Smolit zurück —
## in dem Fall ist `shape == NONE` und der Node zeichnet nichts (das
## Smolit-TextureRect bleibt die aktive Darstellung, aber
## Sichtbarkeits-Toggling ist Sache des Controllers).
func set_identity(ident: int) -> void:
	_identity = ident
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var spec: Dictionary = _IdentityRef.spec(_identity)
	var shape: int = int(spec.get("shape", _IdentityRef.Shape.NONE))
	var color: Color = spec.get("base_color", Color(1, 1, 1, 1))
	match shape:
		_IdentityRef.Shape.ROUNDED_RECT:
			_draw_rounded_rect(rect, color)
			_draw_robot_face(rect)
		_IdentityRef.Shape.CIRCLE:
			_draw_orb(rect, color)
		_IdentityRef.Shape.HUMANOID:
			_draw_humanoid(rect, color)
		_:
			# Shape.NONE — nichts zeichnen. Smolit-TextureRect nutzt
			# diesen Zweig im Theorie-Fall, in der Praxis ist dieser
			# Node dann ohnehin unsichtbar.
			pass


# --- Primitive shapes ----------------------------------------------------


func _draw_rounded_rect(rect: Rect2, color: Color) -> void:
	# "Rundeckiges Rechteck" für Robot-Figur. Godot hat kein direktes
	# `draw_rounded_rect`, also setzen wir es aus zwei Rechtecken und
	# vier Viertelkreisen zusammen. Radius bewusst weich, damit die
	# Figur nicht zu kantig wirkt — aber auch nicht wie ein Oval.
	var r: float = minf(rect.size.x, rect.size.y) * 0.22
	# Horizontaler und vertikaler Mittelstreifen
	draw_rect(Rect2(
		rect.position + Vector2(0, r),
		Vector2(rect.size.x, rect.size.y - 2.0 * r),
	), color)
	draw_rect(Rect2(
		rect.position + Vector2(r, 0),
		Vector2(rect.size.x - 2.0 * r, rect.size.y),
	), color)
	# Vier Ecken als Vollkreise — billig und visuell sauber.
	draw_circle(rect.position + Vector2(r, r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, r), r, color)
	draw_circle(rect.position + Vector2(r, rect.size.y - r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, rect.size.y - r), r, color)


func _draw_robot_face(rect: Rect2) -> void:
	# Polish-Stufe Phase 3.2 Render-MVP: Kopf wird klar lesbarer durch
	# eine etwas dunklere "Face-Plate" (kleine Hinterlegung für die
	# Augen), Augen bekommen Pupillen, die Antenne einen sichtbaren
	# Stalk und einen Mund-Slit. Alles weiter rein prozedural, keine
	# Animation, keine Assets — State-Feedback kommt unverändert über
	# `modulate` (siehe `avatar_controller.gd::_apply_state_visuals`).
	var cx: float = rect.position.x + rect.size.x * 0.5
	var top: float = rect.position.y
	# Face-Plate: ein leicht abgesetztes dunkleres Rounded-Rect im
	# Augenband-Bereich. Hebt die Augenpartie optisch vom Kopf ab und
	# lässt den Roboter weniger wie eine blanke Fläche wirken.
	var plate_rect := Rect2(
		rect.position + Vector2(rect.size.x * 0.16, rect.size.y * 0.30),
		Vector2(rect.size.x * 0.68, rect.size.y * 0.30),
	)
	var plate_color := Color(0.10, 0.16, 0.26, 0.42)
	_draw_inner_rounded_rect(plate_rect, plate_color, rect.size.x * 0.06)
	# PR 30 — Polish: dünner Innen-Rim oben auf der Plate. Ein sehr
	# schwach heller Strich an der Oberkante der Augenband-Plate lässt
	# die Plate „absetzen" und gibt dem Robot eine leichte Fassung,
	# ohne einen echten Rahmen zu setzen. Keine Animation, reine
	# Lesbarkeits-Hilfe.
	draw_line(
		plate_rect.position + Vector2(rect.size.x * 0.01, 0.0),
		plate_rect.position + Vector2(plate_rect.size.x - rect.size.x * 0.01, 0.0),
		_PaletteRef.ROBOT_FACEPLATE_INNER_RIM_COLOR,
		maxf(1.0, rect.size.x * 0.012),
		true,
	)

	# Augen — leicht kleiner und tiefer als zuvor, damit sie in der
	# Face-Plate sitzen. Pupillen sind kleine dunkle Kreise; der Kontrast
	# zur Plate gibt dem Ausdruck eine klare Richtung.
	var eye_y: float = rect.position.y + rect.size.y * 0.45
	var eye_r: float = rect.size.x * 0.085
	var eye_color := Color(1, 1, 1, 0.95)
	var pupil_color := Color(0.08, 0.12, 0.18, 0.95)
	var left_eye := Vector2(rect.position.x + rect.size.x * 0.34, eye_y)
	var right_eye := Vector2(rect.position.x + rect.size.x * 0.66, eye_y)
	draw_circle(left_eye, eye_r, eye_color)
	draw_circle(right_eye, eye_r, eye_color)
	draw_circle(left_eye, eye_r * 0.48, pupil_color)
	draw_circle(right_eye, eye_r * 0.48, pupil_color)
	# PR 30 — Polish: kleiner Specular-Dot auf jeder Pupille. Klassischer
	# Cartoon-Trick für lebendigeren Blick; bewusst klein und links-oben
	# vom Pupillen-Zentrum, damit der Blick nicht ins Leere fällt.
	var specular_offset: Vector2 = Vector2(-eye_r * 0.22, -eye_r * 0.26)
	var specular_r: float = eye_r * 0.16
	draw_circle(left_eye + specular_offset, specular_r,
		_PaletteRef.ROBOT_PUPIL_SPECULAR_COLOR)
	draw_circle(right_eye + specular_offset, specular_r,
		_PaletteRef.ROBOT_PUPIL_SPECULAR_COLOR)

	# Antenne: kurzer vertikaler Stalk plus die bekannte orangene Kuppe.
	# Der Stalk hebt den Dot von der Kopfsilhouette ab, statt ihn wie
	# einen aufgesetzten Aufkleber wirken zu lassen.
	var stalk_w: float = rect.size.x * 0.022
	var stalk_h: float = rect.size.y * 0.12
	var stalk_top_y: float = top + rect.size.y * 0.06
	var stalk_color := Color(0.35, 0.38, 0.44, 0.85)
	draw_rect(
		Rect2(Vector2(cx - stalk_w * 0.5, stalk_top_y), Vector2(stalk_w, stalk_h)),
		stalk_color,
	)
	var antenna_cap_radius: float = rect.size.x * 0.048
	var antenna_cap_center: Vector2 = Vector2(cx, stalk_top_y)
	draw_circle(
		antenna_cap_center,
		antenna_cap_radius,
		Color(1.0, 0.72, 0.32, 1.0),
	)
	# PR 30 — Polish: Mini-Highlight oben-links auf der Kuppe; verstärkt
	# den Kunststoff-/Metall-Eindruck ohne zweite Shader-Linie.
	draw_circle(
		antenna_cap_center + Vector2(-antenna_cap_radius * 0.35, -antenna_cap_radius * 0.35),
		antenna_cap_radius * 0.32,
		_PaletteRef.ROBOT_ANTENNA_HIGHLIGHT_COLOR,
	)

	# Mund-Slit: eine kurze horizontale Linie unter der Face-Plate. Kein
	# Smile, kein Emoji — ein schmaler Strich, der dem Kopf einen
	# klaren "Abschluss nach unten" gibt, ohne ihn zu anthropomorph zu
	# machen.
	var mouth_y: float = rect.position.y + rect.size.y * 0.72
	var mouth_half: float = rect.size.x * 0.14
	draw_line(
		Vector2(cx - mouth_half, mouth_y),
		Vector2(cx + mouth_half, mouth_y),
		Color(0.12, 0.16, 0.22, 0.70),
		maxf(1.0, rect.size.x * 0.02),
		true,
	)


func _draw_orb(rect: Rect2, color: Color) -> void:
	# Polish-Stufe: statt einem harten 35%-Halo + Kernkreis zeichnen wir
	# jetzt einen weicheren Verlauf aus vier konzentrischen Halo-Layern
	# mit abnehmender Alpha. Ergebnis: die Silhouette fadet sauberer nach
	# außen, der Kern bleibt klar erkennbar, und ein kleiner
	# Sekundär-Highlight unten rechts gibt dem Orb Tiefe ohne
	# Shader-Aufwand.
	var center: Vector2 = rect.position + rect.size * 0.5
	var outer_r: float = minf(rect.size.x, rect.size.y) * 0.5
	# Halo-Ringe (außen → innen), jeweils leicht transparenter als der
	# nächste. Der outerste Ring ist fast unsichtbar und simuliert einen
	# weichen Abfall — Godot hat keinen Gradient-Kreis, aber vier
	# Schritte reichen für eine deutlich glattere Anmutung als zuvor.
	var halo_alphas: Array = [0.12, 0.22, 0.34, 0.55]
	var halo_radii: Array = [1.00, 0.93, 0.86, 0.80]
	for i in range(halo_alphas.size()):
		var a: float = float(halo_alphas[i]) * color.a
		var rr: float = outer_r * float(halo_radii[i])
		draw_circle(center, rr, Color(color.r, color.g, color.b, a))
	# Hauptkörper (Kern des Orbs).
	draw_circle(center, outer_r * 0.70, color)
	# PR 30 — Polish: weiche Core-Glow-Scheibe zwischen Kernkreis und
	# Primär-Highlight. Trägt die Base-Color mit verringertem Alpha und
	# fügt dem Orb eine zusätzliche Tiefenstufe — ohne Shader, ohne
	# neuen Pfad. Die Scheibe ist bewusst nach oben-links versetzt,
	# damit sie mit der Licht-Richtung der bestehenden Highlights
	# stimmt.
	draw_circle(
		center - Vector2(outer_r * 0.10, outer_r * 0.12),
		outer_r * _PaletteRef.ORB_CORE_GLOW_RADIUS_RATIO,
		Color(color.r, color.g, color.b, _PaletteRef.ORB_CORE_GLOW_ALPHA),
	)
	# Primär-Highlight oben-links.
	draw_circle(
		center - Vector2(outer_r * 0.20, outer_r * 0.24),
		outer_r * 0.28,
		Color(1, 1, 1, 0.55),
	)
	# Sekundär-Highlight unten-rechts — kleiner, gedämpfter, gibt dem
	# Orb einen weichen "Schulter"-Glanz statt einer flachen Kugel.
	draw_circle(
		center + Vector2(outer_r * 0.24, outer_r * 0.20),
		outer_r * 0.14,
		Color(1, 1, 1, 0.20),
	)


func _draw_humanoid(rect: Rect2, color: Color) -> void:
	# Polish-Stufe: Kopf bekommt sanfte Wangen-Betonung (sehr schwaches
	# Blush), Pupillen erhalten kleine Highlight-Dots, und ein dezenter
	# Halbring unter dem Mund gibt dem Kinn etwas Tiefe. Weiter
	# bewusst flach und symmetrisch — wir wollen keine Karikatur, nur
	# eine klar vom Robot / Orb unterscheidbare Silhouette.
	var center: Vector2 = rect.position + rect.size * 0.5
	var outer_r: float = minf(rect.size.x, rect.size.y) * 0.5
	# Kopf. Radius bleibt leicht unter 50 %, damit die Figur nicht an den
	# Clip-Rand stößt.
	draw_circle(center, outer_r * 0.94, color)

	# Wangen — PR 30 Polish: Zweischicht-Blush für einen weicheren
	# Verlauf. Ein größerer, sehr transparenter Außenkreis plus ein
	# kleinerer, etwas dichterer Innenkreis ersetzen den bisherigen
	# Einzeltupfen. Der Effekt bleibt unter Theme-Tints dezent, weil
	# beide Alphas niedrig bleiben.
	var cheek_rose := Color(1.00, 0.72, 0.68, 1.0)
	var cheek_outer_color := Color(cheek_rose.r, cheek_rose.g, cheek_rose.b,
		_PaletteRef.HUMANOID_CHEEK_OUTER_ALPHA)
	var cheek_inner_color := Color(cheek_rose.r, cheek_rose.g, cheek_rose.b,
		_PaletteRef.HUMANOID_CHEEK_INNER_ALPHA)
	var cheek_outer_r: float = outer_r * 0.18
	var cheek_inner_r: float = outer_r * 0.11
	var cheek_y: float = center.y + outer_r * 0.10
	var cheek_dx: float = outer_r * 0.44
	draw_circle(Vector2(center.x - cheek_dx, cheek_y), cheek_outer_r, cheek_outer_color)
	draw_circle(Vector2(center.x + cheek_dx, cheek_y), cheek_outer_r, cheek_outer_color)
	draw_circle(Vector2(center.x - cheek_dx, cheek_y), cheek_inner_r, cheek_inner_color)
	draw_circle(Vector2(center.x + cheek_dx, cheek_y), cheek_inner_r, cheek_inner_color)

	# Augen + Pupillen-Highlights. Die Augen selbst bleiben klein und
	# dunkel; der Highlight-Dot ist ein kleiner weißer Akzent, der dem
	# Blick Lebendigkeit gibt — aber bewusst klein genug, um nicht
	# überpräsent zu wirken.
	var eye_y: float = center.y - outer_r * 0.10
	var eye_dx: float = outer_r * 0.30
	var eye_r: float = outer_r * 0.09
	var eye_color := Color(0.15, 0.18, 0.22, 0.95)
	var highlight_color := Color(1.0, 1.0, 1.0, 0.85)
	var left_eye := Vector2(center.x - eye_dx, eye_y)
	var right_eye := Vector2(center.x + eye_dx, eye_y)
	draw_circle(left_eye, eye_r, eye_color)
	draw_circle(right_eye, eye_r, eye_color)
	draw_circle(left_eye + Vector2(-eye_r * 0.30, -eye_r * 0.35),
		eye_r * 0.30, highlight_color)
	draw_circle(right_eye + Vector2(-eye_r * 0.30, -eye_r * 0.35),
		eye_r * 0.30, highlight_color)

	# PR 30 — Polish: sehr dezente, statische Augenbrauen. Keine
	# Animation, kein neuer State — nur ein Ruhe-Ausdrucks-Detail, das
	# dem Humanoid-Head einen klaren „Blick" gibt, statt eines Punkt-
	# Augen-Eindrucks. Leicht nach außen geneigt (innere Bogen-Enden
	# tiefer), damit das Gesicht freundlich wirkt.
	var brow_thickness: float = maxf(1.2, outer_r * _PaletteRef.HUMANOID_EYEBROW_THICKNESS_RATIO)
	var brow_y: float = eye_y - eye_r * 1.90
	var brow_half: float = eye_r * 1.10
	var brow_tilt: float = eye_r * 0.35
	# Linke Braue: innere (rechte) Spitze tiefer als äußere (linke).
	draw_line(
		Vector2(left_eye.x - brow_half, brow_y),
		Vector2(left_eye.x + brow_half * 0.60, brow_y + brow_tilt),
		_PaletteRef.HUMANOID_EYEBROW_COLOR,
		brow_thickness,
		true,
	)
	# Rechte Braue: spiegelt die linke.
	draw_line(
		Vector2(right_eye.x + brow_half, brow_y),
		Vector2(right_eye.x - brow_half * 0.60, brow_y + brow_tilt),
		_PaletteRef.HUMANOID_EYEBROW_COLOR,
		brow_thickness,
		true,
	)

	# Mund — wie bisher ein sanftes Lächeln via `draw_arc`. Werte sind
	# unverändert, damit der Grundausdruck identisch bleibt.
	var mouth_center: Vector2 = center + Vector2(0, outer_r * 0.28)
	var mouth_r: float = outer_r * 0.26
	var mouth_color := Color(0.25, 0.20, 0.18, 0.90)
	draw_arc(
		mouth_center,
		mouth_r,
		deg_to_rad(20.0),
		deg_to_rad(160.0),
		24,
		mouth_color,
		minf(outer_r * 0.05, 3.0),
	)

	# Kinn-Schatten: ein schmaler Bogen unter dem Mund, sehr
	# transparent. Gibt dem Gesicht eine minimale Dreidimensionalität,
	# ohne in Schattenspiel abzudriften.
	var chin_center: Vector2 = center + Vector2(0, outer_r * 0.52)
	var chin_r: float = outer_r * 0.62
	var chin_color := Color(0.15, 0.12, 0.10, 0.14)
	draw_arc(
		chin_center,
		chin_r,
		deg_to_rad(35.0),
		deg_to_rad(145.0),
		24,
		chin_color,
		minf(outer_r * 0.045, 2.5),
	)


## Ein kleiner Helper für das Face-Plate-Rendering im Robot-Kopf.
## Verwendet dieselbe „zwei Rechtecke + vier Eckenkreise"-Technik wie
## `_draw_rounded_rect`, bleibt aber lokal inset- und radius-parametriert,
## damit die Face-Plate sauber innerhalb der Kopfsilhouette sitzt.
func _draw_inner_rounded_rect(rect: Rect2, color: Color, corner_radius: float) -> void:
	var r: float = minf(minf(rect.size.x, rect.size.y) * 0.5, corner_radius)
	draw_rect(Rect2(
		rect.position + Vector2(0, r),
		Vector2(rect.size.x, rect.size.y - 2.0 * r),
	), color)
	draw_rect(Rect2(
		rect.position + Vector2(r, 0),
		Vector2(rect.size.x - 2.0 * r, rect.size.y),
	), color)
	draw_circle(rect.position + Vector2(r, r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, r), r, color)
	draw_circle(rect.position + Vector2(r, rect.size.y - r), r, color)
	draw_circle(rect.position + Vector2(rect.size.x - r, rect.size.y - r), r, color)
