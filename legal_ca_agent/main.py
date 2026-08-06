"""Entry point for the separate Legal and CA agent."""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

if __name__ == "__main__":
    venv_adk = PROJECT_ROOT / ".venv" / "Scripts" / "adk.exe"
    try:
        from legal_ca_agent.agent import root_agent  
        print("Legal CA agent is configured.")
    except ModuleNotFoundError as exc:
        print(f"Missing module: {exc}")
        print("Use the project virtual environment to run ADK web:")
    print("Run ADK web from project root with this command:")
    print(f'  & "{venv_adk}" web "{PROJECT_ROOT}" --port 8004')
