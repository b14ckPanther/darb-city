-- Darb loyalty, step 1: partners' offers, anonymous cards, stamps given at the counter, who may stamp, and
-- invite links for a partner's staff. Additive: new tables only.
-- CreateEnum
CREATE TYPE "LoyaltyEventKind" AS ENUM ('stamp', 'redeem');

-- CreateTable
CREATE TABLE "LoyaltyOffer" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "title" JSONB NOT NULL,
    "reward" JSONB NOT NULL,
    "goal" INTEGER NOT NULL,
    "cooldownMinutes" INTEGER NOT NULL DEFAULT 180,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoyaltyOffer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LoyaltyCard" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "secretHash" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoyaltyCard_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LoyaltyEvent" (
    "id" UUID NOT NULL,
    "cardId" UUID NOT NULL,
    "offerId" UUID NOT NULL,
    "kind" "LoyaltyEventKind" NOT NULL,
    "staffId" UUID NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoyaltyEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LoyaltyStaff" (
    "businessId" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "addedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoyaltyStaff_pkey" PRIMARY KEY ("businessId","userId")
);

-- CreateTable
CREATE TABLE "LoyaltyInvite" (
    "id" UUID NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "businessId" UUID NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "uses" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "LoyaltyInvite_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "LoyaltyOffer_businessId_idx" ON "LoyaltyOffer"("businessId");

-- CreateIndex
CREATE UNIQUE INDEX "LoyaltyCard_code_key" ON "LoyaltyCard"("code");

-- CreateIndex
CREATE UNIQUE INDEX "LoyaltyCard_secretHash_key" ON "LoyaltyCard"("secretHash");

-- CreateIndex
CREATE INDEX "LoyaltyEvent_cardId_offerId_at_idx" ON "LoyaltyEvent"("cardId", "offerId", "at");

-- CreateIndex
CREATE INDEX "LoyaltyEvent_offerId_at_idx" ON "LoyaltyEvent"("offerId", "at");

-- CreateIndex
CREATE INDEX "LoyaltyStaff_userId_idx" ON "LoyaltyStaff"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "LoyaltyInvite_tokenHash_key" ON "LoyaltyInvite"("tokenHash");

-- AddForeignKey
ALTER TABLE "LoyaltyOffer" ADD CONSTRAINT "LoyaltyOffer_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoyaltyEvent" ADD CONSTRAINT "LoyaltyEvent_cardId_fkey" FOREIGN KEY ("cardId") REFERENCES "LoyaltyCard"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoyaltyEvent" ADD CONSTRAINT "LoyaltyEvent_offerId_fkey" FOREIGN KEY ("offerId") REFERENCES "LoyaltyOffer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoyaltyEvent" ADD CONSTRAINT "LoyaltyEvent_staffId_fkey" FOREIGN KEY ("staffId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoyaltyStaff" ADD CONSTRAINT "LoyaltyStaff_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoyaltyStaff" ADD CONSTRAINT "LoyaltyStaff_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LoyaltyInvite" ADD CONSTRAINT "LoyaltyInvite_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "Business"("id") ON DELETE CASCADE ON UPDATE CASCADE;

