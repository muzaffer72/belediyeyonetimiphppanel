import express from 'express';
import { storage } from './storage';
import { insertSponsoredAdSchema, insertAdInteractionSchema } from '@shared/schema';
import { z } from 'zod';

const router = express.Router();

// Sponsored Ads Routes
router.get('/api/ads', async (req, res) => {
  try {
    const { scope, status, city, district } = req.query;
    const ads = await storage.getSponsoredAds({
      scope: scope as string,
      status: status as string,
      city: city as string,
      district: district as string
    });
    res.json(ads);
  } catch (error) {
    console.error('Error fetching ads:', error);
    res.status(500).json({ error: 'Failed to fetch ads' });
  }
});

// Splash Screen Ads - Açılış sayfası reklamları için özel endpoint
router.get('/api/ads/splash', async (req, res) => {
  try {
    const splashAds = await storage.getSplashScreenAds();
    res.json(splashAds);
  } catch (error) {
    console.error('Error fetching splash ads:', error);
    res.status(500).json({ error: 'Failed to fetch splash screen ads' });
  }
});

// Hedeflenmiş reklamlar
router.get('/api/ads/targeted', async (req, res) => {
  try {
    const { scope, cityId, districtId } = req.query;
    
    if (!scope) {
      return res.status(400).json({ error: 'Scope parameter is required' });
    }
    
    const ads = await storage.getActiveAdsByScope(
      scope as string,
      cityId as string,
      districtId as string
    );
    res.json(ads);
  } catch (error) {
    console.error('Error fetching targeted ads:', error);
    res.status(500).json({ error: 'Failed to fetch targeted ads' });
  }
});

// Get single ad
router.get('/api/ads/:id', async (req, res) => {
  try {
    const ad = await storage.getSponsoredAdById(req.params.id);
    if (!ad) {
      return res.status(404).json({ error: 'Ad not found' });
    }
    res.json(ad);
  } catch (error) {
    console.error('Error fetching ad:', error);
    res.status(500).json({ error: 'Failed to fetch ad' });
  }
});

// Create new ad
router.post('/api/ads', async (req, res) => {
  try {
    const validatedData = insertSponsoredAdSchema.parse(req.body);
    const newAd = await storage.createSponsoredAd(validatedData);
    res.status(201).json(newAd);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return res.status(400).json({ error: 'Validation error', details: error.errors });
    }
    console.error('Error creating ad:', error);
    res.status(500).json({ error: 'Failed to create ad' });
  }
});

// Update ad
router.patch('/api/ads/:id', async (req, res) => {
  try {
    const validatedData = insertSponsoredAdSchema.partial().parse(req.body);
    const updatedAd = await storage.updateSponsoredAd(req.params.id, validatedData);
    res.json(updatedAd);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return res.status(400).json({ error: 'Validation error', details: error.errors });
    }
    console.error('Error updating ad:', error);
    res.status(500).json({ error: 'Failed to update ad' });
  }
});

// Delete ad
router.delete('/api/ads/:id', async (req, res) => {
  try {
    await storage.deleteSponsoredAd(req.params.id);
    res.status(204).send();
  } catch (error) {
    console.error('Error deleting ad:', error);
    res.status(500).json({ error: 'Failed to delete ad' });
  }
});

// Record ad interaction (impression/click)
router.post('/api/ads/:id/interaction', async (req, res) => {
  try {
    const { interactionType, userId, ipAddress, userAgent } = req.body;
    
    const validatedData = insertAdInteractionSchema.parse({
      adId: req.params.id,
      interactionType,
      userId,
      ipAddress,
      userAgent
    });
    
    const interaction = await storage.recordAdInteraction(validatedData);
    res.status(201).json(interaction);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return res.status(400).json({ error: 'Validation error', details: error.errors });
    }
    console.error('Error recording interaction:', error);
    res.status(500).json({ error: 'Failed to record interaction' });
  }
});

// Get ad analytics
router.get('/api/ads/:id/analytics', async (req, res) => {
  try {
    const analytics = await storage.getAdAnalytics(req.params.id);
    res.json(analytics);
  } catch (error) {
    console.error('Error fetching analytics:', error);
    res.status(500).json({ error: 'Failed to fetch analytics' });
  }
});

// Geography Routes
router.get('/api/cities', async (req, res) => {
  try {
    const cities = await storage.getCities();
    res.json(cities);
  } catch (error) {
    console.error('Error fetching cities:', error);
    res.status(500).json({ error: 'Failed to fetch cities' });
  }
});

router.get('/api/districts', async (req, res) => {
  try {
    const { cityId } = req.query;
    const districts = await storage.getDistricts(cityId as string);
    res.json(districts);
  } catch (error) {
    console.error('Error fetching districts:', error);
    res.status(500).json({ error: 'Failed to fetch districts' });
  }
});

// Users Routes
router.get('/api/users', async (req, res) => {
  try {
    const users = await storage.getUsers();
    res.json(users);
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

router.get('/api/users/:id', async (req, res) => {
  try {
    const user = await storage.getUserById(req.params.id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json(user);
  } catch (error) {
    console.error('Error fetching user:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

export default router;