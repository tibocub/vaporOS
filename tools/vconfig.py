#!/usr/bin/env python3
"""vconfig.py -- resolve a declarative vaporOS board into a NuttX configuration.

    vconfig.py list                         known boards
    vconfig.py check                        validate every board/feature/hardware file
    vconfig.py show   <board>               the resolved plan, with where each option came from
    vconfig.py explain <board> CONFIG_X     every layer that touches one option, and why
    vconfig.py meta   <board> <key>         one metadata value (nuttx_config, runner, ...)
    vconfig.py env    <board>               shell `export` lines for the host toolchain
    vconfig.py patches <board>              NuttX/nuttx-apps patches the board needs
    vconfig.py apply  <board> <nuttx-dir>   run kconfig-tweak for every option, in order
    vconfig.py verify <board> <nuttx-dir>   fail if Kconfig dropped any requested option

A board is a directory `boards/<name>/` holding `board.conf`. It names a base
NuttX configuration, the software `features/*.conf` to include and the
`hardware/<type>/*.conf` descriptors that describe how the board is wired,
then adds its own options. Later layers win:

    base defconfig -> parent board (extends) -> features -> hardware
        -> the board's own [config] -> local/<board>.conf (per-user, untracked)

Format (all files): INI-like sections, `key = value` lines, `#` comments.
In [config] a line is a NuttX option, `CONFIG_NAME=y|n|123|0x10|"text"`; the
comment after it is kept as the rationale and shown by `show`/`explain`.
See boards/README.md for the full reference.

Standard library only, so it runs wherever Python does.
"""

import glob
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BOARDS = ROOT / "boards"
FEATURES = ROOT / "features"
HARDWARE = ROOT / "hardware"
LOCAL = ROOT / "local"

OPT_RE = re.compile(r"^(CONFIG_[A-Za-z0-9_]+)\s*=\s*(.*)$")
SECTION_RE = re.compile(r"^\[([a-z_]+)\]$")


class ConfError(Exception):
    pass


def split_comment(line):
    """Split `value  # why` at the first '#' that is outside double quotes."""
    in_q = False
    for i, ch in enumerate(line):
        if ch == '"':
            in_q = not in_q
        elif ch == "#" and not in_q and (i == 0 or line[i - 1] in " \t"):
            return line[:i].rstrip(), line[i + 1:].strip()
    return line.rstrip(), ""


def parse(path):
    """-> dict section -> list of (text, why, lineno). Comment-only lines directly
    above an entry are folded into its rationale."""
    sections = {}
    cur = None
    pending = []
    for n, raw in enumerate(Path(path).read_text().splitlines(), 1):
        line = raw.strip()
        if not line:
            pending = []
            continue
        if line.startswith("#"):
            pending.append(line.lstrip("# ").rstrip())
            continue
        m = SECTION_RE.match(line)
        if m:
            cur = sections.setdefault(m.group(1), [])
            pending = []
            continue
        if cur is None:
            raise ConfError(f"{path}:{n}: entry outside any [section]")
        text, why = split_comment(line)
        if pending:
            why = " ".join(pending + ([why] if why else []))
            pending = []
        cur.append((text, why, n))
    return sections


def kv(entries, path):
    out = {}
    for text, _, n in entries:
        if "=" not in text:
            raise ConfError(f"{path}:{n}: expected key = value, got {text!r}")
        k, v = text.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def find_board(name):
    if (BOARDS / name / "board.conf").is_file():
        return name
    for d in sorted(BOARDS.iterdir()) if BOARDS.is_dir() else []:
        f = d / "board.conf"
        if f.is_file():
            aliases = kv(parse(f).get("board", []), f).get("aliases", "").split()
            if name in aliases:
                return d.name
    known = ", ".join(sorted(d.name for d in BOARDS.iterdir() if d.is_dir()))
    raise ConfError(f"unknown board {name!r} (known: {known})")


class Layer:
    """One source of options: (origin, option, value, why)."""

    def __init__(self, origin):
        self.origin = origin
        self.options = []


class Plan:
    def __init__(self, name):
        self.name = name
        self.meta = {}
        self.features = []
        self.hardware = {}          # slot -> (descriptor, params)
        self.tools = {"path": [], "env": {}, "require": []}
        self.layers = []            # Layer objects, in application order
        self.patches = []
        self.chain = []

    def options(self):
        """Flattened (option, value, origin, why), in application order."""
        for layer in self.layers:
            for opt, val, why in layer.options:
                yield opt, val, layer.origin, why


