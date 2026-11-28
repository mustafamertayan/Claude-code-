-- =====================================================================
-- Kültürİz veritabanı kurulumu
-- Supabase panelinde: SQL Editor > New query > bu dosyanın tamamını yapıştır > Run
-- Birden fazla kez çalıştırmak güvenlidir.
--
-- Önemli: Siteye İLK kayıt olan kişi otomatik olarak YÖNETİCİ (admin) olur.
-- Kurulumdan hemen sonra siteye ilk sen kayıt ol.
-- =====================================================================

-- ---------- Tablolar ----------
create table if not exists public.profiller (
  id         uuid primary key references auth.users(id) on delete cascade,
  ad         text not null default '' check (char_length(ad) <= 60),
  bio        text not null default '' check (char_length(bio) <= 150),
  foto_url   text not null default '',
  rol        text not null default 'uye' check (rol in ('uye', 'admin')),
  yasakli    boolean not null default false,
  olusturma  timestamptz not null default now()
);

create table if not exists public.gonderiler (
  id            uuid primary key default gen_random_uuid(),
  kullanici_id  uuid not null references public.profiller(id) on delete cascade,
  yer           text not null check (char_length(yer) between 2 and 80),
  konum         text not null default '' check (char_length(konum) <= 80),
  kategori      text not null default 'Diğer' check (char_length(kategori) <= 40),
  enlem         double precision not null check (enlem between -90 and 90),
  boylam        double precision not null check (boylam between -180 and 180),
  notu          text not null default '' check (char_length(notu) <= 500),
  medya         jsonb not null default '[]'::jsonb,
  olusturma     timestamptz not null default now()
);
create index if not exists gonderiler_olusturma_idx on public.gonderiler (olusturma desc);

-- gonderi_id metindir: örnek gönderiler ("efes" gibi) de beğenilip yorumlanabilsin diye.
create table if not exists public.begeniler (
  gonderi_id    text not null,
  kullanici_id  uuid not null references public.profiller(id) on delete cascade,
  olusturma     timestamptz not null default now(),
  primary key (gonderi_id, kullanici_id)
);
create table if not exists public.kayitlar (
  gonderi_id    text not null,
  kullanici_id  uuid not null references public.profiller(id) on delete cascade,
  olusturma     timestamptz not null default now(),
  primary key (gonderi_id, kullanici_id)
);
create table if not exists public.yorumlar (
  id            uuid primary key default gen_random_uuid(),
  gonderi_id    text not null,
  kullanici_id  uuid not null references public.profiller(id) on delete cascade,
  metin         text not null check (char_length(metin) between 1 and 500),
  olusturma     timestamptz not null default now()
);
create index if not exists yorumlar_gonderi_idx on public.yorumlar (gonderi_id, olusturma);

-- ---------- Yardımcı fonksiyonlar ----------
create or replace function public.yonetici_mi() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiller where id = auth.uid() and rol = 'admin');
$$;

create or replace function public.aktif_uye() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiller where id = auth.uid() and not yasakli);
$$;

-- Yeni kayıt olan herkese profil açılır; hiç yönetici yoksa ilk kişi yönetici olur.
create or replace function public.yeni_kullanici() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiller (id, ad, foto_url, rol)
  values (
    new.id,
    left(coalesce(nullif(new.raw_user_meta_data->>'ad', ''), nullif(new.raw_user_meta_data->>'full_name', ''),
                  nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)), 60),
    coalesce(new.raw_user_meta_data->>'avatar_url', ''),
    case when exists (select 1 from public.profiller where rol = 'admin') then 'uye' else 'admin' end
  )
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists yeni_kullanici on auth.users;
create trigger yeni_kullanici after insert on auth.users
  for each row execute function public.yeni_kullanici();

-- Üyeler kendi rolünü ya da kısıtlamasını değiştiremez; bunu yalnızca yönetici yapar.
create or replace function public.profil_koru() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then
    new.rol := old.rol;
    new.yasakli := old.yasakli;
  end if;
  new.id := old.id;
  return new;
end $$;
drop trigger if exists profil_koru on public.profiller;
create trigger profil_koru before update on public.profiller
  for each row execute function public.profil_koru();

-- Gönderi silinince ona ait beğeni, kayıt ve yorumlar da silinir.
create or replace function public.gonderi_temizle() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.begeniler where gonderi_id = old.id::text;
  delete from public.kayitlar  where gonderi_id = old.id::text;
  delete from public.yorumlar  where gonderi_id = old.id::text;
  return old;
end $$;
drop trigger if exists gonderi_temizle on public.gonderiler;
create trigger gonderi_temizle after delete on public.gonderiler
  for each row execute function public.gonderi_temizle();

-- ---------- Satır düzeyi güvenlik (kim neyi görür, kim neyi değiştirir) ----------
alter table public.profiller  enable row level security;
alter table public.gonderiler enable row level security;
alter table public.begeniler  enable row level security;
alter table public.kayitlar   enable row level security;
alter table public.yorumlar   enable row level security;

