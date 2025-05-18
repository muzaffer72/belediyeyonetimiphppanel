import { useState } from "react";
import { useTranslation } from "@/lib/i18n";
import { useToast } from "@/hooks/use-toast";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import { z } from "zod";
import { insertPostSchema } from "@shared/schema";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group";
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

interface PostFormProps {
  postId?: string;
  onClose: () => void;
}

export function PostForm({ postId, onClose }: PostFormProps) {
  const { t } = useTranslation();
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [isSubmitting, setIsSubmitting] = useState(false);

  // Extend the schema with validation
  const formSchema = insertPostSchema.extend({
    title: z.string().min(2, { message: "Title must be at least 2 characters" }),
    description: z.string().min(10, { message: "Description must be at least 10 characters" }),
    type: z.string().min(1, { message: "Type is required" }),
  });

  // Get cities for dropdown
  const { data: cities, isLoading: citiesLoading } = useQuery({
    queryKey: ['/api/cities'],
  });

  // Get post data if editing
  const { data: post, isLoading: postLoading } = useQuery({
    queryKey: [postId ? `/api/posts/${postId}` : null],
    enabled: !!postId
  });

  // Setup form with default values
  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      title: "",
      description: "",
      mediaUrl: "",
      isVideo: false,
      type: "complaint",
      city: "",
      district: "",
      mediaUrls: "",
      isVideoList: "",
      category: "",
      isResolved: false,
      isHidden: false,
      isFeatured: false,
    },
  });

  // Get districts based on selected city
  const selectedCity = form.watch("city");
  const { data: districts, isLoading: districtsLoading } = useQuery({
    queryKey: [selectedCity ? `/api/cities/${selectedCity}/districts` : null],
    enabled: !!selectedCity
  });

  // Update form when post data is loaded
  useState(() => {
    if (post) {
      form.reset({
        title: post.title || "",
        description: post.description || "",
        mediaUrl: post.mediaUrl || "",
        isVideo: post.isVideo || false,
        type: post.type || "complaint",
        city: post.city || "",
        district: post.district || "",
        mediaUrls: post.mediaUrls || "",
        isVideoList: post.isVideoList || "",
        category: post.category || "",
        isResolved: post.isResolved || false,
        isHidden: post.isHidden || false,
        isFeatured: post.isFeatured || false,
      });
    }
  });

  // Create mutation
  const createMutation = useMutation({
    mutationFn: async (data: z.infer<typeof formSchema>) => {
      return apiRequest("POST", "/api/posts", data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.created"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/posts'] });
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
      return apiRequest("PUT", `/api/posts/${postId}`, data);
    },
    onSuccess: () => {
      toast({
        title: t("notifications.success"),
        description: t("notifications.updated"),
      });
      queryClient.invalidateQueries({ queryKey: ['/api/posts'] });
      if (postId) {
        queryClient.invalidateQueries({ queryKey: [`/api/posts/${postId}`] });
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
      if (postId) {
        await updateMutation.mutateAsync(data);
      } else {
        await createMutation.mutateAsync(data);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  if (postId && postLoading) {
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
            name="description"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('common.description')}</FormLabel>
                <FormControl>
                  <Textarea 
                    placeholder={t('common.description')} 
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
            name="type"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>{t('common.type')}</FormLabel>
                <FormControl>
                  <RadioGroup
                    onValueChange={field.onChange}
                    defaultValue={field.value}
                    className="flex flex-col space-y-1"
                  >
                    <FormItem className="flex items-center space-x-3 space-y-0">
                      <FormControl>
                        <RadioGroupItem value="complaint" />
                      </FormControl>
                      <FormLabel className="font-normal">
                        {t('dashboard.complaints')}
                      </FormLabel>
                    </FormItem>
                    <FormItem className="flex items-center space-x-3 space-y-0">
                      <FormControl>
                        <RadioGroupItem value="suggestion" />
                      </FormControl>
                      <FormLabel className="font-normal">
                        {t('dashboard.suggestions')}
                      </FormLabel>
                    </FormItem>
                    <FormItem className="flex items-center space-x-3 space-y-0">
                      <FormControl>
                        <RadioGroupItem value="question" />
                      </FormControl>
                      <FormLabel className="font-normal">
                        {t('dashboard.questions')}
                      </FormLabel>
                    </FormItem>
                    <FormItem className="flex items-center space-x-3 space-y-0">
                      <FormControl>
                        <RadioGroupItem value="thanks" />
                      </FormControl>
                      <FormLabel className="font-normal">
                        {t('dashboard.thanks')}
                      </FormLabel>
                    </FormItem>
                  </RadioGroup>
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
            name="district"
            render={({ field }) => (
              <FormItem className="sm:col-span-3">
                <FormLabel>{t('common.district')}</FormLabel>
                <Select 
                  onValueChange={field.onChange} 
                  defaultValue={field.value}
                  disabled={!selectedCity || districtsLoading}
                >
                  <FormControl>
                    <SelectTrigger>
                      <SelectValue placeholder={t('common.district')} />
                    </SelectTrigger>
                  </FormControl>
                  <SelectContent>
                    {districts?.map((district: any) => (
                      <SelectItem key={district.id} value={district.id}>
                        {district.name}
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
            name="mediaUrl"
            render={({ field }) => (
              <FormItem className="sm:col-span-6">
                <FormLabel>Media URL</FormLabel>
                <FormControl>
                  <Input placeholder="Media URL" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="isVideo"
            render={({ field }) => (
              <FormItem className="flex flex-row items-start space-x-3 space-y-0 sm:col-span-3">
                <FormControl>
                  <Checkbox
                    checked={field.value}
                    onCheckedChange={field.onChange}
                  />
                </FormControl>
                <div className="space-y-1 leading-none">
                  <FormLabel>Is Video</FormLabel>
                </div>
              </FormItem>
            )}
          />

          {postId && (
            <>
              <FormField
                control={form.control}
                name="isResolved"
                render={({ field }) => (
                  <FormItem className="flex flex-row items-start space-x-3 space-y-0 sm:col-span-3">
                    <FormControl>
                      <Checkbox
                        checked={field.value}
                        onCheckedChange={field.onChange}
                      />
                    </FormControl>
                    <div className="space-y-1 leading-none">
                      <FormLabel>{t('common.resolved')}</FormLabel>
                    </div>
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="isHidden"
                render={({ field }) => (
                  <FormItem className="flex flex-row items-start space-x-3 space-y-0 sm:col-span-3">
                    <FormControl>
                      <Checkbox
                        checked={field.value}
                        onCheckedChange={field.onChange}
                      />
                    </FormControl>
                    <div className="space-y-1 leading-none">
                      <FormLabel>{t('common.hide')}</FormLabel>
                    </div>
                  </FormItem>
                )}
              />
            </>
          )}
        </div>

        <div className="flex justify-end space-x-3">
          <Button variant="outline" type="button" onClick={onClose}>
            {t('common.cancel')}
          </Button>
          <Button type="submit" disabled={isSubmitting}>
            {isSubmitting ? (
              <Spinner className="mr-2" />
            ) : null}
            {postId ? t('common.save') : t('common.title')}
          </Button>
        </div>
      </form>
    </Form>
  );
}
