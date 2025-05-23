<?php
session_start();
require_once 'includes/config.php';
require_once 'includes/functions.php';
require_once 'includes/auth.php';

// If not logged in, redirect to login page
if (!isLoggedIn() && basename($_SERVER['PHP_SELF']) != 'login.php') {
    header('Location: login.php');
    exit;
}

// Main page content
include 'includes/header.php';

// Check if a page is requested
$page = isset($_GET['page']) ? $_GET['page'] : 'dashboard';
$allowed_pages = ['dashboard', 'cities', 'districts', 'political-parties', 'posts', 'complaints', 'thanks', 'users', 'announcements', 'settings'];

// Validate the requested page
if (in_array($page, $allowed_pages)) {
    include "pages/$page.php";
} else {
    include "pages/dashboard.php";
}

include 'includes/footer.php';
?>