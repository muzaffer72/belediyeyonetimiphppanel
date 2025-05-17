import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useToast } from "@/hooks/use-toast";
import { useLocation } from "wouter";
import { z } from "zod";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { useMutation } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { Spinner } from "@/components/ui/spinner";

const loginSchema = z.object({
  username: z.string().min(1, { message: "Username is required" }),
  password: z.string().min(1, { message: "Password is required" }),
  rememberMe: z.boolean().default(false),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export default function Login() {
  const { t } = useTranslation();
  const { toast } = useToast();
  const [_, setLocation] = useLocation();

  const form = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      username: "",
      password: "",
      rememberMe: false,
    },
  });

  // This would be a real login mutation in a production app
  const loginMutation = useMutation({
    mutationFn: async (data: LoginFormValues) => {
      // In a real app, this would be a proper login API call
      // For now, we'll simulate a successful login for admin
      if (data.username === "admin" && data.password === "admin") {
        return { success: true };
      }
      
      // Throw an error for other credentials
      throw new Error("Invalid credentials");
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("auth.login.success"),
      });
      // Redirect to dashboard
      setLocation("/");
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: error.message || t("auth.login.error"),
        variant: "destructive",
      });
    },
  });

  const onSubmit = (data: LoginFormValues) => {
    loginMutation.mutate(data);
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-2 text-center">
          <CardTitle className="text-2xl font-bold">BİMER</CardTitle>
          <CardDescription className="text-base">
            {t("app.subtitle")}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
              <FormField
                control={form.control}
                name="username"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>{t("auth.username")}</FormLabel>
                    <FormControl>
                      <Input placeholder={t("auth.username")} {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={form.control}
                name="password"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>{t("auth.password")}</FormLabel>
                    <FormControl>
                      <Input type="password" placeholder={t("auth.password")} {...field} />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <div className="flex items-center justify-between">
                <FormField
                  control={form.control}
                  name="rememberMe"
                  render={({ field }) => (
                    <FormItem className="flex flex-row items-center space-x-2 space-y-0">
                      <FormControl>
                        <Checkbox
                          checked={field.value}
                          onCheckedChange={field.onChange}
                        />
                      </FormControl>
                      <FormLabel className="text-sm font-normal">
                        {t("auth.remember")}
                      </FormLabel>
                    </FormItem>
                  )}
                />
                <Button variant="link" className="p-0 h-auto text-sm">
                  {t("auth.forgot.password")}
                </Button>
              </div>
              <Button
                type="submit"
                className="w-full"
                disabled={loginMutation.isPending}
              >
                {loginMutation.isPending && <Spinner className="mr-2 h-4 w-4" />}
                {t("auth.login")}
              </Button>
            </form>
          </Form>
        </CardContent>
        <CardFooter className="text-center text-sm text-gray-500">
          <div className="w-full text-center">
            <p>Demo credentials: admin / admin</p>
          </div>
        </CardFooter>
      </Card>
    </div>
  );
}
