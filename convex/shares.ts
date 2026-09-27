import { v } from 'convex/values';
import { mutation, query } from './_generated/server';
import { notifyOwner } from './notifications';
import type { Doc, Id } from './_generated/dataModel';
import type { MutationCtx, QueryCtx } from './_generated/server';

/**
 * Collection sharing.
 *
 * The owner keeps authoring in SwiftData; publishing pushes a snapshot here and
 * participants read that snapshot. Membership is deliberately separate from the
 * share code so access survives a code rotation, and `role` already carries
 * "editor" so write access can be added without touching existing rows.
 */

const SHARE_CODE_ALPHABET = 'abcdefghjkmnpqrstuvwxyz23456789';
const SHARE_CODE_LENGTH = 10;

/**
 * Optional string that also tolerates an explicit JSON null.
 *
 * The Swift client encodes absent values as null rather than omitting the key,
 * which `v.optional(v.string())` rejects outright.
 */
/**
 * Mutations whose result the app ignores must return `null`.
 *
 * ConvexMobile's no-result `mutation` overload decodes the response as
 * `String?`, so returning an object like `{ ok: true }` fails at the decoder
 * with "data is not in the correct format" — the mutation itself having already
 * succeeded on the server. Only mutations the app actually reads (publish,
 * join) return a payload.
 */
const nullableString = v.optional(v.union(v.string(), v.null()));

/** Normalizes the client's null into the undefined the schema stores. */
function orUndefined(value: string | null | undefined): string | undefined {
    return value ?? undefined;
}

/** Bookmark payload accepted from the client. */
const bookmarkInput = v.object({
    url: v.string(),
    title: v.string(),
    bookmarkDescription: nullableString,
    thumbnailUrl: nullableString,
    note: nullableString,
    tags: v.array(v.string()),
    siteName: nullableString,
    favicon: nullableString,
    aiSummary: nullableString,
    displayOrder: v.number(),
    createdAt: v.number(),
});

/** The caller's Clerk subject, or null when unauthenticated. */
async function callerClerkId(ctx: QueryCtx | MutationCtx): Promise<string | null> {
    const identity = await ctx.auth.getUserIdentity();
    return identity?.subject ?? null;
}

async function requireCallerClerkId(ctx: QueryCtx | MutationCtx): Promise<string> {
    const clerkId = await callerClerkId(ctx);
    if (!clerkId) {
        throw new Error('not_authenticated');
    }
    return clerkId;
}

/** Generates a code that is not already in use. */
async function generateShareCode(ctx: MutationCtx): Promise<string> {
    for (let attempt = 0; attempt < 8; attempt += 1) {
        let code = '';
        for (let i = 0; i < SHARE_CODE_LENGTH; i += 1) {
            code += SHARE_CODE_ALPHABET[Math.floor(Math.random() * SHARE_CODE_ALPHABET.length)];
        }
        const clash = await ctx.db
            .query('sharedCollections')
            .withIndex('by_shareCode', (q) => q.eq('shareCode', code))
            .unique();
        if (!clash) {
            return code;
        }
    }
    throw new Error('share_code_generation_failed');
}

/** Replaces the stored bookmarks of a collection with the supplied set. */
async function replaceBookmarks(
    ctx: MutationCtx,
    sharedCollectionId: Id<'sharedCollections'>,
    bookmarks: Array<{
        url: string;
        title: string;
        bookmarkDescription?: string | null;
        thumbnailUrl?: string | null;
        note?: string | null;
        tags: string[];
        siteName?: string | null;
        favicon?: string | null;
        aiSummary?: string | null;
        displayOrder: number;
        createdAt: number;
    }>,
): Promise<void> {
    const existing = await ctx.db
        .query('sharedBookmarks')
        .withIndex('by_collection', (q) => q.eq('sharedCollectionId', sharedCollectionId))
        .collect();

    // Only the owner's own rows are replaced. Publishing pushes a snapshot of
    // the owner's local collection, which knows nothing about what an editor
    // contributed — clearing everything would delete their work on the next
    // push, without warning and with no way back.
    const ownerRows = existing.filter((row) => row.addedByClerkId === undefined);
    await Promise.all(ownerRows.map((row) => ctx.db.delete(row._id)));
    await Promise.all(
        bookmarks.map((bookmark) =>
            ctx.db.insert('sharedBookmarks', {
                sharedCollectionId,
                url: bookmark.url,
                title: bookmark.title,
                bookmarkDescription: orUndefined(bookmark.bookmarkDescription),
                thumbnailUrl: orUndefined(bookmark.thumbnailUrl),
                note: orUndefined(bookmark.note),
                tags: bookmark.tags,
                siteName: orUndefined(bookmark.siteName),
                favicon: orUndefined(bookmark.favicon),
                aiSummary: orUndefined(bookmark.aiSummary),
                displayOrder: bookmark.displayOrder,
                createdAt: bookmark.createdAt,
            }),
        ),
    );
}

