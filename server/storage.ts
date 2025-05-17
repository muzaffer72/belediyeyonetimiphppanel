import { v4 as uuidv4 } from "uuid";
import { db } from "../shared/supabase";
import { eq, and, or, ilike, desc, asc, sql, inArray } from "drizzle-orm";
import {
  cities,
  districts,
  users,
  userBans,
  posts,
  comments,
  likes,
  featuredPosts,
  politicalParties,
  municipalityAnnouncements,
  type City,
  type InsertCity,
  type District,
  type InsertDistrict,
  type User,
  type InsertUser,
  type UserBan,
  type InsertUserBan,
  type Post,
  type InsertPost,
  type Comment,
  type InsertComment,
  type Like,
  type InsertLike,
  type FeaturedPost,
  type InsertFeaturedPost,
  type PoliticalParty,
  type InsertPoliticalParty,
  type MunicipalityAnnouncement,
  type InsertMunicipalityAnnouncement,
} from "../shared/schema";
import { PaginationInfo, SortState, FilterState } from "../shared/types";

export interface StorageOptions {
  pagination?: { page: number; pageSize: number };
  sort?: SortState[];
  filters?: FilterState;
}

export interface PaginatedResult<T> {
  data: T[];
  pagination: PaginationInfo;
}

export interface IStorage {
  // City operations
  getCities(options?: StorageOptions): Promise<PaginatedResult<City>>;
  getCityById(id: string): Promise<City | undefined>;
  createCity(city: InsertCity): Promise<City>;
  updateCity(id: string, city: Partial<InsertCity>): Promise<City | undefined>;
  deleteCity(id: string): Promise<boolean>;
  
  // District operations
  getDistricts(options?: StorageOptions): Promise<PaginatedResult<District>>;
  getDistrictById(id: string): Promise<District | undefined>;
  getDistrictsByCityId(cityId: string): Promise<District[]>;
  createDistrict(district: InsertDistrict): Promise<District>;
  updateDistrict(id: string, district: Partial<InsertDistrict>): Promise<District | undefined>;
  deleteDistrict(id: string): Promise<boolean>;
  
  // User operations
  getUsers(options?: StorageOptions): Promise<PaginatedResult<User>>;
  getUserById(id: string): Promise<User | undefined>;
  getUserByUsername(username: string): Promise<User | undefined>;
  getUserByEmail(email: string): Promise<User | undefined>;
  createUser(user: InsertUser): Promise<User>;
  updateUser(id: string, user: Partial<InsertUser>): Promise<User | undefined>;
  deleteUser(id: string): Promise<boolean>;
  
  // User ban operations
  getUserBans(options?: StorageOptions): Promise<PaginatedResult<UserBan>>;
  getUserBanById(id: string): Promise<UserBan | undefined>;
  getUserBansByUserId(userId: string): Promise<UserBan[]>;
  createUserBan(userBan: InsertUserBan): Promise<UserBan>;
  updateUserBan(id: string, userBan: Partial<InsertUserBan>): Promise<UserBan | undefined>;
  deleteUserBan(id: string): Promise<boolean>;
  
  // Post operations
  getPosts(options?: StorageOptions): Promise<PaginatedResult<Post>>;
  getPostById(id: string): Promise<Post | undefined>;
  getPostsByUserId(userId: string): Promise<Post[]>;
  createPost(post: InsertPost): Promise<Post>;
  updatePost(id: string, post: Partial<InsertPost>): Promise<Post | undefined>;
  deletePost(id: string): Promise<boolean>;
  getFeaturedPosts(): Promise<Post[]>;
  togglePostFeatured(id: string, userId: string): Promise<boolean>;
  
  // Comment operations
  getComments(options?: StorageOptions): Promise<PaginatedResult<Comment>>;
  getCommentById(id: string): Promise<Comment | undefined>;
  getCommentsByPostId(postId: string): Promise<Comment[]>;
  createComment(comment: InsertComment): Promise<Comment>;
  updateComment(id: string, comment: Partial<InsertComment>): Promise<Comment | undefined>;
  deleteComment(id: string): Promise<boolean>;
  
