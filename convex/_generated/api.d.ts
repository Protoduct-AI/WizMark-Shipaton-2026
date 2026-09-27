/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as aiExtract from "../aiExtract.js";
import type * as feedback from "../feedback.js";
import type * as gemini from "../gemini.js";
import type * as http from "../http.js";
import type * as notifications from "../notifications.js";
import type * as rateLimit from "../rateLimit.js";
import type * as revenuecat from "../revenuecat.js";
import type * as shares from "../shares.js";
import type * as users from "../users.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  aiExtract: typeof aiExtract;
  feedback: typeof feedback;
  gemini: typeof gemini;
  http: typeof http;
  notifications: typeof notifications;
  rateLimit: typeof rateLimit;
  revenuecat: typeof revenuecat;
  shares: typeof shares;
  users: typeof users;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
