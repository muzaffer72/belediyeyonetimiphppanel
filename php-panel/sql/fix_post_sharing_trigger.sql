-- Bu SQL kodu, gönderi paylaşımını engelleyen triggerları kaldırır ve
-- daha basit, gönderi paylaşımını engellemeyecek triggerlar ekler

-- 1. ADIM: Mevcut tüm sorunlu triggerları kaldır
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;
DROP TRIGGER IF EXISTS update_solution_rates_and_scores ON posts;
DROP TRIGGER IF EXISTS posts_update_solution_rates_trigger ON posts;

-- Eski fonksiyonları da kaldır
DROP FUNCTION IF EXISTS calculate_solution_rate_percentage() CASCADE;
DROP FUNCTION IF EXISTS update_solution_rates_and_scores() CASCADE;
DROP FUNCTION IF EXISTS recalculate_all_party_scores() CASCADE;
DROP FUNCTION IF EXISTS update_party_scores() CASCADE;

-- 2. ADIM: Basit bir solution rate güncelleme fonksiyonu oluştur
-- Bu fonksiyon sadece post insert/update/delete sonrası ilgili district ve city için solution_rate güncelleyecek
CREATE OR REPLACE FUNCTION update_post_stats()
RETURNS TRIGGER AS $$
DECLARE
    affected_district_id INTEGER;
    affected_city_id INTEGER;
BEGIN
    -- Etkilenen district ve city ID'lerini belirle
    IF TG_OP = 'DELETE' THEN
        affected_district_id := OLD.district_id;
        
        -- City ID'yi district tablosundan al
        SELECT city_id INTO affected_city_id 
        FROM districts 
        WHERE id = affected_district_id;
    ELSE
        affected_district_id := NEW.district_id;
        
        -- City ID'yi district tablosundan al
        SELECT city_id INTO affected_city_id 
        FROM districts 
        WHERE id = affected_district_id;
    END IF;
    
    -- Sadece etkilenen district için istatistikleri güncelle
    IF affected_district_id IS NOT NULL THEN
        -- İlçe için toplam/çözülmüş şikayet sayılarını güncelle
        UPDATE districts 
        SET 
            total_complaints = (
                SELECT COUNT(*) 
                FROM posts 
                WHERE district_id = affected_district_id
            ),
            solved_complaints = (
                SELECT COUNT(*) 
                FROM posts 
                WHERE district_id = affected_district_id AND is_resolved = true
            ),
            solution_rate = (
                CASE 
                    WHEN COUNT(*) = 0 THEN 0
                    ELSE (
                        SELECT 
                            (COUNT(CASE WHEN is_resolved = true THEN 1 END) + COALESCE(thanks_count, 0)) * 100.0 / 
                            (COUNT(*) + COALESCE(thanks_count, 0))
                        FROM posts 
                        WHERE district_id = affected_district_id
                    )
                END
            )
        WHERE id = affected_district_id;
    END IF;
    
    -- Sadece etkilenen city için istatistikleri güncelle
    IF affected_city_id IS NOT NULL THEN
        -- Şehir için çözüm oranını güncelle - ilçe ortalamalarını kullanarak
        UPDATE cities c
        SET solution_rate = (
            SELECT 
                CASE 
                    WHEN COUNT(*) = 0 THEN 0
                    ELSE AVG(COALESCE(d.solution_rate, 0))
                END
            FROM districts d 
            WHERE d.city_id = affected_city_id
        )
        WHERE c.id = affected_city_id;
    END IF;
    
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 3. ADIM: Post değişikliklerinde çalışacak yeni trigger oluştur
-- Bu trigger gönderi paylaşımını engellemeyecek kadar basit/hafif
DROP TRIGGER IF EXISTS posts_update_stats_trigger ON posts;
CREATE TRIGGER posts_update_stats_trigger
AFTER INSERT OR UPDATE OR DELETE ON posts
FOR EACH ROW
EXECUTE FUNCTION update_post_stats();

-- İşlem başarılı mesajı
SELECT 'Gönderi paylaşımı için triggerlar başarıyla güncellendi' AS message;