drop policy if exists "profiller_oku" on public.profiller;
create policy "profiller_oku" on public.profiller for select using (true);
drop policy if exists "profiller_guncelle" on public.profiller;
create policy "profiller_guncelle" on public.profiller for update
  using (id = auth.uid() or public.yonetici_mi()) with check (id = auth.uid() or public.yonetici_mi());

drop policy if exists "gonderiler_oku" on public.gonderiler;
create policy "gonderiler_oku" on public.gonderiler for select using (true);
drop policy if exists "gonderiler_ekle" on public.gonderiler;
create policy "gonderiler_ekle" on public.gonderiler for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye());
drop policy if exists "gonderiler_sil" on public.gonderiler;
create policy "gonderiler_sil" on public.gonderiler for delete to authenticated
  using (kullanici_id = auth.uid() or public.yonetici_mi());

drop policy if exists "begeniler_oku" on public.begeniler;
create policy "begeniler_oku" on public.begeniler for select using (true);
drop policy if exists "begeniler_ekle" on public.begeniler;
create policy "begeniler_ekle" on public.begeniler for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye());
drop policy if exists "begeniler_sil" on public.begeniler;
create policy "begeniler_sil" on public.begeniler for delete to authenticated using (kullanici_id = auth.uid());

drop policy if exists "kayitlar_oku" on public.kayitlar;
create policy "kayitlar_oku" on public.kayitlar for select to authenticated using (kullanici_id = auth.uid());
drop policy if exists "kayitlar_ekle" on public.kayitlar;
create policy "kayitlar_ekle" on public.kayitlar for insert to authenticated with check (kullanici_id = auth.uid());
drop policy if exists "kayitlar_sil" on public.kayitlar;
create policy "kayitlar_sil" on public.kayitlar for delete to authenticated using (kullanici_id = auth.uid());

drop policy if exists "yorumlar_oku" on public.yorumlar;
create policy "yorumlar_oku" on public.yorumlar for select using (true);
drop policy if exists "yorumlar_ekle" on public.yorumlar;
create policy "yorumlar_ekle" on public.yorumlar for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye());
drop policy if exists "yorumlar_sil" on public.yorumlar;
create policy "yorumlar_sil" on public.yorumlar for delete to authenticated
  using (kullanici_id = auth.uid() or public.yonetici_mi());

-- ---------- Beğeni ve yorum sayıları ----------
create or replace view public.gonderi_sayilari with (security_invoker = on) as
  select gonderi_id, sum(b)::int as begeni, sum(y)::int as yorum
  from (select gonderi_id, 1 as b, 0 as y from public.begeniler
        union all
        select gonderi_id, 0, 1 from public.yorumlar) t
  group by gonderi_id;
grant select on public.gonderi_sayilari to anon, authenticated;

