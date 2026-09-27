import { v } from 'convex/values';
import { mutation } from './_generated/server';

export const submitFeedback = mutation({
    args: {
        category: v.union(v.literal('bug'), v.literal('feature'), v.literal('other')),
        message: v.string(),
        appVersion: v.optional(v.string()),
        platform: v.optional(v.string()),
    },
    handler: async (ctx, args) => {
        const identity = await ctx.auth.getUserIdentity();
        if (identity === null) {
            throw new Error('Not authenticated');
        }
        const trimmed = args.message.trim();
        if (trimmed.length === 0) {
            throw new Error('Message is required');
        }
        if (trimmed.length > 4000) {
            throw new Error('Message too long');
        }

        await ctx.db.insert('feedback', {
            clerkId: identity.subject,
            email: typeof identity.email === 'string' ? identity.email : undefined,
            category: args.category,
            message: trimmed,
            appVersion: args.appVersion,
            platform: args.platform,
        });

        return { success: true };
    },
});
