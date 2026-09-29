# Nina Web

Landing page, Termos, Política de Privacidade, a página para famílias, o canal de
denúncia, convites e preferências de email da Nina.

## Desenvolvimento

```bash
npm install
npm run dev
```

Use `npm run preview` depois de `npm run build` para executar o resultado com
Cloudflare Workers.

## Design

O site usa o mesmo sistema azulejo do app e é claro por construção: a paleta em
`src/styles/global.css` vem de `Nina/Theme.swift`, a marca em
`src/components/NinaMark.astro` vem de `Nina/NinaMark.swift` (dois desenhos, um
acima e outro abaixo de 34px) e `public/fonts/Fraunces-Regular.ttf` é uma cópia
byte a byte da fonte que o app empacota. Não existe modo escuro porque não existe
paleta escura desenhada.

Não há biblioteca de ícones. `src/components/Glyph.astro` guarda os desenhos de
contorno usados no site; `astro-icon` foi removido porque uma dependência dele
reprova o `npm audit --audit-level=high` que a CI executa.

Os telefones das seções são desenhados em HTML, não são capturas de tela: as
capturas antigas mostravam o app anterior ao redesenho e uma captura fica velha
sozinha. As diferenças em relação às pranchas do Paper estão em
`docs/rebrand-web.md`.

## Cloudflare Workers

- Build command: `npm run build`
- Deploy command: `npm run deploy`
- Root directory: `/web`
- Variáveis:
  - `NINA_SUPABASE_URL`
  - `NINA_SUPABASE_PUBLISHABLE_KEY`
- Variáveis de build (identidade legal, publicada desde 2026-09-26):
  `PUBLIC_NINA_LEGAL_ENTITY_NAME`, `PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT`,
  `PUBLIC_NINA_DPO_NAME`, `PUBLIC_NINA_PRIVACY_CONTACT_EMAIL` e
  `PUBLIC_NINA_DPO_CONTACT_EMAIL`, mais `PUBLIC_NINA_LEGAL_ENTITY_ADDRESS` e
  `PUBLIC_NINA_REPORT_CONTACT_EMAIL` desde 2026-09-29. Os valores ficam só no
  Cloudflare e em `config/production.env`, nunca no repositório, que é público.
  Um build sem eles publica a página de privacidade como incompleta.
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
e incluir esse link em todo email da lista.

A landing promete "um email só, quando a Nina chegar", por isso não existe email
de boas-vindas no cadastro. O único envio é o aviso de lançamento, feito pelo
operador a partir desta máquina com o Resend (chave `NINA_RESEND_API_KEY` em
`config/production.env`, somente envio, nunca no Worker):

```sh
npx deno task waitlist:send --campaign lancamento-2026 --dry-run
npx deno task waitlist:send --campaign lancamento-2026 --test-to voce@exemplo.com
npx deno task waitlist:send --campaign lancamento-2026
```

O primeiro comando só conta os destinatários. O segundo envia a mensagem real
para um endereço de teste, sem tocar no banco. O terceiro lê a lista pela RPC
`list_waitlist_recipients` no instante do envio, manda uma mensagem por
endereço com `Idempotency-Key` estável, e registra cada entrega em
`waitlist_deliveries` pela RPC `record_waitlist_delivery`. Rodar de novo depois
de uma falha envia apenas o que faltou; um endereço que cancelou entre uma
execução e outra fica de fora. O log tem só contagens e códigos, nunca um
endereço. A mensagem exige `PUBLIC_NINA_APP_STORE_ID` numérico, porque leva o
link da App Store, então ela só pode ser enviada com o app publicado.

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
`PUBLIC_NINA_APP_STORE_ID`, outra variável pública de build:

- Sem um identificador numérico real, a página informa que a Nina ainda não
  abriu e oferece a lista de espera.
- Com o identificador, ela mostra o selo local `/images/app-store-badge.svg`
  apontando para `https://apps.apple.com/br/app/id<ID>`. O selo é servido pelo
  próprio domínio porque a CSP usa `img-src 'self' data:`, e o código do convite
  nunca entra nessa URL.

Como o valor é lido no build, publicar o app na App Store exige um novo build e
deploy do site para que o caminho de instalação apareça.

## Metadados legais de produção

A política e os termos usam sete variáveis públicas no momento do build, lidas
por `src/legal.ts`:

