import { pgTable, text, uuid, timestamp, integer, boolean, json } from 'drizzle-orm/pg-core';
import { createInsertSchema } from 'drizzle-zod';
import { z } from 'zod';

// Sponsored Ads Table
export const sponsoredAds = pgTable('sponsored_ads', {
  id: uuid('id').defaultRandom().primaryKey(),
  title: text('title').notNull(),
  content: text('content').notNull(),
  imageUrls: text('image_urls').array().default([]),
  targetUrl: text('target_url'),
  startDate: timestamp('start_date').notNull(),
  endDate: timestamp('end_date').notNull(),
  showAfterPosts: integer('show_after_posts').default(5),
  isPinned: boolean('is_pinned').default(false),
  status: text('status').notNull().default('active'), // active, paused, inactive
  adDisplayScope: text('ad_display_scope').notNull().default('herkes'), // herkes, il, ilce, ililce, splash
  city: text('city'),
  district: text('district'),
  cityId: uuid('city_id'),
  districtId: uuid('district_id'),
  impressions: integer('impressions').default(0),
  clicks: integer('clicks').default(0),
  createdAt: timestamp('created_at').defaultNow(),
  updatedAt: timestamp('updated_at').defaultNow(),
});

// Ad Interactions Table
export const adInteractions = pgTable('ad_interactions', {
  id: uuid('id').defaultRandom().primaryKey(),
  adId: uuid('ad_id').references(() => sponsoredAds.id, { onDelete: 'cascade' }).notNull(),
  userId: uuid('user_id'),
  interactionType: text('interaction_type').notNull(), // impression, click
  timestamp: timestamp('timestamp').defaultNow(),
  ipAddress: text('ip_address'),
  userAgent: text('user_agent'),
});

// Cities Table
export const cities = pgTable('cities', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: text('name').notNull(),
  code: text('code'),
  plateCode: text('plate_code'),
  createdAt: timestamp('created_at').defaultNow(),
});

// Districts Table
export const districts = pgTable('districts', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: text('name').notNull(),
  cityId: uuid('city_id').references(() => cities.id).notNull(),
  code: text('code'),
  createdAt: timestamp('created_at').defaultNow(),
});

// Users Table
export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  username: text('username').unique().notNull(),
  email: text('email').unique().notNull(),
  name: text('name'),
  cityId: uuid('city_id').references(() => cities.id),
  districtId: uuid('district_id').references(() => districts.id),
  createdAt: timestamp('created_at').defaultNow(),
  updatedAt: timestamp('updated_at').defaultNow(),
});

// Insert Schemas
export const insertSponsoredAdSchema = createInsertSchema(sponsoredAds).omit({
  id: true,
  createdAt: true,
  updatedAt: true,
  impressions: true,
  clicks: true,
});

export const insertAdInteractionSchema = createInsertSchema(adInteractions).omit({
  id: true,
  timestamp: true,
});

export const insertCitySchema = createInsertSchema(cities).omit({
  id: true,
  createdAt: true,
});

export const insertDistrictSchema = createInsertSchema(districts).omit({
  id: true,
  createdAt: true,
});

export const insertUserSchema = createInsertSchema(users).omit({
  id: true,
  createdAt: true,
  updatedAt: true,
});

// Types
export type SponsoredAd = typeof sponsoredAds.$inferSelect;
export type InsertSponsoredAd = z.infer<typeof insertSponsoredAdSchema>;

export type AdInteraction = typeof adInteractions.$inferSelect;
export type InsertAdInteraction = z.infer<typeof insertAdInteractionSchema>;

export type City = typeof cities.$inferSelect;
export type InsertCity = z.infer<typeof insertCitySchema>;

export type District = typeof districts.$inferSelect;
export type InsertDistrict = z.infer<typeof insertDistrictSchema>;

export type User = typeof users.$inferSelect;
export type InsertUser = z.infer<typeof insertUserSchema>;