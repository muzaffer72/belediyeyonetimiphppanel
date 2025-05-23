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
-- Data for Name: ad_interactions; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.ad_interactions (id, ad_id, user_id, interaction_type, created_at) FROM stdin;
9ddf6a8b-7e66-4f74-9ad4-0c2c2f95f31e	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 14:20:27.327211+00
c25418e7-3368-4502-a939-6d33eb1bc39a	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 14:20:31.828751+00
db91a15f-ad74-464d-8b6a-cbbb9d99e5c1	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 14:21:08.267952+00
61ff824d-f527-437c-8b40-d78073255b9b	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 14:21:12.667642+00
afc5ef82-ea33-44ac-bb55-f66509df37e8	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 14:21:18.217523+00
87867b25-791b-4e7e-b98c-80c31f8e8b49	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 14:21:53.971825+00
265541a5-0456-4734-bfbf-833a3c2cc71f	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 14:22:00.196799+00
04662242-6146-44f9-8efe-a1954516c7c5	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 14:22:41.91031+00
1b4515b5-8673-4961-aea7-8a920f485861	934bf28f-fe0b-42bc-bc25-a06ede922a31	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 14:22:43.436174+00
facd41e8-304b-47ae-8aa6-ebb59028d814	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:03:34.179327+00
f6ffa5aa-5bae-4e88-bfd3-f067b08a156c	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:04:39.285062+00
0589a07a-77f3-4683-b1c2-f1c4aae379d9	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 15:04:40.816908+00
c64fd91d-7312-4f63-b1fc-56f8c8add75b	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:05:32.731948+00
19ad7821-afdb-4ab5-a3b4-d7c907173dba	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 15:05:44.25014+00
bbc6b502-16a3-4994-887e-eab11e9add24	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:06:45.829615+00
a985ecaf-0b75-4cef-ac1b-182848258c61	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:07:39.53267+00
a0917538-90d3-4ab8-93c1-b8c6882e50ad	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:12:21.037041+00
98227cd0-b4fb-4296-afc5-f4cd410c2304	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:16:34.293149+00
5549da9e-8c7d-45fc-9797-14e2bafec736	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:17:53.820191+00
3ab2929a-2ff9-403c-8739-0e78f446274e	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:18:28.5548+00
00594880-079e-4861-84f6-2a18e7b63dd9	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:18:35.048032+00
2323dc56-307a-41d9-b085-d41bebaaa3cb	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 15:18:51.596712+00
11c2d647-a61c-4488-a020-329ed81f67d4	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 16:21:07.100918+00
6bcfe7f9-9dd0-4029-b36a-58c7d08a7d4e	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 23:25:29.45312+00
5a4e515c-42e2-4927-bae2-c390a2daa9e0	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 23:25:33.496539+00
55c1d469-afa0-463d-83dd-1b231b0c2a95	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 23:25:34.897349+00
f4bb99f4-9d11-4841-954a-55dbab273e4b	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 23:25:50.806141+00
755e3765-cdfc-4697-a7e7-a3e575327d5f	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-22 23:26:00.559347+00
ea556ce5-b4ae-44f0-bca5-3dce2bf4f42b	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-22 23:26:18.911058+00
f2b17bdc-e6fc-4ce6-8885-de2c3630467a	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 05:20:16.520997+00
84b48feb-881d-4e36-8cb2-5e8a9d62c43b	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 05:23:58.789344+00
85287195-c0a5-41fc-8964-924e9d311e94	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 15:08:26.356025+00
ac7c2e58-f450-44e0-acbe-d804787207af	934bf28f-fe0b-42bc-bc25-a06ede922a27	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:08:28.839498+00
7a2d6b65-5246-4bdf-bc06-22464ba32ae6	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 15:08:44.270145+00
22d62803-319a-471f-8c52-a0097d5f67fc	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:28:08.509846+00
1a156f9e-af84-4fe6-925c-2fce090847d3	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:28:08.912743+00
980a30ea-99a2-4324-88e4-1959eb1ade73	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:28:09.667596+00
a7a76674-4ac5-4d52-af41-3f3716488611	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:28:09.684588+00
0ee6800a-c94f-40b7-86e7-f64cb59a7c43	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:28:11.632403+00
f9790c5a-a36d-4976-a5b5-50c14d49de7a	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 15:28:14.13554+00
5f95d04c-9c0d-4e97-90f6-21f82dd4f1d3	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 16:04:07.916114+00
48858b49-8953-497f-9526-a47d09a878ab	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 16:38:54.686436+00
e8de2365-5a8b-48b8-a7c8-6a6fa280a2c4	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 16:38:56.544317+00
b751d2a0-eb43-41cd-bc9b-9a43c07fdfd2	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 16:39:23.396356+00
a3fc501c-360f-4879-ba3e-585f820e1bcf	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 16:39:24.65612+00
4f70afa2-9413-4365-97a1-d478967a1645	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 16:42:35.543346+00
28664d60-8305-4f8c-91c9-ba2e901b5933	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 16:42:40.250076+00
7b61d804-95ba-4a72-a335-c64d0a80e331	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 17:15:23.153793+00
1f466160-9687-4252-b2b3-5bafb088f9c0	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 17:18:49.321222+00
6be3278d-fdf9-44b1-81b7-44e8b4ff845c	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 17:18:54.4916+00
7129392c-5e79-47a8-8495-3bc15b22b43f	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 17:21:10.256092+00
f9902df8-34e4-4cca-b2d4-da4d6f9f1f4c	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 17:22:10.782965+00
47c1e761-af55-48c7-83a3-6cb35b325555	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 17:22:12.882778+00
c50da1f5-d051-4264-9dfc-b210327a7a84	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	impression	2025-05-23 17:35:07.407623+00
ef717a5e-9ecf-4021-8c5c-da6730171567	934bf28f-fe0b-42bc-bc25-a06ede922a29	83190944-98d5-41be-ac3a-178676faf017	click	2025-05-23 17:35:18.256578+00
025e7bec-7800-45e2-8783-887c883e46ea	934bf28f-fe0b-42bc-bc25-a06ede922a29	516b3dcb-aeec-4451-aa13-1894193b0b88	impression	2025-05-23 18:38:06.734409+00
389090a7-bf2d-4363-91c0-8ad466d4d2ae	934bf28f-fe0b-42bc-bc25-a06ede922a29	516b3dcb-aeec-4451-aa13-1894193b0b88	impression	2025-05-23 18:39:09.916481+00
8dbce4e7-4baa-42c5-8273-9887d7072dba	934bf28f-fe0b-42bc-bc25-a06ede922a29	516b3dcb-aeec-4451-aa13-1894193b0b88	click	2025-05-23 18:39:22.447591+00
60d12e2e-4525-47ae-894a-d97cd2baa689	934bf28f-fe0b-42bc-bc25-a06ede922a29	516b3dcb-aeec-4451-aa13-1894193b0b88	impression	2025-05-23 18:48:30.543873+00
86a5df31-e8d5-4e6f-a7dc-46416e4263c9	934bf28f-fe0b-42bc-bc25-a06ede922a29	ebd65a16-8bef-4c21-bcf9-c18dab95947a	impression	2025-05-23 18:53:17.204361+00
5eac47cf-562c-4fea-9c31-15a675ae4039	934bf28f-fe0b-42bc-bc25-a06ede922a29	cdc2d279-8171-4aa5-89cb-10f81fed72c3	impression	2025-05-23 19:03:17.862145+00
04a3758e-7a58-4c56-b16c-a39c3626c400	934bf28f-fe0b-42bc-bc25-a06ede922a29	cdc2d279-8171-4aa5-89cb-10f81fed72c3	impression	2025-05-23 19:04:37.855813+00
5dac59df-29d5-4a9b-91e2-a6148762fabe	934bf28f-fe0b-42bc-bc25-a06ede922a29	cdc2d279-8171-4aa5-89cb-10f81fed72c3	impression	2025-05-23 19:12:05.077854+00
b6eb5dcf-b2e9-44d7-9cff-0032578e21c4	934bf28f-fe0b-42bc-bc25-a06ede922a29	cdc2d279-8171-4aa5-89cb-10f81fed72c3	impression	2025-05-23 19:18:44.554527+00
f9ee2924-437a-42ff-b9d9-c79f13df4789	934bf28f-fe0b-42bc-bc25-a06ede922a29	cdc2d279-8171-4aa5-89cb-10f81fed72c3	click	2025-05-23 19:18:45.180018+00
cf31ca9e-219c-4053-afdc-8757a875328d	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:24:03.221112+00
bab374c3-d7c2-4564-8134-e5dbb81d5e95	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:31:40.194489+00
0bfd98aa-516c-47e0-a27a-1874ab831df3	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:32:38.609737+00
57bc72b3-d0b4-42ba-a890-f92c43eaba1c	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:33:25.067912+00
78dae45b-4727-48bf-afa2-e79e5b127d76	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:43:52.819872+00
14c6c3da-9d0e-499e-a4ed-dc8ce45ea5a3	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:46:16.469754+00
65f7f12b-e413-4dd0-ad0b-9ff73d2ad7da	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:57:40.294867+00
496a2d12-f3f0-40da-86c1-6ab2356dfdce	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 19:59:00.723991+00
47c68042-d128-4ed3-aaca-c7c3ae9002b8	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	click	2025-05-23 20:00:23.617404+00
ab6d9991-005c-471d-b414-46b737b2d103	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 20:09:35.923056+00
d237cff0-a2a1-421b-b9ce-c4cd2af24009	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 20:10:55.087275+00
b6e4142f-ab08-486b-a23a-fe87e02579b9	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 20:17:53.020163+00
d9425c77-76c8-48b1-82ca-23dfe181fdc1	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 20:19:45.676669+00
1576a9ab-f51e-4258-92ac-6190792cf025	934bf28f-fe0b-42bc-bc25-a06ede922a29	8b52a8cb-cb89-4325-9c62-de454a0476fb	impression	2025-05-23 20:27:10.284913+00
\.


--
-- Data for Name: admin_logs; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.admin_logs (id, admin_id, admin_username, action_type, target_type, target_id, details, created_at) FROM stdin;
\.


--
-- Data for Name: badge_view_history; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.badge_view_history (id, user_id, badge_id, viewed_at) FROM stdin;
\.


--
-- Data for Name: badges; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.badges (id, name, description, category, icon_url, required_count, level, created_at) FROM stdin;
15	Sorun Çözücü	İlk sorun çözüldü. Tebrikler, çözümler üretiyorsunuz!	resolutions	/assets/icons/badges/resolution_badge_1.png	1	1	2025-05-20 21:02:41.485844+00
16	Çözüm Uzmanı	5 sorun çözüldü. Şehrinize gerçek katkılar sağlıyorsunuz!	resolutions	/assets/icons/badges/resolution_badge_2.png	5	2	2025-05-20 21:02:41.485844+00
17	Sorun Avcısı	15 sorun çözüldü. Şehrinizi daha yaşanabilir kılıyorsunuz!	resolutions	/assets/icons/badges/resolution_badge_3.png	15	3	2025-05-20 21:02:41.485844+00
18	Dönüşüm Lideri	25 sorun çözüldü. Şehrinizin dönüşümünde öncü rol oynuyorsunuz!	resolutions	/assets/icons/badges/resolution_badge_4.png	25	4	2025-05-20 21:02:41.485844+00
1	Beğeni Çaylağı	İlk beğeniyi aldınız. Halk sizin fikirlerinize değer veriyor!	likes	https://onvao.net/adminpanel/uploads/icons/begeni1.png	1	1	2025-05-20 21:02:41.485844+00
2	Takdir Toplayan	Gönderileriniz 10 beğeni topladı. İnsanlar sizin paylaşımlarınızı takdir ediyor!	likes	https://onvao.net/adminpanel/uploads/icons/begeni2.png	10	2	2025-05-20 21:02:41.485844+00
3	Beğeni Ustası	Gönderileriniz 50 beğeni topladı. Görüşleriniz gerçekten değerli!	likes	https://onvao.net/adminpanel/uploads/icons/begeni3.png	50	3	2025-05-20 21:02:41.485844+00
4	Beğeni Fenomeni	Gönderileriniz 100 beğeni topladı. Harika işler çıkarıyorsunuz!	likes	https://onvao.net/adminpanel/uploads/icons/begeni4.png	100	4	2025-05-20 21:02:41.485844+00
6	İlk Yorum	İlk yorumunuzu aldınız. İnsanlar görüşlerinize yanıt veriyor!	comments	https://onvao.net/adminpanel/uploads/icons/yorum1.png	1	1	2025-05-20 21:02:41.485844+00
5	Beğeni Efsanesi	Gönderileriniz 500 beğeni topladı. Gerçek bir topluluk liderisiniz!	likes	https://onvao.net/adminpanel/uploads/icons/dino.png	500	5	2025-05-20 21:02:41.485844+00
7	Tartışma Başlatıcı	Gönderileriniz 10 yorum aldı. İlgi çekici konular oluşturuyorsunuz!	comments	https://onvao.net/adminpanel/uploads/icons/dino.png	10	2	2025-05-20 21:02:41.485844+00
8	Tartışma Uzmanı	Gönderileriniz 50 yorum aldı. İnsanları konuşturmayı biliyorsunuz!	comments	https://onvao.net/adminpanel/uploads/icons/dino.png	50	3	2025-05-20 21:02:41.485844+00
9	Topluluk Moderatörü	Gönderileriniz 100 yorum aldı. Gerçek bir tartışma liderisiniz!	comments	https://onvao.net/adminpanel/uploads/icons/dino.png	100	4	2025-05-20 21:02:41.485844+00
10	Şehir Sakini	İlk gönderinizi oluşturdunuz. Şehrinizin gelişimine katkı sağlamaya başladınız!	posts	https://onvao.net/adminpanel/uploads/icons/dino.png	1	1	2025-05-20 21:02:41.485844+00
11	Aktif Vatandaş	5 gönderi oluşturdunuz. Şehrinizin sorunlarıyla aktif olarak ilgileniyorsunuz!	posts	https://onvao.net/adminpanel/uploads/icons/dino.png	5	2	2025-05-20 21:02:41.485844+00
12	Mahalle Muhtarı	15 gönderi oluşturdunuz. Mahallenizin sesi olmaya başladınız!	posts	https://onvao.net/adminpanel/uploads/icons/dino.png	15	3	2025-05-20 21:02:41.485844+00
13	Şehir Temsilcisi	30 gönderi oluşturdunuz. Şehrinizin en aktif vatandaşlarından birisiniz!	posts	https://onvao.net/adminpanel/uploads/icons/dino.png	30	4	2025-05-20 21:02:41.485844+00
14	Belediye Başkanı	50 gönderi oluşturdunuz. Şehrinizin gerçek bir liderisiniz!	posts	https://onvao.net/adminpanel/uploads/icons/dino.png	50	5	2025-05-20 21:02:41.485844+00
\.


--
-- Data for Name: cities; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.cities (id, name, created_at, website, phone, email, address, logo_url, cover_image_url, mayor_name, mayor_party, party_logo_url, population, social_media_links, updated_at, type, political_party_id, cozumorani, total_complaints, solved_complaints, thanks_count, solution_rate, solution_last_updated, is_metropolitan) FROM stdin;
550e8400-e29b-41d4-a716-446655440074	Bartın	2025-05-08 22:15:39.978328+00	bartın.bel.tr	+90 000 000 00 00	info@bartın.bel.tr	Bartın Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440069	Bayburt	2025-05-08 22:15:39.978328+00	bayburt.bel.tr	+90 000 000 00 00	info@bayburt.bel.tr	Bayburt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440043	Kütahya	2025-05-08 22:15:39.978328+00	kütahya.bel.tr	+90 000 000 00 00	info@kütahya.bel.tr	Kütahya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440071	Kırıkkale	2025-05-08 22:15:39.978328+00	kırıkkale.bel.tr	+90 000 000 00 00	info@kırıkkale.bel.tr	Kırıkkale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440040	Kırşehir	2025-05-08 22:15:39.978328+00	kırşehir.bel.tr	+90 000 000 00 00	info@kırşehir.bel.tr	Kırşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440050	Nevşehir	2025-05-08 22:15:39.978328+00	nevşehir.bel.tr	+90 000 000 00 00	info@nevşehir.bel.tr	Nevşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440041	Kocaeli	2025-05-08 22:15:39.978328+00	kocaeli.bel.tr	+90 000 000 00 00	info@kocaeli.bel.tr	Kocaeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440059	Tekirdağ	2025-05-08 22:15:39.978328+00	tekirdağ.bel.tr	+90 000 000 00 00	info@tekirdağ.bel.tr	Tekirdağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440004	Ağrı	2025-05-08 22:15:39.978328+00	https://agri.bel.tr	+90 472 215 11 90	info@agri.bel.tr	Fırat Mah. Atalay Cad. No:7, 04100 Merkez/AĞRI	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Hazal Aras	AKP	https://upload-wikimedia-org.translate.goog/wikipedia/en/thumb/5/56/Justice_and_Development_Party_%28Turkey%29_logo.svg/225px-Justice_and_Development_Party_%28Turkey%29_logo.svg.png?_x_tr_sl=en&_x_tr_tl=tr&_x_tr_hl=tr&_x_tr_pto=tc	524644	{"twitter": "https://twitter.com/agri_bld", "facebook": "https://facebook.com/agri.bld", "instagram": "https://instagram.com/agri.bld"}	2025-05-23 06:00:00.073489+00	il	448575ce-7444-4bd7-8070-1753a8ecb16b	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440044	Malatya	2025-05-08 22:15:39.978328+00	malatya.bel.tr	+90 000 000 00 00	info@malatya.bel.tr	Malatya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440077	Yalova	2025-05-08 22:15:39.978328+00	yalova.bel.tr	+90 000 000 00 00	info@yalova.bel.tr	Yalova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440068	Aksaray	2025-05-08 22:15:39.978328+00	aksaray.bel.tr	+90 000 000 00 00	info@aksaray.bel.tr	Aksaray Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440008	Artvin	2025-05-08 22:15:39.978328+00	https://www.artvin.bel.tr	+90 466 212 10 50	info@artvin.bel.tr	Çarşı Mah. Cumhuriyet Cad. No:1 08000 Merkez / ARTVİN	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Bilgehan Erdem	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	169501	{"twitter": "https://twitter.com/artvin_bld", "facebook": "https://facebook.com/artvin.bld", "instagram": "https://instagram.com/artvin.bld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440056	Siirt	2025-05-08 22:15:39.978328+00	siirt.bel.tr	+90 000 000 00 00	info@siirt.bel.tr	Siirt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440032	Muş	2025-05-08 22:15:39.978328+00	https://www.mus.bel.tr	+90 436 212 22 22	info@mus.bel.tr	Merkez Mah. Atatürk Cad. No:7 Merkez / MUŞ	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Mehmet Polat	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	406719	{"twitter": "https://twitter.com/musbld", "facebook": "https://facebook.com/musbld", "instagram": "https://instagram.com/musbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440039	Kırklareli	2025-05-08 22:15:39.978328+00	https://kırklareli.bel.tr	+90 000 000 00 00	info@kırklareli.bel.tr	Kırklareli Belediyesi, Türkiye	https://onvao.net/adminpanel/uploads/cities/6829c1e8d94b0_1747567080.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Muzaffer	Gelecek Partisi	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	50000	{}	2025-05-23 06:00:00.073489+00	il	9c5e67f1-e78a-4fa4-b7ad-2234120a231a	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440048	Muğla	2025-05-08 22:15:39.978328+00	muğla.bel.tr	+90 000 000 00 00	info@muğla.bel.tr	Muğla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440080	Osmaniye	2025-05-08 22:15:39.978328+00	osmaniye.bel.tr	+90 000 000 00 00	info@osmaniye.bel.tr	Osmaniye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440038	Kayseri	2025-05-08 22:15:39.978328+00	kayseri.bel.tr	+90 000 000 00 00	info@kayseri.bel.tr	Kayseri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440036	Kars	2025-05-08 22:15:39.978328+00	kars.bel.tr	+90 000 000 00 00	info@kars.bel.tr	Kars Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440037	Kastamonu	2025-05-08 22:15:39.978328+00	kastamonu.bel.tr	+90 000 000 00 00	info@kastamonu.bel.tr	Kastamonu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440005	Amasya	2025-05-08 22:15:39.978328+00	https://amasya.bel.tr	+90 358 218 80 00	amasya@amasya.bel.tr	Ellibeşevler Mah. Mehmet Varinli Cad. No:95-103a, 05200 Merkez/AMASYA	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Turgay Sevindi	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	337508	{"twitter": "https://twitter.com/amasya_bld", "facebook": "https://facebook.com/amasya.bld", "instagram": "https://instagram.com/amasya.bld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440015	Burdur	2025-05-08 22:15:39.978328+00	https://www.burdur.bel.tr	+90 248 233 53 40	info@burdur.bel.tr	Konak Mah. Atatürk Cad. No:17 Merkez / BURDUR	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Ali Orkun Ercengiz	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	273716	{"twitter": "https://twitter.com/burdurbld", "facebook": "https://facebook.com/burdurbld", "instagram": "https://instagram.com/burdurbld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440045	Manisa	2025-05-08 22:15:39.978328+00	manisa.bel.tr	+90 000 000 00 00	info@manisa.bel.tr	Manisa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440003	Afyonkarahisar	2025-05-08 22:15:39.978328+00	https://afyon.bel.tr	+90 272 213 27 98	info@afyon.bel.tr	Karaman Mah. Albay Reşat Çiğiltepe Cad. No:11, 03200 Merkez/AFYONKARAHİSAR	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Burcu Köksal	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	725568	{"twitter": "https://twitter.com/afyon_bld", "facebook": "https://facebook.com/afyon.bld", "instagram": "https://instagram.com/afyon.bld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440078	Karabük	2025-05-08 22:15:39.978328+00	karabük.bel.tr	+90 000 000 00 00	info@karabük.bel.tr	Karabük Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440058	Sivas	2025-05-08 22:15:39.978328+00	sivas.bel.tr	+90 000 000 00 00	info@sivas.bel.tr	Sivas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440060	Tokat	2025-05-08 22:15:39.978328+00	tokat.bel.tr	+90 000 000 00 00	info@tokat.bel.tr	Tokat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440065	Van	2025-05-08 22:15:39.978328+00	van.bel.tr	+90 000 000 00 00	info@van.bel.tr	Van Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440066	Yozgat	2025-05-08 22:15:39.978328+00	yozgat.bel.tr	+90 000 000 00 00	info@yozgat.bel.tr	Yozgat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440067	Zonguldak	2025-05-08 22:15:39.978328+00	zonguldak.bel.tr	+90 000 000 00 00	info@zonguldak.bel.tr	Zonguldak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440006	Ankara	2025-05-08 22:15:39.978328+00	https://www.ankara.bel.tr	+90 312 507 10 00	baskent@ankara.bel.tr	Atatürk Bulvarı No:1 06100 Kızılay / Çankaya / ANKARA	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Mansur Yavaş	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	5706471	{"twitter": "https://twitter.com/ankarabbld", "facebook": "https://facebook.com/ankarabbld", "instagram": "https://instagram.com/ankarabbld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440028	Hatay	2025-05-08 22:15:39.978328+00	https://www.hatay.bel.tr	+90 326 214 12 12	info@hatay.bel.tr	Antakya Mah. Atatürk Cad. No:10 Antakya / HATAY	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Lütfü Savaş	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	1660476	{"twitter": "https://twitter.com/hataybld", "facebook": "https://facebook.com/hataybld", "instagram": "https://instagram.com/hataybld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440011	Bilecik	2025-05-08 22:15:39.978328+00	bilecik.bel.tr	+90 000 000 00 00	info@bilecik.bel.tr	Bilecik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440031	Muğla	2025-05-08 22:15:39.978328+00	https://www.mugla.bel.tr	+90 252 211 11 11	info@mugla.bel.tr	Menteşe Mah. Atatürk Cad. No:5 Menteşe / MUĞLA	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Mehmet Sekmen	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	1029828	{"twitter": "https://twitter.com/muglabelediyesi", "facebook": "https://facebook.com/muglabelediyesi", "instagram": "https://instagram.com/muglabelediyesi"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440012	Bingöl	2025-05-08 22:15:39.978328+00	bingöl.bel.tr	+90 000 000 00 00	info@bingöl.bel.tr	Bingöl Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440073	Şırnak	2025-05-08 22:15:39.978328+00	https://sirnak.bel.tr	+90 000 000 00 00	info@şırnak.bel.tr	Şırnak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	DEM Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/DEM_PART%C4%B0_LOGOSU.png/250px-DEM_PART%C4%B0_LOGOSU.png	0	{}	2025-05-23 06:00:00.073489+00	il	a3b613a3-500d-41b2-8603-25cb25b0459f	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440013	Bitlis	2025-05-08 22:15:39.978328+00	bitlis.bel.tr	+90 000 000 00 00	info@bitlis.bel.tr	Bitlis Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440010	Balıkesir	2025-05-08 22:15:39.978328+00	https://www.balikesir.bel.tr	+90 266 239 15 10	info@balikesir.bel.tr	Dumlupınar Mah. Gazi Bulvarı No:100 Karesi / BALIKESİR	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Ahmet Akın	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	1282954	{"twitter": "https://twitter.com/balikesir_bld", "facebook": "https://facebook.com/balikesirbb", "instagram": "https://instagram.com/balikesirbuyuksehir"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440009	Aydın	2025-05-08 22:15:39.978328+00	https://www.aydin.bel.tr	+90 256 213 40 00	info@aydin.bel.tr	Ramazanpaşa Mah. İstiklal Cad. No:4 09100 Merkez / AYDIN	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Özlem Çerçioğlu	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	1138592	{"twitter": "https://twitter.com/aydin_bld", "facebook": "https://facebook.com/aydinbuyuksehir", "instagram": "https://instagram.com/aydinbuyuksehir"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440024	Gaziantep	2025-05-08 22:15:39.978328+00	https://www.gaziantep.bel.tr	+90 342 231 70 70	info@gaziantep.bel.tr	Şahinbey Mah. İnönü Cad. No:12 Şahinbey / GAZİANTEP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Fatma Şahin	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	2089000	{"twitter": "https://twitter.com/gaziantepbld", "facebook": "https://facebook.com/gaziantepbld", "instagram": "https://instagram.com/gaziantepbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440016	Bursa	2025-05-08 22:15:39.978328+00	https://www.bursa.bel.tr	+90 224 716 10 00	info@bursa.bel.tr	Sakarya Mah. Yeni Belediye Cad. No:1 Osmangazi / BURSA	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Mustafa Bozbey	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	3101839	{"twitter": "https://twitter.com/bursabuyuksehir", "facebook": "https://facebook.com/bursabbld", "instagram": "https://instagram.com/bursabuyuksehir"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440019	Çorum	2025-05-08 22:15:39.978328+00	https://www.corum.bel.tr	+90 364 225 05 00	info@corum.bel.tr	Yavruturna Mah. Gazi Cad. No:1 Merkez / ÇORUM	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Halil İbrahim Aşgın	AKP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	524130	{"twitter": "https://twitter.com/corumbld", "facebook": "https://facebook.com/corumbld", "instagram": "https://instagram.com/corumbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440020	Denizli	2025-05-08 22:15:39.978328+00	https://www.denizli.bel.tr	+90 258 280 20 20	info@denizli.bel.tr	Altıntop Mah. Lise Cad. No:2 Merkezefendi / DENİZLİ	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Bülent Nuri Çavuşoğlu	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	1050011	{"twitter": "https://twitter.com/denizlibld", "facebook": "https://facebook.com/denizlibld", "instagram": "https://instagram.com/denizlibld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440001	Adana	2025-05-08 22:15:39.978328+00	https://www.adana.bel.tr	+90 322 455 35 00	info@adana.bel.tr	Reşatbey Mahallesi, Atatürk Caddesi No:2, Seyhan / Adana	https://onvao.net/adminpanel/uploads/cities/6829ca76250f9_1747569270.png	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Zeydan Karalar	CHP	https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Cumhuriyet_Halk_Partisi_Logo.svg/200px-Cumhuriyet_Halk_Partisi_Logo.svg.png	2270298	{\n    "facebook": "https://www.facebook.com/adana.bel.tr",\n    "instagram": "https://www.instagram.com/adana.bel.tr/",\n    "twitter": "https://twitter.com/adana_bel_tr"\n  }	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	5	1	1	33.33	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440042	Konya	2025-05-08 22:15:39.978328+00	konya.bel.tr	+90 000 000 00 00	info@konya.bel.tr	Konya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440047	Mardin	2025-05-08 22:15:39.978328+00	mardin.bel.tr	+90 000 000 00 00	info@mardin.bel.tr	Mardin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440026	Gümüşhane	2025-05-08 22:15:39.978328+00	https://www.gumushane.bel.tr	+90 456 212 12 12	info@gumushane.bel.tr	Çarşı Mah. Atatürk Cad. No:2 Merkez / GÜMÜŞHANE	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Ercan Çimen	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	140813	{"twitter": "https://twitter.com/gumushanebld", "facebook": "https://facebook.com/gumushanebld", "instagram": "https://instagram.com/gumushanebld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00	f
550e8400-e29b-41d4-a716-446655440025	Giresun	2025-05-08 22:15:39.978328+00	https://www.giresun.bel.tr	+90 454 212 10 10	info@giresun.bel.tr	Gazi Mah. Atatürk Cad. No:10 Merkez / GİRESUN	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Aytekin Şenlikoğlu	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	446381	{"twitter": "https://twitter.com/giresunbld", "facebook": "https://facebook.com/giresunbld", "instagram": "https://instagram.com/giresunbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00	f
550e8400-e29b-41d4-a716-446655440034	Niğde	2025-05-08 22:15:39.978328+00	https://www.nigde.bel.tr	+90 388 212 33 33	info@nigde.bel.tr	Merkez Mah. Atatürk Cad. No:4 Merkez / NİĞDE	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Emrah Özdemir	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	365419	{"twitter": "https://twitter.com/nigdebld", "facebook": "https://facebook.com/nigdebld", "instagram": "https://instagram.com/nigdebld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00	f
550e8400-e29b-41d4-a716-446655440027	Hakkari	2025-05-08 22:15:39.978328+00	https://www.hakkari.bel.tr	+90 438 212 15 15	info@hakkari.bel.tr	Şemdinli Mah. Atatürk Cad. No:3 Merkez / HAKKARİ	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Cengiz Topel Yıldız	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	280514	{"twitter": "https://twitter.com/hakkaribld", "facebook": "https://facebook.com/hakkaribld", "instagram": "https://instagram.com/hakkaribld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00	f
550e8400-e29b-41d4-a716-446655440021	Erzincan	2025-05-08 22:15:39.978328+00	https://www.erzincan.bel.tr	+90 446 214 13 14	info@erzincan.bel.tr	İstasyon Mah. Atatürk Cad. No:4 Merkez / ERZİNCAN	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Suat Kılıç	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	238172	{"twitter": "https://twitter.com/erzincanbld", "facebook": "https://facebook.com/erzincanbld", "instagram": "https://instagram.com/erzincanbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00	f
550e8400-e29b-41d4-a716-446655440033	Nevşehir	2025-05-08 22:15:39.978328+00	https://www.nevsehir.bel.tr	+90 384 213 44 44	info@nevsehir.bel.tr	Merkez Mah. Atatürk Cad. No:1 Merkez / NEVŞEHİR	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Ürgüp Adayı	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	310033	{"twitter": "https://twitter.com/nevsehirlbld", "facebook": "https://facebook.com/nevsehirlbld", "instagram": "https://instagram.com/nevsehirlbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00	f
550e8400-e29b-41d4-a716-446655440054	Sakarya	2025-05-08 22:15:39.978328+00	sakarya.bel.tr	+90 000 000 00 00	info@sakarya.bel.tr	Sakarya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440055	Samsun	2025-05-08 22:15:39.978328+00	samsun.bel.tr	+90 000 000 00 00	info@samsun.bel.tr	Samsun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440007	Antalya	2025-05-08 22:15:39.978328+00	https://www.antalya.bel.tr	+90 242 249 50 00	info@antalya.bel.tr	Yüksekalan Mah. Adnan Menderes Blv. No:20 07310 Muratpaşa / ANTALYA	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Muhittin Böcek	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	2684562	{"twitter": "https://twitter.com/antalya_bld", "facebook": "https://facebook.com/antalyabb", "instagram": "https://instagram.com/antalya_buyuksehir"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440057	Sinop	2025-05-08 22:15:39.978328+00	sinop.bel.tr	+90 000 000 00 00	info@sinop.bel.tr	Sinop Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440081	Düzce	2025-05-08 22:15:39.978328+00	https://düzce.bel.tr	+90 000 000 00 00	info@düzce.bel.tr	Düzce Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	DEM Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/DEM_PART%C4%B0_LOGOSU.png/250px-DEM_PART%C4%B0_LOGOSU.png	0	{}	2025-05-23 06:00:00.073489+00	il	448575ce-7444-4bd7-8070-1753a8ecb16b	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440017	Çanakkale	2025-05-08 22:15:39.978328+00	https://www.canakkale.bel.tr	+90 286 217 10 12	info@canakkale.bel.tr	Cevatpaşa Mah. Belediye Cad. No:1 Merkez / ÇANAKKALE	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Muharrem Erkek	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	557276	{"twitter": "https://twitter.com/canakkalebld", "facebook": "https://facebook.com/canakkalebld", "instagram": "https://instagram.com/canakkalebld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440046	Kahramanmaraş	2025-05-08 22:15:39.978328+00	kahramanmaraş.bel.tr	+90 000 000 00 00	info@kahramanmaraş.bel.tr	Kahramanmaraş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440070	Karaman	2025-05-08 22:15:39.978328+00	karaman.bel.tr	+90 000 000 00 00	info@karaman.bel.tr	Karaman Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440018	Çankırı	2025-05-08 22:15:39.978328+00	https://www.cankiri.bel.tr	+90 376 213 10 46	info@cankiri.bel.tr	Cumhuriyet Mah. Atatürk Bulvarı No:2 Merkez / ÇANKIRI	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	İsmail Hakkı Esen	MHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	195766	{"twitter": "https://twitter.com/cankiribld", "facebook": "https://facebook.com/cankiribld", "instagram": "https://instagram.com/cankiribld"}	2025-05-23 06:00:00.073489+00	il	dfe1b574-8fcd-4c16-8496-6e96e960b253	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440023	Eskişehir	2025-05-08 22:15:39.978328+00	https://www.eskisehir.bel.tr	+90 222 230 00 00	info@eskisehir.bel.tr	Odunpazarı Mah. Atatürk Cad. No:5 Odunpazarı / ESKİŞEHİR	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Yılmaz Büyükerşen	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	887475	{"twitter": "https://twitter.com/eskisehirbld", "facebook": "https://facebook.com/eskisehirbld", "instagram": "https://instagram.com/eskisehirbld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440072	Batman	2025-05-08 22:15:39.978328+00	https://www.batman.bel.tr	0488 213 27 59	bilgi@batman.bel.tr	Şirinevler, Atatürk Blv. no:2	https://files.sikayetvar.com/lg/cmp/50/5040.png?1522650125	https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/Latrans-Turkey_location_Batman.svg/330px-Latrans-Turkey_location_Batman.svg.png	Ekrem Canalp	AK PARTİ	https://upload.wikimedia.org/wikipedia/tr/d/d5/Adalet_ve_Kalk%C4%B1nma_Partisi_logo.png	506322	https://www.instagram.com/btmnbld	2025-05-23 06:00:00.073489+00	il	448575ce-7444-4bd7-8070-1753a8ecb16b	\N	0	0	1	100.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440062	Tunceli	2025-05-08 22:15:39.978328+00	tunceli.bel.tr	+90 000 000 00 00	info@tunceli.bel.tr	Tunceli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440064	Uşak	2025-05-08 22:15:39.978328+00	uşak.bel.tr	+90 000 000 00 00	info@uşak.bel.tr	Uşak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440052	Ordu	2025-05-08 22:15:39.978328+00	ordu.bel.tr	+90 000 000 00 00	info@ordu.bel.tr	Ordu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440029	Isparta	2025-05-08 22:15:39.978328+00	https://www.isparta.bel.tr	+90 246 213 11 11	info@isparta.bel.tr	Zafer Mah. Atatürk Cad. No:8 Merkez / ISPARTA	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Şükrü Başdeğirmen	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	436999	{"twitter": "https://twitter.com/ispartabld", "facebook": "https://facebook.com/ispartabld", "instagram": "https://instagram.com/ispartabld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440002	Adıyaman	2025-05-08 22:15:39.978328+00	https://adiyaman.bel.tr	+90 416 216 17 20	info@adiyaman.bel.tr	Alitaşı Mah. Atatürk Blv. No:144, 02000 Adıyaman Merkez/ADIYAMAN	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Süleyman Kılınç	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	627509	{"twitter": "https://twitter.com/adiyaman_bld", "facebook": "https://facebook.com/adiyaman.bld", "instagram": "https://instagram.com/adiyaman.bld"}	2025-05-23 06:00:00.073489+00	il	dfe1b574-8fcd-4c16-8496-6e96e960b253	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440030	Mersin	2025-05-08 22:15:39.978328+00	https://www.mersin.bel.tr	+90 324 233 33 33	info@mersin.bel.tr	Yenişehir Mah. Atatürk Cad. No:20 Yenişehir / MERSİN	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Vahap Seçer	CHP	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	1840425	{"twitter": "https://twitter.com/mersinbld", "facebook": "https://facebook.com/mersinbld", "instagram": "https://instagram.com/mersinbld"}	2025-05-23 06:00:00.073489+00	il	46a4359e-86a1-4974-b022-a4532367aa5e	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440022	Erzurum	2025-05-08 22:15:39.978328+00	https://www.erzurum.bel.tr	+90 442 232 33 33	info@erzurum.bel.tr	Kazım Karabekir Mah. Atatürk Cad. No: 1 Yakutiye / ERZURUM	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Mehmet Sekmen	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	762021	{"twitter": "https://twitter.com/erzurumbld", "facebook": "https://facebook.com/erzurumbld", "instagram": "https://instagram.com/erzurumbld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440076	Iğdır	2025-05-08 22:15:39.978328+00	iğdır.bel.tr	+90 000 000 00 00	info@iğdır.bel.tr	Iğdır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440014	Bolu	2025-05-08 22:15:39.978328+00	bolu.bel.tr	+90 000 000 00 00	info@bolu.bel.tr	Bolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440049	Muş	2025-05-08 22:15:39.978328+00	muş.bel.tr	+90 000 000 00 00	info@muş.bel.tr	Muş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440061	Trabzon	2025-05-08 22:15:39.978328+00	trabzon.bel.tr	+90 000 000 00 00	info@trabzon.bel.tr	Trabzon Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440035	Ordu	2025-05-08 22:15:39.978328+00	https://www.ordu.bel.tr	+90 452 212 22 22	info@ordu.bel.tr	Altınordu Mah. Atatürk Cad. No:3 Merkez / ORDU	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	https://st3.depositphotos.com/5918238/18694/i/450/depositphotos_186942178-stock-photo-grunge-scratched-blue-background-illustration.jpg	Engin Tekintaş	AK Parti	https://static.vecteezy.com/system/resources/previews/023/817/918/non_2x/solid-icon-for-demo-vector.jpg	743682	{"twitter": "https://twitter.com/ordubld", "facebook": "https://facebook.com/ordubld", "instagram": "https://instagram.com/ordubld"}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440063	Şanlıurfa	2025-05-08 22:15:39.978328+00	https://urfa.bel.tr	+90 000 000 00 00	info@şanlıurfa.bel.tr	Şanlıurfa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	DEM Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/DEM_PART%C4%B0_LOGOSU.png/250px-DEM_PART%C4%B0_LOGOSU.png	0	{}	2025-05-23 06:00:00.073489+00	il	a3b613a3-500d-41b2-8603-25cb25b0459f	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	t
550e8400-e29b-41d4-a716-446655440053	Rize	2025-05-08 22:15:39.978328+00	rize.bel.tr	+90 000 000 00 00	info@rize.bel.tr	Rize Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440079	Kilis	2025-05-08 22:15:39.978328+00	kilis.bel.tr	+90 000 000 00 00	info@kilis.bel.tr	Kilis Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440075	Ardahan	2025-05-08 22:15:39.978328+00	ardahan.bel.tr	+90 000 000 00 00	info@ardahan.bel.tr	Ardahan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
550e8400-e29b-41d4-a716-446655440051	Niğde	2025-05-08 22:15:39.978328+00	niğde.bel.tr	+90 000 000 00 00	info@niğde.bel.tr	Niğde Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	2025-05-23 06:00:00.073489+00	il	\N	\N	0	0	0	0.00	2025-05-23 06:00:00.073489+00	f
\.


--
-- Data for Name: comments; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.comments (id, post_id, user_id, content, created_at, updated_at, is_hidden) FROM stdin;
2a2a37a5-f31b-4751-8bea-45a37ff82394	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	harikaa	2025-05-21 00:17:00.88946+00	2025-05-21 00:17:00.88953+00	f
4266044e-87e6-49a7-96a7-6bdc033b2e9c	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hasks	2025-05-21 09:48:32.875822+00	2025-05-21 09:48:32.875927+00	f
f5d5d2a1-dce9-4629-b520-a3a2fa097c15	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hwshabs s	2025-05-21 09:48:35.093097+00	2025-05-21 09:48:35.093211+00	f
8fb6db2c-49f1-4095-99da-f912c02e38c4	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hshssnsb	2025-05-21 09:48:36.725864+00	2025-05-21 09:48:36.725941+00	f
7fac4157-38e9-42ad-a0bb-e9456d8d069a	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	a a a a a	2025-05-21 09:48:41.949494+00	2025-05-21 09:48:41.949597+00	f
9edfb4b5-2979-4191-bdb8-f777c71ff9ff	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	bsbsbssbs	2025-05-21 09:48:43.508418+00	2025-05-21 09:48:43.508484+00	f
49752d68-6a03-41b2-af96-1195421f72b0	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	bs s ss a	2025-05-21 09:48:45.009501+00	2025-05-21 09:48:45.009583+00	f
f20ae9c2-f5dc-4169-80ea-82c4ee566371	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	Harikaaaa	2025-05-21 12:00:51.378867+00	2025-05-21 12:00:51.378927+00	f
8f7b2ded-c5c0-4b6a-af9d-3e7faca4c086	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	harika a	2025-05-21 12:00:58.240395+00	2025-05-21 12:00:58.240478+00	f
d00f1613-7ff3-417f-84f5-9763e0eeec43	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hshzs	2025-05-21 12:00:59.771425+00	2025-05-21 12:00:59.771498+00	f
7e9451d7-5c9c-4dab-96f0-030c21dfa573	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	shshshs	2025-05-21 12:01:01.012127+00	2025-05-21 12:01:01.012208+00	f
d32f7bf0-33e2-4465-9c8a-7862af3036dd	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	bsbsbsj	2025-05-21 12:01:02.345549+00	2025-05-21 12:01:02.345672+00	f
b995bac7-10c4-4f56-b193-0f3ee4ed4290	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	shshs	2025-05-21 12:01:03.513124+00	2025-05-21 12:01:03.513199+00	f
207c050f-e825-4bcc-b5a9-2442993defec	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	sususu	2025-05-21 12:01:04.619531+00	2025-05-21 12:01:04.619561+00	f
96b05b48-7146-4adb-8656-c8c4e3fa9faf	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	shshsjs	2025-05-21 12:01:05.802053+00	2025-05-21 12:01:05.802097+00	f
f73090ae-8f79-4ca2-8c3a-44ec0e7e4caf	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hshshshs	2025-05-21 12:01:07.005943+00	2025-05-21 12:01:07.006023+00	f
03b00c81-73c7-48b4-a548-e61600ce0430	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	shshshs	2025-05-21 12:01:08.15508+00	2025-05-21 12:01:08.155147+00	f
79c4ba44-dfcf-4d7d-97d2-468132f7ec00	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hahaha	2025-05-21 12:01:09.478203+00	2025-05-21 12:01:09.478298+00	f
01ffa081-382f-4ef9-9243-74739c0e3b1e	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hahahs	2025-05-21 12:01:10.662154+00	2025-05-21 12:01:10.662227+00	f
968db185-69b7-45b0-a5cd-d6243c496d55	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hshssh	2025-05-21 12:01:11.844387+00	2025-05-21 12:01:11.844469+00	f
489bb2a6-dd6f-42ed-a2b9-13c0c5124314	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hshshs	2025-05-21 12:01:13.028451+00	2025-05-21 12:01:13.028513+00	f
4f8fd569-46ff-4563-8b6d-f645f0a1e6ca	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hhhs	2025-05-21 12:01:14.328591+00	2025-05-21 12:01:14.328672+00	f
521d2779-1a95-4f22-afd9-8ba2c5eae633	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hsusus	2025-05-21 12:01:15.537562+00	2025-05-21 12:01:15.537635+00	f
bb407758-759f-424a-ab5b-5ff1fe28cff1	2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hshshs	2025-05-21 12:01:16.938871+00	2025-05-21 12:01:16.93893+00	f
cce2f6d9-5a87-42c2-82f4-fe36e4adb49b	f4f07614-d116-4b8d-8af9-070378ed808a	83190944-98d5-41be-ac3a-178676faf017	merhaba	2025-05-23 08:23:52.401085+00	2025-05-23 08:23:52.401142+00	f
3b0f737b-94bd-452b-aeb5-bbc0675fea64	f4f07614-d116-4b8d-8af9-070378ed808a	83190944-98d5-41be-ac3a-178676faf017	merhaba	2025-05-23 18:04:30.820892+00	2025-05-23 18:04:30.821044+00	f
2344815d-a3ef-4515-aa6a-24bf9cac6367	b3ff2b41-217e-43dd-80c0-91315c6fc4bb	83190944-98d5-41be-ac3a-178676faf017	yess	2025-05-23 21:51:23.511037+00	2025-05-23 21:51:23.511124+00	f
5f5eac29-dd4f-41ff-b0d3-88577351a621	9ce11574-1cd3-4675-ba13-c0c509ac7085	cdc2d279-8171-4aa5-89cb-10f81fed72c3	merhaba	2025-05-23 22:02:45.488436+00	2025-05-23 22:02:45.488529+00	f
d331244c-d537-4b0e-8318-95e2ebbed004	b3ff2b41-217e-43dd-80c0-91315c6fc4bb	8b52a8cb-cb89-4325-9c62-de454a0476fb	dyryryf	2025-05-23 22:43:28.592263+00	2025-05-23 22:43:28.592294+00	f
f3ee6294-a6fa-4c33-a83f-0ab342eddbda	82ad7704-2910-4e8c-97e8-8ed9f7ca224d	8b52a8cb-cb89-4325-9c62-de454a0476fb	merhaba	2025-05-23 22:56:40.566051+00	2025-05-23 22:56:40.566209+00	f
\.


--
-- Data for Name: districts; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.districts (id, city_id, name, created_at, updated_at, website, phone, email, address, logo_url, cover_image_url, mayor_name, mayor_party, party_logo_url, population, social_media_links, type, political_party_id, cozumorani, total_complaints, solved_complaints, thanks_count, solution_rate, solution_last_updated) FROM stdin;
660e8400-e29b-41d4-a716-446655593166	550e8400-e29b-41d4-a716-446655440072	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://www.batman.bel.tr	0488 213 27 59	bilgi@batman.bel.tr	Şirinevler, Atatürk Blv. no:2	https://images.seeklogo.com/logo-png/42/2/batman-belediyesi-logo-png_seeklogo-429262.png	https://upload.wikimedia.org/wikipedia/commons/thumb/5/50/Latrans-Turkey_location_Batman.svg/330px-Latrans-Turkey_location_Batman.svg.png	Ekrem Canalp	AKP	https://upload-wikimedia-org.translate.goog/wikipedia/en/thumb/5/56/Justice_and_Development_Party_%28Turkey%29_logo.svg/225px-Justice_and_Development_Party_%28Turkey%29_logo.svg.png?_x_tr_sl=en&_x_tr_tl=tr&_x_tr_hl=tr&_x_tr_pto=tc	506322	{}	ilçe	448575ce-7444-4bd7-8070-1753a8ecb16b	\N	1	0	1	50.00	2025-05-23 22:49:03.580181+00
660e8400-e29b-41d4-a716-446655481054	550e8400-e29b-41d4-a716-446655440005	Hamamözü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hamamözü.bel.tr	+90 000 000 00 00	info@hamamözü.bel.tr	Hamamözü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	1	0	0	0.00	2025-05-23 17:21:42.026674+00
660e8400-e29b-41d4-a716-446656344917	550e8400-e29b-41d4-a716-446655440034	Zeytinburnu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	zeytinburnu.bel.tr	+90 000 000 00 00	info@zeytinburnu.bel.tr	Zeytinburnu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655515088	550e8400-e29b-41d4-a716-446655440007	Elmalı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	elmalı.bel.tr	+90 000 000 00 00	info@elmalı.bel.tr	Elmalı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656121694	550e8400-e29b-41d4-a716-446655440054	Kaynarca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kaynarca.bel.tr	+90 000 000 00 00	info@kaynarca.bel.tr	Kaynarca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655705278	550e8400-e29b-41d4-a716-446655440081	Çilimli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çilimli.bel.tr	+90 000 000 00 00	info@çilimli.bel.tr	Çilimli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655869442	550e8400-e29b-41d4-a716-446655440037	Araç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	araç.bel.tr	+90 000 000 00 00	info@araç.bel.tr	Araç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656256829	550e8400-e29b-41d4-a716-446655440066	Saraykent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	saraykent.bel.tr	+90 000 000 00 00	info@saraykent.bel.tr	Saraykent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655738311	550e8400-e29b-41d4-a716-446655440025	Hınıs	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hınıs.bel.tr	+90 000 000 00 00	info@hınıs.bel.tr	Hınıs Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656161734	550e8400-e29b-41d4-a716-446655440058	Akıncılar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akıncılar.bel.tr	+90 000 000 00 00	info@akıncılar.bel.tr	Akıncılar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656194767	550e8400-e29b-41d4-a716-446655440060	Pazar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pazar.bel.tr	+90 000 000 00 00	info@pazar.bel.tr	Pazar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656303876	550e8400-e29b-41d4-a716-446655440019	Laçin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	laçin.bel.tr	+90 000 000 00 00	info@laçin.bel.tr	Laçin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655723296	550e8400-e29b-41d4-a716-446655440023	Maden	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	maden.bel.tr	+90 000 000 00 00	info@maden.bel.tr	Maden Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655529102	550e8400-e29b-41d4-a716-446655440075	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655997570	550e8400-e29b-41d4-a716-446655440044	Kuluncak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kuluncak.bel.tr	+90 000 000 00 00	info@kuluncak.bel.tr	Kuluncak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656012585	550e8400-e29b-41d4-a716-446655440045	Sarıgöl	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıgöl.bel.tr	+90 000 000 00 00	info@sarıgöl.bel.tr	Sarıgöl Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656158731	550e8400-e29b-41d4-a716-446655440057	Saraydüzü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	saraydüzü.bel.tr	+90 000 000 00 00	info@saraydüzü.bel.tr	Saraydüzü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655898471	550e8400-e29b-41d4-a716-446655440038	Talas	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	talas.bel.tr	+90 000 000 00 00	info@talas.bel.tr	Talas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655600173	550e8400-e29b-41d4-a716-446655440069	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655642215	550e8400-e29b-41d4-a716-446655440015	Yeşilova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yeşilova.bel.tr	+90 000 000 00 00	info@yeşilova.bel.tr	Yeşilova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656133706	550e8400-e29b-41d4-a716-446655440055	Canik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	canik.bel.tr	+90 000 000 00 00	info@canik.bel.tr	Canik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655621194	550e8400-e29b-41d4-a716-446655440013	Güroymak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güroymak.bel.tr	+90 000 000 00 00	info@güroymak.bel.tr	Güroymak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655625198	550e8400-e29b-41d4-a716-446655440014	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655641214	550e8400-e29b-41d4-a716-446655440015	Tefenni	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tefenni.bel.tr	+90 000 000 00 00	info@tefenni.bel.tr	Tefenni Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656265838	550e8400-e29b-41d4-a716-446655440066	Şefaatli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şefaatli.bel.tr	+90 000 000 00 00	info@şefaatli.bel.tr	Şefaatli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656292865	550e8400-e29b-41d4-a716-446655440018	Kızılırmak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kızılırmak.bel.tr	+90 000 000 00 00	info@kızılırmak.bel.tr	Kızılırmak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655739312	550e8400-e29b-41d4-a716-446655440025	Karayazı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karayazı.bel.tr	+90 000 000 00 00	info@karayazı.bel.tr	Karayazı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656317890	550e8400-e29b-41d4-a716-446655440034	Bakırköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bakırköy.bel.tr	+90 000 000 00 00	info@bakırköy.bel.tr	Bakırköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655876449	550e8400-e29b-41d4-a716-446655440037	Doğanyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğanyurt.bel.tr	+90 000 000 00 00	info@doğanyurt.bel.tr	Doğanyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655704277	550e8400-e29b-41d4-a716-446655440081	Yığılca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yığılca.bel.tr	+90 000 000 00 00	info@yığılca.bel.tr	Yığılca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655873446	550e8400-e29b-41d4-a716-446655440037	Cide	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	cide.bel.tr	+90 000 000 00 00	info@cide.bel.tr	Cide Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655742315	550e8400-e29b-41d4-a716-446655440025	Narman	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	narman.bel.tr	+90 000 000 00 00	info@narman.bel.tr	Narman Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655848421	550e8400-e29b-41d4-a716-446655440078	Eflani	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eflani.bel.tr	+90 000 000 00 00	info@eflani.bel.tr	Eflani Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656205778	550e8400-e29b-41d4-a716-446655440061	Dernekpazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dernekpazarı.bel.tr	+90 000 000 00 00	info@dernekpazarı.bel.tr	Dernekpazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440004	550e8400-e29b-41d4-a716-446655440001	Karaisalı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karaisalı.bel.tr	+90 000 000 00 00	info@karaisalı.bel.tr	Karaisalı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655663236	550e8400-e29b-41d4-a716-446655440020	Babadağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	babadağ.bel.tr	+90 000 000 00 00	info@babadağ.bel.tr	Babadağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655792365	550e8400-e29b-41d4-a716-446655440028	Çanakçı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çanakçı.bel.tr	+90 000 000 00 00	info@çanakçı.bel.tr	Çanakçı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655577150	550e8400-e29b-41d4-a716-446655440010	Erdek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erdek.bel.tr	+90 000 000 00 00	info@erdek.bel.tr	Erdek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656191764	550e8400-e29b-41d4-a716-446655440060	Başçiftlik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	başçiftlik.bel.tr	+90 000 000 00 00	info@başçiftlik.bel.tr	Başçiftlik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656110683	550e8400-e29b-41d4-a716-446655440053	İkizdere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ikizdere.bel.tr	+90 000 000 00 00	info@ikizdere.bel.tr	İkizdere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656262835	550e8400-e29b-41d4-a716-446655440066	Çandır	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çandır.bel.tr	+90 000 000 00 00	info@çandır.bel.tr	Çandır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655995568	550e8400-e29b-41d4-a716-446655440044	Hekimhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hekimhan.bel.tr	+90 000 000 00 00	info@hekimhan.bel.tr	Hekimhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656240813	550e8400-e29b-41d4-a716-446655440065	Saray	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	saray.bel.tr	+90 000 000 00 00	info@saray.bel.tr	Saray Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655506079	550e8400-e29b-41d4-a716-446655440006	Çamlıdere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çamlıdere.bel.tr	+90 000 000 00 00	info@çamlıdere.bel.tr	Çamlıdere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655562135	550e8400-e29b-41d4-a716-446655440004	Diyadin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	diyadin.bel.tr	+90 000 000 00 00	info@diyadin.bel.tr	Diyadin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655627200	550e8400-e29b-41d4-a716-446655440014	Gerede	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gerede.bel.tr	+90 000 000 00 00	info@gerede.bel.tr	Gerede Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656283856	550e8400-e29b-41d4-a716-446655440017	Yenice	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenice.bel.tr	+90 000 000 00 00	info@yenice.bel.tr	Yenice Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656374947	550e8400-e29b-41d4-a716-446655440035	Selçuk	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	selçuk.bel.tr	+90 000 000 00 00	info@selçuk.bel.tr	Selçuk Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656184757	550e8400-e29b-41d4-a716-446655440059	Saray	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	saray.bel.tr	+90 000 000 00 00	info@saray.bel.tr	Saray Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656131704	550e8400-e29b-41d4-a716-446655440055	Ayvacık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ayvacık.bel.tr	+90 000 000 00 00	info@ayvacık.bel.tr	Ayvacık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655636209	550e8400-e29b-41d4-a716-446655440015	Bucak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bucak.bel.tr	+90 000 000 00 00	info@bucak.bel.tr	Bucak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656383956	550e8400-e29b-41d4-a716-446655440063	Bozova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozova.bel.tr	+90 000 000 00 00	info@bozova.bel.tr	Bozova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656186759	550e8400-e29b-41d4-a716-446655440059	Çerkezköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çerkezköy.bel.tr	+90 000 000 00 00	info@çerkezköy.bel.tr	Çerkezköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656313886	550e8400-e29b-41d4-a716-446655440034	Arnavutköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arnavutköy.bel.tr	+90 000 000 00 00	info@arnavutköy.bel.tr	Arnavutköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655860433	550e8400-e29b-41d4-a716-446655440036	Akyaka	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akyaka.bel.tr	+90 000 000 00 00	info@akyaka.bel.tr	Akyaka Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655541114	550e8400-e29b-41d4-a716-446655440008	Murgul	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	murgul.bel.tr	+90 000 000 00 00	info@murgul.bel.tr	Murgul Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656038611	550e8400-e29b-41d4-a716-446655440033	Toroslar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	toroslar.bel.tr	+90 000 000 00 00	info@toroslar.bel.tr	Toroslar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656045618	550e8400-e29b-41d4-a716-446655440048	Kavaklıdere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kavaklıdere.bel.tr	+90 000 000 00 00	info@kavaklıdere.bel.tr	Kavaklıdere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655865438	550e8400-e29b-41d4-a716-446655440036	Sarıkamış	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıkamış.bel.tr	+90 000 000 00 00	info@sarıkamış.bel.tr	Sarıkamış Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656198771	550e8400-e29b-41d4-a716-446655440060	Turhal	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	turhal.bel.tr	+90 000 000 00 00	info@turhal.bel.tr	Turhal Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655534107	550e8400-e29b-41d4-a716-446655440075	Çıldır	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çıldır.bel.tr	+90 000 000 00 00	info@çıldır.bel.tr	Çıldır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656229802	550e8400-e29b-41d4-a716-446655440064	Karahallı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karahallı.bel.tr	+90 000 000 00 00	info@karahallı.bel.tr	Karahallı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655634207	550e8400-e29b-41d4-a716-446655440015	Altınyayla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altınyayla.bel.tr	+90 000 000 00 00	info@altınyayla.bel.tr	Altınyayla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655977550	550e8400-e29b-41d4-a716-446655440071	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656082655	550e8400-e29b-41d4-a716-446655440052	Kabataş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kabataş.bel.tr	+90 000 000 00 00	info@kabataş.bel.tr	Kabataş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656178751	550e8400-e29b-41d4-a716-446655440059	Ergene	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ergene.bel.tr	+90 000 000 00 00	info@ergene.bel.tr	Ergene Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655845418	550e8400-e29b-41d4-a716-446655440046	Pazarcık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pazarcık.bel.tr	+90 000 000 00 00	info@pazarcık.bel.tr	Pazarcık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656301874	550e8400-e29b-41d4-a716-446655440019	Dodurga	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dodurga.bel.tr	+90 000 000 00 00	info@dodurga.bel.tr	Dodurga Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655502075	550e8400-e29b-41d4-a716-446655440006	Polatlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	polatlı.bel.tr	+90 000 000 00 00	info@polatlı.bel.tr	Polatlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656357930	550e8400-e29b-41d4-a716-446655440035	Bornova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bornova.bel.tr	+90 000 000 00 00	info@bornova.bel.tr	Bornova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656188761	550e8400-e29b-41d4-a716-446655440059	Şarköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şarköy.bel.tr	+90 000 000 00 00	info@şarköy.bel.tr	Şarköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655853426	550e8400-e29b-41d4-a716-446655440078	Yenice	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenice.bel.tr	+90 000 000 00 00	info@yenice.bel.tr	Yenice Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655677250	550e8400-e29b-41d4-a716-446655440020	Çal	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çal.bel.tr	+90 000 000 00 00	info@çal.bel.tr	Çal Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655948521	550e8400-e29b-41d4-a716-446655440042	Yunak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yunak.bel.tr	+90 000 000 00 00	info@yunak.bel.tr	Yunak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655464037	550e8400-e29b-41d4-a716-446655440003	Sultandağı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sultandağı.bel.tr	+90 000 000 00 00	info@sultandağı.bel.tr	Sultandağı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656009582	550e8400-e29b-41d4-a716-446655440045	Kırkağaç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kırkağaç.bel.tr	+90 000 000 00 00	info@kırkağaç.bel.tr	Kırkağaç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656346919	550e8400-e29b-41d4-a716-446655440034	Çekmeköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çekmeköy.bel.tr	+90 000 000 00 00	info@çekmeköy.bel.tr	Çekmeköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655715288	550e8400-e29b-41d4-a716-446655440023	Alacakaya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alacakaya.bel.tr	+90 000 000 00 00	info@alacakaya.bel.tr	Alacakaya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655460033	550e8400-e29b-41d4-a716-446655440003	Hocalar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hocalar.bel.tr	+90 000 000 00 00	info@hocalar.bel.tr	Hocalar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655517090	550e8400-e29b-41d4-a716-446655440007	Gazipaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gazipaşa.bel.tr	+90 000 000 00 00	info@gazipaşa.bel.tr	Gazipaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656381954	550e8400-e29b-41d4-a716-446655440063	Akçakale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akçakale.bel.tr	+90 000 000 00 00	info@akçakale.bel.tr	Akçakale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656234807	550e8400-e29b-41d4-a716-446655440065	Başkale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	başkale.bel.tr	+90 000 000 00 00	info@başkale.bel.tr	Başkale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655847420	550e8400-e29b-41d4-a716-446655440046	Çağlayancerit	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çağlayancerit.bel.tr	+90 000 000 00 00	info@çağlayancerit.bel.tr	Çağlayancerit Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656276849	550e8400-e29b-41d4-a716-446655440017	Biga	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	biga.bel.tr	+90 000 000 00 00	info@biga.bel.tr	Biga Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656091664	550e8400-e29b-41d4-a716-446655440052	Ünye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ünye.bel.tr	+90 000 000 00 00	info@ünye.bel.tr	Ünye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656025598	550e8400-e29b-41d4-a716-446655440047	Savur	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	savur.bel.tr	+90 000 000 00 00	info@savur.bel.tr	Savur Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655996569	550e8400-e29b-41d4-a716-446655440044	Kale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kale.bel.tr	+90 000 000 00 00	info@kale.bel.tr	Kale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655972545	550e8400-e29b-41d4-a716-446655440071	Bahşili	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bahşili.bel.tr	+90 000 000 00 00	info@bahşili.bel.tr	Bahşili Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655834407	550e8400-e29b-41d4-a716-446655440076	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655455028	550e8400-e29b-41d4-a716-446655440003	Bolvadin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bolvadin.bel.tr	+90 000 000 00 00	info@bolvadin.bel.tr	Bolvadin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656157730	550e8400-e29b-41d4-a716-446655440057	Gerze	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gerze.bel.tr	+90 000 000 00 00	info@gerze.bel.tr	Gerze Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655756329	550e8400-e29b-41d4-a716-446655440026	Beylikova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beylikova.bel.tr	+90 000 000 00 00	info@beylikova.bel.tr	Beylikova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655441014	550e8400-e29b-41d4-a716-446655440001	Çukurova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çukurova.bel.tr	+90 000 000 00 00	info@çukurova.bel.tr	Çukurova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440011	550e8400-e29b-41d4-a716-446655440001	Tufanbeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tufanbeyli.bel.tr	+90 000 000 00 00	info@tufanbeyli.bel.tr	Tufanbeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655855428	550e8400-e29b-41d4-a716-446655440070	Başyayla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	başyayla.bel.tr	+90 000 000 00 00	info@başyayla.bel.tr	Başyayla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655941514	550e8400-e29b-41d4-a716-446655440042	Meram	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	meram.bel.tr	+90 000 000 00 00	info@meram.bel.tr	Meram Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656336909	550e8400-e29b-41d4-a716-446655440034	Maltepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	maltepe.bel.tr	+90 000 000 00 00	info@maltepe.bel.tr	Maltepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656026599	550e8400-e29b-41d4-a716-446655440047	Yeşilli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yeşilli.bel.tr	+90 000 000 00 00	info@yeşilli.bel.tr	Yeşilli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656263836	550e8400-e29b-41d4-a716-446655440066	Çayıralan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çayıralan.bel.tr	+90 000 000 00 00	info@çayıralan.bel.tr	Çayıralan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655753326	550e8400-e29b-41d4-a716-446655440025	İspir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ispir.bel.tr	+90 000 000 00 00	info@ispir.bel.tr	İspir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655546119	550e8400-e29b-41d4-a716-446655440009	Didim	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	didim.bel.tr	+90 000 000 00 00	info@didim.bel.tr	Didim Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656006579	550e8400-e29b-41d4-a716-446655440045	Gördes	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gördes.bel.tr	+90 000 000 00 00	info@gördes.bel.tr	Gördes Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655445018	550e8400-e29b-41d4-a716-446655440002	Gerger	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gerger.bel.tr	+90 000 000 00 00	info@gerger.bel.tr	Gerger Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656160733	550e8400-e29b-41d4-a716-446655440057	Türkeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	türkeli.bel.tr	+90 000 000 00 00	info@türkeli.bel.tr	Türkeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656181754	550e8400-e29b-41d4-a716-446655440059	Malkara	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	malkara.bel.tr	+90 000 000 00 00	info@malkara.bel.tr	Malkara Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656060633	550e8400-e29b-41d4-a716-446655440050	Acıgöl	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	acıgöl.bel.tr	+90 000 000 00 00	info@acıgöl.bel.tr	Acıgöl Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656325898	550e8400-e29b-41d4-a716-446655440034	Büyükçekmece	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	büyükçekmece.bel.tr	+90 000 000 00 00	info@büyükçekmece.bel.tr	Büyükçekmece Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655556129	550e8400-e29b-41d4-a716-446655440009	Sultanhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sultanhisar.bel.tr	+90 000 000 00 00	info@sultanhisar.bel.tr	Sultanhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656140713	550e8400-e29b-41d4-a716-446655440055	Terme	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	terme.bel.tr	+90 000 000 00 00	info@terme.bel.tr	Terme Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656199772	550e8400-e29b-41d4-a716-446655440060	Yeşilyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yeşilyurt.bel.tr	+90 000 000 00 00	info@yeşilyurt.bel.tr	Yeşilyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656379952	550e8400-e29b-41d4-a716-446655440035	Çiğli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çiğli.bel.tr	+90 000 000 00 00	info@çiğli.bel.tr	Çiğli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655731304	550e8400-e29b-41d4-a716-446655440024	Tercan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tercan.bel.tr	+90 000 000 00 00	info@tercan.bel.tr	Tercan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655998571	550e8400-e29b-41d4-a716-446655440044	Pütürge	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pütürge.bel.tr	+90 000 000 00 00	info@pütürge.bel.tr	Pütürge Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656055628	550e8400-e29b-41d4-a716-446655440049	Hasköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hasköy.bel.tr	+90 000 000 00 00	info@hasköy.bel.tr	Hasköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655743316	550e8400-e29b-41d4-a716-446655440025	Oltu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	oltu.bel.tr	+90 000 000 00 00	info@oltu.bel.tr	Oltu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656143716	550e8400-e29b-41d4-a716-446655440055	Çarşamba	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çarşamba.bel.tr	+90 000 000 00 00	info@çarşamba.bel.tr	Çarşamba Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656332905	550e8400-e29b-41d4-a716-446655440034	Kadıköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kadıköy.bel.tr	+90 000 000 00 00	info@kadıköy.bel.tr	Kadıköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655536109	550e8400-e29b-41d4-a716-446655440008	Arhavi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arhavi.bel.tr	+90 000 000 00 00	info@arhavi.bel.tr	Arhavi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655612185	550e8400-e29b-41d4-a716-446655440012	Genç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	genç.bel.tr	+90 000 000 00 00	info@genç.bel.tr	Genç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655668241	550e8400-e29b-41d4-a716-446655440020	Buldan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	buldan.bel.tr	+90 000 000 00 00	info@buldan.bel.tr	Buldan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440006	550e8400-e29b-41d4-a716-446655440001	Kozan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kozan.bel.tr	+90 000 000 00 00	info@kozan.bel.tr	Kozan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655553126	550e8400-e29b-41d4-a716-446655440009	Kuşadası	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kuşadası.bel.tr	+90 000 000 00 00	info@kuşadası.bel.tr	Kuşadası Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655717290	550e8400-e29b-41d4-a716-446655440023	Ağın	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ağın.bel.tr	+90 000 000 00 00	info@ağın.bel.tr	Ağın Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656294867	550e8400-e29b-41d4-a716-446655440018	Yapraklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yapraklı.bel.tr	+90 000 000 00 00	info@yapraklı.bel.tr	Yapraklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656201774	550e8400-e29b-41d4-a716-446655440061	Akçaabat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akçaabat.bel.tr	+90 000 000 00 00	info@akçaabat.bel.tr	Akçaabat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656232805	550e8400-e29b-41d4-a716-446655440064	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655518091	550e8400-e29b-41d4-a716-446655440007	Gündoğmuş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gündoğmuş.bel.tr	+90 000 000 00 00	info@gündoğmuş.bel.tr	Gündoğmuş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656004577	550e8400-e29b-41d4-a716-446655440045	Demirci	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	demirci.bel.tr	+90 000 000 00 00	info@demirci.bel.tr	Demirci Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655471044	550e8400-e29b-41d4-a716-446655440068	Ağaçören	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ağaçören.bel.tr	+90 000 000 00 00	info@ağaçören.bel.tr	Ağaçören Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655713286	550e8400-e29b-41d4-a716-446655440022	Uzunköprü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	uzunköprü.bel.tr	+90 000 000 00 00	info@uzunköprü.bel.tr	Uzunköprü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655503076	550e8400-e29b-41d4-a716-446655440006	Pursaklar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pursaklar.bel.tr	+90 000 000 00 00	info@pursaklar.bel.tr	Pursaklar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656394967	550e8400-e29b-41d4-a716-446655440073	Beytüşşebap	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beytüşşebap.bel.tr	+90 000 000 00 00	info@beytüşşebap.bel.tr	Beytüşşebap Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656309882	550e8400-e29b-41d4-a716-446655440019	Uğurludağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	uğurludağ.bel.tr	+90 000 000 00 00	info@uğurludağ.bel.tr	Uğurludağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655609182	550e8400-e29b-41d4-a716-446655440011	İnhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	inhisar.bel.tr	+90 000 000 00 00	info@inhisar.bel.tr	İnhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655921494	550e8400-e29b-41d4-a716-446655440042	Akören	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akören.bel.tr	+90 000 000 00 00	info@akören.bel.tr	Akören Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656274847	550e8400-e29b-41d4-a716-446655440017	Ayvacık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ayvacık.bel.tr	+90 000 000 00 00	info@ayvacık.bel.tr	Ayvacık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656116689	550e8400-e29b-41d4-a716-446655440054	Ferizli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ferizli.bel.tr	+90 000 000 00 00	info@ferizli.bel.tr	Ferizli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655673246	550e8400-e29b-41d4-a716-446655440020	Pamukkale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pamukkale.bel.tr	+90 000 000 00 00	info@pamukkale.bel.tr	Pamukkale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655710283	550e8400-e29b-41d4-a716-446655440022	Lalapaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	lalapaşa.bel.tr	+90 000 000 00 00	info@lalapaşa.bel.tr	Lalapaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655721294	550e8400-e29b-41d4-a716-446655440023	Keban	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keban.bel.tr	+90 000 000 00 00	info@keban.bel.tr	Keban Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655524097	550e8400-e29b-41d4-a716-446655440007	Kumluca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kumluca.bel.tr	+90 000 000 00 00	info@kumluca.bel.tr	Kumluca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655805378	550e8400-e29b-41d4-a716-446655440031	Altınözü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altınözü.bel.tr	+90 000 000 00 00	info@altınözü.bel.tr	Altınözü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656120693	550e8400-e29b-41d4-a716-446655440054	Karasu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karasu.bel.tr	+90 000 000 00 00	info@karasu.bel.tr	Karasu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656051624	550e8400-e29b-41d4-a716-446655440048	Seydikemer	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	seydikemer.bel.tr	+90 000 000 00 00	info@seydikemer.bel.tr	Seydikemer Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656084657	550e8400-e29b-41d4-a716-446655440052	Kumru	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kumru.bel.tr	+90 000 000 00 00	info@kumru.bel.tr	Kumru Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655476049	550e8400-e29b-41d4-a716-446655440068	Sarıyahşi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıyahşi.bel.tr	+90 000 000 00 00	info@sarıyahşi.bel.tr	Sarıyahşi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656085658	550e8400-e29b-41d4-a716-446655440052	Mesudiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mesudiye.bel.tr	+90 000 000 00 00	info@mesudiye.bel.tr	Mesudiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655839412	550e8400-e29b-41d4-a716-446655440046	Dulkadiroğlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dulkadiroğlu.bel.tr	+90 000 000 00 00	info@dulkadiroğlu.bel.tr	Dulkadiroğlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656331904	550e8400-e29b-41d4-a716-446655440034	Güngören	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güngören.bel.tr	+90 000 000 00 00	info@güngören.bel.tr	Güngören Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655754327	550e8400-e29b-41d4-a716-446655440025	Şenkaya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şenkaya.bel.tr	+90 000 000 00 00	info@şenkaya.bel.tr	Şenkaya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656095668	550e8400-e29b-41d4-a716-446655440080	Hasanbeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hasanbeyli.bel.tr	+90 000 000 00 00	info@hasanbeyli.bel.tr	Hasanbeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655584157	550e8400-e29b-41d4-a716-446655440010	Marmara	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	marmara.bel.tr	+90 000 000 00 00	info@marmara.bel.tr	Marmara Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655951524	550e8400-e29b-41d4-a716-446655440043	Altıntaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altıntaş.bel.tr	+90 000 000 00 00	info@altıntaş.bel.tr	Altıntaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655703276	550e8400-e29b-41d4-a716-446655440081	Kaynaşlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kaynaşlı.bel.tr	+90 000 000 00 00	info@kaynaşlı.bel.tr	Kaynaşlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655856429	550e8400-e29b-41d4-a716-446655440070	Ermenek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ermenek.bel.tr	+90 000 000 00 00	info@ermenek.bel.tr	Ermenek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655501074	550e8400-e29b-41d4-a716-446655440006	Nallıhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nallıhan.bel.tr	+90 000 000 00 00	info@nallıhan.bel.tr	Nallıhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656206779	550e8400-e29b-41d4-a716-446655440061	Düzköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	düzköy.bel.tr	+90 000 000 00 00	info@düzköy.bel.tr	Düzköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656113686	550e8400-e29b-41d4-a716-446655440054	Akyazı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akyazı.bel.tr	+90 000 000 00 00	info@akyazı.bel.tr	Akyazı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656233806	550e8400-e29b-41d4-a716-446655440065	Bahçesaray	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bahçesaray.bel.tr	+90 000 000 00 00	info@bahçesaray.bel.tr	Bahçesaray Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656137710	550e8400-e29b-41d4-a716-446655440055	Ondokuzmayıs	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ondokuzmayıs.bel.tr	+90 000 000 00 00	info@ondokuzmayıs.bel.tr	Ondokuzmayıs Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655477050	550e8400-e29b-41d4-a716-446655440068	Sultanhanı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sultanhanı.bel.tr	+90 000 000 00 00	info@sultanhanı.bel.tr	Sultanhanı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655746319	550e8400-e29b-41d4-a716-446655440025	Pasinler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pasinler.bel.tr	+90 000 000 00 00	info@pasinler.bel.tr	Pasinler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655745318	550e8400-e29b-41d4-a716-446655440025	Palandöken	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	palandöken.bel.tr	+90 000 000 00 00	info@palandöken.bel.tr	Palandöken Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655800373	550e8400-e29b-41d4-a716-446655440030	Derecik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derecik.bel.tr	+90 000 000 00 00	info@derecik.bel.tr	Derecik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656348921	550e8400-e29b-41d4-a716-446655440034	Üsküdar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	üsküdar.bel.tr	+90 000 000 00 00	info@üsküdar.bel.tr	Üsküdar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655765338	550e8400-e29b-41d4-a716-446655440026	Sivrihisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sivrihisar.bel.tr	+90 000 000 00 00	info@sivrihisar.bel.tr	Sivrihisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656076649	550e8400-e29b-41d4-a716-446655440052	Aybastı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aybastı.bel.tr	+90 000 000 00 00	info@aybastı.bel.tr	Aybastı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655773346	550e8400-e29b-41d4-a716-446655440027	Oğuzeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	oğuzeli.bel.tr	+90 000 000 00 00	info@oğuzeli.bel.tr	Oğuzeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656347920	550e8400-e29b-41d4-a716-446655440034	Ümraniye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ümraniye.bel.tr	+90 000 000 00 00	info@ümraniye.bel.tr	Ümraniye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656069642	550e8400-e29b-41d4-a716-446655440051	Bor	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bor.bel.tr	+90 000 000 00 00	info@bor.bel.tr	Bor Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655504077	550e8400-e29b-41d4-a716-446655440006	Sincan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sincan.bel.tr	+90 000 000 00 00	info@sincan.bel.tr	Sincan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655701274	550e8400-e29b-41d4-a716-446655440081	Gölyaka	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölyaka.bel.tr	+90 000 000 00 00	info@gölyaka.bel.tr	Gölyaka Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655720293	550e8400-e29b-41d4-a716-446655440023	Karakoçan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karakoçan.bel.tr	+90 000 000 00 00	info@karakoçan.bel.tr	Karakoçan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656300873	550e8400-e29b-41d4-a716-446655440019	Boğazkale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	boğazkale.bel.tr	+90 000 000 00 00	info@boğazkale.bel.tr	Boğazkale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656282855	550e8400-e29b-41d4-a716-446655440017	Lapseki	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	lapseki.bel.tr	+90 000 000 00 00	info@lapseki.bel.tr	Lapseki Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656246819	550e8400-e29b-41d4-a716-446655440077	Altınova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altınova.bel.tr	+90 000 000 00 00	info@altınova.bel.tr	Altınova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656319892	550e8400-e29b-41d4-a716-446655440034	Bağcılar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bağcılar.bel.tr	+90 000 000 00 00	info@bağcılar.bel.tr	Bağcılar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655982555	550e8400-e29b-41d4-a716-446655440040	Akçakent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akçakent.bel.tr	+90 000 000 00 00	info@akçakent.bel.tr	Akçakent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656307880	550e8400-e29b-41d4-a716-446655440019	Oğuzlar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	oğuzlar.bel.tr	+90 000 000 00 00	info@oğuzlar.bel.tr	Oğuzlar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655473046	550e8400-e29b-41d4-a716-446655440068	Gülağaç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gülağaç.bel.tr	+90 000 000 00 00	info@gülağaç.bel.tr	Gülağaç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656235808	550e8400-e29b-41d4-a716-446655440065	Edremit	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	edremit.bel.tr	+90 000 000 00 00	info@edremit.bel.tr	Edremit Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656316889	550e8400-e29b-41d4-a716-446655440034	Bahçelievler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bahçelievler.bel.tr	+90 000 000 00 00	info@bahçelievler.bel.tr	Bahçelievler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655468041	550e8400-e29b-41d4-a716-446655440003	İscehisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	iscehisar.bel.tr	+90 000 000 00 00	info@iscehisar.bel.tr	İscehisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656081654	550e8400-e29b-41d4-a716-446655440052	Kabadüz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kabadüz.bel.tr	+90 000 000 00 00	info@kabadüz.bel.tr	Kabadüz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655872445	550e8400-e29b-41d4-a716-446655440037	Bozkurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozkurt.bel.tr	+90 000 000 00 00	info@bozkurt.bel.tr	Bozkurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656305878	550e8400-e29b-41d4-a716-446655440019	Ortaköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ortaköy.bel.tr	+90 000 000 00 00	info@ortaköy.bel.tr	Ortaköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656250823	550e8400-e29b-41d4-a716-446655440077	Çiftlikköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çiftlikköy.bel.tr	+90 000 000 00 00	info@çiftlikköy.bel.tr	Çiftlikköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655947520	550e8400-e29b-41d4-a716-446655440042	Yalıhüyük	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yalıhüyük.bel.tr	+90 000 000 00 00	info@yalıhüyük.bel.tr	Yalıhüyük Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655604177	550e8400-e29b-41d4-a716-446655440011	Gölpazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölpazarı.bel.tr	+90 000 000 00 00	info@gölpazarı.bel.tr	Gölpazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655870443	550e8400-e29b-41d4-a716-446655440037	Azdavay	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	azdavay.bel.tr	+90 000 000 00 00	info@azdavay.bel.tr	Azdavay Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655955528	550e8400-e29b-41d4-a716-446655440043	Emet	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	emet.bel.tr	+90 000 000 00 00	info@emet.bel.tr	Emet Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656011584	550e8400-e29b-41d4-a716-446655440045	Saruhanlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	saruhanlı.bel.tr	+90 000 000 00 00	info@saruhanlı.bel.tr	Saruhanlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655893466	550e8400-e29b-41d4-a716-446655440038	Kocasinan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kocasinan.bel.tr	+90 000 000 00 00	info@kocasinan.bel.tr	Kocasinan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656086659	550e8400-e29b-41d4-a716-446655440052	Perşembe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	perşembe.bel.tr	+90 000 000 00 00	info@perşembe.bel.tr	Perşembe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656169742	550e8400-e29b-41d4-a716-446655440058	Kangal	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kangal.bel.tr	+90 000 000 00 00	info@kangal.bel.tr	Kangal Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656355928	550e8400-e29b-41d4-a716-446655440035	Bergama	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bergama.bel.tr	+90 000 000 00 00	info@bergama.bel.tr	Bergama Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655687260	550e8400-e29b-41d4-a716-446655440021	Hazro	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hazro.bel.tr	+90 000 000 00 00	info@hazro.bel.tr	Hazro Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655669242	550e8400-e29b-41d4-a716-446655440020	Güney	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güney.bel.tr	+90 000 000 00 00	info@güney.bel.tr	Güney Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655864437	550e8400-e29b-41d4-a716-446655440036	Kağızman	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kağızman.bel.tr	+90 000 000 00 00	info@kağızman.bel.tr	Kağızman Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655624197	550e8400-e29b-41d4-a716-446655440013	Tatvan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tatvan.bel.tr	+90 000 000 00 00	info@tatvan.bel.tr	Tatvan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656297870	550e8400-e29b-41d4-a716-446655440018	Şabanözü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şabanözü.bel.tr	+90 000 000 00 00	info@şabanözü.bel.tr	Şabanözü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655917490	550e8400-e29b-41d4-a716-446655440041	Körfez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	körfez.bel.tr	+90 000 000 00 00	info@körfez.bel.tr	Körfez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655987560	550e8400-e29b-41d4-a716-446655440040	Çiçekdağı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çiçekdağı.bel.tr	+90 000 000 00 00	info@çiçekdağı.bel.tr	Çiçekdağı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655954527	550e8400-e29b-41d4-a716-446655440043	Dumlupınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dumlupınar.bel.tr	+90 000 000 00 00	info@dumlupınar.bel.tr	Dumlupınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656080653	550e8400-e29b-41d4-a716-446655440052	Gürgentepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gürgentepe.bel.tr	+90 000 000 00 00	info@gürgentepe.bel.tr	Gürgentepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655526099	550e8400-e29b-41d4-a716-446655440007	Muratpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	muratpaşa.bel.tr	+90 000 000 00 00	info@muratpaşa.bel.tr	Muratpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656149722	550e8400-e29b-41d4-a716-446655440056	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655644217	550e8400-e29b-41d4-a716-446655440015	Çeltikçi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çeltikçi.bel.tr	+90 000 000 00 00	info@çeltikçi.bel.tr	Çeltikçi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655520093	550e8400-e29b-41d4-a716-446655440007	Kemer	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kemer.bel.tr	+90 000 000 00 00	info@kemer.bel.tr	Kemer Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656165738	550e8400-e29b-41d4-a716-446655440058	Gemerek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gemerek.bel.tr	+90 000 000 00 00	info@gemerek.bel.tr	Gemerek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656100673	550e8400-e29b-41d4-a716-446655440053	Ardeşen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ardeşen.bel.tr	+90 000 000 00 00	info@ardeşen.bel.tr	Ardeşen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655744317	550e8400-e29b-41d4-a716-446655440025	Olur	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	olur.bel.tr	+90 000 000 00 00	info@olur.bel.tr	Olur Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655833406	550e8400-e29b-41d4-a716-446655440076	Aralık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aralık.bel.tr	+90 000 000 00 00	info@aralık.bel.tr	Aralık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656054627	550e8400-e29b-41d4-a716-446655440049	Bulanık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bulanık.bel.tr	+90 000 000 00 00	info@bulanık.bel.tr	Bulanık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656324897	550e8400-e29b-41d4-a716-446655440034	Beşiktaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beşiktaş.bel.tr	+90 000 000 00 00	info@beşiktaş.bel.tr	Beşiktaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655533106	550e8400-e29b-41d4-a716-446655440075	Posof	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	posof.bel.tr	+90 000 000 00 00	info@posof.bel.tr	Posof Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655830403	550e8400-e29b-41d4-a716-446655440032	Yalvaç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yalvaç.bel.tr	+90 000 000 00 00	info@yalvaç.bel.tr	Yalvaç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440009	550e8400-e29b-41d4-a716-446655440001	Sarıçam	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıçam.bel.tr	+90 000 000 00 00	info@sarıçam.bel.tr	Sarıçam Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655993566	550e8400-e29b-41d4-a716-446655440044	Doğanyol	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğanyol.bel.tr	+90 000 000 00 00	info@doğanyol.bel.tr	Doğanyol Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655900473	550e8400-e29b-41d4-a716-446655440038	Yahyalı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yahyalı.bel.tr	+90 000 000 00 00	info@yahyalı.bel.tr	Yahyalı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656268841	550e8400-e29b-41d4-a716-446655440067	Ereğli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ereğli.bel.tr	+90 000 000 00 00	info@ereğli.bel.tr	Ereğli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655796369	550e8400-e29b-41d4-a716-446655440029	Köse	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	köse.bel.tr	+90 000 000 00 00	info@köse.bel.tr	Köse Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655535108	550e8400-e29b-41d4-a716-446655440008	Ardanuç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ardanuç.bel.tr	+90 000 000 00 00	info@ardanuç.bel.tr	Ardanuç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656125698	550e8400-e29b-41d4-a716-446655440054	Serdivan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	serdivan.bel.tr	+90 000 000 00 00	info@serdivan.bel.tr	Serdivan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656117690	550e8400-e29b-41d4-a716-446655440054	Geyve	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	geyve.bel.tr	+90 000 000 00 00	info@geyve.bel.tr	Geyve Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656260833	550e8400-e29b-41d4-a716-446655440066	Yerköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yerköy.bel.tr	+90 000 000 00 00	info@yerköy.bel.tr	Yerköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656225798	550e8400-e29b-41d4-a716-446655440062	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656204777	550e8400-e29b-41d4-a716-446655440061	Beşikdüzü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beşikdüzü.bel.tr	+90 000 000 00 00	info@beşikdüzü.bel.tr	Beşikdüzü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655728301	550e8400-e29b-41d4-a716-446655440024	Kemaliye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kemaliye.bel.tr	+90 000 000 00 00	info@kemaliye.bel.tr	Kemaliye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655528101	550e8400-e29b-41d4-a716-446655440007	İbradı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ibradı.bel.tr	+90 000 000 00 00	info@ibradı.bel.tr	İbradı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656187760	550e8400-e29b-41d4-a716-446655440059	Çorlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çorlu.bel.tr	+90 000 000 00 00	info@çorlu.bel.tr	Çorlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656244817	550e8400-e29b-41d4-a716-446655440065	Özalp	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	özalp.bel.tr	+90 000 000 00 00	info@özalp.bel.tr	Özalp Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656197770	550e8400-e29b-41d4-a716-446655440060	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655708281	550e8400-e29b-41d4-a716-446655440022	Havsa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	havsa.bel.tr	+90 000 000 00 00	info@havsa.bel.tr	Havsa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655733306	550e8400-e29b-41d4-a716-446655440024	Üzümlü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	üzümlü.bel.tr	+90 000 000 00 00	info@üzümlü.bel.tr	Üzümlü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655725298	550e8400-e29b-41d4-a716-446655440023	Sivrice	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sivrice.bel.tr	+90 000 000 00 00	info@sivrice.bel.tr	Sivrice Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656153726	550e8400-e29b-41d4-a716-446655440057	Boyabat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	boyabat.bel.tr	+90 000 000 00 00	info@boyabat.bel.tr	Boyabat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656261834	550e8400-e29b-41d4-a716-446655440066	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655789362	550e8400-e29b-41d4-a716-446655440028	Tirebolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tirebolu.bel.tr	+90 000 000 00 00	info@tirebolu.bel.tr	Tirebolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656050623	550e8400-e29b-41d4-a716-446655440048	Ortaca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ortaca.bel.tr	+90 000 000 00 00	info@ortaca.bel.tr	Ortaca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655759332	550e8400-e29b-41d4-a716-446655440026	Mahmudiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mahmudiye.bel.tr	+90 000 000 00 00	info@mahmudiye.bel.tr	Mahmudiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655942515	550e8400-e29b-41d4-a716-446655440042	Sarayönü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarayönü.bel.tr	+90 000 000 00 00	info@sarayönü.bel.tr	Sarayönü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655727300	550e8400-e29b-41d4-a716-446655440024	Kemah	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kemah.bel.tr	+90 000 000 00 00	info@kemah.bel.tr	Kemah Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655458031	550e8400-e29b-41d4-a716-446655440003	Emirdağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	emirdağ.bel.tr	+90 000 000 00 00	info@emirdağ.bel.tr	Emirdağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656314887	550e8400-e29b-41d4-a716-446655440034	Ataşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ataşehir.bel.tr	+90 000 000 00 00	info@ataşehir.bel.tr	Ataşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655861434	550e8400-e29b-41d4-a716-446655440036	Arpaçay	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arpaçay.bel.tr	+90 000 000 00 00	info@arpaçay.bel.tr	Arpaçay Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655981554	550e8400-e29b-41d4-a716-446655440040	Akpınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akpınar.bel.tr	+90 000 000 00 00	info@akpınar.bel.tr	Akpınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656176749	550e8400-e29b-41d4-a716-446655440058	İmranlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	imranlı.bel.tr	+90 000 000 00 00	info@imranlı.bel.tr	İmranlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656239812	550e8400-e29b-41d4-a716-446655440065	Muradiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	muradiye.bel.tr	+90 000 000 00 00	info@muradiye.bel.tr	Muradiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656092665	550e8400-e29b-41d4-a716-446655440052	İkizce	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ikizce.bel.tr	+90 000 000 00 00	info@ikizce.bel.tr	İkizce Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655491064	550e8400-e29b-41d4-a716-446655440006	Etimesgut	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	etimesgut.bel.tr	+90 000 000 00 00	info@etimesgut.bel.tr	Etimesgut Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656257830	550e8400-e29b-41d4-a716-446655440066	Sarıkaya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıkaya.bel.tr	+90 000 000 00 00	info@sarıkaya.bel.tr	Sarıkaya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655774347	550e8400-e29b-41d4-a716-446655440027	Yavuzeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yavuzeli.bel.tr	+90 000 000 00 00	info@yavuzeli.bel.tr	Yavuzeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656329902	550e8400-e29b-41d4-a716-446655440034	Fatih	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	fatih.bel.tr	+90 000 000 00 00	info@fatih.bel.tr	Fatih Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655548121	550e8400-e29b-41d4-a716-446655440009	Germencik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	germencik.bel.tr	+90 000 000 00 00	info@germencik.bel.tr	Germencik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656352925	550e8400-e29b-41d4-a716-446655440035	Balçova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	balçova.bel.tr	+90 000 000 00 00	info@balçova.bel.tr	Balçova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655488061	550e8400-e29b-41d4-a716-446655440006	Bala	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bala.bel.tr	+90 000 000 00 00	info@bala.bel.tr	Bala Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656272845	550e8400-e29b-41d4-a716-446655440067	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656177750	550e8400-e29b-41d4-a716-446655440058	Şarkışla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şarkışla.bel.tr	+90 000 000 00 00	info@şarkışla.bel.tr	Şarkışla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655778351	550e8400-e29b-41d4-a716-446655440028	Alucra	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alucra.bel.tr	+90 000 000 00 00	info@alucra.bel.tr	Alucra Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656380953	550e8400-e29b-41d4-a716-446655440035	Ödemiş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ödemiş.bel.tr	+90 000 000 00 00	info@ödemiş.bel.tr	Ödemiş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655724297	550e8400-e29b-41d4-a716-446655440023	Palu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	palu.bel.tr	+90 000 000 00 00	info@palu.bel.tr	Palu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655938511	550e8400-e29b-41d4-a716-446655440042	Karapınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karapınar.bel.tr	+90 000 000 00 00	info@karapınar.bel.tr	Karapınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656359932	550e8400-e29b-41d4-a716-446655440035	Dikili	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dikili.bel.tr	+90 000 000 00 00	info@dikili.bel.tr	Dikili Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656286859	550e8400-e29b-41d4-a716-446655440018	Atkaracalar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	atkaracalar.bel.tr	+90 000 000 00 00	info@atkaracalar.bel.tr	Atkaracalar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656195768	550e8400-e29b-41d4-a716-446655440060	Reşadiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	reşadiye.bel.tr	+90 000 000 00 00	info@reşadiye.bel.tr	Reşadiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656222795	550e8400-e29b-41d4-a716-446655440062	Ovacık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ovacık.bel.tr	+90 000 000 00 00	info@ovacık.bel.tr	Ovacık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656290863	550e8400-e29b-41d4-a716-446655440018	Korgun	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	korgun.bel.tr	+90 000 000 00 00	info@korgun.bel.tr	Korgun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656128701	550e8400-e29b-41d4-a716-446655440055	Alaçam	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alaçam.bel.tr	+90 000 000 00 00	info@alaçam.bel.tr	Alaçam Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655655228	550e8400-e29b-41d4-a716-446655440016	Orhaneli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	orhaneli.bel.tr	+90 000 000 00 00	info@orhaneli.bel.tr	Orhaneli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656264837	550e8400-e29b-41d4-a716-446655440066	Çekerek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çekerek.bel.tr	+90 000 000 00 00	info@çekerek.bel.tr	Çekerek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656270843	550e8400-e29b-41d4-a716-446655440067	Kilimli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kilimli.bel.tr	+90 000 000 00 00	info@kilimli.bel.tr	Kilimli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655999572	550e8400-e29b-41d4-a716-446655440044	Yazıhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yazıhan.bel.tr	+90 000 000 00 00	info@yazıhan.bel.tr	Yazıhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656033606	550e8400-e29b-41d4-a716-446655440033	Gülnar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gülnar.bel.tr	+90 000 000 00 00	info@gülnar.bel.tr	Gülnar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655949522	550e8400-e29b-41d4-a716-446655440042	Çeltik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çeltik.bel.tr	+90 000 000 00 00	info@çeltik.bel.tr	Çeltik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656071644	550e8400-e29b-41d4-a716-446655440051	Ulukışla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ulukışla.bel.tr	+90 000 000 00 00	info@ulukışla.bel.tr	Ulukışla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440010	550e8400-e29b-41d4-a716-446655440001	Seyhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	http://.bel.tr	+90 000 000 00 00	info@seyhan.bel.tr	Seyhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	CHP	https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Cumhuriyet_Halk_Partisi_Logo.svg/200px-Cumhuriyet_Halk_Partisi_Logo.svg.png	0	{}	ilçe	46a4359e-86a1-4974-b022-a4532367aa5e	\N	5	1	1	33.33	2025-05-22 14:37:02.590141+00
660e8400-e29b-41d4-a716-446656155728	550e8400-e29b-41d4-a716-446655440057	Durağan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	durağan.bel.tr	+90 000 000 00 00	info@durağan.bel.tr	Durağan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655542115	550e8400-e29b-41d4-a716-446655440008	Yusufeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yusufeli.bel.tr	+90 000 000 00 00	info@yusufeli.bel.tr	Yusufeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656029602	550e8400-e29b-41d4-a716-446655440033	Anamur	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	anamur.bel.tr	+90 000 000 00 00	info@anamur.bel.tr	Anamur Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656146719	550e8400-e29b-41d4-a716-446655440056	Eruh	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eruh.bel.tr	+90 000 000 00 00	info@eruh.bel.tr	Eruh Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656175748	550e8400-e29b-41d4-a716-446655440058	Zara	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	zara.bel.tr	+90 000 000 00 00	info@zara.bel.tr	Zara Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656343916	550e8400-e29b-41d4-a716-446655440034	Tuzla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tuzla.bel.tr	+90 000 000 00 00	info@tuzla.bel.tr	Tuzla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656043616	550e8400-e29b-41d4-a716-446655440048	Datça	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	datça.bel.tr	+90 000 000 00 00	info@datça.bel.tr	Datça Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655852425	550e8400-e29b-41d4-a716-446655440078	Safranbolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	safranbolu.bel.tr	+90 000 000 00 00	info@safranbolu.bel.tr	Safranbolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656334907	550e8400-e29b-41d4-a716-446655440034	Kâğıthane	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kâğıthane.bel.tr	+90 000 000 00 00	info@kâğıthane.bel.tr	Kâğıthane Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655808381	550e8400-e29b-41d4-a716-446655440031	Belen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	belen.bel.tr	+90 000 000 00 00	info@belen.bel.tr	Belen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655730303	550e8400-e29b-41d4-a716-446655440024	Refahiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	refahiye.bel.tr	+90 000 000 00 00	info@refahiye.bel.tr	Refahiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656273846	550e8400-e29b-41d4-a716-446655440067	Çaycuma	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çaycuma.bel.tr	+90 000 000 00 00	info@çaycuma.bel.tr	Çaycuma Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655451024	550e8400-e29b-41d4-a716-446655440002	Çelikhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çelikhan.bel.tr	+90 000 000 00 00	info@çelikhan.bel.tr	Çelikhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656151724	550e8400-e29b-41d4-a716-446655440056	Şirvan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şirvan.bel.tr	+90 000 000 00 00	info@şirvan.bel.tr	Şirvan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655918491	550e8400-e29b-41d4-a716-446655440041	Çayırova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çayırova.bel.tr	+90 000 000 00 00	info@çayırova.bel.tr	Çayırova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655662235	550e8400-e29b-41d4-a716-446655440020	Acıpayam	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	acıpayam.bel.tr	+90 000 000 00 00	info@acıpayam.bel.tr	Acıpayam Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655484057	550e8400-e29b-41d4-a716-446655440005	Taşova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	taşova.bel.tr	+90 000 000 00 00	info@taşova.bel.tr	Taşova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655530103	550e8400-e29b-41d4-a716-446655440075	Damal	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	damal.bel.tr	+90 000 000 00 00	info@damal.bel.tr	Damal Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655633206	550e8400-e29b-41d4-a716-446655440014	Yeniçağa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yeniçağa.bel.tr	+90 000 000 00 00	info@yeniçağa.bel.tr	Yeniçağa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655990563	550e8400-e29b-41d4-a716-446655440044	Arguvan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arguvan.bel.tr	+90 000 000 00 00	info@arguvan.bel.tr	Arguvan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656356929	550e8400-e29b-41d4-a716-446655440035	Beydağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beydağ.bel.tr	+90 000 000 00 00	info@beydağ.bel.tr	Beydağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656058631	550e8400-e29b-41d4-a716-446655440049	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656351924	550e8400-e29b-41d4-a716-446655440035	Aliağa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aliağa.bel.tr	+90 000 000 00 00	info@aliağa.bel.tr	Aliağa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655638211	550e8400-e29b-41d4-a716-446655440015	Gölhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölhisar.bel.tr	+90 000 000 00 00	info@gölhisar.bel.tr	Gölhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655684257	550e8400-e29b-41d4-a716-446655440021	Ergani	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ergani.bel.tr	+90 000 000 00 00	info@ergani.bel.tr	Ergani Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655653226	550e8400-e29b-41d4-a716-446655440016	Mustafakemalpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mustafakemalpaşa.bel.tr	+90 000 000 00 00	info@mustafakemalpaşa.bel.tr	Mustafakemalpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655769342	550e8400-e29b-41d4-a716-446655440027	Araban	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	araban.bel.tr	+90 000 000 00 00	info@araban.bel.tr	Araban Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656002575	550e8400-e29b-41d4-a716-446655440045	Akhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akhisar.bel.tr	+90 000 000 00 00	info@akhisar.bel.tr	Akhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655706279	550e8400-e29b-41d4-a716-446655440022	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	AKP	https://upload-wikimedia-org.translate.goog/wikipedia/en/thumb/5/56/Justice_and_Development_Party_%28Turkey%29_logo.svg/225px-Justice_and_Development_Party_%28Turkey%29_logo.svg.png?_x_tr_sl=en&_x_tr_tl=tr&_x_tr_hl=tr&_x_tr_pto=tc	0	{}	ilçe	448575ce-7444-4bd7-8070-1753a8ecb16b	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656224797	550e8400-e29b-41d4-a716-446655440062	Pülümür	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pülümür.bel.tr	+90 000 000 00 00	info@pülümür.bel.tr	Pülümür Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656094667	550e8400-e29b-41d4-a716-446655440080	Düziçi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	düziçi.bel.tr	+90 000 000 00 00	info@düziçi.bel.tr	Düziçi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655628201	550e8400-e29b-41d4-a716-446655440014	Göynük	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	göynük.bel.tr	+90 000 000 00 00	info@göynük.bel.tr	Göynük Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655578151	550e8400-e29b-41d4-a716-446655440010	Gömeç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gömeç.bel.tr	+90 000 000 00 00	info@gömeç.bel.tr	Gömeç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656052625	550e8400-e29b-41d4-a716-446655440048	Ula	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ula.bel.tr	+90 000 000 00 00	info@ula.bel.tr	Ula Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656349922	550e8400-e29b-41d4-a716-446655440034	Şile	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şile.bel.tr	+90 000 000 00 00	info@şile.bel.tr	Şile Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656097670	550e8400-e29b-41d4-a716-446655440080	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656039612	550e8400-e29b-41d4-a716-446655440033	Yenişehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenişehir.bel.tr	+90 000 000 00 00	info@yenişehir.bel.tr	Yenişehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655640213	550e8400-e29b-41d4-a716-446655440015	Kemer	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kemer.bel.tr	+90 000 000 00 00	info@kemer.bel.tr	Kemer Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656098671	550e8400-e29b-41d4-a716-446655440080	Sumbas	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sumbas.bel.tr	+90 000 000 00 00	info@sumbas.bel.tr	Sumbas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655854427	550e8400-e29b-41d4-a716-446655440070	Ayrancı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ayrancı.bel.tr	+90 000 000 00 00	info@ayrancı.bel.tr	Ayrancı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656109682	550e8400-e29b-41d4-a716-446655440053	Çayeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çayeli.bel.tr	+90 000 000 00 00	info@çayeli.bel.tr	Çayeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655914487	550e8400-e29b-41d4-a716-446655440041	Kandıra	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kandıra.bel.tr	+90 000 000 00 00	info@kandıra.bel.tr	Kandıra Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655632205	550e8400-e29b-41d4-a716-446655440014	Seben	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	seben.bel.tr	+90 000 000 00 00	info@seben.bel.tr	Seben Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655557130	550e8400-e29b-41d4-a716-446655440009	Söke	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	söke.bel.tr	+90 000 000 00 00	info@söke.bel.tr	Söke Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655678251	550e8400-e29b-41d4-a716-446655440020	Çameli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çameli.bel.tr	+90 000 000 00 00	info@çameli.bel.tr	Çameli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656145718	550e8400-e29b-41d4-a716-446655440056	Baykan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	baykan.bel.tr	+90 000 000 00 00	info@baykan.bel.tr	Baykan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656115688	550e8400-e29b-41d4-a716-446655440054	Erenler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erenler.bel.tr	+90 000 000 00 00	info@erenler.bel.tr	Erenler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656057630	550e8400-e29b-41d4-a716-446655440049	Malazgirt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	malazgirt.bel.tr	+90 000 000 00 00	info@malazgirt.bel.tr	Malazgirt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440007	550e8400-e29b-41d4-a716-446655440001	Pozantı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pozantı.bel.tr	+90 000 000 00 00	info@pozantı.bel.tr	Pozantı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655732305	550e8400-e29b-41d4-a716-446655440024	Çayırlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çayırlı.bel.tr	+90 000 000 00 00	info@çayırlı.bel.tr	Çayırlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656112685	550e8400-e29b-41d4-a716-446655440054	Adapazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	adapazarı.bel.tr	+90 000 000 00 00	info@adapazarı.bel.tr	Adapazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655905478	550e8400-e29b-41d4-a716-446655440079	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656221794	550e8400-e29b-41d4-a716-446655440062	Nazımiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nazımiye.bel.tr	+90 000 000 00 00	info@nazımiye.bel.tr	Nazımiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656266839	550e8400-e29b-41d4-a716-446655440067	Alaplı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alaplı.bel.tr	+90 000 000 00 00	info@alaplı.bel.tr	Alaplı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656353926	550e8400-e29b-41d4-a716-446655440035	Bayraklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayraklı.bel.tr	+90 000 000 00 00	info@bayraklı.bel.tr	Bayraklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655857430	550e8400-e29b-41d4-a716-446655440070	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656330903	550e8400-e29b-41d4-a716-446655440034	Gaziosmanpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gaziosmanpaşa.bel.tr	+90 000 000 00 00	info@gaziosmanpaşa.bel.tr	Gaziosmanpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655474047	550e8400-e29b-41d4-a716-446655440068	Güzelyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güzelyurt.bel.tr	+90 000 000 00 00	info@güzelyurt.bel.tr	Güzelyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656281854	550e8400-e29b-41d4-a716-446655440017	Gökçeada	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gökçeada.bel.tr	+90 000 000 00 00	info@gökçeada.bel.tr	Gökçeada Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656220793	550e8400-e29b-41d4-a716-446655440062	Mazgirt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mazgirt.bel.tr	+90 000 000 00 00	info@mazgirt.bel.tr	Mazgirt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655985558	550e8400-e29b-41d4-a716-446655440040	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655450023	550e8400-e29b-41d4-a716-446655440002	Tut	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tut.bel.tr	+90 000 000 00 00	info@tut.bel.tr	Tut Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655798371	550e8400-e29b-41d4-a716-446655440029	Torul	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	torul.bel.tr	+90 000 000 00 00	info@torul.bel.tr	Torul Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440013	550e8400-e29b-41d4-a716-446655440001	Yüreğir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yüreğir.bel.tr	+90 000 000 00 00	info@yüreğir.bel.tr	Yüreğir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656003576	550e8400-e29b-41d4-a716-446655440045	Alaşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alaşehir.bel.tr	+90 000 000 00 00	info@alaşehir.bel.tr	Alaşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656150723	550e8400-e29b-41d4-a716-446655440056	Tillo	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tillo.bel.tr	+90 000 000 00 00	info@tillo.bel.tr	Tillo Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655953526	550e8400-e29b-41d4-a716-446655440043	Domaniç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	domaniç.bel.tr	+90 000 000 00 00	info@domaniç.bel.tr	Domaniç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655514087	550e8400-e29b-41d4-a716-446655440007	Döşemealtı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	döşemealtı.bel.tr	+90 000 000 00 00	info@döşemealtı.bel.tr	Döşemealtı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656141714	550e8400-e29b-41d4-a716-446655440055	Vezirköprü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	vezirköprü.bel.tr	+90 000 000 00 00	info@vezirköprü.bel.tr	Vezirköprü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656059632	550e8400-e29b-41d4-a716-446655440049	Varto	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	varto.bel.tr	+90 000 000 00 00	info@varto.bel.tr	Varto Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656022595	550e8400-e29b-41d4-a716-446655440047	Mazıdağı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mazıdağı.bel.tr	+90 000 000 00 00	info@mazıdağı.bel.tr	Mazıdağı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656016589	550e8400-e29b-41d4-a716-446655440045	Yunusemre	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yunusemre.bel.tr	+90 000 000 00 00	info@yunusemre.bel.tr	Yunusemre Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656196769	550e8400-e29b-41d4-a716-446655440060	Sulusaray	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sulusaray.bel.tr	+90 000 000 00 00	info@sulusaray.bel.tr	Sulusaray Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656056629	550e8400-e29b-41d4-a716-446655440049	Korkut	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	korkut.bel.tr	+90 000 000 00 00	info@korkut.bel.tr	Korkut Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656048621	550e8400-e29b-41d4-a716-446655440048	Menteşe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	menteşe.bel.tr	+90 000 000 00 00	info@menteşe.bel.tr	Menteşe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656364937	550e8400-e29b-41d4-a716-446655440035	Karaburun	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karaburun.bel.tr	+90 000 000 00 00	info@karaburun.bel.tr	Karaburun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655906479	550e8400-e29b-41d4-a716-446655440079	Musabeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	musabeyli.bel.tr	+90 000 000 00 00	info@musabeyli.bel.tr	Musabeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656166739	550e8400-e29b-41d4-a716-446655440058	Gölova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölova.bel.tr	+90 000 000 00 00	info@gölova.bel.tr	Gölova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656361934	550e8400-e29b-41d4-a716-446655440035	Gaziemir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gaziemir.bel.tr	+90 000 000 00 00	info@gaziemir.bel.tr	Gaziemir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655446019	550e8400-e29b-41d4-a716-446655440002	Gölbaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölbaşı.bel.tr	+90 000 000 00 00	info@gölbaşı.bel.tr	Gölbaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656182755	550e8400-e29b-41d4-a716-446655440059	Marmaraereğlisi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	marmaraereğlisi.bel.tr	+90 000 000 00 00	info@marmaraereğlisi.bel.tr	Marmaraereğlisi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656230803	550e8400-e29b-41d4-a716-446655440064	Sivaslı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sivaslı.bel.tr	+90 000 000 00 00	info@sivaslı.bel.tr	Sivaslı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656101674	550e8400-e29b-41d4-a716-446655440053	Derepazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derepazarı.bel.tr	+90 000 000 00 00	info@derepazarı.bel.tr	Derepazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656108681	550e8400-e29b-41d4-a716-446655440053	Çamlıhemşin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çamlıhemşin.bel.tr	+90 000 000 00 00	info@çamlıhemşin.bel.tr	Çamlıhemşin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656107680	550e8400-e29b-41d4-a716-446655440053	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656252825	550e8400-e29b-41d4-a716-446655440066	Akdağmadeni	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akdağmadeni.bel.tr	+90 000 000 00 00	info@akdağmadeni.bel.tr	Akdağmadeni Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656090663	550e8400-e29b-41d4-a716-446655440052	Çaybaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çaybaşı.bel.tr	+90 000 000 00 00	info@çaybaşı.bel.tr	Çaybaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655694267	550e8400-e29b-41d4-a716-446655440021	Yenişehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenişehir.bel.tr	+90 000 000 00 00	info@yenişehir.bel.tr	Yenişehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655803376	550e8400-e29b-41d4-a716-446655440030	Çukurca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çukurca.bel.tr	+90 000 000 00 00	info@çukurca.bel.tr	Çukurca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656162735	550e8400-e29b-41d4-a716-446655440058	Altınyayla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altınyayla.bel.tr	+90 000 000 00 00	info@altınyayla.bel.tr	Altınyayla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655596169	550e8400-e29b-41d4-a716-446655440072	Hasankeyf	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hasankeyf.bel.tr	+90 000 000 00 00	info@hasankeyf.bel.tr	Hasankeyf Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-20 00:16:56.660521+00
660e8400-e29b-41d4-a716-446656231804	550e8400-e29b-41d4-a716-446655440064	Ulubey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ulubey.bel.tr	+90 000 000 00 00	info@ulubey.bel.tr	Ulubey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656168741	550e8400-e29b-41d4-a716-446655440058	Hafik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hafik.bel.tr	+90 000 000 00 00	info@hafik.bel.tr	Hafik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655626199	550e8400-e29b-41d4-a716-446655440014	Dörtdivan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dörtdivan.bel.tr	+90 000 000 00 00	info@dörtdivan.bel.tr	Dörtdivan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656291864	550e8400-e29b-41d4-a716-446655440018	Kurşunlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kurşunlu.bel.tr	+90 000 000 00 00	info@kurşunlu.bel.tr	Kurşunlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655908481	550e8400-e29b-41d4-a716-446655440041	Başiskele	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	başiskele.bel.tr	+90 000 000 00 00	info@başiskele.bel.tr	Başiskele Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656023596	550e8400-e29b-41d4-a716-446655440047	Midyat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	midyat.bel.tr	+90 000 000 00 00	info@midyat.bel.tr	Midyat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655456029	550e8400-e29b-41d4-a716-446655440003	Dazkırı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dazkırı.bel.tr	+90 000 000 00 00	info@dazkırı.bel.tr	Dazkırı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656037610	550e8400-e29b-41d4-a716-446655440033	Tarsus	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tarsus.bel.tr	+90 000 000 00 00	info@tarsus.bel.tr	Tarsus Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655478051	550e8400-e29b-41d4-a716-446655440005	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656308881	550e8400-e29b-41d4-a716-446655440019	Sungurlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sungurlu.bel.tr	+90 000 000 00 00	info@sungurlu.bel.tr	Sungurlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656354927	550e8400-e29b-41d4-a716-446655440035	Bayındır	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayındır.bel.tr	+90 000 000 00 00	info@bayındır.bel.tr	Bayındır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656315888	550e8400-e29b-41d4-a716-446655440034	Avcılar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	avcılar.bel.tr	+90 000 000 00 00	info@avcılar.bel.tr	Avcılar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656293866	550e8400-e29b-41d4-a716-446655440018	Orta	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	orta.bel.tr	+90 000 000 00 00	info@orta.bel.tr	Orta Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655608181	550e8400-e29b-41d4-a716-446655440011	Yenipazar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenipazar.bel.tr	+90 000 000 00 00	info@yenipazar.bel.tr	Yenipazar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440002	550e8400-e29b-41d4-a716-446655440001	Ceyhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ceyhan.bel.tr	+90 000 000 00 00	info@ceyhan.bel.tr	Ceyhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656008581	550e8400-e29b-41d4-a716-446655440045	Köprübaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	köprübaşı.bel.tr	+90 000 000 00 00	info@köprübaşı.bel.tr	Köprübaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656024597	550e8400-e29b-41d4-a716-446655440047	Nusaybin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nusaybin.bel.tr	+90 000 000 00 00	info@nusaybin.bel.tr	Nusaybin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655558131	550e8400-e29b-41d4-a716-446655440009	Yenipazar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenipazar.bel.tr	+90 000 000 00 00	info@yenipazar.bel.tr	Yenipazar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655544117	550e8400-e29b-41d4-a716-446655440009	Bozdoğan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozdoğan.bel.tr	+90 000 000 00 00	info@bozdoğan.bel.tr	Bozdoğan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656254827	550e8400-e29b-41d4-a716-446655440066	Boğazlıyan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	boğazlıyan.bel.tr	+90 000 000 00 00	info@boğazlıyan.bel.tr	Boğazlıyan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656156729	550e8400-e29b-41d4-a716-446655440057	Erfelek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erfelek.bel.tr	+90 000 000 00 00	info@erfelek.bel.tr	Erfelek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655651224	550e8400-e29b-41d4-a716-446655440016	Kestel	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kestel.bel.tr	+90 000 000 00 00	info@kestel.bel.tr	Kestel Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656040613	550e8400-e29b-41d4-a716-446655440033	Çamlıyayla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çamlıyayla.bel.tr	+90 000 000 00 00	info@çamlıyayla.bel.tr	Çamlıyayla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655543116	550e8400-e29b-41d4-a716-446655440008	Şavşat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şavşat.bel.tr	+90 000 000 00 00	info@şavşat.bel.tr	Şavşat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655950523	550e8400-e29b-41d4-a716-446655440042	Çumra	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çumra.bel.tr	+90 000 000 00 00	info@çumra.bel.tr	Çumra Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656103676	550e8400-e29b-41d4-a716-446655440053	Güneysu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güneysu.bel.tr	+90 000 000 00 00	info@güneysu.bel.tr	Güneysu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656152725	550e8400-e29b-41d4-a716-446655440057	Ayancık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ayancık.bel.tr	+90 000 000 00 00	info@ayancık.bel.tr	Ayancık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655685258	550e8400-e29b-41d4-a716-446655440021	Eğil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eğil.bel.tr	+90 000 000 00 00	info@eğil.bel.tr	Eğil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656049622	550e8400-e29b-41d4-a716-446655440048	Milas	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	milas.bel.tr	+90 000 000 00 00	info@milas.bel.tr	Milas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656111684	550e8400-e29b-41d4-a716-446655440053	İyidere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	iyidere.bel.tr	+90 000 000 00 00	info@iyidere.bel.tr	İyidere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656139712	550e8400-e29b-41d4-a716-446655440055	Tekkeköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tekkeköy.bel.tr	+90 000 000 00 00	info@tekkeköy.bel.tr	Tekkeköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656172745	550e8400-e29b-41d4-a716-446655440058	Suşehri	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	suşehri.bel.tr	+90 000 000 00 00	info@suşehri.bel.tr	Suşehri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656203776	550e8400-e29b-41d4-a716-446655440061	Arsin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arsin.bel.tr	+90 000 000 00 00	info@arsin.bel.tr	Arsin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656311884	550e8400-e29b-41d4-a716-446655440019	İskilip	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	iskilip.bel.tr	+90 000 000 00 00	info@iskilip.bel.tr	İskilip Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655475048	550e8400-e29b-41d4-a716-446655440068	Ortaköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ortaköy.bel.tr	+90 000 000 00 00	info@ortaköy.bel.tr	Ortaköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656118691	550e8400-e29b-41d4-a716-446655440054	Hendek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hendek.bel.tr	+90 000 000 00 00	info@hendek.bel.tr	Hendek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656213786	550e8400-e29b-41d4-a716-446655440061	Tonya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tonya.bel.tr	+90 000 000 00 00	info@tonya.bel.tr	Tonya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655452025	550e8400-e29b-41d4-a716-446655440003	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Büyük Birlik Partisi	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656358931	550e8400-e29b-41d4-a716-446655440035	Buca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	buca.bel.tr	+90 000 000 00 00	info@buca.bel.tr	Buca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656393966	550e8400-e29b-41d4-a716-446655440063	Viranşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	viranşehir.bel.tr	+90 000 000 00 00	info@viranşehir.bel.tr	Viranşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655943516	550e8400-e29b-41d4-a716-446655440042	Selçuklu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	selçuklu.bel.tr	+90 000 000 00 00	info@selçuklu.bel.tr	Selçuklu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655559132	550e8400-e29b-41d4-a716-446655440009	Çine	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çine.bel.tr	+90 000 000 00 00	info@çine.bel.tr	Çine Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656064637	550e8400-e29b-41d4-a716-446655440050	Hacıbektaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hacıbektaş.bel.tr	+90 000 000 00 00	info@hacıbektaş.bel.tr	Hacıbektaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656079652	550e8400-e29b-41d4-a716-446655440052	Gülyalı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gülyalı.bel.tr	+90 000 000 00 00	info@gülyalı.bel.tr	Gülyalı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656093666	550e8400-e29b-41d4-a716-446655440080	Bahçe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bahçe.bel.tr	+90 000 000 00 00	info@bahçe.bel.tr	Bahçe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656159732	550e8400-e29b-41d4-a716-446655440057	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656322895	550e8400-e29b-41d4-a716-446655440034	Beylikdüzü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beylikdüzü.bel.tr	+90 000 000 00 00	info@beylikdüzü.bel.tr	Beylikdüzü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656376949	550e8400-e29b-41d4-a716-446655440035	Torbalı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	torbalı.bel.tr	+90 000 000 00 00	info@torbalı.bel.tr	Torbalı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655459032	550e8400-e29b-41d4-a716-446655440003	Evciler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	evciler.bel.tr	+90 000 000 00 00	info@evciler.bel.tr	Evciler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655736309	550e8400-e29b-41d4-a716-446655440025	Aşkale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aşkale.bel.tr	+90 000 000 00 00	info@aşkale.bel.tr	Aşkale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656200773	550e8400-e29b-41d4-a716-446655440060	Zile	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	zile.bel.tr	+90 000 000 00 00	info@zile.bel.tr	Zile Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656258831	550e8400-e29b-41d4-a716-446655440066	Sorgun	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sorgun.bel.tr	+90 000 000 00 00	info@sorgun.bel.tr	Sorgun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656287860	550e8400-e29b-41d4-a716-446655440018	Bayramören	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayramören.bel.tr	+90 000 000 00 00	info@bayramören.bel.tr	Bayramören Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656327900	550e8400-e29b-41d4-a716-446655440034	Esenyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	esenyurt.bel.tr	+90 000 000 00 00	info@esenyurt.bel.tr	Esenyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440008	550e8400-e29b-41d4-a716-446655440001	Saimbeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	saimbeyli.bel.tr	+90 000 000 00 00	info@saimbeyli.bel.tr	Saimbeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655448021	550e8400-e29b-41d4-a716-446655440002	Samsat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	samsat.bel.tr	+90 000 000 00 00	info@samsat.bel.tr	Samsat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655457030	550e8400-e29b-41d4-a716-446655440003	Dinar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dinar.bel.tr	+90 000 000 00 00	info@dinar.bel.tr	Dinar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655531104	550e8400-e29b-41d4-a716-446655440075	Göle	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	göle.bel.tr	+90 000 000 00 00	info@göle.bel.tr	Göle Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	2	0	0	0.00	2025-05-22 17:26:27.66999+00
660e8400-e29b-41d4-a716-446656102675	550e8400-e29b-41d4-a716-446655440053	Fındıklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	fındıklı.bel.tr	+90 000 000 00 00	info@fındıklı.bel.tr	Fındıklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656106679	550e8400-e29b-41d4-a716-446655440053	Pazar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pazar.bel.tr	+90 000 000 00 00	info@pazar.bel.tr	Pazar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656136709	550e8400-e29b-41d4-a716-446655440055	Ladik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ladik.bel.tr	+90 000 000 00 00	info@ladik.bel.tr	Ladik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655532105	550e8400-e29b-41d4-a716-446655440075	Hanak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hanak.bel.tr	+90 000 000 00 00	info@hanak.bel.tr	Hanak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655719292	550e8400-e29b-41d4-a716-446655440023	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656277850	550e8400-e29b-41d4-a716-446655440017	Bozcaada	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozcaada.bel.tr	+90 000 000 00 00	info@bozcaada.bel.tr	Bozcaada Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656279852	550e8400-e29b-41d4-a716-446655440017	Ezine	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ezine.bel.tr	+90 000 000 00 00	info@ezine.bel.tr	Ezine Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655654227	550e8400-e29b-41d4-a716-446655440016	Nilüfer	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nilüfer.bel.tr	+90 000 000 00 00	info@nilüfer.bel.tr	Nilüfer Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656001574	550e8400-e29b-41d4-a716-446655440045	Ahmetli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ahmetli.bel.tr	+90 000 000 00 00	info@ahmetli.bel.tr	Ahmetli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656044617	550e8400-e29b-41d4-a716-446655440048	Fethiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	fethiye.bel.tr	+90 000 000 00 00	info@fethiye.bel.tr	Fethiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655764337	550e8400-e29b-41d4-a716-446655440026	Seyitgazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	seyitgazi.bel.tr	+90 000 000 00 00	info@seyitgazi.bel.tr	Seyitgazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656202775	550e8400-e29b-41d4-a716-446655440061	Araklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	araklı.bel.tr	+90 000 000 00 00	info@araklı.bel.tr	Araklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656170743	550e8400-e29b-41d4-a716-446655440058	Koyulhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	koyulhisar.bel.tr	+90 000 000 00 00	info@koyulhisar.bel.tr	Koyulhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656179752	550e8400-e29b-41d4-a716-446655440059	Hayrabolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hayrabolu.bel.tr	+90 000 000 00 00	info@hayrabolu.bel.tr	Hayrabolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656180753	550e8400-e29b-41d4-a716-446655440059	Kapaklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kapaklı.bel.tr	+90 000 000 00 00	info@kapaklı.bel.tr	Kapaklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656243816	550e8400-e29b-41d4-a716-446655440065	Çatak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çatak.bel.tr	+90 000 000 00 00	info@çatak.bel.tr	Çatak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655597170	550e8400-e29b-41d4-a716-446655440072	Kozluk	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://www.kozluk.bel.tr/	04884112001	kozlukkaymakamlik@gmail.com	KOZLUK BATMAN TÜRKİYE	https://pbs.twimg.com/profile_images/907356430990233600/XxEOgBlL_400x400.jpg	https://batmancagdascom.teimg.com/crop/1280x720/batmancagdas-com/images/haberler/2020/09/kozlukta_14_adrese_izolasyon_h70424_86c57.jpg	Mehmet Veysi Işık	DEM Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/DEM_PART%C4%B0_LOGOSU.png/250px-DEM_PART%C4%B0_LOGOSU.png	61437	{}	ilçe	a3b613a3-500d-41b2-8603-25cb25b0459f	\N	1	1	2	100.00	2025-05-22 17:32:01.956248+00
660e8400-e29b-41d4-a716-446655895468	550e8400-e29b-41d4-a716-446655440038	Pınarbaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pınarbaşı.bel.tr	+90 000 000 00 00	info@pınarbaşı.bel.tr	Pınarbaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655896469	550e8400-e29b-41d4-a716-446655440038	Sarıoğlan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıoğlan.bel.tr	+90 000 000 00 00	info@sarıoğlan.bel.tr	Sarıoğlan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655897470	550e8400-e29b-41d4-a716-446655440038	Sarız	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarız.bel.tr	+90 000 000 00 00	info@sarız.bel.tr	Sarız Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655899472	550e8400-e29b-41d4-a716-446655440038	Tomarza	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tomarza.bel.tr	+90 000 000 00 00	info@tomarza.bel.tr	Tomarza Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655945518	550e8400-e29b-41d4-a716-446655440042	Taşkent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	taşkent.bel.tr	+90 000 000 00 00	info@taşkent.bel.tr	Taşkent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655946519	550e8400-e29b-41d4-a716-446655440042	Tuzlukçu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tuzlukçu.bel.tr	+90 000 000 00 00	info@tuzlukçu.bel.tr	Tuzlukçu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656259832	550e8400-e29b-41d4-a716-446655440066	Yenifakılı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenifakılı.bel.tr	+90 000 000 00 00	info@yenifakılı.bel.tr	Yenifakılı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655758331	550e8400-e29b-41d4-a716-446655440026	Han	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	han.bel.tr	+90 000 000 00 00	info@han.bel.tr	Han Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655863436	550e8400-e29b-41d4-a716-446655440036	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655891464	550e8400-e29b-41d4-a716-446655440038	Felahiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	felahiye.bel.tr	+90 000 000 00 00	info@felahiye.bel.tr	Felahiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656138711	550e8400-e29b-41d4-a716-446655440055	Salıpazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	salıpazarı.bel.tr	+90 000 000 00 00	info@salıpazarı.bel.tr	Salıpazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656163736	550e8400-e29b-41d4-a716-446655440058	Divriği	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	divriği.bel.tr	+90 000 000 00 00	info@divriği.bel.tr	Divriği Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656269842	550e8400-e29b-41d4-a716-446655440067	Gökçebey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gökçebey.bel.tr	+90 000 000 00 00	info@gökçebey.bel.tr	Gökçebey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655443016	550e8400-e29b-41d4-a716-446655440002	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655467040	550e8400-e29b-41d4-a716-446655440003	İhsaniye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ihsaniye.bel.tr	+90 000 000 00 00	info@ihsaniye.bel.tr	İhsaniye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655485058	550e8400-e29b-41d4-a716-446655440006	Akyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akyurt.bel.tr	+90 000 000 00 00	info@akyurt.bel.tr	Akyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655658231	550e8400-e29b-41d4-a716-446655440016	Yenişehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenişehir.bel.tr	+90 000 000 00 00	info@yenişehir.bel.tr	Yenişehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655681254	550e8400-e29b-41d4-a716-446655440021	Bağlar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bağlar.bel.tr	+90 000 000 00 00	info@bağlar.bel.tr	Bağlar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655683256	550e8400-e29b-41d4-a716-446655440021	Dicle	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dicle.bel.tr	+90 000 000 00 00	info@dicle.bel.tr	Dicle Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655757330	550e8400-e29b-41d4-a716-446655440026	Günyüzü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	günyüzü.bel.tr	+90 000 000 00 00	info@günyüzü.bel.tr	Günyüzü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656062635	550e8400-e29b-41d4-a716-446655440050	Derinkuyu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derinkuyu.bel.tr	+90 000 000 00 00	info@derinkuyu.bel.tr	Derinkuyu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440012	550e8400-e29b-41d4-a716-446655440001	Yumurtalık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yumurtalık.bel.tr	+90 000 000 00 00	info@yumurtalık.bel.tr	Yumurtalık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655453026	550e8400-e29b-41d4-a716-446655440003	Bayat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayat.bel.tr	+90 000 000 00 00	info@bayat.bel.tr	Bayat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655989562	550e8400-e29b-41d4-a716-446655440044	Arapgir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arapgir.bel.tr	+90 000 000 00 00	info@arapgir.bel.tr	Arapgir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656075648	550e8400-e29b-41d4-a716-446655440052	Altınordu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altınordu.bel.tr	+90 000 000 00 00	info@altınordu.bel.tr	Altınordu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656089662	550e8400-e29b-41d4-a716-446655440052	Çatalpınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çatalpınar.bel.tr	+90 000 000 00 00	info@çatalpınar.bel.tr	Çatalpınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656280853	550e8400-e29b-41d4-a716-446655440017	Gelibolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gelibolu.bel.tr	+90 000 000 00 00	info@gelibolu.bel.tr	Gelibolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656299872	550e8400-e29b-41d4-a716-446655440019	Bayat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayat.bel.tr	+90 000 000 00 00	info@bayat.bel.tr	Bayat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655650223	550e8400-e29b-41d4-a716-446655440016	Keles	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keles.bel.tr	+90 000 000 00 00	info@keles.bel.tr	Keles Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655652225	550e8400-e29b-41d4-a716-446655440016	Mudanya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mudanya.bel.tr	+90 000 000 00 00	info@mudanya.bel.tr	Mudanya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655952525	550e8400-e29b-41d4-a716-446655440043	Aslanapa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aslanapa.bel.tr	+90 000 000 00 00	info@aslanapa.bel.tr	Aslanapa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655991564	550e8400-e29b-41d4-a716-446655440044	Battalgazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	battalgazi.bel.tr	+90 000 000 00 00	info@battalgazi.bel.tr	Battalgazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656083656	550e8400-e29b-41d4-a716-446655440052	Korgan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	korgan.bel.tr	+90 000 000 00 00	info@korgan.bel.tr	Korgan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656218791	550e8400-e29b-41d4-a716-446655440061	Şalpazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şalpazarı.bel.tr	+90 000 000 00 00	info@şalpazarı.bel.tr	Şalpazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656219792	550e8400-e29b-41d4-a716-446655440062	Hozat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hozat.bel.tr	+90 000 000 00 00	info@hozat.bel.tr	Hozat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655496069	550e8400-e29b-41d4-a716-446655440006	Kahramankazan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kahramankazan.bel.tr	+90 000 000 00 00	info@kahramankazan.bel.tr	Kahramankazan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655497070	550e8400-e29b-41d4-a716-446655440006	Kalecik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kalecik.bel.tr	+90 000 000 00 00	info@kalecik.bel.tr	Kalecik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655499072	550e8400-e29b-41d4-a716-446655440006	Kızılcahamam	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kızılcahamam.bel.tr	+90 000 000 00 00	info@kızılcahamam.bel.tr	Kızılcahamam Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655507080	550e8400-e29b-41d4-a716-446655440006	Çankaya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çankaya.bel.tr	+90 000 000 00 00	info@çankaya.bel.tr	Çankaya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655510083	550e8400-e29b-41d4-a716-446655440007	Akseki	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akseki.bel.tr	+90 000 000 00 00	info@akseki.bel.tr	Akseki Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655700273	550e8400-e29b-41d4-a716-446655440081	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	AKP	https://upload-wikimedia-org.translate.goog/wikipedia/en/thumb/5/56/Justice_and_Development_Party_%28Turkey%29_logo.svg/225px-Justice_and_Development_Party_%28Turkey%29_logo.svg.png?_x_tr_sl=en&_x_tr_tl=tr&_x_tr_hl=tr&_x_tr_pto=tc	0	{}	ilçe	448575ce-7444-4bd7-8070-1753a8ecb16b	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656034607	550e8400-e29b-41d4-a716-446655440033	Mezitli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mezitli.bel.tr	+90 000 000 00 00	info@mezitli.bel.tr	Mezitli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656035608	550e8400-e29b-41d4-a716-446655440033	Mut	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mut.bel.tr	+90 000 000 00 00	info@mut.bel.tr	Mut Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656041614	550e8400-e29b-41d4-a716-446655440048	Bodrum	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bodrum.bel.tr	+90 000 000 00 00	info@bodrum.bel.tr	Bodrum Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656046619	550e8400-e29b-41d4-a716-446655440048	Köyceğiz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	köyceğiz.bel.tr	+90 000 000 00 00	info@köyceğiz.bel.tr	Köyceğiz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656226799	550e8400-e29b-41d4-a716-446655440062	Çemişgezek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çemişgezek.bel.tr	+90 000 000 00 00	info@çemişgezek.bel.tr	Çemişgezek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656228801	550e8400-e29b-41d4-a716-446655440064	Eşme	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eşme.bel.tr	+90 000 000 00 00	info@eşme.bel.tr	Eşme Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656237810	550e8400-e29b-41d4-a716-446655440065	Gevaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gevaş.bel.tr	+90 000 000 00 00	info@gevaş.bel.tr	Gevaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656238811	550e8400-e29b-41d4-a716-446655440065	Gürpınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gürpınar.bel.tr	+90 000 000 00 00	info@gürpınar.bel.tr	Gürpınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655463036	550e8400-e29b-41d4-a716-446655440003	Sinanpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sinanpaşa.bel.tr	+90 000 000 00 00	info@sinanpaşa.bel.tr	Sinanpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656065638	550e8400-e29b-41d4-a716-446655440050	Kozaklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kozaklı.bel.tr	+90 000 000 00 00	info@kozaklı.bel.tr	Kozaklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656066639	550e8400-e29b-41d4-a716-446655440050	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656067640	550e8400-e29b-41d4-a716-446655440050	Ürgüp	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ürgüp.bel.tr	+90 000 000 00 00	info@ürgüp.bel.tr	Ürgüp Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656068641	550e8400-e29b-41d4-a716-446655440051	Altunhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altunhisar.bel.tr	+90 000 000 00 00	info@altunhisar.bel.tr	Altunhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656070643	550e8400-e29b-41d4-a716-446655440051	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656072645	550e8400-e29b-41d4-a716-446655440051	Çamardı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çamardı.bel.tr	+90 000 000 00 00	info@çamardı.bel.tr	Çamardı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655469042	550e8400-e29b-41d4-a716-446655440003	Şuhut	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şuhut.bel.tr	+90 000 000 00 00	info@şuhut.bel.tr	Şuhut Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655545118	550e8400-e29b-41d4-a716-446655440009	Buharkent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	buharkent.bel.tr	+90 000 000 00 00	info@buharkent.bel.tr	Buharkent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655550123	550e8400-e29b-41d4-a716-446655440009	Karpuzlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karpuzlu.bel.tr	+90 000 000 00 00	info@karpuzlu.bel.tr	Karpuzlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656073646	550e8400-e29b-41d4-a716-446655440051	Çiftlik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çiftlik.bel.tr	+90 000 000 00 00	info@çiftlik.bel.tr	Çiftlik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656074647	550e8400-e29b-41d4-a716-446655440052	Akkuş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akkuş.bel.tr	+90 000 000 00 00	info@akkuş.bel.tr	Akkuş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656078651	550e8400-e29b-41d4-a716-446655440052	Gölköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölköy.bel.tr	+90 000 000 00 00	info@gölköy.bel.tr	Gölköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656302875	550e8400-e29b-41d4-a716-446655440019	Kargı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kargı.bel.tr	+90 000 000 00 00	info@kargı.bel.tr	Kargı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655554127	550e8400-e29b-41d4-a716-446655440009	Köşk	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	köşk.bel.tr	+90 000 000 00 00	info@köşk.bel.tr	Köşk Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655598171	550e8400-e29b-41d4-a716-446655440072	Sason	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sason.bel.tr	+90 000 000 00 00	info@sason.bel.tr	Sason Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655639212	550e8400-e29b-41d4-a716-446655440015	Karamanlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karamanlı.bel.tr	+90 000 000 00 00	info@karamanlı.bel.tr	Karamanlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655688261	550e8400-e29b-41d4-a716-446655440021	Kayapınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kayapınar.bel.tr	+90 000 000 00 00	info@kayapınar.bel.tr	Kayapınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655695268	550e8400-e29b-41d4-a716-446655440021	Çermik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çermik.bel.tr	+90 000 000 00 00	info@çermik.bel.tr	Çermik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655699272	550e8400-e29b-41d4-a716-446655440081	Cumayeri	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	cumayeri.bel.tr	+90 000 000 00 00	info@cumayeri.bel.tr	Cumayeri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655821394	550e8400-e29b-41d4-a716-446655440032	Atabey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	atabey.bel.tr	+90 000 000 00 00	info@atabey.bel.tr	Atabey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655689262	550e8400-e29b-41d4-a716-446655440021	Kocaköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kocaköy.bel.tr	+90 000 000 00 00	info@kocaköy.bel.tr	Kocaköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655709282	550e8400-e29b-41d4-a716-446655440022	Keşan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keşan.bel.tr	+90 000 000 00 00	info@keşan.bel.tr	Keşan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655711284	550e8400-e29b-41d4-a716-446655440022	Meriç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	meriç.bel.tr	+90 000 000 00 00	info@meriç.bel.tr	Meriç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655712285	550e8400-e29b-41d4-a716-446655440022	Süloğlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	süloğlu.bel.tr	+90 000 000 00 00	info@süloğlu.bel.tr	Süloğlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655737310	550e8400-e29b-41d4-a716-446655440025	Horasan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	horasan.bel.tr	+90 000 000 00 00	info@horasan.bel.tr	Horasan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655740313	550e8400-e29b-41d4-a716-446655440025	Karaçoban	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karaçoban.bel.tr	+90 000 000 00 00	info@karaçoban.bel.tr	Karaçoban Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655986559	550e8400-e29b-41d4-a716-446655440040	Mucur	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mucur.bel.tr	+90 000 000 00 00	info@mucur.bel.tr	Mucur Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655992565	550e8400-e29b-41d4-a716-446655440044	Darende	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	darende.bel.tr	+90 000 000 00 00	info@darende.bel.tr	Darende Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656036609	550e8400-e29b-41d4-a716-446655440033	Silifke	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	silifke.bel.tr	+90 000 000 00 00	info@silifke.bel.tr	Silifke Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656134707	550e8400-e29b-41d4-a716-446655440055	Havza	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	havza.bel.tr	+90 000 000 00 00	info@havza.bel.tr	Havza Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656135708	550e8400-e29b-41d4-a716-446655440055	Kavak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kavak.bel.tr	+90 000 000 00 00	info@kavak.bel.tr	Kavak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656209782	550e8400-e29b-41d4-a716-446655440061	Maçka	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	maçka.bel.tr	+90 000 000 00 00	info@maçka.bel.tr	Maçka Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656227800	550e8400-e29b-41d4-a716-446655440064	Banaz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	banaz.bel.tr	+90 000 000 00 00	info@banaz.bel.tr	Banaz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656320893	550e8400-e29b-41d4-a716-446655440034	Başakşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	başakşehir.bel.tr	+90 000 000 00 00	info@başakşehir.bel.tr	Başakşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656321894	550e8400-e29b-41d4-a716-446655440034	Beykoz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beykoz.bel.tr	+90 000 000 00 00	info@beykoz.bel.tr	Beykoz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655462035	550e8400-e29b-41d4-a716-446655440003	Sandıklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sandıklı.bel.tr	+90 000 000 00 00	info@sandıklı.bel.tr	Sandıklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655659232	550e8400-e29b-41d4-a716-446655440016	Yıldırım	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yıldırım.bel.tr	+90 000 000 00 00	info@yıldırım.bel.tr	Yıldırım Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655674247	550e8400-e29b-41d4-a716-446655440020	Sarayköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarayköy.bel.tr	+90 000 000 00 00	info@sarayköy.bel.tr	Sarayköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655682255	550e8400-e29b-41d4-a716-446655440021	Bismil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bismil.bel.tr	+90 000 000 00 00	info@bismil.bel.tr	Bismil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655755328	550e8400-e29b-41d4-a716-446655440026	Alpu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alpu.bel.tr	+90 000 000 00 00	info@alpu.bel.tr	Alpu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656288861	550e8400-e29b-41d4-a716-446655440018	Eldivan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eldivan.bel.tr	+90 000 000 00 00	info@eldivan.bel.tr	Eldivan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656328901	550e8400-e29b-41d4-a716-446655440034	Eyüpsultan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eyüpsultan.bel.tr	+90 000 000 00 00	info@eyüpsultan.bel.tr	Eyüpsultan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655978551	550e8400-e29b-41d4-a716-446655440071	Sulakyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sulakyurt.bel.tr	+90 000 000 00 00	info@sulakyurt.bel.tr	Sulakyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656077650	550e8400-e29b-41d4-a716-446655440052	Fatsa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	fatsa.bel.tr	+90 000 000 00 00	info@fatsa.bel.tr	Fatsa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656284857	550e8400-e29b-41d4-a716-446655440017	Çan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çan.bel.tr	+90 000 000 00 00	info@çan.bel.tr	Çan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656285858	550e8400-e29b-41d4-a716-446655440017	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656295868	550e8400-e29b-41d4-a716-446655440018	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656310883	550e8400-e29b-41d4-a716-446655440019	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656318891	550e8400-e29b-41d4-a716-446655440034	Bayrampaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayrampaşa.bel.tr	+90 000 000 00 00	info@bayrampaşa.bel.tr	Bayrampaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656236809	550e8400-e29b-41d4-a716-446655440065	Erciş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erciş.bel.tr	+90 000 000 00 00	info@erciş.bel.tr	Erciş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655702275	550e8400-e29b-41d4-a716-446655440081	Gümüşova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gümüşova.bel.tr	+90 000 000 00 00	info@gümüşova.bel.tr	Gümüşova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655846419	550e8400-e29b-41d4-a716-446655440046	Türkoğlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	türkoğlu.bel.tr	+90 000 000 00 00	info@türkoğlu.bel.tr	Türkoğlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656119692	550e8400-e29b-41d4-a716-446655440054	Karapürçek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karapürçek.bel.tr	+90 000 000 00 00	info@karapürçek.bel.tr	Karapürçek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655826399	550e8400-e29b-41d4-a716-446655440032	Keçiborlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keçiborlu.bel.tr	+90 000 000 00 00	info@keçiborlu.bel.tr	Keçiborlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656088661	550e8400-e29b-41d4-a716-446655440052	Çamaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çamaş.bel.tr	+90 000 000 00 00	info@çamaş.bel.tr	Çamaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656289862	550e8400-e29b-41d4-a716-446655440018	Ilgaz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ilgaz.bel.tr	+90 000 000 00 00	info@ilgaz.bel.tr	Ilgaz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655603176	550e8400-e29b-41d4-a716-446655440011	Bozüyük	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozüyük.bel.tr	+90 000 000 00 00	info@bozüyük.bel.tr	Bozüyük Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655607180	550e8400-e29b-41d4-a716-446655440011	Söğüt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	söğüt.bel.tr	+90 000 000 00 00	info@söğüt.bel.tr	Söğüt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655716289	550e8400-e29b-41d4-a716-446655440023	Arıcak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arıcak.bel.tr	+90 000 000 00 00	info@arıcak.bel.tr	Arıcak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655722295	550e8400-e29b-41d4-a716-446655440023	Kovancılar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kovancılar.bel.tr	+90 000 000 00 00	info@kovancılar.bel.tr	Kovancılar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655877450	550e8400-e29b-41d4-a716-446655440037	Hanönü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hanönü.bel.tr	+90 000 000 00 00	info@hanönü.bel.tr	Hanönü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655976549	550e8400-e29b-41d4-a716-446655440071	Keskin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keskin.bel.tr	+90 000 000 00 00	info@keskin.bel.tr	Keskin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656122695	550e8400-e29b-41d4-a716-446655440054	Kocaali	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kocaali.bel.tr	+90 000 000 00 00	info@kocaali.bel.tr	Kocaali Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655449022	550e8400-e29b-41d4-a716-446655440002	Sincik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sincik.bel.tr	+90 000 000 00 00	info@sincik.bel.tr	Sincik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655610183	550e8400-e29b-41d4-a716-446655440012	Adaklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	adaklı.bel.tr	+90 000 000 00 00	info@adaklı.bel.tr	Adaklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655613186	550e8400-e29b-41d4-a716-446655440012	Karlıova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karlıova.bel.tr	+90 000 000 00 00	info@karlıova.bel.tr	Karlıova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655614187	550e8400-e29b-41d4-a716-446655440012	Kiğı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kiğı.bel.tr	+90 000 000 00 00	info@kiğı.bel.tr	Kiğı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655618191	550e8400-e29b-41d4-a716-446655440013	Adilcevaz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	adilcevaz.bel.tr	+90 000 000 00 00	info@adilcevaz.bel.tr	Adilcevaz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656005578	550e8400-e29b-41d4-a716-446655440045	Gölmarmara	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölmarmara.bel.tr	+90 000 000 00 00	info@gölmarmara.bel.tr	Gölmarmara Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656063636	550e8400-e29b-41d4-a716-446655440050	Gülşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gülşehir.bel.tr	+90 000 000 00 00	info@gülşehir.bel.tr	Gülşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655747320	550e8400-e29b-41d4-a716-446655440025	Pazaryolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pazaryolu.bel.tr	+90 000 000 00 00	info@pazaryolu.bel.tr	Pazaryolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655748321	550e8400-e29b-41d4-a716-446655440025	Tekman	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tekman.bel.tr	+90 000 000 00 00	info@tekman.bel.tr	Tekman Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655930503	550e8400-e29b-41d4-a716-446655440042	Emirgazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	emirgazi.bel.tr	+90 000 000 00 00	info@emirgazi.bel.tr	Emirgazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655940513	550e8400-e29b-41d4-a716-446655440042	Kulu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kulu.bel.tr	+90 000 000 00 00	info@kulu.bel.tr	Kulu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656378951	550e8400-e29b-41d4-a716-446655440035	Çeşme	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çeşme.bel.tr	+90 000 000 00 00	info@çeşme.bel.tr	Çeşme Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656275848	550e8400-e29b-41d4-a716-446655440017	Bayramiç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bayramiç.bel.tr	+90 000 000 00 00	info@bayramiç.bel.tr	Bayramiç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655487060	550e8400-e29b-41d4-a716-446655440006	Ayaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ayaş.bel.tr	+90 000 000 00 00	info@ayaş.bel.tr	Ayaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655661234	550e8400-e29b-41d4-a716-446655440016	İznik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	iznik.bel.tr	+90 000 000 00 00	info@iznik.bel.tr	İznik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656000573	550e8400-e29b-41d4-a716-446655440044	Yeşilyurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yeşilyurt.bel.tr	+90 000 000 00 00	info@yeşilyurt.bel.tr	Yeşilyurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656129702	550e8400-e29b-41d4-a716-446655440055	Asarcık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	asarcık.bel.tr	+90 000 000 00 00	info@asarcık.bel.tr	Asarcık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656278851	550e8400-e29b-41d4-a716-446655440017	Eceabat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eceabat.bel.tr	+90 000 000 00 00	info@eceabat.bel.tr	Eceabat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656360933	550e8400-e29b-41d4-a716-446655440035	Foça	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	foça.bel.tr	+90 000 000 00 00	info@foça.bel.tr	Foça Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656362935	550e8400-e29b-41d4-a716-446655440035	Güzelbahçe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güzelbahçe.bel.tr	+90 000 000 00 00	info@güzelbahçe.bel.tr	Güzelbahçe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655486059	550e8400-e29b-41d4-a716-446655440006	Altındağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altındağ.bel.tr	+90 000 000 00 00	info@altındağ.bel.tr	Altındağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655490063	550e8400-e29b-41d4-a716-446655440006	Elmadağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	elmadağ.bel.tr	+90 000 000 00 00	info@elmadağ.bel.tr	Elmadağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655901474	550e8400-e29b-41d4-a716-446655440038	Yeşilhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yeşilhisar.bel.tr	+90 000 000 00 00	info@yeşilhisar.bel.tr	Yeşilhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656087660	550e8400-e29b-41d4-a716-446655440052	Ulubey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ulubey.bel.tr	+90 000 000 00 00	info@ulubey.bel.tr	Ulubey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656144717	550e8400-e29b-41d4-a716-446655440055	İlkadım	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ilkadım.bel.tr	+90 000 000 00 00	info@ilkadım.bel.tr	İlkadım Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656223796	550e8400-e29b-41d4-a716-446655440062	Pertek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pertek.bel.tr	+90 000 000 00 00	info@pertek.bel.tr	Pertek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656312885	550e8400-e29b-41d4-a716-446655440034	Adalar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	adalar.bel.tr	+90 000 000 00 00	info@adalar.bel.tr	Adalar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655679252	550e8400-e29b-41d4-a716-446655440020	Çardak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çardak.bel.tr	+90 000 000 00 00	info@çardak.bel.tr	Çardak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655916489	550e8400-e29b-41d4-a716-446655440041	Kartepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kartepe.bel.tr	+90 000 000 00 00	info@kartepe.bel.tr	Kartepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655994567	550e8400-e29b-41d4-a716-446655440044	Doğanşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğanşehir.bel.tr	+90 000 000 00 00	info@doğanşehir.bel.tr	Doğanşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656363936	550e8400-e29b-41d4-a716-446655440035	Karabağlar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karabağlar.bel.tr	+90 000 000 00 00	info@karabağlar.bel.tr	Karabağlar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656373946	550e8400-e29b-41d4-a716-446655440035	Seferihisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	seferihisar.bel.tr	+90 000 000 00 00	info@seferihisar.bel.tr	Seferihisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656323896	550e8400-e29b-41d4-a716-446655440034	Beyoğlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beyoğlu.bel.tr	+90 000 000 00 00	info@beyoğlu.bel.tr	Beyoğlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655693266	550e8400-e29b-41d4-a716-446655440021	Sur	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sur.bel.tr	+90 000 000 00 00	info@sur.bel.tr	Sur Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655698271	550e8400-e29b-41d4-a716-446655440081	Akçakoca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akçakoca.bel.tr	+90 000 000 00 00	info@akçakoca.bel.tr	Akçakoca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655489062	550e8400-e29b-41d4-a716-446655440006	Beypazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beypazarı.bel.tr	+90 000 000 00 00	info@beypazarı.bel.tr	Beypazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655791364	550e8400-e29b-41d4-a716-446655440028	Çamoluk	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çamoluk.bel.tr	+90 000 000 00 00	info@çamoluk.bel.tr	Çamoluk Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656296869	550e8400-e29b-41d4-a716-446655440018	Çerkeş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çerkeş.bel.tr	+90 000 000 00 00	info@çerkeş.bel.tr	Çerkeş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655718291	550e8400-e29b-41d4-a716-446655440023	Baskil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	baskil.bel.tr	+90 000 000 00 00	info@baskil.bel.tr	Baskil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655799372	550e8400-e29b-41d4-a716-446655440029	Şiran	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şiran.bel.tr	+90 000 000 00 00	info@şiran.bel.tr	Şiran Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655875448	550e8400-e29b-41d4-a716-446655440037	Devrekani	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	devrekani.bel.tr	+90 000 000 00 00	info@devrekani.bel.tr	Devrekani Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655630203	550e8400-e29b-41d4-a716-446655440014	Mengen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mengen.bel.tr	+90 000 000 00 00	info@mengen.bel.tr	Mengen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655647220	550e8400-e29b-41d4-a716-446655440016	Gürsu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gürsu.bel.tr	+90 000 000 00 00	info@gürsu.bel.tr	Gürsu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655595168	550e8400-e29b-41d4-a716-446655440072	Gercüş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gercüş.bel.tr	+90 000 000 00 00	info@gercüş.bel.tr	Gercüş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656365938	550e8400-e29b-41d4-a716-446655440035	Karşıyaka	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karşıyaka.bel.tr	+90 000 000 00 00	info@karşıyaka.bel.tr	Karşıyaka Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656370943	550e8400-e29b-41d4-a716-446655440035	Menderes	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	menderes.bel.tr	+90 000 000 00 00	info@menderes.bel.tr	Menderes Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656375948	550e8400-e29b-41d4-a716-446655440035	Tire	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tire.bel.tr	+90 000 000 00 00	info@tire.bel.tr	Tire Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656392965	550e8400-e29b-41d4-a716-446655440063	Suruç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	suruç.bel.tr	+90 000 000 00 00	info@suruç.bel.tr	Suruç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655594167	550e8400-e29b-41d4-a716-446655440072	Beşiri	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beşiri.bel.tr	+90 000 000 00 00	info@beşiri.bel.tr	Beşiri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655664237	550e8400-e29b-41d4-a716-446655440020	Baklan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	baklan.bel.tr	+90 000 000 00 00	info@baklan.bel.tr	Baklan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655665238	550e8400-e29b-41d4-a716-446655440020	Bekilli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bekilli.bel.tr	+90 000 000 00 00	info@bekilli.bel.tr	Bekilli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655666239	550e8400-e29b-41d4-a716-446655440020	Beyağaç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beyağaç.bel.tr	+90 000 000 00 00	info@beyağaç.bel.tr	Beyağaç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655667240	550e8400-e29b-41d4-a716-446655440020	Bozkurt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozkurt.bel.tr	+90 000 000 00 00	info@bozkurt.bel.tr	Bozkurt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655690263	550e8400-e29b-41d4-a716-446655440021	Kulp	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kulp.bel.tr	+90 000 000 00 00	info@kulp.bel.tr	Kulp Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655691264	550e8400-e29b-41d4-a716-446655440021	Lice	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	lice.bel.tr	+90 000 000 00 00	info@lice.bel.tr	Lice Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655516089	550e8400-e29b-41d4-a716-446655440007	Finike	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	finike.bel.tr	+90 000 000 00 00	info@finike.bel.tr	Finike Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655523096	550e8400-e29b-41d4-a716-446655440007	Korkuteli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	korkuteli.bel.tr	+90 000 000 00 00	info@korkuteli.bel.tr	Korkuteli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655444017	550e8400-e29b-41d4-a716-446655440002	Besni	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	besni.bel.tr	+90 000 000 00 00	info@besni.bel.tr	Besni Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655707280	550e8400-e29b-41d4-a716-446655440022	Enez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	enez.bel.tr	+90 000 000 00 00	info@enez.bel.tr	Enez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655775348	550e8400-e29b-41d4-a716-446655440027	İslahiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	islahiye.bel.tr	+90 000 000 00 00	info@islahiye.bel.tr	İslahiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655777350	550e8400-e29b-41d4-a716-446655440027	Şehitkamil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şehitkamil.bel.tr	+90 000 000 00 00	info@şehitkamil.bel.tr	Şehitkamil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655779352	550e8400-e29b-41d4-a716-446655440028	Bulancak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bulancak.bel.tr	+90 000 000 00 00	info@bulancak.bel.tr	Bulancak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655780353	550e8400-e29b-41d4-a716-446655440028	Dereli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dereli.bel.tr	+90 000 000 00 00	info@dereli.bel.tr	Dereli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655787360	550e8400-e29b-41d4-a716-446655440028	Keşap	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keşap.bel.tr	+90 000 000 00 00	info@keşap.bel.tr	Keşap Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655788361	550e8400-e29b-41d4-a716-446655440028	Piraziz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	piraziz.bel.tr	+90 000 000 00 00	info@piraziz.bel.tr	Piraziz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655549122	550e8400-e29b-41d4-a716-446655440009	Karacasu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karacasu.bel.tr	+90 000 000 00 00	info@karacasu.bel.tr	Karacasu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655790363	550e8400-e29b-41d4-a716-446655440028	Yağlıdere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yağlıdere.bel.tr	+90 000 000 00 00	info@yağlıdere.bel.tr	Yağlıdere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655793366	550e8400-e29b-41d4-a716-446655440028	Şebinkarahisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şebinkarahisar.bel.tr	+90 000 000 00 00	info@şebinkarahisar.bel.tr	Şebinkarahisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655794367	550e8400-e29b-41d4-a716-446655440029	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655795368	550e8400-e29b-41d4-a716-446655440029	Kelkit	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kelkit.bel.tr	+90 000 000 00 00	info@kelkit.bel.tr	Kelkit Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655797370	550e8400-e29b-41d4-a716-446655440029	Kürtün	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kürtün.bel.tr	+90 000 000 00 00	info@kürtün.bel.tr	Kürtün Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655801374	550e8400-e29b-41d4-a716-446655440030	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655802375	550e8400-e29b-41d4-a716-446655440030	Yüksekova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yüksekova.bel.tr	+90 000 000 00 00	info@yüksekova.bel.tr	Yüksekova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655447020	550e8400-e29b-41d4-a716-446655440002	Kahta	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kahta.bel.tr	+90 000 000 00 00	info@kahta.bel.tr	Kahta Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655551124	550e8400-e29b-41d4-a716-446655440009	Koçarlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	koçarlı.bel.tr	+90 000 000 00 00	info@koçarlı.bel.tr	Koçarlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655726299	550e8400-e29b-41d4-a716-446655440024	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655781354	550e8400-e29b-41d4-a716-446655440028	Doğankent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğankent.bel.tr	+90 000 000 00 00	info@doğankent.bel.tr	Doğankent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655782355	550e8400-e29b-41d4-a716-446655440028	Espiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	espiye.bel.tr	+90 000 000 00 00	info@espiye.bel.tr	Espiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655804377	550e8400-e29b-41d4-a716-446655440030	Şemdinli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şemdinli.bel.tr	+90 000 000 00 00	info@şemdinli.bel.tr	Şemdinli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655806379	550e8400-e29b-41d4-a716-446655440031	Antakya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	antakya.bel.tr	+90 000 000 00 00	info@antakya.bel.tr	Antakya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655807380	550e8400-e29b-41d4-a716-446655440031	Arsuz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arsuz.bel.tr	+90 000 000 00 00	info@arsuz.bel.tr	Arsuz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655776349	550e8400-e29b-41d4-a716-446655440027	Şahinbey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şahinbey.bel.tr	+90 000 000 00 00	info@şahinbey.bel.tr	Şahinbey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655809382	550e8400-e29b-41d4-a716-446655440031	Defne	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	defne.bel.tr	+90 000 000 00 00	info@defne.bel.tr	Defne Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655810383	550e8400-e29b-41d4-a716-446655440031	Dörtyol	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dörtyol.bel.tr	+90 000 000 00 00	info@dörtyol.bel.tr	Dörtyol Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655811384	550e8400-e29b-41d4-a716-446655440031	Erzin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erzin.bel.tr	+90 000 000 00 00	info@erzin.bel.tr	Erzin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655812385	550e8400-e29b-41d4-a716-446655440031	Hassa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hassa.bel.tr	+90 000 000 00 00	info@hassa.bel.tr	Hassa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655820393	550e8400-e29b-41d4-a716-446655440032	Aksu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aksu.bel.tr	+90 000 000 00 00	info@aksu.bel.tr	Aksu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655822395	550e8400-e29b-41d4-a716-446655440032	Eğirdir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eğirdir.bel.tr	+90 000 000 00 00	info@eğirdir.bel.tr	Eğirdir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655823396	550e8400-e29b-41d4-a716-446655440032	Gelendost	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gelendost.bel.tr	+90 000 000 00 00	info@gelendost.bel.tr	Gelendost Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655493066	550e8400-e29b-41d4-a716-446655440006	Gölbaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölbaşı.bel.tr	+90 000 000 00 00	info@gölbaşı.bel.tr	Gölbaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655552125	550e8400-e29b-41d4-a716-446655440009	Kuyucak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kuyucak.bel.tr	+90 000 000 00 00	info@kuyucak.bel.tr	Kuyucak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655643216	550e8400-e29b-41d4-a716-446655440015	Çavdır	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çavdır.bel.tr	+90 000 000 00 00	info@çavdır.bel.tr	Çavdır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655831404	550e8400-e29b-41d4-a716-446655440032	Yenişarbademli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenişarbademli.bel.tr	+90 000 000 00 00	info@yenişarbademli.bel.tr	Yenişarbademli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655835408	550e8400-e29b-41d4-a716-446655440076	Karakoyunlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karakoyunlu.bel.tr	+90 000 000 00 00	info@karakoyunlu.bel.tr	Karakoyunlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655836409	550e8400-e29b-41d4-a716-446655440076	Tuzluca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tuzluca.bel.tr	+90 000 000 00 00	info@tuzluca.bel.tr	Tuzluca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655837410	550e8400-e29b-41d4-a716-446655440046	Afşin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	afşin.bel.tr	+90 000 000 00 00	info@afşin.bel.tr	Afşin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655814387	550e8400-e29b-41d4-a716-446655440031	Kırıkhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kırıkhan.bel.tr	+90 000 000 00 00	info@kırıkhan.bel.tr	Kırıkhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440001	550e8400-e29b-41d4-a716-446655440001	Aladağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://www.aladag.bel.tr	+90 352 555 55 55	info@aladag.bel.tr	Aladağ Mahallesi, Atatürk Caddesi No:1, Aladağ, Adana, Türkiye	https://www.aladag.bel.tr/logo.png	https://www.aladag.bel.tr/cover.jpg	Ali Güler	Cumhuriyet Halk Partisi	https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Cumhuriyet_Halk_Partisi_Logo.svg/200px-Cumhuriyet_Halk_Partisi_Logo.svg.png	15000	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655714287	550e8400-e29b-41d4-a716-446655440022	İpsala	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ipsala.bel.tr	+90 000 000 00 00	info@ipsala.bel.tr	İpsala Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655844417	550e8400-e29b-41d4-a716-446655440046	Onikişubat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	onikişubat.bel.tr	+90 000 000 00 00	info@onikişubat.bel.tr	Onikişubat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655849422	550e8400-e29b-41d4-a716-446655440078	Eskipazar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eskipazar.bel.tr	+90 000 000 00 00	info@eskipazar.bel.tr	Eskipazar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655851424	550e8400-e29b-41d4-a716-446655440078	Ovacık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ovacık.bel.tr	+90 000 000 00 00	info@ovacık.bel.tr	Ovacık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656304877	550e8400-e29b-41d4-a716-446655440019	Mecitözü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mecitözü.bel.tr	+90 000 000 00 00	info@mecitözü.bel.tr	Mecitözü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655483056	550e8400-e29b-41d4-a716-446655440005	Suluova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	suluova.bel.tr	+90 000 000 00 00	info@suluova.bel.tr	Suluova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655572145	550e8400-e29b-41d4-a716-446655440010	Bandırma	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bandırma.bel.tr	+90 000 000 00 00	info@bandırma.bel.tr	Bandırma Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656010583	550e8400-e29b-41d4-a716-446655440045	Salihli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	salihli.bel.tr	+90 000 000 00 00	info@salihli.bel.tr	Salihli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655555128	550e8400-e29b-41d4-a716-446655440009	Nazilli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nazilli.bel.tr	+90 000 000 00 00	info@nazilli.bel.tr	Nazilli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655874447	550e8400-e29b-41d4-a716-446655440037	Daday	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	daday.bel.tr	+90 000 000 00 00	info@daday.bel.tr	Daday Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655880453	550e8400-e29b-41d4-a716-446655440037	Pınarbaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pınarbaşı.bel.tr	+90 000 000 00 00	info@pınarbaşı.bel.tr	Pınarbaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655881454	550e8400-e29b-41d4-a716-446655440037	Seydiler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	seydiler.bel.tr	+90 000 000 00 00	info@seydiler.bel.tr	Seydiler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655883456	550e8400-e29b-41d4-a716-446655440037	Tosya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tosya.bel.tr	+90 000 000 00 00	info@tosya.bel.tr	Tosya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655886459	550e8400-e29b-41d4-a716-446655440037	İnebolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	inebolu.bel.tr	+90 000 000 00 00	info@inebolu.bel.tr	İnebolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655888461	550e8400-e29b-41d4-a716-446655440038	Akkışla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akkışla.bel.tr	+90 000 000 00 00	info@akkışla.bel.tr	Akkışla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655890463	550e8400-e29b-41d4-a716-446655440038	Develi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	develi.bel.tr	+90 000 000 00 00	info@develi.bel.tr	Develi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655479052	550e8400-e29b-41d4-a716-446655440005	Göynücek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	göynücek.bel.tr	+90 000 000 00 00	info@göynücek.bel.tr	Göynücek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655956529	550e8400-e29b-41d4-a716-446655440043	Gediz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gediz.bel.tr	+90 000 000 00 00	info@gediz.bel.tr	Gediz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655580153	550e8400-e29b-41d4-a716-446655440010	Havran	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	havran.bel.tr	+90 000 000 00 00	info@havran.bel.tr	Havran Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655581154	550e8400-e29b-41d4-a716-446655440010	Karesi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karesi.bel.tr	+90 000 000 00 00	info@karesi.bel.tr	Karesi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655601174	550e8400-e29b-41d4-a716-446655440069	Demirözü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	demirözü.bel.tr	+90 000 000 00 00	info@demirözü.bel.tr	Demirözü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655919492	550e8400-e29b-41d4-a716-446655440041	İzmit	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	izmit.bel.tr	+90 000 000 00 00	info@izmit.bel.tr	İzmit Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655920493	550e8400-e29b-41d4-a716-446655440042	Ahırlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ahırlı.bel.tr	+90 000 000 00 00	info@ahırlı.bel.tr	Ahırlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655923496	550e8400-e29b-41d4-a716-446655440042	Altınekin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altınekin.bel.tr	+90 000 000 00 00	info@altınekin.bel.tr	Altınekin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655925498	550e8400-e29b-41d4-a716-446655440042	Bozkır	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozkır.bel.tr	+90 000 000 00 00	info@bozkır.bel.tr	Bozkır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655929502	550e8400-e29b-41d4-a716-446655440042	Doğanhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğanhisar.bel.tr	+90 000 000 00 00	info@doğanhisar.bel.tr	Doğanhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655912485	550e8400-e29b-41d4-a716-446655440041	Gebze	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gebze.bel.tr	+90 000 000 00 00	info@gebze.bel.tr	Gebze Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655928501	550e8400-e29b-41d4-a716-446655440042	Derebucak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derebucak.bel.tr	+90 000 000 00 00	info@derebucak.bel.tr	Derebucak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655931504	550e8400-e29b-41d4-a716-446655440042	Ereğli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ereğli.bel.tr	+90 000 000 00 00	info@ereğli.bel.tr	Ereğli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655932505	550e8400-e29b-41d4-a716-446655440042	Güneysınır	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güneysınır.bel.tr	+90 000 000 00 00	info@güneysınır.bel.tr	Güneysınır Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655933506	550e8400-e29b-41d4-a716-446655440042	Hadim	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hadim.bel.tr	+90 000 000 00 00	info@hadim.bel.tr	Hadim Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655934507	550e8400-e29b-41d4-a716-446655440042	Halkapınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	halkapınar.bel.tr	+90 000 000 00 00	info@halkapınar.bel.tr	Halkapınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655935508	550e8400-e29b-41d4-a716-446655440042	Hüyük	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hüyük.bel.tr	+90 000 000 00 00	info@hüyük.bel.tr	Hüyük Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655944517	550e8400-e29b-41d4-a716-446655440042	Seydişehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	seydişehir.bel.tr	+90 000 000 00 00	info@seydişehir.bel.tr	Seydişehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655569142	550e8400-e29b-41d4-a716-446655440010	Altıeylül	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	altıeylül.bel.tr	+90 000 000 00 00	info@altıeylül.bel.tr	Altıeylül Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655824397	550e8400-e29b-41d4-a716-446655440032	Gönen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gönen.bel.tr	+90 000 000 00 00	info@gönen.bel.tr	Gönen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655827400	550e8400-e29b-41d4-a716-446655440032	Senirkent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	senirkent.bel.tr	+90 000 000 00 00	info@senirkent.bel.tr	Senirkent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655828401	550e8400-e29b-41d4-a716-446655440032	Sütçüler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sütçüler.bel.tr	+90 000 000 00 00	info@sütçüler.bel.tr	Sütçüler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655936509	550e8400-e29b-41d4-a716-446655440042	Ilgın	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ilgın.bel.tr	+90 000 000 00 00	info@ilgın.bel.tr	Ilgın Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655937510	550e8400-e29b-41d4-a716-446655440042	Kadınhanı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kadınhanı.bel.tr	+90 000 000 00 00	info@kadınhanı.bel.tr	Kadınhanı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655939512	550e8400-e29b-41d4-a716-446655440042	Karatay	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karatay.bel.tr	+90 000 000 00 00	info@karatay.bel.tr	Karatay Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656193766	550e8400-e29b-41d4-a716-446655440060	Niksar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	niksar.bel.tr	+90 000 000 00 00	info@niksar.bel.tr	Niksar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655571144	550e8400-e29b-41d4-a716-446655440010	Balya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	balya.bel.tr	+90 000 000 00 00	info@balya.bel.tr	Balya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655862435	550e8400-e29b-41d4-a716-446655440036	Digor	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	digor.bel.tr	+90 000 000 00 00	info@digor.bel.tr	Digor Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655568141	550e8400-e29b-41d4-a716-446655440004	Tutak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tutak.bel.tr	+90 000 000 00 00	info@tutak.bel.tr	Tutak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655696269	550e8400-e29b-41d4-a716-446655440021	Çüngüş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çüngüş.bel.tr	+90 000 000 00 00	info@çüngüş.bel.tr	Çüngüş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655697270	550e8400-e29b-41d4-a716-446655440021	Çınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çınar.bel.tr	+90 000 000 00 00	info@çınar.bel.tr	Çınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655887460	550e8400-e29b-41d4-a716-446655440037	Şenpazar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şenpazar.bel.tr	+90 000 000 00 00	info@şenpazar.bel.tr	Şenpazar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655964537	550e8400-e29b-41d4-a716-446655440039	Babaeski	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	babaeski.bel.tr	+90 000 000 00 00	info@babaeski.bel.tr	Babaeski Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655965538	550e8400-e29b-41d4-a716-446655440039	Demirköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	demirköy.bel.tr	+90 000 000 00 00	info@demirköy.bel.tr	Demirköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655966539	550e8400-e29b-41d4-a716-446655440039	Kofçaz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kofçaz.bel.tr	+90 000 000 00 00	info@kofçaz.bel.tr	Kofçaz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655967540	550e8400-e29b-41d4-a716-446655440039	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://kırklareli.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	9c5e67f1-e78a-4fa4-b7ad-2234120a231a	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655969542	550e8400-e29b-41d4-a716-446655440039	Pehlivanköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pehlivanköy.bel.tr	+90 000 000 00 00	info@pehlivanköy.bel.tr	Pehlivanköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655970543	550e8400-e29b-41d4-a716-446655440039	Pınarhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pınarhisar.bel.tr	+90 000 000 00 00	info@pınarhisar.bel.tr	Pınarhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655466039	550e8400-e29b-41d4-a716-446655440003	Çobanlar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çobanlar.bel.tr	+90 000 000 00 00	info@çobanlar.bel.tr	Çobanlar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655480053	550e8400-e29b-41d4-a716-446655440005	Gümüşhacıköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gümüşhacıköy.bel.tr	+90 000 000 00 00	info@gümüşhacıköy.bel.tr	Gümüşhacıköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655482055	550e8400-e29b-41d4-a716-446655440005	Merzifon	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merzifon.bel.tr	+90 000 000 00 00	info@merzifon.bel.tr	Merzifon Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655560133	550e8400-e29b-41d4-a716-446655440009	İncirliova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	incirliova.bel.tr	+90 000 000 00 00	info@incirliova.bel.tr	İncirliova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655561134	550e8400-e29b-41d4-a716-446655440004	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655563136	550e8400-e29b-41d4-a716-446655440004	Doğubayazıt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğubayazıt.bel.tr	+90 000 000 00 00	info@doğubayazıt.bel.tr	Doğubayazıt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655564137	550e8400-e29b-41d4-a716-446655440004	Eleşkirt	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eleşkirt.bel.tr	+90 000 000 00 00	info@eleşkirt.bel.tr	Eleşkirt Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655570143	550e8400-e29b-41d4-a716-446655440010	Ayvalık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ayvalık.bel.tr	+90 000 000 00 00	info@ayvalık.bel.tr	Ayvalık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655573146	550e8400-e29b-41d4-a716-446655440010	Bigadiç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bigadiç.bel.tr	+90 000 000 00 00	info@bigadiç.bel.tr	Bigadiç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655574147	550e8400-e29b-41d4-a716-446655440010	Burhaniye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	burhaniye.bel.tr	+90 000 000 00 00	info@burhaniye.bel.tr	Burhaniye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655575148	550e8400-e29b-41d4-a716-446655440010	Dursunbey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dursunbey.bel.tr	+90 000 000 00 00	info@dursunbey.bel.tr	Dursunbey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655585158	550e8400-e29b-41d4-a716-446655440010	Savaştepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	savaştepe.bel.tr	+90 000 000 00 00	info@savaştepe.bel.tr	Savaştepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655587160	550e8400-e29b-41d4-a716-446655440010	Sındırgı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sındırgı.bel.tr	+90 000 000 00 00	info@sındırgı.bel.tr	Sındırgı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655589162	550e8400-e29b-41d4-a716-446655440074	Amasra	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	amasra.bel.tr	+90 000 000 00 00	info@amasra.bel.tr	Amasra Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655590163	550e8400-e29b-41d4-a716-446655440074	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655592165	550e8400-e29b-41d4-a716-446655440074	Ulus	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ulus.bel.tr	+90 000 000 00 00	info@ulus.bel.tr	Ulus Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655599172	550e8400-e29b-41d4-a716-446655440069	Aydıntepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aydıntepe.bel.tr	+90 000 000 00 00	info@aydıntepe.bel.tr	Aydıntepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655602175	550e8400-e29b-41d4-a716-446655440011	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655656229	550e8400-e29b-41d4-a716-446655440016	Orhangazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	orhangazi.bel.tr	+90 000 000 00 00	info@orhangazi.bel.tr	Orhangazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655657230	550e8400-e29b-41d4-a716-446655440016	Osmangazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	osmangazi.bel.tr	+90 000 000 00 00	info@osmangazi.bel.tr	Osmangazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655766339	550e8400-e29b-41d4-a716-446655440026	Tepebaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tepebaşı.bel.tr	+90 000 000 00 00	info@tepebaşı.bel.tr	Tepebaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655770343	550e8400-e29b-41d4-a716-446655440027	Karkamış	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karkamış.bel.tr	+90 000 000 00 00	info@karkamış.bel.tr	Karkamış Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655771344	550e8400-e29b-41d4-a716-446655440027	Nizip	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nizip.bel.tr	+90 000 000 00 00	info@nizip.bel.tr	Nizip Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655813386	550e8400-e29b-41d4-a716-446655440031	Kumlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kumlu.bel.tr	+90 000 000 00 00	info@kumlu.bel.tr	Kumlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655902475	550e8400-e29b-41d4-a716-446655440038	Özvatan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	özvatan.bel.tr	+90 000 000 00 00	info@özvatan.bel.tr	Özvatan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655909482	550e8400-e29b-41d4-a716-446655440041	Darıca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	darıca.bel.tr	+90 000 000 00 00	info@darıca.bel.tr	Darıca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655910483	550e8400-e29b-41d4-a716-446655440041	Derince	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derince.bel.tr	+90 000 000 00 00	info@derince.bel.tr	Derince Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655911484	550e8400-e29b-41d4-a716-446655440041	Dilovası	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dilovası.bel.tr	+90 000 000 00 00	info@dilovası.bel.tr	Dilovası Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655915488	550e8400-e29b-41d4-a716-446655440041	Karamürsel	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karamürsel.bel.tr	+90 000 000 00 00	info@karamürsel.bel.tr	Karamürsel Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655926499	550e8400-e29b-41d4-a716-446655440042	Cihanbeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	cihanbeyli.bel.tr	+90 000 000 00 00	info@cihanbeyli.bel.tr	Cihanbeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655868441	550e8400-e29b-41d4-a716-446655440037	Abana	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	abana.bel.tr	+90 000 000 00 00	info@abana.bel.tr	Abana Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655878451	550e8400-e29b-41d4-a716-446655440037	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655958531	550e8400-e29b-41d4-a716-446655440043	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655959532	550e8400-e29b-41d4-a716-446655440043	Pazarlar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pazarlar.bel.tr	+90 000 000 00 00	info@pazarlar.bel.tr	Pazarlar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655961534	550e8400-e29b-41d4-a716-446655440043	Tavşanlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tavşanlı.bel.tr	+90 000 000 00 00	info@tavşanlı.bel.tr	Tavşanlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655962535	550e8400-e29b-41d4-a716-446655440043	Çavdarhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çavdarhisar.bel.tr	+90 000 000 00 00	info@çavdarhisar.bel.tr	Çavdarhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655963536	550e8400-e29b-41d4-a716-446655440043	Şaphane	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şaphane.bel.tr	+90 000 000 00 00	info@şaphane.bel.tr	Şaphane Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655968541	550e8400-e29b-41d4-a716-446655440039	Lüleburgaz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	lüleburgaz.bel.tr	+90 000 000 00 00	info@lüleburgaz.bel.tr	Lüleburgaz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655973546	550e8400-e29b-41d4-a716-446655440071	Balışeyh	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	balışeyh.bel.tr	+90 000 000 00 00	info@balışeyh.bel.tr	Balışeyh Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655974547	550e8400-e29b-41d4-a716-446655440071	Delice	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	delice.bel.tr	+90 000 000 00 00	info@delice.bel.tr	Delice Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655975548	550e8400-e29b-41d4-a716-446655440071	Karakeçili	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karakeçili.bel.tr	+90 000 000 00 00	info@karakeçili.bel.tr	Karakeçili Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655979552	550e8400-e29b-41d4-a716-446655440071	Yahşihan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yahşihan.bel.tr	+90 000 000 00 00	info@yahşihan.bel.tr	Yahşihan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655980553	550e8400-e29b-41d4-a716-446655440071	Çelebi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çelebi.bel.tr	+90 000 000 00 00	info@çelebi.bel.tr	Çelebi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656021594	550e8400-e29b-41d4-a716-446655440047	Kızıltepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kızıltepe.bel.tr	+90 000 000 00 00	info@kızıltepe.bel.tr	Kızıltepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656126699	550e8400-e29b-41d4-a716-446655440054	Söğütlü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	söğütlü.bel.tr	+90 000 000 00 00	info@söğütlü.bel.tr	Söğütlü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656132705	550e8400-e29b-41d4-a716-446655440055	Bafra	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bafra.bel.tr	+90 000 000 00 00	info@bafra.bel.tr	Bafra Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655983556	550e8400-e29b-41d4-a716-446655440040	Boztepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	boztepe.bel.tr	+90 000 000 00 00	info@boztepe.bel.tr	Boztepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655984557	550e8400-e29b-41d4-a716-446655440040	Kaman	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kaman.bel.tr	+90 000 000 00 00	info@kaman.bel.tr	Kaman Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655620193	550e8400-e29b-41d4-a716-446655440013	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655894467	550e8400-e29b-41d4-a716-446655440038	Melikgazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	melikgazi.bel.tr	+90 000 000 00 00	info@melikgazi.bel.tr	Melikgazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655671244	550e8400-e29b-41d4-a716-446655440020	Kale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kale.bel.tr	+90 000 000 00 00	info@kale.bel.tr	Kale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656042615	550e8400-e29b-41d4-a716-446655440048	Dalaman	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dalaman.bel.tr	+90 000 000 00 00	info@dalaman.bel.tr	Dalaman Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656061634	550e8400-e29b-41d4-a716-446655440050	Avanos	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	avanos.bel.tr	+90 000 000 00 00	info@avanos.bel.tr	Avanos Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655567140	550e8400-e29b-41d4-a716-446655440004	Taşlıçay	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	taşlıçay.bel.tr	+90 000 000 00 00	info@taşlıçay.bel.tr	Taşlıçay Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656099672	550e8400-e29b-41d4-a716-446655440080	Toprakkale	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	toprakkale.bel.tr	+90 000 000 00 00	info@toprakkale.bel.tr	Toprakkale Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655566139	550e8400-e29b-41d4-a716-446655440004	Patnos	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	patnos.bel.tr	+90 000 000 00 00	info@patnos.bel.tr	Patnos Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655670243	550e8400-e29b-41d4-a716-446655440020	Honaz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	honaz.bel.tr	+90 000 000 00 00	info@honaz.bel.tr	Honaz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655829402	550e8400-e29b-41d4-a716-446655440032	Uluborlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	uluborlu.bel.tr	+90 000 000 00 00	info@uluborlu.bel.tr	Uluborlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655913486	550e8400-e29b-41d4-a716-446655440041	Gölcük	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gölcük.bel.tr	+90 000 000 00 00	info@gölcük.bel.tr	Gölcük Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655924497	550e8400-e29b-41d4-a716-446655440042	Beyşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	beyşehir.bel.tr	+90 000 000 00 00	info@beyşehir.bel.tr	Beyşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655927500	550e8400-e29b-41d4-a716-446655440042	Derbent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derbent.bel.tr	+90 000 000 00 00	info@derbent.bel.tr	Derbent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656104677	550e8400-e29b-41d4-a716-446655440053	Hemşin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hemşin.bel.tr	+90 000 000 00 00	info@hemşin.bel.tr	Hemşin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656105678	550e8400-e29b-41d4-a716-446655440053	Kalkandere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kalkandere.bel.tr	+90 000 000 00 00	info@kalkandere.bel.tr	Kalkandere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655605178	550e8400-e29b-41d4-a716-446655440011	Osmaneli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	osmaneli.bel.tr	+90 000 000 00 00	info@osmaneli.bel.tr	Osmaneli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655838411	550e8400-e29b-41d4-a716-446655440046	Andırın	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	andırın.bel.tr	+90 000 000 00 00	info@andırın.bel.tr	Andırın Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655840413	550e8400-e29b-41d4-a716-446655440046	Ekinözü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ekinözü.bel.tr	+90 000 000 00 00	info@ekinözü.bel.tr	Ekinözü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655907480	550e8400-e29b-41d4-a716-446655440079	Polateli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	polateli.bel.tr	+90 000 000 00 00	info@polateli.bel.tr	Polateli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655522095	550e8400-e29b-41d4-a716-446655440007	Konyaaltı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	konyaaltı.bel.tr	+90 000 000 00 00	info@konyaaltı.bel.tr	Konyaaltı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655540113	550e8400-e29b-41d4-a716-446655440008	Kemalpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kemalpaşa.bel.tr	+90 000 000 00 00	info@kemalpaşa.bel.tr	Kemalpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655615188	550e8400-e29b-41d4-a716-446655440012	Solhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	solhan.bel.tr	+90 000 000 00 00	info@solhan.bel.tr	Solhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656174747	550e8400-e29b-41d4-a716-446655440058	Yıldızeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yıldızeli.bel.tr	+90 000 000 00 00	info@yıldızeli.bel.tr	Yıldızeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655619192	550e8400-e29b-41d4-a716-446655440013	Ahlat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ahlat.bel.tr	+90 000 000 00 00	info@ahlat.bel.tr	Ahlat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655819392	550e8400-e29b-41d4-a716-446655440031	İskenderun	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	iskenderun.bel.tr	+90 000 000 00 00	info@iskenderun.bel.tr	İskenderun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656171744	550e8400-e29b-41d4-a716-446655440058	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656183756	550e8400-e29b-41d4-a716-446655440059	Muratlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	muratlı.bel.tr	+90 000 000 00 00	info@muratlı.bel.tr	Muratlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656214787	550e8400-e29b-41d4-a716-446655440061	Vakfıkebir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	vakfıkebir.bel.tr	+90 000 000 00 00	info@vakfıkebir.bel.tr	Vakfıkebir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656215788	550e8400-e29b-41d4-a716-446655440061	Yomra	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yomra.bel.tr	+90 000 000 00 00	info@yomra.bel.tr	Yomra Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656216789	550e8400-e29b-41d4-a716-446655440061	Çarşıbaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çarşıbaşı.bel.tr	+90 000 000 00 00	info@çarşıbaşı.bel.tr	Çarşıbaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656217790	550e8400-e29b-41d4-a716-446655440061	Çaykara	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çaykara.bel.tr	+90 000 000 00 00	info@çaykara.bel.tr	Çaykara Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655508081	550e8400-e29b-41d4-a716-446655440006	Çubuk	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çubuk.bel.tr	+90 000 000 00 00	info@çubuk.bel.tr	Çubuk Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655509082	550e8400-e29b-41d4-a716-446655440006	Şereflikoçhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şereflikoçhisar.bel.tr	+90 000 000 00 00	info@şereflikoçhisar.bel.tr	Şereflikoçhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655511084	550e8400-e29b-41d4-a716-446655440007	Aksu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aksu.bel.tr	+90 000 000 00 00	info@aksu.bel.tr	Aksu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655565138	550e8400-e29b-41d4-a716-446655440004	Hamur	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hamur.bel.tr	+90 000 000 00 00	info@hamur.bel.tr	Hamur Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655988561	550e8400-e29b-41d4-a716-446655440044	Akçadağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akçadağ.bel.tr	+90 000 000 00 00	info@akçadağ.bel.tr	Akçadağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656014587	550e8400-e29b-41d4-a716-446655440045	Soma	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	soma.bel.tr	+90 000 000 00 00	info@soma.bel.tr	Soma Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656015588	550e8400-e29b-41d4-a716-446655440045	Turgutlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	turgutlu.bel.tr	+90 000 000 00 00	info@turgutlu.bel.tr	Turgutlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656245818	550e8400-e29b-41d4-a716-446655440065	İpekyolu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ipekyolu.bel.tr	+90 000 000 00 00	info@ipekyolu.bel.tr	İpekyolu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655454027	550e8400-e29b-41d4-a716-446655440003	Başmakçı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	başmakçı.bel.tr	+90 000 000 00 00	info@başmakçı.bel.tr	Başmakçı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655512085	550e8400-e29b-41d4-a716-446655440007	Alanya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alanya.bel.tr	+90 000 000 00 00	info@alanya.bel.tr	Alanya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655692265	550e8400-e29b-41d4-a716-446655440021	Silvan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	silvan.bel.tr	+90 000 000 00 00	info@silvan.bel.tr	Silvan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655879452	550e8400-e29b-41d4-a716-446655440037	Küre	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	küre.bel.tr	+90 000 000 00 00	info@küre.bel.tr	Küre Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656007580	550e8400-e29b-41d4-a716-446655440045	Kula	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kula.bel.tr	+90 000 000 00 00	info@kula.bel.tr	Kula Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656247820	550e8400-e29b-41d4-a716-446655440077	Armutlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	armutlu.bel.tr	+90 000 000 00 00	info@armutlu.bel.tr	Armutlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656248821	550e8400-e29b-41d4-a716-446655440077	Termal	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	termal.bel.tr	+90 000 000 00 00	info@termal.bel.tr	Termal Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656249822	550e8400-e29b-41d4-a716-446655440077	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655492065	550e8400-e29b-41d4-a716-446655440006	Evren	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	evren.bel.tr	+90 000 000 00 00	info@evren.bel.tr	Evren Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655505078	550e8400-e29b-41d4-a716-446655440006	Yenimahalle	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yenimahalle.bel.tr	+90 000 000 00 00	info@yenimahalle.bel.tr	Yenimahalle Belediyesi, Türkiye	https://kurumsalkimlik.chp.org.tr/images/web-bant.svg	https://timelinecovers.pro/facebook-cover/thumbs540/grey-texture-facebook-cover.jpg	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656251824	550e8400-e29b-41d4-a716-446655440077	Çınarcık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çınarcık.bel.tr	+90 000 000 00 00	info@çınarcık.bel.tr	Çınarcık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656253826	550e8400-e29b-41d4-a716-446655440066	Aydıncık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aydıncık.bel.tr	+90 000 000 00 00	info@aydıncık.bel.tr	Aydıncık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655882455	550e8400-e29b-41d4-a716-446655440037	Taşköprü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	taşköprü.bel.tr	+90 000 000 00 00	info@taşköprü.bel.tr	Taşköprü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656326899	550e8400-e29b-41d4-a716-446655440034	Esenler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	esenler.bel.tr	+90 000 000 00 00	info@esenler.bel.tr	Esenler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655470043	550e8400-e29b-41d4-a716-446655440068	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655537110	550e8400-e29b-41d4-a716-446655440008	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655538111	550e8400-e29b-41d4-a716-446655440008	Borçka	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	borçka.bel.tr	+90 000 000 00 00	info@borçka.bel.tr	Borçka Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655539112	550e8400-e29b-41d4-a716-446655440008	Hopa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hopa.bel.tr	+90 000 000 00 00	info@hopa.bel.tr	Hopa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656017590	550e8400-e29b-41d4-a716-446655440045	Şehzadeler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şehzadeler.bel.tr	+90 000 000 00 00	info@şehzadeler.bel.tr	Şehzadeler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656053626	550e8400-e29b-41d4-a716-446655440048	Yatağan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yatağan.bel.tr	+90 000 000 00 00	info@yatağan.bel.tr	Yatağan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656147720	550e8400-e29b-41d4-a716-446655440056	Kurtalan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kurtalan.bel.tr	+90 000 000 00 00	info@kurtalan.bel.tr	Kurtalan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656148721	550e8400-e29b-41d4-a716-446655440056	Pervari	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pervari.bel.tr	+90 000 000 00 00	info@pervari.bel.tr	Pervari Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655660233	550e8400-e29b-41d4-a716-446655440016	İnegöl	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	inegöl.bel.tr	+90 000 000 00 00	info@inegöl.bel.tr	İnegöl Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655825398	550e8400-e29b-41d4-a716-446655440032	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655841414	550e8400-e29b-41d4-a716-446655440046	Elbistan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	elbistan.bel.tr	+90 000 000 00 00	info@elbistan.bel.tr	Elbistan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655889462	550e8400-e29b-41d4-a716-446655440038	Bünyan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bünyan.bel.tr	+90 000 000 00 00	info@bünyan.bel.tr	Bünyan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655903476	550e8400-e29b-41d4-a716-446655440038	İncesu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	incesu.bel.tr	+90 000 000 00 00	info@incesu.bel.tr	İncesu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655971544	550e8400-e29b-41d4-a716-446655440039	Vize	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	vize.bel.tr	+90 000 000 00 00	info@vize.bel.tr	Vize Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656047620	550e8400-e29b-41d4-a716-446655440048	Marmaris	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	marmaris.bel.tr	+90 000 000 00 00	info@marmaris.bel.tr	Marmaris Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656096669	550e8400-e29b-41d4-a716-446655440080	Kadirli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kadirli.bel.tr	+90 000 000 00 00	info@kadirli.bel.tr	Kadirli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655513086	550e8400-e29b-41d4-a716-446655440007	Demre	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	demre.bel.tr	+90 000 000 00 00	info@demre.bel.tr	Demre Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655521094	550e8400-e29b-41d4-a716-446655440007	Kepez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kepez.bel.tr	+90 000 000 00 00	info@kepez.bel.tr	Kepez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655576149	550e8400-e29b-41d4-a716-446655440010	Edremit	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	edremit.bel.tr	+90 000 000 00 00	info@edremit.bel.tr	Edremit Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655866439	550e8400-e29b-41d4-a716-446655440036	Selim	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	selim.bel.tr	+90 000 000 00 00	info@selim.bel.tr	Selim Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655867440	550e8400-e29b-41d4-a716-446655440036	Susuz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	susuz.bel.tr	+90 000 000 00 00	info@susuz.bel.tr	Susuz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655884457	550e8400-e29b-41d4-a716-446655440037	Çatalzeytin	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çatalzeytin.bel.tr	+90 000 000 00 00	info@çatalzeytin.bel.tr	Çatalzeytin Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655885458	550e8400-e29b-41d4-a716-446655440037	İhsangazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ihsangazi.bel.tr	+90 000 000 00 00	info@ihsangazi.bel.tr	İhsangazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655892465	550e8400-e29b-41d4-a716-446655440038	Hacılar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hacılar.bel.tr	+90 000 000 00 00	info@hacılar.bel.tr	Hacılar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656396969	550e8400-e29b-41d4-a716-446655440073	Güçlükonak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güçlükonak.bel.tr	+90 000 000 00 00	info@güçlükonak.bel.tr	Güçlükonak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656397970	550e8400-e29b-41d4-a716-446655440073	Silopi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	silopi.bel.tr	+90 000 000 00 00	info@silopi.bel.tr	Silopi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656399972	550e8400-e29b-41d4-a716-446655440073	İdil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	idil.bel.tr	+90 000 000 00 00	info@idil.bel.tr	İdil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655631204	550e8400-e29b-41d4-a716-446655440014	Mudurnu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mudurnu.bel.tr	+90 000 000 00 00	info@mudurnu.bel.tr	Mudurnu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655635208	550e8400-e29b-41d4-a716-446655440015	Ağlasun	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ağlasun.bel.tr	+90 000 000 00 00	info@ağlasun.bel.tr	Ağlasun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656013586	550e8400-e29b-41d4-a716-446655440045	Selendi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	selendi.bel.tr	+90 000 000 00 00	info@selendi.bel.tr	Selendi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656395968	550e8400-e29b-41d4-a716-446655440073	Cizre	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	cizre.bel.tr	+90 000 000 00 00	info@cizre.bel.tr	Cizre Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656018591	550e8400-e29b-41d4-a716-446655440047	Artuklu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	artuklu.bel.tr	+90 000 000 00 00	info@artuklu.bel.tr	Artuklu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656020593	550e8400-e29b-41d4-a716-446655440047	Derik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	derik.bel.tr	+90 000 000 00 00	info@derik.bel.tr	Derik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656030603	550e8400-e29b-41d4-a716-446655440033	Aydıncık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aydıncık.bel.tr	+90 000 000 00 00	info@aydıncık.bel.tr	Aydıncık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656306879	550e8400-e29b-41d4-a716-446655440019	Osmancık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	osmancık.bel.tr	+90 000 000 00 00	info@osmancık.bel.tr	Osmancık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656031604	550e8400-e29b-41d4-a716-446655440033	Bozyazı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	bozyazı.bel.tr	+90 000 000 00 00	info@bozyazı.bel.tr	Bozyazı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656032605	550e8400-e29b-41d4-a716-446655440033	Erdemli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erdemli.bel.tr	+90 000 000 00 00	info@erdemli.bel.tr	Erdemli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655588161	550e8400-e29b-41d4-a716-446655440010	İvrindi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ivrindi.bel.tr	+90 000 000 00 00	info@ivrindi.bel.tr	İvrindi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655461034	550e8400-e29b-41d4-a716-446655440003	Kızılören	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kızılören.bel.tr	+90 000 000 00 00	info@kızılören.bel.tr	Kızılören Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656142715	550e8400-e29b-41d4-a716-446655440055	Yakakent	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yakakent.bel.tr	+90 000 000 00 00	info@yakakent.bel.tr	Yakakent Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655465038	550e8400-e29b-41d4-a716-446655440003	Çay	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çay.bel.tr	+90 000 000 00 00	info@çay.bel.tr	Çay Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655772345	550e8400-e29b-41d4-a716-446655440027	Nurdağı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nurdağı.bel.tr	+90 000 000 00 00	info@nurdağı.bel.tr	Nurdağı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655850423	550e8400-e29b-41d4-a716-446655440078	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656173746	550e8400-e29b-41d4-a716-446655440058	Ulaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ulaş.bel.tr	+90 000 000 00 00	info@ulaş.bel.tr	Ulaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656189762	550e8400-e29b-41d4-a716-446655440060	Almus	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	almus.bel.tr	+90 000 000 00 00	info@almus.bel.tr	Almus Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656190763	550e8400-e29b-41d4-a716-446655440060	Artova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	artova.bel.tr	+90 000 000 00 00	info@artova.bel.tr	Artova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656192765	550e8400-e29b-41d4-a716-446655440060	Erbaa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	erbaa.bel.tr	+90 000 000 00 00	info@erbaa.bel.tr	Erbaa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656241814	550e8400-e29b-41d4-a716-446655440065	Tuşba	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tuşba.bel.tr	+90 000 000 00 00	info@tuşba.bel.tr	Tuşba Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656242815	550e8400-e29b-41d4-a716-446655440065	Çaldıran	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çaldıran.bel.tr	+90 000 000 00 00	info@çaldıran.bel.tr	Çaldıran Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656255828	550e8400-e29b-41d4-a716-446655440066	Kadışehri	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kadışehri.bel.tr	+90 000 000 00 00	info@kadışehri.bel.tr	Kadışehri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656271844	550e8400-e29b-41d4-a716-446655440067	Kozlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kozlu.bel.tr	+90 000 000 00 00	info@kozlu.bel.tr	Kozlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655494067	550e8400-e29b-41d4-a716-446655440006	Güdül	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güdül.bel.tr	+90 000 000 00 00	info@güdül.bel.tr	Güdül Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655616189	550e8400-e29b-41d4-a716-446655440012	Yayladere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yayladere.bel.tr	+90 000 000 00 00	info@yayladere.bel.tr	Yayladere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656333906	550e8400-e29b-41d4-a716-446655440034	Kartal	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kartal.bel.tr	+90 000 000 00 00	info@kartal.bel.tr	Kartal Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656335908	550e8400-e29b-41d4-a716-446655440034	Küçükçekmece	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	küçükçekmece.bel.tr	+90 000 000 00 00	info@küçükçekmece.bel.tr	Küçükçekmece Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656337910	550e8400-e29b-41d4-a716-446655440034	Pendik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pendik.bel.tr	+90 000 000 00 00	info@pendik.bel.tr	Pendik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656338911	550e8400-e29b-41d4-a716-446655440034	Sancaktepe	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sancaktepe.bel.tr	+90 000 000 00 00	info@sancaktepe.bel.tr	Sancaktepe Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656339912	550e8400-e29b-41d4-a716-446655440034	Sarıyer	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıyer.bel.tr	+90 000 000 00 00	info@sarıyer.bel.tr	Sarıyer Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656340913	550e8400-e29b-41d4-a716-446655440034	Silivri	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	silivri.bel.tr	+90 000 000 00 00	info@silivri.bel.tr	Silivri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656341914	550e8400-e29b-41d4-a716-446655440034	Sultanbeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sultanbeyli.bel.tr	+90 000 000 00 00	info@sultanbeyli.bel.tr	Sultanbeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656342915	550e8400-e29b-41d4-a716-446655440034	Sultangazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sultangazi.bel.tr	+90 000 000 00 00	info@sultangazi.bel.tr	Sultangazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656345918	550e8400-e29b-41d4-a716-446655440034	Çatalca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çatalca.bel.tr	+90 000 000 00 00	info@çatalca.bel.tr	Çatalca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656350923	550e8400-e29b-41d4-a716-446655440034	Şişli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şişli.bel.tr	+90 000 000 00 00	info@şişli.bel.tr	Şişli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655783356	550e8400-e29b-41d4-a716-446655440028	Eynesil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eynesil.bel.tr	+90 000 000 00 00	info@eynesil.bel.tr	Eynesil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655784357	550e8400-e29b-41d4-a716-446655440028	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655785358	550e8400-e29b-41d4-a716-446655440028	Görele	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	görele.bel.tr	+90 000 000 00 00	info@görele.bel.tr	Görele Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655786359	550e8400-e29b-41d4-a716-446655440028	Güce	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	güce.bel.tr	+90 000 000 00 00	info@güce.bel.tr	Güce Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656384957	550e8400-e29b-41d4-a716-446655440063	Ceylanpınar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ceylanpınar.bel.tr	+90 000 000 00 00	info@ceylanpınar.bel.tr	Ceylanpınar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656385958	550e8400-e29b-41d4-a716-446655440063	Eyyübiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eyyübiye.bel.tr	+90 000 000 00 00	info@eyyübiye.bel.tr	Eyyübiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656386959	550e8400-e29b-41d4-a716-446655440063	Halfeti	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	halfeti.bel.tr	+90 000 000 00 00	info@halfeti.bel.tr	Halfeti Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656387960	550e8400-e29b-41d4-a716-446655440063	Haliliye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	haliliye.bel.tr	+90 000 000 00 00	info@haliliye.bel.tr	Haliliye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655442015	550e8400-e29b-41d4-a716-446655440001	İmamoğlu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	imamoğlu.bel.tr	+90 000 000 00 00	info@imamoğlu.bel.tr	İmamoğlu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655582155	550e8400-e29b-41d4-a716-446655440010	Kepsut	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kepsut.bel.tr	+90 000 000 00 00	info@kepsut.bel.tr	Kepsut Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655606179	550e8400-e29b-41d4-a716-446655440011	Pazaryeri	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pazaryeri.bel.tr	+90 000 000 00 00	info@pazaryeri.bel.tr	Pazaryeri Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655629202	550e8400-e29b-41d4-a716-446655440014	Kıbrıscık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kıbrıscık.bel.tr	+90 000 000 00 00	info@kıbrıscık.bel.tr	Kıbrıscık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655816389	550e8400-e29b-41d4-a716-446655440031	Reyhanlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	reyhanlı.bel.tr	+90 000 000 00 00	info@reyhanlı.bel.tr	Reyhanlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655817390	550e8400-e29b-41d4-a716-446655440031	Samandağ	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	samandağ.bel.tr	+90 000 000 00 00	info@samandağ.bel.tr	Samandağ Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655818391	550e8400-e29b-41d4-a716-446655440031	Yayladağı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yayladağı.bel.tr	+90 000 000 00 00	info@yayladağı.bel.tr	Yayladağı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656400973	550e8400-e29b-41d4-a716-446655440073	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	https://kırklareli.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	DEM Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/DEM_PART%C4%B0_LOGOSU.png/250px-DEM_PART%C4%B0_LOGOSU.png	0	{}	ilçe	a3b613a3-500d-41b2-8603-25cb25b0459f	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655579152	550e8400-e29b-41d4-a716-446655440010	Gönen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gönen.bel.tr	+90 000 000 00 00	info@gönen.bel.tr	Gönen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655583156	550e8400-e29b-41d4-a716-446655440010	Manyas	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	manyas.bel.tr	+90 000 000 00 00	info@manyas.bel.tr	Manyas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655611184	550e8400-e29b-41d4-a716-446655440012	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655672245	550e8400-e29b-41d4-a716-446655440020	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655622195	550e8400-e29b-41d4-a716-446655440013	Hizan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hizan.bel.tr	+90 000 000 00 00	info@hizan.bel.tr	Hizan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655623196	550e8400-e29b-41d4-a716-446655440013	Mutki	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mutki.bel.tr	+90 000 000 00 00	info@mutki.bel.tr	Mutki Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655586159	550e8400-e29b-41d4-a716-446655440010	Susurluk	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	susurluk.bel.tr	+90 000 000 00 00	info@susurluk.bel.tr	Susurluk Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655527100	550e8400-e29b-41d4-a716-446655440007	Serik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	serik.bel.tr	+90 000 000 00 00	info@serik.bel.tr	Serik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655547120	550e8400-e29b-41d4-a716-446655440009	Efeler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	efeler.bel.tr	+90 000 000 00 00	info@efeler.bel.tr	Efeler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655734307	550e8400-e29b-41d4-a716-446655440024	İliç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	iliç.bel.tr	+90 000 000 00 00	info@iliç.bel.tr	İliç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655735308	550e8400-e29b-41d4-a716-446655440025	Aziziye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	aziziye.bel.tr	+90 000 000 00 00	info@aziziye.bel.tr	Aziziye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655729302	550e8400-e29b-41d4-a716-446655440024	Otlukbeli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	otlukbeli.bel.tr	+90 000 000 00 00	info@otlukbeli.bel.tr	Otlukbeli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655680253	550e8400-e29b-41d4-a716-446655440020	Çivril	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çivril.bel.tr	+90 000 000 00 00	info@çivril.bel.tr	Çivril Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655686259	550e8400-e29b-41d4-a716-446655440021	Hani	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hani.bel.tr	+90 000 000 00 00	info@hani.bel.tr	Hani Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655645218	550e8400-e29b-41d4-a716-446655440016	Büyükorhan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	büyükorhan.bel.tr	+90 000 000 00 00	info@büyükorhan.bel.tr	Büyükorhan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655646219	550e8400-e29b-41d4-a716-446655440016	Gemlik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gemlik.bel.tr	+90 000 000 00 00	info@gemlik.bel.tr	Gemlik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655648221	550e8400-e29b-41d4-a716-446655440016	Harmancık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	harmancık.bel.tr	+90 000 000 00 00	info@harmancık.bel.tr	Harmancık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655649222	550e8400-e29b-41d4-a716-446655440016	Karacabey	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karacabey.bel.tr	+90 000 000 00 00	info@karacabey.bel.tr	Karacabey Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656298871	550e8400-e29b-41d4-a716-446655440019	Alaca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	alaca.bel.tr	+90 000 000 00 00	info@alaca.bel.tr	Alaca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656371944	550e8400-e29b-41d4-a716-446655440035	Menemen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	menemen.bel.tr	+90 000 000 00 00	info@menemen.bel.tr	Menemen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656372945	550e8400-e29b-41d4-a716-446655440035	Narlıdere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	narlıdere.bel.tr	+90 000 000 00 00	info@narlıdere.bel.tr	Narlıdere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656398971	550e8400-e29b-41d4-a716-446655440073	Uludere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	uludere.bel.tr	+90 000 000 00 00	info@uludere.bel.tr	Uludere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655675248	550e8400-e29b-41d4-a716-446655440020	Serinhisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	serinhisar.bel.tr	+90 000 000 00 00	info@serinhisar.bel.tr	Serinhisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655676249	550e8400-e29b-41d4-a716-446655440020	Tavas	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tavas.bel.tr	+90 000 000 00 00	info@tavas.bel.tr	Tavas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440005	550e8400-e29b-41d4-a716-446655440001	Karataş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karataş.bel.tr	+90 000 000 00 00	info@karataş.bel.tr	Karataş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655922495	550e8400-e29b-41d4-a716-446655440042	Akşehir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akşehir.bel.tr	+90 000 000 00 00	info@akşehir.bel.tr	Akşehir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656027600	550e8400-e29b-41d4-a716-446655440047	Ömerli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ömerli.bel.tr	+90 000 000 00 00	info@ömerli.bel.tr	Ömerli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656028601	550e8400-e29b-41d4-a716-446655440033	Akdeniz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	akdeniz.bel.tr	+90 000 000 00 00	info@akdeniz.bel.tr	Akdeniz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655749322	550e8400-e29b-41d4-a716-446655440025	Tortum	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	tortum.bel.tr	+90 000 000 00 00	info@tortum.bel.tr	Tortum Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655750323	550e8400-e29b-41d4-a716-446655440025	Uzundere	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	uzundere.bel.tr	+90 000 000 00 00	info@uzundere.bel.tr	Uzundere Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655751324	550e8400-e29b-41d4-a716-446655440025	Yakutiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yakutiye.bel.tr	+90 000 000 00 00	info@yakutiye.bel.tr	Yakutiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655752325	550e8400-e29b-41d4-a716-446655440025	Çat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çat.bel.tr	+90 000 000 00 00	info@çat.bel.tr	Çat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655760333	550e8400-e29b-41d4-a716-446655440026	Mihalgazi	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mihalgazi.bel.tr	+90 000 000 00 00	info@mihalgazi.bel.tr	Mihalgazi Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655761334	550e8400-e29b-41d4-a716-446655440026	Mihalıççık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mihalıççık.bel.tr	+90 000 000 00 00	info@mihalıççık.bel.tr	Mihalıççık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655762335	550e8400-e29b-41d4-a716-446655440026	Odunpazarı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	odunpazarı.bel.tr	+90 000 000 00 00	info@odunpazarı.bel.tr	Odunpazarı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655763336	550e8400-e29b-41d4-a716-446655440026	Sarıcakaya	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıcakaya.bel.tr	+90 000 000 00 00	info@sarıcakaya.bel.tr	Sarıcakaya Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655767340	550e8400-e29b-41d4-a716-446655440026	Çifteler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	çifteler.bel.tr	+90 000 000 00 00	info@çifteler.bel.tr	Çifteler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655768341	550e8400-e29b-41d4-a716-446655440026	İnönü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	inönü.bel.tr	+90 000 000 00 00	info@inönü.bel.tr	İnönü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656123696	550e8400-e29b-41d4-a716-446655440054	Pamukova	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	pamukova.bel.tr	+90 000 000 00 00	info@pamukova.bel.tr	Pamukova Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655617190	550e8400-e29b-41d4-a716-446655440012	Yedisu	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	yedisu.bel.tr	+90 000 000 00 00	info@yedisu.bel.tr	Yedisu Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656185758	550e8400-e29b-41d4-a716-446655440059	Süleymanpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	süleymanpaşa.bel.tr	+90 000 000 00 00	info@süleymanpaşa.bel.tr	Süleymanpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656124697	550e8400-e29b-41d4-a716-446655440054	Sapanca	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sapanca.bel.tr	+90 000 000 00 00	info@sapanca.bel.tr	Sapanca Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656127700	550e8400-e29b-41d4-a716-446655440054	Taraklı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	taraklı.bel.tr	+90 000 000 00 00	info@taraklı.bel.tr	Taraklı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656130703	550e8400-e29b-41d4-a716-446655440055	Atakum	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	atakum.bel.tr	+90 000 000 00 00	info@atakum.bel.tr	Atakum Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655519092	550e8400-e29b-41d4-a716-446655440007	Kaş	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kaş.bel.tr	+90 000 000 00 00	info@kaş.bel.tr	Kaş Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655842415	550e8400-e29b-41d4-a716-446655440046	Göksun	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	göksun.bel.tr	+90 000 000 00 00	info@göksun.bel.tr	Göksun Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655843416	550e8400-e29b-41d4-a716-446655440046	Nurhak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	nurhak.bel.tr	+90 000 000 00 00	info@nurhak.bel.tr	Nurhak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655858431	550e8400-e29b-41d4-a716-446655440070	Kazımkarabekir	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kazımkarabekir.bel.tr	+90 000 000 00 00	info@kazımkarabekir.bel.tr	Kazımkarabekir Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656207780	550e8400-e29b-41d4-a716-446655440061	Hayrat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hayrat.bel.tr	+90 000 000 00 00	info@hayrat.bel.tr	Hayrat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656208781	550e8400-e29b-41d4-a716-446655440061	Köprübaşı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	köprübaşı.bel.tr	+90 000 000 00 00	info@köprübaşı.bel.tr	Köprübaşı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656382955	550e8400-e29b-41d4-a716-446655440063	Birecik	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	birecik.bel.tr	+90 000 000 00 00	info@birecik.bel.tr	Birecik Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656366939	550e8400-e29b-41d4-a716-446655440035	Kemalpaşa	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kemalpaşa.bel.tr	+90 000 000 00 00	info@kemalpaşa.bel.tr	Kemalpaşa Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656367940	550e8400-e29b-41d4-a716-446655440035	Kiraz	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kiraz.bel.tr	+90 000 000 00 00	info@kiraz.bel.tr	Kiraz Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655440003	550e8400-e29b-41d4-a716-446655440001	Feke	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	feke.bel.tr	+90 000 000 00 00	info@feke.bel.tr	Feke Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655591164	550e8400-e29b-41d4-a716-446655440074	Kurucaşile	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kurucaşile.bel.tr	+90 000 000 00 00	info@kurucaşile.bel.tr	Kurucaşile Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	1	0	0	0.00	2025-05-23 22:02:38.843017+00
660e8400-e29b-41d4-a716-446655741314	550e8400-e29b-41d4-a716-446655440025	Köprüköy	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	köprüköy.bel.tr	+90 000 000 00 00	info@köprüköy.bel.tr	Köprüköy Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656210783	550e8400-e29b-41d4-a716-446655440061	Of	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	of.bel.tr	+90 000 000 00 00	info@of.bel.tr	Of Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655498071	550e8400-e29b-41d4-a716-446655440006	Keçiören	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	keçiören.bel.tr	+90 000 000 00 00	info@keçiören.bel.tr	Keçiören Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655960533	550e8400-e29b-41d4-a716-446655440043	Simav	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	simav.bel.tr	+90 000 000 00 00	info@simav.bel.tr	Simav Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656114687	550e8400-e29b-41d4-a716-446655440054	Arifiye	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	arifiye.bel.tr	+90 000 000 00 00	info@arifiye.bel.tr	Arifiye Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655871444	550e8400-e29b-41d4-a716-446655440037	Ağlı	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ağlı.bel.tr	+90 000 000 00 00	info@ağlı.bel.tr	Ağlı Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656019592	550e8400-e29b-41d4-a716-446655440047	Dargeçit	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dargeçit.bel.tr	+90 000 000 00 00	info@dargeçit.bel.tr	Dargeçit Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655637210	550e8400-e29b-41d4-a716-446655440015	Merkez	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	merkez.bel.tr	+90 000 000 00 00	info@merkez.bel.tr	Merkez Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655832405	550e8400-e29b-41d4-a716-446655440032	Şarkikaraağaç	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	şarkikaraağaç.bel.tr	+90 000 000 00 00	info@şarkikaraağaç.bel.tr	Şarkikaraağaç Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655500073	550e8400-e29b-41d4-a716-446655440006	Mamak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	mamak.bel.tr	+90 000 000 00 00	info@mamak.bel.tr	Mamak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655525098	550e8400-e29b-41d4-a716-446655440007	Manavgat	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	manavgat.bel.tr	+90 000 000 00 00	info@manavgat.bel.tr	Manavgat Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655957530	550e8400-e29b-41d4-a716-446655440043	Hisarcık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hisarcık.bel.tr	+90 000 000 00 00	info@hisarcık.bel.tr	Hisarcık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656368941	550e8400-e29b-41d4-a716-446655440035	Konak	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	konak.bel.tr	+90 000 000 00 00	info@konak.bel.tr	Konak Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656369942	550e8400-e29b-41d4-a716-446655440035	Kınık	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	kınık.bel.tr	+90 000 000 00 00	info@kınık.bel.tr	Kınık Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656388961	550e8400-e29b-41d4-a716-446655440063	Harran	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	harran.bel.tr	+90 000 000 00 00	info@harran.bel.tr	Harran Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656389962	550e8400-e29b-41d4-a716-446655440063	Hilvan	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	hilvan.bel.tr	+90 000 000 00 00	info@hilvan.bel.tr	Hilvan Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656154727	550e8400-e29b-41d4-a716-446655440057	Dikmen	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	dikmen.bel.tr	+90 000 000 00 00	info@dikmen.bel.tr	Dikmen Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656167740	550e8400-e29b-41d4-a716-446655440058	Gürün	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	gürün.bel.tr	+90 000 000 00 00	info@gürün.bel.tr	Gürün Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655472045	550e8400-e29b-41d4-a716-446655440068	Eskil	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	eskil.bel.tr	+90 000 000 00 00	info@eskil.bel.tr	Eskil Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656164737	550e8400-e29b-41d4-a716-446655440058	Doğanşar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	doğanşar.bel.tr	+90 000 000 00 00	info@doğanşar.bel.tr	Doğanşar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655904477	550e8400-e29b-41d4-a716-446655440079	Elbeyli	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	elbeyli.bel.tr	+90 000 000 00 00	info@elbeyli.bel.tr	Elbeyli Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655495068	550e8400-e29b-41d4-a716-446655440006	Haymana	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	haymana.bel.tr	+90 000 000 00 00	info@haymana.bel.tr	Haymana Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655859432	550e8400-e29b-41d4-a716-446655440070	Sarıveliler	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sarıveliler.bel.tr	+90 000 000 00 00	info@sarıveliler.bel.tr	Sarıveliler Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656267840	550e8400-e29b-41d4-a716-446655440067	Devrek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	devrek.bel.tr	+90 000 000 00 00	info@devrek.bel.tr	Devrek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446655815388	550e8400-e29b-41d4-a716-446655440031	Payas	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	payas.bel.tr	+90 000 000 00 00	info@payas.bel.tr	Payas Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656211784	550e8400-e29b-41d4-a716-446655440061	Ortahisar	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	ortahisar.bel.tr	+90 000 000 00 00	info@ortahisar.bel.tr	Ortahisar Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656212785	550e8400-e29b-41d4-a716-446655440061	Sürmene	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	sürmene.bel.tr	+90 000 000 00 00	info@sürmene.bel.tr	Sürmene Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656377950	550e8400-e29b-41d4-a716-446655440035	Urla	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	urla.bel.tr	+90 000 000 00 00	info@urla.bel.tr	Urla Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656390963	550e8400-e29b-41d4-a716-446655440063	Karaköprü	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	karaköprü.bel.tr	+90 000 000 00 00	info@karaköprü.bel.tr	Karaköprü Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
660e8400-e29b-41d4-a716-446656391964	550e8400-e29b-41d4-a716-446655440063	Siverek	2025-05-08 22:15:39.978328+00	2025-05-23 06:00:00.073489	siverek.bel.tr	+90 000 000 00 00	info@siverek.bel.tr	Siverek Belediyesi, Türkiye	https://cdn-icons-png.flaticon.com/512/5038/5038590.png	https://cdn.pixabay.com/photo/2017/03/31/12/16/cover-2191228_1280.png	Bilgi Yok	Bilgi Yok	https://cdn.vectorstock.com/i/500p/97/05/demo-video-icon-set-room-conference-vector-52929705.jpg	0	{}	ilçe	\N	\N	0	0	0	0.00	2025-05-19 20:01:32.38517+00
\.


--
-- Data for Name: featured_posts; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.featured_posts (id, post_id, user_id, created_at) FROM stdin;
29	46613d25-2635-47a1-9ddc-eed39694edf5	83190944-98d5-41be-ac3a-178676faf017	2025-05-23 08:24:09.191509+00
31	82ad7704-2910-4e8c-97e8-8ed9f7ca224d	8b52a8cb-cb89-4325-9c62-de454a0476fb	2025-05-23 22:57:45.958687+00
\.


--
-- Data for Name: likes; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.likes (id, post_id, user_id, created_at) FROM stdin;
\.


--
-- Data for Name: municipalities_zafer; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.municipalities_zafer (id, name, type, parent_id, cover_image_url, logo_url, mayor_name, mayor_party, party_logo_url, population, phone, website, email, address, social_media_links, created_at, updated_at) FROM stdin;
57394a52-0166-4f1b-9625-20dbf80765a0	Kadıköy	ilçe	599e1d45-cb63-4d99-a7fb-c3b4b7e58a74	https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRLYjetkcwzXZnrDfVq00e2Ybz_HpkAOX-clg&s	https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTT2hm1sDxSdoq5W33CwHi8XvzIyZctnhzQXw&s	Şerdil Dara Odabaşı	CHP	https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Cumhuriyet_Halk_Partisi_Logo.svg/250px-Cumhuriyet_Halk_Partisi_Logo.svg.png	500000	0216 542 50 00	https://www.kadikoy.bel.tr	onerisikayet@kadikoy.bel.tr	Hasanpaşa Mah. Fahrettin Kerim Gökay Cad. No:2 Kadıköy, İstanbul	{https://www.facebook.com/kadikoybelediye,https://twitter.com/kadikoybelediye,https://www.instagram.com/kadikoybelediye}	2025-05-12 18:34:53.172678+00	2025-05-12 18:34:53.172678+00
599e1d45-cb63-4d99-a7fb-c3b4b7e58a74	İstanbul	il	\N	https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRLYjetkcwzXZnrDfVq00e2Ybz_HpkAOX-clg&s	https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTT2hm1sDxSdoq5W33CwHi8XvzIyZctnhzQXw&s	Ekrem İmamoğlu	CHP	https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Cumhuriyet_Halk_Partisi_Logo.svg/250px-Cumhuriyet_Halk_Partisi_Logo.svg.png	16000000	0212 455 14 00	https://www.ibb.istanbul	info@ibb.istanbul	Kemalpaşa Mah. 15 Temmuz Şehitleri Cad. No:5 Beşiktaş, İstanbul	{https://www.facebook.com/istanbulbld,https://twitter.com/istanbulbld,https://www.instagram.com/istanbulbld}	2025-05-12 18:34:53.172678+00	2025-05-12 18:34:53.172678+00
0609259e-387e-46df-98f3-e08cf1d87683	Adana	il	\N	https://example.com/covers/adana_cover.jpg	https://example.com/logos/adana_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1075927	0322 999 00 00	https://www.adana.bel.tr	info@adana.bel.tr	Adana Belediye Binası, Merkez	{https://facebook.com/adanabelediye,https://twitter.com/adanabelediye,https://instagram.com/adanabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
68de68fe-aa4e-47c1-accf-1fe34d642768	Aladağ	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/aladag_cover.jpg	https://example.com/logos/aladag_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	359087	0609259e-8323	https://www.aladag.adana.bel.tr	info@aladag.bel.tr	Aladağ Belediye Binası, Adana	{https://facebook.com/aladagbelediye,https://twitter.com/aladagbelediye,https://instagram.com/aladagbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3a7ff812-7ce5-4842-a228-541745606c18	Ceyhan	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/ceyhan_cover.jpg	https://example.com/logos/ceyhan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	38656	0609259e-2743	https://www.ceyhan.adana.bel.tr	info@ceyhan.bel.tr	Ceyhan Belediye Binası, Adana	{https://facebook.com/ceyhanbelediye,https://twitter.com/ceyhanbelediye,https://instagram.com/ceyhanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d9718d00-c6df-470d-8bf6-55cbf8590015	Çukurova	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/çukurova_cover.jpg	https://example.com/logos/çukurova_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	421929	0609259e-9168	https://www.çukurova.adana.bel.tr	info@çukurova.bel.tr	Çukurova Belediye Binası, Adana	{https://facebook.com/çukurovabelediye,https://twitter.com/çukurovabelediye,https://instagram.com/çukurovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3dd02f08-0682-4047-951a-342cf1901bab	Feke	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/feke_cover.jpg	https://example.com/logos/feke_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	194840	0609259e-5117	https://www.feke.adana.bel.tr	info@feke.bel.tr	Feke Belediye Binası, Adana	{https://facebook.com/fekebelediye,https://twitter.com/fekebelediye,https://instagram.com/fekebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1e0a7e81-6ab0-4694-b12a-043a396e04dd	İmamoğlu	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/imamoglu_cover.jpg	https://example.com/logos/imamoglu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	159336	0609259e-6580	https://www.imamoglu.adana.bel.tr	info@imamoglu.bel.tr	İmamoğlu Belediye Binası, Adana	{https://facebook.com/imamoglubelediye,https://twitter.com/imamoglubelediye,https://instagram.com/imamoglubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ebff8e8f-3736-46dc-a219-13610c8090e4	Karaisalı	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/karaisali_cover.jpg	https://example.com/logos/karaisali_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	246106	0609259e-6483	https://www.karaisali.adana.bel.tr	info@karaisali.bel.tr	Karaisalı Belediye Binası, Adana	{https://facebook.com/karaisalibelediye,https://twitter.com/karaisalibelediye,https://instagram.com/karaisalibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
943cdb32-8b94-45fd-b083-cfa1a06db6c3	Karataş	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/karatas_cover.jpg	https://example.com/logos/karatas_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	287420	0609259e-8725	https://www.karatas.adana.bel.tr	info@karatas.bel.tr	Karataş Belediye Binası, Adana	{https://facebook.com/karatasbelediye,https://twitter.com/karatasbelediye,https://instagram.com/karatasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
86d8be30-5c1d-4439-9fc6-f04d183c0b4d	Kozan	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/kozan_cover.jpg	https://example.com/logos/kozan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	377597	0609259e-7100	https://www.kozan.adana.bel.tr	info@kozan.bel.tr	Kozan Belediye Binası, Adana	{https://facebook.com/kozanbelediye,https://twitter.com/kozanbelediye,https://instagram.com/kozanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b4959d4c-73d9-4ffe-923d-cd84da5e3309	Pozantı	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/pozanti_cover.jpg	https://example.com/logos/pozanti_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	404499	0609259e-3940	https://www.pozanti.adana.bel.tr	info@pozanti.bel.tr	Pozantı Belediye Binası, Adana	{https://facebook.com/pozantibelediye,https://twitter.com/pozantibelediye,https://instagram.com/pozantibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fa8d88fc-eb7b-48f1-862a-a0e1b6607fbf	Saimbeyli	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/saimbeyli_cover.jpg	https://example.com/logos/saimbeyli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	58903	0609259e-9242	https://www.saimbeyli.adana.bel.tr	info@saimbeyli.bel.tr	Saimbeyli Belediye Binası, Adana	{https://facebook.com/saimbeylibelediye,https://twitter.com/saimbeylibelediye,https://instagram.com/saimbeylibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9d98b09c-835c-49fb-9263-32652ccf0d76	Sarıçam	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/sariçam_cover.jpg	https://example.com/logos/sariçam_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	33393	0609259e-3011	https://www.sariçam.adana.bel.tr	info@sariçam.bel.tr	Sarıçam Belediye Binası, Adana	{https://facebook.com/sariçambelediye,https://twitter.com/sariçambelediye,https://instagram.com/sariçambelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b2d2c20b-1eac-4816-b0d2-f7df734fa997	Seyhan	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/seyhan_cover.jpg	https://example.com/logos/seyhan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	303157	0609259e-6111	https://www.seyhan.adana.bel.tr	info@seyhan.bel.tr	Seyhan Belediye Binası, Adana	{https://facebook.com/seyhanbelediye,https://twitter.com/seyhanbelediye,https://instagram.com/seyhanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b755b444-4c8d-4371-a266-4c3c92a09b8e	Tufanbeyli	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/tufanbeyli_cover.jpg	https://example.com/logos/tufanbeyli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	281190	0609259e-2621	https://www.tufanbeyli.adana.bel.tr	info@tufanbeyli.bel.tr	Tufanbeyli Belediye Binası, Adana	{https://facebook.com/tufanbeylibelediye,https://twitter.com/tufanbeylibelediye,https://instagram.com/tufanbeylibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cff8a158-ed94-4499-a900-c76058654054	Yumurtalık	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/yumurtalik_cover.jpg	https://example.com/logos/yumurtalik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	83381	0609259e-0589	https://www.yumurtalik.adana.bel.tr	info@yumurtalik.bel.tr	Yumurtalık Belediye Binası, Adana	{https://facebook.com/yumurtalikbelediye,https://twitter.com/yumurtalikbelediye,https://instagram.com/yumurtalikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a960a3e4-275f-4f73-b9ef-6d0f144ed843	Yüreğir	ilçe	0609259e-387e-46df-98f3-e08cf1d87683	https://example.com/covers/yuregir_cover.jpg	https://example.com/logos/yuregir_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	426261	0609259e-6135	https://www.yuregir.adana.bel.tr	info@yuregir.bel.tr	Yüreğir Belediye Binası, Adana	{https://facebook.com/yuregirbelediye,https://twitter.com/yuregirbelediye,https://instagram.com/yuregirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ac4681a2-df85-43bd-9611-3b318df85411	Adıyaman	il	\N	https://example.com/covers/adiyaman_cover.jpg	https://example.com/logos/adiyaman_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	597277	0416 999 00 00	https://www.adiyaman.bel.tr	info@adiyaman.bel.tr	Adıyaman Belediye Binası, Merkez	{https://facebook.com/adiyamanbelediye,https://twitter.com/adiyamanbelediye,https://instagram.com/adiyamanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
dff786e8-9230-483a-a4b9-bb98798da7df	Adıyaman Merkez	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/adiyaman merkez_cover.jpg	https://example.com/logos/adiyaman merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	172571	ac4681a2-9104	https://www.adiyaman merkez.adiyaman.bel.tr	info@adiyaman merkez.bel.tr	Adıyaman Merkez Belediye Binası, Adıyaman	{"https://facebook.com/adiyaman merkezbelediye","https://twitter.com/adiyaman merkezbelediye","https://instagram.com/adiyaman merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
21f168df-4ad4-4eea-abc3-0a00c9d72d8e	Besni	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/besni_cover.jpg	https://example.com/logos/besni_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	422324	ac4681a2-4701	https://www.besni.adiyaman.bel.tr	info@besni.bel.tr	Besni Belediye Binası, Adıyaman	{https://facebook.com/besnibelediye,https://twitter.com/besnibelediye,https://instagram.com/besnibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
00a7be3d-579c-431a-8654-68b6d3ffef2c	Çelikhan	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/çelikhan_cover.jpg	https://example.com/logos/çelikhan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	130721	ac4681a2-7267	https://www.çelikhan.adiyaman.bel.tr	info@çelikhan.bel.tr	Çelikhan Belediye Binası, Adıyaman	{https://facebook.com/çelikhanbelediye,https://twitter.com/çelikhanbelediye,https://instagram.com/çelikhanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a55bafd0-a528-45fa-924d-a89850282826	Gerger	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/gerger_cover.jpg	https://example.com/logos/gerger_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	16706	ac4681a2-7352	https://www.gerger.adiyaman.bel.tr	info@gerger.bel.tr	Gerger Belediye Binası, Adıyaman	{https://facebook.com/gergerbelediye,https://twitter.com/gergerbelediye,https://instagram.com/gergerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b365a9ab-cd1d-4589-acf7-bdf4f3587108	Gölbaşı	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/golbasi_cover.jpg	https://example.com/logos/golbasi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	41943	ac4681a2-9241	https://www.golbasi.adiyaman.bel.tr	info@golbasi.bel.tr	Gölbaşı Belediye Binası, Adıyaman	{https://facebook.com/golbasibelediye,https://twitter.com/golbasibelediye,https://instagram.com/golbasibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f6e23890-375e-4cd7-a939-d1738aaef72e	Kahta	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/kahta_cover.jpg	https://example.com/logos/kahta_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	254993	ac4681a2-5253	https://www.kahta.adiyaman.bel.tr	info@kahta.bel.tr	Kahta Belediye Binası, Adıyaman	{https://facebook.com/kahtabelediye,https://twitter.com/kahtabelediye,https://instagram.com/kahtabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
127d0d6b-8d89-4117-803a-874805df5fbd	Samsat	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/samsat_cover.jpg	https://example.com/logos/samsat_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	234714	ac4681a2-1064	https://www.samsat.adiyaman.bel.tr	info@samsat.bel.tr	Samsat Belediye Binası, Adıyaman	{https://facebook.com/samsatbelediye,https://twitter.com/samsatbelediye,https://instagram.com/samsatbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
01415012-2527-4c8a-ab85-f9c7d42e84b3	Sincik	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/sincik_cover.jpg	https://example.com/logos/sincik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	192622	ac4681a2-2932	https://www.sincik.adiyaman.bel.tr	info@sincik.bel.tr	Sincik Belediye Binası, Adıyaman	{https://facebook.com/sincikbelediye,https://twitter.com/sincikbelediye,https://instagram.com/sincikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d2dc7cfb-a3af-432d-b084-14f003622f66	Tut	ilçe	ac4681a2-df85-43bd-9611-3b318df85411	https://example.com/covers/tut_cover.jpg	https://example.com/logos/tut_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	506567	ac4681a2-3035	https://www.tut.adiyaman.bel.tr	info@tut.bel.tr	Tut Belediye Binası, Adıyaman	{https://facebook.com/tutbelediye,https://twitter.com/tutbelediye,https://instagram.com/tutbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4371c6a2-c55d-4eab-a40f-86bb03ccda5e	Afyonkarahisar	il	\N	https://example.com/covers/afyonkarahisar_cover.jpg	https://example.com/logos/afyonkarahisar_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	235744	0272 999 00 00	https://www.afyonkarahisar.bel.tr	info@afyonkarahisar.bel.tr	Afyonkarahisar Belediye Binası, Merkez	{https://facebook.com/afyonkarahisarbelediye,https://twitter.com/afyonkarahisarbelediye,https://instagram.com/afyonkarahisarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a26f3a04-a457-4017-802c-9c5e2de81bea	Afyonkarahisar Merkez	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/afyonkarahisar merkez_cover.jpg	https://example.com/logos/afyonkarahisar merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	117816	4371c6a2-4878	https://www.afyonkarahisar merkez.afyonkarahisar.bel.tr	info@afyonkarahisar merkez.bel.tr	Afyonkarahisar Merkez Belediye Binası, Afyonkarahisar	{"https://facebook.com/afyonkarahisar merkezbelediye","https://twitter.com/afyonkarahisar merkezbelediye","https://instagram.com/afyonkarahisar merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3516efb3-b8a4-4e4b-8599-558540a72ba2	Başmakçı	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/basmakçi_cover.jpg	https://example.com/logos/basmakçi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	43296	4371c6a2-3882	https://www.basmakçi.afyonkarahisar.bel.tr	info@basmakçi.bel.tr	Başmakçı Belediye Binası, Afyonkarahisar	{https://facebook.com/basmakçibelediye,https://twitter.com/basmakçibelediye,https://instagram.com/basmakçibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a48c0241-ddc8-4007-b34d-c14d65235405	Bayat	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/bayat_cover.jpg	https://example.com/logos/bayat_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	36363	4371c6a2-5325	https://www.bayat.afyonkarahisar.bel.tr	info@bayat.bel.tr	Bayat Belediye Binası, Afyonkarahisar	{https://facebook.com/bayatbelediye,https://twitter.com/bayatbelediye,https://instagram.com/bayatbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d27919f5-83ea-4824-9a23-ad8fb1bf0c7f	Bolvadin	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/bolvadin_cover.jpg	https://example.com/logos/bolvadin_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	75225	4371c6a2-5030	https://www.bolvadin.afyonkarahisar.bel.tr	info@bolvadin.bel.tr	Bolvadin Belediye Binası, Afyonkarahisar	{https://facebook.com/bolvadinbelediye,https://twitter.com/bolvadinbelediye,https://instagram.com/bolvadinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9ecd0f34-d799-4566-a4fd-24d610ba113f	Çay	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/çay_cover.jpg	https://example.com/logos/çay_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	208464	4371c6a2-9931	https://www.çay.afyonkarahisar.bel.tr	info@çay.bel.tr	Çay Belediye Binası, Afyonkarahisar	{https://facebook.com/çaybelediye,https://twitter.com/çaybelediye,https://instagram.com/çaybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
98869cdb-abe5-4351-8388-46aa885c6f81	Çobanlar	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/çobanlar_cover.jpg	https://example.com/logos/çobanlar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	217550	4371c6a2-9061	https://www.çobanlar.afyonkarahisar.bel.tr	info@çobanlar.bel.tr	Çobanlar Belediye Binası, Afyonkarahisar	{https://facebook.com/çobanlarbelediye,https://twitter.com/çobanlarbelediye,https://instagram.com/çobanlarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c4730f37-0efa-4c4e-9d4c-45564a0fb2ea	Dazkırı	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/dazkiri_cover.jpg	https://example.com/logos/dazkiri_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	284223	4371c6a2-4489	https://www.dazkiri.afyonkarahisar.bel.tr	info@dazkiri.bel.tr	Dazkırı Belediye Binası, Afyonkarahisar	{https://facebook.com/dazkiribelediye,https://twitter.com/dazkiribelediye,https://instagram.com/dazkiribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
2488069b-9198-4602-9d1d-5bba4d203992	Dinar	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/dinar_cover.jpg	https://example.com/logos/dinar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	267324	4371c6a2-6136	https://www.dinar.afyonkarahisar.bel.tr	info@dinar.bel.tr	Dinar Belediye Binası, Afyonkarahisar	{https://facebook.com/dinarbelediye,https://twitter.com/dinarbelediye,https://instagram.com/dinarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
87fdc43a-ac21-4f63-b30d-6e3b3f99b2a3	Emirdağ	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/emirdag_cover.jpg	https://example.com/logos/emirdag_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	344401	4371c6a2-7062	https://www.emirdag.afyonkarahisar.bel.tr	info@emirdag.bel.tr	Emirdağ Belediye Binası, Afyonkarahisar	{https://facebook.com/emirdagbelediye,https://twitter.com/emirdagbelediye,https://instagram.com/emirdagbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
86b406cb-a17d-4c2d-adca-46ad5da39cec	Evciler	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/evciler_cover.jpg	https://example.com/logos/evciler_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	467238	4371c6a2-9214	https://www.evciler.afyonkarahisar.bel.tr	info@evciler.bel.tr	Evciler Belediye Binası, Afyonkarahisar	{https://facebook.com/evcilerbelediye,https://twitter.com/evcilerbelediye,https://instagram.com/evcilerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
dc1c08ec-07ff-4ce6-bdb8-0da02a30c2f9	Hocalar	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/hocalar_cover.jpg	https://example.com/logos/hocalar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	465366	4371c6a2-6755	https://www.hocalar.afyonkarahisar.bel.tr	info@hocalar.bel.tr	Hocalar Belediye Binası, Afyonkarahisar	{https://facebook.com/hocalarbelediye,https://twitter.com/hocalarbelediye,https://instagram.com/hocalarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1e0d33eb-1687-43db-b07b-7e8d2f6074e7	İhsaniye	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/ihsaniye_cover.jpg	https://example.com/logos/ihsaniye_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	332647	4371c6a2-7205	https://www.ihsaniye.afyonkarahisar.bel.tr	info@ihsaniye.bel.tr	İhsaniye Belediye Binası, Afyonkarahisar	{https://facebook.com/ihsaniyebelediye,https://twitter.com/ihsaniyebelediye,https://instagram.com/ihsaniyebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
143de20c-feff-42ef-8fb1-e82f90ef32d3	İscehisar	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/iscehisar_cover.jpg	https://example.com/logos/iscehisar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	405064	4371c6a2-7563	https://www.iscehisar.afyonkarahisar.bel.tr	info@iscehisar.bel.tr	İscehisar Belediye Binası, Afyonkarahisar	{https://facebook.com/iscehisarbelediye,https://twitter.com/iscehisarbelediye,https://instagram.com/iscehisarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4b385a58-8063-40d1-89fb-19a6e92b1ce7	Kızılören	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/kiziloren_cover.jpg	https://example.com/logos/kiziloren_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	285085	4371c6a2-1121	https://www.kiziloren.afyonkarahisar.bel.tr	info@kiziloren.bel.tr	Kızılören Belediye Binası, Afyonkarahisar	{https://facebook.com/kizilorenbelediye,https://twitter.com/kizilorenbelediye,https://instagram.com/kizilorenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
32513bc8-0504-436d-bfd9-c248e2c64fb2	Sandıklı	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/sandikli_cover.jpg	https://example.com/logos/sandikli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	306916	4371c6a2-1036	https://www.sandikli.afyonkarahisar.bel.tr	info@sandikli.bel.tr	Sandıklı Belediye Binası, Afyonkarahisar	{https://facebook.com/sandiklibelediye,https://twitter.com/sandiklibelediye,https://instagram.com/sandiklibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bc7076a5-afb3-4884-b74d-bd9060196e57	Sinanpaşa	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/sinanpasa_cover.jpg	https://example.com/logos/sinanpasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	460788	4371c6a2-4504	https://www.sinanpasa.afyonkarahisar.bel.tr	info@sinanpasa.bel.tr	Sinanpaşa Belediye Binası, Afyonkarahisar	{https://facebook.com/sinanpasabelediye,https://twitter.com/sinanpasabelediye,https://instagram.com/sinanpasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8f2b8010-ea26-4ddb-8e45-172db28939e4	Sultandağı	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/sultandagi_cover.jpg	https://example.com/logos/sultandagi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	232668	4371c6a2-5485	https://www.sultandagi.afyonkarahisar.bel.tr	info@sultandagi.bel.tr	Sultandağı Belediye Binası, Afyonkarahisar	{https://facebook.com/sultandagibelediye,https://twitter.com/sultandagibelediye,https://instagram.com/sultandagibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e128d312-4c07-4ddc-bd0c-5fe9152eb3ba	Şuhut	ilçe	4371c6a2-c55d-4eab-a40f-86bb03ccda5e	https://example.com/covers/şuhut_cover.jpg	https://example.com/logos/şuhut_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	407960	4371c6a2-1355	https://www.şuhut.afyonkarahisar.bel.tr	info@şuhut.bel.tr	Şuhut Belediye Binası, Afyonkarahisar	{https://facebook.com/şuhutbelediye,https://twitter.com/şuhutbelediye,https://instagram.com/şuhutbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
94c2220c-112c-4d1a-802c-8b00c3ebb7a6	Ağrı	il	\N	https://example.com/covers/agri_cover.jpg	https://example.com/logos/agri_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	649398	0472 999 00 00	https://www.agri.bel.tr	info@agri.bel.tr	Ağrı Belediye Binası, Merkez	{https://facebook.com/agribelediye,https://twitter.com/agribelediye,https://instagram.com/agribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9e0ac64d-e626-42d5-a67b-4dcd7fe17407	Ağrı Merkez	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/agri merkez_cover.jpg	https://example.com/logos/agri merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	363387	94c2220c-7768	https://www.agri merkez.agri.bel.tr	info@agri merkez.bel.tr	Ağrı Merkez Belediye Binası, Ağrı	{"https://facebook.com/agri merkezbelediye","https://twitter.com/agri merkezbelediye","https://instagram.com/agri merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
480c4745-4bb6-4004-a1f8-017ab799f7a5	Diyadin	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/diyadin_cover.jpg	https://example.com/logos/diyadin_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	174315	94c2220c-2505	https://www.diyadin.agri.bel.tr	info@diyadin.bel.tr	Diyadin Belediye Binası, Ağrı	{https://facebook.com/diyadinbelediye,https://twitter.com/diyadinbelediye,https://instagram.com/diyadinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c20a1fad-560d-463c-8c2a-313b5faa32ba	Doğubayazıt	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/dogubayazit_cover.jpg	https://example.com/logos/dogubayazit_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	72818	94c2220c-6593	https://www.dogubayazit.agri.bel.tr	info@dogubayazit.bel.tr	Doğubayazıt Belediye Binası, Ağrı	{https://facebook.com/dogubayazitbelediye,https://twitter.com/dogubayazitbelediye,https://instagram.com/dogubayazitbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
74e81d80-ef73-4f23-9ade-25405e1620ce	Eleşkirt	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/eleskirt_cover.jpg	https://example.com/logos/eleskirt_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	272687	94c2220c-1012	https://www.eleskirt.agri.bel.tr	info@eleskirt.bel.tr	Eleşkirt Belediye Binası, Ağrı	{https://facebook.com/eleskirtbelediye,https://twitter.com/eleskirtbelediye,https://instagram.com/eleskirtbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
990deea2-08d2-4bc5-aa4b-0425049f8195	Hamur	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/hamur_cover.jpg	https://example.com/logos/hamur_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	317010	94c2220c-6055	https://www.hamur.agri.bel.tr	info@hamur.bel.tr	Hamur Belediye Binası, Ağrı	{https://facebook.com/hamurbelediye,https://twitter.com/hamurbelediye,https://instagram.com/hamurbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
20b6f62f-40f8-48ab-bb81-224f222f312b	Patnos	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/patnos_cover.jpg	https://example.com/logos/patnos_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	444793	94c2220c-5520	https://www.patnos.agri.bel.tr	info@patnos.bel.tr	Patnos Belediye Binası, Ağrı	{https://facebook.com/patnosbelediye,https://twitter.com/patnosbelediye,https://instagram.com/patnosbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
724e11a7-c883-4ddc-8c6e-023cb89f08fd	Taşlıçay	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/tasliçay_cover.jpg	https://example.com/logos/tasliçay_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	22039	94c2220c-3388	https://www.tasliçay.agri.bel.tr	info@tasliçay.bel.tr	Taşlıçay Belediye Binası, Ağrı	{https://facebook.com/tasliçaybelediye,https://twitter.com/tasliçaybelediye,https://instagram.com/tasliçaybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
7aea47d0-ff84-4cc9-8ac0-dc9ae44c4531	Tutak	ilçe	94c2220c-112c-4d1a-802c-8b00c3ebb7a6	https://example.com/covers/tutak_cover.jpg	https://example.com/logos/tutak_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	54936	94c2220c-6515	https://www.tutak.agri.bel.tr	info@tutak.bel.tr	Tutak Belediye Binası, Ağrı	{https://facebook.com/tutakbelediye,https://twitter.com/tutakbelediye,https://instagram.com/tutakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
24f9dad9-e42f-40b9-8f20-c152d690235c	Aksaray	il	\N	https://example.com/covers/aksaray_cover.jpg	https://example.com/logos/aksaray_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	432236	0382 999 00 00	https://www.aksaray.bel.tr	info@aksaray.bel.tr	Aksaray Belediye Binası, Merkez	{https://facebook.com/aksaraybelediye,https://twitter.com/aksaraybelediye,https://instagram.com/aksaraybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b7901285-875e-4d42-bd14-bc0a512a66d3	Aksaray Merkez	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/aksaray merkez_cover.jpg	https://example.com/logos/aksaray merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	325012	24f9dad9-2487	https://www.aksaray merkez.aksaray.bel.tr	info@aksaray merkez.bel.tr	Aksaray Merkez Belediye Binası, Aksaray	{"https://facebook.com/aksaray merkezbelediye","https://twitter.com/aksaray merkezbelediye","https://instagram.com/aksaray merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4f8c02e4-2fd8-4f5c-94a0-7e54b573e049	Ağaçören	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/agaçoren_cover.jpg	https://example.com/logos/agaçoren_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	93809	24f9dad9-5055	https://www.agaçoren.aksaray.bel.tr	info@agaçoren.bel.tr	Ağaçören Belediye Binası, Aksaray	{https://facebook.com/agaçorenbelediye,https://twitter.com/agaçorenbelediye,https://instagram.com/agaçorenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
7b54a60f-f8e3-4f41-9674-922bcd4ec0a7	Eskil	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/eskil_cover.jpg	https://example.com/logos/eskil_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	146728	24f9dad9-5565	https://www.eskil.aksaray.bel.tr	info@eskil.bel.tr	Eskil Belediye Binası, Aksaray	{https://facebook.com/eskilbelediye,https://twitter.com/eskilbelediye,https://instagram.com/eskilbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0ce8c241-b586-4065-a9d9-0d9f2374488b	Gülağaç	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/gulagaç_cover.jpg	https://example.com/logos/gulagaç_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	192915	24f9dad9-3908	https://www.gulagaç.aksaray.bel.tr	info@gulagaç.bel.tr	Gülağaç Belediye Binası, Aksaray	{https://facebook.com/gulagaçbelediye,https://twitter.com/gulagaçbelediye,https://instagram.com/gulagaçbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f333ec87-e00a-475d-b862-2e56959c7ef5	Güzelyurt	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/guzelyurt_cover.jpg	https://example.com/logos/guzelyurt_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	99995	24f9dad9-7675	https://www.guzelyurt.aksaray.bel.tr	info@guzelyurt.bel.tr	Güzelyurt Belediye Binası, Aksaray	{https://facebook.com/guzelyurtbelediye,https://twitter.com/guzelyurtbelediye,https://instagram.com/guzelyurtbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
84dee7a3-836f-4389-8e36-a549c0409ff4	Ortaköy	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/ortakoy_cover.jpg	https://example.com/logos/ortakoy_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	203644	24f9dad9-9138	https://www.ortakoy.aksaray.bel.tr	info@ortakoy.bel.tr	Ortaköy Belediye Binası, Aksaray	{https://facebook.com/ortakoybelediye,https://twitter.com/ortakoybelediye,https://instagram.com/ortakoybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6d3585dc-7617-4889-a472-e9494701232a	Sarıyahşi	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/sariyahsi_cover.jpg	https://example.com/logos/sariyahsi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	285126	24f9dad9-0006	https://www.sariyahsi.aksaray.bel.tr	info@sariyahsi.bel.tr	Sarıyahşi Belediye Binası, Aksaray	{https://facebook.com/sariyahsibelediye,https://twitter.com/sariyahsibelediye,https://instagram.com/sariyahsibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8f9bff34-45c0-4249-9252-11d952937cc0	Sultanhanı	ilçe	24f9dad9-e42f-40b9-8f20-c152d690235c	https://example.com/covers/sultanhani_cover.jpg	https://example.com/logos/sultanhani_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	502931	24f9dad9-3337	https://www.sultanhani.aksaray.bel.tr	info@sultanhani.bel.tr	Sultanhanı Belediye Binası, Aksaray	{https://facebook.com/sultanhanibelediye,https://twitter.com/sultanhanibelediye,https://instagram.com/sultanhanibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
27c60cf3-f2ea-45c4-9a29-3960a4c32252	Amasya	il	\N	https://example.com/covers/amasya_cover.jpg	https://example.com/logos/amasya_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	596124	0358 999 00 00	https://www.amasya.bel.tr	info@amasya.bel.tr	Amasya Belediye Binası, Merkez	{https://facebook.com/amasyabelediye,https://twitter.com/amasyabelediye,https://instagram.com/amasyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
221bfd2d-e959-473b-9399-e1c7c5a994b9	Amasya Merkez	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/amasya merkez_cover.jpg	https://example.com/logos/amasya merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	363392	27c60cf3-8935	https://www.amasya merkez.amasya.bel.tr	info@amasya merkez.bel.tr	Amasya Merkez Belediye Binası, Amasya	{"https://facebook.com/amasya merkezbelediye","https://twitter.com/amasya merkezbelediye","https://instagram.com/amasya merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8a5d14ae-0fb6-4f0e-b5e7-4e30eecffd39	Göynücek	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/goynucek_cover.jpg	https://example.com/logos/goynucek_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	26620	27c60cf3-8749	https://www.goynucek.amasya.bel.tr	info@goynucek.bel.tr	Göynücek Belediye Binası, Amasya	{https://facebook.com/goynucekbelediye,https://twitter.com/goynucekbelediye,https://instagram.com/goynucekbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e998c443-5cc6-4721-b321-7a65a7a1b3c0	Gümüşhacıköy	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/gumushacikoy_cover.jpg	https://example.com/logos/gumushacikoy_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	287465	27c60cf3-2240	https://www.gumushacikoy.amasya.bel.tr	info@gumushacikoy.bel.tr	Gümüşhacıköy Belediye Binası, Amasya	{https://facebook.com/gumushacikoybelediye,https://twitter.com/gumushacikoybelediye,https://instagram.com/gumushacikoybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
30f09bef-43dd-4d55-b1de-607af15e2193	Hamamözü	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/hamamozu_cover.jpg	https://example.com/logos/hamamozu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	293144	27c60cf3-0233	https://www.hamamozu.amasya.bel.tr	info@hamamozu.bel.tr	Hamamözü Belediye Binası, Amasya	{https://facebook.com/hamamozubelediye,https://twitter.com/hamamozubelediye,https://instagram.com/hamamozubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3fc1c9c1-d97a-4780-90b4-6d720a8d326a	Merzifon	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/merzifon_cover.jpg	https://example.com/logos/merzifon_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	89603	27c60cf3-1130	https://www.merzifon.amasya.bel.tr	info@merzifon.bel.tr	Merzifon Belediye Binası, Amasya	{https://facebook.com/merzifonbelediye,https://twitter.com/merzifonbelediye,https://instagram.com/merzifonbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4dc3a256-819b-4966-97ea-d3ba41640283	Suluova	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/suluova_cover.jpg	https://example.com/logos/suluova_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	367327	27c60cf3-4987	https://www.suluova.amasya.bel.tr	info@suluova.bel.tr	Suluova Belediye Binası, Amasya	{https://facebook.com/suluovabelediye,https://twitter.com/suluovabelediye,https://instagram.com/suluovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a5b79e15-4f2b-473b-9dec-2ba51403ca2a	Taşova	ilçe	27c60cf3-f2ea-45c4-9a29-3960a4c32252	https://example.com/covers/tasova_cover.jpg	https://example.com/logos/tasova_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	172667	27c60cf3-1067	https://www.tasova.amasya.bel.tr	info@tasova.bel.tr	Taşova Belediye Binası, Amasya	{https://facebook.com/tasovabelediye,https://twitter.com/tasovabelediye,https://instagram.com/tasovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
99f57865-6098-4fdc-9b71-176b26de73a3	Ankara	il	\N	https://example.com/covers/ankara_cover.jpg	https://example.com/logos/ankara_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	735489	0312 999 00 00	https://www.ankara.bel.tr	info@ankara.bel.tr	Ankara Belediye Binası, Merkez	{https://facebook.com/ankarabelediye,https://twitter.com/ankarabelediye,https://instagram.com/ankarabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
923bc250-990e-4236-bb31-1efca037fa98	Akyurt	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/akyurt_cover.jpg	https://example.com/logos/akyurt_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	231420	99f57865-7732	https://www.akyurt.ankara.bel.tr	info@akyurt.bel.tr	Akyurt Belediye Binası, Ankara	{https://facebook.com/akyurtbelediye,https://twitter.com/akyurtbelediye,https://instagram.com/akyurtbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c0d635f8-7a43-4934-9e9d-c03ed1ae2115	Altındağ	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/altindag_cover.jpg	https://example.com/logos/altindag_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	154267	99f57865-8176	https://www.altindag.ankara.bel.tr	info@altindag.bel.tr	Altındağ Belediye Binası, Ankara	{https://facebook.com/altindagbelediye,https://twitter.com/altindagbelediye,https://instagram.com/altindagbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
07d4d3de-e9eb-407e-ab4b-b1ce7bf36025	Ayaş	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/ayas_cover.jpg	https://example.com/logos/ayas_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	245724	99f57865-8749	https://www.ayas.ankara.bel.tr	info@ayas.bel.tr	Ayaş Belediye Binası, Ankara	{https://facebook.com/ayasbelediye,https://twitter.com/ayasbelediye,https://instagram.com/ayasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0d4797be-d271-455c-a20a-3a9967fdb423	Bala	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/bala_cover.jpg	https://example.com/logos/bala_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	302114	99f57865-2645	https://www.bala.ankara.bel.tr	info@bala.bel.tr	Bala Belediye Binası, Ankara	{https://facebook.com/balabelediye,https://twitter.com/balabelediye,https://instagram.com/balabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a0c546ec-3af7-48d1-b8f2-deeb1f5e2829	Beypazarı	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/beypazari_cover.jpg	https://example.com/logos/beypazari_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	106106	99f57865-4113	https://www.beypazari.ankara.bel.tr	info@beypazari.bel.tr	Beypazarı Belediye Binası, Ankara	{https://facebook.com/beypazaribelediye,https://twitter.com/beypazaribelediye,https://instagram.com/beypazaribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
49c4edcc-0557-4c41-8e49-dd9f048f5d9c	Çamlıdere	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/çamlidere_cover.jpg	https://example.com/logos/çamlidere_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	328332	99f57865-0983	https://www.çamlidere.ankara.bel.tr	info@çamlidere.bel.tr	Çamlıdere Belediye Binası, Ankara	{https://facebook.com/çamliderebelediye,https://twitter.com/çamliderebelediye,https://instagram.com/çamliderebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ba8d1523-7aff-49a1-b89b-42ef8eafb4dc	Çankaya	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/çankaya_cover.jpg	https://example.com/logos/çankaya_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	479912	99f57865-9666	https://www.çankaya.ankara.bel.tr	info@çankaya.bel.tr	Çankaya Belediye Binası, Ankara	{https://facebook.com/çankayabelediye,https://twitter.com/çankayabelediye,https://instagram.com/çankayabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a21bb154-312b-4f35-8662-5115f33492b4	Çubuk	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/çubuk_cover.jpg	https://example.com/logos/çubuk_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	347584	99f57865-5240	https://www.çubuk.ankara.bel.tr	info@çubuk.bel.tr	Çubuk Belediye Binası, Ankara	{https://facebook.com/çubukbelediye,https://twitter.com/çubukbelediye,https://instagram.com/çubukbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fff0b2d7-7c5c-459c-96ac-e31abca9afcb	Elmadağ	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/elmadag_cover.jpg	https://example.com/logos/elmadag_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	270774	99f57865-6684	https://www.elmadag.ankara.bel.tr	info@elmadag.bel.tr	Elmadağ Belediye Binası, Ankara	{https://facebook.com/elmadagbelediye,https://twitter.com/elmadagbelediye,https://instagram.com/elmadagbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e662d5ac-6c92-469f-aa91-a0707ec0bb78	Etimesgut	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/etimesgut_cover.jpg	https://example.com/logos/etimesgut_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	43447	99f57865-3856	https://www.etimesgut.ankara.bel.tr	info@etimesgut.bel.tr	Etimesgut Belediye Binası, Ankara	{https://facebook.com/etimesgutbelediye,https://twitter.com/etimesgutbelediye,https://instagram.com/etimesgutbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ad252d9e-dc15-4aab-b8d7-ea581a12e67b	Evren	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/evren_cover.jpg	https://example.com/logos/evren_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	58056	99f57865-8003	https://www.evren.ankara.bel.tr	info@evren.bel.tr	Evren Belediye Binası, Ankara	{https://facebook.com/evrenbelediye,https://twitter.com/evrenbelediye,https://instagram.com/evrenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a4fea6f4-b66d-4e67-8e34-923a70b4578d	Gölbaşı	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/golbasi_cover.jpg	https://example.com/logos/golbasi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	436531	99f57865-5754	https://www.golbasi.ankara.bel.tr	info@golbasi.bel.tr	Gölbaşı Belediye Binası, Ankara	{https://facebook.com/golbasibelediye,https://twitter.com/golbasibelediye,https://instagram.com/golbasibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
037ccbb4-1ec2-4974-bfac-879542a9f461	Güdül	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/gudul_cover.jpg	https://example.com/logos/gudul_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	471986	99f57865-4088	https://www.gudul.ankara.bel.tr	info@gudul.bel.tr	Güdül Belediye Binası, Ankara	{https://facebook.com/gudulbelediye,https://twitter.com/gudulbelediye,https://instagram.com/gudulbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ce84d302-a991-484b-bdf1-d7a4d6e1a7fb	Haymana	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/haymana_cover.jpg	https://example.com/logos/haymana_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	270683	99f57865-4701	https://www.haymana.ankara.bel.tr	info@haymana.bel.tr	Haymana Belediye Binası, Ankara	{https://facebook.com/haymanabelediye,https://twitter.com/haymanabelediye,https://instagram.com/haymanabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9e53ef21-e67d-438b-9cbe-e284ca5ee47f	Kahramankazan	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/kahramankazan_cover.jpg	https://example.com/logos/kahramankazan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	115730	99f57865-2313	https://www.kahramankazan.ankara.bel.tr	info@kahramankazan.bel.tr	Kahramankazan Belediye Binası, Ankara	{https://facebook.com/kahramankazanbelediye,https://twitter.com/kahramankazanbelediye,https://instagram.com/kahramankazanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c915b945-0905-45c3-a756-dd555cc824a7	Kalecik	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/kalecik_cover.jpg	https://example.com/logos/kalecik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	246336	99f57865-2657	https://www.kalecik.ankara.bel.tr	info@kalecik.bel.tr	Kalecik Belediye Binası, Ankara	{https://facebook.com/kalecikbelediye,https://twitter.com/kalecikbelediye,https://instagram.com/kalecikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a9a6a67e-3d22-4d6c-bfbd-ce8610a90214	Keçiören	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/keçioren_cover.jpg	https://example.com/logos/keçioren_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	197877	99f57865-9092	https://www.keçioren.ankara.bel.tr	info@keçioren.bel.tr	Keçiören Belediye Binası, Ankara	{https://facebook.com/keçiorenbelediye,https://twitter.com/keçiorenbelediye,https://instagram.com/keçiorenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a0ac5636-a6a7-4852-b579-106c0a87dbea	Kızılcahamam	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/kizilcahamam_cover.jpg	https://example.com/logos/kizilcahamam_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	300156	99f57865-9674	https://www.kizilcahamam.ankara.bel.tr	info@kizilcahamam.bel.tr	Kızılcahamam Belediye Binası, Ankara	{https://facebook.com/kizilcahamambelediye,https://twitter.com/kizilcahamambelediye,https://instagram.com/kizilcahamambelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
382d100a-d073-4a66-b49e-0a2e741c1e3d	Mamak	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/mamak_cover.jpg	https://example.com/logos/mamak_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	426851	99f57865-9702	https://www.mamak.ankara.bel.tr	info@mamak.bel.tr	Mamak Belediye Binası, Ankara	{https://facebook.com/mamakbelediye,https://twitter.com/mamakbelediye,https://instagram.com/mamakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
edf65454-d86b-4231-a2f8-6a5af3260442	Nallıhan	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/nallihan_cover.jpg	https://example.com/logos/nallihan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	106873	99f57865-4389	https://www.nallihan.ankara.bel.tr	info@nallihan.bel.tr	Nallıhan Belediye Binası, Ankara	{https://facebook.com/nallihanbelediye,https://twitter.com/nallihanbelediye,https://instagram.com/nallihanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
25e59bc4-0a1c-4ce4-921d-33307171218b	Polatlı	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/polatli_cover.jpg	https://example.com/logos/polatli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	10816	99f57865-5044	https://www.polatli.ankara.bel.tr	info@polatli.bel.tr	Polatlı Belediye Binası, Ankara	{https://facebook.com/polatlibelediye,https://twitter.com/polatlibelediye,https://instagram.com/polatlibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
891e9f3d-10b5-4e72-9bc9-c3403ed2ca76	Pursaklar	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/pursaklar_cover.jpg	https://example.com/logos/pursaklar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	118064	99f57865-7309	https://www.pursaklar.ankara.bel.tr	info@pursaklar.bel.tr	Pursaklar Belediye Binası, Ankara	{https://facebook.com/pursaklarbelediye,https://twitter.com/pursaklarbelediye,https://instagram.com/pursaklarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
208dd0bc-9e11-40df-8b42-cd4304317199	Sincan	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/sincan_cover.jpg	https://example.com/logos/sincan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	56811	99f57865-4682	https://www.sincan.ankara.bel.tr	info@sincan.bel.tr	Sincan Belediye Binası, Ankara	{https://facebook.com/sincanbelediye,https://twitter.com/sincanbelediye,https://instagram.com/sincanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
59d144d8-8031-4c2f-b574-d54a1cc81f45	Şereflikoçhisar	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/şereflikoçhisar_cover.jpg	https://example.com/logos/şereflikoçhisar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	460261	99f57865-9276	https://www.şereflikoçhisar.ankara.bel.tr	info@şereflikoçhisar.bel.tr	Şereflikoçhisar Belediye Binası, Ankara	{https://facebook.com/şereflikoçhisarbelediye,https://twitter.com/şereflikoçhisarbelediye,https://instagram.com/şereflikoçhisarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a225db0a-ecc7-4737-bac1-6fdadaa04381	Yenimahalle	ilçe	99f57865-6098-4fdc-9b71-176b26de73a3	https://example.com/covers/yenimahalle_cover.jpg	https://example.com/logos/yenimahalle_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	450872	99f57865-5542	https://www.yenimahalle.ankara.bel.tr	info@yenimahalle.bel.tr	Yenimahalle Belediye Binası, Ankara	{https://facebook.com/yenimahallebelediye,https://twitter.com/yenimahallebelediye,https://instagram.com/yenimahallebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
5b290beb-a9e7-4ee4-9d20-81df802be0f5	Antalya	il	\N	https://example.com/covers/antalya_cover.jpg	https://example.com/logos/antalya_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	125216	0242 999 00 00	https://www.antalya.bel.tr	info@antalya.bel.tr	Antalya Belediye Binası, Merkez	{https://facebook.com/antalyabelediye,https://twitter.com/antalyabelediye,https://instagram.com/antalyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
00ac3092-3eff-45d5-8c2e-5cf4d960c097	Akseki	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/akseki_cover.jpg	https://example.com/logos/akseki_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	146408	5b290beb-9444	https://www.akseki.antalya.bel.tr	info@akseki.bel.tr	Akseki Belediye Binası, Antalya	{https://facebook.com/aksekibelediye,https://twitter.com/aksekibelediye,https://instagram.com/aksekibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6b2b48fd-5ec2-4c43-b23f-2f38084e3774	Aksu	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/aksu_cover.jpg	https://example.com/logos/aksu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	400949	5b290beb-1658	https://www.aksu.antalya.bel.tr	info@aksu.bel.tr	Aksu Belediye Binası, Antalya	{https://facebook.com/aksubelediye,https://twitter.com/aksubelediye,https://instagram.com/aksubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f43e479c-060d-411e-94c5-fceb05ac8bc5	Alanya	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/alanya_cover.jpg	https://example.com/logos/alanya_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	286162	5b290beb-5494	https://www.alanya.antalya.bel.tr	info@alanya.bel.tr	Alanya Belediye Binası, Antalya	{https://facebook.com/alanyabelediye,https://twitter.com/alanyabelediye,https://instagram.com/alanyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b62c398d-56bb-4266-bf17-dbd6456c5951	Demre	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/demre_cover.jpg	https://example.com/logos/demre_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	110782	5b290beb-3366	https://www.demre.antalya.bel.tr	info@demre.bel.tr	Demre Belediye Binası, Antalya	{https://facebook.com/demrebelediye,https://twitter.com/demrebelediye,https://instagram.com/demrebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e7e47e4c-471e-4149-9ca9-1fb4c84e9384	Döşemealtı	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/dosemealti_cover.jpg	https://example.com/logos/dosemealti_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	146116	5b290beb-3420	https://www.dosemealti.antalya.bel.tr	info@dosemealti.bel.tr	Döşemealtı Belediye Binası, Antalya	{https://facebook.com/dosemealtibelediye,https://twitter.com/dosemealtibelediye,https://instagram.com/dosemealtibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
019c3345-0df5-4890-8388-bf94003e1ca0	Elmalı	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/elmali_cover.jpg	https://example.com/logos/elmali_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	72097	5b290beb-0845	https://www.elmali.antalya.bel.tr	info@elmali.bel.tr	Elmalı Belediye Binası, Antalya	{https://facebook.com/elmalibelediye,https://twitter.com/elmalibelediye,https://instagram.com/elmalibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
782d423d-9289-43d9-be9b-c96a4fc97ad9	Finike	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/finike_cover.jpg	https://example.com/logos/finike_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	450414	5b290beb-2299	https://www.finike.antalya.bel.tr	info@finike.bel.tr	Finike Belediye Binası, Antalya	{https://facebook.com/finikebelediye,https://twitter.com/finikebelediye,https://instagram.com/finikebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
58cd59a0-fff2-40d6-aff8-88223a5c88eb	Gazipaşa	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/gazipasa_cover.jpg	https://example.com/logos/gazipasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	168277	5b290beb-6240	https://www.gazipasa.antalya.bel.tr	info@gazipasa.bel.tr	Gazipaşa Belediye Binası, Antalya	{https://facebook.com/gazipasabelediye,https://twitter.com/gazipasabelediye,https://instagram.com/gazipasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ea820bac-add6-48ef-aafb-ed171e7b183b	Gündoğmuş	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/gundogmus_cover.jpg	https://example.com/logos/gundogmus_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	408117	5b290beb-3098	https://www.gundogmus.antalya.bel.tr	info@gundogmus.bel.tr	Gündoğmuş Belediye Binası, Antalya	{https://facebook.com/gundogmusbelediye,https://twitter.com/gundogmusbelediye,https://instagram.com/gundogmusbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d7febbe4-2f44-4d55-a085-660439b19a63	İbradı	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/ibradi_cover.jpg	https://example.com/logos/ibradi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	334676	5b290beb-1306	https://www.ibradi.antalya.bel.tr	info@ibradi.bel.tr	İbradı Belediye Binası, Antalya	{https://facebook.com/ibradibelediye,https://twitter.com/ibradibelediye,https://instagram.com/ibradibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
16877781-552f-4a03-9ab8-ad119873ba7b	Kaş	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/kas_cover.jpg	https://example.com/logos/kas_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	293585	5b290beb-4202	https://www.kas.antalya.bel.tr	info@kas.bel.tr	Kaş Belediye Binası, Antalya	{https://facebook.com/kasbelediye,https://twitter.com/kasbelediye,https://instagram.com/kasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d2082793-e98c-44a0-af7e-155e485145c2	Kemer	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/kemer_cover.jpg	https://example.com/logos/kemer_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	339305	5b290beb-6469	https://www.kemer.antalya.bel.tr	info@kemer.bel.tr	Kemer Belediye Binası, Antalya	{https://facebook.com/kemerbelediye,https://twitter.com/kemerbelediye,https://instagram.com/kemerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d2f855ea-b039-4d72-9374-d2091cb2e026	Kepez	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/kepez_cover.jpg	https://example.com/logos/kepez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	311578	5b290beb-6120	https://www.kepez.antalya.bel.tr	info@kepez.bel.tr	Kepez Belediye Binası, Antalya	{https://facebook.com/kepezbelediye,https://twitter.com/kepezbelediye,https://instagram.com/kepezbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1cadd2b7-9746-432f-a8f0-4fb4f26afa70	Konyaaltı	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/konyaalti_cover.jpg	https://example.com/logos/konyaalti_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	396881	5b290beb-5487	https://www.konyaalti.antalya.bel.tr	info@konyaalti.bel.tr	Konyaaltı Belediye Binası, Antalya	{https://facebook.com/konyaaltibelediye,https://twitter.com/konyaaltibelediye,https://instagram.com/konyaaltibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
2d71a73e-4713-475a-8261-a38e236b7da5	Korkuteli	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/korkuteli_cover.jpg	https://example.com/logos/korkuteli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	355268	5b290beb-0623	https://www.korkuteli.antalya.bel.tr	info@korkuteli.bel.tr	Korkuteli Belediye Binası, Antalya	{https://facebook.com/korkutelibelediye,https://twitter.com/korkutelibelediye,https://instagram.com/korkutelibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f8dbc0ac-ba69-431f-83cc-7bb7cbbe28d6	Kumluca	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/kumluca_cover.jpg	https://example.com/logos/kumluca_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	107259	5b290beb-5959	https://www.kumluca.antalya.bel.tr	info@kumluca.bel.tr	Kumluca Belediye Binası, Antalya	{https://facebook.com/kumlucabelediye,https://twitter.com/kumlucabelediye,https://instagram.com/kumlucabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
49aa52b7-77e1-489e-9689-eefc17c109ab	Manavgat	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/manavgat_cover.jpg	https://example.com/logos/manavgat_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	257956	5b290beb-3863	https://www.manavgat.antalya.bel.tr	info@manavgat.bel.tr	Manavgat Belediye Binası, Antalya	{https://facebook.com/manavgatbelediye,https://twitter.com/manavgatbelediye,https://instagram.com/manavgatbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fdffca4b-fa70-4b4a-89e6-c696f000fbea	Muratpaşa	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/muratpasa_cover.jpg	https://example.com/logos/muratpasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	177747	5b290beb-4834	https://www.muratpasa.antalya.bel.tr	info@muratpasa.bel.tr	Muratpaşa Belediye Binası, Antalya	{https://facebook.com/muratpasabelediye,https://twitter.com/muratpasabelediye,https://instagram.com/muratpasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
90f8a692-07b2-4211-89ad-147639e41f3d	Serik	ilçe	5b290beb-a9e7-4ee4-9d20-81df802be0f5	https://example.com/covers/serik_cover.jpg	https://example.com/logos/serik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	275938	5b290beb-7687	https://www.serik.antalya.bel.tr	info@serik.bel.tr	Serik Belediye Binası, Antalya	{https://facebook.com/serikbelediye,https://twitter.com/serikbelediye,https://instagram.com/serikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cf64706e-bbe3-4088-8afc-837fa106ebb1	Ardahan	il	\N	https://example.com/covers/ardahan_cover.jpg	https://example.com/logos/ardahan_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	883723	0478 999 00 00	https://www.ardahan.bel.tr	info@ardahan.bel.tr	Ardahan Belediye Binası, Merkez	{https://facebook.com/ardahanbelediye,https://twitter.com/ardahanbelediye,https://instagram.com/ardahanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b7dc4412-b245-4261-9c7b-7e08fd0223c9	Ardahan Merkez	ilçe	cf64706e-bbe3-4088-8afc-837fa106ebb1	https://example.com/covers/ardahan merkez_cover.jpg	https://example.com/logos/ardahan merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	508110	cf64706e-9709	https://www.ardahan merkez.ardahan.bel.tr	info@ardahan merkez.bel.tr	Ardahan Merkez Belediye Binası, Ardahan	{"https://facebook.com/ardahan merkezbelediye","https://twitter.com/ardahan merkezbelediye","https://instagram.com/ardahan merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
df49a199-2235-4277-b663-db18a39e85f9	Çıldır	ilçe	cf64706e-bbe3-4088-8afc-837fa106ebb1	https://example.com/covers/çildir_cover.jpg	https://example.com/logos/çildir_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	305876	cf64706e-5509	https://www.çildir.ardahan.bel.tr	info@çildir.bel.tr	Çıldır Belediye Binası, Ardahan	{https://facebook.com/çildirbelediye,https://twitter.com/çildirbelediye,https://instagram.com/çildirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9482016e-d748-40ed-a930-beaaba5975b1	Damal	ilçe	cf64706e-bbe3-4088-8afc-837fa106ebb1	https://example.com/covers/damal_cover.jpg	https://example.com/logos/damal_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	440836	cf64706e-5653	https://www.damal.ardahan.bel.tr	info@damal.bel.tr	Damal Belediye Binası, Ardahan	{https://facebook.com/damalbelediye,https://twitter.com/damalbelediye,https://instagram.com/damalbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8902bbd1-18fe-4079-86b9-b3b13e13d250	Göle	ilçe	cf64706e-bbe3-4088-8afc-837fa106ebb1	https://example.com/covers/gole_cover.jpg	https://example.com/logos/gole_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	401972	cf64706e-0362	https://www.gole.ardahan.bel.tr	info@gole.bel.tr	Göle Belediye Binası, Ardahan	{https://facebook.com/golebelediye,https://twitter.com/golebelediye,https://instagram.com/golebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3c57f1d3-c380-448a-84bc-67569b9b99ea	Hanak	ilçe	cf64706e-bbe3-4088-8afc-837fa106ebb1	https://example.com/covers/hanak_cover.jpg	https://example.com/logos/hanak_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	327826	cf64706e-7996	https://www.hanak.ardahan.bel.tr	info@hanak.bel.tr	Hanak Belediye Binası, Ardahan	{https://facebook.com/hanakbelediye,https://twitter.com/hanakbelediye,https://instagram.com/hanakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
202f7577-544b-49f8-adc3-19cc2f99c60c	Posof	ilçe	cf64706e-bbe3-4088-8afc-837fa106ebb1	https://example.com/covers/posof_cover.jpg	https://example.com/logos/posof_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	355563	cf64706e-7367	https://www.posof.ardahan.bel.tr	info@posof.bel.tr	Posof Belediye Binası, Ardahan	{https://facebook.com/posofbelediye,https://twitter.com/posofbelediye,https://instagram.com/posofbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
19949ef9-5ec0-494d-9111-ae80f8439c93	Artvin	il	\N	https://example.com/covers/artvin_cover.jpg	https://example.com/logos/artvin_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1094611	0466 999 00 00	https://www.artvin.bel.tr	info@artvin.bel.tr	Artvin Belediye Binası, Merkez	{https://facebook.com/artvinbelediye,https://twitter.com/artvinbelediye,https://instagram.com/artvinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4904a3b8-6538-47e0-9b23-42f6d700962f	Ardanuç	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/ardanuç_cover.jpg	https://example.com/logos/ardanuç_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	284425	19949ef9-2428	https://www.ardanuç.artvin.bel.tr	info@ardanuç.bel.tr	Ardanuç Belediye Binası, Artvin	{https://facebook.com/ardanuçbelediye,https://twitter.com/ardanuçbelediye,https://instagram.com/ardanuçbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c2b79f1c-1892-40f5-becd-9a647be69525	Arhavi	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/arhavi_cover.jpg	https://example.com/logos/arhavi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	471498	19949ef9-1506	https://www.arhavi.artvin.bel.tr	info@arhavi.bel.tr	Arhavi Belediye Binası, Artvin	{https://facebook.com/arhavibelediye,https://twitter.com/arhavibelediye,https://instagram.com/arhavibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bd275e60-3b14-4580-bc13-36734a3afe6b	Artvin Merkez	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/artvin merkez_cover.jpg	https://example.com/logos/artvin merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	308683	19949ef9-6787	https://www.artvin merkez.artvin.bel.tr	info@artvin merkez.bel.tr	Artvin Merkez Belediye Binası, Artvin	{"https://facebook.com/artvin merkezbelediye","https://twitter.com/artvin merkezbelediye","https://instagram.com/artvin merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f1d37dab-fa41-45f4-8bbb-704f4afe454e	Borçka	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/borçka_cover.jpg	https://example.com/logos/borçka_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	195265	19949ef9-0688	https://www.borçka.artvin.bel.tr	info@borçka.bel.tr	Borçka Belediye Binası, Artvin	{https://facebook.com/borçkabelediye,https://twitter.com/borçkabelediye,https://instagram.com/borçkabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ce1a2d03-5117-4e86-9028-79a02b109900	Hopa	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/hopa_cover.jpg	https://example.com/logos/hopa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	129604	19949ef9-4815	https://www.hopa.artvin.bel.tr	info@hopa.bel.tr	Hopa Belediye Binası, Artvin	{https://facebook.com/hopabelediye,https://twitter.com/hopabelediye,https://instagram.com/hopabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
34bb9ff7-a074-410c-be86-f91f2e742fe7	Kemalpaşa	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/kemalpasa_cover.jpg	https://example.com/logos/kemalpasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	101026	19949ef9-4537	https://www.kemalpasa.artvin.bel.tr	info@kemalpasa.bel.tr	Kemalpaşa Belediye Binası, Artvin	{https://facebook.com/kemalpasabelediye,https://twitter.com/kemalpasabelediye,https://instagram.com/kemalpasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c0022262-839e-4cda-88de-875594f7bfc6	Murgul	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/murgul_cover.jpg	https://example.com/logos/murgul_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	484098	19949ef9-5993	https://www.murgul.artvin.bel.tr	info@murgul.bel.tr	Murgul Belediye Binası, Artvin	{https://facebook.com/murgulbelediye,https://twitter.com/murgulbelediye,https://instagram.com/murgulbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c835e0bb-70da-41e8-b6a6-ed8ce1e7baff	Şavşat	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/şavsat_cover.jpg	https://example.com/logos/şavsat_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	389525	19949ef9-2756	https://www.şavsat.artvin.bel.tr	info@şavsat.bel.tr	Şavşat Belediye Binası, Artvin	{https://facebook.com/şavsatbelediye,https://twitter.com/şavsatbelediye,https://instagram.com/şavsatbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
5af83ed4-1ce0-4c8a-b3a4-44459c3c15ba	Yusufeli	ilçe	19949ef9-5ec0-494d-9111-ae80f8439c93	https://example.com/covers/yusufeli_cover.jpg	https://example.com/logos/yusufeli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	500370	19949ef9-9644	https://www.yusufeli.artvin.bel.tr	info@yusufeli.bel.tr	Yusufeli Belediye Binası, Artvin	{https://facebook.com/yusufelibelediye,https://twitter.com/yusufelibelediye,https://instagram.com/yusufelibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ebcd499c-8f8c-4208-815b-58e914c89fdb	Aydın	il	\N	https://example.com/covers/aydin_cover.jpg	https://example.com/logos/aydin_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	987974	0256 999 00 00	https://www.aydin.bel.tr	info@aydin.bel.tr	Aydın Belediye Binası, Merkez	{https://facebook.com/aydinbelediye,https://twitter.com/aydinbelediye,https://instagram.com/aydinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
5b491d23-10a5-4706-9e9b-f4e4c628535c	Bozdoğan	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/bozdogan_cover.jpg	https://example.com/logos/bozdogan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	72564	ebcd499c-1618	https://www.bozdogan.aydin.bel.tr	info@bozdogan.bel.tr	Bozdoğan Belediye Binası, Aydın	{https://facebook.com/bozdoganbelediye,https://twitter.com/bozdoganbelediye,https://instagram.com/bozdoganbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
81f093b5-f4bf-411c-a209-61e2281dd17b	Buharkent	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/buharkent_cover.jpg	https://example.com/logos/buharkent_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	122953	ebcd499c-4598	https://www.buharkent.aydin.bel.tr	info@buharkent.bel.tr	Buharkent Belediye Binası, Aydın	{https://facebook.com/buharkentbelediye,https://twitter.com/buharkentbelediye,https://instagram.com/buharkentbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1003a576-96df-42f7-a497-d99934f2e510	Çine	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/çine_cover.jpg	https://example.com/logos/çine_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	45257	ebcd499c-0420	https://www.çine.aydin.bel.tr	info@çine.bel.tr	Çine Belediye Binası, Aydın	{https://facebook.com/çinebelediye,https://twitter.com/çinebelediye,https://instagram.com/çinebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
55972e90-60a3-467e-9593-0e3be87117f7	Didim	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/didim_cover.jpg	https://example.com/logos/didim_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	444764	ebcd499c-7478	https://www.didim.aydin.bel.tr	info@didim.bel.tr	Didim Belediye Binası, Aydın	{https://facebook.com/didimbelediye,https://twitter.com/didimbelediye,https://instagram.com/didimbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e8b16f22-fc3e-4137-a00d-1850ad0cec74	Efeler	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/efeler_cover.jpg	https://example.com/logos/efeler_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	184898	ebcd499c-2610	https://www.efeler.aydin.bel.tr	info@efeler.bel.tr	Efeler Belediye Binası, Aydın	{https://facebook.com/efelerbelediye,https://twitter.com/efelerbelediye,https://instagram.com/efelerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1b5e7875-d140-422a-9a4a-b48762b6e02d	Germencik	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/germencik_cover.jpg	https://example.com/logos/germencik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	488635	ebcd499c-3180	https://www.germencik.aydin.bel.tr	info@germencik.bel.tr	Germencik Belediye Binası, Aydın	{https://facebook.com/germencikbelediye,https://twitter.com/germencikbelediye,https://instagram.com/germencikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c30f5052-65cb-4561-92dc-e62e6815113e	İncirliova	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/incirliova_cover.jpg	https://example.com/logos/incirliova_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	69532	ebcd499c-2782	https://www.incirliova.aydin.bel.tr	info@incirliova.bel.tr	İncirliova Belediye Binası, Aydın	{https://facebook.com/incirliovabelediye,https://twitter.com/incirliovabelediye,https://instagram.com/incirliovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
5edc5a12-f5e3-4669-add1-254b48a0f54c	Karacasu	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/karacasu_cover.jpg	https://example.com/logos/karacasu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	263302	ebcd499c-1879	https://www.karacasu.aydin.bel.tr	info@karacasu.bel.tr	Karacasu Belediye Binası, Aydın	{https://facebook.com/karacasubelediye,https://twitter.com/karacasubelediye,https://instagram.com/karacasubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
96829de9-ba59-4a32-84a7-c61f393a6007	Karpuzlu	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/karpuzlu_cover.jpg	https://example.com/logos/karpuzlu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	498952	ebcd499c-2201	https://www.karpuzlu.aydin.bel.tr	info@karpuzlu.bel.tr	Karpuzlu Belediye Binası, Aydın	{https://facebook.com/karpuzlubelediye,https://twitter.com/karpuzlubelediye,https://instagram.com/karpuzlubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
79da605e-cb6e-4838-a582-9ef3251a74f9	Koçarlı	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/koçarli_cover.jpg	https://example.com/logos/koçarli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	157721	ebcd499c-4586	https://www.koçarli.aydin.bel.tr	info@koçarli.bel.tr	Koçarlı Belediye Binası, Aydın	{https://facebook.com/koçarlibelediye,https://twitter.com/koçarlibelediye,https://instagram.com/koçarlibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cfa883b9-157a-4f75-9121-113ed50a2c11	Köşk	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/kosk_cover.jpg	https://example.com/logos/kosk_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	101179	ebcd499c-4487	https://www.kosk.aydin.bel.tr	info@kosk.bel.tr	Köşk Belediye Binası, Aydın	{https://facebook.com/koskbelediye,https://twitter.com/koskbelediye,https://instagram.com/koskbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3fd617a2-6e52-418f-b50b-9e20c0389c3d	Kuşadası	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/kusadasi_cover.jpg	https://example.com/logos/kusadasi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	273523	ebcd499c-6183	https://www.kusadasi.aydin.bel.tr	info@kusadasi.bel.tr	Kuşadası Belediye Binası, Aydın	{https://facebook.com/kusadasibelediye,https://twitter.com/kusadasibelediye,https://instagram.com/kusadasibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
41998208-fcd6-478d-854a-2384dd2bfe3b	Kuyucak	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/kuyucak_cover.jpg	https://example.com/logos/kuyucak_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	149502	ebcd499c-3365	https://www.kuyucak.aydin.bel.tr	info@kuyucak.bel.tr	Kuyucak Belediye Binası, Aydın	{https://facebook.com/kuyucakbelediye,https://twitter.com/kuyucakbelediye,https://instagram.com/kuyucakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
295cf339-5ab0-49d8-917c-980228a7dcc9	Nazilli	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/nazilli_cover.jpg	https://example.com/logos/nazilli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	288435	ebcd499c-2727	https://www.nazilli.aydin.bel.tr	info@nazilli.bel.tr	Nazilli Belediye Binası, Aydın	{https://facebook.com/nazillibelediye,https://twitter.com/nazillibelediye,https://instagram.com/nazillibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bf66b199-e0b8-4a7f-bd57-06b9ac59b32d	Söke	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/soke_cover.jpg	https://example.com/logos/soke_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	350008	ebcd499c-9030	https://www.soke.aydin.bel.tr	info@soke.bel.tr	Söke Belediye Binası, Aydın	{https://facebook.com/sokebelediye,https://twitter.com/sokebelediye,https://instagram.com/sokebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8755dc43-70e5-421e-81a5-f0bfeb747f4b	Sultanhisar	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/sultanhisar_cover.jpg	https://example.com/logos/sultanhisar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	143516	ebcd499c-8137	https://www.sultanhisar.aydin.bel.tr	info@sultanhisar.bel.tr	Sultanhisar Belediye Binası, Aydın	{https://facebook.com/sultanhisarbelediye,https://twitter.com/sultanhisarbelediye,https://instagram.com/sultanhisarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
24c8057c-57dd-43e2-b8ff-ad9cc1c47a90	Yenipazar	ilçe	ebcd499c-8f8c-4208-815b-58e914c89fdb	https://example.com/covers/yenipazar_cover.jpg	https://example.com/logos/yenipazar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	79559	ebcd499c-0042	https://www.yenipazar.aydin.bel.tr	info@yenipazar.bel.tr	Yenipazar Belediye Binası, Aydın	{https://facebook.com/yenipazarbelediye,https://twitter.com/yenipazarbelediye,https://instagram.com/yenipazarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	Balıkesir	il	\N	https://example.com/covers/balikesir_cover.jpg	https://example.com/logos/balikesir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	937572	0266 999 00 00	https://www.balikesir.bel.tr	info@balikesir.bel.tr	Balıkesir Belediye Binası, Merkez	{https://facebook.com/balikesirbelediye,https://twitter.com/balikesirbelediye,https://instagram.com/balikesirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
459e6a1b-e815-4f43-96c6-d21b57c0d491	Altıeylül	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/altieylul_cover.jpg	https://example.com/logos/altieylul_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	229829	0b9bf1c9-5393	https://www.altieylul.balikesir.bel.tr	info@altieylul.bel.tr	Altıeylül Belediye Binası, Balıkesir	{https://facebook.com/altieylulbelediye,https://twitter.com/altieylulbelediye,https://instagram.com/altieylulbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a7458f76-c42c-482c-aee0-2e2dffb6c504	Ayvalık	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/ayvalik_cover.jpg	https://example.com/logos/ayvalik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	55614	0b9bf1c9-7711	https://www.ayvalik.balikesir.bel.tr	info@ayvalik.bel.tr	Ayvalık Belediye Binası, Balıkesir	{https://facebook.com/ayvalikbelediye,https://twitter.com/ayvalikbelediye,https://instagram.com/ayvalikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fdd29fd5-d63f-4fb0-a768-c8e4d4d7b551	Balya	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/balya_cover.jpg	https://example.com/logos/balya_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	101103	0b9bf1c9-9810	https://www.balya.balikesir.bel.tr	info@balya.bel.tr	Balya Belediye Binası, Balıkesir	{https://facebook.com/balyabelediye,https://twitter.com/balyabelediye,https://instagram.com/balyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f7290e97-365a-4424-9798-5f550d5c8b3d	Bandırma	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/bandirma_cover.jpg	https://example.com/logos/bandirma_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	144913	0b9bf1c9-9380	https://www.bandirma.balikesir.bel.tr	info@bandirma.bel.tr	Bandırma Belediye Binası, Balıkesir	{https://facebook.com/bandirmabelediye,https://twitter.com/bandirmabelediye,https://instagram.com/bandirmabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
77f2db18-290c-4ae1-ab1e-8466ccf18918	Bigadiç	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/bigadiç_cover.jpg	https://example.com/logos/bigadiç_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	383814	0b9bf1c9-2589	https://www.bigadiç.balikesir.bel.tr	info@bigadiç.bel.tr	Bigadiç Belediye Binası, Balıkesir	{https://facebook.com/bigadiçbelediye,https://twitter.com/bigadiçbelediye,https://instagram.com/bigadiçbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6bc9f9ab-a7a0-415d-9223-b132876a61b4	Burhaniye	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/burhaniye_cover.jpg	https://example.com/logos/burhaniye_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	171455	0b9bf1c9-6396	https://www.burhaniye.balikesir.bel.tr	info@burhaniye.bel.tr	Burhaniye Belediye Binası, Balıkesir	{https://facebook.com/burhaniyebelediye,https://twitter.com/burhaniyebelediye,https://instagram.com/burhaniyebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b8c70a59-dc97-4cca-a756-d038d0f7cda4	Dursunbey	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/dursunbey_cover.jpg	https://example.com/logos/dursunbey_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	231785	0b9bf1c9-9294	https://www.dursunbey.balikesir.bel.tr	info@dursunbey.bel.tr	Dursunbey Belediye Binası, Balıkesir	{https://facebook.com/dursunbeybelediye,https://twitter.com/dursunbeybelediye,https://instagram.com/dursunbeybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0e572a41-0948-4d1c-8833-0fa00bd7fb38	Edremit	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/edremit_cover.jpg	https://example.com/logos/edremit_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	258333	0b9bf1c9-2724	https://www.edremit.balikesir.bel.tr	info@edremit.bel.tr	Edremit Belediye Binası, Balıkesir	{https://facebook.com/edremitbelediye,https://twitter.com/edremitbelediye,https://instagram.com/edremitbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4f5ca793-7c42-4f67-ad85-ccabee77a09d	Erdek	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/erdek_cover.jpg	https://example.com/logos/erdek_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	347459	0b9bf1c9-8795	https://www.erdek.balikesir.bel.tr	info@erdek.bel.tr	Erdek Belediye Binası, Balıkesir	{https://facebook.com/erdekbelediye,https://twitter.com/erdekbelediye,https://instagram.com/erdekbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
41a76483-0f89-4f28-a1e6-8ffc95ccb525	Gömeç	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/gomeç_cover.jpg	https://example.com/logos/gomeç_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	350103	0b9bf1c9-5718	https://www.gomeç.balikesir.bel.tr	info@gomeç.bel.tr	Gömeç Belediye Binası, Balıkesir	{https://facebook.com/gomeçbelediye,https://twitter.com/gomeçbelediye,https://instagram.com/gomeçbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
97d50796-58d8-4478-b9ed-12a3a0d85bf7	Gönen	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/gonen_cover.jpg	https://example.com/logos/gonen_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	22129	0b9bf1c9-6570	https://www.gonen.balikesir.bel.tr	info@gonen.bel.tr	Gönen Belediye Binası, Balıkesir	{https://facebook.com/gonenbelediye,https://twitter.com/gonenbelediye,https://instagram.com/gonenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
7a7d26f3-24a7-4908-9b55-af5457dba3b6	Havran	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/havran_cover.jpg	https://example.com/logos/havran_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	125028	0b9bf1c9-1510	https://www.havran.balikesir.bel.tr	info@havran.bel.tr	Havran Belediye Binası, Balıkesir	{https://facebook.com/havranbelediye,https://twitter.com/havranbelediye,https://instagram.com/havranbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8702bf25-313e-41f6-88d6-ecd9a649ea43	İvrindi	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/ivrindi_cover.jpg	https://example.com/logos/ivrindi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	166887	0b9bf1c9-9269	https://www.ivrindi.balikesir.bel.tr	info@ivrindi.bel.tr	İvrindi Belediye Binası, Balıkesir	{https://facebook.com/ivrindibelediye,https://twitter.com/ivrindibelediye,https://instagram.com/ivrindibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6f6de275-868b-43b6-9453-1ed24671157e	Karesi	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/karesi_cover.jpg	https://example.com/logos/karesi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	170647	0b9bf1c9-6695	https://www.karesi.balikesir.bel.tr	info@karesi.bel.tr	Karesi Belediye Binası, Balıkesir	{https://facebook.com/karesibelediye,https://twitter.com/karesibelediye,https://instagram.com/karesibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
46bf3022-8adc-4d33-b6d8-567c223a872e	Kepsut	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/kepsut_cover.jpg	https://example.com/logos/kepsut_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	430740	0b9bf1c9-9014	https://www.kepsut.balikesir.bel.tr	info@kepsut.bel.tr	Kepsut Belediye Binası, Balıkesir	{https://facebook.com/kepsutbelediye,https://twitter.com/kepsutbelediye,https://instagram.com/kepsutbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
aa9b6727-1ddc-4e50-90d2-80f278a564c5	Manyas	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/manyas_cover.jpg	https://example.com/logos/manyas_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	145618	0b9bf1c9-9119	https://www.manyas.balikesir.bel.tr	info@manyas.bel.tr	Manyas Belediye Binası, Balıkesir	{https://facebook.com/manyasbelediye,https://twitter.com/manyasbelediye,https://instagram.com/manyasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ceedef89-7e43-4147-8e2a-9967787f103a	Marmara	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/marmara_cover.jpg	https://example.com/logos/marmara_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	415643	0b9bf1c9-0979	https://www.marmara.balikesir.bel.tr	info@marmara.bel.tr	Marmara Belediye Binası, Balıkesir	{https://facebook.com/marmarabelediye,https://twitter.com/marmarabelediye,https://instagram.com/marmarabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
72ac75d8-b542-44f7-ac91-2cd5747769f7	Savaştepe	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/savastepe_cover.jpg	https://example.com/logos/savastepe_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	410050	0b9bf1c9-0396	https://www.savastepe.balikesir.bel.tr	info@savastepe.bel.tr	Savaştepe Belediye Binası, Balıkesir	{https://facebook.com/savastepebelediye,https://twitter.com/savastepebelediye,https://instagram.com/savastepebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cb972d7e-fdb7-4fb9-acac-5270c8ab4ef9	Sındırgı	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/sindirgi_cover.jpg	https://example.com/logos/sindirgi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	214951	0b9bf1c9-8771	https://www.sindirgi.balikesir.bel.tr	info@sindirgi.bel.tr	Sındırgı Belediye Binası, Balıkesir	{https://facebook.com/sindirgibelediye,https://twitter.com/sindirgibelediye,https://instagram.com/sindirgibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c7d7707e-d7d5-46da-ac2d-05f283c421e6	Susurluk	ilçe	0b9bf1c9-3c99-453f-9eeb-745ff5c3ceae	https://example.com/covers/susurluk_cover.jpg	https://example.com/logos/susurluk_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	18361	0b9bf1c9-9776	https://www.susurluk.balikesir.bel.tr	info@susurluk.bel.tr	Susurluk Belediye Binası, Balıkesir	{https://facebook.com/susurlukbelediye,https://twitter.com/susurlukbelediye,https://instagram.com/susurlukbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a30c71e8-6156-4c78-afb3-42b98fbfd169	Bartın	il	\N	https://example.com/covers/bartin_cover.jpg	https://example.com/logos/bartin_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	121606	0378 999 00 00	https://www.bartin.bel.tr	info@bartin.bel.tr	Bartın Belediye Binası, Merkez	{https://facebook.com/bartinbelediye,https://twitter.com/bartinbelediye,https://instagram.com/bartinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
50a7be80-83fe-4c38-aebd-b47cb157f3f3	Amasra	ilçe	a30c71e8-6156-4c78-afb3-42b98fbfd169	https://example.com/covers/amasra_cover.jpg	https://example.com/logos/amasra_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	147804	a30c71e8-1001	https://www.amasra.bartin.bel.tr	info@amasra.bel.tr	Amasra Belediye Binası, Bartın	{https://facebook.com/amasrabelediye,https://twitter.com/amasrabelediye,https://instagram.com/amasrabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8801c632-320d-46d5-bea8-f81ce6d16fef	Bartın Merkez	ilçe	a30c71e8-6156-4c78-afb3-42b98fbfd169	https://example.com/covers/bartin merkez_cover.jpg	https://example.com/logos/bartin merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	146159	a30c71e8-9289	https://www.bartin merkez.bartin.bel.tr	info@bartin merkez.bel.tr	Bartın Merkez Belediye Binası, Bartın	{"https://facebook.com/bartin merkezbelediye","https://twitter.com/bartin merkezbelediye","https://instagram.com/bartin merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6176ee5c-e574-4ffd-b635-0e461ee8e238	Kurucaşile	ilçe	a30c71e8-6156-4c78-afb3-42b98fbfd169	https://example.com/covers/kurucasile_cover.jpg	https://example.com/logos/kurucasile_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	106008	a30c71e8-4532	https://www.kurucasile.bartin.bel.tr	info@kurucasile.bel.tr	Kurucaşile Belediye Binası, Bartın	{https://facebook.com/kurucasilebelediye,https://twitter.com/kurucasilebelediye,https://instagram.com/kurucasilebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d55d48af-314b-42fe-80cf-f435d7964a1e	Ulus	ilçe	a30c71e8-6156-4c78-afb3-42b98fbfd169	https://example.com/covers/ulus_cover.jpg	https://example.com/logos/ulus_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	115680	a30c71e8-6152	https://www.ulus.bartin.bel.tr	info@ulus.bel.tr	Ulus Belediye Binası, Bartın	{https://facebook.com/ulusbelediye,https://twitter.com/ulusbelediye,https://instagram.com/ulusbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b31fa2ab-c3ef-450a-9bf4-bae51a7af751	Batman	il	\N	https://example.com/covers/batman_cover.jpg	https://example.com/logos/batman_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	572843	0488 999 00 00	https://www.batman.bel.tr	info@batman.bel.tr	Batman Belediye Binası, Merkez	{https://facebook.com/batmanbelediye,https://twitter.com/batmanbelediye,https://instagram.com/batmanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e38ae538-4c9b-40e3-a7e5-f0bf8285117b	Batman Merkez	ilçe	b31fa2ab-c3ef-450a-9bf4-bae51a7af751	https://example.com/covers/batman merkez_cover.jpg	https://example.com/logos/batman merkez_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	338121	b31fa2ab-5486	https://www.batman merkez.batman.bel.tr	info@batman merkez.bel.tr	Batman Merkez Belediye Binası, Batman	{"https://facebook.com/batman merkezbelediye","https://twitter.com/batman merkezbelediye","https://instagram.com/batman merkezbelediye"}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
58b1d2ec-22d4-4e89-a1d7-cb50c28c27f9	Beşiri	ilçe	b31fa2ab-c3ef-450a-9bf4-bae51a7af751	https://example.com/covers/besiri_cover.jpg	https://example.com/logos/besiri_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	113825	b31fa2ab-2955	https://www.besiri.batman.bel.tr	info@besiri.bel.tr	Beşiri Belediye Binası, Batman	{https://facebook.com/besiribelediye,https://twitter.com/besiribelediye,https://instagram.com/besiribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3e59d112-d4aa-4b05-805d-4c52446cd2cc	Gercüş	ilçe	b31fa2ab-c3ef-450a-9bf4-bae51a7af751	https://example.com/covers/gercus_cover.jpg	https://example.com/logos/gercus_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	171730	b31fa2ab-1198	https://www.gercus.batman.bel.tr	info@gercus.bel.tr	Gercüş Belediye Binası, Batman	{https://facebook.com/gercusbelediye,https://twitter.com/gercusbelediye,https://instagram.com/gercusbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
7997da2b-5d1f-4a07-af2d-a8105323cb82	Hasankeyf	ilçe	b31fa2ab-c3ef-450a-9bf4-bae51a7af751	https://example.com/covers/hasankeyf_cover.jpg	https://example.com/logos/hasankeyf_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	128752	b31fa2ab-9728	https://www.hasankeyf.batman.bel.tr	info@hasankeyf.bel.tr	Hasankeyf Belediye Binası, Batman	{https://facebook.com/hasankeyfbelediye,https://twitter.com/hasankeyfbelediye,https://instagram.com/hasankeyfbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d6f1c665-f9bd-47e7-8930-02a1ca97c0d1	Kozluk	ilçe	b31fa2ab-c3ef-450a-9bf4-bae51a7af751	https://example.com/covers/kozluk_cover.jpg	https://example.com/logos/kozluk_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	186158	b31fa2ab-5486	https://www.kozluk.batman.bel.tr	info@kozluk.bel.tr	Kozluk Belediye Binası, Batman	{https://facebook.com/kozlukbelediye,https://twitter.com/kozlukbelediye,https://instagram.com/kozlukbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6ee060a5-57a9-4efa-8029-b5ba47dd3b65	Sason	ilçe	b31fa2ab-c3ef-450a-9bf4-bae51a7af751	https://example.com/covers/sason_cover.jpg	https://example.com/logos/sason_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	100148	b31fa2ab-5537	https://www.sason.batman.bel.tr	info@sason.bel.tr	Sason Belediye Binası, Batman	{https://facebook.com/sasonbelediye,https://twitter.com/sasonbelediye,https://instagram.com/sasonbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ef846b51-5f6c-46ab-95c0-153e831ca3d3	Bayburt	il	\N	https://example.com/covers/bayburt_cover.jpg	https://example.com/logos/bayburt_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	572088	0458 999 00 00	https://www.bayburt.bel.tr	info@bayburt.bel.tr	Bayburt Belediye Binası, Merkez	{https://facebook.com/bayburtbelediye,https://twitter.com/bayburtbelediye,https://instagram.com/bayburtbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
29bb1b84-98bf-40d7-b89b-3c0802caa03b	Bilecik	il	\N	https://example.com/covers/bilecik_cover.jpg	https://example.com/logos/bilecik_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	983497	0228 999 00 00	https://www.bilecik.bel.tr	info@bilecik.bel.tr	Bilecik Belediye Binası, Merkez	{https://facebook.com/bilecikbelediye,https://twitter.com/bilecikbelediye,https://instagram.com/bilecikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
2a4fc4b6-64c8-4448-83a6-c8f9754d9804	Bingöl	il	\N	https://example.com/covers/bingol_cover.jpg	https://example.com/logos/bingol_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	101230	0426 999 00 00	https://www.bingol.bel.tr	info@bingol.bel.tr	Bingöl Belediye Binası, Merkez	{https://facebook.com/bingolbelediye,https://twitter.com/bingolbelediye,https://instagram.com/bingolbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3fb4c339-330d-4314-8cf2-10efdcf563ad	Bitlis	il	\N	https://example.com/covers/bitlis_cover.jpg	https://example.com/logos/bitlis_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1050899	0434 999 00 00	https://www.bitlis.bel.tr	info@bitlis.bel.tr	Bitlis Belediye Binası, Merkez	{https://facebook.com/bitlisbelediye,https://twitter.com/bitlisbelediye,https://instagram.com/bitlisbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4137522c-ab72-4605-ba70-b85194cd8c39	Bolu	il	\N	https://example.com/covers/bolu_cover.jpg	https://example.com/logos/bolu_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	665808	0374 999 00 00	https://www.bolu.bel.tr	info@bolu.bel.tr	Bolu Belediye Binası, Merkez	{https://facebook.com/bolubelediye,https://twitter.com/bolubelediye,https://instagram.com/bolubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b3eda108-4d7e-42c6-93e9-07798be39045	Burdur	il	\N	https://example.com/covers/burdur_cover.jpg	https://example.com/logos/burdur_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	170886	0248 999 00 00	https://www.burdur.bel.tr	info@burdur.bel.tr	Burdur Belediye Binası, Merkez	{https://facebook.com/burdurbelediye,https://twitter.com/burdurbelediye,https://instagram.com/burdurbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
094a35b3-0b69-44b7-ab26-b498cff591ba	Bursa	il	\N	https://example.com/covers/bursa_cover.jpg	https://example.com/logos/bursa_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1097752	0224 999 00 00	https://www.bursa.bel.tr	info@bursa.bel.tr	Bursa Belediye Binası, Merkez	{https://facebook.com/bursabelediye,https://twitter.com/bursabelediye,https://instagram.com/bursabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b968dd26-5fc1-4cff-bddc-c7029eb7efaf	Çanakkale	il	\N	https://example.com/covers/çanakkale_cover.jpg	https://example.com/logos/çanakkale_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	906762	0286 999 00 00	https://www.canakkale.bel.tr	info@çanakkale.bel.tr	Çanakkale Belediye Binası, Merkez	{https://facebook.com/çanakkalebelediye,https://twitter.com/çanakkalebelediye,https://instagram.com/çanakkalebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fbfd87e8-4abf-4d33-9f76-82a5d0e8e4d5	Çankırı	il	\N	https://example.com/covers/çankiri_cover.jpg	https://example.com/logos/çankiri_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1082521	0376 999 00 00	https://www.cankiri.bel.tr	info@çankiri.bel.tr	Çankırı Belediye Binası, Merkez	{https://facebook.com/çankiribelediye,https://twitter.com/çankiribelediye,https://instagram.com/çankiribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b0dbe4bf-12ff-4ce9-bf85-54808967a41a	Çorum	il	\N	https://example.com/covers/çorum_cover.jpg	https://example.com/logos/çorum_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	665904	0364 999 00 00	https://www.corum.bel.tr	info@çorum.bel.tr	Çorum Belediye Binası, Merkez	{https://facebook.com/çorumbelediye,https://twitter.com/çorumbelediye,https://instagram.com/çorumbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a683b515-4d96-4e70-adfe-26d7ceb5eb04	Denizli	il	\N	https://example.com/covers/denizli_cover.jpg	https://example.com/logos/denizli_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1056876	0258 999 00 00	https://www.denizli.bel.tr	info@denizli.bel.tr	Denizli Belediye Binası, Merkez	{https://facebook.com/denizlibelediye,https://twitter.com/denizlibelediye,https://instagram.com/denizlibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
7faf12ae-16c8-4f54-bde8-6729cbe094eb	Diyarbakır	il	\N	https://example.com/covers/diyarbakir_cover.jpg	https://example.com/logos/diyarbakir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1031147	0412 999 00 00	https://www.diyarbakir.bel.tr	info@diyarbakir.bel.tr	Diyarbakır Belediye Binası, Merkez	{https://facebook.com/diyarbakirbelediye,https://twitter.com/diyarbakirbelediye,https://instagram.com/diyarbakirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e436d71b-d3cd-4e8b-ad77-d18decf1a27c	Düzce	il	\N	https://example.com/covers/duzce_cover.jpg	https://example.com/logos/duzce_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	385476	0380 999 00 00	https://www.duzce.bel.tr	info@duzce.bel.tr	Düzce Belediye Binası, Merkez	{https://facebook.com/duzcebelediye,https://twitter.com/duzcebelediye,https://instagram.com/duzcebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0ed45b51-0f88-4664-9f64-e1035980628f	Edirne	il	\N	https://example.com/covers/edirne_cover.jpg	https://example.com/logos/edirne_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	406530	0284 999 00 00	https://www.edirne.bel.tr	info@edirne.bel.tr	Edirne Belediye Binası, Merkez	{https://facebook.com/edirnebelediye,https://twitter.com/edirnebelediye,https://instagram.com/edirnebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1be31a9e-03a5-4b87-b1ca-b31badb80fe2	Elazığ	il	\N	https://example.com/covers/elazig_cover.jpg	https://example.com/logos/elazig_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	596927	0424 999 00 00	https://www.elazig.bel.tr	info@elazig.bel.tr	Elazığ Belediye Binası, Merkez	{https://facebook.com/elazigbelediye,https://twitter.com/elazigbelediye,https://instagram.com/elazigbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3b69ba17-b5e3-4f3c-9c8d-4e3be20ba537	Erzincan	il	\N	https://example.com/covers/erzincan_cover.jpg	https://example.com/logos/erzincan_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	970119	0446 999 00 00	https://www.erzincan.bel.tr	info@erzincan.bel.tr	Erzincan Belediye Binası, Merkez	{https://facebook.com/erzincanbelediye,https://twitter.com/erzincanbelediye,https://instagram.com/erzincanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
774e1203-7594-473a-8f37-a2dd4d65af55	Erzurum	il	\N	https://example.com/covers/erzurum_cover.jpg	https://example.com/logos/erzurum_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	678277	0442 999 00 00	https://www.erzurum.bel.tr	info@erzurum.bel.tr	Erzurum Belediye Binası, Merkez	{https://facebook.com/erzurumbelediye,https://twitter.com/erzurumbelediye,https://instagram.com/erzurumbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
08638cff-afa5-45fe-87e4-0446f1227527	Eskişehir	il	\N	https://example.com/covers/eskisehir_cover.jpg	https://example.com/logos/eskisehir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1080550	0222 999 00 00	https://www.eskisehir.bel.tr	info@eskisehir.bel.tr	Eskişehir Belediye Binası, Merkez	{https://facebook.com/eskisehirbelediye,https://twitter.com/eskisehirbelediye,https://instagram.com/eskisehirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
94176274-482d-411e-89b1-ce622e100cf4	Gaziantep	il	\N	https://example.com/covers/gaziantep_cover.jpg	https://example.com/logos/gaziantep_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	669304	0342 999 00 00	https://www.gaziantep.bel.tr	info@gaziantep.bel.tr	Gaziantep Belediye Binası, Merkez	{https://facebook.com/gaziantepbelediye,https://twitter.com/gaziantepbelediye,https://instagram.com/gaziantepbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e791a51e-01fe-4834-8f79-9b12107b77d2	Giresun	il	\N	https://example.com/covers/giresun_cover.jpg	https://example.com/logos/giresun_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	461916	0454 999 00 00	https://www.giresun.bel.tr	info@giresun.bel.tr	Giresun Belediye Binası, Merkez	{https://facebook.com/giresunbelediye,https://twitter.com/giresunbelediye,https://instagram.com/giresunbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
851e199e-0ffe-47ee-ac3b-479b86d785a0	Gümüşhane	il	\N	https://example.com/covers/gumushane_cover.jpg	https://example.com/logos/gumushane_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	480087	0456 999 00 00	https://www.gumushane.bel.tr	info@gumushane.bel.tr	Gümüşhane Belediye Binası, Merkez	{https://facebook.com/gumushanebelediye,https://twitter.com/gumushanebelediye,https://instagram.com/gumushanebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0c856373-5d24-4bcc-81d9-e1177723d9b2	Hakkâri	il	\N	https://example.com/covers/hakkâri_cover.jpg	https://example.com/logos/hakkâri_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1028129	0438 999 00 00	https://www.hakkari.bel.tr	info@hakkâri.bel.tr	Hakkâri Belediye Binası, Merkez	{https://facebook.com/hakkâribelediye,https://twitter.com/hakkâribelediye,https://instagram.com/hakkâribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c2eded67-b5a6-4ac9-bfc1-217631683075	Hatay	il	\N	https://example.com/covers/hatay_cover.jpg	https://example.com/logos/hatay_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	406076	0326 999 00 00	https://www.hatay.bel.tr	info@hatay.bel.tr	Hatay Belediye Binası, Merkez	{https://facebook.com/hataybelediye,https://twitter.com/hataybelediye,https://instagram.com/hataybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
47156bd6-9879-46b3-b51f-84e0644d0f18	Iğdır	il	\N	https://example.com/covers/igdir_cover.jpg	https://example.com/logos/igdir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	507897	0476 999 00 00	https://www.igdir.bel.tr	info@igdir.bel.tr	Iğdır Belediye Binası, Merkez	{https://facebook.com/igdirbelediye,https://twitter.com/igdirbelediye,https://instagram.com/igdirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bfa52976-8583-45fe-ab46-5c9b273a3351	Isparta	il	\N	https://example.com/covers/isparta_cover.jpg	https://example.com/logos/isparta_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	154831	0246 999 00 00	https://www.isparta.bel.tr	info@isparta.bel.tr	Isparta Belediye Binası, Merkez	{https://facebook.com/ispartabelediye,https://twitter.com/ispartabelediye,https://instagram.com/ispartabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a928ea82-4ed2-4164-a2af-220dc27600c8	İstanbul	il	\N	https://example.com/covers/istanbul_cover.jpg	https://example.com/logos/istanbul_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	167993	0212 999 00 00	https://www.ibb.istanbul	info@istanbul.bel.tr	İstanbul Belediye Binası, Merkez	{https://facebook.com/istanbulbelediye,https://twitter.com/istanbulbelediye,https://instagram.com/istanbulbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ebae551b-a859-43f9-9c44-2fc0bb514b15	Adalar	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/adalar_cover.jpg	https://example.com/logos/adalar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	441283	a928ea82-8130	https://www.adalar.istanbul.bel.tr	info@adalar.bel.tr	Adalar Belediye Binası, İstanbul	{https://facebook.com/adalarbelediye,https://twitter.com/adalarbelediye,https://instagram.com/adalarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9dd4f24c-de36-48b4-8771-2e1e49504c2b	Arnavutköy	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/arnavutkoy_cover.jpg	https://example.com/logos/arnavutkoy_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	373536	a928ea82-2337	https://www.arnavutkoy.istanbul.bel.tr	info@arnavutkoy.bel.tr	Arnavutköy Belediye Binası, İstanbul	{https://facebook.com/arnavutkoybelediye,https://twitter.com/arnavutkoybelediye,https://instagram.com/arnavutkoybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3050ca24-ef41-4c29-a5e7-b769e3a6d7ff	Ataşehir	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/atasehir_cover.jpg	https://example.com/logos/atasehir_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	273586	a928ea82-1220	https://www.atasehir.istanbul.bel.tr	info@atasehir.bel.tr	Ataşehir Belediye Binası, İstanbul	{https://facebook.com/atasehirbelediye,https://twitter.com/atasehirbelediye,https://instagram.com/atasehirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
638cca15-cbe8-43f8-9b03-92aecd6a313f	Avcılar	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/avcilar_cover.jpg	https://example.com/logos/avcilar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	303238	a928ea82-0897	https://www.avcilar.istanbul.bel.tr	info@avcilar.bel.tr	Avcılar Belediye Binası, İstanbul	{https://facebook.com/avcilarbelediye,https://twitter.com/avcilarbelediye,https://instagram.com/avcilarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
26838d25-e20e-4c24-85e6-ef55c9d4c427	Bağcılar	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/bagcilar_cover.jpg	https://example.com/logos/bagcilar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	477964	a928ea82-2903	https://www.bagcilar.istanbul.bel.tr	info@bagcilar.bel.tr	Bağcılar Belediye Binası, İstanbul	{https://facebook.com/bagcilarbelediye,https://twitter.com/bagcilarbelediye,https://instagram.com/bagcilarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
af35ced4-4d44-4786-8684-193d31f46890	Bahçelievler	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/bahçelievler_cover.jpg	https://example.com/logos/bahçelievler_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	42385	a928ea82-0996	https://www.bahçelievler.istanbul.bel.tr	info@bahçelievler.bel.tr	Bahçelievler Belediye Binası, İstanbul	{https://facebook.com/bahçelievlerbelediye,https://twitter.com/bahçelievlerbelediye,https://instagram.com/bahçelievlerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
69c3b8ee-13d9-46f1-97f1-5cad38087a6f	Bakırköy	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/bakirkoy_cover.jpg	https://example.com/logos/bakirkoy_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	498715	a928ea82-2746	https://www.bakirkoy.istanbul.bel.tr	info@bakirkoy.bel.tr	Bakırköy Belediye Binası, İstanbul	{https://facebook.com/bakirkoybelediye,https://twitter.com/bakirkoybelediye,https://instagram.com/bakirkoybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9c13d7c2-c768-4d06-8239-6905e9268528	Başakşehir	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/basaksehir_cover.jpg	https://example.com/logos/basaksehir_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	342605	a928ea82-7135	https://www.basaksehir.istanbul.bel.tr	info@basaksehir.bel.tr	Başakşehir Belediye Binası, İstanbul	{https://facebook.com/basaksehirbelediye,https://twitter.com/basaksehirbelediye,https://instagram.com/basaksehirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
435e8dbb-13de-4601-bff1-91446ff561ca	Bayrampaşa	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/bayrampasa_cover.jpg	https://example.com/logos/bayrampasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	409055	a928ea82-6238	https://www.bayrampasa.istanbul.bel.tr	info@bayrampasa.bel.tr	Bayrampaşa Belediye Binası, İstanbul	{https://facebook.com/bayrampasabelediye,https://twitter.com/bayrampasabelediye,https://instagram.com/bayrampasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
92347cda-3166-406f-9e2f-879c7fb93436	Beşiktaş	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/besiktas_cover.jpg	https://example.com/logos/besiktas_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	369969	a928ea82-1242	https://www.besiktas.istanbul.bel.tr	info@besiktas.bel.tr	Beşiktaş Belediye Binası, İstanbul	{https://facebook.com/besiktasbelediye,https://twitter.com/besiktasbelediye,https://instagram.com/besiktasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a5672bfe-18c7-4fff-b515-0ddb8af545f7	Beykoz	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/beykoz_cover.jpg	https://example.com/logos/beykoz_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	132260	a928ea82-8693	https://www.beykoz.istanbul.bel.tr	info@beykoz.bel.tr	Beykoz Belediye Binası, İstanbul	{https://facebook.com/beykozbelediye,https://twitter.com/beykozbelediye,https://instagram.com/beykozbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d90a939e-78bc-46e5-8b4a-502423c9956e	Beylikdüzü	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/beylikduzu_cover.jpg	https://example.com/logos/beylikduzu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	380488	a928ea82-5794	https://www.beylikduzu.istanbul.bel.tr	info@beylikduzu.bel.tr	Beylikdüzü Belediye Binası, İstanbul	{https://facebook.com/beylikduzubelediye,https://twitter.com/beylikduzubelediye,https://instagram.com/beylikduzubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bf08d80f-97d3-4345-8ed8-ef1ad87ae621	Beyoğlu	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/beyoglu_cover.jpg	https://example.com/logos/beyoglu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	277815	a928ea82-1167	https://www.beyoglu.istanbul.bel.tr	info@beyoglu.bel.tr	Beyoğlu Belediye Binası, İstanbul	{https://facebook.com/beyoglubelediye,https://twitter.com/beyoglubelediye,https://instagram.com/beyoglubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a004f798-5e5e-4046-80f8-69fd7781ffce	Büyükçekmece	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/buyukçekmece_cover.jpg	https://example.com/logos/buyukçekmece_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	235969	a928ea82-9344	https://www.buyukçekmece.istanbul.bel.tr	info@buyukçekmece.bel.tr	Büyükçekmece Belediye Binası, İstanbul	{https://facebook.com/buyukçekmecebelediye,https://twitter.com/buyukçekmecebelediye,https://instagram.com/buyukçekmecebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ac9be4d6-fa15-43f3-bfa1-836fb91cc728	Çatalca	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/çatalca_cover.jpg	https://example.com/logos/çatalca_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	76617	a928ea82-6295	https://www.çatalca.istanbul.bel.tr	info@çatalca.bel.tr	Çatalca Belediye Binası, İstanbul	{https://facebook.com/çatalcabelediye,https://twitter.com/çatalcabelediye,https://instagram.com/çatalcabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3fc57ba7-457d-4b73-a490-770618addd31	Çekmeköy	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/çekmekoy_cover.jpg	https://example.com/logos/çekmekoy_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	321878	a928ea82-4601	https://www.çekmekoy.istanbul.bel.tr	info@çekmekoy.bel.tr	Çekmeköy Belediye Binası, İstanbul	{https://facebook.com/çekmekoybelediye,https://twitter.com/çekmekoybelediye,https://instagram.com/çekmekoybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
138390cc-a3d8-45f9-9262-4a8c8d7cb704	Esenler	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/esenler_cover.jpg	https://example.com/logos/esenler_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	362727	a928ea82-2535	https://www.esenler.istanbul.bel.tr	info@esenler.bel.tr	Esenler Belediye Binası, İstanbul	{https://facebook.com/esenlerbelediye,https://twitter.com/esenlerbelediye,https://instagram.com/esenlerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6cf41503-0927-49ec-af78-7173cc7ed165	Esenyurt	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/esenyurt_cover.jpg	https://example.com/logos/esenyurt_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	331456	a928ea82-7902	https://www.esenyurt.istanbul.bel.tr	info@esenyurt.bel.tr	Esenyurt Belediye Binası, İstanbul	{https://facebook.com/esenyurtbelediye,https://twitter.com/esenyurtbelediye,https://instagram.com/esenyurtbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
5e22e42d-310c-4681-a6d7-fbbac2ea16b2	Eyüpsultan	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/eyupsultan_cover.jpg	https://example.com/logos/eyupsultan_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	335801	a928ea82-9178	https://www.eyupsultan.istanbul.bel.tr	info@eyupsultan.bel.tr	Eyüpsultan Belediye Binası, İstanbul	{https://facebook.com/eyupsultanbelediye,https://twitter.com/eyupsultanbelediye,https://instagram.com/eyupsultanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
79d8a91e-e99d-4ad6-9d54-945e9a87e85f	Fatih	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/fatih_cover.jpg	https://example.com/logos/fatih_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	353572	a928ea82-3149	https://www.fatih.istanbul.bel.tr	info@fatih.bel.tr	Fatih Belediye Binası, İstanbul	{https://facebook.com/fatihbelediye,https://twitter.com/fatihbelediye,https://instagram.com/fatihbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
09933206-dd0a-43f0-9a00-8e6a6b8f6764	Tuzla	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/tuzla_cover.jpg	https://example.com/logos/tuzla_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	432463	a928ea82-4236	https://www.tuzla.istanbul.bel.tr	info@tuzla.bel.tr	Tuzla Belediye Binası, İstanbul	{https://facebook.com/tuzlabelediye,https://twitter.com/tuzlabelediye,https://instagram.com/tuzlabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
dbc37dd0-af13-40c8-b46b-9a6e3496ef37	Gaziosmanpaşa	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/gaziosmanpasa_cover.jpg	https://example.com/logos/gaziosmanpasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	343797	a928ea82-4046	https://www.gaziosmanpasa.istanbul.bel.tr	info@gaziosmanpasa.bel.tr	Gaziosmanpaşa Belediye Binası, İstanbul	{https://facebook.com/gaziosmanpasabelediye,https://twitter.com/gaziosmanpasabelediye,https://instagram.com/gaziosmanpasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
edc2aacb-2288-4167-a179-57b8330107a8	Güngören	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/gungoren_cover.jpg	https://example.com/logos/gungoren_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	80251	a928ea82-4860	https://www.gungoren.istanbul.bel.tr	info@gungoren.bel.tr	Güngören Belediye Binası, İstanbul	{https://facebook.com/gungorenbelediye,https://twitter.com/gungorenbelediye,https://instagram.com/gungorenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
117dd379-cdc1-4ab6-8183-21032050544c	Kadıköy	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/kadikoy_cover.jpg	https://example.com/logos/kadikoy_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	38369	a928ea82-6967	https://www.kadikoy.istanbul.bel.tr	info@kadikoy.bel.tr	Kadıköy Belediye Binası, İstanbul	{https://facebook.com/kadikoybelediye,https://twitter.com/kadikoybelediye,https://instagram.com/kadikoybelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1594df61-b64d-4c92-978e-f387851b489f	Kağıthane	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/kagithane_cover.jpg	https://example.com/logos/kagithane_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	363799	a928ea82-0160	https://www.kagithane.istanbul.bel.tr	info@kagithane.bel.tr	Kağıthane Belediye Binası, İstanbul	{https://facebook.com/kagithanebelediye,https://twitter.com/kagithanebelediye,https://instagram.com/kagithanebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
1b44fc0e-fd03-4d4b-991f-4468cb051d29	Kartal	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/kartal_cover.jpg	https://example.com/logos/kartal_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	270716	a928ea82-1909	https://www.kartal.istanbul.bel.tr	info@kartal.bel.tr	Kartal Belediye Binası, İstanbul	{https://facebook.com/kartalbelediye,https://twitter.com/kartalbelediye,https://instagram.com/kartalbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
7f59456d-9051-4f57-bf4e-c5cd1da241ce	Balçova	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/balçova_cover.jpg	https://example.com/logos/balçova_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	67883	f1f7b406-8955	https://www.balçova.izmir.bel.tr	info@balçova.bel.tr	Balçova Belediye Binası, İzmir	{https://facebook.com/balçovabelediye,https://twitter.com/balçovabelediye,https://instagram.com/balçovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c28c413b-eeb3-4223-aaf0-8224aae58959	Küçükçekmece	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/kuçukçekmece_cover.jpg	https://example.com/logos/kuçukçekmece_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	130813	a928ea82-0048	https://www.kuçukçekmece.istanbul.bel.tr	info@kuçukçekmece.bel.tr	Küçükçekmece Belediye Binası, İstanbul	{https://facebook.com/kuçukçekmecebelediye,https://twitter.com/kuçukçekmecebelediye,https://instagram.com/kuçukçekmecebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bff96555-71c7-408f-8d3c-fb346bab268b	Maltepe	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/maltepe_cover.jpg	https://example.com/logos/maltepe_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	371696	a928ea82-1263	https://www.maltepe.istanbul.bel.tr	info@maltepe.bel.tr	Maltepe Belediye Binası, İstanbul	{https://facebook.com/maltepebelediye,https://twitter.com/maltepebelediye,https://instagram.com/maltepebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ae62f9fe-002b-454b-8576-6038508bd26a	Pendik	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/pendik_cover.jpg	https://example.com/logos/pendik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	203075	a928ea82-3738	https://www.pendik.istanbul.bel.tr	info@pendik.bel.tr	Pendik Belediye Binası, İstanbul	{https://facebook.com/pendikbelediye,https://twitter.com/pendikbelediye,https://instagram.com/pendikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
2c321845-a80b-4a4a-92a0-148463024eb8	Sancaktepe	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/sancaktepe_cover.jpg	https://example.com/logos/sancaktepe_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	453475	a928ea82-7684	https://www.sancaktepe.istanbul.bel.tr	info@sancaktepe.bel.tr	Sancaktepe Belediye Binası, İstanbul	{https://facebook.com/sancaktepebelediye,https://twitter.com/sancaktepebelediye,https://instagram.com/sancaktepebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3eee493e-fc6f-44be-944d-d58f74b749da	Sarıyer	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/sariyer_cover.jpg	https://example.com/logos/sariyer_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	60076	a928ea82-2664	https://www.sariyer.istanbul.bel.tr	info@sariyer.bel.tr	Sarıyer Belediye Binası, İstanbul	{https://facebook.com/sariyerbelediye,https://twitter.com/sariyerbelediye,https://instagram.com/sariyerbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
96bd0148-3f11-4200-995e-58b59fd56033	Silivri	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/silivri_cover.jpg	https://example.com/logos/silivri_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	213844	a928ea82-9510	https://www.silivri.istanbul.bel.tr	info@silivri.bel.tr	Silivri Belediye Binası, İstanbul	{https://facebook.com/silivribelediye,https://twitter.com/silivribelediye,https://instagram.com/silivribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
74b1d74c-c53c-4790-9c78-c5298cdc80c2	Sultanbeyli	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/sultanbeyli_cover.jpg	https://example.com/logos/sultanbeyli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	117835	a928ea82-8626	https://www.sultanbeyli.istanbul.bel.tr	info@sultanbeyli.bel.tr	Sultanbeyli Belediye Binası, İstanbul	{https://facebook.com/sultanbeylibelediye,https://twitter.com/sultanbeylibelediye,https://instagram.com/sultanbeylibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
13035278-7fac-4f7c-a5c0-19cc7584d925	Sultangazi	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/sultangazi_cover.jpg	https://example.com/logos/sultangazi_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	107155	a928ea82-4376	https://www.sultangazi.istanbul.bel.tr	info@sultangazi.bel.tr	Sultangazi Belediye Binası, İstanbul	{https://facebook.com/sultangazibelediye,https://twitter.com/sultangazibelediye,https://instagram.com/sultangazibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
556a6f7b-f295-41d4-9ca4-73ff9115c160	Şile	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/şile_cover.jpg	https://example.com/logos/şile_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	311824	a928ea82-3686	https://www.şile.istanbul.bel.tr	info@şile.bel.tr	Şile Belediye Binası, İstanbul	{https://facebook.com/şilebelediye,https://twitter.com/şilebelediye,https://instagram.com/şilebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b89a3672-132a-481e-a064-b1c833b156f6	Şişli	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/şisli_cover.jpg	https://example.com/logos/şisli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	196294	a928ea82-6483	https://www.şisli.istanbul.bel.tr	info@şisli.bel.tr	Şişli Belediye Binası, İstanbul	{https://facebook.com/şislibelediye,https://twitter.com/şislibelediye,https://instagram.com/şislibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0dfc146e-fa60-4008-82cd-13fc2d2c2c92	Ümraniye	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/ümraniye_cover.jpg	https://example.com/logos/ümraniye_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	337469	a928ea82-8302	https://www.ümraniye.istanbul.bel.tr	info@ümraniye.bel.tr	Ümraniye Belediye Binası, İstanbul	{https://facebook.com/ümraniyebelediye,https://twitter.com/ümraniyebelediye,https://instagram.com/ümraniyebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
3a0c435d-0f3e-4b30-8d06-d49e0282f598	Üsküdar	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/üskudar_cover.jpg	https://example.com/logos/üskudar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	190787	a928ea82-9877	https://www.üskudar.istanbul.bel.tr	info@üskudar.bel.tr	Üsküdar Belediye Binası, İstanbul	{https://facebook.com/üskudarbelediye,https://twitter.com/üskudarbelediye,https://instagram.com/üskudarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
4ee3f6d8-a76e-41c4-baa4-c48de13a55e2	Zeytinburnu	ilçe	a928ea82-4ed2-4164-a2af-220dc27600c8	https://example.com/covers/zeytinburnu_cover.jpg	https://example.com/logos/zeytinburnu_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	249909	a928ea82-9446	https://www.zeytinburnu.istanbul.bel.tr	info@zeytinburnu.bel.tr	Zeytinburnu Belediye Binası, İstanbul	{https://facebook.com/zeytinburnubelediye,https://twitter.com/zeytinburnubelediye,https://instagram.com/zeytinburnubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f1f7b406-03e8-470b-a754-b64e8e830700	İzmir	il	\N	https://example.com/covers/izmir_cover.jpg	https://example.com/logos/izmir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	500293	0232 999 00 00	https://www.izmir.bel.tr	info@izmir.bel.tr	İzmir Belediye Binası, Merkez	{https://facebook.com/izmirbelediye,https://twitter.com/izmirbelediye,https://instagram.com/izmirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8b1aa731-9714-4436-b959-754a83e31bc5	Aliağa	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/aliaga_cover.jpg	https://example.com/logos/aliaga_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	164291	f1f7b406-2946	https://www.aliaga.izmir.bel.tr	info@aliaga.bel.tr	Aliağa Belediye Binası, İzmir	{https://facebook.com/aliagabelediye,https://twitter.com/aliagabelediye,https://instagram.com/aliagabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
accfda3c-c73a-443f-a5a0-6af11527ce6f	Bayındır	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/bayindir_cover.jpg	https://example.com/logos/bayindir_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	223493	f1f7b406-8186	https://www.bayindir.izmir.bel.tr	info@bayindir.bel.tr	Bayındır Belediye Binası, İzmir	{https://facebook.com/bayindirbelediye,https://twitter.com/bayindirbelediye,https://instagram.com/bayindirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
62437c27-3ce5-474e-93da-6dfedef6fb9b	Bayraklı	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/bayrakli_cover.jpg	https://example.com/logos/bayrakli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	107056	f1f7b406-4599	https://www.bayrakli.izmir.bel.tr	info@bayrakli.bel.tr	Bayraklı Belediye Binası, İzmir	{https://facebook.com/bayraklibelediye,https://twitter.com/bayraklibelediye,https://instagram.com/bayraklibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9bdd206b-f2dd-4df4-b9ff-ea4d4f8a5dcd	Bergama	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/bergama_cover.jpg	https://example.com/logos/bergama_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	371773	f1f7b406-7371	https://www.bergama.izmir.bel.tr	info@bergama.bel.tr	Bergama Belediye Binası, İzmir	{https://facebook.com/bergamabelediye,https://twitter.com/bergamabelediye,https://instagram.com/bergamabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
002fcb45-62d6-4193-82bf-8d109281b3c0	Beydağ	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/beydag_cover.jpg	https://example.com/logos/beydag_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	427421	f1f7b406-3970	https://www.beydag.izmir.bel.tr	info@beydag.bel.tr	Beydağ Belediye Binası, İzmir	{https://facebook.com/beydagbelediye,https://twitter.com/beydagbelediye,https://instagram.com/beydagbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cde77dda-ec6c-46d3-92aa-2b789866ed22	Bornova	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/bornova_cover.jpg	https://example.com/logos/bornova_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	331750	f1f7b406-7507	https://www.bornova.izmir.bel.tr	info@bornova.bel.tr	Bornova Belediye Binası, İzmir	{https://facebook.com/bornovabelediye,https://twitter.com/bornovabelediye,https://instagram.com/bornovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b4031b50-cc3e-4626-8f0c-393725e96085	Buca	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/buca_cover.jpg	https://example.com/logos/buca_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	178012	f1f7b406-1249	https://www.buca.izmir.bel.tr	info@buca.bel.tr	Buca Belediye Binası, İzmir	{https://facebook.com/bucabelediye,https://twitter.com/bucabelediye,https://instagram.com/bucabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d5e2441d-d037-4fa3-96da-7d68451a5182	Çeşme	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/çesme_cover.jpg	https://example.com/logos/çesme_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	459115	f1f7b406-0722	https://www.çesme.izmir.bel.tr	info@çesme.bel.tr	Çeşme Belediye Binası, İzmir	{https://facebook.com/çesmebelediye,https://twitter.com/çesmebelediye,https://instagram.com/çesmebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9cbc59df-00d5-478d-8c19-d9e808ebe10c	Çiğli	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/çigli_cover.jpg	https://example.com/logos/çigli_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	86028	f1f7b406-6114	https://www.çigli.izmir.bel.tr	info@çigli.bel.tr	Çiğli Belediye Binası, İzmir	{https://facebook.com/çiglibelediye,https://twitter.com/çiglibelediye,https://instagram.com/çiglibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
36645f41-62a9-44ad-be7c-97c642091a4b	Dikili	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/dikili_cover.jpg	https://example.com/logos/dikili_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	367733	f1f7b406-2920	https://www.dikili.izmir.bel.tr	info@dikili.bel.tr	Dikili Belediye Binası, İzmir	{https://facebook.com/dikilibelediye,https://twitter.com/dikilibelediye,https://instagram.com/dikilibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
2c9e494f-c2f8-4b5b-8de0-309e919d80b1	Foça	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/foça_cover.jpg	https://example.com/logos/foça_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	74210	f1f7b406-2667	https://www.foça.izmir.bel.tr	info@foça.bel.tr	Foça Belediye Binası, İzmir	{https://facebook.com/foçabelediye,https://twitter.com/foçabelediye,https://instagram.com/foçabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
33c2a768-0cf8-4e7a-b6f3-7a21652b0f03	Gaziemir	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/gaziemir_cover.jpg	https://example.com/logos/gaziemir_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	306411	f1f7b406-6457	https://www.gaziemir.izmir.bel.tr	info@gaziemir.bel.tr	Gaziemir Belediye Binası, İzmir	{https://facebook.com/gaziemirbelediye,https://twitter.com/gaziemirbelediye,https://instagram.com/gaziemirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c67a78c1-1e1f-4514-a147-f809e3973353	Güzelbahçe	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/guzelbahçe_cover.jpg	https://example.com/logos/guzelbahçe_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	245944	f1f7b406-6440	https://www.guzelbahçe.izmir.bel.tr	info@guzelbahçe.bel.tr	Güzelbahçe Belediye Binası, İzmir	{https://facebook.com/guzelbahçebelediye,https://twitter.com/guzelbahçebelediye,https://instagram.com/guzelbahçebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
2d1fa368-0071-48cb-9495-f900289746d7	Karabağlar	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/karabaglar_cover.jpg	https://example.com/logos/karabaglar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	22841	f1f7b406-2629	https://www.karabaglar.izmir.bel.tr	info@karabaglar.bel.tr	Karabağlar Belediye Binası, İzmir	{https://facebook.com/karabaglarbelediye,https://twitter.com/karabaglarbelediye,https://instagram.com/karabaglarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d7ef55bc-a463-4992-bcb2-2fbf4e1a55f9	Karaburun	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/karaburun_cover.jpg	https://example.com/logos/karaburun_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	148058	f1f7b406-0384	https://www.karaburun.izmir.bel.tr	info@karaburun.bel.tr	Karaburun Belediye Binası, İzmir	{https://facebook.com/karaburunbelediye,https://twitter.com/karaburunbelediye,https://instagram.com/karaburunbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
a437edbd-a865-4d61-8032-fea937b636fb	Karşıyaka	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/karsiyaka_cover.jpg	https://example.com/logos/karsiyaka_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	222278	f1f7b406-9141	https://www.karsiyaka.izmir.bel.tr	info@karsiyaka.bel.tr	Karşıyaka Belediye Binası, İzmir	{https://facebook.com/karsiyakabelediye,https://twitter.com/karsiyakabelediye,https://instagram.com/karsiyakabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c2c40db5-5711-4794-ac0f-fbde5bea8b3d	Kemalpaşa	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/kemalpasa_cover.jpg	https://example.com/logos/kemalpasa_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	478655	f1f7b406-6298	https://www.kemalpasa.izmir.bel.tr	info@kemalpasa.bel.tr	Kemalpaşa Belediye Binası, İzmir	{https://facebook.com/kemalpasabelediye,https://twitter.com/kemalpasabelediye,https://instagram.com/kemalpasabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
46725bb5-ca8d-4e4d-a89b-83c56070037c	Kınık	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/kinik_cover.jpg	https://example.com/logos/kinik_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	119826	f1f7b406-7741	https://www.kinik.izmir.bel.tr	info@kinik.bel.tr	Kınık Belediye Binası, İzmir	{https://facebook.com/kinikbelediye,https://twitter.com/kinikbelediye,https://instagram.com/kinikbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cddb4262-feb3-47fb-a7f1-d7098165bdfa	Kiraz	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/kiraz_cover.jpg	https://example.com/logos/kiraz_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	454219	f1f7b406-5874	https://www.kiraz.izmir.bel.tr	info@kiraz.bel.tr	Kiraz Belediye Binası, İzmir	{https://facebook.com/kirazbelediye,https://twitter.com/kirazbelediye,https://instagram.com/kirazbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c6f92089-78f6-46fc-8006-4ad7c10ca886	Konak	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/konak_cover.jpg	https://example.com/logos/konak_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	277869	f1f7b406-8414	https://www.konak.izmir.bel.tr	info@konak.bel.tr	Konak Belediye Binası, İzmir	{https://facebook.com/konakbelediye,https://twitter.com/konakbelediye,https://instagram.com/konakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d44911fa-de1f-4179-aea8-71731b9d21a6	Menderes	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/menderes_cover.jpg	https://example.com/logos/menderes_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	90178	f1f7b406-2091	https://www.menderes.izmir.bel.tr	info@menderes.bel.tr	Menderes Belediye Binası, İzmir	{https://facebook.com/menderesbelediye,https://twitter.com/menderesbelediye,https://instagram.com/menderesbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b39d7a87-d74a-4fc5-a54e-7504716f55f7	Menemen	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/menemen_cover.jpg	https://example.com/logos/menemen_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	458139	f1f7b406-5826	https://www.menemen.izmir.bel.tr	info@menemen.bel.tr	Menemen Belediye Binası, İzmir	{https://facebook.com/menemenbelediye,https://twitter.com/menemenbelediye,https://instagram.com/menemenbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
dbb4c093-800f-4115-a1a3-da3fcfac5fb6	Narlıdere	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/narlidere_cover.jpg	https://example.com/logos/narlidere_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	241842	f1f7b406-5008	https://www.narlidere.izmir.bel.tr	info@narlidere.bel.tr	Narlıdere Belediye Binası, İzmir	{https://facebook.com/narliderebelediye,https://twitter.com/narliderebelediye,https://instagram.com/narliderebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
900bccd8-cfd4-408e-af85-8c5c2291a826	Ödemiş	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/ödemis_cover.jpg	https://example.com/logos/ödemis_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	415303	f1f7b406-4405	https://www.ödemis.izmir.bel.tr	info@ödemis.bel.tr	Ödemiş Belediye Binası, İzmir	{https://facebook.com/ödemisbelediye,https://twitter.com/ödemisbelediye,https://instagram.com/ödemisbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
abd4dd9a-8195-47d8-8f18-5c0ec79f3f27	Seferihisar	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/seferihisar_cover.jpg	https://example.com/logos/seferihisar_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	356762	f1f7b406-5992	https://www.seferihisar.izmir.bel.tr	info@seferihisar.bel.tr	Seferihisar Belediye Binası, İzmir	{https://facebook.com/seferihisarbelediye,https://twitter.com/seferihisarbelediye,https://instagram.com/seferihisarbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
19b2c281-d744-49b0-ad3c-a3b7751a6cdd	Selçuk	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/selçuk_cover.jpg	https://example.com/logos/selçuk_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	272514	f1f7b406-6115	https://www.selçuk.izmir.bel.tr	info@selçuk.bel.tr	Selçuk Belediye Binası, İzmir	{https://facebook.com/selçukbelediye,https://twitter.com/selçukbelediye,https://instagram.com/selçukbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
05b4a197-0f6b-43e7-827a-8d45543201dd	Tire	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/tire_cover.jpg	https://example.com/logos/tire_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	77148	f1f7b406-7946	https://www.tire.izmir.bel.tr	info@tire.bel.tr	Tire Belediye Binası, İzmir	{https://facebook.com/tirebelediye,https://twitter.com/tirebelediye,https://instagram.com/tirebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d7187a80-b3fa-4ef2-b3c6-ecedb02dd598	Torbalı	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/torbali_cover.jpg	https://example.com/logos/torbali_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	178009	f1f7b406-0575	https://www.torbali.izmir.bel.tr	info@torbali.bel.tr	Torbalı Belediye Binası, İzmir	{https://facebook.com/torbalibelediye,https://twitter.com/torbalibelediye,https://instagram.com/torbalibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b9ac3b25-ff95-4368-8b57-9a37e4859129	Urla	ilçe	f1f7b406-03e8-470b-a754-b64e8e830700	https://example.com/covers/urla_cover.jpg	https://example.com/logos/urla_logo.png	İlçe Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	464517	f1f7b406-3837	https://www.urla.izmir.bel.tr	info@urla.bel.tr	Urla Belediye Binası, İzmir	{https://facebook.com/urlabelediye,https://twitter.com/urlabelediye,https://instagram.com/urlabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
40f9c0a0-91eb-43a6-a8cf-20c631928b94	Kahramanmaraş	il	\N	https://example.com/covers/kahramanmaras_cover.jpg	https://example.com/logos/kahramanmaras_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1013380	0344 999 00 00	https://www.kahramanmaras.bel.tr	info@kahramanmaras.bel.tr	Kahramanmaraş Belediye Binası, Merkez	{https://facebook.com/kahramanmarasbelediye,https://twitter.com/kahramanmarasbelediye,https://instagram.com/kahramanmarasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f20c7675-cde0-4dd0-aaa9-b8960b94e87b	Karabük	il	\N	https://example.com/covers/karabuk_cover.jpg	https://example.com/logos/karabuk_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	221927	0370 999 00 00	https://www.karabuk.bel.tr	info@karabuk.bel.tr	Karabük Belediye Binası, Merkez	{https://facebook.com/karabukbelediye,https://twitter.com/karabukbelediye,https://instagram.com/karabukbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
8deb4bae-40c1-4d15-a25c-9f696a807f65	Karaman	il	\N	https://example.com/covers/karaman_cover.jpg	https://example.com/logos/karaman_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	246321	0338 999 00 00	https://www.karaman.bel.tr	info@karaman.bel.tr	Karaman Belediye Binası, Merkez	{https://facebook.com/karamanbelediye,https://twitter.com/karamanbelediye,https://instagram.com/karamanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b66e09ec-42a5-4cc7-896a-ff9ac1979b7f	Kars	il	\N	https://example.com/covers/kars_cover.jpg	https://example.com/logos/kars_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	135533	0474 999 00 00	https://www.kars.bel.tr	info@kars.bel.tr	Kars Belediye Binası, Merkez	{https://facebook.com/karsbelediye,https://twitter.com/karsbelediye,https://instagram.com/karsbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
64d5bbbc-5c81-44a3-a55b-112a25c4ce43	Kastamonu	il	\N	https://example.com/covers/kastamonu_cover.jpg	https://example.com/logos/kastamonu_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	392074	0366 999 00 00	https://www.kastamonu.bel.tr	info@kastamonu.bel.tr	Kastamonu Belediye Binası, Merkez	{https://facebook.com/kastamonubelediye,https://twitter.com/kastamonubelediye,https://instagram.com/kastamonubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d4f874fc-f2d8-47a9-90b4-4517cca154bd	Kayseri	il	\N	https://example.com/covers/kayseri_cover.jpg	https://example.com/logos/kayseri_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	855839	0352 999 00 00	https://www.kayseri.bel.tr	info@kayseri.bel.tr	Kayseri Belediye Binası, Merkez	{https://facebook.com/kayseribelediye,https://twitter.com/kayseribelediye,https://instagram.com/kayseribelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e38cecba-6dfa-4151-b30e-08eb81911563	Kırıkkale	il	\N	https://example.com/covers/kirikkale_cover.jpg	https://example.com/logos/kirikkale_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	968768	0318 999 00 00	https://www.kirikkale.bel.tr	info@kirikkale.bel.tr	Kırıkkale Belediye Binası, Merkez	{https://facebook.com/kirikkalebelediye,https://twitter.com/kirikkalebelediye,https://instagram.com/kirikkalebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
98e21557-70f5-462c-b2ba-7dabf4cf2260	Kırklareli	il	\N	https://example.com/covers/kirklareli_cover.jpg	https://example.com/logos/kirklareli_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	518634	0288 999 00 00	https://www.kirklareli.bel.tr	info@kirklareli.bel.tr	Kırklareli Belediye Binası, Merkez	{https://facebook.com/kirklarelibelediye,https://twitter.com/kirklarelibelediye,https://instagram.com/kirklarelibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
0ae4b745-bbe6-4cf4-b3cb-29dfd226f9ef	Kırşehir	il	\N	https://example.com/covers/kirsehir_cover.jpg	https://example.com/logos/kirsehir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	905948	0386 999 00 00	https://www.kirsehir.bel.tr	info@kirsehir.bel.tr	Kırşehir Belediye Binası, Merkez	{https://facebook.com/kirsehirbelediye,https://twitter.com/kirsehirbelediye,https://instagram.com/kirsehirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c6bb5f57-8b13-4edf-90ee-b75e316503f4	Kilis	il	\N	https://example.com/covers/kilis_cover.jpg	https://example.com/logos/kilis_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1090663	0348 999 00 00	https://www.kilis.bel.tr	info@kilis.bel.tr	Kilis Belediye Binası, Merkez	{https://facebook.com/kilisbelediye,https://twitter.com/kilisbelediye,https://instagram.com/kilisbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6bdddfe3-da8a-4de3-9c1e-32548e1021f3	Kocaeli	il	\N	https://example.com/covers/kocaeli_cover.jpg	https://example.com/logos/kocaeli_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	207962	0262 999 00 00	https://www.kocaeli.bel.tr	info@kocaeli.bel.tr	Kocaeli Belediye Binası, Merkez	{https://facebook.com/kocaelibelediye,https://twitter.com/kocaelibelediye,https://instagram.com/kocaelibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
25c2a2a7-7329-4447-9128-b95d805c3208	Konya	il	\N	https://example.com/covers/konya_cover.jpg	https://example.com/logos/konya_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1003161	0332 999 00 00	https://www.konya.bel.tr	info@konya.bel.tr	Konya Belediye Binası, Merkez	{https://facebook.com/konyabelediye,https://twitter.com/konyabelediye,https://instagram.com/konyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
96062d16-822a-4aab-bdb6-f34812df3e88	Kütahya	il	\N	https://example.com/covers/kutahya_cover.jpg	https://example.com/logos/kutahya_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	620650	0274 999 00 00	https://www.kutahya.bel.tr	info@kutahya.bel.tr	Kütahya Belediye Binası, Merkez	{https://facebook.com/kutahyabelediye,https://twitter.com/kutahyabelediye,https://instagram.com/kutahyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
198345ec-824f-424f-bfb7-35aa6c01b209	Malatya	il	\N	https://example.com/covers/malatya_cover.jpg	https://example.com/logos/malatya_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	916835	0422 999 00 00	https://www.malatya.bel.tr	info@malatya.bel.tr	Malatya Belediye Binası, Merkez	{https://facebook.com/malatyabelediye,https://twitter.com/malatyabelediye,https://instagram.com/malatyabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
35dd42e3-3e63-45c6-a23d-8a655cca2cfb	Manisa	il	\N	https://example.com/covers/manisa_cover.jpg	https://example.com/logos/manisa_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	251262	0236 999 00 00	https://www.manisa.bel.tr	info@manisa.bel.tr	Manisa Belediye Binası, Merkez	{https://facebook.com/manisabelediye,https://twitter.com/manisabelediye,https://instagram.com/manisabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6bd6f12b-0ae5-4a02-bffb-e5b76df95bbf	Mardin	il	\N	https://example.com/covers/mardin_cover.jpg	https://example.com/logos/mardin_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	485145	0482 999 00 00	https://www.mardin.bel.tr	info@mardin.bel.tr	Mardin Belediye Binası, Merkez	{https://facebook.com/mardinbelediye,https://twitter.com/mardinbelediye,https://instagram.com/mardinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d477766d-68fd-4bf8-92bf-76885a0ed69b	Mersin	il	\N	https://example.com/covers/mersin_cover.jpg	https://example.com/logos/mersin_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	240790	0324 999 00 00	https://www.mersin.bel.tr	info@mersin.bel.tr	Mersin Belediye Binası, Merkez	{https://facebook.com/mersinbelediye,https://twitter.com/mersinbelediye,https://instagram.com/mersinbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
64a72017-3d61-4761-a931-a2cb86c047e0	Muğla	il	\N	https://example.com/covers/mugla_cover.jpg	https://example.com/logos/mugla_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	956245	0252 999 00 00	https://www.mugla.bel.tr	info@mugla.bel.tr	Muğla Belediye Binası, Merkez	{https://facebook.com/muglabelediye,https://twitter.com/muglabelediye,https://instagram.com/muglabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b5331066-d0ab-4514-820a-64d9c513e83c	Muş	il	\N	https://example.com/covers/mus_cover.jpg	https://example.com/logos/mus_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	798393	0436 999 00 00	https://www.mus.bel.tr	info@mus.bel.tr	Muş Belediye Binası, Merkez	{https://facebook.com/musbelediye,https://twitter.com/musbelediye,https://instagram.com/musbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6d93193e-128c-44b5-b31f-a116883f9f02	Nevşehir	il	\N	https://example.com/covers/nevsehir_cover.jpg	https://example.com/logos/nevsehir_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	482470	0384 999 00 00	https://www.nevsehir.bel.tr	info@nevsehir.bel.tr	Nevşehir Belediye Binası, Merkez	{https://facebook.com/nevsehirbelediye,https://twitter.com/nevsehirbelediye,https://instagram.com/nevsehirbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
e35c38df-1154-4442-b487-90b288d84f20	Niğde	il	\N	https://example.com/covers/nigde_cover.jpg	https://example.com/logos/nigde_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	903731	0388 999 00 00	https://www.nigde.bel.tr	info@nigde.bel.tr	Niğde Belediye Binası, Merkez	{https://facebook.com/nigdebelediye,https://twitter.com/nigdebelediye,https://instagram.com/nigdebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d083f2ab-0e13-4a7c-9cd1-83aacba8940e	Ordu	il	\N	https://example.com/covers/ordu_cover.jpg	https://example.com/logos/ordu_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1099821	0452 999 00 00	https://www.ordu.bel.tr	info@ordu.bel.tr	Ordu Belediye Binası, Merkez	{https://facebook.com/ordubelediye,https://twitter.com/ordubelediye,https://instagram.com/ordubelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d7b58a23-de0a-4409-9db5-8691434cad41	Osmaniye	il	\N	https://example.com/covers/osmaniye_cover.jpg	https://example.com/logos/osmaniye_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	519635	0328 999 00 00	https://www.osmaniye.bel.tr	info@osmaniye.bel.tr	Osmaniye Belediye Binası, Merkez	{https://facebook.com/osmaniyebelediye,https://twitter.com/osmaniyebelediye,https://instagram.com/osmaniyebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
f8efa375-a259-423d-82e5-5a98cf267f01	Rize	il	\N	https://example.com/covers/rize_cover.jpg	https://example.com/logos/rize_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1024280	0464 999 00 00	https://www.rize.bel.tr	info@rize.bel.tr	Rize Belediye Binası, Merkez	{https://facebook.com/rizebelediye,https://twitter.com/rizebelediye,https://instagram.com/rizebelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
96c996a5-90f8-49be-8b9e-77fa253b568f	Sakarya	il	\N	https://example.com/covers/sakarya_cover.jpg	https://example.com/logos/sakarya_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	823323	0264 999 00 00	https://www.sakarya.bel.tr	info@sakarya.bel.tr	Sakarya Belediye Binası, Merkez	{https://facebook.com/sakaryabelediye,https://twitter.com/sakaryabelediye,https://instagram.com/sakaryabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
50597f02-8b23-4972-b8e2-5f42cbb57d4f	Samsun	il	\N	https://example.com/covers/samsun_cover.jpg	https://example.com/logos/samsun_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	334816	0362 999 00 00	https://www.samsun.bel.tr	info@samsun.bel.tr	Samsun Belediye Binası, Merkez	{https://facebook.com/samsunbelediye,https://twitter.com/samsunbelediye,https://instagram.com/samsunbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
b87b3dbd-f205-474e-9efd-500421290da1	Siirt	il	\N	https://example.com/covers/siirt_cover.jpg	https://example.com/logos/siirt_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	990526	0484 999 00 00	https://www.siirt.bel.tr	info@siirt.bel.tr	Siirt Belediye Binası, Merkez	{https://facebook.com/siirtbelediye,https://twitter.com/siirtbelediye,https://instagram.com/siirtbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
cb884be5-3da9-4629-b7e9-a9f188ba0694	Sinop	il	\N	https://example.com/covers/sinop_cover.jpg	https://example.com/logos/sinop_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	603791	0368 999 00 00	https://www.sinop.bel.tr	info@sinop.bel.tr	Sinop Belediye Binası, Merkez	{https://facebook.com/sinopbelediye,https://twitter.com/sinopbelediye,https://instagram.com/sinopbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
45c625f4-8bae-4b16-ba20-fdadfe151407	Sivas	il	\N	https://example.com/covers/sivas_cover.jpg	https://example.com/logos/sivas_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	484480	0346 999 00 00	https://www.sivas.bel.tr	info@sivas.bel.tr	Sivas Belediye Binası, Merkez	{https://facebook.com/sivasbelediye,https://twitter.com/sivasbelediye,https://instagram.com/sivasbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
d2748a52-7fde-4d98-abae-5af09b8e4606	Şanlıurfa	il	\N	https://example.com/covers/şanliurfa_cover.jpg	https://example.com/logos/şanliurfa_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	956928	0414 999 00 00	https://www.sanliurfa.bel.tr	info@şanliurfa.bel.tr	Şanlıurfa Belediye Binası, Merkez	{https://facebook.com/şanliurfabelediye,https://twitter.com/şanliurfabelediye,https://instagram.com/şanliurfabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ff8d2205-ebdf-4c46-85a9-6d397d8b26fb	Şırnak	il	\N	https://example.com/covers/şirnak_cover.jpg	https://example.com/logos/şirnak_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	256757	0486 999 00 00	https://www.sirnak.bel.tr	info@şirnak.bel.tr	Şırnak Belediye Binası, Merkez	{https://facebook.com/şirnakbelediye,https://twitter.com/şirnakbelediye,https://instagram.com/şirnakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
ba18188b-ba1d-4a82-aeb3-de970b16774a	Tekirdağ	il	\N	https://example.com/covers/tekirdag_cover.jpg	https://example.com/logos/tekirdag_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	798673	0282 999 00 00	https://www.tekirdag.bel.tr	info@tekirdag.bel.tr	Tekirdağ Belediye Binası, Merkez	{https://facebook.com/tekirdagbelediye,https://twitter.com/tekirdagbelediye,https://instagram.com/tekirdagbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
9f1951af-5a0b-428f-b377-761d93ef6bc8	Tokat	il	\N	https://example.com/covers/tokat_cover.jpg	https://example.com/logos/tokat_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	862921	0356 999 00 00	https://www.tokat.bel.tr	info@tokat.bel.tr	Tokat Belediye Binası, Merkez	{https://facebook.com/tokatbelediye,https://twitter.com/tokatbelediye,https://instagram.com/tokatbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fafc2575-ab82-426f-bbbd-ca94cde2b226	Trabzon	il	\N	https://example.com/covers/trabzon_cover.jpg	https://example.com/logos/trabzon_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	698194	0462 999 00 00	https://www.trabzon.bel.tr	info@trabzon.bel.tr	Trabzon Belediye Binası, Merkez	{https://facebook.com/trabzonbelediye,https://twitter.com/trabzonbelediye,https://instagram.com/trabzonbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
6f707aa5-712f-4b84-9913-513cb62936bd	Tunceli	il	\N	https://example.com/covers/tunceli_cover.jpg	https://example.com/logos/tunceli_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	798305	0428 999 00 00	https://www.tunceli.bel.tr	info@tunceli.bel.tr	Tunceli Belediye Binası, Merkez	{https://facebook.com/tuncelibelediye,https://twitter.com/tuncelibelediye,https://instagram.com/tuncelibelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
c3fca697-16db-4102-b1df-328810c4e352	Uşak	il	\N	https://example.com/covers/usak_cover.jpg	https://example.com/logos/usak_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	185453	0276 999 00 00	https://www.usak.bel.tr	info@usak.bel.tr	Uşak Belediye Binası, Merkez	{https://facebook.com/usakbelediye,https://twitter.com/usakbelediye,https://instagram.com/usakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
efcf86c4-4469-45bd-bfa5-076a0520ed9d	Van	il	\N	https://example.com/covers/van_cover.jpg	https://example.com/logos/van_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	1014931	0432 999 00 00	https://www.van.bel.tr	info@van.bel.tr	Van Belediye Binası, Merkez	{https://facebook.com/vanbelediye,https://twitter.com/vanbelediye,https://instagram.com/vanbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
bf03acbd-4826-46ee-99cf-70b1ddb62175	Yalova	il	\N	https://example.com/covers/yalova_cover.jpg	https://example.com/logos/yalova_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	264407	0226 999 00 00	https://www.yalova.bel.tr	info@yalova.bel.tr	Yalova Belediye Binası, Merkez	{https://facebook.com/yalovabelediye,https://twitter.com/yalovabelediye,https://instagram.com/yalovabelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
fa8500d7-205d-402c-b660-2c5edff9eaf8	Yozgat	il	\N	https://example.com/covers/yozgat_cover.jpg	https://example.com/logos/yozgat_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	451813	0354 999 00 00	https://www.yozgat.bel.tr	info@yozgat.bel.tr	Yozgat Belediye Binası, Merkez	{https://facebook.com/yozgatbelediye,https://twitter.com/yozgatbelediye,https://instagram.com/yozgatbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
67096782-ce0d-49b6-843a-e2fa23d6da10	Zonguldak	il	\N	https://example.com/covers/zonguldak_cover.jpg	https://example.com/logos/zonguldak_logo.png	Belediye Başkanı	Parti	https://example.com/party_logos/default_party_logo.png	585695	0372 999 00 00	https://www.zonguldak.bel.tr	info@zonguldak.bel.tr	Zonguldak Belediye Binası, Merkez	{https://facebook.com/zonguldakbelediye,https://twitter.com/zonguldakbelediye,https://instagram.com/zonguldakbelediye}	2025-05-16 12:59:55.448481+00	2025-05-16 12:59:55.448481+00
\.


--
-- Data for Name: municipality_announcements; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.municipality_announcements (id, municipality_id, title, content, image_url, is_active, created_at, updated_at) FROM stdin;
14eb03df-0929-4844-9e41-05e6b99f626f	57394a52-0166-4f1b-9625-20dbf80765a0	Kadıköy Belediyesi Ücretsiz Sağlık Taramaları	Önümüzdeki hafta boyunca Kadıköy Belediyesi Sağlık Merkezinde ücretsiz sağlık taramaları gerçekleştirilecektir. Tüm Kadıköylüleri bekliyoruz.	https://akdosgb.com/wp-content/uploads/2021/01/Saglik-Taramasi-Yapan-Firmalari.jpg	t	2025-05-12 18:34:53.172678+00	2025-05-12 18:34:53.172678+00
b20dc244-1ea3-4540-a7ef-5c28aafbfd98	599e1d45-cb63-4d99-a7fb-c3b4b7e58a74	İstanbul Haftasonu Kültür Etkinlikleri	Bu haftasonu İstanbul genelinde düzenlenecek olan kültür etkinliklerine tüm vatandaşlarımız davetlidir. Konserler, sergiler ve çocuklar için çeşitli aktiviteler yer almaktadır.	https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSqnW43NqHxn9u8IPcJdgUftNggTlMzex9HNg&s	t	2025-05-12 18:34:53.172678+00	2025-05-12 18:34:53.172678+00
\.


--
-- Data for Name: notification_preferences; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.notification_preferences (id, user_id, likes_enabled, comments_enabled, replies_enabled, mentions_enabled, system_notifications_enabled, created_at, updated_at) FROM stdin;
2f16b1d1-d87b-41ab-a1aa-3d3b4e8e1e0a	2207daaa-64bd-49f2-80f1-4341c07225fd	t	t	t	t	t	2025-05-23 14:10:40.199868+00	2025-05-23 17:23:35.858996+00
97870c0d-010d-400e-8d4d-4364772688c4	83190944-98d5-41be-ac3a-178676faf017	t	t	t	t	t	2025-05-23 15:04:19.535251+00	2025-05-23 15:04:19.535251+00
2f573990-ab0c-46aa-838e-7c70f6d7d119	516b3dcb-aeec-4451-aa13-1894193b0b88	f	f	f	f	f	2025-05-23 18:38:03.097993+00	2025-05-23 21:57:58.291479+00
c335602b-a531-4f14-b41f-045a0b1b96f1	cdc2d279-8171-4aa5-89cb-10f81fed72c3	t	t	t	t	t	2025-05-23 19:02:28.818828+00	2025-05-23 19:02:28.818828+00
3cd31845-5a9c-495c-a2b9-96d2478b2a55	8b52a8cb-cb89-4325-9c62-de454a0476fb	t	t	t	t	t	2025-05-23 19:24:02.471351+00	2025-05-23 19:24:02.471351+00
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.notifications (id, user_id, title, content, type, is_read, sender_id, sender_name, sender_profile_url, related_entity_id, related_entity_type, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: officials; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.officials (id, user_id, city_id, district_id, title, notes, created_at, updated_at) FROM stdin;
1	83190944-98d5-41be-ac3a-178676faf017	550e8400-e29b-41d4-a716-446655440001	660e8400-e29b-41d4-a716-446655440001	Batman Belediyesi Şikayet Sorumlusu	Test hesabı	2025-05-19 22:01:48.420441+00	2025-05-19 22:01:48.420441+00
\.


--
-- Data for Name: political_parties; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.political_parties (id, name, logo_url, score, last_updated, created_at, parti_sikayet_sayisi, parti_cozulmus_sikayet_sayisi, parti_tesekkur_sayisi) FROM stdin;
15a52630-b0b4-4dc9-8b22-0617f1c43f7a	Saadet Partisi	https://upload.wikimedia.org/wikipedia/commons/thumb/2/26/Saadet_Partisi_Kare_Logo.svg/250px-Saadet_Partisi_Kare_Logo.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
2e819f87-dcec-40cf-9225-f9acbead1f06	Vatan Partisi	https://upload.wikimedia.org/wikipedia/tr/thumb/1/16/Vatanpartisilogo.png/250px-Vatanpartisilogo.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
33651132-8656-4b10-8f1c-16ed99c91a6c	DSP	https://upload.wikimedia.org/wikipedia/en/thumb/c/c7/Demokratik_Sol_Parti_%28logo%29.png/150px-Demokratik_Sol_Parti_%28logo%29.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
448575ce-7444-4bd7-8070-1753a8ecb16b	AKP	https://upload-wikimedia-org.translate.goog/wikipedia/en/thumb/5/56/Justice_and_Development_Party_%28Turkey%29_logo.svg/225px-Justice_and_Development_Party_%28Turkey%29_logo.svg.png?_x_tr_sl=en&_x_tr_tl=tr&_x_tr_hl=tr&_x_tr_pto=tc	28.6	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	1	0	2
46a4359e-86a1-4974-b022-a4532367aa5e	CHP	https://upload.wikimedia.org/wikipedia/commons/thumb/e/ef/Cumhuriyet_Halk_Partisi_Logo.svg/200px-Cumhuriyet_Halk_Partisi_Logo.svg.png	28.6	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	5	1	1
5eb2d2c8-e010-4f83-921b-06e7b446cc8f	TİP	https://secim2024-storage.ntv.com.tr/secimsonuc2024/live/assets/img/party/31.svg	0.0	2025-05-23 20:00:00.045783+00	2025-05-20 13:44:39+00	0	0	0
88e2cd92-0b8e-4537-8da1-db92574b67f4	Bağımsız Parti	https://secim2024-storage.ntv.com.tr/secimsonuc2024/live/assets/img/party/b.svg	0.0	2025-05-23 20:00:00.045783+00	2025-05-20 13:29:01+00	0	0	0
9c5e67f1-e78a-4fa4-b7ad-2234120a231a	DEVA	https://upload.wikimedia.org/wikipedia/en/thumb/4/4d/Deva_Party_Logo.svg/500px-Deva_Party_Logo.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
a3b613a3-500d-41b2-8603-25cb25b0459f	DEM Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/DEM_PART%C4%B0_LOGOSU.png/250px-DEM_PART%C4%B0_LOGOSU.png	42.9	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	1	1	2
bf3d799a-d58b-4867-aa84-65389732dc3b	Memleket Partisi	https://upload.wikimedia.org/wikipedia/en/thumb/2/24/Logo_of_the_Homeland_Party_%28Turkey%2C_2021%29.svg/225px-Logo_of_the_Homeland_Party_%28Turkey%2C_2021%29.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
d51123f3-7636-4181-8edb-227c75dcf0e4	Büyük Birlik Partisi	https://upload.wikimedia.org/wikipedia/en/thumb/0/07/Logo_of_the_Great_Unity_Party.svg/300px-Logo_of_the_Great_Unity_Party.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
f01d8318-dc02-471e-bf48-876164fe9686	SOL PARTİ	https://secim2024-storage.ntv.com.tr/secimsonuc2024/live/assets/img/party/3.svg	0.0	2025-05-23 20:00:00.045783+00	2025-05-20 13:42:30+00	0	0	0
f192d104-7d38-45c1-b51f-6a66b75c52ed	Demokrat Parti	https://upload.wikimedia.org/wikipedia/en/thumb/5/52/Logo_of_the_Democratic_Party_%28Turkey%2C_2007%29.svg/300px-Logo_of_the_Democratic_Party_%28Turkey%2C_2007%29.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
04397adc-b513-4b4e-a518-230f7aa7565d	Gelecek Partisi	https://upload.wikimedia.org/wikipedia/tr/thumb/7/79/Gelecek-logo.svg/250px-Gelecek-logo.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
1d2a4b45-d159-4cde-8418-168486e647ab	Zafer Partisi	https://upload.wikimedia.org/wikipedia/tr/9/96/Zafer_Partisi_Logo.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
08450051-c4e3-46ff-9bed-7659e197329a	İYİ Parti	https://upload.wikimedia.org/wikipedia/commons/thumb/e/e0/Logo_of_Good_Party.svg/250px-Logo_of_Good_Party.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
dfe1b574-8fcd-4c16-8496-6e96e960b253	MHP	https://www.mhp.org.tr/usr_img/mhpweb/kurumsal_logo/mhp-logo-acik-01.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
0e6cae03-1e9f-4761-a56a-b0f94ba90a3a	Yeniden Refah Partisi	https://upload.wikimedia.org/wikipedia/commons/thumb/0/0a/Yeniden_Refah_Partisi_logo.svg/250px-Yeniden_Refah_Partisi_logo.svg.png	0.0	2025-05-23 20:00:00.045783+00	2025-05-17 06:59:07.876343+00	0	0	0
\.


--
-- Data for Name: poll_options; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.poll_options (id, poll_id, option_text, color, created_at) FROM stdin;
4f263b10-6885-436b-9fdd-5121938a8cc8	aa61c289-a602-479c-8819-c2d06482d997	Ulaşım	#FF5722	2025-05-17 07:37:29.420923+00
bb175104-f66f-4587-9cfe-e217d4ff5b64	aa61c289-a602-479c-8819-c2d06482d997	Altyapı	#2196F3	2025-05-17 07:37:29.420923+00
1cad6a30-ce01-48ff-9be0-fa6dceae77eb	aa61c289-a602-479c-8819-c2d06482d997	Çevre Düzeni	#4CAF50	2025-05-17 07:37:29.420923+00
09a6e9e1-16c1-4812-8806-8d622a2cb58a	aa61c289-a602-479c-8819-c2d06482d997	Gürültü Kirliliği	#9C27B0	2025-05-17 07:37:29.420923+00
\.


--
-- Data for Name: poll_votes; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.poll_votes (id, poll_id, option_id, user_id, created_at) FROM stdin;
\.


--
-- Data for Name: polls; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.polls (id, title, description, start_date, end_date, created_by, is_active, level, city_id, district_id, created_at, updated_at) FROM stdin;
aa61c289-a602-479c-8819-c2d06482d997	Şehrinizde en önemli sorun nedir?	Belediyemizin odaklanması gereken öncelikli sorunlar	2025-05-17 07:37:29.420923+00	\N	\N	t	country	\N	\N	2025-05-17 07:37:29.420923+00	2025-05-17 07:37:29.420923+00
\.


--
-- Data for Name: posts; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.posts (id, user_id, title, description, media_url, is_video, type, city, district, like_count, comment_count, created_at, updated_at, media_urls, is_video_list, category, is_resolved, is_hidden, monthly_featured_count, is_featured, featured_count, status, city_id, district_id, processing_date, processing_official_id, solution_date, solution_official_id, solution_note, evidence_url, rejection_date, rejection_official_id) FROM stdin;
98ae54a0-c4dc-40b8-9d7d-02c0288de130	83190944-98d5-41be-ac3a-178676faf017	Tesjssjs	qba. a a a a a a	\N	f	complaint	Ardahan	Göle	0	0	2025-05-22 15:59:54.19422+00	2025-05-22 15:59:54.194283+00	\N	\N	other	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
7e6bc917-bd22-457f-878a-02eda93c5f82	83190944-98d5-41be-ac3a-178676faf017	izhwihxihwixhwox	bxjabxjbwidbwifbwifhw	\N	f	complaint	Ardahan	Göle	0	0	2025-05-22 17:26:27.043674+00	2025-05-22 17:26:27.043733+00	\N	\N	road	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
46613d25-2635-47a1-9ddc-eed39694edf5	83190944-98d5-41be-ac3a-178676faf017	denemee	sssms s s sns s s s s	\N	f	complaint	Adana	Seyhan	1	0	2025-05-22 13:19:57.920479+00	2025-05-22 13:19:57.920589+00	\N	\N	road	f	f	1	t	1	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
2d0533ea-7ec9-4734-b732-51f56d5e76b1	83190944-98d5-41be-ac3a-178676faf017	hwnw. aana a a a	h1a a a a a a. aa a	\N	f	complaint	Adana	Seyhan	2	24	2025-05-21 00:12:10.796715+00	2025-05-21 00:12:10.796844+00	\N	\N	road	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
42251cba-314f-44fc-85f7-8001e9d988ad	83190944-98d5-41be-ac3a-178676faf017	vvuvugug8	bjbjbjbibi. k k k o	\N	f	thanks	Adana	Seyhan	1	0	2025-05-21 00:01:37.921071+00	2025-05-21 00:01:37.921167+00	\N	\N	cleaning	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
af6c0a43-688b-48f9-90b9-8b2e04408494	83190944-98d5-41be-ac3a-178676faf017	Harikaaaa	aba a a annaannaana a a a	\N	f	complaint	Adana	Seyhan	1	0	2025-05-21 12:53:53.008728+00	2025-05-21 12:53:53.0088+00	\N	\N	other	t	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
f4f07614-d116-4b8d-8af9-070378ed808a	83190944-98d5-41be-ac3a-178676faf017	haeikaa a a a	ababa a. aa a a a a a a a	\N	f	complaint	Adana	Seyhan	1	2	2025-05-22 14:37:01.728933+00	2025-05-22 14:37:01.729007+00	\N	\N	road	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
82ad7704-2910-4e8c-97e8-8ed9f7ca224d	8b52a8cb-cb89-4325-9c62-de454a0476fb	bznzn.      Nja Nan	aba a a a anana a a a ana a	\N	f	complaint	Batman	Merkez	0	2	2025-05-23 22:49:02.581036+00	2025-05-23 22:49:02.581104+00	\N	\N	other	f	f	1	t	1	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
9ce11574-1cd3-4675-ba13-c0c509ac7085	cdc2d279-8171-4aa5-89cb-10f81fed72c3	merhababana a	anana. a aa. aa a a a	\N	f	complaint	Bartın	Kurucaşile	0	1	2025-05-23 22:02:38.299351+00	2025-05-23 22:02:38.299433+00	\N	\N	road	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
b3ff2b41-217e-43dd-80c0-91315c6fc4bb	83190944-98d5-41be-ac3a-178676faf017	Harisksns snsns s s	qba a a a a a a a a a	\N	f	thanks	Batman	Kozluk	1	3	2025-05-22 17:32:00.929836+00	2025-05-22 17:32:00.929981+00	\N	\N	road	f	f	0	f	0	pending	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.profiles (id, username, email, created_at) FROM stdin;
\.


--
-- Data for Name: resolution_votes; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.resolution_votes (id, post_id, user_id, created_at) FROM stdin;
\.


--
-- Data for Name: sponsored_ads; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.sponsored_ads (id, title, content, image_urls, start_date, end_date, link_type, link_url, phone_number, show_after_posts, is_pinned, city, district, city_id, district_id, impressions, clicks, status, created_at, updated_at, ad_display_scope) FROM stdin;
934bf28f-fe0b-42bc-bc25-a06ede922a29	Batman - İl reklamı	Yeşil Yaşam Cafe, organik ve yerel gıdalar sunan, kültürel etkinliklere ev sahipliği yapan yeni nesil bir kafedir. Haftanın her günü 09:00-23:00 arası açığız. İlk ziyaretinizde %10 indirim.	\N	2025-05-22 11:34:51.518799+00	2025-06-22 11:55:22+00	phone	https://yesilyasamcafe.com	+905551234567	1	t	Batman	Kozluk	550e8400-e29b-41d4-a716-446655440072	660e8400-e29b-41d4-a716-446655597170	0	0	active	2025-05-22 11:34:51.518799+00	2025-05-22 14:11:03.556708+00	il
934bf28f-fe0b-42bc-bc25-a06ede922a31	Yeşil Yaşam Cafe - herkes reklamı	Yeşil Yaşam Cafe, organik ve yerel gıdalar sunan, kültürel etkinliklere ev sahipliği yapan yeni nesil bir kafedir. Haftanın her günü 09:00-23:00 arası açığız. İlk ziyaretinizde %10 indirim.	{https://www.brandingturkiye.com/brtr_icerik/uploads/2018/01/%C4%B0yi-Reklam-%C4%B0%C3%A7in-%C3%87ok-Para-Gerekir-Anlay%C4%B1%C5%9F%C4%B1-%E2%80%9COUT%E2%80%9D.jpg,https://www.reklamnoktasi.com.tr/pnl/img/gorsel/6468eb73496f8_gorsel_guncel.png}	2025-05-22 11:34:51.518799+00	2025-05-22 14:23:20+00	phone	https://yesilyasamcafe.com	+905551234567	5	t	Adana	Seyhan	550e8400-e29b-41d4-a716-446655440005	660e8400-e29b-41d4-a716-446655482055	22	2	active	2025-05-22 11:34:51.518799+00	2025-05-22 14:11:03.556708+00	herkes
934bf28f-fe0b-42bc-bc25-a06ede922a27	Yeşil Yaşam Cafe - İlçe Reklamı	Yeşil Yaşam Cafe, organik ve yerel gıdalar sunan, kültürel etkinliklere ev sahipliği yapan yeni nesil bir kafedir. Haftanın her günü 09:00-23:00 arası açığız. İlk ziyaretinizde %10 indirim.	{https://www.brandingturkiye.com/brtr_icerik/uploads/2018/01/%C4%B0yi-Reklam-%C4%B0%C3%A7in-%C3%87ok-Para-Gerekir-Anlay%C4%B1%C5%9F%C4%B1-%E2%80%9COUT%E2%80%9D.jpg,https://www.reklamnoktasi.com.tr/pnl/img/gorsel/6468eb73496f8_gorsel_guncel.png}	2025-05-22 11:34:51.518799+00	2025-06-22 11:55:22+00	url	https://yesilyasamcafe.com	+905551234567	5	t	Adana	Seyhan	550e8400-e29b-41d4-a716-446655440001	660e8400-e29b-41d4-a716-446655440010	0	0	active	2025-05-22 11:34:51.518799+00	2025-05-22 14:11:03.556708+00	ilce
934bf28f-fe0b-42bc-bc25-a06ede922a30	Ardahan Göle- İl ilçe reklamı	Yeşil Yaşam Cafe, organik ve yerel gıdalar sunan, kültürel etkinliklere ev sahipliği yapan yeni nesil bir kafedir. Haftanın her günü 09:00-23:00 arası açığız. İlk ziyaretinizde %10 indirim.	{https://www.brandingturkiye.com/brtr_icerik/uploads/2018/01/%C4%B0yi-Reklam-%C4%B0%C3%A7in-%C3%87ok-Para-Gerekir-Anlay%C4%B1%C5%9F%C4%B1-%E2%80%9COUT%E2%80%9D.jpg,https://www.reklamnoktasi.com.tr/pnl/img/gorsel/6468eb73496f8_gorsel_guncel.png}	2025-05-22 11:34:51.518799+00	2025-06-22 11:55:22+00	phone	https://yesilyasamcafe.com	+905551234567	1	t	Ardahan	Göle	550e8400-e29b-41d4-a716-446655440075	660e8400-e29b-41d4-a716-446655531104	0	0	active	2025-05-22 11:34:51.518799+00	2025-05-22 14:11:03.556708+00	ililce
\.


--
-- Data for Name: trigger_logs; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.trigger_logs (id, trigger_name, log_message, created_at) FROM stdin;
1	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 15:53:29.23242+00
2	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 15:56:41.817271+00
3	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 100.00, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 100.0000000000000000, Normalize edilmiş skor: 10, Güncellenen parti sayısı: 1	2025-05-18 15:57:47.262899+00
4	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 50.00, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 50.0000000000000000, Normalize edilmiş skor: 5.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 15:57:55.46779+00
5	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 15:58:48.32243+00
6	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 15:59:19.779927+00
7	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 16:06:07.385055+00
8	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 16:06:15.355954+00
9	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 16:06:15.573578+00
10	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 16:07:37.667182+00
12	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 16:46:12.48614+00
16	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 50.00, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 50.0000000000000000, Normalize edilmiş skor: 5.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:04:04.096369+00
19	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 50.00, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 50.0000000000000000, Normalize edilmiş skor: 5.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:15:15.250236+00
25	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446656332905, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 17:21:51.930116+00
30	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 50.00, Toplam ilçe çözüm oranı: 85.00, Entity sayısı: 2, Ortalama çözüm oranı: 67.5000000000000000, Normalize edilmiş skor: 6.7500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:25:04.610361+00
31	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 85.00, Toplam ilçe çözüm oranı: 85.00, Entity sayısı: 2, Ortalama çözüm oranı: 85.0000000000000000, Normalize edilmiş skor: 8.5000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:25:04.610361+00
32	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655594167, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 17:25:47.131197+00
33	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 85.00, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 85.0000000000000000, Normalize edilmiş skor: 8.5000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:26:06.094911+00
34	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:26:06.094911+00
35	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:30:11.496453+00
36	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:30:11.496453+00
37	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:32:27.141658+00
38	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655594167, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 17:32:27.141658+00
39	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446656332905, Parti ID bulunamadı, işlem sonlandırıldı.	2025-05-18 17:32:27.141658+00
40	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:05.145954+00
41	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:05.145954+00
42	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:13.159256+00
43	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:13.159256+00
44	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:16.456017+00
45	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:16.456017+00
46	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 1, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 34.48, Entity sayısı: 1, Ortalama çözüm oranı: 34.4800000000000000, Normalize edilmiş skor: 3.4480000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:21.919326+00
47	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 34.48, Toplam ilçe çözüm oranı: 34.48, Entity sayısı: 2, Ortalama çözüm oranı: 34.4800000000000000, Normalize edilmiş skor: 3.4480000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:21.919326+00
48	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 34.48, Toplam ilçe çözüm oranı: 34.48, Entity sayısı: 2, Ortalama çözüm oranı: 34.4800000000000000, Normalize edilmiş skor: 3.4480000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:52.31102+00
49	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 34.48, Toplam ilçe çözüm oranı: 34.48, Entity sayısı: 2, Ortalama çözüm oranı: 34.4800000000000000, Normalize edilmiş skor: 3.4480000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:52.31102+00
50	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 34.48, Toplam ilçe çözüm oranı: 62.50, Entity sayısı: 2, Ortalama çözüm oranı: 48.4900000000000000, Normalize edilmiş skor: 4.8490000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:58.648025+00
51	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 62.50, Toplam ilçe çözüm oranı: 62.50, Entity sayısı: 2, Ortalama çözüm oranı: 62.5000000000000000, Normalize edilmiş skor: 6.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:34:58.648025+00
52	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 62.50, Toplam ilçe çözüm oranı: 68.75, Entity sayısı: 2, Ortalama çözüm oranı: 65.6250000000000000, Normalize edilmiş skor: 6.5625000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:39:14.686879+00
53	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 68.75, Toplam ilçe çözüm oranı: 68.75, Entity sayısı: 2, Ortalama çözüm oranı: 68.7500000000000000, Normalize edilmiş skor: 6.8750000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:39:14.686879+00
54	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 68.75, Toplam ilçe çözüm oranı: 62.50, Entity sayısı: 2, Ortalama çözüm oranı: 65.6250000000000000, Normalize edilmiş skor: 6.5625000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:39:41.718442+00
55	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 62.50, Toplam ilçe çözüm oranı: 62.50, Entity sayısı: 2, Ortalama çözüm oranı: 62.5000000000000000, Normalize edilmiş skor: 6.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:39:41.718442+00
56	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 62.50, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 63.6050000000000000, Normalize edilmiş skor: 6.3605000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:40:24.053698+00
57	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:40:24.053698+00
58	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: DEM Parti, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:41:12.596457+00
59	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:41:12.596457+00
60	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: DEM Parti, Şehir sayısı: 0, İlçe sayısı: 1, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 33.33, Entity sayısı: 1, Ortalama çözüm oranı: 33.3300000000000000, Normalize edilmiş skor: 3.3330000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:41:46.987508+00
61	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 33.33, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 33.3300000000000000, Normalize edilmiş skor: 3.3330000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:41:46.987508+00
62	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:14.502715+00
63	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:14.502715+00
64	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:16.860278+00
65	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:16.860278+00
66	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:19.361016+00
67	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 64.71, Entity sayısı: 2, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:19.361016+00
68	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655593166, Parti: AKP, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 64.71, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 64.7100000000000000, Normalize edilmiş skor: 6.4710000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:21.711048+00
69	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440072, Parti: AKP, Şehir sayısı: 0, İlçe sayısı: 0, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 0, Entity sayısı: 0, Ortalama çözüm oranı: 0, Normalize edilmiş skor: 0.00000000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:42:21.711048+00
70	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: DEM Parti, Şehir sayısı: 0, İlçe sayısı: 1, Toplam şehir çözüm oranı: 0, Toplam ilçe çözüm oranı: 50.00, Entity sayısı: 1, Ortalama çözüm oranı: 50.0000000000000000, Normalize edilmiş skor: 5.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:43:17.056441+00
71	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: Memleket Partisi, Şehir sayısı: 1, İlçe sayısı: 0, Toplam şehir çözüm oranı: 50.00, Toplam ilçe çözüm oranı: 0, Entity sayısı: 1, Ortalama çözüm oranı: 50.0000000000000000, Normalize edilmiş skor: 5.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:43:17.056441+00
72	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 50.00, Toplam ilçe çözüm oranı: 33.33, Entity sayısı: 2, Ortalama çözüm oranı: 41.6650000000000000, Normalize edilmiş skor: 4.1665000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:45:08.211776+00
73	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 33.33, Toplam ilçe çözüm oranı: 33.33, Entity sayısı: 2, Ortalama çözüm oranı: 33.3300000000000000, Normalize edilmiş skor: 3.3330000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:45:08.211776+00
74	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 33.33, Toplam ilçe çözüm oranı: 25.00, Entity sayısı: 2, Ortalama çözüm oranı: 29.1650000000000000, Normalize edilmiş skor: 2.9165000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:45:08.611162+00
75	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 25.00, Toplam ilçe çözüm oranı: 25.00, Entity sayısı: 2, Ortalama çözüm oranı: 25.0000000000000000, Normalize edilmiş skor: 2.5000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:45:08.611162+00
76	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 25.00, Toplam ilçe çözüm oranı: 40.00, Entity sayısı: 2, Ortalama çözüm oranı: 32.5000000000000000, Normalize edilmiş skor: 3.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:48:37.379354+00
77	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 40.00, Toplam ilçe çözüm oranı: 40.00, Entity sayısı: 2, Ortalama çözüm oranı: 40.0000000000000000, Normalize edilmiş skor: 4.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:48:37.379354+00
78	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 40.00, Toplam ilçe çözüm oranı: 25.00, Entity sayısı: 2, Ortalama çözüm oranı: 32.5000000000000000, Normalize edilmiş skor: 3.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:57:02.970771+00
79	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 25.00, Toplam ilçe çözüm oranı: 25.00, Entity sayısı: 2, Ortalama çözüm oranı: 25.0000000000000000, Normalize edilmiş skor: 2.5000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:57:02.970771+00
80	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 25.00, Toplam ilçe çözüm oranı: 20.00, Entity sayısı: 2, Ortalama çözüm oranı: 22.5000000000000000, Normalize edilmiş skor: 2.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:57:03.459872+00
81	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 20.00, Toplam ilçe çözüm oranı: 20.00, Entity sayısı: 2, Ortalama çözüm oranı: 20.0000000000000000, Normalize edilmiş skor: 2.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:57:03.459872+00
82	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 20.00, Toplam ilçe çözüm oranı: 25.00, Entity sayısı: 2, Ortalama çözüm oranı: 22.5000000000000000, Normalize edilmiş skor: 2.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:59:39.375012+00
83	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 25.00, Toplam ilçe çözüm oranı: 25.00, Entity sayısı: 2, Ortalama çözüm oranı: 25.0000000000000000, Normalize edilmiş skor: 2.5000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:59:39.375012+00
84	districts_solution_rate_trigger	Trigger başladı: districts_solution_rate_trigger, Tablo: districts, İlçe ID: 660e8400-e29b-41d4-a716-446655440010, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 25.00, Toplam ilçe çözüm oranı: 40.00, Entity sayısı: 2, Ortalama çözüm oranı: 32.5000000000000000, Normalize edilmiş skor: 3.2500000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:59:39.783506+00
85	cities_solution_rate_trigger	Trigger başladı: cities_solution_rate_trigger, Tablo: cities, Şehir ID: 550e8400-e29b-41d4-a716-446655440001, Parti: CHP, Şehir sayısı: 1, İlçe sayısı: 1, Toplam şehir çözüm oranı: 40.00, Toplam ilçe çözüm oranı: 40.00, Entity sayısı: 2, Ortalama çözüm oranı: 40.0000000000000000, Normalize edilmiş skor: 4.0000000000000000, Güncellenen parti sayısı: 1	2025-05-18 17:59:39.783506+00
\.


--
-- Data for Name: user_badges; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.user_badges (id, user_id, badge_id, current_count, earned_at) FROM stdin;
10	83190944-98d5-41be-ac3a-178676faf017	10	8	2025-05-21 09:53:53.260333+00
11	83190944-98d5-41be-ac3a-178676faf017	11	8	2025-05-22 11:37:02.049805+00
7	83190944-98d5-41be-ac3a-178676faf017	1	6	2025-05-21 08:57:43.38886+00
13	cdc2d279-8171-4aa5-89cb-10f81fed72c3	6	1	2025-05-23 19:02:46.032196+00
8	83190944-98d5-41be-ac3a-178676faf017	6	28	2025-05-21 09:00:51.604656+00
9	83190944-98d5-41be-ac3a-178676faf017	7	28	2025-05-21 09:00:59.955857+00
14	8b52a8cb-cb89-4325-9c62-de454a0476fb	6	1	2025-05-23 19:56:41.42713+00
\.


--
-- Data for Name: user_bans; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.user_bans (id, user_id, banned_by, reason, ban_start, ban_end, content_action, is_active, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: user_devices; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.user_devices (id, user_id, device_token, platform, last_active, created_at, updated_at) FROM stdin;
cf9d851e-67a9-4fd0-aca3-2f215d07062d	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747685525590	TargetPlatform.android	2025-05-19 23:12:05.594439+00	2025-05-19 20:12:05.709089+00	2025-05-19 20:12:05.709089+00
5c88dde1-d713-44ba-b314-96ef7b5a6836	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747685719503	TargetPlatform.android	2025-05-19 23:15:19.504996+00	2025-05-19 20:15:19.646065+00	2025-05-19 20:15:19.646065+00
fb4f01d9-43f4-485b-b540-108ecfa83084	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747688016381	TargetPlatform.android	2025-05-19 23:53:36.383206+00	2025-05-19 20:53:36.555692+00	2025-05-19 20:53:36.555692+00
6fb7414e-f18c-49d3-a043-2f844c85548b	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747689165625	TargetPlatform.android	2025-05-20 00:12:45.627247+00	2025-05-19 21:12:45.791201+00	2025-05-19 21:12:45.791201+00
f4fdaa9d-b314-480f-aa17-5cb3e891c9cc	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747689253966	TargetPlatform.android	2025-05-20 00:14:13.967476+00	2025-05-19 21:14:14.093484+00	2025-05-19 21:14:14.093484+00
ed2c83c2-3cd6-4607-9061-b6e87eb236e2	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747689385230	TargetPlatform.android	2025-05-20 00:16:25.232004+00	2025-05-19 21:16:25.363474+00	2025-05-19 21:16:25.363474+00
4d65e7dd-6c7b-4706-a30a-52f3aaab10ca	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747693913615	TargetPlatform.android	2025-05-20 01:31:53.617856+00	2025-05-19 22:31:53.779072+00	2025-05-19 22:31:53.779072+00
674e6fb1-facf-47c6-9b10-dc7dcad76a3a	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747694526518	TargetPlatform.android	2025-05-20 01:42:06.521008+00	2025-05-19 22:42:06.652799+00	2025-05-19 22:42:06.652799+00
632cb943-c879-475f-8a8a-6e5845e4d607	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747695003355	TargetPlatform.android	2025-05-20 01:50:03.357788+00	2025-05-19 22:50:03.489478+00	2025-05-19 22:50:03.489478+00
b62ba218-136a-46fb-a837-ab14ae1b2185	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747696229287	TargetPlatform.android	2025-05-20 02:10:29.289187+00	2025-05-19 23:10:29.435009+00	2025-05-19 23:10:29.435009+00
ecdb6826-a17a-4f71-9ec8-86eaed4addc3	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747696259250	TargetPlatform.android	2025-05-20 02:10:59.251599+00	2025-05-19 23:10:59.381032+00	2025-05-19 23:10:59.381032+00
e6e6774e-7e4e-4683-a2df-5698f167f041	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747698775612	TargetPlatform.android	2025-05-20 02:52:55.614181+00	2025-05-19 23:52:55.74413+00	2025-05-19 23:52:55.74413+00
256c8344-02b6-4fd1-ac98-d43ab2a7d78b	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747699619138	TargetPlatform.android	2025-05-20 03:06:59.139758+00	2025-05-20 00:06:59.297151+00	2025-05-20 00:06:59.297151+00
ec3a77f9-e1f2-4922-9149-22f784add9ac	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747702488799	TargetPlatform.android	2025-05-20 03:54:48.801142+00	2025-05-20 00:54:48.928229+00	2025-05-20 00:54:48.928229+00
d80e1eda-b9c4-4bac-ab83-cc6d83b3b337	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747702513441	TargetPlatform.android	2025-05-20 03:55:13.443673+00	2025-05-20 00:55:13.569936+00	2025-05-20 00:55:13.569936+00
2579fe8a-97c2-4b56-9095-585c1a0b9130	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747702526262	TargetPlatform.android	2025-05-20 03:55:26.26454+00	2025-05-20 00:55:26.393451+00	2025-05-20 00:55:26.393451+00
c2bf56e7-8d68-4c4a-9b6c-f37f54af880b	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747705051620	TargetPlatform.android	2025-05-20 04:37:31.622458+00	2025-05-20 01:37:31.788578+00	2025-05-20 01:37:31.788578+00
42bb4c23-c625-4dd1-ab5a-faaa7e4a8ea1	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747705143711	TargetPlatform.android	2025-05-20 04:39:03.713017+00	2025-05-20 01:39:03.837843+00	2025-05-20 01:39:03.837843+00
d6c338df-9599-488a-a296-a947e5ed7cde	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747705155359	TargetPlatform.android	2025-05-20 04:39:15.360565+00	2025-05-20 01:39:15.484108+00	2025-05-20 01:39:15.484108+00
7aec2dc9-dfb3-4add-bfd7-fdd9220fb6a0	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747705643040	TargetPlatform.android	2025-05-20 04:47:23.043264+00	2025-05-20 01:47:23.227444+00	2025-05-20 01:47:23.227444+00
21e7d891-83fe-4330-a041-e335e6db0be1	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747716038631	TargetPlatform.android	2025-05-20 07:40:38.633153+00	2025-05-20 04:40:38.779483+00	2025-05-20 04:40:38.779483+00
c8df9e11-123c-4acf-86f6-4d12f62c6436	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747717428162	TargetPlatform.android	2025-05-20 08:03:48.166095+00	2025-05-20 05:03:48.34274+00	2025-05-20 05:03:48.34274+00
ff790c04-f192-4678-874d-9516b9869e69	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747717480637	TargetPlatform.android	2025-05-20 08:04:40.6393+00	2025-05-20 05:04:40.793714+00	2025-05-20 05:04:40.793714+00
da35d5a7-7370-42a3-a648-518d2d15bcc9	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747717602823	TargetPlatform.android	2025-05-20 08:06:42.825552+00	2025-05-20 05:06:43.019965+00	2025-05-20 05:06:43.019965+00
0a3295e1-ce32-4eae-92b4-fa1cd0176002	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747717784808	TargetPlatform.android	2025-05-20 08:09:44.809552+00	2025-05-20 05:09:44.963655+00	2025-05-20 05:09:44.963655+00
90a00c9e-21b8-43f8-a592-6aa67fe00b45	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747717923143	TargetPlatform.android	2025-05-20 08:12:03.145294+00	2025-05-20 05:12:03.331868+00	2025-05-20 05:12:03.331868+00
3dc0491a-3f8c-4049-8913-a4caf1294ff5	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747719150401	TargetPlatform.android	2025-05-20 08:32:30.404152+00	2025-05-20 05:32:30.576565+00	2025-05-20 05:32:30.576565+00
9420a347-3ffa-44bc-ba9a-5d94a00c8d58	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747722509020	TargetPlatform.android	2025-05-20 09:28:29.023613+00	2025-05-20 06:28:29.20102+00	2025-05-20 06:28:29.20102+00
92146b35-42f3-4048-a45d-0394449cb6fc	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747732552409	TargetPlatform.android	2025-05-20 12:15:52.411429+00	2025-05-20 09:15:52.572988+00	2025-05-20 09:15:52.572988+00
37f31150-dcb4-438e-a152-9260eae6abf0	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747732709422	TargetPlatform.android	2025-05-20 12:18:29.424344+00	2025-05-20 09:18:29.607816+00	2025-05-20 09:18:29.607816+00
41f846b3-1ee5-4cbb-b92a-d7e7f769960b	83190944-98d5-41be-ac3a-178676faf017	web-stub-token-1747744665108	TargetPlatform.android	2025-05-20 15:37:45.109805+00	2025-05-20 12:37:45.271796+00	2025-05-20 12:37:45.271796+00
\.


--
-- Data for Name: user_metadata; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.user_metadata (user_id, is_super_admin) FROM stdin;
83190944-98d5-41be-ac3a-178676faf017	t
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: supabase_admin
--

COPY public.users (id, email, username, profile_image_url, city, district, created_at, updated_at, phone_number, role, city_id, district_id, display_name) FROM stdin;
cdc2d279-8171-4aa5-89cb-10f81fed72c3	cerde@gmail.com	muzaffercerde	\N	Batman	Kozluk	2025-05-23 22:02:26.593641+00	2025-05-23 22:03:02.333751+00	\N	user	550e8400-e29b-41d4-a716-446655440072	660e8400-e29b-41d4-a716-446655597170	Muzaffer
83190944-98d5-41be-ac3a-178676faf017	mail@muzaffersanli.com	Bimer Yönetici	https://bimer.onvao.net:8443/storage/v1/object/public/profilresimleri/83190944-98d5-41be-ac3a-178676faf017/83190944-98d5-41be-ac3a-178676faf017-df43ad98-b712-47d4-adbe-5cdeb578cee6.png	Batman	Merkez	2025-05-12 01:04:34.038125+00	2025-05-23 20:15:16.933793+00	\N	admin	\N	\N	Muzaffer
8b52a8cb-cb89-4325-9c62-de454a0476fb	123456@gmail.com	muzaffer	\N	Batman	Merkez	2025-05-23 22:24:00.345742+00	2025-05-23 22:56:54.092686+00	\N	user	550e8400-e29b-41d4-a716-446655440072	660e8400-e29b-41d4-a716-446655593166	Murat
\.


--
-- Name: badge_view_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: supabase_admin
--

SELECT pg_catalog.setval('public.badge_view_history_id_seq', 1, false);


--
-- Name: badges_id_seq; Type: SEQUENCE SET; Schema: public; Owner: supabase_admin
--

SELECT pg_catalog.setval('public.badges_id_seq', 18, true);


--
-- Name: featured_posts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: supabase_admin
--

SELECT pg_catalog.setval('public.featured_posts_id_seq', 31, true);


--
-- Name: officials_id_seq; Type: SEQUENCE SET; Schema: public; Owner: supabase_admin
--

SELECT pg_catalog.setval('public.officials_id_seq', 1, true);


--
-- Name: trigger_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: supabase_admin
--

SELECT pg_catalog.setval('public.trigger_logs_id_seq', 85, true);


--
-- Name: user_badges_id_seq; Type: SEQUENCE SET; Schema: public; Owner: supabase_admin
--

SELECT pg_catalog.setval('public.user_badges_id_seq', 14, true);


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

