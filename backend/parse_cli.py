import json
import sys
from datetime import date

sys.path.insert(0, "app/ai")  # import the module alone, without the rest of the app
import agenda

text = open(sys.argv[1], encoding="utf-8").read()
model = sys.argv[2] if len(sys.argv) > 2 else agenda.DEFAULT_MODEL
parsed, usage = agenda.parse_agenda(text, date.today(), "Europe/Kyiv", model=model)
print(json.dumps(parsed.model_dump(mode="json"), ensure_ascii=False, indent=2))
print(usage, "cost $", agenda.cost_usd(model, usage))