  // Like operations
  getLikesByPostId(postId: string): Promise<Like[]>;
  createLike(like: InsertLike): Promise<Like>;
  deleteLike(id: string): Promise<boolean>;
  hasUserLikedPost(userId: string, postId: string): Promise<boolean>;
  
  // Political party operations
  getPoliticalParties(options?: StorageOptions): Promise<PaginatedResult<PoliticalParty>>;
  getPoliticalPartyById(id: string): Promise<PoliticalParty | undefined>;
  createPoliticalParty(party: InsertPoliticalParty): Promise<PoliticalParty>;
  updatePoliticalParty(id: string, party: Partial<InsertPoliticalParty>): Promise<PoliticalParty | undefined>;
  deletePoliticalParty(id: string): Promise<boolean>;
  
  // Municipality announcement operations
  getMunicipalityAnnouncements(options?: StorageOptions): Promise<PaginatedResult<MunicipalityAnnouncement>>;
  getMunicipalityAnnouncementById(id: string): Promise<MunicipalityAnnouncement | undefined>;
  getMunicipalityAnnouncementsByMunicipalityId(municipalityId: string): Promise<MunicipalityAnnouncement[]>;
  createMunicipalityAnnouncement(announcement: InsertMunicipalityAnnouncement): Promise<MunicipalityAnnouncement>;
  updateMunicipalityAnnouncement(id: string, announcement: Partial<InsertMunicipalityAnnouncement>): Promise<MunicipalityAnnouncement | undefined>;
  deleteMunicipalityAnnouncement(id: string): Promise<boolean>;
  
  // Dashboard operations
  getDashboardStats(): Promise<{
    totalCities: number;
    activeUsers: number;
    totalPosts: number;
    pendingComplaints: number;
  }>;
  getRecentActivities(limit?: number): Promise<any[]>;
  getPostCategoriesDistribution(): Promise<any[]>;
  getPoliticalPartyDistribution(): Promise<any[]>;
}

export class SupabaseStorage implements IStorage {
  // Apply pagination, sorting, and filtering
  private applyOptions<T>(query: any, options?: StorageOptions): any {
    let modifiedQuery = query;
    
    // Apply filters if provided
    if (options?.filters) {
      for (const [key, value] of Object.entries(options.filters)) {
        if (value !== undefined && value !== null && value !== '') {
          if (typeof value === 'string') {
            modifiedQuery = modifiedQuery.where(ilike(sql.identifier(key), `%${value}%`));
          } else {
            modifiedQuery = modifiedQuery.where(eq(sql.identifier(key), value));
          }
        }
      }
    }
    
    // Apply sorting if provided
    if (options?.sort && options.sort.length > 0) {
      for (const sortItem of options.sort) {
        const order = sortItem.desc ? desc : asc;
        modifiedQuery = modifiedQuery.orderBy(order(sql.identifier(sortItem.id)));
      }
    }
    
    // Calculate total count (before pagination)
    const countQuery = modifiedQuery.$.clone().count();
    
    // Apply pagination if provided
    if (options?.pagination) {
      const { page, pageSize } = options.pagination;
      const offset = (page - 1) * pageSize;
      modifiedQuery = modifiedQuery.limit(pageSize).offset(offset);
    }
    
    return { dataQuery: modifiedQuery, countQuery };
  }

  // City operations
  async getCities(options?: StorageOptions): Promise<PaginatedResult<City>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(cities), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getCityById(id: string): Promise<City | undefined> {
    const result = await db.select().from(cities).where(eq(cities.id, id)).limit(1);
    return result[0];
  }

