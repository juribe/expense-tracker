#!/usr/bin/env python3
"""Analyzer for the 500-case expense parser benchmark.

Builds ground truth from the benchmark document's regular structure plus
explicit overrides for self-corrections, multipliers, transfers, and the
complex composites. Applies the project rules where they differ from the
document: bare "Davibank" must resolve WITH a review flag (never silently),
refunds must stay at the full price and be flagged, and phrase-less entries
default to today.
"""
import json
import re
import unicodedata
from datetime import date, timedelta
from pathlib import Path

MD = Path("/Users/joseuribe/Downloads/expense_parser_500_case_benchmark.md")
RESULTS = Path(__file__).parent / "benchmark_500_results.json"

TODAY = date(2026, 9, 26)
CUENTA, TARJETA, EFECTIVO = "cuenta davibank", "tarjeta davibank", "efectivo"

FOOD = {"Restaurante", "Restaurants", "Comida"}
GROCERIES = {"Comida", "Hogar", "Supermercado"}
TRANSPORTE = {"Transporte"}
PARKING = {"Parking", "Transporte"}
SERVICIOS = {"Servicios públicos"}
ENTRETENIMIENTO = {"Entretenimiento", "Servicios públicos", "Streaming"}
SALUD = {"Salud"}
EDUCACION = {"Educación"}
VIAJES = {"Viajes", "Alojamiento"}
OPEN = None  # no confident default category; present-only check

ITEM_CATEGORY = {
    "almuerzo": FOOD, "desayuno": FOOD, "cena": FOOD, "café": FOOD, "cafe": FOOD,
    "restaurante": FOOD, "didi food": TRANSPORTE | FOOD, "didi": TRANSPORTE | FOOD,
    "food": FOOD, "hamburguesas": FOOD,
    "pizzas": FOOD, "gaseosa": FOOD, "gaseosas": FOOD, "comida": FOOD,
    "mercado": GROCERIES, "supermercado": GROCERIES,
    "gasolina": TRANSPORTE, "taxi": TRANSPORTE, "taxis": TRANSPORTE, "pasaje": TRANSPORTE,
    "parqueadero": PARKING,
    "internet": SERVICIOS | {"Internet", "Hogar"}, "celular": SERVICIOS | {"Electrónica"},
    "netflix": ENTRETENIMIENTO, "spotify": ENTRETENIMIENTO, "hbo": ENTRETENIMIENTO,
    "cine": ENTRETENIMIENTO, "entradas": ENTRETENIMIENTO,
    "farmacia": SALUD, "medicinas": SALUD, "consulta médica": SALUD,
    "consulta": SALUD, "medica": SALUD,
    "curso": EDUCACION, "libro": EDUCACION,
    "hotel": VIAJES, "vuelo": VIAJES,
    "camisa": OPEN, "zapatos": OPEN, "ropa": OPEN, "camisetas": OPEN,
}

STOPWORDS = {
    "hoy", "ayer", "anteayer", "gaste", "gasté", "pague", "pagué", "compre", "compré",
    "con", "de", "del", "en", "la", "las", "el", "los", "mi", "mis", "y", "o", "usando",
    "usé", "use", "un", "una", "unos", "unas", "todo", "todos", "todo", "para", "por",
    "cuenta", "tarjeta", "davibank", "efectivo", "crédito", "credito", "desde",
    "tambien", "también", "después", "despues", "luego", "bueno", "perdon", "perdón",
    "fueron", "aunque", "menos", "porque", "también",
}

def norm(s):
    return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()

def parse_md_cases():
    cases = {}
    for line in MD.read_text().splitlines():
        m = re.match(r"^\s*(\d+)\.\s+`(.+?)`\s*$", line)
        if m:
            cases[int(m.group(1))] = m.group(2)
    assert len(cases) == 500, len(cases)
    return cases

def amounts_in(text):
    found = []
    for m in re.finditer(r"\b\d{1,3}(?:\.\d{3})+\b|\b\d{4,6}\b", text):
        found.append(int(m.group(0).replace(".", "")))
    return found

