# Nina Web

Landing page e fluxo web de convites da Nina.

## Desenvolvimento

```bash
npm install
npm run dev
```

Use `npm run preview` depois de `npm run build` para executar o resultado com
Cloudflare Workers.

## Cloudflare Workers

- Build command: `npm run build`
- Deploy command: `npm run deploy`
- Root directory: `/web`
- Variáveis:
  - `NINA_SUPABASE_URL`
  - `NINA_SUPABASE_PUBLISHABLE_KEY`

Conecte `ninai.app` como domínio principal. O arquivo
`public/.well-known/apple-app-site-association` habilita Universal Links para
`/invite/*`.

Configure `www.ninai.app` no Cloudflare para redirecionar permanentemente para
`https://ninai.app`.
