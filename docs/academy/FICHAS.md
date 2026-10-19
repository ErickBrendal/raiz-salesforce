# Fichas por módulo

## 1. Habilitação
- **Objetivo:** saber, com evidência, quem executa cada processo hoje.
- **Regras:** só `Apto` conta; validade passada vira `Vencida` na gravação; profissional inativo tem as habilitações suspensas; a mesma pessoa não entra duas vezes no mesmo processo (`Chave_Par__c` única).
- **Onde mexer:** `Habilitacao__c`, `RaizHabilitacaoHandler`, `RaizHabilitacaoVencimentoJob`.
- **Armadilha:** o roll-up conta Apto pelo status; se o job diário não rodar, uma validade vencida segue contando até a próxima execução.

## 2. Motor de risco
- **Objetivo:** classificar cada processo em 4 estados e dar um score de 1 a 24.
- **Regras:** ver tabela em [ARQUITETURA](../ARQUITETURA.md).
- **Onde mexer:** fórmulas de `Processo_Critico__c` **e** `RaizRiskEngine`, sempre juntos.
- **Armadilha:** mudar só a fórmula quebra o teste de contrato (`c14`); é proposital.

## 3. Cockpit
- **Objetivo:** visão executiva por cliente.
- **Regras:** indicadores não ficam verdes com dado faltando; ressalvas explicam premissas; concentração por habilitação.
- **Onde mexer:** `RaizCockpitService`, LWC `raizExecutiveCockpit`.
- **Armadilha:** formatação de moeda é feita no Apex de forma fixa (pt-BR); não usar `Decimal.format()`, que depende do locale.

## 4. Simulador de ausência
- **Objetivo:** responder "se esta pessoa faltar, o que para?".
- **Regras:** Para (sobram 0), Fica frágil (sobra 1), Continua coberto (2+); somente leitura.
- **Onde mexer:** `RaizSimulationService`, LWC `raizSimuladorAusencia`.
- **Armadilha:** inicializar campo de classe interna com constante da classe externa causa "Illegal forward reference" no Apex.

## 5. Mitigação
- **Objetivo:** transformar risco em plano com dono, prazo e ações.
- **Regras:** sugestão pelo estado do processo; criar é ação explícita; um plano aberto por processo; concluir exige todas as ações; concluir não cria habilitação.
- **Onde mexer:** `RaizMitigationService`, `Plano_Mitigacao__c`, `Acao_Mitigacao__c`, LWC `raizPlanosMitigacao`.

## 6. Knowledge Hub
- **Objetivo:** ciclo do registro do processo: Backlog → Em elaboração → Em revisão → Aprovado → Publicado.
- **Regras:** só documentos ligados a processo; aprovar e publicar exigem `RAIZ_Aprovar_Documentos` e as 4 seções preenchidas; publicar atualiza `Status_Registro__c` e `Ultima_Revisao__c` do processo.
- **Onde mexer:** `RaizKnowledgeService`, `Business_Rule__c`, LWC `raizKnowledgeHub`.
- **Armadilha:** Apex não diferencia maiúsculas de minúsculas; variável `backlog` e constante `BACKLOG` são o mesmo nome.
