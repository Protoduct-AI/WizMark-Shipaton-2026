import { v } from 'convex/values';
import { type DatabaseReader, internalMutation, mutation, query } from './_generated/server';

const USERNAME_CHARSET = 'abcdefghijklmnopqrstuvwxyz0123456789';

function randomUsername(): string {
    let s = 'user_';
    for (let i = 0; i < 10; i++) {
        s += USERNAME_CHARSET[Math.floor(Math.random() * USERNAME_CHARSET.length)];
    }
    return s;
}

async function generateUniqueUsername(db: DatabaseReader): Promise<string> {
    for (let attempt = 0; attempt < 10; attempt++) {
        const candidate = randomUsername();
        const taken = await db
            .query('user')
            .withIndex('by_username', (q) => q.eq('username', candidate))
            .first();
        if (!taken) return candidate;
    }
    return `user_${Date.now().toString(36)}`;
}

export const createUser = internalMutation({
    args: {
        email: v.string(),
        clerkId: v.string(),
    },
    handler: async (ctx, args) => {
        const username = await generateUniqueUsername(ctx.db);
        const userId = await ctx.db.insert('user', {
            email: args.email,
            clerkId: args.clerkId,
            username,
        });
        return userId;
    },
});

export const deleteUserByClerkId = internalMutation({
    args: { clerkId: v.string() },
    handler: async (ctx, args) => {
        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', args.clerkId))
            .unique();
        if (user) {
            if (user.avatarStorageId) {
                await ctx.storage.delete(user.avatarStorageId);
            }
            await ctx.db.delete(user._id);
        }
        const feedbacks = await ctx.db
            .query('feedback')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', args.clerkId))
            .collect();
        for (const f of feedbacks) {
            await ctx.db.delete(f._id);
        }
    },
});

export const syncEmail = internalMutation({
    args: { clerkId: v.string(), email: v.string() },
    handler: async (ctx, args) => {
        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', args.clerkId))
            .unique();
        if (user && user.email !== args.email) {
            await ctx.db.patch(user._id, { email: args.email });
        }
    },
});

export const backfillUsername = mutation({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }
        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();
        if (!user) {
            return null;
        }
        if (user.username) {
            return null;
        }
        const username = await generateUniqueUsername(ctx.db);
        await ctx.db.patch(user._id, { username });
        return null;
    },
});

export const getCurrentUser = query({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            return null;
        }
        return await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();
    },
});

export const generateAvatarUploadUrl = mutation({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }
        return await ctx.storage.generateUploadUrl();
    },
});

export const updateProfile = mutation({
    args: {
        displayName: v.string(),
        avatarStorageId: v.optional(v.id('_storage')),
        locale: v.optional(v.union(v.literal('ja'), v.literal('en'))),
    },
    handler: async (ctx, args) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }

        const existing = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();

        if (existing) {
            const patch: Record<string, unknown> = {
                displayName: args.displayName,
                avatarStorageId: args.avatarStorageId,
                locale: args.locale,
                profileCompleted: true,
            };
            if (!existing.username) {
                patch.username = await generateUniqueUsername(ctx.db);
            }
            await ctx.db.patch(existing._id, patch);
        } else {
            const email =
                typeof identity.email === 'string' && identity.email.length > 0
                    ? identity.email
                    : '';
            const username = await generateUniqueUsername(ctx.db);
            await ctx.db.insert('user', {
                clerkId: identity.subject,
                email,
                displayName: args.displayName,
                avatarStorageId: args.avatarStorageId,
                locale: args.locale,
                profileCompleted: true,
                username,
            });
        }

        return null;
    },
});

export const getAvatarUrl = query({
    args: { storageId: v.id('_storage') },
    handler: async (ctx, args) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }
        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();
        if (!user || user.avatarStorageId !== args.storageId) {
            throw new Error('Forbidden');
        }
        return await ctx.storage.getUrl(args.storageId);
    },
});

