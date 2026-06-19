# Nina Web

Landing page e fluxo web de convites da Nina.

## Desenvolvimento

```bash
npm install
npm run dev
```

Use `npm run preview` depois de `npm run build` para executar o resultado com
Cloudflare Pages Functions.

## Cloudflare Pages

- Build command: `npm run build`
- Output directory: `dist`
- Variáveis:
  - `SUPABASE_URL`
  - `SUPABASE_PUBLISHABLE_KEY`

Conecte `ninai.app` como domínio principal. O arquivo
`public/.well-known/apple-app-site-association` habilita Universal Links para
`/invite/*`.

Configure `www.ninai.app` no Cloudflare para redirecionar permanentemente para
`https://ninai.app`. Redirecionamentos entre hosts não são aceitos no arquivo
`_redirects` do Pages.
