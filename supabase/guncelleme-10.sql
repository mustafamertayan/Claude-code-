-- =====================================================================
-- Kültürİz güncelleme 10: takip, gizli hesap, engelleme, bildirimler, yorum yanıtı ve
-- yorum beğenisi, yorum/mesaj/profil şikayeti, hesabı silme, anlık mesaj ve bildirim
-- Supabase panelinde: SQL Editor > New query > bu dosyanın tamamını yapıştır > Run
-- Birden fazla kez çalıştırmak güvenlidir.
-- =====================================================================

-- ---------- Gizli hesap ----------
alter table public.profiller add column if not exists gizli boolean not null default false;
grant select (gizli) on public.profiller to anon, authenticated;
grant update (gizli) on public.profiller to authenticated;

-- ---------- Engelleme ----------
create table if not exists public.engellemeler (
  engelleyen uuid not null references public.profiller(id) on delete cascade,
  engellenen uuid not null references public.profiller(id) on delete cascade,
  olusturma  timestamptz not null default now(),
  primary key (engelleyen, engellenen),
  check (engelleyen <> engellenen)
);
create index if not exists engellemeler_engellenen_idx on public.engellemeler (engellenen);
alter table public.engellemeler enable row level security;
drop policy if exists "engel_oku" on public.engellemeler;
create policy "engel_oku" on public.engellemeler for select to authenticated using (engelleyen = auth.uid());
drop policy if exists "engel_ekle" on public.engellemeler;
create policy "engel_ekle" on public.engellemeler for insert to authenticated with check (engelleyen = auth.uid());
drop policy if exists "engel_sil" on public.engellemeler;
create policy "engel_sil" on public.engellemeler for delete to authenticated using (engelleyen = auth.uid());
grant select, insert, delete on public.engellemeler to authenticated;

-- İki kişiden biri diğerini engellemiş mi?
create or replace function public.engel_var(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select a is not null and b is not null and exists (
    select 1 from public.engellemeler e
    where (e.engelleyen = a and e.engellenen = b) or (e.engelleyen = b and e.engellenen = a));
$$;

-- ---------- Takip ----------
create table if not exists public.takipler (
  takip_eden   uuid not null references public.profiller(id) on delete cascade,
  takip_edilen uuid not null references public.profiller(id) on delete cascade,
  onayli       boolean not null default true,
  olusturma    timestamptz not null default now(),
  primary key (takip_eden, takip_edilen),
  check (takip_eden <> takip_edilen)
);
create index if not exists takipler_edilen_idx on public.takipler (takip_edilen);
alter table public.takipler enable row level security;
drop policy if exists "takip_oku" on public.takipler;
create policy "takip_oku" on public.takipler for select to authenticated
  using (onayli or auth.uid() in (takip_eden, takip_edilen));
drop policy if exists "takip_ekle" on public.takipler;
create policy "takip_ekle" on public.takipler for insert to authenticated
  with check (takip_eden = auth.uid() and public.aktif_uye() and not public.engel_var(takip_eden, takip_edilen));
-- Takip isteğini yalnızca takip edilen kişi onaylar.
drop policy if exists "takip_onayla" on public.takipler;
create policy "takip_onayla" on public.takipler for update to authenticated
  using (takip_edilen = auth.uid()) with check (takip_edilen = auth.uid());
-- Takipten çıkma (takip eden) ya da takipçiyi çıkarma / isteği reddetme (takip edilen)
drop policy if exists "takip_sil" on public.takipler;
create policy "takip_sil" on public.takipler for delete to authenticated
  using (auth.uid() in (takip_eden, takip_edilen));
revoke update on public.takipler from anon, authenticated;
grant select, insert, delete on public.takipler to authenticated;
grant update (onayli) on public.takipler to authenticated;

create or replace function public.takip_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    -- Gizli hesaba takip isteği gider; açık hesabı doğrudan takip edilir.
    new.onayli := not coalesce((select gizli from public.profiller where id = new.takip_edilen), false);
    new.olusturma := now();
  elsif tg_op = 'UPDATE' then
    new.takip_eden := old.takip_eden; new.takip_edilen := old.takip_edilen;
    if old.onayli then new.onayli := true; end if;
  end if;
  return new;
end $$;
drop trigger if exists takip_tetik on public.takipler;
create trigger takip_tetik before insert or update on public.takipler for each row execute function public.takip_tetik();

-- Engellenince iki yöndeki takipler de silinir.
create or replace function public.engel_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from public.takipler where (takip_eden = new.engelleyen and takip_edilen = new.engellenen)
                                 or (takip_eden = new.engellenen and takip_edilen = new.engelleyen);
  return new;
end $$;
drop trigger if exists engel_tetik on public.engellemeler;
create trigger engel_tetik after insert on public.engellemeler for each row execute function public.engel_tetik();

-- Hesap gizliden açığa geçince bekleyen istekler onaylanır.
create or replace function public.gizlilik_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.gizli and not new.gizli then
    update public.takipler set onayli = true where takip_edilen = new.id and not onayli;
  end if;
  return new;
end $$;
drop trigger if exists gizlilik_tetik on public.profiller;
create trigger gizlilik_tetik after update of gizli on public.profiller for each row execute function public.gizlilik_tetik();

-- ---------- Kim neyi görebilir ----------
create or replace function public.profil_gorulebilir(sahip uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select sahip = auth.uid() or public.yonetici_mi() or (
    not public.engel_var(sahip, auth.uid()) and (
      not coalesce((select gizli from public.profiller where id = sahip), false)
      or exists (select 1 from public.takipler t where t.takip_eden = auth.uid() and t.takip_edilen = sahip and t.onayli)
    )
  );
$$;
-- Örnek gönderiler ("efes" gibi) herkese açıktır.
create or replace function public.gonderi_gorulebilir(gid text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select public.profil_gorulebilir(g.kullanici_id) from public.gonderiler g where g.id::text = gid), true);
$$;

drop policy if exists "gonderiler_oku" on public.gonderiler;
create policy "gonderiler_oku" on public.gonderiler for select using (public.profil_gorulebilir(kullanici_id));

drop policy if exists "begeniler_oku" on public.begeniler;
create policy "begeniler_oku" on public.begeniler for select using (public.gonderi_gorulebilir(gonderi_id));
drop policy if exists "begeniler_ekle" on public.begeniler;
create policy "begeniler_ekle" on public.begeniler for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye() and public.gonderi_gorulebilir(gonderi_id));

