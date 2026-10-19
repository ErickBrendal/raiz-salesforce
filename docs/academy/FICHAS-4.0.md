# Fichas · RAIZ 4.0

Cada ficha tem três níveis: **básico** (o que faz, para quem é de negócio), **intermediário** (como funciona) e **avançado** (por que foi feito assim e o que custa). Termina com evidência e limitação — se você não consegue mostrar a evidência, não afirme.

---

## 1. Cadastro guiado (`raizGuidedJourney` + `RaizJourneyService`)

**Básico.** Sete telas que ensinam a registrar como um processo crítico é executado. Explica cada campo, mostra o que falta e só grava na última tela.

**Intermediário.**
- Fluxo: Início → Processo → Classificação → Responsabilidade → Conteúdo → Revisão → Confirmação.
- Ao avançar, a tela chama `validar()` no Apex e mostra só os bloqueios da etapa atual. A tela 6 mostra todos, com atalho para a etapa certa.
- `salvar()` grava o rascunho; com "encaminhar", chama `RaizKnowledgeService.moverDocumento` (a mesma regra do Hub) e sincroniza o cartão do Kanban.
- Um documento por processo: salvar de novo atualiza o rascunho; documento em revisão, aprovado ou publicado é recusado.

**Avançado.**
- LWC e não Screen Flow (ADR-011): texto formatado nativo, voltar sem perder dado, Jest.
- Os editores de texto formatado gravam num buffer, não no estado reativo, para o cursor não pular a cada tecla.
- Decisão D6: o cadastro **avisa**, mas não bloqueia o encaminhamento por falta de conteúdo; quem barra é a governança, com motivo registrado.

**Fluxo.** `getContexto` → `getSituacao(processo)` (retoma rascunho ou bloqueia) → `validar` a cada etapa → `salvar(encaminhar)`.

**Exemplo.** Escolha um processo "Sem documento", avance até a tela 6 sem tipo de documento: aparece "Escolha o tipo de documento" com "Corrigir na tela 3".

**Evidência.** `RaizJourneyServiceTest` (caminho feliz, retomada sem duplicar, bloqueios por tela, publicado não duplica, entradas inválidas); Jest `raizGuidedJourney` (7 testes).

**Limitações.** O que foi digitado se perde se a pessoa sair antes da tela 7. Anexos entram depois, pela página do documento.

---

## 2. Governança documental (Flow + `RaizGovernancaAction` + `RaizGovernancaService` + `RaizLog`)

**Básico.** Quando um documento entra em revisão, o RAIZ confere se está completo. Se está, cria a tarefa do revisor, move o cartão no Kanban e avisa o revisor. Se não está, bloqueia e diz o que falta. Um dia depois do prazo, avisa que atrasou — uma vez só.

**Intermediário.**
- Flow `RAIZ_Governanca_Revisao` dispara quando o status **passa** a "Em Analise" (não a cada edição) e só chama a ação Apex.
- `submeter`: `avaliarSubmissao` devolve faltas (título, resumo, etapas, revisor elegível ≠ autor) e avisos (sem prazo, falta para aprovar).
- `escalar`: caminho agendado 1 dia após `Prazo_Revisao__c`; ignora se já saiu de revisão ou já escalou.
- `aoMudarStatus`: chamado pelo Hub; encerra a tarefa e move o cartão.

**Avançado.**
- Idempotência (ADR-013): tarefa só se não houver outra aberta; log com `Chave__c` única — a coluna "Execuções" mostra a repetição.
- `without sharing` (ADR-018) porque cria a tarefa de outra pessoa; nunca toca em status, dono ou conteúdo.
- A ação nunca lança exceção para o Flow: um erro não pode desfazer a mudança de status feita pelo usuário; vira log "Erro".
- Lote limitado a 20 documentos por transação, para caber nos limites de consulta.

**Exemplo.** Documento B da demonstração: sem etapas e sem revisor → "Bloqueado: falta Etapas operacionais, Revisor", 0 tarefas, cartão no Backlog.

