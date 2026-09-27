import { httpRouter } from 'convex/server';
import { api } from './_generated/api';
import { Webhook } from 'svix';
import { internal } from './_generated/api';
import { httpAction } from './_generated/server';

const http = httpRouter();

export const clerkUsersWebhook = httpAction(async (ctx, req) => {
    const webhookSecret = process.env.CLERK_WEBHOOK_SECRET;
    if (!webhookSecret) {
        console.error('Missing CLERK_WEBHOOK_SECRET environment variable');
        return new Response('Server configuration error', { status: 500 });
    }

    const svix_id = req.headers.get('svix-id');
    const svix_timestamp = req.headers.get('svix-timestamp');
    const svix_signature = req.headers.get('svix-signature');

    if (!svix_id || !svix_timestamp || !svix_signature) {
        return new Response('Missing svix headers', { status: 400 });
    }

    const payload = await req.text();

    const wh = new Webhook(webhookSecret);
    let evt: { type: string; data: any };

    try {
        evt = wh.verify(payload, {
            'svix-id': svix_id,
            'svix-timestamp': svix_timestamp,
            'svix-signature': svix_signature,
        }) as { type: string; data: any };
    } catch (err) {
        console.error('Webhook signature verification failed:', err);
        return new Response('Invalid signature', { status: 401 });
    }

    const { type, data } = evt;

    switch (type) {
        case 'user.created':
            await ctx.runMutation(internal.users.createUser, {
                email: data.email_addresses?.[0]?.email_address ?? '',
                clerkId: data.id,
            });
            break;
        case 'user.updated':
            await ctx.runMutation(internal.users.syncEmail, {
                clerkId: data.id,
                email: data.email_addresses?.[0]?.email_address ?? '',
            });
            break;
        case 'user.deleted':
            await ctx.runMutation(internal.users.deleteUserByClerkId, {
                clerkId: data.id,
            });
            break;
        default:
            console.log('Unknown event type:', type);
    }

    return new Response('Webhook processed', { status: 200 });
});

http.route({
    path: '/clerk-users-webhook',
    method: 'POST',
    handler: clerkUsersWebhook,
});

/**
 * Public preview of an invitation, for the web landing page.
 *
 * Someone who taps an invite link without the app installed lands on the site,
 * which needs to say what the invitation is for. Only the collection name,
 * owner name and bookmark count are exposed, and only for a live share.
 */
export const sharePreviewHandler = httpAction(async (ctx, req) => {
    const shareCode = new URL(req.url).searchParams.get('code');

    const cors = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=60',
    };

    if (!shareCode) {
        return new Response(JSON.stringify({ error: 'missing_code' }), {
            status: 400,
            headers: cors,
        });
    }

    const preview = await ctx.runQuery(api.shares.preview, { shareCode });
    if (!preview) {
        return new Response(JSON.stringify({ error: 'not_found' }), {
            status: 404,
            headers: cors,
        });
    }

    return new Response(JSON.stringify(preview), { status: 200, headers: cors });
});

http.route({
    path: '/share-preview',
    method: 'GET',
    handler: sharePreviewHandler,
});

http.route({
    path: '/share-preview',
    method: 'OPTIONS',
    handler: httpAction(async () => {
        return new Response(null, {
            status: 204,
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type',
            },
        });
    }),
});

export default http;
