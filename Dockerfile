# ---------- build stage ----------
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY VpnService.sln ./
COPY VpnService.Api/VpnService.Api.csproj VpnService.Api/
COPY VpnService.Application/VpnService.Application.csproj VpnService.Application/
COPY VpnService.Domain/VpnService.Domain.csproj VpnService.Domain/
COPY VpnService.Infrastructure/VpnService.Infrastructure.csproj VpnService.Infrastructure/
COPY VpnService.Infrastructure.Abstractions/VpnService.Infrastructure.Abstractions.csproj VpnService.Infrastructure.Abstractions/

RUN dotnet restore

COPY . ./
RUN dotnet publish VpnService.Api/VpnService.Api.csproj -c Release -o /out

# ---------- runtime stage ----------
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# Needed for checks/health and WireGuard state reader
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl wireguard-tools iproute2 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /out ./

ENV ASPNETCORE_URLS=http://127.0.0.1:5272
EXPOSE 5272

HEALTHCHECK --interval=10s --timeout=2s --retries=12 \
  CMD curl -fsS http://127.0.0.1:5272/health >/dev/null || exit 1

ENTRYPOINT ["dotnet", "VpnService.Api.dll"]
