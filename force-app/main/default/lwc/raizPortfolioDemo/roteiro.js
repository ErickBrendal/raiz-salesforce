/**
 * Roteiro do RAIZ Portfolio Demo Mode (Onda 10). Versionado junto com o código:
 * mudou a tela, muda o roteiro no mesmo commit. Não traz números fixos — os
 * números são lidos da tela na hora, porque os dados de demonstração mudam.
 */
export const ROTEIRO = [
    {
        id: 'problema', minutos: 1, titulo: 'O problema', aba: 'Cockpit_RAIZ',
        funcional: 'Processos críticos dependem de poucas pessoas. O Cockpit mostra quantos processos estão em ponto único de falha e quanto a operação perderia por hora parada.',
        tecnico: 'Indicadores calculados por fórmulas em Processo_Critico__c (Estado_Cobertura__c, Risco_Score__c, Exposicao_Financeira__c) e agregados por RaizCockpitService, que lê com WITH USER_MODE.',
        clicar: 'Abra o Cockpit com o filtro "Todos os clientes".',
        registro: 'Nenhum: visão geral.',
        esperado: 'Cinco indicadores no topo e o bloco "Estado da cobertura" com os 4 estados.',
        comprovar: 'Abra um processo em ponto único e mostre que o estado vem das habilitações, não de um campo digitado.',
        pergunta: 'Por que fórmula e não Apex para o estado atual?',
        resposta: 'O estado atual precisa estar certo em relatório, list view e API sem depender de execução. O motor Apex (RaizRiskEngine) existe para cenários hipotéticos, e um teste de contrato com 120 combinações garante que os dois dão o mesmo resultado (ADR-002).',
        limitacao: 'Dados fictícios. Sem impacto por hora informado, o processo aparece como "Informação insuficiente", não como zero.'
    },
    {
        id: 'cobertura', minutos: 1, titulo: 'Cobertura em quatro estados', aba: 'Cockpit_RAIZ',
        funcional: 'Sem cobertura, ponto único, coberto e informação insuficiente. Nada fica "verde por falta de dado".',
        tecnico: 'Habilitacao__c com vigência; job diário (RaizHabilitacaoVencimentoJob) vence habilitações, porque roll-up não filtra por TODAY() (ADR-004).',
        clicar: 'Role até "Estado da cobertura" e "Concentração de conhecimento".',
        registro: 'Pessoas listadas em "Concentração de conhecimento".',
        esperado: 'As barras mostram em quantos processos cada pessoa é a única apta.',
        comprovar: 'Mostre a habilitação de uma pessoa e a data de validade.',
        pergunta: 'Como o sistema sabe que a habilitação venceu?',
        resposta: 'Um job agendado diário marca como vencida a habilitação com Valida_Ate__c no passado; os triggers recalculam os contadores do processo.',
        limitacao: 'A habilitação depende de alguém registrar a avaliação: o RAIZ não descobre sozinho quem sabe fazer o quê.'
    },
    {
        id: 'simulador', minutos: 1.5, titulo: 'Simulador de ausência', aba: 'Cockpit_RAIZ',
        funcional: 'Pergunta "e se esta pessoa faltar amanhã?" e responde quais processos param, quais ficam frágeis e quem cobre.',
        tecnico: 'RaizSimulationService recalcula com o RaizRiskEngine sem gravar nada (somente leitura, ADR-007).',
        clicar: 'No bloco "Simulador de ausência", escolha Fabio Teixeira.',
        registro: 'Fabio Teixeira (fictício).',
        esperado: 'Processos que param, que ficam frágeis e que continuam cobertos, com exposição e horas para restabelecer.',
        comprovar: 'Troque a pessoa e mostre que o resultado muda sem criar registro.',
        pergunta: 'Por que o simulador não grava a simulação?',
        resposta: 'Porque simulação não é fato: gravar criaria dado que parece real. Se precisar de histórico, o caminho é um objeto próprio de cenário, fora do cálculo oficial.',
        limitacao: 'Considera só habilitações registradas.'
    },
    {
        id: 'planos', minutos: 1, titulo: 'Do risco ao plano', aba: 'Cockpit_RAIZ',
        funcional: 'Cada risco pode virar plano com ações, responsável e prazo; o Cockpit mostra o score antes e depois.',
        tecnico: 'Plano_Mitigacao__c e Acao_Mitigacao__c; RaizMitigationService; regra de validação impede concluir plano sem ações (ADR-008).',
        clicar: 'Role até "Planos de mitigação".',
        registro: 'Um plano marcado como atrasado.',
        esperado: 'Planos abertos, um atrasado e o progresso das ações.',
        comprovar: 'Mostre que concluir uma ação não muda a cobertura do processo.',
        pergunta: 'Concluir o plano reduz o risco?',
        resposta: 'Não. Plano é intenção; habilitação é fato. O risco só cai quando uma nova pessoa é habilitada e registrada.',
        limitacao: 'Não há notificação de prazo de ação (a governança notifica só documentos).'
    },
    {
        id: 'cadastro', minutos: 1.5, titulo: 'Cadastro guiado', aba: 'RAIZ_Cadastro_Guiado',
        funcional: 'Sete telas que ensinam a registrar o conhecimento de um processo, explicando cada campo. Nada é gravado antes da última tela.',
        tecnico: 'LWC raizGuidedJourney + RaizJourneyService. Escolhido LWC em vez de Screen Flow por causa do texto formatado e do Jest (ADR-011). As regras ficam no Apex; a tela só pergunta.',
        clicar: 'Abra o Cadastro guiado e avance até a tela 6 sem salvar.',
        registro: 'Um processo da lista marcado "Sem documento".',
        esperado: 'A tela 6 lista o que falta e o que impede salvar, com atalho para a tela certa.',
        comprovar: 'Escolha um processo já publicado: o cadastro bloqueia e manda para o Knowledge Hub.',
        pergunta: 'Como evita documento duplicado?',
        resposta: 'Um documento por processo no fluxo. Salvar de novo o mesmo processo atualiza o rascunho existente; se o documento já está em revisão ou publicado, o cadastro recusa.',
        limitacao: 'Se a pessoa sair antes da tela 7, o que digitou se perde; o rascunho salvo é retomado.'
    },
    {
        id: 'governanca', minutos: 1.5, titulo: 'Governança automática', aba: 'RAIZ_Knowledge_Hub',
        funcional: 'Ao entrar em revisão, o documento completo vira tarefa para o revisor, cartão no Kanban e notificação; o incompleto fica bloqueado com o motivo.',
        tecnico: 'Flow disparado por registro (só roteia) chama a ação Apex RaizGovernancaAction; log com chave de idempotência; caminho agendado escala um dia após o prazo (ADR-012, 013, 014, 018).',
        clicar: 'No Knowledge Hub, coluna "Em revisão"; depois abra a aba "Logs de execução RAIZ".',
        registro: 'Documentos "(demonstração)": A em revisão, B bloqueado.',
        esperado: 'A mostra "Em revisão com Revisor Demo"; B mostra "Bloqueado: falta …" em destaque.',
        comprovar: 'No log, a coluna Execuções mostra que rodar de novo não duplica.',
        pergunta: 'Por que Flow e Apex juntos?',
        resposta: 'Flow onde ele é forte (gatilho e agendamento declarativo), Apex onde precisa de teste e regra reutilizada pelo cadastro e pelo Hub. A regra não é copiada nos dois.',
        limitacao: 'O escalonamento depende do relógio da org; não dá para acelerar em teste Apex.'
    },
    {
        id: 'engenharia', minutos: 1, titulo: 'Engenharia que dá para conferir', aba: 'RAIZ_Engineering_Intelligence',
        funcional: 'Status report que separa o que foi declarado do que foi verificado na própria org.',
        tecnico: 'RAIZ_Engineering_Status__c + RAIZ_Evidencia__c; RaizEngineeringVerifier consulta Schema, ApexClass, FlowDefinitionView e ApexTestResult; LWC e cobertura vêm do sf CLI (ADR-015).',
        clicar: 'Abra Engineering Intelligence e clique em "Verificar agora".',
        registro: 'Visão Técnica, filtro por tipo.',
        esperado: 'Cada indicador com a sua regra escrita; data e origem da última verificação.',
        comprovar: 'Mostre a visão Implantações: cada linha veio do relatório de deploy da Salesforce.',
        pergunta: 'O que impede alguém de marcar tudo como verificado?',
        resposta: 'O campo de estado é somente leitura para todos os perfis; só o verificador grava, a partir do que a org responde.',
        limitacao: 'Evidência do sf CLI vale 7 dias: antes de apresentar, rode a atualização de evidências.'
    },
    {
        id: 'integracao', minutos: 0.5, titulo: 'Integração com o GitHub', aba: 'RAIZ_Engineering_Intelligence',
        funcional: 'Liga a versão publicada do código ao que está de fato implantado na org.',
        tecnico: 'Named Credential sem segredo + RaizGitHubService (callout GET, timeout 10 s, tratamento de 401/403/404/429/5xx) e testes com HttpCalloutMock (ADR-016, 017).',
        clicar: 'Engineering Intelligence → visão Integração → "Sincronizar agora".',
        registro: 'Repositório configurado em RAIZ_Integracao__mdt.',
        esperado: 'Releases listadas com a coluna "Implantada na org?".',
        comprovar: 'Uma release sem deploy ligado aparece como "Não".',
        pergunta: 'E se o GitHub cair?',
        resposta: 'A tela lê o que já foi gravado na Salesforce; a falha vira log com o código HTTP e nada é apagado.',
        limitacao: 'Leitura anônima tem limite baixo por IP; a Salesforce compartilha IPs de saída.'
    },
    {
        id: 'ia', minutos: 1, titulo: 'Engineering with AI', aba: null,
        funcional: 'A IA acelerou requisitos, código, testes e documentação; as decisões, aprovações e validações foram do autor.',
        tecnico: 'Cada funcionalidade guarda, separados, "Decisões e validações do autor" e "Apoio de IA". Revisões feitas por IA antes do deploy apontaram falhas corrigidas antes de chegar à org.',
        clicar: 'Veja abaixo, nesta página, os destaques de portfólio.',
        registro: 'Itens de engenharia com "Destaque de portfólio".',
        esperado: 'Para cada destaque: o que o autor decidiu e o que a IA fez.',
        comprovar: 'As decisões citadas (D1 a D6) estão no blueprint versionado do projeto.',
        pergunta: 'Você sabe explicar o código que a IA escreveu?',
        resposta: 'Responder com um exemplo concreto: por que o cadastro usa LWC, por que o log tem chave de idempotência, por que release não prova deploy.',
        limitacao: 'Não apresentar código gerado como prova de competência: a prova é a decisão, o teste e a evidência.'
    }
];