-- ---------- Yönetici: üye listesi (e-postalar yalnızca yöneticiye görünür) ----------
create or replace function public.yonetici_kullanicilar()
returns table (id uuid, ad text, eposta text, rol text, yasakli boolean, olusturma timestamptz, gonderi int, yorum int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then
    raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501';
  end if;
  return query
    select p.id, p.ad, u.email::text, p.rol, p.yasakli, p.olusturma,
           (select count(*)::int from public.gonderiler g where g.kullanici_id = p.id),
           (select count(*)::int from public.yorumlar y where y.kullanici_id = p.id)
    from public.profiller p join auth.users u on u.id = p.id
    order by p.olusturma desc;
end $$;
revoke all on function public.yonetici_kullanicilar() from public, anon;
grant execute on function public.yonetici_kullanicilar() to authenticated;

-- ---------- Fotoğraf ve video deposu ----------
-- Herkes görebilir; üyeler yalnızca kendi klasörlerine (kullanıcı kimliği) yükleyebilir. Dosya sınırı aşağıda (güncelleme 8) 15 MB yapılır.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('medya', 'medya', true, 52428800, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "medya_oku" on storage.objects;
create policy "medya_oku" on storage.objects for select using (bucket_id = 'medya');
drop policy if exists "medya_yukle" on storage.objects;
create policy "medya_yukle" on storage.objects for insert to authenticated
  with check (bucket_id = 'medya' and (storage.foldername(name))[1] = auth.uid()::text and public.aktif_uye());
drop policy if exists "medya_sil" on storage.objects;
create policy "medya_sil" on storage.objects for delete to authenticated
  using (bucket_id = 'medya' and ((storage.foldername(name))[1] = auth.uid()::text or public.yonetici_mi()));

-- ---------- Gerekirse: bir hesabı elle yönetici yapmak ----------
-- update public.profiller set rol = 'admin'
--   where id = (select id from auth.users where email = 'SENIN@EPOSTAN.com');

-- ---------- Güvenlik kuralları (supabase/guvenlik-1.sql ile aynı) ----------
create or replace function public.medya_gecerli(m jsonb, uid uuid) returns boolean
language sql immutable as $$
  select jsonb_typeof(m) = 'array'
     and jsonb_array_length(m) between 1 and 10
     and not exists (
       select 1 from jsonb_array_elements(m) e
       where not (
         jsonb_typeof(e) = 'object'
         and coalesce(e->>'tur', '') in ('foto', 'video')
         and coalesce(e->>'yol', '') like uid::text || '/%'
         and coalesce(e->>'url', '') like 'https://%.supabase.co/storage/v1/object/public/medya/' || uid::text || '/%'
         and coalesce(e->>'url', '') !~ '["''<>\s\\]'
       )
     );
$$;
alter table public.gonderiler drop constraint if exists medya_gecerli;
alter table public.gonderiler add constraint medya_gecerli check (public.medya_gecerli(medya, kullanici_id)) not valid;

-- Profil fotoğrafı: boş, bu projenin deposu ya da Google hesap fotoğrafı.
alter table public.profiller drop constraint if exists foto_url_gecerli;
alter table public.profiller add constraint foto_url_gecerli check (
  foto_url = ''
  or (foto_url ~ '^https://([a-z0-9-]+\.supabase\.co/storage/v1/object/public/medya/|[a-z0-9.-]+\.googleusercontent\.com/)'
      and foto_url !~ '["''<>\s\\]')
) not valid;

-- Toplu spam'e karşı günlük sınır: kişi başı 24 saatte en fazla 20 gönderi ve 200 yorum.
create or replace function public.gunluk_sinir() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if tg_table_name = 'gonderiler' then
    select count(*) into n from public.gonderiler where kullanici_id = new.kullanici_id and olusturma > now() - interval '24 hours';
    if n >= 20 then raise exception 'Günlük gönderi sınırına ulaştın (20). Yarın tekrar dene.' using errcode = 'P0001'; end if;
  else
    select count(*) into n from public.yorumlar where kullanici_id = new.kullanici_id and olusturma > now() - interval '24 hours';
    if n >= 200 then raise exception 'Günlük yorum sınırına ulaştın (200). Yarın tekrar dene.' using errcode = 'P0001'; end if;
  end if;
  return new;
end $$;
drop trigger if exists gunluk_sinir on public.gonderiler;
create trigger gunluk_sinir before insert on public.gonderiler for each row execute function public.gunluk_sinir();
drop trigger if exists gunluk_sinir on public.yorumlar;
create trigger gunluk_sinir before insert on public.yorumlar for each row execute function public.gunluk_sinir();

-- ---------- Güvenlik güncellemesi 2 (supabase/guvenlik-2.sql ile aynı) ----------
alter table public.profiller add column if not exists dogum_tarihi date;

create or replace function public.yas_uygun(d date) returns boolean
language sql stable as $$
  select d is not null and d >= date '1900-01-01' and d <= (current_date - interval '13 years')::date;
$$;

-- Yeni kayıtta doğum tarihi verildiyse 13 yaş kontrolü; ilk kayıt olan yönetici olur.
create or replace function public.yeni_kullanici() returns trigger
language plpgsql security definer set search_path = public as $$
declare d date;
begin
  begin
    d := nullif(new.raw_user_meta_data->>'dogum_tarihi', '')::date;
  exception when others then
    d := null;
  end;
  if d is not null and not public.yas_uygun(d) then
    raise exception 'Kültürİz için en az 13 yaşında olmalısın.' using errcode = 'P0001';
  end if;
  insert into public.profiller (id, ad, foto_url, rol, dogum_tarihi)
  values (
    new.id,
    left(coalesce(nullif(new.raw_user_meta_data->>'ad', ''), nullif(new.raw_user_meta_data->>'full_name', ''),
                  nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)), 60),
    coalesce(new.raw_user_meta_data->>'avatar_url', ''),
    case when exists (select 1 from public.profiller where rol = 'admin') then 'uye' else 'admin' end,
    d
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- Üyeler rolünü/kısıtlamasını değiştiremez; doğum tarihi bir kez girilir ve sonra değiştirilemez.
create or replace function public.profil_koru() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then
    new.rol := old.rol;
    new.yasakli := old.yasakli;
    if old.dogum_tarihi is not null then
      new.dogum_tarihi := old.dogum_tarihi;
    end if;
  end if;
  if new.dogum_tarihi is distinct from old.dogum_tarihi and new.dogum_tarihi is not null and not public.yas_uygun(new.dogum_tarihi) then
    raise exception 'Kültürİz için en az 13 yaşında olmalısın.' using errcode = 'P0001';
  end if;
  new.id := old.id;
  return new;
end $$;

-- Paylaşım, yorum ve beğeni için: kısıtlı olmamak ve yaş şartını karşılamak gerekir.
create or replace function public.aktif_uye() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiller where id = auth.uid() and not yasakli and public.yas_uygun(dogum_tarihi));
$$;

-- Doğum tarihi herkese açık profil bilgisinde görünmez; kişi yalnızca kendi tarihini okuyabilir.
revoke select on public.profiller from anon, authenticated;
grant select (id, ad, bio, foto_url, rol, yasakli, olusturma) on public.profiller to anon, authenticated;
revoke update on public.profiller from anon, authenticated;
grant update (ad, bio, foto_url, dogum_tarihi, rol, yasakli) on public.profiller to authenticated;

create or replace function public.benim_dogum_tarihim() returns date
language sql stable security definer set search_path = public as $$
  select dogum_tarihi from public.profiller where id = auth.uid();
$$;
revoke all on function public.benim_dogum_tarihim() from public, anon;
grant execute on function public.benim_dogum_tarihim() to authenticated;

-- ---------- Şikayetler ----------
create table if not exists public.sikayetler (
  id            uuid primary key default gen_random_uuid(),
  gonderi_id    text not null,
  kullanici_id  uuid not null references public.profiller(id) on delete cascade,
  neden         text not null check (char_length(neden) between 1 and 300),
  olusturma     timestamptz not null default now(),
  unique (gonderi_id, kullanici_id)
);
alter table public.sikayetler enable row level security;
drop policy if exists "sikayetler_ekle" on public.sikayetler;
create policy "sikayetler_ekle" on public.sikayetler for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye());
drop policy if exists "sikayetler_oku" on public.sikayetler;
create policy "sikayetler_oku" on public.sikayetler for select to authenticated using (public.yonetici_mi());
drop policy if exists "sikayetler_sil" on public.sikayetler;
create policy "sikayetler_sil" on public.sikayetler for delete to authenticated using (public.yonetici_mi());
grant select, insert, delete on public.sikayetler to authenticated;

