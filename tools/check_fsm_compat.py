from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
api = ROOT / "scripts" / "CCOIntegrationApi.lua"
moddesc = ROOT / "modDesc.xml"

required_api_tokens = [
    'API_VERSION = "1.2"',
    'cropControlOverrideIntegration',
    'buildNpcMapRegenerationPlan',
    'confirmNpcMapRegeneration',
    'updateNpcMapRegeneration',
    'getActiveContractCount',
    'getContractBoardSummary',
    'getNpcMapRegenerationEquivalence',
    'startNpcMapRegeneration',
    'getNpcMapRegenerationStatus',
]

errors = []
if not api.exists():
    errors.append("missing scripts/CCOIntegrationApi.lua")
else:
    text = api.read_text(encoding="utf-8")
    for token in required_api_tokens:
        if token not in text:
            errors.append(f"missing API token: {token}")

if not moddesc.exists():
    errors.append("missing modDesc.xml")
else:
    text = moddesc.read_text(encoding="utf-8")
    if 'scripts/CCOIntegrationApi.lua' not in text:
        errors.append("modDesc does not load scripts/CCOIntegrationApi.lua")
    try:
        host_pos = text.index('scripts/CropControlOverride.lua')
        api_pos = text.index('scripts/CCOIntegrationApi.lua')
        if api_pos < host_pos:
            errors.append("CCOIntegrationApi loads before CropControlOverride host")
    except ValueError:
        pass

if errors:
    print("FSM compatibility audit: FAIL")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("FSM compatibility audit: PASS")
