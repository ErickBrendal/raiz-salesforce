# RAIZ 4.0 — Auditoria (Fase 0) e Blueprint (Fase 1)

| Campo | Valor |
|---|---|
| Versão | 1.0 — auditoria da org concluída; decisões D1–D6 registradas |
| Data | 18/10/2026 |
| Autor | Erick Almeida (arquitetura e aprovação) · Claude (levantamento e proposta) |
| Org | Developer Edition, alias `radar` |
| Status | Fase 0 concluída (auditoria somente leitura em 18/10/2026, `auditar-raiz4.sh`); Fase 2 pronta para deploy (`raiz-onda6`) |

> ⚠ **Como ler este documento.** Nada abaixo foi implementado. Os itens marcados como "confirmado na org" vêm de deploys e verificações das ondas 1–5, com saída de ferramenta registrada. Os demais são proposta e mudam se a auditoria da org mostrar algo diferente.

---

## 1. Legenda de status

| Status | Significado |
|---|---|
| **Confirmado na org** | Deploy bem-sucedido e verificação executada nas ondas 1–5 (saída registrada) |
| **Confirmado no repositório** | Existe no código-fonte; presença na org ainda não reconfirmada nesta fase |
| **Parcial** | Existe, mas não cobre o que o brief 4.0 pede |
| **Planejado** | Proposto neste blueprint |
| **Não encontrado** | Procurado no repositório e não localizado |
| **Não verificável ainda** | Depende da auditoria da org |

## 2. Matriz de reutilização

| # | Estrutura | Status | Reutilização no 4.0 |
|---|---|---|---|
| 1 | `Processo_Critico__c` + fórmulas de cobertura e risco | Confirmado na org | Base da jornada (seleção do processo) e dos indicadores |
| 2 | `Profissional__c`, `Habilitacao__c`, job de vencimento | Confirmado na org | Contexto do processo (quem cobre); sem mudança |
| 3 | `Plano_Mitigacao__c`, `Acao_Mitigacao__c` | Confirmado na org | Sem mudança; aparece no Demo Mode |
| 4 | `Business_Rule__c` (Documento Funcional) | Confirmado na org | **Documento da jornada.** Recebe campos novos (seção 5.2) |
| 5 | `RaizKnowledgeService` (fluxo Draft → Em Análise → Aprovada → Publicada, `pendencias`) | Confirmado na org | **Fonte única das regras documentais.** Jornada e automação chamam este serviço; nenhuma regra é copiada para Flow |
| 6 | Custom Permission `RAIZ_Aprovar_Documentos` + permsets `EBL_RAIZ_Cockpit`, `RAIZ_Aprovador`, `RAIZ_Leitor` | Confirmado na org | Segregação autor × revisor; permsets recebem os objetos novos |
| 7 | Cockpit (`raizExecutiveCockpit`, `RaizCockpitService`) | Confirmado na org | Ganha bloco "Governança documental" (pendências de revisão) |
| 8 | Knowledge Hub (`raizKnowledgeHub`) | Confirmado na org | Ganha botão "Cadastro guiado" e selo de pendência de revisão |
| 9 | Kanban `CRM_Kanban_Task__c`, lookup `Business_Rule__c` (relação `UserStories`), `Task_Stage_Log__c` | Confirmado na org (105 cartões fictícios) | **Card de acompanhamento** do documento; a automação cria ou move o card |
| 10 | `CRMKanbanService.createTask` | Confirmado no repositório | Criação do card pela automação (reaproveitar em vez de inserir direto) |
| 11 | `CRMKanbanOverdueSchedulable` | Parcial | Só grava `System.debug`; **não serve** como rotina de vencimento |
| 12 | Assistente de documento do Kanban (componente legado) | Parcial | **Não reutilizar como base**: opções de área com nomes de BUs de uma empresa real e controlador com nome dessa empresa. Reaproveitar só o padrão técnico (buffer de rich text). Recomendo tirá-lo da navegação do RAIZ |
| 13 | RAIZ Academy | Parcial | Existe como Markdown no repositório (`docs/academy`), não na org. Recebe fichas por componente |
| 14 | ADRs 001–010, `ARQUITETURA.md`, `DEMO-GUIADA.md` | Confirmado no repositório | Ampliados com ADR-011 em diante |
| 15 | Flows do RAIZ | Não encontrado na org | A org só tem Flows padrão/de pacote; nenhum do RAIZ nem do Kanban |
| 16 | Integrações (Named/External Credential, Remote Site) | Não encontrado na org | 0 Named Credentials e 0 External Credentials; 4 Remote Site Settings de outros projetos (APIs de futebol e mapas), não reutilizáveis |
| 17 | Objeto de inventário técnico / status de engenharia | Não encontrado | Planejado (Módulo B) |
| 18 | Repositório público do RAIZ no GitHub | Não encontrado | Não existe repositório publicado (decisão D3) |
| 19 | Aplicativo Lightning do RAIZ (menu) | Não encontrado na org | Existe o app `CRM_Kanban`; o RAIZ ganha app próprio na Onda 6 |
| 20 | 28 documentos legados sem processo | Confirmado na org | Ficam fora do Hub e da jornada; não serão tocados |


