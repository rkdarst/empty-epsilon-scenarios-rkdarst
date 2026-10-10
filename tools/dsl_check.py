#!/usr/bin/env python3
"""Schema/cross-reference checker for the EE mission DSL (schema v0.1).

Usage: tools/dsl_check.py dsl/samples/last-mile.yaml

Grammar parsing lives in tools/dsl_lang.py, shared with the Phase-2
generator (no parser drift, dsl/DESIGN.md). Checks: schema keys, entity/
archetype discipline, references, the dialog page/reply contract (incl.
`once:`), event grammar, tracker targets, and heuristic comms dead-ends.
Requires PyYAML (./tools/get_pyyaml.sh once on pip-less hosts).
"""
import ast
import itertools
import os
import re
import sys
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsl_lang as L

try:
    import yaml
except ImportError:
    _libs = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "..", "vendor", "pylibs")
    if os.path.isdir(_libs):
        sys.path.insert(1, _libs)
    try:
        import yaml
    except ImportError:
        sys.exit("PyYAML required: run ./tools/get_pyyaml.sh once, or "
                 "apt install python3-yaml")

TOP = {"version", "meta", "world", "items", "flags", "events", "dialogs",
       "stages", "outcomes", "scripts"}
KNOWN_TYPES = {"Basic", "Development", "Mission", "PvP", "Race",
               "Replayable Mission"}
SCOPES = {"world", "ship", "player"}
FIRE_MODES = {"once_when_ready", "retry_until_true"}


class Ctx:
    def __init__(self):
        self.errs, self.warns = [], []
        self.flags, self.opts, self.items = set(), {}, set()
        self.systems, self.ships, self.stations = set(), {}, {}
        self.archetypes, self.objects = set(), set()
        self.known = set()
        self.saw_victory_action = False

    def err(self, m):
        self.errs.append(m)

    def warn(self, m):
        self.warns.append(m)


def check_expr(src, path, ctx):
    try:
        tree = L.parse_expr(src)
    except SyntaxError as exc:
        ctx.err(f"{path}: unparsable expression {src!r}: {exc}")
        return None
    arg_names = {a for fn, args in L.calls(tree)
                 if fn in ("alive", "n_alive", "has") for a in args}
    for n in L.names_of(tree):
        if n in arg_names:
            continue    # ship/archetype/item refs; validated via calls() below
        if n not in ctx.known and n not in L.BUILTINS:
            ctx.err(f"{path}: unknown reference '{n}'")
    for p in sorted(L.attr_paths(tree)):
        root, field = p.split(".", 1)
        if root == "flags" and field not in ctx.flags:
            ctx.err(f"{path}: undeclared flag 'flags.{field}'")
        elif root == "options" and field not in ctx.opts:
            ctx.err(f"{path}: unknown option 'options.{field}'")
        elif root in ctx.stations and field not in (ctx.stations[root].get("fields") or {}):
            ctx.err(f"{path}: undeclared field '{root}.{field}'")
        elif root in ctx.ships:
            ctx.err(f"{path}: unknown attribute '{root}.{field}'")
    for oname, vals in L.option_comparisons(tree):
        allowed = [str(v) for v in ((ctx.opts.get(oname) or {}).get("values") or [])]
        for v in vals:
            if allowed and str(v) not in allowed:
                ctx.err(f"{path}: '{v}' is not a value of option '{oname}'")
    for fname, args in L.calls(tree):
        if fname not in L.FUNCS:
            ctx.err(f"{path}: unknown function {fname}()")
        elif fname == "alive" and len(args) == 1:
            if args[0] in ctx.archetypes:
                ctx.err(f"{path}: alive({args[0]}) on an archetype; use n_alive()")
            elif args[0] not in ctx.objects:
                ctx.err(f"{path}: alive({args[0]}): not an at-start object")
        elif fname == "n_alive" and len(args) == 1 and args[0] not in ctx.ships:
            ctx.err(f"{path}: n_alive({args[0]}): not a ship/archetype")
        elif fname == "has" and len(args) == 2:
            if args[0] not in ctx.ships:
                ctx.err(f"{path}: has(): '{args[0]}' is not a ship")
            if args[1] not in ctx.items:
                ctx.err(f"{path}: has(): '{args[1]}' is not an item")
    return tree


