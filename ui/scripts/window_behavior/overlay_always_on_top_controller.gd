extends RefCounted
## Linux Window Behavior — X11-only Always-on-top Sonderpfad (opt-in)
##
## Kleiner, bewusst eng geschnittener Sonderpfad, der unter **X11**
## (und *nur* dort) `DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP = true`
## setzt, wenn der Nutzer das explizit anfragt. Unter Wayland/GNOME
## (Ziel-Session laut `linux_window_overlay_architecture.md`) tut der
## Pfad bewusst **nichts** — das ist die in
## `docs/linux_always_on_top_decision.md` getroffene Entscheidung.
##
## Dieser Controller ist **nicht** Teil des Overlay-MVPs und **nicht**
## Teil des Click-through-Folgeschritts. Always-on-top ist ein eigenes
## Opt-in; es wird niemals stiller Nebeneffekt der beiden anderen
## Pfade.
##
## Was der Pfad im Erfolgsfall tut (nur wenn alle Gates erfüllt sind):
##   * `DisplayServer.window_set_flag(WINDOW_FLAG_ALWAYS_ON_TOP, true)`
##   * Flag zurücklesen, dokumentieren.
##   * Einen ehrlichen Log-Block ausgeben (`requested / session /
##     candidate / applied / observed / active / reason`).
##
## Was er bewusst **nicht** tut:
##   * Kein produktiver Pfad unter Wayland/GNOME — das Capability-
##     Modul markiert ihn dort als `unsupported`; dieser Controller
##     respektiert das.
##   * Keine GNOME-Shell-Extension, kein layer-shell, keine GDExtension.
##   * Keine neue IPC-Nachricht, keine EventBus-Erweiterung, keine
##     Scene-Änderung, keine neue Presence-Wahrheit.
##   * Keine Überversprechung: „Flag accepted by API" ist *nicht* eine
##     „user-visible guarantee". Selbst unter X11 hängt das sichtbare
##     Stacking-Verhalten vom Window-Manager ab — wir loggen ehrlich,
##     welche Tatsache wir gerade beobachtet haben, und verkaufen sie
##     nicht als Feature-Zusage.
##   * Kein Revert beim Verlassen der App — Godot räumt beim
##     Window-Close selbst auf. Wer das Flag zur Laufzeit wieder
##     ausschalten will, tut das über Godot-API, nicht über diesen
##     Controller.
##
## Aktivierungsregeln (alles UND-verknüpft):
##   1. `SMOLIT_UI_ALWAYS_ON_TOP=1` (eigenes, separates Opt-in).
##   2. `session_type == "x11"` — Wayland, XWayland-Grauzone und
##      „unknown" fallen explizit raus.
##   3. `display_driver != "headless"` — Headless ist kein
##      aussagekräftiger Ort für AOT.
##   4. Godot kennt `WINDOW_FLAG_ALWAYS_ON_TOP` (Capability).
##   5. Capability-Status für Always-on-top == `available`.
##
## Fehlschlag in einem der Punkte ⇒ kein-op mit ehrlichem `reason` im
## Log.

class_name SmolitOverlayAlwaysOnTopController

const _CapabilitiesRef := preload("res://scripts/window_behavior/window_capabilities.gd")

const ENABLE_ENV_VAR: String = "SMOLIT_UI_ALWAYS_ON_TOP"


static func is_requested() -> bool:
	var raw := OS.get_environment(ENABLE_ENV_VAR).strip_edges().to_lower()
	return raw == "1" or raw == "true" or raw == "yes"


