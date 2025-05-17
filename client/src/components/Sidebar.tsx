import { Link, useLocation } from "wouter";
import { useTranslation } from "@/lib/i18n";
import { cn } from "@/lib/utils";

interface SidebarProps {
  collapsed: boolean;
}

export function Sidebar({ collapsed }: SidebarProps) {
  const [location] = useLocation();
  const { t } = useTranslation();
  
  const isActive = (path: string) => {
    return location === path;
  };
  
  const navItems = [
    { path: "/", icon: "dashboard", label: "sidebar.dashboard" },
    { path: "/cities", icon: "location_city", label: "sidebar.cities" },
    { path: "/districts", icon: "apartment", label: "sidebar.districts" },
    { path: "/posts", icon: "article", label: "sidebar.posts" },
    { path: "/comments", icon: "comment", label: "sidebar.comments" },
    { path: "/announcements", icon: "campaign", label: "sidebar.announcements" },
    { path: "/users", icon: "people", label: "sidebar.users" },
    { path: "/parties", icon: "gavel", label: "sidebar.parties" },
  ];
  
  const bottomNavItems = [
    { path: "/settings", icon: "settings", label: "sidebar.settings" },
    { path: "/login", icon: "logout", label: "sidebar.logout" },
  ];
  
  return (
    <aside 
      className={cn(
        "bg-primary-800 text-white flex flex-col z-20 transition-all duration-300",
        collapsed ? "w-20" : "w-64"
      )}
    >
      <div className="flex flex-col h-full">
        <div className="p-4">
          {!collapsed ? (
            <div className="flex items-center justify-center">
              <img 
                src="https://images.unsplash.com/photo-1614028674026-a65e31bfd27c?ixlib=rb-1.2.1&auto=format&fit=crop&w=100&h=100&q=80" 
                alt="Municipality Admin" 
                className="w-12 h-12 rounded-full border-2 border-white"
              />
              <div className="ml-3">
                <p className="font-medium">{t('app.subtitle')}</p>
                <p className="text-xs text-primary-200">Admin</p>
              </div>
            </div>
          ) : (
            <div className="flex justify-center">
              <img 
                src="https://images.unsplash.com/photo-1614028674026-a65e31bfd27c?ixlib=rb-1.2.1&auto=format&fit=crop&w=60&h=60&q=80" 
                alt="Municipality Admin" 
                className="w-10 h-10 rounded-full border-2 border-white"
              />
            </div>
          )}
        </div>
        
        <nav className="flex-1 px-2 pb-4 space-y-1 overflow-y-auto">
          {navItems.map((item) => (
            <Link 
              key={item.path}
              href={item.path}
              className={cn(
                "flex items-center px-3 py-2 text-sm font-medium rounded-md",
                isActive(item.path) 
                  ? "bg-primary-900 text-white" 
                  : "text-primary-100 hover:bg-primary-700"
              )}
            >
              <span className="material-icons mr-3 text-primary-200">{item.icon}</span>
              {!collapsed && <span>{t(item.label)}</span>}
            </Link>
          ))}
          
          <div className="pt-4 mt-4 border-t border-primary-700">
            {bottomNavItems.map((item) => (
              <Link 
                key={item.path}
                href={item.path}
                className={cn(
                  "flex items-center px-3 py-2 text-sm font-medium rounded-md",
                  isActive(item.path) 
                    ? "bg-primary-900 text-white" 
                    : "text-primary-100 hover:bg-primary-700"
                )}
              >
                <span className="material-icons mr-3 text-primary-200">{item.icon}</span>
                {!collapsed && <span>{t(item.label)}</span>}
              </Link>
            ))}
          </div>
        </nav>
      </div>
    </aside>
  );
}
