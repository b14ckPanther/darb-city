import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { RateLimiter } from "../search/rate-limiter.js";
import {
  LoyaltyAdminController,
  LoyaltyCardsController,
  LoyaltyStaffController,
} from "./loyalty.controller.js";
import { LoyaltyService } from "./loyalty.service.js";

/** Darb loyalty: partners' offers, visitors' anonymous cards, and stamps given at the counter. */
@Module({
  imports: [AuthModule],
  controllers: [LoyaltyCardsController, LoyaltyStaffController, LoyaltyAdminController],
  providers: [LoyaltyService, RateLimiter],
})
export class LoyaltyModule {}
