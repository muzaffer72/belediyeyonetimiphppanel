-- Önce eski fonksiyonu düşürelim (eğer varsa)
DROP FUNCTION IF EXISTS update_solution_statistics();

-- Çözüm oranlarını otomatik hesaplayan trigger fonksiyonu
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
  -- Yeni veya güncellenen post'un şehir ve ilçe bilgilerini al
  city_name := NEW.city;
  district_name := NEW.district;
  
  -- Eğer şikayet veya teşekkür değilse işlemi sonlandır
  IF NEW.type != 'complaint' AND NEW.type != 'thanks' THEN
    RETURN NEW;
  END IF;

  -- Şehir ID'sini bul
  SELECT id INTO city_id FROM cities WHERE name = city_name LIMIT 1;
  
  -- İlçe ID'sini bul (şehir ID'si de kontrol edilerek)
  IF district_name IS NOT NULL AND city_id IS NOT NULL THEN
    SELECT d.id INTO district_id 
    FROM districts d 
    WHERE d.name = district_name AND d.city_id = city_id
    LIMIT 1;
  END IF;

  -- Şehir için istatistikleri güncelle
  IF city_id IS NOT NULL THEN
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
  END IF;
  
  -- İlçe için istatistikleri güncelle
  IF district_id IS NOT NULL THEN
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
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Mevcut trigger'ları düşürelim (eğer varsa)
DROP TRIGGER IF EXISTS posts_insert_trigger ON posts;
DROP TRIGGER IF EXISTS posts_update_trigger ON posts;

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