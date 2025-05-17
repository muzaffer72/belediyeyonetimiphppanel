import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useToast } from "@/hooks/use-toast";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { z } from "zod";
import { insertMunicipalityAnnouncementSchema } from "@shared/schema";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
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

interface AnnouncementFormProps {
  announcementId?: string;
  municipalityId?: string;
  onClose: () => void;
}

export function AnnouncementForm({ announcementId, municipalityId: initialMunicipalityId, onClose }: AnnouncementFormProps) {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Extend the schema with validation
  const formSchema = insertMunicipalityAnnouncementSchema.extend({
    title: z.string().min(5, { message: "Title must be at least 5 characters" }),
    content: z.string().min(10, { message: "Content must be at least 10 characters" }),
    municipalityId: z.string().min(1, { message: "Municipality is required" }),
  });

  // Get cities/municipalities for dropdown
  const { data: cities, isLoading: citiesLoading } = useQuery({
    queryKey: ['/api/cities'],
  });

  // Get announcement data if editing
  const { data: announcement, isLoading: announcementLoading } = useQuery({
    queryKey: [announcementId ? `/api/municipality-announcements/${announcementId}` : null],
    enabled: !!announcementId
  });

  // Setup form with default values
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      title: "",
      content: "",
      imageUrl: "",
      isActive: true,
      municipalityId: initialMunicipalityId || "",
    },
  });

  // Update form when announcement data is loaded
  useState(() => {
    if (announcement) {
      form.reset({
        title: announcement.title || "",
        content: announcement.content || "",
        imageUrl: announcement.imageUrl || "",
        isActive: announcement.isActive,
        municipalityId: announcement.municipalityId || initialMunicipalityId || "",
      });
    } else if (initialMunicipalityId) {
      form.setValue("municipalityId", initialMunicipalityId);
    }
  });

  // Create mutation
  const createMutation = useMutation({
    mutationFn: async (data: z.infer<typeof formSchema>) => {
      return apiRequest("POST", "/api/municipality-announcements", data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.created"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/municipality-announcements'] });
      if (initialMunicipalityId) {
        queryClient.invalidateQueries({ queryKey: [`/api/cities/${initialMunicipalityId}/announcements`] });
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

  // Update mutation
  const updateMutation = useMutation({
    mutationFn: async (data: z.infer<typeof formSchema>) => {
      return apiRequest("PUT", `/api/municipality-announcements/${announcementId}`, data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.updated"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/municipality-announcements'] });
      if (announcementId) {
        queryClient.invalidateQueries({ queryKey: [`/api/municipality-announcements/${announcementId}`] });
      }
      const municipalityId = form.getValues().municipalityId;
      if (municipalityId) {
        queryClient.invalidateQueries({ queryKey: [`/api/cities/${municipalityId}/announcements`] });
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
      if (announcementId) {
        await updateMutation.mutateAsync(data);
      } else {
        await createMutation.mutateAsync(data);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (announcementId && announcementLoading) {
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
            name="municipalityId"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('dashboard.total.municipalities')}</FormLabel>
                <Select 
                  onValueChange={field.onChange} 
                  defaultValue={field.value}
                  disabled={citiesLoading || !!initialMunicipalityId}
                >
                  <FormControl>
                    <SelectTrigger>
                      <SelectValue placeholder={t('dashboard.total.municipalities')} />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    {cities?.data.map((city: any) => (
                      <SelectItem key={city.id} value={city.id}>
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
            name="title"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('common.title')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.title')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="content"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('common.content')}</FormLabel>
                <FormControl>
                  <Textarea 
                    placeholder={t('common.content')} 
                    rows={4} 
                    {...field} 
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="imageUrl"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>Image URL</FormLabel>
                <FormControl>
                  <Input placeholder="Image URL" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="isActive"
            render={({ field }) => (
              <FormItem className="flex flex-row items-start space-x-3 space-y-0 sm:col-span-3">
                <FormControl>
                  <Checkbox
                    checked={field.value}
                    onCheckedChange={field.onChange}
                  />
                </FormControl>
                <div className="space-y-1 leading-none">
                  <FormLabel>{t('common.active')}</FormLabel>
                </div>
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
            {announcementId ? t('common.save') : t('announcements.addnew')}
          </Button>
        </div>
      </form>
    </Form>
  );
}
