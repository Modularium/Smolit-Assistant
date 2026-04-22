extends "res://scripts/window_behavior/backend_base.gd"
## Linux Window Behavior — Noop-Backend (first-class Fallback)
##
## Erster-Klasse-Pfad für Sessions, bei denen Smolit aus Client-Sicht
## nicht belastbar entscheiden kann, welches Plattformverhalten
## realistisch ist: `session_type == "unknown"`, oder Umgebungen, in
## denen weder `DISPLAY` noch `WAYLAND_DISPLAY` noch `XDG_SESSION_TYPE`
## eine klare Aussage liefern (CI-Container, Remote-Terminals,
## exotische Setups).
##
## Zweck:
##   * Der Pfad `unsupported / unknown / refused / no-op` hat jetzt
##     einen benannten Platz im Backend-Modell. Die bisherige Logik,
##     dass jeder Aktivierungspfad selbst mit einem ehrlichen Refusal-
##     Dict zurückkommt, bleibt unverändert — die Kontroller-Gates
##     sind nach wie vor die verbindliche Stelle.
##   * `backend_id = "noop"` ist für den Runtime-Report ein klares
##     Signal: Smolit ist an einer Stelle gelandet, an der es
##     bewusst nichts anfasst.
##
## Wichtig:
##   * Dieses Backend delegiert absichtlich an die existierenden
##     Controller. Die Controller liefern in `unknown`- bzw.
##     `unsupported`-Fällen bereits sauber strukturierte Refusal-
##     Dicts inklusive `reason`. Ein separater Short-Circuit hier
##     würde doppelte Wahrheit einführen — das vermeiden wir
##     ausdrücklich (siehe Basisklasse: „Default-Verhalten ist
##     gleichwertig zum vorherigen Direktaufruf").

class_name SmolitWindowBackendNoop


func _init() -> void:
	backend_id = "noop"
	backend_description = "unknown / non-classifiable session — all activation paths will refuse via their own capability gates"