### 2.1 Resultado da auditoria da org (18/10/2026, somente leitura)

| Item | Resultado |
|---|---|
| Org | Developer Edition, instância CAN96 |
| Última execução dos testes RAIZ | 55/55 aprovados (18/10/2026 03:18 UTC) |
| Cobertura das classes RAIZ (ApexCodeCoverageAggregate) | RaizCockpitService 96% · RaizKnowledgeService 96% · RaizSimulationService 98% · RaizRiskEngine 98% · RaizMitigationService 99% · RaizHabilitacaoHandler 94% · RaizHabilitacaoVencimentoJob 94% |
| Jobs agendados do RAIZ | "RAIZ - vencimento de habilitacoes" (diário 05:00) |
| Custom Notification Types | Só 1 padrão; nenhum do RAIZ (criar na Onda 7) |
| Colunas do Kanban | Backlog · Em atendimento (4 colunas) · Pendente (3) · Teste Unitários · Homologação · Hypercare · Fechado · Cancelado · On_Hold |
| Abas e campos com nome de empresa real | Abas, campos e listas de opções do Kanban legado com nomes de empresas reais. **Ficam fora do app RAIZ e do Demo Mode** |
| Projetos duplicados | 5 projetos "EXEMPLO" e 1 de gestão de demandas aparecem 4 vezes cada. Fora do escopo; não alterados |
| Não verificável | Consulta de regras de validação falhou (erro interno da API de ferramentas); contagens agregadas vieram vazias no CSV da CLI |

## 3. Achados que mudam o plano

| # | Achado | Consequência |
|---|---|---|
| A1 | `Business_Rule__c` nasceu para especificação funcional (Cherwell, critérios de aceite, cenários de teste) | A jornada mapeia "Etapas", "Resultado esperado" e "Exceções" para campos existentes e explica isso na tela; campos novos só para o que não existe (seção 5.2) |
| A2 | Hoje Draft → Em Análise não exige conteúdo | Mantido (D6). A exigência de "título e conteúdo mínimo" fica na automação, que bloqueia o encaminhamento sem impedir a mudança de status |
| A3 | A org tem um único usuário real | "Quem escreve não aprova" não pode ser demonstrado sem um segundo usuário (decisão D4) |
| A4 | Leitura anônima da API do GitHub tem limite baixo por IP de origem, e os IPs de saída da Salesforce são compartilhados | HTTP 403/429 é cenário **provável**, não teórico; a sincronização é manual, grava resultado em registros e a tela lê da Salesforce, não do GitHub |
| A5 | O backup do Kanban com as 92 demandas originais está em `~/Downloads/raiz-onda3/kanban` | Nunca entra no repositório público. O pacote `raiz-portfolio` está limpo (verificado: nenhuma ocorrência do nome da empresa) |

