extends SceneTree
## Resolver-Klassifikations-Smoketest.
##
## Exerziert `ui/scripts/window_behavior/backend_resolver.gd` gegen
## neun synthetische Capability-Snapshots und vergleicht die
## tatsächlich zurückgelieferte `backend_id` gegen die erwartete.
## Exit-Code 0 bei allen Treffern, 1 sonst.
##
## Lauf:
##   godot --headless --path ui --script scripts/resolver_classification_smoke.gd
##
## Dokumentation / Einordnung:
##   * `docs/window_behavior_backend_verification.md`
##   * `docs/ui_architecture.md` §9.0 — interne Rollenverteilung
##
## Dieses Skript hat **keinen** produktiven Pfad, setzt keine Flags
## und öffnet kein Fenster. Es ist ein reiner Unit-ähnlicher Smoketest
## für die Klassifikation innerhalb des Resolvers.

const _ResolverRef := preload("res://scripts/window_behavior/backend_resolver.gd")


func _init() -> void:
	var cases := [
		{
			"label": "real X11 session (dev host pattern)",
			"caps": {"session_type": "x11", "display_driver": "x11", "desktop_environment": "ubuntu:GNOME"},
			"expect": "x11",
		},
		{
			"label": "X11 session, Godot headless driver",
			"caps": {"session_type": "x11", "display_driver": "headless", "desktop_environment": "ubuntu:GNOME"},
			"expect": "x11",
		},
		{
			"label": "Wayland/GNOME (Mutter) — native wayland driver",
			"caps": {"session_type": "wayland", "display_driver": "wayland", "desktop_environment": "ubuntu:GNOME"},
			"expect": "wayland-mutter",
		},
		{
			"label": "Wayland/GNOME — Godot headless driver (simulation)",
			"caps": {"session_type": "wayland", "display_driver": "headless", "desktop_environment": "ubuntu:GNOME"},
			"expect": "wayland-mutter",
		},
		{
			"label": "Wayland/Sway (wlroots family)",
			"caps": {"session_type": "wayland", "display_driver": "wayland", "desktop_environment": "sway"},
			"expect": "wayland-wlroots",
		},
		{
			"label": "Wayland/Hyprland (wlroots family)",
			"caps": {"session_type": "wayland", "display_driver": "wayland", "desktop_environment": "Hyprland"},
			"expect": "wayland-wlroots",
		},
		{
			"label": "Wayland/KDE (unknown family → generic fallback)",
			"caps": {"session_type": "wayland", "display_driver": "wayland", "desktop_environment": "KDE"},
			"expect": "wayland-generic",
		},
		{
			"label": "XWayland — Wayland session + X11 display driver",
			"caps": {"session_type": "wayland", "display_driver": "x11", "desktop_environment": "ubuntu:GNOME"},
			"expect": "xwayland",
		},
		{
			"label": "Unknown session_type → noop",
			"caps": {"session_type": "unknown", "display_driver": "headless", "desktop_environment": ""},
			"expect": "noop",
		},
	]
	var all_ok := true
	for case in cases:
		var backend: RefCounted = _ResolverRef.resolve(case["caps"])
		var got: String = backend.backend_id
		var want: String = case["expect"]
		var ok: bool = (got == want)
		all_ok = all_ok and ok
		print("%s  %s  expect=%s  got=%s" % [
			"PASS" if ok else "FAIL",
			case["label"],
			want,
			got,
		])
	print("---")
	print("overall: %s" % ("PASS" if all_ok else "FAIL"))
	quit(0 if all_ok else 1)
