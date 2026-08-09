# Nina Web

Landing page, convites e preferências de email da Nina.

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
- Segredo:
  - `NINA_SUPABASE_SECRET_KEY`: chave `sb_secret_...` dedicada ao Worker, usada
    somente pelos RPCs da lista de espera.
  - `NINA_WAITLIST_HASH_SALT`: valor aleatório com pelo menos 32 caracteres,
    usado somente para gerar identificadores temporários de limite de abuso.

Crie uma chave secreta separada para o Worker no painel da Supabase, para que
ela possa ser rotacionada sem afetar outros serviços. Configure os segredos sem
registrá-los no repositório:

```bash
npx wrangler secret put NINA_SUPABASE_SECRET_KEY
npx wrangler secret put NINA_WAITLIST_HASH_SALT
```

O formulário público chama `register_waitlist_signup`, criado pela migração
`202607290001_web_waitlist.sql`. A resposta nunca informa se um email já estava
cadastrado, e o banco não recebe o endereço IP bruto. A função não pode ser
chamada pelas roles `anon` ou `authenticated`; somente o Worker autenticado como
serviço pode executá-la.

A migração `202607290003_waitlist_unsubscribe.sql` adiciona cancelamento
automático. Cada novo consentimento gira uma capacidade aleatória de uso
exclusivo para cancelamento. O link enviado por email deve ter exatamente este
formato:

```text
https://ninai.app/unsubscribe/#<unsubscribe_token>
```

O token fica no fragmento, não chega ao servidor durante o carregamento da
página e é removido do histórico antes da confirmação. Nunca mova o token para
query string, path, analytics ou logs. O remetente deve selecionar somente
linhas com `status = 'subscribed'`, montar a lista imediatamente antes do envio
e incluir esse link em todo email da lista. A integração com o provedor de email
também deve bloquear envios agendados depois que o status mudar.

Use `GET /api/health` no monitor de disponibilidade. O endpoint faz duas
sondagens somente de leitura, com timeout: uma chamada pública de convite
inexistente e o RPC de serviço `waitlist_healthcheck`. Ele retorna `200` somente
quando o Supabase está acessível, as duas chaves têm o escopo correto e o schema
esperado da lista de espera está aplicado. Configuração ausente, timeout,
resposta malformada ou migração desatualizada retorna `503`. Outros métodos
recebem `405`.

## Página de convite e caminho de instalação

`/invite/<código>` mostra três estados distintos. Um `404` do Worker significa
que o convite não vale mais e a página diz isso sem revelar o motivo, porque
`get_family_invite_preview` responde `{valid:false}` para expirado, esgotado ou
inexistente. Um `502`, um `503` ou uma falha de rede mantêm o estado
"Verificação pendente": a página nunca finge validar nem invalidar um código
quando não conseguiu consultar.

O bloco `[data-invite-install]` é renderizado no servidor a partir de
`PUBLIC_NINA_APP_STORE_ID`, uma sexta variável pública de build:

- Sem um identificador numérico real, a página informa que a Nina ainda não
  abriu e oferece a lista de espera.
- Com o identificador, ela mostra o selo local `/images/app-store-badge.svg`
  apontando para `https://apps.apple.com/br/app/id<ID>`. O selo é servido pelo
  próprio domínio porque a CSP usa `img-src 'self' data:`, e o código do convite
  nunca entra nessa URL.

Como o valor é lido no build, publicar o app na App Store exige um novo build e
deploy do site para que o caminho de instalação apareça.

## Metadados legais de produção

A política usa cinco variáveis públicas no momento do build:

- `PUBLIC_NINA_LEGAL_ENTITY_NAME`
- `PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT`
- `PUBLIC_NINA_PRIVACY_CONTACT_EMAIL`
- `PUBLIC_NINA_DPO_NAME`
- `PUBLIC_NINA_DPO_CONTACT_EMAIL`

Sem todos os valores válidos, a página se identifica explicitamente como
pré-lançamento e recebe `data-legal-status="incomplete"`. O preflight online
exige `complete`, portanto uma build sem a identidade aprovada não pode passar
pelo gate de produção. Esses valores são públicos; nenhuma chave ou segredo deve
usar o prefixo `PUBLIC_`.

O inventário local e os comandos completos estão em
`docs/production-launch-runbook.md`. Depois do deploy, execute a partir da raiz
do repositório:

```sh
npx deno task preflight:production --env-file config/production.env --online
```

Conecte `ninai.app` como domínio principal. O arquivo
`public/.well-known/apple-app-site-association` habilita Universal Links para
`/invite/*`.

Configure `www.ninai.app` no Cloudflare para redirecionar permanentemente para
`https://ninai.app`.
