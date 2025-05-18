import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";

export default function Settings() {
  const { t, locale, setLocale } = useTranslation();
  const { toast } = useToast();

  const [general, setGeneral] = useState({
    appName: "BİMER",
    appSubtitle: "Belediye Yönetim Paneli",
    logoUrl: "",
    pageSize: "10",
  });

  const [notifications, setNotifications] = useState({
    emailNotifications: true,
    pushNotifications: false,
    notifyOnNewPost: true,
    notifyOnNewComment: true,
    notifyOnUserRegistration: false,
  });

  const [appearance, setAppearance] = useState({
    theme: "light",
    language: locale,
  });

  const [security, setSecurity] = useState({
    requireEmailVerification: true,
    twoFactorAuth: false,
    sessionTimeout: "60",
    passwordMinLength: "8",
  });

  const handleSaveGeneral = () => {
    // In a real app, you would make an API call here
    toast({
      title: t("notifications.success"),
      description: t("notifications.saved"),
    });
  };

  const handleSaveNotifications = () => {
    // In a real app, you would make an API call here
    toast({
      title: t("notifications.success"),
      description: t("notifications.saved"),
    });
  };

  const handleSaveAppearance = () => {
    // Update language if changed
    if (appearance.language !== locale) {
      setLocale(appearance.language as 'tr' | 'en');
    }

    // In a real app, you would make an API call here
    toast({
      title: t("notifications.success"),
      description: t("notifications.saved"),
    });
  };

  const handleSaveSecurity = () => {
    // In a real app, you would make an API call here
    toast({
      title: t("notifications.success"),
      description: t("notifications.saved"),
    });
  };

  return (
    <section>
      <div className="mb-6">
        <h2 className="text-2xl font-heading font-bold text-gray-800">{t("settings.title")}</h2>
        <p className="text-gray-500">{t("settings.subtitle")}</p>
      </div>

      <Tabs defaultValue="general" className="space-y-4">
        <TabsList className="grid grid-cols-4 w-full max-w-md">
          <TabsTrigger value="general">
            <span className="material-icons text-sm mr-1">settings</span>
            {t("common.general")}
          </TabsTrigger>
          <TabsTrigger value="notifications">
            <span className="material-icons text-sm mr-1">notifications</span>
            {t("common.notifications")}
          </TabsTrigger>
          <TabsTrigger value="appearance">
            <span className="material-icons text-sm mr-1">palette</span>
            {t("common.appearance")}
          </TabsTrigger>
          <TabsTrigger value="security">
            <span className="material-icons text-sm mr-1">security</span>
            {t("common.security")}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="general">
          <Card>
            <CardHeader>
              <CardTitle>{t("common.general")}</CardTitle>
              <CardDescription>{t("settings.general.description")}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="appName">{t("settings.app.name")}</Label>
                  <Input
                    id="appName"
                    value={general.appName}
                    onChange={(e) => setGeneral({ ...general, appName: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="appSubtitle">{t("settings.app.subtitle")}</Label>
                  <Input
                    id="appSubtitle"
                    value={general.appSubtitle}
                    onChange={(e) => setGeneral({ ...general, appSubtitle: e.target.value })}
                  />
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="logoUrl">{t("common.logo")} URL</Label>
                <Input
                  id="logoUrl"
                  placeholder="https://example.com/logo.png"
                  value={general.logoUrl}
                  onChange={(e) => setGeneral({ ...general, logoUrl: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="pageSize">{t("settings.page.size")}</Label>
                  <Select
                    value={general.pageSize}
                    onValueChange={(value) => setGeneral({ ...general, pageSize: value })}
                  >
                    <SelectTrigger id="pageSize">
                      <SelectValue placeholder="10" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="5">5</SelectItem>
                      <SelectItem value="10">10</SelectItem>
                      <SelectItem value="20">20</SelectItem>
                      <SelectItem value="50">50</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </CardContent>
            <CardFooter>
              <Button onClick={handleSaveGeneral}>{t("common.save")}</Button>
            </CardFooter>
          </Card>
        </TabsContent>

        <TabsContent value="notifications">
          <Card>
            <CardHeader>
              <CardTitle>{t("common.notifications")}</CardTitle>
              <CardDescription>{t("settings.notifications.description")}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label>{t("settings.email.notifications")}</Label>
                    <p className="text-sm text-muted-foreground">
                      {t("settings.email.notifications.description")}
                    </p>
                  </div>
                  <Switch
                    checked={notifications.emailNotifications}
                    onCheckedChange={(checked) =>
                      setNotifications({ ...notifications, emailNotifications: checked })
                    }
                  />
                </div>
                <div className="flex items-center justify-between">
                  <div className="space-y-0.5">
                    <Label>{t("settings.push.notifications")}</Label>
                    <p className="text-sm text-muted-foreground">
                      {t("settings.push.notifications.description")}
                    </p>
                  </div>
                  <Switch
                    checked={notifications.pushNotifications}
                    onCheckedChange={(checked) =>
                      setNotifications({ ...notifications, pushNotifications: checked })
                    }
                  />
                </div>
              </div>
              <div className="space-y-2 border-t pt-4">
                <h3 className="text-sm font-medium">{t("settings.notification.events")}</h3>
                <div className="space-y-2">
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="notifyNewPost"
                      checked={notifications.notifyOnNewPost}
                      onCheckedChange={(checked) =>
                        setNotifications({
                          ...notifications,
                          notifyOnNewPost: checked as boolean,
                        })
                      }
                    />
                    <Label htmlFor="notifyNewPost">{t("settings.notify.new.post")}</Label>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="notifyNewComment"
                      checked={notifications.notifyOnNewComment}
                      onCheckedChange={(checked) =>
                        setNotifications({
                          ...notifications,
                          notifyOnNewComment: checked as boolean,
                        })
                      }
                    />
                    <Label htmlFor="notifyNewComment">{t("settings.notify.new.comment")}</Label>
                  </div>
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id="notifyUserRegistration"
                      checked={notifications.notifyOnUserRegistration}
                      onCheckedChange={(checked) =>
                        setNotifications({
                          ...notifications,
                          notifyOnUserRegistration: checked as boolean,
                        })
                      }
                    />
                    <Label htmlFor="notifyUserRegistration">{t("settings.notify.user.registration")}</Label>
                  </div>
                </div>
              </div>
            </CardContent>
            <CardFooter>
              <Button onClick={handleSaveNotifications}>{t("common.save")}</Button>
            </CardFooter>
          </Card>
        </TabsContent>

        <TabsContent value="appearance">
          <Card>
            <CardHeader>
              <CardTitle>{t("common.appearance")}</CardTitle>
              <CardDescription>{t("settings.appearance.description")}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="theme">{t("settings.theme")}</Label>
                <Select
                  value={appearance.theme}
                  onValueChange={(value) => setAppearance({ ...appearance, theme: value })}
                >
                  <SelectTrigger id="theme">
                    <SelectValue placeholder="Light" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="light">{t("settings.theme.light")}</SelectItem>
                    <SelectItem value="dark">{t("settings.theme.dark")}</SelectItem>
                    <SelectItem value="system">{t("settings.theme.system")}</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label htmlFor="language">{t("app.language")}</Label>
                <Select
                  value={appearance.language}
                  onValueChange={(value) => setAppearance({ ...appearance, language: value })}
                >
                  <SelectTrigger id="language">
                    <SelectValue placeholder="English" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="tr">Türkçe</SelectItem>
                    <SelectItem value="en">English</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </CardContent>
            <CardFooter>
              <Button onClick={handleSaveAppearance}>{t("common.save")}</Button>
            </CardFooter>
          </Card>
        </TabsContent>

        <TabsContent value="security">
          <Card>
            <CardHeader>
              <CardTitle>{t("common.security")}</CardTitle>
              <CardDescription>{t("settings.security.description")}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>{t("settings.require.email.verification")}</Label>
                  <p className="text-sm text-muted-foreground">
                    {t("settings.require.email.verification.description")}
                  </p>
                </div>
                <Switch
                  checked={security.requireEmailVerification}
                  onCheckedChange={(checked) =>
                    setSecurity({ ...security, requireEmailVerification: checked })
                  }
                />
              </div>
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>{t("settings.two.factor.auth")}</Label>
                  <p className="text-sm text-muted-foreground">
                    {t("settings.two.factor.auth.description")}
                  </p>
                </div>
                <Switch
                  checked={security.twoFactorAuth}
                  onCheckedChange={(checked) =>
                    setSecurity({ ...security, twoFactorAuth: checked })
                  }
                />
              </div>
              <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="sessionTimeout">{t("settings.session.timeout")} (minutes)</Label>
                  <Input
                    id="sessionTimeout"
                    type="number"
                    value={security.sessionTimeout}
                    onChange={(e) => setSecurity({ ...security, sessionTimeout: e.target.value })}
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="passwordMinLength">{t("settings.password.min.length")}</Label>
                  <Input
                    id="passwordMinLength"
                    type="number"
                    value={security.passwordMinLength}
                    onChange={(e) => setSecurity({ ...security, passwordMinLength: e.target.value })}
                  />
                </div>
              </div>
            </CardContent>
            <CardFooter>
              <Button onClick={handleSaveSecurity}>{t("common.save")}</Button>
            </CardFooter>
          </Card>
        </TabsContent>
      </Tabs>
    </section>
  );
}
