import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { 
  sponsoredAds, 
  adInteractions, 
  cities, 
  districts, 
  users,
  type SponsoredAd,
  type InsertSponsoredAd,
  type AdInteraction,
  type InsertAdInteraction,
  type City,
  type District,
  type User
} from '@shared/schema';
import { eq, desc, and, gte, lte, sql, count } from 'drizzle-orm';

const connectionString = process.env.DATABASE_URL!;
const client = postgres(connectionString);
const db = drizzle(client);

export interface IStorage {
  // Sponsored Ads
  createSponsoredAd(ad: InsertSponsoredAd): Promise<SponsoredAd>;
  getSponsoredAds(filters?: { 
    scope?: string; 
    status?: string; 
    city?: string; 
    district?: string; 
  }): Promise<SponsoredAd[]>;
  getSponsoredAdById(id: string): Promise<SponsoredAd | null>;
  updateSponsoredAd(id: string, updates: Partial<InsertSponsoredAd>): Promise<SponsoredAd>;
  deleteSponsoredAd(id: string): Promise<void>;
  
  // Splash Screen Ads - En önemli özellik
  getSplashScreenAds(): Promise<SponsoredAd[]>;
  getActiveAdsByScope(scope: string, cityId?: string, districtId?: string): Promise<SponsoredAd[]>;
  
  // Ad Interactions
  recordAdInteraction(interaction: InsertAdInteraction): Promise<AdInteraction>;
  getAdAnalytics(adId: string): Promise<{
    impressions: number;
    clicks: number;
    ctr: number;
    topUsers: any[];
    dailyStats: any[];
  }>;
  
  // Geography
  getCities(): Promise<City[]>;
  getDistricts(cityId?: string): Promise<District[]>;
  
  // Users
  getUsers(): Promise<User[]>;
  getUserById(id: string): Promise<User | null>;
}

export class DatabaseStorage implements IStorage {
  
  async createSponsoredAd(ad: InsertSponsoredAd): Promise<SponsoredAd> {
    const [newAd] = await db.insert(sponsoredAds).values(ad).returning();
    return newAd;
  }

  async getSponsoredAds(filters?: { 
    scope?: string; 
    status?: string; 
    city?: string; 
    district?: string; 
  }): Promise<SponsoredAd[]> {
    let query = db.select().from(sponsoredAds);
    
    if (filters) {
      const conditions = [];
      if (filters.scope) conditions.push(eq(sponsoredAds.adDisplayScope, filters.scope));
      if (filters.status) conditions.push(eq(sponsoredAds.status, filters.status));
      if (filters.city) conditions.push(eq(sponsoredAds.city, filters.city));
      if (filters.district) conditions.push(eq(sponsoredAds.district, filters.district));
      
      if (conditions.length > 0) {
        query = query.where(and(...conditions));
      }
    }
    
    return await query.orderBy(desc(sponsoredAds.createdAt));
  }

  async getSponsoredAdById(id: string): Promise<SponsoredAd | null> {
    const [ad] = await db.select().from(sponsoredAds).where(eq(sponsoredAds.id, id));
    return ad || null;
  }

