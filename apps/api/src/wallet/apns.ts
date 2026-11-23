import { connect } from "node:http2";
import type { PassCredentials } from "./sign.js";

/** Wakes the phones holding a pass, so Wallet fetches the new one. Returns the tokens Apple says are gone. */
export interface PassPusher {
  push(tokens: string[]): Promise<string[]>;
}

/**
 * Apple Push for Wallet: an empty message per phone, sent with the Pass Type ID certificate itself (no separate
 * push key) and the pass type as the topic.
 */
export class ApnsPassPusher implements PassPusher {
  constructor(
    private readonly creds: PassCredentials,
    private readonly topic: string,
    private readonly host = "https://api.push.apple.com",
  ) {}

  async push(tokens: string[]): Promise<string[]> {
    if (tokens.length === 0) return [];
    const session = connect(this.host, { cert: this.creds.cert, key: this.creds.key });
    session.on("error", () => {});
    const gone: string[] = [];
    try {
      await Promise.all(
        tokens.map(
          (token) =>
            new Promise<void>((resolve) => {
              const req = session.request({
                ":method": "POST",
                ":path": `/3/device/${token}`,
                "apns-topic": this.topic,
                "content-type": "application/json",
              });
              req.setTimeout(10_000, () => req.close());
              req.on("response", (headers) => {
                if (headers[":status"] === 410) gone.push(token);
              });
              req.on("error", () => resolve());
              req.on("close", () => resolve());
              req.resume();
              req.end("{}");
            }),
        ),
      );
    } finally {
      session.close();
    }
    return gone;
  }
}

/** For tests and for a server without the certificate: remembers what it was asked to wake. */
export class RecordingPusher implements PassPusher {
  readonly sent: string[][] = [];
  push(tokens: string[]): Promise<string[]> {
    this.sent.push(tokens);
    return Promise.resolve([]);
  }
}
