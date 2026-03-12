#!/bin/sh
set -eu

app_name="${APP_NAME:-ecs-bg-deployment}"
app_version="${APP_VERSION:-v1}"
container_hostname="$(hostname)"
rendered_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

case "$app_version" in
  v1|blue*)
    deploy_label="Blue"
    accent="#0f766e"
    surface="#ecfeff"
    edge="#99f6e4"
    ;;
  v2|green*)
    deploy_label="Green"
    accent="#166534"
    surface="#f0fdf4"
    edge="#86efac"
    ;;
  *)
    deploy_label="Preview"
    accent="#92400e"
    surface="#fffbeb"
    edge="#fcd34d"
    ;;
esac

cat > /usr/share/nginx/html/index.html <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${app_name}</title>
    <style>
      :root {
        --accent: ${accent};
        --surface: ${surface};
        --edge: ${edge};
        --ink: #111827;
        --muted: #4b5563;
        --bg: #f8fafc;
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        font-family: "Avenir Next", Avenir, "Segoe UI", sans-serif;
        color: var(--ink);
        background:
          radial-gradient(circle at top left, rgba(255, 255, 255, 0.9), transparent 40%),
          linear-gradient(135deg, var(--surface), var(--bg));
        min-height: 100vh;
      }

      main {
        max-width: 960px;
        margin: 0 auto;
        padding: 48px 20px 64px;
      }

      .hero {
        border: 1px solid var(--edge);
        border-radius: 28px;
        padding: 32px;
        background: rgba(255, 255, 255, 0.92);
        box-shadow: 0 20px 50px rgba(15, 23, 42, 0.08);
      }

      .eyebrow {
        display: inline-block;
        padding: 8px 12px;
        border-radius: 999px;
        background: var(--surface);
        color: var(--accent);
        font-size: 0.8rem;
        font-weight: 700;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      h1 {
        margin: 20px 0 12px;
        font-size: clamp(2.4rem, 5vw, 4.4rem);
        line-height: 0.95;
      }

      p {
        margin: 0;
        color: var(--muted);
        font-size: 1.05rem;
      }

      .accent-strip {
        margin-top: 28px;
        height: 16px;
        border-radius: 999px;
        background:
          linear-gradient(90deg, var(--accent) 0 70%, rgba(255, 255, 255, 0.6) 70% 100%);
      }

      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
        gap: 16px;
        margin-top: 28px;
      }

      .card {
        padding: 18px;
        border-radius: 18px;
        background: rgba(248, 250, 252, 0.9);
        border: 1px solid rgba(148, 163, 184, 0.22);
      }

      .label {
        display: block;
        margin-bottom: 8px;
        font-size: 0.75rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--muted);
      }

      .value {
        font-size: 1.15rem;
        font-weight: 700;
        word-break: break-word;
      }

      .footer {
        margin-top: 24px;
        color: var(--muted);
        font-size: 0.95rem;
      }

      @media (max-width: 640px) {
        main {
          padding-top: 32px;
        }

        .hero {
          padding: 24px;
        }
      }
    </style>
  </head>
  <body>
    <main>
      <section class="hero">
        <span class="eyebrow">ECS Built-in Blue/Green</span>
        <h1>${app_name}</h1>
        <p>This page is intentionally easy to compare during a deployment. The accent and metadata change with the image tag.</p>
        <div class="accent-strip" aria-hidden="true"></div>
        <div class="grid">
          <article class="card">
            <span class="label">Version</span>
            <div class="value">${app_version}</div>
          </article>
          <article class="card">
            <span class="label">Deployment Color</span>
            <div class="value">${deploy_label}</div>
          </article>
          <article class="card">
            <span class="label">Hostname</span>
            <div class="value">${container_hostname}</div>
          </article>
          <article class="card">
            <span class="label">Rendered At</span>
            <div class="value">${rendered_at}</div>
          </article>
        </div>
        <p class="footer">Open the production and test listener endpoints during rollout to verify which task set is serving traffic.</p>
      </section>
    </main>
  </body>
</html>
EOF

exec "$@"
