-- Mevcut tüm triggerları devre dışı bırak
DROP TRIGGER IF EXISTS posts_solution_rate_trigger ON posts;
DROP TRIGGER IF EXISTS districts_solution_rate_trigger ON districts;
DROP TRIGGER IF EXISTS cities_party_score_trigger ON cities;
DROP TRIGGER IF EXISTS posts_party_score_trigger ON posts;

-- Trigger fonksiyonlarını da kaldır (isteğe bağlı)
DROP FUNCTION IF EXISTS calculate_solution_rate_percentage();
DROP FUNCTION IF EXISTS update_solution_rates_and_scores();
DROP FUNCTION IF EXISTS recalculate_all_party_scores();
DROP FUNCTION IF EXISTS update_party_scores();