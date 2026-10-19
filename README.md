# RAIZ · Operational Resilience Intelligence

Aplicação Salesforce (Apex, LWC e Flow) que responde, com dado e não com opinião:
**se uma pessoa faltar amanhã, quais processos param, quanto isso custa, o que fazer agora — e se o conhecimento para continuar está registrado e revisado.**

Projeto autoral de Erick Almeida (Salesforce Certified Administrator), construído em uma Salesforce Developer Edition com apoio de IA (detalhes em [Como construí o RAIZ](docs/COMO-CONSTRUI-O-RAIZ.md)). **Todos os dados são fictícios.** Nenhum resultado aqui descrito vem de uso em empresa real.

## Módulos

| Módulo | Pergunta que responde | Peças principais |
|---|---|---|
| Cobertura e risco | Quem consegue executar cada processo hoje, com evidência? Qual o risco e a exposição? | `Processo_Critico__c`, `Profissional__c`, `Habilitacao__c`, fórmulas, `RaizRiskEngine`, job diário |
| Cockpit executivo | Onde está o risco e quanto ele vale? | `RaizCockpitService`, `raizExecutiveCockpit` |
| Simulador de ausência | Se esta pessoa faltar, o que para? | `RaizSimulationService`, `raizSimuladorAusencia` |
| Mitigação | Qual o plano, de quem, até quando? | `Plano_Mitigacao__c`, `Acao_Mitigacao__c`, `RaizMitigationService` |
| Knowledge Hub | Em que etapa está o registro de cada processo? | `Business_Rule__c` (reaproveitado), `RaizKnowledgeService`, `raizKnowledgeHub` |
| Cadastro guiado | Como uma pessoa sem experiência registra o conhecimento certo? | `raizGuidedJourney`, `RaizJourneyService` |
| Governança documental | O pedido de revisão chegou a alguém? Está atrasado? Por que travou? | Flow `RAIZ_Governanca_Revisao`, `RaizGovernancaAction`, `RaizGovernancaService`, `RaizLog`, notificação |
| Engineering Status | O que foi construído, e o que está provado na org? | `RAIZ_Engineering_Status__c`, `RAIZ_Evidencia__c`, `RAIZ_Implantacao__c`, `RaizEngineeringVerifier`, `raizEngineeringIntelligence` |
| Integration Hub | Qual versão foi publicada, e ela está implantada? | Named Credential `RAIZ_GitHub`, `RaizGitHubService`, `RAIZ_Release__c` |
| Portfolio Demo Mode | Como apresentar tudo isso em 10 minutos sem afirmar o que não foi provado? | `raizPortfolioDemo` |

## Regras de negócio travadas em teste

1. **Ponto único** = até 1 pessoa apta. **Sem dado nunca vira verde**: "Informação insuficiente" é um estado próprio.
2. **Habilitação registrada prevalece** sobre o número declarado; habilitação vencida não conta.
3. **Simulador é somente leitura.**
4. **Concluir um plano não marca ninguém como apto.**
5. **Quem escreve não aprova**: aprovar e publicar exige a permissão `RAIZ_Aprovar_Documentos`, e o revisor não pode ser o autor.
6. **Encaminhamento incompleto fica bloqueado com o motivo**, sem tarefa e sem mover o cartão.
7. **Rodar a automação de novo não duplica** tarefa, notificação ou log.
8. **Preencher o inventário não valida nada**: só o verificador marca "Verificado".
9. **Release publicada não é implantação.**

## Números verificáveis

Os números abaixo vêm de saídas do sf CLI na org de demonstração. Ver [Testes e evidências](docs/TESTES-E-EVIDENCIAS.md) para data e origem de cada um.

| Item | Valor | Como conferir |
|---|---|---|
| Componentes de metadados | 227 | `sf project convert source --root-dir force-app` → `package.xml` |
| Classes Apex (com testes) / gatilhos / Flow | 25 (11 de teste) / 3 / 1 | `force-app/main/default` |
| Testes Apex na última execução registrada | 103 de 103 (Ondas 9–10) | `sf apex run test` com as classes do script da onda |
| Testes Jest (LWC) | 33 de 33, em 7 componentes | `npm run test:unit` |
| Verificação do inventário na org (Ondas 9–10) | 55 de 55 componentes e 10 de 10 funcionalidades verificados | aba Engineering Intelligence |

## Dependência que não está neste repositório

`RaizGovernancaService` cria e move cartões de um Kanban (`CRM_Kanban_Task__c`, `CRMKanbanService`) que já existia na org de demonstração e **não faz parte deste repositório**. Para implantar em outra org, é preciso esse Kanban ou remover a integração com o cartão (item do [roadmap](docs/ROADMAP.md)).

## Instalar (org de desenvolvimento)

Os scripts em `scripts/implantacao` rodam onda por onda: validação (`--dry-run`), deploy com testes especificados, cargas fictícias idempotentes e verificação. Leia cada script antes de rodar; todos usam o alias `radar`.

## Documentação

- [Arquitetura](docs/ARQUITETURA.md) · [Decisões (ADR)](docs/adr/README.md) · [Blueprint 4.0](docs/BLUEPRINT-RAIZ-4.md)
- [Roteiro de demonstração de 10 minutos](docs/DEMO-GUIADA.md)
- [RAIZ Academy: fichas, trilhas e perguntas de entrevista](docs/academy/README.md)
- [Como construí o RAIZ](docs/COMO-CONSTRUI-O-RAIZ.md) · [Testes e evidências](docs/TESTES-E-EVIDENCIAS.md) · [Roadmap](docs/ROADMAP.md)