def source_classes_in(text):
    """Ordered money-source clauses: tarjeta/cuenta/explicit/bare/efectivo."""
    t = norm(text)
    out = []
    for m in re.finditer(r"davibank", t):
        prefix = t[max(0, m.start() - 24):m.start()]
        if re.search(r"tarjeta(\s+de\s+credito)?(\s+de)?\s+(la|mi|el)?\s*$", prefix):
            out.append((m.start(), "tarjeta"))
        elif re.search(r"cuenta(\s+de\s+ahorros)?(\s+de)?\s+(la|mi|el)?\s*$", prefix):
            out.append((m.start(), "cuenta"))
        else:
            out.append((m.start(), "review"))
    for m in re.finditer(r"\befectivo\b", t):
        out.append((m.start(), "efectivo"))
    out.sort()
    return [cls for _, cls in out]

def date_class_in(text):
    t = norm(text)
    if t.startswith("hoy "): return "hoy"
    if t.startswith("ayer "): return "ayer"
    if t.startswith("anteayer "): return "anteayer"
    for day in ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]:
        if re.match(rf"^el {day} ", t): return f"weekday:{day}"
    if t.startswith("la semana pasada "): return "semana_pasada"
    if t.startswith("el mes pasado "): return "mes_pasado"
    return None

WEEKDAYS = {"lunes": 0, "martes": 1, "miercoles": 2, "jueves": 3, "viernes": 4, "sabado": 5, "domingo": 6}

def date_window(cls):
    if cls == "hoy": return {TODAY}
    if cls == "ayer": return {TODAY - timedelta(days=1)}
    if cls == "anteayer": return {TODAY - timedelta(days=2)}
    if cls == "semana_pasada": return {TODAY - timedelta(days=d) for d in range(7, 14)}
    if cls == "mes_pasado": return {d for d in (TODAY - timedelta(days=n) for n in range(1, 60)) if d.month != TODAY.month}
    if cls and cls.startswith("weekday:"):
        wd = WEEKDAYS[cls.split(":", 1)[1]]
        return {TODAY - timedelta(days=d) for d in range(1, 8) if (TODAY - timedelta(days=d)).weekday() == wd}
    return {TODAY}

def item_keywords(text):
    t = norm(text)
    t = re.sub(r"\b\d{1,3}(?:\.\d{3})+\b|\b\d{4,6}\b", " ", t)
    words = [w for w in re.findall(r"[a-zñ]+", t) if w not in {norm(s) for s in STOPWORDS}]
    return set(words)

def E(amount, source, source_name=None, date_cls=None, item=None, refund=False):
    return {"amount": amount, "source": source, "source_name": source_name or source,
            "date_cls": date_cls, "item": item, "refund": refund}

# --- Overrides: corrections / refunds (unique texts) -------------------------
CORRECTIONS = {
    "Compré zapatos por 180.000, bueno, fueron 160.000.": [E(160000, "none", item="zapatos")],
    "Almuerzo 70.000, perdón, 65.000.": [E(65000, "none", item="almuerzo")],
    "Pagué 120.000 de internet, en realidad fueron 110.000.": [E(110000, "none", item="internet")],
    "Gasté 50.000 en comida, no, fueron 55.000.": [E(55000, "none", item="comida")],
    "Compré una camisa por 200.000, aunque fueron 180.000 con descuento.": [E(180000, "none", item="camisa", refund=True)],
    "Taxi 30.000, bueno, 28.000.": [E(28000, "none", item="taxi")],
    "El mercado costó 300.000, pero me devolvieron 20.000.": [E(300000, "none", item="mercado", refund=True)],
    "Restaurante 100.000, menos 15.000 de descuento.": [E(100000, "none", item="restaurante", refund=True)],
    "Compré zapatos por 250.000 y después me devolvieron 50.000.": [E(250000, "none", item="zapatos", refund=True)],
    "Pagué 80.000 de comida; revisando el recibo fueron 76.500.": [E(76500, "none", item="comida")],
}