/** True when the caller owns the share or has been admitted to it. */
async function canRead(
    ctx: QueryCtx,
    collection: Doc<'sharedCollections'>,
    clerkId: string,
): Promise<boolean> {
    if (collection.ownerClerkId === clerkId) {
        return true;
    }
    const membership = await ctx.db
        .query('collectionMembers')
        .withIndex('by_collection_user', (q) =>
            q.eq('sharedCollectionId', collection._id).eq('clerkId', clerkId),
        )
        .unique();
    return membership !== null;
}

/**
 * Publishes (or re-publishes) a collection and returns its share code.
 *
 * Re-publishing the same `localId` keeps the existing code so links already
 * handed out keep working, and clears a previous revocation.
 */
export const publish = mutation({
    args: {
        localId: v.string(),
        name: v.string(),
        icon: nullableString,
        color: nullableString,
        bookmarks: v.array(bookmarkInput),
    },
    handler: async (ctx, args) => {
        const clerkId = await requireCallerClerkId(ctx);

        const existing = await ctx.db
            .query('sharedCollections')
            .withIndex('by_owner_localId', (q) =>
                q.eq('ownerClerkId', clerkId).eq('localId', args.localId),
            )
            .unique();

        if (existing) {
            await ctx.db.patch(existing._id, {
                name: args.name,
                icon: orUndefined(args.icon),
                color: orUndefined(args.color),
                revoked: false,
                updatedAt: Date.now(),
            });
            await replaceBookmarks(ctx, existing._id, args.bookmarks);
            return { shareCode: existing.shareCode, collectionId: existing._id };
        }

        const shareCode = await generateShareCode(ctx);
        const collectionId = await ctx.db.insert('sharedCollections', {
            ownerClerkId: clerkId,
            localId: args.localId,
            name: args.name,
            icon: orUndefined(args.icon),
            color: orUndefined(args.color),
            shareCode,
            revoked: false,
            defaultRole: 'viewer',
            updatedAt: Date.now(),
        });

        await ctx.db.insert('collectionMembers', {
            sharedCollectionId: collectionId,
            clerkId,
            role: 'owner',
            joinedAt: Date.now(),
        });
        await replaceBookmarks(ctx, collectionId, args.bookmarks);

        return { shareCode, collectionId };
    },
});

/** Stops sharing. The row is kept so the same collection can be re-published. */
export const revoke = mutation({
    args: { localId: v.string() },
    handler: async (ctx, args) => {
        const clerkId = await requireCallerClerkId(ctx);
        const collection = await ctx.db
            .query('sharedCollections')
            .withIndex('by_owner_localId', (q) =>
                q.eq('ownerClerkId', clerkId).eq('localId', args.localId),
            )
            .unique();

        if (!collection) {
            return null;
        }
        await ctx.db.patch(collection._id, { revoked: true, updatedAt: Date.now() });
        return null;
    },
});

/**
 * Preview of an invitation, readable before joining.
 *
 * Deliberately unauthenticated so the invite screen can show what the link
 * leads to; it exposes only the name and the number of bookmarks.
 */