-- ---------- Yorum yanıtı ve yorum beğenisi ----------
alter table public.yorumlar add column if not exists ust_id uuid references public.yorumlar(id) on delete cascade;
grant select (ust_id) on public.yorumlar to anon, authenticated;

drop policy if exists "yorumlar_oku" on public.yorumlar;
create policy "yorumlar_oku" on public.yorumlar for select
  using (public.gonderi_gorulebilir(gonderi_id) and not public.engel_var(kullanici_id, auth.uid()));
drop policy if exists "yorumlar_ekle" on public.yorumlar;
create policy "yorumlar_ekle" on public.yorumlar for insert to authenticated
  with check (kullanici_id = auth.uid() and public.aktif_uye() and public.gonderi_gorulebilir(gonderi_id));

create table if not exists public.yorum_begenileri (
  yorum_id     uuid not null references public.yorumlar(id) on delete cascade,
  kullanici_id uuid not null references public.profiller(id) on delete cascade,
  olusturma    timestamptz not null default now(),
  primary key (yorum_id, kullanici_id)
);
alter table public.yorum_begenileri enable row level security;
drop policy if exists "yb_oku" on public.yorum_begenileri;
create policy "yb_oku" on public.yorum_begenileri for select to authenticated using (true);
drop policy if exists "yb_ekle" on public.yorum_begenileri;
create policy "yb_ekle" on public.yorum_begenileri for insert to authenticated with check (kullanici_id = auth.uid() and public.aktif_uye());
drop policy if exists "yb_sil" on public.yorum_begenileri;
create policy "yb_sil" on public.yorum_begenileri for delete to authenticated using (kullanici_id = auth.uid());
grant select, insert, delete on public.yorum_begenileri to authenticated;

-- ---------- Mesaj: engellenen kişiye mesaj gönderilemez ----------
drop policy if exists "mesajlar_gonder" on public.mesajlar;
create policy "mesajlar_gonder" on public.mesajlar for insert to authenticated
  with check (gonderen_id = auth.uid() and public.aktif_uye() and not public.engel_var(gonderen_id, alici_id));

