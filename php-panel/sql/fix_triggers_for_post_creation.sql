-- Önce varolan triggerları kaldıralım
DROP TRIGGER IF EXISTS posts_insert_trigger ON posts CASCADE;
DROP TRIGGER IF EXISTS posts_update_trigger ON posts CASCADE;

-- Çözüm oranı hesaplama fonksiyonunu güncelleyelim (daha fazla hata kontrolü ile)
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
  -- Temel kontroller
  BEGIN
    -- Yeni veya güncellenen post'un şehir ve ilçe bilgilerini al
    city_name := NEW.city;
    district_name := NEW.district;
    
    -- Eğer city veya type değerleri null ise, işlemi sonlandır
    IF city_name IS NULL OR NEW.type IS NULL THEN
      RETURN NEW;
    END IF;
    
    -- Eğer şikayet veya teşekkür değilse işlemi sonlandır
    IF NEW.type != 'complaint' AND NEW.type != 'thanks' THEN
      RETURN NEW;
    END IF;

    -- Şehir ID'sini bul
    SELECT id INTO city_id FROM cities WHERE name = city_name LIMIT 1;
    
    -- Şehir bulunamadıysa işlemi sonlandır
    IF city_id IS NULL THEN
      RETURN NEW;
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
    EXCEPTION WHEN OTHERS THEN
      -- Şehir güncellemesi sırasında bir hata oluşursa, devam et
      NULL;
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
      EXCEPTION WHEN OTHERS THEN
        -- İlçe güncellemesi sırasında bir hata oluşursa, devam et
        NULL;
      END;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Herhangi bir hata oluşursa, işlemi başarıyla tamamla
    NULL;
  END;
  
  -- İşlemi başarıyla tamamla
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Posts tablosuna eklemeler için yeni trigger (hata durumunda devam edecek şekilde)
CREATE TRIGGER posts_insert_trigger
AFTER INSERT ON posts
FOR EACH ROW
EXECUTE FUNCTION update_solution_statistics();

-- Posts tablosunda güncellemeler için yeni trigger (hata durumunda devam edecek şekilde)
CREATE TRIGGER posts_update_trigger
AFTER UPDATE ON posts
FOR EACH ROW
WHEN (OLD.is_resolved IS DISTINCT FROM NEW.is_resolved 
      OR OLD.type IS DISTINCT FROM NEW.type
      OR OLD.city IS DISTINCT FROM NEW.city
      OR OLD.district IS DISTINCT FROM NEW.district)
EXECUTE FUNCTION update_solution_statistics();