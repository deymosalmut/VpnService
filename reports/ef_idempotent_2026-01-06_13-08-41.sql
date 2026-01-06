CREATE TABLE IF NOT EXISTS "__EFMigrationsHistory" (
    "MigrationId" character varying(150) NOT NULL,
    "ProductVersion" character varying(32) NOT NULL,
    CONSTRAINT "PK___EFMigrationsHistory" PRIMARY KEY ("MigrationId")
);

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE TABLE "RefreshTokens" (
        "Id" uuid NOT NULL,
        "TokenHash" character varying(512) NOT NULL,
        "DeviceId" character varying(255) NOT NULL,
        "ExpiresAt" timestamp with time zone NOT NULL,
        "CreatedAt" timestamp with time zone NOT NULL DEFAULT (CURRENT_TIMESTAMP),
        "IsRevoked" boolean NOT NULL DEFAULT FALSE,
        CONSTRAINT "PK_RefreshTokens" PRIMARY KEY ("Id")
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE TABLE "VpnServers" (
        "Id" uuid NOT NULL,
        "Name" character varying(255) NOT NULL,
        "Gateway" character varying(50) NOT NULL,
        "Network" character varying(50) NOT NULL,
        "CreatedAt" timestamp with time zone NOT NULL DEFAULT (CURRENT_TIMESTAMP),
        CONSTRAINT "PK_VpnServers" PRIMARY KEY ("Id")
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE TABLE "VpnPeers" (
        "Id" uuid NOT NULL,
        "PublicKey" character varying(512) NOT NULL,
        "AssignedIp" character varying(50) NOT NULL,
        "Status" integer NOT NULL,
        "CreatedAt" timestamp with time zone NOT NULL DEFAULT (CURRENT_TIMESTAMP),
        "UpdatedAt" timestamp with time zone,
        "VpnServerId" uuid NOT NULL,
        CONSTRAINT "PK_VpnPeers" PRIMARY KEY ("Id"),
        CONSTRAINT "FK_VpnPeers_VpnServers_VpnServerId" FOREIGN KEY ("VpnServerId") REFERENCES "VpnServers" ("Id") ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE INDEX "IX_RefreshTokens_DeviceId" ON "RefreshTokens" ("DeviceId");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE UNIQUE INDEX "IX_RefreshTokens_TokenHash" ON "RefreshTokens" ("TokenHash");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE UNIQUE INDEX "IX_VpnPeers_AssignedIp" ON "VpnPeers" ("AssignedIp");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE UNIQUE INDEX "IX_VpnPeers_PublicKey" ON "VpnPeers" ("PublicKey");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE INDEX "IX_VpnPeers_VpnServerId" ON "VpnPeers" ("VpnServerId");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    CREATE UNIQUE INDEX "IX_VpnServers_Name" ON "VpnServers" ("Name");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20260106130133_Initial_20260106_130108') THEN
    INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
    VALUES ('20260106130133_Initial_20260106_130108', '9.0.0');
    END IF;
END $EF$;
COMMIT;

