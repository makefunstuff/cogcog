# Hermes CogCog Skill

Connects Hermes to your Neovim session through the CogCog bridge module.
One Python file. No build step. No Node.js.

## Setup

```bash
pip install pynvim
```

Make sure Neovim is running with the socket:
```bash
nvim --listen /tmp/cogcog.sock
```

## Usage

```bash
python3 scripts/cogcog_bridge.py <tool> [json_args]

# Examples:
python3 scripts/cogcog_bridge.py status
python3 scripts/cogcog_bridge.py context
python3 scripts/cogcog_bridge.py buffer '{"path": "main.py"}'
python3 scripts/cogcog_bridge.py diagnostics
python3 scripts/cogcog_bridge.py goto '{"path": "main.py", "line": 42}'
python3 scripts/cogcog_bridge.py quickfix '{"items": [{"filename": "a.py", "lnum": 10, "text": "fix"}]}'
python3 scripts/cogcog_bridge.py exec '{"cmd": "write"}'
python3 scripts/cogcog_bridge.py notify '{"msg": "done"}'
```

See SKILL.md for full details.