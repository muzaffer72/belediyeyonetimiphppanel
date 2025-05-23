<?php
// Common utility functions for the admin panel

/**
 * Sanitize input data
 * @param string $data The data to sanitize
 * @return string Sanitized data
 */
function sanitize($data) {
    $data = trim($data);
    $data = stripslashes($data);
    $data = htmlspecialchars($data);
    return $data;
}

/**
 * Format a date in Turkish format
 * @param string $dateString The date string to format
 * @param bool $includeTime Whether to include time in the output
 * @return string Formatted date
 */
function formatDate($dateString, $includeTime = false) {
    if (empty($dateString)) return '';
    
    $date = new DateTime($dateString);
    if ($includeTime) {
        return $date->format('d.m.Y H:i');
    } else {
        return $date->format('d.m.Y');
    }
}

/**
 * Get all cities from database
 * @param bool $onlyMetropolitan Whether to return only metropolitan cities
 * @return array Array of cities
 */
function getCities($onlyMetropolitan = false) {
    global $pdo;
    
    try {
        $query = "SELECT * FROM cities";
        
        if ($onlyMetropolitan) {
            $query .= " WHERE is_metropolitan = true";
        }
        
        $query .= " ORDER BY name";
        
        $stmt = $pdo->query($query);
        return $stmt->fetchAll();
    } catch (PDOException $e) {
        error_log("Error fetching cities: " . $e->getMessage());
        return [];
    }
}

/**
 * Get districts for a specific city
 * @param int $cityId The city ID
 * @return array Array of districts
 */