-- Gönderi silinince şikayetleri de silinir.
create or replace function public.gonderi_temizle() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.begeniler  where gonderi_id = old.id::text;
  delete from public.kayitlar   where gonderi_id = old.id::text;
  delete from public.yorumlar   where gonderi_id = old.id::text;
  delete from public.sikayetler where gonderi_id = old.id::text;
  return old;
end $$;

-- ---------- Dosya deposu: listeleme kapalı ----------
-- Fotoğraf ve videolar herkese açık adresleriyle görünmeye devam eder; ama kimse depodaki dosyaların listesini çekemez.
drop policy if exists "medya_oku" on storage.objects;
create policy "medya_oku" on storage.objects for select to authenticated
  using (bucket_id = 'medya' and ((storage.foldername(name))[1] = auth.uid()::text or public.yonetici_mi()));

notify pgrst, 'reload schema';

-- ---------- Güncelleme 3 (supabase/guncelleme-3.sql ile aynı) ----------
create or replace function public.kelime_sayisi(t text) returns int
language sql immutable as $$
  select coalesce(array_length(regexp_split_to_array(btrim(coalesce(t, '')), '\s+'), 1), 0) - case when btrim(coalesce(t, '')) = '' then 1 else 0 end;
$$;

alter table public.profiller drop constraint if exists profiller_bio_check;
alter table public.profiller drop constraint if exists bio_uzunluk;
alter table public.profiller add constraint bio_uzunluk check (char_length(bio) <= 2000 and public.kelime_sayisi(bio) <= 250);

alter table public.gonderiler drop constraint if exists gonderiler_notu_check;
alter table public.gonderiler drop constraint if exists notu_uzunluk;
alter table public.gonderiler add constraint notu_uzunluk check (char_length(notu) <= 5000 and public.kelime_sayisi(notu) <= 700);

-- ---------- İlgi alanları ----------
alter table public.profiller add column if not exists ilgi_alanlari text[] not null default '{}';
create or replace function public.ilgi_gecerli(a text[]) returns boolean
language sql immutable as $$
  select coalesce(cardinality(a), 0) <= 3
     and not exists (select 1 from unnest(coalesce(a, '{}')) x where char_length(btrim(x)) not between 1 and 30);
$$;
alter table public.profiller drop constraint if exists ilgi_alanlari_gecerli;
alter table public.profiller add constraint ilgi_alanlari_gecerli check (public.ilgi_gecerli(ilgi_alanlari));
grant select (ilgi_alanlari) on public.profiller to anon, authenticated;
grant update (ilgi_alanlari) on public.profiller to authenticated;