export const exportUserData = query({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }

        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();

        const feedbackRows = await ctx.db
            .query('feedback')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .collect();

        const avatarUrl = user?.avatarStorageId
            ? await ctx.storage.getUrl(user.avatarStorageId)
            : null;

        return {
            exportedAt: new Date().toISOString(),
            schema: 'myapp.user-export.v1',
            user: user
                ? {
                      email: user.email,
                      displayName: user.displayName ?? null,
                      username: user.username ?? null,
                      locale: user.locale ?? null,
                      profileCompleted: user.profileCompleted ?? false,
                      avatarUrl,
                      notificationPrefs: user.notificationPrefs ?? null,
                      createdAt: new Date(user._creationTime).toISOString(),
                  }
                : null,
            feedback: feedbackRows.map((f) => ({
                category: f.category,
                message: f.message,
                appVersion: f.appVersion ?? null,
                platform: f.platform ?? null,
                submittedAt: new Date(f._creationTime).toISOString(),
            })),
        };
    },
});

const USERNAME_REGEX = /^[a-z0-9_.]{3,20}$/;
const USERNAME_COOLDOWN_MS = 7 * 24 * 60 * 60 * 1000;

export const checkUsernameAvailable = query({
    args: { username: v.string() },
    handler: async (ctx, args) => {
        const lower = args.username.trim().toLowerCase();
        if (!USERNAME_REGEX.test(lower)) {
            return { available: false, reason: 'invalid_format' as const };
        }
        const identity = await ctx.auth.getUserIdentity();
        const existing = await ctx.db
            .query('user')
            .withIndex('by_username', (q) => q.eq('username', lower))
            .first();
        if (!existing) {
            return { available: true, reason: null };
        }
        if (identity && existing.clerkId === identity.subject) {
            return { available: true, reason: 'self' as const };
        }
        return { available: false, reason: 'taken' as const };
    },
});

export const updateUsername = mutation({
    args: { username: v.string() },
    handler: async (ctx, args) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }

        const lower = args.username.trim().toLowerCase();
        if (!USERNAME_REGEX.test(lower)) {
            throw new Error('username_invalid_format');
        }

        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();
        if (!user) {
            throw new Error('user_not_found');
        }

        if (user.username === lower) {
            return null;
        }

        if (user.usernameUpdatedAt) {
            const elapsed = Date.now() - user.usernameUpdatedAt;
            if (elapsed < USERNAME_COOLDOWN_MS) {
                throw new Error('username_rate_limited');
            }
        }

        const taken = await ctx.db
            .query('user')
            .withIndex('by_username', (q) => q.eq('username', lower))
            .first();
        if (taken && taken._id !== user._id) {
            throw new Error('username_taken');
        }

        const now = Date.now();
        await ctx.db.patch(user._id, {
            username: lower,
            usernameUpdatedAt: now,
        });
        return null;
    },
});

export const deleteUser = mutation({
    args: {},
    handler: async (ctx) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }

        const clerkId = identity.subject;

        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', clerkId))
            .unique();

        if (user) {
            if (user.avatarStorageId) {
                await ctx.storage.delete(user.avatarStorageId);
            }
            await ctx.db.delete(user._id);
        }

        const feedbackRows = await ctx.db
            .query('feedback')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', clerkId))
            .collect();
        for (const row of feedbackRows) {
            await ctx.db.delete(row._id);
        }

        return null;
    },
});

export const updateNotificationPrefs = mutation({
    args: {
        marketing: v.boolean(),
        updates: v.boolean(),
        reminders: v.boolean(),
    },
    handler: async (ctx, args) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }

        const user = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', identity.subject))
            .unique();

        if (!user) {
            throw new Error('User not found');
        }

        await ctx.db.patch(user._id, {
            notificationPrefs: {
                marketing: args.marketing,
                updates: args.updates,
                reminders: args.reminders,
            },
        });

        return null;
    },
});