MULTIPLIERS = {
    "Tres cafés de 8.500 cada uno.": [E(25500, "none", item="cafés")],
    "Dos hamburguesas de 25.000 y una gaseosa de 8.000.": [E(50000, "none", item="hamburguesas"), E(8000, "none", item="gaseosa")],
    "Compré 4 cafés a 7.000 cada uno.": [E(28000, "none", item="cafés")],
    "Tres almuerzos de 35.000 cada uno.": [E(105000, "none", item="almuerzos")],
    "Dos entradas al cine de 25.000 cada una.": [E(50000, "none", item="cine")],
    "Dos taxis de 18.000 cada uno.": [E(36000, "none", item="taxis")],
    "Tres camisetas de 40.000 cada una.": [E(120000, "none", item="camisetas")],
    "Cuatro personas comimos a 35.000 cada una.": [E(140000, "none", item="personas")],
    "Dos pizzas de 45.000 y tres gaseosas de 6.000.": [E(90000, "none", item="pizzas"), E(18000, "none", item="gaseosas")],
    "Cinco cafés de 9.000 cada uno.": [E(45000, "none", item="cafés")],
}

TRANSFERS = {
    "Pasé 500.000 de Davibank a Nequi.": [E(500000, "review", item="nequi")],
    "Pasé 500.000 desde mi cuenta Davibank a Nequi.": [E(500000, "cuenta", CUENTA, item="nequi")],
    "Pasé 500.000 desde la tarjeta Davibank a otra cuenta.": [E(500000, "tarjeta", TARJETA, item="cuenta")],
    "Transferí 300.000 de Davibank a mi cuenta de ahorros.": [E(300000, "review", item="ahorros")],
    "Moví 200.000 de Davibank a Nequi.": [E(200000, "review", item="nequi")],
    "Recargué Nequi con 150.000 desde mi cuenta Davibank.": [E(150000, "cuenta", CUENTA, item="nequi")],
    "Le transferí 100.000 a mi esposa desde Davibank.": [E(100000, "review", item="esposa")],
    "Pasé 80.000 de Davibank a Nequi y después gasté 30.000 en comida.": [E(80000, "review", item="nequi"), E(30000, "none", item="comida")],
    "Transferí 500.000 desde mi cuenta Davibank y después pagué 70.000 de restaurante con la tarjeta Davibank.": [E(500000, "cuenta", CUENTA, item="cuenta"), E(70000, "tarjeta", TARJETA, item="restaurante")],
    "Pasé 300.000 de Davibank a Nequi, gasté 50.000 en comida y luego pasé otros 100.000.": [E(300000, "review", item="nequi"), E(50000, "none", item="comida"), E(100000, "review", item="nequi")],
}