def check_action(text, path, ctx):
    a = L.parse_action(text)
    if a.get("cond"):
        check_expr(a["cond"], f"{path} [if]", ctx)
    k, args = a["kind"], a.get("args")
    if k in L.TEXT_ACTIONS:
        if k == "victory":
            ctx.saw_victory_action = True
        return
    if k == "set":
        target, val = args
        if target.startswith("flags."):
            if target[6:] not in ctx.flags:
                ctx.err(f"{path}: undeclared flag '{target}'")
        elif "." in target and target.split(".", 1)[0] in ctx.stations:
            root, field = target.split(".", 1)
            if field not in (ctx.stations[root].get("fields") or {}):
                ctx.err(f"{path}: undeclared field '{root}.{field}'")
        else:
            ctx.err(f"{path}: set target must be flags.X or <station>.<field>")
    elif k in ("give", "take"):
        ship, item = args
        if ship not in ctx.ships:
            ctx.err(f"{path}: '{ship}' is not a ship")
        if item not in ctx.items:
            ctx.err(f"{path}: '{item}' is not an item")
    elif k == "give_c":
        if args[0] not in ctx.ships:
            ctx.err(f"{path}: '{args[0]}' is not a ship")
    elif k == "pay":
        amt, ent = args
        if "." in amt:
            root, field = amt.split(".", 1)
            if root not in ctx.stations or field not in (ctx.stations[root].get("fields") or {}):
                ctx.err(f"{path}: pay source '{amt}' is not a declared field")
        elif not amt.isdigit():
            ctx.err(f"{path}: pay amount must be a number or entity.field")
        if ent not in ctx.objects:
            ctx.err(f"{path}: pay target '{ent}' is not a world object")
        else:
            ctx.warn(f"{path}: station accounts are not modelled; 'pay' moves "
                     "player credits only (dsl/DESIGN.md limitations)")
    elif k == "spawn":
        _, name, sysname, at = args
        if name not in ctx.ships:
            ctx.err(f"{path}: spawn target '{name}' is not a ship/archetype")
        elif name not in ctx.archetypes:
            ctx.warn(f"{path}: '{name}' is an at-start entity; spawning "
                     "duplicates it (declare at_start: false for archetypes)")
        if sysname not in ctx.systems:
            ctx.err(f"{path}: unknown system '{sysname}'")
        if at and at not in ctx.objects:
            ctx.err(f"{path}: spawn anchor '{at}' is not a world object")
    elif k == "warp":
        if args[0] not in ctx.ships:
            ctx.err(f"{path}: warp subject '{args[0]}' is not a ship")
        if args[1] not in ctx.systems:
            ctx.err(f"{path}: unknown system '{args[1]}'")
    else:
        ctx.err(f"{path}: unrecognized action {a.get('raw', '')!r}")


def and_terms(node):
    if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
        return [t for v in node.values for t in and_terms(v)]
    return [node]


def only_flags(node):
    names = {n.id for n in ast.walk(node) if isinstance(n, ast.Name)}
    roots = {a.value.id for a in ast.walk(node)
             if isinstance(a, ast.Attribute) and isinstance(a.value, ast.Name)}
    called = {f.func.id for f in ast.walk(node)
              if isinstance(f, ast.Call) and isinstance(f.func, ast.Name)}
    return names <= {"flags"} and roots <= {"flags"} and not called


def scalar_key(node):
    """Scalar expression that is an ordered dead-end dimension source
    (credits | n_alive(x))."""
    src = ast.unparse(node)
    if src == "credits":
        return src
    if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
            and node.func.id == "n_alive"):
        return src
    return None


def eval_scalar_cmp(node, key, val):
    src = ast.unparse(node).replace(key, str(val))
    try:
        return bool(eval(compile(ast.parse(src, mode="eval"), "<de>", "eval"),
                         {"__builtins__": {}}, {}))
    except Exception:
        return None


NUM_SIDE = {ast.Gt: "hi", ast.GtE: "hi", ast.Lt: "lo", ast.LtE: "lo"}


