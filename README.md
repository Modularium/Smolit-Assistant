# Smolit Assistant

Smolit Assistant ist als leichtgewichtiger, always-on Hintergrunddienst aufgebaut. Der Fokus dieses Bootstraps liegt auf einem sauberen Rust-Core, einer klar getrennten Adapter-Schicht und einer minimalen CLI, die Eingaben an ABrain weiterreicht.

## Struktur

```text
smolit-assistant/
├── core/                  # Rust daemon
├── ui/                    # Platzhalter für spätere Godot-UI
├── adapters/
│   ├── abrain/
│   └── adminbot/
├── config/
├── docs/
├── scripts/
├── .env.example
├── README.md
└── ROADMAP.md
```

## Setup

ABrain muss lokal verfügbar sein. Standardmäßig wird der Befehl `abrain` verwendet.

Optionale Konfiguration über `.env` im Repo-Root:

```env
ABRAIN_CMD=abrain
LOG_LEVEL=info
```

## Run

```bash
cd core
cargo run
```

Nach dem Start:

```text
Smolit ready.
> hello
[ABrain Antwort]
> exit
```
