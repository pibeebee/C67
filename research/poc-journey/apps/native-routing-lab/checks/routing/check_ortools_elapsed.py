"""Small real-package checks for elapsed objective and conservative private-car policy."""
import importlib.util
import itertools
from pathlib import Path
import sys

sys.dont_write_bytecode = True

spec=importlib.util.spec_from_file_location('helper',Path(sys.argv[1]))
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
nodes=[dict(id=f'N{i}',name=f'Node {i}',x=i,y=0,dwell=0 if i==0 else 10,opens=200 if i==3 else None,closes=None) for i in range(4)]
costs={(0,1):1,(1,2):1,(3,0):1,(0,3):2,(3,2):1,(2,1):1,(1,0):2}
arcs=[dict(from_=a,to=b,mode='walking',seconds=costs.get((a,b),100),status='available') for a in range(4) for b in range(4) if a!=b]
for a in arcs:a['from']=a.pop('from_')
problem=dict(schemaVersion=1,id='elapsed-regression',nodes=nodes,targets=[1,2,3],origin=0,end=0,deadline=1000,arcs=arcs)
def finish(order):
    t=0;a=0
    for b in order+[0]:
        t+=costs.get((a,b),100)
        if b:t=max(t,nodes[b]['opens'] or 0)+nodes[b]['dwell']
        a=b
    return t
best=min(finish(list(o)) for o in itertools.permutations([1,2,3]))
result=helper.solve(problem,0.3)
assert result['order'] and finish(result['order'])==best,(result,best)
assert result['objective']=='elapsed_v2'
print('PASS: OR-Tools minimises elapsed including opening wait; independent enumeration agrees:',best)
problem['privateCar']=True
result=helper.solve(problem,0.3)
assert result['order'] and result['carStrategy']=='no_automobile'
assert finish(result['order'])==best
print('PASS: OR-Tools private-car policy does not require unavailable automobile arcs; shared budget:',result['timeLimitSeconds'])
