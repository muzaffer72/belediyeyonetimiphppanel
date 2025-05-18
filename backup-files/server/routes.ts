import type { Express } from "express";
import { createServer, type Server } from "http";
import { storage } from "./storage";
import { z } from "zod";
import {
  insertCitySchema,
  insertDistrictSchema,
  insertUserSchema,
  insertUserBanSchema,
  insertPostSchema,
  insertCommentSchema,
  insertLikeSchema,
  insertPoliticalPartySchema,
  insertMunicipalityAnnouncementSchema
} from "../shared/schema";

export async function registerRoutes(app: Express): Promise<Server> {
  // Create HTTP server
  const httpServer = createServer(app);

  // Test route for Supabase connection info
  app.get("/api/test-connection", async (req, res) => {
    try {
      const supabaseUrl = process.env.SUPABASE_URL || '';
      const keyPreview = process.env.SUPABASE_SERVICE_ROLE_KEY ? 
        `${process.env.SUPABASE_SERVICE_ROLE_KEY.substring(0, 5)}...${process.env.SUPABASE_SERVICE_ROLE_KEY.substring(process.env.SUPABASE_SERVICE_ROLE_KEY.length - 5)}` : 
        'not found';
      
      res.json({ 
        success: true, 
        message: 'Connection info retrieved',
        supabase_url: supabaseUrl,
        key_preview: keyPreview,
        has_url: !!process.env.SUPABASE_URL,
        has_key: !!process.env.SUPABASE_SERVICE_ROLE_KEY
      });
    } catch (error) {
      console.error("Test connection error:", error);
      res.status(500).json({ message: "Test connection failed", error: String(error) });
    }
  });

  // Dashboard routes
  app.get("/api/dashboard/stats", async (req, res) => {
    try {
      // Use Supabase client directly instead of going through storage
      const { supabase } = await import("../shared/supabase");
      
      // Run multiple counts using Supabase client
      const [citiesCount, usersCount, postsCount, complaintsCount] = await Promise.all([
        supabase.from('cities').select('*', { count: 'exact', head: true }),
        supabase.from('users').select('*', { count: 'exact', head: true }),
        supabase.from('posts').select('*', { count: 'exact', head: true }),
        supabase.from('posts').select('*', { count: 'exact', head: true })
          .eq('type', 'complaint')
          .eq('is_resolved', false)
      ]);
      
      // Create stats object
      const stats = {
        totalCities: citiesCount.count || 0,
        activeUsers: usersCount.count || 0,
        totalPosts: postsCount.count || 0,
        pendingComplaints: complaintsCount.count || 0
      };
      
      res.json(stats);
    } catch (error) {
      console.error("Error fetching dashboard stats:", error);
      res.status(500).json({ message: "Failed to fetch dashboard statistics" });
    }
  });

  app.get("/api/dashboard/activities", async (req, res) => {
    try {
      const limit = req.query.limit ? parseInt(req.query.limit as string) : 5;
      
      // Use Supabase client directly
      const { supabase } = await import("../shared/supabase");
      
      // Get recent posts (we'll use these as activities)
      const { data: posts, error } = await supabase
        .from('posts')
        .select('id, title, type, user_id, created_at')
        .order('created_at', { ascending: false })
        .limit(limit);
      
      if (error) throw error;
      
      // Get usernames for the posts
      const userIds = [...new Set(posts.map(post => post.user_id))];
      const { data: users } = await supabase
        .from('users')
        .select('id, username, profile_image_url')
        .in('id', userIds);
      
      // Format activities
      const activities = posts.map(post => {
        const user = users.find(u => u.id === post.user_id);
        return {
          id: post.id,
          userId: post.user_id,
          username: user?.username || 'Unknown User',
          userAvatar: user?.profile_image_url,
          action: getActionByPostType(post.type),
          target: post.title,
          timestamp: post.created_at
        };
      });
      
      res.json(activities);
    } catch (error) {
      console.error("Error fetching recent activities:", error);
      res.status(500).json({ 
        message: "Failed to fetch recent activities",
        error: error instanceof Error ? error.message : String(error)
      });
    }
  });
  
  // Helper function to get action description by post type
  function getActionByPostType(type: string): string {
    switch (type) {
      case 'complaint': return 'filed a complaint';
      case 'suggestion': return 'made a suggestion';
      case 'question': return 'asked a question';
      case 'thanks': return 'sent thanks';
      default: return 'created a post';
    }
  }

  app.get("/api/dashboard/post-categories", async (req, res) => {
    try {
      // Use Supabase client directly
      const { supabase } = await import("../shared/supabase");
      
      // Define post types with their UI properties
      const postTypeConfig = {
        'complaint': { icon: 'AlertCircle', color: '#EF4444' },
        'suggestion': { icon: 'Lightbulb', color: '#F59E0B' },
        'question': { icon: 'HelpCircle', color: '#3B82F6' },
        'thanks': { icon: 'Heart', color: '#10B981' }
      };
      
      // Get posts and count by type
      const { data, error } = await supabase
        .from('posts')
        .select('type');
      
      if (error) throw error;
      
      // Count posts by type
      const counts = data.reduce((acc, post) => {
        const type = post.type || 'other';
        acc[type] = (acc[type] || 0) + 1;
        return acc;
      }, {});
      
      // Calculate total
      const total = Object.values(counts).reduce((sum: number, count: any) => sum + count, 0);
      
      // Format the categories
      const categories = Object.entries(counts).map(([type, count]) => {
        const config = postTypeConfig[type as keyof typeof postTypeConfig] || { icon: 'FileText', color: '#6B7280' };
        return {
          type,
          count,
          percentage: total > 0 ? Math.round(((count as number) / total) * 100) : 0,
          icon: config.icon,
          color: config.color
        };
      });
      
      res.json(categories);
    } catch (error) {
      console.error("Error fetching post categories:", error);
      res.status(500).json({ 
        message: "Failed to fetch post categories distribution",
        error: error instanceof Error ? error.message : String(error)
      });
    }
  });

// Helper function to generate consistent colors based on string name
const generateColor = (str: string): string => {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash);
  }
  const c = (hash & 0x00FFFFFF).toString(16).toUpperCase();
  return "#" + "00000".substring(0, 6 - c.length) + c;
};

  app.get("/api/dashboard/party-distribution", async (req, res) => {
    try {
      // Use Supabase client directly
      const { supabase } = await import("../shared/supabase");
      
      // Get political parties
      const { data: parties, error } = await supabase
        .from('political_parties')
        .select('id, name, logo_url, score, last_updated');
      
      if (error) throw error;
      
      // Get city counts by party
      const { data: cities } = await supabase
        .from('cities')
        .select('political_party_id');
      
      // Calculate total cities
      const totalCities = cities.length;
      
      // Count cities by party
      const partyCounts = cities.reduce((acc, city) => {
        const partyId = city.political_party_id;
        if (partyId) {
          acc[partyId] = (acc[partyId] || 0) + 1;
        }
        return acc;
      }, {});
      
      // Format for frontend
      const distribution = parties.map(party => {
        const count = partyCounts[party.id] || 0;
        // Generate color from party name for consistency
        const color = generateColor(party.name);
        
        return {
          id: party.id,
          name: party.name,
          logo: party.logo_url, // Using logo_url from database
          color: color,
          percentage: party.score ? parseFloat(party.score) * 20 : 0 // Convert 0-5 scale to 0-100%
        };
      });
      
      res.json(distribution);
    } catch (error) {
      console.error("Error fetching party distribution:", error);
      res.status(500).json({ 
        message: "Failed to fetch political party distribution",
        error: error instanceof Error ? error.message : String(error)
      });
    }
  });

  // Cities routes
  app.get("/api/cities", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.name) filters.name = req.query.name;
      if (req.query.mayorName) filters.mayorName = req.query.mayorName;
      if (req.query.politicalPartyId) filters.politicalPartyId = req.query.politicalPartyId;
      
      const cities = await storage.getCities({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(cities);
    } catch (error) {
      console.error("Error fetching cities:", error);
      res.status(500).json({ message: "Failed to fetch cities" });
    }
  });

  app.get("/api/cities/:id", async (req, res) => {
    try {
      const city = await storage.getCityById(req.params.id);
      if (!city) {
        return res.status(404).json({ message: "City not found" });
      }
      res.json(city);
    } catch (error) {
      console.error("Error fetching city:", error);
      res.status(500).json({ message: "Failed to fetch city" });
    }
  });

  app.post("/api/cities", async (req, res) => {
    try {
      const validatedData = insertCitySchema.parse(req.body);
      const city = await storage.createCity(validatedData);
      res.status(201).json(city);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid city data", errors: error.errors });
      }
      console.error("Error creating city:", error);
      res.status(500).json({ message: "Failed to create city" });
    }
  });

  app.put("/api/cities/:id", async (req, res) => {
    try {
      const validatedData = insertCitySchema.partial().parse(req.body);
      const city = await storage.updateCity(req.params.id, validatedData);
      if (!city) {
        return res.status(404).json({ message: "City not found" });
      }
      res.json(city);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid city data", errors: error.errors });
      }
      console.error("Error updating city:", error);
      res.status(500).json({ message: "Failed to update city" });
    }
  });

  app.delete("/api/cities/:id", async (req, res) => {
    try {
      const success = await storage.deleteCity(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "City not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting city:", error);
      res.status(500).json({ message: "Failed to delete city" });
    }
  });

  // Districts routes
  app.get("/api/districts", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.name) filters.name = req.query.name;
      if (req.query.cityId) filters.cityId = req.query.cityId;
      if (req.query.mayorName) filters.mayorName = req.query.mayorName;
      if (req.query.politicalPartyId) filters.politicalPartyId = req.query.politicalPartyId;
      
      const districts = await storage.getDistricts({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(districts);
    } catch (error) {
      console.error("Error fetching districts:", error);
      res.status(500).json({ message: "Failed to fetch districts" });
    }
  });

  app.get("/api/districts/:id", async (req, res) => {
    try {
      const district = await storage.getDistrictById(req.params.id);
      if (!district) {
        return res.status(404).json({ message: "District not found" });
      }
      res.json(district);
    } catch (error) {
      console.error("Error fetching district:", error);
      res.status(500).json({ message: "Failed to fetch district" });
    }
  });

  app.get("/api/cities/:cityId/districts", async (req, res) => {
    try {
      const districts = await storage.getDistrictsByCityId(req.params.cityId);
      res.json(districts);
    } catch (error) {
      console.error("Error fetching districts by city:", error);
      res.status(500).json({ message: "Failed to fetch districts for city" });
    }
  });

  app.post("/api/districts", async (req, res) => {
    try {
      const validatedData = insertDistrictSchema.parse(req.body);
      const district = await storage.createDistrict(validatedData);
      res.status(201).json(district);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid district data", errors: error.errors });
      }
      console.error("Error creating district:", error);
      res.status(500).json({ message: "Failed to create district" });
    }
  });

  app.put("/api/districts/:id", async (req, res) => {
    try {
      const validatedData = insertDistrictSchema.partial().parse(req.body);
      const district = await storage.updateDistrict(req.params.id, validatedData);
      if (!district) {
        return res.status(404).json({ message: "District not found" });
      }
      res.json(district);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid district data", errors: error.errors });
      }
      console.error("Error updating district:", error);
      res.status(500).json({ message: "Failed to update district" });
    }
  });

  app.delete("/api/districts/:id", async (req, res) => {
    try {
      const success = await storage.deleteDistrict(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "District not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting district:", error);
      res.status(500).json({ message: "Failed to delete district" });
    }
  });

  // Users routes
  app.get("/api/users", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.username) filters.username = req.query.username;
      if (req.query.email) filters.email = req.query.email;
      if (req.query.city) filters.city = req.query.city;
      if (req.query.district) filters.district = req.query.district;
      if (req.query.role) filters.role = req.query.role;
      
      const users = await storage.getUsers({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(users);
    } catch (error) {
      console.error("Error fetching users:", error);
      res.status(500).json({ message: "Failed to fetch users" });
    }
  });

  app.get("/api/users/:id", async (req, res) => {
    try {
      const user = await storage.getUserById(req.params.id);
      if (!user) {
        return res.status(404).json({ message: "User not found" });
      }
      res.json(user);
    } catch (error) {
      console.error("Error fetching user:", error);
      res.status(500).json({ message: "Failed to fetch user" });
    }
  });

  app.post("/api/users", async (req, res) => {
    try {
      const validatedData = insertUserSchema.parse(req.body);
      const user = await storage.createUser(validatedData);
      res.status(201).json(user);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid user data", errors: error.errors });
      }
      console.error("Error creating user:", error);
      res.status(500).json({ message: "Failed to create user" });
    }
  });

  app.put("/api/users/:id", async (req, res) => {
    try {
      const validatedData = insertUserSchema.partial().parse(req.body);
      const user = await storage.updateUser(req.params.id, validatedData);
      if (!user) {
        return res.status(404).json({ message: "User not found" });
      }
      res.json(user);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid user data", errors: error.errors });
      }
      console.error("Error updating user:", error);
      res.status(500).json({ message: "Failed to update user" });
    }
  });

  app.delete("/api/users/:id", async (req, res) => {
    try {
      const success = await storage.deleteUser(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "User not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting user:", error);
      res.status(500).json({ message: "Failed to delete user" });
    }
  });

  // User bans routes
  app.get("/api/user-bans", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.userId) filters.userId = req.query.userId;
      if (req.query.isActive) filters.isActive = req.query.isActive === 'true';
      
      const bans = await storage.getUserBans({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(bans);
    } catch (error) {
      console.error("Error fetching user bans:", error);
      res.status(500).json({ message: "Failed to fetch user bans" });
    }
  });

  app.get("/api/user-bans/:id", async (req, res) => {
    try {
      const ban = await storage.getUserBanById(req.params.id);
      if (!ban) {
        return res.status(404).json({ message: "User ban not found" });
      }
      res.json(ban);
    } catch (error) {
      console.error("Error fetching user ban:", error);
      res.status(500).json({ message: "Failed to fetch user ban" });
    }
  });

  app.get("/api/users/:userId/bans", async (req, res) => {
    try {
      const bans = await storage.getUserBansByUserId(req.params.userId);
      res.json(bans);
    } catch (error) {
      console.error("Error fetching user bans by user:", error);
      res.status(500).json({ message: "Failed to fetch bans for user" });
    }
  });

  app.post("/api/user-bans", async (req, res) => {
    try {
      const validatedData = insertUserBanSchema.parse(req.body);
      const ban = await storage.createUserBan(validatedData);
      res.status(201).json(ban);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid user ban data", errors: error.errors });
      }
      console.error("Error creating user ban:", error);
      res.status(500).json({ message: "Failed to create user ban" });
    }
  });

  app.put("/api/user-bans/:id", async (req, res) => {
    try {
      const validatedData = insertUserBanSchema.partial().parse(req.body);
      const ban = await storage.updateUserBan(req.params.id, validatedData);
      if (!ban) {
        return res.status(404).json({ message: "User ban not found" });
      }
      res.json(ban);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid user ban data", errors: error.errors });
      }
      console.error("Error updating user ban:", error);
      res.status(500).json({ message: "Failed to update user ban" });
    }
  });

  app.delete("/api/user-bans/:id", async (req, res) => {
    try {
      const success = await storage.deleteUserBan(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "User ban not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting user ban:", error);
      res.status(500).json({ message: "Failed to delete user ban" });
    }
  });

  // Posts routes
  app.get("/api/posts", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.title) filters.title = req.query.title;
      if (req.query.userId) filters.userId = req.query.userId;
      if (req.query.type) filters.type = req.query.type;
      if (req.query.city) filters.city = req.query.city;
      if (req.query.district) filters.district = req.query.district;
      if (req.query.isResolved !== undefined) filters.isResolved = req.query.isResolved === 'true';
      if (req.query.isHidden !== undefined) filters.isHidden = req.query.isHidden === 'true';
      if (req.query.isFeatured !== undefined) filters.isFeatured = req.query.isFeatured === 'true';
      
      const posts = await storage.getPosts({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(posts);
    } catch (error) {
      console.error("Error fetching posts:", error);
      res.status(500).json({ message: "Failed to fetch posts" });
    }
  });

  app.get("/api/posts/featured", async (req, res) => {
    try {
      const featuredPosts = await storage.getFeaturedPosts();
      res.json(featuredPosts);
    } catch (error) {
      console.error("Error fetching featured posts:", error);
      res.status(500).json({ message: "Failed to fetch featured posts" });
    }
  });

  app.get("/api/posts/:id", async (req, res) => {
    try {
      const post = await storage.getPostById(req.params.id);
      if (!post) {
        return res.status(404).json({ message: "Post not found" });
      }
      res.json(post);
    } catch (error) {
      console.error("Error fetching post:", error);
      res.status(500).json({ message: "Failed to fetch post" });
    }
  });

  app.get("/api/users/:userId/posts", async (req, res) => {
    try {
      const posts = await storage.getPostsByUserId(req.params.userId);
      res.json(posts);
    } catch (error) {
      console.error("Error fetching posts by user:", error);
      res.status(500).json({ message: "Failed to fetch posts for user" });
    }
  });

  app.post("/api/posts", async (req, res) => {
    try {
      const validatedData = insertPostSchema.parse(req.body);
      const post = await storage.createPost(validatedData);
      res.status(201).json(post);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid post data", errors: error.errors });
      }
      console.error("Error creating post:", error);
      res.status(500).json({ message: "Failed to create post" });
    }
  });

  app.put("/api/posts/:id", async (req, res) => {
    try {
      const validatedData = insertPostSchema.partial().parse(req.body);
      const post = await storage.updatePost(req.params.id, validatedData);
      if (!post) {
        return res.status(404).json({ message: "Post not found" });
      }
      res.json(post);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid post data", errors: error.errors });
      }
      console.error("Error updating post:", error);
      res.status(500).json({ message: "Failed to update post" });
    }
  });

  app.post("/api/posts/:id/feature", async (req, res) => {
    try {
      const { userId } = req.body;
      if (!userId) {
        return res.status(400).json({ message: "User ID is required" });
      }
      
      const success = await storage.togglePostFeatured(req.params.id, userId);
      if (!success) {
        return res.status(404).json({ message: "Post not found" });
      }
      
      res.status(200).json({ success: true });
    } catch (error) {
      console.error("Error featuring post:", error);
      res.status(500).json({ message: "Failed to feature post" });
    }
  });

  app.delete("/api/posts/:id", async (req, res) => {
    try {
      const success = await storage.deletePost(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "Post not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting post:", error);
      res.status(500).json({ message: "Failed to delete post" });
    }
  });

  // Comments routes
  app.get("/api/comments", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.postId) filters.postId = req.query.postId;
      if (req.query.userId) filters.userId = req.query.userId;
      if (req.query.isHidden !== undefined) filters.isHidden = req.query.isHidden === 'true';
      
      const comments = await storage.getComments({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(comments);
    } catch (error) {
      console.error("Error fetching comments:", error);
      res.status(500).json({ message: "Failed to fetch comments" });
    }
  });

  app.get("/api/comments/:id", async (req, res) => {
    try {
      const comment = await storage.getCommentById(req.params.id);
      if (!comment) {
        return res.status(404).json({ message: "Comment not found" });
      }
      res.json(comment);
    } catch (error) {
      console.error("Error fetching comment:", error);
      res.status(500).json({ message: "Failed to fetch comment" });
    }
  });

  app.get("/api/posts/:postId/comments", async (req, res) => {
    try {
      const comments = await storage.getCommentsByPostId(req.params.postId);
      res.json(comments);
    } catch (error) {
      console.error("Error fetching comments by post:", error);
      res.status(500).json({ message: "Failed to fetch comments for post" });
    }
  });

  app.post("/api/comments", async (req, res) => {
    try {
      const validatedData = insertCommentSchema.parse(req.body);
      const comment = await storage.createComment(validatedData);
      res.status(201).json(comment);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid comment data", errors: error.errors });
      }
      console.error("Error creating comment:", error);
      res.status(500).json({ message: "Failed to create comment" });
    }
  });

  app.put("/api/comments/:id", async (req, res) => {
    try {
      const validatedData = insertCommentSchema.partial().parse(req.body);
      const comment = await storage.updateComment(req.params.id, validatedData);
      if (!comment) {
        return res.status(404).json({ message: "Comment not found" });
      }
      res.json(comment);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid comment data", errors: error.errors });
      }
      console.error("Error updating comment:", error);
      res.status(500).json({ message: "Failed to update comment" });
    }
  });

  app.delete("/api/comments/:id", async (req, res) => {
    try {
      const success = await storage.deleteComment(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "Comment not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting comment:", error);
      res.status(500).json({ message: "Failed to delete comment" });
    }
  });

  // Likes routes
  app.get("/api/posts/:postId/likes", async (req, res) => {
    try {
      const likes = await storage.getLikesByPostId(req.params.postId);
      res.json(likes);
    } catch (error) {
      console.error("Error fetching likes by post:", error);
      res.status(500).json({ message: "Failed to fetch likes for post" });
    }
  });

  app.post("/api/likes", async (req, res) => {
    try {
      const validatedData = insertLikeSchema.parse(req.body);
      const like = await storage.createLike(validatedData);
      res.status(201).json(like);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid like data", errors: error.errors });
      }
      console.error("Error creating like:", error);
      res.status(500).json({ message: "Failed to create like" });
    }
  });

  app.delete("/api/likes/:id", async (req, res) => {
    try {
      const success = await storage.deleteLike(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "Like not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting like:", error);
      res.status(500).json({ message: "Failed to delete like" });
    }
  });

  app.get("/api/posts/:postId/users/:userId/liked", async (req, res) => {
    try {
      const hasLiked = await storage.hasUserLikedPost(req.params.userId, req.params.postId);
      res.json({ hasLiked });
    } catch (error) {
      console.error("Error checking if user liked post:", error);
      res.status(500).json({ message: "Failed to check if user liked post" });
    }
  });

  // Political parties routes
  app.get("/api/political-parties", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.name) filters.name = req.query.name;
      
      const parties = await storage.getPoliticalParties({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(parties);
    } catch (error) {
      console.error("Error fetching political parties:", error);
      res.status(500).json({ message: "Failed to fetch political parties" });
    }
  });

  app.get("/api/political-parties/:id", async (req, res) => {
    try {
      const party = await storage.getPoliticalPartyById(req.params.id);
      if (!party) {
        return res.status(404).json({ message: "Political party not found" });
      }
      res.json(party);
    } catch (error) {
      console.error("Error fetching political party:", error);
      res.status(500).json({ message: "Failed to fetch political party" });
    }
  });

  app.post("/api/political-parties", async (req, res) => {
    try {
      const validatedData = insertPoliticalPartySchema.parse(req.body);
      const party = await storage.createPoliticalParty(validatedData);
      res.status(201).json(party);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid political party data", errors: error.errors });
      }
      console.error("Error creating political party:", error);
      res.status(500).json({ message: "Failed to create political party" });
    }
  });

  app.put("/api/political-parties/:id", async (req, res) => {
    try {
      const validatedData = insertPoliticalPartySchema.partial().parse(req.body);
      const party = await storage.updatePoliticalParty(req.params.id, validatedData);
      if (!party) {
        return res.status(404).json({ message: "Political party not found" });
      }
      res.json(party);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid political party data", errors: error.errors });
      }
      console.error("Error updating political party:", error);
      res.status(500).json({ message: "Failed to update political party" });
    }
  });

  app.delete("/api/political-parties/:id", async (req, res) => {
    try {
      const success = await storage.deletePoliticalParty(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "Political party not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting political party:", error);
      res.status(500).json({ message: "Failed to delete political party" });
    }
  });

  // Municipality announcements routes
  app.get("/api/municipality-announcements", async (req, res) => {
    try {
      const page = req.query.page ? parseInt(req.query.page as string) : 1;
      const pageSize = req.query.pageSize ? parseInt(req.query.pageSize as string) : 10;
      
      const filters: Record<string, any> = {};
      if (req.query.title) filters.title = req.query.title;
      if (req.query.municipalityId) filters.municipalityId = req.query.municipalityId;
      if (req.query.isActive !== undefined) filters.isActive = req.query.isActive === 'true';
      
      const announcements = await storage.getMunicipalityAnnouncements({
        pagination: { page, pageSize },
        filters
      });
      
      res.json(announcements);
    } catch (error) {
      console.error("Error fetching municipality announcements:", error);
      res.status(500).json({ message: "Failed to fetch municipality announcements" });
    }
  });

  app.get("/api/municipality-announcements/:id", async (req, res) => {
    try {
      const announcement = await storage.getMunicipalityAnnouncementById(req.params.id);
      if (!announcement) {
        return res.status(404).json({ message: "Municipality announcement not found" });
      }
      res.json(announcement);
    } catch (error) {
      console.error("Error fetching municipality announcement:", error);
      res.status(500).json({ message: "Failed to fetch municipality announcement" });
    }
  });

  app.get("/api/cities/:municipalityId/announcements", async (req, res) => {
    try {
      const announcements = await storage.getMunicipalityAnnouncementsByMunicipalityId(req.params.municipalityId);
      res.json(announcements);
    } catch (error) {
      console.error("Error fetching announcements by municipality:", error);
      res.status(500).json({ message: "Failed to fetch announcements for municipality" });
    }
  });

  app.post("/api/municipality-announcements", async (req, res) => {
    try {
      const validatedData = insertMunicipalityAnnouncementSchema.parse(req.body);
      const announcement = await storage.createMunicipalityAnnouncement(validatedData);
      res.status(201).json(announcement);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid municipality announcement data", errors: error.errors });
      }
      console.error("Error creating municipality announcement:", error);
      res.status(500).json({ message: "Failed to create municipality announcement" });
    }
  });

  app.put("/api/municipality-announcements/:id", async (req, res) => {
    try {
      const validatedData = insertMunicipalityAnnouncementSchema.partial().parse(req.body);
      const announcement = await storage.updateMunicipalityAnnouncement(req.params.id, validatedData);
      if (!announcement) {
        return res.status(404).json({ message: "Municipality announcement not found" });
      }
      res.json(announcement);
    } catch (error) {
      if (error instanceof z.ZodError) {
        return res.status(400).json({ message: "Invalid municipality announcement data", errors: error.errors });
      }
      console.error("Error updating municipality announcement:", error);
      res.status(500).json({ message: "Failed to update municipality announcement" });
    }
  });

  app.delete("/api/municipality-announcements/:id", async (req, res) => {
    try {
      const success = await storage.deleteMunicipalityAnnouncement(req.params.id);
      if (!success) {
        return res.status(404).json({ message: "Municipality announcement not found" });
      }
      res.status(204).end();
    } catch (error) {
      console.error("Error deleting municipality announcement:", error);
      res.status(500).json({ message: "Failed to delete municipality announcement" });
    }
  });

  return httpServer;
}
