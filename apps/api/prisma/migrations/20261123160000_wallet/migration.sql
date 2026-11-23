-- AlterTable
ALTER TABLE "LoyaltyCard" ADD COLUMN "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- CreateTable
CREATE TABLE "WalletRegistration" (
    "id" UUID NOT NULL,
    "deviceId" TEXT NOT NULL,
    "pushToken" TEXT NOT NULL,
    "cardId" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WalletRegistration_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "WalletRegistration_cardId_idx" ON "WalletRegistration"("cardId");

-- CreateIndex
CREATE UNIQUE INDEX "WalletRegistration_deviceId_cardId_key" ON "WalletRegistration"("deviceId", "cardId");

-- AddForeignKey
ALTER TABLE "WalletRegistration" ADD CONSTRAINT "WalletRegistration_cardId_fkey" FOREIGN KEY ("cardId") REFERENCES "LoyaltyCard"("id") ON DELETE CASCADE ON UPDATE CASCADE;