-- ---------- Şikayet: gönderi, yorum, mesaj, profil ----------
alter table public.sikayetler add column if not exists tur text not null default 'gonderi';
alter table public.sikayetler add column if not exists icerik text not null default '';
alter table public.sikayetler drop constraint if exists sikayet_tur_gecerli;
alter table public.sikayetler add constraint sikayet_tur_gecerli check (tur in ('gonderi', 'yorum', 'mesaj', 'profil'));
-- Şikayet edilen içeriğin o anki hâli sunucuda saklanır (yönetici başkalarının mesajlarını okuyamaz; yalnızca şikayet edileni görür).
create or replace function public.sikayet_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
declare x text;
begin
  if new.tur = 'yorum' then
    select pr.ad || ': ' || y.metin into x from public.yorumlar y join public.profiller pr on pr.id = y.kullanici_id where y.id::text = new.gonderi_id;
  elsif new.tur = 'mesaj' then
    -- Yalnızca kendisine gelen mesaj şikayet edilebilir.
    select pr.ad || ': ' || coalesce(nullif(m.metin, ''), '(gönderi paylaştı)') into x
      from public.mesajlar m join public.profiller pr on pr.id = m.gonderen_id
      where m.id::text = new.gonderi_id and m.alici_id = new.kullanici_id;
    if x is null then raise exception 'Bu mesaj şikayet edilemez.' using errcode = '42501'; end if;
  elsif new.tur = 'profil' then
    select ad || coalesce(nullif(' · ' || bio, ' · '), '') into x from public.profiller where id::text = new.gonderi_id;
  end if;
  new.icerik := left(coalesce(x, ''), 1000);
  return new;
end $$;
drop trigger if exists sikayet_tetik on public.sikayetler;
create trigger sikayet_tetik before insert on public.sikayetler for each row execute function public.sikayet_tetik();

-- ---------- Bildirimler ----------
create table if not exists public.bildirimler (
  id         uuid primary key default gen_random_uuid(),
  alici_id   uuid not null references public.profiller(id) on delete cascade,
  yapan_id   uuid not null references public.profiller(id) on delete cascade,
  tur        text not null check (tur in ('begeni', 'yorum', 'yanit', 'takip', 'takip_istegi', 'takip_onay', 'yorum_begeni')),
  gonderi_id text,
  yorum_id   uuid,
  metin      text not null default '',
  okundu     boolean not null default false,
  olusturma  timestamptz not null default now()
);
create index if not exists bildirimler_alici_idx on public.bildirimler (alici_id, olusturma desc);
alter table public.bildirimler enable row level security;
drop policy if exists "bildirim_oku" on public.bildirimler;
create policy "bildirim_oku" on public.bildirimler for select to authenticated using (alici_id = auth.uid());
drop policy if exists "bildirim_okundu" on public.bildirimler;
create policy "bildirim_okundu" on public.bildirimler for update to authenticated using (alici_id = auth.uid()) with check (alici_id = auth.uid());
drop policy if exists "bildirim_sil" on public.bildirimler;
create policy "bildirim_sil" on public.bildirimler for delete to authenticated using (alici_id = auth.uid());
revoke insert, update on public.bildirimler from anon, authenticated;
grant select, delete on public.bildirimler to authenticated;
grant update (okundu) on public.bildirimler to authenticated;

