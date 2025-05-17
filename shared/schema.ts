import { pgTable, text, uuid, timestamp, varchar, boolean, integer, real } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod";

// Cities/Municipalities schema
export const cities = pgTable("cities", {
  id: uuid("id").primaryKey(),
  name: text("name").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
  website: text("website"),
  phone: text("phone"),
  email: text("email"),
  address: text("address"),
  logoUrl: text("logo_url"),
  coverImageUrl: text("cover_image_url"),
  mayorName: text("mayor_name"),
  mayorParty: text("mayor_party"),
  partyLogoUrl: text("party_logo_url"),
  population: integer("population"),
  socialMediaLinks: text("social_media_links"),
  type: text("type"),
  politicalPartyId: uuid("political_party_id").references(() => politicalParties.id),
});

// Districts schema
export const districts = pgTable("districts", {
  id: uuid("id").primaryKey(),
  cityId: uuid("city_id").references(() => cities.id),
  name: text("name").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
  website: text("website"),
  phone: text("phone"),
  email: text("email"),
  address: text("address"),
  logoUrl: text("logo_url"),
  coverImageUrl: text("cover_image_url"),
  mayorName: text("mayor_name"),
  mayorParty: text("mayor_party"),
  partyLogoUrl: text("party_logo_url"),
  population: integer("population"),
  socialMediaLinks: text("social_media_links"),
  type: text("type"),
  politicalPartyId: uuid("political_party_id").references(() => politicalParties.id),
});

// Users schema
export const users = pgTable("users", {
  id: uuid("id").primaryKey(),
  email: text("email"),
  username: text("username"),
  profileImageUrl: text("profile_image_url"),
  city: text("city"),
  district: text("district"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
  phoneNumber: text("phone_number"),
  role: text("role").default("user"),
});

// User bans schema
export const userBans = pgTable("user_bans", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").references(() => users.id),
  bannedBy: uuid("banned_by").references(() => users.id),
  reason: text("reason"),
  banStart: timestamp("ban_start", { withTimezone: true }),
  banEnd: timestamp("ban_end", { withTimezone: true }),
  contentAction: text("content_action"),
  isActive: boolean("is_active").default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
});

// Posts schema
export const posts = pgTable("posts", {
  id: uuid("id").primaryKey(),
  userId: uuid("user_id").references(() => users.id),
  title: text("title"),
  description: text("description"),
  mediaUrl: text("media_url"),
  isVideo: boolean("is_video").default(false),
  type: text("type"),
  city: text("city"),
  district: text("district"),
  likeCount: integer("like_count").default(0),
  commentCount: integer("comment_count").default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
  mediaUrls: text("media_urls"), // Assumed to be a comma-separated list or JSON string
  isVideoList: text("is_video_list"), // Assumed to be a comma-separated list or JSON string
  category: text("category"),
  isResolved: boolean("is_resolved").default(false),
  isHidden: boolean("is_hidden").default(false),
  monthlyFeaturedCount: integer("monthly_featured_count").default(0),
  isFeatured: boolean("is_featured").default(false),
  featuredCount: integer("featured_count").default(0),
});

// Comments schema
export const comments = pgTable("comments", {
  id: uuid("id").primaryKey(),
  postId: uuid("post_id").references(() => posts.id),
  userId: uuid("user_id").references(() => users.id),
  content: text("content"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
  isHidden: boolean("is_hidden").default(false),
});

// Likes schema
export const likes = pgTable("likes", {
  id: uuid("id").primaryKey(),
  postId: uuid("post_id").references(() => posts.id),
  userId: uuid("user_id").references(() => users.id),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
});

// Featured Posts schema
export const featuredPosts = pgTable("featured_posts", {
  id: text("id").primaryKey(),
  postId: uuid("post_id").references(() => posts.id),
  userId: uuid("user_id").references(() => users.id),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
});

// Political Parties schema
export const politicalParties = pgTable("political_parties", {
  id: uuid("id").primaryKey(),
  name: text("name").notNull(),
  logoUrl: text("logo_url"),
  score: real("score"),
  lastUpdated: timestamp("last_updated", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
});

// Municipality Announcements schema
export const municipalityAnnouncements = pgTable("municipality_announcements", {
  id: uuid("id").primaryKey(),
  municipalityId: uuid("municipality_id").references(() => cities.id),
  title: text("title"),
  content: text("content"),
  imageUrl: text("image_url"),
  isActive: boolean("is_active").default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }),
});

// Insert Schemas
export const insertCitySchema = createInsertSchema(cities).omit({ id: true });
export const insertDistrictSchema = createInsertSchema(districts).omit({ id: true });
export const insertUserSchema = createInsertSchema(users).omit({ id: true });
export const insertUserBanSchema = createInsertSchema(userBans).omit({ id: true });
export const insertPostSchema = createInsertSchema(posts).omit({ id: true });
export const insertCommentSchema = createInsertSchema(comments).omit({ id: true });
export const insertLikeSchema = createInsertSchema(likes).omit({ id: true });
export const insertFeaturedPostSchema = createInsertSchema(featuredPosts).omit({ id: true });
export const insertPoliticalPartySchema = createInsertSchema(politicalParties).omit({ id: true });
export const insertMunicipalityAnnouncementSchema = createInsertSchema(municipalityAnnouncements).omit({ id: true });

// Types
export type City = typeof cities.$inferSelect;
export type InsertCity = z.infer<typeof insertCitySchema>;

export type District = typeof districts.$inferSelect;
export type InsertDistrict = z.infer<typeof insertDistrictSchema>;

export type User = typeof users.$inferSelect;
export type InsertUser = z.infer<typeof insertUserSchema>;

export type UserBan = typeof userBans.$inferSelect;
export type InsertUserBan = z.infer<typeof insertUserBanSchema>;

export type Post = typeof posts.$inferSelect;
export type InsertPost = z.infer<typeof insertPostSchema>;

export type Comment = typeof comments.$inferSelect;
export type InsertComment = z.infer<typeof insertCommentSchema>;

export type Like = typeof likes.$inferSelect;
export type InsertLike = z.infer<typeof insertLikeSchema>;

export type FeaturedPost = typeof featuredPosts.$inferSelect;
export type InsertFeaturedPost = z.infer<typeof insertFeaturedPostSchema>;

export type PoliticalParty = typeof politicalParties.$inferSelect;
export type InsertPoliticalParty = z.infer<typeof insertPoliticalPartySchema>;

export type MunicipalityAnnouncement = typeof municipalityAnnouncements.$inferSelect;
export type InsertMunicipalityAnnouncement = z.infer<typeof insertMunicipalityAnnouncementSchema>;
