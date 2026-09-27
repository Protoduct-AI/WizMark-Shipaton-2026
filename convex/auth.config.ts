import type { AuthConfig } from 'convex/server';

// Debug builds sign in against the Clerk development instance while
// TestFlight/App Store builds use the production instance, so both
// issuer domains must be accepted.
const issuerDomains = [
    process.env.CLERK_JWT_ISSUER_DOMAIN,
    process.env.CLERK_JWT_ISSUER_DOMAIN_PROD,
].filter((domain): domain is string => !!domain);

export default {
    providers: issuerDomains.map((domain) => ({
        domain,
        applicationID: 'convex',
    })),
} satisfies AuthConfig;
