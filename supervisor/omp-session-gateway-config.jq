# Renders omp-session-gateway's config.json for cloudflare-access mode from OMP_GATEWAY_* in .env.
# Mirrors omp-session-gateway/examples/gateway-config.cloudflare-access.jsonc; `make init-omp-gateway` runs it.
{
  http: {
    hostname: "127.0.0.1",
    port: 4317,
    publicOrigin: env.OMP_GATEWAY_ORIGIN
  },
  auth: {
    mode: "cloudflare-access",
    allowedLogins: (env.OMP_GATEWAY_ALLOWED_LOGINS | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))),
    cloudflareAccess: {
      teamDomain: env.OMP_GATEWAY_TEAM_DOMAIN,
      audience: env.OMP_GATEWAY_AUDIENCE
    }
  },
  registry: {
    heartbeatSeconds: 10,
    ttlSeconds: 35,
    maxSessions: 100
  },
  speech: {
    browserRecognition: false
  }
}
