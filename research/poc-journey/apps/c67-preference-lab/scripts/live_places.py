"""Live Places adapter. Provider order is retained; no content enters an LLM/index.
Evidence is scoped to returned fields; venue names and search text are not proof.
No provider payloads are persisted. Only quota counters and opaque IDs/tokens travel.
"""
import base64, concurrent.futures, datetime as dt, hashlib, hmac, json, re, secrets, threading, time
from pathlib import Path
from zoneinfo import ZoneInfo

AREAS=['Jakarta Pusat','Jakarta Selatan','Jakarta Utara','Jakarta Barat','Jakarta Timur']
INTERESTS=['coffee','reading','food','outdoors','culture','shopping','entertainment','architecture','arts']
AXES={'readingActivity':{'onsite','buy'},'coffeeRelation':{'together','separate'},
 'cultureActivity':{'exhibits','building'},'outdoorMoment':{'sunset','daytime'},
 'spending':{'low','flexible'},'walking':{'low','explore'}}
SEARCH_FIELDS='places.id,places.displayName,places.formattedAddress,places.googleMapsUri,places.types,places.primaryType,places.businessStatus,places.attributions,nextPageToken'
WIB=ZoneInfo('Asia/Jakarta')

def normalize(data):
 allowed={'requestID','revision','interests','needs','area','visitAt','durationMinutes','pageTokens'}
 if set(data)-allowed:raise ValueError('Unexpected discovery fields')
 interests=data.get('interests',[])
 if not isinstance(interests,list) or not interests or len(interests)>9 or len(set(interests))!=len(interests) or any(x not in INTERESTS for x in interests):raise ValueError('Choose valid interests')
 if not isinstance(data.get('requestID'),str) or len(data['requestID'])>80:raise ValueError('requestID')
 if not isinstance(data.get('revision'),int):raise ValueError('revision')
 area=data.get('area','Jakarta Pusat')
 if area not in AREAS:raise ValueError('area')
 needs=data.get('needs',{})
 if not isinstance(needs,dict) or len(needs)>6:raise ValueError('needs')
 for axis,need in needs.items():
  if axis not in AXES or not isinstance(need,dict) or set(need)!={'value','must'} or need['value'] not in AXES[axis] or not isinstance(need['must'],bool):raise ValueError('need')
 if 'readingActivity' in needs and 'reading' not in interests:raise ValueError('Reading must be selected')
 if 'coffeeRelation' in needs and not {'coffee','reading'}<=set(interests):raise ValueError('Both interests required')
 visit=data.get('visitAt')
 if visit is not None and not isinstance(visit,str):raise ValueError('visitAt')
 if visit:
  visit=dt.datetime.fromisoformat(visit.replace('Z','+00:00'))
  if visit.tzinfo is None:raise ValueError('Visit timezone required')
  visit=visit.astimezone(WIB)
 duration=data.get('durationMinutes')
 if duration is not None and (not isinstance(duration,int) or not 1<=duration<=480 or not visit):raise ValueError('duration')
 tokens=data.get('pageTokens')
 if tokens is not None and (not isinstance(tokens,dict) or len(tokens)>9 or any(not isinstance(k,str) or not isinstance(v,str) or len(v)>8192 for k,v in tokens.items())):raise ValueError('pagination')
 return {'requestID':data['requestID'],'revision':data['revision'],'interests':interests,'needs':needs,
  'area':area,'visit':visit,'duration':duration,'tokens':dict(tokens) if tokens is not None else None}

