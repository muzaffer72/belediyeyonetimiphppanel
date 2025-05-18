-- 1. Öncelikle tüm eski trigger'ları ve fonksiyonları CASCADE ile düşürelim
DROP TRIGGER IF EXISTS posts_insert_trigger ON posts;
DROP TRIGGER IF EXISTS posts_update_trigger ON posts;
DROP TRIGGER IF EXISTS cities_solution_rate_trigger ON cities;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP FUNCTION IF EXISTS update_solution_statistics() CASCADE;
DROP FUNCTION IF EXISTS update_party_scores() CASCADE;

-- 2. Çözüm oranlarını otomatik hesaplayan trigger fonksiyonu
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

-- 3. Posts tablosuna eklemeler için trigger
CREATE TRIGGER posts_insert_trigger
AFTER INSERT ON posts
FOR EACH ROW
EXECUTE FUNCTION update_solution_statistics();

-- 4. Posts tablosunda güncellemeler için trigger
CREATE TRIGGER posts_update_trigger
AFTER UPDATE ON posts
FOR EACH ROW
WHEN (OLD.is_resolved IS DISTINCT FROM NEW.is_resolved 
      OR OLD.type IS DISTINCT FROM NEW.type
      OR OLD.city IS DISTINCT FROM NEW.city
      OR OLD.district IS DISTINCT FROM NEW.district)
EXECUTE FUNCTION update_solution_statistics();

-- 5. Parti puanlarını otomatik hesaplayan trigger fonksiyonu
CREATE OR REPLACE FUNCTION update_party_scores()
RETURNS TRIGGER AS $$
DECLARE
  party_id UUID;
  city_count INT;
  district_count INT;
  total_solution_rate NUMERIC;
  district_solution_rate NUMERIC;
  entity_count INT;
  avg_solution_rate NUMERIC;
  normalized_score NUMERIC;
BEGIN
  -- Değişen kayıt bir şehir veya ilçe olduğunda, ilgili partinin puanını güncelle
  IF TG_TABLE_NAME = 'cities' THEN
    party_id := NEW.political_party_id;
  ELSIF TG_TABLE_NAME = 'districts' THEN
    party_id := NEW.political_party_id;
  END IF;
  
  -- Parti ID'si boş ise işlemi sonlandır
  IF party_id IS NULL THEN
    RETURN NEW;
  END IF;
  
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
  
  -- İlk başta entity_count ve total_solution_rate NULL olabilir, kontrol ediyoruz
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
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 6. Cities tablosu için trigger
CREATE TRIGGER cities_solution_rate_trigger
AFTER UPDATE OF solution_rate ON cities
FOR EACH ROW
WHEN (OLD.solution_rate IS DISTINCT FROM NEW.solution_rate)
EXECUTE FUNCTION update_party_scores();

-- 7. Districts tablosu için trigger
CREATE TRIGGER districts_solution_rate_trigger
AFTER UPDATE OF solution_rate ON districts
FOR EACH ROW
WHEN (OLD.solution_rate IS DISTINCT FROM NEW.solution_rate)
EXECUTE FUNCTION update_party_scores();