COMPLEX = {
    "Ayer salí con mi esposa: pagué 85.000 del restaurante con Davibank, 18.000 del parqueadero en efectivo y compré medicinas por 42.500 con la cuenta Davibank. También pasé 200.000 de Davibank a Nequi.": [E(85000, "review", date_cls="ayer", item="restaurante"), E(18000, "efectivo", EFECTIVO, "ayer", "parqueadero"), E(42500, "cuenta", CUENTA, "ayer", "medicinas"), E(200000, "review", date_cls="ayer", item="nequi")],
    "Hoy compré mercado por 180.000 con la tarjeta Davibank, pagué 35.000 de taxi en efectivo y almorcé por 65.000 con la cuenta Davibank.": [E(180000, "tarjeta", TARJETA, "hoy", "mercado"), E(35000, "efectivo", EFECTIVO, "hoy", "taxi"), E(65000, "cuenta", CUENTA, "hoy", "almorcé")],
    "El sábado gasté 120.000 en restaurante, 20.000 de parqueadero y 15.000 en café. El restaurante lo pagué con la cuenta Davibank y lo demás en efectivo.": [E(120000, "cuenta", CUENTA, "weekday:sabado", "restaurante"), E(20000, "efectivo", EFECTIVO, "weekday:sabado", "parqueadero"), E(15000, "efectivo", EFECTIVO, "weekday:sabado", "café")],
    "Ayer pagué Netflix 38.900 con la tarjeta Davibank, Spotify 24.900 con Davibank y HBO 29.900 con la cuenta Davibank.": [E(38900, "tarjeta", TARJETA, "ayer", "netflix"), E(24900, "review", date_cls="ayer", item="spotify"), E(29900, "cuenta", CUENTA, "ayer", "hbo")],
    "El lunes pasé 500.000 de Davibank a Nequi, gasté 80.000 en supermercado con la cuenta Davibank y después 35.000 en Didi Food con la tarjeta Davibank.": [E(500000, "review", date_cls="weekday:lunes", item="nequi"), E(80000, "cuenta", CUENTA, "weekday:lunes", "supermercado"), E(35000, "tarjeta", TARJETA, "weekday:lunes", "didi food")],
    "Compré tres cafés de 8.500, un almuerzo de 45.000 y después pagué 15.000 de parqueadero, todo con Davibank.": [E(25500, "review", item="cafés"), E(45000, "review", item="almuerzo"), E(15000, "review", item="parqueadero")],
    "El viernes gasté 150.000 en ropa con la tarjeta Davibank, 80.000 en comida con la cuenta Davibank y 20.000 en taxi en efectivo.": [E(150000, "tarjeta", TARJETA, "weekday:viernes", "ropa"), E(80000, "cuenta", CUENTA, "weekday:viernes", "comida"), E(20000, "efectivo", EFECTIVO, "weekday:viernes", "taxi")],
    "Compré mercado por 200.000 con Davibank, pero me devolvieron 30.000 de unos productos. También pagué 45.000 de almuerzo con la tarjeta Davibank.": [E(200000, "review", item="mercado", refund=True), E(45000, "tarjeta", TARJETA, item="almuerzo")],
    "Ayer gasté 100.000 en comida con Davibank, bueno 90.000 porque nos hicieron descuento, y 25.000 de parqueadero con la cuenta Davibank. Hoy pasé 300.000 de Davibank a Nequi.": [E(90000, "review", date_cls="ayer", item="comida", refund=True), E(25000, "cuenta", CUENTA, "ayer", "parqueadero"), E(300000, "review", date_cls="hoy", item="nequi")],
    "Ayer salí con mi familia: desayuno 45.000, tres almuerzos de 38.000 cada uno, dos cafés de 9.000 cada uno y parqueadero 18.000. El desayuno y los almuerzos los pagué con la cuenta Davibank, los cafés con efectivo y el parqueadero con la tarjeta Davibank. Además pasé 500.000 de Davibank a Nequi.": [E(45000, "cuenta", CUENTA, "ayer", "desayuno"), E(114000, "cuenta", CUENTA, "ayer", "almuerzos"), E(18000, "efectivo", EFECTIVO, "ayer", "cafés"), E(18000, "tarjeta", TARJETA, "ayer", "parqueadero"), E(500000, "review", date_cls="ayer", item="nequi")],
}

OVERRIDES = {}
for d in (CORRECTIONS, MULTIPLIERS, TRANSFERS, COMPLEX):
    OVERRIDES.update(d)

def ground_truth(text):
    if text in OVERRIDES:
        return OVERRIDES[text]
    amounts = amounts_in(text)
    classes = source_classes_in(text)
    date_cls = date_class_in(text)
    kws = item_keywords(text)
    if not classes:
        classes = ["none"] * len(amounts)
    if len(classes) != len(amounts):
        return {"unmapped": True, "amounts": amounts, "classes": classes}
    # Generic cases: item is checked case-level (keyword set + accepted
    # category union), because splitting items positionally is unreliable.
    return [E(a, c, dict(zip(("cuenta", "tarjeta", "efectivo"), (CUENTA, TARJETA, EFECTIVO))).get(c, c), date_cls, None) for a, c in zip(amounts, classes)]

def has_review_flag(expense):
    flags = [w for w in expense.get("warnings", []) if "tight match" in w or "review" in w.lower()]
    return expense.get("money_source_source") == "suggested" or bool(flags)

def warn_has(warnings, needle):
    return any(needle in w.lower() for w in warnings)

