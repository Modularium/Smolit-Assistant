extends Control
## Utterance-Bubble — read-only Presence-UI für `heard` / `response`.
##
## Phase-3.2-MVP der in `docs/ui_architecture.md` §8.4 / ROADMAP Phase
## 3.2 beschriebenen Speech-Bubble. Die Bubble konsumiert die
## bestehenden EventBus-Signale `heard_received` und `response_received`
## und zeigt das jeweils *aktuelle* Utterance an — sie ist bewusst kein
## Chat-, kein Log-, kein Transcript-Renderer.
##
## Bindende Grenzen:
##   * **Rein rendernd.** Keine IPC-Nachrichten, kein Protokoll-Eingriff,
##     keine Core-/ABrain-Kopplung.
##   * **Nur ein aktives Utterance.** Das nächste Event ersetzt den
##     bisherigen Inhalt; keine Historie, keine Scroll-Liste.
##   * **Keine Interaktion.** Mouse-Passthrough; keine Buttons, keine
##     Aktionen, keine Policy-Kopplung.
##   * **Leichtes Fallback.** Leere Texte blenden die Bubble stumm aus,
##     ohne Crash und ohne kaputte Restdarstellung.
##   * **Weicher TTS-Sync.** Seit PR 14 verlängert ein eintreffendes
##     `speaking_started` den Anzeige-Timer einmalig, solange aktuell
##     eine `response`-Bubble sichtbar ist — damit die Antwort nicht
##     ausfadet, während Smolit noch spricht. Kein Phonem-Stream, kein
##     Audio-Timing; `speaking_ended` lässt den normalen Display-Timer
##     zu Ende laufen.
##
## Lifecycle:
##   * Bubble startet unsichtbar. `heard`/`response` löst Fade-in +
##     Anzeige-Timer aus. Neuer Event während eines laufenden Timers
##     ersetzt Text und startet den Timer neu; keine Tween-Leichen.
##   * Timer-Ablauf triggert Fade-out. Nach Fade-out ist die Bubble
##     wieder unsichtbar und der interne Zustand `Kind.NONE`.
##   * `ipc_disconnected` räumt sofort auf (kein Stale-Utterance nach
##     Reconnect).

const _StateRef := preload("res://scripts/utterance/utterance_bubble_state.gd")


## Aktuelles Kind (None / Heard / Response) — Einzelslot, kein Stack.
var _current_kind: int = _StateRef.Kind.NONE

## Sichtbarer, bereits normalisierter Text (MAX_CHARS, Ellipsis,
## strip_edges). Nie roh — der Controller normalisiert einmal beim
## Setzen und merkt sich das Ergebnis.
var _current_text: String = ""

## Laufender Fade-Tween (eine einzige aktive Tween-Instanz, nicht zwei
## parallele). Wird bei jedem neuen Event sauber abgebrochen.
var _fade_tween: Tween = null

## Hide-Timer (Anzeige-Timeout). Kill-and-replace-Muster — wir halten
## genau *einen* Timer, nie mehrere konkurrierende.
var _hide_timer: Timer = null

## Logischer Schatten des Timer-Zustands. Wird `true`, sobald ein
## Anzeige-Zyklus angestoßen ist, und wieder `false`, wenn wir den
## Timer stoppen oder er abläuft. Unabhängig von `Timer.is_stopped()` /
## `time_left` gehalten, weil diese in einem SceneTree ohne laufende
## Frame-Schleife (Smoketest-Kontext) nicht zuverlässig populiert sind.
var _hide_scheduled: bool = false

@onready var _kind_chip: Label = $VBox/KindChip
@onready var _text_label: Label = $VBox/Text


func _ready() -> void:
	# Bubble selbst fängt keine Mauseingaben — sie ist Presence-UI, kein
	# Klickziel. Compact Input, Avatar und Banner bleiben unverändert
	# interaktiv.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _text_label != null:
		_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _kind_chip != null:
		_kind_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Initialer Zustand: unsichtbar, leer. Modulate.a=0 damit die erste
	# Fade-in-Tween nicht von einer halbsichtbaren Bubble aus startet.
	visible = false
	modulate.a = 0.0
	_render_current()

	_hide_timer = Timer.new()
	_hide_timer.one_shot = true
	_hide_timer.autostart = false
	add_child(_hide_timer)
	_hide_timer.timeout.connect(_on_hide_timeout)

	_connect_event_bus()


func _connect_event_bus() -> void:
	# Defensiv: wenn der Autoload fehlt (z. B. Scene als Standalone in
	# einem Smoketest), bleibt die Bubble still statt zu crashen.
	# Laufzeit-Lookup statt statischer Identifier-Auflösung, damit das
	# Script auch in SceneTree-Kontexten parsen kann, in denen der
	# EventBus-Autoload (noch) nicht registriert ist.
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("utterance_bubble: EventBus autoload not available; bubble stays hidden.")
		return
	if bus.has_signal("heard_received"):
		bus.heard_received.connect(_on_heard)
	if bus.has_signal("response_received"):
		bus.response_received.connect(_on_response)
	if bus.has_signal("ipc_disconnected"):
		bus.ipc_disconnected.connect(_on_ipc_disconnected)
	# PR 14 — optionaler TTS-Sync. Wenn der Autoload die neuen Signale
	# kennt, hängen wir uns an; ältere Cores schicken sie nicht, dann
	# bleibt die Bubble beim bisherigen Timer-Verhalten.
	if bus.has_signal("speaking_started_received"):
		bus.speaking_started_received.connect(_on_speaking_started)
	if bus.has_signal("speaking_ended_received"):
		bus.speaking_ended_received.connect(_on_speaking_ended)


