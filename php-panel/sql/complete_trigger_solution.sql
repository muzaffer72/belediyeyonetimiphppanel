-- Önce tüm varolan triggerları kaldıralım
DROP TRIGGER IF EXISTS posts_insert_trigger ON posts CASCADE;
DROP TRIGGER IF EXISTS posts_update_trigger ON posts CASCADE;
DROP TRIGGER IF EXISTS posts_delete_trigger ON posts CASCADE;
DROP TRIGGER IF EXISTS cities_solution_rate_trigger ON cities CASCADE;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts CASCADE;

-- Çözüm oranlarını güncelleyen fonksiyonu yeniden oluşturalım (silme işlemleri için de destek eklenmiş olarak)
CREATE OR REPLACE FUNCTION update_solution_statistics()
RETURNS TRIGGER AS $$
DECLARE
  city_name TEXT;
  district_name TEXT;
  city_id UUID;
  district_id UUID;
  total_city_complaints INT;
  solved_city_complaints INT;
  city_thanks_count INT;
  total_district_complaints INT;
  solved_district_complaints INT;
  district_thanks_count INT;
  city_solution_rate NUMERIC(5,2);
  district_solution_rate NUMERIC(5,2);
BEGIN
  -- Temel kontroller ve değişken ayarlamaları
  BEGIN
    -- İşlem türüne göre (INSERT, UPDATE, DELETE) city ve district bilgilerini al
    IF TG_OP = 'DELETE' THEN
      city_name := OLD.city;
      district_name := OLD.district;
    ELSE
      city_name := NEW.city;
      district_name := NEW.district;
    END IF;
    
    -- Eğer city veya type değerleri null ise, işlemi sonlandır
    IF city_name IS NULL THEN
      RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    
    -- Type kontrolü (DELETE işleminde OLD.type, diğerlerinde NEW.type)
    IF (TG_OP = 'DELETE' AND (OLD.type != 'complaint' AND OLD.type != 'thanks')) OR
       (TG_OP != 'DELETE' AND (NEW.type != 'complaint' AND NEW.type != 'thanks')) THEN
      RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;

    -- Şehir ID'sini bul
    SELECT id INTO city_id FROM cities WHERE name = city_name LIMIT 1;
    
    -- Şehir bulunamadıysa işlemi sonlandır
    IF city_id IS NULL THEN
      RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
    END IF;
    
    -- İlçe ID'sini bul (şehir ID'si de kontrol edilerek)
    IF district_name IS NOT NULL THEN
      SELECT d.id INTO district_id 
      FROM districts d 
      WHERE d.name = district_name AND d.city_id = city_id
      LIMIT 1;
    END IF;

    -- Şehir için istatistikleri güncelle
    BEGIN
      -- Şehir için toplam şikayet ve teşekkür sayılarını hesapla
      SELECT 
        COUNT(*) FILTER (WHERE type = 'complaint'),
        COUNT(*) FILTER (WHERE type = 'complaint' AND is_resolved = 'true'),
        COUNT(*) FILTER (WHERE type = 'thanks')
      INTO 
        total_city_complaints, 
        solved_city_complaints, 
        city_thanks_count
      FROM 
        posts
      WHERE 
        city = city_name;
      
      -- NULL değerleri kontrol et
      total_city_complaints := COALESCE(total_city_complaints, 0);
      solved_city_complaints := COALESCE(solved_city_complaints, 0);
      city_thanks_count := COALESCE(city_thanks_count, 0);
      
      -- Çözüm oranını hesapla
      IF (total_city_complaints + city_thanks_count) > 0 THEN
        city_solution_rate := ((solved_city_complaints + city_thanks_count)::NUMERIC / (total_city_complaints + city_thanks_count)::NUMERIC * 100);
      ELSE
        city_solution_rate := 0;
      END IF;
      
      -- Şehir tablosunu güncelle
      UPDATE cities 
      SET 
        total_complaints = total_city_complaints,
        solved_complaints = solved_city_complaints,
        thanks_count = city_thanks_count,
        solution_rate = city_solution_rate,
        solution_last_updated = CURRENT_TIMESTAMP
      WHERE 
        id = city_id;
      
      -- Şehrin parti puanını da güncelle
      PERFORM update_party_score_for_entity('city', city_id);
      
    EXCEPTION WHEN OTHERS THEN
      -- Şehir güncellemesi sırasında bir hata oluşursa, devam et
      RAISE NOTICE 'Şehir istatistikleri güncellenirken hata: %', SQLERRM;
    END;
    
    -- İlçe için istatistikleri güncelle (eğer ilçe ID'si bulunduysa)
    IF district_id IS NOT NULL THEN
      BEGIN
        -- İlçe için toplam şikayet ve teşekkür sayılarını hesapla
        SELECT 
          COUNT(*) FILTER (WHERE type = 'complaint'),
          COUNT(*) FILTER (WHERE type = 'complaint' AND is_resolved = 'true'),
          COUNT(*) FILTER (WHERE type = 'thanks')
        INTO 
          total_district_complaints, 
          solved_district_complaints, 
          district_thanks_count
        FROM 
          posts
        WHERE 
          district = district_name AND city = city_name;
        
        -- NULL değerleri kontrol et
        total_district_complaints := COALESCE(total_district_complaints, 0);
        solved_district_complaints := COALESCE(solved_district_complaints, 0);
        district_thanks_count := COALESCE(district_thanks_count, 0);
        
        -- Çözüm oranını hesapla
        IF (total_district_complaints + district_thanks_count) > 0 THEN
          district_solution_rate := ((solved_district_complaints + district_thanks_count)::NUMERIC / (total_district_complaints + district_thanks_count)::NUMERIC * 100);
        ELSE
          district_solution_rate := 0;
        END IF;
        
        -- İlçe tablosunu güncelle
        UPDATE districts 
        SET 
          total_complaints = total_district_complaints,
          solved_complaints = solved_district_complaints,
          thanks_count = district_thanks_count,
          solution_rate = district_solution_rate,
          solution_last_updated = CURRENT_TIMESTAMP
        WHERE 
          id = district_id;
          
        -- İlçenin parti puanını da güncelle
        PERFORM update_party_score_for_entity('district', district_id);
        
      EXCEPTION WHEN OTHERS THEN
        -- İlçe güncellemesi sırasında bir hata oluşursa, devam et
        RAISE NOTICE 'İlçe istatistikleri güncellenirken hata: %', SQLERRM;
      END;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Herhangi bir hata oluşursa, işlemi başarıyla tamamla
    RAISE NOTICE 'Genel hata: %', SQLERRM;
  END;
  
  -- İşlemi başarıyla tamamla
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$ LANGUAGE plpgsql;

-- Belirli bir entity için parti puanını güncelleyen yardımcı fonksiyon
CREATE OR REPLACE FUNCTION update_party_score_for_entity(entity_type TEXT, entity_id UUID)
RETURNS VOID AS $$
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
$$ LANGUAGE plpgsql;

-- Parti puanlarını hesaplayan ana fonksiyon
CREATE OR REPLACE FUNCTION update_party_scores(party_id UUID DEFAULT NULL)
RETURNS VOID AS $$
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
$$ LANGUAGE plpgsql;

-- Posts tablosuna eklemeler için trigger
CREATE TRIGGER posts_insert_trigger
AFTER INSERT ON posts
FOR EACH ROW
EXECUTE FUNCTION update_solution_statistics();

-- Posts tablosunda güncellemeler için trigger
CREATE TRIGGER posts_update_trigger
AFTER UPDATE ON posts
FOR EACH ROW
WHEN (OLD.is_resolved IS DISTINCT FROM NEW.is_resolved 
      OR OLD.type IS DISTINCT FROM NEW.type
      OR OLD.city IS DISTINCT FROM NEW.city
      OR OLD.district IS DISTINCT FROM NEW.district)
EXECUTE FUNCTION update_solution_statistics();

-- Posts tablosundan silmeler için trigger
CREATE TRIGGER posts_delete_trigger
AFTER DELETE ON posts
FOR EACH ROW
EXECUTE FUNCTION update_solution_statistics();