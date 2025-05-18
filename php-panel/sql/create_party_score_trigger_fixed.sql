-- Önce eski fonksiyonu düşürelim (eğer varsa)
DROP FUNCTION IF EXISTS update_party_scores();

-- Parti puanlarını otomatik hesaplayan trigger fonksiyonu
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

-- Mevcut trigger'ları düşürelim (eğer varsa)
DROP TRIGGER IF EXISTS cities_solution_rate_trigger ON cities;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;

-- Cities tablosu için trigger
CREATE TRIGGER cities_solution_rate_trigger
AFTER UPDATE OF solution_rate ON cities
FOR EACH ROW
WHEN (OLD.solution_rate IS DISTINCT FROM NEW.solution_rate)
EXECUTE FUNCTION update_party_scores();

-- Districts tablosu için trigger
CREATE TRIGGER districts_solution_rate_trigger
AFTER UPDATE OF solution_rate ON districts
FOR EACH ROW
WHEN (OLD.solution_rate IS DISTINCT FROM NEW.solution_rate)
EXECUTE FUNCTION update_party_scores();