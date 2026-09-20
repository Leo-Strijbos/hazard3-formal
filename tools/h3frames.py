import re,sys
VAR=re.compile(r"^\$var\s+\S+\s+(\d+)\s+(\S+)\s*(.*?)\s*\$end\s*$")
L=open(sys.argv[1],errors="replace").read().split("\n"); n={};w={};i=0
while i<len(L):
    l=L[i].strip()
    if l.startswith("$var"):
        m=VAR.match(l)
        if m and m.group(3): n[m.group(2)]=m.group(3); w[m.group(2)]=int(m.group(1))
    elif l.startswith("$enddefinitions"): break
    i+=1
fr=[];v={};t=None
for l in L[i:]:
    l=l.rstrip()
    if not l: continue
    if l[0]=="#":
        if t is not None: fr.append(dict(v))
        t=int(l[1:])
    elif l[0]=="b":
        p=l[1:].split(" ",1)
        if len(p)==2: v[p[1].strip()]=p[0]
    elif l[0] in "01xz" and len(l)>1: v[l[1:]]=l[0]
if t is not None: fr.append(dict(v))
by={n[s]:s for s in n}
def hx(b,wd):
    try: return f"0x{int(b,2):0{(wd+3)//4}x}" if wd>1 else b
    except: return b
print(f"  {'signal':<42}"+"".join(f"{'f%d'%k:>14}" for k in range(len(fr))))
for name in sys.argv[2:]:
    s=by.get(name)
    if not s: print(f"  {name:<42} (absent)"); continue
    print(f"  {name:<42}"+"".join(f"{hx(f.get(s,'?'),w[s]):>14}" for f in fr))
