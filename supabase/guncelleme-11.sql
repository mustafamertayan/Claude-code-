-- =====================================================================
-- Kültürİz güncelleme 11: Tarih Yarışması sıralaması
-- Supabase panelinde: SQL Editor > New query > bu dosyanın tamamını yapıştır > Run
-- Birden fazla kez çalıştırmak güvenlidir.
-- =====================================================================

-- Oyun puanlarına "tarih" modu eklenir (en fazla 1500 puan: 10 soru × 150).
alter table public.oyun_skorlari drop constraint if exists oyun_skorlari_mod_check;
alter table public.oyun_skorlari drop constraint if exists oyun_mod_gecerli;
alter table public.oyun_skorlari add constraint oyun_mod_gecerli check (
  (mod in ('turkiye', 'dunya') and puan between 0 and 5000) or (mod = 'tarih' and puan between 0 and 1500)
);

notify pgrst, 'reload schema';
