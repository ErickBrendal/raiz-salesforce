# Como explicar o projeto

Respostas curtas para perguntas técnicas frequentes. Cada uma aponta a evidência no repositório.

| Pergunta | Resposta curta | Evidência |
|---|---|---|
| Por que fórmula **e** Apex com a mesma regra? | Fórmula serve relatório e estado atual; Apex responde cenários hipotéticos. Um teste prende os dois. | ADR-002, `c14FormulaEMotorConcordam` |
| Como você evita que o painel minta? | Dado faltando vira estado próprio, indicador não fica verde e a premissa aparece em ressalva. | ADR-003, `semInformacaoNaoViraVerdeNemPontoUnico` |
| Como fica a segurança? | `with sharing`, `USER_MODE` em leitura e escrita, permission sets por papel, teste com usuário sem acesso. | ADR-006 |
| Por que não usou o Salesforce Knowledge? | Ativar é irreversível; a org já tinha um objeto de documento com o ciclo necessário. | ADR-005 |
| Como lida com regra que depende da data de hoje? | Roll-up não aceita `TODAY()`: gatilho na gravação + job diário. | ADR-004, `c09JobDiarioVenceOQueExpirou` |
| O simulador altera dados? | Não. O teste confere DML zero e `SystemModstamp` inalterado. | ADR-007, `simulacaoNaoGravaNada` |
| Como você publica sem quebrar a org? | Validação prévia (dry-run) e testes especificados; duas falhas foram pegas antes de tocar a org. | ADR-009 |
| O que você faria a seguir? | Lista de habilitações na página do processo, histórico de simulação salvo por ação explícita, reativação de profissional restaurando habilitações. | Pendências nos relatórios de fase |

> Os resultados de experiências profissionais anteriores não pertencem a este projeto e não devem ser apresentados como resultados do RAIZ.