## 4. Arquitetura proposta

```
                 ┌──────────── UI (LWC, tema escuro RAIZ) ─────────────┐
 Cadastro guiado │ raizGuidedJourney ──► RaizJourneyService ─┐         │
 Knowledge Hub   │ raizKnowledgeHub ───► RaizKnowledgeService◄┘ (regras)│
 Eng. Intelligence│ raizEngineeringIntelligence ► RaizEngineeringService│
 Demo Mode       │ raizPortfolioDemo  (roteiro em Static Resource JSON) │
                 └──────────────────────────────────────────────────────┘
 Business_Rule__c ── Status muda para "Em Analise"
        │
        ▼  Flow disparado por registro: RAIZ_Governanca_Revisao  (só roteia)
        ├─ caminho imediato ─► Invocable RaizGovernancaAction.submeter
        │                       valida (RaizKnowledgeService) → Task do revisor
        │                       → card no Kanban → notificação → log (upsert por chave)
        └─ caminho agendado (1 dia após Prazo_Revisao__c, se ainda em análise)
                              ─► RaizGovernancaAction.escalar (uma vez só)

 Integration Hub: botão "Sincronizar" ─► RaizGitHubService ─► Named Credential RAIZ_GitHub
        └─► RAIZ_Release__c  +  RAIZ_Log_Execucao__c      (config: RAIZ_Integracao__mdt)

 Engineering Status: RaizEngineeringVerifier (Apex: Schema, ApexClass, ApexTrigger,
        FlowDefinitionView, CronTrigger, ApexTestResult)  +  script sf CLI (LWC, cobertura,
        deploy)  ─►  RAIZ_Evidencia__c  ─►  Estado_Validacao__c (só o verificador grava)
```

### 4.1 Decisões propostas (viram ADRs)

| ADR | Decisão | Alternativa descartada | Motivo |
|---|---|---|---|
| 011 | Jornada em **LWC** com `lightning-progress-indicator` e `lightning-input-rich-text` (D1) | Screen Flow | Os campos do documento são rich text; o Screen Flow não tem entrada rich text nativa e 7 telas com "voltar" e revisão em XML de Flow são frágeis de manter. LWC permite testes Jest |
| 012 | Automação em **Flow disparado por registro** que só roteia; regras em Apex invocável | Tudo em Flow / tudo em trigger | Mostra Flow onde ele é forte (gatilho e caminho agendado) sem duplicar regra |
| 013 | Idempotência por chave única (`Chave__c` com External ID) no log e verificação de Task aberta antes de criar | Flags espalhadas | Reexecução atualiza em vez de duplicar |
| 014 | Notificação por **Custom Notification** (sino + app) | E-mail | Gratuita, nativa, sem limite de e-mail da DE |
| 015 | "Declarado" × "Verificado": `Estado_Validacao__c` só é gravado pelo verificador; FLS somente leitura para todos | Campo editável | Preencher o registro não valida nada |
| 016 | GitHub somente leitura, sem segredo na v1, via Named Credential; tela lê dos registros sincronizados | Callout ao abrir a tela | Funciona com GitHub fora do ar e respeita o limite de requisições |
| 017 | Release ≠ implantação: `RAIZ_Implantacao__c` só nasce de saída real de deploy | Marcar release como implantada | Release publicada não prova deploy na org |

## 5. Modelo de dados

### 5.1 Objetos novos (aprovação D2)

