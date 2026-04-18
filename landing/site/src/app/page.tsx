/**
 * TacNet landing page — Phase 1 token-verification shell.
 *
 * Purpose of this file right now: prove the token chain works.
 *   - DM Sans + JetBrains Mono load via next/font
 *   - Palette A variables resolve
 *   - 48px grid + inset page border render
 *   - Pulsing OPERATIONAL dot animates (and freezes on reduced-motion)
 *
 * Real sections (Hero, DataBand, Architecture, etc.) land in Phase 2+.
 * Spec: ../../PLAN.md
 */

export default function Home() {
  return (
    <main
      className="relative min-h-screen"
      style={{
        // Inset page border on desktop — AliasKit lift
        padding: 'clamp(0px, 2vw, 16px)',
      }}
    >
      <div
        className="relative mx-auto max-w-[1400px] border border-[color:var(--color-border)]"
        style={{ minHeight: 'calc(100vh - clamp(0px, 4vw, 32px))' }}
      >
        {/* 48px grid underlay */}
        <div
          aria-hidden
          className="bg-grid-48 pointer-events-none absolute inset-0"
        />

        <div className="relative px-6 py-16 sm:px-10 lg:px-14">
          {/* Identity strip */}
          <header className="flex items-center gap-3">
            <div
              aria-hidden
              className="pulse-op h-2 w-2 rounded-full"
              style={{ background: 'var(--color-accent)' }}
            />
            <span
              className="text-[11px] uppercase tracking-[0.14em]"
              style={{
                color: 'var(--color-accent)',
                fontFamily: 'var(--font-mono)',
              }}
            >
              Operational
            </span>
            <span
              className="text-[11px] uppercase tracking-[0.08em]"
              style={{
                color: 'var(--color-text-dim)',
                fontFamily: 'var(--font-mono)',
              }}
            >
              · Phase 1 · token verification
            </span>
          </header>

          {/* Wordmark */}
          <div className="mt-10">
            <span
              className="text-[11px] uppercase tracking-[0.18em]"
              style={{
                color: 'var(--color-text-muted)',
                fontFamily: 'var(--font-mono)',
              }}
            >
              [ Offline-first tactical comms ]
            </span>
          </div>

          {/* H1 — DM Sans display */}
          <h1
            className="mt-6 max-w-4xl font-semibold leading-[0.98]"
            style={{
              fontSize: 'clamp(2.75rem, 7vw + 1rem, 7rem)',
              letterSpacing: '-0.03em',
              color: 'var(--color-text)',
            }}
          >
            Voice. Mesh. Offline.
          </h1>

          {/* Subhead */}
          <p
            className="mt-8 max-w-2xl text-lg leading-[1.6]"
            style={{ color: 'var(--color-text-muted)' }}
          >
            Every phone runs Gemma 4 on-device and compacts its children&rsquo;s
            transmissions as summaries that climb the command tree.
            Zero servers. Zero cloud. Full spec.
          </p>

          {/* Token probe panel — proves every variable resolves */}
          <section
            className="mt-16 border"
            style={{
              borderColor: 'var(--color-border)',
              background: 'var(--color-surface)',
            }}
          >
            <div
              className="border-b px-6 py-4"
              style={{ borderColor: 'var(--color-border)' }}
            >
              <span
                className="text-[11px] uppercase tracking-[0.12em]"
                style={{
                  color: 'var(--color-text-muted)',
                  fontFamily: 'var(--font-mono)',
                }}
              >
                // design-token probe
              </span>
            </div>

            <div className="grid gap-px sm:grid-cols-2 lg:grid-cols-4" style={{ background: 'var(--color-border)' }}>
              {[
                { label: 'bg', value: '#0A0D0B', swatch: 'var(--color-bg)' },
                { label: 'surface', value: '#111511', swatch: 'var(--color-surface)' },
                { label: 'elevated', value: '#1A1F1A', swatch: 'var(--color-elevated)' },
                { label: 'border', value: '#1F251F', swatch: 'var(--color-border)' },
                { label: 'text', value: '#E8ECE9', swatch: 'var(--color-text)' },
                { label: 'text-muted', value: '#8A918C', swatch: 'var(--color-text-muted)' },
                { label: 'accent', value: '#B8FF2C', swatch: 'var(--color-accent)' },
                { label: 'signal-amber', value: '#FFB020', swatch: 'var(--color-signal-amber)' },
              ].map((t) => (
                <div
                  key={t.label}
                  className="flex items-center gap-3 p-5"
                  style={{ background: 'var(--color-surface)' }}
                >
                  <div
                    className="h-7 w-7 shrink-0 border"
                    style={{
                      background: t.swatch,
                      borderColor: 'var(--color-border-hot)',
                    }}
                  />
                  <div className="min-w-0">
                    <div
                      className="truncate text-[11px]"
                      style={{
                        color: 'var(--color-text)',
                        fontFamily: 'var(--font-mono)',
                      }}
                    >
                      --color-{t.label}
                    </div>
                    <div
                      className="text-[10px]"
                      style={{
                        color: 'var(--color-text-dim)',
                        fontFamily: 'var(--font-mono)',
                      }}
                    >
                      {t.value}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </section>

          {/* Mono readout strip */}
          <section
            className="mt-8 grid gap-px border"
            style={{
              borderColor: 'var(--color-border)',
              background: 'var(--color-border)',
              gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
            }}
          >
            {[
              { big: '4', small: 'Phones in demo' },
              { big: '0', small: 'Servers required' },
              { big: '< 2 s', small: 'Compaction latency' },
              { big: '6.7 GB', small: 'Model on-device' },
            ].map((s) => (
              <div
                key={s.small}
                className="px-6 py-6"
                style={{ background: 'var(--color-surface)' }}
              >
                <div
                  className="leading-none"
                  style={{
                    color: 'var(--color-text)',
                    fontFamily: 'var(--font-mono)',
                    fontSize: 'clamp(1.75rem, 3.2vw, 2.75rem)',
                    fontWeight: 500,
                  }}
                >
                  {s.big}
                </div>
                <div
                  className="mt-3 uppercase"
                  style={{
                    color: 'var(--color-text-muted)',
                    fontFamily: 'var(--font-mono)',
                    fontSize: '10px',
                    letterSpacing: '0.14em',
                  }}
                >
                  {s.small}
                </div>
              </div>
            ))}
          </section>

          {/* CTA stub */}
          <div className="mt-14 flex flex-wrap items-center gap-6">
            <button
              type="button"
              className="inline-flex items-center gap-2 px-5 py-3 text-sm font-medium"
              style={{
                background: 'var(--color-accent)',
                color: 'var(--color-bg)',
                borderRadius: 'var(--radius-btn)',
                fontFamily: 'var(--font-mono)',
                letterSpacing: '0.06em',
              }}
            >
              [ WATCH DEMO &rarr; ]
            </button>
            <a
              href="#"
              className="inline-flex items-center gap-2 text-sm underline-offset-4 hover:underline"
              style={{
                color: 'var(--color-text-muted)',
                fontFamily: 'var(--font-mono)',
                letterSpacing: '0.06em',
              }}
            >
              READ THE SPEC &rarr;
            </a>
          </div>

          {/* Footer note — will be replaced in Phase 3 */}
          <footer
            className="mt-24 border-t pt-6"
            style={{ borderColor: 'var(--color-border)' }}
          >
            <span
              className="text-[11px]"
              style={{
                color: 'var(--color-text-dim)',
                fontFamily: 'var(--font-mono)',
                letterSpacing: '0.06em',
              }}
            >
              Built at the YC &times; Cactus &times; Gemma 4 hackathon &middot; 2025
            </span>
          </footer>
        </div>
      </div>
    </main>
  );
}
