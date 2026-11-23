import { createHash } from "node:crypto";
import forge from "node-forge";
import { zip } from "./zip.js";

/** The Pass Type ID certificate and its key, plus Apple's intermediate (WWDR G4), all PEM. */
export interface PassCredentials {
  cert: string;
  key: string;
  wwdr: string;
}

/**
 * A signed .pkpass: the files, a manifest of their SHA-1s, and a detached PKCS #7 signature of the manifest made
 * with the Pass Type ID certificate. Wallet refuses a pass whose signature or manifest does not match.
 */
export function signedPass(files: ReadonlyMap<string, Buffer>, creds: PassCredentials): Buffer {
  const manifest: Record<string, string> = {};
  for (const [name, data] of files) manifest[name] = createHash("sha1").update(data).digest("hex");
  const manifestJson = Buffer.from(JSON.stringify(manifest), "utf8");

  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(manifestJson.toString("binary"));
  const cert = forge.pki.certificateFromPem(creds.cert);
  p7.addCertificate(cert);
  p7.addCertificate(forge.pki.certificateFromPem(creds.wwdr));
  p7.addSigner({
    key: forge.pki.privateKeyFromPem(creds.key),
    certificate: cert,
    digestAlgorithm: forge.pki.oids["sha256"]!,
    authenticatedAttributes: [
      { type: forge.pki.oids["contentType"]!, value: forge.pki.oids["data"]! },
      { type: forge.pki.oids["messageDigest"]! },
      { type: forge.pki.oids["signingTime"]!, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: true });
  const signature = Buffer.from(forge.asn1.toDer(p7.toAsn1()).getBytes(), "binary");

  return zip(new Map([...files, ["manifest.json", manifestJson], ["signature", signature]]));
}

/** PEM as given, or a PEM pasted base64-encoded into one line (easier in a hosting dashboard). */
export function pem(value: string): string {
  const v = value.trim();
  return v.startsWith("-----BEGIN") ? v : Buffer.from(v, "base64").toString("utf8").trim();
}