def classify_term(node):
    """Dead-end analysis term: static (flags-only) | num (ordered scalar keyed
    by expression: credits thresholds, n_alive counters) | bool (free boolean
    unknown; key shared for same expressions) | const."""
    if isinstance(node, ast.Constant):
        return ("const", bool(node.value))
    if isinstance(node, ast.Compare) and len(node.ops) == 1:
        for side, lit, flip in ((node.left, node.comparators[0], False),
                                (node.comparators[0], node.left, True)):
            key = scalar_key(side)
            if key is None:
                continue
            if isinstance(lit, ast.Constant) and isinstance(lit.value, int):
                lo = eval_scalar_cmp(node, key, 0)
                hi = eval_scalar_cmp(node, key, max(lit.value, 1))
                if lo is not None and hi is not None:
                    if lo == hi:
                        return ("const", lo)
                    return ("num", key, "lo" if lo else "hi")
            else:  # non-constant bound (e.g. credits >= station.price):
                want = NUM_SIDE.get(type(node.ops[0]))  # operator polarity
                if want and flip:
                    want = "hi" if want == "lo" else "lo"
                if want:
                    return ("num", key, want)
    if isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
        return ("bool", ast.unparse(node), True)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not) \
            and isinstance(node.operand, ast.Call):
        return ("bool", ast.unparse(node.operand), False)
    if only_flags(node):
        return ("static", ast.unparse(node))
    return ("bool", ast.unparse(node), True)


def term_visible(t, fvals, numval, bvals):
    if t[0] == "const":
        return t[1]
    if t[0] == "static":
        env = {"flags": types.SimpleNamespace(**fvals)}
        try:
            return bool(eval(t[1], {"__builtins__": {}}, env))
        except Exception:
            return True
    if t[0] == "num":
        return numval[t[1]] == t[2]
    return bvals[t[1]] == t[2]


def deadend_check(page_path, replies, ctx):
    """Warn when every reply of a page could be hidden at once (comms
    dead-end). Conservative enumeration over flags x credits x booleans."""
    if not replies:
        ctx.warn(f"{page_path}: page has no replies")
        return
    if any("when" not in r and "once" not in r for r in replies):
        return
    parsed, flagset, numkeys, bool_used = [], set(), set(), set()
    for r in replies:
        src = r.get("when")
        if r.get("once"):
            ctx.flags.add(str(r["once"]))
            src = f"not flags.{r['once']}" + (f" and ({src})" if src else "")
        try:
            tree = L.parse_expr(src)
        except SyntaxError:
            return
        terms = []
        for node in and_terms(tree.body):
            t = classify_term(node)
            if t[0] == "static":
                flagset |= {p.split(".", 1)[1] for p in L.attr_paths(node)
                            if p.startswith("flags.")}
            elif t[0] == "num":
                numkeys.add(t[1])
            elif t[0] == "bool":
                bool_used.add(t[1])
            terms.append(t)
        parsed.append(terms)
    flagset = sorted(flagset)
    bools = sorted(bool_used)
    numkeys = sorted(numkeys)
    if len(flagset) > 6 or len(numkeys) + len(bools) > 4:
        ctx.warn(f"{page_path}: too many conditions to prove always-answerable")
        return
    dims = [(False, True)] * len(flagset)
    dims += [("lo", "hi")] * len(numkeys)
    dims += [(False, True)] * len(bools)
    for combo in itertools.product(*dims):
        fv = dict(zip(flagset, combo[:len(flagset)]))
        cut = len(flagset)
        nv = dict(zip(numkeys, combo[cut:cut + len(numkeys)]))
        bv = dict(zip(bools, combo[cut + len(numkeys):]))
        if all(not all(term_visible(t, fv, nv, bv) for t in ts) for ts in parsed):
            ctx.warn(f"{page_path}: all replies can be hidden at once "
                     "(comms dead-end); add an always-visible reply")
            return


def walk_whens(node, path, ctx):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "when" and isinstance(v, str):
                check_expr(v, f"{path}.when", ctx)
            else:
                walk_whens(v, f"{path}.{k}", ctx)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_whens(v, f"{path}[{i}]", ctx)