  async createCity(city: InsertCity): Promise<City> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(cities).values({
      id,
      ...city,
      createdAt: now,
      updatedAt: now
    }).returning();
    return result[0];
  }

  async updateCity(id: string, city: Partial<InsertCity>): Promise<City | undefined> {
    const now = new Date();
    const result = await db.update(cities)
      .set({ ...city, updatedAt: now })
      .where(eq(cities.id, id))
      .returning();
    return result[0];
  }

  async deleteCity(id: string): Promise<boolean> {
    const result = await db.delete(cities).where(eq(cities.id, id)).returning({ id: cities.id });
    return result.length > 0;
  }

  // District operations
  async getDistricts(options?: StorageOptions): Promise<PaginatedResult<District>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(districts), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getDistrictById(id: string): Promise<District | undefined> {
    const result = await db.select().from(districts).where(eq(districts.id, id)).limit(1);
    return result[0];
  }

  async getDistrictsByCityId(cityId: string): Promise<District[]> {
    return db.select().from(districts).where(eq(districts.cityId, cityId));
  }

  async createDistrict(district: InsertDistrict): Promise<District> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(districts).values({
      id,
      ...district,
      createdAt: now,
      updatedAt: now
    }).returning();
    return result[0];
  }

  async updateDistrict(id: string, district: Partial<InsertDistrict>): Promise<District | undefined> {
    const now = new Date();
    const result = await db.update(districts)
      .set({ ...district, updatedAt: now })
      .where(eq(districts.id, id))
      .returning();
    return result[0];
  }

  async deleteDistrict(id: string): Promise<boolean> {
    const result = await db.delete(districts).where(eq(districts.id, id)).returning({ id: districts.id });
    return result.length > 0;
  }

  // User operations
  async getUsers(options?: StorageOptions): Promise<PaginatedResult<User>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(users), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getUserById(id: string): Promise<User | undefined> {
    const result = await db.select().from(users).where(eq(users.id, id)).limit(1);
    return result[0];
  }

  async getUserByUsername(username: string): Promise<User | undefined> {
    const result = await db.select().from(users).where(eq(users.username, username)).limit(1);
    return result[0];
  }

  async getUserByEmail(email: string): Promise<User | undefined> {
    const result = await db.select().from(users).where(eq(users.email, email)).limit(1);
    return result[0];
  }

  async createUser(user: InsertUser): Promise<User> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(users).values({
      id,
      ...user,
      createdAt: now,
      updatedAt: now
    }).returning();
    return result[0];
  }

  async updateUser(id: string, user: Partial<InsertUser>): Promise<User | undefined> {
    const now = new Date();
    const result = await db.update(users)
      .set({ ...user, updatedAt: now })
      .where(eq(users.id, id))
      .returning();
    return result[0];
  }

  async deleteUser(id: string): Promise<boolean> {
    const result = await db.delete(users).where(eq(users.id, id)).returning({ id: users.id });
    return result.length > 0;
  }

  // User ban operations
  async getUserBans(options?: StorageOptions): Promise<PaginatedResult<UserBan>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(userBans), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getUserBanById(id: string): Promise<UserBan | undefined> {
    const result = await db.select().from(userBans).where(eq(userBans.id, id)).limit(1);
    return result[0];
  }

  async getUserBansByUserId(userId: string): Promise<UserBan[]> {
    return db.select().from(userBans).where(eq(userBans.userId, userId));
  }

  async createUserBan(userBan: InsertUserBan): Promise<UserBan> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(userBans).values({
      id,
      ...userBan,
      createdAt: now,
      updatedAt: now
    }).returning();
    return result[0];
  }

  async updateUserBan(id: string, userBan: Partial<InsertUserBan>): Promise<UserBan | undefined> {
    const now = new Date();
    const result = await db.update(userBans)
      .set({ ...userBan, updatedAt: now })
      .where(eq(userBans.id, id))
      .returning();
    return result[0];
  }

  async deleteUserBan(id: string): Promise<boolean> {
    const result = await db.delete(userBans).where(eq(userBans.id, id)).returning({ id: userBans.id });
    return result.length > 0;
  }

  // Post operations
  async getPosts(options?: StorageOptions): Promise<PaginatedResult<Post>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(posts), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getPostById(id: string): Promise<Post | undefined> {
    const result = await db.select().from(posts).where(eq(posts.id, id)).limit(1);
    return result[0];
  }

  async getPostsByUserId(userId: string): Promise<Post[]> {
    return db.select().from(posts).where(eq(posts.userId, userId));
  }

  async createPost(post: InsertPost): Promise<Post> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(posts).values({
      id,
      ...post,
      createdAt: now,
      updatedAt: now
    }).returning();
    return result[0];
  }

  async updatePost(id: string, post: Partial<InsertPost>): Promise<Post | undefined> {
    const now = new Date();
    const result = await db.update(posts)
      .set({ ...post, updatedAt: now })
      .where(eq(posts.id, id))
      .returning();
    return result[0];
  }

  async deletePost(id: string): Promise<boolean> {
    const result = await db.delete(posts).where(eq(posts.id, id)).returning({ id: posts.id });
    return result.length > 0;
  }

  async getFeaturedPosts(): Promise<Post[]> {
    const featuredIds = await db.select({ postId: featuredPosts.postId }).from(featuredPosts);
    const postIds = featuredIds.map(fp => fp.postId);
    
    if (postIds.length === 0) {
      return [];
    }
    
    return db.select().from(posts).where(inArray(posts.id, postIds));
  }

  async togglePostFeatured(id: string, userId: string): Promise<boolean> {
    const post = await this.getPostById(id);
    if (!post) return false;
    
    const existingFeatured = await db.select()
      .from(featuredPosts)
      .where(eq(featuredPosts.postId, id))
      .limit(1);
    
    if (existingFeatured.length > 0) {
      // Remove from featured
      await db.delete(featuredPosts).where(eq(featuredPosts.postId, id));
      await this.updatePost(id, { isFeatured: false });
      return true;
    } else {
      // Add to featured
      const featuredId = String(Date.now()); // Simple ID generation
      await db.insert(featuredPosts).values({
        id: featuredId,
        postId: id,
        userId,
        createdAt: new Date()
      });
      await this.updatePost(id, { isFeatured: true, featuredCount: (post.featuredCount || 0) + 1 });
      return true;
    }
  }

  // Comment operations
  async getComments(options?: StorageOptions): Promise<PaginatedResult<Comment>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(comments), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getCommentById(id: string): Promise<Comment | undefined> {
    const result = await db.select().from(comments).where(eq(comments.id, id)).limit(1);
    return result[0];
  }

  async getCommentsByPostId(postId: string): Promise<Comment[]> {
    return db.select().from(comments).where(eq(comments.postId, postId));
  }

  async createComment(comment: InsertComment): Promise<Comment> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(comments).values({
      id,
      ...comment,
      createdAt: now,
      updatedAt: now
    }).returning();
    
    // Update comment count on the post
    const post = await this.getPostById(comment.postId);
    if (post) {
      await this.updatePost(post.id, { commentCount: (post.commentCount || 0) + 1 });
    }
    
    return result[0];
  }

  async updateComment(id: string, comment: Partial<InsertComment>): Promise<Comment | undefined> {
    const now = new Date();
    const result = await db.update(comments)
      .set({ ...comment, updatedAt: now })
      .where(eq(comments.id, id))
      .returning();
    return result[0];
  }

  async deleteComment(id: string): Promise<boolean> {
    const comment = await this.getCommentById(id);
    if (!comment) return false;
    
    const result = await db.delete(comments).where(eq(comments.id, id)).returning({ id: comments.id });
    
    // Update comment count on the post
    const post = await this.getPostById(comment.postId);
    if (post && post.commentCount && post.commentCount > 0) {
      await this.updatePost(post.id, { commentCount: post.commentCount - 1 });
    }
    
    return result.length > 0;
  }

  // Like operations
  async getLikesByPostId(postId: string): Promise<Like[]> {
    return db.select().from(likes).where(eq(likes.postId, postId));
  }

  async createLike(like: InsertLike): Promise<Like> {
    // Check if user already liked the post
    const existingLike = await db.select()
      .from(likes)
      .where(and(eq(likes.postId, like.postId), eq(likes.userId, like.userId)))
      .limit(1);
    
    if (existingLike.length > 0) {
      return existingLike[0];
    }
    
    const id = uuidv4();
    const result = await db.insert(likes).values({
      id,
      ...like,
      createdAt: new Date()
    }).returning();
    
    // Update like count on the post
    const post = await this.getPostById(like.postId);
    if (post) {
      await this.updatePost(post.id, { likeCount: (post.likeCount || 0) + 1 });
    }
    
    return result[0];
  }

  async deleteLike(id: string): Promise<boolean> {
    const like = await db.select().from(likes).where(eq(likes.id, id)).limit(1);
    if (like.length === 0) return false;
    
    const result = await db.delete(likes).where(eq(likes.id, id)).returning({ id: likes.id });
    
    // Update like count on the post
    const post = await this.getPostById(like[0].postId);
    if (post && post.likeCount && post.likeCount > 0) {
      await this.updatePost(post.id, { likeCount: post.likeCount - 1 });
    }
    
    return result.length > 0;
  }

  async hasUserLikedPost(userId: string, postId: string): Promise<boolean> {
    const like = await db.select()
      .from(likes)
      .where(and(eq(likes.postId, postId), eq(likes.userId, userId)))
      .limit(1);
    
    return like.length > 0;
  }

  // Political party operations
  async getPoliticalParties(options?: StorageOptions): Promise<PaginatedResult<PoliticalParty>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(politicalParties), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getPoliticalPartyById(id: string): Promise<PoliticalParty | undefined> {
    const result = await db.select().from(politicalParties).where(eq(politicalParties.id, id)).limit(1);
    return result[0];
  }

  async createPoliticalParty(party: InsertPoliticalParty): Promise<PoliticalParty> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(politicalParties).values({
      id,
      ...party,
      lastUpdated: now,
      createdAt: now
    }).returning();
    return result[0];
  }

  async updatePoliticalParty(id: string, party: Partial<InsertPoliticalParty>): Promise<PoliticalParty | undefined> {
    const now = new Date();
    const result = await db.update(politicalParties)
      .set({ ...party, lastUpdated: now })
      .where(eq(politicalParties.id, id))
      .returning();
    return result[0];
  }

  async deletePoliticalParty(id: string): Promise<boolean> {
    const result = await db.delete(politicalParties).where(eq(politicalParties.id, id)).returning({ id: politicalParties.id });
    return result.length > 0;
  }

  // Municipality announcement operations
  async getMunicipalityAnnouncements(options?: StorageOptions): Promise<PaginatedResult<MunicipalityAnnouncement>> {
    const { dataQuery, countQuery } = this.applyOptions(db.select().from(municipalityAnnouncements), options);
    
    const [data, countResult] = await Promise.all([
      dataQuery,
      db.execute(countQuery)
    ]);
    
    const total = Number(countResult[0]?.count || 0);
    const pageSize = options?.pagination?.pageSize || total;
    const pageCount = Math.ceil(total / pageSize);
    
    return {
      data,
      pagination: {
        pageIndex: options?.pagination?.page ? options.pagination.page - 1 : 0,
        pageSize,
        pageCount,
        total
      }
    };
  }

  async getMunicipalityAnnouncementById(id: string): Promise<MunicipalityAnnouncement | undefined> {
    const result = await db.select().from(municipalityAnnouncements).where(eq(municipalityAnnouncements.id, id)).limit(1);
    return result[0];
  }

  async getMunicipalityAnnouncementsByMunicipalityId(municipalityId: string): Promise<MunicipalityAnnouncement[]> {
    return db.select()
      .from(municipalityAnnouncements)
      .where(eq(municipalityAnnouncements.municipalityId, municipalityId));
  }

  async createMunicipalityAnnouncement(announcement: InsertMunicipalityAnnouncement): Promise<MunicipalityAnnouncement> {
    const id = uuidv4();
    const now = new Date();
    const result = await db.insert(municipalityAnnouncements).values({
      id,
      ...announcement,
      createdAt: now,
      updatedAt: now
    }).returning();
    return result[0];
  }

  async updateMunicipalityAnnouncement(id: string, announcement: Partial<InsertMunicipalityAnnouncement>): Promise<MunicipalityAnnouncement | undefined> {
    const now = new Date();
    const result = await db.update(municipalityAnnouncements)
      .set({ ...announcement, updatedAt: now })
      .where(eq(municipalityAnnouncements.id, id))
      .returning();
    return result[0];
  }

  async deleteMunicipalityAnnouncement(id: string): Promise<boolean> {
    const result = await db.delete(municipalityAnnouncements)
      .where(eq(municipalityAnnouncements.id, id))
      .returning({ id: municipalityAnnouncements.id });
    return result.length > 0;
  }

  // Dashboard operations
  async getDashboardStats(): Promise<{
    totalCities: number;
    activeUsers: number;
    totalPosts: number;
    pendingComplaints: number;
  }> {
    const [citiesCount, usersCount, postsCount, pendingComplaintsCount] = await Promise.all([
      db.select({ count: sql<number>`count(*)` }).from(cities),
      db.select({ count: sql<number>`count(*)` }).from(users),
      db.select({ count: sql<number>`count(*)` }).from(posts),
      db.select({ count: sql<number>`count(*)` })
        .from(posts)
        .where(and(eq(posts.type, 'complaint'), eq(posts.isResolved, false)))
    ]);

    return {
      totalCities: citiesCount[0]?.count || 0,
      activeUsers: usersCount[0]?.count || 0,
      totalPosts: postsCount[0]?.count || 0,
      pendingComplaints: pendingComplaintsCount[0]?.count || 0,
    };
  }

  async getRecentActivities(limit: number = 5): Promise<any[]> {
    // For recent activities, we'll combine recent posts, comments, and user registrations
    const [recentPosts, recentComments, recentUsers] = await Promise.all([
      db.select({
        id: posts.id,
        userId: posts.userId,
        type: sql<string>`'post'`,
        title: posts.title,
        createdAt: posts.createdAt,
      }).from(posts).orderBy(desc(posts.createdAt)).limit(limit),
      
      db.select({
        id: comments.id,
        userId: comments.userId,
        type: sql<string>`'comment'`,
        postId: comments.postId,
        createdAt: comments.createdAt,
      }).from(comments).orderBy(desc(comments.createdAt)).limit(limit),
      
      db.select({
        id: users.id,
        userId: users.id,
        type: sql<string>`'user'`,
        username: users.username,
        createdAt: users.createdAt,
      }).from(users).orderBy(desc(users.createdAt)).limit(limit)
    ]);
    
    // Combine and sort by createdAt
    const combined = [...recentPosts, ...recentComments, ...recentUsers]
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
      .slice(0, limit);
    
    // Fetch user details for each activity
    const activities = await Promise.all(
      combined.map(async (activity) => {
        const user = await this.getUserById(activity.userId);
        
        let details: any = {
          id: activity.id,
          user: {
            id: user?.id,
            username: user?.username,
            profileImageUrl: user?.profileImageUrl
          },
          timestamp: activity.createdAt,
          type: activity.type
        };
        
        if (activity.type === 'post') {
          details.content = activity.title;
          details.action = 'added a new post';
        } else if (activity.type === 'comment') {
          const post = await this.getPostById(activity.postId);
          details.postTitle = post?.title;
          details.postId = post?.id;
          details.action = 'commented on a post';
        } else if (activity.type === 'user') {
          details.action = 'joined the platform';
        }
        
        return details;
      })
    );
    
    return activities;
  }

  async getPostCategoriesDistribution(): Promise<any[]> {
    const categoryCounts = await db.select({
      category: posts.category,
      count: sql<number>`count(*)`
    })
    .from(posts)
    .groupBy(posts.category);
    
    const totalPosts = await db.select({
      count: sql<number>`count(*)`
    }).from(posts);
    
    const total = totalPosts[0]?.count || 0;
    
    return categoryCounts.map(category => ({
      category: category.category || 'uncategorized',
      count: category.count,
      percentage: Math.round((category.count / total) * 100)
    }));
  }

  async getPoliticalPartyDistribution(): Promise<any[]> {
    // Get count of cities by political party
    const cityCounts = await db.select({
      partyId: cities.politicalPartyId,
      count: sql<number>`count(*)`
    })
    .from(cities)
    .where(sql`${cities.politicalPartyId} is not null`)
    .groupBy(cities.politicalPartyId);
    
    const totalCities = await db.select({
      count: sql<number>`count(*)`
    }).from(cities);
    
    const total = totalCities[0]?.count || 0;
    
    // Get party details for each count
    const distribution = await Promise.all(
      cityCounts.map(async (count) => {
        const party = await this.getPoliticalPartyById(count.partyId);
        return {
          id: party?.id,
          name: party?.name || 'Unknown',
          logoUrl: party?.logoUrl,
          score: party?.score,
          count: count.count,
          percentage: Math.round((count.count / total) * 100)
        };
      })
    );
    
    // Sort by count descending
    return distribution.sort((a, b) => b.count - a.count);
  }
}

export const storage = new SupabaseStorage();
