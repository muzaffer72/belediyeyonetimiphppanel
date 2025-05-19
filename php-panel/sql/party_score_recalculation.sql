-- Bu fonksiyon, tüm partilerin puanlarını dengeli bir şekilde yeniden hesaplar
-- 100'lük sisteme göre puanlama yapar
CREATE OR REPLACE FUNCTION recalculate_all_party_scores() 
RETURNS VOID AS $$
DECLARE
    total_parties INTEGER;
    total_posts INTEGER;
    total_thanks INTEGER;
    total_resolved_complaints INTEGER;
    total_cities INTEGER;
    avg_city_solution_rate NUMERIC;
BEGIN
    -- Toplam parti sayısını al
    SELECT COUNT(*) INTO total_parties FROM political_parties;
    
    -- Toplam gönderi, teşekkür ve çözülmüş şikayet sayılarını al
    SELECT COUNT(*) INTO total_posts FROM posts WHERE type IN ('complaint', 'thanks');
    SELECT COUNT(*) INTO total_thanks FROM posts WHERE type = 'thanks';
    SELECT COUNT(*) INTO total_resolved_complaints FROM posts 
        WHERE type = 'complaint' AND is_resolved = 'true';
    
    -- Toplam şehir sayısı
    SELECT COUNT(*) INTO total_cities FROM cities WHERE political_party_id IS NOT NULL;
    
    -- Ortalama şehir çözüm oranını hesapla
    SELECT AVG(solution_rate) INTO avg_city_solution_rate FROM cities;
    
    -- Eğer hiç gönderi yoksa veya çözüm oranları sıfırsa, puanları eşit dağıt
    IF total_posts = 0 OR (total_thanks = 0 AND total_resolved_complaints = 0) THEN
        UPDATE political_parties SET score = 100 / NULLIF(total_parties, 0);
        RETURN;
    END IF;
    
    -- Her parti için şehirlerin solution_rate ortalamasını hesapla
    -- ve skor olarak belirle (100'lük sistem)
    UPDATE political_parties p
    SET score = COALESCE(
        (SELECT AVG(c.solution_rate) 
         FROM cities c 
         WHERE c.political_party_id = p.id)
    , 0);
    
    -- Eğer tüm partilerin puanı sıfırsa, puanları eşit dağıt
    IF NOT EXISTS (SELECT 1 FROM political_parties WHERE score > 0) THEN
        UPDATE political_parties SET score = 100 / NULLIF(total_parties, 0);
    END IF;
    
    -- Toplam puanların 100'e eşit olmasını sağla (normalizasyon)
    -- Eğer toplam puan 0 değilse ölçeklendirme yap
    IF (SELECT SUM(score) FROM political_parties) > 0 THEN
        UPDATE political_parties
        SET score = (score * 100) / (SELECT SUM(score) FROM political_parties)
        WHERE EXISTS (SELECT 1 FROM political_parties WHERE score > 0);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Çözüm oranlarını ve parti puanlarını yeniden hesaplayan tetikleyici fonksiyon
CREATE OR REPLACE FUNCTION update_solution_rates_and_scores() 
RETURNS TRIGGER AS $$
BEGIN
    -- Şehirlerin çözüm oranlarını ilçelere göre güncelle
    UPDATE cities c
    SET solution_rate = (
        SELECT AVG(d.solution_rate)
        FROM districts d
        WHERE d.city_id = c.id
    );
    
    -- İlçe çözüm oranlarını hesapla
    UPDATE districts d
    SET solution_rate = (
        WITH district_stats AS (
            SELECT 
                district_id,
                COUNT(*) FILTER (WHERE type = 'complaint') AS total_complaints,
                COUNT(*) FILTER (WHERE type = 'complaint' AND is_resolved = 'true') AS resolved_complaints,
                COUNT(*) FILTER (WHERE type = 'thanks') AS thanks_count
            FROM posts
            WHERE district_id IS NOT NULL
            GROUP BY district_id
        )
        SELECT 
            CASE 
                WHEN (ds.total_complaints + ds.thanks_count) > 0 
                THEN ((ds.resolved_complaints + ds.thanks_count) * 100.0 / (ds.total_complaints + ds.thanks_count))
                ELSE 0
            END
        FROM district_stats ds
        WHERE ds.district_id = d.id
    );
    
    -- Tüm parti puanlarını yeniden hesapla
    PERFORM recalculate_all_party_scores();
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Bu trigger'ı ilgili tablolardaki değişikliklerde çalıştır
DROP TRIGGER IF EXISTS posts_update_solution_rates_trigger ON posts;
CREATE TRIGGER posts_update_solution_rates_trigger
AFTER INSERT OR UPDATE OR DELETE ON posts
FOR EACH ROW
EXECUTE FUNCTION update_solution_rates_and_scores();

-- Mevcut çözüm oranlarını hesaplamak için bu fonksiyonu bir kez çalıştırın
SELECT recalculate_all_party_scores();