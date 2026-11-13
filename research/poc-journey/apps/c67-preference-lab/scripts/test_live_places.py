import datetime as dt, json, tempfile, unittest, uuid
from pathlib import Path
from live_places import LivePlaces, assess, hours_state, normalize, plan, WIB

def request(interests=None,needs=None,**extra):
 return dict(requestID=str(uuid.uuid4()),revision=1,interests=interests or ['reading'],needs=needs or {},area='Jakarta Pusat',**extra)
def need(value,must=False):return {'value':value,'must':must}
def place(ident='owned-a',**extra):
 return dict(id=ident,displayName={'text':'Authored adapter fixture'},formattedAddress='Synthetic address',googleMapsUri='https://maps.google.com/',types=['library'],businessStatus='OPERATIONAL',**extra)
NOW=dt.datetime(2026,11,9,12,tzinfo=WIB)

class LivePlaceTests(unittest.TestCase):
 def test_no_interests_cannot_invent_reading(self):
  r=request();r['interests']=[]
  with self.assertRaises(ValueError):normalize(r)
 def test_shopping_never_defaults_to_reading(self):
  groups=plan(normalize(request(['shopping'])))
  self.assertEqual([g['id'] for g in groups],['shopping']);self.assertNotIn('perpustakaan',groups[0]['query'])
 def test_relation_preserves_all_interests(self):
  combined=request(['reading','coffee'],{'readingActivity':need('buy'),'coffeeRelation':need('together')})
  groups=plan(normalize(combined));self.assertEqual(len(groups),1);self.assertIn('toko buku kafe',groups[0]['query'])
  combined['needs']['coffeeRelation']=need('separate');groups=plan(normalize(combined))
  self.assertEqual({g['id'] for g in groups},{'reading','coffee'})
 def test_unrelated_fields_and_unselected_activities_rejected(self):
  for r in [request(answers={'hidden':'answer'}),request(['shopping'],{'readingActivity':need('onsite')})]:
   with self.assertRaises(ValueError):normalize(r)
 def test_library_type_does_not_certify_reading_or_required_need(self):
  n=normalize(request(needs={'readingActivity':need('onsite',True)}))
  checks,status,required=assess(place(),n,NOW)
  self.assertEqual(required,'unknown');self.assertEqual(status,'conditional')
  self.assertEqual(next(c for c in checks if c['id']=='readingActivity')['status'],'unknown')
 def test_coffee_missing_is_not_false(self):
  n=normalize(request(['coffee']))
  for v,expected in [(None,'unknown'),(True,'supported'),(False,'contradicted')]:
   p=place()
   if v is not None:p['servesCoffee']=v
   checks,_,_=assess(p,n,NOW)
   self.assertEqual(next(c for c in checks if c['id']=='coffee')['status'],expected)
 def test_combined_activity_needs_both_facts_at_same_place(self):
  n=normalize(request(['reading','coffee'],{'readingActivity':need('buy'),'coffeeRelation':need('together',True)}))
  p=place(servesCoffee=True);p['types']=['book_store','cafe']
  checks,_,required=assess(p,n,NOW);self.assertEqual(required,'supported')
  n['needs']['readingActivity']=need('onsite');checks,_,required=assess(p,n,NOW)
  self.assertEqual(required,'unknown')
 def test_permanent_closure_is_not_hidden(self):
  p=place();p['businessStatus']='CLOSED_PERMANENTLY'
  checks,status,required=assess(p,normalize(request()),NOW)
  self.assertEqual(status,'conflict');self.assertEqual(required,'contradicted')
 def hours(self):
  return {'utcOffsetMinutes':420,'currentOpeningHours':{'periods':[{'open':{'date':{'year':2026,'month':11,'day':10},'hour':10},'close':{'date':{'year':2026,'month':11,'day':10},'hour':17}}]}}
 def test_full_dwell_and_closing_boundary(self):
  p=self.hours()
  self.assertEqual(hours_state(p,dt.datetime(2026,11,10,16,tzinfo=WIB),60,NOW)[0],'supported')
  self.assertEqual(hours_state(p,dt.datetime(2026,11,10,16,30,tzinfo=WIB),60,NOW)[0],'contradicted')
  self.assertEqual(hours_state(p,dt.datetime(2026,11,10,17,tzinfo=WIB),None,NOW)[0],'contradicted')
 def test_weekly_hours_and_unknown_timezone_are_not_date_verification(self):
  p={'regularOpeningHours':{'openNow':True}}
  self.assertEqual(hours_state(p,dt.datetime(2026,11,10,10,tzinfo=WIB),None,NOW)[0],'unknown')
  p=self.hours();p.pop('utcOffsetMinutes')
  self.assertEqual(hours_state(p,dt.datetime(2026,11,10,10,tzinfo=WIB),None,NOW)[0],'unknown')
 def test_truncated_and_far_future_hours_remain_unknown(self):
  p=self.hours();p['currentOpeningHours']['periods'][0]['close']['truncated']=True
  self.assertEqual(hours_state(p,dt.datetime(2026,11,10,18,tzinfo=WIB),None,NOW)[0],'unknown')
  self.assertEqual(hours_state(p,dt.datetime(2026,12,10,12,tzinfo=WIB),None,NOW)[0],'unknown')
 def test_order_dedup_and_signed_pagination(self):
  calls=[]
  def transport(url,body,headers,timeout,method='POST'):
   calls.append((url,body,headers))
   self.assertNotIn('reviews',headers['X-Goog-FieldMask']);self.assertNotIn('photos',headers['X-Goog-FieldMask'])
   if body.get('pageToken'):return {'places':[place('owned-b'),place('owned-c')]}
   return {'places':[place('owned-a'),place('owned-b')],'nextPageToken':'opaque-provider-token'}
  with tempfile.TemporaryDirectory() as folder:
   service=LivePlaces('dummy',transport,folder)
   data=request(needs={'readingActivity':need('buy')});r=service.discover(data)
   self.assertEqual([p['id'] for p in r['places']],['owned-a','owned-b'])
   follow=dict(data,pageTokens=r['pageTokens']);page=service.discover(follow)
   self.assertEqual([p['id'] for p in page['places']],['owned-b','owned-c'])
   changed=dict(data,area='Jakarta Selatan',pageTokens=r['pageTokens'])
   with self.assertRaises(ValueError):service.discover(changed)
 def test_partial_provider_failure_keeps_other_group_and_needs(self):
  def transport(url,body,headers,timeout,method='POST'):
   if 'perpustakaan' in body.get('textQuery',''):raise RuntimeError('provider_timeout')
   if method=='GET':return {'id':url.rsplit('/',1)[1],'servesCoffee':True}
   return {'places':[place()]}
  with tempfile.TemporaryDirectory() as folder:
   service=LivePlaces('dummy',transport,folder)
   r=service.discover(request(['coffee','reading'],{'readingActivity':need('onsite',True),'coffeeRelation':need('separate')}))
   self.assertEqual(len(r['places']),1);self.assertTrue(r['warnings'])
   read=next(c for c in r['places'][0]['checks'] if c['id']=='readingActivity')
   self.assertEqual(read['scope'],'other_activity');self.assertEqual(r['places'][0]['requiredStatus'],'not_requested')
 def test_separate_activities_do_not_require_library_to_serve_coffee(self):
  n=normalize(request(['reading','coffee'],{'readingActivity':need('onsite',True),'coffeeRelation':need('separate',True)}))
  p=place(servesCoffee=False);p['searchGroups']=['reading']
  checks,status,_=assess(p,n,NOW)
  coffee=next(c for c in checks if c['id']=='coffee')
  self.assertEqual(coffee['scope'],'other_activity');self.assertNotEqual(status,'conflict')
 def test_exhausted_budget_is_explicit_empty_result(self):
  with tempfile.TemporaryDirectory() as folder:
   service=LivePlaces('dummy',lambda *a,**k:self.fail('must not call'),folder,max_calls=0)
   r=service.discover(request())
   self.assertEqual(r['providerCalls'],0);self.assertEqual(r['places'],[]);self.assertTrue(r['warnings'])

if __name__=='__main__':unittest.main()