- `PUBLIC_NINA_LEGAL_ENTITY_NAME`
- `PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT`: com 14 dígitos a página diz CNPJ e trata
  a controladora como empresa; com 11 dígitos diz CPF e trata como pessoa física.
  Qualquer outro formato aparece como "documento".
- `PUBLIC_NINA_LEGAL_ENTITY_ADDRESS`: endereço da controladora. É opcional hoje e
  aparece depois do documento quando existe. Um valor com `replace` ou outro
  marcador de exemplo é ignorado.
- `PUBLIC_NINA_PRIVACY_CONTACT_EMAIL`
- `PUBLIC_NINA_REPORT_CONTACT_EMAIL`: caixa do canal de denúncia (Termos §20,
  `/denuncia/`, `/familias/`). Sem ela, a denúncia vai para o email de
  privacidade.
- `PUBLIC_NINA_DPO_NAME`
- `PUBLIC_NINA_DPO_CONTACT_EMAIL`

Sem nome, documento, email de privacidade, encarregado e email do encarregado
válidos, a página se identifica explicitamente como pré-lançamento e recebe
`data-legal-status="incomplete"`. O preflight online exige `complete`, portanto
uma build sem a identidade aprovada não pode passar pelo gate de produção.

A página de privacidade e os termos também levam `data-legal-launch`. Ele só vale
`ready` quando a identidade está completa, o documento é um CNPJ, o endereço
existe e o encarregado tem um nome diferente do da controladora. Os valores de
hoje, de pessoa física com o próprio controlador como encarregado, continuam
`complete` e ficam `pending`. O preflight de produção
(`deployment.legal-launch-identity`) reprova o lançamento enquanto isso não
mudar. Esses valores são públicos; nenhuma chave ou segredo deve usar o prefixo
`PUBLIC_`.

Um build de teste com valores fictícios de lançamento, numa pasta temporária para
que `npm run deploy` nunca publique o resultado:

```sh
PUBLIC_NINA_LEGAL_ENTITY_NAME="Nina Tecnologia Ltda." \
PUBLIC_NINA_LEGAL_ENTITY_DOCUMENT="12.345.678/0001-90" \
PUBLIC_NINA_LEGAL_ENTITY_ADDRESS="Rua das Flores, 100, São Paulo, SP" \
PUBLIC_NINA_PRIVACY_CONTACT_EMAIL="privacidade@ninai.app" \
PUBLIC_NINA_DPO_NAME="Beltrana Encarregada" \
PUBLIC_NINA_DPO_CONTACT_EMAIL="dpo@ninai.app" \
npx astro build --outDir "$(mktemp -d)/dist" | tail -1
```

Depois, confira a pasta impressa com
`grep -o 'data-legal-[a-z]*="[a-z]*"' <pasta>/privacidade/index.html`. O resultado
deve ser `data-legal-status="complete"` e `data-legal-launch="ready"`. Um
`pending` com esses valores significa que a regra de `src/legal.ts` mudou.

## Classificação indicativa

A classificação fica numa constante só, em `src/rating.ts`:

```ts
export const ninaRatingCode: NinaRatingCode = "L";
```

O rodapé de todas as páginas (`src/components/SiteFooter.astro`) mostra o
símbolo (`src/components/RatingMark.astro`, SVG sem estilo embutido), os Termos
§4 dizem a classificação por `ninaRating.termsPhrase` e `/familias/` a explica.
A linha acima precisa ser igual a `NinaRating.currentCode` em
`Nina/NinaRating.swift`; o preflight `repository.rating-constant-consistency`
compara as duas. Se a Apple ou o Ministério da Justiça atribuírem 10 ou 12, mude
as duas constantes no mesmo commit. As cores do símbolo ainda não foram
conferidas com a arte oficial do gov.br/mj.

## Páginas para famílias e denúncia

`/familias/` é a URL de adequação etária informada à App Store e a página que a
Lei 15.211/2025 (art. 16) pede, legível sem instalar o app. `/denuncia/` explica
o canal de denúncia (arts. 29, 30 e 33). As duas são estáticas, seguem a mesma
CSP das outras páginas e são linkadas do rodapé, dos Termos e da Política de
Privacidade. O resumo da avaliação de impacto em `/familias/` acompanha
`docs/privacy/avaliacao-impacto-criancas.md`: quando o documento muda, a seção 10
da página muda junto.

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