export const preview = query({
    args: { shareCode: v.string() },
    handler: async (ctx, args) => {
        const collection = await ctx.db
            .query('sharedCollections')
            .withIndex('by_shareCode', (q) => q.eq('shareCode', args.shareCode))
            .unique();

        if (!collection || collection.revoked) {
            return null;
        }

        const owner = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', collection.ownerClerkId))
            .unique();

        const bookmarks = await ctx.db
            .query('sharedBookmarks')
            .withIndex('by_collection', (q) => q.eq('sharedCollectionId', collection._id))
            .collect();

        return {
            name: collection.name,
            icon: collection.icon ?? null,
            color: collection.color ?? null,
            ownerName: owner?.displayName ?? owner?.username ?? null,
            bookmarkCount: bookmarks.length,
        };
    },
});

/** Admits the caller to the share the code points at. Idempotent. */
export const join = mutation({
    args: { shareCode: v.string() },
    handler: async (ctx, args) => {
        const clerkId = await requireCallerClerkId(ctx);

        const collection = await ctx.db
            .query('sharedCollections')
            .withIndex('by_shareCode', (q) => q.eq('shareCode', args.shareCode))
            .unique();

        if (!collection || collection.revoked) {
            throw new Error('share_not_found');
        }

        // The owner already has this collection locally, and listSharedWithMe
        // filters them out. Reporting a successful join would promise a
        // collection that never appears.
        if (collection.ownerClerkId === clerkId) {
            throw new Error('already_owner');
        }

        const existing = await ctx.db
            .query('collectionMembers')
            .withIndex('by_collection_user', (q) =>
                q.eq('sharedCollectionId', collection._id).eq('clerkId', clerkId),
            )
            .unique();

        if (!existing) {
            await ctx.db.insert('collectionMembers', {
                sharedCollectionId: collection._id,
                clerkId,
                // Rows predating defaultRole have none, and those links were
                // issued as view-only.
                role: collection.defaultRole ?? 'viewer',
                joinedAt: Date.now(),
            });

            // The owner issued a link and then had no way of knowing whether
            // anyone used it.
            const joiner = await ctx.db
                .query('user')
                .withIndex('by_clerkId', (q) => q.eq('clerkId', clerkId))
                .unique();
            await notifyOwner(ctx, {
                ownerClerkId: collection.ownerClerkId,
                kind: 'member_joined',
                title: '共有に参加がありました',
                body: `${joiner?.displayName ?? joiner?.username ?? '新しいメンバー'} さんが「${collection.name}」に参加しました。`,
            });
        }

        return { collectionId: collection._id, name: collection.name };
    },
});

/** Leaves a share. The owner cannot leave; they revoke instead. */
export const leave = mutation({
    args: { sharedCollectionId: v.id('sharedCollections') },
    handler: async (ctx, args) => {
        const clerkId = await requireCallerClerkId(ctx);
        const membership = await ctx.db
            .query('collectionMembers')
            .withIndex('by_collection_user', (q) =>
                q.eq('sharedCollectionId', args.sharedCollectionId).eq('clerkId', clerkId),
            )
            .unique();

        if (!membership || membership.role === 'owner') {
            return null;
        }
        await ctx.db.delete(membership._id);

        const collection = await ctx.db.get(args.sharedCollectionId);
        if (collection) {
            const leaver = await ctx.db
                .query('user')
                .withIndex('by_clerkId', (q) => q.eq('clerkId', clerkId))
                .unique();
            await notifyOwner(ctx, {
                ownerClerkId: collection.ownerClerkId,
                kind: 'member_left',
                title: '共有から退出がありました',
                body: `${leaver?.displayName ?? leaver?.username ?? 'メンバー'} さんが「${collection.name}」から退出しました。`,
            });
        }
        return null;
    },
});

/**
 * Collections shared *with* the caller, including their bookmarks.
 *
 * Excludes the caller's own shares so the home screen does not show a
 * duplicate of a collection they already have locally.
 */