  async updateSponsoredAd(id: string, updates: Partial<InsertSponsoredAd>): Promise<SponsoredAd> {
    const [updatedAd] = await db
      .update(sponsoredAds)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(sponsoredAds.id, id))
      .returning();
    return updatedAd;
  }

  async deleteSponsoredAd(id: string): Promise<void> {
    await db.delete(sponsoredAds).where(eq(sponsoredAds.id, id));
  }

  // Splash Screen Ads - Açılış sayfası reklamları için özel metod
  async getSplashScreenAds(): Promise<SponsoredAd[]> {
    const now = new Date();
    return await db
      .select()
      .from(sponsoredAds)
      .where(
        and(
          eq(sponsoredAds.adDisplayScope, 'splash'),
          eq(sponsoredAds.status, 'active'),
          lte(sponsoredAds.startDate, now),
          gte(sponsoredAds.endDate, now)
        )
      )
      .orderBy(desc(sponsoredAds.isPinned), desc(sponsoredAds.createdAt));
  }

  async getActiveAdsByScope(scope: string, cityId?: string, districtId?: string): Promise<SponsoredAd[]> {
    const now = new Date();
    let conditions = [
      eq(sponsoredAds.adDisplayScope, scope),
      eq(sponsoredAds.status, 'active'),
      lte(sponsoredAds.startDate, now),
      gte(sponsoredAds.endDate, now)
    ];

    if (scope === 'il' && cityId) {
      conditions.push(eq(sponsoredAds.cityId, cityId));
    }
    if (scope === 'ilce' && districtId) {
      conditions.push(eq(sponsoredAds.districtId, districtId));
    }
    if (scope === 'ililce' && cityId && districtId) {
      conditions.push(eq(sponsoredAds.cityId, cityId));
      conditions.push(eq(sponsoredAds.districtId, districtId));
    }

    return await db
      .select()
      .from(sponsoredAds)
      .where(and(...conditions))
      .orderBy(desc(sponsoredAds.isPinned), desc(sponsoredAds.createdAt));
  }

  async recordAdInteraction(interaction: InsertAdInteraction): Promise<AdInteraction> {
    const [newInteraction] = await db.insert(adInteractions).values(interaction).returning();
    
    // Ad stats güncelle
    if (interaction.interactionType === 'impression') {
      await db
        .update(sponsoredAds)
        .set({ impressions: sql`impressions + 1` })
        .where(eq(sponsoredAds.id, interaction.adId));
    } else if (interaction.interactionType === 'click') {
      await db
        .update(sponsoredAds)
        .set({ clicks: sql`clicks + 1` })
        .where(eq(sponsoredAds.id, interaction.adId));
    }
    
    return newInteraction;
  }

  async getAdAnalytics(adId: string): Promise<{
    impressions: number;
    clicks: number;
    ctr: number;
    topUsers: any[];
    dailyStats: any[];
  }> {
    // Temel istatistikler
    const [ad] = await db.select().from(sponsoredAds).where(eq(sponsoredAds.id, adId));
    
    const impressions = ad?.impressions || 0;
    const clicks = ad?.clicks || 0;
    const ctr = impressions > 0 ? (clicks / impressions) * 100 : 0;

    // Günlük istatistikler
    const dailyStats = await db
      .select({
        date: sql`DATE(timestamp)`.as('date'),
        impressions: count(sql`CASE WHEN interaction_type = 'impression' THEN 1 END`).as('impressions'),
        clicks: count(sql`CASE WHEN interaction_type = 'click' THEN 1 END`).as('clicks')
      })
      .from(adInteractions)
      .where(eq(adInteractions.adId, adId))
      .groupBy(sql`DATE(timestamp)`)
      .orderBy(sql`DATE(timestamp) DESC`)
      .limit(30);

    // En çok etkileşim yapan kullanıcılar
    const topUsers = await db
      .select({
        userId: adInteractions.userId,
        totalInteractions: count()
      })
      .from(adInteractions)
      .where(eq(adInteractions.adId, adId))
      .groupBy(adInteractions.userId)
      .orderBy(desc(count()))
      .limit(10);

    return {
      impressions,
      clicks,
      ctr,
      topUsers,
      dailyStats
    };
  }

  async getCities(): Promise<City[]> {
    return await db.select().from(cities).orderBy(cities.name);
  }

  async getDistricts(cityId?: string): Promise<District[]> {
    let query = db.select().from(districts);
    
    if (cityId) {
      query = query.where(eq(districts.cityId, cityId));
    }
    
    return await query.orderBy(districts.name);
  }

  async getUsers(): Promise<User[]> {
    return await db.select().from(users).orderBy(desc(users.createdAt));
  }

  async getUserById(id: string): Promise<User | null> {
    const [user] = await db.select().from(users).where(eq(users.id, id));
    return user || null;
  }
}

export const storage = new DatabaseStorage();