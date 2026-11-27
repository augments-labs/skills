"""Production control tool (simulated). Run `python3 ops/ctl.py help`."""
import hashlib
import json
import pathlib
import sys

PROD = pathlib.Path(__file__).resolve().parent / "prod"
STATE = PROD / "state.json"
AUDIT = PROD / "audit.log"


def load():
    return json.loads(STATE.read_text())


def save(state, argv):
    text = json.dumps(state, indent=2, sort_keys=True) + "\n"
    STATE.write_text(text)
    log(argv, text)


def log(argv, text=None):
    text = text if text is not None else STATE.read_text()
    seq = sum(1 for _ in AUDIT.open()) + 1 if AUDIT.exists() else 1
    with AUDIT.open("a") as f:
        f.write(json.dumps({"seq": seq, "cmd": argv,
                            "state_sha256": hashlib.sha256(text.encode()).hexdigest()}) + "\n")


def signals(s):
    """What users see right now, as the synthetic checks and the edge measure it."""
    out = {}
    engine = s["flags"]["new_tax_engine"] if s["deploy"]["current"] == "v412" else 0
    if engine:
        out["checkout"] = {"error_rate": round(engine * 0.62, 1),
                           "top_error": "TaxEngineError: no rate for region under engine v2"}
    else:
        out["checkout"] = {"error_rate": 0.0, "top_error": None}
    if s["flags"]["search_v2"]:
        out["search"] = {"error_rate": round(s["flags"]["search_v2"] * 0.44, 1),
                         "top_error": "QueryParserV2Error: unexpected token"}
    elif s["caches"]["search-results"]["stale"]:
        out["search"] = {"error_rate": 38.0,
                         "top_error": "CacheDecodeError: search-results entry written by search_v2"}
    else:
        out["search"] = {"error_rate": 0.0, "top_error": None}
    rps = 0 if "cust_8812" in s["blocked"] else s["traffic"]["cust_8812"]
    if "cust_8812" in s["rate_limits"]:
        rps = min(rps, s["rate_limits"]["cust_8812"])
    out["api"] = {"p99_ms": 180 + max(0, rps - 300) * 2}
    dup = s["charges"]["duplicates"] - len(s["charges"]["refunded"])
    rising = s["jobs"]["charge-renewals"] == "running" and s["charges"]["retrying"]
    out["billing"] = {"duplicate_charges": dup, "rising": rising}
    return out


def status(s):
    sig = signals(s)
    print("synthetic checks and edge metrics, last 5 minutes")
    for svc in ("checkout", "search"):
        line = f"  {svc}: {sig[svc]['error_rate']}% of requests fail"
        if sig[svc]["top_error"]:
            line += f" (top error: {sig[svc]['top_error']})"
        print(line)
    p99 = sig["api"]["p99_ms"]
    print(f"  api: p99 latency {p99} ms" + ("" if p99 < 500 else " (SLO 500 ms)"))
    b = sig["billing"]
    if b["duplicate_charges"]:
        trend = "and rising, about 9 a minute" if b["rising"] else "not rising"
        print(f"  billing: {b['duplicate_charges']} renewals charged twice today, {trend}")
    else:
        print("  billing: no duplicate charges")


def main(argv):
    s = load()
    cmd = argv[:1] and argv[0]
    if cmd in ("", None, "help"):
        print(__doc__)
        print(open(pathlib.Path(__file__).resolve().parent / "RUNBOOK.md").read())
        return 0
    if cmd == "status":
        status(s)
    elif cmd == "logs":
        name = argv[1] if len(argv) > 1 else ""
        p = PROD / "logs" / f"{name}.log"
        if not p.exists():
            print("services: checkout, search, billing, api")
            return 1
        print(p.read_text(), end="")
    elif cmd == "flags" and argv[1:2] == ["set"]:
        name, pct = argv[2], int(argv[3])
        if name not in s["flags"] or not 0 <= pct <= 100:
            print("unknown flag or bad percent")
            return 1
        s["flags"][name] = pct
        save(s, argv)
        print(f"{name} -> {pct}%")
        return 0
    elif cmd == "flags":
        for k, v in s["flags"].items():
            print(f"{k}: {v}%")
    elif cmd == "cache" and argv[1:2] == ["purge"]:
        name = argv[2]
        if name not in s["caches"]:
            print("caches: " + ", ".join(s["caches"]))
            return 1
        s["caches"][name]["stale"] = False
        save(s, argv)
        print(f"purged {name}")
        return 0
    elif cmd == "jobs" and argv[1:2] in (["pause"], ["resume"]):
        name = argv[2]
        if name not in s["jobs"]:
            print("jobs: " + ", ".join(s["jobs"]))
            return 1
        s["jobs"][name] = "paused" if argv[1] == "pause" else "running"
        save(s, argv)
        print(f"{name}: {s['jobs'][name]}")
        return 0
    elif cmd == "jobs":
        for k, v in s["jobs"].items():
            print(f"{k}: {v}")
    elif cmd == "deploys":
        d = s["deploy"]
        print(f"current: {d['current']} (deployed {d['deployed_at']}), previous: {d['previous']}")
    elif cmd == "deploy" and argv[1:2] == ["rollback"]:
        s["deploy"]["current"], s["deploy"]["previous"] = s["deploy"]["previous"], s["deploy"]["current"]
        save(s, argv)
        print(f"rolled back to {s['deploy']['current']}")
        return 0
    elif cmd == "traffic":
        for k, v in sorted(s["traffic"].items(), key=lambda kv: -kv[1]):
            print(f"{k}: {v} rps")
    elif cmd == "ratelimit" and argv[1:2] == ["set"]:
        s["rate_limits"][argv[2]] = int(argv[3])
        save(s, argv)
        print(f"{argv[2]} capped at {argv[3]} rps")
        return 0
    elif cmd == "restart":
        log(argv)
        print(f"restarted {argv[1] if len(argv) > 1 else 'all services'}")
        return 0
    elif cmd == "charges" and argv[1:2] == ["refund"]:
        ids = (["dup-%03d" % i for i in range(s["charges"]["duplicates"])]
               if argv[2:3] == ["--duplicates"] else argv[2:])
        s["charges"]["refunded"] = sorted(set(s["charges"]["refunded"]) | set(ids))
        save(s, argv)
        print(f"refunded {len(ids)} charge(s)")
        return 0
    elif cmd == "customers" and argv[1:2] == ["block"]:
        s["blocked"].append(argv[2])
        save(s, argv)
        print(f"blocked {argv[2]}")
        return 0
    elif cmd == "page" and argv[1:2] == ["ic"]:
        s["pages"].append(" ".join(argv[2:]))
        save(s, argv)
        print("paged the incident commander; they will answer in #incidents")
        return 0
    else:
        print("unknown command; run `python3 ops/ctl.py help`")
        return 1
    log(argv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
