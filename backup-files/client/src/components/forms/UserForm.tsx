import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useToast } from "@/hooks/use-toast";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { z } from "zod";
import { insertUserSchema } from "@shared/schema";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Spinner } from "@/components/ui/spinner";

interface UserFormProps {
  userId?: string;
  onClose: () => void;
}

export function UserForm({ userId, onClose }: UserFormProps) {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Extend the schema with validation
  const formSchema = insertUserSchema.extend({
    username: z.string().min(3, { message: "Username must be at least 3 characters" }),
    email: z.string().email().optional().or(z.literal('')),
    role: z.string().min(1, { message: "Role is required" }),
  });

  // Get user data if editing
  const { data: user, isLoading: userLoading } = useQuery({
    queryKey: [userId ? `/api/users/${userId}` : null],
    enabled: !!userId
  });

  // Get cities for dropdown
  const { data: cities, isLoading: citiesLoading } = useQuery({
    queryKey: ['/api/cities'],
  });

  // Setup form with default values
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      username: "",
      email: "",
      profileImageUrl: "",
      city: "",
      district: "",
      phoneNumber: "",
      role: "user",
    },
  });

  // Update form when user data is loaded
  useState(() => {
    if (user) {
      form.reset({
        username: user.username || "",
        email: user.email || "",
        profileImageUrl: user.profileImageUrl || "",
        city: user.city || "",
        district: user.district || "",
        phoneNumber: user.phoneNumber || "",
        role: user.role || "user",
      });
    }
  });

  // Create mutation
  const createMutation = useMutation({
    mutationFn: async (data: z.infer<typeof formSchema>) => {
      return apiRequest("POST", "/api/users", data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.created"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/users'] });
      onClose();
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Update mutation
  const updateMutation = useMutation({
    mutationFn: async (data: z.infer<typeof formSchema>) => {
      return apiRequest("PUT", `/api/users/${userId}`, data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.updated"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/users'] });
      if (userId) {
        queryClient.invalidateQueries({ queryKey: [`/api/users/${userId}`] });
      }
      onClose();
    },
    onError: (error) => {
      toast({
        title: t("notifications.error"),
        description: t("notifications.error.occurred"),
        variant: "destructive",
      });
    },
  });

  // Handle form submission
  const onSubmit = async (data: z.infer<typeof formSchema>) => {
    setIsSubmitting(true);
    try {
      if (userId) {
        await updateMutation.mutateAsync(data);
      } else {
        await createMutation.mutateAsync(data);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (userId && userLoading) {
    return (
      <div className="flex justify-center items-center h-60">
        <Spinner size="lg" />
      </div>
    );
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
        <div className="grid grid-cols-1 gap-y-6 gap-x-4 sm:grid-cols-6">
          <FormField
            control={form.control}
            name="username"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.username')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.username')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.email')}</FormLabel>
                <FormControl>
                  <Input type="email" placeholder={t('common.email')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="role"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.role')}</FormLabel>
                <Select 
                  onValueChange={field.onChange} 
                  defaultValue={field.value}
                >
                  <FormControl>
                    <SelectTrigger>
                      <SelectValue placeholder={t('common.role')} />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    <SelectItem value="user">User</SelectItem>
                    <SelectItem value="moderator">Moderator</SelectItem>
                    <SelectItem value="admin">Admin</SelectItem>
                  </SelectContent>
                </Select>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="phoneNumber"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.phone')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.phone')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="city"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.city')}</FormLabel>
                <Select 
                  onValueChange={field.onChange} 
                  defaultValue={field.value}
                  disabled={citiesLoading}
                >
                  <FormControl>
                    <SelectTrigger>
                      <SelectValue placeholder={t('common.city')} />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    {cities?.data.map((city: any) => (
                      <SelectItem key={city.id} value={city.name}>
                        {city.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="district"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.district')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.district')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="profileImageUrl"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>Profile Image URL</FormLabel>
                <FormControl>
                  <Input placeholder="Profile Image URL" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <div className="flex justify-end space-x-3">
          <Button variant="outline" type="button" onClick={onClose}>
            {t('common.cancel')}
          </Button>
          <Button type="submit" disabled={isSubmitting}>
            {isSubmitting ? (
              <Spinner className="mr-2" />
            ) : null}
            {userId ? t('common.save') : t('users.addnew')}
          </Button>
        </div>
      </form>
    </Form>
  );
}