def finish_checks(doc, ctx, meta, world, dialogs):
    for dlg in dialogs.values():          # auto-declare once: bookkeeping flags
        for page in (dlg.get("pages") or {}).values():
            for r in page.get("replies") or []:
                if r.get("once"):
                    ctx.flags.add(str(r["once"]))
    for sname, st in ctx.stations.items():
        if st.get("comms") and st["comms"] not in dialogs:
            ctx.err(f"station {sname}: comms dialog {st['comms']!r} undefined")
    for dname, dlg in dialogs.items():
        pages = dlg.get("pages") or {}
        if dlg.get("greeting") not in pages:
            ctx.err(f"dialogs.{dname}: greeting page missing")
        for pname, page in pages.items():
            path = f"dialogs.{dname}.{pname}"
            if "text" not in page:
                ctx.err(f"{path}: page needs text")
            if "do" in page:
                ctx.err(f"{path}: pages must not have do: (actions belong "
                        "on replies)")
            replies = page.get("replies") or []
            for i, r in enumerate(replies):
                rp = f"{path}.replies[{i}]"
                if not ({"to", "say", "do"} & set(r)):
                    ctx.err(f"{rp}: reply needs to/say/do")
                if r.get("to") is not None and r["to"] not in pages:
                    ctx.err(f"{rp}: to: page {r['to']!r} undefined")
                if (r.get("then") or {}).get("replies") not in (None, *pages):
                    ctx.err(f"{rp}: then.replies page undefined")
                if "when" in r:
                    check_expr(r["when"], rp, ctx)
                if "once" in r and not re.fullmatch(r"\w+", str(r["once"])):
                    ctx.err(f"{rp}: once: must be a flag name")
                for act in r.get("do") or []:
                    check_action(act, rp, ctx)
            deadend_check(path, replies, ctx)

    for ename, ev in (doc.get("events") or {}).items():
        path = f"events.{ename}"
        if ev.get("fire", "once_when_ready") not in FIRE_MODES:
            ctx.err(f"{path}: unknown fire mode")
        has_after = isinstance(ev.get("after"), (int, float))
        af = ev.get("after_flag")
        if has_after == bool(af):
            ctx.err(f"{path}: exactly one of after:/after_flag: required")
        if af:
            if af.get("flag") not in ctx.flags or \
                    not isinstance(af.get("delay"), (int, float)):
                ctx.err(f"{path}: after_flag needs a declared flag + delay")
        for act in ev.get("do") or []:
            check_action(act, path, ctx)

    for i, st in enumerate(doc.get("stages") or []):
        path = f"stages[{i}]"
        tr = st.get("tracker")
        if isinstance(tr, dict):
            if set(tr) == {"station"} and tr["station"] not in ctx.stations:
                ctx.err(f"{path}: tracker station is not a station")
            elif set(tr) == {"object"} and tr["object"] not in ctx.objects:
                ctx.err(f"{path}: tracker object is not an object/"
                        "wormhole end")
            elif set(tr) not in ({"station"}, {"object"}):
                ctx.err(f"{path}: tracker keys must be station or object")
        elif tr is not None and tr != "none":
            ctx.err(f"{path}: tracker must be none or a map")

    for oname, oc in (doc.get("outcomes") or {}).items():
        if oname not in ("victory", "defeat"):
            ctx.err(f"outcomes: unknown outcome {oname!r}")
        elif not (oc or {}).get("when"):
            ctx.err(f"outcomes.{oname}: when required")
    if ctx.saw_victory_action and "victory" in (doc.get("outcomes") or {}):
        ctx.warn("two victory paths (victory: action + outcomes.victory); "
                 "the action wins by ending instantly (dsl/DESIGN.md)")

    for sname, body in (doc.get("scripts") or {}).items():
        if not isinstance(body, str):
            ctx.err(f"scripts.{sname}: must be a raw Lua string")
        else:
            ctx.warn(f"scripts.{sname}: raw Lua passthrough, not validated")

    walk_whens({k: doc.get(k) for k in ("events", "stages", "outcomes")},
               "doc", ctx)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    doc = yaml.safe_load(open(sys.argv[1]))
    ctx = Ctx()
    if doc.get("version") not in (0.1, "0.1"):
        ctx.err(f"unsupported schema version {doc.get('version')!r} "
                "(this checker implements 0.1)")
    for key in doc:
        if key not in TOP:
            ctx.err(f"unknown top-level key {key!r}")

    meta = doc.get("meta") or {}
    for k in ("name", "description"):
        if k not in meta:
            ctx.err(f"meta.{k} is required")
    if meta.get("type") not in KNOWN_TYPES:
        ctx.err(f"meta.type {meta.get('type')!r} not in {sorted(KNOWN_TYPES)}")
    if not meta.get("api"):
        ctx.err("meta.api is required (pinned vendored EE)")
    elif meta["api"] != L.CURRENT_API:
        ctx.warn(f"meta.api {meta['api']!r} differs from vendored "
                 f"{L.CURRENT_API}")

    world = doc.get("world") or {}
    ctx.systems = set(world.get("systems") or [])
    if not ctx.systems:
        ctx.err("world.systems is required")
    for sname in (world.get("stars") or {}):
        if sname not in ctx.systems:
            ctx.err(f"world.stars.{sname}: not in world.systems")
    for link in world.get("links") or []:
        for end in re.split(r"<->|--", str(link)):
            if end.strip() and end.strip() not in ctx.systems:
                ctx.err(f"world.links: unknown system {end.strip()!r}")
    ctx.ships = world.get("ships") or {}
    ctx.stations = world.get("stations") or {}
    for name, s in ctx.ships.items():
        at = s.get("at_start", "position" in s)
        if at:
            if "position" not in s:
                ctx.err(f"ships.{name}: at-start entity needs position")
            if s.get("system") not in ctx.systems:
                ctx.err(f"ships.{name}: unknown system {s.get('system')!r}")
        else:
            ctx.archetypes.add(name)
            if "position" in s:
                ctx.err(f"ships.{name}: archetype must not have position")
    if not any(s.get("player") for s in ctx.ships.values()):
        ctx.warn("no ship has player: true")
    ctx.objects = (set(ctx.stations)
                   | {n for n in ctx.ships if n not in ctx.archetypes})
    for name, st in ctx.stations.items():
        if st.get("system") not in ctx.systems:
            ctx.err(f"stations.{name}: unknown system")
    for wname, wh in (world.get("wormholes") or {}).items():
        for side in ("a", "b"):
            end = wh.get(side) or {}
            if end.get("system") not in ctx.systems:
                ctx.err(f"world.wormholes.{wname}.{side}: unknown system")
            ctx.objects.add(f"{wname}.{side}")

    for fname, fv in (doc.get("flags") or {}).items():
        if isinstance(fv, dict) and fv.get("scope", "world") not in SCOPES:
            ctx.err(f"flags.{fname}: scope must be world|ship|player")
        ctx.flags.add(fname)
    ctx.items = set(doc.get("items") or {})
    for iname, iv in (doc.get("items") or {}).items():
        if (iv or {}).get("instance", "count") not in ("one_of", "count"):
            ctx.err(f"items.{iname}: instance must be one_of|count")
        if (iv or {}).get("spawn_as") not in ("teleport_object", "cargo"):
            ctx.err(f"items.{iname}: spawn_as must be teleport_object|cargo")
    ctx.opts = meta.get("options") or {}
    for oname, ov in ctx.opts.items():
        values = (ov or {}).get("values") or []
        if "default" in (ov or {}) and ov["default"] not in values:
            ctx.err(f"options.{oname}: default not in values")
    ctx.known = (set(ctx.objects) | ctx.items | {"flags", "options"}
                 | L.FUNCS
                 | {str(v) for ov in ctx.opts.values()
                    for v in ((ov or {}).get("values") or [])})
    finish_checks(doc, ctx, meta, world, dialogs := doc.get("dialogs") or {})

    n_pages = sum(len(d.get("pages") or {}) for d in dialogs.values())
    for w in ctx.warns:
        print("  warn:", w)
    if ctx.errs:
        print(f"FAIL: {len(ctx.errs)} problem(s)")
        for e in ctx.errs:
            print("  -", e)
        sys.exit(1)
    print(f"OK: {sys.argv[1]} — {len(dialogs)} dialogs, {n_pages} pages, "
          f"{len(ctx.archetypes)} archetypes, "
          f"{len(doc.get('stages') or [])} stages, "
          f"{len(doc.get('events') or {})} events, "
          f"{len(ctx.warns)} warning(s)")


if __name__ == "__main__":
    main()