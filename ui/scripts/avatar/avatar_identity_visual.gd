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
	# Minimaler Ausdruck: zwei Augen + ein orangefarbener Antennen-
	# Punkt oben. Bewusst nicht animiert — State-Feedback kommt über
	# den vom Controller vorgegebenen `modulate`.
	var eye_y: float = rect.position.y + rect.size.y * 0.44
	var eye_r: float = rect.size.x * 0.085
	var eye_color := Color(1, 1, 1, 0.95)
	draw_circle(
		Vector2(rect.position.x + rect.size.x * 0.33, eye_y), eye_r, eye_color,
	)
	draw_circle(
		Vector2(rect.position.x + rect.size.x * 0.67, eye_y), eye_r, eye_color,
	)
	# Antennen-Dot
	draw_circle(
		Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.14),
		rect.size.x * 0.045,
		Color(1.0, 0.72, 0.32, 1.0),
	)


func _draw_orb(rect: Rect2, color: Color) -> void:
	# Drei konzentrische Kreise ergeben ein weiches Glow-Orb ohne
	# Shader-Aufwand: äußerer Halo (halbtransparent), Kernkreis,
	# innerer Highlight-Spot (off-center).
	var center: Vector2 = rect.position + rect.size * 0.5
	var outer_r: float = minf(rect.size.x, rect.size.y) * 0.5
	# Halo
	draw_circle(center, outer_r,
		Color(color.r, color.g, color.b, color.a * 0.35))
	# Hauptkörper
	draw_circle(center, outer_r * 0.78, color)
	# Highlight (oben-links leicht versetzt)
	draw_circle(
		center - Vector2(outer_r * 0.18, outer_r * 0.22),
		outer_r * 0.28,
		Color(1, 1, 1, 0.5),
	)


func _draw_humanoid(rect: Rect2, color: Color) -> void:
	# Ruhiges menschlich gelesenes Gesicht: ein Kreis in Hauttönen
	# plus zwei Augen und ein kleiner Mund-Arc. Bewusst flach und
	# symmetrisch — wir wollen weder Charakterdesign noch Karikatur,
	# nur eine deutlich vom Robot / Orb unterscheidbare Silhouette.
	var center: Vector2 = rect.position + rect.size * 0.5
	var outer_r: float = minf(rect.size.x, rect.size.y) * 0.5
	# Hauptkörper (Kopf) — der Radius ist leicht unter 50 %, damit die
	# Figur nicht an den Clip-Rand des AvatarRoot-Layout-Rects stößt.
	draw_circle(center, outer_r * 0.94, color)
	# Augen — leicht unterhalb der Mitte, vertikal identisch.
	var eye_y: float = center.y - outer_r * 0.10
	var eye_dx: float = outer_r * 0.30
	var eye_r: float = outer_r * 0.09
	var eye_color := Color(0.15, 0.18, 0.22, 0.95)
	draw_circle(Vector2(center.x - eye_dx, eye_y), eye_r, eye_color)
	draw_circle(Vector2(center.x + eye_dx, eye_y), eye_r, eye_color)
	# Mund — ein sehr flacher Bogen, gezeichnet als `draw_arc` mit
	# einer kleinen Linienstärke. Ein Smile ohne Übertreibung; die
	# Neutralität erlaubt es State-Tints, die Stimmung zu tragen.
	var mouth_center: Vector2 = center + Vector2(0, outer_r * 0.28)
	var mouth_r: float = outer_r * 0.26
	var mouth_color := Color(0.25, 0.20, 0.18, 0.90)
	# Arc-Winkel in Radian: unterer Halbkreis-Ausschnitt. Godot
	# zeichnet `draw_arc` standardmäßig gegen den Uhrzeigersinn vom
	# Start- zum Endwinkel; ein Bereich von 0.15π bis 0.85π auf einer
	# abwärts zeigenden Ringachse liefert ein sanftes Lächeln.
	draw_arc(
		mouth_center,
		mouth_r,
		deg_to_rad(20.0),
		deg_to_rad(160.0),
		24,
		mouth_color,
		minf(outer_r * 0.05, 3.0),
	)