| Objeto | Para quê | Campos principais |
|---|---|---|
| `RAIZ_Engineering_Status__c` | Item do inventário: funcionalidade **ou** componente | `Nivel__c` (Funcionalidade / Componente), `Funcionalidade__c` (lookup para o próprio objeto), `Modulo__c`, `Tipo_Componente__c`, `API_Name__c`, `Objetivo_Funcional__c`, `Problema_Negocio__c`, `Tecnologia__c`, `Status_Implementacao__c` (Planejado / Parcial / Implementado), `Estado_Validacao__c` (Declarado / Verificado / Falhou / Não verificável — só o verificador grava), `Ultima_Verificacao__c`, `Origem_Verificacao__c`, `Prioridade__c`, `Complexidade__c`, `Release__c`, `ADR__c`, `Uso_IA__c`, `Contribuicao_Humana__c`, `Limitacoes__c`, `Proxima_Evolucao__c`, `Link_Documentacao__c` |
| `RAIZ_Evidencia__c` | Prova ligada a um item (mestre-detalhe) | `Tipo__c` (Metadado na org / Teste Apex / Teste Jest / Deploy / Documento), `Origem__c` (Verificador Apex / sf CLI / Manual), `Resultado__c` (Aprovado / Reprovado), `Detalhe__c` (texto curto), `Verificado_Em__c`, `Implantacao__c` |
| `RAIZ_Release__c` | Versão no repositório | `Tag__c` (External ID), `Nome__c`, `Publicada_Em__c`, `URL__c`, `Resumo__c`, `Fonte__c` (GitHub / Manual), `Sincronizado_Em__c` |
| `RAIZ_Implantacao__c` | Deploy real na org | `Deploy_Id__c` (External ID), `Org__c`, `Executado_Em__c`, `Testes_Executados__c`, `Testes_Aprovados__c`, `Componentes__c`, `Resultado__c`, `Release__c` |
| `RAIZ_Log_Execucao__c` | Execuções de automação e integração | `Tipo__c` (Automação / Integração / Verificação), `Status__c`, `Mensagem__c` (sem segredo, sem corpo de resposta bruto), `Registro_Id__c`, `Chave__c` (External ID, único), `Executado_Em__c`, `Codigo_HTTP__c` |
| `RAIZ_Integracao__mdt` | Configuração do repositório | `Owner__c`, `Repositorio__c`, `Named_Credential__c`, `Ativo__c`, `Demonstracao__c` (marca repositório de terceiros usado só para provar o mecanismo) |

### 5.2 Campos novos em `Business_Rule__c`

| Campo | Tipo | Tela da jornada |
|---|---|---|
| `Tipo_Documento__c` | Picklist (Procedimento operacional / Regra de negócio / Plano de contingência / Checklist) | 3 |
| `Revisor__c` | Lookup User | 4 |
| `Prazo_Revisao__c` | Data | 4 |
| `Proxima_Revisao__c` | Data | 4 |
| `Pre_Requisitos__c`, `Plano_Contingencia__c`, `Referencias__c` | Rich text | 5 |
| `Data_Solicitacao_Revisao__c`, `Escalonado_Em__c`, `Governanca_Status__c` | Data/hora e texto (só automação grava) | — |

**Mapeamento para campos existentes (explicado na tela):** Objetivo → `Proposito_Documento__c`; Etapas operacionais → `Descricao_Demanda__c`; Resultado esperado → `Criterios_Aceite__c`; Exceções → `Cenarios_Teste__c`; Palavras-chave → `Keywords__c`; Categoria → `Domain__c`; Criticidade → `Criticality__c`; Responsável → `Business_Owner__c`; Data de referência → `Last_Review_Date__c`.

## 6. Backlog por fase

| Fase | Entrega | Critério de aceite resumido |
|---|---|---|
| 2 | `raizGuidedJourney` (7 telas) + `RaizJourneyService` + aba "Cadastro guiado" | Salva só na tela 7; reenvio não duplica (retoma o rascunho do mesmo processo); trata processo inexistente, sem permissão, obrigatório ausente, duplicado, publicado, erro de gravação; Jest + Apex |
| 3 | Flow `RAIZ_Governanca_Revisao`, `RaizGovernancaAction`, Custom Notification, log | Cenário de sucesso (Task + card + notificação + log) e de erro (documento incompleto → log "Bloqueado" sem Task); segunda execução não duplica; caminho agendado escala uma vez |
| 4 | Objetos de engenharia, `RaizEngineeringVerifier`, `raizEngineeringIntelligence` (5 visões) | Cada indicador com regra escrita na tela; funcionalidade e componente contados separadamente; item sem evidência aparece como "Declarado" |
| 5 | Named Credential, `RaizGitHubService`, sincronização manual | `HttpCalloutMock` para 200, 401/403, 404, 429, timeout, JSON inválido, repositório sem release; log sem segredo; tela funciona com GitHub fora |
| 6 | `raizPortfolioDemo` (funcional × técnico, roteiro de 10 min, "Engineering with AI") | Só links válidos, só fatos registrados; dados fictícios identificados |
| 7 | Academy: fichas por componente, 5 roteiros por perfil, relatório "Como construí o RAIZ" | Cada ficha aponta para evidência real |
| 8 | Quality gate | Todos os testes Apex e Jest, permsets revisados, evidências consolidadas |

