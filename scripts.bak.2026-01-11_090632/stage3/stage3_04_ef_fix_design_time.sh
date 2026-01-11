#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/vpn-service}"
cd "$REPO_ROOT"

source "scripts/lib/report.sh"
source "scripts/lib/appdb.sh"

APP_DB_ENV="${APP_DB_ENV:-$REPO_ROOT/infra/local/app-db.env}"
APP_LOCAL_ENV="${APP_LOCAL_ENV:-$REPO_ROOT/infra/local/app.env}"

INFRA_CSPROJ="./VpnService.Infrastructure/VpnService.Infrastructure.csproj"
FACTORY_FILE="./VpnService.Infrastructure/Persistence/VpnDbContextFactory.cs"

report_init "stage34_ef_fix_design_time"

rc=0
{
  section "Stage 3.4 — EF FIX (design-time)"

  run_step "Precheck: infrastructure csproj exists" bash -lc "
    cd '$REPO_ROOT'
    test -f '$INFRA_CSPROJ'
  "

  run_step "Load app DB env (normalize)" bash -lc "
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    echo \"PG_HOST=\$PG_HOST PG_PORT=\$PG_PORT PG_DATABASE=\$PG_DATABASE PG_USER=\$PG_USER PG_PASSWORD=\${PG_PASSWORD:+SET}\"
  "

  # Persist startup project to Infrastructure (so migrations scripts use it)
  run_step "Persist APP_CSPROJ=Infrastructure" bash -lc "
    cd '$REPO_ROOT'
    mkdir -p 'infra/local'
    cat > 'infra/local/app.env' <<EOT
# local app settings (gitignored)
export APP_CSPROJ=\"$INFRA_CSPROJ\"
EOT
  "

  section "Patch csproj: ensure Microsoft.EntityFrameworkCore.Design referenced"
  run_step_tee "Add EFCore.Design package reference if missing" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    f='$INFRA_CSPROJ'

    if grep -q 'Microsoft.EntityFrameworkCore.Design' \"\$f\"; then
      echo 'OK already references Microsoft.EntityFrameworkCore.Design'
      exit 0
    fi

    # Insert into first ItemGroup that has PackageReference, otherwise create new ItemGroup before closing Project.
    python3 - <<'PY'
from pathlib import Path
import re

p = Path('$INFRA_CSPROJ')
s = p.read_text(encoding='utf-8', errors='ignore')

pkg = '    <PackageReference Include=\"Microsoft.EntityFrameworkCore.Design\" Version=\"9.0.11\">\\n      <PrivateAssets>all</PrivateAssets>\\n      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>\\n    </PackageReference>\\n'

if 'Microsoft.EntityFrameworkCore.Design' in s:
    print('already present')
    raise SystemExit(0)

# Try to inject into an existing ItemGroup containing PackageReference
m = re.search(r'(<ItemGroup>\\s*(?:.|\\n)*?<PackageReference[^>]+>)(?:.|\\n)*?</ItemGroup>', s)
if m:
    # inject before closing </ItemGroup> of that first match
    start = m.start()
    end = m.end()
    block = s[start:end]
    block2 = re.sub(r'(</ItemGroup>)', pkg + r'\\1', block, count=1)
    s = s[:start] + block2 + s[end:]
else:
    # create new ItemGroup before </Project>
    s = re.sub(r'(</Project>)', f'  <ItemGroup>\\n{pkg}  </ItemGroup>\\n\\1', s, count=1)

p.write_text(s, encoding='utf-8')
print('patched', p)
PY
  "

  section "Add design-time DbContext factory (no DI required)"
  run_step_tee "Create VpnDbContextFactory.cs if missing" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'

    if [[ -f '$FACTORY_FILE' ]]; then
      echo 'OK factory already exists:' '$FACTORY_FILE'
      exit 0
    fi

    mkdir -p \"$(dirname "$FACTORY_FILE")\"

    cat > '$FACTORY_FILE' <<'CS'
using System;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;
using VpnService.Infrastructure.Persistence;

namespace VpnService.Infrastructure.Persistence
{
    /// <summary>
    /// Design-time factory for EF Core tools (dotnet ef).
    /// Keeps migrations workable without relying on DI/host startup.
    /// </summary>
    public sealed class VpnDbContextFactory : IDesignTimeDbContextFactory<VpnDbContext>
    {
        public VpnDbContext CreateDbContext(string[] args)
        {
            var host = GetEnv(\"PG_HOST\", \"127.0.0.1\");
            var port = GetEnv(\"PG_PORT\", \"5432\");
            var db   = GetEnv(\"PG_DATABASE\", GetEnv(\"PG_DB\", \"vpnservice\"));
            var user = GetEnv(\"PG_USER\", \"vpnservice\");
            var pass = GetEnv(\"PG_PASSWORD\", \"\");

            if (string.IsNullOrWhiteSpace(pass))
                throw new InvalidOperationException(\"PG_PASSWORD is empty. Provide PG_PASSWORD for design-time migrations.\");

            var conn = $\"Host={host};Port={port};Database={db};Username={user};Password={pass};Include Error Detail=true\";

            var options = new DbContextOptionsBuilder<VpnDbContext>()
                .UseNpgsql(conn)
                .Options;

            return new VpnDbContext(options);
        }

        private static string GetEnv(string key, string fallback)
            => Environment.GetEnvironmentVariable(key) is { Length: > 0 } v ? v : fallback;
    }
}
CS

    echo 'OK created:' '$FACTORY_FILE'
  "

  section "Verify EF migrations list now works (with env from app-db.env)"
  run_step_tee "dotnet ef migrations list (Infrastructure) using env" bash -lc "
    set -Eeuo pipefail
    cd '$REPO_ROOT'
    source scripts/lib/appdb.sh
    load_app_db_env '$APP_DB_ENV'
    dotnet ef migrations list --project '$INFRA_CSPROJ' --startup-project '$INFRA_CSPROJ'
  "

  section "DONE"
} || rc=$?

maybe_commit_report_on_fail "$rc"
exit "$rc"
