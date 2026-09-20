import re,sys,datetime
lines=open("/var/tmp/h3loop.log",errors="replace").read().split("\n")
rounds={}; cur=None
def t(s):
    m=re.search(r"(\d\d):(\d\d)",s); return int(m[1])*60+int(m[2]) if m else None
for l in lines:
    m=re.match(r"=== ROUND (\S+) \(v",l)
    if m: cur=m[1]; rounds[cur]={"start":t(l),"n":0,"proved":0,"timeout":0,"refuted":0,"core":0}; continue
    if cur is None: continue
    r=rounds[cur]
    if "core pre-screen done" in l: r["core_done"]=t(l); r["core"]=int(re.search(r": (\d+) proved",l)[1])
    elif l.startswith("build rc="): r["build_done_line"]=True
    elif l.startswith("=== proving"): r["prove_start"]=t(l); r["n"]=int(re.search(r"proving (\d+)",l)[1])
    elif l.startswith("RESULT Cti") and "(GOAL)" not in l:
        if "RESULT: UNSAT" in l: r["proved"]+=1
        elif "REFUTED" in l: r["refuted"]+=1
        elif " t=" in l: r["timeout"]+=1
    elif l.startswith("=== goals"): r["goals_start"]=t(l)
    elif l.startswith("ROUND-"): r["done"]=t(l)
print("round      start core_done prove_start goals done | n  core proved tout ref | build_min prove_min goal_min total_min")
for k,r in rounds.items():
    if k in("fix1",): continue
    s=r.get("start"); cd=r.get("core_done"); ps=r.get("prove_start"); gs=r.get("goals_start"); d=r.get("done")
    f=lambda a,b: (b-a) if (a is not None and b is not None and b>=a) else None
    print(f"{k:9s} {s} {cd} {ps} {gs} {d} | {r['n']:2d} {r['core']:3d} {r['proved']:3d} {r['timeout']:3d} {r['refuted']:2d} | {f(cd,ps)} {f(ps,gs)} {f(gs,d)} {f(s,d)}")