def plan(n):
 interests=n['interests']; needs=n['needs']; groups=[]
 def value(axis):return needs.get(axis,{}).get('value')
 def add(key,label,query,covered):groups.append({'id':key,'label':label,'query':query+' '+n['area'],'interests':covered})
 reading='toko buku' if value('readingActivity')=='buy' else 'perpustakaan tempat membaca' if value('readingActivity')=='onsite' else 'perpustakaan toko buku'
 handled=set()
 if {'coffee','reading'}<=set(interests) and value('coffeeRelation')=='together':
  add('reading-coffee','Buku dan kopi dalam satu tempat',('toko buku kafe' if value('readingActivity')=='buy' else 'kafe untuk membaca buku'),['coffee','reading']);handled={'coffee','reading'}
 queries={'coffee':('Kopi','kafe coffee shop'),'reading':('Membaca dan buku',reading),
  'food':('Kuliner','restoran'),'outdoors':('Alam dan taman','taman'),
  'culture':('Museum dan budaya','museum'),'shopping':('Belanja','pusat perbelanjaan'),
  'entertainment':('Hiburan','tempat hiburan'),'architecture':('Arsitektur','bangunan bersejarah'),
  'arts':('Seni','galeri seni')}
 for interest in interests:
  if interest not in handled:
   label,query=queries[interest];add(interest,label,query,[interest])
 if value('cultureActivity')=='building':
  for group in groups:
   if group['id']=='culture':group['query']='museum arsitektur bangunan bersejarah '+n['area']
 if value('outdoorMoment')=='sunset':
  for group in groups:
   if group['id']=='outdoors':group['query']='taman pantai menikmati senja '+n['area']
 return groups

def hours_state(place,visit,duration,now):
 if not visit:return 'unknown','Jam kunjungan belum ditentukan',''
 hours=place.get('currentOpeningHours'); field='currentOpeningHours'
 if place.get('utcOffsetMinutes') != 420 or not hours or not now.date()<=visit.date()<=now.date()+dt.timedelta(days=6):
  # Weekly hours do not establish dated exceptions. Do not certify from regular hours.
  return 'unknown','Jam untuk tanggal kunjungan belum dapat dipastikan','regularOpeningHours' if place.get('regularOpeningHours') else ''
 periods=hours.get('periods')
 if not isinstance(periods,list):return 'unknown','Sesi buka tidak tersedia',field
 end=visit+dt.timedelta(minutes=duration or 0)
 def point(p):
  if not isinstance(p,dict):return None
  date=p.get('date')
  if not date:return None
  try:return dt.datetime(date['year'],date['month'],date['day'],p.get('hour',0),p.get('minute',0),tzinfo=WIB)
  except (KeyError,ValueError):return None
 for period in periods:
  op,cl=period.get('open',{}),period.get('close')
  if not cl and op.get('day')==0 and op.get('hour',0)==0 and op.get('minute',0)==0:
   return 'supported','Provider mencatat buka 24 jam; akses dan penerimaan terakhir belum dipastikan',field
  start,finish=point(op),point(cl)
  if start is not None and finish is not None and start<=visit<finish and end<=finish:
   return 'supported',('Durasi kunjungan berada dalam sesi buka provider' if duration else 'Waktu kedatangan berada dalam sesi buka provider')+'; penerimaan terakhir belum dipastikan',field
 if not periods:return 'contradicted','Provider tidak mencatat sesi buka pada rentang ini',field
 if all(point(p.get('open')) is not None and point(p.get('close')) is not None and not p.get('open',{}).get('truncated') and not p.get('close',{}).get('truncated') for p in periods):
  return 'contradicted','Waktu atau durasi yang dipilih berada di luar sesi buka provider',field
 return 'unknown','Sesi buka tidak lengkap untuk memastikan waktu kunjungan',field

