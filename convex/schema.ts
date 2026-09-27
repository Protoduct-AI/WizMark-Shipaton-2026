import { defineSchema, defineTable } from 'convex/server';
import { v } from 'convex/values';

export default defineSchema({
    user: defineTable({
        email: v.string(),
        clerkId: v.string(),
        displayName: v.optional(v.string()),
        username: v.optional(v.string()),
        usernameUpdatedAt: v.optional(v.number()),
        avatarStorageId: v.optional(v.id('_storage')),
        profileCompleted: v.optional(v.boolean()),
        locale: v.optional(v.union(v.literal('ja'), v.literal('en'))),
        notificationPrefs: v.optional(
            v.object({
                marketing: v.boolean(),
                updates: v.boolean(),
                reminders: v.boolean(),
            }),
        ),
    })
        .index('by_clerkId', ['clerkId'])
        .index('by_username', ['username']),

    feedback: defineTable({
        clerkId: v.optional(v.string()),
        email: v.optional(v.string()),
        category: v.union(v.literal('bug'), v.literal('feature'), v.literal('other')),
        message: v.string(),
        appVersion: v.optional(v.string()),
        platform: v.optional(v.string()),
    }).index('by_clerkId', ['clerkId']),

    aiRateLimits: defineTable({
        key: v.string(),
        windowStart: v.number(),
        count: v.number(),
    }).index('by_key', ['key']),

    /**
     * A collection its owner published for sharing.
     *
     * The owner's copy stays in SwiftData; this is the snapshot participants
     * read. `shareCode` is the opaque token carried by the invitation link.
     * `revoked` retires a share without deleting history.
     */
    /**
     * Messages shown in the app's notification inbox.
     *
     * Two kinds arrive here. Announcements are written by us and go to
     * everyone; invitation events are generated when someone joins or leaves a
     * collection, and go only to the owner. Both need somewhere to live that
     * survives the push notification being missed or dismissed.
     *
     * `clerkId` absent means the message is for everyone.
     */
    notifications: defineTable({
        clerkId: v.optional(v.string()),
        kind: v.union(
            v.literal('announcement'),
            v.literal('member_joined'),
            v.literal('member_left'),
            v.literal('bookmark_added'),
        ),
        title: v.string(),
        body: v.string(),
        /// Deep link opened when the row is tapped, e.g. wizmark://join/abc.
        link: v.optional(v.string()),
        createdAt: v.number(),
        /// Announcements older than this are not shown to new users.
        expiresAt: v.optional(v.number()),
    })
        .index('by_recipient', ['clerkId', 'createdAt'])
        .index('by_broadcast', ['kind', 'createdAt']),

    /**
     * Which notifications a user has already read.
     *
     * Kept apart from the notification itself so one announcement row can serve
     * every user without being copied per person.
     */
    notificationReads: defineTable({
        clerkId: v.string(),
        notificationId: v.id('notifications'),
        readAt: v.number(),
    })
        .index('by_user', ['clerkId'])
        .index('by_user_notification', ['clerkId', 'notificationId']),

    sharedCollections: defineTable({
        ownerClerkId: v.string(),
        localId: v.string(),
        name: v.string(),
        icon: v.optional(v.string()),
        color: v.optional(v.string()),
        shareCode: v.string(),
        revoked: v.optional(v.boolean()),
        // Role handed to whoever redeems the link. Optional so collections
        // published before this existed keep working as view-only.
        defaultRole: v.optional(v.union(v.literal('viewer'), v.literal('editor'))),
        updatedAt: v.number(),
    })
        .index('by_owner', ['ownerClerkId'])
        .index('by_shareCode', ['shareCode'])
        .index('by_owner_localId', ['ownerClerkId', 'localId']),

    /**
     * Bookmarks belonging to a published collection.
     *
     * Replaced wholesale on each publish, so the set always mirrors the owner's
     * collection at the time it was last pushed.
     */
    sharedBookmarks: defineTable({
        sharedCollectionId: v.id('sharedCollections'),
        // Who put this here. Absent means the owner, via publish — those rows
        // are replaced wholesale on every publish, so anything an editor adds
        // has to be distinguishable or it would be wiped on the next push.
        addedByClerkId: v.optional(v.string()),
        url: v.string(),
        title: v.string(),
        bookmarkDescription: v.optional(v.string()),
        thumbnailUrl: v.optional(v.string()),
        note: v.optional(v.string()),
        tags: v.array(v.string()),
        siteName: v.optional(v.string()),
        favicon: v.optional(v.string()),
        aiSummary: v.optional(v.string()),
        displayOrder: v.number(),
        createdAt: v.number(),
    }).index('by_collection', ['sharedCollectionId']),

    /**
     * Who may read a shared collection.
     *
     * `role` already distinguishes viewer from editor so write access can be
     * granted later without migrating existing rows.
     */
    collectionMembers: defineTable({
        sharedCollectionId: v.id('sharedCollections'),
        clerkId: v.string(),
        role: v.union(v.literal('owner'), v.literal('viewer'), v.literal('editor')),
        joinedAt: v.number(),
    })
        .index('by_collection', ['sharedCollectionId'])
        .index('by_user', ['clerkId'])
        .index('by_collection_user', ['sharedCollectionId', 'clerkId']),
});
