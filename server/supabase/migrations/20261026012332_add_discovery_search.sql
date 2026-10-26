create index rundown_search_idx on public.rundown_versions using gin(to_tsvector('simple',title||' '||area||' '||summary)) where published;
create index rundown_area_id_idx on public.rundown_versions(lower(area),id desc) where published;
create function public.search_rundowns(p_query text default '',p_area text default null,p_limit integer default 20,p_cursor text default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare q text:=lower(btrim(coalesce(p_query,''))); a text:=nullif(lower(btrim(p_area)),''); after_id uuid; c jsonb; result jsonb;
begin
 if length(q)>120 or length(a)>80 or p_limit is null or p_limit not between 1 and 50 then raise sqlstate 'PT400' using message='Invalid discovery filters or limit'; end if;
 if p_cursor is not null then begin
  if length(p_cursor)>1024 then raise invalid_parameter_value; end if;
  c:=convert_from(decode(p_cursor,'base64'),'UTF8')::jsonb;
  if c->>'q' is distinct from q or c->>'a' is distinct from a or c->>'v' is distinct from '1' then raise invalid_parameter_value; end if;
  after_id:=(c->>'id')::uuid; if after_id is null then raise invalid_parameter_value; end if;
 exception when data_exception then raise sqlstate 'PT400' using message='Invalid discovery cursor'; end; end if;
 with page as materialized(select id,title,area,summary,stops from public.rundown_versions
 where published and (a is null or lower(area)=a) and (q='' or to_tsvector('simple',title||' '||area||' '||summary) @@ plainto_tsquery('simple',q)) and (after_id is null or id<after_id) order by id desc limit p_limit+1),
 chosen as materialized(select * from page order by id desc limit p_limit)
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x) order by id desc) from chosen x),'[]'::jsonb),
 'next_cursor',case when (select count(*) from page)>p_limit then (select replace(encode(convert_to(jsonb_build_object('v',1,'q',q,'a',a,'id',id)::text,'UTF8'),'base64'),E'\n','') from chosen order by id asc limit 1) else null end) into result;
 return result;
end;
$$;
revoke all on function public.search_rundowns(text,text,integer,text) from public,anon,authenticated;
grant execute on function public.search_rundowns(text,text,integer,text) to anon,authenticated;