def assess(place,n,now):
 types=set(place.get('types',[]));checks=[]
 separate=n['needs'].get('coffeeRelation',{}).get('value')=='separate'
 activity_groups=set(place.get('searchGroups',[]))
 url=place.get('googleMapsUri') or 'https://maps.google.com/?q=place_id:'+place['id']
 def add(key,label,status,text,field='',must=False,scope='venue'):
  checks.append({'id':key,'label':label,'status':status,'text':text,'field':field,
    'sourceURL':url if field else '', 'checkedAt':now.isoformat(),'must':must,'scope':scope})
 def coffee(must=False):
  v=place.get('servesCoffee')
  if v is True:add('coffee','Kopi','supported','Provider menyatakan menyediakan kopi','servesCoffee',must)
  elif v is False:add('coffee','Kopi','contradicted','Provider menyatakan tidak menyediakan kopi','servesCoffee',must)
  else:add('coffee','Kopi','unknown','Kategori kafe hanya petunjuk; ketersediaan kopi belum dipastikan','types',must)
 def read(value,must=False):
  if value=='buy' and 'book_store' in types:
   add('readingActivity','Mencari atau membeli buku','supported','Berkategori toko buku; stok, tiket dan layanan belum dipastikan','types',must)
  elif value=='buy':add('readingActivity','Mencari atau membeli buku','unknown','Kategori toko buku belum ditemukan; bukan bukti bahwa buku tidak dijual','types',must)
  else:
   hint='Berkategori perpustakaan. ' if 'library' in types else ''
   add('readingActivity','Membaca di tempat','unknown',hint+'Aturan membaca, tempat duduk dan lama kunjungan belum diketahui','types',must)
 for interest in n['interests']:
  if separate and interest not in activity_groups:
   key='coffee' if interest=='coffee' else 'readingActivity' if interest=='reading' else 'interest-'+interest
   label='Kopi' if interest=='coffee' else 'Kegiatan membaca' if interest=='reading' else 'Kegiatan lain'
   must=n['needs'].get('readingActivity',{}).get('must',False) if interest=='reading' else False
   add(key,label,'unknown','Dinilai pada pilihan kegiatan lain; tidak diwajibkan pada tempat ini','',must,'other_activity')
   continue
  if interest=='coffee':coffee(n['needs'].get('coffeeRelation',{}).get('must',False))
  elif interest=='reading':
   need=n['needs'].get('readingActivity')
   if need:read(need['value'],need['must'])
   else:add('readingActivity','Kegiatan membaca','unknown','Membaca di tempat atau mencari buku belum ditentukan')
  else:
   categories={'food':{'restaurant','food'},'culture':{'museum','cultural_center'},'shopping':{'shopping_mall','market','department_store'},
    'outdoors':{'park','garden','botanical_garden','national_park','zoo'},'arts':{'art_gallery','art_museum','art_studio'},
    'architecture':{'historical_landmark','historical_place','cultural_landmark'},'entertainment':{'movie_theater','amusement_park','aquarium','tourist_attraction'}}
   labels={'food':'Kuliner','culture':'Museum dan budaya','shopping':'Belanja','outdoors':'Alam dan taman','arts':'Seni','architecture':'Arsitektur','entertainment':'Hiburan'}
   match=bool(types & categories.get(interest,set()))
   add('interest-'+interest,labels[interest],'supported' if match else 'unknown',
     'Kategori provider mendukung jenis kegiatan umum; pengalaman rinci belum dipastikan' if match else 'Kategori provider belum mendukung kebutuhan ini','types')
 for axis,need in n['needs'].items():
  value,must=need['value'],need['must']
  if axis=='coffeeRelation':
   if value=='together':
    supported=all(any(c['id']==key and c['status']=='supported' for c in checks) for key in ['coffee','readingActivity'])
    contradiction=any(c['id'] in ['coffee','readingActivity'] and c['status']=='contradicted' for c in checks)
    add(axis,'Buku dan kopi di satu tempat','contradicted' if contradiction else 'supported' if supported else 'unknown',
      'Kedua kebutuhan didukung pada identitas tempat yang sama' if supported else 'Seluruh kebutuhan harus didukung pada tempat yang sama; kecocokan belum lengkap','',must)
   else:add(axis,'Boleh di tempat berbeda','unknown','Kandidat dicari per kegiatan; pasangan tempat dan rutenya belum disusun','',must,'trip')
  elif axis=='cultureActivity':add(axis,'Isi pameran' if value=='exhibits' else 'Pengalaman arsitektur','unknown','Kategori museum/bangunan belum membuktikan jenis pameran, akses atau pengalaman arsitektur','types',must)
  elif axis=='outdoorMoment':add(axis,'Pengalaman saat senja' if value=='sunset' else 'Kegiatan saat terang','unknown','Waktu terbaik, paparan cuaca dan kondisi langit belum dinilai','',must)
  elif axis=='spending':
   if value=='flexible':add(axis,'Pengeluaran fleksibel','supported','Tidak ada batas rupiah yang ditetapkan pengguna','',must)
   else:
    price=place.get('priceLevel'); supported=price in ['PRICE_LEVEL_FREE','PRICE_LEVEL_INEXPENSIVE']
    add(axis,'Pengeluaran lebih hemat','supported' if supported else 'unknown',
      'Provider menandai tingkat harga rendah; bukan total biaya perjalanan' if supported else 'Belum ada bukti biaya rendah yang cukup; tidak dibuat batas rupiah','priceLevel' if price else '',must)
  elif axis=='walking':add(axis,'Sedikit berjalan' if value=='low' else 'Boleh menjelajah','unknown',
      'Pintu masuk, perpindahan dan jarak berjalan belum dihitung; kategori tempat tidak membuktikannya','',must)
 if place.get('businessStatus') in ['CLOSED_PERMANENTLY','CLOSED_TEMPORARILY']:
  add('business','Status operasional','contradicted','Provider mencatat tempat tutup','businessStatus',True)
 elif place.get('businessStatus')=='OPERATIONAL':add('business','Status operasional','supported','Provider mencatat tempat beroperasi; bukan kepastian sedang buka','businessStatus')
 else:add('business','Status operasional','unknown','Status operasional belum tersedia','businessStatus')
 if n['visit']:
  status,text,field=hours_state(place,n['visit'],n['duration'],now);add('visitHours','Jam kunjungan',status,text,field,True)
 required=[c for c in checks if c['must'] and c['scope']=='venue']
 required_status='not_requested' if not required else 'contradicted' if any(c['status']=='contradicted' for c in required) else 'unknown' if any(c['status']=='unknown' for c in required) else 'supported'
 local=[c for c in checks if c['scope']=='venue']
 status='conflict' if any(c['status']=='contradicted' for c in local) else 'conditional' if any(c['status']=='unknown' for c in local) else 'supported'
 return checks,status,required_status

