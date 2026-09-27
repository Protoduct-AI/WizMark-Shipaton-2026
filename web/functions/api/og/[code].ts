/**
 * Draws the link-preview image for an invitation.
 *
 * A shared screenshot of the app says nothing about which collection is being
 * shared, so the card carries the collection name, who shared it, and how many
 * bookmarks are inside.
 *
 * SVG rather than a rendered PNG: the platforms that matter accept it, and it
 * avoids pulling a rasteriser and font files into a Worker that would otherwise
 * have no dependencies. The collection's own colour tints the card, so two
 * invitations from the same person still look different.
 */

interface SharePreview {
    name: string;
    icon: string | null;
    color: string | null;
    ownerName: string | null;
    bookmarkCount: number;
}

const CONVEX_SITE_URL = 'https://vibrant-basilisk-719.convex.site';
const DEFAULT_ACCENT = '#4C7DF0';

export const onRequestGet: PagesFunction = async ({ params }) => {
    const code = String(params.code ?? '');
    const preview = await loadPreview(code);

    return new Response(render(preview), {
        headers: {
            'content-type': 'image/svg+xml; charset=utf-8',
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
        return res.ok ? ((await res.json()) as SharePreview) : null;
    } catch {
        return null;
    }
}

function render(preview: SharePreview | null): string {
    const accent = normaliseColour(preview?.color) ?? DEFAULT_ACCENT;
    const name = preview?.name ?? 'WizMark';
    const owner = preview?.ownerName?.trim();
    const count = preview?.bookmarkCount ?? 0;

    const eyebrow = owner ? `${owner} さんが共有しています` : 'コレクションへの招待';
    const footer = `ブックマーク ${count} 件 · WizMark`;

    // Two lines is all that fits at this size without the name shrinking to
    // something unreadable in a timeline.
    const lines = wrap(name, 15, 2);

    return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0B0D18"/>
      <stop offset="100%" stop-color="#141A2E"/>
    </linearGradient>
    <linearGradient id="accent" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="${accent}"/>
      <stop offset="100%" stop-color="${accent}" stop-opacity="0.35"/>
    </linearGradient>
  </defs>

  <rect width="1200" height="630" fill="url(#bg)"/>
  <rect width="1200" height="8" fill="url(#accent)"/>
  <circle cx="1080" cy="120" r="220" fill="${accent}" opacity="0.10"/>

  <text x="90" y="150" font-family="Hiragino Sans, Hiragino Kaku Gothic ProN, sans-serif"
        font-size="30" fill="${accent}">${escapeXml(eyebrow)}</text>

${lines
    .map(
        (line, index) =>
            `  <text x="90" y="${268 + index * 92}" font-family="Hiragino Sans, Hiragino Kaku Gothic ProN, sans-serif" font-size="76" font-weight="bold" fill="#FFFFFF">${escapeXml(line)}</text>`,
    )
    .join('\n')}

  <text x="90" y="540" font-family="Hiragino Sans, Hiragino Kaku Gothic ProN, sans-serif"
        font-size="30" fill="#9AA4C8">${escapeXml(footer)}</text>
</svg>`;
}

/** Accepts the `#RRGGBB` the app stores, and refuses anything else. */
function normaliseColour(value: string | null | undefined): string | null {
    if (!value) return null;
    return /^#[0-9a-fA-F]{6}$/.test(value) ? value : null;
}

/**
 * Breaks a title into at most `maxLines`, counting CJK characters as full width
 * so a Japanese name does not overflow at the same character count as a Latin
 * one. The last line is elided when there is more text than fits.
 */
function wrap(text: string, perLine: number, maxLines: number): string[] {
    const lines: string[] = [];
    let current = '';
    let width = 0;

    for (const char of text) {
        const charWidth = /[　-鿿＀-￯]/.test(char) ? 1 : 0.55;
        if (width + charWidth > perLine && current) {
            lines.push(current);
            if (lines.length === maxLines) {
                return elide(lines, text);
            }
            current = '';
            width = 0;
        }
        current += char;
        width += charWidth;
    }
    if (current) lines.push(current);
    return lines.length ? lines.slice(0, maxLines) : ['WizMark'];
}

function elide(lines: string[], full: string): string[] {
    const shown = lines.join('');
    if (shown.length >= full.length) return lines;
    const last = lines[lines.length - 1];
    lines[lines.length - 1] = last.slice(0, Math.max(0, last.length - 1)) + '…';
    return lines;
}

function escapeXml(value: string): string {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}
