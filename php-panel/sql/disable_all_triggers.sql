-- Tüm triggerları tamamen kaldıran SQL kodu

-- 1. ADIM: Tüm mevcut triggerları kaldır
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;
DROP TRIGGER IF EXISTS update_solution_rates_and_scores ON posts;
DROP TRIGGER IF EXISTS posts_update_solution_rates_trigger ON posts;
DROP TRIGGER IF EXISTS posts_update_stats_trigger ON posts;
DROP TRIGGER IF EXISTS update_party_scores_cities_trigger ON cities;
DROP TRIGGER IF EXISTS update_party_scores_districts_trigger ON districts;
DROP TRIGGER IF EXISTS update_party_scores_posts_trigger ON posts;

-- 2. ADIM: Tüm eski trigger fonksiyonlarını kaldır
DROP FUNCTION IF EXISTS calculate_solution_rate_percentage() CASCADE;
DROP FUNCTION IF EXISTS update_solution_rates_and_scores() CASCADE;
DROP FUNCTION IF EXISTS recalculate_all_party_scores() CASCADE;
DROP FUNCTION IF EXISTS update_party_scores() CASCADE;
DROP FUNCTION IF EXISTS update_post_stats() CASCADE;

-- 3. ADIM: Sadece cron işlemi için bir fonksiyon oluştur
CREATE OR REPLACE FUNCTION cron_update_party_scores()
RETURNS void AS $$
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
    SET score = ps.final_score
    FROM party_scores ps
    WHERE pp.id = ps.id;
END;
$$ LANGUAGE plpgsql;

-- 4. ADIM: Cron işlemi ayarla
SELECT cron.schedule(
  'update-party-scores-daily',
  '0 0 * * *',  -- Her gün gece yarısı
  $$SELECT cron_update_party_scores()$$
);

-- İşlem başarılı mesajı
SELECT 'Triggerlar kaldırılıp cron işlemi ayarlandı. Gönderi paylaşımı artık sorunsuz çalışacak.' AS message;