export const listSharedWithMe = query({
    args: {},
    handler: async (ctx) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return [];
        }

        const memberships = await ctx.db
            .query('collectionMembers')
            .withIndex('by_user', (q) => q.eq('clerkId', clerkId))
            .collect();

        const results = [];
        for (const membership of memberships) {
            if (membership.role === 'owner') {
                continue;
            }
            const collection = await ctx.db.get(membership.sharedCollectionId);
            if (!collection || collection.revoked) {
                continue;
            }

            const owner = await ctx.db
                .query('user')
                .withIndex('by_clerkId', (q) => q.eq('clerkId', collection.ownerClerkId))
                .unique();

            const bookmarks = await ctx.db
                .query('sharedBookmarks')
                .withIndex('by_collection', (q) => q.eq('sharedCollectionId', collection._id))
                .collect();

            results.push({
                id: collection._id,
                name: collection.name,
                icon: collection.icon ?? null,
                color: collection.color ?? null,
                ownerName: owner?.displayName ?? owner?.username ?? null,
                role: membership.role,
                updatedAt: collection.updatedAt,
                bookmarks: bookmarks
                    .sort((a, b) => a.displayOrder - b.displayOrder)
                    .map((bookmark) => ({
                        id: bookmark._id,
                        url: bookmark.url,
                        title: bookmark.title,
                        bookmarkDescription: bookmark.bookmarkDescription ?? null,
                        thumbnailUrl: bookmark.thumbnailUrl ?? null,
                        note: bookmark.note ?? null,
                        tags: bookmark.tags,
                        siteName: bookmark.siteName ?? null,
                        favicon: bookmark.favicon ?? null,
                        aiSummary: bookmark.aiSummary ?? null,
                        createdAt: bookmark.createdAt,
                        // The client uses this to decide whether to offer
                        // deletion: you can take back what you added, and the
                        // owner can remove anything.
                        addedByMe: bookmark.addedByClerkId === clerkId,
                    })),
            });
        }

        return results;
    },
});

/** The share state of one of the caller's own collections, if published. */
export const myShare = query({
    args: { localId: v.string() },
    handler: async (ctx, args) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return null;
        }

        const collection = await ctx.db
            .query('sharedCollections')
            .withIndex('by_owner_localId', (q) =>
                q.eq('ownerClerkId', clerkId).eq('localId', args.localId),
            )
            .unique();

        if (!collection || collection.revoked) {
            return null;
        }

        const members = await ctx.db
            .query('collectionMembers')
            .withIndex('by_collection', (q) => q.eq('sharedCollectionId', collection._id))
            .collect();

        const participants = [];
        for (const member of members) {
            if (member.role === 'owner') {
                continue;
            }
            const profile = await ctx.db
                .query('user')
                .withIndex('by_clerkId', (q) => q.eq('clerkId', member.clerkId))
                .unique();
            participants.push({
                clerkId: member.clerkId,
                name: profile?.displayName ?? profile?.username ?? null,
                email: profile?.email ?? null,
                role: member.role,
                joinedAt: member.joinedAt,
            });
        }

        return {
            collectionId: collection._id,
            shareCode: collection.shareCode,
            defaultRole: collection.defaultRole ?? 'viewer',
            updatedAt: collection.updatedAt,
            participants,
        };
    },
});

/**
 * Every collection the caller owns and has published.
 *
 * listSharedWithMe deliberately skips the owner, and myShare is a one-shot read
 * that returns no bookmarks. Between them the owner could see neither who
 * joined nor what anyone contributed. This is the subscribed counterpart:
 * participants and contributions both arrive live.
 *
 * Only rows an editor added are returned. The rest mirror the owner's own
 * collection, which they already have locally.
 */