-- ---------- Sansür ----------
-- Kelimeler küçük harfe çevrilir (Türkçe kurallarıyla), rakam/simge hileleri (s1kt1r, @, $) çözülür,
-- tekrarlanan harfler teke indirilir (siiiiktir -> siktir). Eşleşen kelimenin ilk harfi kalır, gerisi yıldız olur.
create or replace function public.kufur_mu(w text) returns boolean
language plpgsql immutable as $$
declare n text;
begin
  n := replace(replace(w, 'İ', 'i'), 'I', 'ı');
  n := lower(n);
  n := translate(n, '0134@$5€', 'oieaasse');
  n := regexp_replace(n, '[^[:alpha:]]', '', 'g');
  n := regexp_replace(n, '(.)\1+', '\1', 'g');
  if n = '' then return false; end if;
  if n = any (array[
      'amk','amq','amg','aq','mk','mq','oç','oc','pç','sik','göt','götü','götler','pust','dick','dicks','pusy','fck','niga'
    ]) then return true; end if;
  return n ~ ('^(orospu|orosbu|oruspu|orspu|yarak|yarağ|dalyarak|dalyarağ|amına|amınak|aminak|amcık|amcik|amını|siktir|sikeyim|sikerim|sikiyim|sikim|sikik|sikiş|siker|sikti'
           || '|götün|götver|götlek|ibne|kahpe|pezevenk|pezo|puşt|gavat|kaltak|fahişe|fahise|sürtük|surtuk|yavşak|yavsak|şerefsiz|serefsiz|gerizekalı|gerizekali|taşak|tasak|piç'
           || '|fuck|shit|bitch|ashole|motherf|cunt|whore|slut|retard|porn)');
end $$;

create or replace function public.sansurle(t text) returns text
language plpgsql immutable as $$
declare parca text; sonuc text := '';
begin
  if t is null or t = '' then return t; end if;
  for parca in select (regexp_matches(t, '([^[:space:][:punct:]]+|[[:space:][:punct:]]+)', 'g'))[1] loop
    if parca !~ '^[[:space:][:punct:]]+$' and public.kufur_mu(parca) then
      sonuc := sonuc || left(parca, 1) || repeat('*', char_length(parca) - 1);
    else
      sonuc := sonuc || parca;
    end if;
  end loop;
  return sonuc;
end $$;

create or replace function public.sansur_tetik() returns trigger
language plpgsql as $$
begin
  if tg_table_name = 'gonderiler' then
    new.yer := public.sansurle(new.yer); new.konum := public.sansurle(new.konum); new.notu := public.sansurle(new.notu);
  elsif tg_table_name = 'yorumlar' then
    new.metin := public.sansurle(new.metin);
  elsif tg_table_name = 'profiller' then
    new.ad := public.sansurle(new.ad); new.bio := public.sansurle(new.bio);
    new.ilgi_alanlari := coalesce((select array_agg(public.sansurle(x)) from unnest(new.ilgi_alanlari) x), '{}');
  elsif tg_table_name = 'sikayetler' then
    new.neden := public.sansurle(new.neden);
  end if;
  return new;
end $$;
drop trigger if exists sansur on public.gonderiler;
create trigger sansur before insert or update on public.gonderiler for each row execute function public.sansur_tetik();
drop trigger if exists sansur on public.yorumlar;
create trigger sansur before insert or update on public.yorumlar for each row execute function public.sansur_tetik();
drop trigger if exists sansur on public.profiller;
create trigger sansur before insert or update on public.profiller for each row execute function public.sansur_tetik();
drop trigger if exists sansur on public.sikayetler;
create trigger sansur before insert or update on public.sikayetler for each row execute function public.sansur_tetik();

-- Mevcut içerikleri de sansürden geçir.
update public.gonderiler set yer = public.sansurle(yer), konum = public.sansurle(konum), notu = public.sansurle(notu)
  where yer <> public.sansurle(yer) or konum <> public.sansurle(konum) or notu <> public.sansurle(notu);
update public.yorumlar set metin = public.sansurle(metin) where metin <> public.sansurle(metin);
update public.profiller set ad = public.sansurle(ad), bio = public.sansurle(bio) where ad <> public.sansurle(ad) or bio <> public.sansurle(bio);

notify pgrst, 'reload schema';

-- ---------- Güncelleme 4 (supabase/guncelleme-4.sql ile aynı) ----------
alter table public.profiller add column if not exists okul text;
alter table public.profiller add column if not exists sube text;
alter table public.profiller add column if not exists okul_no text;
alter table public.profiller drop constraint if exists okul_gecerli;
alter table public.profiller add constraint okul_gecerli check (
  (okul is null or char_length(btrim(okul)) between 2 and 80)
  and (sube is null or char_length(btrim(sube)) between 1 and 10)
  and (okul_no is null or okul_no ~ '^[0-9]{1,8}$')
);
-- Herkese açık profil sütunları değişmedi; okul bilgileri listede yok, yani başkaları göremez.
grant update (okul, sube, okul_no) on public.profiller to authenticated;

-- Kişinin kendi gizli bilgileri
create or replace function public.benim_bilgilerim() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('dogum_tarihi', dogum_tarihi, 'okul', okul, 'sube', sube, 'okul_no', okul_no)
  from public.profiller where id = auth.uid();