**Evidência.** `RaizGovernancaActionTest` (sucesso uma vez só, bloqueado sem tarefa, ignorado, lote, escalonamento único, aprovação encerra a tarefa, cockpit e hub); demonstração A/B/C na org.

**Limitações.** O escalonamento depende do relógio da org; não há teste Apex que avance o tempo. O cartão do Kanban usa o acesso de quem disparou.

---

## 3. Engineering Status e Intelligence

**Básico.** Um inventário do que foi construído — funcionalidades e componentes — conferido contra a própria org. O painel mostra o que está provado e o que é só declarado.

**Intermediário.**
- `RAIZ_Engineering_Status__c` guarda o item; `RAIZ_Evidencia__c` guarda cada prova (tipo, origem, resultado, data).
- `RaizEngineeringVerifier` consulta a org por tipo de item e grava o estado; a funcionalidade só fica "Verificada" se todos os seus componentes estiverem.
- `RAIZ_Implantacao__c` vem do relatório real de deploy, via script.

**Avançado.**
- Declarado × verificado (ADR-015): o campo de estado é somente leitura para todos; preencher não valida.
- Apex não lê `LightningComponentBundle` nem `ApexCodeCoverageAggregate`; essas provas vêm do sf CLI e expiram em 7 dias, para não virarem certidão eterna.
- Cada indicador traz a regra de cálculo; funcionalidade e componente são contados separadamente.

**Exemplo.** O teste cria um item marcado "Verificado" à mão para uma funcionalidade planejada: o verificador devolve "Declarado".

**Evidência.** `RaizEngineeringTest`; verificação na org (Ondas 9–10): 55 de 55 componentes e 10 de 10 funcionalidades verificados.

**Limitações.** O inventário é mantido à mão: um componente que não está no inventário não é verificado. Jest roda no computador do autor e não gera evidência automática.

---

## 4. Integration Hub · GitHub (`RaizGitHubService`)

**Básico.** Lê as versões publicadas do RAIZ no GitHub e mostra se cada uma está de fato implantada na org.

**Intermediário.**
- Configuração em `RAIZ_Integracao__mdt.RAIZ_GitHub` (dono, repositório, Named Credential).
- `sincronizar()`: GET do repositório e das releases (timeout de 10 s), ignora rascunhos, grava `RAIZ_Release__c` por `Tag__c`.
- Erros 401, 403 (limite ou acesso), 404, 429 e 5xx viram mensagem clara e log com o código HTTP.

**Avançado.**
- Sem segredo (ADR-016): repositório público, Named Credential anônima. Para subir o limite, External Credential com token somente leitura.
- Todos os callouts acontecem antes de qualquer gravação (o Apex não permite callout depois de DML na mesma transação).
- A tela lê da Salesforce, não do GitHub: funciona com o GitHub fora do ar.
- Release ≠ implantação (ADR-017).

**Evidência.** `RaizGitHubServiceTest` com `HttpCalloutMock` (200, 401, 403, 404, 429, 5xx, timeout, JSON inválido, lista vazia, desativada, repetição sem duplicar, release sem deploy).

**Limitações.** Leitura anônima: 60 requisições por hora por IP, e a Salesforce compartilha IPs. A ligação release ↔ deploy é um passo explícito.

---

## 5. Portfolio Demo Mode (`raizPortfolioDemo`)

**Básico.** O roteiro de 10 minutos dentro da própria org, com visão funcional e técnica.

**Intermediário.** O roteiro mora em `roteiro.js`, versionado com o código. Cada etapa traz: onde clicar, registro, o que deve acontecer, como comprovar, pergunta provável, resposta e limitação. O rodapé "Engineering with AI" lê o inventário de engenharia.

**Avançado.** Não há número fixo no roteiro: os dados de demonstração mudam e o apresentador lê da tela. Um teste Jest confere que o roteiro cabe em 7 a 10 minutos e que nenhuma etapa está sem pergunta ou limitação.

**Evidência.** Jest `raizPortfolioDemo` (2 testes).