def evaluate(case_no, text, row, gt):
    fail_stages = set()
    notes = []

    if not row.get("ok"):
        fail_stages.add("extraction")
        return fail_stages, notes, "error"

    extracted = row.get("expenses", [])
    if isinstance(gt, dict) and gt.get("unmapped"):
        notes.append("UNMAPPED-GROUND-TRUTH")
        return {"other"}, notes, "unmapped"

    # extraction: count and amounts
    extracted_amounts = [e.get("amount") or 0 for e in extracted]
    expected_amounts = [g["amount"] for g in gt]
    exp_sorted, got_sorted = sorted(expected_amounts), sorted(extracted_amounts)
    missing = extra = 0
    ea, ga = list(exp_sorted), list(got_sorted)
    for a in list(ea):
        if a in ga: ga.remove(a); ea.remove(a)
    missing, extra = len(ea), len(ga)

    # Our merge rule takes precedence over the document: several expenses of
    # the same category may arrive as one candidate when the summed total is
    # consistent with the itemized amounts (same purchase). That is a
    # tracked "merged-ok" outcome, not a failure.
    merged_ok = (
        missing >= 1
        and len(extracted) < len(gt) and len(extracted) >= 1
        and sum(extracted_amounts) == sum(expected_amounts)
        and len({e.get("category_name") for e in extracted}) == 1
    )
    if merged_ok:
        notes.append(f"c{case_no}: merged-ok ({len(extracted)} expense, sum consistent)")
        return fail_stages, notes, None
    if missing or extra:
        fail_stages.add("multiple_expense_split" if missing and extra else ("extraction" if missing and not extracted_amounts else "multiple_expense_split"))
        if missing: fail_stages.add("extraction")
        if extra: fail_stages.add("multiple_expense_split")

    matched = {}
    for g in gt:
        best = None
        for i, e in enumerate(extracted):
            if i in matched: continue
            if (e.get("amount") or 0) == g["amount"]:
                best = i; break
        if best is None:
            continue
        matched[best] = g
        e = extracted[i]
        # money source
        sclass, sname = g["source"], g["source_name"]
        got_name, got_id = e.get("money_source_name"), e.get("money_source_id")
        flagged = e.get("money_source_source") == "suggested" or warn_has(e.get("warnings", []), "tight match")
        if sclass == "review":
            if not got_id:
                fail_stages.add("money_source"); notes.append(f"c{case_no}: source missing (expected review)")
            elif not flagged:
                fail_stages.add("ambiguity_resolution"); notes.append(f"c{case_no}: silent guess '{got_name}' (bare Davibank)")
        elif sclass == "none":
            if got_id:
                fail_stages.add("money_source"); notes.append(f"c{case_no}: unexpected source '{got_name}'")
        else:
            if not got_id:
                fail_stages.add("money_source"); notes.append(f"c{case_no}: source missing (expected {sname})")
            elif got_name != sname:
                fail_stages.add("money_source"); notes.append(f"c{case_no}: wrong source '{got_name}' != '{sname}'")
            elif flagged:
                notes.append(f"c{case_no}: correct source '{sname}' but flagged (minor)")
        # date
        want = date_window(g.get("date_cls"))
        try:
            d = date.fromisoformat(e["date"][:10]) if e.get("date") else None
        except Exception:
            d = None
        if d is None or d not in want:
            fail_stages.add("date"); notes.append(f"c{case_no}: date {d} not in {sorted(want)[:3]}")
        # category + description: per-item when known, case-level otherwise
        kw = norm(g.get("item")) if g.get("item") else None
        acc = ITEM_CATEGORY.get(kw) if kw else None
        if kw is None:
            kw_set = item_keywords(text)
            accs = [ITEM_CATEGORY[k] for k in kw_set if k in ITEM_CATEGORY and ITEM_CATEGORY[k] is not OPEN]
            # Any unmapped or open item allows categories outside the map:
            # fall back to a present-only check for the whole case.
            acc = set().union(*accs) if accs and len(accs) == len(kw_set) else OPEN
        cname = e.get("category_name")
        suggested = e.get("suggested_category_name")
        if acc is OPEN or acc is None:
            if cname is None and not suggested:
                fail_stages.add("category"); notes.append(f"c{case_no}: no category for {kw or 'item'}")
        else:
            if cname is None:
                if suggested: notes.append(f"c{case_no}: category suggested ({suggested}) for {kw or 'item'}")
                else: fail_stages.add("category"); notes.append(f"c{case_no}: no category for {kw or 'item'}")
            elif cname not in acc:
                fail_stages.add("category"); notes.append(f"c{case_no}: category '{cname}' not in {acc} for {kw or 'item'}")
        # description
        desc = norm(e.get("description") or "")
        if kw:
            if kw not in desc and not any(part in desc for part in kw.split()):
                fail_stages.add("description"); notes.append(f"c{case_no}: description '{e.get('description')}' lacks '{kw}'")
        else:
            kw_set = item_keywords(text)
            if kw_set and not any(k in desc for k in kw_set):
                fail_stages.add("description"); notes.append(f"c{case_no}: description '{e.get('description')}' lacks any of {sorted(kw_set)[:4]}")
        # refund
        if g.get("refund") and not warn_has(e.get("warnings", []), "refund"):
            fail_stages.add("ambiguity_resolution"); notes.append(f"c{case_no}: refund not flagged")
    return fail_stages, notes, None

