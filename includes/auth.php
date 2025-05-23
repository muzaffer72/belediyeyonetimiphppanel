<?php
// Authentication related functions

/**
 * Check if user is logged in
 * @return bool True if user is logged in, false otherwise
 */
function isLoggedIn() {
    return isset($_SESSION['user_id']) && !empty($_SESSION['user_id']);
}

/**
 * Attempt to log in a user
 * @param string $username The username
 * @param string $password The password
 * @return bool True if login successful, false otherwise
 */
function loginUser($username, $password) {
    global $pdo;
    
    try {
        // Fetch the user
        $stmt = $pdo->prepare("SELECT id, username, password_hash, role FROM admin_users WHERE username = :username AND is_active = true");
        $stmt->execute(['username' => $username]);
        $user = $stmt->fetch();
        
        // Check if user exists and password is correct
        if ($user && password_verify($password, $user['password_hash'])) {
            // Set session variables
            $_SESSION['user_id'] = $user['id'];
            $_SESSION['username'] = $user['username'];
            $_SESSION['role'] = $user['role'];
            
            // Update last login time
            $updateStmt = $pdo->prepare("UPDATE admin_users SET last_login = NOW() WHERE id = :id");
            $updateStmt->execute(['id' => $user['id']]);
            
            return true;
        }
    } catch (PDOException $e) {
        error_log("Login error: " . $e->getMessage());
    }
    
    return false;
}

/**
 * Log out the current user
 */
function logoutUser() {
    // Unset all session variables
    $_SESSION = [];
    
    // Delete the session cookie
    if (ini_get("session.use_cookies")) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000,
            $params["path"], $params["domain"],
            $params["secure"], $params["httponly"]
        );
    }
    
    // Destroy the session
    session_destroy();
}

/**
 * Register a new admin user
 * @param array $userData User data array containing username, password, email, and role
 * @return bool|string True on success, error message on failure
 */
function registerUser($userData) {
    global $pdo;
    
    try {
        // Check if username already exists
        $stmt = $pdo->prepare("SELECT id FROM admin_users WHERE username = :username");
        $stmt->execute(['username' => $userData['username']]);
        if ($stmt->rowCount() > 0) {
            return "Bu kullanıcı adı zaten kullanımda.";
        }
        
        // Check if email already exists
        $stmt = $pdo->prepare("SELECT id FROM admin_users WHERE email = :email");
        $stmt->execute(['email' => $userData['email']]);
        if ($stmt->rowCount() > 0) {
            return "Bu e-posta adresi zaten kullanımda.";
        }
        
        // Hash password
        $passwordHash = password_hash($userData['password'], PASSWORD_DEFAULT);
        
        // Insert new user
        $stmt = $pdo->prepare("
            INSERT INTO admin_users (username, password_hash, email, role, is_active, created_at)
            VALUES (:username, :password_hash, :email, :role, true, NOW())
        ");
        
        $stmt->execute([
            'username' => $userData['username'],
            'password_hash' => $passwordHash,
            'email' => $userData['email'],
            'role' => $userData['role']
        ]);
        
        return true;
    } catch (PDOException $e) {
        error_log("Registration error: " . $e->getMessage());
        return "Kayıt sırasında bir hata oluştu. Lütfen daha sonra tekrar deneyin.";
    }
}

/**
 * Check if user has specific permission
 * @param string $permission The permission to check
 * @return bool True if user has permission, false otherwise
 */
function hasPermission($permission) {
    if (!isLoggedIn()) return false;
    
    // Admin has all permissions
    if ($_SESSION['role'] === 'admin') return true;
    
    // For other roles, you need to implement a permission system
    $rolePermissions = [
        'manager' => ['view_dashboard', 'manage_cities', 'manage_districts', 'view_posts', 'moderate_posts', 'view_users'],
        'moderator' => ['view_dashboard', 'view_posts', 'moderate_posts'],
        'editor' => ['view_dashboard', 'view_posts', 'create_announcements']
    ];
    
    if (isset($rolePermissions[$_SESSION['role']])) {
        return in_array($permission, $rolePermissions[$_SESSION['role']]);
    }
    
    return false;
}
?>