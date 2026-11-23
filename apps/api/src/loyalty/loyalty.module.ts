import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { RateLimiter } from "../search/rate-limiter.js";
import {
  LoyaltyAdminController,
  LoyaltyCardsController,
  LoyaltyStaffController,
} from "./loyalty.controller.js";
import { APP_CONFIG, type AppConfig } from "../config.js";
import { ApnsPassPusher } from "../wallet/apns.js";
import { pem } from "../wallet/sign.js";
import { WalletController } from "../wallet/wallet.controller.js";
import { PASS_PUSHER, WalletService } from "../wallet/wallet.service.js";
import { LoyaltyService } from "./loyalty.service.js";

/**
 * Darb loyalty: partners' offers, visitors' anonymous cards, and stamps given at the counter. The card lives in
 * Apple Wallet, which this module also serves and wakes when a stamp lands.
 */
@Module({
  imports: [AuthModule],
  controllers: [
    LoyaltyCardsController,
    LoyaltyStaffController,
    LoyaltyAdminController,
    WalletController,
  ],
  providers: [
    LoyaltyService,
    RateLimiter,
    WalletService,
    {
      provide: PASS_PUSHER,
      inject: [APP_CONFIG],
      useFactory: (config: AppConfig) => {
        const { cert, key, passType } = config.wallet;
        return cert && key
          ? new ApnsPassPusher({ cert: pem(cert), key: pem(key), wwdr: "" }, passType)
          : null;
      },
    },
  ],
})
export class LoyaltyModule {}
