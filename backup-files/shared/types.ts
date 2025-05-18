export type Language = 'tr' | 'en';

export type PostType = 'complaint' | 'suggestion' | 'question' | 'thanks';

export interface DashboardStats {
  totalCities: number;
  activeUsers: number;
  totalPosts: number;
  pendingComplaints: number;
}

export interface ActivityItem {
  id: string;
  userId: string;
  username: string;
  userAvatar?: string;
  action: string;
  target?: string;
  timestamp: Date;
}

export interface PartyDistribution {
  id: string;
  name: string;
  logo: string;
  percentage: number;
  color: string;
}

export interface PostCategory {
  type: PostType;
  count: number;
  percentage: number;
  icon: string;
  color: string;
}

export interface ChartData {
  name: string;
  value: number;
}

export interface CityMapData {
  cityName: string;
  value: number;
  lat: number;
  lng: number;
}

export interface UserRole {
  value: string;
  label: string;
}

export interface StatusOption {
  value: string;
  label: string;
  color: string;
}

export interface PostTypeOption {
  value: PostType;
  label: string;
  icon: string;
  color: string;
}

export interface PaginationInfo {
  pageIndex: number;
  pageSize: number;
  pageCount: number;
  total: number;
}

export type SortDirection = 'asc' | 'desc';

export interface SortState {
  id: string;
  desc: boolean;
}

export interface FilterState {
  [key: string]: any;
}
