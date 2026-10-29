import json
import sys
import time
from datetime import date

sys.path.insert(0, "app/ai")
import agenda

# A fixed date, so two runs of different prompt versions can be compared.
TODAY = date(2026, 10, 27)
NO_USAGE = {"input_tokens": 0, "output_tokens": 0}

model = sys.argv[1] if len(sys.argv) > 1 else agenda.DEFAULT_MODEL
for n in range(1, 6):
    text = open(f"sample{n}.txt", encoding="utf-8").read()
    started = time.monotonic()
    try:
        parsed, usage = agenda.parse_agenda(text, TODAY, "Europe/Kyiv", model=model)
        out = json.dumps(parsed.model_dump(mode="json"), ensure_ascii=False)
    except Exception as e:
        out = f"ERROR {type(e).__name__}: {e}"
        usage = getattr(e, "usage", NO_USAGE)
    secs = time.monotonic() - started
    print(
        f"--- #{n} | {usage['input_tokens']} in / {usage['output_tokens']} out"
        f" | ${agenda.cost_usd(model, usage)} | {secs:.1f}s"
    )
    print(out)
