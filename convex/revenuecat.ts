const SUBSCRIBERS_ENDPOINT = 'https://api.revenuecat.com/v1/subscribers';

/** Must match PurchaseConfig.proEntitlementId in the iOS app. */
const PRO_ENTITLEMENT_ID = 'pro';

/**
 * Verify the authenticated user's Pro entitlement on the server.
 * Missing configuration, unavailable upstreams and invalid responses deny access.
 */
export async function hasProEntitlement(authenticatedUserId: string): Promise<boolean> {
    const apiKey = process.env.REVENUECAT_API_KEY;
    if (!apiKey || !authenticatedUserId) {
        console.warn('RevenueCat verification denied: missing server configuration or user identity');
        return false;
    }

    try {
        const response = await fetch(
            `${SUBSCRIBERS_ENDPOINT}/${encodeURIComponent(authenticatedUserId)}`,
            { headers: { Authorization: `Bearer ${apiKey}` } },
        );
        if (!response.ok) {
            console.warn(`RevenueCat verification denied: subscriber lookup returned ${response.status}`);
            return false;
        }
        const data = await response.json();
        const entitlement = data?.subscriber?.entitlements?.[PRO_ENTITLEMENT_ID];
        if (!entitlement || typeof entitlement !== 'object') {
            return false;
        }
        if (entitlement.expires_date === null) {
            return true;
        }
        return (
            typeof entitlement.expires_date === 'string' &&
            Date.parse(entitlement.expires_date) > Date.now()
        );
    } catch {
        // Do not log request details or credentials from upstream errors.
        console.warn('RevenueCat verification denied: subscriber lookup unavailable or invalid');
        return false;
    }
}