class LivePlaces:
 def __init__(self,key,transport,local,max_calls=100):
  self.key=key;self.transport=transport;self.local=Path(local);self.max_calls=max_calls
  self.lock=threading.Lock();self.day=dt.datetime.now(dt.timezone.utc).date().isoformat()
  self.pagination_key=secrets.token_bytes(32)
  try:
   old=json.loads((self.local/'places-usage.json').read_text());self.count=old.get('attempts',0) if old.get('day')==self.day else 0
  except (OSError,ValueError):self.count=0
 def call(self,url,body,fields,timeout=8,method='POST',tally=None):
  with self.lock:
   today=dt.datetime.now(dt.timezone.utc).date().isoformat()
   if today!=self.day:self.day=today;self.count=0
   if self.count>=self.max_calls:raise RuntimeError('places_budget')
   self.count+=1
   if tally is not None:tally[0]+=1
   self.local.mkdir(parents=True,exist_ok=True)
   (self.local/'places-usage.json').write_text(json.dumps({'day':self.day,'attempts':self.count,'cap':self.max_calls}))
  return self.transport(url,body,{'X-Goog-Api-Key':self.key,'X-Goog-FieldMask':fields},timeout,method=method)
 def context(self,n):
  data={k:n[k] for k in ['interests','needs','area','duration']};data['visit']=n['visit'].isoformat() if n['visit'] else None
  return hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
 def pack_token(self,token,context,query):
  payload=json.dumps({'token':token,'context':context,'query':query,'expires':time.time()+600},separators=(',',':')).encode()
  sig=hmac.new(self.pagination_key,payload,hashlib.sha256).hexdigest()
  return base64.urlsafe_b64encode(payload).decode()+'.'+sig
 def unpack_token(self,token,context,query):
  try:
   raw,sig=token.rsplit('.',1);payload=base64.urlsafe_b64decode(raw);data=json.loads(payload)
   if not hmac.compare_digest(sig,hmac.new(self.pagination_key,payload,hashlib.sha256).hexdigest()) or data['context']!=context or data['query']!=query or data['expires']<time.time():raise ValueError('stale_pagination')
   return data['token']
  except (ValueError,KeyError,TypeError):raise ValueError('pagination_context') from None
 def discover(self,data):
  began=time.monotonic();n=normalize(data);groups=plan(n);attempts=[0];warnings=[];deadline=began+18
  context=self.context(n)
  if n['tokens'] is not None:
   allowed={g['id'] for g in groups}
   if not n['tokens'] or set(n['tokens'])-allowed:raise ValueError('Pagination context mismatch')
   groups=[g for g in groups if g['id'] in n['tokens']]
   for g in groups:n['tokens'][g['id']]=self.unpack_token(n['tokens'][g['id']],context,g['query'])
  def search(g):
   if time.monotonic()>=deadline:return g,{},'deadline'
   body={'textQuery':g['query'],'languageCode':'id','pageSize':6}
   if n['tokens'] is not None:body['pageToken']=n['tokens'][g['id']]
   try:return g,self.call('https://places.googleapis.com/v1/places:searchText',body,SEARCH_FIELDS, min(8,max(.2,deadline-time.monotonic())),tally=attempts),None
   except (RuntimeError,ValueError,TimeoutError) as e:return g,{},type(e).__name__
  with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:responses=list(pool.map(search,groups))
  merged={};order=[];next_tokens={};out_groups=[]
  for g,r,error in responses:
   out_groups.append({'id':g['id'],'label':g['label'],'query':g['query'],'count':len(r.get('places',[])),'error':error})
   if error:warnings.append('Pencarian '+g['label']+' belum tersedia; kebutuhan tetap dipertahankan.')
   if r.get('nextPageToken'):next_tokens[g['id']]=self.pack_token(r['nextPageToken'],context,g['query'])
   for index,p in enumerate(r.get('places',[])):
    ident=p.get('id')
    if not isinstance(ident,str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,200}',ident):continue
    if ident not in merged:merged[ident]=dict(p,searchGroups=[g['id']],providerPosition=index+1);order.append(ident)
    elif g['id'] not in merged[ident]['searchGroups']:merged[ident]['searchGroups'].append(g['id'])
  # Select just the fields relevant to the current needs, never reviews/prose/photos.
  fields=['id','businessStatus','attributions']
  if 'coffee' in n['interests']:fields+=['servesCoffee','dineIn']
  if 'spending' in n['needs']:fields+=['priceLevel','priceRange']
  if n['visit']:fields+=['currentOpeningHours','regularOpeningHours','utcOffsetMinutes']
  def details(ident):
   if time.monotonic()>=deadline:return ident,None
   try:
    p=self.call('https://places.googleapis.com/v1/places/'+ident,{},','.join(fields),min(5,max(.2,deadline-time.monotonic())),method='GET',tally=attempts)
    return ident,p if p.get('id')==ident else None
   except (RuntimeError,ValueError,TimeoutError):return ident,None
  # Fairly enrich across groups. Separate reading stops need not fetch coffee facts.
  enrich=[]
  for group in groups:
   match=next((i for i in order if group['id'] in merged[i]['searchGroups'] and i not in enrich),None)
   if match:enrich.append(match)
  enrich=(enrich+[i for i in order if i not in enrich])
  separate=n['needs'].get('coffeeRelation',{}).get('value')=='separate'
  enrich=[i for i in enrich if n['visit'] or 'spending' in n['needs'] or ('coffee' in n['interests'] and (not separate or 'coffee' in merged[i]['searchGroups']))][:18]
  if len(fields)>3:
   with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    for ident,d in pool.map(details,enrich):
     if d:merged[ident].update(d)
     else:warnings.append('Sebagian detail tempat belum tersedia; ditandai belum diketahui.')
  now=dt.datetime.now(WIB);cards=[]
  for ident in order:
   p=merged[ident];checks,status,required=assess(p,n,now)
   cards.append({'id':ident,'name':p.get('displayName',{}).get('text','Nama belum tersedia'),
    'address':p.get('formattedAddress','Alamat belum tersedia'),'googleMapsURL':p.get('googleMapsUri'),
    'types':p.get('types',[]),'searchGroups':p['searchGroups'],'providerPosition':p['providerPosition'],
    'checks':checks,'status':status,'requiredStatus':required,'attributions':p.get('attributions',[])})
  if not cards:warnings.append('Belum ada hasil. Preferensi tidak diubah atau dilonggarkan.')
  if 'coffee' in n['interests'] and 'reading' in n['interests'] and 'coffeeRelation' not in n['needs']:
   warnings.append('Hubungan tempat untuk kopi dan membaca belum ditentukan; hasil dikelompokkan per kegiatan.')
  return {'requestID':n['requestID'],'revision':n['revision'],'places':cards,'searches':out_groups,
    'pageTokens':next_tokens,'warnings':list(dict.fromkeys(warnings)),
    'notice':'Hasil Google Maps sesuai urutan provider per pencarian. Penilaian kebutuhan dibuat aplikasi dari field yang tersedia.',
    'seconds':time.monotonic()-began,'providerCalls':attempts[0],'checkedAt':now.isoformat()}
