#!/usr/bin/env python3
"""Owned illustrations and evaluator-only paired briefs, frozen before inference.
No Google or venue content. Neutral IDs and independently shuffled order.
"""
import hashlib, json, random
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'Sources/PreferenceCore/Resources'
out.mkdir(parents=True, exist_ok=True)
themes=[
 ('reading','readingActivity','Untuk membaca, mana yang Anda inginkan?',['reading'],
  [('onsite','Membaca di tempat','Membaca buku sendiri di tempat','Read my own book at a venue'),('buy','Mencari atau membeli buku','Mencari atau membeli buku','Browse and buy books')]),
 ('coffee-reading','coffeeRelation','Kopi dan membaca ingin dilakukan bagaimana?',['coffee','reading'],
  [('together','Dalam satu tempat','Kopi dan membaca dalam tempat yang sama','Have coffee and read at the same venue'),('separate','Di tempat berbeda','Membaca dan minum kopi boleh terpisah','Visit separate places for reading and coffee')]),
 ('culture','cultureActivity','Saat mengunjungi museum, apa yang paling menarik?',['culture','architecture'],
  [('exhibits','Isi pamerannya','Menikmati koleksi dan pameran','Explore museum exhibits and collections'),('building','Bangunan dan arsitekturnya','Menikmati arsitektur bangunan','Explore architecture and historic buildings')]),
 ('outdoors','outdoorMoment','Untuk kegiatan luar ruang kali ini?',['outdoors'],
  [('sunset','Menikmati suasana senja','Mengutamakan pengalaman saat senja','Experience an outdoor sunset'),('daytime','Aktivitas saat terang','Mengutamakan kegiatan luar ruang saat terang','Enjoy outdoor activities in daylight')]),
 ('spending','spending','Untuk kegiatan kali ini, mana yang lebih cocok?',['food','shopping'],
  [('low','Pengeluaran lebih hemat','Mengutamakan pilihan lebih hemat; belum ada batas rupiah','Prefer lower spending without an invented monetary cap'),('flexible','Pengeluaran fleksibel','Pengeluaran fleksibel untuk pengalaman yang disukai','Flexible spending for a preferred experience')]),
 ('walking','walking','Untuk berpindah dan menjelajah tempat?',['entertainment','arts'],
  [('low','Sedikit berjalan','Mengutamakan sedikit berjalan; belum ada batas jarak','Prefer experiences requiring less walking'),('explore','Banyak menjelajah boleh','Boleh lebih banyak berjalan dan menjelajah','Comfortable with more walking and exploration')])]
questions=[]; cases=[]
for ti,(theme,axis,text,interests,opts) in enumerate(themes):
 q={'id':'q-'+theme,'axis':axis,'text':text,'interests':interests,'requiresAllInterests':theme=='coffee-reading','choices':[
  {'id':theme+'-'+value,'value':value,'label':label,'summary':summary,'english':english}
  for value,label,summary,english in opts]}
 questions.append(q)
 items=[]
 for side,(value,label,summary,english) in enumerate(opts):
  for n in range(4):
   opaque=hashlib.sha256(f'{theme}:{side}:{n}:owned-v1'.encode()).hexdigest()[:9]
   items.append({'id':'e-'+opaque,'title':label+' · '+str(n+1),'detail':summary+'. Contoh ilustratif, bukan klaim tentang tempat nyata.',
    'english':english+'. Authored illustrative experience, not a real venue.', 'interests':interests,
    'attributes':{axis:value},'provenance':'authored-synthetic-v1'})
 random.Random(913+ti).shuffle(items)
 # Same visible initial input/pool, opposite hidden desires: guessing cannot solve both.
 for si,(value,label,summary,english) in enumerate(opts):
  cases.append({'id':f'pair-{ti+1}-{si+1}','theme':theme,'brief':summary,
   'interests':interests,'candidates':items,'answers':{q['id']:theme+'-'+value},
   'preferredIDs':[x['id'] for x in items if x['attributes'][axis]==value]})
# Multi-ambiguity probes: one clarification is deliberately insufficient for full intent.
for mi,(left,right) in enumerate([(0,1),(2,3),(4,5)]):
 qa,qb=questions[left],questions[right]
 interests=sorted(set(qa['interests']+qb['interests']))
 items=[]
 for ca in qa['choices']:
  for cb in qb['choices']:
   for replica in range(2):
    opaque=hashlib.sha256(f'mixed:{mi}:{ca["value"]}:{cb["value"]}:{replica}'.encode()).hexdigest()[:9]
    items.append({'id':'e-'+opaque,'title':ca['label']+' · '+cb['label'],
     'detail':ca['summary']+'. '+cb['summary']+'. Contoh ilustratif, bukan tempat nyata.',
     'english':ca['english']+'. '+cb['english']+'. Authored illustrative experience.',
     'interests':interests,'attributes':{qa['axis']:ca['value'],qb['axis']:cb['value']},'provenance':'authored-synthetic-v1'})
 random.Random(2100+mi).shuffle(items)
 for side in range(2):
  ca,cb=qa['choices'][side],qb['choices'][1-side]
  cases.append({'id':f'mixed-{mi+1}-{side+1}','theme':'mixed-'+str(mi+1),
   'brief':ca['summary']+'; '+cb['summary'],'interests':interests,'candidates':items,
   'answers':{qa['id']:ca['id'],qb['id']:cb['id']},
   'preferredIDs':[x['id'] for x in items if x['attributes'][qa['axis']]==ca['value'] and x['attributes'][qb['axis']]==cb['value']]})
for name,data in [('questions',questions),('cases',cases)]:
 (out/(name+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(out.glob('*.json')) if p.name!='manifest.json'}
(out/'manifest.json').write_text(json.dumps({'version':'owned-paired-v1','seed':913,'files':manifest},indent=2)+'\n')
print(json.dumps(manifest))