## Call-site aus `main.gd::_ready()`, **unabhängig** von Overlay/
## Click-through. Rückgabe: Statusreport als Dictionary, analog zu den
## anderen Controllern. Der Controller selbst hält keinen State, braucht
## keine Subscriptions und wird nach dem Aufruf freigegeben — AOT ist
## ein Flag, keine Laufzeitbeobachtung.
static func activate_if_requested(anchor: Node) -> Dictionary:
	var requested := is_requested()

	var summary := {
		"requested": requested,
		"session_type": "",
		"display_driver": "",
		"capability_status": "",
		"capability_reason": "",
		"candidate": false,
		"applied": false,
		"observed": false,
		"active": false,
		"reason": "",
	}

	if not requested:
		summary["reason"] = "always-on-top not requested (SMOLIT_UI_ALWAYS_ON_TOP unset)"
		_log_summary(summary)
		return summary

	var capabilities: Dictionary = _CapabilitiesRef.detect()
	var session: String = str(capabilities.get("session_type", "unknown"))
	var driver: String = str(capabilities.get("display_driver", "unknown"))
	summary["session_type"] = session
	summary["display_driver"] = driver

	var cap: Dictionary = capabilities.get("always_on_top", {})
	var cap_status: int = int(cap.get("status", _CapabilitiesRef.Status.UNKNOWN))
	var cap_reason: String = str(cap.get("reason", ""))
	summary["capability_status"] = _CapabilitiesRef.name_of_status(cap_status)
	summary["capability_reason"] = cap_reason

	# Gate 1: X11-only. Wayland/GNOME bleibt ausdrücklich ohne AOT-
	# Versprechen (siehe docs/linux_always_on_top_decision.md).
	if session != "x11":
		summary["reason"] = "always-on-top special path is X11-only; current session=%s — no-op by design (see docs/linux_always_on_top_decision.md)" % session
		_log_summary(summary)
		return summary

	# Gate 2: kein sinnvoller AOT-Lauf unter Headless — das Ergebnis
	# wäre nicht aussagekräftig, und produktiv ist ohnehin irrelevant.
	if driver == "headless":
		summary["reason"] = "display_driver=headless — AOT not applied (headless does not reflect real WM stacking)"
		_log_summary(summary)
		return summary

	# Gate 3: Capability-Status muss `available` sein. Unter X11 ist das
	# laut `window_capabilities.gd` der Normalfall; hier zur Sicherheit
	# nochmal lokal verifiziert, damit eine spätere Capability-Änderung
	# nicht still zum Promise wird.
	if cap_status != _CapabilitiesRef.Status.AVAILABLE:
		summary["reason"] = "always-on-top capability not available on this session (status=%s) — %s" % [
			_CapabilitiesRef.name_of_status(cap_status),
			cap_reason,
		]
		_log_summary(summary)
		return summary

	# Gate 4: Godot muss das Flag kennen. In Godot 4.x üblich, aber
	# belt+suspenders.
	if not _godot_knows_flag("WINDOW_FLAG_ALWAYS_ON_TOP"):
		summary["reason"] = "WINDOW_FLAG_ALWAYS_ON_TOP not known to this Godot build"
		_log_summary(summary)
		return summary

	summary["candidate"] = true

	# Flag setzen, zurücklesen. Das sagt uns, *dass* Godot den Wunsch
	# angenommen hat — nicht, dass der WM dauerhaft stacked. Der Log-
	# Text ist dementsprechend vorsichtig formuliert.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	var observed: bool = DisplayServer.window_get_flag(
		DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP
	)
	summary["applied"] = true
	summary["observed"] = observed
	summary["active"] = observed
	if observed:
		summary["reason"] = "X11 WMs typically honour _NET_WM_STATE_ABOVE — behaviour still depends on the specific WM, not a universal guarantee"
	else:
		summary["reason"] = "flag write did not stick on read-back — Godot/WM rejected the request; no AOT active"
		summary["active"] = false

	# Anchor wird aktuell nicht genutzt (AOT ist fensterweit), aber die
	# Signatur bleibt symmetrisch zu den anderen Controllern, falls
	# später pro-Fenster-Logik dazukommt.
	if anchor == null:
		# Kein Fehler — wir brauchen den Anchor nicht, aber wir
		# dokumentieren den Fall im Log.
		pass

	_log_summary(summary)
	return summary


# --- Logging -------------------------------------------------------------


static func _log_summary(summary: Dictionary) -> void:
	print(
		"[always-on-top] requested=%s session=%s driver=%s candidate=%s applied=%s observed=%s active=%s"
		% [
			bool(summary.get("requested", false)),
			str(summary.get("session_type", "")),
			str(summary.get("display_driver", "")),
			bool(summary.get("candidate", false)),
			bool(summary.get("applied", false)),
			bool(summary.get("observed", false)),
			bool(summary.get("active", false)),
		]
	)
	var cap_status: String = str(summary.get("capability_status", ""))
	if cap_status != "":
		print(
			"[always-on-top] capability=%s (%s)"
			% [cap_status, str(summary.get("capability_reason", ""))]
		)
	var reason: String = str(summary.get("reason", ""))
	if reason != "":
		print("[always-on-top] reason: %s" % reason)
	# Immer die Einordnung dazu, damit kein Log-Leser den positiven
	# `active=true`-Fall als allgemeines Produktversprechen missversteht.
	if bool(summary.get("active", false)):
		print("[always-on-top] note: X11-only special path; Wayland/GNOME intentionally not targeted here (see docs/linux_always_on_top_decision.md)")


# --- helpers -------------------------------------------------------------


static func _godot_knows_flag(flag_name: String) -> bool:
	if not ClassDB.class_exists("DisplayServer"):
		return false
	for constant_name in ClassDB.class_get_integer_constant_list("DisplayServer"):
		if constant_name == flag_name:
			return true
	return false