create or replace function public.bildir(alici uuid, yapan uuid, t text, gid text, yid uuid, m text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if alici is null or yapan is null or alici = yapan or public.engel_var(alici, yapan) then return; end if;
  insert into public.bildirimler (alici_id, yapan_id, tur, gonderi_id, yorum_id, metin) values (alici, yapan, t, gid, yid, left(coalesce(m, ''), 120));
end $$;
revoke all on function public.bildir(uuid, uuid, text, text, uuid, text) from public, anon, authenticated;

create or replace function public.bildirim_tetik() returns trigger
language plpgsql security definer set search_path = public as $$
declare sahip uuid; ust uuid; gid text; m text;
begin
  if tg_table_name = 'begeniler' then
    select kullanici_id into sahip from public.gonderiler where id::text = coalesce(new.gonderi_id, old.gonderi_id);
    if tg_op = 'INSERT' then perform public.bildir(sahip, new.kullanici_id, 'begeni', new.gonderi_id, null, '');
    else delete from public.bildirimler where tur = 'begeni' and yapan_id = old.kullanici_id and gonderi_id = old.gonderi_id; end if;
  elsif tg_table_name = 'yorumlar' then
    select kullanici_id into sahip from public.gonderiler where id::text = new.gonderi_id;
    if new.ust_id is not null then
      select kullanici_id into ust from public.yorumlar where id = new.ust_id;
      perform public.bildir(ust, new.kullanici_id, 'yanit', new.gonderi_id, new.id, new.metin);
    end if;
    if ust is distinct from sahip then perform public.bildir(sahip, new.kullanici_id, 'yorum', new.gonderi_id, new.id, new.metin); end if;
  elsif tg_table_name = 'yorum_begenileri' then
    if tg_op = 'INSERT' then
      select kullanici_id, gonderi_id, metin into ust, gid, m from public.yorumlar where id = new.yorum_id;
      perform public.bildir(ust, new.kullanici_id, 'yorum_begeni', gid, new.yorum_id, m);
    else delete from public.bildirimler where tur = 'yorum_begeni' and yapan_id = old.kullanici_id and yorum_id = old.yorum_id; end if;
  elsif tg_table_name = 'takipler' then
    if tg_op = 'INSERT' then
      perform public.bildir(new.takip_edilen, new.takip_eden, case when new.onayli then 'takip' else 'takip_istegi' end, null, null, '');
    elsif tg_op = 'UPDATE' and new.onayli and not old.onayli then
      update public.bildirimler set tur = 'takip' where tur = 'takip_istegi' and alici_id = new.takip_edilen and yapan_id = new.takip_eden;
      perform public.bildir(new.takip_eden, new.takip_edilen, 'takip_onay', null, null, '');
    elsif tg_op = 'DELETE' then
      delete from public.bildirimler where tur in ('takip', 'takip_istegi') and alici_id = old.takip_edilen and yapan_id = old.takip_eden;
    end if;
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists bildirim on public.begeniler;
create trigger bildirim after insert or delete on public.begeniler for each row execute function public.bildirim_tetik();
drop trigger if exists bildirim on public.yorumlar;
create trigger bildirim after insert on public.yorumlar for each row execute function public.bildirim_tetik();
drop trigger if exists bildirim on public.yorum_begenileri;
create trigger bildirim after insert or delete on public.yorum_begenileri for each row execute function public.bildirim_tetik();
drop trigger if exists bildirim on public.takipler;
create trigger bildirim after insert or update or delete on public.takipler for each row execute function public.bildirim_tetik();

-- Tam yasak (güncelleme 9) yeni tablolar için de geçerli olsun.
do $$
declare t text;
begin
  if to_regprocedure('public.engelli()') is null then return; end if;
  foreach t in array array['takipler', 'engellemeler', 'yorum_begenileri', 'bildirimler'] loop
    execute format('drop policy if exists ip_engel on public.%I', t);
    execute format('create policy ip_engel on public.%I as restrictive for all to anon, authenticated using (not (select public.engelli())) with check (not (select public.engelli()))', t);
  end loop;
end $$;

-- ---------- Hesabımı sil ----------
-- Hesap ve ona bağlı her şey (profil, gönderiler, yorumlar, beğeniler, mesajlar, takipler, bildirimler) silinir.
-- Fotoğraf ve videolar, yöneticinin depolama temizliğinde (güncelleme 8) depodan da silinir.
create or replace function public.hesabimi_sil() returns void
language plpgsql security definer set search_path = public, auth as $$
begin
  if auth.uid() is null then raise exception 'Giriş yapmalısın' using errcode = '42501'; end if;
  if public.yonetici_mi() and (select count(*) from public.profiller where rol = 'admin') <= 1 then
    raise exception 'Tek yönetici sensin. Hesabını silmeden önce başka birini yönetici yap.' using errcode = 'P0001';
  end if;
  delete from public.gonderiler where kullanici_id = auth.uid();
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.hesabimi_sil() from public, anon;
grant execute on function public.hesabimi_sil() to authenticated;

-- ---------- Anlık mesaj ve bildirim ----------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mesajlar') then
      alter publication supabase_realtime add table public.mesajlar;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'bildirimler') then
      alter publication supabase_realtime add table public.bildirimler;
    end if;
  end if;
end $$;

notify pgrst, 'reload schema';
