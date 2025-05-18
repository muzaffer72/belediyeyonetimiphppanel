import { useTranslation } from "@/lib/i18n";
import { useState } from "react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Locale } from "@/lib/i18n";

interface HeaderProps {
  toggleSidebar: () => void;
}

export function Header({ toggleSidebar }: HeaderProps) {
  const { t, locale, setLocale } = useTranslation();
  const [showNotifications, setShowNotifications] = useState(false);
  
  const handleLocaleChange = (value: string) => {
    setLocale(value as Locale);
  };
  
  return (
    <header className="bg-white border-b border-gray-200 sticky top-0 z-30">
      <div className="flex justify-between items-center px-4 py-3">
        <div className="flex items-center">
          <button 
            onClick={toggleSidebar}
            className="p-2 rounded-md text-gray-500 hover:text-gray-900 focus:outline-none"
          >
            <span className="material-icons">menu</span>
          </button>
          <h1 className="ml-4 text-2xl font-heading font-semibold text-primary-800">{t('app.title')}</h1>
          <p className="ml-2 text-sm text-gray-500">{t('app.subtitle')}</p>
        </div>
        <div className="flex items-center space-x-4">
          <div className="relative">
            <button 
              className="p-2 rounded-full text-gray-500 hover:text-gray-900 hover:bg-gray-100 focus:outline-none"
              onClick={() => setShowNotifications(!showNotifications)}
            >
              <span className="material-icons">notifications</span>
              <span className="absolute top-1 right-1 w-2 h-2 bg-red-500 rounded-full"></span>
            </button>
            {/* Dropdown for notifications would go here */}
          </div>
          <div className="relative">
            <button className="flex items-center text-sm rounded-full focus:outline-none">
              <span className="sr-only">Open user menu</span>
              <img 
                className="h-8 w-8 rounded-full border border-gray-300" 
                src="https://images.unsplash.com/photo-1519244703995-f4e0f30006d5?ixlib=rb-1.2.1&auto=format&fit=facearea&facepad=2&w=256&h=256&q=80" 
                alt="Admin User"
              />
            </button>
          </div>
          <div className="hidden lg:flex items-center border-l pl-4 border-gray-200">
            <Select defaultValue={locale} onValueChange={handleLocaleChange}>
              <SelectTrigger className="w-[100px] h-8 text-sm">
                <SelectValue placeholder={t('app.language')} />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="tr">Türkçe</SelectItem>
                <SelectItem value="en">English</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </div>
    </header>
  );
}
