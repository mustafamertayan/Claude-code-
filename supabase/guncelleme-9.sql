-- =====================================================================
-- Kültürİz güncelleme 9: tam yasaklama (hesap + IP)
-- Yasaklanan hesap ve yasaklanan IP adreslerinden gelen istekler, yönetici yasağı
-- kaldırana kadar hiçbir veriyi göremez ve hiçbir şey yazamaz. Yöneticiler etkilenmez.
-- Supabase panelinde: SQL Editor > New query > bu dosyanın tamamını yapıştır > Run
-- Birden fazla kez çalıştırmak güvenlidir.
-- =====================================================================

-- Üyelerin bağlandığı ağlar (IPv4 tam adres, IPv6 /64 ağ). Yalnızca yönetici görür.
create table if not exists public.kullanici_ipleri (
  kullanici_id uuid not null references public.profiller(id) on delete cascade,
  ag           cidr not null,
  ilk          timestamptz not null default now(),
  son          timestamptz not null default now(),
  primary key (kullanici_id, ag)
);
create index if not exists kullanici_ipleri_ag_idx on public.kullanici_ipleri using gist (ag inet_ops);

create table if not exists public.yasakli_ipler (
  ag           cidr primary key,
  kullanici_id uuid references public.profiller(id) on delete set null,
  olusturma    timestamptz not null default now()
);
create index if not exists yasakli_ipler_ag_idx on public.yasakli_ipler using gist (ag inet_ops);

alter table public.kullanici_ipleri enable row level security;
alter table public.yasakli_ipler enable row level security;
revoke all on public.kullanici_ipleri from anon, authenticated;
revoke all on public.yasakli_ipler from anon, authenticated;

-- İsteğin geldiği ağ
create or replace function public.istek_ag() returns cidr
language plpgsql stable as $$
declare h json; ip inet; t text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then return null;
  end;
  if h is null then return null; end if;
  t := btrim(coalesce(nullif(h->>'cf-connecting-ip', ''), nullif(h->>'x-real-ip', ''), split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1)));
  if t = '' then return null; end if;
  begin
    ip := t::inet;
  exception when others then return null;
  end;
  if family(ip) = 6 then return network(set_masklen(ip, 64))::cidr; end if;
  return network(set_masklen(ip, 32))::cidr;
end $$;

create or replace function public.ip_engelli() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.yasakli_ipler y where public.istek_ag() <<= y.ag);
$$;

-- Bu istek engelli mi? (yasaklı hesap ya da yasaklı IP; yöneticiler hariç)
create or replace function public.engelli() returns boolean
language sql stable security definer set search_path = public as $$
  select not public.yonetici_mi() and (
    exists (select 1 from public.profiller where id = auth.uid() and yasakli)
    or public.ip_engelli()
  );
$$;
grant execute on function public.engelli() to anon, authenticated;

-- Kısıtlı üye artık hiçbir şey yazamaz (eskisi gibi) ve IP'si yasaklıysa da yazamaz.
create or replace function public.aktif_uye() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiller where id = auth.uid() and not yasakli and public.yas_uygun(dogum_tarihi))
     and not public.ip_engelli();
$$;

-- Site açılışında çağrılır: erişim durumu + (giriş yapılmışsa) bağlanılan ağı kaydeder.
create or replace function public.erisim_kontrol() returns json
language plpgsql volatile security definer set search_path = public as $$
declare a cidr := public.istek_ag(); hesap boolean := false; ipy boolean;
begin
  if auth.uid() is not null and a is not null and exists (select 1 from public.profiller where id = auth.uid()) then
    insert into public.kullanici_ipleri (kullanici_id, ag) values (auth.uid(), a)
    on conflict (kullanici_id, ag) do update set son = now();
  end if;
  if public.yonetici_mi() then return json_build_object('engelli', false); end if;
  select coalesce(yasakli, false) into hesap from public.profiller where id = auth.uid();
  ipy := public.ip_engelli();
  return json_build_object('engelli', coalesce(hesap, false) or ipy, 'neden', case when coalesce(hesap, false) then 'hesap' when ipy then 'ip' end);
end $$;
revoke all on function public.erisim_kontrol() from public;
grant execute on function public.erisim_kontrol() to anon, authenticated;

