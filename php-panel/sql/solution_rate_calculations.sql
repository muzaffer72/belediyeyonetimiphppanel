-- Çözüm oranı hesaplama fonksiyonu (100'lük sisteme göre)
CREATE OR REPLACE FUNCTION calculate_solution_rate_percentage() 
RETURNS TRIGGER AS $$
DECLARE
    district_id_var TEXT;
    city_id_var TEXT;
    total_complaints INTEGER;
    resolved_complaints INTEGER;
    thanks_count INTEGER;
    total_posts INTEGER;
    solution_rate NUMERIC;
BEGIN
    -- Eğer posts tablosunda bir değişiklik varsa
    IF TG_TABLE_NAME = 'posts' THEN
        -- İlçe ve şehir ID'lerini al
        district_id_var := NEW.district_id;
        IF district_id_var IS NOT NULL THEN
            -- İlçe çözüm oranını hesapla
            -- Toplam şikayet sayısı
            SELECT COUNT(*) INTO total_complaints 
            FROM posts 
            WHERE district_id = district_id_var AND type = 'complaint';
            
            -- Çözülmüş şikayet sayısı
            SELECT COUNT(*) INTO resolved_complaints 
            FROM posts 
            WHERE district_id = district_id_var AND type = 'complaint' AND is_resolved = 'true';
            
            -- Teşekkür sayısı
            SELECT COUNT(*) INTO thanks_count 
            FROM posts 
            WHERE district_id = district_id_var AND type = 'thanks';
            
            -- Toplam gönderi sayısı (şikayet + teşekkür)
            total_posts := total_complaints + thanks_count;
            
            -- Çözüm oranını hesapla (yüzde olarak)
            -- Formül: (Çözülen Şikayetler + Teşekkürler) / (Toplam Şikayetler + Teşekkürler) * 100
            IF total_posts > 0 THEN
                solution_rate := ((resolved_complaints + thanks_count)::NUMERIC / total_posts) * 100;
            ELSE
                solution_rate := 0;
            END IF;
            
            -- İlçe çözüm oranını güncelle
            UPDATE districts
            SET solution_rate = solution_rate
            WHERE id = district_id_var;
            
            -- İlçenin bağlı olduğu şehri bul ve bu şehrin çözüm oranını güncelle
            SELECT city_id INTO city_id_var
            FROM districts
            WHERE id = district_id_var;
            
            IF city_id_var IS NOT NULL THEN
                -- Şehir çözüm oranını, bağlı ilçelerin çözüm oranlarının ortalaması olarak güncelle
                UPDATE cities
                SET solution_rate = (
                    SELECT AVG(solution_rate)
                    FROM districts
                    WHERE city_id = city_id_var
                )
                WHERE id = city_id_var;
                
                -- Şehrin bağlı olduğu partinin skorunu güncelle
                -- Politikayı değiştirdim: Tüm partilerin puanlarını her değişiklikte yeniden hesapla
                -- Böylece oranlar her zaman güncel kalır
                UPDATE political_parties
                SET score = (
                    -- Tüm political_parties için puanları yeniden hesapla
                    -- Bir partinin tüm şehirlerindeki çözüm oranlarının ortalaması
                    SELECT COALESCE(AVG(c.solution_rate), 0)
                    FROM cities c
                    WHERE c.political_party_id = political_parties.id
                );
                
                -- Eğer hiç teşekkür/şikayet yoksa veya çözüm oranları sıfırsa, parti puanları eşit dağıtılsın
                -- Bu hem partiler arasında hem de sıfırdan başlayınca eşitliği sağlar
                DECLARE
                    total_parties INTEGER;
                    active_parties INTEGER;
                    any_activity BOOLEAN;
                BEGIN
                    -- Aktif partileri say (en az bir şehri olan)
                    SELECT COUNT(*) INTO total_parties FROM political_parties;
                    SELECT COUNT(DISTINCT political_party_id) INTO active_parties 
                    FROM cities 
                    WHERE political_party_id IS NOT NULL;
                    
                    -- Herhangi bir aktivite var mı kontrol et (çözülen şikayet veya teşekkür)
                    SELECT EXISTS(
                        SELECT 1 FROM posts WHERE type = 'thanks' OR (type = 'complaint' AND is_resolved = 'true')
                    ) INTO any_activity;
                    
                    -- Aktif parti yoksa veya henüz hiç aktivite yoksa, puanları eşitle
                    IF active_parties = 0 OR NOT any_activity THEN
                        UPDATE political_parties
                        SET score = 100 / NULLIF(total_parties, 0);
                    END IF;
                END;
            END IF;
        END IF;
    END IF;
    
    -- Eğer districts tablosunda bir değişiklik varsa direkt bağlı olduğu şehrin çözüm oranını güncelle
    IF TG_TABLE_NAME = 'districts' AND (TG_OP = 'UPDATE' OR TG_OP = 'INSERT') THEN
        city_id_var := NEW.city_id;
        
        IF city_id_var IS NOT NULL THEN
            -- Şehir çözüm oranını, bağlı ilçelerin çözüm oranlarının ortalaması olarak güncelle
            UPDATE cities
            SET solution_rate = (
                SELECT AVG(solution_rate)
                FROM districts
                WHERE city_id = city_id_var
            )
            WHERE id = city_id_var;
            
            -- Şehrin bağlı olduğu partinin skorunu güncelle
            UPDATE political_parties
            SET score = (
                SELECT AVG(c.solution_rate)
                FROM cities c
                WHERE c.political_party_id = political_parties.id
            )
            WHERE id IN (
                SELECT political_party_id
                FROM cities
                WHERE id = city_id_var
                AND political_party_id IS NOT NULL
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bu trigger'ı posts tablosundaki değişikliklerde çalıştır
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
CREATE TRIGGER posts_solution_rate_trigger
AFTER INSERT OR UPDATE OR DELETE ON posts
FOR EACH ROW
EXECUTE FUNCTION calculate_solution_rate_percentage();

-- Bu trigger'ı districts tablosundaki değişikliklerde çalıştır
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
CREATE TRIGGER districts_solution_rate_trigger
AFTER INSERT OR UPDATE ON districts
FOR EACH ROW
EXECUTE FUNCTION calculate_solution_rate_percentage();

-- Bu trigger'ı cities tablosundaki değişikliklerde çalıştır
-- Özellikle political_party_id değişikliklerinde parti skorunu güncellemek için
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
CREATE TRIGGER cities_party_score_trigger
AFTER UPDATE OF political_party_id ON cities
FOR EACH ROW
WHEN (OLD.political_party_id IS DISTINCT FROM NEW.political_party_id)
EXECUTE FUNCTION calculate_solution_rate_percentage();