### 6.1 Regras de cálculo do Engineering Intelligence

| Indicador | Regra |
|---|---|
| Funcionalidades implementadas | `Nivel = Funcionalidade` e `Status_Implementacao = Implementado` |
| Funcionalidades validadas | As anteriores com todos os componentes filhos `Verificado` nos últimos 7 dias |
| Componentes sem evidência | `Nivel = Componente` sem nenhuma evidência `Aprovado` |
| Testes executados / aprovados | Última `RAIZ_Implantacao__c` com `Resultado = Sucesso` (origem: saída do deploy) |
| Integrações verificadas | Itens de integração com última execução `Sucesso` nos últimos 7 dias |
| Pendências técnicas | `Status_Implementacao` ≠ Implementado, ou `Estado_Validacao` = Falhou |

Toda visão mostra data e origem da última verificação.

## 7. Riscos

| Risco | Prob. | Mitigação |
|---|---|---|
| Limite anônimo do GitHub (A4) | Alta | Sincronização manual, cache em registros, mensagem clara no 403/429; opção de token somente leitura guardado na External Credential (você digita no Setup; eu nunca vejo) |
| External Credential sem autenticação pode não se comportar como esperado na DE | Média | Validar com `--dry-run`; plano B: Named Credential legada sem autenticação |
| Flow e trigger na mesma alteração de status (loops) | Média | Flow só no evento "mudou para Em Análise"; Apex não altera `Status__c` |
| Segundo usuário indisponível (A3) | Média | Decisão D4 |
| Escopo grande (8 fases) | Alta | Cada fase entrega algo usável e pode ser a última; ordem recomendada: 2 → 3 → 4 → 5 → 6 → 7 → 8 |

## 8. Decisões (18/10/2026)

| # | Decisão | Resultado |
|---|---|---|
| D1 | Tecnologia da jornada | **LWC** (ADR-011) |
| D2 | 5 objetos + 1 Custom Metadata + 10 campos em `Business_Rule__c` + permsets | **Aprovado como proposto** |
| D3 | Repositório do GitHub | **Publicar o RAIZ**: eu preparo e reviso o `raiz-portfolio`; o Erick publica como repositório público com release `v1.0.0` |
| D4 | Usuário revisor de demonstração | **Aprovado**: 1 usuário fictício "Revisor Demo", criado por script que o Erick roda |
| D5 | Prazo padrão de revisão | **Não aprovado.** Sem prazo automático: o prazo é informado na tela 4. Documento enviado sem prazo gera pendência "sem prazo" no log e não entra no caminho agendado |
| D6 | Exigir conteúdo para Draft → Em Análise | **Não aprovado.** O Hub continua como está. A automação valida na submissão: documento incompleto não gera Task nem card, fica com `Governanca_Status__c = Bloqueado: falta …`, o autor é notificado e o log registra o motivo — este é o cenário de erro da demonstração |

## 9. Próximo passo

1. Você roda `bash auditar-raiz4.sh` (somente leitura).
2. Eu leio `saida/`, atualizo as linhas "Não verificável ainda" e fecho a versão 1.0 deste blueprint.
3. Começo a Fase 2 (cadastro guiado) junto com os objetos aprovados em D2, para validar tudo num único deploy.
