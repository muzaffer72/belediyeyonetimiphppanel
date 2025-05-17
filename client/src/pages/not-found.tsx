import { Link } from "wouter";
import { useTranslation } from "@/lib/i18n";
import { Button } from "@/components/ui/button";

export default function NotFound() {
  const { t } = useTranslation();
  
  return (
    <div className="flex flex-col items-center justify-center h-screen bg-gray-50">
      <div className="text-center max-w-md px-4">
        <h1 className="text-6xl font-extrabold text-gray-900 mb-6">404</h1>
        <div className="text-5xl font-bold text-primary-600 mb-4">{t("notfound.title")}</div>
        <p className="text-lg text-gray-600 mb-8">
          {t("notfound.message")}
        </p>
        <div className="flex flex-col space-y-3 sm:flex-row sm:space-y-0 sm:space-x-3 justify-center">
          <Button asChild>
            <Link href="/">
              <span className="material-icons mr-2">home</span>
              {t("notfound.home")}
            </Link>
          </Button>
          <Button variant="outline" asChild>
            <Link href="/dashboard">
              <span className="material-icons mr-2">dashboard</span>
              {t("notfound.dashboard")}
            </Link>
          </Button>
        </div>
      </div>
    </div>
  );
}