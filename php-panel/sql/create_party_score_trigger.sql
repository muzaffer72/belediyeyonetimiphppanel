-- Parti Puanlama Sistemi için Trigger Fonksiyonu 
-- Bu fonksiyon, şehir, ilçe veya postlardaki değişikliklerde çalışacak
-- ve parti puanlarını otomatik olarak güncelleyecektir

-- Önce Fonksiyonu Oluştur
CREATE OR REPLACE FUNCTION update_party_scores()
RETURNS TRIGGER AS $$
BEGIN
    -- 1. Adım: political_parties tablosuna sütunları ekle (eğer yoksa)
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

    -- 2. Adım: Tüm partilerin istatistiklerini sıfırla
    UPDATE political_parties
    SET 
        parti_sikayet_sayisi = 0,
        parti_cozulmus_sikayet_sayisi = 0,
        parti_tesekkur_sayisi = 0,
        score = 0;

    -- 3. Adım: Şehir ve ilçelerden toplamları hesapla
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
    -- Büyükşehir olan şehirlerden toplanan istatistikler
    city_party_stats AS (
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
    -- Büyükşehir olmayan şehirlerin istatistikleri
    normal_city_party_stats AS (
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
    -- Büyükşehirlerdeki ilçe istatistikleri
    district_party_stats AS (
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
    -- Normal ilçe istatistikleri
    normal_district_party_stats AS (
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
    -- Tüm istatistikleri birleştir
    combined_stats AS (
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
            -- Normal şehir istatistikleri
            COALESCE(ncps.total_normal_city_complaints, 0) AS normal_city_complaints,
            COALESCE(ncps.total_normal_city_solved_complaints, 0) AS normal_city_solved_complaints,
            COALESCE(ncps.total_normal_city_thanks, 0) AS normal_city_thanks,
            -- Normal ilçe istatistikleri
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
    
    -- 4. Adım: Parti istatistiklerini güncelle
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

    -- 5. Adım: Puanları hesapla
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
    
    -- 6. Adım: Puanları güncelle
    UPDATE political_parties pp
    SET score = ps.final_score
    FROM party_scores ps
    WHERE pp.id = ps.id;

    RETURN NULL; -- Trigger fonksiyonu olduğu için NULL döndür
END;
$$ LANGUAGE plpgsql;

-- Trigger'ları oluştur
-- 1. Şehir tablosu değiştiğinde çalışacak trigger
DROP TRIGGER IF EXISTS update_party_scores_cities_trigger ON cities;
CREATE TRIGGER update_party_scores_cities_trigger
AFTER INSERT OR UPDATE OR DELETE ON cities
FOR EACH STATEMENT
EXECUTE FUNCTION update_party_scores();

-- 2. İlçe tablosu değiştiğinde çalışacak trigger
DROP TRIGGER IF EXISTS update_party_scores_districts_trigger ON districts;
CREATE TRIGGER update_party_scores_districts_trigger
AFTER INSERT OR UPDATE OR DELETE ON districts
FOR EACH STATEMENT
EXECUTE FUNCTION update_party_scores();

-- 3. Post tablosu değiştiğinde çalışacak trigger
DROP TRIGGER IF EXISTS update_party_scores_posts_trigger ON posts;
CREATE TRIGGER update_party_scores_posts_trigger
AFTER INSERT OR UPDATE OR DELETE ON posts
FOR EACH STATEMENT
EXECUTE FUNCTION update_party_scores();

-- 4. Alternatif: Supabase cron uygulaması için fonksiyon
-- Bu fonksiyonu Supabase cron ile çağırabilirsiniz (örneğin günde bir kez)
CREATE OR REPLACE FUNCTION cron_update_party_scores()
RETURNS void AS $$
BEGIN
    PERFORM update_party_scores(); -- Mevcut fonksiyonu çağır
END;
$$ LANGUAGE plpgsql;