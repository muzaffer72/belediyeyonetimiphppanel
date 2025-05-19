-- Parti puanlarını hesaplayan basit ve doğrudan bir trigger
-- İlçe ve şehir hesaplamaları mevcut kodları korur, sadece parti puanlaması yeniden düzenlenir

-- Trigger fonksiyonu - olabildiğince basit tutuldu
CREATE OR REPLACE FUNCTION update_party_scores() 
RETURNS TRIGGER AS $$
BEGIN
    -- Tüm parti puanlarını hesapla
    -- Her partideki çözülmüş şikayet ve teşekkür oranlarına göre 100 üzerinden puanlama yapar
    
    WITH party_stats AS (
        -- Her parti için toplam şikayet, çözülmüş şikayet ve teşekkür sayılarını hesapla
        SELECT 
            pp.id AS party_id,
            COALESCE(SUM(CASE WHEN p.type = 'complaint' THEN 1 ELSE 0 END), 0) AS total_complaints,
            COALESCE(SUM(CASE WHEN p.type = 'complaint' AND p.is_resolved = 'true' THEN 1 ELSE 0 END), 0) AS resolved_complaints,
            COALESCE(SUM(CASE WHEN p.type = 'thanks' THEN 1 ELSE 0 END), 0) AS thanks_count
        FROM 
            political_parties pp
            LEFT JOIN cities c ON pp.id = c.political_party_id
            LEFT JOIN districts d ON c.id = d.city_id
            LEFT JOIN posts p ON d.id = p.district_id
        GROUP BY 
            pp.id
    ),
    -- Çözüm oranlarını hesapla ve toplam puanı bul
    party_scores AS (
        SELECT 
            party_id,
            CASE 
                WHEN (total_complaints + thanks_count) > 0 
                THEN ((resolved_complaints + thanks_count) * 100.0 / (total_complaints + thanks_count))
                ELSE 0
            END AS raw_score
        FROM 
            party_stats
    ),
    -- Toplam skorları hesapla (normalize etmek için)
    totals AS (
        SELECT NULLIF(SUM(raw_score), 0) AS total_score FROM party_scores
    )
    -- Parti puanlarını güncelle
    UPDATE political_parties pp
    SET score = 
        CASE 
            -- Toplam puan 0 değilse normalize et
            WHEN (SELECT total_score FROM totals) > 0 
            THEN (
                SELECT (ps.raw_score * 100) / t.total_score
                FROM party_scores ps, totals t
                WHERE ps.party_id = pp.id
            )
            -- Tüm partilere eşit puan dağıt
            ELSE (
                SELECT 100.0 / COUNT(*) 
                FROM political_parties
            )
        END;
            
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Tetikleyiciyi oluştur
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;
CREATE TRIGGER posts_party_score_trigger
AFTER INSERT OR UPDATE OR DELETE ON posts
FOR EACH STATEMENT
EXECUTE FUNCTION update_party_scores();