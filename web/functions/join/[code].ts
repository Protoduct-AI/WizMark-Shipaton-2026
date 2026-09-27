/**
 * Serves the invitation page with link-preview tags that describe the actual
 * invitation.
 *
 * The site is a SPA, so a crawler that does not run JavaScript sees only the
 * static index.html — every invitation looked identical in a message thread,
 * advertising the app rather than saying who shared what. This function fills
 * the tags in from the share before the HTML goes out.
 *
 * The page itself is unchanged: the same index.html and the same bundle are
 * returned, so the React app still takes over and renders the real page for a
 * person. Only the head is rewritten.
 */

interface SharePreview {
    name: string;
    icon: string | null;
    color: string | null;
    ownerName: string | null;
    bookmarkCount: number;
}

const CONVEX_SITE_URL = 'https://vibrant-basilisk-719.convex.site';
const SITE_URL = 'https://wizmark.protoductai.com';

export const onRequestGet: PagesFunction = async (context) => {
    const { params, request, next } = context;
    const code = String(params.code ?? '');

    // Fetch the SPA shell exactly as it would be served without this function.
    const response = await next();
    const contentType = response.headers.get('content-type') ?? '';
    if (!contentType.includes('text/html')) {
        return response;
    }

    const preview = await loadPreview(code);
    const html = await response.text();

    return new Response(rewriteHead(html, preview, code, request), {
        status: response.status,
        headers: {
            ...Object.fromEntries(response.headers),
            'content-type': 'text/html; charset=utf-8',
            // Previews are cached hard by the platforms that read them, and the
            // collection name can change, so keep the window short.
            'cache-control': 'public, max-age=300',
        },
    });
};

async function loadPreview(code: string): Promise<SharePreview | null> {
    if (!code) return null;
    try {
        const res = await fetch(
            `${CONVEX_SITE_URL}/share-preview?code=${encodeURIComponent(code)}`,
            { cf: { cacheTtl: 60 } },
        );
        if (!res.ok) return null;
        return (await res.json()) as SharePreview;
    } catch {
        // A preview that cannot be loaded should still render the page; it just
        // falls back to the generic tags below.
        return null;
    }
}

function rewriteHead(
    html: string,
    preview: SharePreview | null,
    code: string,
    request: Request,
): string {
    const locale = preferredLocale(request);
    const url = `${SITE_URL}/join/${code}`;

    const { title, description } = describe(preview, locale);
    const image = `${SITE_URL}/api/og/${encodeURIComponent(code)}`;

    const tags = [
        `<title>${escapeHtml(title)}</title>`,
        meta('name', 'description', description),
        meta('property', 'og:type', 'website'),
        meta('property', 'og:site_name', 'WizMark'),
        meta('property', 'og:title', title),
        meta('property', 'og:description', description),
        meta('property', 'og:url', url),
        meta('property', 'og:image', image),
        meta('property', 'og:image:width', '1200'),
        meta('property', 'og:image:height', '630'),
        meta('property', 'og:locale', locale === 'ja' ? 'ja_JP' : 'en_US'),
        meta('name', 'twitter:card', 'summary_large_image'),
        meta('name', 'twitter:title', title),
        meta('name', 'twitter:description', description),
        meta('name', 'twitter:image', image),
    ].join('\n    ');

    // Drop the static tags first, otherwise crawlers that take the first match
    // would keep showing the generic ones.
    const stripped = html
        .replace(/<title>[\s\S]*?<\/title>/i, '')
        .replace(/<meta[^>]+(?:property|name)=["'](?:og:|twitter:)[^"']*["'][^>]*>/gi, '')
        .replace(/<meta[^>]+name=["']description["'][^>]*>/gi, '');

    return stripped.replace(/<\/head>/i, `    ${tags}\n  </head>`);
}

function describe(
    preview: SharePreview | null,
    locale: 'ja' | 'en',
): { title: string; description: string } {
    if (!preview) {
        return locale === 'ja'
            ? {
                  title: 'コレクションへの招待 | WizMark',
                  description: 'WizMark で共有されたコレクションの招待リンクです。',
              }
            : {
                  title: 'Collection invitation | WizMark',
                  description: 'An invitation to a collection shared on WizMark.',
              };
    }

    const owner = preview.ownerName?.trim();
    const count = preview.bookmarkCount;

    if (locale === 'ja') {
        return {
            title: owner
                ? `${owner} さんが「${preview.name}」を共有しています`
                : `「${preview.name}」への招待`,
            description: `ブックマーク ${count} 件。WizMark で開くと、そのまま閲覧できます。`,
        };
    }
    return {
        title: owner
            ? `${owner} shared "${preview.name}" with you`
            : `You are invited to "${preview.name}"`,
        description: `${count} bookmark${count === 1 ? '' : 's'}. Open it in WizMark to start reading.`,
    };
}

function preferredLocale(request: Request): 'ja' | 'en' {
    const header = request.headers.get('accept-language') ?? '';
    return header.toLowerCase().includes('ja') ? 'ja' : 'en';
}

function meta(kind: 'name' | 'property', key: string, value: string): string {
    return `<meta ${kind}="${key}" content="${escapeHtml(value)}" />`;
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}