$$;
revoke all on function public.benim_bilgilerim() from public, anon;
grant execute on function public.benim_bilgilerim() to authenticated;

-- ---------- Kayıt: doğum tarihi + okul bilgileri ----------
create or replace function public.yeni_kullanici() returns trigger
language plpgsql security definer set search_path = public as $$
declare d date; o text; s text; n text; m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  begin
    d := nullif(m->>'dogum_tarihi', '')::date;
  exception when others then
    d := null;
  end;
  if d is not null and not public.yas_uygun(d) then
    raise exception 'Kültürİz için en az 13 yaşında olmalısın.' using errcode = 'P0001';
  end if;
  o := nullif(btrim(coalesce(m->>'okul', '')), '');
  s := nullif(btrim(coalesce(m->>'sube', '')), '');
  n := nullif(btrim(coalesce(m->>'okul_no', '')), '');
  if o is not null and char_length(o) not between 2 and 80 then o := null; end if;
  if s is not null and char_length(s) > 10 then s := null; end if;
  if n is not null and n !~ '^[0-9]{1,8}$' then n := null; end if;
  insert into public.profiller (id, ad, foto_url, rol, dogum_tarihi, okul, sube, okul_no)
  values (
    new.id,
    left(coalesce(nullif(m->>'ad', ''), nullif(m->>'full_name', ''), nullif(m->>'name', ''), split_part(new.email, '@', 1)), 60),
    coalesce(m->>'avatar_url', ''),
    case when exists (select 1 from public.profiller where rol = 'admin') then 'uye' else 'admin' end,
    d, o, s, n
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- Rol/kısıtlama yalnızca yönetici; doğum tarihi ve okul bilgileri bir kez girilir (yönetici düzeltebilir).
create or replace function public.profil_koru() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then
    new.rol := old.rol;
    new.yasakli := old.yasakli;
    if old.dogum_tarihi is not null then new.dogum_tarihi := old.dogum_tarihi; end if;
    if old.okul is not null then new.okul := old.okul; end if;
    if old.sube is not null then new.sube := old.sube; end if;
    if old.okul_no is not null then new.okul_no := old.okul_no; end if;
  end if;
  if new.dogum_tarihi is distinct from old.dogum_tarihi and new.dogum_tarihi is not null and not public.yas_uygun(new.dogum_tarihi) then
    raise exception 'Kültürİz için en az 13 yaşında olmalısın.' using errcode = 'P0001';
  end if;
  new.id := old.id;
  return new;
end $$;

-- Sansür okul ve şube alanlarını da kapsar.
create or replace function public.sansur_tetik() returns trigger
language plpgsql as $$
begin
  if tg_table_name = 'gonderiler' then
    new.yer := public.sansurle(new.yer); new.konum := public.sansurle(new.konum); new.notu := public.sansurle(new.notu);
  elsif tg_table_name = 'yorumlar' then
    new.metin := public.sansurle(new.metin);
  elsif tg_table_name = 'profiller' then
    new.ad := public.sansurle(new.ad); new.bio := public.sansurle(new.bio);
    new.okul := public.sansurle(new.okul); new.sube := public.sansurle(new.sube);
    new.ilgi_alanlari := coalesce((select array_agg(public.sansurle(x)) from unnest(new.ilgi_alanlari) x), '{}');
  elsif tg_table_name = 'sikayetler' then
    new.neden := public.sansurle(new.neden);
  end if;
  return new;
end $$;

-- Yönetici üye listesi: doğum tarihi ve okul bilgileriyle
drop function if exists public.yonetici_kullanicilar();
create function public.yonetici_kullanicilar()
returns table (id uuid, ad text, eposta text, rol text, yasakli boolean, olusturma timestamptz, gonderi int, yorum int,
               dogum_tarihi date, okul text, sube text, okul_no text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.yonetici_mi() then
    raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501';
  end if;
  return query
    select p.id, p.ad, u.email::text, p.rol, p.yasakli, p.olusturma,
           (select count(*)::int from public.gonderiler g where g.kullanici_id = p.id),
           (select count(*)::int from public.yorumlar y where y.kullanici_id = p.id),
           p.dogum_tarihi, p.okul, p.sube, p.okul_no
    from public.profiller p join auth.users u on u.id = p.id
    order by p.olusturma desc;
end $$;
revoke all on function public.yonetici_kullanicilar() from public, anon;
grant execute on function public.yonetici_kullanicilar() to authenticated;

-- ---------- Gönderi başına en fazla 7 dosya ----------
create or replace function public.medya_gecerli(m jsonb, uid uuid) returns boolean
language sql immutable as $$
  select jsonb_typeof(m) = 'array'
     and jsonb_array_length(m) between 1 and 7
     and not exists (
       select 1 from jsonb_array_elements(m) e
       where not (
         jsonb_typeof(e) = 'object'
         and coalesce(e->>'tur', '') in ('foto', 'video')
         and coalesce(e->>'yol', '') like uid::text || '/%'
         and coalesce(e->>'url', '') like 'https://%.supabase.co/storage/v1/object/public/medya/' || uid::text || '/%'
         and coalesce(e->>'url', '') !~ '["''<>\s\\]'
       )
     );
$$;

notify pgrst, 'reload schema';

-- ---------- Güncelleme 5 (supabase/guncelleme-5.sql ile aynı) ----------
alter table public.gonderiler add column if not exists duzenlendi timestamptz;

-- Gönderi sahibi (kısıtlı değilse) kendi gönderisini, yönetici her gönderiyi düzenleyebilir.
drop policy if exists "gonderiler_guncelle" on public.gonderiler;
create policy "gonderiler_guncelle" on public.gonderiler for update to authenticated
  using ((kullanici_id = auth.uid() and public.aktif_uye()) or public.yonetici_mi())
  with check ((kullanici_id = auth.uid() and public.aktif_uye()) or public.yonetici_mi());
grant update (yer, konum, kategori, enlem, boylam, notu, medya) on public.gonderiler to authenticated;

-- Düzenlemede gönderinin sahibi, kimliği ve paylaşım tarihi değişmez; düzenlenme zamanı kaydedilir.
create or replace function public.gonderi_koru() returns trigger
language plpgsql as $$
begin
  new.id := old.id;
  new.kullanici_id := old.kullanici_id;
  new.olusturma := old.olusturma;
  new.duzenlendi := now();
  return new;
end $$;
drop trigger if exists gonderi_koru on public.gonderiler;
create trigger gonderi_koru before update on public.gonderiler for each row execute function public.gonderi_koru();

notify pgrst, 'reload schema';

-- ---------- Güncelleme 6 (supabase/guncelleme-6.sql ile aynı) ----------
create table if not exists public.mesajlar (
  id          uuid primary key default gen_random_uuid(),
  gonderen_id uuid not null references public.profiller(id) on delete cascade,
  alici_id    uuid not null references public.profiller(id) on delete cascade,
  gonderi_id  text,
  metin       text not null default '' check (char_length(metin) <= 1000),
  okundu      boolean not null default false,
  olusturma   timestamptz not null default now(),
  check (gonderen_id <> alici_id),
  check (gonderi_id is not null or char_length(btrim(metin)) > 0)
);
create index if not exists mesajlar_alici_idx on public.mesajlar (alici_id, olusturma desc);
create index if not exists mesajlar_gonderen_idx on public.mesajlar (gonderen_id, olusturma desc);

-- Mesajları yalnızca gönderen ve alan görür (yönetici dahil başka kimse göremez).
alter table public.mesajlar enable row level security;
drop policy if exists "mesajlar_oku" on public.mesajlar;
create policy "mesajlar_oku" on public.mesajlar for select to authenticated
  using (auth.uid() in (gonderen_id, alici_id));
drop policy if exists "mesajlar_gonder" on public.mesajlar;
create policy "mesajlar_gonder" on public.mesajlar for insert to authenticated
  with check (gonderen_id = auth.uid() and public.aktif_uye());
-- Alan kişi yalnızca "okundu" bilgisini değiştirebilir.
drop policy if exists "mesajlar_okundu" on public.mesajlar;
create policy "mesajlar_okundu" on public.mesajlar for update to authenticated
  using (alici_id = auth.uid()) with check (alici_id = auth.uid());
revoke update on public.mesajlar from anon, authenticated;
grant update (okundu) on public.mesajlar to authenticated;
grant select, insert on public.mesajlar to authenticated;
drop policy if exists "mesajlar_sil" on public.mesajlar;
create policy "mesajlar_sil" on public.mesajlar for delete to authenticated using (gonderen_id = auth.uid());
grant delete on public.mesajlar to authenticated;

-- Sansür ve günlük sınır (kişi başı 24 saatte 300 mesaj)
create or replace function public.mesaj_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if tg_op = 'INSERT' then
    select count(*) into n from public.mesajlar where gonderen_id = new.gonderen_id and olusturma > now() - interval '24 hours';
    if n >= 300 then raise exception 'Günlük mesaj sınırına ulaştın (300). Yarın tekrar dene.' using errcode = 'P0001'; end if;
    new.metin := public.sansurle(new.metin);
    new.okundu := false;
    new.olusturma := now();
  end if;
  return new;
end $$;
drop trigger if exists mesaj_tetik on public.mesajlar;
create trigger mesaj_tetik before insert on public.mesajlar for each row execute function public.mesaj_tetik();

notify pgrst, 'reload schema';

-- =====================================================================
-- Kültürİz güncelleme 7: "Haritada Bul" oyunu ve sıralama tablosu
-- Supabase panelinde: SQL Editor > New query > bu dosyanın tamamını yapıştır > Run
-- Birden fazla kez çalıştırmak güvenlidir.
-- =====================================================================

create table if not exists public.oyun_skorlari (
  id           uuid primary key default gen_random_uuid(),
  kullanici_id uuid not null references public.profiller(id) on delete cascade,
  mod          text not null check (mod in ('turkiye', 'dunya')),
  puan         int  not null check (puan between 0 and 5000),
  olusturma    timestamptz not null default now()
);
create index if not exists oyun_skorlari_mod_idx on public.oyun_skorlari (mod, puan desc);

alter table public.oyun_skorlari enable row level security;
drop policy if exists "oyun_oku" on public.oyun_skorlari;
create policy "oyun_oku" on public.oyun_skorlari for select to authenticated using (true);
drop policy if exists "oyun_ekle" on public.oyun_skorlari;
create policy "oyun_ekle" on public.oyun_skorlari for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye());
drop policy if exists "oyun_sil" on public.oyun_skorlari;
create policy "oyun_sil" on public.oyun_skorlari for delete to authenticated using (public.yonetici_mi());
revoke all on public.oyun_skorlari from anon;
grant select, insert, delete on public.oyun_skorlari to authenticated;

-- Günde en fazla 60 oyun kaydı; zaman sunucudan alınır.
create or replace function public.oyun_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from public.oyun_skorlari where kullanici_id = new.kullanici_id and olusturma > now() - interval '24 hours';
  if n >= 60 then raise exception 'Bugünlük yeterince oynadın (60 oyun). Yarın tekrar dene.' using errcode = 'P0001'; end if;
  new.olusturma := now();
  return new;
end $$;
drop trigger if exists oyun_tetik on public.oyun_skorlari;
create trigger oyun_tetik before insert on public.oyun_skorlari for each row execute function public.oyun_tetik();

-- Sıralama: her oyuncunun en iyi puanı
create or replace function public.oyun_liderler(m text)
returns table (kullanici_id uuid, ad text, foto_url text, puan int)
language sql stable security definer set search_path = public as $$
  select p.id, p.ad, coalesce(p.foto_url, ''), max(s.puan)::int
  from public.oyun_skorlari s join public.profiller p on p.id = s.kullanici_id
  where s.mod = m and not p.yasakli
  group by p.id, p.ad, p.foto_url
  order by max(s.puan) desc, min(s.olusturma)
  limit 20;
$$;
revoke all on function public.oyun_liderler(text) from public, anon;
grant execute on function public.oyun_liderler(text) to authenticated;

notify pgrst, 'reload schema';

-- =====================================================================
-- Kültürİz güncelleme 8: video sınırı (dosya başına 15 MB) ve depolama temizliği
-- Supabase panelinde: SQL Editor > New query > bu dosyanın tamamını yapıştır > Run
-- Birden fazla kez çalıştırmak güvenlidir.
-- =====================================================================

-- Dosya başına en fazla 15 MB (fotoğraflar site tarafından zaten küçültülüyor).
update storage.buckets set file_size_limit = 15728640 where id = 'medya';

-- Yönetici için depolama durumu: toplam boyut, dosya sayısı ve hiçbir gönderi ya da
-- profil fotoğrafı tarafından kullanılmayan (silinmiş içeriklerden kalan) dosyalar.
-- Son 1 saatte yüklenen dosyalar, yükleme sürüyor olabileceği için listeye girmez.
create or replace function public.depolama_durumu() returns json
language plpgsql stable security definer set search_path = public, storage as $$
declare r json;
begin
  if not public.yonetici_mi() then
    raise exception 'Bu işlem için yönetici olmalısın' using errcode = '42501';
  end if;
  with kullanilan as (
    select e->>'yol' as yol
      from public.gonderiler g, jsonb_array_elements(case when jsonb_typeof(g.medya) = 'array' then g.medya else '[]'::jsonb end) e
     where e->>'yol' is not null
    union
    select substring(p.foto_url from '/storage/v1/object/public/medya/(.*)$')
      from public.profiller p
     where p.foto_url like '%/storage/v1/object/public/medya/%'
  ), dosyalar as (
    select o.name, coalesce((o.metadata->>'size')::bigint, 0) as boyut,
           (o.created_at < now() - interval '1 hour'
            and not exists (select 1 from kullanilan k where k.yol = o.name)) as yetim
      from storage.objects o
     where o.bucket_id = 'medya'
  )
  select json_build_object(
           'toplam', coalesce(sum(boyut), 0),
           'sayi', count(*),
           'yetim', coalesce((select json_agg(name) from (select name from dosyalar where yetim limit 1000) y), '[]'::json),
           'yetim_boyut', coalesce(sum(boyut) filter (where yetim), 0)
         )
    into r from dosyalar;
  return r;
end $$;
revoke all on function public.depolama_durumu() from public, anon;
grant execute on function public.depolama_durumu() to authenticated;

notify pgrst, 'reload schema';

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