def parse_options(entries, path, subst=None):
    out = []
    for text, why, n in entries:
        m = OPT_RE.match(text)
        if not m:
            raise ConfError(f"{path}:{n}: not a CONFIG_X=value line: {text!r}")
        val = m.group(2).strip()
        if subst:
            def rep(mm):
                if mm.group(1) not in subst:
                    raise ConfError(f"{path}:{n}: unknown parameter ${{{mm.group(1)}}}")
                return subst[mm.group(1)]
            val = re.sub(r"\$\{([a-z_]+)\}", rep, val)
        out.append((m.group(1), val, why))
    return out


def load_feature(name):
    f = FEATURES / f"{name}.conf"
    if not f.is_file():
        raise ConfError(f"unknown feature {name!r} ({f} does not exist)")
    sec = parse(f)
    layer = Layer(f"feature:{name}")
    layer.options = parse_options(sec.get("config", []), f)
    layer.meta = kv(sec.get("feature", []), f)
    layer.requires = [t for t, _, _ in sec.get("requires", [])]
    return layer


def load_hardware(slot, spec):
    """spec = 'type/name key=value ...'."""
    parts = shlex.split(spec)
    if not parts:
        raise ConfError(f"hardware slot {slot!r} has no descriptor")
    desc, given = parts[0], {}
    for p in parts[1:]:
        if "=" not in p:
            raise ConfError(f"hardware {slot}: parameter {p!r} is not key=value")
        k, v = p.split("=", 1)
        given[k] = v
    f = HARDWARE / f"{desc}.conf"
    if not f.is_file():
        raise ConfError(f"hardware {slot}: unknown descriptor {desc!r} ({f} does not exist)")
    sec = parse(f)
    meta = kv(sec.get("hardware", []), f)
    status = meta.get("status", "untested")
    if status not in ("verified", "untested", "draft"):
        raise ConfError(f"{f}: status must be verified, untested or draft, not {status!r}")
    if status == "draft" and os.environ.get("VCONFIG_ALLOW_DRAFT") != "1":
        raise ConfError(f"hardware {slot}: {desc} is a draft (vaporOS cannot drive it yet; "
                        f"see hardware/README.md). Set VCONFIG_ALLOW_DRAFT=1 to try anyway.")
    params = {}
    for text, _, n in sec.get("params", []):
        k, _, v = text.partition("=")
        params[k.strip()] = v.strip()          # empty default => required
    for k in given:
        if k not in params:
            raise ConfError(f"hardware {slot} ({desc}): no parameter {k!r} "
                            f"(has: {', '.join(params) or 'none'})")
    values = {}
    for k, default in params.items():
        values[k] = given.get(k, default)
        if values[k] == "":
            raise ConfError(f"hardware {slot} ({desc}): parameter {k!r} is required")
    layer = Layer(f"hardware:{slot}={desc}")
    layer.options = parse_options(sec.get("config", []), f, values)
    layer.meta = meta
    layer.values = values
    return layer


def resolve(name, _seen=None):
    name = find_board(name)
    _seen = _seen or []
    if name in _seen:
        raise ConfError(f"board extends loop: {' -> '.join(_seen + [name])}")
    f = BOARDS / name / "board.conf"
    sec = parse(f)
    board = kv(sec.get("board", []), f)

    plan = Plan(name)
    if board.get("extends"):
        plan = resolve(board["extends"], _seen + [name])
        plan.name = name
    plan.chain.append(name)

    for k, v in board.items():
        if k not in ("extends", "aliases"):
            plan.meta[k] = v
    if "aliases" in board:
        plan.meta["aliases"] = board["aliases"]

    for t, _, _ in sec.get("patches", []):
        if t not in plan.patches:
            plan.patches.append(t)

    # features: `name` adds, `-name` removes one inherited from a parent
    for t, _, _ in sec.get("features", []):
        if t.startswith("-"):
            plan.features = [x for x in plan.features if x != t[1:]]
            plan.layers = [l for l in plan.layers if l.origin != f"feature:{t[1:]}"]
        elif t not in plan.features:
            plan.features.append(t)
            layer = load_feature(t)
            plan.layers.append(layer)
            for r in layer.requires:
                if r.startswith("patch ") and r.split()[1] not in plan.patches:
                    plan.patches.append(r.split()[1])

    for text, _, n in sec.get("hardware", []):
        slot, _, spec = text.partition("=")
        slot = slot.strip()
        if slot in plan.hardware:               # child redefines the slot
            plan.layers = [l for l in plan.layers
                           if not l.origin.startswith(f"hardware:{slot}=")]
        layer = load_hardware(slot, spec.strip())
        plan.hardware[slot] = (spec.strip(), layer.values)
        plan.layers.append(layer)

    for text, _, n in sec.get("tools", []):
        k, _, v = text.partition("=")
        k, v = k.strip(), v.strip()
        if k == "path":
            plan.tools["path"].append(v)
        elif k == "require":
            plan.tools["require"] += v.split()
        elif k.startswith("env."):
            plan.tools["env"][k[4:]] = v
        else:
            raise ConfError(f"{f}: unknown [tools] key {k!r}")

    own = Layer(f"board:{name}")
    own.options = parse_options(sec.get("config", []), f)
    plan.layers.append(own)

    local = LOCAL / f"{name}.conf"
    if local.is_file():
        lsec = parse(local)
        ll = Layer(f"local:{name}")
        ll.options = parse_options(lsec.get("config", []), local)
        plan.layers.append(ll)
    return plan


