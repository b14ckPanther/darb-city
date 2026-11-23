import { Module } from "@nestjs/common";
import { AppDataController } from "./app-data.controller.js";

@Module({ controllers: [AppDataController] })
export class AppDataModule {}
