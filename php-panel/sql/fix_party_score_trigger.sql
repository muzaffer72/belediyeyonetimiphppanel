-- Supabase'de SQL Editör sayfasında çalıştırın

-- Öncelikle mevcut triggerları temizleyelim
DROP TRIGGER IF EXISTS cities_solution_rate_trigger ON cities;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP FUNCTION IF EXISTS update_party_scores() CASCADE;

-- Debugging için bir log tablosu oluşturalım
CREATE TABLE IF NOT EXISTS trigger_logs (
    id SERIAL PRIMARY KEY,
    trigger_name TEXT,
    log_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Parti puanlarını hesaplayan fonksiyon (debug bilgileri ile)
CREATE OR REPLACE FUNCTION update_party_scores()
RETURNS TRIGGER AS $$
DECLARE
  party_id UUID;
  party_name TEXT;
  city_count INT;
  district_count INT;
  total_solution_rate NUMERIC;
  district_solution_rate NUMERIC;
  entity_count INT;
  avg_solution_rate NUMERIC;
  normalized_score NUMERIC;
  log_message TEXT;
BEGIN
  -- Debug mesajı başlat
  log_message := 'Trigger başladı: ' || TG_NAME || ', Tablo: ' || TG_TABLE_NAME;
  
  -- Hangi entity değişti?
  IF TG_TABLE_NAME = 'cities' THEN
    party_id := NEW.political_party_id;
    log_message := log_message || ', Şehir ID: ' || NEW.id;
  ELSIF TG_TABLE_NAME = 'districts' THEN
    party_id := NEW.political_party_id;
    log_message := log_message || ', İlçe ID: ' || NEW.id;
  END IF;
  
  -- Parti ID'si boş ise işlemi sonlandır
  IF party_id IS NULL THEN
    log_message := log_message || ', Parti ID bulunamadı, işlem sonlandırıldı.';
    INSERT INTO trigger_logs (trigger_name, log_message) VALUES (TG_NAME, log_message);
    RETURN NEW;
  END IF;
  
  -- Parti adını al
  SELECT name INTO party_name FROM political_parties WHERE id = party_id;
  log_message := log_message || ', Parti: ' || COALESCE(party_name, 'Bilinmiyor');
  
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
  
  -- Debug bilgisi
  log_message := log_message || ', Şehir sayısı: ' || city_count || 
                ', İlçe sayısı: ' || district_count ||
                ', Toplam şehir çözüm oranı: ' || total_solution_rate ||
                ', Toplam ilçe çözüm oranı: ' || district_solution_rate;
  
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
  
  -- Debug bilgisi
  log_message := log_message || ', Entity sayısı: ' || entity_count ||
                ', Ortalama çözüm oranı: ' || avg_solution_rate ||
                ', Normalize edilmiş skor: ' || normalized_score;
                
  -- Parti puanını güncelle
  UPDATE political_parties
  SET 
    score = normalized_score,
    last_updated = CURRENT_TIMESTAMP
  WHERE 
    id = party_id;
    
  -- İşlem sonucu
  GET DIAGNOSTICS city_count = ROW_COUNT;
  log_message := log_message || ', Güncellenen parti sayısı: ' || city_count;
  
  -- Log kaydı
  INSERT INTO trigger_logs (trigger_name, log_message) VALUES (TG_NAME, log_message);
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Hata durumunda log
  log_message := log_message || ', HATA: ' || SQLERRM;
  INSERT INTO trigger_logs (trigger_name, log_message) VALUES (TG_NAME, log_message);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Cities tablosu için trigger (herhangi bir değişiklik durumunda)
CREATE TRIGGER cities_solution_rate_trigger
AFTER UPDATE ON cities
FOR EACH ROW
WHEN (OLD.solution_rate IS DISTINCT FROM NEW.solution_rate OR
      OLD.total_complaints IS DISTINCT FROM NEW.total_complaints OR
      OLD.solved_complaints IS DISTINCT FROM NEW.solved_complaints OR
      OLD.thanks_count IS DISTINCT FROM NEW.thanks_count)
EXECUTE FUNCTION update_party_scores();

-- Districts tablosu için trigger (herhangi bir değişiklik durumunda)
CREATE TRIGGER districts_solution_rate_trigger
AFTER UPDATE ON districts
FOR EACH ROW
WHEN (OLD.solution_rate IS DISTINCT FROM NEW.solution_rate OR
      OLD.total_complaints IS DISTINCT FROM NEW.total_complaints OR
      OLD.solved_complaints IS DISTINCT FROM NEW.solved_complaints OR
      OLD.thanks_count IS DISTINCT FROM NEW.thanks_count)
EXECUTE FUNCTION update_party_scores();

-- Trigger'ların kurulumunu kontrol et
SELECT 
  trigger_name, 
  event_manipulation, 
  event_object_table, 
  action_statement
FROM 
  information_schema.triggers
WHERE 
  event_object_table IN ('cities', 'districts')
ORDER BY 
  trigger_name;