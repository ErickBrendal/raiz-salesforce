# Como construí o RAIZ: arquitetura, engenharia Salesforce e desenvolvimento assistido por IA

| Campo | Valor |
|---|---|
| Autor | Erick Almeida · Salesforce Certified Administrator |
| Período | outubro de 2026 |
| Ambiente | Salesforce Developer Edition, sf CLI 2.154 no macOS |
| Ferramenta de IA | Claude (Anthropic), em sessão de trabalho com acesso à pasta do projeto |
| Dados | Todos fictícios |

## 1. O problema

Em operações reais, processos críticos dependem de uma ou duas pessoas, e o conhecimento para executá-los não está escrito ou não é revisado. O risco não aparece em nenhum relatório até alguém faltar. O RAIZ transforma essa pergunta em dado: quem está habilitado para cada processo, quanto custa a ausência, qual o plano e se o registro do conhecimento existe e foi revisado.

## 2. Como o trabalho foi dividido

| Papel | Quem | O que fez de fato |
|---|---|---|
| Problema, método e regras | Autor | Escreveu os briefs (Missão RAIZ e RAIZ 4.0), definiu os 4 estados da cobertura, a separação autor × aprovador e o princípio "declarado não é verificado" |
| Decisões entre alternativas | Autor | Ver seção 3 |
| Aprovação de mudança estrutural | Autor | Aprovou cada onda antes do deploy e cada objeto novo |
| Execução na org | Autor | Rodou todos os scripts de validação, deploy e carga no próprio Mac e conferiu as telas |
| Estruturação de requisitos, código, testes, documentação | IA | Gerou o código Apex, LWC, Flow, metadados, scripts e estes documentos a partir do brief |
| Revisão antes do deploy | IA (segundo agente) | Revisou cada pacote e apontou falhas que fariam o deploy ou um teste falhar |
| Leitura de resultados | IA + autor | A IA leu as saídas dos scripts e propôs a correção; o autor decidiu seguir |

O valor profissional não está em ter digitado o código, e sim em saber o que pedir, julgar a proposta, recusar o que não serve e provar que funciona.

## 3. Decisões tomadas pelo autor

| Decisão | Escolha | Alternativa recusada |
|---|---|---|
| Fonte da cobertura | Habilitação individual registrada | Número de pessoas aptas digitado |
| Simulador antigo (por dono do registro) | Remover; manter só o calculado por habilitação | Manter os dois |
| Demandas do Kanban com aparência real | Trocar por fictícias e remover as cópias (com backup) | Manter |
| D1 · Tecnologia do cadastro guiado | LWC | Screen Flow |
| D2 · Modelo de dados do 4.0 | 5 objetos + 1 Custom Metadata, como proposto | Versão sem release/implantação |
| D3 · Integração | Publicar o próprio repositório (`raiz-salesforce`) | Repositório de terceiros |
| D4 · Revisor | Criar usuário fictício "Revisor Demo" | Demonstrar sem segregação |
| D5 · Prazo padrão de revisão | Não ter prazo automático | 3/5 dias úteis |
| D6 · Exigir conteúdo para ir à revisão | Não exigir no Hub; a automação bloqueia e explica | Bloquear a mudança de status |

## 4. O que foi construído

| Onda | Entrega | Validação registrada |
|---|---|---|
| 1–2 | Habilitação, motor de risco, 4 estados, job de vencimento | Teste de contrato fórmula × Apex com 120 combinações |
| 3 | Planos de mitigação; simulador por habilitação | 45/45 testes no deploy |
| 4 | Cockpit v2 | 48/48 |
| 5 | Knowledge Hub com aprovador separado | 55/55 |
| 6 | Cadastro guiado, app RAIZ | 69/69 no deploy; 76/76 na rodada com cobertura |
| 7 | Governança documental (Flow + Apex), log, notificação | 77/77 no deploy; 85/85; demonstração A/B/C conferida na org |
| 8 | Engineering Status, verificador, painel | 83/83 no deploy; 92/92; 50 de 50 componentes verificados |
| 9–10 | Integração GitHub, Portfolio Demo Mode | 94/94 no deploy; 103/103; `RaizGitHubService` 91%; 55 de 55 componentes verificados; leitura do GitHub conferida com 404 e 200 |

## 5. Problemas reais encontrados e como foram resolvidos

| Onde | Problema | Como apareceu | Correção |
|---|---|---|---|
| Onda 1 | "Illegal forward reference" em campo de classe interna | Validação do deploy | Inicializar a lista vazia e preencher no método |
| Onda 1 | `AuraHandledException` sem `setMessage()` esconde a mensagem no teste | Revisão antes do deploy | Função auxiliar que cria a exceção já com a mensagem |
| Onda 1 | Fórmula do farol estourando o limite de tamanho | Revisão antes do deploy | `CASE` sobre os 11 scores possíveis |
| Onda 3 | Reabrir um plano criava um segundo plano aberto | Revisão | Verificação antes de reabrir |
| Onda 3 | Carga sobrescrevia dado do usuário | Revisão | Carga só cria, nunca altera |
| Onda 5 | Variável `backlog` colidindo com a constante `BACKLOG` (Apex não diferencia maiúsculas) | Compilação | Renomear |
| Onda 5 | Regra de validação da org não bloqueava como esperado | Teste falhou no deploy | Conferência de conteúdo também no Apex |
| Onda 6 | Elemento inválido no XML do app | Validação do deploy | Remover o elemento |
| Onda 6 | Script do revisor não achava perfil: nomes de perfil vêm em português | Saída do script vazia | Procurar o perfil pela licença |
| Onda 6 | Título com 121–255 caracteres passaria na tela e falharia ao gravar | Revisão | Limite de 120 em Apex e na tela |
| Onda 7 | Ícone de aba inexistente derrubaria o deploy inteiro | Revisão | Ícone válido da lista do CLI |
| Onda 7 | Documento bloqueado ganhou cartão na coluna de análise | Saída da demonstração | Cartão de documento bloqueado fica no Backlog (Onda 8) |
| Onda 8 | Cobertura de uma classe abaixo de 75% e CSV com fim de linha CRLF | Revisão | Teste adicional; arquivos em LF |
| Onda 8 | "Argument 3 cannot be null" no teste do painel | Validação do deploy | Mensagem do assert nunca nula |
| Onda 9 | Callout depois de DML no mesmo teste é proibido no Apex | Desenho dos testes | Uma sincronização por teste; código faz todos os callouts antes de gravar |

## 6. Trade-offs assumidos

- **Reaproveitar o Documento Funcional** custa nomes de campo de especificação; ganha não ativar Knowledge.
- **`without sharing` na automação** dá confiabilidade; exige revisão rigorosa dessas três classes.
- **Evidência do sf CLI com validade de 7 dias** obriga a rodar um script antes de apresentar; evita certidão eterna.
- **GitHub sem token** evita segredo; aceita o limite anônimo do GitHub.
- **Dependência do Kanban existente** acelerou a entrega; impede instalar o RAIZ sozinho em outra org (roadmap).

## 7. Melhorias futuras

Ver [Roadmap](ROADMAP.md).
