--
-- PostgreSQL database dump
--

-- Dumped from database version 15.8
-- Dumped by pg_dump version 15.8

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--

CREATE SCHEMA public;


ALTER SCHEMA public OWNER TO pg_database_owner;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: pg_database_owner
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: basit_tesekkur_gonderisi_sil(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.basit_tesekkur_gonderisi_sil(post_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    district_name TEXT;
    post_type TEXT;
    current_count INTEGER;
BEGIN
    -- Gönderinin tipini ve ilçesini al
    SELECT type, district INTO post_type, district_name FROM posts WHERE id = post_id;
    
    -- Log bilgisi
    RAISE NOTICE 'Silinen gönderi - ID: %, Tip: %, İlçe: %', post_id, post_type, district_name;
    
    -- Gönderiyi sil
    DELETE FROM posts WHERE id = post_id;
    
    -- Thanks count güncelleme - sadece teşekkür tipindeki gönderiler için
    IF post_type IN ('thanks', 'appreciation') THEN
        -- İlçenin mevcut teşekkür sayısını al
        SELECT NULLIF(thanks_count, '')::INTEGER INTO current_count 
        FROM districts 
        WHERE name = district_name;
        
        -- Null kontrolü
        IF current_count IS NULL THEN
            current_count := 0;
        END IF;
        
        -- Log bilgisi
        RAISE NOTICE 'İlçe % için mevcut teşekkür sayısı: %', district_name, current_count;
        
        -- Teşekkür sayısını azalt (0'ın altına düşmemesi için kontrol et)
        IF current_count > 0 THEN
            current_count := current_count - 1;
            
            -- İlçe teşekkür sayısını güncelle
            UPDATE districts 
            SET thanks_count = current_count::TEXT 
            WHERE name = district_name;
            
            RAISE NOTICE 'İlçe % için teşekkür sayısı % olarak güncellendi', district_name, current_count;
        END IF;
    END IF;
END;
$$;


ALTER FUNCTION public.basit_tesekkur_gonderisi_sil(post_id uuid) OWNER TO supabase_admin;

--
-- Name: calculate_city_scores(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.calculate_city_scores() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    city_rec RECORD;
    v_total_complaints INT;
    v_solved_complaints INT;
    v_thanks_count INT;
    v_solution_rate DECIMAL(5,2);
    district_count INT;
BEGIN
    -- Tüm şehirleri dolaş
    FOR city_rec IN SELECT id, name, is_metropolitan FROM cities LOOP
        
        -- Büyükşehir ise, tüm ilçelerin toplamını hesapla
        IF city_rec.is_metropolitan THEN
            -- İlçe sayısını bul
            SELECT COUNT(*) INTO district_count
            FROM districts
            WHERE city_id = city_rec.id;
            
            -- Tüm ilçelerin toplam değerlerini al
            SELECT 
                SUM(COALESCE(total_complaints::INT, 0)),
                SUM(COALESCE(solved_complaints::INT, 0)),
                SUM(COALESCE(thanks_count::INT, 0))
            INTO
                v_total_complaints,
                v_solved_complaints,
                v_thanks_count
            FROM districts
            WHERE city_id = city_rec.id;
            
            -- Çözüm oranını hesapla
            IF (v_total_complaints + v_thanks_count) > 0 THEN
                v_solution_rate := ((v_thanks_count + v_solved_complaints)::DECIMAL / (v_total_complaints + v_thanks_count)::DECIMAL) * 100;
            ELSE
                v_solution_rate := 0;
            END IF;
            
            -- Şehir skorlarını güncelle (büyükşehir için)
            UPDATE cities
            SET total_complaints = COALESCE(v_total_complaints, 0)::TEXT,
                solved_complaints = COALESCE(v_solved_complaints, 0)::TEXT,
                thanks_count = COALESCE(v_thanks_count, 0)::TEXT,
                solution_rate = COALESCE(v_solution_rate, 0)::TEXT,
                solution_last_updated = NOW()
            WHERE id = city_rec.id;
            
        ELSE
            -- Büyükşehir değilse, Merkez ilçesinin değerlerini kullan
            SELECT 
                COALESCE(d.total_complaints::INT, 0),
                COALESCE(d.solved_complaints::INT, 0),
                COALESCE(d.thanks_count::INT, 0),
                COALESCE(d.solution_rate::DECIMAL, 0)
            INTO
                v_total_complaints,
                v_solved_complaints,
                v_thanks_count,
                v_solution_rate
            FROM districts d
            WHERE d.city_id = city_rec.id AND d.name = 'Merkez'
            LIMIT 1;
            
            -- Merkez ilçe bulunamadıysa 0 değerlerini kullan
            IF v_total_complaints IS NULL THEN
                v_total_complaints := 0;
                v_solved_complaints := 0;
                v_thanks_count := 0;
                v_solution_rate := 0;
            END IF;
            
            -- Şehir skorlarını güncelle (normal şehir için)
            UPDATE cities
            SET total_complaints = v_total_complaints::TEXT,
                solved_complaints = v_solved_complaints::TEXT,
                thanks_count = v_thanks_count::TEXT,
                solution_rate = v_solution_rate::TEXT,
                solution_last_updated = NOW()
            WHERE id = city_rec.id;
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION public.calculate_city_scores() OWNER TO supabase_admin;

--
-- Name: calculate_party_scores(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.calculate_party_scores() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    party_rec RECORD;
    city_district_count INT;
    total_solution_rate DECIMAL(10,2);
    avg_solution_rate DECIMAL(5,2);
    parties_count INT;
    party_rank INT;
    max_score DECIMAL(5,2) := 100.0; -- Maksimum skor (100 üzerinden)
BEGIN
    -- Toplam aktif parti sayısını bul
    SELECT COUNT(*) INTO parties_count FROM political_parties WHERE id IN (
        SELECT DISTINCT political_party_id FROM districts WHERE political_party_id IS NOT NULL
    );
    
    -- Her parti için hesaplama yap
    FOR party_rec IN SELECT id, name FROM political_parties LOOP
        -- Bu partinin yönettiği ilçelerin sayısını ve toplam çözüm oranını bul
        SELECT 
            COUNT(*),
            SUM(COALESCE(solution_rate::DECIMAL, 0))
        INTO
            city_district_count,
            total_solution_rate
        FROM districts
        WHERE political_party_id = party_rec.id;
        
        -- Ortalama çözüm oranını hesapla
        IF city_district_count > 0 THEN
            avg_solution_rate := total_solution_rate / city_district_count;
        ELSE
            avg_solution_rate := 0;
        END IF;
        
        -- Partiyi güncelle
        UPDATE political_parties
        SET score = avg_solution_rate,
            last_updated = NOW()
        WHERE id = party_rec.id;
    END LOOP;
    
    -- Partileri skorlarına göre sırala ve yüzdelik dilimlerini hesapla
    FOR party_rec IN SELECT id, name, score,
                       ROW_NUMBER() OVER (ORDER BY score DESC) as rank
                    FROM political_parties
                    WHERE score > 0
                    ORDER BY score DESC LOOP
        
        -- Sıralama indeksine göre yeni bir skor hesapla (100'den 1'e kadar, yüzdelik dilimlere göre)
        IF parties_count > 0 THEN
            -- Sıralamayı 100-1 arasında bir skora dönüştür (1. parti 100 puan, sonuncu parti 1 puan)
            party_rank := party_rec.rank;
            UPDATE political_parties
            SET score = max_score - ((party_rank - 1.0) / parties_count) * (max_score - 1.0)
            WHERE id = party_rec.id;
        END IF;
    END LOOP;
END;
$$;


ALTER FUNCTION public.calculate_party_scores() OWNER TO supabase_admin;

--
-- Name: calculate_party_scores_integer(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.calculate_party_scores_integer() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Önce skorları hesapla
    PERFORM calculate_party_scores_simple();
    
    -- Sonra ondalık değerleri tamsayıya yuvarla
    UPDATE political_parties
    SET score = ROUND(score);
    
    RAISE NOTICE 'Parti skorları tam sayıya yuvarlandı.';
END;
$$;


ALTER FUNCTION public.calculate_party_scores_integer() OWNER TO supabase_admin;

--
-- Name: calculate_party_scores_simple(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.calculate_party_scores_simple() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Her parti için ortalama çözüm oranını hesapla
    UPDATE political_parties p
    SET score = (
        SELECT COALESCE(AVG(d.solution_rate::decimal), 0) 
        FROM districts d
        WHERE d.political_party_id = p.id
    ),
    last_updated = NOW();
    
    RAISE NOTICE 'Parti skorları güncellendi.';
END;
$$;


ALTER FUNCTION public.calculate_party_scores_simple() OWNER TO supabase_admin;

--
-- Name: change_post_type(text, uuid, text, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.change_post_type(post_id text, district_id uuid, old_type text, new_type text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_is_solved BOOLEAN;
BEGIN
    -- Gönderinin çözüm durumunu al
    SELECT is_solved INTO v_is_solved FROM posts WHERE id = post_id;
    
    -- Gönderi tipini güncelle
    UPDATE posts
    SET type = new_type,
        updated_at = NOW()
    WHERE id = post_id;
    
    -- İstatistikleri güncelle:
    
    -- Teşekkürden şikayete dönüştürülüyor
    IF old_type = 'thanks' AND (new_type = 'complaint' OR new_type = 'suggestion') THEN
        -- İlçe istatistiklerini güncelle
        PERFORM update_district_stats(
            district_id, 
            1,              -- total_complaints +1 arttır
            CASE WHEN v_is_solved THEN 1 ELSE 0 END,  -- Çözüldüyse solved_complaints +1 
            -1              -- thanks_count -1 azalt
        );
    
    -- Şikayetten teşekküre dönüştürülüyor
    ELSIF (old_type = 'complaint' OR old_type = 'suggestion') AND new_type = 'thanks' THEN
        -- İlçe istatistiklerini güncelle
        PERFORM update_district_stats(
            district_id, 
            -1,             -- total_complaints -1 azalt
            CASE WHEN v_is_solved THEN -1 ELSE 0 END,  -- Çözüldüyse solved_complaints -1
            1               -- thanks_count +1 arttır
        );
    END IF;
    
    -- Parti skorlarını güncelle
    PERFORM calculate_party_scores_integer();
    
    RAISE NOTICE 'Gönderi tipi değiştirildi ve istatistikler güncellendi.';
END;
$$;


ALTER FUNCTION public.change_post_type(post_id text, district_id uuid, old_type text, new_type text) OWNER TO supabase_admin;

--
-- Name: cleanup_expired_ad_logs(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.cleanup_expired_ad_logs() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    current_date TIMESTAMP := NOW();
BEGIN
    -- Reklamın bitiş tarihinden 1 ay geçmiş olan reklamların loglarını sil
    DELETE FROM ad_interactions 
    WHERE ad_id IN (
        SELECT id 
        FROM sponsored_ads 
        WHERE end_date < (current_date - INTERVAL '1 month')
    );
    
    RAISE NOTICE 'Süresi dolmuş reklam logları temizlendi: %', current_date;
END;
$$;


ALTER FUNCTION public.cleanup_expired_ad_logs() OWNER TO supabase_admin;

--
-- Name: comment_delete_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.comment_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM decrement_comment_count(OLD.post_id);
  RETURN OLD;
END;
$$;


ALTER FUNCTION public.comment_delete_trigger() OWNER TO supabase_admin;

--
-- Name: comment_insert_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.comment_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM increment_comment_count(NEW.post_id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.comment_insert_trigger() OWNER TO supabase_admin;

--
-- Name: create_comment_notification(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.create_comment_notification() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_post_owner_id UUID;
  v_post_title TEXT;
  v_commenter_name TEXT;
  v_commenter_profile_url TEXT;
BEGIN
  -- Post sahibini bul
  SELECT user_id, title INTO v_post_owner_id, v_post_title 
  FROM public.posts 
  WHERE id = NEW.post_id;
  
  -- Eğer kendi gönderisine yorum yapıyorsa bildirim oluşturma
  IF v_post_owner_id = NEW.user_id THEN
    RETURN NEW;
  END IF;
  
  -- Yorum yapan kullanıcı bilgilerini al
  SELECT username, profile_image_url INTO v_commenter_name, v_commenter_profile_url 
  FROM public.users 
  WHERE id = NEW.user_id;
  
  -- Bildirim oluştur
  INSERT INTO public.notifications (
    user_id, 
    title, 
    content, 
    type, 
    sender_id, 
    sender_name, 
    sender_profile_url, 
    related_entity_id, 
    related_entity_type
  ) VALUES (
    v_post_owner_id,
    'Gönderinize yorum yapıldı',
    COALESCE(v_commenter_name, 'Bir kullanıcı') || ' "' || COALESCE(SUBSTRING(v_post_title FROM 1 FOR 30), 'Gönderinize') || '..." gönderinize yorum yaptı',
    'comment',
    NEW.user_id,
    v_commenter_name,
    v_commenter_profile_url,
    NEW.post_id,
    'post'
  );
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_comment_notification() OWNER TO supabase_admin;

--
-- Name: create_default_notification_preferences(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.create_default_notification_preferences() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  BEGIN
    INSERT INTO public.notification_preferences (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Notification preferences creation failed: %', SQLERRM;
  END;
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_default_notification_preferences() OWNER TO supabase_admin;

--
-- Name: create_notification_preferences_safe(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.create_notification_preferences_safe() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- 5 saniye bekle (kullanıcı kaydı tamamen tamamlanması için)
  PERFORM pg_sleep(5);
  
  -- Tercih kaydı var mı kontrol et
  IF NOT EXISTS (SELECT 1 FROM notification_preferences WHERE user_id = NEW.id) THEN
    -- Yoksa oluştur
    INSERT INTO notification_preferences (
      user_id,
      likes_enabled,
      comments_enabled,
      replies_enabled,
      mentions_enabled,
      system_notifications_enabled
    ) VALUES (
      NEW.id,
      true,
      true,
      true,
      true,
      true
    );
  END IF;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_notification_preferences_safe() OWNER TO supabase_admin;

--
-- Name: cron_update_party_scores(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.cron_update_party_scores() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- 1. İlçe çözüm oranlarını hesapla
    UPDATE districts d
    SET solution_rate = (
        CASE 
            WHEN (COALESCE(d.total_complaints, 0) + COALESCE(d.thanks_count, 0)) = 0 THEN 0
            ELSE ((COALESCE(d.solved_complaints, 0) + COALESCE(d.thanks_count, 0)) * 100.0 / 
                  (COALESCE(d.total_complaints, 0) + COALESCE(d.thanks_count, 0)))
        END
    );
    
    -- 2. Şehir çözüm oranlarını hesapla
    UPDATE cities c
    SET solution_rate = (
        CASE 
            WHEN (COALESCE(c.total_complaints, 0) + COALESCE(c.thanks_count, 0)) = 0 THEN 0
            ELSE ((COALESCE(c.solved_complaints, 0) + COALESCE(c.thanks_count, 0)) * 100.0 / 
                  (COALESCE(c.total_complaints, 0) + COALESCE(c.thanks_count, 0)))
        END
    );

    -- 3. Parti istatistiklerini hesapla
    -- Öncelikle parti_sikayet_sayisi sütunu vb. yoksa ekle
    BEGIN
        ALTER TABLE political_parties ADD COLUMN parti_sikayet_sayisi INTEGER DEFAULT 0;
    EXCEPTION WHEN duplicate_column THEN
        -- Sütun zaten var, bir şey yapma
    END;
    
    BEGIN
        ALTER TABLE political_parties ADD COLUMN parti_cozulmus_sikayet_sayisi INTEGER DEFAULT 0;
    EXCEPTION WHEN duplicate_column THEN
        -- Sütun zaten var, bir şey yapma
    END;
    
    BEGIN
        ALTER TABLE political_parties ADD COLUMN parti_tesekkur_sayisi INTEGER DEFAULT 0;
    EXCEPTION WHEN duplicate_column THEN
        -- Sütun zaten var, bir şey yapma
    END;

    -- Parti istatistiklerini sıfırla
    UPDATE political_parties
    SET 
        parti_sikayet_sayisi = 0,
        parti_cozulmus_sikayet_sayisi = 0,
        parti_tesekkur_sayisi = 0,
        score = 0;

    -- Büyükşehir olan ve olmayan şehirler için ayrı hesaplamalar yap
    WITH city_groups AS (
        -- Şehirleri büyükşehir olma durumuna göre grupla
        SELECT 
            id,
            political_party_id,
            total_complaints,
            solved_complaints,
            thanks_count,
            is_metropolitan
        FROM 
            cities
        WHERE 
            political_party_id IS NOT NULL
    ),
    city_party_stats AS (
        -- Sadece büyükşehir olan şehirlerden toplanan istatistikler
        SELECT 
            c.political_party_id,
            SUM(COALESCE(c.total_complaints, 0)) AS total_city_complaints,
            SUM(COALESCE(c.solved_complaints, 0)) AS total_city_solved_complaints,
            SUM(COALESCE(c.thanks_count, 0)) AS total_city_thanks
        FROM 
            city_groups c
        WHERE 
            c.is_metropolitan = true
        GROUP BY 
            c.political_party_id
    ),
    normal_city_party_stats AS (
        -- Büyükşehir olmayan şehirlerin istatistikleri - bunlar olduğu gibi kalır
        SELECT 
            c.political_party_id,
            SUM(COALESCE(c.total_complaints, 0)) AS total_normal_city_complaints,
            SUM(COALESCE(c.solved_complaints, 0)) AS total_normal_city_solved_complaints,
            SUM(COALESCE(c.thanks_count, 0)) AS total_normal_city_thanks
        FROM 
            city_groups c
        WHERE 
            c.is_metropolitan = false
        GROUP BY 
            c.political_party_id
    ),
    district_party_stats AS (
        -- İlçelerden toplanan istatistikler - sadece büyükşehirlerdeki ilçeler
        SELECT 
            d.political_party_id,
            SUM(COALESCE(d.total_complaints, 0)) AS total_district_complaints,
            SUM(COALESCE(d.solved_complaints, 0)) AS total_district_solved_complaints,
            SUM(COALESCE(d.thanks_count, 0)) AS total_district_thanks
        FROM 
            districts d
        JOIN 
            cities c ON d.city_id = c.id
        WHERE 
            d.political_party_id IS NOT NULL AND c.is_metropolitan = true
        GROUP BY 
            d.political_party_id
    ),
    normal_district_party_stats AS (
        -- Büyükşehir olmayan ilçelerin istatistikleri
        SELECT 
            d.political_party_id,
            SUM(COALESCE(d.total_complaints, 0)) AS total_normal_district_complaints,
            SUM(COALESCE(d.solved_complaints, 0)) AS total_normal_district_solved_complaints,
            SUM(COALESCE(d.thanks_count, 0)) AS total_normal_district_thanks
        FROM 
            districts d
        JOIN 
            cities c ON d.city_id = c.id
        WHERE 
            d.political_party_id IS NOT NULL AND c.is_metropolitan = false
        GROUP BY 
            d.political_party_id
    ),
    combined_stats AS (
        -- Tüm istatistikleri birleştir
        SELECT 
            p.id AS party_id,
            -- Büyükşehir istatistikleri (50% paylaşım)
            COALESCE(cps.total_city_complaints * 0.5, 0) AS metro_city_complaints,
            COALESCE(cps.total_city_solved_complaints * 0.5, 0) AS metro_city_solved_complaints,
            COALESCE(cps.total_city_thanks * 0.5, 0) AS metro_city_thanks,
            -- Büyükşehirlerdeki ilçe istatistikleri (50% paylaşım)
            COALESCE(dps.total_district_complaints * 0.5, 0) AS metro_district_complaints,
            COALESCE(dps.total_district_solved_complaints * 0.5, 0) AS metro_district_solved_complaints,
            COALESCE(dps.total_district_thanks * 0.5, 0) AS metro_district_thanks,
            -- Normal şehir istatistikleri (tam)
            COALESCE(ncps.total_normal_city_complaints, 0) AS normal_city_complaints,
            COALESCE(ncps.total_normal_city_solved_complaints, 0) AS normal_city_solved_complaints,
            COALESCE(ncps.total_normal_city_thanks, 0) AS normal_city_thanks,
            -- Normal ilçe istatistikleri (tam)
            COALESCE(ndps.total_normal_district_complaints, 0) AS normal_district_complaints,
            COALESCE(ndps.total_normal_district_solved_complaints, 0) AS normal_district_solved_complaints,
            COALESCE(ndps.total_normal_district_thanks, 0) AS normal_district_thanks
        FROM 
            political_parties p
        LEFT JOIN 
            city_party_stats cps ON p.id = cps.political_party_id
        LEFT JOIN 
            district_party_stats dps ON p.id = dps.political_party_id
        LEFT JOIN 
            normal_city_party_stats ncps ON p.id = ncps.political_party_id
        LEFT JOIN 
            normal_district_party_stats ndps ON p.id = ndps.political_party_id
    )
    
    -- Parti istatistiklerini güncelle
    UPDATE political_parties pp
    SET 
        parti_sikayet_sayisi = CAST(ROUND(
            cs.metro_city_complaints + cs.metro_district_complaints +
            cs.normal_city_complaints + cs.normal_district_complaints
        ) AS INTEGER),
        parti_cozulmus_sikayet_sayisi = CAST(ROUND(
            cs.metro_city_solved_complaints + cs.metro_district_solved_complaints +
            cs.normal_city_solved_complaints + cs.normal_district_solved_complaints
        ) AS INTEGER),
        parti_tesekkur_sayisi = CAST(ROUND(
            cs.metro_city_thanks + cs.metro_district_thanks +
            cs.normal_city_thanks + cs.normal_district_thanks
        ) AS INTEGER)
    FROM 
        combined_stats cs
    WHERE 
        pp.id = cs.party_id;

    -- Parti başarı puanlarını hesapla
    WITH party_counts AS (
        -- Her bir partinin sayılarını al
        SELECT 
            id,
            name,
            parti_cozulmus_sikayet_sayisi,
            parti_tesekkur_sayisi,
            -- Parti başarı puanı
            (COALESCE(parti_cozulmus_sikayet_sayisi, 0) + COALESCE(parti_tesekkur_sayisi, 0)) AS success_count
        FROM 
            political_parties
    ),
    total_counts AS (
        -- Tüm partilerin toplam başarı sayısını hesapla
        SELECT 
            SUM(success_count) AS total_success_count
        FROM 
            party_counts
        WHERE 
            success_count > 0
    ),
    party_scores AS (
        -- 100 puanı tüm partilerin başarı sayılarına göre orantılı dağıt
        SELECT 
            id,
            name,
            success_count,
            CASE
                -- Eğer toplam başarı sayısı sıfırsa kimseye puan verme
                WHEN (SELECT total_success_count FROM total_counts) = 0 THEN 0
                -- Değilse puanı orantılı dağıt
                ELSE (success_count * 100.0) / (SELECT total_success_count FROM total_counts)
            END AS final_score
        FROM 
            party_counts
    )
    
    -- Puanları güncelle
    UPDATE political_parties pp
    SET score = ps.final_score,
	last_updated = NOW()
    FROM party_scores ps
    WHERE pp.id = ps.id;
END;
$$;


ALTER FUNCTION public.cron_update_party_scores() OWNER TO supabase_admin;

--
-- Name: daily_calculate_party_scores(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.daily_calculate_party_scores() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Parti skorlarını hesapla
    PERFORM calculate_party_scores();
    
    RAISE NOTICE 'Günlük parti skorları güncellendi: %', NOW();
END;
$$;


ALTER FUNCTION public.daily_calculate_party_scores() OWNER TO supabase_admin;

--
-- Name: FUNCTION daily_calculate_party_scores(); Type: COMMENT; Schema: public; Owner: supabase_admin
--

COMMENT ON FUNCTION public.daily_calculate_party_scores() IS 'Bu fonksiyon her gün gece yarısı çalıştırılmalıdır. 
Tüm partilerin performans skorlarını 100 üzerinden hesaplar.';


--
-- Name: decrement_comment_count(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.decrement_comment_count(post_id_param uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE posts
  SET comment_count = GREATEST(0, comment_count - 1)
  WHERE id = post_id_param;
END;
$$;


ALTER FUNCTION public.decrement_comment_count(post_id_param uuid) OWNER TO supabase_admin;

--
-- Name: decrement_like_count(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.decrement_like_count(post_id_param uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE posts
  SET like_count = GREATEST(0, like_count - 1)
  WHERE id = post_id_param;
END;
$$;


ALTER FUNCTION public.decrement_like_count(post_id_param uuid) OWNER TO supabase_admin;

--
-- Name: delete_post(text, uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.delete_post(post_id text, district_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_post_type TEXT;
    v_is_solved BOOLEAN;
BEGIN
    -- Gönderi bilgilerini al
    SELECT type, is_solved 
    INTO v_post_type, v_is_solved 
    FROM posts 
    WHERE id = post_id;
    
    -- İstatistikleri güncelle
    IF v_post_type = 'thanks' THEN
        -- Teşekkür gönderisi siliniyor
        PERFORM update_district_stats(
            district_id, 
            0,              -- total_complaints değişimi yok
            0,              -- solved_complaints değişimi yok
            -1              -- thanks_count -1 azalt
        );
    ELSE
        -- Şikayet/öneri gönderisi siliniyor
        PERFORM update_district_stats(
            district_id, 
            -1,             -- total_complaints -1 azalt
            CASE WHEN v_is_solved THEN -1 ELSE 0 END,  -- Çözüldüyse solved_complaints -1
            0               -- thanks_count değişimi yok
        );
    END IF;
    
    -- Gönderiyi sil
    DELETE FROM posts WHERE id = post_id;
    
    -- Parti skorlarını güncelle
    PERFORM calculate_party_scores_integer();
    
    RAISE NOTICE 'Gönderi silindi ve istatistikler güncellendi.';
END;
$$;


ALTER FUNCTION public.delete_post(post_id text, district_id uuid) OWNER TO supabase_admin;

--
-- Name: delete_post_fix_thanks(uuid, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.delete_post_fix_thanks(post_id uuid, district_name text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    post_type TEXT;
    d_id INTEGER;
    current_count INTEGER;
BEGIN
    SELECT type INTO post_type FROM posts WHERE id = post_id;
    RAISE NOTICE 'Silinen gönderi tipi: %', post_type;

    SELECT id INTO d_id FROM districts WHERE name = district_name;

    SELECT COALESCE(NULLIF(thanks_count, ''), '0')::INTEGER INTO current_count 
    FROM districts 
    WHERE id = d_id;

    RAISE NOTICE 'Silme öncesi teşekkür sayısı: %', current_count;

    DELETE FROM posts WHERE id = post_id;

    IF post_type = 'thanks' OR post_type = 'appreciation' THEN
        current_count := GREATEST(0, current_count - 1);

        UPDATE districts
        SET thanks_count = current_count::TEXT
        WHERE id = d_id;

        RAISE NOTICE 'Güncellenmiş teşekkür sayısı: %', current_count;
    END IF;
END;
$$;


ALTER FUNCTION public.delete_post_fix_thanks(post_id uuid, district_name text) OWNER TO supabase_admin;

--
-- Name: featured_post_delete_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.featured_post_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM update_featured_count(OLD.post_id);
  RETURN OLD;
END;
$$;


ALTER FUNCTION public.featured_post_delete_trigger() OWNER TO supabase_admin;

--
-- Name: featured_post_insert_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.featured_post_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM update_featured_count(NEW.post_id);
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.featured_post_insert_trigger() OWNER TO supabase_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: comments; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.comments (
    id uuid NOT NULL,
    post_id uuid,
    user_id uuid,
    content text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_hidden boolean DEFAULT false
);


ALTER TABLE public.comments OWNER TO supabase_admin;

--
-- Name: filter_visible_comments(boolean); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.filter_visible_comments(show_hidden boolean DEFAULT false) RETURNS SETOF public.comments
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF show_hidden OR (SELECT role FROM users WHERE id = auth.uid()) = 'admin' THEN
    RETURN QUERY SELECT * FROM comments;
  ELSE
    RETURN QUERY SELECT * FROM comments WHERE is_hidden = false;
  END IF;
END;
$$;


ALTER FUNCTION public.filter_visible_comments(show_hidden boolean) OWNER TO supabase_admin;

--
-- Name: posts; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.posts (
    id uuid NOT NULL,
    user_id uuid,
    title text NOT NULL,
    description text NOT NULL,
    media_url text,
    is_video boolean DEFAULT false,
    type text NOT NULL,
    city text NOT NULL,
    district text NOT NULL,
    like_count integer DEFAULT 0,
    comment_count integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    media_urls text,
    is_video_list text,
    category text DEFAULT 'other'::text,
    is_resolved boolean DEFAULT false,
    is_hidden boolean DEFAULT false,
    monthly_featured_count integer DEFAULT 0,
    is_featured boolean DEFAULT false,
    featured_count integer DEFAULT 0,
    status character varying(50) DEFAULT 'pending'::character varying,
    city_id uuid,
    district_id uuid,
    processing_date timestamp with time zone,
    processing_official_id integer,
    solution_date timestamp with time zone,
    solution_official_id integer,
    solution_note text,
    evidence_url text,
    rejection_date timestamp with time zone,
    rejection_official_id integer
);


ALTER TABLE public.posts OWNER TO supabase_admin;

--
-- Name: filter_visible_posts(boolean); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.filter_visible_posts(show_hidden boolean DEFAULT false) RETURNS SETOF public.posts
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF show_hidden OR (SELECT role FROM users WHERE id = auth.uid()) = 'admin' THEN
    RETURN QUERY SELECT * FROM posts;
  ELSE
    RETURN QUERY SELECT * FROM posts WHERE is_hidden = false;
  END IF;
END;
$$;


ALTER FUNCTION public.filter_visible_posts(show_hidden boolean) OWNER TO supabase_admin;

--
-- Name: handle_updated_at(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.handle_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.handle_updated_at() OWNER TO supabase_admin;

--
-- Name: increment_comment_count(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.increment_comment_count(post_id_param uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE posts
  SET comment_count = comment_count + 1
  WHERE id = post_id_param;
END;
$$;


ALTER FUNCTION public.increment_comment_count(post_id_param uuid) OWNER TO supabase_admin;

--
-- Name: increment_like_count(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.increment_like_count(post_id_param uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  UPDATE posts
  SET like_count = like_count + 1
  WHERE id = post_id_param;
END;
$$;


ALTER FUNCTION public.increment_like_count(post_id_param uuid) OWNER TO supabase_admin;

--
-- Name: is_user_banned(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.is_user_banned(user_id uuid) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
  ban_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO ban_count 
  FROM user_bans 
  WHERE user_id = is_user_banned.user_id 
    AND is_active = true 
    AND ban_end > now();

  RETURN ban_count > 0;
END;
$$;


ALTER FUNCTION public.is_user_banned(user_id uuid) OWNER TO supabase_admin;

--
-- Name: manual_update_all_stats(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.manual_update_all_stats() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM party_stats_update_all();
END;
$$;


ALTER FUNCTION public.manual_update_all_stats() OWNER TO supabase_admin;

--
-- Name: mark_post_as_solved(text, uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.mark_post_as_solved(post_id text, district_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Önce gönderiyi çözüldü olarak işaretle
    UPDATE posts
    SET is_solved = TRUE, 
        solved_at = NOW(),
        updated_at = NOW()
    WHERE id = post_id;
    
    -- İlçe istatistiklerini güncelle
    PERFORM update_district_stats(
        district_id, 
        0,  -- total_complaints değişimi yok
        1,  -- solved_complaints +1 arttır
        0   -- thanks_count değişimi yok
    );
    
    -- Parti skorlarını güncelle
    PERFORM calculate_party_scores_integer();
    
    RAISE NOTICE 'Gönderi çözüldü olarak işaretlendi ve istatistikler güncellendi.';
END;
$$;


ALTER FUNCTION public.mark_post_as_solved(post_id text, district_id uuid) OWNER TO supabase_admin;

--
-- Name: party_stats_calculate_scores(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_calculate_scores() RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
    party_record RECORD;
    total_points DECIMAL := 0;
    total_cities_count INT;
    party_solution_score DECIMAL;
BEGIN
    -- Toplam şehir sayısını hesapla
    SELECT COUNT(*) INTO total_cities_count FROM cities;
    
    -- Her parti için çözüm puanlarını hesapla ve topla
    FOR party_record IN 
        SELECT 
            p.id, 
            p.name,
            SUM(CASE 
                WHEN c.solution_rate ~ '^[0-9]+(\.[0-9]+)?$' 
                THEN c.solution_rate::DECIMAL 
                ELSE 0 
            END) as total_solution_rate
        FROM political_parties p
        LEFT JOIN cities c ON c.political_party_id = p.id
        GROUP BY p.id, p.name
    LOOP
        RAISE NOTICE 'Parti: %, Toplam Puan: %', 
            party_record.name, party_record.total_solution_rate;
        
        -- Toplam puanı hesapla (tüm partilerin toplam çözüm oranı)
        total_points := total_points + COALESCE(party_record.total_solution_rate, 0);
    END LOOP;
    
    RAISE NOTICE 'Tüm partilerin toplam puanı: %', total_points;
    
    -- Her bir parti için yeni puanı hesapla ve güncelle (100 üzerinden)
    IF total_points > 0 THEN
        FOR party_record IN 
            SELECT 
                p.id, 
                p.name,
                SUM(CASE 
                    WHEN c.solution_rate ~ '^[0-9]+(\.[0-9]+)?$' 
                    THEN c.solution_rate::DECIMAL 
                    ELSE 0 
                END) as total_solution_rate
            FROM political_parties p
            LEFT JOIN cities c ON c.political_party_id = p.id
            GROUP BY p.id, p.name
        LOOP
            -- Partinin payına düşen puanı hesapla (100 üzerinden)
            IF party_record.total_solution_rate IS NOT NULL AND party_record.total_solution_rate > 0 THEN
                party_solution_score := (party_record.total_solution_rate / total_points) * 100;
            ELSE
                party_solution_score := 0;
            END IF;
            
            -- Puanı yuvarla ve kaydet
            party_solution_score := ROUND(party_solution_score)::INTEGER;
            
            -- Parti skorunu güncelle
            UPDATE political_parties
            SET 
                score = party_solution_score,
                last_updated = CURRENT_TIMESTAMP
            WHERE id = party_record.id;
            
            RAISE NOTICE 'Parti: %, Yeni Puan: %', 
                party_record.name, party_solution_score;
        END LOOP;
    END IF;
END;
$_$;


ALTER FUNCTION public.party_stats_calculate_scores() OWNER TO supabase_admin;

--
-- Name: party_stats_post_delete_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_post_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  _district_id UUID := OLD.district_id; -- DÜZELTME: UUID olarak değiştirildi
BEGIN
  RAISE NOTICE 'Trigger tetiklendi, eski tip: %, district_id: %', OLD.type, _district_id;

  IF _district_id IS NULL THEN
    RAISE NOTICE 'District_id boş!';
    RETURN OLD;
  END IF;

  BEGIN
    IF OLD.type = 'complaint' THEN
      RAISE NOTICE 'Complaint silindi. District ID: %', _district_id;
      UPDATE districts
      SET total_complaints = GREATEST(0, total_complaints - 1)
      WHERE id = _district_id; -- UUID ile karşılaştırma
      
      IF OLD.is_resolved = true THEN
        UPDATE districts
        SET solved_complaints = GREATEST(0, solved_complaints - 1)
        WHERE id = _district_id;
      END IF;
      
    ELSIF OLD.type IN ('thanks', 'appreciation') THEN
      RAISE NOTICE 'Thanks/Appreciation silindi. District ID: %', _district_id;
      UPDATE districts
      SET thanks_count = GREATEST(0, thanks_count - 1)
      WHERE id = _district_id;
    ELSE
      RAISE NOTICE 'Tip koşullarına uymadı: %', OLD.type;
    END IF;
    
    -- Solution Rate Güncellemesi
    UPDATE districts
    SET solution_rate = CASE 
      WHEN (total_complaints + thanks_count) > 0 THEN 
        (solved_complaints + thanks_count)::DECIMAL / 
        (total_complaints + thanks_count)::DECIMAL * 100
      ELSE 0
    END
    WHERE id = _district_id;
    
    PERFORM party_stats_update_city_int((SELECT city_id FROM districts WHERE id = _district_id));
    PERFORM party_stats_calculate_scores();
    
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Hata: %', SQLERRM;
  END;
  
  RETURN OLD;
END;
$$;


ALTER FUNCTION public.party_stats_post_delete_trigger() OWNER TO supabase_admin;

--
-- Name: party_stats_post_insert_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_post_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  district_id INTEGER;
BEGIN
  -- Hata yakalamayı ekleyelim
  BEGIN
    -- İlçe ID'sini bul
    SELECT id INTO district_id FROM districts WHERE name = NEW.district;
    
    IF district_id IS NOT NULL THEN
      -- Gönderi tipine göre istatistik güncelleme
      IF NEW.type = 'complaint' THEN
        -- Şikayet gönderisi
        UPDATE districts
        SET total_complaints = total_complaints + 1
        WHERE id = district_id;
      ELSIF NEW.type = 'thanks' OR NEW.type = 'appreciation' THEN
        -- Teşekkür gönderisi
        UPDATE districts
        SET thanks_count = thanks_count + 1
        WHERE id = district_id;
      END IF;
      
      -- Çözüm oranını güncelle
      UPDATE districts
      SET solution_rate = CASE 
        WHEN total_complaints + thanks_count > 0 THEN 
          (solved_complaints + thanks_count)::DECIMAL / 
          (total_complaints + thanks_count)::DECIMAL * 100
        ELSE 0
      END
      WHERE id = district_id;
      
      -- İlgili şehri güncelle
      PERFORM party_stats_update_city_int((SELECT city_id FROM districts WHERE id = district_id));
      
      -- Parti skorlarını güncelle
      PERFORM party_stats_calculate_scores();
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Hata olursa yakalayıp işleme devam et
    RAISE NOTICE 'Gönderi için istatistik güncellemede hata: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.party_stats_post_insert_trigger() OWNER TO supabase_admin;

--
-- Name: party_stats_post_update_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_post_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  district_id INTEGER;
BEGIN
  -- Hata yakalamayı ekleyelim
  BEGIN
    -- İlçe ID'sini bul
    SELECT id INTO district_id FROM districts WHERE name = NEW.district;
    
    IF district_id IS NOT NULL THEN
      -- Eğer çözüm durumu değiştiyse
      IF OLD.is_resolved IS DISTINCT FROM NEW.is_resolved THEN
        IF NEW.is_resolved = true AND NEW.type = 'complaint' THEN
          -- Çözülen şikayet sayısını artır
          UPDATE districts
          SET solved_complaints = solved_complaints + 1
          WHERE id = district_id;
        ELSIF OLD.is_resolved = true AND OLD.type = 'complaint' THEN
          -- Çözülen şikayet sayısını azalt
          UPDATE districts
          SET solved_complaints = GREATEST(0, solved_complaints - 1)
          WHERE id = district_id;
        END IF;
      END IF;
      
      -- Eğer gönderi tipi değiştiyse
      IF OLD.type IS DISTINCT FROM NEW.type THEN
        -- Eski tip şikayet ise
        IF OLD.type = 'complaint' THEN
          UPDATE districts
          SET total_complaints = GREATEST(0, total_complaints - 1)
          WHERE id = district_id;
          
          -- Çözülmüş şikayet ise çözülen sayısını da azalt
          IF OLD.is_resolved = true THEN
            UPDATE districts
            SET solved_complaints = GREATEST(0, solved_complaints - 1)
            WHERE id = district_id;
          END IF;
        ELSIF OLD.type = 'thanks' OR OLD.type = 'appreciation' THEN
          UPDATE districts
          SET thanks_count = GREATEST(0, thanks_count - 1)
          WHERE id = district_id;
        END IF;
        
        -- Yeni tip şikayet ise
        IF NEW.type = 'complaint' THEN
          UPDATE districts
          SET total_complaints = total_complaints + 1
          WHERE id = district_id;
          
          -- Çözülmüş şikayet ise çözülen sayısını da artır
          IF NEW.is_resolved = true THEN
            UPDATE districts
            SET solved_complaints = solved_complaints + 1
            WHERE id = district_id;
          END IF;
        ELSIF NEW.type = 'thanks' OR NEW.type = 'appreciation' THEN
          UPDATE districts
          SET thanks_count = thanks_count + 1
          WHERE id = district_id;
        END IF;
      END IF;
      
      -- Çözüm oranını güncelle
      UPDATE districts
      SET solution_rate = CASE 
        WHEN total_complaints + thanks_count > 0 THEN 
          (solved_complaints + thanks_count)::DECIMAL / 
          (total_complaints + thanks_count)::DECIMAL * 100
        ELSE 0
      END
      WHERE id = district_id;
      
      -- İlgili şehri güncelle
      PERFORM party_stats_update_city_int((SELECT city_id FROM districts WHERE id = district_id));
      
      -- Parti skorlarını güncelle
      PERFORM party_stats_calculate_scores();
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Hata olursa yakalayıp işleme devam et
    RAISE NOTICE 'Gönderi için istatistik güncellemede hata: %', SQLERRM;
  END;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.party_stats_post_update_trigger() OWNER TO supabase_admin;

--
-- Name: party_stats_update_all(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_update_all() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  district_rec RECORD;
  city_rec RECORD;
BEGIN
  -- Try-catch bloğu ekleyelim
  BEGIN
    -- Önce tüm ilçelerin istatistiklerini güncelle
    FOR district_rec IN SELECT id FROM districts LOOP
      BEGIN
        PERFORM party_stats_update_district(district_rec.id);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'İlçe güncelleme hatası (ID: %): %', district_rec.id, SQLERRM;
      END;
    END LOOP;
    
    -- Sonra tüm şehirlerin istatistiklerini güncelle
    FOR city_rec IN SELECT id FROM cities LOOP
      BEGIN
        PERFORM party_stats_update_city(city_rec.id);
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Şehir güncelleme hatası (ID: %): %', city_rec.id, SQLERRM;
      END;
    END LOOP;
    
    -- En son parti skorlarını güncelle
    PERFORM party_stats_calculate_scores();
    
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Güncelleme sırasında hata: %', SQLERRM;
  END;
END;
$$;


ALTER FUNCTION public.party_stats_update_all() OWNER TO supabase_admin;

--
-- Name: party_stats_update_city(integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_update_city(city_id_param integer) RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
  is_metropolitan_var BOOLEAN;
  total_complaints_count INT := 0;
  solved_complaints_count INT := 0;
  thanks_count_value INT := 0;
  solution_rate_value DECIMAL := 0;
  city_name_var TEXT;
BEGIN
  -- Şehir adını ve büyükşehir olup olmadığını al
  SELECT name, c.is_metropolitan INTO city_name_var, is_metropolitan_var 
  FROM cities c
  WHERE c.id = city_id_param;
  
  -- Büyükşehir mi kontrolü
  IF is_metropolitan_var = true THEN
    -- Büyükşehir ise tüm ilçelerin toplamını al
    SELECT 
      COALESCE(SUM(CASE WHEN total_complaints ~ '^[0-9]+$' THEN total_complaints::INT ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN solved_complaints ~ '^[0-9]+$' THEN solved_complaints::INT ELSE 0 END), 0),
      COALESCE(SUM(CASE WHEN thanks_count ~ '^[0-9]+$' THEN thanks_count::INT ELSE 0 END), 0)
    INTO 
      total_complaints_count,
      solved_complaints_count,
      thanks_count_value
    FROM districts
    WHERE city_id = city_id_param;
  ELSE
    -- Normal şehir ise sadece "Merkez" ilçesini al
    SELECT 
      COALESCE(CASE WHEN total_complaints ~ '^[0-9]+$' THEN total_complaints::INT ELSE 0 END, 0),
      COALESCE(CASE WHEN solved_complaints ~ '^[0-9]+$' THEN solved_complaints::INT ELSE 0 END, 0),
      COALESCE(CASE WHEN thanks_count ~ '^[0-9]+$' THEN thanks_count::INT ELSE 0 END, 0)
    INTO 
      total_complaints_count,
      solved_complaints_count,
      thanks_count_value
    FROM districts
    WHERE city_id = city_id_param 
      AND name = 'Merkez';
  END IF;
  
  -- Çözüm oranını hesapla
  IF total_complaints_count + thanks_count_value > 0 THEN
    solution_rate_value := (solved_complaints_count + thanks_count_value)::DECIMAL / 
                        (total_complaints_count + thanks_count_value)::DECIMAL * 100;
  ELSE
    solution_rate_value := 0;
  END IF;

  -- Şehir tablosunu güncelle (TEXT olarak)
  UPDATE cities
  SET 
    total_complaints = total_complaints_count::TEXT,
    solved_complaints = solved_complaints_count::TEXT,
    thanks_count = thanks_count_value::TEXT,
    solution_rate = solution_rate_value::TEXT
  WHERE id = city_id_param;
END;
$_$;


ALTER FUNCTION public.party_stats_update_city(city_id_param integer) OWNER TO supabase_admin;

--
-- Name: party_stats_update_city_int(integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_update_city_int(city_id_param integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  is_metropolitan BOOLEAN;
  total_complaints_count INT := 0;
  solved_complaints_count INT := 0;
  thanks_count_value INT := 0;
  solution_rate_value DECIMAL := 0;
  city_name_var TEXT;
BEGIN
  -- Şehir adını al
  SELECT name, is_metropolitan INTO city_name_var, is_metropolitan 
  FROM cities 
  WHERE id = city_id_param;
  
  -- Büyükşehir mi kontrolü
  IF is_metropolitan = true THEN
    -- Büyükşehir ise tüm ilçelerin toplamını al
    SELECT 
      COALESCE(SUM(total_complaints), 0),
      COALESCE(SUM(solved_complaints), 0),
      COALESCE(SUM(thanks_count), 0)
    INTO 
      total_complaints_count,
      solved_complaints_count,
      thanks_count_value
    FROM districts
    WHERE city_id = city_id_param;
  ELSE
    -- Normal şehir ise sadece "Merkez" ilçesini al
    SELECT 
      COALESCE(total_complaints, 0),
      COALESCE(solved_complaints, 0),
      COALESCE(thanks_count, 0)
    INTO 
      total_complaints_count,
      solved_complaints_count,
      thanks_count_value
    FROM districts
    WHERE city_id = city_id_param 
      AND name = 'Merkez';
  END IF;
  
  -- Çözüm oranını hesapla
  IF total_complaints_count + thanks_count_value > 0 THEN
    solution_rate_value := (solved_complaints_count + thanks_count_value)::DECIMAL / 
                        (total_complaints_count + thanks_count_value)::DECIMAL * 100;
  ELSE
    solution_rate_value := 0;
  END IF;

  -- Şehir tablosunu güncelle
  UPDATE cities
  SET 
    total_complaints = total_complaints_count,
    solved_complaints = solved_complaints_count,
    thanks_count = thanks_count_value,
    solution_rate = solution_rate_value
  WHERE id = city_id_param;
END;
$$;


ALTER FUNCTION public.party_stats_update_city_int(city_id_param integer) OWNER TO supabase_admin;

--
-- Name: party_stats_update_district(integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_update_district(district_id_param integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  total_complaints_count INT;
  solved_complaints_count INT;
  thanks_posts_count INT;
  solution_rate_value DECIMAL;
  district_name TEXT;
BEGIN
  -- İlçe adını al
  SELECT name INTO district_name FROM districts WHERE id = district_id_param;
  
  -- İlgili ilçe için şikayet sayımı
  SELECT COUNT(*) INTO total_complaints_count
  FROM posts
  WHERE district = district_name
  AND type = 'complaint';
  
  -- Çözülen şikayet sayımı
  SELECT COUNT(*) INTO solved_complaints_count
  FROM posts
  WHERE district = district_name
  AND type = 'complaint'
  AND is_resolved = true;
  
  -- Teşekkür gönderisi sayımı
  SELECT COUNT(*) INTO thanks_posts_count
  FROM posts
  WHERE district = district_name
  AND (type = 'thanks' OR type = 'appreciation');
  
  -- Çözüm oranını hesapla
  IF total_complaints_count + thanks_posts_count > 0 THEN
    solution_rate_value := (solved_complaints_count + thanks_posts_count)::DECIMAL / 
                          (total_complaints_count + thanks_posts_count)::DECIMAL * 100;
  ELSE
    solution_rate_value := 0;
  END IF;
  
  -- İlçe tablosunu güncelle (TEXT olarak)
  UPDATE districts
  SET total_complaints = total_complaints_count::TEXT,
      solved_complaints = solved_complaints_count::TEXT,
      thanks_count = thanks_posts_count::TEXT,
      solution_rate = solution_rate_value::TEXT
  WHERE id = district_id_param;
END;
$$;


ALTER FUNCTION public.party_stats_update_district(district_id_param integer) OWNER TO supabase_admin;

--
-- Name: party_stats_update_district_int(integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.party_stats_update_district_int(district_id_param integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  total_complaints_count INT;
  solved_complaints_count INT;
  thanks_posts_count INT;
  solution_rate_value DECIMAL;
  district_name TEXT;
BEGIN
  -- İlçe adını al
  SELECT name INTO district_name FROM districts WHERE id = district_id_param;
  
  -- İlgili ilçe için şikayet sayımı
  SELECT COUNT(*) INTO total_complaints_count
  FROM posts
  WHERE district = district_name
  AND type = 'complaint';
  
  -- Çözülen şikayet sayımı
  SELECT COUNT(*) INTO solved_complaints_count
  FROM posts
  WHERE district = district_name
  AND type = 'complaint'
  AND is_resolved = true;
  
  -- Teşekkür gönderisi sayımı
  SELECT COUNT(*) INTO thanks_posts_count
  FROM posts
  WHERE district = district_name
  AND (type = 'thanks' OR type = 'appreciation');
  
  -- Çözüm oranını hesapla
  IF total_complaints_count + thanks_posts_count > 0 THEN
    solution_rate_value := (solved_complaints_count + thanks_posts_count)::DECIMAL / 
                           (total_complaints_count + thanks_posts_count)::DECIMAL * 100;
  ELSE
    solution_rate_value := 0;
  END IF;
  
  -- İlçe tablosunu güncelle
  UPDATE districts
  SET total_complaints = total_complaints_count,
      solved_complaints = solved_complaints_count,
      thanks_count = thanks_posts_count,
      solution_rate = solution_rate_value
  WHERE id = district_id_param;
END;
$$;


ALTER FUNCTION public.party_stats_update_district_int(district_id_param integer) OWNER TO supabase_admin;

--
-- Name: unmark_post_as_solved(text, uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.unmark_post_as_solved(post_id text, district_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Önce gönderinin çözüldü işaretini kaldır
    UPDATE posts
    SET is_solved = FALSE, 
        solved_at = NULL,
        updated_at = NOW()
    WHERE id = post_id;
    
    -- İlçe istatistiklerini güncelle
    PERFORM update_district_stats(
        district_id, 
        0,             -- total_complaints değişimi yok
        -1,            -- solved_complaints -1 azalt
        0              -- thanks_count değişimi yok
    );
    
    -- Parti skorlarını güncelle
    PERFORM calculate_party_scores_integer();
    
    RAISE NOTICE 'Gönderinin çözüldü işareti kaldırıldı ve istatistikler güncellendi.';
END;
$$;


ALTER FUNCTION public.unmark_post_as_solved(post_id text, district_id uuid) OWNER TO supabase_admin;

--
-- Name: update_ad_stats(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_ad_stats() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.interaction_type = 'impression' THEN
        UPDATE sponsored_ads SET impressions = impressions + 1 WHERE id = NEW.ad_id;
    ELSIF NEW.interaction_type = 'click' THEN
        UPDATE sponsored_ads SET clicks = clicks + 1 WHERE id = NEW.ad_id;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_ad_stats() OWNER TO supabase_admin;

--
-- Name: update_all_monthly_featured_counts(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_all_monthly_featured_counts() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  post_id_var UUID;
  post_ids CURSOR FOR SELECT id FROM posts;
BEGIN
  OPEN post_ids;
  LOOP
    FETCH post_ids INTO post_id_var;
    EXIT WHEN NOT FOUND;
    
    -- Her gönderi için öne çıkarma sayısını güncelle
    PERFORM update_featured_count(post_id_var);
  END LOOP;
  CLOSE post_ids;
END;
$$;


ALTER FUNCTION public.update_all_monthly_featured_counts() OWNER TO supabase_admin;

--
-- Name: update_all_statistics(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_all_statistics() RETURNS void
    LANGUAGE plpgsql
    AS $_$
DECLARE
    district_rec RECORD;
    city_rec RECORD;
    v_total_complaints INT;
    v_solved_complaints INT;
    v_thanks_count INT;
    v_solution_rate DECIMAL(5,2);
    v_district_count INT;
BEGIN
    -- 1. Önce tüm ilçelerin çözüm oranlarını hesapla
    FOR district_rec IN SELECT id FROM districts LOOP
        -- İlçe istatistiklerini güncelle
        SELECT 
            COALESCE(total_complaints, 0)::INT,
            COALESCE(solved_complaints, 0)::INT,
            COALESCE(thanks_count, 0)::INT
        INTO 
            v_total_complaints,
            v_solved_complaints,
            v_thanks_count
        FROM districts
        WHERE id = district_rec.id;
        
        -- Çözüm oranını hesapla
        IF (v_total_complaints + v_thanks_count) > 0 THEN
            v_solution_rate := ((v_thanks_count + v_solved_complaints)::DECIMAL / 
                            (v_total_complaints + v_thanks_count)::DECIMAL) * 100;
        ELSE
            v_solution_rate := 0;
        END IF;
        
        -- İlçe skorunu güncelle
        UPDATE districts
        SET solution_rate = v_solution_rate,
            solution_last_updated = NOW()
        WHERE id = district_rec.id;
    END LOOP;
    
    -- 2. Şimdi şehir skorlarını hesapla
    FOR city_rec IN SELECT id, name, is_metropolitan FROM cities LOOP
        -- Büyükşehir ise, tüm ilçelerin toplamını hesapla
        IF city_rec.is_metropolitan THEN
            -- İlçe sayısını bul
            SELECT COUNT(*) INTO v_district_count
            FROM districts
            WHERE city_id = city_rec.id;
            
            -- Tüm ilçelerin toplam değerlerini al
            SELECT 
                SUM(COALESCE(total_complaints, 0)::INT),
                SUM(COALESCE(solved_complaints, 0)::INT),
                SUM(COALESCE(thanks_count, 0)::INT)
            INTO
                v_total_complaints,
                v_solved_complaints,
                v_thanks_count
            FROM districts
            WHERE city_id = city_rec.id;
            
            -- Çözüm oranını hesapla
            IF (v_total_complaints + v_thanks_count) > 0 THEN
                v_solution_rate := ((v_thanks_count + v_solved_complaints)::DECIMAL / 
                                (v_total_complaints + v_thanks_count)::DECIMAL) * 100;
            ELSE
                v_solution_rate := 0;
            END IF;
            
            -- Şehir skorlarını güncelle (büyükşehir için)
            UPDATE cities
            SET total_complaints = COALESCE(v_total_complaints, 0),
                solved_complaints = COALESCE(v_solved_complaints, 0),
                thanks_count = COALESCE(v_thanks_count, 0),
                solution_rate = COALESCE(v_solution_rate, 0),
                solution_last_updated = NOW()
            WHERE id = city_rec.id;
            
        ELSE
            -- Büyükşehir değilse, Merkez ilçesinin değerlerini kullan
            SELECT 
                COALESCE(d.total_complaints, 0)::INT,
                COALESCE(d.solved_complaints, 0)::INT,
                COALESCE(d.thanks_count, 0)::INT,
                COALESCE(d.solution_rate, 0)::DECIMAL
            INTO
                v_total_complaints,
                v_solved_complaints,
                v_thanks_count,
                v_solution_rate
            FROM districts d
            WHERE d.city_id = city_rec.id AND d.name = 'Merkez'
            LIMIT 1;
            
            -- Merkez ilçe bulunamadıysa 0 değerlerini kullan
            IF v_total_complaints IS NULL THEN
                v_total_complaints := 0;
                v_solved_complaints := 0;
                v_thanks_count := 0;
                v_solution_rate := 0;
            END IF;
            
            -- Şehir skorlarını güncelle (normal şehir için)
            UPDATE cities
            SET total_complaints = v_total_complaints,
                solved_complaints = v_solved_complaints,
                thanks_count = v_thanks_count,
                solution_rate = v_solution_rate,
                solution_last_updated = NOW()
            WHERE id = city_rec.id;
        END IF;
    END LOOP;
    
    -- 3. Son olarak, parti skorlarını tam sayı olarak hesapla
    UPDATE political_parties p
    SET score = ROUND((
        SELECT COALESCE(AVG(
            CASE 
                WHEN d.solution_rate IS NULL THEN 0
                WHEN d.solution_rate::TEXT ~ '^[0-9]+(\.[0-9]+)?$' THEN d.solution_rate::DECIMAL
                ELSE 0
            END
        ), 0) 
        FROM districts d
        WHERE d.political_party_id = p.id
    )),
    last_updated = NOW();
    
    RAISE NOTICE 'Tüm istatistikler başarıyla güncellendi.';
END;
$_$;


ALTER FUNCTION public.update_all_statistics() OWNER TO supabase_admin;

--
-- Name: update_city_scores_trigger(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_city_scores_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_city_id UUID;
    v_city_name TEXT;
    v_is_metro BOOLEAN;
    v_total_complaints_sum INT := 0;
    v_solved_complaints_sum INT := 0;
    v_thanks_count_sum INT := 0;
    v_solution_rate_avg DECIMAL(5,2) := 0;
    v_district_count INT := 0;
    v_merkez_exists BOOLEAN := FALSE;
BEGIN
    -- İlçenin bağlı olduğu şehir ID'sini al
    v_city_id := NEW.city_id;
    
    -- Şehir bilgilerini al
    SELECT name, is_metropolitan INTO v_city_name, v_is_metro 
    FROM cities 
    WHERE id = v_city_id;
    
    -- Büyükşehir mi kontrolü
    IF v_is_metro IS TRUE THEN
        -- Büyükşehir için tüm ilçelerin toplamını hesapla
        SELECT 
            COUNT(*),
            SUM(COALESCE(total_complaints::INT, 0)),
            SUM(COALESCE(solved_complaints::INT, 0)),
            SUM(COALESCE(thanks_count::INT, 0))
        INTO
            v_district_count,
            v_total_complaints_sum,
            v_solved_complaints_sum,
            v_thanks_count_sum
        FROM districts
        WHERE city_id = v_city_id;
        
        -- Çözüm oranını hesapla
        IF (v_total_complaints_sum + v_thanks_count_sum) > 0 THEN
            v_solution_rate_avg := ((v_thanks_count_sum + v_solved_complaints_sum)::DECIMAL / 
                                (v_total_complaints_sum + v_thanks_count_sum)::DECIMAL) * 100;
        ELSE
            v_solution_rate_avg := 0;
        END IF;
        
        -- Şehir skorlarını güncelle - Veri tiplerini kontrol edelim
        UPDATE cities
        SET total_complaints = v_total_complaints_sum,
            solved_complaints = v_solved_complaints_sum,
            thanks_count = v_thanks_count_sum,
            solution_rate = v_solution_rate_avg,
            solution_last_updated = NOW()
        WHERE id = v_city_id;
    ELSE
        -- Büyükşehir değilse, "Merkez" ilçesi var mı kontrol et
        SELECT EXISTS (
            SELECT 1 FROM districts d
            WHERE d.city_id = v_city_id AND d.name = 'Merkez'
        ) INTO v_merkez_exists;
        
        IF v_merkez_exists THEN
            -- Merkez ilçesinin değerlerini al
            SELECT 
                COALESCE(d.total_complaints::INT, 0),
                COALESCE(d.solved_complaints::INT, 0),
                COALESCE(d.thanks_count::INT, 0),
                COALESCE(d.solution_rate::DECIMAL, 0)
            INTO
                v_total_complaints_sum,
                v_solved_complaints_sum,
                v_thanks_count_sum,
                v_solution_rate_avg
            FROM districts d
            WHERE d.city_id = v_city_id AND d.name = 'Merkez';
            
            -- Şehir skorlarını güncelle - Veri tiplerini kontrol edelim
            UPDATE cities
            SET total_complaints = v_total_complaints_sum,
                solved_complaints = v_solved_complaints_sum,
                thanks_count = v_thanks_count_sum,
                solution_rate = v_solution_rate_avg,
                solution_last_updated = NOW()
            WHERE id = v_city_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_city_scores_trigger() OWNER TO supabase_admin;

--
-- Name: update_comment_badges(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_comment_badges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  post_owner_id UUID;
  comment_count INT;
  badge RECORD;
BEGIN
  -- Gönderinin sahibini bul
  SELECT user_id INTO post_owner_id FROM posts WHERE id = NEW.post_id;
  
  -- Yorum sayısını bul
  SELECT COUNT(*) INTO comment_count FROM comments 
  WHERE post_id IN (SELECT id FROM posts WHERE user_id = post_owner_id);
  
  -- Yorum rozetlerini kontrol et
  FOR badge IN 
    SELECT * FROM badges WHERE category = 'comments' ORDER BY level ASC
  LOOP
    -- Eğer rozet daha önce kazanılmamışsa ve gerekli sayıya ulaşıldıysa
    IF comment_count >= badge.required_count THEN
      -- Kullanıcının bu rozeti var mı diye kontrol et
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = post_owner_id AND badge_id = badge.id) THEN
        -- Rozeti kullanıcıya ekle
        INSERT INTO user_badges (user_id, badge_id, current_count, earned_at)
        VALUES (post_owner_id, badge.id, comment_count, NOW());
        
        -- Bildirim gönder (notifications tablosu varsa)
        BEGIN
          INSERT INTO notifications (
            user_id, 
            title, 
            content, 
            type, 
            related_entity_id, 
            related_entity_type
          ) VALUES (
            post_owner_id,
            'Yeni Rozet Kazandınız!',
            'Tebrikler! "' || badge.name || '" rozetini kazandınız.',
            'badge',
            badge.id::TEXT,
            'badge'
          );
        EXCEPTION WHEN OTHERS THEN
          -- Bildirim eklenemezse sessizce devam et
          NULL;
        END;
      ELSE
        -- Mevcut rozeti güncelle
        UPDATE user_badges 
        SET current_count = comment_count
        WHERE user_id = post_owner_id AND badge_id = badge.id;
      END IF;
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_comment_badges() OWNER TO supabase_admin;

--
-- Name: update_district_statistics(text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_district_statistics(district_name text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  district_id INTEGER;
  city_id INTEGER;
  total_complaints_count INT;
  solved_complaints_count INT;
  thanks_posts_count INT;
  solution_rate_value DECIMAL;
BEGIN
  -- İlçe ID'sini bul
  SELECT id, city_id INTO district_id, city_id 
  FROM districts 
  WHERE name = district_name;
  
  IF district_id IS NULL THEN
    RETURN;
  END IF;
  
  -- İstatistikleri hesapla
  SELECT 
    COUNT(*) FILTER (WHERE type = 'complaint'),
    COUNT(*) FILTER (WHERE type = 'complaint' AND is_resolved = true),
    COUNT(*) FILTER (WHERE type = 'thanks' OR type = 'appreciation')
  INTO
    total_complaints_count, solved_complaints_count, thanks_posts_count
  FROM posts
  WHERE district = district_name;
  
  -- Çözüm oranını hesapla
  IF total_complaints_count + thanks_posts_count > 0 THEN
    solution_rate_value := (solved_complaints_count + thanks_posts_count)::DECIMAL / 
                        (total_complaints_count + thanks_posts_count)::DECIMAL * 100;
  ELSE
    solution_rate_value := 0;
  END IF;
  
  -- İlçe tablosunu güncelle
  UPDATE districts
  SET 
    total_complaints = total_complaints_count::TEXT,
    solved_complaints = solved_complaints_count::TEXT,
    thanks_count = thanks_posts_count::TEXT,
    solution_rate = solution_rate_value::TEXT
  WHERE id = district_id;
  
  -- Şehir istatistiklerini güncelle
  IF city_id IS NOT NULL THEN
    PERFORM party_stats_update_city(city_id);
  END IF;
END;
$$;


ALTER FUNCTION public.update_district_statistics(district_name text) OWNER TO supabase_admin;

--
-- Name: update_district_stats(uuid, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_district_stats(p_district_id uuid, p_total_complaints_change integer DEFAULT 0, p_solved_complaints_change integer DEFAULT 0, p_thanks_count_change integer DEFAULT 0) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_complaints INT;
    v_solved_complaints INT;
    v_thanks_count INT;
    v_solution_rate DECIMAL(5,2);
    v_numerator INT;
    v_denominator INT;
BEGIN
    -- Mevcut değerleri al
    SELECT 
        COALESCE(total_complaints::INT, 0),
        COALESCE(solved_complaints::INT, 0),
        COALESCE(thanks_count::INT, 0)
    INTO 
        v_total_complaints,
        v_solved_complaints,
        v_thanks_count
    FROM districts
    WHERE id = p_district_id;
    
    -- Değerleri güncelle
    v_total_complaints := v_total_complaints + p_total_complaints_change;
    v_solved_complaints := v_solved_complaints + p_solved_complaints_change;
    v_thanks_count := v_thanks_count + p_thanks_count_change;
    
    -- Negatif olmasını engelle
    IF v_total_complaints < 0 THEN
        v_total_complaints := 0;
    END IF;
    
    IF v_solved_complaints < 0 THEN
        v_solved_complaints := 0;
    END IF;
    
    IF v_thanks_count < 0 THEN
        v_thanks_count := 0;
    END IF;
    
    -- Çözülen sayısı toplam şikayetlerden fazla olmasın
    IF v_solved_complaints > v_total_complaints THEN
        v_solved_complaints := v_total_complaints;
    END IF;
    
    -- Çözüm oranını hesapla: (çözülen+teşekkür)/(toplam+teşekkür)*100
    v_numerator := (v_total_complaints + v_thanks_count);
    v_denominator := (v_thanks_count + v_solved_complaints);
    
    IF v_numerator > 0 AND v_denominator > 0 THEN
        v_solution_rate := (v_denominator::DECIMAL / v_numerator::DECIMAL) * 100;
    ELSE
        v_solution_rate := 0;
    END IF;
    
    -- Verileri güncelle
    UPDATE districts
    SET total_complaints = v_total_complaints::TEXT,
        solved_complaints = v_solved_complaints::TEXT,
        thanks_count = v_thanks_count::TEXT,
        solution_rate = v_solution_rate::TEXT,
        solution_last_updated = NOW()
    WHERE id = p_district_id;
END;
$$;


ALTER FUNCTION public.update_district_stats(p_district_id uuid, p_total_complaints_change integer, p_solved_complaints_change integer, p_thanks_count_change integer) OWNER TO supabase_admin;

--
-- Name: update_featured_count(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_featured_count(post_id_param uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  count_val INTEGER;
  monthly_count_val INTEGER;
BEGIN
  -- Gönderi için toplam öne çıkarma sayısını hesapla
  SELECT COUNT(*) INTO count_val
  FROM featured_posts
  WHERE post_id = post_id_param;
  
  -- Son 1 aydaki öne çıkarma sayısını hesapla
  SELECT COUNT(*) INTO monthly_count_val
  FROM featured_posts
  WHERE post_id = post_id_param
  AND created_at >= NOW() - INTERVAL '1 month';
  
  -- Gönderi tablosundaki sayıları güncelle
  UPDATE posts
  SET 
    featured_count = count_val,
    monthly_featured_count = monthly_count_val,
    is_featured = count_val > 0
  WHERE id = post_id_param;
END;
$$;


ALTER FUNCTION public.update_featured_count(post_id_param uuid) OWNER TO supabase_admin;

--
-- Name: update_like_badges(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_like_badges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  post_owner_id UUID;
  like_count INT;
  badge RECORD;
BEGIN
  -- Gönderinin sahibini bul
  SELECT user_id INTO post_owner_id FROM posts WHERE id = NEW.post_id;
  
  -- Beğeni sayısını bul
  SELECT COUNT(*) INTO like_count FROM likes 
  WHERE post_id IN (SELECT id FROM posts WHERE user_id = post_owner_id);
  
  -- Beğeni rozetlerini kontrol et
  FOR badge IN 
    SELECT * FROM badges WHERE category = 'likes' ORDER BY level ASC
  LOOP
    -- Eğer rozet daha önce kazanılmamışsa ve gerekli sayıya ulaşıldıysa
    IF like_count >= badge.required_count THEN
      -- Kullanıcının bu rozeti var mı diye kontrol et
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = post_owner_id AND badge_id = badge.id) THEN
        -- Rozeti kullanıcıya ekle
        INSERT INTO user_badges (user_id, badge_id, current_count, earned_at)
        VALUES (post_owner_id, badge.id, like_count, NOW());
        
        -- Bildirim gönder (notifications tablosu varsa)
        BEGIN
          INSERT INTO notifications (
            user_id, 
            title, 
            content, 
            type, 
            related_entity_id, 
            related_entity_type
          ) VALUES (
            post_owner_id,
            'Yeni Rozet Kazandınız!',
            'Tebrikler! "' || badge.name || '" rozetini kazandınız.',
            'badge',
            badge.id::TEXT,
            'badge'
          );
        EXCEPTION WHEN OTHERS THEN
          -- Bildirim eklenemezse sessizce devam et
          NULL;
        END;
      ELSE
        -- Mevcut rozeti güncelle
        UPDATE user_badges 
        SET current_count = like_count
        WHERE user_id = post_owner_id AND badge_id = badge.id;
      END IF;
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_like_badges() OWNER TO supabase_admin;

--
-- Name: update_party_score_for_entity(text, uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_party_score_for_entity(entity_type text, entity_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  party_id UUID;
BEGIN
  -- Entity tipine göre parti ID'sini al
  IF entity_type = 'city' THEN
    SELECT political_party_id INTO party_id FROM cities WHERE id = entity_id;
  ELSIF entity_type = 'district' THEN
    SELECT political_party_id INTO party_id FROM districts WHERE id = entity_id;
  ELSE
    RETURN;
  END IF;
  
  -- Parti ID'si yoksa işlemi sonlandır
  IF party_id IS NULL THEN
    RETURN;
  END IF;
  
  -- Parti puanını hesapla ve güncelle
  PERFORM update_party_scores(party_id);
END;
$$;


ALTER FUNCTION public.update_party_score_for_entity(entity_type text, entity_id uuid) OWNER TO supabase_admin;

--
-- Name: update_party_scores(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_party_scores(party_id uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  current_party_id UUID;
  party_rec RECORD;
  city_count INT;
  district_count INT;
  total_solution_rate NUMERIC;
  district_solution_rate NUMERIC;
  entity_count INT;
  avg_solution_rate NUMERIC;
  normalized_score NUMERIC;
BEGIN
  -- Tek parti için mi yoksa tüm partiler için mi çalışacağımızı belirle
  IF party_id IS NOT NULL THEN
    -- Tek bir parti için hesaplama
    
    -- Bu parti ile ilişkili şehir ve ilçelerin çözüm oranlarının toplamını hesapla
    SELECT 
      COUNT(c.id), 
      SUM(c.solution_rate)
    INTO 
      city_count,
      total_solution_rate
    FROM 
      cities c
    WHERE 
      c.political_party_id = party_id AND
      c.solution_rate > 0;
    
    -- İlk başta city_count ve total_solution_rate NULL olabilir, kontrol ediyoruz
    city_count := COALESCE(city_count, 0);
    total_solution_rate := COALESCE(total_solution_rate, 0);
    
    -- Bu parti ile ilişkili ilçelerin çözüm oranlarının toplamını hesapla
    SELECT 
      COUNT(d.id), 
      SUM(d.solution_rate)
    INTO 
      district_count,
      district_solution_rate
    FROM 
      districts d
    WHERE 
      d.political_party_id = party_id AND
      d.solution_rate > 0;
    
    -- İlk başta district_count ve district_solution_rate NULL olabilir, kontrol ediyoruz
    district_count := COALESCE(district_count, 0);
    district_solution_rate := COALESCE(district_solution_rate, 0);
    
    -- Toplam entity sayısı ve toplam çözüm oranı
    entity_count := city_count + district_count;
    total_solution_rate := total_solution_rate + district_solution_rate;
    
    -- Ortalama çözüm oranını hesapla
    IF entity_count > 0 THEN
      avg_solution_rate := total_solution_rate / entity_count;
    ELSE
      avg_solution_rate := 0;
    END IF;
    
    -- Parti puanını 0-10 arası bir değere dönüştür
    normalized_score := LEAST(10, avg_solution_rate / 10);
    
    -- Parti puanını güncelle
    UPDATE political_parties
    SET 
      score = normalized_score,
      last_updated = CURRENT_TIMESTAMP
    WHERE 
      id = party_id;
      
  ELSE
    -- Tüm partiler için hesaplama
    FOR party_rec IN SELECT id FROM political_parties LOOP
      current_party_id := party_rec.id;
      
      -- Recursive olmayan şekilde fonksiyonu tekrar çağır (tek parti için)
      PERFORM update_party_scores(current_party_id);
    END LOOP;
  END IF;
END;
$$;


ALTER FUNCTION public.update_party_scores(party_id uuid) OWNER TO supabase_admin;

--
-- Name: update_post_badges(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_post_badges() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  post_count INT;
  badge RECORD;
BEGIN
  -- Gönderi sayısını bul
  SELECT COUNT(*) INTO post_count FROM posts WHERE user_id = NEW.user_id;
  
  -- Gönderi rozetlerini kontrol et
  FOR badge IN 
    SELECT * FROM badges WHERE category = 'posts' ORDER BY level ASC
  LOOP
    -- Eğer rozet daha önce kazanılmamışsa ve gerekli sayıya ulaşıldıysa
    IF post_count >= badge.required_count THEN
      -- Kullanıcının bu rozeti var mı diye kontrol et
      IF NOT EXISTS (SELECT 1 FROM user_badges WHERE user_id = NEW.user_id AND badge_id = badge.id) THEN
        -- Rozeti kullanıcıya ekle
        INSERT INTO user_badges (user_id, badge_id, current_count, earned_at)
        VALUES (NEW.user_id, badge.id, post_count, NOW());
        
        -- Bildirim gönder (notifications tablosu varsa)
        BEGIN
          INSERT INTO notifications (
            user_id, 
            title, 
            content, 
            type, 
            related_entity_id, 
            related_entity_type
          ) VALUES (
            NEW.user_id,
            'Yeni Rozet Kazandınız!',
            'Tebrikler! "' || badge.name || '" rozetini kazandınız.',
            'badge',
            badge.id::TEXT,
            'badge'
          );
        EXCEPTION WHEN OTHERS THEN
          -- Bildirim eklenemezse sessizce devam et
          NULL;
        END;
      ELSE
        -- Mevcut rozeti güncelle
        UPDATE user_badges 
        SET current_count = post_count
        WHERE user_id = NEW.user_id AND badge_id = badge.id;
      END IF;
    END IF;
  END LOOP;
  
  RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_post_badges() OWNER TO supabase_admin;

--
-- Name: update_resolution_badges_status(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_resolution_badges_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
      DECLARE
        resolution_count INT;
        badge RECORD;
      BEGIN
        IF NEW.status = 'resolved' AND (OLD.status IS NULL OR OLD.status != 'resolved') THEN
          SELECT COUNT(*) INTO resolution_count FROM posts 
          WHERE user_id = NEW.user_id AND status = 'resolved';

          FOR badge IN 
            SELECT * FROM badges WHERE category = 'resolutions' ORDER BY level ASC
          LOOP
            IF resolution_count >= badge.required_count THEN
              IF NOT EXISTS (
                SELECT 1 FROM user_badges 
                WHERE user_id = NEW.user_id AND badge_id = badge.id
              ) THEN
                INSERT INTO user_badges (user_id, badge_id, current_count, earned_at)
                VALUES (NEW.user_id, badge.id, resolution_count, NOW());

                BEGIN
                  INSERT INTO notifications (
                    user_id, 
                    title, 
                    content, 
                    type, 
                    related_entity_id, 
                    related_entity_type
                  ) VALUES (
                    NEW.user_id,
                    'Yeni Rozet Kazandınız!',
                    'Tebrikler! "' || badge.name || '" rozetini kazandınız.',
                    'badge',
                    badge.id::TEXT,
                    'badge'
                  );
                EXCEPTION WHEN OTHERS THEN
                  NULL;
                END;
              ELSE
                UPDATE user_badges 
                SET current_count = resolution_count
                WHERE user_id = NEW.user_id AND badge_id = badge.id;
              END IF;
            END IF;
          END LOOP;
        END IF;
        RETURN NEW;
      END;
      $$;


ALTER FUNCTION public.update_resolution_badges_status() OWNER TO supabase_admin;

--
-- Name: update_sponsored_ads_stats(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_sponsored_ads_stats() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Her reklam için toplu sayım yaparak güncelleme
    UPDATE sponsored_ads AS sa
    SET 
        impressions = (
            SELECT COUNT(*) 
            FROM ad_interactions 
            WHERE ad_id = sa.id AND interaction_type = 'impression'
        ),
        clicks = (
            SELECT COUNT(*) 
            FROM ad_interactions 
            WHERE ad_id = sa.id AND interaction_type = 'click'
        ),
        updated_at = NOW();
        
    RAISE NOTICE 'Reklam istatistikleri toplu olarak güncellendi: %', NOW();
END;
$$;


ALTER FUNCTION public.update_sponsored_ads_stats() OWNER TO supabase_admin;

--
-- Name: update_stats_on_post_changes(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_stats_on_post_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
DECLARE
    district_name TEXT;
    city_id_var INTEGER;
    total_complaints_count INT;
    solved_complaints_count INT;
    thanks_count_value INT;
    solution_rate_calc DECIMAL;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE NOTICE 'Silinen gönderinin tipi: %', OLD.type;
        district_name := OLD.district;
    ELSE
        district_name := NEW.district;
    END IF;

    RAISE NOTICE 'İşlenen ilçe: %', district_name;

    SELECT 
        COUNT(*) FILTER (WHERE type = 'complaint'),
        COUNT(*) FILTER (WHERE type = 'complaint' AND is_resolved = true),
        COUNT(*) FILTER (WHERE type = 'thanks' OR type = 'appreciation')
    INTO
        total_complaints_count, solved_complaints_count, thanks_count_value
    FROM posts
    WHERE district = district_name;

    RAISE NOTICE 'İlçe istatistikleri: şikayet=%, çözülen=%, teşekkür=%', 
        total_complaints_count, solved_complaints_count, thanks_count_value;

    UPDATE districts
    SET 
        total_complaints = total_complaints_count::TEXT,
        solved_complaints = solved_complaints_count::TEXT,
        thanks_count = thanks_count_value::TEXT
    WHERE name = district_name;

    IF (total_complaints_count + thanks_count_value) > 0 THEN
        solution_rate_calc := (solved_complaints_count + thanks_count_value)::DECIMAL / 
                              (total_complaints_count + thanks_count_value)::DECIMAL * 100;
    ELSE
        solution_rate_calc := 0;
    END IF;

    UPDATE districts
    SET solution_rate = solution_rate_calc::TEXT
    WHERE name = district_name;

    SELECT d.city_id INTO city_id_var
    FROM districts d
    WHERE d.name = district_name
    LIMIT 1;

    IF city_id_var IS NOT NULL THEN
        SELECT 
            SUM(CASE WHEN d.total_complaints ~ '^[0-9]+$' THEN d.total_complaints::INT ELSE 0 END),
            SUM(CASE WHEN d.solved_complaints ~ '^[0-9]+$' THEN d.solved_complaints::INT ELSE 0 END),
            SUM(CASE WHEN d.thanks_count ~ '^[0-9]+$' THEN d.thanks_count::INT ELSE 0 END)
        INTO 
            total_complaints_count, solved_complaints_count, thanks_count_value
        FROM districts d
        WHERE d.city_id = city_id_var;

        IF (total_complaints_count + thanks_count_value) > 0 THEN
            solution_rate_calc := (solved_complaints_count + thanks_count_value)::DECIMAL / 
                                  (total_complaints_count + thanks_count_value)::DECIMAL * 100;
        ELSE
            solution_rate_calc := 0;
        END IF;

        UPDATE cities
        SET 
            total_complaints = total_complaints_count::TEXT,
            solved_complaints = solved_complaints_count::TEXT,
            thanks_count = thanks_count_value::TEXT,
            solution_rate = solution_rate_calc::TEXT
        WHERE id = city_id_var;

        PERFORM party_stats_calculate_scores();
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$_$;


ALTER FUNCTION public.update_stats_on_post_changes() OWNER TO supabase_admin;

--
-- Name: ad_interactions; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.ad_interactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ad_id uuid,
    user_id uuid,
    interaction_type character varying(20) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ad_interactions_interaction_type_check CHECK (((interaction_type)::text = ANY (ARRAY[('impression'::character varying)::text, ('click'::character varying)::text])))
);


ALTER TABLE public.ad_interactions OWNER TO supabase_admin;

--
-- Name: admin_logs; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.admin_logs (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    admin_id uuid NOT NULL,
    admin_username character varying(255) NOT NULL,
    action_type character varying(50) NOT NULL,
    target_type character varying(50) NOT NULL,
    target_id character varying(36) NOT NULL,
    details jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.admin_logs OWNER TO supabase_admin;

--
-- Name: badge_view_history; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.badge_view_history (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    badge_id integer NOT NULL,
    viewed_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.badge_view_history OWNER TO supabase_admin;

--
-- Name: badge_view_history_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

CREATE SEQUENCE public.badge_view_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.badge_view_history_id_seq OWNER TO supabase_admin;

--
-- Name: badge_view_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: supabase_admin
--

ALTER SEQUENCE public.badge_view_history_id_seq OWNED BY public.badge_view_history.id;


--
-- Name: badges; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.badges (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    description text NOT NULL,
    category character varying(50) NOT NULL,
    icon_url text NOT NULL,
    required_count integer NOT NULL,
    level integer NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.badges OWNER TO supabase_admin;

--
-- Name: badges_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

CREATE SEQUENCE public.badges_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.badges_id_seq OWNER TO supabase_admin;

--
-- Name: badges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: supabase_admin
--

ALTER SEQUENCE public.badges_id_seq OWNED BY public.badges.id;


--
-- Name: cities; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.cities (
    id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    website character varying,
    phone character varying,
    email character varying,
    address text,
    logo_url text,
    cover_image_url text,
    mayor_name text,
    mayor_party text,
    party_logo_url text,
    population integer,
    social_media_links text,
    updated_at timestamp with time zone,
    type character varying,
    political_party_id uuid,
    cozumorani text,
    total_complaints integer DEFAULT 0,
    solved_complaints integer DEFAULT 0,
    thanks_count integer DEFAULT 0,
    solution_rate numeric(5,2) DEFAULT 0,
    solution_last_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_metropolitan boolean DEFAULT false,
    CONSTRAINT cities_type_check CHECK (((type)::text = ANY (ARRAY[('il'::character varying)::text, ('il'::character varying)::text])))
);


ALTER TABLE public.cities OWNER TO supabase_admin;

--
-- Name: districts; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.districts (
    id uuid NOT NULL,
    city_id uuid,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    website character varying(255),
    phone character varying(20),
    email character varying(255),
    address text,
    logo_url text,
    cover_image_url text,
    mayor_name character varying(255),
    mayor_party character varying(100),
    party_logo_url text,
    population integer,
    social_media_links text[],
    type character varying,
    political_party_id uuid,
    cozumorani text,
    total_complaints integer DEFAULT 0,
    solved_complaints integer DEFAULT 0,
    thanks_count integer DEFAULT 0,
    solution_rate numeric(5,2) DEFAULT 0,
    solution_last_updated timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT districts_type_check CHECK (((type)::text = ANY (ARRAY[('il'::character varying)::text, ('ilçe'::character varying)::text])))
);


ALTER TABLE public.districts OWNER TO supabase_admin;

--
-- Name: featured_posts; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.featured_posts (
    id integer NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.featured_posts OWNER TO supabase_admin;

--
-- Name: featured_posts_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

CREATE SEQUENCE public.featured_posts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.featured_posts_id_seq OWNER TO supabase_admin;

--
-- Name: featured_posts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: supabase_admin
--

ALTER SEQUENCE public.featured_posts_id_seq OWNED BY public.featured_posts.id;


--
-- Name: likes; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.likes (
    id uuid NOT NULL,
    post_id uuid,
    user_id uuid,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.likes OWNER TO supabase_admin;

--
-- Name: municipalities_zafer; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.municipalities_zafer (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    type character varying(50) NOT NULL,
    parent_id uuid,
    cover_image_url text,
    logo_url text,
    mayor_name character varying(255),
    mayor_party character varying(100),
    party_logo_url text,
    population integer,
    phone character varying(100),
    website character varying(255),
    email character varying(255),
    address text,
    social_media_links text[],
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT municipalities_type_check CHECK (((type)::text = ANY (ARRAY[('il'::character varying)::text, ('ilçe'::character varying)::text])))
);


ALTER TABLE public.municipalities_zafer OWNER TO supabase_admin;

--
-- Name: municipality_announcements; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.municipality_announcements (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    municipality_id uuid NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    image_url text,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.municipality_announcements OWNER TO supabase_admin;

--
-- Name: notification_preferences; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.notification_preferences (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    likes_enabled boolean DEFAULT true NOT NULL,
    comments_enabled boolean DEFAULT true NOT NULL,
    replies_enabled boolean DEFAULT true NOT NULL,
    mentions_enabled boolean DEFAULT true NOT NULL,
    system_notifications_enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.notification_preferences OWNER TO supabase_admin;

--
-- Name: notifications; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.notifications (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    title text NOT NULL,
    content text NOT NULL,
    type text NOT NULL,
    is_read boolean DEFAULT false NOT NULL,
    sender_id uuid,
    sender_name text,
    sender_profile_url text,
    related_entity_id text,
    related_entity_type text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['like'::text, 'comment'::text, 'reply'::text, 'mention'::text, 'system'::text])))
);


ALTER TABLE public.notifications OWNER TO supabase_admin;

--
-- Name: officials; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.officials (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    city_id uuid,
    district_id uuid,
    title character varying(255),
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.officials OWNER TO supabase_admin;

--
-- Name: officials_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

CREATE SEQUENCE public.officials_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.officials_id_seq OWNER TO supabase_admin;

--
-- Name: officials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: supabase_admin
--

ALTER SEQUENCE public.officials_id_seq OWNED BY public.officials.id;


--
-- Name: political_parties; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.political_parties (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    name text NOT NULL,
    logo_url text,
    score numeric(4,1),
    last_updated timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    parti_sikayet_sayisi integer DEFAULT 0,
    parti_cozulmus_sikayet_sayisi integer DEFAULT 0,
    parti_tesekkur_sayisi integer DEFAULT 0
);


ALTER TABLE public.political_parties OWNER TO supabase_admin;

--
-- Name: poll_options; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.poll_options (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    poll_id uuid,
    option_text text NOT NULL,
    color text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.poll_options OWNER TO supabase_admin;

--
-- Name: poll_votes; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.poll_votes (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    poll_id uuid,
    option_id uuid,
    user_id uuid,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.poll_votes OWNER TO supabase_admin;

--
-- Name: polls; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.polls (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    title text NOT NULL,
    description text,
    start_date timestamp with time zone DEFAULT now(),
    end_date timestamp with time zone,
    created_by uuid,
    is_active boolean DEFAULT true,
    level text NOT NULL,
    city_id uuid,
    district_id uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT polls_level_check CHECK ((level = ANY (ARRAY['country'::text, 'city'::text, 'district'::text])))
);


ALTER TABLE public.polls OWNER TO supabase_admin;

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.profiles (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    username text NOT NULL,
    email text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.profiles OWNER TO supabase_admin;

--
-- Name: resolution_votes; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.resolution_votes (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.resolution_votes OWNER TO supabase_admin;

--
-- Name: sponsored_ads; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.sponsored_ads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title character varying(255) NOT NULL,
    content text NOT NULL,
    image_urls text[] DEFAULT '{}'::text[],
    start_date timestamp with time zone NOT NULL,
    end_date timestamp with time zone NOT NULL,
    link_type character varying(50) NOT NULL,
    link_url character varying(255),
    phone_number character varying(50),
    show_after_posts integer DEFAULT 5,
    is_pinned boolean DEFAULT false,
    city character varying,
    district character varying,
    city_id uuid,
    district_id uuid,
    impressions integer DEFAULT 0,
    clicks integer DEFAULT 0,
    status character varying DEFAULT 'active'::character varying,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    ad_display_scope text DEFAULT 'herkes'::text,
    CONSTRAINT ad_display_scope_check CHECK ((ad_display_scope = ANY (ARRAY['il'::text, 'ilce'::text, 'ililce'::text, 'herkes'::text]))),
    CONSTRAINT sponsored_ads_link_type_check1 CHECK (((link_type)::text = ANY (ARRAY[('url'::character varying)::text, ('phone'::character varying)::text])))
);


ALTER TABLE public.sponsored_ads OWNER TO supabase_admin;

--
-- Name: trigger_logs; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.trigger_logs (
    id integer NOT NULL,
    trigger_name text,
    log_message text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.trigger_logs OWNER TO supabase_admin;

--
-- Name: trigger_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

CREATE SEQUENCE public.trigger_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.trigger_logs_id_seq OWNER TO supabase_admin;

--
-- Name: trigger_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: supabase_admin
--

ALTER SEQUENCE public.trigger_logs_id_seq OWNED BY public.trigger_logs.id;


--
-- Name: user_badges; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.user_badges (
    id integer NOT NULL,
    user_id uuid NOT NULL,
    badge_id integer NOT NULL,
    current_count integer DEFAULT 0 NOT NULL,
    earned_at timestamp with time zone
);


ALTER TABLE public.user_badges OWNER TO supabase_admin;

--
-- Name: user_badges_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

CREATE SEQUENCE public.user_badges_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_badges_id_seq OWNER TO supabase_admin;

--
-- Name: user_badges_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: supabase_admin
--

ALTER SEQUENCE public.user_badges_id_seq OWNED BY public.user_badges.id;


--
-- Name: user_badges_view; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.user_badges_view AS
 SELECT ub.id,
    ub.user_id,
    ub.badge_id,
    ub.current_count,
    ub.earned_at,
    b.name AS badge_name,
    b.description AS badge_description,
    b.category,
    b.icon_url,
    b.required_count,
    b.level
   FROM (public.user_badges ub
     JOIN public.badges b ON ((ub.badge_id = b.id)));


ALTER TABLE public.user_badges_view OWNER TO supabase_admin;

--
-- Name: user_bans; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.user_bans (
    id uuid DEFAULT extensions.uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    banned_by uuid NOT NULL,
    reason text,
    ban_start timestamp with time zone DEFAULT now() NOT NULL,
    ban_end timestamp with time zone NOT NULL,
    content_action character varying(20) DEFAULT 'none'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_bans OWNER TO supabase_admin;

--
-- Name: user_devices; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.user_devices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    device_token text NOT NULL,
    platform text,
    last_active timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.user_devices OWNER TO supabase_admin;

--
-- Name: user_metadata; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.user_metadata (
    user_id uuid NOT NULL,
    is_super_admin boolean DEFAULT false
);


ALTER TABLE public.user_metadata OWNER TO supabase_admin;

--
-- Name: users; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    email text NOT NULL,
    username text NOT NULL,
    profile_image_url text,
    city text NOT NULL,
    district text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    phone_number numeric,
    role character varying(20) DEFAULT 'user'::character varying,
    city_id uuid,
    district_id uuid,
    display_name text
);


ALTER TABLE public.users OWNER TO supabase_admin;

--
-- Name: badge_view_history id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badge_view_history ALTER COLUMN id SET DEFAULT nextval('public.badge_view_history_id_seq'::regclass);


--
-- Name: badges id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badges ALTER COLUMN id SET DEFAULT nextval('public.badges_id_seq'::regclass);


--
-- Name: featured_posts id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.featured_posts ALTER COLUMN id SET DEFAULT nextval('public.featured_posts_id_seq'::regclass);


--
-- Name: officials id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.officials ALTER COLUMN id SET DEFAULT nextval('public.officials_id_seq'::regclass);


--
-- Name: trigger_logs id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.trigger_logs ALTER COLUMN id SET DEFAULT nextval('public.trigger_logs_id_seq'::regclass);


--
-- Name: user_badges id; Type: DEFAULT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_badges ALTER COLUMN id SET DEFAULT nextval('public.user_badges_id_seq'::regclass);


--
-- Name: ad_interactions ad_interactions_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.ad_interactions
    ADD CONSTRAINT ad_interactions_pkey PRIMARY KEY (id);


--
-- Name: admin_logs admin_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.admin_logs
    ADD CONSTRAINT admin_logs_pkey PRIMARY KEY (id);


--
-- Name: badge_view_history badge_view_history_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badge_view_history
    ADD CONSTRAINT badge_view_history_pkey PRIMARY KEY (id);


--
-- Name: badges badges_category_level_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT badges_category_level_key UNIQUE (category, level);


--
-- Name: badges badges_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT badges_pkey PRIMARY KEY (id);


--
-- Name: cities cities_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: districts districts_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_pkey PRIMARY KEY (id);


--
-- Name: featured_posts featured_posts_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.featured_posts
    ADD CONSTRAINT featured_posts_pkey PRIMARY KEY (id);


--
-- Name: featured_posts featured_posts_post_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.featured_posts
    ADD CONSTRAINT featured_posts_post_id_user_id_key UNIQUE (post_id, user_id);


--
-- Name: likes likes_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_pkey PRIMARY KEY (id);


--
-- Name: likes likes_post_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_post_id_user_id_key UNIQUE (post_id, user_id);


--
-- Name: municipalities_zafer municipalities_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.municipalities_zafer
    ADD CONSTRAINT municipalities_pkey PRIMARY KEY (id);


--
-- Name: municipality_announcements municipality_announcements_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.municipality_announcements
    ADD CONSTRAINT municipality_announcements_pkey PRIMARY KEY (id);


--
-- Name: notification_preferences notification_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.notification_preferences
    ADD CONSTRAINT notification_preferences_pkey PRIMARY KEY (id);


--
-- Name: notification_preferences notification_preferences_user_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.notification_preferences
    ADD CONSTRAINT notification_preferences_user_id_key UNIQUE (user_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: officials officials_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.officials
    ADD CONSTRAINT officials_pkey PRIMARY KEY (id);


--
-- Name: political_parties political_parties_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.political_parties
    ADD CONSTRAINT political_parties_pkey PRIMARY KEY (id);


--
-- Name: poll_options poll_options_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_options
    ADD CONSTRAINT poll_options_pkey PRIMARY KEY (id);


--
-- Name: poll_votes poll_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_votes
    ADD CONSTRAINT poll_votes_pkey PRIMARY KEY (id);


--
-- Name: poll_votes poll_votes_poll_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_votes
    ADD CONSTRAINT poll_votes_poll_id_user_id_key UNIQUE (poll_id, user_id);


--
-- Name: polls polls_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.polls
    ADD CONSTRAINT polls_pkey PRIMARY KEY (id);


--
-- Name: posts posts_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_email_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_email_key UNIQUE (email);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: resolution_votes resolution_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.resolution_votes
    ADD CONSTRAINT resolution_votes_pkey PRIMARY KEY (id);


--
-- Name: resolution_votes resolution_votes_post_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.resolution_votes
    ADD CONSTRAINT resolution_votes_post_id_user_id_key UNIQUE (post_id, user_id);


--
-- Name: sponsored_ads sponsored_ads_pkey1; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sponsored_ads
    ADD CONSTRAINT sponsored_ads_pkey1 PRIMARY KEY (id);


--
-- Name: trigger_logs trigger_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.trigger_logs
    ADD CONSTRAINT trigger_logs_pkey PRIMARY KEY (id);


--
-- Name: user_badges user_badges_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_badges
    ADD CONSTRAINT user_badges_pkey PRIMARY KEY (id);


--
-- Name: user_badges user_badges_user_id_badge_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_badges
    ADD CONSTRAINT user_badges_user_id_badge_id_key UNIQUE (user_id, badge_id);


--
-- Name: user_bans user_bans_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_pkey PRIMARY KEY (id);


--
-- Name: user_devices user_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_pkey PRIMARY KEY (id);


--
-- Name: user_devices user_devices_user_id_device_token_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_user_id_device_token_key UNIQUE (user_id, device_token);


--
-- Name: user_metadata user_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_metadata
    ADD CONSTRAINT user_metadata_pkey PRIMARY KEY (user_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_phone_number_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_number_key UNIQUE (phone_number);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: admin_logs_admin_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX admin_logs_admin_id_idx ON public.admin_logs USING btree (admin_id);


--
-- Name: admin_logs_created_at_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX admin_logs_created_at_idx ON public.admin_logs USING btree (created_at);


--
-- Name: admin_logs_target_type_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX admin_logs_target_type_idx ON public.admin_logs USING btree (target_type);


--
-- Name: featured_posts_post_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX featured_posts_post_id_idx ON public.featured_posts USING btree (post_id);


--
-- Name: featured_posts_user_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX featured_posts_user_id_idx ON public.featured_posts USING btree (user_id);


--
-- Name: idx_notification_preferences_user_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_notification_preferences_user_id ON public.notification_preferences USING btree (user_id);


--
-- Name: idx_notifications_created_at; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_notifications_created_at ON public.notifications USING btree (created_at);


--
-- Name: idx_notifications_is_read; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_notifications_is_read ON public.notifications USING btree (is_read);


--
-- Name: idx_notifications_user_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_notifications_user_id ON public.notifications USING btree (user_id);


--
-- Name: idx_officials_city_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_officials_city_id ON public.officials USING btree (city_id);


--
-- Name: idx_officials_district_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_officials_district_id ON public.officials USING btree (district_id);


--
-- Name: idx_officials_user_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_officials_user_id ON public.officials USING btree (user_id);


--
-- Name: idx_posts_category; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_posts_category ON public.posts USING btree (category);


--
-- Name: idx_posts_city_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_posts_city_id ON public.posts USING btree (city_id);


--
-- Name: idx_posts_district_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_posts_district_id ON public.posts USING btree (district_id);


--
-- Name: idx_posts_status; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_posts_status ON public.posts USING btree (status);


--
-- Name: idx_resolution_votes_post_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_resolution_votes_post_id ON public.resolution_votes USING btree (post_id);


--
-- Name: idx_resolution_votes_user_id; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX idx_resolution_votes_user_id ON public.resolution_votes USING btree (user_id);


--
-- Name: user_bans_banned_by_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX user_bans_banned_by_idx ON public.user_bans USING btree (banned_by);


--
-- Name: user_bans_is_active_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX user_bans_is_active_idx ON public.user_bans USING btree (is_active);


--
-- Name: user_bans_user_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX user_bans_user_id_idx ON public.user_bans USING btree (user_id);


--
-- Name: ad_interactions ad_interaction_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER ad_interaction_trigger AFTER INSERT ON public.ad_interactions FOR EACH ROW EXECUTE FUNCTION public.update_ad_stats();


--
-- Name: comments after_comment_delete; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER after_comment_delete AFTER DELETE ON public.comments FOR EACH ROW EXECUTE FUNCTION public.comment_delete_trigger();


--
-- Name: comments after_comment_insert; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER after_comment_insert AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.comment_insert_trigger();


--
-- Name: featured_posts after_featured_post_delete; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER after_featured_post_delete AFTER DELETE ON public.featured_posts FOR EACH ROW EXECUTE FUNCTION public.featured_post_delete_trigger();


--
-- Name: featured_posts after_featured_post_insert; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER after_featured_post_insert AFTER INSERT ON public.featured_posts FOR EACH ROW EXECUTE FUNCTION public.featured_post_insert_trigger();


--
-- Name: posts party_stats_post_delete_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER party_stats_post_delete_trigger AFTER DELETE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.party_stats_post_delete_trigger();

ALTER TABLE public.posts DISABLE TRIGGER party_stats_post_delete_trigger;


--
-- Name: posts party_stats_post_insert_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER party_stats_post_insert_trigger AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION public.party_stats_post_insert_trigger();

ALTER TABLE public.posts DISABLE TRIGGER party_stats_post_insert_trigger;


--
-- Name: posts party_stats_post_update_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER party_stats_post_update_trigger AFTER UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.party_stats_post_update_trigger();

ALTER TABLE public.posts DISABLE TRIGGER party_stats_post_update_trigger;


--
-- Name: cities set_cities_updated_at; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER set_cities_updated_at BEFORE UPDATE ON public.cities FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.cities DISABLE TRIGGER set_cities_updated_at;


--
-- Name: districts set_districts_updated_at; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER set_districts_updated_at BEFORE UPDATE ON public.districts FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

ALTER TABLE public.districts DISABLE TRIGGER set_districts_updated_at;


--
-- Name: municipalities_zafer set_municipalities_updated_at; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER set_municipalities_updated_at BEFORE UPDATE ON public.municipalities_zafer FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


--
-- Name: districts update_city_scores_on_district_change; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_city_scores_on_district_change AFTER UPDATE OF total_complaints, solved_complaints, thanks_count, solution_rate ON public.districts FOR EACH ROW EXECUTE FUNCTION public.update_city_scores_trigger();

ALTER TABLE public.districts DISABLE TRIGGER update_city_scores_on_district_change;


--
-- Name: comments update_comment_badges_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_comment_badges_trigger AFTER INSERT ON public.comments FOR EACH ROW EXECUTE FUNCTION public.update_comment_badges();


--
-- Name: likes update_like_badges_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_like_badges_trigger AFTER INSERT ON public.likes FOR EACH ROW EXECUTE FUNCTION public.update_like_badges();


--
-- Name: posts update_post_badges_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_post_badges_trigger AFTER INSERT ON public.posts FOR EACH ROW EXECUTE FUNCTION public.update_post_badges();

ALTER TABLE public.posts DISABLE TRIGGER update_post_badges_trigger;


--
-- Name: posts update_resolution_badges_status_trigger; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER update_resolution_badges_status_trigger AFTER UPDATE OF status ON public.posts FOR EACH ROW EXECUTE FUNCTION public.update_resolution_badges_status();

ALTER TABLE public.posts DISABLE TRIGGER update_resolution_badges_status_trigger;


--
-- Name: ad_interactions ad_interactions_ad_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.ad_interactions
    ADD CONSTRAINT ad_interactions_ad_id_fkey FOREIGN KEY (ad_id) REFERENCES public.sponsored_ads(id);


--
-- Name: ad_interactions ad_interactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.ad_interactions
    ADD CONSTRAINT ad_interactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);


--
-- Name: admin_logs admin_logs_admin_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.admin_logs
    ADD CONSTRAINT admin_logs_admin_id_fkey FOREIGN KEY (admin_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: badge_view_history badge_view_history_badge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badge_view_history
    ADD CONSTRAINT badge_view_history_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES public.badges(id) ON DELETE CASCADE;


--
-- Name: badge_view_history badge_view_history_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.badge_view_history
    ADD CONSTRAINT badge_view_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: cities cities_political_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.cities
    ADD CONSTRAINT cities_political_party_id_fkey FOREIGN KEY (political_party_id) REFERENCES public.political_parties(id);


--
-- Name: comments comments_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: comments comments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: districts districts_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id) ON DELETE CASCADE;


--
-- Name: districts districts_political_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_political_party_id_fkey FOREIGN KEY (political_party_id) REFERENCES public.political_parties(id);


--
-- Name: featured_posts featured_posts_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.featured_posts
    ADD CONSTRAINT featured_posts_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: featured_posts featured_posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.featured_posts
    ADD CONSTRAINT featured_posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: likes likes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: likes likes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.likes
    ADD CONSTRAINT likes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: municipalities_zafer municipalities_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.municipalities_zafer
    ADD CONSTRAINT municipalities_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.municipalities_zafer(id);


--
-- Name: municipality_announcements municipality_announcements_municipality_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.municipality_announcements
    ADD CONSTRAINT municipality_announcements_municipality_id_fkey FOREIGN KEY (municipality_id) REFERENCES public.municipalities_zafer(id);


--
-- Name: notification_preferences notification_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.notification_preferences
    ADD CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_sender_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: officials officials_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.officials
    ADD CONSTRAINT officials_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id) ON DELETE CASCADE;


--
-- Name: officials officials_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.officials
    ADD CONSTRAINT officials_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.districts(id) ON DELETE SET NULL;


--
-- Name: officials officials_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.officials
    ADD CONSTRAINT officials_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: poll_options poll_options_poll_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_options
    ADD CONSTRAINT poll_options_poll_id_fkey FOREIGN KEY (poll_id) REFERENCES public.polls(id) ON DELETE CASCADE;


--
-- Name: poll_votes poll_votes_option_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_votes
    ADD CONSTRAINT poll_votes_option_id_fkey FOREIGN KEY (option_id) REFERENCES public.poll_options(id) ON DELETE CASCADE;


--
-- Name: poll_votes poll_votes_poll_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_votes
    ADD CONSTRAINT poll_votes_poll_id_fkey FOREIGN KEY (poll_id) REFERENCES public.polls(id) ON DELETE CASCADE;


--
-- Name: poll_votes poll_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.poll_votes
    ADD CONSTRAINT poll_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id);


--
-- Name: polls polls_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.polls
    ADD CONSTRAINT polls_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id);


--
-- Name: polls polls_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.polls
    ADD CONSTRAINT polls_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id);


--
-- Name: polls polls_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.polls
    ADD CONSTRAINT polls_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.districts(id);


--
-- Name: posts posts_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id) ON DELETE SET NULL;


--
-- Name: posts posts_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.districts(id) ON DELETE SET NULL;


--
-- Name: posts posts_processing_official_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_processing_official_id_fkey FOREIGN KEY (processing_official_id) REFERENCES public.officials(id) ON DELETE SET NULL;


--
-- Name: posts posts_rejection_official_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_rejection_official_id_fkey FOREIGN KEY (rejection_official_id) REFERENCES public.officials(id) ON DELETE SET NULL;


--
-- Name: posts posts_solution_official_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_solution_official_id_fkey FOREIGN KEY (solution_official_id) REFERENCES public.officials(id) ON DELETE SET NULL;


--
-- Name: posts posts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.posts
    ADD CONSTRAINT posts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: resolution_votes resolution_votes_post_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.resolution_votes
    ADD CONSTRAINT resolution_votes_post_id_fkey FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE;


--
-- Name: resolution_votes resolution_votes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.resolution_votes
    ADD CONSTRAINT resolution_votes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: sponsored_ads sponsored_ads_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sponsored_ads
    ADD CONSTRAINT sponsored_ads_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id) ON DELETE SET NULL;


--
-- Name: sponsored_ads sponsored_ads_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.sponsored_ads
    ADD CONSTRAINT sponsored_ads_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.districts(id) ON DELETE SET NULL;


--
-- Name: user_badges user_badges_badge_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_badges
    ADD CONSTRAINT user_badges_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES public.badges(id) ON DELETE CASCADE;


--
-- Name: user_badges user_badges_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_badges
    ADD CONSTRAINT user_badges_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_bans user_bans_banned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_banned_by_fkey FOREIGN KEY (banned_by) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_bans user_bans_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_bans
    ADD CONSTRAINT user_bans_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_metadata user_metadata_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.user_metadata
    ADD CONSTRAINT user_metadata_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: users users_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.cities(id);


--
-- Name: users users_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.districts(id);


--
-- Name: admin_logs Admin kullanıcıları log oluşturabilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Admin kullanıcıları log oluşturabilir" ON public.admin_logs FOR INSERT WITH CHECK (((( SELECT users.role
   FROM public.users
  WHERE (users.id = auth.uid())))::text = 'admin'::text));


--
-- Name: user_bans Admin kullanıcıları tüm ban kayıtlarını görebilir ve y; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Admin kullanıcıları tüm ban kayıtlarını görebilir ve y" ON public.user_bans USING (((( SELECT users.role
   FROM public.users
  WHERE (users.id = auth.uid())))::text = 'admin'::text));


--
-- Name: admin_logs Admin kullanıcıları tüm logları görebilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Admin kullanıcıları tüm logları görebilir" ON public.admin_logs FOR SELECT USING (((( SELECT users.role
   FROM public.users
  WHERE (users.id = auth.uid())))::text = 'admin'::text));


--
-- Name: cities Allow updates on cities; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Allow updates on cities" ON public.cities FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: districts Allow updates on districts; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Allow updates on districts" ON public.districts FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: political_parties Allow updates on political_parties; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Allow updates on political_parties" ON public.political_parties FOR UPDATE TO authenticated USING (true) WITH CHECK (true);


--
-- Name: cities Cities are editable by authenticated users; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Cities are editable by authenticated users" ON public.cities FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: cities Cities are insertable by authenticated users; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Cities are insertable by authenticated users" ON public.cities FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: cities Cities are viewable by everyone; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Cities are viewable by everyone" ON public.cities FOR SELECT USING (true);


--
-- Name: districts Districts are editable by authenticated users; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Districts are editable by authenticated users" ON public.districts FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: districts Districts are insertable by authenticated users; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Districts are insertable by authenticated users" ON public.districts FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: districts Districts are viewable by everyone; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Districts are viewable by everyone" ON public.districts FOR SELECT USING (true);


--
-- Name: featured_posts Giriş yapmış kullanıcılar gönderi öne çıkarabilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Giriş yapmış kullanıcılar gönderi öne çıkarabilir" ON public.featured_posts FOR INSERT TO authenticated WITH CHECK (true);


--
-- Name: ad_interactions Herkes etkileşim ekleyebilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Herkes etkileşim ekleyebilir" ON public.ad_interactions FOR INSERT WITH CHECK (true);


--
-- Name: ad_interactions Herkes etkileşimleri görebilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Herkes etkileşimleri görebilir" ON public.ad_interactions FOR SELECT USING (true);


--
-- Name: sponsored_ads Herkes reklamları görebilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Herkes reklamları görebilir" ON public.sponsored_ads FOR SELECT USING (true);


--
-- Name: featured_posts Herkes öne çıkarılan gönderileri görüntüleyebilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Herkes öne çıkarılan gönderileri görüntüleyebilir" ON public.featured_posts FOR SELECT USING (true);


--
-- Name: user_bans Kullanıcılar kendi ban kayıtlarını görebilir; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Kullanıcılar kendi ban kayıtlarını görebilir" ON public.user_bans FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: featured_posts Kullanıcılar kendi öne çıkardıkları gönderileri kaldır; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Kullanıcılar kendi öne çıkardıkları gönderileri kaldır" ON public.featured_posts FOR DELETE TO authenticated USING ((auth.uid() = user_id));


--
-- Name: municipalities_zafer Municipalities are editable by authenticated users; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Municipalities are editable by authenticated users" ON public.municipalities_zafer FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: municipalities_zafer Municipalities are insertable by authenticated users; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Municipalities are insertable by authenticated users" ON public.municipalities_zafer FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: municipalities_zafer Municipalities are viewable by everyone; Type: POLICY; Schema: public; Owner: supabase_admin
--

CREATE POLICY "Municipalities are viewable by everyone" ON public.municipalities_zafer FOR SELECT USING (true);


--
-- Name: admin_logs; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public.admin_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: featured_posts; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public.featured_posts ENABLE ROW LEVEL SECURITY;

--
-- Name: municipalities_zafer; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public.municipalities_zafer ENABLE ROW LEVEL SECURITY;

--
-- Name: sponsored_ads; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public.sponsored_ads ENABLE ROW LEVEL SECURITY;

--
-- Name: user_bans; Type: ROW SECURITY; Schema: public; Owner: supabase_admin
--

ALTER TABLE public.user_bans ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION basit_tesekkur_gonderisi_sil(post_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.basit_tesekkur_gonderisi_sil(post_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.basit_tesekkur_gonderisi_sil(post_id uuid) TO anon;
GRANT ALL ON FUNCTION public.basit_tesekkur_gonderisi_sil(post_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.basit_tesekkur_gonderisi_sil(post_id uuid) TO service_role;


--
-- Name: FUNCTION calculate_city_scores(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.calculate_city_scores() TO postgres;
GRANT ALL ON FUNCTION public.calculate_city_scores() TO anon;
GRANT ALL ON FUNCTION public.calculate_city_scores() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_city_scores() TO service_role;


--
-- Name: FUNCTION calculate_party_scores(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.calculate_party_scores() TO postgres;
GRANT ALL ON FUNCTION public.calculate_party_scores() TO anon;
GRANT ALL ON FUNCTION public.calculate_party_scores() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_party_scores() TO service_role;


--
-- Name: FUNCTION calculate_party_scores_integer(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.calculate_party_scores_integer() TO postgres;
GRANT ALL ON FUNCTION public.calculate_party_scores_integer() TO anon;
GRANT ALL ON FUNCTION public.calculate_party_scores_integer() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_party_scores_integer() TO service_role;


--
-- Name: FUNCTION calculate_party_scores_simple(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.calculate_party_scores_simple() TO postgres;
GRANT ALL ON FUNCTION public.calculate_party_scores_simple() TO anon;
GRANT ALL ON FUNCTION public.calculate_party_scores_simple() TO authenticated;
GRANT ALL ON FUNCTION public.calculate_party_scores_simple() TO service_role;


--
-- Name: FUNCTION change_post_type(post_id text, district_id uuid, old_type text, new_type text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.change_post_type(post_id text, district_id uuid, old_type text, new_type text) TO postgres;
GRANT ALL ON FUNCTION public.change_post_type(post_id text, district_id uuid, old_type text, new_type text) TO anon;
GRANT ALL ON FUNCTION public.change_post_type(post_id text, district_id uuid, old_type text, new_type text) TO authenticated;
GRANT ALL ON FUNCTION public.change_post_type(post_id text, district_id uuid, old_type text, new_type text) TO service_role;


--
-- Name: FUNCTION cleanup_expired_ad_logs(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.cleanup_expired_ad_logs() TO postgres;
GRANT ALL ON FUNCTION public.cleanup_expired_ad_logs() TO anon;
GRANT ALL ON FUNCTION public.cleanup_expired_ad_logs() TO authenticated;
GRANT ALL ON FUNCTION public.cleanup_expired_ad_logs() TO service_role;


--
-- Name: FUNCTION comment_delete_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.comment_delete_trigger() TO postgres;
GRANT ALL ON FUNCTION public.comment_delete_trigger() TO anon;
GRANT ALL ON FUNCTION public.comment_delete_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.comment_delete_trigger() TO service_role;


--
-- Name: FUNCTION comment_insert_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.comment_insert_trigger() TO postgres;
GRANT ALL ON FUNCTION public.comment_insert_trigger() TO anon;
GRANT ALL ON FUNCTION public.comment_insert_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.comment_insert_trigger() TO service_role;


--
-- Name: FUNCTION create_comment_notification(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.create_comment_notification() TO postgres;
GRANT ALL ON FUNCTION public.create_comment_notification() TO anon;
GRANT ALL ON FUNCTION public.create_comment_notification() TO authenticated;
GRANT ALL ON FUNCTION public.create_comment_notification() TO service_role;


--
-- Name: FUNCTION create_default_notification_preferences(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.create_default_notification_preferences() TO postgres;
GRANT ALL ON FUNCTION public.create_default_notification_preferences() TO anon;
GRANT ALL ON FUNCTION public.create_default_notification_preferences() TO authenticated;
GRANT ALL ON FUNCTION public.create_default_notification_preferences() TO service_role;


--
-- Name: FUNCTION create_notification_preferences_safe(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.create_notification_preferences_safe() TO postgres;
GRANT ALL ON FUNCTION public.create_notification_preferences_safe() TO anon;
GRANT ALL ON FUNCTION public.create_notification_preferences_safe() TO authenticated;
GRANT ALL ON FUNCTION public.create_notification_preferences_safe() TO service_role;


--
-- Name: FUNCTION cron_update_party_scores(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.cron_update_party_scores() TO postgres;
GRANT ALL ON FUNCTION public.cron_update_party_scores() TO anon;
GRANT ALL ON FUNCTION public.cron_update_party_scores() TO authenticated;
GRANT ALL ON FUNCTION public.cron_update_party_scores() TO service_role;


--
-- Name: FUNCTION daily_calculate_party_scores(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.daily_calculate_party_scores() TO postgres;
GRANT ALL ON FUNCTION public.daily_calculate_party_scores() TO anon;
GRANT ALL ON FUNCTION public.daily_calculate_party_scores() TO authenticated;
GRANT ALL ON FUNCTION public.daily_calculate_party_scores() TO service_role;


--
-- Name: FUNCTION decrement_comment_count(post_id_param uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.decrement_comment_count(post_id_param uuid) TO postgres;
GRANT ALL ON FUNCTION public.decrement_comment_count(post_id_param uuid) TO anon;
GRANT ALL ON FUNCTION public.decrement_comment_count(post_id_param uuid) TO authenticated;
GRANT ALL ON FUNCTION public.decrement_comment_count(post_id_param uuid) TO service_role;


--
-- Name: FUNCTION decrement_like_count(post_id_param uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.decrement_like_count(post_id_param uuid) TO postgres;
GRANT ALL ON FUNCTION public.decrement_like_count(post_id_param uuid) TO anon;
GRANT ALL ON FUNCTION public.decrement_like_count(post_id_param uuid) TO authenticated;
GRANT ALL ON FUNCTION public.decrement_like_count(post_id_param uuid) TO service_role;


--
-- Name: FUNCTION delete_post(post_id text, district_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.delete_post(post_id text, district_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.delete_post(post_id text, district_id uuid) TO anon;
GRANT ALL ON FUNCTION public.delete_post(post_id text, district_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.delete_post(post_id text, district_id uuid) TO service_role;


--
-- Name: FUNCTION delete_post_fix_thanks(post_id uuid, district_name text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.delete_post_fix_thanks(post_id uuid, district_name text) TO postgres;
GRANT ALL ON FUNCTION public.delete_post_fix_thanks(post_id uuid, district_name text) TO anon;
GRANT ALL ON FUNCTION public.delete_post_fix_thanks(post_id uuid, district_name text) TO authenticated;
GRANT ALL ON FUNCTION public.delete_post_fix_thanks(post_id uuid, district_name text) TO service_role;


--
-- Name: FUNCTION featured_post_delete_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.featured_post_delete_trigger() TO postgres;
GRANT ALL ON FUNCTION public.featured_post_delete_trigger() TO anon;
GRANT ALL ON FUNCTION public.featured_post_delete_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.featured_post_delete_trigger() TO service_role;


--
-- Name: FUNCTION featured_post_insert_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.featured_post_insert_trigger() TO postgres;
GRANT ALL ON FUNCTION public.featured_post_insert_trigger() TO anon;
GRANT ALL ON FUNCTION public.featured_post_insert_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.featured_post_insert_trigger() TO service_role;


--
-- Name: TABLE comments; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.comments TO postgres;
GRANT ALL ON TABLE public.comments TO anon;
GRANT ALL ON TABLE public.comments TO authenticated;
GRANT ALL ON TABLE public.comments TO service_role;


--
-- Name: FUNCTION filter_visible_comments(show_hidden boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.filter_visible_comments(show_hidden boolean) TO postgres;
GRANT ALL ON FUNCTION public.filter_visible_comments(show_hidden boolean) TO anon;
GRANT ALL ON FUNCTION public.filter_visible_comments(show_hidden boolean) TO authenticated;
GRANT ALL ON FUNCTION public.filter_visible_comments(show_hidden boolean) TO service_role;


--
-- Name: TABLE posts; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.posts TO postgres;
GRANT ALL ON TABLE public.posts TO anon;
GRANT ALL ON TABLE public.posts TO authenticated;
GRANT ALL ON TABLE public.posts TO service_role;


--
-- Name: FUNCTION filter_visible_posts(show_hidden boolean); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.filter_visible_posts(show_hidden boolean) TO postgres;
GRANT ALL ON FUNCTION public.filter_visible_posts(show_hidden boolean) TO anon;
GRANT ALL ON FUNCTION public.filter_visible_posts(show_hidden boolean) TO authenticated;
GRANT ALL ON FUNCTION public.filter_visible_posts(show_hidden boolean) TO service_role;


--
-- Name: FUNCTION handle_updated_at(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.handle_updated_at() TO postgres;
GRANT ALL ON FUNCTION public.handle_updated_at() TO anon;
GRANT ALL ON FUNCTION public.handle_updated_at() TO authenticated;
GRANT ALL ON FUNCTION public.handle_updated_at() TO service_role;


--
-- Name: FUNCTION increment_comment_count(post_id_param uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.increment_comment_count(post_id_param uuid) TO postgres;
GRANT ALL ON FUNCTION public.increment_comment_count(post_id_param uuid) TO anon;
GRANT ALL ON FUNCTION public.increment_comment_count(post_id_param uuid) TO authenticated;
GRANT ALL ON FUNCTION public.increment_comment_count(post_id_param uuid) TO service_role;


--
-- Name: FUNCTION increment_like_count(post_id_param uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.increment_like_count(post_id_param uuid) TO postgres;
GRANT ALL ON FUNCTION public.increment_like_count(post_id_param uuid) TO anon;
GRANT ALL ON FUNCTION public.increment_like_count(post_id_param uuid) TO authenticated;
GRANT ALL ON FUNCTION public.increment_like_count(post_id_param uuid) TO service_role;


--
-- Name: FUNCTION is_user_banned(user_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.is_user_banned(user_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.is_user_banned(user_id uuid) TO anon;
GRANT ALL ON FUNCTION public.is_user_banned(user_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.is_user_banned(user_id uuid) TO service_role;


--
-- Name: FUNCTION manual_update_all_stats(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.manual_update_all_stats() TO postgres;
GRANT ALL ON FUNCTION public.manual_update_all_stats() TO anon;
GRANT ALL ON FUNCTION public.manual_update_all_stats() TO authenticated;
GRANT ALL ON FUNCTION public.manual_update_all_stats() TO service_role;


--
-- Name: FUNCTION mark_post_as_solved(post_id text, district_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.mark_post_as_solved(post_id text, district_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.mark_post_as_solved(post_id text, district_id uuid) TO anon;
GRANT ALL ON FUNCTION public.mark_post_as_solved(post_id text, district_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.mark_post_as_solved(post_id text, district_id uuid) TO service_role;


--
-- Name: FUNCTION party_stats_calculate_scores(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_calculate_scores() TO postgres;
GRANT ALL ON FUNCTION public.party_stats_calculate_scores() TO anon;
GRANT ALL ON FUNCTION public.party_stats_calculate_scores() TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_calculate_scores() TO service_role;


--
-- Name: FUNCTION party_stats_post_delete_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_post_delete_trigger() TO postgres;
GRANT ALL ON FUNCTION public.party_stats_post_delete_trigger() TO anon;
GRANT ALL ON FUNCTION public.party_stats_post_delete_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_post_delete_trigger() TO service_role;


--
-- Name: FUNCTION party_stats_post_insert_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_post_insert_trigger() TO postgres;
GRANT ALL ON FUNCTION public.party_stats_post_insert_trigger() TO anon;
GRANT ALL ON FUNCTION public.party_stats_post_insert_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_post_insert_trigger() TO service_role;


--
-- Name: FUNCTION party_stats_post_update_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_post_update_trigger() TO postgres;
GRANT ALL ON FUNCTION public.party_stats_post_update_trigger() TO anon;
GRANT ALL ON FUNCTION public.party_stats_post_update_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_post_update_trigger() TO service_role;


--
-- Name: FUNCTION party_stats_update_all(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_update_all() TO postgres;
GRANT ALL ON FUNCTION public.party_stats_update_all() TO anon;
GRANT ALL ON FUNCTION public.party_stats_update_all() TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_update_all() TO service_role;


--
-- Name: FUNCTION party_stats_update_city(city_id_param integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_update_city(city_id_param integer) TO postgres;
GRANT ALL ON FUNCTION public.party_stats_update_city(city_id_param integer) TO anon;
GRANT ALL ON FUNCTION public.party_stats_update_city(city_id_param integer) TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_update_city(city_id_param integer) TO service_role;


--
-- Name: FUNCTION party_stats_update_city_int(city_id_param integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_update_city_int(city_id_param integer) TO postgres;
GRANT ALL ON FUNCTION public.party_stats_update_city_int(city_id_param integer) TO anon;
GRANT ALL ON FUNCTION public.party_stats_update_city_int(city_id_param integer) TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_update_city_int(city_id_param integer) TO service_role;


--
-- Name: FUNCTION party_stats_update_district(district_id_param integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_update_district(district_id_param integer) TO postgres;
GRANT ALL ON FUNCTION public.party_stats_update_district(district_id_param integer) TO anon;
GRANT ALL ON FUNCTION public.party_stats_update_district(district_id_param integer) TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_update_district(district_id_param integer) TO service_role;


--
-- Name: FUNCTION party_stats_update_district_int(district_id_param integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.party_stats_update_district_int(district_id_param integer) TO postgres;
GRANT ALL ON FUNCTION public.party_stats_update_district_int(district_id_param integer) TO anon;
GRANT ALL ON FUNCTION public.party_stats_update_district_int(district_id_param integer) TO authenticated;
GRANT ALL ON FUNCTION public.party_stats_update_district_int(district_id_param integer) TO service_role;


--
-- Name: FUNCTION unmark_post_as_solved(post_id text, district_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.unmark_post_as_solved(post_id text, district_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.unmark_post_as_solved(post_id text, district_id uuid) TO anon;
GRANT ALL ON FUNCTION public.unmark_post_as_solved(post_id text, district_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.unmark_post_as_solved(post_id text, district_id uuid) TO service_role;


--
-- Name: FUNCTION update_ad_stats(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_ad_stats() TO postgres;
GRANT ALL ON FUNCTION public.update_ad_stats() TO anon;
GRANT ALL ON FUNCTION public.update_ad_stats() TO authenticated;
GRANT ALL ON FUNCTION public.update_ad_stats() TO service_role;


--
-- Name: FUNCTION update_all_monthly_featured_counts(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_all_monthly_featured_counts() TO postgres;
GRANT ALL ON FUNCTION public.update_all_monthly_featured_counts() TO anon;
GRANT ALL ON FUNCTION public.update_all_monthly_featured_counts() TO authenticated;
GRANT ALL ON FUNCTION public.update_all_monthly_featured_counts() TO service_role;


--
-- Name: FUNCTION update_all_statistics(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_all_statistics() TO postgres;
GRANT ALL ON FUNCTION public.update_all_statistics() TO anon;
GRANT ALL ON FUNCTION public.update_all_statistics() TO authenticated;
GRANT ALL ON FUNCTION public.update_all_statistics() TO service_role;


--
-- Name: FUNCTION update_city_scores_trigger(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_city_scores_trigger() TO postgres;
GRANT ALL ON FUNCTION public.update_city_scores_trigger() TO anon;
GRANT ALL ON FUNCTION public.update_city_scores_trigger() TO authenticated;
GRANT ALL ON FUNCTION public.update_city_scores_trigger() TO service_role;


--
-- Name: FUNCTION update_comment_badges(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_comment_badges() TO postgres;
GRANT ALL ON FUNCTION public.update_comment_badges() TO anon;
GRANT ALL ON FUNCTION public.update_comment_badges() TO authenticated;
GRANT ALL ON FUNCTION public.update_comment_badges() TO service_role;


--
-- Name: FUNCTION update_district_statistics(district_name text); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_district_statistics(district_name text) TO postgres;
GRANT ALL ON FUNCTION public.update_district_statistics(district_name text) TO anon;
GRANT ALL ON FUNCTION public.update_district_statistics(district_name text) TO authenticated;
GRANT ALL ON FUNCTION public.update_district_statistics(district_name text) TO service_role;


--
-- Name: FUNCTION update_district_stats(p_district_id uuid, p_total_complaints_change integer, p_solved_complaints_change integer, p_thanks_count_change integer); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_district_stats(p_district_id uuid, p_total_complaints_change integer, p_solved_complaints_change integer, p_thanks_count_change integer) TO postgres;
GRANT ALL ON FUNCTION public.update_district_stats(p_district_id uuid, p_total_complaints_change integer, p_solved_complaints_change integer, p_thanks_count_change integer) TO anon;
GRANT ALL ON FUNCTION public.update_district_stats(p_district_id uuid, p_total_complaints_change integer, p_solved_complaints_change integer, p_thanks_count_change integer) TO authenticated;
GRANT ALL ON FUNCTION public.update_district_stats(p_district_id uuid, p_total_complaints_change integer, p_solved_complaints_change integer, p_thanks_count_change integer) TO service_role;


--
-- Name: FUNCTION update_featured_count(post_id_param uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_featured_count(post_id_param uuid) TO postgres;
GRANT ALL ON FUNCTION public.update_featured_count(post_id_param uuid) TO anon;
GRANT ALL ON FUNCTION public.update_featured_count(post_id_param uuid) TO authenticated;
GRANT ALL ON FUNCTION public.update_featured_count(post_id_param uuid) TO service_role;


--
-- Name: FUNCTION update_like_badges(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_like_badges() TO postgres;
GRANT ALL ON FUNCTION public.update_like_badges() TO anon;
GRANT ALL ON FUNCTION public.update_like_badges() TO authenticated;
GRANT ALL ON FUNCTION public.update_like_badges() TO service_role;


--
-- Name: FUNCTION update_party_score_for_entity(entity_type text, entity_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_party_score_for_entity(entity_type text, entity_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.update_party_score_for_entity(entity_type text, entity_id uuid) TO anon;
GRANT ALL ON FUNCTION public.update_party_score_for_entity(entity_type text, entity_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.update_party_score_for_entity(entity_type text, entity_id uuid) TO service_role;


--
-- Name: FUNCTION update_party_scores(party_id uuid); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_party_scores(party_id uuid) TO postgres;
GRANT ALL ON FUNCTION public.update_party_scores(party_id uuid) TO anon;
GRANT ALL ON FUNCTION public.update_party_scores(party_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.update_party_scores(party_id uuid) TO service_role;


--
-- Name: FUNCTION update_post_badges(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_post_badges() TO postgres;
GRANT ALL ON FUNCTION public.update_post_badges() TO anon;
GRANT ALL ON FUNCTION public.update_post_badges() TO authenticated;
GRANT ALL ON FUNCTION public.update_post_badges() TO service_role;


--
-- Name: FUNCTION update_resolution_badges_status(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_resolution_badges_status() TO postgres;
GRANT ALL ON FUNCTION public.update_resolution_badges_status() TO anon;
GRANT ALL ON FUNCTION public.update_resolution_badges_status() TO authenticated;
GRANT ALL ON FUNCTION public.update_resolution_badges_status() TO service_role;


--
-- Name: FUNCTION update_sponsored_ads_stats(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_sponsored_ads_stats() TO postgres;
GRANT ALL ON FUNCTION public.update_sponsored_ads_stats() TO anon;
GRANT ALL ON FUNCTION public.update_sponsored_ads_stats() TO authenticated;
GRANT ALL ON FUNCTION public.update_sponsored_ads_stats() TO service_role;


--
-- Name: FUNCTION update_stats_on_post_changes(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_stats_on_post_changes() TO postgres;
GRANT ALL ON FUNCTION public.update_stats_on_post_changes() TO anon;
GRANT ALL ON FUNCTION public.update_stats_on_post_changes() TO authenticated;
GRANT ALL ON FUNCTION public.update_stats_on_post_changes() TO service_role;


--
-- Name: TABLE ad_interactions; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.ad_interactions TO postgres;
GRANT ALL ON TABLE public.ad_interactions TO anon;
GRANT ALL ON TABLE public.ad_interactions TO authenticated;
GRANT ALL ON TABLE public.ad_interactions TO service_role;


--
-- Name: TABLE admin_logs; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.admin_logs TO postgres;
GRANT ALL ON TABLE public.admin_logs TO anon;
GRANT ALL ON TABLE public.admin_logs TO authenticated;
GRANT ALL ON TABLE public.admin_logs TO service_role;


--
-- Name: TABLE badge_view_history; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.badge_view_history TO postgres;
GRANT ALL ON TABLE public.badge_view_history TO anon;
GRANT ALL ON TABLE public.badge_view_history TO authenticated;
GRANT ALL ON TABLE public.badge_view_history TO service_role;


--
-- Name: SEQUENCE badge_view_history_id_seq; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public.badge_view_history_id_seq TO postgres;
GRANT ALL ON SEQUENCE public.badge_view_history_id_seq TO anon;
GRANT ALL ON SEQUENCE public.badge_view_history_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.badge_view_history_id_seq TO service_role;


--
-- Name: TABLE badges; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.badges TO postgres;
GRANT ALL ON TABLE public.badges TO anon;
GRANT ALL ON TABLE public.badges TO authenticated;
GRANT ALL ON TABLE public.badges TO service_role;


--
-- Name: SEQUENCE badges_id_seq; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public.badges_id_seq TO postgres;
GRANT ALL ON SEQUENCE public.badges_id_seq TO anon;
GRANT ALL ON SEQUENCE public.badges_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.badges_id_seq TO service_role;


--
-- Name: TABLE cities; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.cities TO postgres;
GRANT ALL ON TABLE public.cities TO anon;
GRANT ALL ON TABLE public.cities TO authenticated;
GRANT ALL ON TABLE public.cities TO service_role;


--
-- Name: TABLE districts; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.districts TO postgres;
GRANT ALL ON TABLE public.districts TO anon;
GRANT ALL ON TABLE public.districts TO authenticated;
GRANT ALL ON TABLE public.districts TO service_role;


--
-- Name: TABLE featured_posts; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.featured_posts TO postgres;
GRANT ALL ON TABLE public.featured_posts TO anon;
GRANT ALL ON TABLE public.featured_posts TO authenticated;
GRANT ALL ON TABLE public.featured_posts TO service_role;


--
-- Name: SEQUENCE featured_posts_id_seq; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public.featured_posts_id_seq TO postgres;
GRANT ALL ON SEQUENCE public.featured_posts_id_seq TO anon;
GRANT ALL ON SEQUENCE public.featured_posts_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.featured_posts_id_seq TO service_role;


--
-- Name: TABLE likes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.likes TO postgres;
GRANT ALL ON TABLE public.likes TO anon;
GRANT ALL ON TABLE public.likes TO authenticated;
GRANT ALL ON TABLE public.likes TO service_role;


--
-- Name: TABLE municipalities_zafer; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.municipalities_zafer TO postgres;
GRANT ALL ON TABLE public.municipalities_zafer TO anon;
GRANT ALL ON TABLE public.municipalities_zafer TO authenticated;
GRANT ALL ON TABLE public.municipalities_zafer TO service_role;


--
-- Name: TABLE municipality_announcements; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.municipality_announcements TO postgres;
GRANT ALL ON TABLE public.municipality_announcements TO anon;
GRANT ALL ON TABLE public.municipality_announcements TO authenticated;
GRANT ALL ON TABLE public.municipality_announcements TO service_role;


--
-- Name: TABLE notification_preferences; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.notification_preferences TO postgres;
GRANT ALL ON TABLE public.notification_preferences TO anon;
GRANT ALL ON TABLE public.notification_preferences TO authenticated;
GRANT ALL ON TABLE public.notification_preferences TO service_role;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.notifications TO postgres;
GRANT ALL ON TABLE public.notifications TO anon;
GRANT ALL ON TABLE public.notifications TO authenticated;
GRANT ALL ON TABLE public.notifications TO service_role;


--
-- Name: TABLE officials; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.officials TO postgres;
GRANT ALL ON TABLE public.officials TO anon;
GRANT ALL ON TABLE public.officials TO authenticated;
GRANT ALL ON TABLE public.officials TO service_role;


--
-- Name: SEQUENCE officials_id_seq; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public.officials_id_seq TO postgres;
GRANT ALL ON SEQUENCE public.officials_id_seq TO anon;
GRANT ALL ON SEQUENCE public.officials_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.officials_id_seq TO service_role;


--
-- Name: TABLE political_parties; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.political_parties TO postgres;
GRANT ALL ON TABLE public.political_parties TO anon;
GRANT ALL ON TABLE public.political_parties TO authenticated;
GRANT ALL ON TABLE public.political_parties TO service_role;


--
-- Name: TABLE poll_options; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.poll_options TO postgres;
GRANT ALL ON TABLE public.poll_options TO anon;
GRANT ALL ON TABLE public.poll_options TO authenticated;
GRANT ALL ON TABLE public.poll_options TO service_role;


--
-- Name: TABLE poll_votes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.poll_votes TO postgres;
GRANT ALL ON TABLE public.poll_votes TO anon;
GRANT ALL ON TABLE public.poll_votes TO authenticated;
GRANT ALL ON TABLE public.poll_votes TO service_role;


--
-- Name: TABLE polls; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.polls TO postgres;
GRANT ALL ON TABLE public.polls TO anon;
GRANT ALL ON TABLE public.polls TO authenticated;
GRANT ALL ON TABLE public.polls TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.profiles TO postgres;
GRANT ALL ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT ALL ON TABLE public.profiles TO service_role;


--
-- Name: TABLE resolution_votes; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.resolution_votes TO postgres;
GRANT ALL ON TABLE public.resolution_votes TO anon;
GRANT ALL ON TABLE public.resolution_votes TO authenticated;
GRANT ALL ON TABLE public.resolution_votes TO service_role;


--
-- Name: TABLE sponsored_ads; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.sponsored_ads TO postgres;
GRANT ALL ON TABLE public.sponsored_ads TO anon;
GRANT ALL ON TABLE public.sponsored_ads TO authenticated;
GRANT ALL ON TABLE public.sponsored_ads TO service_role;


--
-- Name: TABLE trigger_logs; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.trigger_logs TO postgres;
GRANT ALL ON TABLE public.trigger_logs TO anon;
GRANT ALL ON TABLE public.trigger_logs TO authenticated;
GRANT ALL ON TABLE public.trigger_logs TO service_role;


--
-- Name: SEQUENCE trigger_logs_id_seq; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public.trigger_logs_id_seq TO postgres;
GRANT ALL ON SEQUENCE public.trigger_logs_id_seq TO anon;
GRANT ALL ON SEQUENCE public.trigger_logs_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.trigger_logs_id_seq TO service_role;


--
-- Name: TABLE user_badges; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.user_badges TO postgres;
GRANT ALL ON TABLE public.user_badges TO anon;
GRANT ALL ON TABLE public.user_badges TO authenticated;
GRANT ALL ON TABLE public.user_badges TO service_role;


--
-- Name: SEQUENCE user_badges_id_seq; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON SEQUENCE public.user_badges_id_seq TO postgres;
GRANT ALL ON SEQUENCE public.user_badges_id_seq TO anon;
GRANT ALL ON SEQUENCE public.user_badges_id_seq TO authenticated;
GRANT ALL ON SEQUENCE public.user_badges_id_seq TO service_role;


--
-- Name: TABLE user_badges_view; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.user_badges_view TO postgres;
GRANT ALL ON TABLE public.user_badges_view TO anon;
GRANT ALL ON TABLE public.user_badges_view TO authenticated;
GRANT ALL ON TABLE public.user_badges_view TO service_role;


--
-- Name: TABLE user_bans; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.user_bans TO postgres;
GRANT ALL ON TABLE public.user_bans TO anon;
GRANT ALL ON TABLE public.user_bans TO authenticated;
GRANT ALL ON TABLE public.user_bans TO service_role;


--
-- Name: TABLE user_devices; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.user_devices TO postgres;
GRANT ALL ON TABLE public.user_devices TO anon;
GRANT ALL ON TABLE public.user_devices TO authenticated;
GRANT ALL ON TABLE public.user_devices TO service_role;


--
-- Name: TABLE user_metadata; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.user_metadata TO postgres;
GRANT ALL ON TABLE public.user_metadata TO anon;
GRANT ALL ON TABLE public.user_metadata TO authenticated;
GRANT ALL ON TABLE public.user_metadata TO service_role;


--
-- Name: TABLE users; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.users TO postgres;
GRANT ALL ON TABLE public.users TO anon;
GRANT ALL ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: supabase_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES  TO service_role;


--
-- PostgreSQL database dump complete
--