def main():
    cases = parse_md_cases()
    rows = {r["case"]: r for r in json.load(open(RESULTS))}

    total_expected = total_extracted = 0
    passed = failed = 0
    stage_counts = {}
    notes_all = []
    ms = {"resolved": 0, "review_pass": 0, "review_fail": 0, "cuenta_ok": 0, "tarjeta_ok": 0,
          "cuenta_bad": 0, "tarjeta_bad": 0, "none_ok": 0, "none_bad": 0, "missing": 0}
    cat_failures = {}
    worst = []
    patterns = {}

    for no in sorted(cases):
        text = cases[no]
        row = rows.get(no)
        if row is None:
            continue
        gt = ground_truth(text)
        total_expected += len(gt) if not isinstance(gt, dict) else len(gt.get("amounts", []))
        total_extracted += len(row.get("expenses", [])) if row.get("ok") else 0

        stages, notes, unmapped = evaluate(no, text, row, gt)
        notes_all.extend(notes)

        if unmapped:
            patterns["unmapped-ground-truth"] = patterns.get("unmapped-ground-truth", 0) + 1
            failed += 1
            worst.append((no, text, "unmapped", notes))
            continue

        if not row.get("ok"):
            patterns["pipeline-error"] = patterns.get("pipeline-error", 0) + 1

        for s in stages:
            stage_counts[s] = stage_counts.get(s, 0) + 1
            patterns[s] = patterns.get(s, 0) + 1
        if stages:
            failed += 1
            worst.append((no, text, sorted(stages), notes))
        else:
            passed += 1

    print(f"=== OVERALL ===")
    print(f"cases evaluated: {passed + failed}")
    print(f"passed: {passed} ({100 * passed / (passed + failed):.1f}%)")
    print(f"failed: {failed}")
    print(f"expected expenses: {total_expected}, extracted: {total_extracted}, delta: {total_extracted - total_expected}")
    print()
    print("=== FIELD / STAGE FAILURES ===")
    for s, c in sorted(stage_counts.items(), key=lambda kv: -kv[1]):
        print(f"  {s}: {c}")
    print()
    print("=== FAILURE PATTERNS (top) ===")
    for p, c in sorted(patterns.items(), key=lambda kv: -kv[1])[:10]:
        print(f"  {p}: {c}")
    print()
    print("=== WORST 20 CASES ===")
    for no, text, stages, notes in worst[:20]:
        print(f"  case {no} [{','.join(map(str, stages))}] {text[:70]}")
        for n in notes[:3]:
            print(f"      - {n}")
    print()
    print("=== SAMPLE NOTES (first 40) ===")
    for n in notes_all[:40]:
        print(f"  {n}")

    json.dump({"passed": passed, "failed": failed,
               "stage_counts": stage_counts, "patterns": patterns, "worst": worst[:20]},
              open(Path(__file__).parent / "benchmark_500_analysis.json", "w"), indent=2, default=str)
    print("analysis -> script/experiments/benchmark_500_analysis.json")

if __name__ == "__main__":
    main()
