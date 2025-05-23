<?php
session_start();
require_once 'includes/auth.php';

// Log out the user
logoutUser();

// Redirect to login page
header('Location: login.php');
exit;
?>