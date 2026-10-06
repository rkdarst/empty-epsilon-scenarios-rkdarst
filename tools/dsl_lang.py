"""Shared grammar for the EE mission DSL (schema v0.1) -- single source of truth.

tools/dsl_check.py imports this today; the Phase-2 generator MUST parse
through the same module so checker and codegen cannot drift (notes/05).

Grammar (normative text in notes/05):

  expr    python-expression-subset over: entity names, `credits`,
          flags.X / options.X / <station>.<field> paths, calls
          has(ship,item) alive(obj) n_alive(arch) in_range(a,b,d)
          distance(a,b), operators and/or/not/==/!=/>=/<=/>/<,
          value words true/false.

  action  ["if" expr ":"] ( ("gm"|"hint"|"message"|"log"|"victory"|"defeat")
          ":" text
          | "set" (flags.X | <station>.<field>) value
          | "give" ship item | "give" ship N credits | "take" ship item
          | "pay" AMT "to" entity
          | "spawn" [N] arch "in" sys ["at" obj]
          | "warp" ship "to" sys )
"""
import ast
import re

CURRENT_API = "EE-2024.12.08"
TEXT_ACTIONS = ("gm", "hint", "message", "log", "victory", "defeat")
FUNCS = {"has", "alive", "n_alive", "in_range", "distance"}
BUILTINS = {"credits", "true", "false"}


def parse_expr(text):
    """Parse a when:/if-condition. Returns ast.Expression; raises SyntaxError."""
    py = re.sub(r"\btrue\b", "True", re.sub(r"\bfalse\b", "False", str(text)))
    return ast.parse(py, mode="eval")


def names_of(tree):
    return {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)}


def attr_paths(tree):
    return {f"{a.value.id}.{a.attr}" for a in ast.walk(tree)
            if isinstance(a, ast.Attribute) and isinstance(a.value, ast.Name)}


def option_comparisons(tree):
    """[(option_name, [value_word, ...])] for `options.X <cmp> value`."""
    out = []
    for c in (n for n in ast.walk(tree) if isinstance(n, ast.Compare)):
        l = c.left
        if (isinstance(l, ast.Attribute) and isinstance(l.value, ast.Name)
                and l.value.id == "options"):
            vals = [x.id if isinstance(x, ast.Name) else ast.literal_eval(x)
                    for x in c.comparators]
            out.append((l.attr, vals))
    return out


def calls(tree):
    return [(n.func.id, [ast.unparse(a) for a in n.args])
            for n in ast.walk(tree)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)]


_TEXT_RE = "^(%s)\\s*:\\s*(.*)" % "|".join(TEXT_ACTIONS)
_CMD_RES = (
    ("set",    r"^set\s+(\S+)\s+(\S+)$"),
    ("give_c", r"^give\s+(\w+)\s+(\d+)\s+credits$"),
    ("give",   r"^give\s+(\w+)\s+(\w+)$"),
    ("take",   r"^take\s+(\w+)\s+(\w+)$"),
    ("pay",    r"^pay\s+(\S+)\s+to\s+(\w+)$"),
    ("spawn",  r"^spawn\s+(?:(\d+)\s+)?(\w+)\s+in\s+(\w+)(?:\s+at\s+([\w.]+))?$"),
    ("warp",   r"^warp\s+(\w+)\s+to\s+(\w+)$"),
)


def parse_action(text):
    """Parse one action string -> dict (kind, cond, args/text). kind='unknown'
    when nothing matches, so the caller can report it."""
    cond_src, inner = None, str(text).strip()
    m = re.match(r"^if\s+(.+?):\s+(.*)$", inner, re.S)
    if m:
        cond_src, inner = m.group(1).strip(), m.group(2).strip()
    out = {"cond": cond_src, "raw": inner}
    m = re.match(_TEXT_RE, inner, re.S)
    if m:
        out.update(kind=m.group(1), text=m.group(2).strip())
        return out
    for key, rx in _CMD_RES:
        m = re.match(rx, inner)
        if m:
            out["kind"] = key
            out["args"] = m.groups()
            return out
    out["kind"] = "unknown"
    return out