# ----------------------------------------------------------------- commands

def final_values(plan):
    last = {}
    for opt, val, origin, why in plan.options():
        last[opt] = (val, origin, why)
    return last


def cmd_list(_):
    for d in sorted(BOARDS.iterdir()):
        f = d / "board.conf"
        if f.is_file():
            b = kv(parse(f).get("board", []), f)
            print(f"{d.name:<16} {b.get('description', '')}")


def cmd_check(_):
    bad = 0
    for d in sorted(BOARDS.iterdir()):
        if (d / "board.conf").is_file():
            try:
                plan = resolve(d.name)
                for need in ("nuttx_config", "runner"):
                    if need not in plan.meta:
                        raise ConfError(f"{d.name}: [board] {need} is required")
                for p in plan.patches:
                    if not any((ROOT / "patches").glob(f"*/{p}")):
                        raise ConfError(f"{d.name}: patch {p!r} not found under patches/")
                print(f"ok   {d.name}: {len(plan.features)} features, "
                      f"{len(plan.hardware)} hardware, {len(final_values(plan))} options")
            except ConfError as e:
                bad += 1
                print(f"FAIL {e}")
    for f in sorted(HARDWARE.glob("*/*.conf")):
        try:
            sec = parse(f)
            meta = kv(sec.get("hardware", []), f)
            for need in ("type", "description", "status"):
                if need not in meta:
                    raise ConfError(f"{f}: [hardware] {need} is required")
            if meta["status"] not in ("verified", "untested", "draft"):
                raise ConfError(f"{f}: bad status {meta['status']!r}")
            if meta["status"] == "verified" and "verified_on" not in meta:
                raise ConfError(f"{f}: a verified descriptor must say verified_on")
            names = {k.strip() for k, _, _ in (t.partition("=") for t, _, _ in sec.get("params", []))}
            for t, _, n in sec.get("config", []):
                for ref in re.findall(r"\$\{([a-z_]+)\}", t):
                    if ref not in names:
                        raise ConfError(f"{f}:{n}: uses undefined parameter ${{{ref}}}")
            parse_options(sec.get("config", []), f)
            print(f"ok   hardware {f.parent.name}/{f.stem} [{meta['status']}]")
        except ConfError as e:
            bad += 1
            print(f"FAIL {e}")
    for f in sorted(FEATURES.glob("*.conf")):
        try:
            load_feature(f.stem)
        except ConfError as e:
            bad += 1
            print(f"FAIL {e}")
    return 1 if bad else 0


def cmd_show(args):
    plan = resolve(args[0])
    print(f"board {plan.name}" + (f" (extends {' -> '.join(plan.chain[:-1])})"
                                  if len(plan.chain) > 1 else ""))
    for k, v in plan.meta.items():
        print(f"  {k} = {v}")
    if plan.patches:
        print("  patches: " + ", ".join(plan.patches))
    for slot, (spec, _) in plan.hardware.items():
        print(f"  hardware {slot}: {spec}")
    final = final_values(plan)
    print()
    for layer in plan.layers:
        shown = [(o, v, w) for o, v, w in layer.options if final[o][1] == layer.origin]
        if not shown:
            continue
        print(f"[{layer.origin}]")
        for o, v, w in shown:
            print(f"  {o}={v}" + (f"   # {w}" if w else ""))
    return 0


def cmd_explain(args):
    plan = resolve(args[0])
    opt = args[1] if args[1].startswith("CONFIG_") else "CONFIG_" + args[1]
    hits = [(origin, val, why) for o, val, origin, why in plan.options() if o == opt]
    if not hits:
        print(f"{opt}: not set by any vaporOS layer (NuttX default / base defconfig)")
        return 1
    for i, (origin, val, why) in enumerate(hits):
        tag = "wins " if i == len(hits) - 1 else "overridden"
        print(f"{tag:<10} {origin}: {opt}={val}" + (f"\n           why: {why}" if why else ""))
    return 0