export const myShares = query({
    args: {},
    handler: async (ctx) => {
        const clerkId = await callerClerkId(ctx);
        if (!clerkId) {
            return [];
        }

        const collections = await ctx.db
            .query('sharedCollections')
            .withIndex('by_owner_localId', (q) => q.eq('ownerClerkId', clerkId))
            .collect();

        const results = [];
        for (const collection of collections) {
            if (collection.revoked) {
                continue;
            }

            const members = await ctx.db
                .query('collectionMembers')
                .withIndex('by_collection', (q) => q.eq('sharedCollectionId', collection._id))
                .collect();

            const participants = [];
            for (const member of members) {
                if (member.role === 'owner') {
                    continue;
                }
                const profile = await ctx.db
                    .query('user')
                    .withIndex('by_clerkId', (q) => q.eq('clerkId', member.clerkId))
                    .unique();
                participants.push({
                    clerkId: member.clerkId,
                    name: profile?.displayName ?? profile?.username ?? null,
                    email: profile?.email ?? null,
                    role: member.role,
                    joinedAt: member.joinedAt,
                });
            }

            const rows = await ctx.db
                .query('sharedBookmarks')
                .withIndex('by_collection', (q) => q.eq('sharedCollectionId', collection._id))
                .collect();

            const names = new Map();
            const contributions = [];
            for (const row of rows.sort((a, b) => a.displayOrder - b.displayOrder)) {
                const addedBy = row.addedByClerkId;
                if (addedBy === undefined) {
                    continue;
                }
                if (!names.has(addedBy)) {
                    const profile = await ctx.db
                        .query('user')
                        .withIndex('by_clerkId', (q) => q.eq('clerkId', addedBy))
                        .unique();
                    names.set(addedBy, profile?.displayName ?? profile?.username ?? null);
                }
                contributions.push({
                    id: row._id,
                    url: row.url,
                    title: row.title,
                    bookmarkDescription: row.bookmarkDescription ?? null,
                    thumbnailUrl: row.thumbnailUrl ?? null,
                    note: row.note ?? null,
                    tags: row.tags,
                    siteName: row.siteName ?? null,
                    favicon: row.favicon ?? null,
                    aiSummary: row.aiSummary ?? null,
                    createdAt: row.createdAt,
                    addedByName: names.get(addedBy),
                });
            }

            results.push({
                localId: collection.localId,
                collectionId: collection._id,
                shareCode: collection.shareCode,
                defaultRole: collection.defaultRole ?? 'viewer',
                updatedAt: collection.updatedAt,
                participants,
                contributions,
            });
        }

        return results;
    },
});

/** Removes a participant. Owner only. */
const grantableRole = v.union(v.literal('viewer'), v.literal('editor'));

/**
 * Changes the role handed to people who redeem the link from now on.
 *
 * Existing members keep whatever they already have — downgrading a link should
 * not silently strip access someone is already relying on. Use `setMemberRole`
 * to change an individual.
 */
export const setDefaultRole = mutation({
    args: {
        sharedCollectionId: v.id('sharedCollections'),
        role: grantableRole,
    },
    handler: async (ctx, args) => {
        const callerId = await requireCallerClerkId(ctx);
        const collection = await ctx.db.get(args.sharedCollectionId);
        if (!collection || collection.ownerClerkId !== callerId) {
            throw new Error('not_authorized');
        }

        await ctx.db.patch(args.sharedCollectionId, { defaultRole: args.role });
        return null;
    },
});

/**
 * Changes one member's role.
 *
 * Ownership is not transferable here: the owner row is what proves who may
 * administer the share, so it stays put.
 */
export const setMemberRole = mutation({
    args: {
        sharedCollectionId: v.id('sharedCollections'),
        clerkId: v.string(),
        role: grantableRole,
    },
    handler: async (ctx, args) => {
        const callerId = await requireCallerClerkId(ctx);
        const collection = await ctx.db.get(args.sharedCollectionId);
        if (!collection || collection.ownerClerkId !== callerId) {
            throw new Error('not_authorized');
        }
        if (args.clerkId === collection.ownerClerkId) {
            throw new Error('cannot_change_owner');
        }

        const membership = await ctx.db
            .query('collectionMembers')
            .withIndex('by_collection_user', (q) =>
                q.eq('sharedCollectionId', args.sharedCollectionId).eq('clerkId', args.clerkId),
            )
            .unique();

        if (!membership) {
            throw new Error('member_not_found');
        }

        await ctx.db.patch(membership._id, { role: args.role });
        return null;
    },
});

/** The roles allowed to add to a collection they do not own. */
const EDITOR_ROLES = ['owner', 'editor'];

/**
 * Adds a bookmark to a shared collection.
 *
 * Open to editors as well as the owner, which is the point of the role. The row
 * records who added it so publish leaves it alone and so it can be attributed
 * in the list.
 */
