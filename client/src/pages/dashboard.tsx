import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { DashboardCards } from "@/components/DashboardCards";
import { RecentActivities } from "@/components/RecentActivities";
import { GeographicDistribution } from "@/components/GeographicDistribution";
import { PoliticalDistribution } from "@/components/PoliticalDistribution";
import { PostCategories } from "@/components/PostCategories";

export default function Dashboard() {
  const { t } = useTranslation();
  
  return (
    <section>
      <div className="mb-6">
        <h2 className="text-2xl font-heading font-bold text-gray-800">{t('dashboard.title')}</h2>
        <p className="text-gray-500">{t('dashboard.subtitle')}</p>
      </div>

      {/* Stats Overview */}
      <DashboardCards />

      {/* Recent Activity & Geographic Distribution */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
        <RecentActivities />
        <GeographicDistribution />
      </div>

      {/* Political Party Distribution & Post Categories */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <PoliticalDistribution />
        <PostCategories />
      </div>
    </section>
  );
}
