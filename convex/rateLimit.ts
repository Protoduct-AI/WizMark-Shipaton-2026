import { v } from 'convex/values';
import { internalMutation } from './_generated/server';

/** Fixed-window rate limit shared by all AI extraction entry points. */
const WINDOW_MS = 60 * 60 * 1000;
const MAX_REQUESTS_PER_WINDOW = 60;

/**
 * Coarse ceiling applied per client IP on the unauthenticated HTTP endpoint.
 * Mobile carriers place many subscribers behind a single CGNAT address, so
 * this only has to stop runaway abuse, not enforce the per-user allowance.
 */
export const IP_MAX_REQUESTS_PER_WINDOW = 300;

/**
 * Transactionally consume one request slot for the given key.
 * Returns whether the request is allowed and, when denied, how many
 * seconds remain until the window resets.
 *
 * `max` overrides the per-window allowance; callers use a higher ceiling for
 * coarse keys such as client IP, which mobile carriers share across many
 * subscribers via CGNAT.
 */
export const check = internalMutation({
    args: { key: v.string(), max: v.optional(v.number()) },
    returns: v.object({
        allowed: v.boolean(),
        retryAfterSeconds: v.number(),
    }),
    handler: async (ctx, { key, max }) => {
        const limit = max ?? MAX_REQUESTS_PER_WINDOW;
        const now = Date.now();
        const existing = await ctx.db
            .query('aiRateLimits')
            .withIndex('by_key', (q) => q.eq('key', key))
            .unique();

        if (!existing || now - existing.windowStart >= WINDOW_MS) {
            if (existing) {
                await ctx.db.patch(existing._id, { windowStart: now, count: 1 });
            } else {
                await ctx.db.insert('aiRateLimits', { key, windowStart: now, count: 1 });
            }
            return { allowed: true, retryAfterSeconds: 0 };
        }

        if (existing.count >= limit) {
            const retryAfterSeconds = Math.ceil((existing.windowStart + WINDOW_MS - now) / 1000);
            return { allowed: false, retryAfterSeconds };
        }

        await ctx.db.patch(existing._id, { count: existing.count + 1 });
        return { allowed: true, retryAfterSeconds: 0 };
    },
});
