#!/usr/bin/env python3
import sys
vcd, names = sys.argv[1], sys.argv[2].split(',')
sym2name={}; scope=[]
lines=open(vcd).read().split('\n'); i=0
while i<len(lines):
    l=lines[i].strip()
    if l.startswith('$scope'): scope.append(l.split()[2])
    elif l.startswith('$upscope'): scope.pop()
    elif l.startswith('$var'):
        p=l.split(); sym2name[p[3]]='.'.join(scope+[p[4]])
    elif l.startswith('$enddefinitions'): break
    i+=1
rows=[]; vals={}; t=None
for l in lines[i:]:
    l=l.strip()
    if l.startswith('#'):
        if t is not None: rows.append((t,dict(vals)))
        t=int(l[1:])
    elif l.startswith('b'):
        v,s=l.split(); vals[sym2name.get(s,s)]=v[1:]
    elif l and l[0] in '01xz' and len(l)>1:
        vals[sym2name.get(l[1:],l[1:])]=l[0]
if t is not None: rows.append((t,dict(vals)))
def short(n): return n.split('.')[-1] if len(n)<24 else n[-22:]
print(' | '.join([f'{"t":>4}']+[f'{short(n):>18}' for n in names]))
for t,v in rows:
    print(' | '.join([f'{t:>4}']+[f'{v.get(n,"-"):>18}' for n in names]))