function getDistricts($cityId) {
    global $pdo;
    
    try {
        $stmt = $pdo->prepare("
            SELECT d.*, pp.name as party_name 
            FROM districts d
            LEFT JOIN political_parties pp ON d.political_party_id = pp.id
            WHERE d.city_id = :city_id
            ORDER BY d.name
        ");
        $stmt->execute(['city_id' => $cityId]);
        return $stmt->fetchAll();
    } catch (PDOException $e) {
        error_log("Error fetching districts: " . $e->getMessage());
        return [];
    }
}

/**
 * Get all political parties
 * @return array Array of political parties
 */
function getPoliticalParties() {
    global $pdo;
    
    try {
        $stmt = $pdo->query("SELECT * FROM political_parties ORDER BY name");
        return $stmt->fetchAll();
    } catch (PDOException $e) {
        error_log("Error fetching political parties: " . $e->getMessage());
        return [];
    }
}

/**
 * Get posts with filtering options
 * @param array $filters Associative array of filter options
 * @param int $page Page number
 * @param int $perPage Number of items per page
 * @return array Array containing 'posts' and 'total' count
 */
function getPosts($filters = [], $page = 1, $perPage = 20) {
    global $pdo;
    
    try {
        $conditions = [];
        $params = [];
        
        // Add filter conditions
        if (!empty($filters['district'])) {
            $conditions[] = "p.district = :district";
            $params['district'] = $filters['district'];
        }
        
        if (!empty($filters['type'])) {
            $conditions[] = "p.type = :type";
            $params['type'] = $filters['type'];
        }
        
        if (isset($filters['is_resolved']) && $filters['is_resolved'] !== '') {
            $conditions[] = "p.is_resolved = :is_resolved";
            $params['is_resolved'] = (bool)$filters['is_resolved'];
        }
        
        // Build WHERE clause
        $whereClause = empty($conditions) ? "" : "WHERE " . implode(" AND ", $conditions);
        
        // Calculate offset
        $offset = ($page - 1) * $perPage;
        
        // Get total count
        $countQuery = "SELECT COUNT(*) FROM posts p $whereClause";
        $countStmt = $pdo->prepare($countQuery);
        $countStmt->execute($params);
        $total = $countStmt->fetchColumn();
        
        // Get posts
        $query = "
            SELECT p.*, 
                u.username as user_name,
                d.name as district_name,
                c.name as city_name,
                (SELECT COUNT(*) FROM comments WHERE post_id = p.id) as comment_count,
                (SELECT COUNT(*) FROM likes WHERE post_id = p.id) as like_count
            FROM posts p
            LEFT JOIN users u ON p.user_id = u.id
            LEFT JOIN districts d ON p.district = d.name
            LEFT JOIN cities c ON d.city_id = c.id
            $whereClause
            ORDER BY p.created_at DESC
            LIMIT :limit OFFSET :offset
        ";
        
        $stmt = $pdo->prepare($query);
        
        // Add limit and offset
        $stmt->bindValue(':limit', $perPage, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        
        // Bind other parameters
        foreach ($params as $key => $value) {
            $stmt->bindValue(':' . $key, $value);
        }
        
        $stmt->execute();
        $posts = $stmt->fetchAll();
        
        return [
            'posts' => $posts,
            'total' => $total
        ];
    } catch (PDOException $e) {
        error_log("Error fetching posts: " . $e->getMessage());
        return [
            'posts' => [],
            'total' => 0
        ];
    }
}

/**
 * Get dashboard statistics
 * @return array Statistics for dashboard
 */
function getDashboardStats() {
    global $pdo;
    
    try {
        $stats = [];
        
        // Total posts
        $stmt = $pdo->query("SELECT COUNT(*) FROM posts");
        $stats['total_posts'] = $stmt->fetchColumn();
        
        // Total complaints
        $stmt = $pdo->query("SELECT COUNT(*) FROM posts WHERE type = 'complaint'");
        $stats['total_complaints'] = $stmt->fetchColumn();
        
        // Resolved complaints
        $stmt = $pdo->query("SELECT COUNT(*) FROM posts WHERE type = 'complaint' AND is_resolved = true");
        $stats['resolved_complaints'] = $stmt->fetchColumn();
        
        // Thank you posts
        $stmt = $pdo->query("SELECT COUNT(*) FROM posts WHERE type = 'thanks' OR type = 'appreciation'");
        $stats['thanks_posts'] = $stmt->fetchColumn();
        
        // Total users
        $stmt = $pdo->query("SELECT COUNT(*) FROM users");
        $stats['total_users'] = $stmt->fetchColumn();
        
        // Recent posts - last 7 days
        $stmt = $pdo->query("SELECT COUNT(*) FROM posts WHERE created_at >= NOW() - INTERVAL '7 days'");
        $stats['recent_posts'] = $stmt->fetchColumn();
        
        // Resolution rate
        if ($stats['total_complaints'] > 0) {
            $stats['resolution_rate'] = round(($stats['resolved_complaints'] / $stats['total_complaints']) * 100, 2);
        } else {
            $stats['resolution_rate'] = 0;
        }
        
        // Best performing districts - based on solution_rate
        $stmt = $pdo->query("
            SELECT d.name, d.solution_rate, c.name as city_name, pp.name as party_name
            FROM districts d
            LEFT JOIN cities c ON d.city_id = c.id
            LEFT JOIN political_parties pp ON d.political_party_id = pp.id
            WHERE d.solution_rate IS NOT NULL AND CAST(d.solution_rate AS FLOAT) > 0
            ORDER BY CAST(d.solution_rate AS FLOAT) DESC
            LIMIT 5
        ");
        $stats['best_districts'] = $stmt->fetchAll();
        
        // Political party scores
        $stmt = $pdo->query("
            SELECT name, score, last_updated
            FROM political_parties
            WHERE score IS NOT NULL AND score > 0
            ORDER BY score DESC
        ");
        $stats['party_scores'] = $stmt->fetchAll();
        
        return $stats;
    } catch (PDOException $e) {
        error_log("Error fetching dashboard stats: " . $e->getMessage());
        return [
            'total_posts' => 0,
            'total_complaints' => 0,
            'resolved_complaints' => 0,
            'thanks_posts' => 0,
            'total_users' => 0,
            'recent_posts' => 0,
            'resolution_rate' => 0,
            'best_districts' => [],
            'party_scores' => []
        ];
    }
}

/**
 * Generate pagination links
 * @param int $currentPage Current page number
 * @param int $totalPages Total number of pages
 * @param string $baseUrl Base URL for pagination links
 * @return string HTML pagination links
 */
function generatePagination($currentPage, $totalPages, $baseUrl) {
    if ($totalPages <= 1) return '';
    
    $html = '<nav aria-label="Sayfalama"><ul class="pagination">';
    
    // Previous page link
    if ($currentPage > 1) {
        $html .= '<li class="page-item"><a class="page-link" href="' . $baseUrl . '&page=' . ($currentPage - 1) . '">&laquo; Önceki</a></li>';
    } else {
        $html .= '<li class="page-item disabled"><span class="page-link">&laquo; Önceki</span></li>';
    }
    
    // Page numbers
    $startPage = max(1, $currentPage - 2);
    $endPage = min($totalPages, $currentPage + 2);
    
    if ($startPage > 1) {
        $html .= '<li class="page-item"><a class="page-link" href="' . $baseUrl . '&page=1">1</a></li>';
        if ($startPage > 2) {
            $html .= '<li class="page-item disabled"><span class="page-link">...</span></li>';
        }
    }
    
    for ($i = $startPage; $i <= $endPage; $i++) {
        if ($i == $currentPage) {
            $html .= '<li class="page-item active"><span class="page-link">' . $i . '</span></li>';
        } else {
            $html .= '<li class="page-item"><a class="page-link" href="' . $baseUrl . '&page=' . $i . '">' . $i . '</a></li>';
        }
    }
    
    if ($endPage < $totalPages) {
        if ($endPage < $totalPages - 1) {
            $html .= '<li class="page-item disabled"><span class="page-link">...</span></li>';
        }
        $html .= '<li class="page-item"><a class="page-link" href="' . $baseUrl . '&page=' . $totalPages . '">' . $totalPages . '</a></li>';
    }
    
    // Next page link
    if ($currentPage < $totalPages) {
        $html .= '<li class="page-item"><a class="page-link" href="' . $baseUrl . '&page=' . ($currentPage + 1) . '">Sonraki &raquo;</a></li>';
    } else {
        $html .= '<li class="page-item disabled"><span class="page-link">Sonraki &raquo;</span></li>';
    }
    
    $html .= '</ul></nav>';
    
    return $html;
}

/**
 * Display success or error messages
 * @return string HTML for displaying messages
 */
function displayMessages() {
    $html = '';
    
    if (isset($_SESSION['success_message'])) {
        $html .= '<div class="alert alert-success alert-dismissible fade show" role="alert">
                ' . $_SESSION['success_message'] . '
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
              </div>';
        unset($_SESSION['success_message']);
    }
    
    if (isset($_SESSION['error_message'])) {
        $html .= '<div class="alert alert-danger alert-dismissible fade show" role="alert">
                ' . $_SESSION['error_message'] . '
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
              </div>';
        unset($_SESSION['error_message']);
    }
    
    return $html;
}

/**
 * Create admin_users table if it doesn't exist and add a default admin user
 */
function setupAdminUsers() {
    global $pdo;
    
    try {
        // Check if admin_users table exists
        $stmt = $pdo->query("SELECT to_regclass('public.admin_users')");
        $tableExists = $stmt->fetchColumn();
        
        if (!$tableExists) {
            // Create the admin_users table
            $pdo->exec("
                CREATE TABLE admin_users (
                    id SERIAL PRIMARY KEY,
                    username VARCHAR(50) NOT NULL UNIQUE,
                    password_hash VARCHAR(255) NOT NULL,
                    email VARCHAR(100) NOT NULL UNIQUE,
                    role VARCHAR(20) NOT NULL DEFAULT 'editor',
                    is_active BOOLEAN DEFAULT TRUE,
                    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                    last_login TIMESTAMP WITH TIME ZONE
                )
            ");
            
            // Create default admin user
            $username = 'admin';
            $passwordHash = password_hash('admin123', PASSWORD_DEFAULT);
            $email = 'admin@belediye.gov.tr';
            
            $stmt = $pdo->prepare("
                INSERT INTO admin_users (username, password_hash, email, role)
                VALUES (:username, :password_hash, :email, 'admin')
            ");
            
            $stmt->execute([
                'username' => $username,
                'password_hash' => $passwordHash,
                'email' => $email
            ]);
            
            error_log("Admin users table created with default admin user");
        }
    } catch (PDOException $e) {
        error_log("Error setting up admin users: " . $e->getMessage());
    }
}

// Call the setup function
setupAdminUsers();
?>