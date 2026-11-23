import { verifyToken } from "@clerk/backend";
import type { AuthConfig } from "../config.js";
import { InvalidTokenError, type TokenVerifier, type VerifiedToken } from "./token-verifier.js";

/** Verifies Clerk session JWTs (spec §6.4: Clerk is admin-only in v1). Never logs the token. */
export class ClerkTokenVerifier implements TokenVerifier {
  constructor(
    private readonly auth: AuthConfig,
    private readonly verifyImpl: typeof verifyToken = verifyToken,
  ) {}

  async verify(token: string): Promise<VerifiedToken> {
    const key = this.auth.clerkJwtKey
      ? { jwtKey: this.auth.clerkJwtKey }
      : { secretKey: this.auth.clerkSecretKey ?? "" };
    try {
      const claims = (await this.verifyImpl(token, key)) as Record<string, unknown>;
      const sub = typeof claims["sub"] === "string" ? claims["sub"] : "";
      if (!sub) throw new Error("no subject");
      // azp is the browser origin the session token was minted for. A token from a browser must name
      // one of ours; the native iPhone app sends no origin, so its tokens carry no azp at all.
      const azp = claims["azp"];
      const parties = this.auth.authorizedParties;
      if (azp !== undefined && parties.length && !parties.includes(String(azp)))
        throw new Error("foreign origin");
      const email = typeof claims["email"] === "string" ? claims["email"].toLowerCase() : null;
      return { sub, email, emailVerified: claims["email_verified"] === true };
    } catch {
      throw new InvalidTokenError("Invalid or expired session");
    }
  }
}