export const addSharedBookmark = mutation({
    args: {
        sharedCollectionId: v.id('sharedCollections'),
        url: v.string(),
        title: v.string(),
        bookmarkDescription: nullableString,
        thumbnailUrl: nullableString,
        siteName: nullableString,
        tags: v.optional(v.array(v.string())),
    },
    handler: async (ctx, args) => {
        const clerkId = await requireCallerClerkId(ctx);
        const collection = await ctx.db.get(args.sharedCollectionId);
        if (!collection || collection.revoked) {
            throw new Error('share_not_found');
        }

        const membership = await ctx.db
            .query('collectionMembers')
            .withIndex('by_collection_user', (q) =>
                q.eq('sharedCollectionId', args.sharedCollectionId).eq('clerkId', clerkId),
            )
            .unique();

        if (!membership || !EDITOR_ROLES.includes(membership.role)) {
            throw new Error('not_authorized');
        }

        const url = args.url.trim();
        if (!url) {
            throw new Error('url_required');
        }

        // The client caps this too, but the server is what protects everyone
        // else in the collection from one oversized row.
        const TITLE_LIMIT = 200;
        const title = (args.title.trim() || url).slice(0, TITLE_LIMIT);

        // New rows go to the end, after whatever is already there.
        const siblings = await ctx.db
            .query('sharedBookmarks')
            .withIndex('by_collection', (q) => q.eq('sharedCollectionId', args.sharedCollectionId))
            .collect();
        const nextOrder = siblings.reduce((max, row) => Math.max(max, row.displayOrder), -1) + 1;

        await ctx.db.insert('sharedBookmarks', {
            sharedCollectionId: args.sharedCollectionId,
            addedByClerkId: clerkId,
            url,
            title,
            bookmarkDescription: orUndefined(args.bookmarkDescription),
            thumbnailUrl: orUndefined(args.thumbnailUrl),
            note: undefined,
            tags: args.tags ?? [],
            siteName: orUndefined(args.siteName),
            favicon: undefined,
            aiSummary: undefined,
            displayOrder: nextOrder,
            createdAt: Date.now(),
        });

        await ctx.db.patch(args.sharedCollectionId, { updatedAt: Date.now() });

        // The owner is skipped by listSharedWithMe, so a contribution is easy to
        // miss even once myShares surfaces it. Tell them it arrived.
        const contributor = await ctx.db
            .query('user')
            .withIndex('by_clerkId', (q) => q.eq('clerkId', clerkId))
            .unique();
        await notifyOwner(ctx, {
            ownerClerkId: collection.ownerClerkId,
            kind: 'bookmark_added',
            title: collection.name,
            body: `${contributor?.displayName ?? contributor?.username ?? 'メンバー'}さんが「${title}」を追加しました`,
        });

        return null;
    },
});

/**
 * Removes a bookmark from a shared collection.
 *
 * An editor may take back what they added; the owner may remove anything. An
 * editor cannot delete the owner's rows — those mirror the owner's own
 * collection, and removing one here would be undone by the next publish anyway.
 */
export const removeSharedBookmark = mutation({
    args: { bookmarkId: v.id('sharedBookmarks') },
    handler: async (ctx, args) => {
        const clerkId = await requireCallerClerkId(ctx);
        const bookmark = await ctx.db.get(args.bookmarkId);
        if (!bookmark) {
            return null;
        }

        const collection = await ctx.db.get(bookmark.sharedCollectionId);
        if (!collection) {
            return null;
        }

        const isOwner = collection.ownerClerkId === clerkId;
        const isAuthor = bookmark.addedByClerkId === clerkId;
        if (!isOwner && !isAuthor) {
            throw new Error('not_authorized');
        }

        await ctx.db.delete(args.bookmarkId);
        await ctx.db.patch(bookmark.sharedCollectionId, { updatedAt: Date.now() });
        return null;
    },
});

export const removeMember = mutation({
    args: {
        sharedCollectionId: v.id('sharedCollections'),
        clerkId: v.string(),
    },
    handler: async (ctx, args) => {
        const callerId = await requireCallerClerkId(ctx);
        const collection = await ctx.db.get(args.sharedCollectionId);
        if (!collection || collection.ownerClerkId !== callerId) {
            throw new Error('not_authorized');
        }

        const membership = await ctx.db
            .query('collectionMembers')
            .withIndex('by_collection_user', (q) =>
                q.eq('sharedCollectionId', args.sharedCollectionId).eq('clerkId', args.clerkId),
            )
            .unique();

        if (membership && membership.role !== 'owner') {
            await ctx.db.delete(membership._id);
        }
        return null;
    },
});
