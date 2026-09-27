import { v } from 'convex/values';
import { mutation, query } from './_generated/server';
import type { MutationCtx, QueryCtx } from './_generated/server';
import type { Id } from './_generated/dataModel';

/**
 * The notification inbox behind the bell.
 *
 * Push notifications are missed, dismissed, and silenced. Anything worth
 * telling someone has to survive that, which is what this is for: announcements
 * we write, and events on their own shares.
 */

/** Announcements older than this stop appearing for everyone. */
const ANNOUNCEMENT_LIFETIME_MS = 60 * 24 * 60 * 60 * 1000;

async function callerClerkId(ctx: QueryCtx | MutationCtx): Promise<string | null> {
    const identity = await ctx.auth.getUserIdentity();
    return identity?.subject ?? null;
}

/**
 * Everything addressed to this user, newest first.
 *
 * Announcements and personal messages are merged here rather than in the app,
 * so the unread count and the list cannot disagree.
 */
export const list = query({
    args: { limit: v.optional(v.number()) },
    handler: async (ctx, args) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return [];
        }

        const limit = Math.min(args.limit ?? 50, 100);
        const now = Date.now();

        const personal = await ctx.db
            .query('notifications')
            .withIndex('by_recipient', (q) => q.eq('clerkId', clerkId))
            .order('desc')
            .take(limit);

        const announcements = await ctx.db
            .query('notifications')
            .withIndex('by_broadcast', (q) => q.eq('kind', 'announcement'))
            .order('desc')
            .take(limit);

        const reads = await ctx.db
            .query('notificationReads')
            .withIndex('by_user', (q) => q.eq('clerkId', clerkId))
            .collect();
        const readIds = new Set(reads.map((row) => row.notificationId));

        const merged = [...personal, ...announcements.filter((row) => !row.clerkId)]
            .filter((row) => !row.expiresAt || row.expiresAt > now)
            .filter((row) => row.kind !== 'announcement' || row.createdAt > now - ANNOUNCEMENT_LIFETIME_MS)
            .sort((a, b) => b.createdAt - a.createdAt)
            .slice(0, limit);

        return merged.map((row) => ({
            id: row._id,
            kind: row.kind,
            title: row.title,
            body: row.body,
            link: row.link ?? null,
            createdAt: row.createdAt,
            isRead: readIds.has(row._id),
        }));
    },
});

/** How many rows the bell should badge. */
export const unreadCount = query({
    args: {},
    handler: async (ctx) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return 0;
        }

        const now = Date.now();
        const personal = await ctx.db
            .query('notifications')
            .withIndex('by_recipient', (q) => q.eq('clerkId', clerkId))
            .take(100);
        const announcements = await ctx.db
            .query('notifications')
            .withIndex('by_broadcast', (q) => q.eq('kind', 'announcement'))
            .take(100);

        const reads = await ctx.db
            .query('notificationReads')
            .withIndex('by_user', (q) => q.eq('clerkId', clerkId))
            .collect();
        const readIds = new Set(reads.map((row) => row.notificationId));

        return [...personal, ...announcements.filter((row) => !row.clerkId)]
            .filter((row) => !row.expiresAt || row.expiresAt > now)
            .filter((row) => row.kind !== 'announcement' || row.createdAt > now - ANNOUNCEMENT_LIFETIME_MS)
            .filter((row) => !readIds.has(row._id)).length;
    },
});

export const markRead = mutation({
    args: { notificationId: v.id('notifications') },
    handler: async (ctx, args) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return null;
        }

        const existing = await ctx.db
            .query('notificationReads')
            .withIndex('by_user_notification', (q) =>
                q.eq('clerkId', clerkId).eq('notificationId', args.notificationId),
            )
            .unique();
        if (existing) {
            return null;
        }

        await ctx.db.insert('notificationReads', {
            clerkId,
            notificationId: args.notificationId,
            readAt: Date.now(),
        });
        return null;
    },
});

export const markAllRead = mutation({
    args: {},
    handler: async (ctx) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return null;
        }

        const now = Date.now();
        const personal = await ctx.db
            .query('notifications')
            .withIndex('by_recipient', (q) => q.eq('clerkId', clerkId))
            .take(100);
        const announcements = await ctx.db
            .query('notifications')
            .withIndex('by_broadcast', (q) => q.eq('kind', 'announcement'))
            .take(100);

        const reads = await ctx.db
            .query('notificationReads')
            .withIndex('by_user', (q) => q.eq('clerkId', clerkId))
            .collect();
        const readIds = new Set(reads.map((row) => row.notificationId));

        const unread = [...personal, ...announcements.filter((row) => !row.clerkId)]
            .filter((row) => !row.expiresAt || row.expiresAt > now)
            .filter((row) => !readIds.has(row._id));

        for (const row of unread) {
            await ctx.db.insert('notificationReads', {
                clerkId,
                notificationId: row._id,
                readAt: now,
            });
        }
        return null;
    },
});

/**
 * Records an event on a share for its owner.
 *
 * Called from the sharing mutations rather than exposed to the app: the app has
 * no business writing someone else's inbox.
 */
export async function notifyOwner(
    ctx: MutationCtx,
    args: {
        ownerClerkId: string;
        kind: 'member_joined' | 'member_left' | 'bookmark_added';
        title: string;
        body: string;
        link?: string;
    },
): Promise<Id<'notifications'> | null> {
    // Nothing to tell someone about their own action.
    const caller = await callerClerkId(ctx);
    if (caller === args.ownerClerkId) {
        return null;
    }

    return await ctx.db.insert('notifications', {
        clerkId: args.ownerClerkId,
        kind: args.kind,
        title: args.title,
        body: args.body,
        link: args.link,
        createdAt: Date.now(),
    });
}