def cmd_meta(args):
    plan = resolve(args[0])
    print(plan.meta.get(args[1], ""))
    return 0


def expand(s):
    def rep(m):
        return os.environ.get(m.group(1)) or m.group(2)
    s = re.sub(r"\$\{([A-Z_]+):-([^}]*)\}", rep, s)
    return os.path.expanduser(s)


def cmd_patches(args):
    for p in resolve(args[0]).patches:
        print(p)
    return 0


def cmd_env(args):
    plan = resolve(args[0])
    paths = []
    for p in plan.tools["path"]:
        hits = sorted(glob.glob(expand(p)))
        paths += hits or [expand(p)]
    for k, v in plan.tools["env"].items():
        print(f"export {k}={shlex.quote(expand(v))}")
    if paths:
        print("export PATH=" + shlex.quote(":".join(paths)) + ':"$PATH"')
    print("VCONFIG_REQUIRE=" + shlex.quote(" ".join(plan.tools["require"])))
    return 0


def tweak_args(opt, val):
    if val == "y":
        return ["--enable", opt]
    if val == "n":
        return ["--disable", opt]
    if val.startswith('"') and val.endswith('"'):
        return ["--set-str", opt, val[1:-1]]
    if re.fullmatch(r"-?(0x[0-9a-fA-F]+|\d+)", val):
        return ["--set-val", opt, val]
    raise ConfError(f"{opt}={val!r}: value must be y, n, a number or a quoted string")


def set_mixed_case(path, opt, val):
    """kconfig-tweak upper-cases the option name, so it cannot set NuttX options such as NETDB_DNSSERVER_IPv4ADDR
    (it appends a CONFIG_..._IPV4ADDR line that Kconfig ignores): edit the line ourselves."""
    name = opt if opt.startswith("CONFIG_") else "CONFIG_" + opt
    line = f"# {name} is not set" if val == "n" else f"{name}={val}"
    lines = [l for l in path.read_text().splitlines()
             if not (l.startswith(name + "=") or l == f"# {name} is not set")]
    path.write_text("\n".join(lines + [line]) + "\n")


def cmd_apply(args):
    plan = resolve(args[0])
    nuttx = Path(args[1])
    for opt, val, origin, why in plan.options():
        if opt != opt.upper():
            set_mixed_case(nuttx / ".config", opt, val)
            continue
        subprocess.run(["kconfig-tweak", *tweak_args(opt, val)], cwd=nuttx, check=True)
    return 0


def read_dotconfig(path):
    """-> dict option -> value string; 'not set' options are absent."""
    out = {}
    for line in Path(path).read_text().splitlines():
        m = re.match(r"^(CONFIG_[A-Za-z0-9_]+)=(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def same_value(want, got):
    if got is None:
        return want == "n"
    if want == "n":
        return False
    if re.fullmatch(r"-?(0x[0-9a-fA-F]+|\d+)", want) and re.fullmatch(r"-?(0x[0-9a-fA-F]+|\d+)", got):
        return int(want, 0) == int(got, 0)
    return want == got


def cmd_verify(args):
    """Kconfig silently drops an option whose dependencies are not met. Compare
    what the board asked for against the .config it ended up with."""
    plan = resolve(args[0])
    have = read_dotconfig(Path(args[1]) / ".config")
    bad = 0
    for opt, (val, origin, why) in final_values(plan).items():
        if not same_value(val, have.get(opt)):
            bad += 1
            got = have.get(opt, "not set")
            print(f"NOT HONORED  {opt}: wanted {val}, .config has {got}\n"
                  f"             asked for by {origin}" + (f" ({why})" if why else "") + "\n"
                  f"             Kconfig dropped it: an unmet dependency (see `make menuconfig` search for it).",
                  file=sys.stderr)
    if bad:
        print(f"vconfig: {bad} option(s) were not honored by Kconfig for {plan.name}", file=sys.stderr)
    return 1 if bad else 0


COMMANDS = {"list": (cmd_list, 0), "check": (cmd_check, 0), "show": (cmd_show, 1),
            "explain": (cmd_explain, 2), "meta": (cmd_meta, 2), "env": (cmd_env, 1),
            "apply": (cmd_apply, 2), "patches": (cmd_patches, 1), "verify": (cmd_verify, 2)}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(__doc__)
        return 2
    fn, nargs = COMMANDS[argv[1]]
    if len(argv) - 2 < nargs:
        print(f"vconfig {argv[1]}: needs {nargs} argument(s)", file=sys.stderr)
        return 2
    try:
        return fn(argv[2:]) or 0
    except ConfError as e:
        print(f"vconfig: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
