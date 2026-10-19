# Testes e evidências

Só entram aqui números lidos em saída do sf CLI ou do Jest. Quando um número ainda não foi medido, está escrito "a medir".

## Execuções registradas na org de demonstração

| Data | Onda | Deploy (testes especificados) | Rodada com cobertura | Origem |
|---|---|---|---|---|
| 17/10/2026 | 3 | 45/45 | — | saída de `implantar-onda3.sh` |
| 17/10/2026 | 4 | 48/48 | — | saída de `implantar-onda4.sh` |
| 18/10/2026 | 5 | 55/55 | 60/60 | saída de `implantar-onda5.sh` |
| 18/10/2026 | 6 | 69/69 | 76/76 | saída de `implantar-onda6.sh` |
| 18/10/2026 | 7 | 77/77 | 85/85 | saída de `implantar-onda7.sh` |
| 19/10/2026 | 8 | 83/83 | 92/92 | saída de `implantar-onda8.sh` |
| 19/10/2026 | 9–10 | 94/94 | 103/103 | saída de `implantar-onda9.sh` (deploy 0AfgK00000Wu1YVSAZ) |

## Cobertura por classe (última medição registrada)

| Classe | Cobertura | Medição |
|---|---|---|
| RaizCockpitService | 96% | Onda 7 |
| RaizKnowledgeService | 96% | Onda 7 |
| RaizGovernancaService | 100% | Ondas 6 e 8 |
| RaizGovernancaAction | 93% | Onda 7 |
| RaizLog | 92% | Onda 7 |
| RaizJourneyService | 93% | Onda 6 |
| RaizEngineeringVerifier | 97% | Ondas 8 e 9 |
| RaizEngineeringService | 99% | Ondas 8 e 9 |
| RaizSimulationService · RaizRiskEngine · RaizMitigationService | 98% · 98% · 99% | auditoria de 18/10/2026 |
| RaizHabilitacaoHandler · RaizHabilitacaoVencimentoJob | 94% · 94% | auditoria de 18/10/2026 |
| RaizGitHubService | 91% | Onda 9 |

## Jest (LWC)

33 testes em 7 componentes, todos aprovados (`npm run test:unit`, 19/10/2026).

## Demonstração da governança (18/10/2026)

| Documento | Situação gravada | Tarefas | Log |
|---|---|---|---|
| A · completo | Em revisão com Revisor Demo até 23/10/2026 | 1 | Sucesso, 1 execução |
| B · sem etapas e sem revisor | Bloqueado: falta Etapas operacionais, Revisor | 0 | Bloqueado, 1 execução |
| C · prazo no mesmo dia | Em revisão com Revisor Demo até 18/10/2026 | 1 | Sucesso, 1 execução |

## Verificação do inventário (19/10/2026, Onda 8)

60 itens: 58 verificados, 0 falhas, 0 não verificáveis, 2 planejados. Funcionalidades validadas: 8 de 8 implementadas. Componentes verificados: 50 de 50.

## Verificação do inventário (19/10/2026, Ondas 9–10 · quality gate)

65 itens: 65 verificados, 0 falhas, 0 não verificáveis, 0 planejados. Funcionalidades: 10 de 10 implementadas e 10 de 10 validadas. Componentes verificados: 55 de 55. Sem evidência aprovada: 0. Evidências do sf CLI (LWC e cobertura): 24. Testes na última implantação: 94 de 94. Flow de governança ativo. "Integrações verificadas = 3 de 3" conta os **componentes** do módulo Integração com estado Verificado; não significa que a sincronização com o GitHub já trouxe uma release.

## Integração GitHub (19/10/2026)

| Momento | Resultado registrado no log |
|---|---|
| Antes de criar o repositório | Erro · HTTP 404 · repositório não encontrado ou não público |
| Repositório criado, sem release | Ignorado · HTTP 200 · encontrado, mas sem releases publicadas |
| Após publicar a release v1.0.0 | a medir |