# --- Event handlers ------------------------------------------------------


func _on_heard(text: String) -> void:
	set_utterance(_StateRef.Kind.HEARD, text)


func _on_response(text: String) -> void:
	set_utterance(_StateRef.Kind.RESPONSE, text)


func _on_ipc_disconnected() -> void:
	# Verbindung weg → aktuelles Utterance ist nicht mehr vertrauens-
	# würdig. Harter Reset ohne Fade-out, damit ein Reconnect mit einem
	# sauberen, leeren Zustand startet.
	clear_utterance()


func _on_speaking_started(_payload: Dictionary) -> void:
	# PR 14 — Wenn die Bubble gerade eine `response` zeigt und TTS
	# wirklich anläuft, setzen wir den Anzeige-Timer einmal zurück. So
	# liest der User die Antwort nicht weg, während sie noch gesprochen
	# wird. `heard`-Bubbles und leere Zustände lassen wir bewusst in
	# Ruhe — der `heard`-Timer markiert den STT-Moment, nicht die
	# Sprechdauer.
	if _current_kind != _StateRef.Kind.RESPONSE:
		return
	if _hide_timer == null:
		return
	_hide_timer.stop()
	_hide_timer.wait_time = max(0.1, _StateRef.display_seconds_for(_StateRef.Kind.RESPONSE))
	_hide_timer.start()
	_hide_scheduled = true


func _on_speaking_ended(_payload: Dictionary) -> void:
	# Bewusst leer: der normale Display-Timer läuft weiter und blendet
	# die Bubble regulär aus. Wir wollen nicht am Sprechende hart
	# abschneiden — das wäre ein harter UX-Knick.
	pass


# --- Öffentliche, test-freundliche API ----------------------------------


## Setzt den aktuellen Bubble-Inhalt deterministisch. Wird sowohl von
## den EventBus-Handlern als auch vom Smoketest aufgerufen.
##   * Leerer / whitespace-only Text → still ausblenden, kein Render.
##   * Nicht-leer → normalisieren, Text + Chip setzen, Fade-in starten,
##     Hide-Timer pro Kind-Dauer (re)starten.
func set_utterance(kind: int, raw_text: String) -> void:
	var normalized: String = _StateRef.normalize_text(raw_text)
	if not _StateRef.has_content(kind, normalized):
		clear_utterance()
		return

	_current_kind = kind
	_current_text = normalized
	_render_current()
	_begin_show_cycle(_StateRef.display_seconds_for(kind))


## Räumt den Bubble-Zustand ohne Fade sofort auf. Wird bei
## `ipc_disconnected` und bei „Eingabe ist leer" genutzt.
func clear_utterance() -> void:
	_kill_fade_tween()
	if _hide_timer != null:
		_hide_timer.stop()
	_hide_scheduled = false
	_current_kind = _StateRef.Kind.NONE
	_current_text = ""
	_render_current()
	visible = false
	modulate.a = 0.0


## Pure Introspektion für den Smoketest / Dev-Inspektion. Liefert den
## aktuell sichtbaren (oder zuletzt gesetzten) Inhalt — ohne Nebeneffekt.
func current_snapshot() -> Dictionary:
	return {
		"kind": _current_kind,
		"kind_name": _StateRef.kind_name(_current_kind),
		"text": _current_text,
		"visible": visible,
		"alpha": modulate.a,
		"timer_running": _hide_scheduled,
	}


# --- Intern: Rendering + Lifecycle --------------------------------------


func _render_current() -> void:
	if _text_label != null:
		_text_label.text = _current_text
	if _kind_chip != null:
		_kind_chip.text = _StateRef.chip_label_for(_current_kind)


func _begin_show_cycle(display_seconds: float) -> void:
	_kill_fade_tween()
	visible = true
	# Fade-in ab aktuellem Alpha — wenn schon sichtbar, ist das ein
	# weicher Refresh statt Re-Fade von 0.
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, _StateRef.FADE_IN_SECONDS)
	_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if _hide_timer != null:
		_hide_timer.stop()
		_hide_timer.wait_time = max(0.1, display_seconds)
		_hide_timer.start()
	_hide_scheduled = true


func _on_hide_timeout() -> void:
	# Nur ausblenden, wenn wir noch den Inhalt von damals zeigen;
	# zwischenzeitlich gestartete Cycles haben eigene Timer.
	if _current_kind == _StateRef.Kind.NONE:
		return
	_kill_fade_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, _StateRef.FADE_OUT_SECONDS)
	_fade_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_on_fade_out_finished)


func _on_fade_out_finished() -> void:
	# Tween-Leichen vermeiden: wenn in der Zwischenzeit ein neues
	# Utterance gesetzt wurde (alpha > 0 erreicht), ignorieren wir den
	# Abschluss der alten Fade-out-Sequenz.
	if modulate.a > 0.01:
		return
	visible = false
	_hide_scheduled = false
	_current_kind = _StateRef.Kind.NONE
	_current_text = ""
	_render_current()


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