-- Engelli isteklere tüm tablolar kapalı (kısıtlayıcı politika, diğer kurallarla birlikte uygulanır).
do $$
declare t text;
begin
  foreach t in array array['profiller', 'gonderiler', 'begeniler', 'kayitlar', 'yorumlar', 'sikayetler', 'mesajlar', 'oyun_skorlari'] loop
    if to_regclass('public.' || t) is not null then
      execute format('drop policy if exists ip_engel on public.%I', t);
      execute format('create policy ip_engel on public.%I as restrictive for all to anon, authenticated using (not (select public.engelli())) with check (not (select public.engelli()))', t);
    end if;
  end loop;
end $$;

-- Fotoğraf/video yükleme de kapalı
drop policy if exists "medya_yukle" on storage.objects;
create policy "medya_yukle" on storage.objects for insert to authenticated
  with check (bucket_id = 'medya' and (storage.foldername(name))[1] = auth.uid()::text and public.aktif_uye());

-- ---------- Yönetici işlemleri ----------
create or replace function public.yonetici_ip_listesi(uid uuid)
returns table (ag text, son timestamptz, paylasan int, yasakli boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501'; end if;
  return query
    select host(k.ag) || case when family(k.ag) = 6 then '/64' else '' end, k.son,
           (select count(*)::int from public.kullanici_ipleri o where o.ag = k.ag and o.kullanici_id <> uid),
           exists (select 1 from public.yasakli_ipler y where k.ag <<= y.ag)
    from public.kullanici_ipleri k where k.kullanici_id = uid
    order by k.son desc limit 30;
end $$;

create or replace function public.yonetici_yasakla(uid uuid, aglar text[]) returns void
language plpgsql security definer set search_path = public as $$
declare a text;
begin
  if not public.yonetici_mi() then raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501'; end if;
  if uid = auth.uid() then raise exception 'Kendini yasaklayamazsın.' using errcode = 'P0001'; end if;
  if exists (select 1 from public.profiller where id = uid and rol = 'admin') then
    raise exception 'Önce bu kişinin yöneticiliğini al.' using errcode = 'P0001';
  end if;
  update public.profiller set yasakli = true where id = uid;
  foreach a in array coalesce(aglar, '{}') loop
    -- Yalnızca bu üyenin gerçekten kullandığı ağlar yasaklanabilir.
    insert into public.yasakli_ipler (ag, kullanici_id)
    select k.ag, uid from public.kullanici_ipleri k where k.kullanici_id = uid and k.ag = a::cidr
    on conflict (ag) do nothing;
  end loop;
end $$;

create or replace function public.yonetici_yasak_kaldir(uid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501'; end if;
  update public.profiller set yasakli = false where id = uid;
  delete from public.yasakli_ipler where kullanici_id = uid;
end $$;

create or replace function public.yonetici_yasakli_ipler()
returns table (ag text, ad text, olusturma timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501'; end if;
  return query
    select host(y.ag) || case when family(y.ag) = 6 then '/64' else '' end, coalesce(p.ad, 'Silinmiş hesap'), y.olusturma
    from public.yasakli_ipler y left join public.profiller p on p.id = y.kullanici_id
    order by y.olusturma desc;
end $$;

create or replace function public.yonetici_ip_kaldir(a text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501'; end if;
  delete from public.yasakli_ipler where ag = a::cidr;
end $$;

revoke all on function public.yonetici_ip_listesi(uuid) from public, anon;
revoke all on function public.yonetici_yasakla(uuid, text[]) from public, anon;
revoke all on function public.yonetici_yasak_kaldir(uuid) from public, anon;
revoke all on function public.yonetici_yasakli_ipler() from public, anon;
revoke all on function public.yonetici_ip_kaldir(text) from public, anon;
grant execute on function public.yonetici_ip_listesi(uuid) to authenticated;
grant execute on function public.yonetici_yasakla(uuid, text[]) to authenticated;
grant execute on function public.yonetici_yasak_kaldir(uuid) to authenticated;
grant execute on function public.yonetici_yasakli_ipler() to authenticated;
grant execute on function public.yonetici_ip_kaldir(text) to authenticated;

notify pgrst, 'reload schema';
