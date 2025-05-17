import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useToast } from "@/hooks/use-toast";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { z } from "zod";
import { insertCitySchema } from "@shared/schema";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
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

interface CityFormProps {
  cityId?: string;
  onClose: () => void;
}

export function CityForm({ cityId, onClose }: CityFormProps) {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Extend the schema with validation
  const formSchema = insertCitySchema.extend({
    name: z.string().min(2, { message: "City name must be at least 2 characters" }),
    mayorName: z.string().optional(),
    population: z.coerce.number().optional(),
    email: z.string().email().optional().or(z.literal('')),
  });

  // Get political parties for dropdown
  const { data: parties, isLoading: partiesLoading } = useQuery({
    queryKey: ['/api/political-parties'],
  });

  // Get city data if editing
  const { data: city, isLoading: cityLoading } = useQuery({
    queryKey: [cityId ? `/api/cities/${cityId}` : null],
    enabled: !!cityId
  });

  // Setup form with default values
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      name: "",
      mayorName: "",
      mayorParty: "",
      population: undefined,
      email: "",
      phone: "",
      address: "",
      website: "",
      logoUrl: "",
      coverImageUrl: "",
      type: "municipality",
      politicalPartyId: undefined,
    },
  });

  // Update form when city data is loaded
  useState(() => {
    if (city) {
      form.reset({
        name: city.name || "",
        mayorName: city.mayorName || "",
        mayorParty: city.mayorParty || "",
        population: city.population || undefined,
        email: city.email || "",
        phone: city.phone || "",
        address: city.address || "",
        website: city.website || "",
        logoUrl: city.logoUrl || "",
        coverImageUrl: city.coverImageUrl || "",
        type: city.type || "municipality",
        politicalPartyId: city.politicalPartyId,
      });
    }
  });

  // Create mutation
  const createMutation = useMutation({
    mutationFn: async (data: z.infer<typeof formSchema>) => {
      return apiRequest("POST", `/api/cities`, data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.created"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/cities'] });
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
      return apiRequest("PUT", `/api/cities/${cityId}`, data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.updated"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/cities'] });
      queryClient.invalidateQueries({ queryKey: [`/api/cities/${cityId}`] });
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
      if (cityId) {
        await updateMutation.mutateAsync(data);
      } else {
        await createMutation.mutateAsync(data);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (cityId && cityLoading) {
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
            name="name"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('form.city.name')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('form.city.name')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="mayorName"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('form.mayor.name')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('form.mayor.name')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="politicalPartyId"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('form.party')}</FormLabel>
                <Select 
                  onValueChange={field.onChange} 
                  defaultValue={field.value}
                  disabled={partiesLoading}
                >
                  <FormControl>
                    <SelectTrigger>
                      <SelectValue placeholder={t('form.party')} />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    {parties?.data.map((party: any) => (
                      <SelectItem key={party.id} value={party.id}>
                        {party.name}
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
            name="population"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('form.population')}</FormLabel>
                <FormControl>
                  <Input type="number" placeholder={t('form.population')} {...field} />
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
                <FormLabel>{t('form.email')}</FormLabel>
                <FormControl>
                  <Input type="email" placeholder={t('form.email')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="phone"
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
            name="website"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('common.website')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.website')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="address"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('form.address')}</FormLabel>
                <FormControl>
                  <Textarea placeholder={t('form.address')} rows={3} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="logoUrl"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.logo')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.logo')} {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="coverImageUrl"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.cover')}</FormLabel>
                <FormControl>
                  <Input placeholder={t('common.cover')} {...field} />
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
            {cityId ? t('common.save') : t('cities.addnew')}
          </Button>
        </div>
      </form>
    </Form>
  );
}
