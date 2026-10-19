# Perguntas de entrevista · respostas fundamentadas

Cada resposta aponta onde está a prova. Se a pergunta for sobre algo que não existe no RAIZ, diga que não existe.

## Arquitetura e decisões

**Por que um record-triggered Flow chamando Apex, e não só um trigger?**
Flow onde ele é mais forte: gatilho por mudança de status e caminho agendado por campo de data, sem código de agendamento. Regra em Apex porque é a mesma regra usada pelo cadastro e pelo Hub, e precisa de teste. O Flow não tem regra de negócio. *Evidência:* ADR-012, `RAIZ_Governanca_Revisao.flow-meta.xml`.

**Como você evita loop entre o Flow e a ação que atualiza o mesmo registro?**
O Flow exige que o registro *passe* a atender o critério (`doesRequireRecordChangedToMeetCriteria`). A ação atualiza só campos de governança; o status continua "Em Analise", então o critério não muda de falso para verdadeiro. *Evidência:* o teste da ação roda com o Flow ativo e não duplica.

**O que significa idempotência aqui, na prática?**
Rodar de novo não cria tarefa, notificação nem log novo: tarefa só se não houver aberta; log com chave única que soma execuções. *Evidência:* coluna "Execuções" no log; `sucessoCriaTarefaUmaVezSo`.

**Por que `without sharing` em algumas classes? Isso não é um risco?**
É, por isso é restrito: só a automação, o log e o verificador, porque criam a tarefa de outra pessoa ou leem metadados de segurança. Essas classes nunca mudam status, dono ou conteúdo. Telas e leituras são `with sharing` + `WITH USER_MODE`. *Evidência:* ADR-018 e cabeçalho de cada classe.

**Por que reaproveitar o Documento Funcional em vez do Salesforce Knowledge?**
O objeto já existia com campos e permissões; ativar Knowledge muda licenciamento e modelo. O custo é semântico: alguns campos têm nome de especificação, e o cadastro explica o mapeamento na tela. *Evidência:* ADR-005, ficha do cadastro.

## Integração

**Como a integração lida com o GitHub fora do ar ou com limite de chamadas?**
A tela lê registros já gravados na Salesforce; a sincronização é manual, com timeout de 10 s; 403 com `X-RateLimit-Remaining: 0` vira mensagem de limite com horário de liberação; nada é apagado em erro. *Evidência:* `RaizGitHubServiceTest`.

**Onde está o token?**
Não há token: o repositório é público e a Named Credential é anônima. Se for preciso, o caminho é External Credential com token somente leitura digitado no Setup — nunca em código ou campo. *Evidência:* ADR-016.

**Por que não marcar a release como implantada?**
Porque publicar uma tag não prova deploy. Implantação só nasce do relatório real do deploy. *Evidência:* ADR-017, visão Implantações.

## Qualidade

**Como você sabe que o status report não está mentindo?**
O estado de validação é somente leitura para todos; só o verificador grava, consultando a própria org. LWC e cobertura vêm do sf CLI e expiram em 7 dias. *Evidência:* ADR-015, `RaizEngineeringTest`.

**Que tipo de teste você escreveu?**
Apex com usuários de teste com e sem permissão (`USER_MODE` falha sem FLS), testes de contrato fórmula × motor (120 combinações), mocks HTTP para cada código de erro, e Jest para cada tela. *Evidência:* [Testes e evidências](../TESTES-E-EVIDENCIAS.md).

## IA

**Você escreveu esse código?**
A maior parte do código foi gerada com IA a partir do meu brief. O meu trabalho foi definir o problema e as regras, decidir entre alternativas (por exemplo LWC × Screen Flow, sem prazo padrão, não exigir conteúdo no Hub), aprovar cada mudança estrutural, executar e conferir cada deploy e cada tela. Revisões feitas por IA antes do deploy encontraram falhas que foram corrigidas antes de chegar à org. *Evidência:* [Como construí o RAIZ](../COMO-CONSTRUI-O-RAIZ.md).

**Então o que você sabe fazer sem a IA?**
Responder com um caso concreto: explicar por que o callout tem de vir antes do DML, por que o teste do painel quebrou com "Argument 3 cannot be null", ou por que o cartão do documento bloqueado precisava voltar para o Backlog — e mostrar onde isso está no código.
